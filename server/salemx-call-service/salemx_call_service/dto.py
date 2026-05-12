"""Request and response DTOs for native direct-call LiveKit token allocation."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Literal

from .errors import bad_request, unsupported_intent

Direction = Literal["outgoing", "incoming"]


def _required_string(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise bad_request(error=f"Missing or invalid {key}.")
    return value


def _optional_string(payload: dict[str, Any], key: str) -> str | None:
    value = payload.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise bad_request(error=f"Invalid {key}.")
    return value


@dataclass(frozen=True)
class TokenRequest:
    version: int
    call_id: str
    room_id: str
    peer_user_id: str
    intent: str
    direction: Direction
    device_id: str | None = None
    client_transaction_id: str | None = None

    @classmethod
    def from_mapping(cls, payload: dict[str, Any]) -> "TokenRequest":
        version = payload.get("version")
        if version != 1:
            raise bad_request(errcode="M_UNRECOGNIZED", error="Unsupported direct-call token request version.")

        intent = _required_string(payload, "intent")
        if intent != "audio":
            raise unsupported_intent()

        direction = _required_string(payload, "direction")
        if direction not in ("outgoing", "incoming"):
            raise bad_request(error="Invalid direction.")

        return cls(
            version=version,
            call_id=_required_string(payload, "call_id"),
            room_id=_required_string(payload, "room_id"),
            peer_user_id=_required_string(payload, "peer_user_id"),
            intent=intent,
            direction=direction,  # type: ignore[arg-type]
            device_id=_optional_string(payload, "device_id"),
            client_transaction_id=_optional_string(payload, "client_transaction_id"),
        )

    def safe_log_fields(self) -> dict[str, Any]:
        return {
            "call_id": self.call_id,
            "intent": self.intent,
            "direction": self.direction,
            "has_device_id": self.device_id is not None,
            "has_client_transaction_id": self.client_transaction_id is not None,
        }


@dataclass(frozen=True)
class LiveKitPayload:
    server_url: str
    room_name: str
    participant_token: str
    expires_at: datetime

    def as_dict(self) -> dict[str, Any]:
        return {
            "server_url": self.server_url,
            "room_name": self.room_name,
            "participant_token": self.participant_token,
            "expires_at": self.expires_at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        }


@dataclass(frozen=True)
class AllocationPayload:
    id: str
    call_id: str
    intent: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "call_id": self.call_id,
            "intent": self.intent,
        }


@dataclass(frozen=True)
class TokenResponse:
    livekit: LiveKitPayload
    allocation: AllocationPayload
    version: int = 1

    def as_dict(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "livekit": self.livekit.as_dict(),
            "allocation": self.allocation.as_dict(),
        }
