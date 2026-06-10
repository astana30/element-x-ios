"""Foreground-only direct-call signaling boundary."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass
from typing import Any, Callable

from .auth import AuthenticatedUser
from .errors import bad_request
from .logging_utils import stable_redacted_id

LOGGER = logging.getLogger(__name__)

FOREGROUND_CALL_INVITE_TYPE = "foreground.call.invite"
FOREGROUND_CALL_READY_TYPE = "foreground.ready"
MAX_CALL_HANDLE_LENGTH = 128
MAX_DISPLAY_LABEL_LENGTH = 120
DEFAULT_QUEUE_SIZE = 16


@dataclass(frozen=True)
class ForegroundCallInvitePayload:
    call_handle: str
    call_kind: str
    created_at_ms: int
    expires_at_ms: int
    display_label: str
    version: int = 1
    type: str = FOREGROUND_CALL_INVITE_TYPE

    @classmethod
    def from_mapping(cls, payload: dict[str, Any]) -> "ForegroundCallInvitePayload":
        event_type = _required_string(payload, "type")
        if event_type != FOREGROUND_CALL_INVITE_TYPE:
            raise bad_request(error="Unsupported foreground signaling event type.")

        version = payload.get("version")
        if version != 1:
            raise bad_request(errcode="M_UNRECOGNIZED", error="Unsupported foreground signaling version.")

        call_handle = _required_string(payload, "call_handle", max_length=MAX_CALL_HANDLE_LENGTH)
        if not _is_safe_opaque_handle(call_handle):
            raise bad_request(error="Invalid foreground call handle.")

        call_kind = _required_string(payload, "call_kind")
        if call_kind != "audio":
            raise bad_request(error="Unsupported foreground call kind.")

        created_at_ms = _required_int(payload, "created_at_ms")
        expires_at_ms = _required_int(payload, "expires_at_ms")
        if expires_at_ms <= created_at_ms:
            raise bad_request(error="Invalid foreground call expiry.")

        display_label = _required_string(payload, "display_label", max_length=MAX_DISPLAY_LABEL_LENGTH)

        return cls(
            call_handle=call_handle,
            call_kind=call_kind,
            created_at_ms=created_at_ms,
            expires_at_ms=expires_at_ms,
            display_label=display_label,
        )

    def as_dict(self) -> dict[str, object]:
        return {
            "type": self.type,
            "version": self.version,
            "call_handle": self.call_handle,
            "call_kind": self.call_kind,
            "created_at_ms": self.created_at_ms,
            "expires_at_ms": self.expires_at_ms,
            "display_label": self.display_label,
        }

    def is_expired(self, now_ms: int) -> bool:
        return now_ms >= self.expires_at_ms


@dataclass(frozen=True)
class ForegroundCallInviteRequest:
    recipient: str
    recipient_device: str | None
    invite: ForegroundCallInvitePayload

    @classmethod
    def from_mapping(cls, payload: dict[str, Any]) -> "ForegroundCallInviteRequest":
        recipient = _required_string(payload, "recipient")
        recipient_device = _optional_string(payload, "recipient_device")
        return cls(
            recipient=recipient,
            recipient_device=recipient_device,
            invite=ForegroundCallInvitePayload.from_mapping(payload),
        )


@dataclass(frozen=True)
class ForegroundCallSignalingPublishResult:
    subscriber_available: bool
    delivered: bool
    dropped: bool

    def as_dict(self) -> dict[str, object]:
        return {
            "version": 1,
            "subscriber_available": self.subscriber_available,
            "delivered": self.delivered,
            "dropped": self.dropped,
        }


@dataclass(frozen=True)
class ForegroundCallSignalingDiagnostics:
    subscriber_count: int
    delivered_invite_count: int
    dropped_invite_count: int
    latest_result: str

    def as_dict(self) -> dict[str, object]:
        return {
            "subscriber_count": self.subscriber_count,
            "delivered_invite_count": self.delivered_invite_count,
            "dropped_invite_count": self.dropped_invite_count,
            "latest_result": self.latest_result,
        }


@dataclass(frozen=True)
class ForegroundCallSignalingSubscription:
    account_key: str
    device_key: str | None
    queue: asyncio.Queue[ForegroundCallInvitePayload]

    async def next_event(self) -> ForegroundCallInvitePayload:
        return await self.queue.get()


class ForegroundCallSignalingService:
    def __init__(self, queue_size: int = DEFAULT_QUEUE_SIZE, clock_ms: Callable[[], int] | None = None) -> None:
        self._queue_size = queue_size
        self._clock_ms = clock_ms or _current_time_ms
        self._subscriptions: dict[tuple[str, str | None], list[ForegroundCallSignalingSubscription]] = {}
        self._delivered_invite_count = 0
        self._dropped_invite_count = 0
        self._latest_result = "idle"

    @property
    def diagnostics(self) -> ForegroundCallSignalingDiagnostics:
        return ForegroundCallSignalingDiagnostics(
            subscriber_count=sum(len(subscriptions) for subscriptions in self._subscriptions.values()),
            delivered_invite_count=self._delivered_invite_count,
            dropped_invite_count=self._dropped_invite_count,
            latest_result=self._latest_result,
        )

    def subscribe(self, authenticated_user: AuthenticatedUser) -> ForegroundCallSignalingSubscription:
        key = _subscription_key(authenticated_user.user_id, authenticated_user.device_id)
        subscription = ForegroundCallSignalingSubscription(
            account_key=key[0],
            device_key=key[1],
            queue=asyncio.Queue(maxsize=self._queue_size),
        )
        self._subscriptions.setdefault(key, []).append(subscription)
        self._latest_result = "subscribed"
        LOGGER.info(
            "foreground signaling subscribed account_hash=%s device_bound=%s subscriber_count=%d",
            stable_redacted_id(authenticated_user.user_id),
            authenticated_user.device_id is not None,
            self.diagnostics.subscriber_count,
        )
        return subscription

    def unsubscribe(self, subscription: ForegroundCallSignalingSubscription) -> None:
        key = _subscription_key(subscription.account_key, subscription.device_key)
        subscriptions = self._subscriptions.get(key, [])
        self._subscriptions[key] = [current for current in subscriptions if current is not subscription]
        if not self._subscriptions[key]:
            self._subscriptions.pop(key, None)
        self._latest_result = "unsubscribed"
        LOGGER.info(
            "foreground signaling unsubscribed account_hash=%s device_bound=%s subscriber_count=%d",
            stable_redacted_id(subscription.account_key),
            subscription.device_key is not None,
            self.diagnostics.subscriber_count,
        )

    def publish_invite(self, invite_request: ForegroundCallInviteRequest) -> ForegroundCallSignalingPublishResult:
        subscriptions = self._target_subscriptions(invite_request.recipient, invite_request.recipient_device)
        subscriber_available = bool(subscriptions)
        if invite_request.invite.is_expired(self._clock_ms()):
            self._dropped_invite_count += 1
            self._latest_result = "stale"
            LOGGER.info(
                "foreground signaling invite stale subscriber_available=%s delivered=False dropped=True call_kind=%s",
                subscriber_available,
                invite_request.invite.call_kind,
            )
            return ForegroundCallSignalingPublishResult(
                subscriber_available=subscriber_available,
                delivered=False,
                dropped=True,
            )

        delivered = 0
        dropped = 0
        for subscription in subscriptions:
            try:
                subscription.queue.put_nowait(invite_request.invite)
                delivered += 1
            except asyncio.QueueFull:
                dropped += 1

        self._delivered_invite_count += delivered
        self._dropped_invite_count += dropped
        self._latest_result = "delivered" if delivered > 0 else "dropped" if dropped > 0 else "unavailable"

        LOGGER.info(
            "foreground signaling invite handled subscriber_available=%s delivered=%s dropped=%s call_kind=%s",
            subscriber_available,
            delivered > 0,
            dropped > 0,
            invite_request.invite.call_kind,
        )
        return ForegroundCallSignalingPublishResult(
            subscriber_available=subscriber_available,
            delivered=delivered > 0,
            dropped=dropped > 0,
        )

    def _target_subscriptions(self, recipient: str, recipient_device: str | None) -> list[ForegroundCallSignalingSubscription]:
        if recipient_device is not None:
            return list(self._subscriptions.get(_subscription_key(recipient, recipient_device), []))

        subscriptions: list[ForegroundCallSignalingSubscription] = []
        for (account_key, _), current_subscriptions in self._subscriptions.items():
            if account_key == recipient:
                subscriptions.extend(current_subscriptions)
        return subscriptions


def foreground_ready_sse_event() -> str:
    return _sse_event(FOREGROUND_CALL_READY_TYPE, {"ready": True})


def foreground_invite_sse_event(invite: ForegroundCallInvitePayload) -> str:
    return _sse_event(FOREGROUND_CALL_INVITE_TYPE, invite.as_dict())


def _sse_event(event_type: str, data: dict[str, object]) -> str:
    return f"event: {event_type}\ndata: {json.dumps(data, separators=(',', ':'))}\n\n"


def _subscription_key(account_key: str, device_key: str | None) -> tuple[str, str | None]:
    return account_key, device_key


def _required_string(payload: dict[str, Any], key: str, max_length: int | None = None) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise bad_request(error=f"Missing or invalid {key}.")
    normalized = value.strip()
    if max_length is not None and len(normalized) > max_length:
        raise bad_request(error=f"Invalid {key}.")
    return normalized


def _optional_string(payload: dict[str, Any], key: str) -> str | None:
    value = payload.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value.strip():
        raise bad_request(error=f"Invalid {key}.")
    return value.strip()


def _required_int(payload: dict[str, Any], key: str) -> int:
    value = payload.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise bad_request(error=f"Missing or invalid {key}.")
    return value


def _is_safe_opaque_handle(value: str) -> bool:
    return all(character.isalnum() or character in "-_." for character in value)


def _current_time_ms() -> int:
    return int(time.time() * 1000)
