"""Explicit local-only fake service wiring for smoke tests."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from os import environ
from typing import Any

from .allocation import InMemoryAllocationStore
from .auth import AuthenticatedUser, MatrixAuthValidatorProtocol
from .dto import TokenRequest
from .errors import CallServiceError
from .livekit_tokens import IssuedLiveKitToken, LiveKitGrant, LiveKitTokenIssuerProtocol
from .room_validation import RoomEligibility, RoomValidatorProtocol
from .service import DirectCallTokenService

FAKE_MODE_ENV = "SALEMX_CALL_SERVICE_FAKE_MODE"
FAKE_LIVEKIT_URL_ENV = "LIVEKIT_URL"
DEFAULT_FAKE_LIVEKIT_URL = "wss://local-smoke.livekit.invalid"
DIRECT_CALL_CAPABILITY_NAME = "kz.salemx.direct_call.native"
DIRECT_CALL_KEY_ENVELOPE = "matrix_sdk_direct_call_media_key_envelope_v1"


class FakeLocalAuthValidator(MatrixAuthValidatorProtocol):
    async def validate_bearer_token(self, bearer_token: str) -> AuthenticatedUser:
        if not bearer_token.strip():
            raise CallServiceError(status_code=401, errcode="M_UNKNOWN_TOKEN", error="Missing or invalid Matrix access token.")
        return AuthenticatedUser("@local-smoke-user:local.test")


class FakeLocalRoomValidator(RoomValidatorProtocol):
    async def validate_direct_call_room(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest) -> RoomEligibility:
        if token_request.peer_user_id == authenticated_user.user_id:
            raise CallServiceError(status_code=403, errcode="M_DIRECT_CALL_PEER_MISMATCH", error="Peer user does not match the direct-call room.")
        return RoomEligibility((authenticated_user.user_id, token_request.peer_user_id), True)


class FakeLocalLiveKitTokenIssuer(LiveKitTokenIssuerProtocol):
    async def issue_token(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest, allocation: Any) -> IssuedLiveKitToken:
        grant = LiveKitGrant(room_join=True,
                             room=allocation.livekit_room_name,
                             can_publish=True,
                             can_subscribe=True,
                             can_publish_data=False)
        return IssuedLiveKitToken(participant_token="local-smoke-participant-token",
                                  expires_at=datetime.now(timezone.utc) + timedelta(seconds=120),
                                  grant=grant)


def fake_mode_enabled() -> bool:
    return environ.get(FAKE_MODE_ENV) == "1"


def fake_livekit_url() -> str:
    configured_url = environ.get(FAKE_LIVEKIT_URL_ENV, "").strip()
    return configured_url or DEFAULT_FAKE_LIVEKIT_URL


def make_fake_local_service() -> DirectCallTokenService:
    return DirectCallTokenService(
        auth_validator=FakeLocalAuthValidator(),
        room_validator=FakeLocalRoomValidator(),
        allocation_store=InMemoryAllocationStore(allocation_ttl_seconds=300),
        token_issuer=FakeLocalLiveKitTokenIssuer(),
        livekit_server_url=fake_livekit_url(),
    )


def make_fake_capabilities_payload(token_endpoint_path: str) -> dict[str, Any]:
    return {
        "capabilities": {
            DIRECT_CALL_CAPABILITY_NAME: {
                "enabled": True,
                "version": 1,
                "token_endpoint": token_endpoint_path,
                "intents": ["audio"],
                "media_transport": "livekit",
                "e2ee_required": True,
                "key_envelope": DIRECT_CALL_KEY_ENVELOPE,
            }
        }
    }
