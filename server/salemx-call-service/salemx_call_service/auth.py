"""Matrix authentication boundary for the direct-call token service."""

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from typing import Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .errors import MISSING_OR_INVALID_TOKEN, CallServiceError


@dataclass(frozen=True)
class AuthenticatedUser:
    user_id: str
    device_id: str | None = None


class MatrixAuthValidatorProtocol(Protocol):
    async def validate_bearer_token(self, bearer_token: str) -> AuthenticatedUser:
        ...


class SynapseMatrixAuthValidator:
    """Validates Matrix access tokens via Synapse whoami.

    The token is intentionally only passed as an Authorization header and must not be logged.
    """

    def __init__(self, synapse_base_url: str, timeout_seconds: float = 5.0) -> None:
        self._whoami_url = synapse_base_url.rstrip("/") + "/_matrix/client/v3/account/whoami"
        self._timeout_seconds = timeout_seconds

    async def validate_bearer_token(self, bearer_token: str) -> AuthenticatedUser:
        if not bearer_token:
            raise MISSING_OR_INVALID_TOKEN
        return await asyncio.to_thread(self._validate_sync, bearer_token)

    def _validate_sync(self, bearer_token: str) -> AuthenticatedUser:
        request = Request(self._whoami_url, method="GET", headers={"Authorization": f"Bearer {bearer_token}"})
        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:  # noqa: S310 - URL comes from operator config.
                payload = json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise MISSING_OR_INVALID_TOKEN from exc

        user_id = payload.get("user_id")
        if not isinstance(user_id, str) or not user_id:
            raise MISSING_OR_INVALID_TOKEN

        device_id = payload.get("device_id")
        return AuthenticatedUser(user_id=user_id, device_id=device_id if isinstance(device_id, str) and device_id else None)


def bearer_token_from_authorization(authorization: str | None) -> str:
    if authorization is None:
        raise MISSING_OR_INVALID_TOKEN

    prefix = "Bearer "
    if not authorization.startswith(prefix):
        raise MISSING_OR_INVALID_TOKEN

    token = authorization[len(prefix):]
    if token == "":
        raise MISSING_OR_INVALID_TOKEN
    return token


def validate_device_binding(request_device_id: str | None, authenticated_device_id: str | None) -> None:
    if request_device_id is None or authenticated_device_id is None:
        return
    if request_device_id != authenticated_device_id:
        raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Device does not match authenticated session.")
