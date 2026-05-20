"""Redacted rate limiting boundary for direct-call token issuance."""

from __future__ import annotations

import asyncio
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Protocol

from .auth import AuthenticatedUser
from .dto import TokenRequest
from .errors import CallServiceError, rate_limit_store_unavailable
from .logging_utils import stable_redacted_id
from .storage_keys import StorageKeyHasher


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


class RedisRateLimitClientProtocol(Protocol):
    async def check_and_record(self,
                               keys: tuple[str, ...],
                               now_ms: int,
                               window_ms: int,
                               limit_per_minute: int,
                               member: str) -> tuple[bool, int]:
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


class RedisRateLimitClient:
    """Small Lua-backed adapter over redis.asyncio."""

    _CHECK_AND_RECORD_SCRIPT = """
local now_ms = tonumber(ARGV[1])
local window_ms = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])
local member = ARGV[4]
local retry_after_ms = 0

for index, key in ipairs(KEYS) do
  redis.call('ZREMRANGEBYSCORE', key, '-inf', now_ms - window_ms)
  local count = redis.call('ZCARD', key)
  if count >= limit then
    local oldest = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
    if oldest[2] ~= nil then
      local key_retry_after = (tonumber(oldest[2]) + window_ms) - now_ms
      if key_retry_after > retry_after_ms then
        retry_after_ms = key_retry_after
      end
    end
  end
end

if retry_after_ms > 0 then
  return {0, retry_after_ms}
end

for index, key in ipairs(KEYS) do
  redis.call('ZADD', key, now_ms, member .. ':' .. index)
  redis.call('PEXPIRE', key, window_ms)
end

return {1, 0}
"""

    def __init__(self, redis_client: object) -> None:
        self._redis_client = redis_client

    async def check_and_record(self,
                               keys: tuple[str, ...],
                               now_ms: int,
                               window_ms: int,
                               limit_per_minute: int,
                               member: str) -> tuple[bool, int]:
        result = await self._redis_client.eval(  # type: ignore[attr-defined]
            self._CHECK_AND_RECORD_SCRIPT,
            len(keys),
            *keys,
            now_ms,
            window_ms,
            limit_per_minute,
            member,
        )
        if not isinstance(result, (list, tuple)) or len(result) != 2:
            raise rate_limit_store_unavailable()
        allowed = int(result[0]) == 1
        retry_after_ms = max(0, int(result[1]))
        return allowed, retry_after_ms


class RedisRateLimiter:
    """Redis-backed shared rate limiter for staging."""

    _KEY_PREFIX = "salemx:dc:rl:v1"
    _WINDOW_MS = 60_000

    def __init__(self,
                 redis_client: RedisRateLimitClientProtocol,
                 storage_key_hasher: StorageKeyHasher) -> None:
        self._redis_client = redis_client
        self._storage_key_hasher = storage_key_hasher

    async def check_and_record(self,
                               rate_limit_keys: tuple[RateLimitKey, ...],
                               limit_per_minute: int,
                               now: datetime | None = None) -> RateLimitDecision:
        if limit_per_minute <= 0:
            raise rate_limit_store_unavailable()
        if not rate_limit_keys:
            raise rate_limit_store_unavailable()

        now = now or datetime.now(timezone.utc)
        now_ms = int(now.timestamp() * 1000)
        redis_keys = tuple(self._redis_key(rate_limit_key) for rate_limit_key in rate_limit_keys)
        member = secrets.token_urlsafe(18)

        try:
            allowed, retry_after_ms = await self._redis_client.check_and_record(
                redis_keys,
                now_ms,
                self._WINDOW_MS,
                limit_per_minute,
                member,
            )
        except Exception as error:
            if isinstance(error, CallServiceError):
                raise
            raise rate_limit_store_unavailable() from error

        if allowed:
            return RateLimitDecision.allowed_decision()
        return RateLimitDecision.limited(max(1, retry_after_ms))

    def _redis_key(self, rate_limit_key: RateLimitKey) -> str:
        scope = rate_limit_key.value.split(":", 1)[0]
        return self._storage_key_hasher.redis_key(f"{self._KEY_PREFIX}:{scope}", rate_limit_key.value)


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
