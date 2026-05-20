"""Opaque LiveKit room allocation store."""

from __future__ import annotations

import asyncio
import json
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol

from .dto import TokenRequest
from .errors import CallServiceError, allocation_failed
from .storage_keys import StorageKeyHasher


@dataclass(frozen=True)
class Allocation:
    id: str
    call_id: str
    room_id: str
    intent: str
    livekit_room_name: str
    expires_at: datetime


@dataclass(frozen=True)
class AllocationKey:
    room_id: str
    call_id: str
    intent: str

    @classmethod
    def from_token_request(cls, token_request: TokenRequest) -> "AllocationKey":
        return cls(
            room_id=token_request.room_id,
            call_id=token_request.call_id,
            intent=token_request.intent,
        )

    def as_store_key(self) -> tuple[str, str, str]:
        return self.room_id, self.call_id, self.intent


@dataclass(frozen=True)
class AllocationMetadata:
    call_id: str
    room_id: str
    intent: str

    @classmethod
    def from_token_request(cls, token_request: TokenRequest) -> "AllocationMetadata":
        return cls(
            call_id=token_request.call_id,
            room_id=token_request.room_id,
            intent=token_request.intent,
        )


class AllocationStoreProtocol(Protocol):
    async def create_or_reuse(self, allocation_key: AllocationKey, metadata: AllocationMetadata, ttl_seconds: int) -> Allocation:
        ...

    async def get(self, allocation_key: AllocationKey) -> Allocation | None:
        ...


class RedisAllocationClientProtocol(Protocol):
    async def set_if_absent_with_ttl(self, key: str, value: str, ttl_seconds: int) -> bool:
        ...

    async def get(self, key: str) -> str | None:
        ...


class InMemoryAllocationStore:
    """In-memory allocation store for the skeleton.

    Production should replace this with a shared transactional store so callers and callees
    converge on the same LiveKit room across service instances.
    """

    def __init__(self, allocation_ttl_seconds: int = 300) -> None:
        self._allocation_ttl = timedelta(seconds=allocation_ttl_seconds)
        self._allocations: dict[tuple[str, str, str], Allocation] = {}
        self._lock = asyncio.Lock()

    async def allocation_for(self, token_request: TokenRequest) -> Allocation:
        return await self.create_or_reuse(
            AllocationKey.from_token_request(token_request),
            AllocationMetadata.from_token_request(token_request),
            int(self._allocation_ttl.total_seconds()),
        )

    async def create_or_reuse(self, allocation_key: AllocationKey, metadata: AllocationMetadata, ttl_seconds: int) -> Allocation:
        store_key = allocation_key.as_store_key()
        now = datetime.now(timezone.utc)

        async with self._lock:
            existing = self._allocations.get(store_key)
            if existing is not None and existing.expires_at > now:
                return existing

            allocation_id = secrets.token_urlsafe(24)
            allocation = Allocation(
                id=allocation_id,
                call_id=metadata.call_id,
                room_id=metadata.room_id,
                intent=metadata.intent,
                livekit_room_name=f"salemx-dc-{allocation_id}",
                expires_at=now + timedelta(seconds=ttl_seconds),
            )
            self._allocations[store_key] = allocation
            return allocation

    async def get(self, allocation_key: AllocationKey) -> Allocation | None:
        now = datetime.now(timezone.utc)
        async with self._lock:
            existing = self._allocations.get(allocation_key.as_store_key())
            if existing is None or existing.expires_at <= now:
                return None
            return existing

    async def cleanup_expired(self) -> None:
        now = datetime.now(timezone.utc)
        async with self._lock:
            self._allocations = {key: allocation for key, allocation in self._allocations.items() if allocation.expires_at > now}


class RedisAllocationClient:
    """Small adapter over redis.asyncio to keep Redis imports out of tests."""

    def __init__(self, redis_client: object) -> None:
        self._redis_client = redis_client

    async def set_if_absent_with_ttl(self, key: str, value: str, ttl_seconds: int) -> bool:
        result = await self._redis_client.set(key, value, ex=ttl_seconds, nx=True)  # type: ignore[attr-defined]
        return bool(result)

    async def get(self, key: str) -> str | None:
        value = await self._redis_client.get(key)  # type: ignore[attr-defined]
        if value is None:
            return None
        if isinstance(value, bytes):
            return value.decode("utf-8")
        return str(value)


class RedisAllocationStore:
    """Redis-backed shared allocation store for staging.

    Redis keys are HMAC-derived and values intentionally avoid raw room IDs or peer IDs.
    """

    _KEY_PREFIX = "salemx:dc:alloc:v1"

    def __init__(self,
                 redis_client: RedisAllocationClientProtocol,
                 storage_key_hasher: StorageKeyHasher,
                 max_create_retries: int = 3) -> None:
        self._redis_client = redis_client
        self._storage_key_hasher = storage_key_hasher
        self._max_create_retries = max(1, max_create_retries)

    async def create_or_reuse(self, allocation_key: AllocationKey, metadata: AllocationMetadata, ttl_seconds: int) -> Allocation:
        if ttl_seconds <= 0:
            raise allocation_failed()

        redis_key = self._redis_key(allocation_key)
        for _ in range(self._max_create_retries):
            allocation = self._new_allocation(metadata, ttl_seconds)
            try:
                created = await self._redis_client.set_if_absent_with_ttl(
                    redis_key,
                    _encode_redis_allocation(allocation),
                    ttl_seconds,
                )
                if created:
                    return allocation

                existing = await self._existing_allocation(redis_key, allocation_key)
                if existing is not None:
                    return existing
            except Exception as error:
                if isinstance(error, CallServiceError):
                    raise
                raise allocation_failed() from error

        raise allocation_failed()

    async def get(self, allocation_key: AllocationKey) -> Allocation | None:
        try:
            return await self._existing_allocation(self._redis_key(allocation_key), allocation_key)
        except Exception as error:
            if isinstance(error, CallServiceError):
                raise
            raise allocation_failed() from error

    def _redis_key(self, allocation_key: AllocationKey) -> str:
        return self._storage_key_hasher.redis_key(
            self._KEY_PREFIX,
            allocation_key.room_id,
            allocation_key.call_id,
            allocation_key.intent,
        )

    def _new_allocation(self, metadata: AllocationMetadata, ttl_seconds: int) -> Allocation:
        now = datetime.now(timezone.utc)
        expires_at_ms = int((now + timedelta(seconds=ttl_seconds)).timestamp() * 1000)
        allocation_id = secrets.token_urlsafe(24)
        return Allocation(
            id=allocation_id,
            call_id=metadata.call_id,
            room_id=metadata.room_id,
            intent=metadata.intent,
            livekit_room_name=f"salemx-dc-{allocation_id}",
            expires_at=datetime.fromtimestamp(expires_at_ms / 1000, tz=timezone.utc),
        )

    async def _existing_allocation(self, redis_key: str, allocation_key: AllocationKey) -> Allocation | None:
        raw_allocation = await self._redis_client.get(redis_key)
        if raw_allocation is None:
            return None
        return _decode_redis_allocation(raw_allocation, allocation_key)


class SharedAllocationStoreSkeleton:
    """Fail-closed placeholder for future shared allocation stores.

    Staging can validate that a shared store kind is declared without silently using
    process memory. Token issuance remains blocked until a real Redis/Postgres
    implementation replaces this skeleton.
    """

    def __init__(self, store_kind: str) -> None:
        self.store_kind = store_kind

    async def create_or_reuse(self, allocation_key: AllocationKey, metadata: AllocationMetadata, ttl_seconds: int) -> Allocation:
        raise allocation_failed()

    async def get(self, allocation_key: AllocationKey) -> Allocation | None:
        return None


def _encode_redis_allocation(allocation: Allocation) -> str:
    return json.dumps({
        "version": 1,
        "allocation_id": allocation.id,
        "livekit_room_name": allocation.livekit_room_name,
        "intent": allocation.intent,
        "expires_at_ms": int(allocation.expires_at.timestamp() * 1000),
    }, sort_keys=True, separators=(",", ":"))


def _decode_redis_allocation(raw_allocation: str, allocation_key: AllocationKey) -> Allocation:
    try:
        payload = json.loads(raw_allocation)
        if not isinstance(payload, dict) or payload.get("version") != 1:
            raise ValueError("Unsupported allocation payload.")
        allocation_id = _required_payload_string(payload, "allocation_id")
        livekit_room_name = _required_payload_string(payload, "livekit_room_name")
        intent = _required_payload_string(payload, "intent")
        expires_at_ms = payload.get("expires_at_ms")
        if not isinstance(expires_at_ms, int):
            raise ValueError("Missing allocation expiry.")
        if intent != allocation_key.intent:
            raise ValueError("Allocation intent mismatch.")
    except Exception as error:
        raise allocation_failed() from error

    expires_at = datetime.fromtimestamp(expires_at_ms / 1000, tz=timezone.utc)
    if expires_at <= datetime.now(timezone.utc):
        raise allocation_failed()

    return Allocation(
        id=allocation_id,
        call_id=allocation_key.call_id,
        room_id=allocation_key.room_id,
        intent=intent,
        livekit_room_name=livekit_room_name,
        expires_at=expires_at,
    )


def _required_payload_string(payload: dict[str, object], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f"Missing allocation {key}.")
    return value
