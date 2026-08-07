"""Durable, encrypted PostgreSQL storage for SalemX direct-call dispatches."""

from __future__ import annotations

import hashlib
import hmac
import json
import secrets
from contextlib import AbstractContextManager
from dataclasses import dataclass
from enum import Enum
from typing import Callable, Mapping, Protocol, Sequence
from uuid import UUID, uuid4

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF


class DispatchState(str, Enum):
    PREPARED = "prepared"
    CLAIMED = "claimed"
    SENDING = "sending"
    SENT = "sent"
    CONSUMED = "consumed"
    CANCELLED = "cancelled"
    EXPIRED = "expired"
    SEND_FAILED = "send_failed"
    DELIVERY_UNKNOWN = "delivery_unknown"


class APNsOutcome(str, Enum):
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    UNKNOWN = "unknown"


class ProductionDispatchStoreError(RuntimeError):
    pass


class DispatchNotFoundError(ProductionDispatchStoreError):
    pass


class DispatchOwnershipError(ProductionDispatchStoreError):
    pass


class DispatchExpiredError(ProductionDispatchStoreError):
    pass


class DispatchTransitionError(ProductionDispatchStoreError):
    pass


class MetadataAuthenticationError(ProductionDispatchStoreError):
    pass


@dataclass(frozen=True)
class DispatchIdentity:
    user_id: str
    device_id: str
    session_generation: str


@dataclass(frozen=True)
class DispatchReferences:
    dispatch_id: UUID
    sender_reference: str
    receiver_reference: str


@dataclass(frozen=True)
class DispatchSnapshot:
    dispatch_id: UUID
    state: DispatchState
    row_version: int
    send_attempt_count: int
    apns_outcome: APNsOutcome | None
    receiver_token_binding_revision: int


@dataclass(frozen=True)
class ConsumedDispatch:
    snapshot: DispatchSnapshot
    metadata: Mapping[str, object]


@dataclass(frozen=True)
class SendAdmission:
    snapshot: DispatchSnapshot
    metadata: Mapping[str, object]
    already_sent: bool


@dataclass(frozen=True)
class CapabilitySnapshot:
    capability_id: UUID
    protocol_version: int
    supported_intent: str
    handoff_classification: str
    token_binding_revision: int


class CursorProtocol(Protocol):
    def execute(self, query: str, params: Sequence[object] = ()) -> object: ...

    def fetchone(self) -> Mapping[str, object] | None: ...

    def fetchall(self) -> Sequence[Mapping[str, object]]: ...

    def __enter__(self) -> "CursorProtocol": ...

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None: ...


class ConnectionProtocol(Protocol):
    def cursor(self) -> CursorProtocol: ...

    def transaction(self) -> AbstractContextManager[object]: ...

    def __enter__(self) -> "ConnectionProtocol": ...

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None: ...


ConnectionFactory = Callable[[str], AbstractContextManager[ConnectionProtocol]]


class _DispatchCrypto:
    def __init__(self, master_key: bytes) -> None:
        if len(master_key) != 32:
            raise ValueError("The direct-call store master key must contain exactly 32 bytes.")
        self._encryption_key = self._derive_key(master_key, b"salemx-direct-call-metadata-encryption-v1")
        self._index_key = self._derive_key(master_key, b"salemx-direct-call-index-v1")

    @staticmethod
    def _derive_key(master_key: bytes, info: bytes) -> bytes:
        return HKDF(algorithm=hashes.SHA256(), length=32, salt=None, info=info).derive(master_key)

    def digest(self, classification: str, value: str) -> bytes:
        payload = classification.encode("ascii") + b"\x00" + value.encode("utf-8")
        return hmac.new(self._index_key, payload, hashlib.sha256).digest()

    def encrypt(self, dispatch_id: UUID, metadata: Mapping[str, object]) -> tuple[bytes, bytes]:
        plaintext = json.dumps(metadata, sort_keys=True, separators=(",", ":")).encode("utf-8")
        nonce = secrets.token_bytes(12)
        ciphertext = AESGCM(self._encryption_key).encrypt(nonce, plaintext, self._aad(dispatch_id))
        return nonce, ciphertext

    def decrypt(self, dispatch_id: UUID, nonce: bytes, ciphertext: bytes) -> Mapping[str, object]:
        try:
            plaintext = AESGCM(self._encryption_key).decrypt(nonce, ciphertext, self._aad(dispatch_id))
        except InvalidTag as error:
            raise MetadataAuthenticationError("Stored dispatch metadata failed authentication.") from error
        decoded = json.loads(plaintext)
        if not isinstance(decoded, dict):
            raise MetadataAuthenticationError("Stored dispatch metadata has an invalid shape.")
        return decoded

    @staticmethod
    def _aad(dispatch_id: UUID) -> bytes:
        return b"salemx-direct-call-dispatch-v1\x00" + dispatch_id.bytes


class PostgresProductionDispatchStore:
    def __init__(self,
                 dsn: str,
                 master_key: bytes,
                 connection_factory: ConnectionFactory | None = None) -> None:
        if not dsn:
            raise ValueError("A PostgreSQL DSN is required.")
        self._dsn = dsn
        self._crypto = _DispatchCrypto(master_key)
        self._connection_factory = connection_factory or _psycopg_connection

    def register_capability(self,
                            identity: DispatchIdentity,
                            environment: str,
                            protocol_version: int,
                            supported_intent: str,
                            handoff_classification: str,
                            token_binding_revision: int,
                            expires_in_seconds: int) -> CapabilitySnapshot:
        if protocol_version <= 0 or token_binding_revision < 0 or expires_in_seconds <= 0:
            raise ValueError("Invalid capability parameters.")
        params: tuple[object, ...] = (
            uuid4(),
            self._crypto.digest("capability-user", identity.user_id),
            self._crypto.digest("capability-device", identity.device_id),
            self._crypto.digest("capability-environment", environment),
            self._crypto.digest("capability-generation", identity.session_generation),
            protocol_version,
            supported_intent,
            handoff_classification,
            token_binding_revision,
            expires_in_seconds,
        )
        row = self._execute_one(_UPSERT_CAPABILITY_SQL, params)
        return _capability_snapshot(row)

    def create_dispatch(self,
                        sender: DispatchIdentity,
                        receiver: DispatchIdentity,
                        receiver_token_binding_revision: int,
                        metadata: Mapping[str, object],
                        expires_in_seconds: int) -> DispatchReferences:
        if receiver_token_binding_revision < 0 or expires_in_seconds <= 0:
            raise ValueError("Invalid dispatch parameters.")
        dispatch_id = uuid4()
        sender_reference = secrets.token_urlsafe(32)
        receiver_reference = secrets.token_urlsafe(32)
        nonce, ciphertext = self._crypto.encrypt(dispatch_id, metadata)
        params: tuple[object, ...] = (
            dispatch_id,
            self._crypto.digest("sender-reference", sender_reference),
            self._crypto.digest("receiver-reference", receiver_reference),
            nonce,
            ciphertext,
            *self._identity_digests("sender", sender),
            *self._identity_digests("receiver", receiver),
            receiver_token_binding_revision,
            expires_in_seconds,
        )
        self._execute_one(_CREATE_DISPATCH_SQL, params)
        return DispatchReferences(dispatch_id, sender_reference, receiver_reference)

    def claim(self, sender_reference: str, sender: DispatchIdentity) -> DispatchSnapshot:
        reference_digest = self._crypto.digest("sender-reference", sender_reference)
        owner_digests = self._identity_digests("sender", sender)
        with self._transaction() as cursor:
            row = _execute_fetchone(cursor, _CLAIM_SQL, (reference_digest, *owner_digests))
            if row is not None:
                return _dispatch_snapshot(row)
            row = self._load_sender(cursor, reference_digest)
            self._validate_sender(row, owner_digests)
            if _row_bool(row, "is_expired"):
                self._expire_locked(cursor, row)
                raise DispatchExpiredError("The dispatch has expired.")
            if _row_state(row) == DispatchState.CLAIMED:
                return _dispatch_snapshot(row)
            raise DispatchTransitionError("The dispatch cannot be claimed from its current state.")

    def claim_exact(self, dispatch_id: UUID, sender_reference: str, sender: DispatchIdentity) -> DispatchSnapshot:
        self._validate_exact_sender(dispatch_id, sender_reference, sender)
        return self.claim(sender_reference, sender)

    def admit_send(self, sender_reference: str, sender: DispatchIdentity) -> DispatchSnapshot:
        reference_digest = self._crypto.digest("sender-reference", sender_reference)
        owner_digests = self._identity_digests("sender", sender)
        with self._transaction() as cursor:
            row = _execute_fetchone(cursor, _ADMIT_SEND_SQL, (reference_digest, *owner_digests))
            if row is not None:
                return _dispatch_snapshot(row)
            row = self._load_sender(cursor, reference_digest)
            self._validate_sender(row, owner_digests)
            if _row_bool(row, "is_expired"):
                self._expire_locked(cursor, row)
                raise DispatchExpiredError("The dispatch has expired.")
            raise DispatchTransitionError("A send attempt has already been admitted or is not claimable.")

    def inspect_exact(self,
                      dispatch_id: UUID,
                      sender_reference: str,
                      receiver_reference: str,
                      sender: DispatchIdentity,
                      receiver_token_binding_revision: int | None) -> ConsumedDispatch:
        reference_digest = self._crypto.digest("sender-reference", sender_reference)
        receiver_reference_digest = self._crypto.digest("receiver-reference", receiver_reference)
        owner_digests = self._identity_digests("sender", sender)
        with self._transaction() as cursor:
            row = self._load_sender(cursor, reference_digest)
            self._validate_sender(row, owner_digests)
            self._validate_exact_row(row, dispatch_id, receiver_reference_digest, receiver_token_binding_revision)
            if _row_bool(row, "is_expired"):
                self._expire_locked(cursor, row)
                raise DispatchExpiredError("The dispatch has expired.")
            return ConsumedDispatch(_dispatch_snapshot(row), self._decrypt_row(row))

    def admit_send_exact(self,
                         dispatch_id: UUID,
                         sender_reference: str,
                         receiver_reference: str,
                         sender: DispatchIdentity,
                         receiver_token_binding_revision: int) -> SendAdmission:
        inspected = self.inspect_exact(
            dispatch_id, sender_reference, receiver_reference, sender, receiver_token_binding_revision,
        )
        if inspected.snapshot.state == DispatchState.SENT:
            return SendAdmission(inspected.snapshot, {}, True)
        try:
            snapshot = self.admit_send(sender_reference, sender)
        except DispatchTransitionError:
            current = self.inspect_exact(
                dispatch_id, sender_reference, receiver_reference, sender, receiver_token_binding_revision,
            )
            if current.snapshot.state == DispatchState.SENT:
                return SendAdmission(current.snapshot, {}, True)
            raise
        return SendAdmission(snapshot, inspected.metadata, False)

    def complete_send(self,
                      sender_reference: str,
                      sender: DispatchIdentity,
                      outcome: APNsOutcome) -> DispatchSnapshot:
        reference_digest = self._crypto.digest("sender-reference", sender_reference)
        owner_digests = self._identity_digests("sender", sender)
        target_state = {
            APNsOutcome.ACCEPTED: DispatchState.SENT,
            APNsOutcome.REJECTED: DispatchState.SEND_FAILED,
            APNsOutcome.UNKNOWN: DispatchState.DELIVERY_UNKNOWN,
        }[outcome]
        with self._transaction() as cursor:
            row = _execute_fetchone(
                cursor,
                _COMPLETE_SEND_SQL,
                (target_state.value, outcome.value, reference_digest, *owner_digests),
            )
            if row is not None:
                return _dispatch_snapshot(row)
            row = self._load_sender(cursor, reference_digest)
            self._validate_sender(row, owner_digests)
            if _row_state(row) == target_state and _row_value(row, "apns_outcome_bucket") == outcome.value:
                return _dispatch_snapshot(row)
            raise DispatchTransitionError("The APNs result cannot be applied to this dispatch.")

    def complete_send_exact(self,
                            dispatch_id: UUID,
                            sender_reference: str,
                            sender: DispatchIdentity,
                            outcome: APNsOutcome) -> DispatchSnapshot:
        self._validate_exact_sender(dispatch_id, sender_reference, sender)
        return self.complete_send(sender_reference, sender, outcome)

    def cancel(self, sender_reference: str, sender: DispatchIdentity) -> DispatchSnapshot:
        reference_digest = self._crypto.digest("sender-reference", sender_reference)
        owner_digests = self._identity_digests("sender", sender)
        with self._transaction() as cursor:
            row = _execute_fetchone(cursor, _CANCEL_SQL, (reference_digest, *owner_digests))
            if row is not None:
                return _dispatch_snapshot(row)
            row = self._load_sender(cursor, reference_digest)
            self._validate_sender(row, owner_digests)
            if _row_bool(row, "is_expired"):
                self._expire_locked(cursor, row)
                raise DispatchExpiredError("The dispatch has expired.")
            if _row_state(row) == DispatchState.CANCELLED:
                return _dispatch_snapshot(row)
            raise DispatchTransitionError("The dispatch cannot be cancelled from its current state.")

    def cancel_exact(self, dispatch_id: UUID, sender_reference: str, sender: DispatchIdentity) -> DispatchSnapshot:
        self._validate_exact_sender(dispatch_id, sender_reference, sender)
        return self.cancel(sender_reference, sender)

    def consume(self, receiver_reference: str, receiver: DispatchIdentity) -> ConsumedDispatch:
        reference_digest = self._crypto.digest("receiver-reference", receiver_reference)
        owner_digests = self._identity_digests("receiver", receiver)
        with self._transaction() as cursor:
            row = _execute_fetchone(cursor, _LOAD_RECEIVER_SQL, (reference_digest,))
            if row is None:
                raise DispatchNotFoundError("The dispatch was not found.")
            self._validate_receiver(row, owner_digests)
            if _row_bool(row, "is_expired") and _row_state(row) != DispatchState.CONSUMED:
                self._expire_locked(cursor, row)
                raise DispatchExpiredError("The dispatch has expired.")
            if _row_state(row) not in {DispatchState.SENT, DispatchState.CONSUMED}:
                raise DispatchTransitionError("The dispatch is not consumable.")
            metadata = self._decrypt_row(row)
            if _row_state(row) == DispatchState.SENT:
                updated = _execute_fetchone(
                    cursor,
                    _CONSUME_SQL,
                    (reference_digest, *owner_digests),
                )
                if updated is None:
                    raise DispatchTransitionError("The dispatch could not be consumed atomically.")
                row = updated
            return ConsumedDispatch(_dispatch_snapshot(row), metadata)

    def consume_exact(self,
                      dispatch_id: UUID,
                      receiver_reference: str,
                      receiver: DispatchIdentity) -> ConsumedDispatch:
        reference_digest = self._crypto.digest("receiver-reference", receiver_reference)
        with self._transaction() as cursor:
            row = _execute_fetchone(cursor, _LOAD_RECEIVER_SQL, (reference_digest,))
            if row is None:
                raise DispatchNotFoundError("The dispatch was not found.")
            if UUID(str(_row_value(row, "dispatch_id"))) != dispatch_id:
                raise DispatchNotFoundError("The dispatch was not found.")
        return self.consume(receiver_reference, receiver)

    def expire_due(self) -> int:
        with self._transaction() as cursor:
            expired = _execute_fetchall(cursor, _EXPIRE_DUE_SQL, ())
            unknown = _execute_fetchall(cursor, _MARK_UNKNOWN_DUE_SQL, ())
            return len(expired) + len(unknown)

    def _execute_one(self, query: str, params: Sequence[object]) -> Mapping[str, object]:
        with self._transaction() as cursor:
            row = _execute_fetchone(cursor, query, params)
            if row is None:
                raise ProductionDispatchStoreError("The database operation returned no record.")
            return row

    def _transaction(self) -> AbstractContextManager[CursorProtocol]:
        return _Transaction(self._connection_factory, self._dsn)

    def _identity_digests(self, prefix: str, identity: DispatchIdentity) -> tuple[bytes, bytes, bytes]:
        return (
            self._crypto.digest(f"{prefix}-user", identity.user_id),
            self._crypto.digest(f"{prefix}-device", identity.device_id),
            self._crypto.digest(f"{prefix}-generation", identity.session_generation),
        )

    def _load_sender(self, cursor: CursorProtocol, reference_digest: bytes) -> Mapping[str, object]:
        row = _execute_fetchone(cursor, _LOAD_SENDER_SQL, (reference_digest,))
        if row is None:
            raise DispatchNotFoundError("The dispatch was not found.")
        return row

    def _validate_exact_sender(self,
                               dispatch_id: UUID,
                               sender_reference: str,
                               sender: DispatchIdentity) -> None:
        reference_digest = self._crypto.digest("sender-reference", sender_reference)
        owner_digests = self._identity_digests("sender", sender)
        with self._transaction() as cursor:
            row = self._load_sender(cursor, reference_digest)
            self._validate_sender(row, owner_digests)
            if UUID(str(_row_value(row, "dispatch_id"))) != dispatch_id:
                raise DispatchNotFoundError("The dispatch was not found.")

    @staticmethod
    def _validate_exact_row(row: Mapping[str, object],
                            dispatch_id: UUID,
                            receiver_reference_digest: bytes,
                            receiver_token_binding_revision: int | None) -> None:
        if UUID(str(_row_value(row, "dispatch_id"))) != dispatch_id:
            raise DispatchNotFoundError("The dispatch was not found.")
        if not hmac.compare_digest(bytes(_row_value(row, "receiver_reference_digest")), receiver_reference_digest):
            raise DispatchNotFoundError("The dispatch was not found.")
        if (receiver_token_binding_revision is not None
                and int(_row_value(row, "receiver_token_binding_revision")) != receiver_token_binding_revision):
            raise DispatchTransitionError("The receiver token binding changed.")

    @staticmethod
    def _validate_sender(row: Mapping[str, object], expected: tuple[bytes, bytes, bytes]) -> None:
        _validate_owner(row, "sender", expected)

    @staticmethod
    def _validate_receiver(row: Mapping[str, object], expected: tuple[bytes, bytes, bytes]) -> None:
        _validate_owner(row, "receiver", expected)

    @staticmethod
    def _expire_locked(cursor: CursorProtocol, row: Mapping[str, object]) -> None:
        state = _row_state(row)
        query = _MARK_UNKNOWN_ONE_SQL if state == DispatchState.SENDING else _MARK_EXPIRED_ONE_SQL
        _execute_fetchone(cursor, query, (_row_value(row, "dispatch_id"),))

    def _decrypt_row(self, row: Mapping[str, object]) -> Mapping[str, object]:
        return self._crypto.decrypt(
            UUID(str(_row_value(row, "dispatch_id"))),
            bytes(_row_value(row, "metadata_nonce")),
            bytes(_row_value(row, "encrypted_metadata")),
        )


class _Transaction(AbstractContextManager[CursorProtocol]):
    def __init__(self, connection_factory: ConnectionFactory, dsn: str) -> None:
        self._connection_manager = connection_factory(dsn)
        self._connection: ConnectionProtocol | None = None
        self._transaction_manager: AbstractContextManager[object] | None = None
        self._cursor: CursorProtocol | None = None

    def __enter__(self) -> CursorProtocol:
        self._connection = self._connection_manager.__enter__()
        self._transaction_manager = self._connection.transaction()
        self._transaction_manager.__enter__()
        self._cursor = self._connection.cursor()
        return self._cursor.__enter__()

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None:
        if self._cursor is not None:
            self._cursor.__exit__(exc_type, exc_value, traceback)
        if self._transaction_manager is not None:
            self._transaction_manager.__exit__(exc_type, exc_value, traceback)
        self._connection_manager.__exit__(exc_type, exc_value, traceback)


def _psycopg_connection(dsn: str) -> AbstractContextManager[ConnectionProtocol]:
    import psycopg
    from psycopg.rows import dict_row

    return psycopg.connect(dsn, row_factory=dict_row)


def _execute_fetchone(cursor: CursorProtocol,
                      query: str,
                      params: Sequence[object]) -> Mapping[str, object] | None:
    cursor.execute(query, params)
    return cursor.fetchone()


def _execute_fetchall(cursor: CursorProtocol,
                      query: str,
                      params: Sequence[object]) -> Sequence[Mapping[str, object]]:
    cursor.execute(query, params)
    return cursor.fetchall()


def _validate_owner(row: Mapping[str, object], prefix: str, expected: tuple[bytes, bytes, bytes]) -> None:
    actual = (
        bytes(_row_value(row, f"{prefix}_user_digest")),
        bytes(_row_value(row, f"{prefix}_device_digest")),
        bytes(_row_value(row, f"{prefix}_generation_digest")),
    )
    if not all(hmac.compare_digest(left, right) for left, right in zip(actual, expected)):
        raise DispatchOwnershipError("The authenticated dispatch owner does not match.")


def _dispatch_snapshot(row: Mapping[str, object]) -> DispatchSnapshot:
    outcome = _row_value(row, "apns_outcome_bucket")
    return DispatchSnapshot(
        dispatch_id=UUID(str(_row_value(row, "dispatch_id"))),
        state=_row_state(row),
        row_version=int(_row_value(row, "row_version")),
        send_attempt_count=int(_row_value(row, "send_attempt_count")),
        apns_outcome=APNsOutcome(str(outcome)) if outcome is not None else None,
        receiver_token_binding_revision=int(_row_value(row, "receiver_token_binding_revision")),
    )


def _capability_snapshot(row: Mapping[str, object]) -> CapabilitySnapshot:
    return CapabilitySnapshot(
        capability_id=UUID(str(_row_value(row, "capability_id"))),
        protocol_version=int(_row_value(row, "protocol_version")),
        supported_intent=str(_row_value(row, "supported_intent")),
        handoff_classification=str(_row_value(row, "handoff_classification")),
        token_binding_revision=int(_row_value(row, "token_binding_revision")),
    )


def _row_value(row: Mapping[str, object], key: str) -> object:
    if key not in row:
        raise ProductionDispatchStoreError("The database returned an incomplete record.")
    return row[key]


def _row_state(row: Mapping[str, object]) -> DispatchState:
    return DispatchState(str(_row_value(row, "state")))


def _row_bool(row: Mapping[str, object], key: str) -> bool:
    return bool(_row_value(row, key))


_UPSERT_CAPABILITY_SQL = """/* production_dispatch:upsert_capability */
INSERT INTO salemx_direct_call_capabilities (
    capability_id, user_digest, device_digest, environment_digest, session_generation_digest,
    protocol_version, supported_intent, handoff_classification, token_binding_revision, expires_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP + (%s * INTERVAL '1 second'))
ON CONFLICT (user_digest, device_digest, environment_digest, session_generation_digest, protocol_version, supported_intent)
DO UPDATE SET handoff_classification = EXCLUDED.handoff_classification,
              token_binding_revision = EXCLUDED.token_binding_revision,
              refreshed_at = CURRENT_TIMESTAMP,
              expires_at = EXCLUDED.expires_at
RETURNING *
"""

_CREATE_DISPATCH_SQL = """/* production_dispatch:create */
INSERT INTO salemx_direct_call_dispatches (
    dispatch_id, sender_reference_digest, receiver_reference_digest, metadata_nonce, encrypted_metadata,
    sender_user_digest, sender_device_digest, sender_generation_digest,
    receiver_user_digest, receiver_device_digest, receiver_generation_digest,
    receiver_token_binding_revision, state, expires_at
) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'prepared',
          CURRENT_TIMESTAMP + (%s * INTERVAL '1 second'))
RETURNING *, FALSE AS is_expired
"""

_CLAIM_SQL = """/* production_dispatch:claim */
UPDATE salemx_direct_call_dispatches
SET state = 'claimed', row_version = row_version + 1, transitioned_at = CURRENT_TIMESTAMP
WHERE sender_reference_digest = %s
  AND sender_user_digest = %s AND sender_device_digest = %s AND sender_generation_digest = %s
  AND state = 'prepared' AND expires_at > CURRENT_TIMESTAMP
RETURNING *, FALSE AS is_expired
"""

_ADMIT_SEND_SQL = """/* production_dispatch:admit_send */
UPDATE salemx_direct_call_dispatches
SET state = 'sending', row_version = row_version + 1, transitioned_at = CURRENT_TIMESTAMP, send_attempt_count = 1
WHERE sender_reference_digest = %s
  AND sender_user_digest = %s AND sender_device_digest = %s AND sender_generation_digest = %s
  AND state = 'claimed' AND send_attempt_count = 0 AND expires_at > CURRENT_TIMESTAMP
RETURNING *, FALSE AS is_expired
"""

_COMPLETE_SEND_SQL = """/* production_dispatch:complete_send */
UPDATE salemx_direct_call_dispatches
SET state = %s, apns_outcome_bucket = %s, row_version = row_version + 1, transitioned_at = CURRENT_TIMESTAMP
WHERE sender_reference_digest = %s
  AND sender_user_digest = %s AND sender_device_digest = %s AND sender_generation_digest = %s
  AND state = 'sending' AND send_attempt_count = 1
RETURNING *, (expires_at <= CURRENT_TIMESTAMP) AS is_expired
"""

_CANCEL_SQL = """/* production_dispatch:cancel */
UPDATE salemx_direct_call_dispatches
SET state = 'cancelled', row_version = row_version + 1, transitioned_at = CURRENT_TIMESTAMP
WHERE sender_reference_digest = %s
  AND sender_user_digest = %s AND sender_device_digest = %s AND sender_generation_digest = %s
  AND state IN ('prepared', 'claimed') AND expires_at > CURRENT_TIMESTAMP
RETURNING *, FALSE AS is_expired
"""

_CONSUME_SQL = """/* production_dispatch:consume */
UPDATE salemx_direct_call_dispatches
SET state = 'consumed', row_version = row_version + 1, transitioned_at = CURRENT_TIMESTAMP
WHERE receiver_reference_digest = %s
  AND receiver_user_digest = %s AND receiver_device_digest = %s AND receiver_generation_digest = %s
  AND state = 'sent' AND apns_outcome_bucket = 'accepted' AND expires_at > CURRENT_TIMESTAMP
RETURNING *, FALSE AS is_expired
"""

_LOAD_SENDER_SQL = """/* production_dispatch:load_sender */
SELECT *, (expires_at <= CURRENT_TIMESTAMP) AS is_expired
FROM salemx_direct_call_dispatches WHERE sender_reference_digest = %s FOR UPDATE
"""

_LOAD_RECEIVER_SQL = """/* production_dispatch:load_receiver */
SELECT *, (expires_at <= CURRENT_TIMESTAMP) AS is_expired
FROM salemx_direct_call_dispatches WHERE receiver_reference_digest = %s FOR UPDATE
"""

_MARK_EXPIRED_ONE_SQL = """/* production_dispatch:expire_one */
UPDATE salemx_direct_call_dispatches
SET state = 'expired', row_version = row_version + 1, transitioned_at = CURRENT_TIMESTAMP
WHERE dispatch_id = %s AND state IN ('prepared', 'claimed', 'sent')
RETURNING *, TRUE AS is_expired
"""

_MARK_UNKNOWN_ONE_SQL = """/* production_dispatch:unknown_one */
UPDATE salemx_direct_call_dispatches
SET state = 'delivery_unknown', apns_outcome_bucket = 'unknown',
    row_version = row_version + 1, transitioned_at = CURRENT_TIMESTAMP
WHERE dispatch_id = %s AND state = 'sending' AND send_attempt_count = 1
RETURNING *, TRUE AS is_expired
"""

_EXPIRE_DUE_SQL = """/* production_dispatch:expire_due */
UPDATE salemx_direct_call_dispatches
SET state = 'expired', row_version = row_version + 1, transitioned_at = CURRENT_TIMESTAMP
WHERE expires_at <= CURRENT_TIMESTAMP AND state IN ('prepared', 'claimed', 'sent')
RETURNING *
"""

_MARK_UNKNOWN_DUE_SQL = """/* production_dispatch:unknown_due */
UPDATE salemx_direct_call_dispatches
SET state = 'delivery_unknown', apns_outcome_bucket = 'unknown',
    row_version = row_version + 1, transitioned_at = CURRENT_TIMESTAMP
WHERE expires_at <= CURRENT_TIMESTAMP AND state = 'sending' AND send_attempt_count = 1
RETURNING *
"""
