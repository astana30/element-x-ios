"""Redacted rate limiting boundary for direct-call token issuance."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Protocol

from .auth import AuthenticatedUser
from .dto import TokenRequest
from .errors import rate_limit_store_unavailable
from .logging_utils import stable_redacted_id


class RateLimitReason(str, Enum):
    OK = "ok"
    RATE_LIMITED = "rateLimited"
    STORE_UNAVAILABLE = "rateLimitStoreUnavailable"


@dataclass(frozen=True)
class RateLimitKey:
    value: str

    @classmethod
    def keys_for(cls, authenticated_user: AuthenticatedUser, token_request: TokenRequest) -> tuple["RateLimitKey", ...]:
        keys = [
            cls(f"user:{stable_redacted_id(authenticated_user.user_id)}"),
            cls(f"room-call:{stable_redacted_id(token_request.room_id)}:{stable_redacted_id(token_request.call_id)}:{token_request.intent}"),
        ]
        device_id = authenticated_user.device_id or token_request.device_id
        if device_id is not None:
            keys.append(cls(f"device:{stable_redacted_id(authenticated_user.user_id)}:{stable_redacted_id(device_id)}"))
        return tuple(keys)


@dataclass(frozen=True)
class RateLimitDecision:
    allowed: bool
    reason: str
    retry_after_ms: int | None = None

    @classmethod
    def allowed_decision(cls) -> "RateLimitDecision":
        return cls(allowed=True, reason=RateLimitReason.OK.value)

    @classmethod
    def limited(cls, retry_after_ms: int) -> "RateLimitDecision":
        return cls(allowed=False, reason=RateLimitReason.RATE_LIMITED.value, retry_after_ms=retry_after_ms)


class RateLimiterProtocol(Protocol):
    async def check_and_record(self,
                               rate_limit_keys: tuple[RateLimitKey, ...],
                               limit_per_minute: int,
                               now: datetime | None = None) -> RateLimitDecision:
        ...


class InMemoryRateLimiter:
    """In-memory limiter for local fake mode and unit tests only."""

    def __init__(self) -> None:
        self._requests: dict[str, list[datetime]] = {}
        self._lock = asyncio.Lock()

    async def check_and_record(self,
                               rate_limit_keys: tuple[RateLimitKey, ...],
                               limit_per_minute: int,
                               now: datetime | None = None) -> RateLimitDecision:
        if limit_per_minute <= 0:
            raise rate_limit_store_unavailable()

        now = now or datetime.now(timezone.utc)
        window_started_at = now - timedelta(minutes=1)

        async with self._lock:
            for rate_limit_key in rate_limit_keys:
                self._requests[rate_limit_key.value] = [
                    request_time for request_time in self._requests.get(rate_limit_key.value, []) if request_time > window_started_at
                ]

            retry_after_ms = _retry_after_ms(self._requests, rate_limit_keys, limit_per_minute, now)
            if retry_after_ms is not None:
                return RateLimitDecision.limited(retry_after_ms)

            for rate_limit_key in rate_limit_keys:
                self._requests.setdefault(rate_limit_key.value, []).append(now)
            return RateLimitDecision.allowed_decision()


class SharedRateLimiterSkeleton:
    """Fail-closed placeholder for future shared rate limiter stores."""

    def __init__(self, store_kind: str) -> None:
        self.store_kind = store_kind

    async def check_and_record(self,
                               rate_limit_keys: tuple[RateLimitKey, ...],
                               limit_per_minute: int,
                               now: datetime | None = None) -> RateLimitDecision:
        raise rate_limit_store_unavailable()


def _retry_after_ms(requests: dict[str, list[datetime]],
                    rate_limit_keys: tuple[RateLimitKey, ...],
                    limit_per_minute: int,
                    now: datetime) -> int | None:
    retry_after_values: list[int] = []
    for rate_limit_key in rate_limit_keys:
        request_times = requests.get(rate_limit_key.value, [])
        if len(request_times) < limit_per_minute:
            continue
        oldest_request = min(request_times)
        retry_at = oldest_request + timedelta(minutes=1)
        retry_after_ms = max(1, int((retry_at - now).total_seconds() * 1000))
        retry_after_values.append(retry_after_ms)

    if not retry_after_values:
        return None
    return max(retry_after_values)
