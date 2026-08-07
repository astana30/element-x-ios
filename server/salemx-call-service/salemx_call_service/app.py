"""FastAPI entrypoint for the SalemX native direct-call token service."""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import logging
import secrets
import time
from dataclasses import replace
from os import environ
from typing import Any, Optional
from uuid import UUID

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
    ForegroundCallDeliveryMode,
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
    PendingCallMetadataRequest,
    PendingCallMetadataStoreProtocol,
)
from .pushkit_tokens import (
    DisabledPushKitTokenStore,
    FilePushKitTokenStore,
    is_hex_pushkit_token,
    PushKitTokenBinding,
    PushKitTokenRegistrationDiagnostics,
    PushKitTokenRegistrationRequest,
    PushKitTokenRecord,
    record_updated_age_bucket,
    redacted_latest_user_record_key,
    PushKitTokenStoreProtocol,
)
from .production_dispatch_store import (
    APNsOutcome,
    DispatchExpiredError,
    DispatchIdentity,
    DispatchNotFoundError,
    DispatchOwnershipError,
    DispatchState,
    DispatchTransitionError,
    MetadataAuthenticationError,
    PostgresProductionDispatchStore,
    ProductionDispatchStoreError,
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
FOREGROUND_SIGNALING_INVITE_PREPARE_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite/prepare"
FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite/send-prepared"
FOREGROUND_SIGNALING_INVITE_CANCEL_PREPARED_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite/cancel-prepared"
FOREGROUND_SIGNALING_PENDING_METADATA_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata/{metadata_reference}"
FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata/{metadata_reference}/sender"
FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_CLAIM_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata/sender/claim"
FOREGROUND_SIGNALING_PENDING_METADATA_RECEIVER_CONSUME_PATH = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata/receiver/consume"
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
INTERNAL_PENDING_STORE_SNAPSHOT_PATH = "/_salemx/internal/pending-store/snapshot"
PENDING_STORE_AUDIT_CREDENTIAL_HEADER = "X-SalemX-Pending-Store-Audit-Credential"
PENDING_STORE_AUDIT_CREDENTIAL_CONTEXT = b"salemx-pending-store-audit-v1"
INVITE_DIAGNOSTICS_NO_SEND_HEADER_VALUE = "z4f_invite_401_reason"
REDIS_READINESS_TIMEOUT_SECONDS = 0.5
FOREGROUND_SIGNALING_STREAM_HEARTBEAT_SECONDS = 15.0
LOGGER = logging.getLogger(__name__)


def create_app(config: ServiceConfig | None = None,
               token_service: DirectCallTokenService | None = None,
               foreground_signaling_service: ForegroundCallSignalingService | None = None,
               pushkit_token_store: PushKitTokenStoreProtocol | None = None,
               apns_voip_send_service: APNsVoIPSandboxSendService | None = None,
               pending_metadata_store: PendingCallMetadataStoreProtocol | None = None,
               production_dispatch_store: PostgresProductionDispatchStore | None = None,
               direct_call_capability_v1_enabled: bool | None = None,
               direct_call_dispatch_v1_admission_enabled: bool | None = None,
               direct_call_dispatch_v1_completion_enabled: bool | None = None,
               pending_store_audit_credential: str | None = None,
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

    @app.exception_handler(CallServiceError)
    async def call_service_error_handler(_: Request, error: CallServiceError) -> JSONResponse:
        status_code, body = error_response(error)
        return JSONResponse(status_code=status_code, content=body)

    @app.exception_handler(ProductionDispatchStoreError)
    async def production_dispatch_store_error_handler(_: Request, error: ProductionDispatchStoreError) -> JSONResponse:
        status_code, body = error_response(_call_service_error_for_dispatch_store(error))
        return JSONResponse(status_code=status_code, content=body)
    signaling_service = foreground_signaling_service or ForegroundCallSignalingService()
    token_store = pushkit_token_store or _pushkit_token_store_for_runtime(runtime_config)
    voip_send_service = apns_voip_send_service or APNsVoIPSandboxSendService(APNsVoIPSandboxConfig.from_env())
    pending_store = pending_metadata_store or InMemoryPendingCallMetadataStore()
    dispatch_store = production_dispatch_store or _production_dispatch_store_for_runtime(runtime_config)
    capability_v1_enabled = (
        direct_call_capability_v1_enabled
        if direct_call_capability_v1_enabled is not None
        else runtime_config is not None and runtime_config.direct_call_capability_v1_enabled
    )
    dispatch_v1_admission_enabled = (
        direct_call_dispatch_v1_admission_enabled
        if direct_call_dispatch_v1_admission_enabled is not None
        else runtime_config is not None and runtime_config.direct_call_dispatch_v1_admission_enabled
    )
    dispatch_v1_completion_enabled = (
        direct_call_dispatch_v1_completion_enabled
        if direct_call_dispatch_v1_completion_enabled is not None
        else runtime_config is not None and runtime_config.direct_call_dispatch_v1_completion_enabled
    )
    root_audit_credential = _pending_store_root_audit_credential(
        pending_store_audit_credential,
        runtime_config,
    )

    @app.get(HEALTH_PATH)
    async def health() -> JSONResponse:
        return JSONResponse(status_code=200, content=readiness.as_dict())

    @app.get(READINESS_PATH)
    async def ready() -> JSONResponse:
        current_readiness = _request_time_readiness(runtime_config, readiness)
        return JSONResponse(status_code=200 if current_readiness.ready else 503, content=current_readiness.as_dict())

    @app.get(INTERNAL_PENDING_STORE_SNAPSHOT_PATH)
    async def internal_pending_store_snapshot(
        request: Request,
        audit_credential: Optional[str] = Header(
            default=None,
            alias=PENDING_STORE_AUDIT_CREDENTIAL_HEADER,
        ),
    ) -> JSONResponse:
        authorized = (
            _is_direct_loopback_request(request)
            and root_audit_credential is not None
            and audit_credential is not None
            and hmac.compare_digest(audit_credential, root_audit_credential)
        )
        if not authorized:
            return JSONResponse(
                status_code=404,
                content={"errcode": "M_NOT_FOUND", "error": "Not found."},
            )
        snapshot = pending_store.snapshot_counts(int(time.time() * 1000))
        return JSONResponse(
            status_code=200,
            content=snapshot.as_dict(),
            headers={"Cache-Control": "no-store"},
        )

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
            if registration_request.protocol_version == 1 and capability_v1_enabled:
                active_dispatch_store = _require_dispatch_store(dispatch_store)
                identity = _dispatch_identity_for_record(authenticated_user.user_id, stored_record)
                active_dispatch_store.register_capability(
                    identity=identity,
                    environment=registration_request.environment_class,
                    protocol_version=1,
                    supported_intent="audio",
                    handoff_classification="matrixrtc_element_call",
                    token_binding_revision=_token_binding_revision(stored_record),
                    expires_in_seconds=registration_request.capability_expires_in_seconds,
                )
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

    @app.post(FOREGROUND_SIGNALING_INVITE_PREPARE_PATH)
    async def foreground_signaling_invite_prepare(
        request: Request,
        authorization: Optional[str] = Header(default=None),
    ) -> JSONResponse:
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
            if payload.get("dispatch_protocol_version") == 1:
                if not capability_v1_enabled or not dispatch_v1_admission_enabled:
                    raise CallServiceError(status_code=404, errcode="M_UNRECOGNIZED", error="Direct-call dispatch v1 is disabled.")
                active_dispatch_store = _require_dispatch_store(dispatch_store)
                invite_request = ForegroundCallInviteRequest.from_mapping(payload)
                pending_metadata = pending_metadata_from_invite_payload(payload, authenticated_user)
                if pending_metadata is None:
                    raise bad_request(error="Pending metadata is required.")
                generation = _required_opaque_generation(payload)
                now_ms = int(time.time() * 1000)
                expires_in_seconds = _bounded_dispatch_expiry(invite_request.invite.expires_at_ms, now_ms)
                await service.room_validator.validate_direct_call_room(
                    authenticated_user,
                    pending_metadata.sender_view_payload(invite_request.recipient).as_token_request(),
                )
                sender_record = _capable_record_for_identity(
                    authenticated_user.user_id, authenticated_user.device_id, generation, token_store,
                )
                receiver_record = _capable_latest_record(invite_request.recipient, token_store)
                sender_identity = _dispatch_identity_for_record(authenticated_user.user_id, sender_record)
                receiver_identity = _dispatch_identity_for_record(invite_request.recipient, receiver_record)
                references = active_dispatch_store.create_dispatch(
                    sender=sender_identity,
                    receiver=receiver_identity,
                    receiver_token_binding_revision=_token_binding_revision(receiver_record),
                    metadata={
                        **pending_metadata.token_request_payload(),
                        "recipient": invite_request.recipient,
                        "expires_at_ms": invite_request.invite.expires_at_ms,
                    },
                    expires_in_seconds=expires_in_seconds,
                )
                return JSONResponse(status_code=200, content={
                    "dispatch_protocol_version": 1,
                    "dispatch_id": str(references.dispatch_id),
                    "sender_reference": references.sender_reference,
                    "receiver_reference": references.receiver_reference,
                    "state": DispatchState.PREPARED.value,
                })
            invite_request = ForegroundCallInviteRequest.from_mapping(payload)
            pending_metadata = pending_metadata_from_invite_payload(payload, authenticated_user)
            if pending_metadata is None:
                raise bad_request(error="Pending metadata is required.")
            pending_metadata_reference = pending_store.store(
                recipient=invite_request.recipient,
                recipient_device=None,
                expires_at_ms=invite_request.invite.expires_at_ms,
                metadata=pending_metadata,
            )
            sender_authorized_metadata_reference = pending_store.store(
                recipient=invite_request.recipient,
                recipient_device=None,
                expires_at_ms=invite_request.invite.expires_at_ms,
                metadata=pending_metadata,
                sender_only=True,
                sender_device=None,
                prepared_receiver_reference=pending_metadata_reference,
            )
            body: dict[str, object] = {
                "fresh_metadata_created": True,
                "fresh_metadata_result_bucket": "success_redacted",
                "fresh_metadata_state_bucket": "prepared_not_sent_redacted",
                "fresh_metadata_bound_sender_bucket": "matched_redacted",
                "fresh_metadata_bound_receiver_bucket": "pending_token_registry_binding_redacted",
                "prepare_sender_device_binding_mode_bucket": "user_only_until_claim_redacted",
                "claim_sender_device_lock_result_bucket": "not_reached",
                "send_prepared_claimed_device_required": True,
                "prepared_metadata_claimed_by_sender": False,
                "sender_authorized_metadata_source_available": True,
                "sender_authorized_metadata_reference_present": True,
                "sender_authorized_metadata_reference": sender_authorized_metadata_reference,
                "sender_uses_receiver_pending_metadata_reference": False,
                "pending_metadata_reference_present": True,
                "pending_metadata_payload_redacted": True,
                "pending_metadata_created": True,
                "valid_invite_sent": False,
                "background_apns_push_requested": False,
                "APNs_sent": False,
                "APNs_send_count": 0,
                "APNs_type_bucket": "not_requested",
                "production_APNs_sent": False,
                "media_credentials_requested": False,
                "media_connect_requested": False,
                "matrix_event_emit_requested": False,
                "raw_identifiers_logged": False,
                "blocked_reason": "none",
            }
            return JSONResponse(status_code=200, content=body)
        except CallServiceError as error:
            status_code, body = error_response(error)
            return JSONResponse(status_code=status_code, content=body)

    @app.post(FOREGROUND_SIGNALING_INVITE_SEND_PREPARED_PATH)
    async def foreground_signaling_invite_send_prepared(
        request: Request,
        authorization: Optional[str] = Header(default=None),
    ) -> JSONResponse:
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
            if payload.get("dispatch_protocol_version") == 1:
                if not dispatch_v1_completion_enabled:
                    raise CallServiceError(status_code=404, errcode="M_UNRECOGNIZED", error="Direct-call dispatch v1 is disabled.")
                active_dispatch_store = _require_dispatch_store(dispatch_store)
                dispatch_id, sender_reference, receiver_reference = _exact_dispatch_request(payload, require_receiver_reference=True)
                generation = _required_opaque_generation(payload)
                sender_record = _capable_record_for_identity(
                    authenticated_user.user_id, authenticated_user.device_id, generation, token_store,
                )
                sender_identity = _dispatch_identity_for_record(authenticated_user.user_id, sender_record)
                inspected = active_dispatch_store.inspect_exact(
                    dispatch_id, sender_reference, receiver_reference, sender_identity, None,
                )
                if inspected.snapshot.state == DispatchState.SENT:
                    return JSONResponse(status_code=200, content=_stored_dispatch_success())
                recipient = inspected.metadata.get("recipient")
                if not isinstance(recipient, str) or not recipient:
                    raise CallServiceError(status_code=409, errcode="M_DIRECT_CALL_METADATA_INVALID", error="Prepared metadata is invalid.")
                receiver_record = _capable_latest_record(recipient, token_store)
                receiver_revision = _token_binding_revision(receiver_record)
                admission = active_dispatch_store.admit_send_exact(
                    dispatch_id,
                    sender_reference,
                    receiver_reference,
                    sender_identity,
                    receiver_revision,
                )
                if admission.already_sent:
                    return JSONResponse(status_code=200, content=_stored_dispatch_success())
                try:
                    current_receiver_record = _capable_latest_record(recipient, token_store)
                    if _token_binding_revision(current_receiver_record) != receiver_revision:
                        active_dispatch_store.complete_send_exact(
                            dispatch_id, sender_reference, sender_identity, APNsOutcome.REJECTED,
                        )
                        raise CallServiceError(status_code=409,
                                               errcode="M_DIRECT_CALL_RECEIVER_BINDING_UNAVAILABLE",
                                               error="Registered receiver binding changed.")
                    metadata = PendingCallMetadataRequest.from_mapping(dict(admission.metadata), authenticated_user)
                    expires_at_ms = admission.metadata.get("expires_at_ms")
                    if not isinstance(expires_at_ms, int) or isinstance(expires_at_ms, bool):
                        raise ValueError("Invalid encrypted metadata expiry.")
                    body = _prepared_invite_apns_diagnostics(
                        recipient=recipient,
                        token_record=current_receiver_record,
                        voip_send_service=voip_send_service,
                        pending_metadata_reference=receiver_reference,
                        metadata=metadata,
                        expires_at_ms=expires_at_ms,
                    )
                except CallServiceError as error:
                    if error.errcode == "M_DIRECT_CALL_RECEIVER_BINDING_UNAVAILABLE":
                        raise
                    active_dispatch_store.complete_send_exact(
                        dispatch_id, sender_reference, sender_identity, APNsOutcome.UNKNOWN,
                    )
                    raise CallServiceError(status_code=502,
                                           errcode="M_DIRECT_CALL_APNS_DELIVERY_UNKNOWN",
                                           error="APNs delivery outcome is unknown.") from error
                except Exception as error:
                    active_dispatch_store.complete_send_exact(
                        dispatch_id, sender_reference, sender_identity, APNsOutcome.UNKNOWN,
                    )
                    raise CallServiceError(status_code=502,
                                           errcode="M_DIRECT_CALL_APNS_DELIVERY_UNKNOWN",
                                           error="APNs delivery outcome is unknown.") from error
                apns_accepted = body.get("APNs_sent") is True
                active_dispatch_store.complete_send_exact(
                    dispatch_id,
                    sender_reference,
                    sender_identity,
                    APNsOutcome.ACCEPTED if apns_accepted else APNsOutcome.REJECTED,
                )
                if not apns_accepted:
                    raise CallServiceError(status_code=502,
                                           errcode="M_DIRECT_CALL_APNS_DELIVERY_FAILED",
                                           error="APNs delivery failed.")
                return JSONResponse(status_code=200, content=_stored_dispatch_success())
            version = payload.get("version")
            if version != 1:
                raise bad_request(errcode="M_UNRECOGNIZED", error="Unsupported prepared invite send version.")
            sender_reference = payload.get("sender_authorized_metadata_reference")
            if not isinstance(sender_reference, str) or not sender_reference:
                raise bad_request(error="Missing prepared metadata reference.")
            now_ms = int(time.time() * 1000)
            recipient = pending_store.prepared_recipient(
                sender_reference,
                authenticated_user,
                now_ms,
            )
            token_record = _preferred_receiver_token_record(recipient, token_store)
            if token_record is None:
                raise CallServiceError(status_code=409,
                                       errcode="M_DIRECT_CALL_RECEIVER_BINDING_UNAVAILABLE",
                                       error="Registered receiver binding is unavailable.")
            receiver_binding = token_record.authoritative_binding
            if receiver_binding is None or not receiver_binding.matches_user(recipient):
                raise CallServiceError(status_code=409,
                                       errcode="M_DIRECT_CALL_RECEIVER_BINDING_UNAVAILABLE",
                                       error="Registered receiver binding is unavailable.")
            receiver_record = pending_store.begin_prepared_send(
                sender_reference,
                authenticated_user,
                now_ms,
                receiver_binding,
            )
            try:
                body = _prepared_invite_apns_diagnostics(
                    recipient=receiver_record.recipient,
                    token_record=token_record,
                    voip_send_service=voip_send_service,
                    pending_metadata_reference=receiver_record.reference,
                    metadata=receiver_record.metadata,
                    expires_at_ms=receiver_record.expires_at_ms,
                )
            except Exception:
                pending_store.complete_prepared_send(
                    sender_reference,
                    authenticated_user,
                    int(time.time() * 1000),
                    receiver_binding,
                    accepted=False,
                )
                raise CallServiceError(status_code=502,
                                       errcode="M_DIRECT_CALL_APNS_DELIVERY_FAILED",
                                       error="APNs delivery failed.")
            apns_sent = body.get("APNs_sent") is True
            pending_store.complete_prepared_send(
                sender_reference,
                authenticated_user,
                int(time.time() * 1000),
                receiver_binding,
                accepted=apns_sent,
            )
            body.update({
                "fresh_metadata_created": True,
                "fresh_metadata_result_bucket": "success_redacted",
                "fresh_metadata_state_bucket": "sent_redacted" if apns_sent else "send_attempted_redacted",
                "fresh_metadata_bound_sender_bucket": "matched_redacted",
                "fresh_metadata_bound_receiver_bucket": "matched_redacted",
                "prepare_sender_device_binding_mode_bucket": "user_only_until_claim_redacted",
                "claim_sender_device_lock_result_bucket": "success_redacted",
                "send_prepared_claimed_device_required": True,
                "prepared_metadata_claimed_by_sender": True,
                "valid_invite_sent": apns_sent,
                "pending_metadata_created": True,
                "APNs_send_count": 1 if body.get("background_apns_push_requested") is True else 0,
                "APNs_type_bucket": f"{token_record.environment_class}_redacted"
                if body.get("background_apns_push_requested") is True else "not_requested",
                "production_APNs_sent": apns_sent and token_record.environment_class == "production",
                "raw_identifiers_logged": False,
            })
            if not apns_sent:
                body["errcode"] = "M_DIRECT_CALL_APNS_DELIVERY_FAILED"
                body["error"] = "APNs delivery failed."
                return JSONResponse(status_code=502, content=body)
            return JSONResponse(status_code=200, content=body)
        except CallServiceError as error:
            status_code, body = error_response(error)
            if status_code == 409:
                body["diagnostics"] = {
                    "prepared_metadata_claimed_by_sender": True,
                    "APNs_sent": False,
                    "APNs_send_count": 0,
                    "APNs_type_bucket": "not_requested",
                    "production_APNs_sent": False,
                    "blocked_reason": "receiver_binding_unavailable_redacted"
                    if error.errcode == "M_DIRECT_CALL_RECEIVER_BINDING_UNAVAILABLE"
                    else "prepared_invite_already_sent_redacted",
                }
            return JSONResponse(status_code=status_code, content=body)

    @app.post(FOREGROUND_SIGNALING_INVITE_PATH)
    async def foreground_signaling_invite(
        request: Request,
        authorization: Optional[str] = Header(default=None),
        invite_diagnostics_no_send: Optional[str] = Header(default=None, alias="X-SalemX-Invite-Diagnostics-No-Send"),
    ) -> JSONResponse:
        diagnostics_no_send_requested = _invite_diagnostics_no_send_requested(invite_diagnostics_no_send)
        delivery_attempt_id: str | None = None
        try:
            if service is None:
                raise CallServiceError(status_code=503,
                                       errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                       error="Direct-call service is not ready.")
            try:
                bearer_token = bearer_token_from_authorization(authorization)
            except CallServiceError as error:
                raise error.with_diagnostics(_invite_401_diagnostics(
                    "request_auth_header_missing" if authorization is None else "request_auth_header_invalid",
                    diagnostics_no_send_requested,
                )) from error
            try:
                authenticated_user = await service.auth_validator.validate_bearer_token(bearer_token)
            except CallServiceError as error:
                if error.status_code == 401:
                    raise error.with_diagnostics(_invite_401_diagnostics(
                        "request_matrix_whoami_failed",
                        diagnostics_no_send_requested,
                    )) from error
                raise
            delivery_attempt_id = _new_delivery_attempt_id()
            payload: Any = await request.json()
            if not isinstance(payload, dict):
                raise bad_request(error="Request body must be a JSON object.")
            try:
                invite_request = ForegroundCallInviteRequest.from_mapping(payload)
                pending_metadata = pending_metadata_from_invite_payload(payload, authenticated_user)
            except CallServiceError as error:
                if diagnostics_no_send_requested:
                    raise error.with_diagnostics(_invite_no_send_error_diagnostics("invite_body_validation_failed")) from error
                raise
            if diagnostics_no_send_requested:
                return JSONResponse(status_code=200, content=_invite_no_send_success_diagnostics(pending_metadata is not None))

            if invite_request.delivery_mode == ForegroundCallDeliveryMode.FOREGROUND_ONLY:
                if pending_metadata is None:
                    raise bad_request(error="Pending metadata is required for foreground-only delivery.")

                lease = signaling_service.exact_active_subscription_lease(invite_request)
                if lease is None:
                    raise _foreground_only_delivery_unavailable(
                        delivery_attempt_id=delivery_attempt_id,
                        result=None,
                        blocked_reason="foreground_stream_unavailable",
                    )

                receiver_token_binding = _authoritative_receiver_token_binding(
                    recipient=invite_request.recipient,
                    token_store=token_store,
                )
                pending_metadata_reference = pending_store.store(
                    recipient=invite_request.recipient,
                    recipient_device=None,
                    expires_at_ms=invite_request.invite.expires_at_ms,
                    metadata=pending_metadata,
                    sender_device=authenticated_user.device_id,
                    receiver_token_binding=receiver_token_binding,
                )
                sender_authorized_metadata_reference = pending_store.store(
                    recipient=invite_request.recipient,
                    recipient_device=None,
                    expires_at_ms=invite_request.invite.expires_at_ms,
                    metadata=pending_metadata,
                    sender_only=True,
                    sender_device=authenticated_user.device_id,
                )
                result = signaling_service.publish_invite_to_lease(invite_request, lease)
                if not result.delivered:
                    pending_store.discard(pending_metadata_reference)
                    pending_store.discard(sender_authorized_metadata_reference)
                    raise _foreground_only_delivery_unavailable(
                        delivery_attempt_id=delivery_attempt_id,
                        result=result,
                        blocked_reason="foreground_delivery_failed_after_metadata_claim",
                    )

                result_body = result.as_dict()
                result_body["pending_metadata_reference"] = pending_metadata_reference
                result_body.update(_sender_authorized_metadata_diagnostics(sender_authorized_metadata_reference))
                result_body.update(_foreground_signaling_invite_diagnostics(
                    invite_request,
                    signaling_service,
                    delivery_attempt_id=delivery_attempt_id,
                    result=result,
                ))
                result_body.update(pending_metadata.safe_diagnostics())
                result_body.update(_foreground_only_no_apns_diagnostics())
                LOGGER.info(
                    "foreground signaling invite handled delivery_attempt_id=%s delivery_mode=foreground_only "
                    "subscriber_available=%s delivered=%s dropped=%s call_kind=%s "
                    "background_apns_push_requested=False background_apns_push_result=suppressed_redacted",
                    delivery_attempt_id,
                    result.subscriber_available,
                    result.delivered,
                    result.dropped,
                    invite_request.invite.call_kind,
                )
                return JSONResponse(status_code=200, content=result_body)

            pending_metadata_reference: str | None = None
            sender_authorized_metadata_reference: str | None = None
            pending_metadata_diagnostics = no_pending_metadata_diagnostics()
            if pending_metadata is not None:
                receiver_token_binding = _authoritative_receiver_token_binding(
                    recipient=invite_request.recipient,
                    token_store=token_store,
                )
                pending_metadata_reference = pending_store.store(
                    recipient=invite_request.recipient,
                    recipient_device=None,
                    expires_at_ms=invite_request.invite.expires_at_ms,
                    metadata=pending_metadata,
                    sender_device=authenticated_user.device_id,
                    receiver_token_binding=receiver_token_binding,
                )
                sender_authorized_metadata_reference = pending_store.store(
                    recipient=invite_request.recipient,
                    recipient_device=None,
                    expires_at_ms=invite_request.invite.expires_at_ms,
                    metadata=pending_metadata,
                    sender_only=True,
                    sender_device=authenticated_user.device_id,
                )
                pending_metadata_diagnostics = pending_metadata.safe_diagnostics()
            result = signaling_service.publish_invite(invite_request)
            result_body = result.as_dict()
            if pending_metadata_reference is not None:
                result_body["pending_metadata_reference"] = pending_metadata_reference
            result_body.update(_sender_authorized_metadata_diagnostics(sender_authorized_metadata_reference))
            result_body.update(_foreground_signaling_invite_diagnostics(
                invite_request,
                signaling_service,
                delivery_attempt_id=delivery_attempt_id,
                result=result,
            ))
            result_body.update(pending_metadata_diagnostics)
            result_body.update(_background_invite_apns_diagnostics(
                invite_request=invite_request,
                token_store=token_store,
                voip_send_service=voip_send_service,
                invite_dropped=result.dropped,
                pending_metadata_reference=pending_metadata_reference,
                pending_metadata=pending_metadata,
            ))
            LOGGER.info(
                "foreground signaling invite handled delivery_attempt_id=%s delivery_mode=%s "
                "subscriber_available=%s delivered=%s dropped=%s call_kind=%s "
                "background_apns_push_requested=%s background_apns_push_result=%s",
                delivery_attempt_id,
                invite_request.delivery_mode.value,
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

    @app.post(FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_CLAIM_PATH)
    async def foreground_signaling_pending_metadata_sender_claim_v1(
        request: Request,
        authorization: Optional[str] = Header(default=None),
    ) -> JSONResponse:
        if service is None:
            raise CallServiceError(status_code=503,
                                   errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                   error="Direct-call service is not ready.")
        if not dispatch_v1_admission_enabled:
            raise CallServiceError(status_code=404, errcode="M_UNRECOGNIZED", error="Direct-call dispatch v1 is disabled.")
        authenticated_user = await service.auth_validator.validate_bearer_token(
            bearer_token_from_authorization(authorization),
        )
        payload: Any = await request.json()
        if not isinstance(payload, dict) or payload.get("dispatch_protocol_version") != 1:
            raise bad_request(error="Invalid direct-call dispatch claim.")
        dispatch_id, sender_reference, _ = _exact_dispatch_request(payload, require_receiver_reference=False)
        generation = _required_opaque_generation(payload)
        sender_record = _capable_record_for_identity(
            authenticated_user.user_id, authenticated_user.device_id, generation, token_store,
        )
        snapshot = _require_dispatch_store(dispatch_store).claim_exact(
            dispatch_id,
            sender_reference,
            _dispatch_identity_for_record(authenticated_user.user_id, sender_record),
        )
        return JSONResponse(status_code=200, content={
            "dispatch_protocol_version": 1,
            "state": snapshot.state.value,
            "claimed": True,
        })

    @app.post(FOREGROUND_SIGNALING_INVITE_CANCEL_PREPARED_PATH)
    async def foreground_signaling_invite_cancel_prepared_v1(
        request: Request,
        authorization: Optional[str] = Header(default=None),
    ) -> JSONResponse:
        if service is None:
            raise CallServiceError(status_code=503,
                                   errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                   error="Direct-call service is not ready.")
        if not dispatch_v1_admission_enabled:
            raise CallServiceError(status_code=404, errcode="M_UNRECOGNIZED", error="Direct-call dispatch v1 is disabled.")
        authenticated_user = await service.auth_validator.validate_bearer_token(
            bearer_token_from_authorization(authorization),
        )
        payload: Any = await request.json()
        if not isinstance(payload, dict) or payload.get("dispatch_protocol_version") != 1:
            raise bad_request(error="Invalid direct-call dispatch cancellation.")
        dispatch_id, sender_reference, _ = _exact_dispatch_request(payload, require_receiver_reference=False)
        generation = _required_opaque_generation(payload)
        sender_record = _capable_record_for_identity(
            authenticated_user.user_id, authenticated_user.device_id, generation, token_store,
        )
        snapshot = _require_dispatch_store(dispatch_store).cancel_exact(
            dispatch_id,
            sender_reference,
            _dispatch_identity_for_record(authenticated_user.user_id, sender_record),
        )
        return JSONResponse(status_code=200, content={
            "dispatch_protocol_version": 1,
            "state": snapshot.state.value,
            "cancelled": True,
        })

    @app.post(FOREGROUND_SIGNALING_PENDING_METADATA_RECEIVER_CONSUME_PATH)
    async def foreground_signaling_pending_metadata_receiver_consume_v1(
        request: Request,
        authorization: Optional[str] = Header(default=None),
    ) -> JSONResponse:
        if service is None:
            raise CallServiceError(status_code=503,
                                   errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                   error="Direct-call service is not ready.")
        if not dispatch_v1_completion_enabled:
            raise CallServiceError(status_code=404, errcode="M_UNRECOGNIZED", error="Direct-call dispatch v1 is disabled.")
        authenticated_user = await service.auth_validator.validate_bearer_token(
            bearer_token_from_authorization(authorization),
        )
        payload: Any = await request.json()
        if not isinstance(payload, dict) or payload.get("dispatch_protocol_version") != 1:
            raise bad_request(error="Invalid direct-call metadata consumption.")
        dispatch_id = _required_dispatch_id(payload)
        receiver_reference = _required_opaque_reference(payload, "receiver_reference")
        generation = _required_opaque_generation(payload)
        receiver_record = _capable_record_for_identity(
            authenticated_user.user_id, authenticated_user.device_id, generation, token_store,
        )
        consumed = _require_dispatch_store(dispatch_store).consume_exact(
            dispatch_id,
            receiver_reference,
            _dispatch_identity_for_record(authenticated_user.user_id, receiver_record),
        )
        metadata = consumed.metadata
        response_keys = ("version", "call_id", "room_id", "peer_user_id", "direction", "intent", "expires_at_ms")
        return JSONResponse(status_code=200, content={
            "dispatch_protocol_version": 1,
            "state": consumed.snapshot.state.value,
            **{key: metadata[key] for key in response_keys if key in metadata},
        })

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
            return JSONResponse(status_code=200, content=metadata.response_payload())
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

    @app.get(FOREGROUND_SIGNALING_PENDING_METADATA_SENDER_CLAIM_PATH)
    async def foreground_signaling_pending_metadata_sender_claim(authorization: Optional[str] = Header(default=None)) -> JSONResponse:
        auth_header_seen = authorization is not None
        auth_scheme_bucket = _authorization_scheme_bucket(authorization)
        token_validation_bucket = "not_reached"
        authenticated_user_bucket = "not_reached"
        bound_sender_bucket = "not_checked"
        bound_device_bucket = "not_checked"
        try:
            if service is None:
                raise CallServiceError(status_code=503,
                                       errcode="M_DIRECT_CALL_SERVICE_UNAVAILABLE",
                                       error="Direct-call service is not ready.")
            bearer_token = bearer_token_from_authorization(authorization)
            authenticated_user = await service.auth_validator.validate_bearer_token(bearer_token)
            token_validation_bucket = "success_redacted"
            authenticated_user_bucket = "present_redacted"
            metadata = pending_store.claim_latest_sender_view(authenticated_user, int(time.time() * 1000))
            bound_sender_bucket = "matched_redacted"
            bound_device_bucket = "claimed_by_current_app_device_redacted"
            body = metadata.token_request_payload()
            body.update(_sender_metadata_claim_diagnostics(
                "success_redacted",
                auth_header_seen=auth_header_seen,
                auth_scheme_bucket=auth_scheme_bucket,
                token_validation_bucket=token_validation_bucket,
                authenticated_user_bucket=authenticated_user_bucket,
                bound_sender_bucket=bound_sender_bucket,
                bound_device_bucket=bound_device_bucket,
            ))
            return JSONResponse(status_code=200, content=body)
        except CallServiceError as error:
            status_code, body = error_response(error)
            if status_code in (401, 403, 404):
                if status_code == 401 and auth_header_seen and auth_scheme_bucket == "bearer_redacted":
                    token_validation_bucket = "unauthorized_redacted"
                    authenticated_user_bucket = "missing"
                elif status_code == 403 and authenticated_user_bucket == "present_redacted":
                    bound_sender_bucket = "matched_redacted"
                    bound_device_bucket = "mismatch_redacted"
                elif status_code == 404 and authenticated_user_bucket == "present_redacted":
                    bound_sender_bucket = "mismatch_redacted"
                body["diagnostics"] = _sender_metadata_claim_diagnostics(
                    _sender_metadata_claim_result_bucket(status_code),
                    auth_header_seen=auth_header_seen,
                    auth_scheme_bucket=auth_scheme_bucket,
                    token_validation_bucket=token_validation_bucket,
                    authenticated_user_bucket=authenticated_user_bucket,
                    bound_sender_bucket=bound_sender_bucket,
                    bound_device_bucket=bound_device_bucket,
                )
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
    *,
    delivery_attempt_id: str,
    result: object,
) -> dict[str, object]:
    target_subscriber_count = signaling_service.subscriber_count_for(
        invite_request.recipient,
        invite_request.recipient_device,
    )
    return {
        "delivery_attempt_id": delivery_attempt_id,
        "delivery_attempt_id_present": True,
        "delivery_mode": invite_request.delivery_mode.value,
        "active_subscriber_count": signaling_service.diagnostics.subscriber_count,
        "target_subscriber_count": target_subscriber_count,
        "target_active_subscriber_count": target_subscriber_count,
        "foreground_stream_present": getattr(result, "subscriber_available", False),
        "foreground_delivery_attempted": True,
        "foreground_delivery_succeeded": getattr(result, "delivered", False),
    }


def _new_delivery_attempt_id() -> str:
    return "da_" + secrets.token_urlsafe(18)


def _foreground_only_no_apns_diagnostics() -> dict[str, object]:
    return {
        "real_non_dev_invite_used": True,
        "dev_invite_used": False,
        "background_apns_push_requested": False,
        "background_apns_push_result": "suppressed_redacted",
        "background_apns_failure_reason": "none",
        "persisted_pushkit_token_lookup_result": "not_requested",
        "pushkit_token_redacted": True,
        "apns_environment": "suppressed",
        "apns_topic_resolved": False,
        "apns_requested": False,
        "apns_provider_invoked": False,
        "apns_provider_accepted": False,
        "media_credentials_requested": False,
        "media_connect_requested": False,
        "matrix_event_emit_requested": False,
        "safe_to_send_apns": False,
        "APNs_sent": False,
        "blocked_reason": "none",
    }


def _foreground_only_delivery_unavailable(
    *,
    delivery_attempt_id: str,
    result: object | None,
    blocked_reason: str,
) -> CallServiceError:
    diagnostics = {
        "delivery_attempt_id": delivery_attempt_id,
        "delivery_attempt_id_present": True,
        "delivery_mode": ForegroundCallDeliveryMode.FOREGROUND_ONLY.value,
        "foreground_stream_present": getattr(result, "subscriber_available", False),
        "foreground_delivery_attempted": result is not None,
        "foreground_delivery_succeeded": False,
        "background_apns_push_requested": False,
        "background_apns_push_result": "suppressed_redacted",
        "background_apns_failure_reason": "none",
        "persisted_pushkit_token_lookup_result": "not_requested",
        "pushkit_token_redacted": True,
        "apns_requested": False,
        "apns_provider_invoked": False,
        "apns_provider_accepted": False,
        "media_credentials_requested": False,
        "media_connect_requested": False,
        "matrix_event_emit_requested": False,
        "safe_to_send_apns": False,
        "APNs_sent": False,
        "blocked_reason": blocked_reason,
    }
    return CallServiceError(
        status_code=409,
        errcode="M_DIRECT_CALL_FOREGROUND_STREAM_UNAVAILABLE",
        error="A matching foreground call signaling stream is not available.",
        diagnostics=diagnostics,
    )


def _sender_authorized_metadata_diagnostics(reference: str | None) -> dict[str, object]:
    reference_present = reference is not None
    diagnostics: dict[str, object] = {
        "sender_authorized_metadata_source_available": reference_present,
        "sender_authorized_metadata_reference_present": reference_present,
        "sender_authorized_metadata_source_role_bucket": "invite_creator_sender_metadata_reference_redacted" if reference_present else "missing_redacted",
        "sender_authorized_metadata_source_scope_bucket": "sender_authorized_metadata_scope_redacted" if reference_present else "missing_redacted",
        "sender_uses_receiver_pending_metadata_reference": False,
        "sender_authorized_metadata_fetch_authenticated_required": reference_present,
        "sender_authorized_metadata_raw_identifiers_logged": False,
    }
    if reference_present:
        diagnostics["sender_authorized_metadata_reference"] = reference
    return diagnostics


def _sender_metadata_claim_result_bucket(status_code: int) -> str:
    if status_code == 401:
        return "unauthorized_redacted"
    if status_code == 403:
        return "forbidden_redacted"
    if status_code == 404:
        return "missing_redacted"
    return "blocked_redacted"


def _authorization_scheme_bucket(authorization: str | None) -> str:
    if authorization is None:
        return "missing"
    if authorization.startswith("Bearer ") and len(authorization) > len("Bearer "):
        return "bearer_redacted"
    return "unknown_redacted"


def _sender_metadata_claim_diagnostics(result_bucket: str,
                                       *,
                                       auth_header_seen: bool = False,
                                       auth_scheme_bucket: str = "missing",
                                       token_validation_bucket: str = "not_reached",
                                       authenticated_user_bucket: str = "not_reached",
                                       bound_sender_bucket: str = "not_checked",
                                       bound_device_bucket: str = "not_checked") -> dict[str, object]:
    success = result_bucket == "success_redacted"
    if bound_device_bucket in ("claimed_by_current_app_device_redacted", "matched_redacted"):
        claim_lock_bucket = "success_redacted"
    elif bound_device_bucket == "mismatch_redacted":
        claim_lock_bucket = "mismatch_redacted"
    else:
        claim_lock_bucket = "not_reached"
    return {
        "server_side_sender_metadata_lookup_requested": True,
        "server_side_sender_metadata_lookup_result_bucket": result_bucket,
        "server_side_sender_metadata_claim_requested": True,
        "server_side_sender_metadata_claim_result_bucket": result_bucket,
        "prepare_sender_device_binding_mode_bucket": "user_only_until_claim_redacted",
        "claim_sender_device_lock_result_bucket": claim_lock_bucket,
        "send_prepared_claimed_device_required": True,
        "server_claim_auth_header_seen": auth_header_seen,
        "server_claim_auth_scheme_bucket": auth_scheme_bucket,
        "server_claim_token_validation_bucket": token_validation_bucket,
        "server_claim_authenticated_user_bucket": authenticated_user_bucket,
        "server_claim_bound_sender_bucket": bound_sender_bucket,
        "server_claim_bound_device_bucket": bound_device_bucket,
        "sender_authorized_metadata_source_available": success,
        "sender_uses_receiver_pending_metadata_reference": False,
        "server_side_sender_metadata_claim_raw_identifiers_logged": False,
    }


def _invite_diagnostics_no_send_requested(header_value: str | None) -> bool:
    return header_value == INVITE_DIAGNOSTICS_NO_SEND_HEADER_VALUE


def _invite_401_diagnostics(reason_bucket: str, no_send_requested: bool) -> dict[str, object]:
    return {
        "invite_401_reason_bucket": reason_bucket,
        "invite_diagnostic_auth_result_bucket": "auth_failed_redacted",
        "invite_diagnostic_validation_result_bucket": "not_reached_redacted",
        "invite_diagnostic_no_send_requested": no_send_requested,
        "invite_diagnostic_reason_buckets_supported": [
            "request_auth_header_missing",
            "request_auth_header_invalid",
            "request_matrix_whoami_failed",
            "sender_room_membership_auth_failed",
            "sender_not_room_member",
            "receiver_not_room_member",
            "encrypted_room_check_failed",
            "sender_authorized_metadata_source_failed",
            "invite_body_validation_failed",
            "pending_metadata_authorization_failed",
            "apns_preflight_auth_failed",
            "unknown_401_source",
        ],
        "pending_metadata_created": False,
        "valid_invite_sent": False,
        "background_apns_push_requested": False,
        "APNs_sent": False,
        "raw_identifiers_logged": False,
    }


def _invite_no_send_error_diagnostics(reason_bucket: str) -> dict[str, object]:
    return {
        "invite_401_reason_bucket": reason_bucket,
        "invite_diagnostic_auth_result_bucket": "auth_passed_redacted",
        "invite_diagnostic_validation_result_bucket": "validation_failed_redacted",
        "diagnostic_validation_result_bucket": "validation_failed_redacted",
        "invite_diagnostic_no_send_requested": True,
        "pending_metadata_created": False,
        "diagnostic_pending_metadata_created": False,
        "valid_invite_sent": False,
        "background_apns_push_requested": False,
        "diagnostic_background_apns_push_requested": False,
        "APNs_sent": False,
        "diagnostic_apns_sent": False,
        "diagnostic_no_send_suppressed_apns": True,
        "raw_identifiers_logged": False,
    }


def _invite_no_send_success_diagnostics(pending_metadata_requested: bool) -> dict[str, object]:
    return {
        "invite_401_reason_bucket": "none",
        "invite_diagnostic_auth_result_bucket": "auth_passed_redacted",
        "invite_diagnostic_validation_result_bucket": "validation_passed_no_send_redacted",
        "diagnostic_validation_result_bucket": "validation_passed_no_send_redacted",
        "invite_diagnostic_no_send_requested": True,
        "real_non_dev_invite_used": True,
        "dev_invite_used": False,
        "pending_metadata_source_requested": pending_metadata_requested,
        "pending_metadata_source_created": False,
        "diagnostic_pending_metadata_created": False,
        "pending_metadata_reference_present": False,
        "sender_authorized_metadata_source_available": False,
        "sender_authorized_metadata_reference_present": False,
        "background_apns_push_requested": False,
        "diagnostic_background_apns_push_requested": False,
        "background_apns_push_result": "not_requested",
        "background_apns_failure_reason": "none",
        "safe_to_send_apns": False,
        "APNs_sent": False,
        "diagnostic_apns_sent": False,
        "diagnostic_no_send_suppressed_apns": True,
        "valid_invite_sent": False,
        "media_credentials_requested": False,
        "media_connect_requested": False,
        "matrix_event_emit_requested": False,
        "raw_identifiers_logged": False,
        "blocked_reason": "diagnostic_no_send",
    }


def _authoritative_receiver_token_binding(
    recipient: str,
    token_store: PushKitTokenStoreProtocol,
) -> PushKitTokenBinding | None:
    token_record = _preferred_receiver_token_record(recipient, token_store)
    if token_record is None:
        return None
    receiver_binding = token_record.authoritative_binding
    return receiver_binding if receiver_binding is not None and receiver_binding.matches_user(recipient) else None


def _preferred_receiver_token_record(
    recipient: str,
    token_store: PushKitTokenStoreProtocol,
) -> PushKitTokenRecord | None:
    return (
        token_store.retrieve_latest_for_user(recipient, "production")
        or token_store.retrieve_latest_for_user(recipient, "development")
    )


def _call_bootstrap_payload(
    metadata: PendingCallMetadataRequest,
    pending_metadata_reference: str,
    expires_at_ms: int,
) -> dict[str, object]:
    return {
        "roomID": metadata.room_id,
        "roomDisplayName": "SalemX audio call",
        "callIntent": "audio",
        "rtcNotifyEventID": pending_metadata_reference,
        "expirationDate": expires_at_ms / 1000,
    }


def _prepared_invite_apns_diagnostics(
    recipient: str,
    token_record: PushKitTokenRecord,
    voip_send_service: APNsVoIPSandboxSendService,
    pending_metadata_reference: str,
    metadata: PendingCallMetadataRequest,
    expires_at_ms: int,
) -> dict[str, object]:
    lookup_store_key_redacted = redacted_latest_user_record_key(recipient, token_record.environment_class)
    diagnostics = voip_send_service.send(
        APNsVoIPSandboxSendRequest(version=1, dry_run=False),
        token_record,
        payload_kind="real_invite_controlled",
        pending_metadata_reference=pending_metadata_reference,
        call_bootstrap=_call_bootstrap_payload(metadata, pending_metadata_reference, expires_at_ms),
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
        "real_invite_lookup_environment": token_record.environment_class,
        "real_invite_lookup_token_is_hex": is_hex_pushkit_token(token_record.token),
        "upload_invite_store_key_match": True,
        "safe_to_send_apns": True,
        "apns_requested": diagnostics.apns_voip_push_send_requested,
        "apns_provider_invoked": diagnostics.apns_provider_requested,
        "apns_provider_accepted": diagnostics.apns_provider_accepted,
        "APNs_sent": diagnostics.apns_provider_accepted,
        "blocked_reason": "none" if diagnostics.apns_provider_accepted else diagnostics.blocked_reason,
    }


def _background_invite_apns_diagnostics(
    invite_request: ForegroundCallInviteRequest,
    token_store: PushKitTokenStoreProtocol,
    voip_send_service: APNsVoIPSandboxSendService,
    invite_dropped: bool,
    pending_metadata_reference: str | None = None,
    pending_metadata: PendingCallMetadataRequest | None = None,
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
            "safe_to_send_apns": False,
            "apns_requested": False,
            "apns_provider_invoked": False,
            "apns_provider_accepted": False,
            "APNs_sent": False,
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
            "apns_requested": False,
            "apns_provider_invoked": False,
            "apns_provider_accepted": False,
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

    token_record = _preferred_receiver_token_record(invite_request.recipient, token_store)
    environment_class = token_record.environment_class if token_record is not None else "production"
    lookup_store_key_redacted = redacted_latest_user_record_key(invite_request.recipient, environment_class)
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
            "pushkit_upload_environment": environment_class,
            "pushkit_upload_token_is_hex": False,
            "real_invite_lookup_store_key_redacted": lookup_store_key_redacted,
            "real_invite_lookup_record_updated_age_bucket": "missing",
            "real_invite_lookup_environment": environment_class,
            "real_invite_lookup_token_is_hex": False,
            "upload_invite_store_key_match": False,
            "safe_to_send_apns": False,
            "apns_requested": False,
            "apns_provider_invoked": False,
            "apns_provider_accepted": False,
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

    if pending_metadata is None:
        return {
            "real_non_dev_invite_used": True,
            "dev_invite_used": False,
            "background_apns_push_requested": False,
            "background_apns_push_result": "skipped_redacted",
            "persisted_pushkit_token_lookup_result": "found",
            "pushkit_token_redacted": True,
            "safe_to_send_apns": False,
            "APNs_sent": False,
            "blocked_reason": "pending_metadata_missing_before_apns",
        }

    diagnostics = voip_send_service.send(
        APNsVoIPSandboxSendRequest(version=1, dry_run=False),
        token_record,
        payload_kind="real_invite_controlled",
        pending_metadata_reference=pending_metadata_reference,
        call_bootstrap=_call_bootstrap_payload(
            pending_metadata,
            pending_metadata_reference,
            invite_request.invite.expires_at_ms,
        ),
    )
    expected_success = f"{diagnostics.apns_environment}_success"
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
        "real_invite_lookup_environment": token_record.environment_class,
        "real_invite_lookup_token_is_hex": is_hex_pushkit_token(token_record.token),
        "upload_invite_store_key_match": True,
        "safe_to_send_apns": True,
        "apns_requested": diagnostics.apns_voip_push_send_requested,
        "apns_provider_invoked": diagnostics.apns_provider_requested,
        "apns_provider_accepted": diagnostics.apns_voip_push_send_result == expected_success,
        "APNs_sent": diagnostics.apns_voip_push_send_result == expected_success,
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
        "blocked_reason": "none" if diagnostics.apns_voip_push_send_result == expected_success else diagnostics.blocked_reason,
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


def _is_direct_loopback_request(request: Request) -> bool:
    if request.client is None:
        return False
    if any(header in request.headers for header in ("forwarded", "x-forwarded-for", "x-real-ip")):
        return False
    return request.client.host in {"127.0.0.1", "::1", "localhost"}


def _pending_store_root_audit_credential(
    explicit_credential: str | None,
    runtime_config: ServiceConfig | None,
) -> str | None:
    if explicit_credential is not None:
        return explicit_credential if len(explicit_credential) >= 32 else None
    if runtime_config is None or runtime_config.storage_key_secret is None:
        return None
    return hmac.new(
        runtime_config.storage_key_secret.encode("utf-8"),
        PENDING_STORE_AUDIT_CREDENTIAL_CONTEXT,
        hashlib.sha256,
    ).hexdigest()


def _production_dispatch_store_for_runtime(config: ServiceConfig | None) -> PostgresProductionDispatchStore | None:
    if config is None or not config.direct_call_pending_store_enabled:
        return None
    if config.direct_call_database_dsn is None or config.direct_call_store_master_key is None:
        return None
    return PostgresProductionDispatchStore(config.direct_call_database_dsn, config.direct_call_store_master_key)


def _require_dispatch_store(store: PostgresProductionDispatchStore | None) -> PostgresProductionDispatchStore:
    if store is None:
        raise CallServiceError(status_code=503,
                               errcode="M_DIRECT_CALL_DISPATCH_STORE_UNAVAILABLE",
                               error="Direct-call dispatch storage is unavailable.")
    return store


def _token_binding_revision(record: PushKitTokenRecord | None) -> int:
    binding = record.authoritative_binding if record is not None else None
    if binding is None:
        raise CallServiceError(status_code=409,
                               errcode="M_DIRECT_CALL_RECEIVER_BINDING_UNAVAILABLE",
                               error="Registered device binding is unavailable.")
    return binding.token_binding_revision


def _dispatch_identity_for_record(user_id: str, record: PushKitTokenRecord | None) -> DispatchIdentity:
    binding = record.authoritative_binding if record is not None else None
    generation = record.app_session_generation if record is not None else None
    if binding is None or generation is None:
        raise CallServiceError(status_code=409,
                               errcode="M_DIRECT_CALL_CAPABILITY_UNAVAILABLE",
                               error="Direct-call capability is unavailable.")
    return DispatchIdentity(user_id=user_id, device_id=binding.device_binding, session_generation=generation)


def _capable_record_for_identity(user_id: str,
                                 device_id: str | None,
                                 generation: str,
                                 token_store: PushKitTokenStoreProtocol) -> PushKitTokenRecord:
    if device_id is None:
        raise CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="A device-bound session is required.")
    for environment in ("production", "development"):
        record = token_store.retrieve(user_id, device_id, environment)
        if record is not None and record.supports_direct_audio_v1() and record.app_session_generation == generation:
            return record
    raise CallServiceError(status_code=403,
                           errcode="M_DIRECT_CALL_CAPABILITY_MISMATCH",
                           error="Direct-call capability does not match the authenticated session.")


def _capable_latest_record(user_id: str, token_store: PushKitTokenStoreProtocol) -> PushKitTokenRecord:
    record = _preferred_receiver_token_record(user_id, token_store)
    if record is None or not record.supports_direct_audio_v1():
        raise CallServiceError(status_code=409,
                               errcode="M_DIRECT_CALL_CAPABILITY_UNAVAILABLE",
                               error="The receiver does not support direct-call protocol v1.")
    return record


def _required_opaque_generation(payload: dict[str, Any]) -> str:
    value = payload.get("app_session_generation")
    if not isinstance(value, str) or not value or len(value) > 256:
        raise bad_request(error="Invalid app session generation.")
    return value


def _required_opaque_reference(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value or len(value) > 512:
        raise bad_request(error="Invalid direct-call dispatch reference.")
    return value


def _required_dispatch_id(payload: dict[str, Any]) -> UUID:
    value = payload.get("dispatch_id")
    if not isinstance(value, str):
        raise bad_request(error="Invalid direct-call dispatch identifier.")
    try:
        return UUID(value)
    except ValueError as error:
        raise bad_request(error="Invalid direct-call dispatch identifier.") from error


def _exact_dispatch_request(payload: dict[str, Any], require_receiver_reference: bool) -> tuple[UUID, str, str]:
    receiver_reference = _required_opaque_reference(payload, "receiver_reference") if require_receiver_reference else ""
    return (
        _required_dispatch_id(payload),
        _required_opaque_reference(payload, "sender_reference"),
        receiver_reference,
    )


def _bounded_dispatch_expiry(expires_at_ms: int, now_ms: int) -> int:
    remaining_ms = expires_at_ms - now_ms
    if remaining_ms <= 0 or remaining_ms > 120_000:
        raise bad_request(error="Direct-call dispatch expiry must be between 1 and 120 seconds.")
    return max(1, (remaining_ms + 999) // 1000)


def _stored_dispatch_success() -> dict[str, object]:
    return {
        "dispatch_protocol_version": 1,
        "state": DispatchState.SENT.value,
        "APNs_sent": True,
        "APNs_send_count": 1,
        "raw_identifiers_logged": False,
    }


def _call_service_error_for_dispatch_store(error: ProductionDispatchStoreError) -> CallServiceError:
    if isinstance(error, DispatchOwnershipError):
        return CallServiceError(status_code=403, errcode="M_FORBIDDEN", error="Direct-call dispatch ownership mismatch.")
    if isinstance(error, DispatchNotFoundError):
        return CallServiceError(status_code=404, errcode="M_NOT_FOUND", error="Direct-call dispatch was not found.")
    if isinstance(error, DispatchExpiredError):
        return CallServiceError(status_code=410, errcode="M_DIRECT_CALL_DISPATCH_EXPIRED", error="Direct-call dispatch expired.")
    if isinstance(error, (DispatchTransitionError, MetadataAuthenticationError)):
        return CallServiceError(status_code=409, errcode="M_DIRECT_CALL_DISPATCH_CONFLICT", error="Direct-call dispatch state conflict.")
    return CallServiceError(status_code=503,
                            errcode="M_DIRECT_CALL_DISPATCH_STORE_UNAVAILABLE",
                            error="Direct-call dispatch storage is unavailable.")


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
