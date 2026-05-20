"""FastAPI entrypoint for the SalemX native direct-call token service."""

from __future__ import annotations

from os import environ
from typing import Any, Optional

from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse

from .allocation import InMemoryAllocationStore, RedisAllocationClient, RedisAllocationStore, SharedAllocationStoreSkeleton
from .auth import SynapseMatrixAuthValidator, bearer_token_from_authorization
from .config import (
    ServiceConfig,
    ServiceMode,
    ServicePreflightError,
    ServicePreflightReason,
    ServiceReadiness,
    service_mode_from_env,
    service_readiness_from_config,
    validate_service_preflight,
)
from .errors import CallServiceError, bad_request
from .livekit_tokens import LiveKitJWTTokenIssuer
from .local_fake import make_fake_capabilities_payload, make_fake_local_service
from .logging_utils import configure_logging
from .rate_limiting import InMemoryRateLimiter, SharedRateLimiterSkeleton
from .rate_limiting import RedisRateLimitClient, RedisRateLimiter
from .room_validation import SynapseRoomValidator
from .service import DirectCallTokenService, error_response
from .storage_keys import StorageKeyHasher

ENDPOINT_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"
CAPABILITIES_PATH = "/_matrix/client/v3/capabilities"
HEALTH_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/health"
READINESS_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/readiness"


def create_app(config: ServiceConfig | None = None,
               token_service: DirectCallTokenService | None = None,
               strict_startup: bool = True) -> FastAPI:
    service: DirectCallTokenService | None
    readiness: ServiceReadiness
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
            token_ttl_bounded=True,
            allocation_ttl_bounded=True,
            allocation_store_configured=True,
            allocation_store_shared=True,
            allocation_store_connected=True,
            rate_limit_configured=True,
            rate_limit_shared=True,
            rate_limit_connected=True,
            storage_key_configured=True,
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
                configure_logging(config.log_level)
                service = DirectCallTokenService(
                    auth_validator=SynapseMatrixAuthValidator(config.synapse_base_url),
                    room_validator=SynapseRoomValidator(config.synapse_base_url, config.synapse_admin_token),
                    allocation_store=_allocation_store_for_config(config),
                    rate_limiter=_rate_limiter_for_config(config),
                    token_issuer=LiveKitJWTTokenIssuer(config.livekit_api_key, config.livekit_api_secret, config.token_ttl_seconds),
                    livekit_server_url=config.livekit_url,
                    allocation_ttl_seconds=config.allocation_ttl_seconds,
                    rate_limit_per_minute=config.rate_limit_per_minute,
                )
        except ServicePreflightError as error:
            readiness = error.readiness
            service = None
            if strict_startup:
                raise RuntimeError(str(error)) from error

    app = FastAPI(title="SalemX Direct Call Service", version="0.1.0")

    @app.get(HEALTH_PATH)
    async def health() -> JSONResponse:
        return JSONResponse(status_code=200, content=readiness.as_dict())

    @app.get(READINESS_PATH)
    async def ready() -> JSONResponse:
        return JSONResponse(status_code=200 if readiness.ready else 503, content=readiness.as_dict())

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


def _redis_client_from_url(redis_url: str) -> object:
    try:
        from redis import asyncio as redis_asyncio
    except ModuleNotFoundError as error:
        raise RuntimeError("Redis support requires the pinned redis dependency.") from error
    return redis_asyncio.from_url(redis_url, encoding="utf-8", decode_responses=True)


app = create_app()
