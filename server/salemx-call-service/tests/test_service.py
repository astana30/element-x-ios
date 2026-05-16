from __future__ import annotations

import asyncio
import base64
import json
import os
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from salemx_call_service.allocation import Allocation, InMemoryAllocationStore
from salemx_call_service.auth import AuthenticatedUser
from salemx_call_service.dto import TokenRequest
from salemx_call_service.errors import CallServiceError
from salemx_call_service.livekit_tokens import IssuedLiveKitToken, LiveKitGrant, LiveKitJWTTokenIssuer
from salemx_call_service.local_fake import (
    DEFAULT_FAKE_LIVEKIT_URL,
    DIRECT_CALL_CAPABILITY_NAME,
    FAKE_LIVEKIT_URL_ENV,
    FAKE_MODE_ENV,
    make_fake_capabilities_payload,
)
from salemx_call_service.room_validation import InMemoryRoomValidator, RoomEligibility, SynapseRoomValidator
from salemx_call_service.service import DirectCallTokenService
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
    def __init__(self) -> None:
        self.issued: list[tuple[AuthenticatedUser, TokenRequest, Allocation, LiveKitGrant]] = []

    async def issue_token(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest, allocation: Allocation) -> IssuedLiveKitToken:
        grant = LiveKitGrant(room_join=True, room=allocation.livekit_room_name, can_publish=True, can_subscribe=True, can_publish_data=False)
        self.issued.append((authenticated_user, token_request, allocation, grant))
        return IssuedLiveKitToken(
            participant_token="participant-token-sensitive",
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=120),
            grant=grant,
        )


class DirectCallTokenServiceTests(unittest.IsolatedAsyncioTestCase):
    def make_service(self, rooms: dict[str, RoomEligibility] | None = None, issuer: FakeLiveKitTokenIssuer | None = None) -> DirectCallTokenService:
        return DirectCallTokenService(
            auth_validator=FakeAuthValidator({
                "matrix-token-a-sensitive": AuthenticatedUser("@alice:example.test", "DEVICEA"),
                "matrix-token-b-sensitive": AuthenticatedUser("@bob:example.test", "DEVICEB"),
            }),
            room_validator=InMemoryRoomValidator(rooms or {
                "!room:example.test": RoomEligibility(("@alice:example.test", "@bob:example.test"), True),
            }),
            allocation_store=InMemoryAllocationStore(allocation_ttl_seconds=300),
            token_issuer=issuer or FakeLiveKitTokenIssuer(),
            livekit_server_url="wss://livekit.example.test",
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
        service = self.make_service(issuer=issuer)

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

    async def test_valid_incoming_reuses_allocation(self) -> None:
        service = self.make_service()

        outgoing = await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())
        incoming = await service.issue_token(
            "Bearer matrix-token-b-sensitive",
            self.valid_payload(peer_user_id="@alice:example.test", direction="incoming", device_id="DEVICEB"),
        )

        self.assertEqual(outgoing.allocation.id, incoming.allocation.id)
        self.assertEqual(outgoing.livekit.room_name, incoming.livekit.room_name)

    async def test_concurrent_same_call_reuses_allocation(self) -> None:
        service = self.make_service()

        responses = await asyncio.gather(
            service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-1")),
            service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload(client_transaction_id="txn-2")),
        )

        self.assertEqual(responses[0].allocation.id, responses[1].allocation.id)
        self.assertEqual(responses[0].livekit.room_name, responses[1].livekit.room_name)

    async def test_logs_do_not_contain_tokens_or_raw_room_id(self) -> None:
        service = self.make_service()

        with self.assertLogs("salemx_call_service.service", level="INFO") as logs:
            await service.issue_token("Bearer matrix-token-a-sensitive", self.valid_payload())

        joined_logs = "\n".join(logs.output)
        self.assertNotIn("matrix-token-a-sensitive", joined_logs)
        self.assertNotIn("participant-token-sensitive", joined_logs)
        self.assertNotIn("!room:example.test", joined_logs)


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
            with patch.dict(os.environ, {FAKE_MODE_ENV: "1"}, clear=True):
                from salemx_call_service.app import CAPABILITIES_PATH as app_capabilities_path
                from salemx_call_service.app import create_app
        except ModuleNotFoundError as error:
            if error.name == "fastapi":
                self.skipTest("FastAPI is not installed in this Python environment.")
            raise

        production_like_app = create_app(token_service=DirectCallTokenServiceTests().make_service())
        production_like_paths = {route.path for route in production_like_app.routes}

        with patch.dict(os.environ, {FAKE_MODE_ENV: "1"}, clear=False):
            fake_app = create_app()
        fake_paths = {route.path for route in fake_app.routes}

        self.assertNotIn(app_capabilities_path, production_like_paths)
        self.assertIn(app_capabilities_path, fake_paths)


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

    async def test_fake_mode_uses_livekit_url_env_when_present(self) -> None:
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

        body = response.as_dict()
        self.assertEqual(body["version"], 1)
        self.assertEqual(body["livekit"]["server_url"], "ws://localhost:7880")
        self.assertEqual(body["allocation"]["call_id"], "call-a")
        self.assertTrue(body["livekit"]["room_name"].startswith("salemx-dc-"))
        self.assertTrue(body["livekit"]["participant_token"])

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
            with patch.dict(os.environ, {FAKE_MODE_ENV: "1"}, clear=True):
                from salemx_call_service.app import ENDPOINT_PATH, create_app
        except ModuleNotFoundError as error:
            if error.name == "fastapi":
                self.skipTest("FastAPI is not installed in this Python environment.")
            raise

        with patch.dict(os.environ, {
            FAKE_MODE_ENV: "1",
            FAKE_LIVEKIT_URL_ENV: "ws://localhost:7880",
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
        self.assertTrue(body["livekit"]["participant_token"])

    async def test_default_mode_still_requires_production_config(self) -> None:
        try:
            with patch.dict(os.environ, {}, clear=True):
                from salemx_call_service.app import create_app
        except ModuleNotFoundError as error:
            if error.name == "fastapi":
                self.skipTest("FastAPI is not installed in this Python environment.")
            raise

        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "SYNAPSE_BASE_URL"):
                create_app()


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


if __name__ == "__main__":
    unittest.main()
