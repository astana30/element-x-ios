from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from salemx_call_service.allocation import (
    Allocation,
    AllocationKey,
    AllocationMetadata,
    InMemoryAllocationStore,
    RedisAllocationStore,
    SharedAllocationStoreSkeleton,
)
from salemx_call_service.auth import AuthenticatedUser
from salemx_call_service.config import (
    ALLOCATION_STORE_ENV,
    ALLOCATION_STORE_URL_ENV,
    ALLOW_MEMORY_ALLOCATION_STORE_ENV,
    ALLOW_MEMORY_RATE_LIMITER_ENV,
    ALLOW_INSECURE_LIVEKIT_URL_ENV,
    NATIVE_AUDIO_ELIGIBILITY_ALLOWED_HOMESERVERS_ENV,
    NATIVE_AUDIO_ELIGIBILITY_ALLOWED_USERS_ENV,
    NATIVE_AUDIO_ELIGIBILITY_ENABLED_ENV,
    RATE_LIMIT_PER_MINUTE_ENV,
    RATE_LIMIT_STORE_ENV,
    RATE_LIMIT_STORE_URL_ENV,
    SERVICE_MODE_ENV,
    STORAGE_KEY_SECRET_ENV,
    AllocationStoreKind,
    RateLimitStoreKind,
    ServiceMode,
    ServicePreflightError,
    service_readiness_from_env,
    validate_service_preflight,
)
from salemx_call_service.dto import TokenRequest
from salemx_call_service.eligibility import (
    AlwaysEligibleNativeAudioEligibilityPolicy,
    DisabledNativeAudioEligibilityPolicy,
    NativeAudioEligibilityPolicyProtocol,
    StaticAllowlistNativeAudioEligibilityPolicy,
)
from salemx_call_service.errors import CallServiceError, livekit_room_unavailable
from salemx_call_service.livekit_rooms import (
    LiveKitRoomServiceHTTPResponse,
    LiveKitRoomServiceProvisioner,
)
from salemx_call_service.livekit_tokens import IssuedLiveKitToken, LiveKitGrant, LiveKitJWTTokenIssuer
from salemx_call_service.local_fake import (
    DEFAULT_FAKE_LIVEKIT_URL,
    DIRECT_CALL_CAPABILITY_NAME,
    FAKE_LIVEKIT_API_KEY_ENV,
    FAKE_LIVEKIT_API_SECRET_ENV,
    FAKE_LIVEKIT_URL_ENV,
    FAKE_MODE_ENV,
    make_fake_capabilities_payload,
)
from salemx_call_service.room_validation import InMemoryRoomValidator, RoomEligibility, SynapseRoomValidator
from salemx_call_service.rate_limiting import (
    InMemoryRateLimiter,
    RateLimiterProtocol,
    RateLimitKey,
    RedisRateLimiter,
    SharedRateLimiterSkeleton,
)
from salemx_call_service.service import DirectCallTokenService
from salemx_call_service.storage_keys import StorageKeyHasher
from salemx_call_service.synapse_http import SynapseHTTPResponse

TOKEN_ENDPOINT_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"
CAPABILITIES_PATH = "/_matrix/client/v3/capabilities"


class FakeAuthValidator:
    def __init__(self, tokens: dict[str, AuthenticatedUser]) -> None:
        self.tokens = tokens

    async def validate_bearer_token(self, bearer_token: str) -> AuthenticatedUser:
        user = self.tokens.get(bearer_token)
        if user is None:
            raise CallServiceError(status_code=401, errcode="M_UNKNOWN_TOKEN", error="Missing or invalid Matrix access token.")
        return user


class FakeLiveKitTokenIssuer:
    def __init__(self, events: list[str] | None = None) -> None:
        self.issued: list[tuple[AuthenticatedUser, TokenRequest, Allocation, LiveKitGrant]] = []
        self.events = events

    async def issue_token(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest, allocation: Allocation) -> IssuedLiveKitToken:
        grant = LiveKitGrant(room_join=True, room=allocation.livekit_room_name, can_publish=True, can_subscribe=True, can_publish_data=False)
        self.issued.append((authenticated_user, token_request, allocation, grant))
        if self.events is not None:
            self.events.append("issue-token")
        return IssuedLiveKitToken(
            participant_token="participant-token-sensitive",
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=120),
            grant=grant,
        )


class FakeLiveKitRoomProvisioner:
    def __init__(self, fail: bool = False, events: list[str] | None = None) -> None:
        self.fail = fail
        self.events = events
        self.ensured_rooms: list[str] = []

    async def ensure_room(self, room_name: str) -> None:
        self.ensured_rooms.append(room_name)
        if self.events is not None:
            self.events.append("ensure-room")
        if self.fail:
            raise livekit_room_unavailable()


class FakeLiveKitRoomServiceHTTPClient:
    def __init__(self, response: LiveKitRoomServiceHTTPResponse) -> None:
        self.response = response
        self.requests: list[tuple[str, str, dict[str, object], float]] = []

    def create_room(self,
                    endpoint_url: str,
                    authorization: str,
                    payload: dict[str, object],
                    timeout_seconds: float) -> LiveKitRoomServiceHTTPResponse:
        self.requests.append((endpoint_url, authorization, payload, timeout_seconds))
        return self.response


class FakeRedisAllocationClient:
    def __init__(self, fail: bool = False, conflict_miss_count: int = 0) -> None:
        self.fail = fail
        self.conflict_miss_count = conflict_miss_count
        self.values: dict[str, tuple[str, datetime]] = {}
        self.set_keys: list[str] = []
        self.set_values: list[str] = []

    async def set_if_absent_with_ttl(self, key: str, value: str, ttl_seconds: int) -> bool:
        if self.fail:
            raise RuntimeError("redis unavailable")
        self._remove_expired()
        self.set_keys.append(key)
        self.set_values.append(value)
        if self.conflict_miss_count > 0:
            self.conflict_miss_count -= 1
            return False
        if key in self.values:
            return False
        self.values[key] = (value, datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds))
        return True

    async def get(self, key: str) -> str | None:
        if self.fail:
            raise RuntimeError("redis unavailable")
        self._remove_expired()
        value = self.values.get(key)
        if value is None:
            return None
        return value[0]

    def _remove_expired(self) -> None:
        now = datetime.now(timezone.utc)
        self.values = {key: value for key, value in self.values.items() if value[1] > now}


class FakeRedisRateLimitClient:
    def __init__(self, fail: bool = False) -> None:
        self.fail = fail
        self.records: dict[str, list[int]] = {}
        self.recorded_keys: list[str] = []

    async def check_and_record(self,
                               keys: tuple[str, ...],
                               now_ms: int,
                               window_ms: int,
                               limit_per_minute: int,
                               member: str) -> tuple[bool, int]:
        if self.fail:
            raise RuntimeError("redis unavailable")

        window_started_at = now_ms - window_ms
        for key in keys:
            self.records[key] = [recorded_at for recorded_at in self.records.get(key, []) if recorded_at > window_started_at]

        retry_after_values: list[int] = []
        for key in keys:
            if len(self.records.get(key, [])) < limit_per_minute:
                continue
            oldest = min(self.records[key])
            retry_after_values.append(max(1, oldest + window_ms - now_ms))

        if retry_after_values:
            return False, max(retry_after_values)

        for key in keys:
            self.records.setdefault(key, []).append(now_ms)
            self.recorded_keys.append(key)
        return True, 0


class RecordingRateLimiter(InMemoryRateLimiter):
    def __init__(self, events: list[str]) -> None:
        super().__init__()
        self._events = events

    async def check_and_record(self,
                               keys: tuple[RateLimitKey, ...],
                               limit_per_minute: int,
                               now: datetime | None = None) -> object:
        self._events.append("rate-limit")
        return await super().check_and_record(keys, limit_per_minute, now)


class DirectCallTokenServiceTests(unittest.IsolatedAsyncioTestCase):
    def make_service(self,
                     rooms: dict[str, RoomEligibility] | None = None,
                     issuer: FakeLiveKitTokenIssuer | None = None,
                     provisioner: FakeLiveKitRoomProvisioner | None = None,
                     rate_limiter: RateLimiterProtocol | None = None,
                     rate_limit_per_minute: int = 30,
                     eligibility_policy: NativeAudioEligibilityPolicyProtocol | None = None) -> DirectCallTokenService:
        return DirectCallTokenService(
            auth_validator=FakeAuthValidator({
                "matrix-token-a-sensitive": AuthenticatedUser("@alice:example.test", "DEVICEA"),
                "matrix-token-b-sensitive": AuthenticatedUser("@bob:example.test", "DEVICEB"),
            }),
            room_validator=InMemoryRoomValidator(rooms or {
                "!room:example.test": RoomEligibility(("@alice:example.test", "@bob:example.test"), True),
            }),
            allocation_store=InMemoryAllocationStore(allocation_ttl_seconds=300),
            rate_limiter=rate_limiter or InMemoryRateLimiter(),
            room_provisioner=provisioner or FakeLiveKitRoomProvisioner(),
            token_issuer=issuer or FakeLiveKitTokenIssuer(),
            livekit_server_url="wss://livekit.example.test",
            rate_limit_per_minute=rate_limit_per_minute,
            eligibility_policy=eligibility_policy or AlwaysEligibleNativeAudioEligibilityPolicy(),
        )

    def valid_payload(self, **overrides: object) -> dict[str, object]:
        payload: dict[str, object] = {
            "version": 1,
            "call_id": "call-a",
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "direction": "outgoing",
            "device_id": "DEVICEA",
            "client_transaction_id": "txn-a",
        }
        payload.update(overrides)
        return payload

    async def expect_error(self, payload: dict[str, object], errcode: str, authorization: str | None = "Bearer matrix-token-a-sensitive") -> None:
        service = self.make_service()
        with self.assertRaises(CallServiceError) as context:
            await service.issue_token(authorization, payload)
        self.assertEqual(context.exception.errcode, errcode)

    async def test_missing_authorization_returns_unknown_token(self) -> None:
        await self.expect_error(self.valid_payload(), "M_UNKNOWN_TOKEN", authorization=None)

    async def test_invalid_bearer_returns_unknown_token(self) -> None:
        await self.expect_error(self.valid_payload(), "M_UNKNOWN_TOKEN", authorization="Bearer invalid-token")

    async def test_unsupported_version_returns_unrecognized(self) -> None:
        await self.expect_error(self.valid_payload(version=2), "M_UNRECOGNIZED")

    async def test_unsupported_intent_returns_direct_call_error(self) -> None:
        await self.expect_error(self.valid_payload(intent="video"), "M_DIRECT_CALL_UNSUPPORTED_INTENT")

    async def test_requester_not_joined_returns_not_joined(self) -> None:
        service = self.make_service({
            "!room:example.test": RoomEligibility(("@charlie:example.test", "@bob:example.test"), True),
        })
        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())
        self.assertEqual(context.exception.errcode, "M_NOT_JOINED")

    async def test_peer_not_joined_returns_peer_mismatch(self) -> None:
        service = self.make_service({
            "!room:example.test": RoomEligibility(("@alice:example.test", "@charlie:example.test"), True),
        })
        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())
        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_PEER_MISMATCH")

    async def test_unencrypted_room_returns_room_not_encrypted(self) -> None:
        service = self.make_service({
            "!room:example.test": RoomEligibility(("@alice:example.test", "@bob:example.test"), False),
        })
        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())
        self.assertEqual(context.exception.errcode, "M_ROOM_NOT_ENCRYPTED")

    async def test_multi_member_room_returns_not_one_to_one(self) -> None:
        service = self.make_service({
            "!room:example.test": RoomEligibility(("@alice:example.test", "@bob:example.test", "@charlie:example.test"), True),
        })
        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())
        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_NOT_1_TO_1")

    async def test_valid_outgoing_creates_opaque_allocation(self) -> None:
        issuer = FakeLiveKitTokenIssuer()
        provisioner = FakeLiveKitRoomProvisioner()
        service = self.make_service(issuer=issuer, provisioner=provisioner)

        response = await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())
        body = response.as_dict()

        self.assertEqual(body["version"], 1)
        self.assertEqual(body["allocation"]["call_id"], "call-a")
        self.assertEqual(body["allocation"]["intent"], "audio")
        self.assertTrue(body["allocation"]["id"])
        self.assertTrue(body["livekit"]["room_name"].startswith("salemx-dc-"))
        self.assertNotIn("!room:example.test", body["livekit"]["room_name"])
        self.assertEqual(body["livekit"]["participant_token"], "participant-token-sensitive")
        self.assertEqual(issuer.issued[0][3].room, body["livekit"]["room_name"])
        self.assertTrue(issuer.issued[0][3].room_join)
        self.assertTrue(issuer.issued[0][3].can_publish)
        self.assertTrue(issuer.issued[0][3].can_subscribe)
        self.assertFalse(issuer.issued[0][3].can_publish_data)
        self.assertEqual(provisioner.ensured_rooms, [body["livekit"]["room_name"]])

    async def test_livekit_room_is_ensured_after_allocation_before_token_issue(self) -> None:
        events: list[str] = []
        issuer = FakeLiveKitTokenIssuer(events=events)
        provisioner = FakeLiveKitRoomProvisioner(events=events)
        service = self.make_service(issuer=issuer, provisioner=provisioner)

        response = await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())

        self.assertEqual(events, ["ensure-room", "issue-token"])
        self.assertEqual(provisioner.ensured_rooms, [response.livekit.room_name])
        self.assertEqual(issuer.issued[0][2].livekit_room_name, response.livekit.room_name)

    async def test_livekit_room_provision_failure_fails_closed_without_token(self) -> None:
        issuer = FakeLiveKitTokenIssuer()
        provisioner = FakeLiveKitRoomProvisioner(fail=True)
        service = self.make_service(issuer=issuer, provisioner=provisioner)

        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())

        self.assertEqual(context.exception.status_code, 503)
        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_LIVEKIT_ROOM_UNAVAILABLE")
        self.assertEqual(len(provisioner.ensured_rooms), 1)
        self.assertEqual(len(issuer.issued), 0)

    async def test_valid_incoming_reuses_allocation(self) -> None:
        provisioner = FakeLiveKitRoomProvisioner()
        service = self.make_service(provisioner=provisioner)

        outgoing = await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())
        incoming = await service.issue_token(
            "Bearer matrix-token-b-sensitive",
            self.valid_payload(peer_user_id="@alice:example.test", direction="incoming", device_id="DEVICEB"),
        )

        self.assertEqual(outgoing.allocation.id, incoming.allocation.id)
        self.assertEqual(outgoing.livekit.room_name, incoming.livekit.room_name)
        self.assertEqual(provisioner.ensured_rooms, [outgoing.livekit.room_name, incoming.livekit.room_name])

    async def test_concurrent_same_call_reuses_allocation(self) -> None:
        provisioner = FakeLiveKitRoomProvisioner()
        service = self.make_service(provisioner=provisioner)

        responses = await asyncio.gather(
            service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-1")),
            service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-2")),
        )

        self.assertEqual(responses[0].allocation.id, responses[1].allocation.id)
        self.assertEqual(responses[0].livekit.room_name, responses[1].livekit.room_name)
        self.assertEqual(len(provisioner.ensured_rooms), 2)
        self.assertEqual(set(provisioner.ensured_rooms), {responses[0].livekit.room_name})

    async def test_under_rate_limit_token_request_succeeds(self) -> None:
        issuer = FakeLiveKitTokenIssuer()
        service = self.make_service(issuer=issuer, rate_limit_per_minute=2)

        response = await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())

        self.assertEqual(response.allocation.call_id, "call-a")
        self.assertEqual(len(issuer.issued), 1)

    async def test_over_rate_limit_returns_429(self) -> None:
        service = self.make_service(rate_limit_per_minute=1)

        await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-1"))
        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-2"))

        self.assertEqual(context.exception.status_code, 429)
        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_RATE_LIMITED")
        self.assertIsNotNone(context.exception.retry_after_ms)

    async def test_no_token_is_issued_after_rate_limit_is_exceeded(self) -> None:
        issuer = FakeLiveKitTokenIssuer()
        provisioner = FakeLiveKitRoomProvisioner()
        service = self.make_service(issuer=issuer, provisioner=provisioner, rate_limit_per_minute=1)

        await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-1"))
        with self.assertRaises(CallServiceError):
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-2"))

        self.assertEqual(len(issuer.issued), 1)
        self.assertEqual(len(provisioner.ensured_rooms), 1)

    async def test_no_token_is_issued_after_redis_rate_limit_is_exceeded(self) -> None:
        issuer = FakeLiveKitTokenIssuer()
        provisioner = FakeLiveKitRoomProvisioner()
        service = self.make_service(
            issuer=issuer,
            provisioner=provisioner,
            rate_limiter=RedisRateLimiter(FakeRedisRateLimitClient(), StorageKeyHasher("storage-key-secret")),
            rate_limit_per_minute=1,
        )

        await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-1"))
        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-2"))

        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_RATE_LIMITED")
        self.assertEqual(len(issuer.issued), 1)
        self.assertEqual(len(provisioner.ensured_rooms), 1)

    async def test_rate_limit_store_unavailable_fails_before_token_issue(self) -> None:
        issuer = FakeLiveKitTokenIssuer()
        provisioner = FakeLiveKitRoomProvisioner()
        service = self.make_service(
            issuer=issuer,
            provisioner=provisioner,
            rate_limiter=SharedRateLimiterSkeleton(RateLimitStoreKind.REDIS.value),
        )

        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())

        self.assertEqual(context.exception.status_code, 503)
        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE")
        self.assertEqual(len(issuer.issued), 0)
        self.assertEqual(len(provisioner.ensured_rooms), 0)

    async def test_rate_limited_logs_do_not_contain_raw_ids_or_tokens(self) -> None:
        service = self.make_service(rate_limit_per_minute=1)

        await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-1"))
        with self.assertLogs("salemx_call_service.service", level="INFO") as logs:
            with self.assertRaises(CallServiceError):
                await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-2"))

        log_output = "\n".join(logs.output)
        self.assertNotIn("matrix-token-a-sensitive", log_output)
        self.assertNotIn("@alice:example.test", log_output)
        self.assertNotIn("@bob:example.test", log_output)
        self.assertNotIn("!room:example.test", log_output)

    async def test_livekit_room_provision_failure_logs_are_redacted(self) -> None:
        http_client = FakeLiveKitRoomServiceHTTPClient(LiveKitRoomServiceHTTPResponse(500, '{"code":"internal"}'))
        provisioner = LiveKitRoomServiceProvisioner(
            "wss://livekit.example.test",
            "test-api-key",
            "test-signing-key",
            http_client=http_client,
        )

        with self.assertLogs("salemx_call_service.livekit_rooms", level="WARNING") as logs:
            with self.assertRaises(CallServiceError):
                await provisioner.ensure_room("salemx-dc-room-sensitive")

        log_output = "\n".join(logs.output)
        self.assertNotIn("test-signing-key", log_output)
        self.assertNotIn("test-api-key", log_output)
        self.assertNotIn("salemx-dc-room-sensitive", log_output)
        self.assertNotIn("!room:example.test", log_output)
        self.assertNotIn("@alice:example.test", log_output)
        self.assertNotIn("@bob:example.test", log_output)

    async def test_logs_do_not_contain_tokens_or_raw_room_id(self) -> None:
        service = self.make_service()

        with self.assertLogs("salemx_call_service.service", level="INFO") as logs:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())

        joined_logs = "\n".join(logs.output)
        self.assertNotIn("matrix-token-a-sensitive", joined_logs)
        self.assertNotIn("participant-token-sensitive", joined_logs)
        self.assertNotIn("!room:example.test", joined_logs)

    async def test_default_eligibility_policy_fails_closed_without_token(self) -> None:
        issuer = FakeLiveKitTokenIssuer()
        provisioner = FakeLiveKitRoomProvisioner()
        service = self.make_service(
            issuer=issuer,
            provisioner=provisioner,
            eligibility_policy=DisabledNativeAudioEligibilityPolicy(),
        )

        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())

        self.assertEqual(context.exception.status_code, 403)
        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_NOT_ELIGIBLE")
        self.assertEqual(len(issuer.issued), 0)
        self.assertEqual(provisioner.ensured_rooms, [])

    async def test_eligibility_rejection_happens_before_rate_limit_allocation_or_room_creation(self) -> None:
        events: list[str] = []
        issuer = FakeLiveKitTokenIssuer(events=events)
        provisioner = FakeLiveKitRoomProvisioner(events=events)
        service = self.make_service(
            issuer=issuer,
            provisioner=provisioner,
            rate_limiter=RecordingRateLimiter(events),
            eligibility_policy=StaticAllowlistNativeAudioEligibilityPolicy(allowed_user_ids=("@bob:example.test",)),
        )

        with self.assertRaises(CallServiceError) as context:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())

        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_NOT_ELIGIBLE")
        self.assertEqual(events, [])
        self.assertEqual(len(issuer.issued), 0)
        self.assertEqual(provisioner.ensured_rooms, [])

    async def test_eligibility_endpoint_default_disabled_is_redacted(self) -> None:
        service = self.make_service(eligibility_policy=DisabledNativeAudioEligibilityPolicy())

        result = await service.evaluate_eligibility("Bearer matrix-token-a-sensitive", {
            "version": 1,
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "device_id": "DEVICEA",
        })
        body = result.as_dict()
        output = json.dumps(body, sort_keys=True)

        self.assertEqual(body["state"], "unavailable")
        self.assertEqual(body["reason"], "capabilityMissing")
        self.assertFalse(body["capability_present"])
        self.assertNotIn("!room:example.test", output)
        self.assertNotIn("@alice:example.test", output)
        self.assertNotIn("@bob:example.test", output)
        self.assertNotIn("DEVICEA", output)

    async def test_eligibility_caller_not_allowlisted_returns_account_not_eligible(self) -> None:
        service = self.make_service(eligibility_policy=StaticAllowlistNativeAudioEligibilityPolicy(
            allowed_user_ids=("@bob:example.test",),
            allowed_homeservers=("example.test",),
        ))

        result = await service.evaluate_eligibility("Bearer matrix-token-a-sensitive", {
            "version": 1,
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "device_id": "DEVICEA",
        })

        self.assertEqual(result.as_dict()["state"], "unavailable")
        self.assertEqual(result.as_dict()["reason"], "accountNotEligible")
        self.assertFalse(result.account_eligible)
        self.assertTrue(result.peer_eligible)

    async def test_eligibility_peer_not_allowlisted_returns_peer_not_eligible(self) -> None:
        service = self.make_service(eligibility_policy=StaticAllowlistNativeAudioEligibilityPolicy(
            allowed_user_ids=("@alice:example.test",),
            allowed_homeservers=("example.test",),
        ))

        result = await service.evaluate_eligibility("Bearer matrix-token-a-sensitive", {
            "version": 1,
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "device_id": "DEVICEA",
        })

        self.assertEqual(result.as_dict()["state"], "unavailable")
        self.assertEqual(result.as_dict()["reason"], "peerNotEligible")
        self.assertTrue(result.account_eligible)
        self.assertFalse(result.peer_eligible)

    async def test_eligibility_both_allowlisted_valid_room_returns_eligible(self) -> None:
        service = self.make_service(eligibility_policy=StaticAllowlistNativeAudioEligibilityPolicy(
            allowed_user_ids=("@alice:example.test", "@bob:example.test"),
            allowed_homeservers=("example.test",),
        ))

        result = await service.evaluate_eligibility("Bearer matrix-token-a-sensitive", {
            "version": 1,
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "device_id": "DEVICEA",
        })

        body = result.as_dict()
        self.assertEqual(body["state"], "eligible")
        self.assertIsNone(body["reason"])
        self.assertTrue(body["account_eligible"])
        self.assertTrue(body["peer_eligible"])
        self.assertTrue(body["room_eligible"])
        self.assertIsNone(body["trust_ready"])

    async def test_eligibility_invalid_room_returns_room_not_eligible(self) -> None:
        service = self.make_service(
            rooms={"!room:example.test": RoomEligibility(("@alice:example.test", "@bob:example.test"), False)},
            eligibility_policy=StaticAllowlistNativeAudioEligibilityPolicy(
                allowed_user_ids=("@alice:example.test", "@bob:example.test"),
            ),
        )

        result = await service.evaluate_eligibility("Bearer matrix-token-a-sensitive", {
            "version": 1,
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "device_id": "DEVICEA",
        })

        self.assertEqual(result.as_dict()["state"], "unavailable")
        self.assertEqual(result.as_dict()["reason"], "roomNotEligible")
        self.assertFalse(result.room_eligible)


class AllocationStoreTests(unittest.IsolatedAsyncioTestCase):
    def token_request(self, direction: str = "outgoing", peer_user_id: str = "@bob:example.test") -> TokenRequest:
        return TokenRequest.from_mapping({
            "version": 1,
            "call_id": "call-a",
            "room_id": "!room:example.test",
            "peer_user_id": peer_user_id,
            "intent": "audio",
            "direction": direction,
        })

    async def test_memory_store_create_or_reuse_keeps_same_allocation(self) -> None:
        store = InMemoryAllocationStore(allocation_ttl_seconds=300)
        request = self.token_request()
        allocation_key = AllocationKey.from_token_request(request)
        metadata = AllocationMetadata.from_token_request(request)

        first = await store.create_or_reuse(allocation_key, metadata, ttl_seconds=300)
        second = await store.create_or_reuse(allocation_key, metadata, ttl_seconds=300)

        self.assertEqual(first.id, second.id)
        self.assertEqual(first.livekit_room_name, second.livekit_room_name)
        self.assertEqual(await store.get(allocation_key), first)

    async def test_memory_store_replaces_expired_allocation(self) -> None:
        store = InMemoryAllocationStore(allocation_ttl_seconds=0)
        request = self.token_request()

        first = await store.allocation_for(request)
        second = await store.allocation_for(request)

        self.assertNotEqual(first.id, second.id)

    async def test_caller_and_callee_share_allocation_key(self) -> None:
        store = InMemoryAllocationStore(allocation_ttl_seconds=300)
        outgoing_request = self.token_request(direction="outgoing", peer_user_id="@bob:example.test")
        incoming_request = self.token_request(direction="incoming", peer_user_id="@alice:example.test")

        outgoing = await store.create_or_reuse(
            AllocationKey.from_token_request(outgoing_request),
            AllocationMetadata.from_token_request(outgoing_request),
            ttl_seconds=300,
        )
        incoming = await store.create_or_reuse(
            AllocationKey.from_token_request(incoming_request),
            AllocationMetadata.from_token_request(incoming_request),
            ttl_seconds=300,
        )

        self.assertEqual(outgoing.id, incoming.id)
        self.assertEqual(outgoing.livekit_room_name, incoming.livekit_room_name)

    async def test_redis_store_create_or_reuse_keeps_same_allocation(self) -> None:
        redis_client = FakeRedisAllocationClient()
        store = RedisAllocationStore(redis_client, StorageKeyHasher("storage-key-secret"))
        request = self.token_request()
        allocation_key = AllocationKey.from_token_request(request)
        metadata = AllocationMetadata.from_token_request(request)

        first = await store.create_or_reuse(allocation_key, metadata, ttl_seconds=300)
        second = await store.create_or_reuse(allocation_key, metadata, ttl_seconds=300)

        self.assertEqual(first.id, second.id)
        self.assertEqual(first.livekit_room_name, second.livekit_room_name)
        self.assertEqual(await store.get(allocation_key), first)

    async def test_redis_store_caller_and_callee_share_allocation_key(self) -> None:
        redis_client = FakeRedisAllocationClient()
        store = RedisAllocationStore(redis_client, StorageKeyHasher("storage-key-secret"))
        outgoing_request = self.token_request(direction="outgoing", peer_user_id="@bob:example.test")
        incoming_request = self.token_request(direction="incoming", peer_user_id="@alice:example.test")

        outgoing = await store.create_or_reuse(
            AllocationKey.from_token_request(outgoing_request),
            AllocationMetadata.from_token_request(outgoing_request),
            ttl_seconds=300,
        )
        incoming = await store.create_or_reuse(
            AllocationKey.from_token_request(incoming_request),
            AllocationMetadata.from_token_request(incoming_request),
            ttl_seconds=300,
        )

        self.assertEqual(outgoing.id, incoming.id)
        self.assertEqual(outgoing.livekit_room_name, incoming.livekit_room_name)

    async def test_redis_store_retries_bounded_race_miss(self) -> None:
        redis_client = FakeRedisAllocationClient(conflict_miss_count=1)
        store = RedisAllocationStore(redis_client, StorageKeyHasher("storage-key-secret"), max_create_retries=2)
        request = self.token_request()

        allocation = await store.create_or_reuse(
            AllocationKey.from_token_request(request),
            AllocationMetadata.from_token_request(request),
            ttl_seconds=300,
        )

        self.assertTrue(allocation.livekit_room_name.startswith("salemx-dc-"))
        self.assertEqual(len(redis_client.set_keys), 2)

    async def test_redis_store_replaces_expired_missing_allocation(self) -> None:
        redis_client = FakeRedisAllocationClient()
        store = RedisAllocationStore(redis_client, StorageKeyHasher("storage-key-secret"))
        request = self.token_request()
        allocation_key = AllocationKey.from_token_request(request)
        metadata = AllocationMetadata.from_token_request(request)

        first = await store.create_or_reuse(allocation_key, metadata, ttl_seconds=300)
        stored_key = redis_client.set_keys[0]
        stored_value = redis_client.values[stored_key][0]
        redis_client.values[stored_key] = (stored_value, datetime.now(timezone.utc) - timedelta(seconds=1))
        second = await store.create_or_reuse(allocation_key, metadata, ttl_seconds=300)

        self.assertNotEqual(first.id, second.id)
        self.assertEqual(await store.get(allocation_key), second)

    async def test_redis_store_failure_maps_to_allocation_failed(self) -> None:
        redis_client = FakeRedisAllocationClient(fail=True)
        store = RedisAllocationStore(redis_client, StorageKeyHasher("storage-key-secret"))
        request = self.token_request()

        with self.assertRaises(CallServiceError) as context:
            await store.create_or_reuse(
                AllocationKey.from_token_request(request),
                AllocationMetadata.from_token_request(request),
                ttl_seconds=300,
            )

        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_ALLOCATION_FAILED")

    async def test_redis_store_keys_and_values_do_not_contain_raw_identifiers(self) -> None:
        redis_client = FakeRedisAllocationClient()
        store = RedisAllocationStore(redis_client, StorageKeyHasher("storage-key-secret"))
        request = self.token_request()

        await store.create_or_reuse(
            AllocationKey.from_token_request(request),
            AllocationMetadata.from_token_request(request),
            ttl_seconds=300,
        )

        serialized_storage = "\n".join(redis_client.set_keys + redis_client.set_values)
        self.assertNotIn("!room:example.test", serialized_storage)
        self.assertNotIn("@alice:example.test", serialized_storage)
        self.assertNotIn("@bob:example.test", serialized_storage)

    async def test_shared_store_skeleton_fails_closed(self) -> None:
        store = SharedAllocationStoreSkeleton(AllocationStoreKind.REDIS.value)
        request = self.token_request()

        with self.assertRaises(CallServiceError) as context:
            await store.create_or_reuse(
                AllocationKey.from_token_request(request),
                AllocationMetadata.from_token_request(request),
                ttl_seconds=300,
            )

        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_ALLOCATION_FAILED")


class RateLimiterTests(unittest.IsolatedAsyncioTestCase):
    async def test_memory_rate_limiter_allows_requests_under_limit(self) -> None:
        limiter = InMemoryRateLimiter()
        now = datetime(2026, 5, 20, tzinfo=timezone.utc)
        keys = (RateLimitKey("user:redacted"), RateLimitKey("room:redacted"))

        first = await limiter.check_and_record(keys, limit_per_minute=2, now=now)
        second = await limiter.check_and_record(keys, limit_per_minute=2, now=now + timedelta(seconds=1))

        self.assertTrue(first.allowed)
        self.assertTrue(second.allowed)

    async def test_memory_rate_limiter_limits_each_key_without_partial_record(self) -> None:
        limiter = InMemoryRateLimiter()
        now = datetime(2026, 5, 20, tzinfo=timezone.utc)
        user_key = RateLimitKey("user:redacted")
        room_key = RateLimitKey("room:redacted")

        await limiter.check_and_record((user_key,), limit_per_minute=1, now=now)
        limited = await limiter.check_and_record((user_key, room_key), limit_per_minute=1, now=now + timedelta(seconds=1))
        room_only = await limiter.check_and_record((room_key,), limit_per_minute=1, now=now + timedelta(seconds=2))

        self.assertFalse(limited.allowed)
        self.assertEqual(limited.reason, "rateLimited")
        self.assertIsNotNone(limited.retry_after_ms)
        self.assertTrue(room_only.allowed)

    async def test_redis_rate_limiter_allows_requests_under_limit(self) -> None:
        redis_client = FakeRedisRateLimitClient()
        limiter = RedisRateLimiter(redis_client, StorageKeyHasher("storage-key-secret"))
        now = datetime(2026, 5, 20, tzinfo=timezone.utc)

        first = await limiter.check_and_record((RateLimitKey("user:redacted"),), limit_per_minute=2, now=now)
        second = await limiter.check_and_record((RateLimitKey("user:redacted"),), limit_per_minute=2, now=now + timedelta(seconds=1))

        self.assertTrue(first.allowed)
        self.assertTrue(second.allowed)

    async def test_redis_rate_limiter_denies_over_limit_with_retry_after(self) -> None:
        redis_client = FakeRedisRateLimitClient()
        limiter = RedisRateLimiter(redis_client, StorageKeyHasher("storage-key-secret"))
        now = datetime(2026, 5, 20, tzinfo=timezone.utc)

        await limiter.check_and_record((RateLimitKey("user:redacted"),), limit_per_minute=1, now=now)
        limited = await limiter.check_and_record((RateLimitKey("user:redacted"),), limit_per_minute=1, now=now + timedelta(seconds=1))

        self.assertFalse(limited.allowed)
        self.assertEqual(limited.reason, "rateLimited")
        self.assertIsNotNone(limited.retry_after_ms)

    async def test_redis_rate_limiter_does_not_partially_record_multi_key_limit(self) -> None:
        redis_client = FakeRedisRateLimitClient()
        limiter = RedisRateLimiter(redis_client, StorageKeyHasher("storage-key-secret"))
        now = datetime(2026, 5, 20, tzinfo=timezone.utc)
        user_key = RateLimitKey("user:redacted")
        room_key = RateLimitKey("room:redacted")

        await limiter.check_and_record((user_key,), limit_per_minute=1, now=now)
        limited = await limiter.check_and_record((user_key, room_key), limit_per_minute=1, now=now + timedelta(seconds=1))
        room_only = await limiter.check_and_record((room_key,), limit_per_minute=1, now=now + timedelta(seconds=2))

        self.assertFalse(limited.allowed)
        self.assertTrue(room_only.allowed)

    async def test_redis_rate_limiter_failure_maps_to_store_unavailable(self) -> None:
        redis_client = FakeRedisRateLimitClient(fail=True)
        limiter = RedisRateLimiter(redis_client, StorageKeyHasher("storage-key-secret"))

        with self.assertRaises(CallServiceError) as context:
            await limiter.check_and_record((RateLimitKey("user:redacted"),), limit_per_minute=30)

        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE")

    async def test_redis_rate_limiter_keys_do_not_contain_raw_identifiers(self) -> None:
        redis_client = FakeRedisRateLimitClient()
        limiter = RedisRateLimiter(redis_client, StorageKeyHasher("storage-key-secret"))
        request = TokenRequest.from_mapping({
            "version": 1,
            "call_id": "call-a",
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "direction": "outgoing",
            "device_id": "DEVICEA",
        })
        keys = RateLimitKey.keys_for(AuthenticatedUser("@alice:example.test", "DEVICEA"), request)

        await limiter.check_and_record(keys, limit_per_minute=30)

        serialized_keys = "\n".join(redis_client.recorded_keys)
        self.assertNotIn("@alice:example.test", serialized_keys)
        self.assertNotIn("@bob:example.test", serialized_keys)
        self.assertNotIn("!room:example.test", serialized_keys)
        self.assertNotIn("DEVICEA", serialized_keys)
        self.assertNotIn("matrix-token-a-sensitive", serialized_keys)
        self.assertNotIn("participant-token-sensitive", serialized_keys)

    async def test_shared_rate_limiter_skeleton_fails_closed(self) -> None:
        limiter = SharedRateLimiterSkeleton(RateLimitStoreKind.REDIS.value)

        with self.assertRaises(CallServiceError) as context:
            await limiter.check_and_record((RateLimitKey("user:redacted"),), limit_per_minute=30)

        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE")


class ServicePreflightTests(unittest.TestCase):
    def test_staging_preflight_refuses_memory_allocation_store_by_default(self) -> None:
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.MEMORY.value,
            ALLOCATION_STORE_URL_ENV: "",
        })

        readiness = service_readiness_from_env(env)

        self.assertFalse(readiness.ready)
        self.assertEqual(readiness.reason, "memoryAllocationStoreForbidden")
        self.assertFalse(readiness.allocation_store_configured)
        self.assertFalse(readiness.allocation_store_shared)
        with self.assertRaises(ServicePreflightError):
            validate_service_preflight(env)

    def test_staging_preflight_accepts_redis_allocation_store_shape(self) -> None:
        secret = "allocation-store-password-sensitive"
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.REDIS.value,
            ALLOCATION_STORE_URL_ENV: f"redis://:{secret}@allocation.example.test/0",
        })

        readiness = validate_service_preflight(env)
        output = json.dumps(readiness.as_dict(), sort_keys=True)

        self.assertTrue(readiness.ready)
        self.assertEqual(readiness.reason, "ok")
        self.assertTrue(readiness.livekit_room_provisioning_configured)
        self.assertTrue(readiness.allocation_store_configured)
        self.assertTrue(readiness.allocation_store_shared)
        self.assertTrue(readiness.allocation_store_connected)
        self.assertNotIn(secret, output)
        self.assertNotIn("allocation.example.test", output)

    def test_staging_preflight_refuses_postgres_allocation_until_implemented(self) -> None:
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.POSTGRES.value,
            ALLOCATION_STORE_URL_ENV: "postgres://allocation.example.test/db",
        })

        readiness = service_readiness_from_env(env)

        self.assertFalse(readiness.ready)
        self.assertEqual(readiness.reason, "unsupportedAllocationStore")
        self.assertFalse(readiness.allocation_store_connected)

    def test_staging_preflight_refuses_missing_shared_store_location(self) -> None:
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.REDIS.value,
            ALLOCATION_STORE_URL_ENV: "",
        })

        readiness = service_readiness_from_env(env)

        self.assertFalse(readiness.ready)
        self.assertEqual(readiness.reason, "missingAllocationStoreConfig")
        self.assertFalse(readiness.allocation_store_configured)
        self.assertTrue(readiness.allocation_store_shared)

    def test_staging_preflight_refuses_unsupported_allocation_store(self) -> None:
        env = _staging_env({
            ALLOCATION_STORE_ENV: "filesystem",
            ALLOCATION_STORE_URL_ENV: "/tmp/store",
        })

        readiness = service_readiness_from_env(env)

        self.assertFalse(readiness.ready)
        self.assertEqual(readiness.reason, "unsupportedAllocationStore")
        self.assertFalse(readiness.allocation_store_configured)

    def test_staging_preflight_refuses_memory_rate_limiter_by_default(self) -> None:
        env = _staging_env({
            RATE_LIMIT_STORE_ENV: RateLimitStoreKind.MEMORY.value,
            RATE_LIMIT_STORE_URL_ENV: "",
        })

        readiness = service_readiness_from_env(env)

        self.assertFalse(readiness.ready)
        self.assertEqual(readiness.reason, "invalidRateLimitConfig")
        self.assertFalse(readiness.rate_limit_configured)
        self.assertFalse(readiness.rate_limit_shared)

    def test_staging_preflight_accepts_redis_rate_limiter_shape(self) -> None:
        secret = "rate-limit-store-password-sensitive"
        env = _staging_env({
            RATE_LIMIT_STORE_ENV: RateLimitStoreKind.REDIS.value,
            RATE_LIMIT_STORE_URL_ENV: f"redis://:{secret}@rate-limit.example.test/0",
        })

        readiness = validate_service_preflight(env)
        output = json.dumps(readiness.as_dict(), sort_keys=True)

        self.assertTrue(readiness.ready)
        self.assertEqual(readiness.reason, "ok")
        self.assertTrue(readiness.as_dict()["liveKitRoomProvisioningConfigured"])
        self.assertTrue(readiness.rate_limit_configured)
        self.assertTrue(readiness.rate_limit_shared)
        self.assertTrue(readiness.rate_limit_connected)
        self.assertNotIn(secret, output)
        self.assertNotIn("rate-limit.example.test", output)

    def test_staging_preflight_refuses_missing_shared_rate_limiter_location(self) -> None:
        env = _staging_env({
            RATE_LIMIT_STORE_ENV: RateLimitStoreKind.POSTGRES.value,
            RATE_LIMIT_STORE_URL_ENV: "",
        })

        readiness = service_readiness_from_env(env)

        self.assertFalse(readiness.ready)
        self.assertEqual(readiness.reason, "invalidRateLimitConfig")
        self.assertFalse(readiness.rate_limit_configured)
        self.assertTrue(readiness.rate_limit_shared)

    def test_staging_preflight_refuses_invalid_rate_limit_per_minute(self) -> None:
        env = _staging_env({RATE_LIMIT_PER_MINUTE_ENV: "0"})

        readiness = service_readiness_from_env(env)

        self.assertFalse(readiness.ready)
        self.assertEqual(readiness.reason, "invalidRateLimitConfig")

    def test_staging_preflight_requires_storage_key_secret_for_redis(self) -> None:
        env = _staging_env({STORAGE_KEY_SECRET_ENV: ""})

        readiness = service_readiness_from_env(env)

        self.assertFalse(readiness.ready)
        self.assertEqual(readiness.reason, "missingStorageKeySecret")
        self.assertFalse(readiness.storage_key_configured)

    def test_staging_preflight_refuses_allocation_ttl_shorter_than_token_ttl(self) -> None:
        env = _staging_env({"TOKEN_TTL_SECONDS": "120", "ALLOCATION_TTL_SECONDS": "60"})

        readiness = service_readiness_from_env(env)

        self.assertFalse(readiness.ready)
        self.assertEqual(readiness.reason, "invalidTokenTTL")
        self.assertFalse(readiness.allocation_ttl_bounded)

    def test_staging_preflight_reports_native_audio_eligibility_disabled_by_default(self) -> None:
        readiness = service_readiness_from_env(_staging_env())
        body = readiness.as_dict()

        self.assertTrue(readiness.ready)
        self.assertFalse(body["nativeAudioEligibilityConfigured"])
        self.assertFalse(body["nativeAudioEligibilityAllowlistConfigured"])

    def test_staging_preflight_reports_native_audio_eligibility_without_values(self) -> None:
        env = _staging_env({
            NATIVE_AUDIO_ELIGIBILITY_ENABLED_ENV: "1",
            NATIVE_AUDIO_ELIGIBILITY_ALLOWED_USERS_ENV: "@alice:example.test,@bob:example.test",
            NATIVE_AUDIO_ELIGIBILITY_ALLOWED_HOMESERVERS_ENV: "example.test",
        })

        readiness = service_readiness_from_env(env)
        output = json.dumps(readiness.as_dict(), sort_keys=True)

        self.assertTrue(readiness.ready)
        self.assertTrue(readiness.as_dict()["nativeAudioEligibilityConfigured"])
        self.assertTrue(readiness.as_dict()["nativeAudioEligibilityAllowlistConfigured"])
        self.assertNotIn("@alice:example.test", output)
        self.assertNotIn("@bob:example.test", output)
        self.assertNotIn("example.test", output)


class LocalFakeCapabilityTests(unittest.IsolatedAsyncioTestCase):
    def test_fake_capabilities_payload_matches_app_contract(self) -> None:
        payload = make_fake_capabilities_payload(TOKEN_ENDPOINT_PATH)
        capability = payload["capabilities"][DIRECT_CALL_CAPABILITY_NAME]

        self.assertTrue(capability["enabled"])
        self.assertEqual(capability["version"], 1)
        self.assertEqual(capability["token_endpoint"], TOKEN_ENDPOINT_PATH)
        self.assertEqual(capability["intents"], ["audio"])
        self.assertEqual(capability["media_transport"], "livekit")
        self.assertTrue(capability["e2ee_required"])
        self.assertEqual(capability["key_envelope"], "matrix_sdk_direct_call_media_key_envelope_v1")

    async def test_fake_mode_registers_local_capabilities_route_only_when_explicitly_enabled(self) -> None:
        try:
            with patch.dict(os.environ, {SERVICE_MODE_ENV: ServiceMode.LOCAL_FAKE.value, FAKE_MODE_ENV: "1"}, clear=True):
                from salemx_call_service.app import CAPABILITIES_PATH as app_capabilities_path
                from salemx_call_service.app import create_app
        except ModuleNotFoundError as error:
            if error.name == "fastapi":
                self.skipTest("FastAPI is not installed in this Python environment.")
            raise

        production_like_app = create_app(token_service=DirectCallTokenServiceTests().make_service())
        production_like_paths = {route.path for route in production_like_app.routes}

        with patch.dict(os.environ, {SERVICE_MODE_ENV: ServiceMode.LOCAL_FAKE.value, FAKE_MODE_ENV: "1"}, clear=False):
            fake_app = create_app()
        fake_paths = {route.path for route in fake_app.routes}

        self.assertNotIn(app_capabilities_path, production_like_paths)
        self.assertIn(app_capabilities_path, fake_paths)


class LiveKitRoomServiceProvisionerTests(unittest.IsolatedAsyncioTestCase):
    async def test_create_room_uses_room_service_endpoint_and_room_create_grant(self) -> None:
        http_client = FakeLiveKitRoomServiceHTTPClient(LiveKitRoomServiceHTTPResponse(200, '{"name":"redacted"}'))
        provisioner = LiveKitRoomServiceProvisioner(
            "wss://livekit.example.test",
            "test-api-key",
            "test-signing-key",
            empty_timeout_seconds=180,
            departure_timeout_seconds=15,
            http_client=http_client,
        )

        await provisioner.ensure_room("salemx-dc-allocation-a")

        self.assertEqual(len(http_client.requests), 1)
        endpoint_url, authorization, payload, timeout_seconds = http_client.requests[0]
        self.assertEqual(endpoint_url, "https://livekit.example.test/twirp/livekit.RoomService/CreateRoom")
        self.assertEqual(payload["name"], "salemx-dc-allocation-a")
        self.assertEqual(payload["empty_timeout"], 180)
        self.assertEqual(payload["departure_timeout"], 15)
        self.assertGreater(timeout_seconds, 0)
        self.assertTrue(authorization.startswith("Bearer "))
        claims = LiveKitJWTTokenIssuerTests.decode_unverified_claims(authorization.removeprefix("Bearer "))
        self.assertEqual(claims["iss"], "test-api-key")
        self.assertTrue(claims["video"]["roomCreate"])
        self.assertNotIn("roomAdmin", claims["video"])
        self.assertNotIn("roomJoin", claims["video"])

    async def test_already_exists_response_is_success(self) -> None:
        http_client = FakeLiveKitRoomServiceHTTPClient(LiveKitRoomServiceHTTPResponse(409, '{"code":"already_exists"}'))
        provisioner = LiveKitRoomServiceProvisioner(
            "wss://livekit.example.test",
            "test-api-key",
            "test-signing-key",
            http_client=http_client,
        )

        await provisioner.ensure_room("salemx-dc-existing")

        self.assertEqual(len(http_client.requests), 1)

    async def test_create_room_failure_raises_safe_error(self) -> None:
        http_client = FakeLiveKitRoomServiceHTTPClient(LiveKitRoomServiceHTTPResponse(503, '{"code":"unavailable"}'))
        provisioner = LiveKitRoomServiceProvisioner(
            "wss://livekit.example.test",
            "test-api-key",
            "test-signing-key",
            http_client=http_client,
        )

        with self.assertRaises(CallServiceError) as context:
            await provisioner.ensure_room("salemx-dc-unavailable")

        self.assertEqual(context.exception.errcode, "M_DIRECT_CALL_LIVEKIT_ROOM_UNAVAILABLE")
        self.assertNotIn("salemx-dc-unavailable", context.exception.error)


class LiveKitJWTTokenIssuerTests(unittest.IsolatedAsyncioTestCase):
    async def test_issued_token_grants_are_scoped_to_one_room_without_admin_grants(self) -> None:
        issuer = LiveKitJWTTokenIssuer(api_key="test-api-key", api_secret="test-signing-key", token_ttl_seconds=120)
        allocation = Allocation(
            id="allocation-a",
            call_id="call-a",
            room_id="!room:example.test",
            intent="audio",
            livekit_room_name="salemx-dc-allocation-a",
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=300),
        )
        request = TokenRequest.from_mapping({
            "version": 1,
            "call_id": "call-a",
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "direction": "outgoing",
        })

        issued = await issuer.issue_token(AuthenticatedUser("@alice:example.test"), request, allocation)
        claims = self.decode_unverified_claims(issued.participant_token)

        self.assertEqual(claims["iss"], "test-api-key")
        self.assertIsInstance(claims["sub"], str)
        self.assertTrue(claims["sub"])
        self.assertNotIn("iat", claims)
        self.assertIsInstance(claims["nbf"], int)
        self.assertIsInstance(claims["exp"], int)
        self.assertLess(claims["nbf"], claims["exp"])
        self.assertEqual(claims["video"]["room"], "salemx-dc-allocation-a")
        self.assertTrue(claims["video"]["roomJoin"])
        self.assertTrue(claims["video"]["canPublish"])
        self.assertTrue(claims["video"]["canSubscribe"])
        self.assertFalse(claims["video"]["canPublishData"])
        self.assertNotIn("roomAdmin", claims["video"])
        self.assertNotIn("!room:example.test", issued.participant_token)

    @staticmethod
    def decode_unverified_claims(token: str) -> dict[str, object]:
        payload = token.split(".")[1]
        padded = payload + "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(padded.encode("ascii")))

    @staticmethod
    def verify_hs256_signature(token: str, signing_key: str) -> bool:
        header, payload, signature = token.split(".")
        expected_signature = hmac.new(signing_key.encode("utf-8"),
                                      f"{header}.{payload}".encode("ascii"),
                                      hashlib.sha256).digest()
        expected = base64.urlsafe_b64encode(expected_signature).rstrip(b"=").decode("ascii")
        return hmac.compare_digest(signature, expected)


class FakeSynapseHTTPClient:
    def __init__(self, responses: dict[str, SynapseHTTPResponse]) -> None:
        self.responses = responses
        self.paths: list[str] = []

    async def get_json(self, path: str) -> SynapseHTTPResponse:
        self.paths.append(path)
        return self.responses.get(path, SynapseHTTPResponse(status_code=404, json_body=None))


class SynapseRoomValidatorTests(unittest.IsolatedAsyncioTestCase):
    room_id = "!room:example.test"
    encoded_room_id = "%21room%3Aexample.test"
    members_path = f"/_synapse/admin/v1/rooms/{encoded_room_id}/members"
    state_path = f"/_synapse/admin/v1/rooms/{encoded_room_id}/state"

    def make_validator(self, members_response: SynapseHTTPResponse, state_response: SynapseHTTPResponse) -> tuple[SynapseRoomValidator, FakeSynapseHTTPClient]:
        http_client = FakeSynapseHTTPClient({
            self.members_path: members_response,
            self.state_path: state_response,
        })
        return SynapseRoomValidator("https://synapse.example.test", "admin-token-sensitive", http_client), http_client

    def token_request(self, peer_user_id: str = "@bob:example.test") -> TokenRequest:
        return TokenRequest.from_mapping({
            "version": 1,
            "call_id": "call-a",
            "room_id": self.room_id,
            "peer_user_id": peer_user_id,
            "intent": "audio",
            "direction": "outgoing",
        })

    async def validate(self, members_body: object, state_body: object, peer_user_id: str = "@bob:example.test") -> RoomEligibility:
        validator, _ = self.make_validator(
            SynapseHTTPResponse(status_code=200, json_body=members_body),
            SynapseHTTPResponse(status_code=200, json_body=state_body),
        )
        return await validator.validate_direct_call_room(AuthenticatedUser("@alice:example.test"), self.token_request(peer_user_id))

    async def expect_error(self,
                           members_response: SynapseHTTPResponse,
                           state_response: SynapseHTTPResponse,
                           errcode: str,
                           peer_user_id: str = "@bob:example.test") -> None:
        validator, _ = self.make_validator(members_response, state_response)
        with self.assertRaises(CallServiceError) as context:
            await validator.validate_direct_call_room(AuthenticatedUser("@alice:example.test"), self.token_request(peer_user_id))
        self.assertEqual(context.exception.errcode, errcode)

    async def test_valid_encrypted_one_to_one_room_passes(self) -> None:
        validator, http_client = self.make_validator(
            SynapseHTTPResponse(status_code=200, json_body={"members": ["@alice:example.test", "@bob:example.test"]}),
            SynapseHTTPResponse(status_code=200, json_body={"state": [{"type": "m.room.encryption", "content": {"algorithm": "m.megolm.v1.aes-sha2"}}]}),
        )

        eligibility = await validator.validate_direct_call_room(AuthenticatedUser("@alice:example.test"), self.token_request())

        self.assertEqual(eligibility.joined_user_ids, ("@alice:example.test", "@bob:example.test"))
        self.assertTrue(eligibility.is_encrypted)
        self.assertEqual(http_client.paths, [self.members_path, self.state_path])

    async def test_requester_not_joined_rejected(self) -> None:
        await self.expect_error(
            SynapseHTTPResponse(status_code=200, json_body={"members": ["@charlie:example.test", "@bob:example.test"]}),
            SynapseHTTPResponse(status_code=200, json_body={"state": [{"type": "m.room.encryption"}]}),
            "M_NOT_JOINED",
        )

    async def test_peer_not_joined_rejected(self) -> None:
        await self.expect_error(
            SynapseHTTPResponse(status_code=200, json_body={"members": ["@alice:example.test", "@charlie:example.test"]}),
            SynapseHTTPResponse(status_code=200, json_body={"state": [{"type": "m.room.encryption"}]}),
            "M_DIRECT_CALL_PEER_MISMATCH",
        )

    async def test_more_than_two_joined_members_rejected(self) -> None:
        await self.expect_error(
            SynapseHTTPResponse(status_code=200, json_body={"members": ["@alice:example.test", "@bob:example.test", "@charlie:example.test"]}),
            SynapseHTTPResponse(status_code=200, json_body={"state": [{"type": "m.room.encryption"}]}),
            "M_DIRECT_CALL_NOT_1_TO_1",
        )

    async def test_room_without_encryption_rejected(self) -> None:
        await self.expect_error(
            SynapseHTTPResponse(status_code=200, json_body={"members": ["@alice:example.test", "@bob:example.test"]}),
            SynapseHTTPResponse(status_code=200, json_body={"state": [{"type": "m.room.name"}]}),
            "M_ROOM_NOT_ENCRYPTED",
        )

    async def test_synapse_forbidden_fails_closed(self) -> None:
        await self.expect_error(
            SynapseHTTPResponse(status_code=403, json_body={"errcode": "M_FORBIDDEN"}),
            SynapseHTTPResponse(status_code=200, json_body={"state": [{"type": "m.room.encryption"}]}),
            "M_FORBIDDEN",
        )

    async def test_synapse_not_found_fails_closed(self) -> None:
        await self.expect_error(
            SynapseHTTPResponse(status_code=404, json_body={"errcode": "M_NOT_FOUND"}),
            SynapseHTTPResponse(status_code=200, json_body={"state": [{"type": "m.room.encryption"}]}),
            "M_UNKNOWN",
        )

    async def test_malformed_synapse_response_fails_closed(self) -> None:
        await self.expect_error(
            SynapseHTTPResponse(status_code=200, json_body={"members": "not-a-list"}),
            SynapseHTTPResponse(status_code=200, json_body={"state": [{"type": "m.room.encryption"}]}),
            "M_UNKNOWN",
        )

    async def test_admin_token_not_in_logs_or_errors(self) -> None:
        validator, _ = self.make_validator(
            SynapseHTTPResponse(status_code=200, json_body={"members": ["@alice:example.test", "@bob:example.test"]}),
            SynapseHTTPResponse(status_code=200, json_body={"state": [{"type": "m.room.name"}]}),
        )

        with self.assertLogs("salemx_call_service.room_validation", level="INFO") as logs:
            with self.assertRaises(CallServiceError) as context:
                await validator.validate_direct_call_room(AuthenticatedUser("@alice:example.test"), self.token_request())

        self.assertEqual(context.exception.errcode, "M_ROOM_NOT_ENCRYPTED")
        log_output = "\n".join(logs.output)
        self.assertNotIn("admin-token-sensitive", log_output)
        self.assertNotIn("!room:example.test", log_output)
        self.assertNotIn("@alice:example.test", log_output)
        self.assertNotIn("admin-token-sensitive", str(context.exception))


class LocalFakeModeTests(unittest.IsolatedAsyncioTestCase):
    async def test_fake_mode_is_off_by_default(self) -> None:
        from salemx_call_service import local_fake

        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(local_fake.fake_mode_enabled())

    async def test_fake_mode_accepts_non_empty_bearer_and_can_issue_app_shaped_response(self) -> None:
        from salemx_call_service import local_fake

        with patch.dict(os.environ, {
            local_fake.FAKE_MODE_ENV: "1",
        }, clear=True):
            service = local_fake.make_fake_local_service()
            response = await service.issue_token("Bearer local-fake-bearer", {
                "version": 1,
                "call_id": "call-a",
                "room_id": "!runtime-room:example.test",
                "peer_user_id": "@runtime-peer:example.test",
                "intent": "audio",
                "direction": "outgoing",
                "device_id": "REALDEVICE",
            })

        body = response.as_dict()
        self.assertEqual(body["version"], 1)
        self.assertEqual(body["allocation"]["call_id"], "call-a")
        self.assertEqual(body["allocation"]["intent"], "audio")
        self.assertTrue(body["livekit"]["room_name"].startswith("salemx-dc-"))
        self.assertEqual(body["livekit"]["server_url"], DEFAULT_FAKE_LIVEKIT_URL)
        self.assertTrue(body["livekit"]["participant_token"])

    async def test_fake_mode_uses_memory_rate_limiter(self) -> None:
        from salemx_call_service import local_fake

        with patch.dict(os.environ, {
            local_fake.FAKE_MODE_ENV: "1",
        }, clear=True):
            service = local_fake.make_fake_local_service()

        self.assertIsInstance(service.rate_limiter, InMemoryRateLimiter)

    async def test_fake_mode_uses_livekit_url_env_when_present(self) -> None:
        from salemx_call_service import local_fake

        with patch.dict(os.environ, {
            local_fake.FAKE_MODE_ENV: "1",
            local_fake.FAKE_LIVEKIT_URL_ENV: "ws://localhost:7880",
            local_fake.FAKE_LIVEKIT_API_KEY_ENV: "test-api-key",
            local_fake.FAKE_LIVEKIT_API_SECRET_ENV: "test-signing-key",
        }, clear=True):
            service = local_fake.make_fake_local_service()
            response = await service.issue_token("Bearer local-fake-bearer", {
                "version": 1,
                "call_id": "call-a",
                "room_id": "!runtime-room:example.test",
                "peer_user_id": "@runtime-peer:example.test",
                "intent": "audio",
                "direction": "outgoing",
                "device_id": "REALDEVICE",
            })

        body = response.as_dict()
        self.assertEqual(body["version"], 1)
        self.assertEqual(body["livekit"]["server_url"], "ws://localhost:7880")
        self.assertEqual(body["allocation"]["call_id"], "call-a")
        self.assertTrue(body["livekit"]["room_name"].startswith("salemx-dc-"))
        self.assertTrue(body["livekit"]["participant_token"])

    async def test_fake_mode_uses_livekit_jwt_when_api_credentials_are_present(self) -> None:
        from salemx_call_service import local_fake

        with patch.dict(os.environ, {
            local_fake.FAKE_MODE_ENV: "1",
            local_fake.FAKE_LIVEKIT_URL_ENV: "ws://localhost:7880",
            local_fake.FAKE_LIVEKIT_API_KEY_ENV: "test-api-key",
            local_fake.FAKE_LIVEKIT_API_SECRET_ENV: "test-signing-key",
        }, clear=True):
            service = local_fake.make_fake_local_service()
            response = await service.issue_token("Bearer local-fake-bearer", {
                "version": 1,
                "call_id": "call-a",
                "room_id": "!runtime-room:example.test",
                "peer_user_id": "@runtime-peer:example.test",
                "intent": "audio",
                "direction": "outgoing",
                "device_id": "REALDEVICE",
            })
            incoming_response = await service.issue_token("Bearer local-fake-bearer", {
                "version": 1,
                "call_id": "call-a",
                "room_id": "!runtime-room:example.test",
                "peer_user_id": "@runtime-peer:example.test",
                "intent": "audio",
                "direction": "incoming",
                "device_id": "REALDEVICE",
            })

        body = response.as_dict()
        participant_token = body["livekit"]["participant_token"]
        claims = LiveKitJWTTokenIssuerTests.decode_unverified_claims(participant_token)
        self.assertEqual(claims["iss"], "test-api-key")
        self.assertTrue(claims["sub"])
        self.assertIsInstance(claims["iat"], int)
        self.assertIsInstance(claims["nbf"], int)
        self.assertIsInstance(claims["exp"], int)
        self.assertLess(claims["nbf"], claims["exp"])
        self.assertEqual(claims["video"]["room"], body["livekit"]["room_name"])
        self.assertTrue(claims["video"]["roomJoin"])
        self.assertTrue(claims["video"]["canPublish"])
        self.assertTrue(claims["video"]["canSubscribe"])
        self.assertFalse(claims["video"]["canPublishData"])
        self.assertTrue(LiveKitJWTTokenIssuerTests.verify_hs256_signature(participant_token, "test-signing-key"))
        incoming_claims = LiveKitJWTTokenIssuerTests.decode_unverified_claims(incoming_response.as_dict()["livekit"]["participant_token"])
        self.assertNotEqual(claims["sub"], incoming_claims["sub"])

    async def test_fake_mode_uses_placeholder_token_without_api_credentials(self) -> None:
        from salemx_call_service import local_fake

        with patch.dict(os.environ, {
            local_fake.FAKE_MODE_ENV: "1",
            local_fake.FAKE_LIVEKIT_URL_ENV: "ws://localhost:7880",
        }, clear=True):
            service = local_fake.make_fake_local_service()
            response = await service.issue_token("Bearer local-fake-bearer", {
                "version": 1,
                "call_id": "call-a",
                "room_id": "!runtime-room:example.test",
                "peer_user_id": "@runtime-peer:example.test",
                "intent": "audio",
                "direction": "outgoing",
                "device_id": "REALDEVICE",
            })

        self.assertEqual(response.as_dict()["livekit"]["participant_token"], "local-smoke-participant-token")

    async def test_fake_mode_uses_default_livekit_url_when_env_is_blank(self) -> None:
        from salemx_call_service import local_fake

        with patch.dict(os.environ, {
            local_fake.FAKE_MODE_ENV: "1",
            local_fake.FAKE_LIVEKIT_URL_ENV: "   ",
        }, clear=True):
            service = local_fake.make_fake_local_service()
            response = await service.issue_token("Bearer local-fake-bearer", {
                "version": 1,
                "call_id": "call-a",
                "room_id": "!runtime-room:example.test",
                "peer_user_id": "@runtime-peer:example.test",
                "intent": "audio",
                "direction": "outgoing",
                "device_id": "REALDEVICE",
            })

        self.assertEqual(response.as_dict()["livekit"]["server_url"], DEFAULT_FAKE_LIVEKIT_URL)

    async def test_fake_mode_rejects_missing_bearer(self) -> None:
        from salemx_call_service import local_fake

        with patch.dict(os.environ, {local_fake.FAKE_MODE_ENV: "1"}, clear=True):
            service = local_fake.make_fake_local_service()
            with self.assertRaises(CallServiceError) as context:
                await service.issue_token(None, {
                    "version": 1,
                    "call_id": "call-a",
                    "room_id": "!runtime-room:example.test",
                    "peer_user_id": "@runtime-peer:example.test",
                    "intent": "audio",
                    "direction": "outgoing",
                })

        self.assertEqual(context.exception.errcode, "M_UNKNOWN_TOKEN")

    async def test_fake_mode_rejects_blank_bearer(self) -> None:
        from salemx_call_service import local_fake

        with patch.dict(os.environ, {local_fake.FAKE_MODE_ENV: "1"}, clear=True):
            service = local_fake.make_fake_local_service()
            with self.assertRaises(CallServiceError) as context:
                await service.issue_token("Bearer   ", {
                    "version": 1,
                    "call_id": "call-a",
                    "room_id": "!runtime-room:example.test",
                    "peer_user_id": "@runtime-peer:example.test",
                    "intent": "audio",
                    "direction": "outgoing",
                })

        self.assertEqual(context.exception.errcode, "M_UNKNOWN_TOKEN")

    async def test_fake_mode_does_not_log_bearer_value(self) -> None:
        from salemx_call_service import local_fake

        local_bearer = "redaction-check-bearer"
        with patch.dict(os.environ, {local_fake.FAKE_MODE_ENV: "1"}, clear=True):
            service = local_fake.make_fake_local_service()
            with self.assertLogs("salemx_call_service.service", level="INFO") as logs:
                await service.issue_token(f"Bearer {local_bearer}", {
                    "version": 1,
                    "call_id": "call-a",
                    "room_id": "!runtime-room:example.test",
                    "peer_user_id": "@runtime-peer:example.test",
                    "intent": "audio",
                    "direction": "outgoing",
                })

        self.assertNotIn(local_bearer, "\n".join(logs.output))

    async def test_fake_mode_token_endpoint_returns_200(self) -> None:
        try:
            with patch.dict(os.environ, {SERVICE_MODE_ENV: ServiceMode.LOCAL_FAKE.value, FAKE_MODE_ENV: "1"}, clear=True):
                from salemx_call_service.app import ENDPOINT_PATH, create_app
        except ModuleNotFoundError as error:
            if error.name == "fastapi":
                self.skipTest("FastAPI is not installed in this Python environment.")
            raise

        with patch.dict(os.environ, {
            SERVICE_MODE_ENV: ServiceMode.LOCAL_FAKE.value,
            FAKE_MODE_ENV: "1",
            FAKE_LIVEKIT_URL_ENV: "ws://localhost:7880",
            FAKE_LIVEKIT_API_KEY_ENV: "test-api-key",
            FAKE_LIVEKIT_API_SECRET_ENV: "test-signing-key",
        }, clear=True):
            app = create_app()

        status_code, body = await _asgi_post_json(app, ENDPOINT_PATH, {
            "authorization": "Bearer local-fake-bearer",
            "content-type": "application/json",
        }, {
            "version": 1,
            "call_id": "call-a",
            "room_id": "!runtime-room:example.test",
            "peer_user_id": "@runtime-peer:example.test",
            "intent": "audio",
            "direction": "outgoing",
            "device_id": "REALDEVICE",
        })

        self.assertEqual(status_code, 200)
        self.assertEqual(body["version"], 1)
        self.assertEqual(body["allocation"]["call_id"], "call-a")
        self.assertEqual(body["allocation"]["intent"], "audio")
        self.assertEqual(body["livekit"]["server_url"], "ws://localhost:7880")
        self.assertTrue(body["livekit"]["room_name"].startswith("salemx-dc-"))
        claims = LiveKitJWTTokenIssuerTests.decode_unverified_claims(body["livekit"]["participant_token"])
        self.assertEqual(claims["iss"], "test-api-key")
        self.assertEqual(claims["video"]["room"], body["livekit"]["room_name"])
        self.assertTrue(LiveKitJWTTokenIssuerTests.verify_hs256_signature(body["livekit"]["participant_token"], "test-signing-key"))

    async def test_token_endpoint_over_redis_rate_limit_returns_429_without_second_token(self) -> None:
        try:
            with patch.dict(os.environ, {SERVICE_MODE_ENV: ServiceMode.LOCAL_FAKE.value}, clear=True):
                from salemx_call_service.app import ENDPOINT_PATH, create_app
        except ModuleNotFoundError as error:
            if error.name == "fastapi":
                self.skipTest("FastAPI is not installed in this Python environment.")
            raise

        issuer = FakeLiveKitTokenIssuer()
        service = DirectCallTokenServiceTests().make_service(
            issuer=issuer,
            rate_limiter=RedisRateLimiter(FakeRedisRateLimitClient(), StorageKeyHasher("storage-key-secret")),
            rate_limit_per_minute=1,
        )
        app = create_app(token_service=service)
        payload = DirectCallTokenServiceTests().valid_payload()

        first_status, first_body = await _asgi_post_json(app, ENDPOINT_PATH, {
            "authorization": "Bearer matrix-token-a-sensitive",
            "content-type": "application/json",
        }, payload | {"client_transaction_id": "txn-route-1"})
        second_status, second_body = await _asgi_post_json(app, ENDPOINT_PATH, {
            "authorization": "Bearer matrix-token-a-sensitive",
            "content-type": "application/json",
        }, payload | {"client_transaction_id": "txn-route-2"})

        self.assertEqual(first_status, 200)
        self.assertIn("livekit", first_body)
        self.assertEqual(second_status, 429)
        self.assertEqual(second_body["errcode"], "M_DIRECT_CALL_RATE_LIMITED")
        self.assertIsInstance(second_body["retry_after_ms"], int)
        self.assertNotIn("participant_token", second_body)
        self.assertEqual(len(issuer.issued), 1)

    async def test_eligibility_endpoint_returns_redacted_unavailable_response(self) -> None:
        try:
            with patch.dict(os.environ, {SERVICE_MODE_ENV: ServiceMode.LOCAL_FAKE.value}, clear=True):
                from salemx_call_service.app import ELIGIBILITY_PATH, create_app
        except ModuleNotFoundError as error:
            if error.name == "fastapi":
                self.skipTest("FastAPI is not installed in this Python environment.")
            raise

        service = DirectCallTokenServiceTests().make_service(
            eligibility_policy=StaticAllowlistNativeAudioEligibilityPolicy(allowed_user_ids=("@bob:example.test",)),
        )
        app = create_app(token_service=service)

        status, body = await _asgi_post_json(app, ELIGIBILITY_PATH, {
            "authorization": "Bearer matrix-token-a-sensitive",
            "content-type": "application/json",
        }, {
            "version": 1,
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "device_id": "DEVICEA",
        })
        output = json.dumps(body, sort_keys=True)

        self.assertEqual(status, 200)
        self.assertEqual(body["state"], "unavailable")
        self.assertEqual(body["reason"], "accountNotEligible")
        self.assertIn("account_eligible", body)
        self.assertNotIn("!room:example.test", output)
        self.assertNotIn("@alice:example.test", output)
        self.assertNotIn("@bob:example.test", output)
        self.assertNotIn("DEVICEA", output)
        self.assertNotIn("participant_token", output)

    async def test_eligibility_endpoint_returns_eligible_when_allowlisted(self) -> None:
        try:
            with patch.dict(os.environ, {SERVICE_MODE_ENV: ServiceMode.LOCAL_FAKE.value}, clear=True):
                from salemx_call_service.app import ELIGIBILITY_PATH, create_app
        except ModuleNotFoundError as error:
            if error.name == "fastapi":
                self.skipTest("FastAPI is not installed in this Python environment.")
            raise

        service = DirectCallTokenServiceTests().make_service(
            eligibility_policy=StaticAllowlistNativeAudioEligibilityPolicy(
                allowed_user_ids=("@alice:example.test", "@bob:example.test"),
            ),
        )
        app = create_app(token_service=service)

        status, body = await _asgi_post_json(app, ELIGIBILITY_PATH, {
            "authorization": "Bearer matrix-token-a-sensitive",
            "content-type": "application/json",
        }, {
            "version": 1,
            "room_id": "!room:example.test",
            "peer_user_id": "@bob:example.test",
            "intent": "audio",
            "device_id": "DEVICEA",
        })

        self.assertEqual(status, 200)
        self.assertEqual(body["state"], "eligible")
        self.assertIsNone(body["reason"])
        self.assertTrue(body["account_eligible"])
        self.assertTrue(body["peer_eligible"])
        self.assertTrue(body["room_eligible"])

    async def test_staging_mode_refuses_fake_mode(self) -> None:
        app_module = _load_app_module()

        with patch.dict(os.environ, _staging_env({FAKE_MODE_ENV: "1"}), clear=True):
            with self.assertRaisesRegex(RuntimeError, "fakeModeForbidden"):
                app_module.create_app()
            app = app_module.create_app(strict_startup=False)

        status_code, body = await _asgi_get_json(app, app_module.READINESS_PATH)
        self.assertEqual(status_code, 503)
        self.assertFalse(body["ready"])
        self.assertEqual(body["reason"], "fakeModeForbidden")

    async def test_staging_mode_refuses_missing_synapse_config(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({"SYNAPSE_BASE_URL": "", "SYNAPSE_ADMIN_TOKEN": ""})

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "missingSynapseConfig"):
                app_module.create_app()

    async def test_staging_mode_refuses_missing_livekit_config(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({"LIVEKIT_URL": "", "LIVEKIT_API_KEY": "", "LIVEKIT_API_SECRET": ""})

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "missingLiveKitConfig"):
                app_module.create_app()

    async def test_staging_mode_refuses_insecure_livekit_url_unless_explicitly_allowed(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({"LIVEKIT_URL": "ws://livekit.example.test"})

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "insecureLiveKitURL"):
                app_module.create_app()

        with patch.dict(os.environ, env | {ALLOW_INSECURE_LIVEKIT_URL_ENV: "1"}, clear=True), _patch_redis_ping(app_module):
            app = app_module.create_app()

        status_code, body = await _asgi_get_json(app, app_module.READINESS_PATH)
        self.assertEqual(status_code, 200)
        self.assertTrue(body["ready"])
        self.assertEqual(body["reason"], "ok")
        self.assertFalse(body["liveKitURLSecure"])

    async def test_staging_mode_refuses_placeholder_livekit_url(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({"LIVEKIT_URL": "wss://local-smoke.livekit.invalid"})

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "placeholderLiveKitURL"):
                app_module.create_app()

    async def test_staging_mode_refuses_invalid_token_ttl(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({"TOKEN_TTL_SECONDS": "9999"})

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "invalidTokenTTL"):
                app_module.create_app()

    async def test_staging_mode_refuses_memory_rate_limiter_by_default(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({
            RATE_LIMIT_STORE_ENV: RateLimitStoreKind.MEMORY.value,
            RATE_LIMIT_STORE_URL_ENV: "",
        })

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "invalidRateLimitConfig"):
                app_module.create_app()

    async def test_staging_mode_accepts_declared_shared_rate_limiter_without_exposing_secret(self) -> None:
        app_module = _load_app_module()
        rate_limit_secret = "rate-limit-store-password-sensitive"
        env = _staging_env({
            RATE_LIMIT_STORE_ENV: RateLimitStoreKind.REDIS.value,
            RATE_LIMIT_STORE_URL_ENV: f"redis://:{rate_limit_secret}@rate-limit.example.test/0",
        })

        with patch.dict(os.environ, env, clear=True), _patch_redis_ping(app_module):
            app = app_module.create_app()

        status_code, body = await _asgi_get_json(app, app_module.READINESS_PATH)
        output = json.dumps(body, sort_keys=True)

        self.assertEqual(status_code, 200)
        self.assertTrue(body["ready"])
        self.assertTrue(body["rateLimitConfigured"])
        self.assertTrue(body["rateLimitShared"])
        self.assertTrue(body["rateLimitConnected"])
        self.assertNotIn(rate_limit_secret, output)
        self.assertNotIn("rate-limit.example.test", output)

    async def test_staging_mode_refuses_memory_allocation_store_by_default(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.MEMORY.value,
            ALLOCATION_STORE_URL_ENV: "",
        })

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "memoryAllocationStoreForbidden"):
                app_module.create_app()

    async def test_staging_mode_allows_memory_allocation_store_with_explicit_override(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.MEMORY.value,
            ALLOCATION_STORE_URL_ENV: "",
            ALLOW_MEMORY_ALLOCATION_STORE_ENV: "1",
        })

        with patch.dict(os.environ, env, clear=True), _patch_redis_ping(app_module):
            app = app_module.create_app()

        status_code, body = await _asgi_get_json(app, app_module.READINESS_PATH)
        self.assertEqual(status_code, 200)
        self.assertTrue(body["ready"])
        self.assertTrue(body["allocationStoreConfigured"])
        self.assertFalse(body["allocationStoreShared"])
        self.assertTrue(body["allocationStoreConnected"])

    async def test_staging_mode_accepts_declared_shared_allocation_store_without_exposing_secret(self) -> None:
        app_module = _load_app_module()
        allocation_store_secret = "allocation-store-password-sensitive"
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.REDIS.value,
            ALLOCATION_STORE_URL_ENV: f"redis://:{allocation_store_secret}@allocation.example.test/0",
        })

        with patch.dict(os.environ, env, clear=True), _patch_redis_ping(app_module):
            app = app_module.create_app()

        status_code, body = await _asgi_get_json(app, app_module.READINESS_PATH)
        output = json.dumps(body, sort_keys=True)

        self.assertEqual(status_code, 200)
        self.assertTrue(body["ready"])
        self.assertEqual(body["reason"], "ok")
        self.assertTrue(body["allocationStoreConfigured"])
        self.assertTrue(body["allocationStoreShared"])
        self.assertTrue(body["allocationStoreConnected"])
        self.assertNotIn(allocation_store_secret, output)
        self.assertNotIn("allocation.example.test", output)

    async def test_staging_readiness_fails_when_allocation_redis_ping_fails(self) -> None:
        app_module = _load_app_module()
        allocation_store_secret = "allocation-store-password-sensitive"
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.REDIS.value,
            ALLOCATION_STORE_URL_ENV: f"redis://:{allocation_store_secret}@allocation.example.test/0",
        })

        with patch.dict(os.environ, env, clear=True), _patch_redis_ping(app_module, allocation_connected=False):
            with self.assertRaisesRegex(RuntimeError, "allocationStoreUnavailable"):
                app_module.create_app()
            app = app_module.create_app(strict_startup=False)

        status_code, body = await _asgi_get_json(app, app_module.READINESS_PATH)
        output = json.dumps(body, sort_keys=True)

        self.assertEqual(status_code, 503)
        self.assertFalse(body["ready"])
        self.assertEqual(body["reason"], "allocationStoreUnavailable")
        self.assertFalse(body["allocationStoreConnected"])
        self.assertTrue(body["rateLimitConnected"])
        self.assertNotIn(allocation_store_secret, output)
        self.assertNotIn("allocation.example.test", output)

    async def test_staging_readiness_fails_when_rate_limit_redis_ping_fails(self) -> None:
        app_module = _load_app_module()
        rate_limit_secret = "rate-limit-store-password-sensitive"
        env = _staging_env({
            RATE_LIMIT_STORE_ENV: RateLimitStoreKind.REDIS.value,
            RATE_LIMIT_STORE_URL_ENV: f"redis://:{rate_limit_secret}@rate-limit.example.test/0",
        })

        with patch.dict(os.environ, env, clear=True), _patch_redis_ping(app_module, rate_limit_connected=False):
            with self.assertRaisesRegex(RuntimeError, "rateLimitStoreUnavailable"):
                app_module.create_app()
            app = app_module.create_app(strict_startup=False)

        status_code, body = await _asgi_get_json(app, app_module.READINESS_PATH)
        output = json.dumps(body, sort_keys=True)

        self.assertEqual(status_code, 503)
        self.assertFalse(body["ready"])
        self.assertEqual(body["reason"], "rateLimitStoreUnavailable")
        self.assertTrue(body["allocationStoreConnected"])
        self.assertFalse(body["rateLimitConnected"])
        self.assertNotIn(rate_limit_secret, output)
        self.assertNotIn("rate-limit.example.test", output)

    async def test_staging_readiness_rechecks_redis_without_recreating_app(self) -> None:
        app_module = _load_app_module()
        redis_status = {"allocation": True, "rate_limit": True}
        env = _staging_env()

        with patch.dict(os.environ, env, clear=True), _patch_redis_ping_from_status(app_module, redis_status):
            app = app_module.create_app()

            available_status, available_body = await _asgi_get_json(app, app_module.READINESS_PATH)
            redis_status["rate_limit"] = False
            unavailable_status, unavailable_body = await _asgi_get_json(app, app_module.READINESS_PATH)
            redis_status["rate_limit"] = True
            restored_status, restored_body = await _asgi_get_json(app, app_module.READINESS_PATH)

        self.assertEqual(available_status, 200)
        self.assertTrue(available_body["ready"])
        self.assertEqual(available_body["reason"], "ok")
        self.assertTrue(available_body["allocationStoreConnected"])
        self.assertTrue(available_body["rateLimitConnected"])

        self.assertEqual(unavailable_status, 503)
        self.assertFalse(unavailable_body["ready"])
        self.assertEqual(unavailable_body["reason"], "rateLimitStoreUnavailable")
        self.assertTrue(unavailable_body["allocationStoreConnected"])
        self.assertFalse(unavailable_body["rateLimitConnected"])

        self.assertEqual(restored_status, 200)
        self.assertTrue(restored_body["ready"])
        self.assertEqual(restored_body["reason"], "ok")
        self.assertTrue(restored_body["allocationStoreConnected"])
        self.assertTrue(restored_body["rateLimitConnected"])

    async def test_staging_mode_refuses_postgres_allocation_until_implemented(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.POSTGRES.value,
            ALLOCATION_STORE_URL_ENV: "postgres://allocation.example.test/db",
        })

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "unsupportedAllocationStore"):
                app_module.create_app()

    async def test_staging_mode_refuses_missing_storage_key_secret_for_redis(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({STORAGE_KEY_SECRET_ENV: ""})

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "missingStorageKeySecret"):
                app_module.create_app()

    async def test_staging_mode_refuses_shared_allocation_store_without_location(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({
            ALLOCATION_STORE_ENV: AllocationStoreKind.POSTGRES.value,
            ALLOCATION_STORE_URL_ENV: "",
        })

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "missingAllocationStoreConfig"):
                app_module.create_app()

    async def test_staging_mode_refuses_unsupported_allocation_store(self) -> None:
        app_module = _load_app_module()
        env = _staging_env({
            ALLOCATION_STORE_ENV: "filesystem",
            ALLOCATION_STORE_URL_ENV: "/tmp/allocation-store",
        })

        with patch.dict(os.environ, env, clear=True):
            with self.assertRaisesRegex(RuntimeError, "unsupportedAllocationStore"):
                app_module.create_app()

    async def test_health_and_readiness_do_not_expose_secrets(self) -> None:
        app_module = _load_app_module()
        allocation_store_secret = "allocation-store-secret-sensitive"
        rate_limit_secret = "rate-limit-store-secret-sensitive"
        storage_key_secret = "storage-key-secret-sensitive"
        env = _staging_env({
            FAKE_MODE_ENV: "1",
            "SYNAPSE_ADMIN_TOKEN": "synapse-admin-token-sensitive",
            "LIVEKIT_API_SECRET": "livekit-api-secret-sensitive",
            ALLOCATION_STORE_URL_ENV: f"postgres://user:{allocation_store_secret}@allocation.example.test/db",
            RATE_LIMIT_STORE_URL_ENV: f"postgres://user:{rate_limit_secret}@rate-limit.example.test/db",
            STORAGE_KEY_SECRET_ENV: storage_key_secret,
        })

        with patch.dict(os.environ, env, clear=True):
            app = app_module.create_app(strict_startup=False)

        health_status, health_body = await _asgi_get_json(app, app_module.HEALTH_PATH)
        readiness_status, readiness_body = await _asgi_get_json(app, app_module.READINESS_PATH)
        output = json.dumps({"health": health_body, "readiness": readiness_body}, sort_keys=True)

        self.assertEqual(health_status, 200)
        self.assertEqual(readiness_status, 503)
        self.assertEqual(readiness_body["reason"], "fakeModeForbidden")
        self.assertNotIn("synapse-admin-token-sensitive", output)
        self.assertNotIn("livekit-api-secret-sensitive", output)
        self.assertNotIn("livekit-api-key-sensitive", output)
        self.assertNotIn(allocation_store_secret, output)
        self.assertNotIn("allocation.example.test", output)
        self.assertNotIn(rate_limit_secret, output)
        self.assertNotIn("rate-limit.example.test", output)
        self.assertNotIn(storage_key_secret, output)

    async def test_default_mode_still_requires_production_config(self) -> None:
        app_module = _load_app_module()

        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "missingSynapseConfig"):
                app_module.create_app()


async def _asgi_post_json(app: object, path: str, headers: dict[str, str], payload: dict[str, object]) -> tuple[int, dict[str, object]]:
    body = json.dumps(payload).encode("utf-8")
    sent_messages: list[dict[str, object]] = []
    received = False

    async def receive() -> dict[str, object]:
        nonlocal received
        if received:
            return {"type": "http.disconnect"}
        received = True
        return {"type": "http.request", "body": body, "more_body": False}

    async def send(message: dict[str, object]) -> None:
        sent_messages.append(message)

    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "POST",
        "scheme": "http",
        "path": path,
        "raw_path": path.encode("ascii"),
        "query_string": b"",
        "headers": [(key.encode("ascii"), value.encode("utf-8")) for key, value in headers.items()],
        "client": ("127.0.0.1", 12345),
        "server": ("testserver", 80),
    }
    await app(scope, receive, send)  # type: ignore[operator]

    status = next(message["status"] for message in sent_messages if message["type"] == "http.response.start")
    response_body = b"".join(message.get("body", b"") for message in sent_messages if message["type"] == "http.response.body")
    return int(status), json.loads(response_body.decode("utf-8"))


async def _asgi_get_json(app: object, path: str) -> tuple[int, dict[str, object]]:
    sent_messages: list[dict[str, object]] = []
    received = False

    async def receive() -> dict[str, object]:
        nonlocal received
        if received:
            return {"type": "http.disconnect"}
        received = True
        return {"type": "http.request", "body": b"", "more_body": False}

    async def send(message: dict[str, object]) -> None:
        sent_messages.append(message)

    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": "GET",
        "scheme": "http",
        "path": path,
        "raw_path": path.encode("ascii"),
        "query_string": b"",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "server": ("testserver", 80),
    }
    await app(scope, receive, send)  # type: ignore[operator]

    status = next(message["status"] for message in sent_messages if message["type"] == "http.response.start")
    response_body = b"".join(message.get("body", b"") for message in sent_messages if message["type"] == "http.response.body")
    return int(status), json.loads(response_body.decode("utf-8"))


def _load_app_module() -> object:
    try:
        with patch.dict(os.environ, {SERVICE_MODE_ENV: ServiceMode.LOCAL_FAKE.value}, clear=True):
            from salemx_call_service import app as app_module
    except ModuleNotFoundError as error:
        if error.name == "fastapi":
            raise unittest.SkipTest("FastAPI is not installed in this Python environment.") from error
        raise
    return app_module


def _patch_redis_ping(app_module: object,
                      allocation_connected: bool = True,
                      rate_limit_connected: bool = True) -> object:
    return _patch_redis_ping_from_status(
        app_module,
        {
            "allocation": allocation_connected,
            "rate_limit": rate_limit_connected,
        },
    )


def _patch_redis_ping_from_status(app_module: object, status: dict[str, bool]) -> object:
    def redis_ping(redis_url: str) -> bool:
        if "allocation" in redis_url:
            return status["allocation"]
        if "rate-limit" in redis_url:
            return status["rate_limit"]
        return status["allocation"] and status["rate_limit"]

    return patch.object(app_module, "_redis_ping_url", side_effect=redis_ping)


def _staging_env(overrides: dict[str, str] | None = None) -> dict[str, str]:
    env = {
        SERVICE_MODE_ENV: ServiceMode.STAGING.value,
        "SYNAPSE_BASE_URL": "https://synapse.example.test",
        "SYNAPSE_ADMIN_TOKEN": "synapse-admin-token-sensitive",
        "LIVEKIT_URL": "wss://livekit.example.test",
        "LIVEKIT_API_KEY": "livekit-api-key-sensitive",
        "LIVEKIT_API_SECRET": "livekit-api-secret-sensitive",
        ALLOCATION_STORE_ENV: AllocationStoreKind.REDIS.value,
        ALLOCATION_STORE_URL_ENV: "redis://allocation.example.test/0",
        RATE_LIMIT_STORE_ENV: RateLimitStoreKind.REDIS.value,
        RATE_LIMIT_STORE_URL_ENV: "redis://rate-limit.example.test/0",
        RATE_LIMIT_PER_MINUTE_ENV: "30",
        STORAGE_KEY_SECRET_ENV: "storage-key-secret-sensitive",
    }
    if overrides is not None:
        env.update(overrides)
    return env


if __name__ == "__main__":
    unittest.main()
