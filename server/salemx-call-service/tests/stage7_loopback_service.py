"""Test-only loopback server for the Stage 7 Swift HTTP contract."""

from __future__ import annotations

import hashlib
import os
from dataclasses import dataclass
from types import SimpleNamespace

import uvicorn
from fastapi import Request
from fastapi.responses import JSONResponse

os.environ.setdefault("SALEMX_CALL_SERVICE_MODE", "local_fake")

from salemx_call_service import app as app_module
from salemx_call_service.auth import AuthenticatedUser
from salemx_call_service.errors import CallServiceError
from salemx_call_service.production_dispatch_store import PostgresProductionDispatchStore
from salemx_call_service.pushkit_tokens import InMemoryPushKitTokenStore
from salemx_call_service.room_validation import RoomEligibility


POSTGRES_DSN_ENV = "SALEM_STAGE7_POSTGRES_DSN"
LOOPBACK_PORT_ENV = "SALEM_STAGE7_LOOPBACK_PORT"
METRICS_PATH = "/_salemx/test-only/stage7/metrics"
SENDER_TOKEN = "stage7-sender-auth-token"
RECEIVER_TOKEN = "stage7-receiver-auth-token"
SENDER = AuthenticatedUser("@stage7-swift-sender:example.invalid", "STAGE7-SWIFT-SENDER")
RECEIVER = AuthenticatedUser("@stage7-swift-receiver:example.invalid", "STAGE7-SWIFT-RECEIVER")
MASTER_KEY = hashlib.sha256(b"salemx-stage7-isolated-postgres-key").digest()


@dataclass
class _Metrics:
    sender_auth_count: int = 0
    receiver_auth_count: int = 0
    rejected_auth_count: int = 0
    fake_apns_attempt_count: int = 0
    fake_apns_accepted_count: int = 0
    fake_apns_ambiguous_count: int = 0

    def as_dict(self) -> dict[str, int]:
        return {
            "sender_auth_count": self.sender_auth_count,
            "receiver_auth_count": self.receiver_auth_count,
            "rejected_auth_count": self.rejected_auth_count,
            "fake_apns_attempt_count": self.fake_apns_attempt_count,
            "fake_apns_accepted_count": self.fake_apns_accepted_count,
            "fake_apns_ambiguous_count": self.fake_apns_ambiguous_count,
        }


class _SyntheticMatrixAuthValidator:
    def __init__(self, metrics: _Metrics) -> None:
        self._metrics = metrics

    async def validate_bearer_token(self, bearer_token: str) -> AuthenticatedUser:
        if bearer_token == SENDER_TOKEN:
            self._metrics.sender_auth_count += 1
            return SENDER
        if bearer_token == RECEIVER_TOKEN:
            self._metrics.receiver_auth_count += 1
            return RECEIVER
        self._metrics.rejected_auth_count += 1
        raise CallServiceError(status_code=401, errcode="M_UNKNOWN_TOKEN", error="Unknown synthetic token.")


class _SyntheticRoomValidator:
    async def validate_direct_call_room(
        self,
        authenticated_user: AuthenticatedUser,
        token_request: object,
    ) -> RoomEligibility:
        members = (SENDER.user_id, RECEIVER.user_id)
        if authenticated_user.user_id != SENDER.user_id or getattr(token_request, "peer_user_id", None) != RECEIVER.user_id:
            raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Synthetic room is ineligible.")
        return RoomEligibility(members, True)


class _FakeAPNsService:
    def __init__(self, metrics: _Metrics) -> None:
        self._metrics = metrics

    def send(self, *_: object, **kwargs: object) -> object:
        self._metrics.fake_apns_attempt_count += 1
        call_bootstrap = kwargs.get("call_bootstrap")
        room_id = call_bootstrap.get("roomID") if isinstance(call_bootstrap, dict) else None
        if isinstance(room_id, str) and "ambiguous" in room_id:
            self._metrics.fake_apns_ambiguous_count += 1
            raise RuntimeError("redacted ambiguous APNs fixture")
        self._metrics.fake_apns_accepted_count += 1
        return SimpleNamespace(
            apns_voip_push_send_requested=True,
            apns_voip_push_send_result="production_success",
            apns_failure_reason="none",
            persisted_pushkit_token_lookup_result="found",
            pushkit_token_redacted=True,
            apns_environment="production",
            apns_topic_resolved=True,
            media_credentials_requested=False,
            media_connect_requested=False,
            matrix_event_emit_requested=False,
            apns_provider_requested=True,
            apns_provider_accepted=True,
            blocked_reason="none",
        )


def _make_app() -> object:
    dsn = os.environ.get(POSTGRES_DSN_ENV, "")
    if not dsn:
        raise RuntimeError(f"{POSTGRES_DSN_ENV} is required.")

    metrics = _Metrics()
    service = SimpleNamespace(
        auth_validator=_SyntheticMatrixAuthValidator(metrics),
        room_validator=_SyntheticRoomValidator(),
    )
    application = app_module.create_app(
        token_service=service,
        pushkit_token_store=InMemoryPushKitTokenStore(),
        apns_voip_send_service=_FakeAPNsService(metrics),
        production_dispatch_store=PostgresProductionDispatchStore(dsn, MASTER_KEY),
        direct_call_capability_v1_enabled=True,
        direct_call_dispatch_v1_admission_enabled=True,
        direct_call_dispatch_v1_completion_enabled=True,
    )

    @application.get(METRICS_PATH)
    async def stage7_metrics(request: Request) -> JSONResponse:
        if request.client is None or request.client.host not in {"127.0.0.1", "::1"}:
            return JSONResponse(status_code=404, content={"detail": "Not found."})
        return JSONResponse(status_code=200, content=metrics.as_dict(), headers={"Cache-Control": "no-store"})

    return application


app = _make_app()


if __name__ == "__main__":
    port = int(os.environ[LOOPBACK_PORT_ENV])
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning", access_log=False)
