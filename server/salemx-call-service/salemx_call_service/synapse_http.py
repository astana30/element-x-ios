"""Small redacted HTTP boundary for Synapse admin/service calls."""

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


@dataclass(frozen=True)
class SynapseHTTPResponse:
    status_code: int
    json_body: Any


class SynapseHTTPClientProtocol(Protocol):
    async def get_json(self, path: str) -> SynapseHTTPResponse:
        ...


class UrllibSynapseHTTPClient:
    """Minimal Synapse HTTP client.

    The admin token is only sent as an Authorization header and must never be logged.
    """

    def __init__(self, synapse_base_url: str, synapse_admin_token: str, timeout_seconds: float = 5.0) -> None:
        self._synapse_base_url = synapse_base_url.rstrip("/")
        self._synapse_admin_token = synapse_admin_token
        self._timeout_seconds = timeout_seconds

    async def get_json(self, path: str) -> SynapseHTTPResponse:
        return await asyncio.to_thread(self._get_json_sync, path)

    def _get_json_sync(self, path: str) -> SynapseHTTPResponse:
        request = Request(
            self._synapse_base_url + path,
            method="GET",
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {self._synapse_admin_token}",
            },
        )
        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:  # noqa: S310 - URL comes from operator config.
                return SynapseHTTPResponse(status_code=response.status, json_body=_decode_json(response.read()))
        except HTTPError as error:
            return SynapseHTTPResponse(status_code=error.code, json_body=_decode_json(error.read()))
        except (URLError, TimeoutError, OSError):
            return SynapseHTTPResponse(status_code=0, json_body=None)


def _decode_json(data: bytes) -> Any:
    if not data:
        return None
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
