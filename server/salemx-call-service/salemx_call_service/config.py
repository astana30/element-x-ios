"""Environment configuration for the SalemX direct-call token service."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from os import environ
from typing import Mapping
from urllib.parse import urlparse

SERVICE_MODE_ENV = "SALEMX_CALL_SERVICE_MODE"
LEGACY_FAKE_MODE_ENV = "SALEMX_CALL_SERVICE_FAKE_MODE"
ALLOW_INSECURE_LIVEKIT_URL_ENV = "SALEMX_CALL_SERVICE_ALLOW_INSECURE_LIVEKIT_URL"

DEFAULT_SERVICE_MODE = "staging"
PLACEHOLDER_LIVEKIT_HOST = "local-smoke.livekit.invalid"
MIN_TOKEN_TTL_SECONDS = 30
MAX_TOKEN_TTL_SECONDS = 300


class ServiceMode(str, Enum):
    LOCAL_FAKE = "local_fake"
    STAGING = "staging"
    PRODUCTION = "production"


class ServicePreflightReason(str, Enum):
    OK = "ok"
    FAKE_MODE_FORBIDDEN = "fakeModeForbidden"
    MISSING_SYNAPSE_CONFIG = "missingSynapseConfig"
    MISSING_LIVEKIT_CONFIG = "missingLiveKitConfig"
    INSECURE_LIVEKIT_URL = "insecureLiveKitURL"
    PLACEHOLDER_LIVEKIT_URL = "placeholderLiveKitURL"
    INVALID_TOKEN_TTL = "invalidTokenTTL"
    UNSUPPORTED_MODE = "unsupportedMode"


@dataclass(frozen=True)
class ServiceReadiness:
    mode: str
    ready: bool
    reason: str
    fake_mode_enabled: bool
    synapse_configured: bool
    livekit_configured: bool
    livekit_url_secure: bool
    livekit_url_placeholder: bool
    token_ttl_bounded: bool

    def as_dict(self) -> dict[str, object]:
        return {
            "mode": self.mode,
            "ready": self.ready,
            "reason": self.reason,
            "fakeModeEnabled": self.fake_mode_enabled,
            "synapseConfigured": self.synapse_configured,
            "liveKitConfigured": self.livekit_configured,
            "liveKitURLSecure": self.livekit_url_secure,
            "liveKitURLPlaceholder": self.livekit_url_placeholder,
            "tokenTTLBounded": self.token_ttl_bounded,
        }


class ServicePreflightError(RuntimeError):
    def __init__(self, readiness: ServiceReadiness) -> None:
        self.readiness = readiness
        super().__init__(f"Call service preflight failed: {readiness.reason}")


@dataclass(frozen=True)
class ServiceConfig:
    synapse_base_url: str
    synapse_admin_token: str
    livekit_url: str
    livekit_api_key: str
    livekit_api_secret: str
    token_ttl_seconds: int = 120
    allocation_ttl_seconds: int = 300
    rate_limit_per_minute: int = 30
    log_level: str = "INFO"

    @classmethod
    def from_env(cls) -> "ServiceConfig":
        validate_service_preflight(environ)
        return cls(
            synapse_base_url=_required_env("SYNAPSE_BASE_URL"),
            synapse_admin_token=_required_env("SYNAPSE_ADMIN_TOKEN"),
            livekit_url=_required_env("LIVEKIT_URL"),
            livekit_api_key=_required_env("LIVEKIT_API_KEY"),
            livekit_api_secret=_required_env("LIVEKIT_API_SECRET"),
            token_ttl_seconds=_int_env("TOKEN_TTL_SECONDS", 120),
            allocation_ttl_seconds=_int_env("ALLOCATION_TTL_SECONDS", 300),
            rate_limit_per_minute=_int_env("RATE_LIMIT_PER_MINUTE", 30),
            log_level=environ.get("LOG_LEVEL", "INFO"),
        )


def service_mode_from_env(env: Mapping[str, str] = environ) -> str:
    return _env_value(env, SERVICE_MODE_ENV) or DEFAULT_SERVICE_MODE


def service_readiness_from_env(env: Mapping[str, str] = environ) -> ServiceReadiness:
    mode = service_mode_from_env(env)
    fake_mode_enabled = _env_value(env, LEGACY_FAKE_MODE_ENV) == "1" or mode == ServiceMode.LOCAL_FAKE.value

    if mode == ServiceMode.LOCAL_FAKE.value:
        return ServiceReadiness(
            mode=mode,
            ready=True,
            reason=ServicePreflightReason.OK.value,
            fake_mode_enabled=True,
            synapse_configured=False,
            livekit_configured=_configured(env, "LIVEKIT_URL"),
            livekit_url_secure=_is_secure_livekit_url(_env_value(env, "LIVEKIT_URL")),
            livekit_url_placeholder=_is_placeholder_livekit_url(_env_value(env, "LIVEKIT_URL")),
            token_ttl_bounded=True,
        )

    if mode != ServiceMode.STAGING.value:
        return _readiness(mode, False, ServicePreflightReason.UNSUPPORTED_MODE, fake_mode_enabled=fake_mode_enabled)

    return _staging_readiness(
        mode=mode,
        fake_mode_enabled=fake_mode_enabled,
        synapse_base_url=_env_value(env, "SYNAPSE_BASE_URL"),
        synapse_admin_token=_env_value(env, "SYNAPSE_ADMIN_TOKEN"),
        livekit_url=_env_value(env, "LIVEKIT_URL"),
        livekit_api_key=_env_value(env, "LIVEKIT_API_KEY"),
        livekit_api_secret=_env_value(env, "LIVEKIT_API_SECRET"),
        token_ttl_value=_env_value(env, "TOKEN_TTL_SECONDS"),
        allow_insecure_livekit_url=_env_value(env, ALLOW_INSECURE_LIVEKIT_URL_ENV) == "1",
    )


def service_readiness_from_config(config: ServiceConfig, env: Mapping[str, str] = environ) -> ServiceReadiness:
    mode = service_mode_from_env(env)
    fake_mode_enabled = _env_value(env, LEGACY_FAKE_MODE_ENV) == "1"
    if mode != ServiceMode.STAGING.value:
        return _readiness(mode, False, ServicePreflightReason.UNSUPPORTED_MODE, fake_mode_enabled=fake_mode_enabled)

    return _staging_readiness(
        mode=mode,
        fake_mode_enabled=fake_mode_enabled,
        synapse_base_url=config.synapse_base_url,
        synapse_admin_token=config.synapse_admin_token,
        livekit_url=config.livekit_url,
        livekit_api_key=config.livekit_api_key,
        livekit_api_secret=config.livekit_api_secret,
        token_ttl_value=str(config.token_ttl_seconds),
        allow_insecure_livekit_url=_env_value(env, ALLOW_INSECURE_LIVEKIT_URL_ENV) == "1",
    )


def validate_service_preflight(env: Mapping[str, str] = environ) -> ServiceReadiness:
    readiness = service_readiness_from_env(env)
    if not readiness.ready:
        raise ServicePreflightError(readiness)
    return readiness


def _staging_readiness(mode: str,
                       fake_mode_enabled: bool,
                       synapse_base_url: str | None,
                       synapse_admin_token: str | None,
                       livekit_url: str | None,
                       livekit_api_key: str | None,
                       livekit_api_secret: str | None,
                       token_ttl_value: str | None,
                       allow_insecure_livekit_url: bool) -> ServiceReadiness:
    synapse_configured = bool(synapse_base_url and synapse_admin_token)
    livekit_configured = bool(livekit_url and livekit_api_key and livekit_api_secret)
    livekit_url_secure = _is_secure_livekit_url(livekit_url)
    livekit_url_placeholder = _is_placeholder_livekit_url(livekit_url)
    token_ttl_bounded = _token_ttl_bounded(token_ttl_value)

    if fake_mode_enabled:
        reason = ServicePreflightReason.FAKE_MODE_FORBIDDEN
    elif not synapse_configured:
        reason = ServicePreflightReason.MISSING_SYNAPSE_CONFIG
    elif not livekit_configured:
        reason = ServicePreflightReason.MISSING_LIVEKIT_CONFIG
    elif livekit_url_placeholder:
        reason = ServicePreflightReason.PLACEHOLDER_LIVEKIT_URL
    elif not livekit_url_secure and not allow_insecure_livekit_url:
        reason = ServicePreflightReason.INSECURE_LIVEKIT_URL
    elif not token_ttl_bounded:
        reason = ServicePreflightReason.INVALID_TOKEN_TTL
    else:
        reason = ServicePreflightReason.OK

    return ServiceReadiness(
        mode=mode,
        ready=reason == ServicePreflightReason.OK,
        reason=reason.value,
        fake_mode_enabled=fake_mode_enabled,
        synapse_configured=synapse_configured,
        livekit_configured=livekit_configured,
        livekit_url_secure=livekit_url_secure,
        livekit_url_placeholder=livekit_url_placeholder,
        token_ttl_bounded=token_ttl_bounded,
    )


def _readiness(mode: str,
               ready: bool,
               reason: ServicePreflightReason,
               fake_mode_enabled: bool = False) -> ServiceReadiness:
    return ServiceReadiness(
        mode=mode,
        ready=ready,
        reason=reason.value,
        fake_mode_enabled=fake_mode_enabled,
        synapse_configured=False,
        livekit_configured=False,
        livekit_url_secure=False,
        livekit_url_placeholder=False,
        token_ttl_bounded=True,
    )


def _configured(env: Mapping[str, str], name: str) -> bool:
    return _env_value(env, name) is not None


def _env_value(env: Mapping[str, str], name: str) -> str | None:
    value = env.get(name)
    if value is None:
        return None
    value = value.strip()
    return value or None


def _is_secure_livekit_url(livekit_url: str | None) -> bool:
    if livekit_url is None:
        return False
    return urlparse(livekit_url).scheme == "wss"


def _is_placeholder_livekit_url(livekit_url: str | None) -> bool:
    if livekit_url is None:
        return False
    return urlparse(livekit_url).hostname == PLACEHOLDER_LIVEKIT_HOST


def _token_ttl_bounded(value: str | None) -> bool:
    if value is None:
        return True
    try:
        token_ttl_seconds = int(value)
    except ValueError:
        return False
    return MIN_TOKEN_TTL_SECONDS <= token_ttl_seconds <= MAX_TOKEN_TTL_SECONDS


def _required_env(name: str) -> str:
    value = _env_value(environ, name)
    if value is None:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _int_env(name: str, default: int) -> int:
    value = environ.get(name)
    if value is None or value == "":
        return default
    return int(value)
