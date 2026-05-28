"""Core direct-call token service orchestration."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field, replace
from typing import Any

from .allocation import AllocationKey, AllocationMetadata, AllocationStoreProtocol
from .auth import AuthenticatedUser, MatrixAuthValidatorProtocol, bearer_token_from_authorization, validate_device_binding
from .dto import AllocationPayload, EligibilityRequest, LiveKitPayload, TokenDiagnosticsPayload, TokenRequest, TokenResponse
from .eligibility import (
    DisabledNativeAudioEligibilityPolicy,
    NativeAudioEligibilityPolicyProtocol,
    NativeAudioEligibilityReason,
    NativeAudioEligibilityResult,
    eligibility_result_for_room_validation_error,
    eligibility_result_for_service_unavailable,
)
from .errors import CallServiceError, native_audio_not_eligible, rate_limited
from .livekit_rooms import LiveKitRoomProvisionerProtocol
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
    room_provisioner: LiveKitRoomProvisionerProtocol
    token_issuer: LiveKitTokenIssuerProtocol
    livekit_server_url: str
    allocation_ttl_seconds: int = 300
    rate_limit_per_minute: int = 30
    eligibility_policy: NativeAudioEligibilityPolicyProtocol = field(default_factory=DisabledNativeAudioEligibilityPolicy)

    async def evaluate_eligibility(self, authorization: str | None, payload: dict[str, Any]) -> NativeAudioEligibilityResult:
        bearer_token = bearer_token_from_authorization(authorization)
        eligibility_request = EligibilityRequest.from_mapping(payload)
        authenticated_user = await self.auth_validator.validate_bearer_token(bearer_token)
        validate_device_binding(eligibility_request.device_id, authenticated_user.device_id)
        token_request = eligibility_request.as_room_validation_request()

        try:
            room_eligibility = await self.room_validator.validate_direct_call_room(authenticated_user, token_request)
        except CallServiceError as error:
            result = _eligibility_result_for_room_error(error)
            _log_eligibility_result(result, authenticated_user, token_request)
            return result

        result = await self.eligibility_policy.evaluate(authenticated_user, token_request, room_eligibility)
        _log_eligibility_result(result, authenticated_user, token_request)
        return result

    async def issue_token(self, authorization: str | None, payload: dict[str, Any]) -> TokenResponse:
        diagnostics = TokenDiagnosticsPayload(token_request_seen=True)
        try:
            bearer_token = bearer_token_from_authorization(authorization)
            token_request = TokenRequest.from_mapping(payload)
            authenticated_user = await self.auth_validator.validate_bearer_token(bearer_token)
            validate_device_binding(token_request.device_id, authenticated_user.device_id)
            room_eligibility = await self.room_validator.validate_direct_call_room(authenticated_user, token_request)
            eligibility = await self.eligibility_policy.evaluate(authenticated_user, token_request, room_eligibility)
            diagnostics = replace(diagnostics, eligibility_allowed=eligibility.eligible)
            if not eligibility.eligible:
                LOGGER.info(
                    "direct-call token request eligibility rejected reason=%s room_hash=%s user_hash=%s",
                    eligibility.reason.value if eligibility.reason is not None else "unknown",
                    stable_redacted_id(token_request.room_id),
                    stable_redacted_id(authenticated_user.user_id),
                )
                raise native_audio_not_eligible()

            rate_limit_decision = await self.rate_limiter.check_and_record(
                RateLimitKey.keys_for(authenticated_user, token_request),
                self.rate_limit_per_minute,
            )
            if not rate_limit_decision.allowed:
                retry_after_ms = rate_limit_decision.retry_after_ms or 60000
                diagnostics = replace(diagnostics, rate_limited=True)
                LOGGER.info("direct-call token request rate limited retry_after_ms=%d", retry_after_ms)
                raise rate_limited(retry_after_ms)

            diagnostics = replace(diagnostics, allocation_attempted=True)
            allocation = await self.allocation_store.create_or_reuse(
                AllocationKey.from_token_request(token_request),
                AllocationMetadata.from_token_request(token_request),
                self.allocation_ttl_seconds,
            )
            diagnostics = replace(diagnostics, livekit_room_precreate_attempted=True)
            await self.room_provisioner.ensure_room(allocation.livekit_room_name)
            issued_token = await self.token_issuer.issue_token(authenticated_user, token_request, allocation)
            diagnostics = replace(diagnostics,
                                  token_status=200,
                                  token_errcode=None,
                                  token_reason="issued",
                                  token_issued=True)
            _log_token_diagnostics(diagnostics)

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
                diagnostics=diagnostics,
            )
        except CallServiceError as error:
            diagnostics = _diagnostics_for_error(error, diagnostics)
            _log_token_diagnostics(diagnostics)
            raise error.with_diagnostics(diagnostics.as_dict()) from error


def error_response(error: CallServiceError) -> tuple[int, dict[str, Any]]:
    LOGGER.info("direct-call request failed errcode=%s status=%s", error.errcode, error.status_code)
    return error.status_code, error.as_dict()


def _diagnostics_for_error(error: CallServiceError, diagnostics: TokenDiagnosticsPayload) -> TokenDiagnosticsPayload:
    return replace(
        diagnostics,
        token_status=error.status_code,
        token_errcode=error.errcode,
        token_reason=_token_reason_for_error(error, diagnostics),
        rate_limited=diagnostics.rate_limited or error.errcode == "M_DIRECT_CALL_RATE_LIMITED",
        token_issued=False,
    )


def _token_reason_for_error(error: CallServiceError, diagnostics: TokenDiagnosticsPayload) -> str:
    if error.errcode == "M_DIRECT_CALL_NOT_ELIGIBLE":
        return "eligibilityRejected"
    if error.errcode == "M_DIRECT_CALL_RATE_LIMITED":
        return "rateLimited"
    if error.errcode == "M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE":
        return "rateLimitStoreUnavailable"
    if error.errcode == "M_DIRECT_CALL_ALLOCATION_FAILED":
        return "allocationFailed"
    if error.errcode == "M_DIRECT_CALL_LIVEKIT_ROOM_UNAVAILABLE":
        return "liveKitRoomPrecreateFailed"
    if error.errcode == "M_DIRECT_CALL_UNSUPPORTED_INTENT":
        return "unsupportedIntent"
    if error.errcode in {"M_NOT_JOINED", "M_DIRECT_CALL_PEER_MISMATCH", "M_ROOM_NOT_ENCRYPTED", "M_DIRECT_CALL_NOT_1_TO_1"}:
        return "roomValidationFailed"
    if error.errcode in {"M_UNKNOWN_TOKEN", "M_FORBIDDEN"}:
        return "authRejected"
    if error.status_code == 400:
        return "badRequest"
    if diagnostics.livekit_room_precreate_attempted and not diagnostics.token_issued:
        return "tokenSigningFailed"
    if error.status_code >= 500:
        return "serviceUnavailable"
    return "unknown"


def _log_token_diagnostics(diagnostics: TokenDiagnosticsPayload) -> None:
    LOGGER.info(
        "direct-call token diagnostics token_request_seen=%s token_status=%s token_errcode=%s token_reason=%s "
        "eligibility_allowed=%s rate_limited=%s allocation_attempted=%s livekit_room_precreate_attempted=%s token_issued=%s",
        diagnostics.token_request_seen,
        diagnostics.token_status if diagnostics.token_status is not None else "none",
        diagnostics.token_errcode if diagnostics.token_errcode is not None else "none",
        diagnostics.token_reason,
        diagnostics.eligibility_allowed,
        diagnostics.rate_limited,
        diagnostics.allocation_attempted,
        diagnostics.livekit_room_precreate_attempted,
        diagnostics.token_issued,
    )


def _eligibility_result_for_room_error(error: CallServiceError) -> NativeAudioEligibilityResult:
    if error.errcode in {"M_NOT_JOINED", "M_DIRECT_CALL_PEER_MISMATCH", "M_ROOM_NOT_ENCRYPTED", "M_DIRECT_CALL_NOT_1_TO_1"}:
        return eligibility_result_for_room_validation_error()
    if error.status_code >= 500 or error.errcode in {"M_UNKNOWN", "M_FORBIDDEN"}:
        return eligibility_result_for_service_unavailable()
    return NativeAudioEligibilityResult.unavailable(NativeAudioEligibilityReason.UNKNOWN)


def _log_eligibility_result(result: NativeAudioEligibilityResult,
                            authenticated_user: AuthenticatedUser,
                            token_request: TokenRequest) -> None:
    LOGGER.info(
        "direct-call eligibility result=%s reason=%s room_hash=%s user_hash=%s",
        result.state.value,
        result.reason.value if result.reason is not None else "none",
        stable_redacted_id(token_request.room_id),
        stable_redacted_id(authenticated_user.user_id),
    )
