"""Room eligibility validation boundary."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from .auth import AuthenticatedUser
from .dto import TokenRequest
from .errors import CallServiceError, not_joined, not_one_to_one, peer_mismatch, room_not_encrypted


@dataclass(frozen=True)
class RoomEligibility:
    joined_user_ids: tuple[str, ...]
    is_encrypted: bool


class RoomValidatorProtocol(Protocol):
    async def validate_direct_call_room(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest) -> RoomEligibility:
        ...


class InMemoryRoomValidator:
    """Test/development room validator with explicit room fixtures."""

    def __init__(self, rooms: dict[str, RoomEligibility]) -> None:
        self._rooms = rooms

    async def validate_direct_call_room(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest) -> RoomEligibility:
        eligibility = self._rooms.get(token_request.room_id)
        if eligibility is None or authenticated_user.user_id not in eligibility.joined_user_ids:
            raise not_joined()

        if token_request.peer_user_id not in eligibility.joined_user_ids:
            raise peer_mismatch()

        if not eligibility.is_encrypted:
            raise room_not_encrypted()

        if len(eligibility.joined_user_ids) != 2:
            raise not_one_to_one()

        expected_peer = next(user_id for user_id in eligibility.joined_user_ids if user_id != authenticated_user.user_id)
        if expected_peer != token_request.peer_user_id:
            raise peer_mismatch()

        return eligibility


class SynapseRoomValidator:
    """Production boundary for Synapse room membership/state validation.

    The skeleton intentionally keeps this unimplemented because Synapse deployments vary in
    admin API shape and auth. Production integration should fetch joined members and
    m.room.encryption state through a service credential without logging raw room content.
    """

    def __init__(self, synapse_base_url: str, synapse_admin_token: str) -> None:
        self._synapse_base_url = synapse_base_url.rstrip("/")
        self._synapse_admin_token = synapse_admin_token

    async def validate_direct_call_room(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest) -> RoomEligibility:
        raise CallServiceError(
            status_code=501,
            errcode="M_UNKNOWN",
            error="Room eligibility validation is not implemented for this deployment.",
        )
