"""Redacted PushKit token registration contract for native direct-call VoIP readiness."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .errors import bad_request


def _required_string(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise bad_request(error=f"Missing or invalid {key}.")
    return value


@dataclass(frozen=True)
class PushKitTokenRegistrationRequest:
    version: int
    token_present: bool
    environment_class: str

    @classmethod
    def from_mapping(cls, payload: dict[str, Any]) -> "PushKitTokenRegistrationRequest":
        version = payload.get("version")
        if version != 1:
            raise bad_request(errcode="M_UNRECOGNIZED", error="Unsupported PushKit token registration request version.")

        token = _required_string(payload, "token")
        if len(token) > 8192:
            raise bad_request(error="Invalid token.")

        environment_class = payload.get("environment", "development")
        if environment_class not in {"development", "production"}:
            raise bad_request(error="Invalid environment.")

        return cls(
            version=version,
            token_present=True,
            environment_class=environment_class,
        )


@dataclass(frozen=True)
class PushKitTokenRegistrationDiagnostics:
    pushkit_token_registration_invoked: bool = True
    pushkit_token_present: bool = False
    pushkit_token_store_requested: bool = False
    pushkit_token_store_result: str = "not_persisted"
    pushkit_token_registration_result: str = "rejected_redacted"
    voip_push_send_requested: bool = False
    apns_provider_requested: bool = False
    media_credentials_requested: bool = False
    media_connect_requested: bool = False
    matrix_event_emit_requested: bool = False
    blocked_reason: str = "none"

    @classmethod
    def accepted(cls, request: PushKitTokenRegistrationRequest) -> "PushKitTokenRegistrationDiagnostics":
        return cls(
            pushkit_token_present=request.token_present,
            pushkit_token_registration_result="registered",
        )

    def as_dict(self) -> dict[str, Any]:
        return {
            "pushkit_token_registration_invoked": self.pushkit_token_registration_invoked,
            "pushkit_token_present": self.pushkit_token_present,
            "pushkit_token_store_requested": self.pushkit_token_store_requested,
            "pushkit_token_store_result": self.pushkit_token_store_result,
            "pushkit_token_registration_result": self.pushkit_token_registration_result,
            "voip_push_send_requested": self.voip_push_send_requested,
            "apns_provider_requested": self.apns_provider_requested,
            "media_credentials_requested": self.media_credentials_requested,
            "media_connect_requested": self.media_connect_requested,
            "matrix_event_emit_requested": self.matrix_event_emit_requested,
            "blocked_reason": self.blocked_reason,
        }
