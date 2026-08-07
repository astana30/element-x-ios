"""Focused tests for the durable direct-call dispatch store."""

from __future__ import annotations

import base64
import copy
import logging
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import AbstractContextManager
from pathlib import Path
from typing import Mapping, Sequence
from uuid import UUID

from salemx_call_service.config import (
    DIRECT_CALL_DATABASE_DSN_ENV,
    DIRECT_CALL_PENDING_STORE_ENABLED_ENV,
    DIRECT_CALL_STORE_MASTER_KEY_B64_ENV,
    DirectCallStoreConfigurationError,
    direct_call_store_settings_from_env,
)
from salemx_call_service.production_dispatch_store import (
    APNsOutcome,
    DispatchExpiredError,
    DispatchIdentity,
    DispatchNotFoundError,
    DispatchOwnershipError,
    DispatchState,
    DispatchTransitionError,
    MetadataAuthenticationError,
    PostgresProductionDispatchStore,
)


class FakeDatabase:
    def __init__(self) -> None:
        self.rows: dict[UUID, dict[str, object]] = {}
        self.capabilities: dict[tuple[bytes, ...], dict[str, object]] = {}
        self.now = 1_000
        self.lock = threading.Lock()

    def connect(self, dsn: str) -> "FakeConnection":
        if not dsn.startswith("postgres"):
            raise AssertionError("Unexpected DSN classification.")
        return FakeConnection(self)


class FakeConnection(AbstractContextManager["FakeConnection"]):
    def __init__(self, database: FakeDatabase) -> None:
        self.database = database

    def __enter__(self) -> "FakeConnection":
        return self

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None:
        return None

    def transaction(self) -> "FakeConnection":
        return self

    def cursor(self) -> "FakeCursor":
        return FakeCursor(self.database)


class FakeCursor(AbstractContextManager["FakeCursor"]):
    def __init__(self, database: FakeDatabase) -> None:
        self.database = database
        self.results: list[dict[str, object]] = []

    def __enter__(self) -> "FakeCursor":
        return self

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None:
        return None

    def execute(self, query: str, params: Sequence[object] = ()) -> object:
        operation = query.split("production_dispatch:", 1)[1].split(" ", 1)[0]
        with self.database.lock:
            self.results = self._execute(operation, params)
        return self

    def fetchone(self) -> Mapping[str, object] | None:
        return copy.deepcopy(self.results[0]) if self.results else None

    def fetchall(self) -> Sequence[Mapping[str, object]]:
        return copy.deepcopy(self.results)

    def _execute(self, operation: str, params: Sequence[object]) -> list[dict[str, object]]:
        handlers = {
            "upsert_capability": self._upsert_capability,
            "create": self._create,
            "claim": self._claim,
            "admit_send": self._admit_send,
            "complete_send": self._complete_send,
            "cancel": self._cancel,
            "consume": self._consume,
            "load_sender": self._load_sender,
            "load_receiver": self._load_receiver,
            "expire_one": self._expire_one,
            "unknown_one": self._unknown_one,
            "expire_due": self._expire_due,
            "unknown_due": self._unknown_due,
        }
        result = handlers[operation](params)
        return [result] if isinstance(result, dict) else result

    def _upsert_capability(self, params: Sequence[object]) -> dict[str, object]:
        key = tuple(params[1:7])
        row = self.database.capabilities.get(key, {
            "capability_id": params[0],
            "protocol_version": params[5],
            "supported_intent": params[6],
        })
        row.update({
            "handoff_classification": params[7],
            "token_binding_revision": params[8],
            "expires_at": self.database.now + int(params[9]),
        })
        self.database.capabilities[key] = row
        return row

    def _create(self, params: Sequence[object]) -> dict[str, object]:
        row = {
            "dispatch_id": params[0],
            "sender_reference_digest": params[1],
            "receiver_reference_digest": params[2],
            "metadata_nonce": params[3],
            "encrypted_metadata": params[4],
            "sender_user_digest": params[5],
            "sender_device_digest": params[6],
            "sender_generation_digest": params[7],
            "receiver_user_digest": params[8],
            "receiver_device_digest": params[9],
            "receiver_generation_digest": params[10],
            "receiver_token_binding_revision": params[11],
            "state": "prepared",
            "row_version": 0,
            "send_attempt_count": 0,
            "apns_outcome_bucket": None,
            "expires_at": self.database.now + int(params[12]),
            "is_expired": False,
        }
        self.database.rows[UUID(str(params[0]))] = row
        return row

    def _claim(self, params: Sequence[object]) -> dict[str, object] | list[dict[str, object]]:
        row = self._by_digest("sender_reference_digest", params[0])
        if row and self._owner_matches(row, "sender", params[1:4]) and row["state"] == "prepared" and not self._expired(row):
            self._transition(row, "claimed")
            return row
        return []

    def _admit_send(self, params: Sequence[object]) -> dict[str, object] | list[dict[str, object]]:
        row = self._by_digest("sender_reference_digest", params[0])
        if row and self._owner_matches(row, "sender", params[1:4]) and row["state"] == "claimed" and row["send_attempt_count"] == 0 and not self._expired(row):
            row["send_attempt_count"] = 1
            self._transition(row, "sending")
            return row
        return []

    def _complete_send(self, params: Sequence[object]) -> dict[str, object] | list[dict[str, object]]:
        row = self._by_digest("sender_reference_digest", params[2])
        if row and self._owner_matches(row, "sender", params[3:6]) and row["state"] == "sending" and row["send_attempt_count"] == 1:
            row["apns_outcome_bucket"] = params[1]
            self._transition(row, str(params[0]))
            return row
        return []

    def _cancel(self, params: Sequence[object]) -> dict[str, object] | list[dict[str, object]]:
        row = self._by_digest("sender_reference_digest", params[0])
        if row and self._owner_matches(row, "sender", params[1:4]) and row["state"] in {"prepared", "claimed"} and not self._expired(row):
            self._transition(row, "cancelled")
            return row
        return []

    def _consume(self, params: Sequence[object]) -> dict[str, object] | list[dict[str, object]]:
        row = self._by_digest("receiver_reference_digest", params[0])
        if row and self._owner_matches(row, "receiver", params[1:4]) and row["state"] == "sent" and not self._expired(row):
            self._transition(row, "consumed")
            return row
        return []

    def _load_sender(self, params: Sequence[object]) -> dict[str, object] | list[dict[str, object]]:
        return self._load("sender_reference_digest", params[0])

    def _load_receiver(self, params: Sequence[object]) -> dict[str, object] | list[dict[str, object]]:
        return self._load("receiver_reference_digest", params[0])

    def _load(self, key: str, value: object) -> dict[str, object] | list[dict[str, object]]:
        row = self._by_digest(key, value)
        if row is None:
            return []
        row["is_expired"] = self._expired(row)
        return row

    def _expire_one(self, params: Sequence[object]) -> dict[str, object] | list[dict[str, object]]:
        row = self.database.rows.get(UUID(str(params[0])))
        if row and row["state"] in {"prepared", "claimed", "sent"}:
            self._transition(row, "expired")
            return row
        return []

    def _unknown_one(self, params: Sequence[object]) -> dict[str, object] | list[dict[str, object]]:
        row = self.database.rows.get(UUID(str(params[0])))
        if row and row["state"] == "sending":
            row["apns_outcome_bucket"] = "unknown"
            self._transition(row, "delivery_unknown")
            return row
        return []

    def _expire_due(self, params: Sequence[object]) -> list[dict[str, object]]:
        rows = []
        for row in self.database.rows.values():
            if self._expired(row) and row["state"] in {"prepared", "claimed", "sent"}:
                self._transition(row, "expired")
                rows.append(row)
        return rows

    def _unknown_due(self, params: Sequence[object]) -> list[dict[str, object]]:
        rows = []
        for row in self.database.rows.values():
            if self._expired(row) and row["state"] == "sending":
                row["apns_outcome_bucket"] = "unknown"
                self._transition(row, "delivery_unknown")
                rows.append(row)
        return rows

    def _by_digest(self, key: str, value: object) -> dict[str, object] | None:
        return next((row for row in self.database.rows.values() if row[key] == value), None)

    def _expired(self, row: Mapping[str, object]) -> bool:
        return int(row["expires_at"]) <= self.database.now

    @staticmethod
    def _owner_matches(row: Mapping[str, object], prefix: str, expected: Sequence[object]) -> bool:
        return tuple(expected) == (
            row[f"{prefix}_user_digest"],
            row[f"{prefix}_device_digest"],
            row[f"{prefix}_generation_digest"],
        )

    @staticmethod
    def _transition(row: dict[str, object], state: str) -> None:
        row["state"] = state
        row["row_version"] = int(row["row_version"]) + 1
        row["is_expired"] = False


class ProductionDispatchStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.database = FakeDatabase()
        self.master_key = b"k" * 32
        self.store = PostgresProductionDispatchStore(
            "postgresql://store.example.test/salemx",
            self.master_key,
            self.database.connect,
        )
        self.sender = DispatchIdentity("sender-user", "sender-device", "sender-generation")
        self.receiver = DispatchIdentity("receiver-user", "receiver-device", "receiver-generation")
        self.metadata = {"room_id": "private-room", "call_id": "private-call", "intent": "audio"}

    def create(self, expires_in_seconds: int = 60):
        return self.store.create_dispatch(self.sender, self.receiver, 7, self.metadata, expires_in_seconds)

    def test_encrypted_metadata_round_trip_and_plaintext_absent(self) -> None:
        references = self.create()
        persisted = next(iter(self.database.rows.values()))
        representation = repr(persisted)
        for plaintext in (*self.metadata.values(), self.sender.user_id, self.receiver.device_id):
            self.assertNotIn(str(plaintext), representation)
        self.store.claim(references.sender_reference, self.sender)
        self.store.admit_send(references.sender_reference, self.sender)
        self.store.complete_send(references.sender_reference, self.sender, APNsOutcome.ACCEPTED)
        consumed = self.store.consume(references.receiver_reference, self.receiver)
        self.assertEqual(consumed.metadata, self.metadata)
        self.assertEqual(consumed.snapshot.state, DispatchState.CONSUMED)

    def test_wrong_master_key_cannot_resolve_keyed_reference(self) -> None:
        references = self.create()
        self.store.claim(references.sender_reference, self.sender)
        self.store.admit_send(references.sender_reference, self.sender)
        self.store.complete_send(references.sender_reference, self.sender, APNsOutcome.ACCEPTED)
        wrong_store = PostgresProductionDispatchStore(
            "postgresql://store.example.test/salemx",
            b"w" * 32,
            self.database.connect,
        )
        with self.assertRaises(DispatchNotFoundError):
            wrong_store.consume(references.receiver_reference, self.receiver)
        self.assertEqual(next(iter(self.database.rows.values()))["state"], "sent")

    def test_ciphertext_authentication_failure_prevents_consumption(self) -> None:
        references = self.create()
        self.store.claim(references.sender_reference, self.sender)
        self.store.admit_send(references.sender_reference, self.sender)
        self.store.complete_send(references.sender_reference, self.sender, APNsOutcome.ACCEPTED)
        persisted = next(iter(self.database.rows.values()))
        ciphertext = bytes(persisted["encrypted_metadata"])
        persisted["encrypted_metadata"] = ciphertext[:-1] + bytes([ciphertext[-1] ^ 1])
        with self.assertRaises(MetadataAuthenticationError):
            self.store.consume(references.receiver_reference, self.receiver)
        self.assertEqual(persisted["state"], "sent")

    def test_owner_device_and_generation_mismatches_fail_closed(self) -> None:
        references = self.create()
        mismatches = (
            DispatchIdentity("wrong-user", self.sender.device_id, self.sender.session_generation),
            DispatchIdentity(self.sender.user_id, "wrong-device", self.sender.session_generation),
            DispatchIdentity(self.sender.user_id, self.sender.device_id, "wrong-generation"),
        )
        for identity in mismatches:
            with self.assertRaises(DispatchOwnershipError):
                self.store.claim(references.sender_reference, identity)

    def test_claim_and_cancel_are_idempotent(self) -> None:
        references = self.create()
        first_claim = self.store.claim(references.sender_reference, self.sender)
        second_claim = self.store.claim(references.sender_reference, self.sender)
        self.assertEqual(first_claim.row_version, second_claim.row_version)
        first_cancel = self.store.cancel(references.sender_reference, self.sender)
        second_cancel = self.store.cancel(references.sender_reference, self.sender)
        self.assertEqual(first_cancel.row_version, second_cancel.row_version)

    def test_concurrent_send_admission_permits_exactly_one(self) -> None:
        references = self.create()
        self.store.claim(references.sender_reference, self.sender)

        def admit() -> bool:
            try:
                self.store.admit_send(references.sender_reference, self.sender)
            except DispatchTransitionError:
                return False
            return True

        with ThreadPoolExecutor(max_workers=2) as executor:
            admitted = list(executor.map(lambda _: admit(), range(2)))
        self.assertEqual(admitted.count(True), 1)
        self.assertEqual(next(iter(self.database.rows.values()))["send_attempt_count"], 1)

    def test_duplicate_completion_returns_stored_result_without_resend(self) -> None:
        references = self.create()
        self.store.claim(references.sender_reference, self.sender)
        self.store.admit_send(references.sender_reference, self.sender)
        first = self.store.complete_send(references.sender_reference, self.sender, APNsOutcome.ACCEPTED)
        second = self.store.complete_send(references.sender_reference, self.sender, APNsOutcome.ACCEPTED)
        self.assertEqual(first, second)
        self.assertEqual(first.send_attempt_count, 1)

    def test_rejected_and_unknown_outcomes_are_terminal(self) -> None:
        for outcome, expected_state in (
            (APNsOutcome.REJECTED, DispatchState.SEND_FAILED),
            (APNsOutcome.UNKNOWN, DispatchState.DELIVERY_UNKNOWN),
        ):
            references = self.create()
            self.store.claim(references.sender_reference, self.sender)
            self.store.admit_send(references.sender_reference, self.sender)
            snapshot = self.store.complete_send(references.sender_reference, self.sender, outcome)
            self.assertEqual(snapshot.state, expected_state)
            self.assertEqual(snapshot.send_attempt_count, 1)
            with self.assertRaises(DispatchTransitionError):
                self.store.admit_send(references.sender_reference, self.sender)

    def test_expiry_uses_database_time_and_blocks_consumption(self) -> None:
        references = self.create(expires_in_seconds=1)
        self.database.now += 2
        with self.assertRaises(DispatchExpiredError):
            self.store.claim(references.sender_reference, self.sender)
        self.assertEqual(next(iter(self.database.rows.values()))["state"], "expired")

    def test_capability_upsert_uses_only_keyed_identity_values(self) -> None:
        snapshot = self.store.register_capability(self.receiver, "production", 1, "audio", "matrixrtc", 9, 60)
        self.assertEqual(snapshot.protocol_version, 1)
        self.assertEqual(snapshot.token_binding_revision, 9)
        self.assertNotIn(self.receiver.user_id, repr(self.database.capabilities))

    def test_no_sensitive_values_are_logged(self) -> None:
        logger = logging.getLogger("salemx_call_service.production_dispatch_store")
        with self.assertLogs(logger, level="CRITICAL") as captured:
            logger.critical("store-test-marker")
            self.create()
        output = "\n".join(captured.output)
        for value in (*self.metadata.values(), self.sender.user_id, self.receiver.device_id):
            self.assertNotIn(str(value), output)


class ProductionDispatchConfigurationTests(unittest.TestCase):
    def test_feature_defaults_disabled_without_changing_baseline_configuration(self) -> None:
        self.assertFalse(direct_call_store_settings_from_env({}).enabled)
        ignored = direct_call_store_settings_from_env({
            DIRECT_CALL_DATABASE_DSN_ENV: "not-a-dsn",
            DIRECT_CALL_STORE_MASTER_KEY_B64_ENV: "not-a-key",
        })
        self.assertFalse(ignored.enabled)

    def test_enabled_feature_requires_postgres_dsn_and_32_byte_key(self) -> None:
        base_env = {DIRECT_CALL_PENDING_STORE_ENABLED_ENV: "1"}
        with self.assertRaises(DirectCallStoreConfigurationError):
            direct_call_store_settings_from_env(base_env)
        with self.assertRaises(DirectCallStoreConfigurationError):
            direct_call_store_settings_from_env({
                **base_env,
                DIRECT_CALL_DATABASE_DSN_ENV: "postgresql://store.example.test/salemx",
                DIRECT_CALL_STORE_MASTER_KEY_B64_ENV: base64.b64encode(b"short").decode(),
            })
        settings = direct_call_store_settings_from_env({
            **base_env,
            DIRECT_CALL_DATABASE_DSN_ENV: "postgresql://store.example.test/salemx",
            DIRECT_CALL_STORE_MASTER_KEY_B64_ENV: base64.b64encode(b"k" * 32).decode(),
        })
        self.assertTrue(settings.enabled)
        self.assertEqual(settings.master_key, b"k" * 32)


class ProductionDispatchMigrationTests(unittest.TestCase):
    def test_migration_shape_and_constraints(self) -> None:
        migration = (Path(__file__).parents[1] / "migrations" / "0001_production_dispatch_v1.sql").read_text()
        required_fragments = (
            "CREATE TABLE IF NOT EXISTS salemx_direct_call_capabilities",
            "CREATE TABLE IF NOT EXISTS salemx_direct_call_dispatches",
            "sender_reference_digest BYTEA NOT NULL UNIQUE",
            "receiver_reference_digest BYTEA NOT NULL UNIQUE",
            "send_attempt_count IN (0, 1)",
            "salemx_direct_call_dispatches_active_expiry_idx",
            "WHERE state IN ('prepared', 'claimed', 'sending', 'sent')",
        )
        for fragment in required_fragments:
            self.assertIn(fragment, migration)
        forbidden_columns = ("room_id ", "call_id ", "user_id ", "device_id ", "pushkit_token")
        lowered = migration.lower()
        for column in forbidden_columns:
            self.assertNotIn(column, lowered)


if __name__ == "__main__":
    unittest.main()
