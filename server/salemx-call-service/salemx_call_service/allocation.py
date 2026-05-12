"""Opaque LiveKit room allocation store."""

from __future__ import annotations

import asyncio
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol

from .dto import TokenRequest


@dataclass(frozen=True)
class Allocation:
    id: str
    call_id: str
    room_id: str
    intent: str
    livekit_room_name: str
    expires_at: datetime


class AllocationStoreProtocol(Protocol):
    async def allocation_for(self, token_request: TokenRequest) -> Allocation:
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
        key = (token_request.room_id, token_request.call_id, token_request.intent)
        now = datetime.now(timezone.utc)

        async with self._lock:
            existing = self._allocations.get(key)
            if existing is not None and existing.expires_at > now:
                return existing

            allocation_id = secrets.token_urlsafe(24)
            allocation = Allocation(
                id=allocation_id,
                call_id=token_request.call_id,
                room_id=token_request.room_id,
                intent=token_request.intent,
                livekit_room_name=f"salemx-dc-{allocation_id}",
                expires_at=now + self._allocation_ttl,
            )
            self._allocations[key] = allocation
            return allocation

    async def cleanup_expired(self) -> None:
        now = datetime.now(timezone.utc)
        async with self._lock:
            self._allocations = {key: allocation for key, allocation in self._allocations.items() if allocation.expires_at > now}
