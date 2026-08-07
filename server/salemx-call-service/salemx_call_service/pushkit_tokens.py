"""Redacted PushKit token registration contract for native direct-call VoIP readiness."""

from __future__ import annotations

from dataclasses import dataclass
from dataclasses import field
from datetime import datetime, timezone
import hashlib
import hmac
import json
import os
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any
from typing import Protocol

from .errors import bad_request
from .logging_utils import stable_redacted_id


def _required_string(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise bad_request(error=f"Missing or invalid {key}.")
    return value


@dataclass(frozen=True)
class PushKitTokenRegistrationRequest:
    version: int
    token: str = field(repr=False)
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
            token=token,
            token_present=True,
            environment_class=environment_class,
        )


@dataclass(frozen=True)
class PushKitTokenBinding:
    environment_class: str
    user_binding: str = field(repr=False)
    device_binding: str = field(repr=False)
    token_record_binding: str = field(repr=False)

    def matches_user(self, user_id: str) -> bool:
        return hmac.compare_digest(self.user_binding, _record_key(user_id, None, self.environment_class))

    def matches_identity(self, user_id: str, device_id: str | None) -> bool:
        if device_id is None or not self.matches_user(user_id):
            return False
        return hmac.compare_digest(self.device_binding, _record_key(user_id, device_id, self.environment_class))


@dataclass(frozen=True)
class PushKitTokenRecord:
    token: str = field(repr=False)
    environment_class: str
    updated_at: datetime
    user_binding: str | None = field(default=None, repr=False)
    device_binding: str | None = field(default=None, repr=False)
    token_record_binding: str | None = field(default=None, repr=False)

    @property
    def authoritative_binding(self) -> PushKitTokenBinding | None:
        if self.user_binding is None or self.device_binding is None or self.token_record_binding is None:
            return None
        expected_binding = _token_record_binding(
            token=self.token,
            environment_class=self.environment_class,
            user_binding=self.user_binding,
            device_binding=self.device_binding,
        )
        if not hmac.compare_digest(self.token_record_binding, expected_binding):
            return None
        return PushKitTokenBinding(
            environment_class=self.environment_class,
            user_binding=self.user_binding,
            device_binding=self.device_binding,
            token_record_binding=self.token_record_binding,
        )


class PushKitTokenStoreProtocol(Protocol):
    def store(self, user_id: str, device_id: str | None, request: PushKitTokenRegistrationRequest) -> str:
        ...

    def retrieve(self, user_id: str, device_id: str | None, environment_class: str) -> PushKitTokenRecord | None:
        ...

    def retrieve_latest_for_user(self, user_id: str, environment_class: str) -> PushKitTokenRecord | None:
        ...


class DisabledPushKitTokenStore:
    def store(self, user_id: str, device_id: str | None, request: PushKitTokenRegistrationRequest) -> str:
        return "not_persisted"

    def retrieve(self, user_id: str, device_id: str | None, environment_class: str) -> PushKitTokenRecord | None:
        return None

    def retrieve_latest_for_user(self, user_id: str, environment_class: str) -> PushKitTokenRecord | None:
        return None


class InMemoryPushKitTokenStore:
    def __init__(self) -> None:
        self._records: dict[str, PushKitTokenRecord] = {}

    def store(self, user_id: str, device_id: str | None, request: PushKitTokenRegistrationRequest) -> str:
        user_binding = _record_key(user_id, None, request.environment_class)
        device_binding = _record_key(user_id, device_id, request.environment_class) if device_id is not None else None
        record = PushKitTokenRecord(
            token=request.token,
            environment_class=request.environment_class,
            updated_at=datetime.now(timezone.utc),
            user_binding=user_binding,
            device_binding=device_binding,
            token_record_binding=_token_record_binding(
                token=request.token,
                environment_class=request.environment_class,
                user_binding=user_binding,
                device_binding=device_binding,
            ) if device_binding is not None else None,
        )
        self._records[_record_key(user_id, device_id, request.environment_class)] = record
        self._records[_record_key(user_id, None, request.environment_class)] = record
        return "persisted"

    def retrieve(self, user_id: str, device_id: str | None, environment_class: str) -> PushKitTokenRecord | None:
        return self._records.get(_record_key(user_id, device_id, environment_class))

    def retrieve_latest_for_user(self, user_id: str, environment_class: str) -> PushKitTokenRecord | None:
        return self.retrieve(user_id, None, environment_class)


class FilePushKitTokenStore:
    """Small server-side token store.

    The file contains raw PushKit tokens for future APNs provider use, so it must never be logged or exposed by API
    responses. Keys are stable hashes of Matrix user/device/environment instead of raw identifiers.
    """

    def __init__(self, path: str) -> None:
        self._path = Path(path)

    def store(self, user_id: str, device_id: str | None, request: PushKitTokenRegistrationRequest) -> str:
        records = self._read_records()
        user_binding = _record_key(user_id, None, request.environment_class)
        device_binding = _record_key(user_id, device_id, request.environment_class) if device_id is not None else None
        record = {
            "token": request.token,
            "environment": request.environment_class,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "user_binding": user_binding,
            "device_binding": device_binding,
            "token_record_binding": _token_record_binding(
                token=request.token,
                environment_class=request.environment_class,
                user_binding=user_binding,
                device_binding=device_binding,
            ) if device_binding is not None else None,
        }
        records[_record_key(user_id, device_id, request.environment_class)] = record
        records[_record_key(user_id, None, request.environment_class)] = record
        self._write_records(records)
        return "persisted"

    def retrieve(self, user_id: str, device_id: str | None, environment_class: str) -> PushKitTokenRecord | None:
        record = self._read_records().get(_record_key(user_id, device_id, environment_class))
        if not isinstance(record, dict):
            return None

        token = record.get("token")
        stored_environment = record.get("environment")
        updated_at = record.get("updated_at")
        user_binding = record.get("user_binding")
        device_binding = record.get("device_binding")
        token_record_binding = record.get("token_record_binding")
        if not isinstance(token, str) or not isinstance(stored_environment, str) or not isinstance(updated_at, str):
            return None

        try:
            parsed_updated_at = datetime.fromisoformat(updated_at)
        except ValueError:
            parsed_updated_at = datetime.fromtimestamp(0, timezone.utc)

        return PushKitTokenRecord(
            token=token,
            environment_class=stored_environment,
            updated_at=parsed_updated_at,
            user_binding=user_binding if isinstance(user_binding, str) else None,
            device_binding=device_binding if isinstance(device_binding, str) else None,
            token_record_binding=token_record_binding if isinstance(token_record_binding, str) else None,
        )

    def retrieve_latest_for_user(self, user_id: str, environment_class: str) -> PushKitTokenRecord | None:
        return self.retrieve(user_id, None, environment_class)

    def _read_records(self) -> dict[str, dict[str, Any]]:
        if not self._path.exists():
            return {}
        with self._path.open("r", encoding="utf-8") as file:
            payload = json.load(file)
        if not isinstance(payload, dict):
            return {}
        return {key: value for key, value in payload.items() if isinstance(key, str) and isinstance(value, dict)}

    def _write_records(self, records: dict[str, dict[str, str]]) -> None:
        self._path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self._path.parent, 0o700)

        with NamedTemporaryFile("w", encoding="utf-8", dir=str(self._path.parent), delete=False) as file:
            json.dump(records, file, sort_keys=True)
            file.write("\n")
            temporary_path = file.name

        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, self._path)
        os.chmod(self._path, 0o600)


@dataclass(frozen=True)
class PushKitTokenRegistrationDiagnostics:
    pushkit_token_registration_invoked: bool = True
    pushkit_token_present: bool = False
    pushkit_token_redacted: bool = True
    pushkit_token_store_requested: bool = False
    pushkit_token_store_result: str = "not_persisted"
    pushkit_token_registration_result: str = "rejected_redacted"
    pushkit_token_retrieval_internal_check: str = "not_requested"
    pushkit_token_api_exposes_raw_token: bool = False
    voip_push_send_requested: bool = False
    apns_provider_requested: bool = False
    media_credentials_requested: bool = False
    media_connect_requested: bool = False
    matrix_event_emit_requested: bool = False
    blocked_reason: str = "none"
    pushkit_upload_store_key_redacted: str = "none"
    pushkit_upload_record_updated_age_bucket: str = "unknown"
    pushkit_upload_environment: str = "unknown"
    pushkit_upload_token_is_hex: bool = False

    @classmethod
    def accepted(cls,
                 request: PushKitTokenRegistrationRequest,
                 store_result: str = "not_persisted",
                 retrieval_internal_check: str = "not_requested",
                 store_key_redacted: str = "none",
                 record_updated_age_bucket: str = "unknown") -> "PushKitTokenRegistrationDiagnostics":
        return cls(
            pushkit_token_present=request.token_present,
            pushkit_token_store_requested=store_result == "persisted",
            pushkit_token_store_result=store_result,
            pushkit_token_registration_result="registered",
            pushkit_token_retrieval_internal_check=retrieval_internal_check,
            pushkit_upload_store_key_redacted=store_key_redacted,
            pushkit_upload_record_updated_age_bucket=record_updated_age_bucket,
            pushkit_upload_environment=request.environment_class,
            pushkit_upload_token_is_hex=is_hex_pushkit_token(request.token),
        )

    def as_dict(self) -> dict[str, Any]:
        return {
            "pushkit_token_registration_invoked": self.pushkit_token_registration_invoked,
            "pushkit_token_present": self.pushkit_token_present,
            "pushkit_token_redacted": self.pushkit_token_redacted,
            "pushkit_token_store_requested": self.pushkit_token_store_requested,
            "pushkit_token_store_result": self.pushkit_token_store_result,
            "pushkit_token_registration_result": self.pushkit_token_registration_result,
            "pushkit_token_retrieval_internal_check": self.pushkit_token_retrieval_internal_check,
            "pushkit_token_api_exposes_raw_token": self.pushkit_token_api_exposes_raw_token,
            "voip_push_send_requested": self.voip_push_send_requested,
            "apns_provider_requested": self.apns_provider_requested,
            "media_credentials_requested": self.media_credentials_requested,
            "media_connect_requested": self.media_connect_requested,
            "matrix_event_emit_requested": self.matrix_event_emit_requested,
            "blocked_reason": self.blocked_reason,
            "pushkit_upload_store_key_redacted": self.pushkit_upload_store_key_redacted,
            "pushkit_upload_record_updated_age_bucket": self.pushkit_upload_record_updated_age_bucket,
            "pushkit_upload_environment": self.pushkit_upload_environment,
            "pushkit_upload_token_is_hex": self.pushkit_upload_token_is_hex,
        }


def _record_key(user_id: str, device_id: str | None, environment_class: str) -> str:
    device_component = device_id or "unbound"
    return hashlib.sha256(f"{user_id}\n{device_component}\n{environment_class}".encode("utf-8")).hexdigest()


def _token_record_binding(token: str,
                          environment_class: str,
                          user_binding: str,
                          device_binding: str) -> str:
    return hashlib.sha256(
        f"{token}\n{environment_class}\n{user_binding}\n{device_binding}".encode("utf-8"),
    ).hexdigest()


def redacted_latest_user_record_key(user_id: str, environment_class: str) -> str:
    return stable_redacted_id(_record_key(user_id, None, environment_class))


def record_updated_age_bucket(record: PushKitTokenRecord | None, now: datetime | None = None) -> str:
    if record is None:
        return "missing"

    reference = now or datetime.now(timezone.utc)
    updated_at = record.updated_at
    if updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)

    age_seconds = max(0.0, (reference - updated_at).total_seconds())
    if age_seconds < 5 * 60:
        return "<5m"
    if age_seconds < 30 * 60:
        return "5-30m"
    return ">30m"


def is_hex_pushkit_token(token: str) -> bool:
    return bool(token) and len(token) % 2 == 0 and all(character in "0123456789abcdefABCDEF" for character in token)
