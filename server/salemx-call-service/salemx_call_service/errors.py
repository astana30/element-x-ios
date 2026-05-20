"""Matrix-style error helpers for the SalemX direct-call token service."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class CallServiceError(Exception):
    status_code: int
    errcode: str
    error: str
    retry_after_ms: int | None = None

    def as_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "errcode": self.errcode,
            "error": self.error,
        }
        if self.retry_after_ms is not None:
            payload["retry_after_ms"] = self.retry_after_ms
        return payload


MISSING_OR_INVALID_TOKEN = CallServiceError(
    status_code=401,
    errcode="M_UNKNOWN_TOKEN",
    error="Missing or invalid Matrix access token.",
)


def bad_request(errcode: str = "M_UNKNOWN", error: str = "Invalid request.") -> CallServiceError:
    return CallServiceError(status_code=400, errcode=errcode, error=error)


def unsupported_intent() -> CallServiceError:
    return CallServiceError(
        status_code=400,
        errcode="M_DIRECT_CALL_UNSUPPORTED_INTENT",
        error="Only audio direct calls are supported.",
    )


def not_joined() -> CallServiceError:
    return CallServiceError(status_code=403, errcode="M_NOT_JOINED", error="User is not joined to the room.")


def peer_mismatch() -> CallServiceError:
    return CallServiceError(
        status_code=403,
        errcode="M_DIRECT_CALL_PEER_MISMATCH",
        error="Peer is not eligible for this direct-call room.",
    )


def room_not_encrypted() -> CallServiceError:
    return CallServiceError(status_code=403, errcode="M_ROOM_NOT_ENCRYPTED", error="Room is not encrypted.")


def not_one_to_one() -> CallServiceError:
    return CallServiceError(
        status_code=403,
        errcode="M_DIRECT_CALL_NOT_1_TO_1",
        error="Room is not an encrypted one-to-one room.",
    )


def rate_limited(retry_after_ms: int) -> CallServiceError:
    return CallServiceError(
        status_code=429,
        errcode="M_DIRECT_CALL_RATE_LIMITED",
        error="Direct-call token request rate limited.",
        retry_after_ms=retry_after_ms,
    )


def rate_limit_store_unavailable() -> CallServiceError:
    return CallServiceError(
        status_code=503,
        errcode="M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE",
        error="Direct-call rate limit store is unavailable.",
    )


def allocation_failed() -> CallServiceError:
    return CallServiceError(
        status_code=503,
        errcode="M_DIRECT_CALL_ALLOCATION_FAILED",
        error="Unable to allocate media room.",
    )
