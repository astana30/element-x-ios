"""FastAPI entrypoint for the SalemX native direct-call token service."""

from __future__ import annotations

from os import environ
from typing import Any, Optional

from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse

from .allocation import InMemoryAllocationStore
from .auth import SynapseMatrixAuthValidator, bearer_token_from_authorization
from .config import ServiceConfig
from .errors import CallServiceError, bad_request
from .livekit_tokens import LiveKitJWTTokenIssuer
from .local_fake import fake_mode_enabled, make_fake_capabilities_payload, make_fake_local_service
from .logging_utils import configure_logging
from .room_validation import SynapseRoomValidator
from .service import DirectCallTokenService, error_response

ENDPOINT_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"
CAPABILITIES_PATH = "/_matrix/client/v3/capabilities"


def create_app(config: ServiceConfig | None = None, token_service: DirectCallTokenService | None = None) -> FastAPI:
    service: DirectCallTokenService
    local_fake_capabilities_enabled = token_service is None and fake_mode_enabled()
    if token_service is not None:
        configure_logging("INFO")
        service = token_service
    elif fake_mode_enabled():
        configure_logging(environ.get("LOG_LEVEL", "INFO"))
        service = make_fake_local_service()
    else:
        config = config or ServiceConfig.from_env()
        configure_logging(config.log_level)
        service = DirectCallTokenService(
            auth_validator=SynapseMatrixAuthValidator(config.synapse_base_url),
            room_validator=SynapseRoomValidator(config.synapse_base_url, config.synapse_admin_token),
            allocation_store=InMemoryAllocationStore(config.allocation_ttl_seconds),
            token_issuer=LiveKitJWTTokenIssuer(config.livekit_api_key, config.livekit_api_secret, config.token_ttl_seconds),
            livekit_server_url=config.livekit_url,
        )

    app = FastAPI(title="SalemX Direct Call Service", version="0.1.0")

    @app.post(ENDPOINT_PATH)
    async def livekit_token(request: Request, authorization: Optional[str] = Header(default=None)) -> JSONResponse:
        try:
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
                bearer_token = bearer_token_from_authorization(authorization)
                await service.auth_validator.validate_bearer_token(bearer_token)
                return JSONResponse(status_code=200, content=make_fake_capabilities_payload(ENDPOINT_PATH))
            except CallServiceError as error:
                status_code, body = error_response(error)
                return JSONResponse(status_code=status_code, content=body)

    return app


app = create_app()
