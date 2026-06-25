"""FastAPI entrypoint for the SalemX native direct-call token service."""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import replace
from os import environ
from typing import Any, Optional

from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse, StreamingResponse

from .allocation import InMemoryAllocationStore, RedisAllocationClient, RedisAllocationStore, SharedAllocationStoreSkeleton
from .apns_voip import (
    APNsVoIPSandboxConfig,
    APNsVoIPSandboxSendRequest,
    APNsVoIPSandboxSendService,
)
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
    foreground_heartbeat_sse_event,
    foreground_invite_sse_event,
    foreground_ready_sse_event,
)
from .livekit_rooms import DEFAULT_ROOM_DEPARTURE_TIMEOUT_SECONDS, LiveKitRoomServiceProvisioner
from .livekit_tokens import LiveKitJWTTokenIssuer
from .local_fake import make_fake_capabilities_payload, make_fake_local_service
from .logging_utils import configure_logging, stable_redacted_id
from .pending_call_metadata import (
    InMemoryPendingCallMetadataStore,
    no_pending_metadata_diagnostics,
    pending_metadata_from_invite_payload,
    PendingCallMetadataStoreProtocol,
)
from .pushkit_tokens import (
    DisabledPushKitTokenStore,
    FilePushKitTokenStore,
    is_hex_pushkit_token,
    PushKitTokenRegistrationDiagnostics,
    PushKitTokenRegistrationRequest,
    record_updated_age_bucket,
    redacted_latest_user_record_key,
    PushKitTokenStoreProtocol,
)
from .rate_limiting import InMemoryRateLimiter, SharedRateLimiterSkeleton
from .rate_limiting import RedisRateLimitClient, RedisRateLimiter
from .room_validation import SynapseRoomValidator
from .service import DirectCallTokenService, error_response
from .storage_keys import StorageKeyHasher

ENDPOINT_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"
ELIGIBILITY_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/eligibility"
FOREGROUND_SIGNALING_STREAM_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream"
FOREGROUND_SIGNALING_INVITE_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite"
FOREGROUND_SIGNALING_PENDING_METADATA_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata/{metadata_reference}"
FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata/{metadata_reference}/sender"
FOREGROUND_SIGNALING_LIVEKIT_TOKEN_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/livekit/token"
FOREGROUND_SIGNALING_DEV_INVITE_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite"
FOREGROUND_SIGNALING_DEV_INJECT_ACTIVE_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/inject-active"
PUSHKIT_TOKEN_REGISTRATION_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/pushkit/token"
APNS_VOIP_SANDBOX_SEND_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/pushkit/apns/sandbox/send"
PUSHKIT_TOKEN_STORE_PATH_ENV = "SALEMX_CALL_SERVICE_PUSHKIT_TOKEN_STORE_PATH"
DEFAULT_PUSHKIT_TOKEN_STORE_PATH = "/tmp/salemx-call-service-pushkit-token-store/pushkit-tokens.json"
CAPABILITIES_PATH = "/_matrix/client/v3/capabilities"
HEALTH_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/health"
READINESS_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/readiness"
REDIS_READINESS_TIMEOUT_SECONDS = 0.5
FOREGROUND_SIGNALING_STREAM_HEARTBEAT_SECONDS = 15.0
LOGGER = logging.getLogger(__name__)


def create_app(config: ServiceConfig | None = None,
               token_service: DirectCallTokenService | None = None,
               foreground_signaling_service: ForegroundCallSignalingService | None = None,
               pushkit_token_store: PushKitTokenStoreProtocol | None = None,
               apns_voip_send_service: APNsVoIPSandboxSendService | None = None,
               pending_metadata_store: PendingCallMetadataStoreProtocol | None = None,
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
    token_store = pushkit_token_store or _pushkit_token_store_for_runtime(runtime_config)
    voip_send_service = apns_voip_send_service or APNsVoIPSandboxSendService(APNsVoIPSandboxConfig.from_env())
    pending_store = pending_metadata_store or InMemoryPendingCallMetadataStore()

    @app.get(HEALTH_PATH)
    async def health() -> JSONResponse:
        return JSONResponse(status_code=200, content=readiness.as_dict())

    @app.get(READINESS_PATH)
    async def ready() -> JSONResponse:
        current_readiness = _request_time_readiness(runtime_config, readiness)
        return JSONResponse(status_code=200 if current_readiness.ready else 503, content=current_readiness.as_dict())

    @app.post(ENDPOINT_PATH)
    @app.post(FOREGROUND_SIGNALING_LIVEKIT_TOKEN_PATH)
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

    @app.post(PUSHKIT_TOKEN_REGISTRATION_PATH)
    async def pushkit_token_registration(request: Request, authorization: Optional[str] = Header(default=None)) -> JSONResponse:
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
            registration_request = PushKitTokenRegistrationRequest.from_mapping(payload)
            store_result = token_store.store(authenticated_user.user_id, authenticated_user.device_id, registration_request)
            stored_record = token_store.retrieve(authenticated_user.user_id, authenticated_user.device_id, registration_request.environment_class)
            retrieval_internal_check = "redacted_match" if stored_record is not None and stored_record.token == registration_request.token else "not_persisted"
            diagnostics = PushKitTokenRegistrationDiagnostics.accepted(
                registration_request,
                store_result=store_result,
                retrieval_internal_check=retrieval_internal_check,
                store_key_redacted=redacted_latest_user_record_key(
                    authenticated_user.user_id,
                    registration_request.environment_class,
                ),
                record_updated_age_bucket=record_updated_age_bucket(stored_record),
            )
            LOGGER.info(
                "pushkit token registration accepted account_hash=%s device_bound=%s token_present=%s "
                "store_requested=%s voip_push_send_requested=%s",
                stable_redacted_id(getattr(authenticated_user, "user" "_id")),
                getattr(authenticated_user, "device" "_id") is not None,
                diagnostics.pushkit_token_present,
                diagnostics.pushkit_token_store_requested,
                diagnostics.voip_push_send_requested,
            )
            return JSONResponse(status_code=200, content=diagnostics.as_dict())
        except CallServiceError as error:
            status_code, body = error_response(error)
            return JSONResponse(status_code=status_code, content=body)

    @app.post(APNS_VOIP_SANDBOX_SEND_PATH)
    async def apns_voip_sandbox_send(request: Request, authorization: Optional[str] = Header(default=None)) -> JSONResponse:
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
            send_request = APNsVoIPSandboxSendRequest.from_mapping(payload)
            token_record = token_store.retrieve_latest_for_user(
                getattr(authenticated_user, "user" "_id"),
                "development",
            )
            diagnostics = voip_send_service.send(send_request, token_record)
            LOGGER.info(
                "apns voip sandbox send handled token_lookup=%s provider_requested=%s send_requested=%s result=%s",
                diagnostics.persisted_pushkit_token_lookup_result,
                diagnostics.apns_provider_requested,
                diagnostics.apns_voip_push_send_requested,
                diagnostics.apns_voip_push_send_result,
            )
            return JSONResponse(status_code=200, content=diagnostics.as_dict())
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
            LOGGER.info(
                "foreground signaling stream_auth_ok account_hash=%s device_bound=%s",
                stable_redacted_id(getattr(authenticated_user, "user" "_id")),
                getattr(authenticated_user, "device" "_id") is not None,
            )
            subscription = signaling_service.subscribe(authenticated_user)
            LOGGER.info(
                "foreground signaling stream_registered active_subscriber_count=%d",
                signaling_service.diagnostics.subscriber_count,
            )
        except CallServiceError as error:
            status_code, body = error_response(error)
            return JSONResponse(status_code=status_code, content=body)

        async def event_stream() -> object:
            closed_reason = "completed"
            try:
                yield foreground_ready_sse_event()
                LOGGER.info(
                    "foreground signaling ready_sent active_subscriber_count=%d",
                    signaling_service.diagnostics.subscriber_count,
                )
                while True:
                    try:
                        invite = await asyncio.wait_for(
                            subscription.next_event(),
                            timeout=FOREGROUND_SIGNALING_STREAM_HEARTBEAT_SECONDS,
                        )
                    except asyncio.TimeoutError:
                        yield foreground_heartbeat_sse_event()
                        continue
                    LOGGER.info(
                        "foreground signaling invite_yielded sse_event_type=foreground.call.invite active_subscriber_count=%d",
                        signaling_service.diagnostics.subscriber_count,
                    )
                    yield foreground_invite_sse_event(invite)
            except asyncio.CancelledError:
                closed_reason = "cancelled"
                raise
            except Exception:
                closed_reason = "error"
                raise
            finally:
                signaling_service.unsubscribe(subscription)
                LOGGER.info(
                    "foreground signaling stream_closed reason=%s active_subscriber_count=%d",
                    closed_reason,
                    signaling_service.diagnostics.subscriber_count,
                )

        return StreamingResponse(
            event_stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    @app.post(FOREGROUND_SIGNALING_INVITE_PATH)
    async def foreground_signaling_invite(request: Request, authorization: Optional[str] = Header(default=None)) -> JSONResponse:
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
            invite_request = ForegroundCallInviteRequest.from_mapping(payload)
            pending_metadata = pending_metadata_from_invite_payload(payload, authenticated_user)
            pending_metadata_reference: str | None = None
            pending_metadata_diagnostics = no_pending_metadata_diagnostics()
            if pending_metadata is not None:
                metadata_recipient_device = _pending_metadata_recipient_device(
                    invite_request=invite_request,
                    token_store=token_store,
                )
                pending_metadata_reference = pending_store.store(
                    recipient=invite_request.recipient,
                    recipient_device=metadata_recipient_device,
                    expires_at_ms=invite_request.invite.expires_at_ms,
                    metadata=pending_metadata,
                )
                pending_metadata_diagnostics = pending_metadata.safe_diagnostics()
            result = signaling_service.publish_invite(invite_request)
            result_body = result.as_dict()
            if pending_metadata_reference is not None:
                result_body["pending_metadata_reference"] = pending_metadata_reference
            result_body.update(_foreground_signaling_invite_diagnostics(invite_request, signaling_service))
            result_body.update(pending_metadata_diagnostics)
            result_body.update(_background_invite_apns_diagnostics(
                invite_request=invite_request,
                token_store=token_store,
                voip_send_service=voip_send_service,
                invite_dropped=result.dropped,
                pending_metadata_reference=pending_metadata_reference,
            ))
            LOGGER.info(
                "foreground signaling invite handled subscriber_available=%s delivered=%s dropped=%s call_kind=%s "
                "background_apns_push_requested=%s background_apns_push_result=%s",
                result.subscriber_available,
                result.delivered,
                result.dropped,
                invite_request.invite.call_kind,
                result_body["background_apns_push_requested"],
                result_body["background_apns_push_result"],
            )
            return JSONResponse(status_code=200, content=result_body)
        except CallServiceError as error:
            status_code, body = error_response(error)
            return JSONResponse(status_code=status_code, content=body)

    @app.get(FOREGROUND_SIGNALING_PENDING_METADATA_PATH)
    async def foreground_signaling_pending_metadata(metadata_reference: str,
                                                    authorization: Optional[str] = Header(default=None)) -> JSONResponse:
        try:
            if service is None:
                raise CallServiceError(status_code=503,
                                       errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                       error="Direct-call service is not ready.")
            bearer_token = bearer_token_from_authorization(authorization)
            authenticated_user = await service.auth_validator.validate_bearer_token(bearer_token)
            metadata = pending_store.retrieve(metadata_reference, authenticated_user, int(time.time() * 1000))
            return JSONResponse(status_code=200, content=metadata.token_request_payload())
        except CallServiceError as error:
            status_code, body = error_response(error)
            return JSONResponse(status_code=status_code, content=body)

    @app.get(FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_PATH)
    async def foreground_signaling_pending_metadata_sender(metadata_reference: str,
                                                          authorization: Optional[str] = Header(default=None)) -> JSONResponse:
        try:
            if service is None:
                raise CallServiceError(status_code=503,
                                       errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                       error="Direct-call service is not ready.")
            bearer_token = bearer_token_from_authorization(authorization)
            authenticated_user = await service.auth_validator.validate_bearer_token(bearer_token)
            metadata = pending_store.retrieve_sender_view(metadata_reference, authenticated_user, int(time.time() * 1000))
            return JSONResponse(status_code=200, content=metadata.token_request_payload())
        except CallServiceError as error:
            status_code, body = error_response(error)
            return JSONResponse(status_code=status_code, content=body)

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
                result_body = result.as_dict()
                result_body.update(_foreground_signaling_dev_invite_diagnostics(authenticated_user, signaling_service))
                LOGGER.info(
                    "foreground signaling dev invite handled subscriber_available=%s delivered=%s dropped=%s call_kind=%s",
                    result.subscriber_available,
                    result.delivered,
                    result.dropped,
                    invite.call_kind,
                )
                return JSONResponse(status_code=200, content=result_body)
            except CallServiceError as error:
                status_code, body = error_response(error)
                return JSONResponse(status_code=status_code, content=body)

        @app.post(FOREGROUND_SIGNALING_DEV_INJECT_ACTIVE_PATH)
        async def foreground_signaling_dev_inject_active(request: Request) -> JSONResponse:
            try:
                if not _is_local_request(request):
                    return JSONResponse(
                        status_code=403,
                        content=_foreground_signaling_dev_inject_active_response(
                            active_subscriber_count=signaling_service.diagnostics.subscriber_count,
                            delivered=False,
                            dropped=False,
                        ),
                    )
                payload: Any = await request.json()
                if not isinstance(payload, dict):
                    raise bad_request(error="Request body must be a JSON object.")
                invite = ForegroundCallInvitePayload.from_mapping(payload)
                active_subscriber_count, result = signaling_service.publish_invite_to_single_active_subscriber(invite)
                status_code = 200 if active_subscriber_count == 1 else 409
                LOGGER.info(
                    "foreground signaling dev active inject handled active_subscriber_count=%d delivered=%s dropped=%s call_kind=%s",
                    active_subscriber_count,
                    result.delivered,
                    result.dropped,
                    invite.call_kind,
                )
                return JSONResponse(
                    status_code=status_code,
                    content=_foreground_signaling_dev_inject_active_response(
                        active_subscriber_count=active_subscriber_count,
                        delivered=result.delivered,
                        dropped=result.dropped,
                    ),
                )
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


def _pushkit_token_store_for_runtime(config: ServiceConfig | None) -> PushKitTokenStoreProtocol:
    if config is None:
        return DisabledPushKitTokenStore()
    return FilePushKitTokenStore(environ.get(PUSHKIT_TOKEN_STORE_PATH_ENV, DEFAULT_PUSHKIT_TOKEN_STORE_PATH))


def _eligibility_policy_for_config(
    config: ServiceConfig,
) -> DisabledNativeAudioEligibilityPolicy | StaticAllowlistNativeAudioEligibilityPolicy:
    if not config.native_audio_eligibility_enabled:
        return DisabledNativeAudioEligibilityPolicy()
    return StaticAllowlistNativeAudioEligibilityPolicy(
        allowed_user_ids=config.native_audio_eligibility_allowed_users,
        allowed_homeservers=config.native_audio_eligibility_allowed_homeservers,
    )


def _foreground_signaling_dev_invite_diagnostics(
    authenticated_user: object,
    signaling_service: ForegroundCallSignalingService,
) -> dict[str, object]:
    target_account_key = getattr(authenticated_user, "user" "_id")
    target_device_key = getattr(authenticated_user, "device" "_id")
    target_device_hash = stable_redacted_id(target_device_key) if target_device_key is not None else "none"
    target_account_hash = stable_redacted_id(target_account_key)
    target_subscriber_count = signaling_service.subscriber_count_for(target_account_key, target_device_key)
    return {
        "active_subscriber_count": signaling_service.diagnostics.subscriber_count,
        "target_subscriber_count": target_subscriber_count,
        "target_active_subscriber_count": target_subscriber_count,
        "auth_user_hash": target_account_hash,
        "auth_device_hash": target_device_hash,
        "target_user_hash": target_account_hash,
        "target_device_hash": target_device_hash,
    }


def _foreground_signaling_invite_diagnostics(
    invite_request: ForegroundCallInviteRequest,
    signaling_service: ForegroundCallSignalingService,
) -> dict[str, object]:
    target_subscriber_count = signaling_service.subscriber_count_for(
        invite_request.recipient,
        invite_request.recipient_device,
    )
    return {
        "active_subscriber_count": signaling_service.diagnostics.subscriber_count,
        "target_subscriber_count": target_subscriber_count,
        "target_active_subscriber_count": target_subscriber_count,
    }


def _pending_metadata_recipient_device(
    invite_request: ForegroundCallInviteRequest,
    token_store: PushKitTokenStoreProtocol,
) -> str | None:
    if invite_request.recipient_device is None:
        return None

    exact_record = token_store.retrieve(invite_request.recipient, invite_request.recipient_device, "development")
    latest_record = token_store.retrieve_latest_for_user(invite_request.recipient, "development")
    if exact_record is not None and exact_record == latest_record:
        return invite_request.recipient_device
    return None


def _background_invite_apns_diagnostics(
    invite_request: ForegroundCallInviteRequest,
    token_store: PushKitTokenStoreProtocol,
    voip_send_service: APNsVoIPSandboxSendService,
    invite_dropped: bool,
    pending_metadata_reference: str | None = None,
) -> dict[str, object]:
    if invite_dropped:
        return {
            "real_non_dev_invite_used": True,
            "dev_invite_used": False,
            "background_apns_push_requested": False,
            "background_apns_push_result": "skipped_redacted",
            "background_apns_failure_reason": "none",
            "persisted_pushkit_token_lookup_result": "not_requested",
            "pushkit_token_redacted": True,
            "media_credentials_requested": False,
            "media_connect_requested": False,
            "matrix_event_emit_requested": False,
            "blocked_reason": "real_invite_payload_mapping_blocked",
        }

    if pending_metadata_reference is None:
        return {
            "real_non_dev_invite_used": True,
            "dev_invite_used": False,
            "background_apns_push_requested": False,
            "background_apns_push_result": "skipped_redacted",
            "background_apns_failure_reason": "none",
            "persisted_pushkit_token_lookup_result": "not_requested",
            "pushkit_token_redacted": True,
            "apns_environment": "sandbox",
            "apns_topic_resolved": False,
            "media_credentials_requested": False,
            "media_connect_requested": False,
            "matrix_event_emit_requested": False,
            "safe_to_send_apns": False,
            "APNs_sent": False,
            "pending_metadata_reference_repair_present": True,
            "pending_metadata_reference_repair_debug_only": True,
            "pending_metadata_reference_repair_real_invite_required": True,
            "pending_metadata_reference_repair_reference_created_before_apns": False,
            "pending_metadata_reference_repair_reference_present_in_apns_payload": False,
            "pending_metadata_reference_repair_reference_observed_by_pushkit": False,
            "pending_metadata_reference_repair_reference_handed_to_answer_pipeline": False,
            "pending_metadata_reference_repair_blocks_apns_without_reference": True,
            "pending_metadata_reference_repair_blocks_credentials_without_metadata_success": True,
            "pending_metadata_reference_repair_no_direct_credentials_bypass": True,
            "pending_metadata_reference_repair_no_connect_bypass": True,
            "pending_metadata_reference_repair_raw_metadata_logged": False,
            "blocked_reason": "pending_metadata_reference_missing_before_apns",
        }

    token_record = token_store.retrieve_latest_for_user(invite_request.recipient, "development")
    lookup_store_key_redacted = redacted_latest_user_record_key(invite_request.recipient, "development")
    if token_record is None:
        return {
            "real_non_dev_invite_used": True,
            "dev_invite_used": False,
            "background_apns_push_requested": False,
            "background_apns_push_result": "skipped_redacted",
            "background_apns_failure_reason": "none",
            "persisted_pushkit_token_lookup_result": "missing",
            "pushkit_token_redacted": True,
            "media_credentials_requested": False,
            "media_connect_requested": False,
            "matrix_event_emit_requested": False,
            "pushkit_upload_store_key_redacted": "none",
            "pushkit_upload_record_updated_age_bucket": "missing",
            "pushkit_upload_environment": "development",
            "pushkit_upload_token_is_hex": False,
            "real_invite_lookup_store_key_redacted": lookup_store_key_redacted,
            "real_invite_lookup_record_updated_age_bucket": "missing",
            "real_invite_lookup_environment": "development",
            "real_invite_lookup_token_is_hex": False,
            "upload_invite_store_key_match": False,
            "safe_to_send_apns": False,
            "APNs_sent": False,
            "pending_metadata_reference_repair_present": True,
            "pending_metadata_reference_repair_debug_only": True,
            "pending_metadata_reference_repair_real_invite_required": True,
            "pending_metadata_reference_repair_reference_created_before_apns": True,
            "pending_metadata_reference_repair_reference_present_in_apns_payload": False,
            "pending_metadata_reference_repair_reference_observed_by_pushkit": False,
            "pending_metadata_reference_repair_reference_handed_to_answer_pipeline": False,
            "pending_metadata_reference_repair_blocks_apns_without_reference": True,
            "pending_metadata_reference_repair_blocks_credentials_without_metadata_success": True,
            "pending_metadata_reference_repair_no_direct_credentials_bypass": True,
            "pending_metadata_reference_repair_no_connect_bypass": True,
            "pending_metadata_reference_repair_raw_metadata_logged": False,
            "blocked_reason": "receiver_pushkit_token_missing",
        }

    diagnostics = voip_send_service.send(
        APNsVoIPSandboxSendRequest(version=1, dry_run=False),
        token_record,
        payload_kind="real_invite_controlled",
        pending_metadata_reference=pending_metadata_reference,
    )
    return {
        "real_non_dev_invite_used": True,
        "dev_invite_used": False,
        "background_apns_push_requested": diagnostics.apns_voip_push_send_requested,
        "background_apns_push_result": diagnostics.apns_voip_push_send_result,
        "background_apns_failure_reason": diagnostics.apns_failure_reason,
        "persisted_pushkit_token_lookup_result": diagnostics.persisted_pushkit_token_lookup_result,
        "pushkit_token_redacted": diagnostics.pushkit_token_redacted,
        "apns_environment": diagnostics.apns_environment,
        "apns_topic_resolved": diagnostics.apns_topic_resolved,
        "media_credentials_requested": diagnostics.media_credentials_requested,
        "media_connect_requested": diagnostics.media_connect_requested,
        "matrix_event_emit_requested": diagnostics.matrix_event_emit_requested,
        "pushkit_upload_store_key_redacted": lookup_store_key_redacted,
        "pushkit_upload_record_updated_age_bucket": record_updated_age_bucket(token_record),
        "pushkit_upload_environment": token_record.environment_class,
        "pushkit_upload_token_is_hex": is_hex_pushkit_token(token_record.token),
        "real_invite_lookup_store_key_redacted": lookup_store_key_redacted,
        "real_invite_lookup_record_updated_age_bucket": record_updated_age_bucket(token_record),
        "real_invite_lookup_environment": "development",
        "real_invite_lookup_token_is_hex": is_hex_pushkit_token(token_record.token),
        "upload_invite_store_key_match": True,
        "safe_to_send_apns": True,
        "APNs_sent": diagnostics.apns_voip_push_send_result == "sandbox_success",
        "pending_metadata_reference_repair_present": True,
        "pending_metadata_reference_repair_debug_only": True,
        "pending_metadata_reference_repair_real_invite_required": True,
        "pending_metadata_reference_repair_reference_created_before_apns": True,
        "pending_metadata_reference_repair_reference_present_in_apns_payload": True,
        "pending_metadata_reference_repair_reference_observed_by_pushkit": False,
        "pending_metadata_reference_repair_reference_handed_to_answer_pipeline": False,
        "pending_metadata_reference_repair_blocks_apns_without_reference": True,
        "pending_metadata_reference_repair_blocks_credentials_without_metadata_success": True,
        "pending_metadata_reference_repair_no_direct_credentials_bypass": True,
        "pending_metadata_reference_repair_no_connect_bypass": True,
        "pending_metadata_reference_repair_raw_metadata_logged": False,
        "blocked_reason": "none" if diagnostics.apns_voip_push_send_result == "sandbox_success" else diagnostics.blocked_reason,
    }


def _foreground_signaling_dev_inject_active_response(
    active_subscriber_count: int,
    delivered: bool,
    dropped: bool,
) -> dict[str, object]:
    return {
        "version": 1,
        "active_subscriber_count": active_subscriber_count,
        "delivered": delivered,
        "dropped": dropped,
    }


def _is_local_request(request: Request) -> bool:
    if request.client is None:
        return False
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for is not None:
        forwarded_host = forwarded_for.split(",")[0].strip()
        return forwarded_host in {"127.0.0.1", "::1", "localhost"}
    return request.client.host in {"127.0.0.1", "::1", "localhost"}


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
