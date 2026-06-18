"""Redacted APNs VoIP sandbox send scaffold for controlled direct-call smoke tests."""

from __future__ import annotations

import base64
from dataclasses import dataclass
import json
from os import environ
from pathlib import Path
import time
from typing import Any
from typing import Protocol

import httpx
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.serialization import load_pem_private_key

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
    team_id: str | None
    key_id: str | None
    auth_key_path: str | None
    topic: str | None

    @classmethod
    def from_env(cls) -> "APNsVoIPSandboxConfig":
        return cls(
            enabled=environ.get(APNS_VOIP_ENABLED_ENV) == "1",
            environment=environ.get(APNS_VOIP_ENVIRONMENT_ENV, "sandbox"),
            team_id=environ.get(APNS_TEAM_ID_ENV),
            key_id=environ.get(APNS_KEY_ID_ENV),
            auth_key_path=environ.get(APNS_AUTH_KEY_PATH_ENV),
            topic=environ.get(APNS_TOPIC_ENV),
        )

    @property
    def credentials_available(self) -> bool:
        return bool(self.team_id and self.key_id and self.auth_key_path)

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


@dataclass(frozen=True)
class APNsVoIPPushResult:
    result: str
    failure_reason: str = "none"


class APNsVoIPProviderProtocol(Protocol):
    def send_sandbox_push(self, request: APNsVoIPPushRequest) -> APNsVoIPPushResult:
        ...


class DisabledAPNsVoIPProvider:
    def send_sandbox_push(self, request: APNsVoIPPushRequest) -> APNsVoIPPushResult:
        return APNsVoIPPushResult(result="sandbox_failure_redacted", failure_reason="provider_disabled")


class APNsVoIPHTTP2Provider:
    def __init__(self,
                 config: APNsVoIPSandboxConfig,
                 timeout_seconds: float = 10.0) -> None:
        self._config = config
        self._timeout_seconds = timeout_seconds

    def send_sandbox_push(self, request: APNsVoIPPushRequest) -> APNsVoIPPushResult:
        if self._config.environment != "sandbox":
            return APNsVoIPPushResult(result="sandbox_failure_redacted", failure_reason="environment_mismatch")
        if self._config.team_id is None or self._config.key_id is None or self._config.auth_key_path is None:
            return APNsVoIPPushResult(result="sandbox_failure_redacted", failure_reason="credentials_missing")

        jwt = _apns_provider_jwt(
            team_id=self._config.team_id,
            key_id=self._config.key_id,
            auth_key_path=self._config.auth_key_path,
        )
        headers = {
            "authorization": f"bearer {jwt}",
            "apns-push-type": "voip",
            "apns-topic": request.topic,
            "apns-priority": "10",
        }
        url = f"https://api.sandbox.push.apple.com/3/device/{request.token}"
        try:
            with httpx.Client(http2=True, timeout=self._timeout_seconds) as client:
                response = client.post(url, headers=headers, json=request.payload)
        except httpx.HTTPError:
            return APNsVoIPPushResult(result="sandbox_failure_redacted", failure_reason="transport_error")

        if 200 <= response.status_code < 300:
            return APNsVoIPPushResult(result="sandbox_success")
        return APNsVoIPPushResult(result="sandbox_failure_redacted", failure_reason=_redacted_apns_failure_reason(response))


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
    apns_failure_reason: str = "none"
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
            "apns_failure_reason": self.apns_failure_reason,
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
        self._provider = provider or APNsVoIPHTTP2Provider(config)

    def send(self,
             request: APNsVoIPSandboxSendRequest,
             token_record: PushKitTokenRecord | None,
             payload_kind: str = "sandbox_voip_smoke",
             pending_metadata_reference: str | None = None) -> APNsVoIPSendDiagnostics:
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

        payload = _sandbox_payload(payload_kind, pending_metadata_reference=pending_metadata_reference)
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
                apns_failure_reason="credentials_missing",
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
            apns_voip_push_send_result=send_result.result,
            apns_failure_reason=send_result.failure_reason,
            blocked_reason="none" if send_result.result == "sandbox_success" else "apns_sandbox_send_http_failure_redacted",
        )


def _sandbox_payload(kind: str = "sandbox_voip_smoke",
                     pending_metadata_reference: str | None = None) -> dict[str, object]:
    salemx_payload: dict[str, object] = {
        "version": 1,
        "kind": kind,
        "redacted": True,
    }
    if pending_metadata_reference:
        salemx_payload["pending_metadata_reference"] = pending_metadata_reference
        salemx_payload["pending_metadata_reference_redacted"] = True

    return {
        "aps": {
            "content-available": 1,
        },
        "salemx_direct_call": salemx_payload,
    }


def _apns_provider_jwt(team_id: str, key_id: str, auth_key_path: str) -> str:
    private_key = load_pem_private_key(Path(auth_key_path).read_bytes(), password=None)
    if not isinstance(private_key, ec.EllipticCurvePrivateKey):
        raise ValueError("APNs auth key must be an elliptic curve private key.")

    header = {
        "alg": "ES256",
        "kid": key_id,
    }
    claims = {
        "iss": team_id,
        "iat": int(time.time()),
    }
    signing_input = ".".join([
        _base64_url_json(header),
        _base64_url_json(claims),
    ])
    der_signature = private_key.sign(signing_input.encode("ascii"), ec.ECDSA(hashes.SHA256()))
    r_value, s_value = decode_dss_signature(der_signature)
    signature = r_value.to_bytes(32, "big") + s_value.to_bytes(32, "big")
    return signing_input + "." + _base64_url_bytes(signature)


def _redacted_apns_failure_reason(response: httpx.Response) -> str:
    try:
        reason = response.json().get("reason")
    except (json.JSONDecodeError, ValueError, AttributeError):
        return "http_failure_redacted"
    if isinstance(reason, str) and reason.isidentifier():
        return reason
    return "http_failure_redacted"


def _base64_url_json(payload: dict[str, object]) -> str:
    return _base64_url_bytes(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"))


def _base64_url_bytes(payload: bytes) -> str:
    return base64.urlsafe_b64encode(payload).rstrip(b"=").decode("ascii")
