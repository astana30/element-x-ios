"""Room eligibility validation boundary."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.parse import quote

from .auth import AuthenticatedUser
from .dto import TokenRequest
from .errors import CallServiceError, not_joined, not_one_to_one, peer_mismatch, room_not_encrypted
from .logging_utils import stable_redacted_id
from .synapse_http import SynapseHTTPClientProtocol, UrllibSynapseHTTPClient

LOGGER = logging.getLogger(__name__)


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

    Uses Synapse admin/service endpoints and keeps all request/response bodies out of logs.
    """

    def __init__(self, synapse_base_url: str, synapse_admin_token: str, http_client: SynapseHTTPClientProtocol | None = None) -> None:
        self._http_client = http_client or UrllibSynapseHTTPClient(synapse_base_url, synapse_admin_token)

    async def validate_direct_call_room(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest) -> RoomEligibility:
        started_at = time.monotonic()
        room_hash = stable_redacted_id(token_request.room_id)
        user_hash = stable_redacted_id(authenticated_user.user_id)

        try:
            joined_user_ids = await self._joined_members(token_request.room_id)
            is_encrypted = await self._room_has_encryption_state(token_request.room_id)
            eligibility = RoomEligibility(joined_user_ids=tuple(sorted(joined_user_ids)), is_encrypted=is_encrypted)
            self._validate_eligibility(authenticated_user, token_request, eligibility)
            self._log_result("ok", room_hash, user_hash, started_at)
            return eligibility
        except CallServiceError as error:
            self._log_result(error.errcode, room_hash, user_hash, started_at)
            raise

    async def _joined_members(self, room_id: str) -> set[str]:
        response = await self._http_client.get_json(f"/_synapse/admin/v1/rooms/{quote(room_id, safe='')}/members")
        if response.status_code == 403:
            raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Unable to validate room membership.")
        if response.status_code == 404:
            raise CallServiceError(status_code=404, errcode="M_UNKNOWN", error="Unable to validate room membership.")
        if response.status_code < 200 or response.status_code >= 300:
            raise CallServiceError(status_code=502, errcode="M_UNKNOWN", error="Unable to validate room membership.")

        joined_user_ids = _extract_joined_user_ids(response.json_body)
        if joined_user_ids is None:
            raise CallServiceError(status_code=502, errcode="M_UNKNOWN", error="Unable to validate room membership.")
        return joined_user_ids

    async def _room_has_encryption_state(self, room_id: str) -> bool:
        response = await self._http_client.get_json(f"/_synapse/admin/v1/rooms/{quote(room_id, safe='')}/state")
        if response.status_code == 403:
            raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Unable to validate room state.")
        if response.status_code == 404:
            raise room_not_encrypted()
        if response.status_code < 200 or response.status_code >= 300:
            raise CallServiceError(status_code=502, errcode="M_UNKNOWN", error="Unable to validate room state.")

        has_encryption = _contains_encryption_state(response.json_body)
        if has_encryption is None:
            raise CallServiceError(status_code=502, errcode="M_UNKNOWN", error="Unable to validate room state.")
        return has_encryption

    def _validate_eligibility(self, authenticated_user: AuthenticatedUser, token_request: TokenRequest, eligibility: RoomEligibility) -> None:
        if authenticated_user.user_id not in eligibility.joined_user_ids:
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

    @staticmethod
    def _log_result(result: str, room_hash: str, user_hash: str, started_at: float) -> None:
        LOGGER.info(
            "synapse direct-call room validation result=%s room_hash=%s user_hash=%s latency_ms=%d",
            result,
            room_hash,
            user_hash,
            int((time.monotonic() - started_at) * 1000),
        )


def _extract_joined_user_ids(body: Any) -> set[str] | None:
    if not isinstance(body, dict):
        return None

    members = body.get("members")
    if isinstance(members, list):
        return _extract_member_list(members)

    chunk = body.get("chunk")
    if isinstance(chunk, list):
        return _extract_member_list(chunk)

    joined = body.get("joined")
    if isinstance(joined, dict):
        return {user_id for user_id in joined if isinstance(user_id, str) and user_id}

    return None


def _extract_member_list(members: list[Any]) -> set[str] | None:
    joined_user_ids: set[str] = set()

    for member in members:
        if isinstance(member, str) and member:
            joined_user_ids.add(member)
            continue

        if not isinstance(member, dict):
            return None

        membership = member.get("membership", "join")
        user_id = member.get("user_id") or member.get("user_id_or_localpart")
        if membership == "join" and isinstance(user_id, str) and user_id:
            joined_user_ids.add(user_id)

    return joined_user_ids


def _contains_encryption_state(body: Any) -> bool | None:
    if not isinstance(body, dict):
        return None

    if body.get("type") == "m.room.encryption":
        return True

    state = body.get("state")
    if isinstance(state, list):
        return any(_state_event_type(event) == "m.room.encryption" for event in state)

    events = body.get("events")
    if isinstance(events, list):
        return any(_state_event_type(event) == "m.room.encryption" for event in events)

    return False


def _state_event_type(event: Any) -> str | None:
    if not isinstance(event, dict):
        return None
    event_type = event.get("type")
    return event_type if isinstance(event_type, str) else None
