"""Environment configuration for the SalemX direct-call token service."""

from __future__ import annotations

from dataclasses import dataclass
from os import environ


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


def _required_env(name: str) -> str:
    value = environ.get(name)
    if value is None or value == "":
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _int_env(name: str, default: int) -> int:
    value = environ.get(name)
    if value is None or value == "":
        return default
    return int(value)
