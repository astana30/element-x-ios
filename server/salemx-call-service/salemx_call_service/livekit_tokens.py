"""LiveKit participant-token issuing boundary."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol

from .allocation import Allocation
from .auth import AuthenticatedUser
from .dto import TokenRequest


@dataclass(frozen=True)
class LiveKitGrant:
    room_join: bool
    room: str
    can_publish: bool
    can_subscribe: bool
    can_publish_data: bool

    def as_livekit_claim(self) -> dict[str, object]:
        return {
            "roomJoin": self.room_join,
            "room": self.room,
            "canPublish": self.can_publish,
            "canSubscribe": self.can_subscribe,
            "canPublishData": self.can_publish_data,
        }


@dataclass(frozen=True)
class IssuedLiveKitToken:
    participant_token: str
    expires_at: datetime
    grant: LiveKitGrant


class LiveKitTokenIssuerProtocol(Protocol):
    async def issue_token(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest, allocation: Allocation) -> IssuedLiveKitToken:
        ...


class LiveKitJWTTokenIssuer:
    """Minimal LiveKit-compatible HS256 JWT issuer.

    The API secret remains server-side only. Returned participant tokens must not be logged.
    """

    def __init__(self,
                 api_key: str,
                 api_secret: str,
                 token_ttl_seconds: int = 120,
                 include_issued_at: bool = False,
                 include_device_in_identity: bool = False) -> None:
        self._api_key = api_key
        self._api_secret = api_secret.encode("utf-8")
        self._token_ttl_seconds = token_ttl_seconds
        self._include_issued_at = include_issued_at
        self._include_device_in_identity = include_device_in_identity

    async def issue_token(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest, allocation: Allocation) -> IssuedLiveKitToken:
        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(seconds=self._token_ttl_seconds)
        grant = LiveKitGrant(
            room_join=True,
            room=allocation.livekit_room_name,
            can_publish=True,
            can_subscribe=True,
            can_publish_data=False,
        )
        claims = {
            "iss": self._api_key,
            "sub": self._participant_identity(allocation, authenticated_user, token_request),
            "nbf": int(now.timestamp()),
            "exp": int(expires_at.timestamp()),
            "video": grant.as_livekit_claim(),
        }
        if self._include_issued_at:
            claims["iat"] = int(now.timestamp())

        token = encode_livekit_jwt(claims, self._api_secret)
        return IssuedLiveKitToken(participant_token=token, expires_at=expires_at, grant=grant)

    def _participant_identity(self, allocation: Allocation, authenticated_user: AuthenticatedUser, token_request: TokenRequest) -> str:
        if not self._include_device_in_identity:
            digest = hashlib.sha256(f"{allocation.id}:{authenticated_user.user_id}".encode("utf-8")).hexdigest()[:24]
            return f"salemx-dc-{digest}"

        device_id = authenticated_user.device_id or token_request.device_id or "unknown-device"
        digest = hashlib.sha256(f"{allocation.id}:{authenticated_user.user_id}:{device_id}:{token_request.direction}".encode("utf-8")).hexdigest()[:24]
        return f"salemx-dc-{digest}"


def _base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def encode_livekit_jwt(claims: dict[str, object], secret: bytes) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    header_part = _base64url(json.dumps(header, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    claims_part = _base64url(json.dumps(claims, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signing_input = f"{header_part}.{claims_part}".encode("ascii")
    signature = hmac.new(secret, signing_input, hashlib.sha256).digest()
    return f"{header_part}.{claims_part}.{_base64url(signature)}"
