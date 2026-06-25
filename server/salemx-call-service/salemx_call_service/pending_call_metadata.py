"""Authenticated pending direct-call metadata source."""

from __future__ import annotations

from dataclasses import dataclass
import secrets
from typing import Any, Protocol

from .auth import AuthenticatedUser
from .dto import TokenRequest
from .errors import CallServiceError, bad_request


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


class PendingCallMetadataStoreProtocol(Protocol):
    def store(self,
              recipient: str,
              recipient_device: str | None,
              expires_at_ms: int,
              metadata: PendingCallMetadataRequest) -> str:
        ...

    def retrieve(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        ...

    def retrieve_sender_view(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        ...


class InMemoryPendingCallMetadataStore:
    def __init__(self) -> None:
        self._records: dict[str, PendingCallMetadataRecord] = {}

    def store(self,
              recipient: str,
              recipient_device: str | None,
              expires_at_ms: int,
              metadata: PendingCallMetadataRequest) -> str:
        reference = secrets.token_urlsafe(24)
        self._records[reference] = PendingCallMetadataRecord(
            reference=reference,
            recipient=recipient,
            recipient_device=recipient_device,
            expires_at_ms=expires_at_ms,
            metadata=metadata,
        )
        return reference

    def retrieve(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        record = self._active_record(reference, now_ms)
        if record.recipient != authenticated_user.user_id:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        if record.recipient_device is not None and record.recipient_device != authenticated_user.device_id:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        return record.metadata

    def retrieve_sender_view(self, reference: str, authenticated_user: AuthenticatedUser, now_ms: int) -> PendingCallMetadataRequest:
        record = self._active_record(reference, now_ms)
        if record.metadata.peer_user_id != authenticated_user.user_id:
            raise CallServiceError(status_code=403,
                                   errcode="M_FORBIDDEN",
                                   error="Pending call metadata is not available.")
        return record.metadata.sender_view_payload(record.recipient)

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
