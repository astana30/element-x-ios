"""FastAPI entrypoint for the SalemX native direct-call token service."""

from __future__ import annotations

import asyncio
import logging
from dataclasses import replace
from os import environ
from typing import Any, Optional

from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse, StreamingResponse

from .allocation import InMemoryAllocationStore, RedisAllocationClient, RedisAllocationStore, SharedAllocationStoreSkeleton
from .auth import SynapseMatrixAuthValidator, bearer_token_from_authorization
from .config import (
    ServiceConfig,
    ServiceMode,
    ServicePreflightError,
    ServicePreflightReason,
    ServiceReadiness,
    FOREGROUND_SIGNALING_DEV_INVITE_ENABLED_ENV,
    service_mode_from_env,
    service_readiness_from_config,
    validate_service_preflight,
)
from .eligibility import DisabledNativeAudioEligibilityPolicy, StaticAllowlistNativeAudioEligibilityPolicy
from .errors import CallServiceError, bad_request
from .foreground_signaling import (
    ForegroundCallInvitePayload,
    ForegroundCallInviteRequest,
    ForegroundCallSignalingService,
    foreground_invite_sse_event,
    foreground_ready_sse_event,
)
from .livekit_rooms import DEFAULT_ROOM_DEPARTURE_TIMEOUT_SECONDS, LiveKitRoomServiceProvisioner
from .livekit_tokens import LiveKitJWTTokenIssuer
from .local_fake import make_fake_capabilities_payload, make_fake_local_service
from .logging_utils import configure_logging
from .rate_limiting import InMemoryRateLimiter, SharedRateLimiterSkeleton
from .rate_limiting import RedisRateLimitClient, RedisRateLimiter
from .room_validation import SynapseRoomValidator
from .service import DirectCallTokenService, error_response
from .storage_keys import StorageKeyHasher

ENDPOINT_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"
ELIGIBILITY_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/eligibility"
FOREGROUND_SIGNALING_STREAM_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream"
FOREGROUND_SIGNALING_DEV_INVITE_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite"
CAPABILITIES_PATH = "/_matrix/client/v3/capabilities"
HEALTH_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/health"
READINESS_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/readiness"
REDIS_READINESS_TIMEOUT_SECONDS = 0.5
LOGGER = logging.getLogger(__name__)


def create_app(config: ServiceConfig | None = None,
               token_service: DirectCallTokenService | None = None,
               foreground_signaling_service: ForegroundCallSignalingService | None = None,
               strict_startup: bool = True) -> FastAPI:
    service: DirectCallTokenService | None
    readiness: ServiceReadiness
    runtime_config: ServiceConfig | None = None
    local_fake_capabilities_enabled = False
    if token_service is not None:
        configure_logging("INFO")
        service = token_service
        readiness = ServiceReadiness(
            mode=ServiceMode.STAGING.value,
            ready=True,
            reason=ServicePreflightReason.OK.value,
            fake_mode_enabled=False,
            synapse_configured=True,
            livekit_configured=True,
            livekit_url_secure=True,
            livekit_url_placeholder=False,
            livekit_room_provisioning_configured=True,
            token_ttl_bounded=True,
            allocation_ttl_bounded=True,
            allocation_store_configured=True,
            allocation_store_shared=True,
            allocation_store_connected=True,
            rate_limit_configured=True,
            rate_limit_shared=True,
            rate_limit_connected=True,
            storage_key_configured=True,
            native_audio_eligibility_configured=True,
            native_audio_eligibility_allowlist_configured=True,
        )
    else:
        configure_logging(environ.get("LOG_LEVEL", "INFO"))
        try:
            mode = service_mode_from_env()
            if mode == ServiceMode.LOCAL_FAKE.value:
                readiness = validate_service_preflight()
                service = make_fake_local_service()
                local_fake_capabilities_enabled = True
            else:
                readiness = service_readiness_from_config(config) if config is not None else validate_service_preflight()
                config = config or ServiceConfig.from_env()
                readiness = _readiness_with_live_store_checks(config, readiness)
                if not readiness.ready:
                    raise ServicePreflightError(readiness)
                runtime_config = config
                configure_logging(config.log_level)
                service = DirectCallTokenService(
                    auth_validator=SynapseMatrixAuthValidator(config.synapse_base_url),
                    room_validator=SynapseRoomValidator(config.synapse_base_url, config.synapse_admin_token),
                    allocation_store=_allocation_store_for_config(config),
                    rate_limiter=_rate_limiter_for_config(config),
                    room_provisioner=LiveKitRoomServiceProvisioner(
                        config.livekit_url,
                        config.livekit_api_key,
                        config.livekit_api_secret,
                        empty_timeout_seconds=config.allocation_ttl_seconds,
                        departure_timeout_seconds=DEFAULT_ROOM_DEPARTURE_TIMEOUT_SECONDS,
                    ),
                    token_issuer=LiveKitJWTTokenIssuer(config.livekit_api_key, config.livekit_api_secret, config.token_ttl_seconds),
                    livekit_server_url=config.livekit_url,
                    allocation_ttl_seconds=config.allocation_ttl_seconds,
                    rate_limit_per_minute=config.rate_limit_per_minute,
                    eligibility_policy=_eligibility_policy_for_config(config),
                )
        except ServicePreflightError as error:
            readiness = error.readiness
            service = None
            if strict_startup:
                raise RuntimeError(str(error)) from error

    app = FastAPI(title="SalemX Direct Call Service", version="0.1.0")
    signaling_service = foreground_signaling_service or ForegroundCallSignalingService()

    @app.get(HEALTH_PATH)
    async def health() -> JSONResponse:
        return JSONResponse(status_code=200, content=readiness.as_dict())

    @app.get(READINESS_PATH)
    async def ready() -> JSONResponse:
        current_readiness = _request_time_readiness(runtime_config, readiness)
        return JSONResponse(status_code=200 if current_readiness.ready else 503, content=current_readiness.as_dict())

    @app.post(ENDPOINT_PATH)
    async def livekit_token(request: Request, authorization: Optional[str] = Header(default=None)) -> JSONResponse:
        try:
            if service is None:
                raise CallServiceError(status_code=503,
                                       errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                       error="Direct-call service is not ready.")
            payload: Any = await request.json()
            if not isinstance(payload, dict):
                raise bad_request(error="Request body must be a JSON object.")
            response = await service.issue_token(authorization, payload)
            return JSONResponse(status_code=200, content=response.as_dict())
        except CallServiceError as error:
            status_code, body = error_response(error)
            return JSONResponse(status_code=status_code, content=body)

    @app.post(ELIGIBILITY_PATH)
    async def native_audio_eligibility(request: Request, authorization: Optional[str] = Header(default=None)) -> JSONResponse:
        try:
            if service is None:
                raise CallServiceError(status_code=503,
                                       errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                       error="Direct-call service is not ready.")
            payload: Any = await request.json()
            if not isinstance(payload, dict):
                raise bad_request(error="Request body must be a JSON object.")
            response = await service.evaluate_eligibility(authorization, payload)
            return JSONResponse(status_code=200, content=response.as_dict())
        except CallServiceError as error:
            status_code, body = error_response(error)
            return JSONResponse(status_code=status_code, content=body)

    @app.get(FOREGROUND_SIGNALING_STREAM_PATH)
    async def foreground_signaling_stream(authorization: Optional[str] = Header(default=None)):
        try:
            if service is None:
                raise CallServiceError(status_code=503,
                                       errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                       error="Direct-call service is not ready.")
            bearer_token = bearer_token_from_authorization(authorization)
            authenticated_user = await service.auth_validator.validate_bearer_token(bearer_token)
            subscription = signaling_service.subscribe(authenticated_user)
        except CallServiceError as error:
            status_code, body = error_response(error)
            return JSONResponse(status_code=status_code, content=body)

        async def event_stream() -> object:
            try:
                yield foreground_ready_sse_event()
                while True:
                    invite = await subscription.next_event()
                    yield foreground_invite_sse_event(invite)
            except asyncio.CancelledError:
                raise
            finally:
                signaling_service.unsubscribe(subscription)

        return StreamingResponse(
            event_stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-store"},
        )

    if environ.get(FOREGROUND_SIGNALING_DEV_INVITE_ENABLED_ENV) == "1":
        @app.post(FOREGROUND_SIGNALING_DEV_INVITE_PATH)
        async def foreground_signaling_dev_invite(request: Request, authorization: Optional[str] = Header(default=None)) -> JSONResponse:
            try:
                if service is None:
                    raise CallServiceError(status_code=503,
                                           errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                           error="Direct-call service is not ready.")
                bearer_token = bearer_token_from_authorization(authorization)
                authenticated_user = await service.auth_validator.validate_bearer_token(bearer_token)
                payload: Any = await request.json()
                if not isinstance(payload, dict):
                    raise bad_request(error="Request body must be a JSON object.")
                invite = ForegroundCallInvitePayload.from_mapping(payload)
                result = signaling_service.publish_invite(ForegroundCallInviteRequest(
                    recipient=getattr(authenticated_user, "user" "_id"),
                    recipient_device=getattr(authenticated_user, "device" "_id"),
                    invite=invite,
                ))
                LOGGER.info(
                    "foreground signaling dev invite handled subscriber_available=%s delivered=%s dropped=%s call_kind=%s",
                    result.subscriber_available,
                    result.delivered,
                    result.dropped,
                    invite.call_kind,
                )
                return JSONResponse(status_code=200, content=result.as_dict())
            except CallServiceError as error:
                status_code, body = error_response(error)
                return JSONResponse(status_code=status_code, content=body)

    if local_fake_capabilities_enabled:
        @app.get(CAPABILITIES_PATH)
        async def local_fake_capabilities(authorization: Optional[str] = Header(default=None)) -> JSONResponse:
            try:
                if service is None:
                    raise CallServiceError(status_code=503,
                                           errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                           error="Direct-call service is not ready.")
                bearer_token = bearer_token_from_authorization(authorization)
                await service.auth_validator.validate_bearer_token(bearer_token)
                return JSONResponse(status_code=200, content=make_fake_capabilities_payload(ENDPOINT_PATH))
            except CallServiceError as error:
                status_code, body = error_response(error)
                return JSONResponse(status_code=status_code, content=body)

    return app


def _allocation_store_for_config(config: ServiceConfig) -> InMemoryAllocationStore | RedisAllocationStore | SharedAllocationStoreSkeleton:
    if config.allocation_store == "memory":
        return InMemoryAllocationStore(config.allocation_ttl_seconds)
    if config.allocation_store == "redis" and config.allocation_store_url is not None and config.storage_key_secret is not None:
        return RedisAllocationStore(
            RedisAllocationClient(_redis_client_from_url(config.allocation_store_url)),
            StorageKeyHasher(config.storage_key_secret),
        )
    return SharedAllocationStoreSkeleton(config.allocation_store)


def _rate_limiter_for_config(config: ServiceConfig) -> InMemoryRateLimiter | RedisRateLimiter | SharedRateLimiterSkeleton:
    if config.rate_limit_store == "memory":
        return InMemoryRateLimiter()
    if config.rate_limit_store == "redis" and config.rate_limit_store_url is not None and config.storage_key_secret is not None:
        return RedisRateLimiter(
            RedisRateLimitClient(_redis_client_from_url(config.rate_limit_store_url)),
            StorageKeyHasher(config.storage_key_secret),
        )
    return SharedRateLimiterSkeleton(config.rate_limit_store)


def _eligibility_policy_for_config(
    config: ServiceConfig,
) -> DisabledNativeAudioEligibilityPolicy | StaticAllowlistNativeAudioEligibilityPolicy:
    if not config.native_audio_eligibility_enabled:
        return DisabledNativeAudioEligibilityPolicy()
    return StaticAllowlistNativeAudioEligibilityPolicy(
        allowed_user_ids=config.native_audio_eligibility_allowed_users,
        allowed_homeservers=config.native_audio_eligibility_allowed_homeservers,
    )


def _redis_client_from_url(redis_url: str) -> object:
    try:
        from redis import asyncio as redis_asyncio
    except ModuleNotFoundError as error:
        raise RuntimeError("Redis support requires the pinned redis dependency.") from error
    return redis_asyncio.from_url(redis_url, encoding="utf-8", decode_responses=True)


def _readiness_with_live_store_checks(config: ServiceConfig, readiness: ServiceReadiness) -> ServiceReadiness:
    if not readiness.ready:
        return readiness

    allocation_store_connected = readiness.allocation_store_connected
    rate_limit_connected = readiness.rate_limit_connected

    if config.allocation_store == "redis" and config.allocation_store_url is not None:
        allocation_store_connected = _redis_ping_url(config.allocation_store_url)
    if config.rate_limit_store == "redis" and config.rate_limit_store_url is not None:
        rate_limit_connected = _redis_ping_url(config.rate_limit_store_url)

    reason = ServicePreflightReason.OK.value
    if not allocation_store_connected:
        reason = ServicePreflightReason.ALLOCATION_STORE_UNAVAILABLE.value
    elif not rate_limit_connected:
        reason = ServicePreflightReason.RATE_LIMIT_STORE_UNAVAILABLE.value

    return replace(
        readiness,
        ready=reason == ServicePreflightReason.OK.value,
        reason=reason,
        allocation_store_connected=allocation_store_connected,
        rate_limit_connected=rate_limit_connected,
    )


def _request_time_readiness(config: ServiceConfig | None, readiness: ServiceReadiness) -> ServiceReadiness:
    if config is None:
        return readiness
    return _readiness_with_live_store_checks(config, readiness)


def _redis_ping_url(redis_url: str) -> bool:
    try:
        from redis import Redis
    except ModuleNotFoundError:
        return False

    client: object | None = None
    try:
        client = Redis.from_url(
            redis_url,
            socket_connect_timeout=REDIS_READINESS_TIMEOUT_SECONDS,
            socket_timeout=REDIS_READINESS_TIMEOUT_SECONDS,
            encoding="utf-8",
            decode_responses=True,
        )
        return bool(client.ping())  # type: ignore[attr-defined]
    except Exception:
        return False
    finally:
        if client is not None:
            try:
                client.close()  # type: ignore[attr-defined]
            except Exception:
                pass


app = create_app()
