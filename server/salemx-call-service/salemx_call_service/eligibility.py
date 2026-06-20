"""Native audio internal-pilot eligibility policy boundary."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Protocol

from .auth import AuthenticatedUser
from .dto import TokenRequest
from .room_validation import RoomEligibility


class NativeAudioEligibilityState(str, Enum):
    ELIGIBLE = "eligible"
    UNAVAILABLE = "unavailable"


class NativeAudioEligibilityReason(str, Enum):
    ACCOUNT_NOT_ELIGIBLE = "accountNotEligible"
    PEER_NOT_ELIGIBLE = "peerNotEligible"
    ROOM_NOT_ELIGIBLE = "roomNotEligible"
    TRUST_NOT_READY = "trustNotReady"
    SERVICE_UNAVAILABLE = "serviceUnavailable"
    CAPABILITY_MISSING = "capabilityMissing"
    UNSUPPORTED_CLIENT = "unsupportedClient"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class NativeAudioEligibilityResult:
    state: NativeAudioEligibilityState
    reason: NativeAudioEligibilityReason | None
    account_eligible: bool
    peer_eligible: bool
    room_eligible: bool
    trust_ready: bool | None
    service_available: bool
    capability_present: bool
    client_supported: bool

    @property
    def eligible(self) -> bool:
        return self.state == NativeAudioEligibilityState.ELIGIBLE

    def as_dict(self) -> dict[str, object]:
        return {
            "state": self.state.value,
            "reason": self.reason.value if self.reason is not None else None,
            "account_eligible": self.account_eligible,
            "peer_eligible": self.peer_eligible,
            "room_eligible": self.room_eligible,
            "trust_ready": self.trust_ready,
            "service_available": self.service_available,
            "capability_present": self.capability_present,
            "client_supported": self.client_supported,
        }

    @classmethod
    def eligible_result(cls) -> "NativeAudioEligibilityResult":
        return cls(
            state=NativeAudioEligibilityState.ELIGIBLE,
            reason=None,
            account_eligible=True,
            peer_eligible=True,
            room_eligible=True,
            trust_ready=None,
            service_available=True,
            capability_present=True,
            client_supported=True,
        )

    @classmethod
    def unavailable(cls,
                    reason: NativeAudioEligibilityReason,
                    *,
                    account_eligible: bool = False,
                    peer_eligible: bool = False,
                    room_eligible: bool = False,
                    trust_ready: bool | None = None,
                    service_available: bool = True,
                    capability_present: bool = True,
                    client_supported: bool = True) -> "NativeAudioEligibilityResult":
        return cls(
            state=NativeAudioEligibilityState.UNAVAILABLE,
            reason=reason,
            account_eligible=account_eligible,
            peer_eligible=peer_eligible,
            room_eligible=room_eligible,
            trust_ready=trust_ready,
            service_available=service_available,
            capability_present=capability_present,
            client_supported=client_supported,
        )


class NativeAudioEligibilityPolicyProtocol(Protocol):
    async def evaluate(self,
                       authenticated_user: AuthenticatedUser,
                       token_request: TokenRequest,
                       room_eligibility: RoomEligibility) -> NativeAudioEligibilityResult:
        ...


class DisabledNativeAudioEligibilityPolicy:
    async def evaluate(self,
                       authenticated_user: AuthenticatedUser,
                       token_request: TokenRequest,
                       room_eligibility: RoomEligibility) -> NativeAudioEligibilityResult:
        return NativeAudioEligibilityResult.unavailable(
            NativeAudioEligibilityReason.CAPABILITY_MISSING,
            service_available=True,
            capability_present=False,
        )


class AlwaysEligibleNativeAudioEligibilityPolicy:
    async def evaluate(self,
                       authenticated_user: AuthenticatedUser,
                       token_request: TokenRequest,
                       room_eligibility: RoomEligibility) -> NativeAudioEligibilityResult:
        return NativeAudioEligibilityResult.eligible_result()


class StaticAllowlistNativeAudioEligibilityPolicy:
    def __init__(self,
                 allowed_user_ids: tuple[str, ...],
                 allowed_homeservers: tuple[str, ...] = ()) -> None:
        self._allowed_user_ids = frozenset(allowed_user_ids)
        self._allowed_homeservers = frozenset(allowed_homeservers)

    async def evaluate(self,
                       authenticated_user: AuthenticatedUser,
                       token_request: TokenRequest,
                       room_eligibility: RoomEligibility) -> NativeAudioEligibilityResult:
        room_eligible = _room_is_eligible(authenticated_user, token_request, room_eligibility)
        account_eligible = self._user_allowed(authenticated_user.user_id)
        peer_eligible = self._peer_allowed(token_request)

        if not account_eligible:
            return NativeAudioEligibilityResult.unavailable(
                NativeAudioEligibilityReason.ACCOUNT_NOT_ELIGIBLE,
                account_eligible=False,
                peer_eligible=peer_eligible,
                room_eligible=room_eligible,
            )

        if not peer_eligible:
            return NativeAudioEligibilityResult.unavailable(
                NativeAudioEligibilityReason.PEER_NOT_ELIGIBLE,
                account_eligible=True,
                peer_eligible=False,
                room_eligible=room_eligible,
            )

        if not room_eligible:
            return NativeAudioEligibilityResult.unavailable(
                NativeAudioEligibilityReason.ROOM_NOT_ELIGIBLE,
                account_eligible=True,
                peer_eligible=True,
                room_eligible=False,
            )

        return NativeAudioEligibilityResult.eligible_result()

    def _user_allowed(self, user_id: str) -> bool:
        if user_id not in self._allowed_user_ids:
            return False
        if not self._allowed_homeservers:
            return True
        return _homeserver_from_user_id(user_id) in self._allowed_homeservers

    def _peer_allowed(self, token_request: TokenRequest) -> bool:
        if token_request.direction == "incoming":
            if not self._allowed_homeservers:
                return True
            return _homeserver_from_user_id(token_request.peer_user_id) in self._allowed_homeservers
        return self._user_allowed(token_request.peer_user_id)


def eligibility_result_for_room_validation_error() -> NativeAudioEligibilityResult:
    return NativeAudioEligibilityResult.unavailable(
        NativeAudioEligibilityReason.ROOM_NOT_ELIGIBLE,
        account_eligible=False,
        peer_eligible=False,
        room_eligible=False,
        trust_ready=None,
        service_available=True,
        capability_present=True,
        client_supported=True,
    )


def eligibility_result_for_service_unavailable() -> NativeAudioEligibilityResult:
    return NativeAudioEligibilityResult.unavailable(
        NativeAudioEligibilityReason.SERVICE_UNAVAILABLE,
        account_eligible=False,
        peer_eligible=False,
        room_eligible=False,
        trust_ready=None,
        service_available=False,
        capability_present=True,
        client_supported=True,
    )


def _room_is_eligible(authenticated_user: AuthenticatedUser,
                      token_request: TokenRequest,
                      room_eligibility: RoomEligibility) -> bool:
    if not room_eligibility.is_encrypted:
        return False
    if len(room_eligibility.joined_user_ids) != 2:
        return False
    if authenticated_user.user_id not in room_eligibility.joined_user_ids:
        return False
    if token_request.peer_user_id not in room_eligibility.joined_user_ids:
        return False
    expected_peer = next(user_id for user_id in room_eligibility.joined_user_ids if user_id != authenticated_user.user_id)
    return expected_peer == token_request.peer_user_id


def _homeserver_from_user_id(user_id: str) -> str | None:
    if not user_id.startswith("@") or ":" not in user_id:
        return None
    return user_id.rsplit(":", 1)[1] or None
