from __future__ import annotations

import asyncio
from dataclasses import dataclass
import json
from types import SimpleNamespace
import os
import time
import unittest
from uuid import UUID

import httpx

os.environ.setdefault("SALEMX_CALL_SERVICE_MODE", "local_fake")

from salemx_call_service import app as app_module
from salemx_call_service.apns_voip import _voip_payload
from salemx_call_service.auth import AuthenticatedUser
from salemx_call_service.errors import CallServiceError
from salemx_call_service.production_dispatch_store import (
    APNsOutcome,
    ConsumedDispatch,
    DispatchIdentity,
    DispatchReferences,
    DispatchSnapshot,
    DispatchState,
    SendAdmission,
)
from salemx_call_service.pushkit_tokens import InMemoryPushKitTokenStore, PushKitTokenRegistrationRequest
from salemx_call_service.room_validation import RoomEligibility


DISPATCH_ID = UUID("11111111-1111-4111-8111-111111111111")


class FakeAuthValidator:
    async def validate_bearer_token(self, bearer_token: str) -> AuthenticatedUser:
        users = {
            "auth-a": AuthenticatedUser("@sender:example.org", "SENDER"),
            "auth-b": AuthenticatedUser("@receiver:example.org", "RECEIVER"),
            "auth-other": AuthenticatedUser("@sender:example.org", "OTHER"),
            "auth-receiver-other": AuthenticatedUser("@receiver:example.org", "OTHER"),
        }
        if bearer_token not in users:
            raise CallServiceError(status_code=401, errcode="M_UNKNOWN_TOKEN", error="Unknown token.")
        return users[bearer_token]


class FakeRoomValidator:
    def __init__(self) -> None:
        self.encrypted = True
        self.members = ("@sender:example.org", "@receiver:example.org")
        self.requests = 0

    async def validate_direct_call_room(self, authenticated_user: AuthenticatedUser, token_request: object) -> RoomEligibility:
        self.requests += 1
        if not self.encrypted or len(self.members) != 2:
            raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Room is ineligible.")
        if authenticated_user.user_id not in self.members or getattr(token_request, "peer_user_id") not in self.members:
            raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Room is ineligible.")
        return RoomEligibility(self.members, self.encrypted)


@dataclass
class FakeDispatchStore:
    state: DispatchState = DispatchState.PREPARED
    apns_outcome: APNsOutcome | None = None
    send_attempts: int = 0
    captured_revision: int = 0
    sender: DispatchIdentity | None = None
    receiver: DispatchIdentity | None = None
    metadata: dict[str, object] | None = None
    capability_identity: DispatchIdentity | None = None
    capability_count: int = 0
    claim_count: int = 0
    cancel_count: int = 0
    consume_count: int = 0

    def register_capability(self, **values: object) -> object:
        self.capability_count += 1
        self.capability_identity = values["identity"]  # type: ignore[assignment]
        return SimpleNamespace()

    def create_dispatch(self, **values: object) -> DispatchReferences:
        self.sender = values["sender"]  # type: ignore[assignment]
        self.receiver = values["receiver"]  # type: ignore[assignment]
        self.captured_revision = int(values["receiver_token_binding_revision"])
        self.metadata = dict(values["metadata"])  # type: ignore[arg-type]
        self.state = DispatchState.PREPARED
        return DispatchReferences(DISPATCH_ID, "sender-reference", "receiver-reference")

    def claim_exact(self, dispatch_id: UUID, sender_reference: str, sender: DispatchIdentity) -> DispatchSnapshot:
        self._validate_sender(dispatch_id, sender_reference, sender)
        self.claim_count += 1
        if self.state == DispatchState.PREPARED:
            self.state = DispatchState.CLAIMED
        return self._snapshot()

    def inspect_exact(self,
                      dispatch_id: UUID,
                      sender_reference: str,
                      receiver_reference: str,
                      sender: DispatchIdentity,
                      receiver_token_binding_revision: int | None) -> ConsumedDispatch:
        self._validate_sender(dispatch_id, sender_reference, sender)
        if receiver_reference != "receiver-reference":
            raise AssertionError("wrong receiver reference")
        if receiver_token_binding_revision is not None and receiver_token_binding_revision != self.captured_revision:
            raise CallServiceError(status_code=409, errcode="M_CONFLICT", error="Binding rotated.")
        return ConsumedDispatch(self._snapshot(), self.metadata or {})

    def admit_send_exact(self,
                         dispatch_id: UUID,
                         sender_reference: str,
                         receiver_reference: str,
                         sender: DispatchIdentity,
                         receiver_token_binding_revision: int) -> SendAdmission:
        inspected = self.inspect_exact(
            dispatch_id, sender_reference, receiver_reference, sender, receiver_token_binding_revision,
        )
        if self.state == DispatchState.SENT:
            return SendAdmission(self._snapshot(), {}, True)
        if self.state != DispatchState.CLAIMED or self.send_attempts != 0:
            raise CallServiceError(status_code=409, errcode="M_CONFLICT", error="Already admitted.")
        self.send_attempts = 1
        self.state = DispatchState.SENDING
        return SendAdmission(self._snapshot(), inspected.metadata, False)

    def complete_send_exact(self,
                            dispatch_id: UUID,
                            sender_reference: str,
                            sender: DispatchIdentity,
                            outcome: APNsOutcome) -> DispatchSnapshot:
        self._validate_sender(dispatch_id, sender_reference, sender)
        self.apns_outcome = outcome
        self.state = {
            APNsOutcome.ACCEPTED: DispatchState.SENT,
            APNsOutcome.REJECTED: DispatchState.SEND_FAILED,
            APNsOutcome.UNKNOWN: DispatchState.DELIVERY_UNKNOWN,
        }[outcome]
        return self._snapshot()

    def cancel_exact(self, dispatch_id: UUID, sender_reference: str, sender: DispatchIdentity) -> DispatchSnapshot:
        self._validate_sender(dispatch_id, sender_reference, sender)
        self.cancel_count += 1
        self.state = DispatchState.CANCELLED
        return self._snapshot()

    def consume_exact(self,
                      dispatch_id: UUID,
                      receiver_reference: str,
                      receiver: DispatchIdentity) -> ConsumedDispatch:
        if dispatch_id != DISPATCH_ID or receiver_reference != "receiver-reference" or receiver != self.receiver:
            raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Receiver mismatch.")
        if self.state != DispatchState.SENT:
            raise CallServiceError(status_code=409, errcode="M_CONFLICT", error="Not consumable.")
        self.consume_count += 1
        self.state = DispatchState.CONSUMED
        return ConsumedDispatch(self._snapshot(), self.metadata or {})

    def _validate_sender(self, dispatch_id: UUID, sender_reference: str, sender: DispatchIdentity) -> None:
        if dispatch_id != DISPATCH_ID or sender_reference != "sender-reference" or sender != self.sender:
            raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Sender mismatch.")

    def _snapshot(self) -> DispatchSnapshot:
        return DispatchSnapshot(
            DISPATCH_ID,
            self.state,
            1,
            self.send_attempts,
            self.apns_outcome,
            self.captured_revision,
        )


class FakeAPNsService:
    def __init__(self, outcome: str = "accepted") -> None:
        self.outcome = outcome
        self.invocations = 0
        self.dispatch_ids: list[str | None] = []
        self.call_bootstraps: list[object] = []

    def send(self, *_: object, **values: object) -> object:
        self.invocations += 1
        dispatch_id = values.get("dispatch_id")
        self.dispatch_ids.append(dispatch_id if isinstance(dispatch_id, str) else None)
        self.call_bootstraps.append(values.get("call_bootstrap"))
        if self.outcome == "exception":
            raise RuntimeError("redacted transport failure")
        accepted = self.outcome == "accepted"
        return SimpleNamespace(
            apns_voip_push_send_requested=True,
            apns_voip_push_send_result="production_success" if accepted else "production_rejected",
            apns_failure_reason="none" if accepted else "rejected_redacted",
            persisted_pushkit_token_lookup_result="found",
            pushkit_token_redacted=True,
            apns_environment="production",
            apns_topic_resolved=True,
            media_credentials_requested=False,
            media_connect_requested=False,
            matrix_event_emit_requested=False,
            apns_provider_requested=True,
            apns_provider_accepted=accepted,
            blocked_reason="none" if accepted else "apns_rejected_redacted",
        )


class ProductionDispatchRouteTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.auth = FakeAuthValidator()
        self.room = FakeRoomValidator()
        self.service = SimpleNamespace(auth_validator=self.auth, room_validator=self.room)
        self.tokens = InMemoryPushKitTokenStore()
        self.store = FakeDispatchStore()
        self.apns = FakeAPNsService()
        self._register("@sender:example.org", "SENDER", "gen-sender")
        self._register("@receiver:example.org", "RECEIVER", "gen-receiver")

    def _register(self, user_id: str, device_id: str, generation: str) -> None:
        request = PushKitTokenRegistrationRequest.from_mapping({
            "version": 1,
            "token": "a" * 64,
            "environment": "production",
            "protocol_version": 1,
            "intents": ["audio"],
            "receiver_handoff": "matrixrtc_element_call",
            "app_session_generation": generation,
        })
        self.tokens.store(user_id, device_id, request)

    def _app(self, enabled: bool = True) -> object:
        return app_module.create_app(
            token_service=self.service,
            pushkit_token_store=self.tokens,
            apns_voip_send_service=self.apns,
            production_dispatch_store=self.store,
            direct_call_capability_v1_enabled=enabled,
            direct_call_dispatch_v1_admission_enabled=enabled,
            direct_call_dispatch_v1_completion_enabled=enabled,
        )

    def _prepare_payload(self) -> dict[str, object]:
        now_ms = int(time.time() * 1000)
        return {
            "dispatch_protocol_version": 1,
            "type": "foreground.call.invite",
            "version": 1,
            "recipient": "@receiver:example.org",
            "call_handle": "opaque-call-handle",
            "call_kind": "audio",
            "created_at_ms": now_ms,
            "expires_at_ms": now_ms + 60_000,
            "display_label": "Audio call",
            "app_session_generation": "gen-sender",
            "pending_metadata": {
                "version": 1,
                "call_id": "opaque-call-id",
                "room_id": "!opaque-room:example.org",
                "intent": "audio",
            },
        }

    async def _post(self, app: object, path: str, token: str, payload: dict[str, object]) -> httpx.Response:
        transport = httpx.ASGITransport(app=app)  # type: ignore[arg-type]
        async with httpx.AsyncClient(transport=transport, base_url="https://test.invalid") as client:
            return await client.post(path, headers={"Authorization": f"Bearer {token}"}, json=payload)

    async def _prepare_and_claim(self, app: object) -> None:
        response = await self._post(app, app_module.FOREGROUND_SIGNALING_INVITE_PREPARE_PATH, "auth-a", self._prepare_payload())
        self.assertEqual(response.status_code, 200)
        response = await self._post(app, app_module.FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_CLAIM_PATH, "auth-a", {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "sender_reference": "sender-reference",
            "app_session_generation": "gen-sender",
        })
        self.assertEqual(response.status_code, 200)

    async def test_flags_disabled_fail_closed_and_do_not_touch_store(self) -> None:
        response = await self._post(
            self._app(False), app_module.FOREGROUND_SIGNALING_INVITE_PREPARE_PATH, "auth-a", self._prepare_payload(),
        )
        self.assertEqual(response.status_code, 404)
        self.assertIsNone(self.store.sender)

    async def test_capability_registration_derives_authenticated_identity(self) -> None:
        response = await self._post(self._app(), app_module.PUSHKIT_TOKEN_REGISTRATION_PATH, "auth-a", {
            "version": 1,
            "token": "b" * 64,
            "environment": "production",
            "protocol_version": 1,
            "intents": ["audio"],
            "receiver_handoff": "matrixrtc_element_call",
            "app_session_generation": "new-generation",
            "user_id": "untrusted",
            "device_id": "untrusted",
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.store.capability_count, 1)
        self.assertEqual(self.store.capability_identity.user_id, "@sender:example.org")  # type: ignore[union-attr]
        self.assertNotEqual(self.store.capability_identity.device_id, "untrusted")  # type: ignore[union-attr]

    async def test_prepare_validates_room_and_binds_generations(self) -> None:
        response = await self._post(self._app(), app_module.FOREGROUND_SIGNALING_INVITE_PREPARE_PATH, "auth-a", self._prepare_payload())
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.room.requests, 1)
        self.assertEqual(self.store.sender.session_generation, "gen-sender")  # type: ignore[union-attr]
        self.assertEqual(self.store.receiver.session_generation, "gen-receiver")  # type: ignore[union-attr]

    async def test_ineligible_room_fails_before_durable_prepare(self) -> None:
        self.room.encrypted = False
        response = await self._post(self._app(), app_module.FOREGROUND_SIGNALING_INVITE_PREPARE_PATH, "auth-a", self._prepare_payload())
        self.assertEqual(response.status_code, 403)
        self.assertIsNone(self.store.sender)

    async def test_capability_expiry_is_bounded(self) -> None:
        response = await self._post(self._app(), app_module.PUSHKIT_TOKEN_REGISTRATION_PATH, "auth-a", {
            "version": 1,
            "token": "b" * 64,
            "environment": "production",
            "protocol_version": 1,
            "intents": ["audio"],
            "receiver_handoff": "matrixrtc_element_call",
            "app_session_generation": "new-generation",
            "capability_expires_in_seconds": 86401,
        })
        self.assertEqual(response.status_code, 400)
        self.assertEqual(self.store.capability_count, 0)

    async def test_wrong_generation_rejected_before_claim(self) -> None:
        app = self._app()
        response = await self._post(app, app_module.FOREGROUND_SIGNALING_INVITE_PREPARE_PATH, "auth-a", self._prepare_payload())
        self.assertEqual(response.status_code, 200)
        response = await self._post(app, app_module.FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_CLAIM_PATH, "auth-a", {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "sender_reference": "sender-reference",
            "app_session_generation": "stale",
        })
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.store.claim_count, 0)

    async def test_other_authenticated_device_cannot_claim(self) -> None:
        app = self._app()
        response = await self._post(app, app_module.FOREGROUND_SIGNALING_INVITE_PREPARE_PATH, "auth-a", self._prepare_payload())
        self.assertEqual(response.status_code, 200)
        response = await self._post(app, app_module.FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_CLAIM_PATH, "auth-other", {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "sender_reference": "sender-reference",
            "app_session_generation": "gen-sender",
        })
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.store.claim_count, 0)

    async def test_duplicate_claim_is_idempotent(self) -> None:
        app = self._app()
        await self._prepare_and_claim(app)
        await self._prepare_and_claim_claim_only(app)
        self.assertEqual(self.store.claim_count, 2)
        self.assertEqual(self.store.state, DispatchState.CLAIMED)

    async def _prepare_and_claim_claim_only(self, app: object) -> None:
        response = await self._post(app, app_module.FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_CLAIM_PATH, "auth-a", {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "sender_reference": "sender-reference",
            "app_session_generation": "gen-sender",
        })
        self.assertEqual(response.status_code, 200)

    async def test_duplicate_send_invokes_apns_once(self) -> None:
        app = self._app()
        await self._prepare_and_claim(app)
        payload = self._send_payload()
        first, second = await asyncio.gather(
            self._post(app, app_module.FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH, "auth-a", payload),
            self._post(app, app_module.FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH, "auth-a", payload),
        )
        self.assertEqual(sorted((first.status_code, second.status_code)), [200, 200])
        self.assertEqual(self.apns.invocations, 1)
        self.assertEqual(self.apns.dispatch_ids, [str(DISPATCH_ID)])
        self.assertEqual(self.apns.call_bootstraps, [None])
        self.assertEqual(self.store.send_attempts, 1)

    def test_production_apns_payload_adds_only_opaque_dispatch_routing(self) -> None:
        payload = _voip_payload(
            "real_invite_controlled",
            pending_metadata_reference="receiver-reference",
            dispatch_id=str(DISPATCH_ID),
        )
        self.assertEqual(payload, {
            "aps": {"content-available": 1},
            "salemx_direct_call": {
                "version": 1,
                "kind": "real_invite_controlled",
                "redacted": True,
                "receiver_reference": "receiver-reference",
                "dispatch_id": str(DISPATCH_ID),
            },
        })
        self.assertLess(len(json.dumps(payload, separators=(",", ":")).encode("utf-8")), 512)

    def test_legacy_apns_payload_is_unchanged_without_dispatch_id(self) -> None:
        payload = _voip_payload("real_invite_controlled", pending_metadata_reference="receiver-reference")
        self.assertEqual(payload, {
            "aps": {"content-available": 1},
            "salemx_direct_call": {
                "version": 1,
                "kind": "real_invite_controlled",
                "redacted": True,
                "pending_metadata_reference": "receiver-reference",
                "pending_metadata_reference_redacted": True,
            },
        })

    async def test_token_rotation_after_prepare_fails_closed_without_apns(self) -> None:
        app = self._app()
        await self._prepare_and_claim(app)
        self._register_with_token("@receiver:example.org", "RECEIVER", "gen-receiver", "c" * 64)
        response = await self._post(
            app, app_module.FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH, "auth-a", self._send_payload(),
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.apns.invocations, 0)

    def _register_with_token(self, user_id: str, device_id: str, generation: str, token: str) -> None:
        request = PushKitTokenRegistrationRequest.from_mapping({
            "version": 1,
            "token": token,
            "environment": "production",
            "protocol_version": 1,
            "intents": ["audio"],
            "receiver_handoff": "matrixrtc_element_call",
            "app_session_generation": generation,
        })
        self.tokens.store(user_id, device_id, request)

    async def test_rejected_and_ambiguous_apns_outcomes_fail_closed(self) -> None:
        for outcome, expected_state in (("rejected", DispatchState.SEND_FAILED), ("exception", DispatchState.DELIVERY_UNKNOWN)):
            with self.subTest(outcome=outcome):
                self.store = FakeDispatchStore()
                self.apns = FakeAPNsService(outcome)
                app = self._app()
                await self._prepare_and_claim(app)
                response = await self._post(
                    app, app_module.FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH, "auth-a", self._send_payload(),
                )
                self.assertEqual(response.status_code, 502)
                self.assertEqual(self.store.state, expected_state)

    async def test_cancel_and_receiver_consume_are_exact_and_non_replayable(self) -> None:
        app = self._app()
        await self._prepare_and_claim(app)
        cancel = await self._post(app, app_module.FOREGROUND_SIGNALING_INVITE_CANCEL_PREPARED_PATH, "auth-a", {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "sender_reference": "sender-reference",
            "app_session_generation": "gen-sender",
        })
        self.assertEqual(cancel.status_code, 200)
        consume = await self._post(app, app_module.FOREGROUND_SIGNALING_PENDING_METADATA_RECEIVER_CONSUME_PATH, "auth-b", {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "receiver_reference": "receiver-reference",
            "app_session_generation": "gen-receiver",
        })
        self.assertEqual(consume.status_code, 409)

    async def test_duplicate_cancel_is_idempotent(self) -> None:
        app = self._app()
        await self._prepare_and_claim(app)
        payload = {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "sender_reference": "sender-reference",
            "app_session_generation": "gen-sender",
        }
        first = await self._post(app, app_module.FOREGROUND_SIGNALING_INVITE_CANCEL_PREPARED_PATH, "auth-a", payload)
        second = await self._post(app, app_module.FOREGROUND_SIGNALING_INVITE_CANCEL_PREPARED_PATH, "auth-a", payload)
        self.assertEqual((first.status_code, second.status_code), (200, 200))

    async def test_expired_dispatch_cannot_be_consumed(self) -> None:
        app = self._app()
        await self._prepare_and_claim(app)
        self.store.state = DispatchState.EXPIRED
        response = await self._post(app, app_module.FOREGROUND_SIGNALING_PENDING_METADATA_RECEIVER_CONSUME_PATH, "auth-b", {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "receiver_reference": "receiver-reference",
            "app_session_generation": "gen-receiver",
        })
        self.assertEqual(response.status_code, 409)
        self.assertEqual(self.store.consume_count, 0)

    async def test_registration_logs_are_redacted(self) -> None:
        with self.assertLogs("salemx_call_service.app", level="INFO") as captured:
            response = await self._post(self._app(), app_module.PUSHKIT_TOKEN_REGISTRATION_PATH, "auth-a", {
                "version": 1,
                "token": "d" * 64,
                "environment": "production",
                "protocol_version": 1,
                "intents": ["audio"],
                "receiver_handoff": "matrixrtc_element_call",
                "app_session_generation": "private-generation",
            })
        self.assertEqual(response.status_code, 200)
        output = "\n".join(captured.output)
        self.assertNotIn("@sender:example.org", output)
        self.assertNotIn("SENDER", output)
        self.assertNotIn("d" * 64, output)
        self.assertNotIn("private-generation", output)

    async def test_successful_receiver_consume_is_exact(self) -> None:
        app = self._app()
        await self._prepare_and_claim(app)
        sent = await self._post(app, app_module.FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH, "auth-a", self._send_payload())
        self.assertEqual(sent.status_code, 200)
        consume = await self._post(app, app_module.FOREGROUND_SIGNALING_PENDING_METADATA_RECEIVER_CONSUME_PATH, "auth-b", {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "receiver_reference": "receiver-reference",
            "app_session_generation": "gen-receiver",
        })
        self.assertEqual(consume.status_code, 200)
        self.assertEqual(self.store.consume_count, 1)
        replay = await self._post(app, app_module.FOREGROUND_SIGNALING_PENDING_METADATA_RECEIVER_CONSUME_PATH, "auth-b", {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "receiver_reference": "receiver-reference",
            "app_session_generation": "gen-receiver",
        })
        self.assertEqual(replay.status_code, 409)
        self.assertEqual(self.store.consume_count, 1)

    async def test_receiver_consume_rejects_wrong_generation_and_device_before_store(self) -> None:
        for token, generation in (("auth-b", "stale"), ("auth-receiver-other", "gen-receiver-other")):
            with self.subTest(token=token):
                self.store = FakeDispatchStore()
                app = self._app()
                await self._prepare_and_claim(app)
                sent = await self._post(
                    app, app_module.FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH, "auth-a", self._send_payload(),
                )
                self.assertEqual(sent.status_code, 200)
                if token == "auth-receiver-other":
                    self._register("@receiver:example.org", "OTHER", generation)
                consume = await self._post(
                    app,
                    app_module.FOREGROUND_SIGNALING_PENDING_METADATA_RECEIVER_CONSUME_PATH,
                    token,
                    {
                        "dispatch_protocol_version": 1,
                        "dispatch_id": str(DISPATCH_ID),
                        "receiver_reference": "receiver-reference",
                        "app_session_generation": generation,
                    },
                )
                self.assertEqual(consume.status_code, 403)
                self.assertEqual(self.store.consume_count, 0)

    def _send_payload(self) -> dict[str, object]:
        return {
            "dispatch_protocol_version": 1,
            "dispatch_id": str(DISPATCH_ID),
            "sender_reference": "sender-reference",
            "receiver_reference": "receiver-reference",
            "app_session_generation": "gen-sender",
        }


if __name__ == "__main__":
    unittest.main()
