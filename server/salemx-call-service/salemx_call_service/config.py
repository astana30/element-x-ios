"""Environment configuration for the SalemX direct-call token service."""

from __future__ import annotations

from base64 import b64decode
from binascii import Error as BinasciiError
from dataclasses import dataclass
from enum import Enum
from os import environ
from typing import Mapping
from urllib.parse import urlparse

SERVICE_MODE_ENV = "SALEMX_CALL_SERVICE_MODE"
LEGACY_FAKE_MODE_ENV = "SALEMX_CALL_SERVICE_FAKE_MODE"
ALLOW_INSECURE_LIVEKIT_URL_ENV = "SALEMX_CALL_SERVICE_ALLOW_INSECURE_LIVEKIT_URL"
ALLOCATION_STORE_ENV = "SALEMX_CALL_SERVICE_ALLOCATION_STORE"
ALLOCATION_STORE_URL_ENV = "SALEMX_CALL_SERVICE_ALLOCATION_STORE_URL"
ALLOW_MEMORY_ALLOCATION_STORE_ENV = "SALEMX_CALL_SERVICE_ALLOW_MEMORY_ALLOCATION_STORE"
RATE_LIMIT_STORE_ENV = "SALEMX_CALL_SERVICE_RATE_LIMIT_STORE"
RATE_LIMIT_STORE_URL_ENV = "SALEMX_CALL_SERVICE_RATE_LIMIT_STORE_URL"
RATE_LIMIT_PER_MINUTE_ENV = "SALEMX_CALL_SERVICE_RATE_LIMIT_PER_MINUTE"
LEGACY_RATE_LIMIT_PER_MINUTE_ENV = "RATE_LIMIT_PER_MINUTE"
ALLOW_MEMORY_RATE_LIMITER_ENV = "SALEMX_CALL_SERVICE_ALLOW_MEMORY_RATE_LIMITER"
STORAGE_KEY_SECRET_ENV = "SALEMX_CALL_SERVICE_STORAGE_KEY_SECRET"
NATIVE_AUDIO_ELIGIBILITY_ENABLED_ENV = "SALEMX_NATIVE_AUDIO_ELIGIBILITY_ENABLED"
LEGACY_NATIVE_AUDIO_ELIGIBILITY_ENABLED_ENV = "SALEMXNATIVE_AUDIO_ELIGIBILITY_ENABLED"
NATIVE_AUDIO_ELIGIBILITY_ALLOWED_USERS_ENV = "SALEMX_NATIVE_AUDIO_ELIGIBILITY_ALLOWED_USERS"
NATIVE_AUDIO_ELIGIBILITY_ALLOWED_HOMESERVERS_ENV = "SALEMX_NATIVE_AUDIO_ELIGIBILITY_ALLOWED_HOMESERVERS"
FOREGROUND_SIGNALING_DEV_INVITE_ENABLED_ENV = "SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED"
DIRECT_CALL_PENDING_STORE_ENABLED_ENV = "SALEMX_DIRECT_CALL_PENDING_STORE_ENABLED"
DIRECT_CALL_DATABASE_DSN_ENV = "SALEMX_DIRECT_CALL_DATABASE_DSN"
DIRECT_CALL_STORE_MASTER_KEY_B64_ENV = "SALEMX_DIRECT_CALL_STORE_MASTER_KEY_B64"

DEFAULT_SERVICE_MODE = "staging"
DEFAULT_ALLOCATION_STORE = "memory"
DEFAULT_RATE_LIMIT_STORE = "memory"
PLACEHOLDER_LIVEKIT_HOST = "local-smoke.livekit.invalid"
MIN_TOKEN_TTL_SECONDS = 30
MAX_TOKEN_TTL_SECONDS = 300
MIN_RATE_LIMIT_PER_MINUTE = 1
MAX_RATE_LIMIT_PER_MINUTE = 600


class ServiceMode(str, Enum):
    LOCAL_FAKE = "local_fake"
    STAGING = "staging"
    PRODUCTION = "production"


class AllocationStoreKind(str, Enum):
    MEMORY = "memory"
    REDIS = "redis"
    POSTGRES = "postgres"


class RateLimitStoreKind(str, Enum):
    MEMORY = "memory"
    REDIS = "redis"
    POSTGRES = "postgres"


class ServicePreflightReason(str, Enum):
    OK = "ok"
    FAKE_MODE_FORBIDDEN = "fakeModeForbidden"
    MISSING_SYNAPSE_CONFIG = "missingSynapseConfig"
    MISSING_LIVEKIT_CONFIG = "missingLiveKitConfig"
    INSECURE_LIVEKIT_URL = "insecureLiveKitURL"
    PLACEHOLDER_LIVEKIT_URL = "placeholderLiveKitURL"
    INVALID_TOKEN_TTL = "invalidTokenTTL"
    MISSING_ALLOCATION_STORE_CONFIG = "missingAllocationStoreConfig"
    MEMORY_ALLOCATION_STORE_FORBIDDEN = "memoryAllocationStoreForbidden"
    UNSUPPORTED_ALLOCATION_STORE = "unsupportedAllocationStore"
    ALLOCATION_STORE_UNAVAILABLE = "allocationStoreUnavailable"
    INVALID_RATE_LIMIT_CONFIG = "invalidRateLimitConfig"
    RATE_LIMIT_STORE_UNAVAILABLE = "rateLimitStoreUnavailable"
    MISSING_STORAGE_KEY_SECRET = "missingStorageKeySecret"
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
    livekit_room_provisioning_configured: bool
    token_ttl_bounded: bool
    allocation_ttl_bounded: bool
    allocation_store_configured: bool
    allocation_store_shared: bool
    allocation_store_connected: bool
    rate_limit_configured: bool
    rate_limit_shared: bool
    rate_limit_connected: bool
    storage_key_configured: bool
    native_audio_eligibility_configured: bool
    native_audio_eligibility_allowlist_configured: bool

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
            "liveKitRoomProvisioningConfigured": self.livekit_room_provisioning_configured,
            "tokenTTLBounded": self.token_ttl_bounded,
            "allocationTTLBounded": self.allocation_ttl_bounded,
            "allocationStoreConfigured": self.allocation_store_configured,
            "allocationStoreShared": self.allocation_store_shared,
            "allocationStoreConnected": self.allocation_store_connected,
            "rateLimitConfigured": self.rate_limit_configured,
            "rateLimitShared": self.rate_limit_shared,
            "rateLimitConnected": self.rate_limit_connected,
            "storageKeyConfigured": self.storage_key_configured,
            "nativeAudioEligibilityConfigured": self.native_audio_eligibility_configured,
            "nativeAudioEligibilityAllowlistConfigured": self.native_audio_eligibility_allowlist_configured,
        }


class ServicePreflightError(RuntimeError):
    def __init__(self, readiness: ServiceReadiness) -> None:
        self.readiness = readiness
        super().__init__(f"Call service preflight failed: {readiness.reason}")


class DirectCallStoreConfigurationError(RuntimeError):
    """Raised without including database or key material in the error."""


@dataclass(frozen=True)
class DirectCallStoreSettings:
    enabled: bool = False
    database_dsn: str | None = None
    master_key: bytes | None = None


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
    allocation_store: str = DEFAULT_ALLOCATION_STORE
    allocation_store_url: str | None = None
    rate_limit_store: str = DEFAULT_RATE_LIMIT_STORE
    rate_limit_store_url: str | None = None
    storage_key_secret: str | None = None
    native_audio_eligibility_enabled: bool = False
    native_audio_eligibility_allowed_users: tuple[str, ...] = ()
    native_audio_eligibility_allowed_homeservers: tuple[str, ...] = ()
    direct_call_pending_store_enabled: bool = False
    direct_call_database_dsn: str | None = None
    direct_call_store_master_key: bytes | None = None

    def __post_init__(self) -> None:
        _validate_direct_call_store_values(
            self.direct_call_pending_store_enabled,
            self.direct_call_database_dsn,
            self.direct_call_store_master_key,
        )

    @classmethod
    def from_env(cls) -> "ServiceConfig":
        validate_service_preflight(environ)
        direct_call_store_settings = direct_call_store_settings_from_env(environ)
        return cls(
            synapse_base_url=_required_env("SYNAPSE_BASE_URL"),
            synapse_admin_token=_required_env("SYNAPSE_ADMIN_TOKEN"),
            livekit_url=_required_env("LIVEKIT_URL"),
            livekit_api_key=_required_env("LIVEKIT_API_KEY"),
            livekit_api_secret=_required_env("LIVEKIT_API_SECRET"),
            token_ttl_seconds=_int_env("TOKEN_TTL_SECONDS", 120),
            allocation_ttl_seconds=_int_env("ALLOCATION_TTL_SECONDS", 300),
            rate_limit_per_minute=_rate_limit_per_minute_env(),
            log_level=environ.get("LOG_LEVEL", "INFO"),
            allocation_store=_env_value(environ, ALLOCATION_STORE_ENV) or DEFAULT_ALLOCATION_STORE,
            allocation_store_url=_env_value(environ, ALLOCATION_STORE_URL_ENV),
            rate_limit_store=_env_value(environ, RATE_LIMIT_STORE_ENV) or DEFAULT_RATE_LIMIT_STORE,
            rate_limit_store_url=_env_value(environ, RATE_LIMIT_STORE_URL_ENV),
            storage_key_secret=_env_value(environ, STORAGE_KEY_SECRET_ENV),
            native_audio_eligibility_enabled=_native_audio_eligibility_enabled(environ),
            native_audio_eligibility_allowed_users=_csv_env(NATIVE_AUDIO_ELIGIBILITY_ALLOWED_USERS_ENV),
            native_audio_eligibility_allowed_homeservers=_csv_env(NATIVE_AUDIO_ELIGIBILITY_ALLOWED_HOMESERVERS_ENV),
            direct_call_pending_store_enabled=direct_call_store_settings.enabled,
            direct_call_database_dsn=direct_call_store_settings.database_dsn,
            direct_call_store_master_key=direct_call_store_settings.master_key,
        )


def direct_call_store_settings_from_env(env: Mapping[str, str] = environ) -> DirectCallStoreSettings:
    enabled_value = _env_value(env, DIRECT_CALL_PENDING_STORE_ENABLED_ENV)
    if enabled_value not in {None, "0", "1"}:
        raise DirectCallStoreConfigurationError("Invalid direct-call pending store feature value.")
    if enabled_value != "1":
        return DirectCallStoreSettings()

    database_dsn = _env_value(env, DIRECT_CALL_DATABASE_DSN_ENV)
    master_key_b64 = _env_value(env, DIRECT_CALL_STORE_MASTER_KEY_B64_ENV)
    master_key = _decode_direct_call_store_master_key(master_key_b64)
    _validate_direct_call_store_values(True, database_dsn, master_key)
    return DirectCallStoreSettings(enabled=True, database_dsn=database_dsn, master_key=master_key)


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
            livekit_room_provisioning_configured=True,
            token_ttl_bounded=True,
            allocation_ttl_bounded=True,
            allocation_store_configured=True,
            allocation_store_shared=False,
            allocation_store_connected=True,
            rate_limit_configured=True,
            rate_limit_shared=False,
            rate_limit_connected=True,
            storage_key_configured=False,
            native_audio_eligibility_configured=True,
            native_audio_eligibility_allowlist_configured=True,
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
        allocation_ttl_value=_env_value(env, "ALLOCATION_TTL_SECONDS"),
        allocation_store_value=_env_value(env, ALLOCATION_STORE_ENV),
        allocation_store_url=_env_value(env, ALLOCATION_STORE_URL_ENV),
        rate_limit_store_value=_env_value(env, RATE_LIMIT_STORE_ENV),
        rate_limit_store_url=_env_value(env, RATE_LIMIT_STORE_URL_ENV),
        rate_limit_per_minute_value=_rate_limit_per_minute_value(env),
        storage_key_secret=_env_value(env, STORAGE_KEY_SECRET_ENV),
        native_audio_eligibility_enabled=_native_audio_eligibility_enabled(env),
        native_audio_eligibility_allowed_users=_csv_value(_env_value(env, NATIVE_AUDIO_ELIGIBILITY_ALLOWED_USERS_ENV)),
        native_audio_eligibility_allowed_homeservers=_csv_value(_env_value(env, NATIVE_AUDIO_ELIGIBILITY_ALLOWED_HOMESERVERS_ENV)),
        allow_insecure_livekit_url=_env_value(env, ALLOW_INSECURE_LIVEKIT_URL_ENV) == "1",
        allow_memory_allocation_store=_env_value(env, ALLOW_MEMORY_ALLOCATION_STORE_ENV) == "1",
        allow_memory_rate_limiter=_env_value(env, ALLOW_MEMORY_RATE_LIMITER_ENV) == "1",
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
        allocation_ttl_value=str(config.allocation_ttl_seconds),
        allocation_store_value=config.allocation_store,
        allocation_store_url=config.allocation_store_url,
        rate_limit_store_value=config.rate_limit_store,
        rate_limit_store_url=config.rate_limit_store_url,
        rate_limit_per_minute_value=str(config.rate_limit_per_minute),
        storage_key_secret=config.storage_key_secret,
        native_audio_eligibility_enabled=config.native_audio_eligibility_enabled,
        native_audio_eligibility_allowed_users=config.native_audio_eligibility_allowed_users,
        native_audio_eligibility_allowed_homeservers=config.native_audio_eligibility_allowed_homeservers,
        allow_insecure_livekit_url=_env_value(env, ALLOW_INSECURE_LIVEKIT_URL_ENV) == "1",
        allow_memory_allocation_store=_env_value(env, ALLOW_MEMORY_ALLOCATION_STORE_ENV) == "1",
        allow_memory_rate_limiter=_env_value(env, ALLOW_MEMORY_RATE_LIMITER_ENV) == "1",
    )


def validate_service_preflight(env: Mapping[str, str] = environ) -> ServiceReadiness:
    readiness = service_readiness_from_env(env)
    if not readiness.ready:
        raise ServicePreflightError(readiness)
    direct_call_store_settings_from_env(env)
    return readiness


def _decode_direct_call_store_master_key(value: str | None) -> bytes | None:
    if value is None:
        return None
    try:
        return b64decode(value, validate=True)
    except (BinasciiError, ValueError) as error:
        raise DirectCallStoreConfigurationError("Invalid direct-call store master key.") from error


def _validate_direct_call_store_values(enabled: bool,
                                       database_dsn: str | None,
                                       master_key: bytes | None) -> None:
    if not enabled:
        return
    parsed_dsn = urlparse(database_dsn or "")
    if parsed_dsn.scheme not in {"postgres", "postgresql"} or not parsed_dsn.hostname or parsed_dsn.path in {"", "/"}:
        raise DirectCallStoreConfigurationError("Invalid direct-call database configuration.")
    if master_key is None or len(master_key) != 32:
        raise DirectCallStoreConfigurationError("Invalid direct-call store master key.")


def _staging_readiness(mode: str,
                       fake_mode_enabled: bool,
                       synapse_base_url: str | None,
                       synapse_admin_token: str | None,
                       livekit_url: str | None,
                       livekit_api_key: str | None,
                       livekit_api_secret: str | None,
                       token_ttl_value: str | None,
                       allocation_ttl_value: str | None,
                       allocation_store_value: str | None,
                       allocation_store_url: str | None,
                       rate_limit_store_value: str | None,
                       rate_limit_store_url: str | None,
                       rate_limit_per_minute_value: str | None,
                       storage_key_secret: str | None,
                       native_audio_eligibility_enabled: bool,
                       native_audio_eligibility_allowed_users: tuple[str, ...],
                       native_audio_eligibility_allowed_homeservers: tuple[str, ...],
                       allow_insecure_livekit_url: bool,
                       allow_memory_allocation_store: bool,
                       allow_memory_rate_limiter: bool) -> ServiceReadiness:
    synapse_configured = bool(synapse_base_url and synapse_admin_token)
    livekit_configured = bool(livekit_url and livekit_api_key and livekit_api_secret)
    livekit_url_secure = _is_secure_livekit_url(livekit_url)
    livekit_url_placeholder = _is_placeholder_livekit_url(livekit_url)
    livekit_room_provisioning_configured = livekit_configured
    token_ttl_bounded = _token_ttl_bounded(token_ttl_value)
    allocation_ttl_bounded = _allocation_ttl_bounded(allocation_ttl_value, token_ttl_value)
    allocation_store_configured = _allocation_store_configured(allocation_store_value, allocation_store_url, allow_memory_allocation_store)
    allocation_store_shared = _allocation_store_shared(allocation_store_value)
    allocation_store_connected = _store_has_runtime_implementation(allocation_store_value, allow_memory_allocation_store)
    rate_limit_per_minute_bounded = _rate_limit_per_minute_bounded(rate_limit_per_minute_value)
    rate_limit_configured = _rate_limit_configured(rate_limit_store_value, rate_limit_store_url, allow_memory_rate_limiter)
    rate_limit_shared = _rate_limit_shared(rate_limit_store_value)
    rate_limit_connected = _store_has_runtime_implementation(rate_limit_store_value, allow_memory_rate_limiter)
    storage_key_configured = _storage_key_configured(
        allocation_store_value,
        rate_limit_store_value,
        storage_key_secret,
    )
    native_audio_eligibility_configured = native_audio_eligibility_enabled
    native_audio_eligibility_allowlist_configured = (
        native_audio_eligibility_enabled
        and len(native_audio_eligibility_allowed_users) > 0
    )

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
    elif not allocation_ttl_bounded:
        reason = ServicePreflightReason.INVALID_TOKEN_TTL
    elif allocation_store_value is None:
        reason = ServicePreflightReason.MISSING_ALLOCATION_STORE_CONFIG
    elif not _allocation_store_supported(allocation_store_value):
        reason = ServicePreflightReason.UNSUPPORTED_ALLOCATION_STORE
    elif _allocation_store_is_memory(allocation_store_value) and not allow_memory_allocation_store:
        reason = ServicePreflightReason.MEMORY_ALLOCATION_STORE_FORBIDDEN
    elif not allocation_store_configured:
        reason = ServicePreflightReason.MISSING_ALLOCATION_STORE_CONFIG
    elif not allocation_store_connected:
        reason = ServicePreflightReason.UNSUPPORTED_ALLOCATION_STORE
    elif not storage_key_configured:
        reason = ServicePreflightReason.MISSING_STORAGE_KEY_SECRET
    elif not rate_limit_per_minute_bounded:
        reason = ServicePreflightReason.INVALID_RATE_LIMIT_CONFIG
    elif not _rate_limit_store_supported(rate_limit_store_value):
        reason = ServicePreflightReason.INVALID_RATE_LIMIT_CONFIG
    elif _rate_limit_is_memory(rate_limit_store_value) and not allow_memory_rate_limiter:
        reason = ServicePreflightReason.INVALID_RATE_LIMIT_CONFIG
    elif not rate_limit_configured:
        reason = ServicePreflightReason.INVALID_RATE_LIMIT_CONFIG
    elif not rate_limit_connected:
        reason = ServicePreflightReason.INVALID_RATE_LIMIT_CONFIG
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
        livekit_room_provisioning_configured=livekit_room_provisioning_configured,
        token_ttl_bounded=token_ttl_bounded,
        allocation_ttl_bounded=allocation_ttl_bounded,
        allocation_store_configured=allocation_store_configured,
        allocation_store_shared=allocation_store_shared,
        allocation_store_connected=allocation_store_connected,
        rate_limit_configured=rate_limit_configured,
        rate_limit_shared=rate_limit_shared,
        rate_limit_connected=rate_limit_connected,
        storage_key_configured=storage_key_configured,
        native_audio_eligibility_configured=native_audio_eligibility_configured,
        native_audio_eligibility_allowlist_configured=native_audio_eligibility_allowlist_configured,
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
        livekit_room_provisioning_configured=False,
        token_ttl_bounded=True,
        allocation_ttl_bounded=True,
        allocation_store_configured=False,
        allocation_store_shared=False,
        allocation_store_connected=False,
        rate_limit_configured=False,
        rate_limit_shared=False,
        rate_limit_connected=False,
        storage_key_configured=False,
        native_audio_eligibility_configured=False,
        native_audio_eligibility_allowlist_configured=False,
    )


def _configured(env: Mapping[str, str], name: str) -> bool:
    return _env_value(env, name) is not None


def _native_audio_eligibility_enabled(env: Mapping[str, str]) -> bool:
    return (
        _env_value(env, NATIVE_AUDIO_ELIGIBILITY_ENABLED_ENV) == "1"
        or _env_value(env, LEGACY_NATIVE_AUDIO_ELIGIBILITY_ENABLED_ENV) == "1"
    )


def _env_value(env: Mapping[str, str], name: str) -> str | None:
    value = env.get(name)
    if value is None:
        return None
    value = value.strip()
    return value or None


def _csv_env(name: str) -> tuple[str, ...]:
    return _csv_value(_env_value(environ, name))


def _csv_value(value: str | None) -> tuple[str, ...]:
    if value is None:
        return ()
    return tuple(item.strip() for item in value.split(",") if item.strip())


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


def _allocation_ttl_bounded(allocation_ttl_value: str | None, token_ttl_value: str | None) -> bool:
    try:
        allocation_ttl_seconds = int(allocation_ttl_value or "300")
        token_ttl_seconds = int(token_ttl_value or "120")
    except ValueError:
        return False
    return allocation_ttl_seconds >= token_ttl_seconds


def _allocation_store_supported(value: str | None) -> bool:
    return value in {kind.value for kind in AllocationStoreKind}


def _allocation_store_is_memory(value: str | None) -> bool:
    return value == AllocationStoreKind.MEMORY.value


def _allocation_store_shared(value: str | None) -> bool:
    return value in {AllocationStoreKind.REDIS.value, AllocationStoreKind.POSTGRES.value}


def _allocation_store_configured(value: str | None, allocation_store_url: str | None, allow_memory_allocation_store: bool) -> bool:
    if value is None:
        return False
    if _allocation_store_is_memory(value):
        return allow_memory_allocation_store
    if _allocation_store_shared(value):
        return allocation_store_url is not None
    return False


def _store_has_runtime_implementation(value: str | None, allow_memory: bool) -> bool:
    if value == AllocationStoreKind.MEMORY.value:
        return allow_memory
    return value == AllocationStoreKind.REDIS.value


def _rate_limit_store_supported(value: str | None) -> bool:
    return value in {kind.value for kind in RateLimitStoreKind}


def _rate_limit_is_memory(value: str | None) -> bool:
    return value == RateLimitStoreKind.MEMORY.value


def _rate_limit_shared(value: str | None) -> bool:
    return value in {RateLimitStoreKind.REDIS.value, RateLimitStoreKind.POSTGRES.value}


def _rate_limit_configured(value: str | None, rate_limit_store_url: str | None, allow_memory_rate_limiter: bool) -> bool:
    if value is None:
        return False
    if _rate_limit_is_memory(value):
        return allow_memory_rate_limiter
    if _rate_limit_shared(value):
        return rate_limit_store_url is not None
    return False


def _rate_limit_per_minute_bounded(value: str | None) -> bool:
    if value is None:
        return False
    try:
        rate_limit_per_minute = int(value)
    except ValueError:
        return False
    return MIN_RATE_LIMIT_PER_MINUTE <= rate_limit_per_minute <= MAX_RATE_LIMIT_PER_MINUTE


def _rate_limit_per_minute_value(env: Mapping[str, str]) -> str | None:
    return _env_value(env, RATE_LIMIT_PER_MINUTE_ENV) or _env_value(env, LEGACY_RATE_LIMIT_PER_MINUTE_ENV) or "30"


def _rate_limit_per_minute_env() -> int:
    return int(_rate_limit_per_minute_value(environ) or "30")


def _storage_key_configured(allocation_store_value: str | None,
                            rate_limit_store_value: str | None,
                            storage_key_secret: str | None) -> bool:
    if allocation_store_value == AllocationStoreKind.REDIS.value or rate_limit_store_value == RateLimitStoreKind.REDIS.value:
        return storage_key_secret is not None
    return True


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
