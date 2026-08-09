"""Stage 7 acceptance coverage against an isolated real PostgreSQL database."""

from __future__ import annotations

import asyncio
import hashlib
import os
import subprocess
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID, uuid4

import httpx
import psycopg
from psycopg.errors import CheckViolation, UniqueViolation

os.environ.setdefault("SALEMX_CALL_SERVICE_MODE", "local_fake")

from salemx_call_service import app as app_module
from salemx_call_service.auth import AuthenticatedUser
from salemx_call_service.config import direct_call_store_settings_from_env
from salemx_call_service.errors import CallServiceError
from salemx_call_service.production_dispatch_store import (
    APNsOutcome,
    DispatchExpiredError,
    DispatchIdentity,
    DispatchNotFoundError,
    DispatchOwnershipError,
    DispatchState,
    DispatchTransitionError,
    PostgresProductionDispatchStore,
)
from salemx_call_service.pushkit_tokens import InMemoryPushKitTokenStore, PushKitTokenRegistrationRequest
from salemx_call_service.room_validation import RoomEligibility


POSTGRES_DSN_ENV = "SALEM_STAGE7_POSTGRES_DSN"
POSTGRES_CONTAINER_ENV = "SALEM_STAGE7_POSTGRES_CONTAINER"
POSTGRES_USER_ENV = "SALEM_STAGE7_POSTGRES_USER"
POSTGRES_DATABASE_ENV = "SALEM_STAGE7_POSTGRES_DATABASE"
CONCURRENCY = 32
MASTER_KEY = hashlib.sha256(b"salemx-stage7-isolated-postgres-key").digest()
MIGRATION = Path(__file__).parents[1] / "migrations" / "0001_production_dispatch_v1.sql"


def _dsn() -> str:
    value = os.environ.get(POSTGRES_DSN_ENV)
    if not value:
        raise unittest.SkipTest(f"{POSTGRES_DSN_ENV} is required for the isolated Stage 7 suite.")
    return value


def _store() -> PostgresProductionDispatchStore:
    return PostgresProductionDispatchStore(_dsn(), MASTER_KEY)


def _apply_migration() -> None:
    with psycopg.connect(_dsn(), autocommit=True) as connection:
        connection.execute(MIGRATION.read_text())


def _schema_signature() -> tuple[tuple[object, ...], ...]:
    query = """
        SELECT 'constraint', conname, pg_get_constraintdef(oid)
          FROM pg_constraint
         WHERE conrelid IN (
             'salemx_direct_call_capabilities'::regclass,
             'salemx_direct_call_dispatches'::regclass
         )
        UNION ALL
        SELECT 'index', indexname, indexdef
          FROM pg_indexes
         WHERE schemaname = 'public'
           AND tablename IN ('salemx_direct_call_capabilities', 'salemx_direct_call_dispatches')
        ORDER BY 1, 2, 3
    """
    with psycopg.connect(_dsn()) as connection:
        return tuple(tuple(row) for row in connection.execute(query).fetchall())


def _identity(role: str, generation: str = "generation-1") -> DispatchIdentity:
    suffix = uuid4().hex
    return DispatchIdentity(
        f"@stage7-{role}-{suffix}:example.invalid",
        f"STAGE7-{role.upper()}-{suffix}",
        f"{generation}-{suffix}",
    )


def _metadata() -> dict[str, object]:
    suffix = uuid4().hex
    return {
        "room_id": f"!stage7-room-{suffix}:example.invalid",
        "call_id": f"stage7-call-{suffix}",
        "intent": "audio",
        "peer_user_id": f"@stage7-peer-{suffix}:example.invalid",
        "direction": "incoming",
    }


def _row_state(dispatch_id: UUID) -> tuple[str, int, int]:
    with psycopg.connect(_dsn()) as connection:
        row = connection.execute(
            "SELECT state, row_version, send_attempt_count FROM salemx_direct_call_dispatches WHERE dispatch_id = %s",
            (dispatch_id,),
        ).fetchone()
    if row is None:
        raise AssertionError("Expected durable dispatch row.")
    return str(row[0]), int(row[1]), int(row[2])


class _FakeAuthValidator:
    def __init__(self, users: dict[str, AuthenticatedUser]) -> None:
        self.users = users
        self.seen_tokens: list[str] = []

    async def validate_bearer_token(self, bearer_token: str) -> AuthenticatedUser:
        self.seen_tokens.append(bearer_token)
        user = self.users.get(bearer_token)
        if user is None:
            raise CallServiceError(status_code=401, errcode="M_UNKNOWN_TOKEN", error="Unknown token.")
        return user


class _FakeRoomValidator:
    def __init__(self, members: tuple[str, str]) -> None:
        self.members = members

    async def validate_direct_call_room(
        self,
        authenticated_user: AuthenticatedUser,
        token_request: object,
    ) -> RoomEligibility:
        if authenticated_user.user_id not in self.members or getattr(token_request, "peer_user_id") not in self.members:
            raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Room is ineligible.")
        return RoomEligibility(self.members, True)


@dataclass
class _FakeAPNsService:
    outcome: str = "accepted"
    invocations: int = 0

    def send(self, *_: object, **__: object) -> object:
        self.invocations += 1
        if self.outcome == "exception":
            raise RuntimeError("redacted ambiguous transport fixture")
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


class _RouteHarness:
    def __init__(self, outcome: str = "accepted", enabled: bool = True) -> None:
        suffix = uuid4().hex
        self.sender = AuthenticatedUser(f"@stage7-sender-{suffix}:example.invalid", f"SENDER-{suffix}")
        self.receiver = AuthenticatedUser(f"@stage7-receiver-{suffix}:example.invalid", f"RECEIVER-{suffix}")
        self.sender_token = f"stage7-sender-auth-{suffix}"
        self.receiver_token = f"stage7-receiver-auth-{suffix}"
        self.sender_generation = f"stage7-sender-generation-{suffix}"
        self.receiver_generation = f"stage7-receiver-generation-{suffix}"
        self.auth = _FakeAuthValidator({
            self.sender_token: self.sender,
            self.receiver_token: self.receiver,
        })
        self.tokens = InMemoryPushKitTokenStore()
        self.apns = _FakeAPNsService(outcome)
        self._register(self.sender, self.sender_generation, "a")
        self._register(self.receiver, self.receiver_generation, "b")
        service = SimpleNamespace(
            auth_validator=self.auth,
            room_validator=_FakeRoomValidator((self.sender.user_id, self.receiver.user_id)),
        )
        self.app = app_module.create_app(
            token_service=service,
            pushkit_token_store=self.tokens,
            apns_voip_send_service=self.apns,
            production_dispatch_store=_store(),
            direct_call_capability_v1_enabled=enabled,
            direct_call_dispatch_v1_admission_enabled=enabled,
            direct_call_dispatch_v1_completion_enabled=enabled,
        )

    def _register(self, user: AuthenticatedUser, generation: str, token_character: str) -> None:
        request = PushKitTokenRegistrationRequest.from_mapping({
            "version": 1,
            "token": token_character * 64,
            "environment": "production",
            "protocol_version": 1,
            "intents": ["audio"],
            "receiver_handoff": "matrixrtc_element_call",
            "app_session_generation": generation,
        })
        self.tokens.store(user.user_id, user.device_id, request)

    def prepare_payload(self, expires_in_ms: int = 60_000) -> dict[str, object]:
        now_ms = int(time.time() * 1000)
        return {
            "dispatch_protocol_version": 1,
            "type": "foreground.call.invite",
            "version": 1,
            "recipient": self.receiver.user_id,
            "call_handle": f"stage7-handle-{uuid4().hex}",
            "call_kind": "audio",
            "created_at_ms": now_ms,
            "expires_at_ms": now_ms + expires_in_ms,
            "display_label": "Audio call",
            "delivery_mode": "foreground_and_apns",
            "app_session_generation": self.sender_generation,
            "pending_metadata": {
                "version": 1,
                "call_id": f"stage7-call-{uuid4().hex}",
                "room_id": f"!stage7-room-{uuid4().hex}:example.invalid",
                "intent": "audio",
            },
        }

    async def post(self, path: str, token: str, payload: dict[str, object]) -> httpx.Response:
        transport = httpx.ASGITransport(app=self.app)  # type: ignore[arg-type]
        async with httpx.AsyncClient(transport=transport, base_url="http://127.0.0.1") as client:
            return await client.post(path, headers={"Authorization": f"Bearer {token}"}, json=payload)

    async def prepare_and_claim(self) -> dict[str, object]:
        prepared = await self.post(
            app_module.FOREGROUND_SIGNALING_INVITE_PREPARE_PATH,
            self.sender_token,
            self.prepare_payload(),
        )
        if prepared.status_code != 200:
            raise AssertionError(f"Prepare failed with status {prepared.status_code}.")
        body = prepared.json()
        claimed = await self.post(
            app_module.FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_CLAIM_PATH,
            self.sender_token,
            {
                "dispatch_protocol_version": 1,
                "dispatch_id": body["dispatch_id"],
                "sender_reference": body["sender_reference"],
                "app_session_generation": self.sender_generation,
            },
        )
        if claimed.status_code != 200:
            raise AssertionError(f"Claim failed with status {claimed.status_code}.")
        return body

    def send_payload(self, prepared: dict[str, object]) -> dict[str, object]:
        return {
            "dispatch_protocol_version": 1,
            "dispatch_id": prepared["dispatch_id"],
            "sender_reference": prepared["sender_reference"],
            "receiver_reference": prepared["receiver_reference"],
            "app_session_generation": self.sender_generation,
        }


class Stage7PostgresIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_stage7_real_postgres_contract(self) -> None:
        with psycopg.connect(_dsn()) as connection:
            tables_before = connection.execute(
                "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name"
            ).fetchall()
        self.assertEqual(tables_before, [])

        _apply_migration()
        first_signature = _schema_signature()
        _apply_migration()
        self.assertEqual(_schema_signature(), first_signature)
        signature_text = repr(first_signature)
        for expected in (
            "salemx_direct_call_capabilities_active_binding_key",
            "salemx_direct_call_dispatches_sender_reference_digest_key",
            "salemx_direct_call_dispatches_receiver_reference_digest_key",
            "salemx_direct_call_dispatches_active_expiry_idx",
        ):
            self.assertIn(expected, signature_text)

        self.assertFalse(direct_call_store_settings_from_env({}).enabled)
        await self._verify_disabled_routes()
        self._verify_capability_rotation()
        terminal_ids, plaintext = self._verify_full_lifecycle_and_replay()
        self._verify_constraints_and_transaction_rollback(terminal_ids[0])
        self._verify_connection_recreation_and_restart_persistence()
        self._verify_concurrent_claims()
        self._verify_concurrent_send_admission()
        self._verify_cancel_and_expiry_races()
        await self._verify_concurrent_route_sends()
        failure_ids = await self._verify_failure_semantics()
        terminal_ids.extend(failure_ids)
        self._verify_plaintext_absent(plaintext)
        self._verify_terminal_records_do_not_reappear(terminal_ids)

        print("stage7_concurrent_claims=32 claim_winner_count=1")
        print("stage7_concurrent_sends=32 fake_apns_attempt_count=1")

    async def _verify_disabled_routes(self) -> None:
        harness = _RouteHarness(enabled=False)
        response = await harness.post(
            app_module.FOREGROUND_SIGNALING_INVITE_PREPARE_PATH,
            harness.sender_token,
            harness.prepare_payload(),
        )
        self.assertEqual(response.status_code, 404)

    def _verify_capability_rotation(self) -> None:
        store = _store()
        base_user = f"@stage7-capability-{uuid4().hex}:example.invalid"
        base_device = f"STAGE7-CAP-{uuid4().hex}"
        first_identity = DispatchIdentity(base_user, base_device, "generation-one")
        first = store.register_capability(first_identity, "production", 1, "audio", "matrixrtc_element_call", 1, 60)
        rotated = store.register_capability(first_identity, "production", 1, "audio", "matrixrtc_element_call", 2, 60)
        next_generation = store.register_capability(
            DispatchIdentity(base_user, base_device, "generation-two"),
            "production", 1, "audio", "matrixrtc_element_call", 3, 60,
        )
        self.assertEqual(first.capability_id, rotated.capability_id)
        self.assertEqual(rotated.token_binding_revision, 2)
        self.assertNotEqual(first.capability_id, next_generation.capability_id)

    def _verify_full_lifecycle_and_replay(self) -> tuple[list[UUID], tuple[str, ...]]:
        sender = _identity("sender")
        receiver = _identity("receiver")
        metadata = _metadata()
        store = _store()
        references = store.create_dispatch(sender, receiver, 7, metadata, 60)
        with self.assertRaises(DispatchNotFoundError):
            store.claim_exact(uuid4(), references.sender_reference, sender)
        with self.assertRaises(DispatchNotFoundError):
            store.claim("wrong-exact-reference", sender)
        for wrong_identity in (
            DispatchIdentity("@wrong:example.invalid", sender.device_id, sender.session_generation),
            DispatchIdentity(sender.user_id, "WRONG-DEVICE", sender.session_generation),
            DispatchIdentity(sender.user_id, sender.device_id, "wrong-generation"),
        ):
            with self.assertRaises(DispatchOwnershipError):
                store.claim(references.sender_reference, wrong_identity)

        claimed = store.claim_exact(references.dispatch_id, references.sender_reference, sender)
        self.assertEqual(claimed.state, DispatchState.CLAIMED)
        admission = store.admit_send_exact(
            references.dispatch_id,
            references.sender_reference,
            references.receiver_reference,
            sender,
            7,
        )
        self.assertFalse(admission.already_sent)
        self.assertEqual(admission.metadata, metadata)
        sent = store.complete_send_exact(references.dispatch_id, references.sender_reference, sender, APNsOutcome.ACCEPTED)
        self.assertEqual(sent.state, DispatchState.SENT)

        recreated_store = _store()
        consumed = recreated_store.consume_exact(references.dispatch_id, references.receiver_reference, receiver)
        self.assertEqual(consumed.metadata, metadata)
        self.assertEqual(consumed.snapshot.state, DispatchState.CONSUMED)
        with self.assertRaises(DispatchTransitionError):
            recreated_store.consume_exact(references.dispatch_id, references.receiver_reference, receiver)
        plaintext = (
            sender.user_id, sender.device_id, sender.session_generation,
            receiver.user_id, receiver.device_id, receiver.session_generation,
            str(metadata["room_id"]), str(metadata["call_id"]), str(metadata["peer_user_id"]),
        )
        return [references.dispatch_id], plaintext

    def _verify_constraints_and_transaction_rollback(self, dispatch_id: UUID) -> None:
        with psycopg.connect(_dsn()) as connection:
            with self.assertRaises(CheckViolation):
                with connection.transaction():
                    connection.execute(
                        "UPDATE salemx_direct_call_dispatches SET send_attempt_count = 2 WHERE dispatch_id = %s",
                        (dispatch_id,),
                    )
            row = connection.execute(
                "SELECT send_attempt_count FROM salemx_direct_call_dispatches WHERE dispatch_id = %s",
                (dispatch_id,),
            ).fetchone()
            self.assertEqual(row, (1,))

        first = _store().create_dispatch(_identity("unique-a"), _identity("unique-b"), 1, _metadata(), 60)
        second = _store().create_dispatch(_identity("unique-c"), _identity("unique-d"), 1, _metadata(), 60)
        with psycopg.connect(_dsn()) as connection:
            first_digest = connection.execute(
                "SELECT sender_reference_digest FROM salemx_direct_call_dispatches WHERE dispatch_id = %s",
                (first.dispatch_id,),
            ).fetchone()
            self.assertIsNotNone(first_digest)
            with self.assertRaises(UniqueViolation):
                with connection.transaction():
                    connection.execute(
                        "UPDATE salemx_direct_call_dispatches SET sender_reference_digest = %s WHERE dispatch_id = %s",
                        (first_digest[0], second.dispatch_id),  # type: ignore[index]
                    )
            self.assertNotEqual(
                connection.execute(
                    "SELECT sender_reference_digest FROM salemx_direct_call_dispatches WHERE dispatch_id = %s",
                    (second.dispatch_id,),
                ).fetchone(),
                first_digest,
            )

    def _verify_connection_recreation_and_restart_persistence(self) -> None:
        sender = _identity("restart-sender")
        receiver = _identity("restart-receiver")
        references = _store().create_dispatch(sender, receiver, 1, _metadata(), 60)
        _store().claim_exact(references.dispatch_id, references.sender_reference, sender)
        container = os.environ.get(POSTGRES_CONTAINER_ENV)
        user = os.environ.get(POSTGRES_USER_ENV)
        database = os.environ.get(POSTGRES_DATABASE_ENV)
        if not container or not user or not database:
            self.fail("Exact Stage 7 PostgreSQL resource environment is missing.")
        subprocess.run(["docker", "restart", container], check=True, stdout=subprocess.DEVNULL)
        for _ in range(30):
            ready = subprocess.run(
                ["docker", "exec", container, "pg_isready", "--username", user, "--dbname", database],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if ready.returncode == 0:
                break
            time.sleep(1)
        else:
            self.fail("PostgreSQL did not become ready after exact-container restart.")
        published = subprocess.check_output(
            ["docker", "port", container, "5432/tcp"],
            text=True,
        ).strip()
        if not published.startswith("127.0.0.1:"):
            self.fail("Restarted PostgreSQL port is not loopback-only.")
        host_port = int(published.rsplit(":", 1)[1])
        os.environ[POSTGRES_DSN_ENV] = f"postgresql://{user}@127.0.0.1:{host_port}/{database}"
        for _ in range(30):
            try:
                with psycopg.connect(_dsn(), connect_timeout=1) as connection:
                    connection.execute("SELECT 1")
                break
            except psycopg.OperationalError:
                time.sleep(1)
        else:
            self.fail("PostgreSQL loopback endpoint did not recover after exact-container restart.")
        cancelled = _store().cancel_exact(references.dispatch_id, references.sender_reference, sender)
        self.assertEqual(cancelled.state, DispatchState.CANCELLED)

    def _verify_concurrent_claims(self) -> None:
        sender = _identity("claim-sender")
        references = _store().create_dispatch(sender, _identity("claim-receiver"), 1, _metadata(), 60)
        barrier = threading.Barrier(CONCURRENCY)

        def claim(_: int) -> DispatchState:
            barrier.wait()
            return _store().claim_exact(references.dispatch_id, references.sender_reference, sender).state

        with ThreadPoolExecutor(max_workers=CONCURRENCY) as executor:
            states = list(executor.map(claim, range(CONCURRENCY)))
        self.assertEqual(states, [DispatchState.CLAIMED] * CONCURRENCY)
        self.assertEqual(_row_state(references.dispatch_id), (DispatchState.CLAIMED.value, 1, 0))

    def _verify_concurrent_send_admission(self) -> None:
        sender = _identity("send-sender")
        receiver = _identity("send-receiver")
        references = _store().create_dispatch(sender, receiver, 5, _metadata(), 60)
        _store().claim_exact(references.dispatch_id, references.sender_reference, sender)
        barrier = threading.Barrier(CONCURRENCY)

        def admit(_: int) -> bool:
            barrier.wait()
            try:
                _store().admit_send_exact(
                    references.dispatch_id,
                    references.sender_reference,
                    references.receiver_reference,
                    sender,
                    5,
                )
            except DispatchTransitionError:
                return False
            return True

        with ThreadPoolExecutor(max_workers=CONCURRENCY) as executor:
            winners = list(executor.map(admit, range(CONCURRENCY)))
        self.assertEqual(winners.count(True), 1)
        self.assertEqual(_row_state(references.dispatch_id), (DispatchState.SENDING.value, 2, 1))
        _store().complete_send_exact(references.dispatch_id, references.sender_reference, sender, APNsOutcome.ACCEPTED)

    def _verify_cancel_and_expiry_races(self) -> None:
        sender = _identity("cancel-claim-sender")
        references = _store().create_dispatch(sender, _identity("cancel-claim-receiver"), 1, _metadata(), 60)
        barrier = threading.Barrier(2)

        def claim() -> str:
            barrier.wait()
            try:
                return _store().claim_exact(references.dispatch_id, references.sender_reference, sender).state.value
            except DispatchTransitionError:
                return "rejected"

        def cancel() -> str:
            barrier.wait()
            try:
                return _store().cancel_exact(references.dispatch_id, references.sender_reference, sender).state.value
            except DispatchTransitionError:
                return "rejected"

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = [executor.submit(claim), executor.submit(cancel)]
            outcomes = [future.result() for future in results]
        self.assertIn(_row_state(references.dispatch_id)[0], {DispatchState.CLAIMED.value, DispatchState.CANCELLED.value})
        self.assertNotEqual(outcomes, ["rejected", "rejected"])

        send_sender = _identity("cancel-send-sender")
        send_references = _store().create_dispatch(send_sender, _identity("cancel-send-receiver"), 1, _metadata(), 60)
        _store().claim(send_references.sender_reference, send_sender)
        barrier = threading.Barrier(2)

        def admit_send() -> str:
            barrier.wait()
            try:
                return _store().admit_send(send_references.sender_reference, send_sender).state.value
            except DispatchTransitionError:
                return "rejected"

        def cancel_send() -> str:
            barrier.wait()
            try:
                return _store().cancel(send_references.sender_reference, send_sender).state.value
            except DispatchTransitionError:
                return "rejected"

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = [executor.submit(admit_send), executor.submit(cancel_send)]
            _ = [future.result() for future in results]
        self.assertIn(_row_state(send_references.dispatch_id)[0], {DispatchState.SENDING.value, DispatchState.CANCELLED.value})

        expiry_sender = _identity("expiry-sender")
        expired = _store().create_dispatch(expiry_sender, _identity("expiry-receiver"), 1, _metadata(), 1)
        _store().claim(expired.sender_reference, expiry_sender)
        time.sleep(1.1)
        with self.assertRaises(DispatchExpiredError):
            _store().admit_send(expired.sender_reference, expiry_sender)
        with self.assertRaises(DispatchExpiredError):
            _store().admit_send(expired.sender_reference, expiry_sender)
        self.assertGreaterEqual(_store().expire_due(), 1)
        self.assertEqual(_row_state(expired.dispatch_id)[0], DispatchState.EXPIRED.value)

    async def _verify_concurrent_route_sends(self) -> None:
        harness = _RouteHarness()
        prepared = await harness.prepare_and_claim()
        payload = harness.send_payload(prepared)
        responses = await asyncio.gather(*[
            harness.post(app_module.FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH, harness.sender_token, payload)
            for _ in range(CONCURRENCY)
        ])
        self.assertEqual([response.status_code for response in responses], [200] * CONCURRENCY)
        self.assertEqual(harness.apns.invocations, 1)
        self.assertTrue(all(response.json().get("APNs_send_count") == 1 for response in responses))

    async def _verify_failure_semantics(self) -> list[UUID]:
        terminal_ids: list[UUID] = []
        for outcome, expected_state, expected_errcode in (
            ("rejected", DispatchState.SEND_FAILED, "M_DIRECT_CALL_APNS_DELIVERY_FAILED"),
            ("exception", DispatchState.DELIVERY_UNKNOWN, "M_DIRECT_CALL_APNS_DELIVERY_UNKNOWN"),
        ):
            harness = _RouteHarness(outcome=outcome)
            prepared = await harness.prepare_and_claim()
            payload = harness.send_payload(prepared)
            first = await harness.post(
                app_module.FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH,
                harness.sender_token,
                payload,
            )
            retry = await harness.post(
                app_module.FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH,
                harness.sender_token,
                payload,
            )
            self.assertEqual(first.status_code, 502)
            self.assertEqual(first.json().get("errcode"), expected_errcode)
            self.assertEqual(retry.status_code, 409)
            self.assertEqual(harness.apns.invocations, 1)
            dispatch_id = UUID(str(prepared["dispatch_id"]))
            self.assertEqual(_row_state(dispatch_id)[0], expected_state.value)
            terminal_ids.append(dispatch_id)
        return terminal_ids

    def _verify_plaintext_absent(self, plaintext: tuple[str, ...]) -> None:
        with psycopg.connect(_dsn()) as connection:
            capability_rows = connection.execute(
                "SELECT row_to_json(value)::text FROM salemx_direct_call_capabilities AS value"
            ).fetchall()
            dispatch_rows = connection.execute(
                "SELECT row_to_json(value)::text FROM salemx_direct_call_dispatches AS value"
            ).fetchall()
        stored = "\n".join(str(row[0]) for row in capability_rows + dispatch_rows)
        for value in plaintext:
            self.assertNotIn(value, stored)

    def _verify_terminal_records_do_not_reappear(self, terminal_ids: list[UUID]) -> None:
        with psycopg.connect(_dsn()) as connection:
            states = dict(connection.execute(
                "SELECT dispatch_id, state FROM salemx_direct_call_dispatches WHERE dispatch_id = ANY(%s)",
                (terminal_ids,),
            ).fetchall())
        self.assertEqual(states[terminal_ids[0]], DispatchState.CONSUMED.value)
        self.assertIn(DispatchState.SEND_FAILED.value, states.values())
        self.assertIn(DispatchState.DELIVERY_UNKNOWN.value, states.values())
        self.assertNotIn(DispatchState.PREPARED.value, states.values())
        self.assertNotIn(DispatchState.CLAIMED.value, states.values())


if __name__ == "__main__":
    unittest.main()
