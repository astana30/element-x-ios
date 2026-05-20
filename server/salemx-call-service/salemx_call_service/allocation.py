"""Opaque LiveKit room allocation store."""

from __future__ import annotations

import asyncio
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol

from .dto import TokenRequest
from .errors import allocation_failed


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
