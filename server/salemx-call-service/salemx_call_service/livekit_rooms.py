"""LiveKit room provisioning boundary."""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol
from urllib import error as urllib_error
from urllib import request as urllib_request
from urllib.parse import urlparse, urlunparse

from .errors import livekit_room_unavailable
from .livekit_tokens import encode_livekit_jwt
from .logging_utils import stable_redacted_id

LOGGER = logging.getLogger(__name__)

DEFAULT_ROOM_EMPTY_TIMEOUT_SECONDS = 300
DEFAULT_ROOM_DEPARTURE_TIMEOUT_SECONDS = 20
ROOM_PROVISION_TOKEN_TTL_SECONDS = 90


class LiveKitRoomProvisionerProtocol(Protocol):
    async def ensure_room(self, room_name: str) -> None:
        ...


class NoopLiveKitRoomProvisioner:
    async def ensure_room(self, room_name: str) -> None:
        return None


@dataclass(frozen=True)
class LiveKitRoomServiceHTTPResponse:
    status_code: int
    body: str


class LiveKitRoomServiceHTTPClientProtocol(Protocol):
    def create_room(self,
                    endpoint_url: str,
                    authorization: str,
                    payload: dict[str, object],
                    timeout_seconds: float) -> LiveKitRoomServiceHTTPResponse:
        ...


class LiveKitRoomServiceHTTPClient:
    def create_room(self,
                    endpoint_url: str,
                    authorization: str,
                    payload: dict[str, object],
                    timeout_seconds: float) -> LiveKitRoomServiceHTTPResponse:
        request = urllib_request.Request(
            endpoint_url,
            data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
            headers={
                "Authorization": authorization,
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib_request.urlopen(request, timeout=timeout_seconds) as response:
                body = response.read().decode("utf-8", errors="replace")
                return LiveKitRoomServiceHTTPResponse(status_code=response.status, body=body)
        except urllib_error.HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            return LiveKitRoomServiceHTTPResponse(status_code=error.code, body=body)
        except urllib_error.URLError as error:
            raise livekit_room_unavailable() from error


class LiveKitRoomServiceProvisioner:
    """Creates allocated LiveKit rooms server-side before participant tokens are issued."""

    def __init__(self,
                 livekit_url: str,
                 api_key: str,
                 api_secret: str,
                 empty_timeout_seconds: int = DEFAULT_ROOM_EMPTY_TIMEOUT_SECONDS,
                 departure_timeout_seconds: int = DEFAULT_ROOM_DEPARTURE_TIMEOUT_SECONDS,
                 http_client: LiveKitRoomServiceHTTPClientProtocol | None = None,
                 request_timeout_seconds: float = 5.0) -> None:
        self._endpoint_url = _room_service_endpoint_url(livekit_url)
        self._api_key = api_key
        self._api_secret = api_secret.encode("utf-8")
        self._empty_timeout_seconds = max(1, empty_timeout_seconds)
        self._departure_timeout_seconds = max(1, departure_timeout_seconds)
        self._http_client = http_client or LiveKitRoomServiceHTTPClient()
        self._request_timeout_seconds = request_timeout_seconds

    async def ensure_room(self, room_name: str) -> None:
        if not room_name.strip():
            raise livekit_room_unavailable()

        payload = {
            "name": room_name,
            "empty_timeout": self._empty_timeout_seconds,
            "departure_timeout": self._departure_timeout_seconds,
        }
        response = await asyncio.to_thread(
            self._http_client.create_room,
            self._endpoint_url,
            f"Bearer {self._room_create_token()}",
            payload,
            self._request_timeout_seconds,
        )

        if response.status_code == 200:
            LOGGER.info("ensured LiveKit room room_hash=%s result=created", stable_redacted_id(room_name))
            return None

        reason = _redacted_twirp_reason(response)
        if _is_already_exists(response, reason):
            LOGGER.info("ensured LiveKit room room_hash=%s result=alreadyExists", stable_redacted_id(room_name))
            return None

        LOGGER.warning(
            "LiveKit room provision failed room_hash=%s status=%d reason=%s",
            stable_redacted_id(room_name),
            response.status_code,
            reason,
        )
        raise livekit_room_unavailable()

    def _room_create_token(self) -> str:
        now = datetime.now(timezone.utc)
        claims = {
            "iss": self._api_key,
            "sub": "salemx-call-service-room-provisioner",
            "nbf": int(now.timestamp()),
            "exp": int((now + timedelta(seconds=ROOM_PROVISION_TOKEN_TTL_SECONDS)).timestamp()),
            "video": {
                "roomCreate": True,
            },
        }
        return encode_livekit_jwt(claims, self._api_secret)


def _room_service_endpoint_url(livekit_url: str) -> str:
    parsed = urlparse(livekit_url)
    if parsed.scheme == "wss":
        scheme = "https"
    elif parsed.scheme == "ws":
        scheme = "http"
    else:
        scheme = parsed.scheme

    base_path = parsed.path.rstrip("/")
    endpoint_path = f"{base_path}/twirp/livekit.RoomService/CreateRoom"
    return urlunparse((scheme, parsed.netloc, endpoint_path, "", "", ""))


def _redacted_twirp_reason(response: LiveKitRoomServiceHTTPResponse) -> str:
    try:
        payload = json.loads(response.body)
    except json.JSONDecodeError:
        return "httpError"
    if isinstance(payload, dict):
        code = payload.get("code")
        if isinstance(code, str) and code:
            return code
    return "httpError"


def _is_already_exists(response: LiveKitRoomServiceHTTPResponse, reason: str) -> bool:
    if response.status_code == 409:
        return True
    if reason in {"already_exists", "already-exists"}:
        return True
    return "already exists" in response.body.lower()
