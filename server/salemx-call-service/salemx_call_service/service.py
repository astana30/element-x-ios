"""Core direct-call token service orchestration."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

from .allocation import AllocationKey, AllocationMetadata, AllocationStoreProtocol
from .auth import MatrixAuthValidatorProtocol, bearer_token_from_authorization, validate_device_binding
from .dto import AllocationPayload, LiveKitPayload, TokenRequest, TokenResponse
from .errors import CallServiceError, rate_limited
from .livekit_tokens import LiveKitTokenIssuerProtocol
from .logging_utils import stable_redacted_id
from .rate_limiting import RateLimiterProtocol, RateLimitKey
from .room_validation import RoomValidatorProtocol

LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class DirectCallTokenService:
    auth_validator: MatrixAuthValidatorProtocol
    room_validator: RoomValidatorProtocol
    allocation_store: AllocationStoreProtocol
    rate_limiter: RateLimiterProtocol
    token_issuer: LiveKitTokenIssuerProtocol
    livekit_server_url: str
    allocation_ttl_seconds: int = 300
    rate_limit_per_minute: int = 30

    async def issue_token(self, authorization: str | None, payload: dict[str, Any]) -> TokenResponse:
        bearer_token = bearer_token_from_authorization(authorization)
        token_request = TokenRequest.from_mapping(payload)
        authenticated_user = await self.auth_validator.validate_bearer_token(bearer_token)
        validate_device_binding(token_request.device_id, authenticated_user.device_id)

        rate_limit_decision = await self.rate_limiter.check_and_record(
            RateLimitKey.keys_for(authenticated_user, token_request),
            self.rate_limit_per_minute,
        )
        if not rate_limit_decision.allowed:
            retry_after_ms = rate_limit_decision.retry_after_ms or 60000
            LOGGER.info("direct-call token request rate limited retry_after_ms=%d", retry_after_ms)
            raise rate_limited(retry_after_ms)

        await self.room_validator.validate_direct_call_room(authenticated_user, token_request)
        allocation = await self.allocation_store.create_or_reuse(
            AllocationKey.from_token_request(token_request),
            AllocationMetadata.from_token_request(token_request),
            self.allocation_ttl_seconds,
        )
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
