"""Authenticated pending direct-call metadata source."""

from __future__ import annotations

from dataclasses import dataclass
from functools import wraps
import secrets
from threading import RLock
from typing import Any, Callable, Protocol, TypeVar

from .auth import AuthenticatedUser
from .dto import TokenRequest
from .errors import CallServiceError, bad_request
from .pushkit_tokens import PushKitTokenBinding


ReturnValue = TypeVar("ReturnValue")


def _synchronized_store_operation(operation: Callable[..., ReturnValue]) -> Callable[..., ReturnValue]:
    @wraps(operation)
    def synchronized(self: "InMemoryPendingCallMetadataStore", *args: object, **kwargs: object) -> ReturnValue:
        with self._lock:
            return operation(self, *args, **kwargs)

    return synchronized


@dataclass(frozen=True)
class PendingCallMetadataRequest:
    call_id: str
    room_id: str
    peer_user_id: str
    direction: str
    intent: str

    @classmethod
    def from_mapping(cls, payload: dict[str, Any], authenticated_user: AuthenticatedUser) -> "PendingCallMetadataRequest":
        version = payload.get("version")
        if version != 1:
            raise bad_request(errcode="M_UNRECOGNIZED", error="Unsupported pending metadata version.")

        intent = _required_string(payload, "intent")
        if intent != "audio":
            raise bad_request(error="Unsupported pending metadata intent.")

        return cls(
            call_id=_required_string(payload, "call_id"),
            room_id=_required_string(payload, "room_id"),
            peer_user_id=authenticated_user.user_id,
            direction="incoming",
            intent=intent,
        )

    def token_request_payload(self) -> dict[str, object]:
        return {
            "version": 1,
            "call_id": self.call_id,
            "room_id": self.room_id,
            "peer_user_id": self.peer_user_id,
            "direction": self.direction,
            "intent": self.intent,
        }

    def sender_view_payload(self, recipient: str) -> "PendingCallMetadataRequest":
        return PendingCallMetadataRequest(
            call_id=self.call_id,
            room_id=self.room_id,
            peer_user_id=recipient,
            direction="outgoing",
            intent=self.intent,
        )

    def as_token_request(self) -> TokenRequest:
        return TokenRequest.from_mapping(self.token_request_payload())

    def safe_diagnostics(self, source_created: bool = True, reference_present: bool = True) -> dict[str, object]:
        return {
            "pending_metadata_source_requested": True,
            "pending_metadata_source_created": source_created,
            "pending_metadata_reference_present": reference_present,
            "pending_metadata_payload_redacted": True,
            "pending_metadata_has_call_identifier": bool(self.call_id),
            "pending_metadata_has_room_binding": bool(self.room_id),
            "pending_metadata_has_peer": bool(self.peer_user_id),
            "pending_metadata_direction": self.direction,
            "pending_metadata_intent": self.intent,
            "pending_metadata_fetch_authenticated_required": True,
        }


@dataclass(frozen=True)
class PendingCallMetadataRecord:
    reference: str
    recipient: str
    recipient_device: str | None
    expires_at_ms: int
    metadata: PendingCallMetadataRequest
    sender_only: bool = False
    sender_device: str | None = None
    prepared_receiver_reference: str | None = None
    claimed_by_sender: bool = False
    sending: bool = False
    sent: bool = False
    receiver_token_binding: PushKitTokenBinding | None = None


@dataclass(frozen=True)
class PendingCallMetadataSnapshotCounts:
    total: int
    active_unexpired: int
    expired_inert: int
    orphaned_or_invalid: int

    def as_dict(self) -> dict[str, int]:
        return {
            "total": self.total,
            "active_unexpired": self.active_unexpired,
            "expired_inert": self.expired_inert,
            "orphaned_or_invalid": self.orphaned_or_invalid,
        }


def _is_nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value)


def _is_optional_nonempty_string(value: object) -> bool:
    return value is None or _is_nonempty_string(value)


def _is_binding_shape_valid(binding: object) -> bool:
    if not isinstance(binding, PushKitTokenBinding):
        return False
    return (
        binding.environment_class in {"development", "production"}
        and _is_nonempty_string(binding.user_binding)
        and _is_nonempty_string(binding.device_binding)
        and _is_nonempty_string(binding.token_record_binding)
    )


def _pending_record_shape_is_valid(reference: object, record: object) -> bool:
    if not isinstance(reference, str) or not isinstance(record, PendingCallMetadataRecord):
        return False
    metadata = record.metadata
    if not isinstance(metadata, PendingCallMetadataRequest):
        return False
    if not (
        reference
        and record.reference == reference
        and _is_nonempty_string(record.recipient)
        and _is_optional_nonempty_string(record.recipient_device)
        and isinstance(record.expires_at_ms, int)
        and not isinstance(record.expires_at_ms, bool)
        and record.expires_at_ms >= 0
        and _is_nonempty_string(metadata.call_id)
        and _is_nonempty_string(metadata.room_id)
        and _is_nonempty_string(metadata.peer_user_id)
        and metadata.direction == "incoming"
        and metadata.intent == "audio"
        and isinstance(record.sender_only, bool)
        and _is_optional_nonempty_string(record.sender_device)
        and _is_optional_nonempty_string(record.prepared_receiver_reference)
        and isinstance(record.claimed_by_sender, bool)
        and isinstance(record.sending, bool)
        and isinstance(record.sent, bool)
        and (record.receiver_token_binding is None or _is_binding_shape_valid(record.receiver_token_binding))
    ):
        return False
    if record.sender_only and record.receiver_token_binding is not None:
        return False
    if record.prepared_receiver_reference is not None and not record.sender_only:
        return False
    if record.sender_only and record.sent and record.prepared_receiver_reference is None:
        return False
    if record.sending and (not record.sender_only or not record.claimed_by_sender or record.sender_device is None):
        return False
    if record.sending and record.sent:
        return False
    if not record.sender_only and record.sent and record.receiver_token_binding is None:
        return False
    return True


def _pending_record_is_valid(reference: object,
                             record: object,
                             records: dict[str, PendingCallMetadataRecord]) -> bool:
    if not _pending_record_shape_is_valid(reference, record):
        return False
    if not isinstance(record, PendingCallMetadataRecord) or record.prepared_receiver_reference is None:
        return True
    receiver_record = records.get(record.prepared_receiver_reference)
    return (
        _pending_record_shape_is_valid(record.prepared_receiver_reference, receiver_record)
        and isinstance(receiver_record, PendingCallMetadataRecord)
        and not receiver_record.sender_only
        and receiver_record.prepared_receiver_reference is None
        and receiver_record.recipient == record.recipient
        and receiver_record.metadata == record.metadata
    )


@dataclass(frozen=True)
class AuthenticatedPendingCallMetadata:
    metadata: PendingCallMetadataRequest
    expires_at_ms: int
    sender_user_id: str
    sender_device_id: str
    receiver_user_id: str
    receiver_device_id: str

    def response_payload(self) -> dict[str, object]:
        return {
            **self.metadata.token_request_payload(),
            "expires_at_ms": self.expires_at_ms,
            "sender_user_id": self.sender_user_id,
            "sender_device_id": self.sender_device_id,
            "peer_device_id": self.sender_device_id,
            "receiver_user_id": self.receiver_user_id,
            "receiver_device_id": self.receiver_device_id,
        }


class PendingCallMetadataStoreProtocol(Protocol):
    def snapshot_counts(self, now_ms: int) -> PendingCallMetadataSnapshotCounts:
        ...

    def store(self,
              recipient: str,
              recipient_device: str | None,
              expires_at_ms: int,
              metadata: PendingCallMetadataRequest,
              sender_only: bool = False,
              sender_device: str | None = None,
              prepared_receiver_reference: str | None = None,
              receiver_token_binding: PushKitTokenBinding | None = None) -> str:
        ...

    def retrieve(self,
                 reference: str,
                 authenticated_user: AuthenticatedUser,
                 now_ms: int) -> AuthenticatedPendingCallMetadata:
        ...

    def retrieve_sender_view(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        ...

    def claim_latest_sender_view(self, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        ...

    def mark_prepared_sender_claimed(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        ...

    def prepared_recipient(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> str:
        ...

    def begin_prepared_send(self,
                            reference: str,
                            authenticated_user: AuthenticatedUser,
                            now_ms: int,
                            receiver_token_binding: PushKitTokenBinding) -> PendingCallMetadataRecord:
        ...

    def complete_prepared_send(self,
                               reference: str,
                               authenticated_user: AuthenticatedUser,
                               now_ms: int,
                               receiver_token_binding: PushKitTokenBinding,
                               accepted: bool) -> None:
        ...

    def discard(self, reference: str) -> None:
        ...


class InMemoryPendingCallMetadataStore:
    def __init__(self) -> None:
        self._records: dict[str, PendingCallMetadataRecord] = {}
        self._lock = RLock()

    @_synchronized_store_operation
    def snapshot_counts(self, now_ms: int) -> PendingCallMetadataSnapshotCounts:
        if not isinstance(now_ms, int) or isinstance(now_ms, bool) or now_ms < 0:
            raise ValueError("Invalid snapshot time.")
        records = dict(self._records)
        invalid_references = {
            reference
            for reference, record in records.items()
            if not _pending_record_is_valid(reference, record, records)
        }
        active_unexpired = sum(
            reference not in invalid_references and record.expires_at_ms > now_ms
            for reference, record in records.items()
        )
        expired_inert = sum(
            reference not in invalid_references and record.expires_at_ms <= now_ms
            for reference, record in records.items()
        )
        return PendingCallMetadataSnapshotCounts(
            total=len(records),
            active_unexpired=active_unexpired,
            expired_inert=expired_inert,
            orphaned_or_invalid=len(invalid_references),
        )

    @_synchronized_store_operation
    def store(self,
              recipient: str,
              recipient_device: str | None,
              expires_at_ms: int,
              metadata: PendingCallMetadataRequest,
              sender_only: bool = False,
              sender_device: str | None = None,
              prepared_receiver_reference: str | None = None,
              receiver_token_binding: PushKitTokenBinding | None = None) -> str:
        reference = secrets.token_urlsafe(24)
        self._records[reference] = PendingCallMetadataRecord(
            reference=reference,
            recipient=recipient,
            recipient_device=recipient_device,
            expires_at_ms=expires_at_ms,
            metadata=metadata,
            sender_only=sender_only,
            sender_device=sender_device,
            prepared_receiver_reference=prepared_receiver_reference,
            receiver_token_binding=receiver_token_binding,
        )
        return reference

    @_synchronized_store_operation
    def retrieve(self,
                 reference: str,
                 authenticated_user: AuthenticatedUser,
                 now_ms: int) -> AuthenticatedPendingCallMetadata:
        record = self._active_record(reference, now_ms)
        if record.sender_only:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        if record.sender_device is None or record.receiver_token_binding is None:
            raise CallServiceError(status_code=409,
                                   errcode="M_CONFLICT",
                                   error="Pending call metadata binding is unavailable.")
        authenticated_device_id = authenticated_user.device_id
        if authenticated_device_id is None:
            raise CallServiceError(status_code=409,
                                   errcode="M_CONFLICT",
                                   error="Pending call metadata binding does not match the authenticated receiver.")
        receiver_matches = record.recipient == authenticated_user.user_id and record.receiver_token_binding.matches_identity(
            authenticated_user.user_id, authenticated_device_id,
        )
        if not receiver_matches:
            raise CallServiceError(status_code=409,
                                   errcode="M_CONFLICT",
                                   error="Pending call metadata binding does not match the authenticated receiver.")

        self._records.pop(reference, None)
        return AuthenticatedPendingCallMetadata(
            metadata=record.metadata,
            expires_at_ms=record.expires_at_ms,
            sender_user_id=record.metadata.peer_user_id,
            sender_device_id=record.sender_device,
            receiver_user_id=authenticated_user.user_id,
            receiver_device_id=authenticated_device_id,
        )

    @_synchronized_store_operation
    def retrieve_sender_view(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        record = self._active_record(reference, now_ms)
        if not record.sender_only:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        if record.metadata.peer_user_id != authenticated_user.user_id:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        if record.sender_device is not None and record.sender_device != authenticated_user.device_id:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        return record.metadata.sender_view_payload(record.recipient)

    @_synchronized_store_operation
    def claim_latest_sender_view(self, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        active_sender_records: list[PendingCallMetadataRecord] = []
        for reference, record in list(self._records.items()):
            if record.expires_at_ms <= now_ms:
                self._records.pop(reference, None)
                continue
            if record.sender_only and record.metadata.peer_user_id == authenticated_user.user_id:
                active_sender_records.append(record)

        if not active_sender_records:
            raise CallServiceError(status_code=404,
                                   errcode="M_NOT_FOUND",
                                   error="Pending call metadata was not found.")

        record = active_sender_records[-1]
        if record.prepared_receiver_reference is not None:
            if authenticated_user.device_id is None:
                raise CallServiceError(status_code=403,
                                       errcode="M_FORBIDDEN",
                                       error="Pending call metadata is not available.")
            self._records[record.reference] = PendingCallMetadataRecord(
                reference=record.reference,
                recipient=record.recipient,
                recipient_device=record.recipient_device,
                expires_at_ms=record.expires_at_ms,
                metadata=record.metadata,
                sender_only=record.sender_only,
                sender_device=authenticated_user.device_id,
                prepared_receiver_reference=record.prepared_receiver_reference,
                claimed_by_sender=True,
                sending=record.sending,
                sent=record.sent,
                receiver_token_binding=record.receiver_token_binding,
            )
            return record.metadata.sender_view_payload(record.recipient)
        if record.sender_device is not None and record.sender_device != authenticated_user.device_id:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        return record.metadata.sender_view_payload(record.recipient)

    @_synchronized_store_operation
    def mark_prepared_sender_claimed(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        record = self._sender_record(reference, authenticated_user, now_ms)
        self._records[record.reference] = PendingCallMetadataRecord(
            reference=record.reference,
            recipient=record.recipient,
            recipient_device=record.recipient_device,
            expires_at_ms=record.expires_at_ms,
            metadata=record.metadata,
            sender_only=record.sender_only,
            sender_device=record.sender_device,
            prepared_receiver_reference=record.prepared_receiver_reference,
            claimed_by_sender=True,
            sending=record.sending,
            sent=record.sent,
            receiver_token_binding=record.receiver_token_binding,
        )
        return record.metadata.sender_view_payload(record.recipient)

    @_synchronized_store_operation
    def prepared_recipient(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> str:
        record = self._sender_record(reference, authenticated_user, now_ms)
        self._validate_prepared_sender_record(record)
        return record.recipient

    @_synchronized_store_operation
    def begin_prepared_send(self,
                            reference: str,
                            authenticated_user: AuthenticatedUser,
                            now_ms: int,
                            receiver_token_binding: PushKitTokenBinding) -> PendingCallMetadataRecord:
        record = self._sender_record(reference, authenticated_user, now_ms)
        self._validate_prepared_sender_record(record)
        if not receiver_token_binding.matches_user(record.recipient):
            raise CallServiceError(status_code=409,
                                   errcode="M_DIRECT_CALL_RECEIVER_BINDING_UNAVAILABLE",
                                   error="Registered receiver binding is unavailable.")
        if record.sent:
            raise CallServiceError(status_code=409,
                                   errcode="M_LIMIT_EXCEEDED",
                                   error="Prepared call metadata was already sent.")
        if record.sending:
            raise CallServiceError(status_code=409,
                                   errcode="M_LIMIT_EXCEEDED",
                                   error="Prepared call metadata send is already in progress.")
        if record.prepared_receiver_reference is None:
            raise CallServiceError(status_code=404,
                                   errcode="M_NOT_FOUND",
                                   error="Prepared call metadata was not found.")
        receiver_record = self._active_record(record.prepared_receiver_reference, now_ms)
        if receiver_record.recipient != record.recipient:
            raise CallServiceError(status_code=409,
                                   errcode="M_CONFLICT",
                                   error="Prepared receiver metadata binding is unavailable.")
        bound_receiver_record = PendingCallMetadataRecord(
            reference=receiver_record.reference,
            recipient=receiver_record.recipient,
            recipient_device=None,
            expires_at_ms=receiver_record.expires_at_ms,
            metadata=receiver_record.metadata,
            sender_only=receiver_record.sender_only,
            sender_device=record.sender_device,
            prepared_receiver_reference=receiver_record.prepared_receiver_reference,
            claimed_by_sender=True,
            sent=False,
            receiver_token_binding=receiver_token_binding,
        )
        self._records[record.reference] = PendingCallMetadataRecord(
            reference=record.reference,
            recipient=record.recipient,
            recipient_device=record.recipient_device,
            expires_at_ms=record.expires_at_ms,
            metadata=record.metadata,
            sender_only=record.sender_only,
            sender_device=record.sender_device,
            prepared_receiver_reference=record.prepared_receiver_reference,
            claimed_by_sender=record.claimed_by_sender,
            sending=True,
            sent=False,
            receiver_token_binding=record.receiver_token_binding,
        )
        return bound_receiver_record

    @_synchronized_store_operation
    def complete_prepared_send(self,
                               reference: str,
                               authenticated_user: AuthenticatedUser,
                               now_ms: int,
                               receiver_token_binding: PushKitTokenBinding,
                               accepted: bool) -> None:
        record = self._sender_record(reference, authenticated_user, now_ms)
        self._validate_prepared_sender_record(record)
        if not record.sending or record.sent or record.prepared_receiver_reference is None:
            raise CallServiceError(status_code=409,
                                   errcode="M_CONFLICT",
                                   error="Prepared call metadata send state is unavailable.")
        if not receiver_token_binding.matches_user(record.recipient):
            raise CallServiceError(status_code=409,
                                   errcode="M_DIRECT_CALL_RECEIVER_BINDING_UNAVAILABLE",
                                   error="Registered receiver binding is unavailable.")
        receiver_record = self._active_record(record.prepared_receiver_reference, now_ms)
        if accepted:
            self._records[receiver_record.reference] = PendingCallMetadataRecord(
                reference=receiver_record.reference,
                recipient=receiver_record.recipient,
                recipient_device=None,
                expires_at_ms=receiver_record.expires_at_ms,
                metadata=receiver_record.metadata,
                sender_only=receiver_record.sender_only,
                sender_device=record.sender_device,
                prepared_receiver_reference=receiver_record.prepared_receiver_reference,
                claimed_by_sender=True,
                sent=True,
                receiver_token_binding=receiver_token_binding,
            )
        self._records[record.reference] = PendingCallMetadataRecord(
            reference=record.reference,
            recipient=record.recipient,
            recipient_device=record.recipient_device,
            expires_at_ms=record.expires_at_ms,
            metadata=record.metadata,
            sender_only=record.sender_only,
            sender_device=record.sender_device,
            prepared_receiver_reference=record.prepared_receiver_reference,
            claimed_by_sender=record.claimed_by_sender,
            sending=False,
            sent=accepted,
            receiver_token_binding=record.receiver_token_binding,
        )

    @staticmethod
    def _validate_prepared_sender_record(record: PendingCallMetadataRecord) -> None:
        if not record.claimed_by_sender:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Prepared call metadata has not been claimed.")
        if record.sender_device is None:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Prepared call metadata claimed device is unavailable.")

    @_synchronized_store_operation
    def discard(self, reference: str) -> None:
        self._records.pop(reference, None)

    @_synchronized_store_operation
    def _sender_record(self,
                       reference: str,
                       authenticated_user: AuthenticatedUser,
                       now_ms: int,
                       enforce_device: bool = True) -> PendingCallMetadataRecord:
        record = self._active_record(reference, now_ms)
        if not record.sender_only:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        if record.metadata.peer_user_id != authenticated_user.user_id:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        if enforce_device and record.sender_device is not None and record.sender_device != authenticated_user.device_id:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        return record

    @_synchronized_store_operation
    def _active_record(self, reference: str, now_ms: int) -> PendingCallMetadataRecord:
        record = self._records.get(reference)
        if record is None:
            raise CallServiceError(status_code=404,
                                   errcode="M_NOT_FOUND",
                                   error="Pending call metadata was not found.")
        if record.expires_at_ms <= now_ms:
            self._records.pop(reference, None)
            raise CallServiceError(status_code=404,
                                   errcode="M_NOT_FOUND",
                                   error="Pending call metadata was not found.")
        return record


def pending_metadata_from_invite_payload(payload: dict[str, Any],
                                         authenticated_user: AuthenticatedUser) -> PendingCallMetadataRequest | None:
    metadata_payload = payload.get("pending_metadata")
    if metadata_payload is None:
        return None
    if not isinstance(metadata_payload, dict):
        raise bad_request(error="Invalid pending metadata.")
    return PendingCallMetadataRequest.from_mapping(metadata_payload, authenticated_user)


def no_pending_metadata_diagnostics() -> dict[str, object]:
    return {
        "pending_metadata_source_requested": False,
        "pending_metadata_source_created": False,
        "pending_metadata_reference_present": False,
        "pending_metadata_payload_redacted": True,
        "pending_metadata_has_call_identifier": False,
        "pending_metadata_has_room_binding": False,
        "pending_metadata_has_peer": False,
        "pending_metadata_direction": "none",
        "pending_metadata_intent": "none",
        "pending_metadata_fetch_authenticated_required": False,
    }


def _required_string(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise bad_request(error=f"Missing or invalid {key}.")
    return value
