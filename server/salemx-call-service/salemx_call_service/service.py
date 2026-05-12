"""Core direct-call token service orchestration."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

from .allocation import AllocationStoreProtocol
from .auth import MatrixAuthValidatorProtocol, bearer_token_from_authorization, validate_device_binding
from .dto import AllocationPayload, LiveKitPayload, TokenRequest, TokenResponse
from .errors import CallServiceError
from .livekit_tokens import LiveKitTokenIssuerProtocol
from .logging_utils import stable_redacted_id
from .room_validation import RoomValidatorProtocol

LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class DirectCallTokenService:
    auth_validator: MatrixAuthValidatorProtocol
    room_validator: RoomValidatorProtocol
    allocation_store: AllocationStoreProtocol
    token_issuer: LiveKitTokenIssuerProtocol
    livekit_server_url: str

    async def issue_token(self, authorization: str | None, payload: dict[str, Any]) -> TokenResponse:
        bearer_token = bearer_token_from_authorization(authorization)
        token_request = TokenRequest.from_mapping(payload)
        authenticated_user = await self.auth_validator.validate_bearer_token(bearer_token)
        validate_device_binding(token_request.device_id, authenticated_user.device_id)

        await self.room_validator.validate_direct_call_room(authenticated_user, token_request)
        allocation = await self.allocation_store.allocation_for(token_request)
        issued_token = await self.token_issuer.issue_token(authenticated_user, token_request, allocation)

        LOGGER.info(
            "issued direct-call LiveKit token allocation_id=%s call_id=%s room_hash=%s user_hash=%s intent=%s direction=%s",
            allocation.id,
            token_request.call_id,
            stable_redacted_id(token_request.room_id),
            stable_redacted_id(authenticated_user.user_id),
            token_request.intent,
            token_request.direction,
        )

        return TokenResponse(
            livekit=LiveKitPayload(
                server_url=self.livekit_server_url,
                room_name=allocation.livekit_room_name,
                participant_token=issued_token.participant_token,
                expires_at=issued_token.expires_at,
            ),
            allocation=AllocationPayload(
                id=allocation.id,
                call_id=allocation.call_id,
                intent=allocation.intent,
            ),
        )


def error_response(error: CallServiceError) -> tuple[int, dict[str, Any]]:
    LOGGER.info("direct-call token request failed errcode=%s status=%s", error.errcode, error.status_code)
    return error.status_code, error.as_dict()
