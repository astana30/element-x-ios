"""Redacted APNs VoIP sandbox send scaffold for controlled direct-call smoke tests."""

from __future__ import annotations

from dataclasses import dataclass
from os import environ
from typing import Any
from typing import Protocol

from .errors import bad_request
from .pushkit_tokens import PushKitTokenRecord


APNS_VOIP_ENABLED_ENV = "SALEMX_APNS_VOIP_ENABLED"
APNS_VOIP_ENVIRONMENT_ENV = "SALEMX_APNS_VOIP_ENVIRONMENT"
APNS_TEAM_ID_ENV = "SALEMX_APNS_TEAM_ID"
APNS_KEY_ID_ENV = "SALEMX_APNS_KEY_ID"
APNS_AUTH_KEY_PATH_ENV = "SALEMX_APNS_AUTH_KEY_PATH"
APNS_TOPIC_ENV = "SALEMX_APNS_TOPIC"


@dataclass(frozen=True)
class APNsVoIPSandboxConfig:
    enabled: bool
    environment: str
    team_id_present: bool
    key_id_present: bool
    auth_key_path_present: bool
    topic: str | None

    @classmethod
    def from_env(cls) -> "APNsVoIPSandboxConfig":
        return cls(
            enabled=environ.get(APNS_VOIP_ENABLED_ENV) == "1",
            environment=environ.get(APNS_VOIP_ENVIRONMENT_ENV, "sandbox"),
            team_id_present=bool(environ.get(APNS_TEAM_ID_ENV)),
            key_id_present=bool(environ.get(APNS_KEY_ID_ENV)),
            auth_key_path_present=bool(environ.get(APNS_AUTH_KEY_PATH_ENV)),
            topic=environ.get(APNS_TOPIC_ENV),
        )

    @property
    def credentials_available(self) -> bool:
        return self.team_id_present and self.key_id_present and self.auth_key_path_present

    @property
    def topic_resolved(self) -> bool:
        return self.topic is not None and self.topic.endswith(".voip")


@dataclass(frozen=True)
class APNsVoIPSandboxSendRequest:
    version: int
    dry_run: bool

    @classmethod
    def from_mapping(cls, payload: dict[str, Any]) -> "APNsVoIPSandboxSendRequest":
        version = payload.get("version")
        if version != 1:
            raise bad_request(errcode="M_UNRECOGNIZED", error="Unsupported APNs VoIP send request version.")

        dry_run = payload.get("dry_run", False)
        if not isinstance(dry_run, bool):
            raise bad_request(error="Invalid dry_run.")

        return cls(version=version, dry_run=dry_run)


@dataclass(frozen=True)
class APNsVoIPPushRequest:
    token: str
    topic: str
    payload: dict[str, object]
    environment: str


class APNsVoIPProviderProtocol(Protocol):
    def send_sandbox_push(self, request: APNsVoIPPushRequest) -> str:
        ...


class DisabledAPNsVoIPProvider:
    def send_sandbox_push(self, request: APNsVoIPPushRequest) -> str:
        return "sandbox_failure_redacted"


@dataclass(frozen=True)
class APNsVoIPSendDiagnostics:
    apns_voip_control_invoked: bool = True
    persisted_pushkit_token_lookup_requested: bool = True
    persisted_pushkit_token_lookup_result: str = "missing"
    pushkit_token_redacted: bool = True
    apns_provider_requested: bool = False
    apns_credentials_available: bool = False
    apns_environment: str = "sandbox"
    apns_topic_resolved: bool = False
    apns_voip_payload_built: bool = False
    apns_voip_push_send_requested: bool = False
    apns_voip_push_send_result: str = "not_run"
    apns_response_redacted: bool = True
    voip_push_repeated_send_requested: bool = False
    media_credentials_requested: bool = False
    media_connect_requested: bool = False
    matrix_event_emit_requested: bool = False
    real_pushkit_background_callback_wired: bool = False
    blocked_reason: str = "none"

    def as_dict(self) -> dict[str, object]:
        return {
            "apns_voip_control_invoked": self.apns_voip_control_invoked,
            "persisted_pushkit_token_lookup_requested": self.persisted_pushkit_token_lookup_requested,
            "persisted_pushkit_token_lookup_result": self.persisted_pushkit_token_lookup_result,
            "pushkit_token_redacted": self.pushkit_token_redacted,
            "apns_provider_requested": self.apns_provider_requested,
            "apns_credentials_available": self.apns_credentials_available,
            "apns_environment": self.apns_environment,
            "apns_topic_resolved": self.apns_topic_resolved,
            "apns_voip_payload_built": self.apns_voip_payload_built,
            "apns_voip_push_send_requested": self.apns_voip_push_send_requested,
            "apns_voip_push_send_result": self.apns_voip_push_send_result,
            "apns_response_redacted": self.apns_response_redacted,
            "voip_push_repeated_send_requested": self.voip_push_repeated_send_requested,
            "media_credentials_requested": self.media_credentials_requested,
            "media_connect_requested": self.media_connect_requested,
            "matrix_event_emit_requested": self.matrix_event_emit_requested,
            "real_pushkit_background_callback_wired": self.real_pushkit_background_callback_wired,
            "blocked_reason": self.blocked_reason,
        }


class APNsVoIPSandboxSendService:
    def __init__(self,
                 config: APNsVoIPSandboxConfig,
                 provider: APNsVoIPProviderProtocol | None = None) -> None:
        self._config = config
        self._provider = provider or DisabledAPNsVoIPProvider()

    def send(self, request: APNsVoIPSandboxSendRequest, token_record: PushKitTokenRecord | None) -> APNsVoIPSendDiagnostics:
        if token_record is None:
            return APNsVoIPSendDiagnostics(
                persisted_pushkit_token_lookup_result="missing",
                apns_credentials_available=self._config.credentials_available,
                apns_environment=self._config.environment,
                apns_topic_resolved=self._config.topic_resolved,
                blocked_reason="persisted_pushkit_token_missing",
            )

        if self._config.environment != "sandbox":
            return APNsVoIPSendDiagnostics(
                persisted_pushkit_token_lookup_result="found",
                apns_credentials_available=self._config.credentials_available,
                apns_environment=self._config.environment,
                apns_topic_resolved=self._config.topic_resolved,
                blocked_reason="apns_production_environment_rejected",
            )

        if not self._config.topic_resolved:
            return APNsVoIPSendDiagnostics(
                persisted_pushkit_token_lookup_result="found",
                apns_credentials_available=self._config.credentials_available,
                apns_environment=self._config.environment,
                apns_topic_resolved=False,
                blocked_reason="apns_voip_topic_unresolved",
            )

        payload = _sandbox_payload()
        if request.dry_run:
            return APNsVoIPSendDiagnostics(
                persisted_pushkit_token_lookup_result="found",
                apns_credentials_available=self._config.credentials_available,
                apns_environment="sandbox",
                apns_topic_resolved=True,
                apns_voip_payload_built=True,
                apns_voip_push_send_result="dry_run",
            )

        if not self._config.enabled:
            return APNsVoIPSendDiagnostics(
                persisted_pushkit_token_lookup_result="found",
                apns_credentials_available=self._config.credentials_available,
                apns_environment="sandbox",
                apns_topic_resolved=True,
                apns_voip_payload_built=True,
                blocked_reason="apns_voip_send_disabled",
            )

        if not self._config.credentials_available:
            return APNsVoIPSendDiagnostics(
                persisted_pushkit_token_lookup_result="found",
                apns_credentials_available=False,
                apns_environment="sandbox",
                apns_topic_resolved=True,
                apns_voip_payload_built=True,
                apns_voip_push_send_result="not_run_credentials_missing",
                blocked_reason="apns_credentials_unavailable",
            )

        send_result = self._provider.send_sandbox_push(APNsVoIPPushRequest(
            token=token_record.token,
            topic=self._config.topic or "",
            payload=payload,
            environment="sandbox",
        ))
        return APNsVoIPSendDiagnostics(
            persisted_pushkit_token_lookup_result="found",
            apns_provider_requested=True,
            apns_credentials_available=True,
            apns_environment="sandbox",
            apns_topic_resolved=True,
            apns_voip_payload_built=True,
            apns_voip_push_send_requested=True,
            apns_voip_push_send_result=send_result,
            blocked_reason="none" if send_result == "sandbox_success" else "apns_sandbox_send_http_failure_redacted",
        )


def _sandbox_payload() -> dict[str, object]:
    return {
        "aps": {
            "content-available": 1,
        },
        "salemx_direct_call": {
            "version": 1,
            "kind": "sandbox_voip_smoke",
            "redacted": True,
        },
    }
