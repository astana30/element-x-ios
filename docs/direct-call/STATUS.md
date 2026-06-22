# Native Direct-Call Status

## Current Phase

After 2.48T-Physical4-MissedSurface — a single real non-dev sandbox APNs was sent and reached PushKit, but the first controlled audio-connect physical attempt did not complete because CallKit report completion/surface was not observed and no CallKit Answer action was received. No pending metadata fetch, media credentials request, media connect, LiveKit join, microphone/camera permission, Matrix event emission, full call flow, or retry was performed. The next phase is `2.48T-CallKitSurfaceRepair — fix CallKit report completion/surface before any APNs retry`.

## Latest App Code Checkpoint

2.39V `bf4ae10a5` `Polish native audio foreground limitation UX`

## Latest Backend Code Checkpoint

2.47E `Verify server allocation token expiry`

## Latest Signing Checkpoint

2.40F `fa9e71689` `Merge branch 'salemx-2.40f-signing-remediation' into salemx-native-direct-calls`

Signing proof tag: `salemx-2.40f-signing-proof-20260608`

Proof doc: `docs/direct-call/APPLE_SIGNING_PROOF_2026-06-08.md`

## Latest SDK Checkpoint

f7c2cfe5c `Add direct-call media key envelope crypto tests`

SDK tag: `salemx-direct-call-key-envelope-f7c2cfe5c`

## Latest Wrapper Checkpoint

1e58d0a `Add direct-call media key envelope bindings`

Wrapper tag: `salemx-matrix-rust-components-swift-26.03.10-salemx.3`

## Published Artifact

- URL: https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip
- Checksum: `654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e`

## Proven Checkpoints

- 2.48T-Physical4-MissedSurface closes the physical attempt as missed/no-answer/no-surface triage:
  - A single sandbox APNs was sent through the real non-dev invite path and was not repeated:
    ```text
    invite_send_attempted=true
    invite_http_code=200
    real_non_dev_invite_used=True
    dev_invite_used=False
    background_apns_push_requested=True
    background_apns_push_result=sandbox_success
    APNs_sent=true
    blocked_reason=none
    ```
  - The phase-specific physical proof at `/tmp/salemx-voip-push-receipt-proof-2.48t-physical4-polled.txt` showed PushKit receipt but no answer surface/action completion:
    ```text
    proof_generation=generation_3
    proof_last_updated_by=voip_push_callback
    physical_voip_push_received=true
    pushkit_callback_invoked=true
    pushkit_payload_kind=real_invite_controlled
    callkit_report_requested=true
    callkit_report_result=pending
    callkit_report_completion_observed=false
    pushkit_completion_called=false
    callkit_first_action_kind=none
    callkit_answer_action_received=false
    ```
  - Required conclusion:
    ```text
    2.48T-Physical4 = APNs sent once and PushKit received, but first controlled audio-connect did not complete.
    Reason: CallKit report remained pending, report completion was not observed, PushKit completion was not called, and no CallKit Answer action was received.
    No pending metadata fetch.
    No media credentials request.
    No media connect.
    No LiveKit join.
    No microphone permission.
    No camera permission.
    No Matrix event emit.
    No full call flow.
    No retry performed.
    ```
  - Connect and privacy safety remained closed:
    ```text
    pending_metadata_fetch_requested=false
    pending_metadata_fetch_result=not_requested
    media_credentials_requested=false
    media_credentials_result=not_requested
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    livekit_connect_audio_invoked=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    blocked_reason=none
    ```
  - This is not a first controlled audio-connect proof close. Next phase: `2.48T-CallKitSurfaceRepair — fix CallKit report completion/surface before any APNs retry`.
  - No repeated APNs, production APNs, `dev/invite`, connect retry, LiveKit join, microphone/camera permission request, Matrix event emission, full call flow, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48T-RealBridge real controlled audio-connect bridge is wired:
  - This is a code/test implementation phase only; it is not a physical APNs, media-connect, LiveKit join, microphone-permission, camera-permission, Matrix-event, or full-call task.
  - The DEBUG/test-controlled bridge replaces the fake-only proof boundary with a narrow runtime boundary that can call `DirectCallEngine.acceptCall`, which reaches `connectMediaIfReady`, `LiveKitDirectCallMediaEngine.connectAudio`, and the LiveKit audio connect boundary only after every gate is true.
  - The bridge proof fields are present and default disabled:
    ```text
    controlled_connect_real_bridge_present=true
    controlled_connect_real_bridge_debug_only=true
    controlled_connect_real_bridge_default_disabled=true
    controlled_connect_real_bridge_requires_credentials=true
    controlled_connect_real_bridge_requires_enablement=true
    controlled_connect_real_bridge_requires_operator_approval=true
    controlled_connect_real_bridge_requires_future_phase_permission=true
    controlled_connect_real_bridge_audio_only=true
    controlled_connect_real_bridge_video_allowed=false
    controlled_connect_real_bridge_matrix_events_allowed=false
    controlled_connect_real_bridge_raw_credentials_logged=false
    controlled_connect_real_bridge_one_shot=true
    controlled_connect_real_bridge_allowed=false
    controlled_connect_real_bridge_blocked_reason=default_disabled_no_connect
    controlled_connect_real_bridge_blocked_before_connect_media=true
    controlled_connect_real_bridge_can_call_connect_media_when_all_gates_true=true
    controlled_connect_real_bridge_can_call_livekit_audio_when_all_gates_true=true
    controlled_connect_real_bridge_uses_fake_engine_in_tests_only=true
    controlled_connect_real_bridge_uses_real_runtime_boundary_when_not_test=true
    ```
  - Default runtime remains no-connect:
    ```text
    controlled_connect_first_attempt_requested=false
    controlled_connect_first_attempt_allowed=false
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    livekit_connect_audio_invoked=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - When receiver session validation, fresh credentials, enablement, operator approval, future phase permission, activation, execution, audio-only safety, and one-shot gates are all true, unit/source-guard proof shows the test seam can reach a fake media engine only in tests, while the non-test runtime boundary can reach the real connect-media boundary.
  - Next phase: `2.48T-Physical4 — one-shot first controlled audio-connect physical attempt`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, physical media connection, real device LiveKit join, microphone/camera permission request on device, Matrix event emission, full direct-call flow, default controlled-connect enablement, default operator approval, default future physical-connect permission, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48T-RealRuntime real controlled audio-connect runtime path is wired:
  - This is a code/test preparation phase only; it is not a physical APNs, media-connect, LiveKit join, microphone-permission, camera-permission, Matrix-event, or full-call task.
  - `requestControlledMediaCredentialsForControlledRuntime` now feeds the controlled runtime preflight after authenticated pending metadata and media credentials; default runtime remains blocked.
  - The real runtime proof fields are present and default disabled:
    ```text
    controlled_connect_real_runtime_path_present=true
    controlled_connect_real_runtime_path_debug_only=true
    controlled_connect_real_runtime_path_default_disabled=true
    controlled_connect_real_runtime_path_requires_credentials=true
    controlled_connect_real_runtime_path_requires_enablement=true
    controlled_connect_real_runtime_path_requires_operator_approval=true
    controlled_connect_real_runtime_path_requires_future_phase_permission=true
    controlled_connect_real_runtime_path_audio_only=true
    controlled_connect_real_runtime_path_video_allowed=false
    controlled_connect_real_runtime_path_matrix_events_allowed=false
    controlled_connect_real_runtime_path_raw_credentials_logged=false
    controlled_connect_real_runtime_path_one_shot=true
    controlled_connect_real_runtime_path_allowed=false
    controlled_connect_real_runtime_path_blocked_reason=default_disabled_no_connect
    controlled_connect_real_runtime_path_blocked_before_engine=true
    controlled_connect_real_runtime_path_can_call_connect_media_when_all_gates_true=true
    controlled_connect_real_runtime_path_can_call_livekit_audio_when_all_gates_true=true
    ```
  - Default runtime remains no-connect:
    ```text
    enablement_enabled=false
    operator_approved=false
    future_phase_permitted=false
    activation_allowed=false
    execution_allowed=false
    controlled_connect_first_attempt_requested=false
    controlled_connect_first_attempt_allowed=false
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    livekit_connect_audio_invoked=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - When receiver session, fresh credentials, enablement, operator approval, future phase permission, activation, execution, audio-only safety, and one-shot gates are all true in the fake/test seam, the runtime path records one controlled first attempt with `media_connect_requested=true`, `media_connect_attempted=true`, `livekit_join_requested=true`, `livekit_connect_audio_invoked=true`, `controlled_connect_first_attempt_started=true`, `controlled_connect_first_attempt_completed=true`, and `controlled_connect_first_attempt_repeated=false`.
  - Next phase: `2.48T-Physical3 — one-shot first controlled audio-connect physical attempt`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, physical media connection, real LiveKit join, microphone/camera permission request on device, Matrix event emission, full direct-call flow, default controlled-connect enablement, default operator approval, default future physical-connect permission, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48T-RealPath true one-shot audio-connect runtime path is prepared:
  - This is a code/test preparation phase only; it is not a physical APNs, media-connect, LiveKit join, microphone-permission, camera-permission, Matrix-event, or full-call task.
  - The real runtime path proof fields are present and default disabled:
    ```text
    controlled_connect_real_audio_path_present=true
    controlled_connect_real_audio_path_debug_only=true
    controlled_connect_real_audio_path_default_disabled=true
    controlled_connect_real_audio_path_requires_enablement=true
    controlled_connect_real_audio_path_requires_operator_approval=true
    controlled_connect_real_audio_path_requires_future_phase_permission=true
    controlled_connect_real_audio_path_audio_only=true
    controlled_connect_real_audio_path_video_allowed=false
    controlled_connect_real_audio_path_matrix_events_allowed=false
    controlled_connect_real_audio_path_raw_credentials_logged=false
    controlled_connect_real_audio_path_one_shot=true
    controlled_connect_real_audio_path_allowed=false
    controlled_connect_real_audio_path_blocked_reason=default_disabled_no_connect
    controlled_connect_real_audio_path_blocked_before_engine=true
    controlled_connect_real_audio_path_can_reach_engine_when_all_gates_true=true
    ```
  - Default runtime remains no-connect:
    ```text
    controlled_connect_first_attempt_requested=false
    controlled_connect_first_attempt_allowed=false
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    livekit_connect_audio_invoked=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - When all gates are explicitly true in the fake/test seam, the real path can reach the existing `DirectCallEngine.connectMediaIfReady` / `LiveKitDirectCallMediaEngine.connectAudio` boundary without performing physical media.
  - Next phase: `2.48T-Physical2 — one-shot first controlled audio-connect physical attempt`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, physical media connection, real LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, default controlled-connect enablement, default operator approval, default future physical-connect permission, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48T-Prep first controlled audio-connect attempt plumbing is implemented:
  - This is a code/test preparation phase only; it is not a physical APNs, media-connect, LiveKit join, or real-call task.
  - Default proof fields:
    ```text
    controlled_connect_first_attempt_requested=false
    controlled_connect_first_attempt_allowed=false
    controlled_connect_first_attempt_started=false
    controlled_connect_first_attempt_completed=false
    controlled_connect_first_attempt_repeated=false
    controlled_connect_first_attempt_result=not_requested
    controlled_connect_first_attempt_error_bucket=none
    controlled_connect_first_attempt_audio_only=true
    controlled_connect_first_attempt_video_allowed=false
    controlled_connect_first_attempt_matrix_events_allowed=false
    controlled_connect_first_attempt_raw_credentials_logged=false
    controlled_connect_first_attempt_blocked_reason=default_disabled_no_connect
    ```
  - Runtime default remains no-connect:
    ```text
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - The DEBUG/test-only fake boundary can prove all gates explicitly true without real network/media:
    ```text
    controlled_connect_first_attempt_requested=true
    controlled_connect_first_attempt_allowed=true
    controlled_connect_first_attempt_started=true
    controlled_connect_first_attempt_completed=true
    controlled_connect_first_attempt_repeated=false
    controlled_connect_first_attempt_result=success_redacted
    controlled_connect_first_attempt_error_bucket=none
    ```
  - The fake boundary records only test-safe media attempt fields, with no real LiveKit network, camera permission, Matrix event emission, or full flow.
  - Next phase: `2.48T-Physical2 — one-shot first controlled audio-connect physical attempt`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, physical media connection, real LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, default controlled-connect enablement, default operator approval, default future physical-connect permission, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48S final pre-connect operator gate is ready:
  - Conclusion:
    ```text
    2.48S = final pre-connect operator gate
    physical connect not performed
    controlled connect not enabled
    default remains no-connect
    ```
  - Final go/no-go checklist:
    ```text
    operator_gate_receiver_app_session_validated=true
    operator_gate_terminal_tokens_required=true
    operator_gate_room_validation_required=true
    operator_gate_single_sandbox_apns_only=true
    operator_gate_green_answer_required=true
    operator_gate_audio_only=true
    operator_gate_video_disabled=true
    operator_gate_matrix_events_disabled=true
    operator_gate_raw_credentials_logging_forbidden=true
    operator_gate_rollback_required=true
    operator_gate_one_shot_only=true
    operator_gate_no_repeat_apns=true
    operator_gate_stop_after_first_connect_result=true
    ```
  - Allowed future first-connect scope:
    ```text
    allow_one_controlled_audio_connect_attempt=true
    allow_livekit_join_attempt=true
    allow_microphone_permission_request=only_if_required_for_audio_connect
    allow_camera_permission_request=false
    allow_matrix_event_emit=false
    allow_full_call_flow=false
    allow_repeated_apns=false
    ```
  - Final stop conditions:
    ```text
    stop_if_receiver_app_session_invalid=true
    stop_if_terminal_tokens_invalid=true
    stop_if_room_validation_fails=true
    stop_if_pending_metadata_fetch_fails=true
    stop_if_credentials_fail=true
    stop_if_enablement_not_enabled=true
    stop_if_operator_not_approved=true
    stop_if_future_phase_not_permitted=true
    stop_if_video_enabled=true
    stop_if_camera_permission_requested=true
    stop_if_matrix_event_emit_requested=true
    stop_if_full_call_flow_started=true
    stop_after_first_connect_result=true
    ```
  - Required proof fields for the future first controlled connect:
    ```text
    controlled_connect_enablement_enabled=true
    controlled_connect_enablement_operator_approved=true
    controlled_connect_enablement_future_phase_permitted=true
    controlled_connect_enablement_execution_allowed=true
    controlled_audio_connect_activation_allowed=true
    controlled_audio_connect_execution_future_phase_permitted=true
    controlled_audio_connect_execution_allowed=true
    media_connect_requested=true
    media_connect_attempted=true
    livekit_join_requested=true
    livekit_connect_audio_invoked=true
    controlled_connect_first_attempt_result=<success_or_blocked_redacted>
    controlled_connect_first_attempt_error_bucket=<none_or_redacted_bucket>
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - `2.48S result = ready for one-shot first controlled audio-connect physical attempt`.
  - Next phase: `2.48T — one-shot first controlled audio-connect physical attempt`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, operator approval enablement, future physical-connect permission enablement, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced during this docs-only gate.
- 2.48R physical proof of first-run activation path default-disabled succeeded:
  - `2.48R = physical proof succeeded`.
  - Proof file: `/tmp/salemx-voip-push-receipt-proof-2.48r-polled.txt`.
  - Proof generation: `generation_8`.
  - One corrected flat-schema sandbox APNs send returned `invite_http_code=200`, `background_apns_push_result=sandbox_success`, and `blocked_reason=none`; APNs must not be repeated for this proof.
  - PushKit, CallKit, pending metadata, and credentials succeeded:
    ```text
    physical_voip_push_received=true
    pushkit_callback_invoked=true
    pushkit_payload_kind=real_invite_controlled
    callkit_first_action_kind=answer
    callkit_answer_action_delivered=true
    callkit_answer_action_received=true
    callkit_answer_action_fulfilled=true
    pending_metadata_fetch_result=success_redacted
    pending_metadata_fetch_http_status_bucket=2xx
    pending_metadata_fetch_errcode=none
    pending_metadata_fetch_failure_reason=none
    foreground_pending_call_metadata_handoff_observed=true
    media_credentials_result=success_redacted
    media_credentials_payload_redacted=true
    ```
  - The 2.48Q first-run controlled audio-connect activation path was present on-device and remained default-disabled:
    ```text
    controlled_audio_connect_activation_path_present=true
    controlled_audio_connect_activation_debug_only=true
    controlled_audio_connect_activation_one_shot=true
    controlled_audio_connect_activation_default_disabled=true
    controlled_audio_connect_activation_requires_receiver_session=true
    controlled_audio_connect_activation_requires_fresh_credentials=true
    controlled_audio_connect_activation_requires_enablement=true
    controlled_audio_connect_activation_requires_operator_approval=true
    controlled_audio_connect_activation_requires_future_phase_permission=true
    controlled_audio_connect_activation_audio_only=true
    controlled_audio_connect_activation_video_allowed=false
    controlled_audio_connect_activation_matrix_events_allowed=false
    controlled_audio_connect_activation_raw_credentials_logged=false
    controlled_audio_connect_activation_rollback_available=true
    controlled_audio_connect_activation_allowed=false
    controlled_audio_connect_activation_blocked_reason=activation_path_disabled_no_connect
    controlled_audio_connect_activation_blocked_before_engine=true
    controlled_audio_connect_activation_blocked_before_livekit_join=true
    controlled_audio_connect_activation_blocked_before_permissions=true
    controlled_audio_connect_activation_blocked_before_matrix_events=true
    ```
  - The 2.48N execution gate remained default-blocked and the media-connect preflight reached the guard before connect:
    ```text
    controlled_audio_connect_execution_gate_present=true
    controlled_audio_connect_execution_debug_only=true
    controlled_audio_connect_execution_audio_only=true
    controlled_audio_connect_execution_video_allowed=false
    controlled_audio_connect_execution_matrix_events_allowed=false
    controlled_audio_connect_execution_raw_credentials_logged=false
    controlled_audio_connect_execution_future_phase_permitted=false
    controlled_audio_connect_execution_allowed=false
    controlled_audio_connect_execution_blocked_reason=future_phase_not_permitted_no_connect
    media_connect_preflight_requested=true
    media_connect_preflight_metadata_available=true
    media_connect_preflight_credentials_available=true
    media_connect_preflight_token_present=true
    media_connect_preflight_url_present=true
    media_connect_preflight_expires_at_present=true
    media_connect_execution_allowed=false
    media_connect_preflight_result=blocked_before_connect_redacted
    media_connect_engine_invoked=false
    livekit_connect_audio_invoked=false
    ```
  - Safety boundary:
    ```text
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    blocked_reason=none
    ```
  - Next phase: `2.48S — final pre-connect operator gate, no physical connect`.
  - No repeated APNs, production APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, operator approval enablement, future physical-connect permission enablement, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced during close-out.
- 2.48Q first controlled audio-connect activation path is implemented, default disabled:
  - `2.48Q = first controlled audio-connect activation path, default disabled, no physical connect`.
  - Added `SalemXControlledAudioConnectActivationPath` beside the existing controlled-connect switch, enablement, and audio execution gate.
  - The path is explicit, DEBUG/test-controlled, one-shot, audio-only, rollback-ready, and redacted. It requires receiver app session validation, fresh credentials, enablement, operator approval, and future phase permission before activation could ever be allowed.
  - Default activation path proof:
    ```text
    controlled_audio_connect_activation_path_present=true
    controlled_audio_connect_activation_debug_only=true
    controlled_audio_connect_activation_one_shot=true
    controlled_audio_connect_activation_default_disabled=true
    controlled_audio_connect_activation_requires_receiver_session=true
    controlled_audio_connect_activation_requires_fresh_credentials=true
    controlled_audio_connect_activation_requires_enablement=true
    controlled_audio_connect_activation_requires_operator_approval=true
    controlled_audio_connect_activation_requires_future_phase_permission=true
    controlled_audio_connect_activation_audio_only=true
    controlled_audio_connect_activation_video_allowed=false
    controlled_audio_connect_activation_matrix_events_allowed=false
    controlled_audio_connect_activation_raw_credentials_logged=false
    controlled_audio_connect_activation_rollback_available=true
    controlled_audio_connect_activation_allowed=false
    controlled_audio_connect_activation_blocked_reason=activation_path_disabled_no_connect
    controlled_audio_connect_activation_blocked_before_engine=true
    controlled_audio_connect_activation_blocked_before_livekit_join=true
    controlled_audio_connect_activation_blocked_before_permissions=true
    controlled_audio_connect_activation_blocked_before_matrix_events=true
    ```
  - Default no-connect fields remain:
    ```text
    controlled_connect_enablement_enabled=false
    controlled_connect_enablement_operator_approved=false
    controlled_connect_enablement_future_phase_permitted=false
    controlled_audio_connect_execution_allowed=false
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - Targeted source-guard tests prove the activation path exists, is DEBUG/test-only, default-disabled, one-shot, receiver-session gated, fresh-credential gated, enablement gated, operator-approval gated, future-phase gated, audio-only, video-disabled, Matrix-event-disabled, raw-credential-log-disabled, rollback-ready, and blocked before engine/LiveKit/permissions/Matrix events.
  - Existing 2.48K enablement, 2.48N execution gate, and 2.48O no-connect proof expectations remain preserved.
  - Next phase: `2.48R — physical proof of first-run activation path default-disabled, no LiveKit join`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, physical media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, future physical-connect permission enablement, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48P first controlled audio-connect activation plan is ready:
  - This is a docs-only activation plan for the first future controlled audio-only connect attempt; it is not a physical APNs task, media-connect execution task, LiveKit join task, or real-call task.
  - Conclusion:
    ```text
    2.48P = first controlled audio-connect activation plan
    physical connect not performed
    controlled connect not enabled
    default remains no-connect
    ```
  - First controlled audio-connect activation requirements:
    ```text
    first_connect_requires_receiver_app_session_validated=true
    first_connect_requires_terminal_tokens_valid=true
    first_connect_requires_room_validation_pass=true
    first_connect_requires_single_sandbox_apns=true
    first_connect_requires_green_answer=true
    first_connect_requires_fresh_credentials=true
    first_connect_requires_enablement_enabled=true
    first_connect_requires_operator_approved=true
    first_connect_requires_future_phase_permitted=true
    first_connect_audio_only=true
    first_connect_video_allowed=false
    first_connect_matrix_events_allowed=false
    first_connect_raw_credentials_logged=false
    first_connect_rollback_available=true
    first_connect_one_shot_only=true
    ```
  - Allowed future scope:
    ```text
    allow_audio_connect_attempt=true
    allow_livekit_join_attempt=true
    allow_microphone_permission_request=only_if_required_for_audio_connect
    allow_camera_permission_request=false
    allow_matrix_event_emit=false
    allow_full_call_flow=false
    allow_repeated_apns=false
    ```
  - First controlled connect stop conditions:
    ```text
    stop_if_receiver_app_session_invalid=true
    stop_if_pending_metadata_fetch_fails=true
    stop_if_credentials_fail=true
    stop_if_enablement_not_enabled=true
    stop_if_operator_not_approved=true
    stop_if_future_phase_not_permitted=true
    stop_if_video_permission_requested=true
    stop_if_camera_permission_requested=true
    stop_if_matrix_event_emit_requested=true
    stop_if_full_call_flow_started=true
    stop_after_first_connect_result=true
    ```
  - Required proof fields for the future first controlled connect:
    ```text
    controlled_audio_connect_execution_future_phase_permitted=true
    controlled_audio_connect_execution_allowed=true
    media_connect_requested=true
    media_connect_attempted=true
    livekit_join_requested=true
    livekit_connect_audio_invoked=true
    controlled_connect_first_attempt_result=<success_or_blocked_redacted>
    controlled_connect_first_attempt_error_bucket=<none_or_redacted_bucket>
    microphone_permission_requested=<true_if_required_or_false_if_not_required>
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - Rollback expectations:
    ```text
    rollback_disable_enablement=true
    rollback_clear_operator_approval=true
    rollback_clear_future_phase_permission=true
    rollback_restore_execution_allowed_false=true
    rollback_restore_no_connect_default=true
    ```
  - Readiness conclusion:
    ```text
    2.48P result = ready to implement first controlled audio-connect activation path, no physical connect performed
    ```
  - Next phase: `2.48Q — implement first controlled audio-connect activation path, default disabled, no physical connect`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, future physical-connect permission enablement, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48O physical proof of the audio-connect execution gate succeeded with no media connect:
  - `2.48O = physical proof succeeded`.
  - Proof path: `/tmp/salemx-voip-push-receipt-proof-2.48o-polled.txt`.
  - Proof generation: `generation_8`.
  - The one-shot corrected flat-schema real non-dev invite/APNs path returned `invite_http_code=200`, `real_non_dev_invite_used=True`, `dev_invite_used=False`, `background_apns_push_requested=True`, `background_apns_push_result=sandbox_success`, and `blocked_reason=none`.
  - Answer pipeline succeeded:
    ```text
    physical_voip_push_received=true
    pushkit_callback_invoked=true
    pushkit_payload_kind=real_invite_controlled
    callkit_first_action_kind=answer
    callkit_answer_action_delivered=true
    callkit_answer_action_received=true
    callkit_answer_action_fulfilled=true
    pending_metadata_fetch_result=success_redacted
    pending_metadata_fetch_http_status_bucket=2xx
    pending_metadata_fetch_errcode=none
    pending_metadata_fetch_failure_reason=none
    foreground_pending_call_metadata_handoff_observed=true
    media_credentials_result=success_redacted
    ```
  - 2.48K enablement remained present and default-off:
    ```text
    controlled_connect_enablement_wiring_present=true
    controlled_connect_enablement_debug_only=true
    controlled_connect_enablement_default_off=true
    controlled_connect_enablement_operator_approval_required=true
    controlled_connect_enablement_one_shot=true
    controlled_connect_enablement_fresh_credentials_required=true
    controlled_connect_enablement_audio_only=true
    controlled_connect_enablement_video_allowed=false
    controlled_connect_enablement_matrix_events_allowed=false
    controlled_connect_enablement_raw_credentials_logged=false
    controlled_connect_enablement_rollback_available=true
    controlled_connect_enablement_enabled=false
    controlled_connect_enablement_operator_approved=false
    controlled_connect_enablement_future_phase_permitted=false
    controlled_connect_enablement_execution_allowed=false
    controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
    ```
  - 2.48N controlled audio-connect execution gate was present on-device and default-blocked:
    ```text
    controlled_audio_connect_execution_gate_present=true
    controlled_audio_connect_execution_debug_only=true
    controlled_audio_connect_execution_audio_only=true
    controlled_audio_connect_execution_video_allowed=false
    controlled_audio_connect_execution_matrix_events_allowed=false
    controlled_audio_connect_execution_raw_credentials_logged=false
    controlled_audio_connect_execution_requires_enablement=true
    controlled_audio_connect_execution_requires_operator_approval=true
    controlled_audio_connect_execution_requires_future_phase_permission=true
    controlled_audio_connect_execution_future_phase_permitted=false
    controlled_audio_connect_execution_allowed=false
    controlled_audio_connect_execution_blocked_reason=future_phase_not_permitted_no_connect
    controlled_audio_connect_execution_blocked_before_engine=true
    controlled_audio_connect_execution_blocked_before_livekit_join=true
    controlled_audio_connect_execution_blocked_before_permissions=true
    controlled_audio_connect_execution_blocked_before_matrix_events=true
    ```
  - Media-connect preflight reached the guard and stopped before connect:
    ```text
    media_connect_preflight_requested=true
    media_connect_preflight_metadata_available=true
    media_connect_preflight_credentials_available=true
    media_connect_preflight_token_present=true
    media_connect_preflight_url_present=true
    media_connect_preflight_expires_at_present=true
    media_connect_execution_allowed=false
    media_connect_preflight_result=blocked_before_connect_redacted
    media_connect_engine_invoked=false
    livekit_connect_audio_invoked=false
    ```
  - Safety boundary remained intact:
    ```text
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    blocked_reason=none
    ```
  - `2.48O result = controlled audio-connect execution gate present on-device, DEBUG-only, audio-only, video disabled, Matrix events disabled, raw credentials not logged, future phase not permitted, execution not allowed, blocked before engine/LiveKit/permissions/Matrix events, no media connect`.
  - Next phase: `2.48P — first controlled audio-connect activation plan, no physical connect`.
  - No repeated APNs, production APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, future physical-connect permission enablement, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48N first controlled audio-connect execution path is implemented, default disabled:
  - `2.48N = first controlled audio-connect execution path, default disabled, no physical connect`.
  - Added `SalemXControlledAudioConnectExecutionGate` beside the existing DEBUG-only controlled-connect switch, activation wiring, and enablement wiring proof surface.
  - The gate is explicit and redacted: it receives only credential presence plus the existing activation/enablement configurations, and it logs booleans/reasons only.
  - Default gate proof:
    ```text
    controlled_audio_connect_execution_gate_present=true
    controlled_audio_connect_execution_debug_only=true
    controlled_audio_connect_execution_audio_only=true
    controlled_audio_connect_execution_video_allowed=false
    controlled_audio_connect_execution_matrix_events_allowed=false
    controlled_audio_connect_execution_raw_credentials_logged=false
    controlled_audio_connect_execution_requires_enablement=true
    controlled_audio_connect_execution_requires_operator_approval=true
    controlled_audio_connect_execution_requires_future_phase_permission=true
    controlled_audio_connect_execution_future_phase_permitted=false
    controlled_audio_connect_execution_allowed=false
    controlled_audio_connect_execution_blocked_reason=future_phase_not_permitted_no_connect
    controlled_audio_connect_execution_blocked_before_engine=true
    controlled_audio_connect_execution_blocked_before_livekit_join=true
    controlled_audio_connect_execution_blocked_before_permissions=true
    controlled_audio_connect_execution_blocked_before_matrix_events=true
    ```
  - The execution gate is recorded from the media-connect preflight after credentials are present, but default execution remains blocked before `connectMediaIfReady`, `LiveKitDirectCallMediaEngine.connectAudio`, microphone/camera permission, Matrix event emission, or full flow.
  - Existing safety fields remain false:
    ```text
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - Targeted source-guard tests prove the execution gate exists, is DEBUG/test-only, requires enablement/operator/future permission, keeps future physical-connect permission false by default, keeps execution false by default, requires every gate before execution, preserves audio-only scope, keeps video/Matrix events/raw credential logging disabled, keeps media engine and LiveKit `connectAudio` uninvoked, keeps permission and full-flow paths absent, and restores no-connect on rollback/default state.
  - Next phase: `2.48O — physical proof of audio-connect execution gate default-blocked, no LiveKit join`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, physical media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, future physical-connect permission enablement, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48M controlled-connect first-run readiness gate is complete:
  - `2.48M = controlled-connect first-run readiness gate`.
  - `physical connect not performed`.
  - `controlled connect not enabled`.
  - `default remains no-connect`.
  - Review conclusion: `DirectCallEngine.requestMediaCredentials` remains the credentials-only boundary; `DirectCallEngine.connectMediaIfReady` remains the private media boundary that requires a connecting session, ready encryption, valid key handle, and audio intent; `LiveKitDirectCallMediaEngine.connectAudio` remains the first real media-connect boundary and stays unreached until an explicitly approved later phase.
  - The DEBUG proof adapter's controlled-connect switch, activation wiring, and enablement wiring remain default-disabled/default-off, rollback-ready, audio-only, video-disabled, Matrix-event-disabled, raw-credential-log-disabled, and blocked before engine/LiveKit/permissions/events.
  - Readiness checklist:
    ```text
    readiness_pushkit_apns_path_proved=true
    readiness_callkit_answer_path_proved=true
    readiness_pending_metadata_fetch_proved=true
    readiness_receiver_app_session_validated=true
    readiness_media_credentials_proved=true
    readiness_credentials_cleanup_proved=true
    readiness_server_token_expiry_proved=true
    readiness_enablement_default_off_proved=true
    readiness_enablement_one_shot_proved=true
    readiness_audio_only_scope_proved=true
    readiness_video_disabled=true
    readiness_matrix_events_disabled=true
    readiness_raw_credentials_not_logged=true
    readiness_rollback_available=true
    readiness_tests_passed=true
    readiness_physical_connect_not_yet_approved=true
    ```
  - First controlled connect blockers:
    ```text
    block_if_receiver_app_session_invalid=true
    block_if_terminal_tokens_invalid=true
    block_if_room_validation_fails=true
    block_if_credentials_fail=true
    block_if_enablement_not_default_off=true
    block_if_video_enabled=true
    block_if_matrix_events_enabled=true
    block_if_raw_credentials_logged=true
    block_if_rollback_missing=true
    block_if_tests_fail=true
    ```
  - Readiness conclusion:
    ```text
    2.48M result = ready for first controlled audio-only connect implementation phase, no physical connect performed
    ```
  - Next phase: `2.48N — implement first controlled audio-connect execution path, default disabled, no physical connect`.
  - Next-phase guardrails:
    ```text
    controlled_connect_enablement_enabled=false
    controlled_connect_enablement_operator_approved=false
    controlled_connect_enablement_future_phase_permitted=false
    controlled_connect_enablement_execution_allowed=false
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, future physical-connect permission enablement, production-enabled connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48L-Retry2 physically closed the post-session-repair proof with no media connect:
  - `2.48L-Retry2 = physical proof succeeded`.
  - Proof path: `/tmp/salemx-voip-push-receipt-proof-2.48l-retry2-polled.txt`.
  - Proof generation: `generation_14`.
  - Receiver app session validation held.
  - Exactly one sandbox APNs was sent and returned `background_apns_push_result=sandbox_success`; no repeat APNs was sent.
  - PushKit and CallKit Answer succeeded:
    ```text
    physical_voip_push_received=true
    pushkit_callback_invoked=true
    pushkit_payload_kind=real_invite_controlled
    callkit_first_action_kind=answer
    callkit_answer_action_delivered=true
    callkit_answer_action_received=true
    callkit_answer_action_fulfilled=true
    ```
  - Pending metadata fetch succeeded after receiver app session validation:
    ```text
    pending_metadata_fetch_result=success_redacted
    pending_metadata_fetch_http_status_bucket=2xx
    pending_metadata_fetch_errcode=none
    pending_metadata_fetch_failure_reason=none
    foreground_pending_call_metadata_handoff_observed=true
    ```
  - Credentials were requested and received:
    ```text
    media_credentials_request_metadata_available=true
    media_credentials_boundary_reached=true
    media_credentials_requested=true
    media_credentials_request_authorized=true
    media_credentials_result=success_redacted
    media_credentials_token_received=true
    media_credentials_url_received=true
    media_credentials_expires_at_present=true
    media_credentials_payload_redacted=true
    ```
  - 2.48K enablement wiring was present on-device and default-off:
    ```text
    controlled_connect_enablement_wiring_present=true
    controlled_connect_enablement_debug_only=true
    controlled_connect_enablement_default_off=true
    controlled_connect_enablement_operator_approval_required=true
    controlled_connect_enablement_one_shot=true
    controlled_connect_enablement_fresh_credentials_required=true
    controlled_connect_enablement_audio_only=true
    controlled_connect_enablement_video_allowed=false
    controlled_connect_enablement_matrix_events_allowed=false
    controlled_connect_enablement_raw_credentials_logged=false
    controlled_connect_enablement_rollback_available=true
    controlled_connect_enablement_enabled=false
    controlled_connect_enablement_operator_approved=false
    controlled_connect_enablement_future_phase_permitted=false
    controlled_connect_enablement_execution_allowed=false
    controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
    ```
  - Media-connect preflight reached the guard and blocked before connect:
    ```text
    media_connect_preflight_requested=true
    media_connect_preflight_metadata_available=true
    media_connect_preflight_credentials_available=true
    media_connect_preflight_token_present=true
    media_connect_preflight_url_present=true
    media_connect_preflight_expires_at_present=true
    media_connect_execution_allowed=false
    media_connect_preflight_result=blocked_before_connect_redacted
    media_connect_blocked_reason=disabled_switch_no_connect
    media_connect_engine_invoked=false
    livekit_connect_audio_invoked=false
    ```
  - Safety boundary remained intact:
    ```text
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    blocked_reason=none
    ```
  - Close-out summary:
    ```text
    pending metadata fetch succeeded
    credentials requested and received
    enablement wiring present on-device
    enablement default off
    execution allowed=false
    blocked reason=enablement_disabled_no_connect
    no media connect
    no LiveKit join
    no mic/camera permission
    no Matrix events
    no full call flow
    ```
  - Next phase: `2.48M — controlled-connect first-run readiness gate, no physical connect`.
  - No repeated APNs, production APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, future physical-connect permission enablement, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48L-Retry2Plan prepared the one-shot retry plan after receiver app session validation:
  - `2.48L-Retry2Plan = ready for one explicit retry only after receiver app session validation`.
  - `receiver app Matrix session validated=true`.
  - `APNs not sent`.
  - `default remains no-connect`.
  - Retry2 requirements:
    ```text
    retry2_requires_receiver_app_session_validated=true
    retry2_requires_fresh_debug_app_running=true
    retry2_requires_terminal_tokens_valid=true
    retry2_requires_room_validation_pass=true
    retry2_requires_single_sandbox_apns=true
    retry2_requires_operator_green_answer_ready=true
    retry2_requires_post_answer_polling=true
    retry2_rejects_stale_proof=true
    retry2_forbids_media_connect=true
    retry2_forbids_livekit_join=true
    retry2_forbids_permissions=true
    retry2_forbids_matrix_events=true
    retry2_forbids_full_flow=true
    ```
  - Required success fields for the future retry:
    ```text
    pending_metadata_fetch_result=success_redacted
    foreground_pending_call_metadata_handoff_observed=true
    media_credentials_result=success_redacted
    controlled_connect_enablement_wiring_present=true
    controlled_connect_enablement_enabled=false
    controlled_connect_enablement_execution_allowed=false
    controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
    media_connect_preflight_requested=true
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    blocked_reason=none
    ```
  - Stop conditions:
    ```text
    if APNs sent once, do not repeat automatically
    if pending_metadata_fetch_result=blocked_redacted, stop and classify
    if media_credentials_result=not_requested after Answer, stop and classify
    if enablement fields missing, verify installed commit before any retry
    if media_connect_requested=true, stop as safety regression
    if livekit_join_requested=true, stop as safety regression
    ```
  - Next phase: `2.48L-Retry2 — one-shot physical proof retry after app session validation, no LiveKit join`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, future physical-connect permission enablement, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48L-SessionRepair validated the iPhone app Matrix session without sending APNs:
  - `2.48L-SessionRepair = complete`.
  - Installed and launched the freshly built Debug app on iPhone PRO, then triggered only the local DEBUG session-whoami URL after app session restore completed.
  - First immediate local trigger proved the timing boundary and stopped before `/whoami` with `blocked_reason=missing_active_session`; no APNs or retry path was used.
  - Delayed local trigger copied `/tmp/salemx-matrix-session-whoami-proof-2.48l-sessionrepair-retry.txt` and proved:
    ```text
    iphone_app_matrix_session_present=true
    iphone_app_matrix_session_whoami_result=success_redacted
    iphone_app_matrix_session_user_hash=497015f5745c933a
    iphone_app_matrix_session_user_hash_matches_expected=true
    iphone_app_matrix_session_device_present=true
    iphone_app_pending_metadata_auth_ready=true
    blocked_reason=none
    ```
  - The proof remained local/redacted and preserved the safety boundary:
    ```text
    APNs_sent=false
    dev_invite_used=false
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - Session-repair conclusion:
    ```text
    receiver_app_session_validated=true
    receiver_app_session_matches_expected_hash=true
    pending_metadata_retry_precondition_app_session_valid=true
    retry_not_performed=true
    ```
  - Terminal invite tokens remain insufficient proof for app pending metadata auth; the iPhone app session itself is now validated.
  - Next phase: `2.48L-Retry2Plan — one-shot retry after receiver app session validation, no immediate APNs`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, future physical-connect permission enablement, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48L-Metadata401 classified the pending metadata auth failure without retrying APNs:
  - `2.48L physical attempt = incomplete`.
  - The one-shot real non-dev invite/APNs had already succeeded once with `invite_http_code=200`, `background_apns_push_result=sandbox_success`, and `APNs_sent=true`; no repeat APNs was performed during classification.
  - The copied proof `/tmp/salemx-voip-push-receipt-proof-2.48l-polled.txt` recorded `proof_generation=generation_7`.
  - PushKit and CallKit reached the expected controlled path: `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=real_invite_controlled`, `callkit_first_action_kind=answer`, `callkit_answer_action_received=true`, and `callkit_answer_action_fulfilled=true`.
  - 2.48K enablement fields were present on-device and default-off, including `controlled_connect_enablement_wiring_present=true`, `controlled_connect_enablement_default_off=true`, `controlled_connect_enablement_execution_allowed=false`, and `controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect`.
  - Failure point:
    ```text
    pending_metadata_fetch_result=blocked_redacted
    pending_metadata_fetch_http_status_bucket=401
    pending_metadata_fetch_errcode=M_UNKNOWN_TOKEN
    pending_metadata_fetch_failure_reason=auth_rejected
    blocked_reason=pending_metadata_fetch_http_failure_redacted
    ```
  - Because pending metadata fetch failed, `foreground_pending_call_metadata_handoff_observed=false`, `media_credentials_requested=false`, and `media_connect_preflight_requested=false`; 2.48L is not closed.
  - Investigation conclusion:
    ```text
    likely_iPhone_app_matrix_session_invalid_or_stale=true
    terminal_invite_tokens_are_not_sufficient_for_iPhone_pending_metadata_fetch=true
    receiver_app_session_must_be_valid_before_retry=true
    ```
  - The distinction is important: terminal Token A/B were valid enough to send the invite, but pending metadata fetch is performed by the iPhone app using its own stored/authenticated Matrix session. A successful pending metadata fetch is the code path that records foreground handoff and then requests controlled media credentials; the `401 M_UNKNOWN_TOKEN` prevented that handoff.
  - Safety boundary remained intact: `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `microphone_permission_requested=false`, `camera_permission_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - Next phase: `2.48L-SessionRepair — refresh/validate iPhone app Matrix session before any APNs retry, no APNs`.
  - No repeated APNs, production APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, future physical-connect permission enablement, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this classification checkpoint.
- 2.48K explicit one-shot controlled-connect enablement is implemented:
  - `2.48K = explicit one-shot controlled-connect enablement, default off`.
  - Added a DEBUG-only enablement configuration/proof layer beside the existing controlled-connect switch and activation proof surface in `NativeIncomingSyntheticCallKitUIProofAdapter.swift`.
  - The enablement gate is deliberately conservative: `debugOnly && oneShotEnablementEnabled && operatorApproved && freshCredentialsPresent && audioOnlyScope && futureConnectPhasePermitted`. For 2.48K, default enablement and operator approval are false, and future physical-connect permission is false.
  - Default proof fields:
    ```text
    controlled_connect_enablement_wiring_present=true
    controlled_connect_enablement_debug_only=true
    controlled_connect_enablement_default_off=true
    controlled_connect_enablement_operator_approval_required=true
    controlled_connect_enablement_one_shot=true
    controlled_connect_enablement_fresh_credentials_required=true
    controlled_connect_enablement_audio_only=true
    controlled_connect_enablement_video_allowed=false
    controlled_connect_enablement_matrix_events_allowed=false
    controlled_connect_enablement_raw_credentials_logged=false
    controlled_connect_enablement_rollback_available=true
    controlled_connect_enablement_enabled=false
    controlled_connect_enablement_operator_approved=false
    controlled_connect_enablement_future_phase_permitted=false
    controlled_connect_enablement_execution_allowed=false
    controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
    ```
  - Media preflight now combines the existing switch execution gate with the new enablement execution gate, so default execution remains false before engine invocation. The existing disabled-switch blocked reason remains the first preflight blocker while the new enablement-specific blocked reason is recorded separately.
  - Rollback proof now restores both the activation configuration and the enablement configuration to the disabled no-connect state.
  - Targeted source-guard tests were extended to prove DEBUG-only enablement wiring, default-off enablement, operator approval false by default, future phase permission false by default, all-gates-required execution, audio-only scope, video disabled, Matrix events disabled, raw credential logging disabled, rollback restoration, media engine false, LiveKit `connectAudio` false, microphone/camera permission paths absent, Matrix event emission absent, and full-flow false.
  - Existing hard safety fields remain false:
    ```text
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - Next phase: `2.48L — physical proof of enablement default-off, no LiveKit join`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, default controlled-connect enablement, default operator approval enablement, production connect behavior, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48J controlled-connect enablement implementation plan is documented:
  - `2.48J = controlled-connect enablement implementation plan`.
  - `physical connect not performed`.
  - `controlled connect not yet enabled`.
  - `default remains no-connect`.
  - Investigation conclusion: keep `DirectCallEngine.requestMediaCredentials` as the credentials-only boundary; keep `DirectCallEngine.connectMediaIfReady` as the private media boundary that must stay unreached in 2.48K; treat `LiveKitDirectCallMediaEngine.connectAudio` as the first real media-connect boundary and keep it uninvoked until a later physical-connect phase explicitly permits it.
  - Narrow 2.48K implementation path: add explicit DEBUG-only one-shot enablement configuration/proof mechanics around the existing `SalemXControlledMediaConnectSwitch` and `SalemXControlledMediaConnectActivationConfiguration` proof surface, default the enablement off, keep operator approval false by default, require fresh credentials and audio-only scope before execution can ever be considered, and preserve video/Matrix/raw-credential hard stops.
  - 2.48K required enablement defaults:
    ```text
    enablement_debug_only=true
    enablement_default_enabled=false
    enablement_operator_approval_default=false
    enablement_requires_fresh_credentials=true
    enablement_requires_audio_only_scope=true
    enablement_video_disabled=true
    enablement_matrix_events_disabled=true
    enablement_raw_credentials_logged=false
    enablement_rollback_available=true
    enablement_tests_required_before_physical=true
    ```
  - Future 2.48K proof fields:
    ```text
    controlled_connect_enablement_wiring_present=true
    controlled_connect_enablement_debug_only=true
    controlled_connect_enablement_default_off=true
    controlled_connect_enablement_operator_approval_required=true
    controlled_connect_enablement_audio_only=true
    controlled_connect_enablement_video_allowed=false
    controlled_connect_enablement_matrix_events_allowed=false
    controlled_connect_enablement_raw_credentials_logged=false
    controlled_connect_enablement_rollback_available=true
    controlled_connect_enablement_execution_allowed=false
    ```
  - 2.48K stop/safety fields must remain false:
    ```text
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - Rollback expectations:
    ```text
    rollback_disables_enablement=true
    rollback_clears_operator_approval=true
    rollback_restores_execution_allowed_false=true
    rollback_preserves_no_connect=true
    ```
  - 2.48K tests must be completed before any future physical proof: source guards for DEBUG-only placement, default-off enablement, operator-approval default false, fresh-credentials requirement, audio-only scope, video/Matrix/raw-credential disabled behavior, rollback proof fields, false stop/safety fields, and absence of `connectMediaIfReady`, `.connectAudio`, microphone/camera permission, and Matrix event-emission paths from the enablement proof surface.
  - Next phase: `2.48K — implement explicit one-shot controlled-connect enablement, default off, no physical connect`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this planning checkpoint.
- 2.48I-Retry physical disabled-activation proof succeeded:
  - `2.48I-Retry = physical proof succeeded`.
  - The phase-specific proof file `/tmp/salemx-voip-push-receipt-proof-2.48i-retry-polled.txt` recorded `proof_generation=generation_8`; stale `/tmp/salemx-voip-push-receipt-proof-current.txt` was not used for classification.
  - The one-shot real non-dev invite/APNs retry had already sent exactly once and returned `background_apns_push_result=sandbox_success` with `blocked_reason=none`. No repeat APNs was sent during close-out.
  - Activation wiring was present on-device: DEBUG-only, default disabled, requires operator approval, rollback available, `planned_audio_only_redacted` scope, video disabled, Matrix events disabled, and raw credentials logging disabled.
  - Answer pipeline reached successfully: `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=real_invite_controlled`, `pending_metadata_fetch_result=success_redacted`, `pending_metadata_fetch_http_status_bucket=2xx`, `pending_metadata_fetch_errcode=none`, `pending_metadata_fetch_failure_reason=none`, `callkit_first_action_kind=answer`, `callkit_answer_action_delivered=true`, `callkit_answer_action_received=true`, and `callkit_answer_action_fulfilled=true`.
  - Foreground handoff succeeded with `foreground_call_state=real_invite_pending_media`, authenticated pending metadata source, call/room/peer bindings present, `foreground_pending_call_metadata_direction=incoming`, and `foreground_pending_call_metadata_intent=audio`.
  - Credentials were requested and received: `media_credentials_request_metadata_available=true`, `media_credentials_boundary_reached=true`, `media_credentials_requested=true`, `media_credentials_request_authorized=true`, `media_credentials_result=success_redacted`, token/URL receipt booleans true, expiry present, and payload redacted. Cleanup/expiry stayed safe with cleanup cleared, post-cleanup token/URL/expiry/payload booleans false, reuse disallowed, and `media_credentials_expiry_check_result=expired_or_not_reusable_redacted`.
  - Media-connect preflight reached the disabled guard and stopped before connect: `controlled_connect_switch_enabled=false`, `controlled_connect_operator_approved=false`, `controlled_connect_execution_allowed=false`, `controlled_connect_blocked_reason=disabled_switch_no_connect`, `media_connect_preflight_requested=true`, `media_connect_execution_allowed=false`, `media_connect_preflight_result=blocked_before_connect_redacted`, `media_connect_blocked_reason=disabled_switch_no_connect`, `media_connect_engine_invoked=false`, and `livekit_connect_audio_invoked=false`.
  - Safety boundary stayed intact: `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `microphone_permission_requested=false`, `camera_permission_requested=false`, `matrix_event_emit_requested=false`, `real_call_flow_started=false`, and `blocked_reason=none`.
  - `pushkit_completion_answerable_window_result=timeout_elapsed`, `operator_ready_to_answer=false`, and `voip_operator_marker_set_before_report=false` were not blockers because the actual CallKit Answer path completed.
  - Close-out record: activation wiring present on-device, Answer pipeline reached, credentials requested and received, media-connect preflight reached guard, `execution_allowed=false`, blocked reason `disabled_switch_no_connect`, no media connect, no LiveKit join, no mic/camera permission, no Matrix events, and no full call flow.
  - Next phase: `2.48J — controlled-connect enablement implementation plan, no physical connect`.
  - No repeated APNs, production APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this close-out.
- 2.48I-RetryPlan prepared the next one-shot Answer-path retry without sending APNs:
  - `2.48I-RetryPlan = ready for one explicit operator-approved retry only`.
  - The retry plan reduces the previous avoidable failure causes by requiring a fresh Debug install from current HEAD, an explicit app foreground/background state check before any future send, an operator-ready confirmation for the green Answer tap, post-Answer polling before copying proof, phase-specific proof copying, generation verification, and one future sandbox APNs maximum.
  - Retry checklist:
    ```text
    retry_requires_fresh_debug_install=true
    retry_requires_current_head_confirmed=true
    retry_requires_single_sandbox_apns=true
    retry_requires_operator_answer_ready=true
    retry_requires_green_answer_tap=true
    retry_requires_post_answer_polling=true
    retry_rejects_stale_generation=true
    retry_requires_activation_fields=true
    retry_requires_answer_pipeline_fields=true
    retry_requires_credentials_fields=true
    retry_requires_preflight_block_fields=true
    retry_forbids_connect=true
    retry_forbids_livekit_join=true
    retry_forbids_permissions=true
    retry_forbids_matrix_events=true
    retry_forbids_full_flow=true
    ```
  - Required success fields for the retry:
    ```text
    callkit_first_action_kind=answer
    callkit_answer_action_delivered=true
    callkit_answer_action_received=true
    callkit_answer_action_fulfilled=true
    media_credentials_result=success_redacted
    media_connect_preflight_requested=true
    controlled_connect_activation_wiring_present=true
    controlled_connect_execution_allowed=false
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    blocked_reason=none
    ```
  - Retry stop conditions:
    ```text
    if APNs sent once, do not repeat automatically
    if callkit_first_action_kind=none, stop and classify
    if activation fields missing, verify installed commit before any retry
    if credentials not requested after Answer, stop and classify
    if media_connect_requested=true, stop as safety regression
    if livekit_join_requested=true, stop as safety regression
    ```
  - The next phase is `2.48I-Retry — one-shot physical proof retry, no LiveKit join`, not an actual connect phase.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, controlled-connect switch enablement, controlled-connect operator approval enablement, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this planning checkpoint.
- 2.48I-Triage classified the physical disabled-activation proof attempt as incomplete:
  - The one-shot real non-dev invite/APNs attempt passed preflight once with receiver hash `497015f5745c933a`, sender hash `7d434d7f252427fb`, `sender_equals_receiver=false`, `room_validation_preflight=pass`, `local_schema_valid=true`, `invite_http_code=200`, `real_non_dev_invite_used=true`, `dev_invite_used=false`, `background_apns_push_requested=true`, `background_apns_push_result=sandbox_success`, and `blocked_reason=none`.
  - Actual 2.48I proof generation `generation_1` recorded `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=real_invite_controlled`, and the 2.48H activation fields on-device: wiring present, DEBUG-only, default disabled, operator approval required, rollback available, and `planned_audio_only_redacted` scope.
  - The attempt did not close because it stopped before the Answer pipeline: `callkit_report_requested=true`, `callkit_report_result=pending`, `callkit_report_completion_observed=false`, `pushkit_completion_called=false`, `callkit_first_action_kind=none`, `callkit_answer_action_delivered=false`, `callkit_answer_action_received=false`, and `callkit_answer_action_fulfilled=false`.
  - As a result, `media_credentials_result=not_requested` and `media_connect_preflight_result=not_requested`; 2.48I is not closed.
  - Safety boundary remained intact: `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `microphone_permission_requested=false`, `camera_permission_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - Local artifact note: `/tmp/salemx-voip-push-receipt-proof-current.txt` was stale `generation_8` from an earlier successful run; the 2.48I classification uses `/tmp/salemx-voip-push-receipt-proof-2.48i-polled.txt`.
  - Most likely classification: CallKit UI did not surface or the operator could not tap Answer because the CallKit report completion never arrived. There is no evidence that 2.48H activation wiring caused a media/connect regression; the activation fields were present and all connect/LiveKit/permission/Matrix/full-flow fields remained false.
  - Next phase: `2.48I-RetryPlan — one-shot Answer-path retry plan with explicit operator approval, no immediate APNs`.
  - No repeated APNs, production APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this triage.
- 2.48H-QA broader DirectCall source-guard triage is complete:
  - `2.48H-QA result = broader DirectCall checks passed after narrow source-guard fix`.
  - The broader selected DirectCall run reproduced only source-guard drift in three contract tests:
    - `backgroundRealCallKitAdapterKeepsDiagnosticsRedactedAndUnwiredFromPushCallbacks`
    - `debugElementCallPushKitRegistryForwardsRedactedSalemXPayload`
    - `debugLocalCallKitOnlyProofIsSeparatedFromVoIPReceiptProof`
  - The drift was limited to stale expected source text and range selection: the CallKit report field is now rendered dynamically, the Element Call PushKit interception order assertion needed to be scoped to the incoming-push callback body, and the local CallKit-only proof slices needed to stop before the later VoIP operator helper.
  - No Swift runtime code changed. The 2.48H activation wiring tests passed, and the broader selected command passed after the narrow test guard fixes with 131 tests across `DirectCallEngineTests` and `NativeIncomingCallLifecycleContractTests`.
  - Next phase remains: `2.48I — physical proof of activation wiring disabled, no LiveKit join`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48H controlled-connect activation switch wiring is implemented with default disabled:
  - Added a DEBUG-only activation configuration wrapper around the existing controlled-connect switch proof gate. The default configuration uses the disabled switch, `operatorApproved=false`, `planned_audio_only_redacted` scope, video disabled, Matrix events disabled, raw credentials logging disabled, and rollback available.
  - The future activation gate still requires both switch enabled and explicit operator approval before execution can be allowed. Default execution remains blocked before media engine invocation, LiveKit join, permissions, Matrix events, and full flow.
  - New default proof fields:
    ```text
    controlled_connect_activation_wiring_present=true
    controlled_connect_activation_debug_only=true
    controlled_connect_activation_default_disabled=true
    controlled_connect_activation_requires_operator_approval=true
    controlled_connect_activation_rollback_available=true
    controlled_connect_activation_scope=planned_audio_only_redacted
    controlled_connect_video_allowed=false
    controlled_connect_matrix_events_allowed=false
    controlled_connect_raw_credentials_logged=false
    controlled_connect_switch_enabled=false
    controlled_connect_operator_approved=false
    controlled_connect_execution_allowed=false
    controlled_connect_blocked_reason=disabled_switch_no_connect
    media_connect_engine_invoked=false
    livekit_connect_audio_invoked=false
    media_connect_requested=false
    media_connect_attempted=false
    livekit_join_requested=false
    microphone_permission_requested=false
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - Rollback proof support restores the disabled activation configuration and keeps media execution, media-engine invocation, and LiveKit connect invocation false.
  - Source-guard tests now cover activation wiring presence, DEBUG/test-only placement, disabled default, operator approval false default, both-gates-required execution, rollback/no-connect proof, video disabled, Matrix events disabled, raw credential logging disabled, media-engine/LiveKit invocation false, permission paths false, and full flow false.
  - Next phase: `2.48I — physical proof of activation wiring disabled, no LiveKit join`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48G controlled-connect activation plan and rollback design is documented without physical connect:
  - This phase reviewed the current activation boundary and made no Swift or server code changes. The credentials-only boundary remains `DirectCallEngine.requestMediaCredentials`; the future media boundary remains `DirectCallEngine.connectMediaIfReady` followed by `LiveKitDirectCallMediaEngine.connectAudio` only after an explicitly approved connecting-session path.
  - Controlled connect is still not approved; physical connect is still not performed; the default remains no-connect.
  - Activation checklist:
    ```text
    activation_requires_debug_only_switch=true
    activation_requires_operator_approval=true
    activation_requires_one_shot_physical_run=true
    activation_audio_only=true
    activation_video_disabled=true
    activation_matrix_events_disabled=true
    activation_requires_fresh_credentials=true
    activation_requires_expiry_check=true
    activation_requires_rollback_plan=true
    activation_requires_redacted_proof=true
    activation_requires_no_raw_token_logging=true
    activation_requires_tests_before_physical=true
    ```
  - Rollback plan:
    ```text
    rollback_disable_switch=true
    rollback_operator_approval_false=true
    rollback_restore_execution_allowed_false=true
    rollback_keep_media_engine_invoked_false=true
    rollback_keep_livekit_join_requested_false=true
    rollback_keep_permissions_unrequested=true
    rollback_keep_matrix_events_false=true
    ```
  - Planned future first controlled-connect proof fields:
    ```text
    controlled_connect_switch_enabled=true
    controlled_connect_operator_approved=true
    controlled_connect_execution_allowed=true
    controlled_connect_activation_scope=audio_only_redacted
    controlled_connect_video_allowed=false
    controlled_connect_matrix_events_allowed=false
    controlled_connect_raw_credentials_logged=false
    controlled_connect_rollback_available=true
    ```
  - Hard stop fields remain false unless a future phase explicitly allows them:
    ```text
    camera_permission_requested=false
    matrix_event_emit_requested=false
    real_call_flow_started=false
    ```
  - Required before any physical activation: changed-file/targeted DirectCall tests, proof/source guard tests for the disabled default and operator gate, server token/allocation/pre-create expiry tests, route safety checks, fresh bounded credentials, expiry validation, redacted proof, privacy scan, and immediate rollback availability.
  - Next phase: `2.48H — implement controlled-connect activation switch wiring, default disabled, no physical connect`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48F physical disabled controlled-connect switch proof succeeded:
  - Proof generation `generation_8` reached the one-shot real non-dev invite/APNs/PushKit/CallKit Answer path with receiver hash `497015f5745c933a`, sender hash `7d434d7f252427fb`, `sender_equals_receiver=false`, `room_validation_preflight=pass`, `local_schema_valid=true`, `invite_http_code=200`, `real_non_dev_invite_used=true`, `dev_invite_used=false`, `background_apns_push_requested=true`, `background_apns_push_result=sandbox_success`, and `blocked_reason=none`.
  - The controlled push/CallKit/credentials path remained successful: `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=real_invite_controlled`, pending metadata fetch `success_redacted` with `2xx`, CallKit first action `answer`, foreground pending metadata handoff observed, and controlled credentials `success_redacted` with token/URL/expiry presence booleans true and payload redacted.
  - The disabled controlled-connect switch was present on-device and blocked execution: `controlled_connect_switch_present=true`, `controlled_connect_switch_debug_only=true`, `controlled_connect_switch_enabled=false`, `controlled_connect_operator_approved=false`, `controlled_connect_execution_allowed=false`, `controlled_connect_blocked_reason=disabled_switch_no_connect`, and blocked-before-engine/LiveKit-join/permissions/Matrix-events booleans true.
  - The media-connect preflight still reached the guard and blocked before connect with metadata/credentials/token/URL/expiry present, `media_connect_execution_allowed=false`, `media_connect_preflight_result=blocked_before_connect_redacted`, `media_connect_blocked_reason=disabled_switch_no_connect`, `media_connect_engine_invoked=false`, and `livekit_connect_audio_invoked=false`.
  - Safety proof remained false for `media_connect_requested`, `media_connect_attempted`, `livekit_join_requested`, `microphone_permission_requested`, `camera_permission_requested`, `matrix_event_emit_requested`, and `real_call_flow_started`.
  - No repeated APNs, production APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID exposure, forbidden project/signing file change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this close-out.
- 2.48E disabled controlled-connect switch/proof gates are implemented:
  - The DEBUG-only proof surface records `controlled_connect_switch_present=true`, `controlled_connect_switch_debug_only=true`, `controlled_connect_switch_enabled=false`, `controlled_connect_operator_approved=false`, `controlled_connect_execution_allowed=false`, and `controlled_connect_blocked_reason=disabled_switch_no_connect`.
  - The guard records `controlled_connect_blocked_before_engine=true`, `controlled_connect_blocked_before_livekit_join=true`, `controlled_connect_blocked_before_permissions=true`, and `controlled_connect_blocked_before_matrix_events=true`.
  - The media preflight remains blocked with `media_connect_execution_allowed=false`, `media_connect_blocked_reason=disabled_switch_no_connect`, `media_connect_engine_invoked=false`, and `livekit_connect_audio_invoked=false`.
  - Safety fields remain false for `media_connect_requested`, `media_connect_attempted`, `livekit_join_requested`, `microphone_permission_requested`, `camera_permission_requested`, `matrix_event_emit_requested`, and `real_call_flow_started`.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48C physical controlled media-connect preflight proof succeeded:
  - Proof generation `generation_8` reached the real invite/APNs/PushKit/CallKit Answer path and kept `dev_invite_used=false`, `background_apns_push_result=sandbox_success`, and `blocked_reason=none`.
  - Authenticated pending metadata fetch succeeded with `pending_metadata_fetch_result=success_redacted`, `pending_metadata_fetch_http_status_bucket=2xx`, `pending_metadata_fetch_errcode=none`, and `pending_metadata_fetch_failure_reason=none`.
  - Controlled credentials succeeded with `media_credentials_result=success_redacted`, `media_credentials_token_received=true`, `media_credentials_url_received=true`, `media_credentials_expires_at_present=true`, and `media_credentials_payload_redacted=true`.
  - Cleanup/expiry proof remained present: `media_credentials_cleanup_result=cleared`, post-cleanup token/URL/expiry/payload booleans false, reuse disallowed, and `media_credentials_expiry_check_result=expired_or_not_reusable_redacted`.
  - The 2.48C guard recorded credentials present at preflight, `media_connect_guard_enabled=true`, `media_connect_execution_allowed=false`, `media_connect_preflight_result=blocked_before_connect_redacted`, and `media_connect_blocked_reason=controlled_preflight_no_connect`.
  - The media engine was not invoked and LiveKit `connectAudio` was not invoked: `media_connect_engine_invoked=false` and `livekit_connect_audio_invoked=false`.
  - Safety proof remained false for `media_connect_requested`, `media_connect_attempted`, `livekit_join_requested`, `microphone_permission_requested`, `camera_permission_requested`, `matrix_event_emit_requested`, and `real_call_flow_started`.
  - No repeated APNs, production APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this close-out.
- 2.48D server/client readiness review before controlled connect is complete:
  - `DirectCallEngine.requestMediaCredentials` is a credentials-only boundary; `DirectCallEngine.connectMediaIfReady` is the separate media-connect gate that calls `mediaEngine.connectAudio` only after a connecting session, ready encryption, valid key handle, and audio intent.
  - `LiveKitDirectCallMediaEngine.connectAudio` is the first path that configures the audio route, obtains credentials again, builds E2EE context, and calls the LiveKit client connect boundary. It initializes microphone state disabled and does not create a camera path.
  - The 2.48B/2.48C proof adapter already records the no-connect guard fields, including `media_connect_execution_allowed=false`, `media_connect_engine_invoked=false`, and `livekit_connect_audio_invoked=false`.
  - Server route/tests cover token issuance through the foreground-signaling token alias, room pre-create before token issue, bounded participant-token expiry, bounded allocation TTL, repeated-request allocation reuse with fresh bounded credentials, and rate-limit rejection before allocation/room pre-create.
  - Readiness checklist: `client_preflight_guard_present=true`, `client_default_connect_allowed=false`, `client_media_engine_invocation_proven_false=true`, `client_livekit_connect_audio_invocation_proven_false=true`, `client_mic_permission_boundary_identified=true`, `client_camera_permission_boundary_identified=true`, `client_matrix_event_emit_boundary_identified=true`, `server_token_expiry_verified=true`, `server_allocation_ttl_verified=true`, `server_rate_limit_no_allocation_verified=true`, `credentials_redaction_verified=true`, `cleanup_non_persistence_verified=true`, `rollback_kill_switch_required=true`, and `controlled_connect_not_yet_approved=true`.
  - Gates before any future controlled connect: require an explicit DEBUG-only connect switch, one-shot operator approval, video disabled, Matrix event emission disabled, audio permission only in the future connect phase, a stop before LiveKit join unless explicitly permitted, redacted proof only, and immediate rollback to no-connect.
  - No APNs, production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` change, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this review.
- 2.48B controlled media-connect preflight guard is implemented as a DEBUG-only proof step:
  - After controlled media credentials succeed, the proof records preflight metadata/credential availability, token/URL/expiry presence booleans, `media_connect_guard_enabled=true`, and `media_connect_execution_allowed=false`.
  - The preflight result is `blocked_before_connect_redacted` with `media_connect_blocked_reason=controlled_preflight_no_connect`; it does not invoke the media engine or LiveKit connect path.
  - Safety fields remain false: `media_connect_requested`, `media_connect_attempted`, `media_connect_engine_invoked`, `livekit_connect_audio_invoked`, `livekit_join_requested`, `microphone_permission_requested`, `camera_permission_requested`, `matrix_event_emit_requested`, and `real_call_flow_started`.
  - No APNs, production APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.48A controlled media connect planning is documented with no runtime behavior change:
  - Issued media credentials would be consumed through the existing `DirectCallMediaConnectionInfo` path, then ultimately by `DirectCallEngine.connectMediaIfReady` and `LiveKitDirectCallMediaEngine.connectAudio`.
  - The existing credentials-only boundary is `DirectCallEngine.requestMediaCredentials`, which calls `DirectCallMediaCredentialsBoundaryRequesting.requestMediaCredentials` and deliberately does not call `connectAudio`.
  - The existing LiveKit/media seams are `DirectCallMediaEngineProtocol`, `DirectCallLiveKitMediaEngineFactory`, `LiveKitDirectCallMediaEngine`, `DirectCallLiveKitClientProtocol`, `DirectCallMediaE2EEContextProviderProtocol`, `DirectCallAudioRouteControllerProtocol`, and `DirectCallLiveKitTokenProvider`.
  - The proposed 2.48B boundary must be explicit DEBUG-only and stop before `liveKitClient.connect`, microphone/camera permission, or media publication.
  - Required proof fields and tests are listed in `NEXT_CODEX_PROMPT.md`; all connect/join/mic/camera/Matrix/full-flow fields remain false until a separately approved controlled connect phase.
- 2.47E server-side media credentials allocation/token expiry is verified without LiveKit join:
  - Participant token expiry remains bounded by the token issuer TTL.
  - Allocation expiry remains bounded by the allocation store TTL and is intentionally longer than token expiry.
  - Repeated credentials requests reuse the active allocation while issuing fresh bounded participant tokens.
  - Expired allocation state is not returned/reused by the in-memory store; Redis-backed allocation tests already cover expired-key replacement and redacted storage.
  - The token path performs room pre-create before token issue only; no server test or verification path joins LiveKit.
  - Successful token issuance logs now use redacted allocation/call hashes, not raw allocation IDs or call IDs.
  - Safety remains unchanged: no APNs, no media connect, no LiveKit join, no microphone/camera permission request, no Matrix event emit, and no full direct-call flow in this phase.
- 2.47C controlled real media credentials request, no-connect is implemented as a DEBUG-only code checkpoint:
  - After authenticated pending metadata fetch succeeds, the controlled proof path requests credentials through the existing `DirectCallLiveKitTokenProvider` and active app auth boundary.
  - The proof records `media_credentials_requested=true`, `media_credentials_request_authorized=true/false`, `media_credentials_result=success_redacted` or `blocked_redacted`, token/URL receipt booleans, token/URL redaction booleans, expiry presence, payload redaction, no local persistence, and cleanup status.
  - The path deliberately keeps `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `microphone_permission_requested=false`, `camera_permission_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - Changed-file SwiftFormat passed, changed-file SwiftLint passed with only the existing file-length warning, and targeted DirectCall tests passed (`38 tests`).
  - No APNs was sent for this code checkpoint. No production APNs, repeated APNs, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47C physical proof reached the no-connect credentials request boundary but is blocked:
  - Real invite/APNs/PushKit/CallKit Answer, authenticated pending metadata fetch, and `media_credentials_request_metadata_available=true` succeeded.
  - Credentials request proof recorded `media_credentials_requested=true`, `media_credentials_request_authorized=true`, `media_credentials_result=blocked_redacted`, `media_credentials_token_received=false`, `media_credentials_url_received=false`, `media_credentials_expires_at_present=false`, and `blocked_reason=media_credentials_request_failed_redacted`.
  - The proof now records redacted token diagnostics: request seen, HTTP status bucket, token reason, eligibility, rate limit, allocation attempted, LiveKit room precreate attempted, and token issued booleans.
  - No APNs was sent for this diagnostic patch. No production APNs, repeated APNs, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47C2 targets the token 404 only:
  - Root cause: physical proof returned `media_credentials_token_request_seen=true`, `media_credentials_token_http_status_bucket=404`, and `media_credentials_token_reason=unknown`, while unauthenticated route probes showed the public canonical token route returned `404 M_UNRECOGNIZED` and existing call-service routes returned `401`.
  - The server keeps the canonical token route and adds an authenticated alias at `/foreground-signaling/livekit/token`, reusing the same token handler.
  - The DEBUG controlled PushKit proof path now requests credentials through that alias so it can use the already exposed foreground-signaling route family.
  - Targeted server route tests, server compileall, changed-file SwiftFormat/SwiftLint, and targeted DirectCall tests passed.
  - No APNs was sent for this fix. No production APNs, repeated APNs, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47C5 targets the pending metadata fetch blocker only:
  - The latest physical proof reached real invite/APNs/PushKit/CallKit Answer with `pending_metadata_reference_present=true`, but pending metadata fetch returned `blocked_redacted` before metadata handoff.
  - Public unauthenticated route probes show `/foreground-signaling/pending-metadata/{reference}` is covered and returns auth-gated `401`, not `404`; the existing server test proves valid receiver auth can fetch the stored metadata in-process.
  - The iOS proof now records redacted `pending_metadata_fetch_http_status_bucket`, `pending_metadata_fetch_errcode`, and `pending_metadata_fetch_failure_reason` fields so the next physical run can distinguish `auth_rejected`, `forbidden`, `not_found`, `server_error`, `network_failure`, or payload/schema failure without logging raw metadata.
  - No APNs was sent for this diagnostic fix. No production APNs, repeated APNs, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47C6 fixes the pending metadata fetch `403 M_FORBIDDEN` blocker:
  - Root cause: the pending metadata record was bound to the invite's requested `recipient_device`, while the APNs send path uses the latest receiver PushKit token for the receiver account. A stale requested device can still produce a successful APNs delivery to the physical receiver, but the receiver's authenticated metadata fetch is then forbidden.
  - The server now keeps exact device binding only when the requested device token record is the same latest development PushKit token record APNs will use; otherwise the pending metadata is bound to the receiver account.
  - Targeted tests prove exact-device fetch still forbids a different receiver device, stale requested-device metadata follows the latest PushKit token receiver, and unrelated users remain forbidden.
  - No APNs was sent for this server fix. No production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47C7 fixes the media credentials `eligibilityRejected` blocker for incoming receiver token requests:
  - Physical proof after 2.47C6 reached `pending_metadata_fetch_result=success_redacted`, `media_credentials_request_metadata_available=true`, and token request seen, then blocked with `media_credentials_token_http_status_bucket=403`, `media_credentials_token_reason=eligibilityRejected`, and `media_credentials_eligibility_allowed=false`.
  - Root cause: the static eligibility policy required the caller peer's exact user ID to also be allowlisted, even for incoming receiver credentials requests. The pending metadata correctly sets `peer_user_id` to the caller, while the active authenticated requester is the receiver.
  - The policy still requires the authenticated receiver account to be allowlisted and keeps encrypted 1:1 room validation. For incoming direction, the peer is accepted through room validation, and a configured homeserver allowlist still applies to the peer homeserver.
  - Targeted service and route tests prove incoming receiver token requests pass, non-allowlisted receivers fail before allocation, unsupported peer homeservers fail before allocation, and the foreground-signaling token alias uses the same path.
  - No APNs was sent for this server fix. No production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47C8 fixes the persistent deployed eligibility switch mismatch:
  - After deploying 2.47C7, direct no-APNs credentials proof still returned `media_credentials_token_http_status_bucket=403`, `media_credentials_token_reason=eligibilityRejected`, and `media_credentials_eligibility_allowed=false`.
  - Root cause: staging set `SALEMXNATIVE_AUDIO_ELIGIBILITY_ENABLED=1`, while the service only read the canonical `SALEMX_NATIVE_AUDIO_ELIGIBILITY_ENABLED`. The allowlist values were present, but the service could still build the disabled eligibility policy.
  - The service now accepts the explicit legacy switch spelling as an alias for the canonical switch. This does not enable eligibility implicitly; it still requires the switch value `1` and the existing allowlist/homeserver values.
  - Targeted tests prove readiness and `ServiceConfig.from_env()` both enable eligibility from the legacy switch, and the incoming receiver token eligibility tests still pass.
  - No APNs was sent for this server fix. No production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47C physical close-out passed after the pending metadata, eligibility, and env compatibility fixes:
  - Final proof recorded `pending_metadata_fetch_result=success_redacted`, `foreground_pending_call_metadata_handoff_observed=true`, `media_credentials_request_metadata_available=true`, `media_credentials_boundary_reached=true`, `media_credentials_requested=true`, `media_credentials_request_authorized=true`, and `media_credentials_token_request_seen=true`.
  - The credentials request succeeded with `media_credentials_token_http_status_bucket=2xx`, `media_credentials_token_reason=issued`, `media_credentials_result=success_redacted`, `media_credentials_token_received=true`, `media_credentials_url_received=true`, and `media_credentials_expires_at_present=true`.
  - Cleanup proof recorded `media_credentials_cleanup_requested=true` and `media_credentials_cleanup_result=cleared`.
  - Final safety proof remained `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `microphone_permission_requested=false`, `camera_permission_requested=false`, `matrix_event_emit_requested=false`, `real_call_flow_started=false`, and `blocked_reason=none`.
  - No APNs was sent after the successful proof. No production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this close-out.
- 2.47D credentials cleanup / expiry proof is physically closed as a DEBUG-only no-connect proof:
  - Real invite/APNs/PushKit/CallKit Answer, authenticated pending metadata fetch, foreground metadata handoff, and controlled credentials request all passed with `media_credentials_token_http_status_bucket=2xx`, `media_credentials_token_reason=issued`, `media_credentials_result=success_redacted`, token/URL receipt booleans true, expiry present, and payload redacted.
  - Cleanup proof recorded `media_credentials_cleanup_requested=true`, `media_credentials_cleanup_result=cleared`, `media_credentials_post_cleanup_token_present=false`, `media_credentials_post_cleanup_url_present=false`, `media_credentials_post_cleanup_expires_at_present=false`, and `media_credentials_post_cleanup_payload_present=false`.
  - Non-reuse/expiry proof recorded `media_credentials_reuse_attempted=false`, `media_credentials_reuse_allowed=false`, `media_credentials_expiry_reference_present=true`, `media_credentials_expiry_check_requested=true`, and `media_credentials_expiry_check_result=expired_or_not_reusable_redacted`.
  - Final safety proof remained `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `microphone_permission_requested=false`, `camera_permission_requested=false`, `matrix_event_emit_requested=false`, `real_call_flow_started=false`, and `blocked_reason=none`.
  - No APNs was sent after the successful proof. No production APNs, repeated APNs, `dev/invite`, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced by this close-out.
- 2.47B5 authenticated pending metadata fetch handoff is physically validated after CallKit Answer:
  - The VoIP receipt proof now records `pending_metadata_fetch_requested`, `pending_metadata_fetch_authorized`, `pending_metadata_fetch_result`, and `pending_metadata_payload_redacted`.
  - When the APNs payload includes an opaque `pending_metadata_reference`, the controlled Answer path schedules an authenticated fetch through the existing app auth boundary, parses only the server pending-metadata response, and records `foreground_pending_call_metadata_source=authenticated_pending_metadata_fetch`.
  - Physical proof reached `physical_voip_push_received=true`, `pushkit_payload_kind=real_invite_controlled`, `pending_metadata_reference_present=true`, `pending_metadata_fetch_requested=true`, `pending_metadata_fetch_authorized=true`, `pending_metadata_fetch_result=success_redacted`, `callkit_first_action_kind=answer`, and `callkit_answer_action_received=true`.
  - Success proof sets pending metadata presence booleans for call identifier, room binding, peer, incoming direction, and audio intent, reaches `media_credentials_request_metadata_available=true`, and records `media_credentials_request_metadata_source=authenticated_pending_metadata_fetch`.
  - This phase deliberately keeps `media_credentials_requested=false`, `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `microphone_permission_requested=false`, `camera_permission_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`, with `blocked_reason=media_credentials_request_deferred_until_next_phase`.
  - Changed-file SwiftFormat passed, changed-file SwiftLint passed with only the existing file-length warning, and targeted DirectCall tests passed (`38 tests`).
  - No production APNs, repeated APNs, real media credentials request, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47B4 authenticated pending metadata source is implemented as the next safe bridge toward real credential requests:
  - The real non-dev invite route now accepts optional `pending_metadata` containing real call metadata, derives receiver-safe metadata from the authenticated caller, and stores it behind an opaque reference.
  - The APNs VoIP payload carries only `pending_metadata_reference` plus redaction proof; it does not carry raw call ID, room ID, peer/user/device identifiers, call handles, token, URL, auth header, or invite body.
  - A new authenticated pending-metadata fetch endpoint returns the stored token-request metadata only to the intended receiver/device before expiry.
  - The iOS VoIP receipt proof records `pending_metadata_reference_present`, `pending_metadata_reference_redacted`, `pending_metadata_fetch_required`, and `pending_metadata_fetch_requested=false`.
  - Server compileall passed, full call-service pytest passed (`154 passed`), changed-file SwiftFormat passed, changed-file SwiftLint passed with only the existing file-length warning, and targeted DirectCall tests passed (`38 tests`).
  - No APNs, production APNs, repeated APNs, real media credentials request, media connection, LiveKit join, microphone/camera permission request, Matrix event emission, full direct-call flow, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47B2 controlled media credentials request using handed-off metadata is implemented as a DEBUG-only boundary step:
  - The foreground production accept path now requests credentials through the existing `DirectCallLiveKitTokenProvider` seam after `foreground_call_state=real_invite_pending_media` metadata is available.
  - The request path uses the active `DirectCallSession` and does not call `connectAudio`, request microphone/camera, join LiveKit, emit Matrix events, or start full call flow.
  - Dedicated proof records `media_credentials_requested=true`, `media_credentials_request_authorized=true/false`, `media_credentials_result=success_redacted` or `blocked_redacted`, token/URL/payload redaction booleans, `media_credentials_local_persistence_requested=false`, and cleanup status.
  - LiveKit token request/response descriptions now redact call ID, room ID, peer/user metadata, token, URL, and allocation identifiers.
  - No APNs was sent for this code checkpoint. Targeted SwiftFormat passed, SwiftLint passed aside from existing file-length warnings, and targeted DirectCall test build reached simulator launch before the known `FBSOpenApplicationServiceErrorDomain / SBMainWorkspace` environment failure.
  - No production APNs, repeated APNs, media connection, LiveKit join, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47B controlled media credentials request lifecycle is physically validated as a safe blocked boundary:
  - Real non-dev invite/APNs reached SalemX VoIP receipt, CallKit report, Answer, controlled in-app screen, and `foreground_call_state=real_invite_pending_media`.
  - The media boundary now records explicit lifecycle fields: `media_credentials_request_planned=false`, `media_credentials_requested=false`, `media_credentials_request_authorized=false`, `media_credentials_result=blocked_redacted`, `media_credentials_token_received=false`, `media_credentials_token_redacted=true`, `media_credentials_url_received=false`, `media_credentials_url_redacted=true`, `media_credentials_payload_redacted=true`, `media_credentials_local_persistence_requested=false`, `media_credentials_cleanup_requested=false`, and `media_credentials_cleanup_result=not_requested`.
  - Current blocker is `media_credentials_request_boundary_not_ready`, because the foreground pending-call proof path still lacks a safe internal handoff for the raw request metadata required by the existing token endpoint.
  - Proof kept `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - No APNs was sent after the passing proof. No production APNs, repeated APNs, real media credentials request, media connection, LiveKit join, Matrix event emission, full call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47B1 real foreground pending-call metadata handoff is implemented as a DEBUG-only redacted bridge from `DirectCallSession`:
  - The existing production accept path now records a safe metadata handoff after `acceptIncomingCall()` returns a `DirectCallSession`.
  - The proof records only source, redacted payload status, metadata presence booleans, safe direction/intent values, and metadata availability for the existing credentials boundary.
  - The synthetic PushKit proof path still records `media_credentials_request_metadata_available=false` and remains blocked before any credential request when no real session metadata is available.
  - No APNs, production APNs, repeated push, real media credentials request, media connection, LiveKit join, Matrix event emission, full call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47A13 proof split and answerable-window diagnostic are implemented and physically narrowed:
  - Local CallKit-only smoke now writes only `Documents/salemx-local-callkit-only-proof.txt` with `proof_source=local_callkit_only`, `local_callkit_only_report_result=reported`, `local_callkit_only_first_action_kind=answer`, `local_callkit_only_answer_action_delivered=true`, `local_callkit_only_end_action_delivered=false`, and `blocked_reason=none`.
  - Real VoIP PushKit receipt writes only `Documents/salemx-voip-push-receipt-proof.txt` with `proof_source=voip_push_receipt`, `pushkit_payload_kind=real_invite_controlled`, `pushkit_completion_answerable_window_requested=true`, `pushkit_completion_answerable_window_result=first_action_observed`, `callkit_first_action_kind=end`, `callkit_answer_action_delivered=false`, and `blocked_reason=background_callkit_end_before_operator_action`.
  - The PushKit upload smoke proof remains separate at `Documents/salemx-pushkit-token-upload-smoke-proof.txt`.
  - Proof source/generation/last-updated fields are redacted and contain no raw tokens, auth headers, payloads, Matrix IDs, device IDs, call handles, private logs, or LiveKit URLs.
  - Proof kept `media_credentials_requested=false`, `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - No production APNs push, repeated APNs push in this commit step, real media credential request, media connection, LiveKit join, Matrix event emission, full direct-call flow, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47A10 background PushKit CallKit auto-End isolation is implemented and physically narrowed:
  - Local CallKit-only proof still works: `local_callkit_only_first_action_kind=answer`, `local_callkit_only_answer_action_delivered=true`, `local_callkit_only_end_action_delivered=false`, and `blocked_reason=none`.
  - Exactly one authenticated real non-dev invite/APNs attempt returned `background_apns_push_result=sandbox_success`; dev invite was not used.
  - Dedicated VoIP receipt proof reached `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=real_invite_controlled`, `callkit_report_result=reported`, `callkit_report_completion_observed=true`, `pushkit_completion_called=true`, `pushkit_completion_after_report_ms_bucket=<100ms`, and `callkit_end_after_pushkit_completion_ms_bucket=>2000ms`.
  - App state was foreground at PushKit receipt, report completion, and first CallKit action. CallKit update/config proof was valid generic audio-only, provider/delegate/active UUID were retained, provider reset and audio activation/deactivation were not observed before first action, and local end/invalidate/report-ended/timeout booleans stayed false.
  - The first delivered CallKit action was End: `callkit_first_action_kind=end`, `callkit_first_action_after_report_ms_bucket=>2000ms`, `callkit_ui_surface_observed_by_operator=false`, `callkit_answer_action_delivered=false`, and `blocked_reason=background_callkit_end_before_operator_action`.
  - Proof kept `media_credentials_requested=false`, `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - No production APNs push, repeated APNs push, real media credential request, media connection, LiveKit join, Matrix event emission, full direct-call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or staged `REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` was introduced.
- 2.47A6 CallKit End-before-Answer diagnostic is implemented and physically narrowed:
  - Diagnostic proof fields now record redacted CallKit report timing/config, retained provider/delegate/active UUID, first action kind, first action timing bucket, End action matching, local-end/invalidate/report-ended/timeout booleans, and event order.
  - Exactly one authenticated real non-dev invite/APNs attempt returned `background_apns_push_result=sandbox_success`; dev invite was not used.
  - Dedicated VoIP receipt proof reached `callkit_report_result=reported`, `callkit_report_completion_observed=true`, `callkit_provider_retained_for_answer=true`, `callkit_delegate_retained_for_answer=true`, `callkit_active_call_uuid_retained=true`, `callkit_first_action_kind=end`, `callkit_first_action_after_report_ms_bucket=>2000ms`, and `blocked_reason=system_or_user_end_before_answer`.
  - Proof kept `local_end_request_before_answer=false`, `provider_invalidate_before_answer=false`, `report_call_ended_before_answer=false`, `controlled_timeout_before_answer=false`, `media_credentials_requested=false`, `media_connect_requested=false`, `livekit_join_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - No production APNs push, repeated push, real media credential request, media connection, LiveKit join, Matrix event emission, full direct-call flow, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.47A7 CallKit Answer-vs-End interaction validation diagnostics are implemented:
  - The dedicated VoIP receipt proof now includes redacted operator observation fields: `callkit_ui_surface_observed_by_operator`, `callkit_operator_intended_action`, and `callkit_operator_action_timing_bucket`.
  - Internal diagnostics can mark Answer intent timing as `immediate`, `1-2s`, or `>2s`, or mark End intent, without storing screenshots, private logs, raw IDs, payloads, tokens, or URLs.
  - Physical validation after the diagnostic update reached `callkit_first_action_kind=end` with `callkit_first_action_after_report_ms_bucket=500-2000ms`.
  - Operator UI/Answer intent remained unmarked: `callkit_ui_surface_observed_by_operator=false`, `callkit_operator_intended_action=unknown`, and `callkit_operator_action_timing_bucket=unknown`.
  - Local End request, provider invalidation, report-ended, and controlled timeout before Answer remained false; current blocker is `system_end_before_answer_window`.
  - No APNs send, production APNs, repeated push, real media credential request, media connection, LiveKit join, Matrix event emission, full direct-call flow, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced by this diagnostic update.
- 2.47A controlled media credentials boundary is implemented but not physically successful:
  - The dedicated VoIP receipt proof records the planner-only boundary after `foreground_call_state=real_invite_pending_media`.
  - Planned proof fields include `media_credentials_boundary_reached=true`, `media_credentials_request_planned=true`, `media_credentials_result=planned_redacted`, `media_credentials_token_redacted=true`, `media_credentials_url_redacted=true`, and `media_credentials_payload_redacted=true`.
  - Proof keeps `media_credentials_requested=false`, `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - Changed-file SwiftFormat, changed-file SwiftLint, targeted DirectCall tests, and physical Debug build/install passed.
  - Route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, unauthenticated token registration `401`, and unauthenticated APNs send control `401`.
  - Later physical validation reached APNs and CallKit report, but did not reach Answer/foreground state/media planner because CallKit delivered End before Answer.
  - No production APNs push, repeated push, media connection, LiveKit join, Matrix event emission, full direct-call flow, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.46B real-invite foreground call-state handoff passed:
  - A fresh physical Debug build was installed on the connected iPhone.
  - Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, unauthenticated token registration `401`, and unauthenticated APNs send control `401`.
  - Exactly one authenticated non-dev invite/APNs attempt was run; dev invite was not used.
  - Dedicated VoIP receipt proof reached `pushkit_payload_kind=real_invite_controlled`, `real_invite_payload_mapping_observed=true`, `callkit_report_result=reported`, `pushkit_completion_called=true`, `callkit_answer_action_received=true`, `callkit_answer_action_fulfilled=true`, `controlled_in_app_screen_presented=true`, `foreground_call_state_handoff_requested=true`, `foreground_call_state_handoff_observed=true`, `foreground_call_state=real_invite_pending_media`, `foreground_call_state_source=callkit_answer_real_invite_controlled`, `foreground_call_state_payload_redacted=true`, `foreground_call_state_has_stable_redacted_correlation=true`, and `blocked_reason=none`.
  - Proof kept `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - No production APNs push, repeated push, media behavior, Matrix event emission, full direct-call flow, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.45B PushKit callback controlled CallKit report proof passed:
  - A fresh physical Debug build was installed on the connected iPhone.
  - The manual PushKit upload smoke refreshed the persisted staging token with redacted `http_success`, `registered`, `persisted`, and `redacted_match` proof.
  - Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, unauthenticated token registration `401`, and unauthenticated APNs send control `401`.
  - APNs dry-run returned HTTP `200` with persisted token lookup `found`, credentials available, sandbox environment, topic resolved, result `dry_run`, and `blocked_reason=none`.
  - Exactly one real sandbox VoIP push send was attempted and returned `apns_voip_push_send_result=sandbox_success`, `apns_failure_reason=none`, and `blocked_reason=none`.
  - Physical iPhone proof reached `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_redacted=true`, `pushkit_payload_kind=sandbox_voip_smoke`, `pushkit_completion_called=true`, `callkit_report_requested=true`, and `callkit_report_result=reported`.
  - Proof kept `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - No production APNs push, repeated push, media behavior, Matrix event emission, full direct-call flow, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.45A physical VoIP push receipt proof passed:
  - A fresh physical Debug build was installed on the connected iPhone.
  - The manual PushKit upload smoke refreshed the persisted staging token with redacted `http_success`, `registered`, `persisted`, and `redacted_match` proof.
  - Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, unauthenticated token registration `401`, and unauthenticated APNs send control `401`.
  - APNs dry-run returned HTTP `200` with persisted token lookup `found`, credentials available, sandbox environment, topic resolved, result `dry_run`, and `blocked_reason=none`.
  - Exactly one real sandbox VoIP push send was attempted and returned `apns_voip_push_send_result=sandbox_success`, `apns_failure_reason=none`, and `blocked_reason=none`.
  - Physical iPhone proof reached `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_redacted=true`, `pushkit_payload_version=1`, `pushkit_payload_kind=sandbox_voip_smoke`, and `pushkit_completion_called=true`.
  - Proof kept `callkit_report_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`.
  - No production APNs push, repeated push, CallKit report from PushKit, media behavior, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.44C controlled APNs VoIP sandbox send scaffold is implemented and deployed:
  - Added a server-side APNs VoIP sandbox scaffold with an explicit auth-gated control route and redacted diagnostics.
  - APNs send remains disabled by default and production APNs environment is rejected in this scaffold.
  - Local server validation passed: compileall passed and pytest reported `151 passed`.
  - Deployed only `server/salemx-call-service/salemx_call_service/app.py` and `server/salemx-call-service/salemx_call_service/apns_voip.py` to staging.
  - Remote compileall passed; `salemx-call-service` restart succeeded; service active was verified after restart.
  - Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.
  - The controlled localhost scaffold invocation returned redacted `persisted_pushkit_token_lookup_result=missing` and `blocked_reason=persisted_pushkit_token_missing` for the available staging credential.
  - APNs credentials/topic were not configured in the service environment; no APNs provider request, real sandbox send, production APNs send, repeated push, standard APNs token request, real PushKit/background callback wiring, CallKit report from PushKit, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.44B1 physical persisted PushKit token upload smoke passed:
  - A physical iPhone became available through CoreDevice/Xcode.
  - Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.
  - The updated Debug build installed and the DEBUG/manual smoke control received a real PushKit token, redacted it, and uploaded it to staging.
  - Redacted proof reached `pushkit_token_upload_result=http_success`, `pushkit_token_registration_result=registered`, `pushkit_token_server_store_requested=true`, `pushkit_token_server_store_result=persisted`, `pushkit_token_retrieval_internal_check=redacted_match`, and `pushkit_token_api_exposes_raw_token=false`.
  - iOS local token persistence remained `false`; the API did not return the raw token; retrieval remains internal-only.
  - No standard APNs token request, APNs provider request, server VoIP push delivery, real PushKit/background callback wiring into call flow, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.44B controlled server-side PushKit token persistence is implemented and deployed:
  - Server persistence uses a minimal file-backed store at `/tmp/salemx-call-service-pushkit-token-store/pushkit-tokens.json`, with `0700` directory permissions, `0600` file permissions, and hashed user/device/environment keys.
  - The raw token is stored only inside the server-side store for future internal APNs send code and is never returned by API, logged, printed, copied into docs, or exposed in diagnostics.
  - Local server validation passed: compileall passed and pytest reported `142 passed`.
  - Deployed only `server/salemx-call-service/salemx_call_service/app.py` and `server/salemx-call-service/salemx_call_service/pushkit_tokens.py` to staging.
  - Remote compileall passed; `salemx-call-service` restart succeeded; service active was verified after restart.
  - Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.
  - No standard APNs token request, APNs provider request, server VoIP push delivery, real PushKit/background callback wiring into call flow, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.44A controlled physical PushKit token upload smoke passed:
  - Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.
  - Physical iPhone availability, Debug build, install, and launch were verified with the current `M639Y9MFR2` signing state.
  - PushKit registration and upload were invoked only through explicit DEBUG/manual smoke controls, not app startup or normal runtime.
  - Redacted proof reached `physical_device_available=true`, `pushkit_registration_manual_invoked=true`, `pushkit_token_received=true`, `pushkit_token_redacted=true`, `pushkit_token_upload_requested=true`, `pushkit_token_upload_result=http_success`, and `pushkit_token_registration_result=registered`.
  - Redacted proof kept `pushkit_token_local_persistence_requested=false`, `pushkit_token_server_store_requested=false`, `pushkit_token_server_store_result=not_persisted`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, and `real_pushkit_background_callback_wired=false`.
  - No raw PushKit/APNs token was printed, logged, persisted, uploaded to durable storage, recorded in docs, or committed.
  - No standard APNs token request, APNs provider request, server VoIP push delivery, real PushKit/background callback wiring into call flow, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.43Z public token route proxy smoke passed:
  - Staging localhost token registration remained unauthenticated `401`.
  - Public staging token registration changed from unauthenticated `404` to `401`.
  - Public `dev/invite=404`, unauthenticated non-dev invite `401`, and unauthenticated stream `401` remained intact.
  - The public reverse proxy token-registration route was added to the same `salemx-call-service` upstream used by foreground signaling.
  - nginx syntax validation passed, nginx was reloaded, and nginx active status was verified after reload.
  - Synthetic-token public staging registration passed with client `pushkit_token_upload_result=http_success` and server `pushkit_token_registration_result=registered`.
  - Server proof kept `pushkit_token_store_requested=false`, `pushkit_token_store_result=not_persisted`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
  - No real PushKit/APNs token was used, logged, persisted, uploaded, or recorded.
- 2.43U staging SSH/network deploy path recovery is blocked:
  - The staging SSH alias resolves to port `71`, which is the expected deploy port for this environment.
  - Port `22` is not the primary deploy check for this environment.
  - A bounded port `71` connectivity check failed before authentication or host-key negotiation.
  - A bounded SSH probe through the port `71` alias timed out before `systemctl` could run.
  - Redacted blocker: `staging_deploy_blocked_by_firewall_or_network_path`.
  - No server deployment, restart, synthetic-token staging smoke, environment-variable change, or route activation was performed.
  - Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
  - Direct `salemx-call-service active` status is not verified.
- 2.43V manual staging deploy package is documented:
  - Added `docs/direct-call/PUSHKIT_STAGING_MANUAL_DEPLOY_RUNBOOK.md`.
  - The package lists only the 2.43Q/2.43R call-service endpoint files: runtime `app.py` and `pushkit_tokens.py`, plus `tests/test_service.py` for validation.
  - The runbook covers safe manual deployment options, pre-deploy checks, post-deploy route checks, synthetic-token smoke proof, forbidden data, rollback, and next prompt constraints.
  - No deploy, restart, live smoke, environment-variable change, or route activation was performed.
  - Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
- 2.43Y staging token endpoint post-restart smoke is blocked at the public route:
  - Narrow sudo restart/status access for `salemx-call-service` was added manually.
  - Service active was verified after restart.
  - Localhost route checks on the staging host show token registration is active and auth-gated with unauthenticated `401`.
  - Public live route checks still show unauthenticated token registration `404`, so the endpoint is not exposed through the public staging route.
  - Redacted blocker: `staging_token_registration_route_still_missing_after_restart`.
  - No synthetic-token staging smoke was run.
  - Live public route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
- 2.43X staging service restart activation smoke is blocked:
  - SSH access on port `71` is still verified.
  - Direct `salemx-call-service active` status is verified before restart.
  - Restarting only `salemx-call-service` with direct `systemctl` is blocked by interactive authentication.
  - Restarting with non-interactive `sudo -n systemctl restart salemx-call-service` is blocked because sudo requires a password.
  - Redacted blocker: `staging_restart_blocked_by_sudo_password_required`.
  - No restart, synthetic-token staging smoke, environment-variable change, route activation, or additional file deploy was performed.
  - Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
- Resumed 2.43W fail2ban-aware staging deploy smoke is blocked at service restart:
  - SSH auth on port `71` is verified with publickey.
  - The two runtime files for the token endpoint were copied to staging: `app.py` and `pushkit_tokens.py`.
  - Remote compileall for `salemx_call_service` passed.
  - Restarting `salemx-call-service` is blocked by service restart authorization.
  - Redacted blocker: `staging_deploy_blocked_by_restart_auth`.
  - Direct `salemx-call-service active` status was verified, but it is still the pre-restart process.
  - No synthetic-token staging smoke was run.
  - Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
- Earlier 2.43W fail2ban-aware staging deploy smoke was blocked by SSH auth:
  - The operator manually cleared fail2ban before this attempt.
  - The staging SSH alias still resolves to port `71`.
  - Bounded port `71` connectivity is now open.
  - A bounded SSH probe reached authentication but was rejected before any remote command could run.
  - Redacted blocker: `staging_deploy_blocked_by_auth`.
  - No server deployment, restart, synthetic-token staging smoke, environment-variable change, or route activation was performed.
  - Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
  - Direct `salemx-call-service active` status is not verified.
- 2.43T staging deploy access remediation is blocked:
  - Existing repo docs/scripts describe local staging harnesses but do not provide a complete remote deployment recipe.
  - The local SSH config contains a staging deploy alias using a non-standard SSH port, and the configured identity file is present.
  - Bounded connectivity checks to the configured alias port and port 22 both failed from this machine before authentication or host-key negotiation.
  - A bounded SSH probe to the configured staging alias timed out before `systemctl` could run.
  - Redacted blocker: `staging_deploy_blocked_by_ssh_timeout`.
  - No server deployment, restart, synthetic-token staging smoke, environment-variable change, or route activation was performed.
  - Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
  - Direct `salemx-call-service active` status is not verified.
- 2.43S staging PushKit token endpoint deploy smoke is blocked:
  - Pre-deploy local server tests still pass: `139 passed`.
  - Python compileall passed.
  - SSH to the staging deploy alias timed out, so no server deployment or restart was performed.
  - Redacted blocker: `staging_deploy_blocked_by_ssh_timeout`.
  - Live staging token registration remains `404` because 2.43Q/2.43R server code is not deployed there.
  - No staging synthetic-token registration pass is claimed.
  - No real PushKit/APNs token was used, logged, persisted, uploaded, or recorded. No APNs provider request, VoIP push delivery, real PushKit/background callback wiring, media behavior, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.
- 2.43R validates local fake-token app/server registration:
  - The smoke uses the changed local server app only; no live staging deploy is performed.
  - Client-side proof reached `pushkit_token_registration_invoked=true`, `pushkit_token_present=true`, `pushkit_token_upload_requested=true`, `pushkit_token_persistence_requested=false`, `pushkit_token_upload_result=http_success`, `apns_registration_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
  - Server-side proof reached `pushkit_token_registration_invoked=true`, `pushkit_token_present=true`, `pushkit_token_store_requested=false`, `pushkit_token_store_result=not_persisted`, `pushkit_token_registration_result=registered`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
  - Local route safety remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.
  - No real PushKit token is used, logged, persisted as raw, uploaded from actual PushKit runtime, recorded, documented, or committed. No APNs registration, VoIP push delivery, real PushKit/background callback wiring, media behavior, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration is introduced.
- 2.43Q adds a server PushKit token registration endpoint/contract:
  - `POST /_matrix/client/unstable/kz.salemx.direct_call/pushkit/token` is auth-gated through the existing Matrix bearer-token validator.
  - Tests use synthetic token payloads only and verify unauthenticated `401`, authenticated redacted success, malformed-payload rejection, no raw token in logs/diagnostics, and disabled dev route behavior.
  - Successful diagnostics include `pushkit_token_registration_result=registered`, `pushkit_token_store_requested=false`, `pushkit_token_store_result=not_persisted`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
  - No durable token persistence, real app-runtime token upload, APNs provider call, server VoIP push delivery, APNs registration, real PushKit/background callback wiring, media behavior, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration is introduced.
- 2.43P adds a PushKit token registration contract/client seam:
  - The seam accepts token bytes only at the client boundary and reduces diagnostics to redacted presence/status classes.
  - Tests use an injected fake transport to prove one redacted registration request can be produced for a synthetic token.
  - Empty tokens fail closed before any upload attempt, and fake transport failures return redacted failure classes.
  - No real network upload is implemented, no token is persisted, and no raw PushKit/APNs token appears in diagnostics.
  - No APNs registration is requested, no real PushKit/background callback is wired, no server VoIP push delivery is attempted, and no media/Matrix/Element Call route behavior is changed.
- 2.43O validates controlled local PushKit registration smoke:
  - The physical Debug build, install, and launch succeeded using `DEVELOPMENT_TEAM=M639Y9MFR2`.
  - PushKit registration was requested only through the DEBUG-only local manual smoke control while the app remained foreground.
  - Redacted smoke diagnostics reached `pushkit_registration_requested=true`, `pushkit_feature_gate_enabled=true`, `pushkit_registry_create_requested=true`, `pushkit_token_update_received=true`, and `pushkit_registration_result=token_received`.
  - The smoke proof kept `pushkit_token_persistence_requested=false`, `pushkit_token_upload_requested=false`, `apns_registration_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
  - No raw PushKit/APNs token was copied, logged, pasted, persisted, uploaded, recorded, documented, or committed.
  - No APNs registration was requested, no real PushKit/background payload callback was wired into the native direct-call flow, no media credential or media connection behavior was introduced, and foreground real invite behavior remains unchanged.
  - Real native direct-call PushKit registration remains disabled by default outside the controlled local DEBUG smoke.
- 2.43N validates physical install capability state:
  - Developer Mode was enabled manually on the physical iPhone; the device was restarted, unlocked, trusted, reconnected, and available to Xcode/CoreDevice.
  - The physical iOS Debug build, install, and launch succeeded using the checked-in 2.43L capability/signing state and `DEVELOPMENT_TEAM=M639Y9MFR2`.
  - Effective Team ID / App Identifier prefix class is `M639Y9MFR2`.
  - Effective bundle ID class is `kz.salemx.msg`.
  - Effective app entitlements include development `aps-environment` and the expected app group/keychain classes.
  - Effective `UIBackgroundModes` includes `voip`.
  - No unexpected unrestricted VoIP entitlement was present.
  - The old team ID `83LGSC2QPV` was not present in the built app bundle.
  - No physical PushKit registration smoke was run.
  - Real PushKit registration remains disabled by default, no PushKit/APNs token was requested/logged/persisted, no APNs registration was added, no real PushKit/background callback was wired, and no media/Matrix/Element Call route behavior was changed.
- 2.43B adds a safe background invite payload contract/parser seam:
  - The parser is inert and side-effect free; it does not register PushKit, request a VoIP token, register APNs, report CallKit automatically, emit Matrix events, request media credentials, connect media, or change production call behavior.
  - Parser diagnostics are redacted status classes only: `valid`, `missing_required_field`, `invalid_type`, `invalid_timestamp`, `expired`, `future_timestamp_excessive`, `unsupported_version`, `malformed_payload`, and `redacted`.
  - Timestamp guardrails match the foreground invite path: current payloads and small future skew are accepted, while expired payloads and excessive future timestamps fail closed.
  - Signing, provisioning, project files, `Info.plist`, `app.yml`, and entitlements remain untouched.
  - The foreground real-invite path remains unchanged.
  - Future 2.43C work should be separately scoped as PushKit registration/token-handling design or implementation only if explicitly allowed.
  - Future entitlement/signing/project changes require a separate explicit task.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
- 2.43C adds a safe background invite intake seam:
  - The intake consumes the 2.43B parser result and returns only redacted internal decisions such as `ignore_invalid_payload`, `ignore_expired_payload`, `ignore_future_timestamp_excessive`, `requires_authenticated_session`, `prepare_foreground_equivalent_incoming`, and `requires_callkit_report_later`.
  - Intake diagnostics are redacted booleans/status classes only and keep `callkit_report_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
  - PushKit registration, APNs registration, VoIP/background entitlements, project/signing files, CallKit reporting, media credentials, media connection, Matrix event emission, and production background behavior remain unimplemented.
  - The foreground real-invite path remains unchanged.
  - Future 2.43D may design or implement a CallKit reporting adapter seam for background invite decisions, still without PushKit registration unless explicitly allowed.
  - Any future signing, entitlement, provisioning, project, `Info.plist`, or `app.yml` change requires a separate explicit task.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
- 2.43D adds a safe background CallKit report request planner seam:
  - The planner consumes the 2.43C intake result and returns either a redacted internal `reportable_incoming_call_request` model or non-reportable decisions for invalid, expired, excessive-future, and missing-session cases.
  - Planner diagnostics are redacted booleans/status classes only and keep `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
  - No real `CXProvider` or PushKit/background callback reports a CallKit incoming call in this task.
  - PushKit registration, APNs registration, VoIP/background entitlements, project/signing files, media credentials, media connection, Matrix event emission, and production background behavior remain unimplemented.
  - The foreground real-invite path remains unchanged.
  - Future 2.43E may add a fake/test-only CallKit adapter boundary or a controlled real CallKit adapter, still without PushKit registration unless explicitly allowed.
  - Any future signing, entitlement, provisioning, project, `Info.plist`, or `app.yml` change requires a separate explicit task.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
- 2.43E adds a safe background CallKit adapter boundary and fake/test reporting seam:
  - The adapter consumes the 2.43D report planning result and returns redacted statuses such as `not_reported_not_reportable`, `not_reported_missing_authenticated_context`, `report_attempt_recorded`, and `report_failed_redacted`.
  - Tests can inject a fake recorder and prove one redacted report attempt is recorded for a reportable request.
  - Non-reportable and missing-session decisions record no report attempt and expose only redacted blocked reasons.
  - Adapter diagnostics keep `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, `pushkit_registration_requested=false`, and `apns_registration_requested=false`.
  - No real PushKit/background callback is wired to this adapter, and no real `CXProvider.reportNewIncomingCall` call is introduced in this task.
  - PushKit registration, APNs registration, VoIP/background entitlements, project/signing files, media credentials, media connection, Matrix event emission, and production background behavior remain unimplemented.
  - The foreground real-invite path remains unchanged.
  - Future real CallKit and PushKit lifecycle work must stay separated from entitlement/signing/project changes unless separately authorized.
  - Any future signing, entitlement, provisioning, project, `Info.plist`, or `app.yml` change requires a separate explicit task.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
- 2.43F adds a controlled real CallKit adapter behind the existing boundary:
  - The adapter consumes the 2.43D report planning result and translates reportable requests into a CallKit-provider report request through an injected provider protocol.
  - Tests use a fake provider to prove exactly one report attempt for a valid request, no report attempt for non-reportable decisions, and redacted provider failures.
  - The iOS provider implementation can build a `CXCallUpdate` from safe internal request data, but it is not wired to PushKit/APNs/background callbacks, app launch, or production background behavior.
  - Diagnostics remain redacted booleans/status classes and keep `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, `pushkit_registration_requested=false`, and `apns_registration_requested=false`.
  - PushKit registration, APNs registration, VoIP/background entitlements, project/signing files, media credentials, media connection, Matrix event emission, Element Call route replacement, and production background behavior remain unimplemented.
  - The foreground real-invite path remains unchanged.
  - Future PushKit lifecycle work must keep entitlement/signing/project changes separate unless explicitly authorized.
  - Any future signing, entitlement, provisioning, project, `Info.plist`, or `app.yml` change requires a separate explicit task.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
- 2.43G adds a PushKit lifecycle abstraction/fake seam:
  - The seam defines redacted fake lifecycle events for registration requests, token updates, token invalidation, payload receipt, and registration-unavailable states.
  - Fake payload receipt composes the 2.43B parser, 2.43C intake, 2.43D planner, and an injected fake/test 2.43F CallKit adapter path.
  - Token update and invalidation events produce redacted decisions only; raw PushKit/APNs tokens are not logged, persisted, sent to a server, or exposed in diagnostics.
  - Diagnostics keep `pushkit_registration_requested=false`, `apns_registration_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
  - No real `PKPushRegistry` is created, no PushKit/APNs token is requested, no app-start or background callback is wired, and no production background behavior is introduced.
  - PushKit registration, APNs registration, VoIP/background entitlements, project/signing files, media credentials, media connection, Matrix event emission, Element Call route replacement, and production background behavior remain unimplemented.
  - The foreground real-invite path remains unchanged.
  - Future 2.43I may be an explicit PushKit registration design task, but entitlement/signing/project changes remain separate and require explicit authorization.
  - Any future signing, entitlement, provisioning, project, `Info.plist`, or `app.yml` change requires a separate explicit task.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
- 2.43H adds a docs-first PushKit entitlement/provisioning/server readiness plan:
  - The plan lives in `docs/direct-call/PUSHKIT_READINESS_PLAN.md` and does not implement PushKit registration, APNs registration, background callbacks, entitlement changes, provisioning changes, project/signing edits, media behavior, Matrix event emission, or production background behavior.
  - It records the safe baseline after 2.42M/2.42O and the 2.43B-G parser, intake, planner, adapter, real CallKit adapter, and fake lifecycle seams.
  - It separates future work into registrar design, token redaction/lifecycle tests, controlled physical registration smoke, server token registration contract, and later VoIP push delivery smoke.
  - It documents Apple capability/provisioning requirements, including `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
  - It requires any future entitlement, signing, provisioning, project, `Info.plist`, or `app.yml` change to be separately authorized.
  - It keeps raw PushKit/APNs tokens, identifiers, request payloads, private logs, and secret-bearing URLs out of diagnostics/docs/logs.
  - It preserves the validated foreground real-invite path, keeps dev routes disabled, keeps real non-dev routes auth-gated, and forbids media credentials, media connection, and Matrix event emission from push receipt.
  - Future PushKit registration work remains separate and must not touch entitlement/signing/project changes unless explicitly authorized.
- 2.43I adds a gated PushKit registrar scaffold:
  - The registrar feature gate defaults disabled.
  - Default configuration does not create a PushKit registry, request a PushKit token, persist a token, or upload a token.
  - The isolated real PushKit registry factory imports PushKit, but it is not wired to app startup or production background callbacks.
  - Enabled tests use a fake registry/fake delegate only.
  - Token update and invalidation diagnostics are redacted and never include raw PushKit/APNs tokens.
  - APNs registration, VoIP/background entitlement changes, project/signing edits, media credentials, media connection, Matrix event emission, Element Call route replacement, and production background behavior remain unimplemented.
  - The foreground real-invite path remains unchanged.
  - Future 2.43J may run a controlled local physical PushKit registrar smoke only after explicit approval and entitlement/profile readiness.
  - Any future signing, entitlement, provisioning, project, `Info.plist`, or `app.yml` change requires a separate explicit task.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
- 2.43J documents PushKit capability readiness verification:
  - The readiness matrix in `docs/direct-call/PUSHKIT_READINESS_PLAN.md` records foreground baseline, background seams, registrar scaffold, runtime registration, entitlements, provisioning, team ID, server token registration, provider credentials, route safety, privacy, and rollback status.
  - Current code has a gated scaffold only; real PushKit registration remains disabled and is not wired to app startup.
  - Tracked `ElementX/SupportingFiles/ElementX.entitlements` contains development `aps-environment`, and tracked `ElementX/SupportingFiles/Info.plist` includes `UIBackgroundModes` with `voip`; Apple Developer portal and installed provisioning profile readiness remain not verified by this docs-only task.
  - Tracked `app.yml` still references old `DEVELOPMENT_TEAM: 83LGSC2QPV`; physical Debug work must use `M639Y9MFR2`, and any signing remediation requires a separate explicit task.
  - Server token registration and VoIP push provider readiness remain not implemented or not verified.
  - Route-level safety remains verified with `dev/invite=404`, unauthenticated non-dev invite `401`, and unauthenticated stream `401`.
  - Direct `systemctl` service status must not be claimed unless it is actually verified.
  - No PushKit/APNs token request, APNs registration, entitlement/profile/project/signing edit, media credential request, media connection, Matrix event emission, Element Call route replacement, physical smoke, or production background behavior was added.
- 2.43K documents a PushKit entitlement/provisioning change proposal:
  - The proposal lives in `docs/direct-call/PUSHKIT_ENTITLEMENT_CHANGE_PROPOSAL.md`.
  - It is docs-only and does not apply project, signing, entitlement, `Info.plist`, `app.yml`, provisioning, bundle ID, PushKit registration, APNs registration, token request, media, Matrix event, Element Call route, or production background behavior changes.
  - Current tracked state: main app, NSE, and Share Extension entitlement files exist and are referenced by target/project config.
  - Main app entitlements include development `aps-environment`; no tracked entitlement file includes `com.apple.developer.pushkit.unrestricted-voip` or another PushKit/VoIP-specific entitlement key.
  - Main app `Info.plist` and target config already include `UIBackgroundModes` with `voip`.
  - Tracked `app.yml` and generated project state still reference old team `83LGSC2QPV`; future physical PushKit work must use `M639Y9MFR2`.
  - Future edits to `.entitlements`, `Info.plist`, `SalemX.xcodeproj/project.pbxproj`, `app.yml`, or signing/provisioning settings require explicit user authorization.
  - Real PushKit registration remains disabled and unwired, and server token/provider readiness remains separate future work.
- 2.43L applies minimal PushKit capability-file readiness changes:
  - Updated only `SalemX.xcodeproj/project.pbxproj` generated Development Team / project-level `DEVELOPMENT_TEAM` references from old `83LGSC2QPV` to `M639Y9MFR2`.
  - Left `ElementX/SupportingFiles/ElementX.entitlements` unchanged because development `aps-environment` is already present.
  - Left `ElementX/SupportingFiles/Info.plist` unchanged because `UIBackgroundModes` already includes `voip`.
  - Did not add `com.apple.developer.pushkit.unrestricted-voip` or any speculative PushKit/VoIP-specific entitlement key.
  - Did not touch NSE or Share Extension entitlements.
  - Did not edit `app.yml`; it still contains the old team value and must not be used to regenerate the project for PushKit physical smoke readiness until a separate source-config remediation task is approved.
  - Real PushKit registration remains disabled by default, no PushKit/APNs token is requested, no APNs registration is added, no real PushKit/background callback is wired, and no media/Matrix/Element Call route behavior is changed.
  - Next step should be controlled build/profile validation against the checked-in project and Apple Developer/profile state, not token registration.
- 2.43M validates PushKit capability build/profile state:
  - Built the checked-in 2.43L project for the generic physical iOS Debug destination using `DEVELOPMENT_TEAM=M639Y9MFR2`, `CODE_SIGN_STYLE=Automatic`, `-allowProvisioningUpdates`, and `-allowProvisioningDeviceRegistration`.
  - The build succeeded and produced a signed `SalemX.app`.
  - Effective Team ID / App Identifier prefix class is `M639Y9MFR2`.
  - Effective bundle ID class is `kz.salemx.msg`.
  - Effective app entitlements include development `aps-environment`, expected app group/keychain classes, and no unexpected unrestricted VoIP entitlement.
  - Effective `UIBackgroundModes` includes `voip`.
  - The old team ID `83LGSC2QPV` was not present in the built app bundle.
  - Physical install was blocked because CoreDevice listed the available physical phones as unavailable.
  - `app.yml` remains a regeneration risk and must not be used to regenerate the project until source-config signing remediation is separately approved.
  - Real PushKit registration remains disabled by default, no PushKit/APNs token was requested/logged/persisted, no APNs registration was added, no real PushKit/background callback was wired, and no media/Matrix/Element Call route behavior was changed.
- 2.43A documents the PushKit/APNs/background incoming-call investigation after the 2.42O foreground baseline:
  - The 2.42O validated foreground real-invite baseline remains unchanged.
  - Existing PushKit registration and VoIP push handling are present in the Element Call service path, not in SalemX native direct-call background behavior.
  - Normal APNs registration exists through `AppDelegate`, `AppCoordinator`, and `NotificationManager`.
  - Tracked app files already contain development APNs and background-mode assumptions, but this investigation does not change signing, provisioning, project settings, `Info.plist`, `app.yml`, or entitlements.
  - Native direct-call background PushKit/APNs incoming-call support is not implemented yet.
  - Future PushKit/APNs work must be separately scoped and must not alter the validated foreground real-invite path.
  - PushKit receipt must not request media credentials, connect media, emit Matrix events from invite receipt, use dev routes, or expose raw identifiers, tokens, request payloads, private logs, or secret-bearing URLs.
  - Dev routes remain disabled and real non-dev routes remain auth-gated.
  - Direct `systemctl` SSH checks may be blocked by host-key/auth and must be reported separately from route-level safety checks.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
- 2.42O consolidates the validated foreground real-invite token-guard baseline:
  - 2.42L hardened stale-token/`401` sender diagnostics at `9544d85090bb152f5c28d5acd11f37815556e078`.
  - 2.42M1 added the DEBUG-only sender bridge at `751316429c5476217f7b881d9a2f542a4e7e3b3b`.
  - 2.42M2 added the DEBUG-only receiver SSE bridge/proof path at `6c1c47b5386ed5051cea8ee0277719b4d2bd4cce`.
  - 2.42M3 added DEBUG-only in-app foreground smoke controls at `a579509c6ea7c294fa428370efa10bf875b053bb`.
  - 2.42M4 exposed the DEBUG-only `Internal diagnostics` entry at `26a07771c22c8c3d615b9c34552f3b811510b724`.
  - 2.42M physical two-device foreground real-invite smoke passed at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`.
  - 2.42N guarded the DEBUG smoke tooling release surface at `26e520b6f6ec0220ce118051f5acac36ed40bfba`.
  - Current validated foreground real-invite baseline is `26e520b6f6ec0220ce118051f5acac36ed40bfba`; future branches should start from that validated head or a documented descendant.
  - `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` remains intentionally untracked and must not be staged or committed.
  - The dev route remains disabled by default, and the real non-dev route remains auth-gated.
  - Receiver identifiers were used locally only during smoke and were not recorded.
  - No media credentials, media connection, PushKit/APNs/background behavior, Matrix event emission from invite receipt, Element Call route replacement, signing/project setting, `app.yml`, `Info.plist`, or entitlement change was added.
  - Route-level safety checks can confirm `dev/invite=404`, unauthenticated non-dev invite `401`, and unauthenticated stream `401`; direct `systemctl` SSH checks may be blocked by host-key/auth and must be reported separately when not verified.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used for current physical Debug builds.
- 2.42N verifies and hardens the DEBUG-only foreground smoke tooling release surface after the 2.42M pass at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`:
  - The M1-M4 sender bridge, receiver bridge, in-app foreground smoke controls, and Settings `Internal diagnostics` entry are local supervised smoke tooling only.
  - Source-surface tests now guard that the smoke bridges, receiver proof controls, Settings Developer Options action, and session registration hook remain inside DEBUG compile gates.
  - Proof summaries and sender diagnostics remain redacted booleans/status classes and must not expose access tokens, authorization headers, user IDs, device IDs, room IDs, recipients, call handles, request payloads, private logs, or secret-bearing URLs.
  - The smoke tooling must not be used as production call behavior.
  - The dev route remains disabled by default, and the real non-dev route remains auth-gated.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used for current physical Debug builds.
- 2.42M physical regression smoke passed after foreground real-invite token guard hardening:
  - Baseline token guard commit: `9544d85090bb152f5c28d5acd11f37815556e078`.
  - Sender bridge commit: `751316429c5476217f7b881d9a2f542a4e7e3b3b`.
  - Receiver bridge commit: `6c1c47b5386ed5051cea8ee0277719b4d2bd4cce`.
  - In-app receiver controls commit: `a579509c6ea7c294fa428370efa10bf875b053bb`.
  - Developer Options entry commit: `26a07771c22c8c3d615b9c34552f3b811510b724`.
  - Receiver pre-invite proof was collected through DEBUG in-app smoke controls at `Settings -> Internal diagnostics -> General -> Foreground SSE smoke`.
  - The sender bridge was invoked locally only; receiver identifiers were typed locally and were not recorded, logged, documented, or committed.
  - Redacted sender diagnostics reached `sender_invite_post_status=http_success`, `sender_invite_delivery_report_received=true`, and `sender_invite_blocked_reason=none`.
  - Server diagnostics showed one active subscriber, `subscriber_available=True`, `invite_enqueued=True`, `delivered=True`, `dropped=False`, `invite_yielded`, and `sse_event_type=foreground.call.invite`.
  - Receiver diagnostics reached `sse_connected=true`, `stream_failure=none`, `raw_event_received=true`, `sse_event_type=foreground.call.invite`, `invite_parse_succeeded=true`, `pipeline_delivered=true`, `invite_received=true`, `invite_valid=true`, and `incoming_requested=true`.
  - The authenticated real non-dev invite route was used; the dev route remained disabled, unauthenticated non-dev invite remained `401`, and unauthenticated stream remained `401`.
  - No media credentials, media connection, PushKit/APNs/background path, Matrix event emission from invite receipt, Element Call route replacement, signing/project setting, `app.yml`, `Info.plist`, or entitlement change was added.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used for current physical Debug builds.
- 2.42M4 exposes the DEBUG-only Developer Options entry:
  - This was the final reachability fix before the 2.42M physical regression smoke pass.
  - The latest blocker was `debug_smoke_controls_not_reachable_from_settings`; 2.42M3 controls were present on `DeveloperOptionsScreen`, but that screen was not reachable from the visible Settings UI.
  - Settings now exposes a DEBUG-only `Internal diagnostics` row that opens the existing Developer Options screen.
  - The receiver smoke path should now be reachable as `Settings -> Internal diagnostics -> General -> Foreground SSE smoke`.
  - Receiver identifiers remain local-only sensitive inputs and must not be recorded, logged, documented, or committed.
  - The physical regression smoke must still use the authenticated non-dev foreground invite route with the dev route disabled.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used for current physical Debug builds.
- 2.42M3 adds DEBUG-only in-app foreground smoke controls:
  - The 2.42M physical regression smoke remains pending and is not marked passed.
  - The latest blocker was `receiver_sse_proof_unavailable`; receiver LLDB/CoreDevice expression evaluation was not reliable enough for supervised smoke proof.
  - The 2.42M1 sender bridge commit `751316429c5476217f7b881d9a2f542a4e7e3b3b` and 2.42M2 receiver bridge commit `6c1c47b5386ed5051cea8ee0277719b4d2bd4cce` remain reachable.
  - Developer Options now exposes DEBUG-only foreground SSE smoke controls that start the current-session receiver stream and display the existing redacted receiver proof summary from inside the app.
  - The in-app proof shows only safe booleans/status classes for connection, stream failure, event type, invite parsing, pipeline delivery, invite validity, and incoming request state.
  - Receiver identifiers remain local-only sensitive inputs and must not be recorded, logged, documented, or committed.
  - The physical regression smoke must still use the authenticated non-dev foreground invite route with the dev route disabled.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used for current physical Debug builds.
- 2.42M2 adds a DEBUG-only receiver SSE bridge/proof path:
  - The 2.42M physical regression smoke remains pending and is not marked passed.
  - The latest blocker was `receiver_sse_proof_blocked_by_coredevice_lldb_handshake`; receiver LLDB/CoreDevice handshakes were unstable, while no non-LLDB receiver proof path existed.
  - 2.42M1 sender bridge commit `751316429c5476217f7b881d9a2f542a4e7e3b3b` remains reachable.
  - `SalemXForegroundSSEReceiverSmokeDebugBridge` can configure/start/stop the existing active-session SSE helper and return a redacted state summary for supervised smoke proof.
  - The state summary contains only safe booleans/status classes for SSE connection, stream failure, event type, invite parsing, pipeline delivery, invite validity, and incoming request state.
  - Receiver identifiers remain local-only sensitive inputs and must not be recorded, logged, documented, or committed.
  - The bridge does not store identifiers, expose tokens, weaken server auth, use dev routes, request media credentials, connect media, emit Matrix events, add PushKit/APNs/background behavior, or replace Element Call routing.
  - The next physical regression smoke must still use the authenticated non-dev foreground invite route with the dev route disabled.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used for current physical Debug builds.
- 2.42M1 adds a DEBUG-only local bridge for supervised foreground real-invite smoke invocation:
  - The 2.42M regression smoke was blocked by LLDB invocation friction, not by server state, device availability, or the proven 2.42K route.
  - `SalemXForegroundSSESmokeDebugBridge` forwards the local-only sender invocation to the existing DEBUG sender helper without changing production call behavior.
  - Receiver identifiers remain local-only sensitive inputs and must not be recorded, logged, documented, or committed.
  - The bridge does not store identifiers, expose tokens, weaken server auth, use dev routes, request media credentials, connect media, emit Matrix events, add PushKit/APNs/background behavior, or replace Element Call routing.
  - The 2.42M physical regression smoke is still pending and must use the authenticated non-dev foreground invite route with the dev route disabled.
- 2.42L hardens the supervised real foreground invite sender helper after the 2.42K pass at `00b7db4db914eed61bb45cc51fff7082d15da323`:
  - The DEBUG-only sender helper now treats a first authenticated real-invite `401` as a stale-token class and retries at most once after asking the active session token provider for a fresh value.
  - Retry diagnostics remain redacted booleans/enums: `sender_token_refresh_needed`, `sender_token_refresh_attempted`, `sender_token_refresh_succeeded`, `sender_invite_retry_requested`, and `sender_invite_retry_status`.
  - The helper still does not print, return, store, document, or log access token values, recipient identifiers, device identifiers, call handles, request payloads, or private URLs.
  - The real non-dev invite route remains authenticated and independent from `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED`.
  - The dev route must remain disabled outside controlled smoke; disabled public dev routes return `404`.
  - Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used for current physical Debug builds.
  - Invite receipt still does not request media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, add background incoming behavior, or replace Element Call routing.
- 2.42K validated the supervised foreground real invite path at `00b7db4db914eed61bb45cc51fff7082d15da323`:
  - The sender used the DEBUG-only active-session helper against the authenticated non-dev route `/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite`.
  - The dev route stayed disabled; no `dev/invite`, no `dev/inject-active`, and no `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1` were used.
  - Server diagnostics confirmed one active target subscriber, delivery, enqueue, yield, and `sse_event_type=foreground.call.invite`.
  - Receiver diagnostics confirmed `sse_connected=true`, `stream_failure=none`, `raw_event_received=true`, `invite_parse_succeeded=true`, `pipeline_delivered=true`, `invite_received=true`, `invite_valid=true`, and `incoming_requested=true`.
  - No media credential request, media connect, Matrix event emission, Element Call route replacement, PushKit/APNs behavior, background incoming behavior, signing/project setting change, or raw runtime log documentation was added.
- 2.42J hardens supervised foreground SSE smoke guardrails after the 2.42I pass at `a4d427f5b07e662695ce108530bbafc9bfdd9399`:
  - Server tests explicitly cover disabled dev routes returning not found, enabled authenticated dev-invite requiring an active session, local-only self-injection fail-closed behavior, stream unauthenticated rejection, and redacted SSE/log diagnostics.
  - The server stream and dev routes continue to emit only safe stage names, booleans, counts, hashes, and enums. `foreground.keepalive` remains a comment-only SSE heartbeat.
  - The iOS DEBUG smoke helper remains DEBUG-only and does not print, return, store, document, or log active credential values.
  - Invite receipt still does not request media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, add background incoming behavior, or replace Element Call routing.
  - Timestamp validation coverage confirms current invites and small future skew are accepted, while expired invites and excessive future timestamps fail closed.
  - Physical Debug build documentation now records `DEVELOPMENT_TEAM=M639Y9MFR2` as the current local signing override and explicitly says not to use the old `83LGSC2QPV` team for current physical Debug builds.
  - The `Package.resolved` hook warning was checked lightly; the root file exists, no package resolution change was needed, and no package file was changed.
  - No signing/project setting, bundle, entitlement, `Info.plist`, `app.yml`, `project.yml`, production URL, credential, media behavior, broad rollout, production/public rollout, or global activation change was added.
- 2.42I-S completed the supervised physical iPhone foreground SSE smoke:
  - A Debug physical iPhone build was installed using local command-line signing overrides only; no project signing files were intentionally changed.
  - The active-session LLDB helper emitted `helper_invoked=true`, found the active session credential internally, and reached `foreground_sse_start_requested=true` without printing, returning, writing, or documenting credential values.
  - The call-service stream emitted `stream_auth_ok`, `stream_registered`, and `ready_sent` with `active_subscriber_count=1`.
  - The iOS stream reached `sse_connected=true` and `stream_failure=none`.
  - The local-only self-injection route returned `active_subscriber_count=1`, `delivered=true`, and `dropped=false`.
  - Server diagnostics confirmed `invite_enqueued=true`, `invite_yielded=true`, and `sse_event_type=foreground.call.invite`.
  - iOS diagnostics confirmed `raw_event_received=true`, `sse_event_type=foreground.call.invite`, `invite_parse_attempted=true`, `invite_parse_succeeded=true`, `pipeline_delivered=true`, `invite_received=true`, `invite_valid=true`, and `incoming_requested=true`.
  - The invite validator now allows a small future-skew window for server/device clock drift while still rejecting larger future timestamps.
  - After the smoke, `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=0` was restored and the public dev invite route returned `404`.
  - Raw runtime logs remain intentionally omitted.
  - Invite receipt still does not request media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, add background incoming behavior, or replace Element Call routing.
  - No signing/project setting, bundle, entitlement, `Info.plist`, `app.yml`, production URL, credential, media behavior, broad rollout, production/public rollout, or global activation change was added.
- 2.42I prepared and hardened the supervised foreground SSE smoke:
  - The physical iPhone active-session helper reached `sse_connected=true`, proving `foreground.ready` parsing and active app session request construction without copying the app credential into LLDB.
  - A local-only call-service self-injection route was added for the remaining invite delivery proof: `POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/inject-active`.
  - The self-injection route is registered only when `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1`, accepts only localhost requests, requires exactly one active foreground SSE subscriber, and returns only redacted active-subscriber count plus delivered/dropped booleans.
  - `docs/direct-call/SUPERVISED_FOREGROUND_SSE_SMOKE.md` defines local/staging server enablement, rollback, iOS Debug configuration, safe placeholder invite shape, redacted diagnostics, pass/fail criteria, and raw-log handling.
  - The server dev invite route remains disabled by default and must be enabled only with `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1` during supervision.
  - The iOS DEBUG owner remains disabled by default and requires explicit construction with injected request/transport/handler dependencies.
  - The expected smoke checks `sse_configured`, `sse_started`, `sse_connected`, `invite_received`, `invite_valid`, `incoming_requested`, `fallback_deduped`, `transport_stopped`, and safe `stream_failure`.
  - Invite receipt must still not request media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, add background incoming behavior, or replace Element Call routing.
  - No signing/project setting, bundle, entitlement, `Info.plist`, `app.yml`, production URL, credential, media behavior, broad rollout, production/public rollout, or global activation change was added.
- 2.42H adds a DEBUG-only foreground SSE runtime owner:
  - `DebugForegroundCallSignalingSSERuntimeOwner` can start/stop an injected foreground signaling transport when explicitly enabled and an authenticated session is available.
  - The owner is DEBUG-only, disabled by default, and not wired into production app lifecycle.
  - It does not construct URLs, auth headers, credentials, or production configuration.
  - Redacted diagnostics cover `sse_configured`, `sse_started`, `sse_connected`, `invite_received`, `invite_valid`, `incoming_requested`, `fallback_deduped`, and `transport_stopped`.
  - Valid invites feed the existing `ForegroundCallInviteHandler`; malformed, stale, terminal, duplicate, unsupported, or unverifiable invites still fail closed.
  - Timeline/room-list fallback can be de-duplicated after an SSE-delivered invite by safe local call handle.
  - Invite receipt does not request media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, add background incoming behavior, or replace Element Call routing.
  - Implementation details are documented in `docs/direct-call/DEBUG_FOREGROUND_SSE_RUNTIME_OWNER.md`.
- 2.42G documents supervised foreground signaling smoke wiring:
  - The iOS side already has `ForegroundCallSignalingSSETransport`, `URLSessionForegroundCallSignalingSSEStream`, injected `URLRequest`, `ForegroundCallSignalingTransportPipeline`, and `ForegroundCallInviteHandler`.
  - The transport remains disabled by default and does not construct server URLs or auth headers.
  - No runtime app owner was added because the app still needs a safe foreground-session lifecycle owner, authenticated request construction, reconnect/backoff, fallback de-duplication, and physical-path diagnostics.
  - Required smoke diagnostics are safe booleans only: `sse_configured`, `sse_connected`, `invite_received`, `invite_valid`, and `incoming_requested`.
  - Invite receipt must still not request media credentials, connect media, emit Matrix events, or bypass foreground authority.
  - No PushKit/APNs runtime, background incoming behavior, signing/project setting change, Element Call route replacement, hardcoded production URL, credential value, media behavior change, broad rollout, or production/public rollout was added.
  - Smoke wiring is documented in `docs/direct-call/FOREGROUND_SIGNALING_SMOKE_WIRING.md`.
- 2.42F adds a supervised, dev-only foreground invite source to the call-service:
  - The route is `POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite`.
  - It is registered only when `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1` is set; default deployments do not expose it.
  - The route authenticates the active session, validates the same opaque foreground invite payload used by the SSE stream, and publishes through the existing internal `ForegroundCallSignalingService` fanout.
  - To avoid raw routing values in request bodies, it targets only the authenticated foreground subscriber for the same active session/device.
  - It does not issue media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, add background incoming behavior, replace Element Call routing, or change iOS signing/project settings.
  - Server notes are documented in `server/salemx-call-service/docs/FOREGROUND_SIGNALING_DEV_INVITE.md`.
- 2.42E added an iOS foreground SSE transport client boundary:
  - The transport is disabled by default and requires explicit construction/configuration.
  - The URLSession stream wrapper requires an injected request; no production URL or credential value is hardcoded.
  - Valid `foreground.call.invite` SSE events feed the existing foreground signaling pipeline, while ready, malformed, stale, unsupported, and duplicate events fail closed or are ignored.
  - Invite receipt does not request media credentials, connect media, emit Matrix events, or bypass foreground authority.
  - No PushKit/APNs runtime, background incoming behavior, signing/project setting change, Element Call route replacement, media behavior change, broad rollout, or production/public rollout was added.
- 2.42D added the call-service foreground signaling endpoint:
  - The server exposes `GET /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream` for authenticated foreground SSE subscribers.
  - It emits a `foreground.ready` event and validated opaque `foreground.call.invite` events from an internal in-memory fanout boundary.
  - Expired invites are dropped before fanout with redacted diagnostics.
  - The stream does not issue media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, or add background incoming behavior.
- 2.42C inspected the SalemX call-service and app signaling boundary for a server-backed foreground invite transport:
  - The call-service currently exposes redacted health/readiness, native audio eligibility, server-issued media credential allocation, and local fake capability discovery only.
  - No foreground call invite subscription, fanout, acknowledgement, stale invalidation, reconnect/resume, or app runtime endpoint configuration exists yet.
  - Because no endpoint exists, 2.42C stays docs-only and does not add a production WebSocket/SSE/long-poll transport or hardcoded server URL.
  - The 2.42B disabled/default transport and in-memory test transport remain the only executable foreground signaling transport proof.
  - The required server endpoint contract, opaque invite payload, acknowledgement model, redacted diagnostics, and blockers are documented in `docs/direct-call/SERVER_BACKED_FOREGROUND_SIGNALING.md`.
  - No PushKit/APNs runtime, background incoming behavior, signing/project setting change, Element Call route replacement, media behavior change, broad rollout, or production/public rollout was added.
- 2.42B adds a foreground signaling transport prototype:
  - `ForegroundCallSignalingTransport`, `DisabledForegroundCallSignalingTransport`, `InMemoryForegroundCallSignalingTransport`, `ForegroundCallSignalingTransportEvent`, `ForegroundCallSignalingTransportDiagnostics`, and `ForegroundCallSignalingTransportPipeline` define a mockable transport layer for the 2.42A invite contract.
  - The disabled/default transport emits no invites. The in-memory transport can deliver safe invite signals immediately in tests.
  - The transport pipeline feeds invite events into `ForegroundCallInviteHandler`, preserving duplicate, stale, terminal, malformed, active-session, and reporting-failure guards.
  - Invite receipt still does not request media credentials, connect media, emit Matrix call events, or bypass the foreground acceptance gate.
  - Server requirements for a future authenticated foreground transport are documented in `docs/direct-call/FOREGROUND_SIGNALING_TRANSPORT_PROTOTYPE.md`.
  - No production WebSocket/SSE transport, PushKit/APNs runtime, background incoming behavior, signing/project setting change, Element Call route replacement, media behavior change, broad rollout, or production/public rollout was added.
- 2.42A adds an inert foreground call signaling channel contract and client boundary:
  - `ForegroundCallInviteSignal`, `ForegroundCallSignalingClientProtocol`, `DisabledForegroundCallSignalingClient`, `ForegroundCallInviteValidator`, and `ForegroundCallInviteHandler` define the future foreground invite path without adding a production transport.
  - A validated foreground invite can request the existing foreground incoming/CallKit reporting abstraction through safe local identity data.
  - Duplicate, stale, terminal, malformed, unsupported, active-session, and reporting-failure cases fail closed with redacted diagnostics.
  - Invite receipt does not request media credentials, connect media, emit Matrix events, or bypass the foreground acceptance gate.
  - Answer still requires server-issued media credential authority before any future media connection is allowed.
  - Server requirements for a future authenticated foreground signaling channel are documented in `docs/direct-call/FOREGROUND_CALL_SIGNALING_CHANNEL.md`.
  - No PushKit/APNs runtime, background incoming behavior, signing/project setting change, Element Call route replacement, media behavior change, broad rollout, or production/public rollout was added.
- 2.41G-A6 investigated faster foreground call invite sources after current-room fast-path diagnostics showed repeated-call events arriving with `over10s` delay:
  - The open-room flow already subscribes the room and live timeline before the foreground observer attaches.
  - The current-room observer is useful but still depends on materialized timeline updates; physical diagnostics showed the event can reach that source too late.
  - Room-list fallback is not earlier because it depends on room-summary/latest-event updates.
  - Notification manager surfaces are not a foreground Matrix call invite stream.
  - Existing Element Call PushKit/VoIP handling is out of scope for this foreground-only phase.
  - The native direct-call SDK timeline listener pattern is for SalemX native direct-call custom envelopes; using a similar source for Element Call requires a separate Element Call invite observer/contract.
  - No safe existing app-side source was found that observes Element Call call invite/member events earlier than Matrix sync/timeline or room-summary materialization while keeping PushKit/APNs/background out of scope.
  - This phase is docs-only: no runtime code, PushKit/APNs/background behavior, signing/project change, Element Call route change, media behavior change, broad rollout, or production/public rollout was added.
- 2.41G-A adds repeat-call audio lifecycle cleanup for the existing Embedded Element Call audio route:
  - Foreground audio still uses the existing Element Call route with audio start mode.
  - On call-screen stop or local termination, `CallScreenViewModel` now performs an idempotent embedded web content reset that stops audio/video element tracks, detaches stream-backed media, clears media sources, and stops the page load.
  - Existing widget hangup, Matrix termination request, and Element Call service teardown paths remain in place.
  - Unit coverage verifies End and stop reset embedded web content once, keep widget hangup/termination behavior, and tear down the Element Call session.
  - Physical two-iPhone repeat-call smoke is still required to confirm whether the stutter/hesitation is fixed or only narrowed.
  - No PushKit/APNs/background incoming, signing/project changes, Element Call route replacement, private native video implementation, credential-authority bypass, broad rollout, or production/public rollout was added.
- 2.41F adds redacted Element Call media diagnostics for the existing embedded call route:
  - Native-shell diagnostics now record safe stage booleans/enums for URL generation, start mode, direct-room chrome, content loaded, media capture permission kind, and widget media state.
  - A narrow injected web view diagnostic reports only schema, safe stage, elapsed bucket, video element counts, visible/playing/stream-backed/muted counts, and a derived remote-renderer-candidate boolean.
  - The diagnostics intentionally omit raw room/user/device/event identifiers, URLs, credentials, media stream IDs, participant IDs, track IDs, Matrix event bodies, and raw widget messages.
  - This can identify whether each device has only a self-view renderer or multiple video renderer candidates, but it cannot yet prove MatrixRTC same-session, publish, subscribe, grant, or participant-to-renderer mapping.
  - No PushKit/APNs/background incoming, signing/project changes, Element Call route replacement, private native direct-call video implementation, broad rollout, or production/public rollout was added.
- 2.41E inspected the Element Call / embedded call video path after the two-physical-iPhone self-view-only smoke:
  - The normal room video button flows through `displayCall(startMode: .video)`, `presentCallScreen(startMode: .video)`, `ElementCallConfiguration.roomCall`, `CallScreenViewModel`, `ElementCallWidgetDriver`, and the embedded Element Call web view.
  - Direct room video uses the SDK direct-message video call intent; direct room audio uses the separate voice intent.
  - The app-side embedded call URL hides app-replaced controls and screensharing for direct rooms, but no app-side audio-only video-disable parameter was found.
  - The embedded web view remains visible for direct video calls and grants media capture for the embedded call origin.
  - Remote video publication, subscription, and renderer attachment are owned by Element Call / MatrixRTC inside the web view, not by the native shell.
  - No narrow Swift runtime fix is safe without redacted Element Call / MatrixRTC runtime diagnostics. The next step is redacted media diagnostics on two physical iPhones.
  - No runtime code changed. PushKit/APNs/background incoming, signing/project changes, Element Call route replacement, private native direct-call video implementation, broad rollout, and production/public rollout remain blocked.
- 2.41D inspected the video path after the two-physical-iPhone smoke where local video appeared but remote participant video was not visible:
  - The standard room video button routes through `displayCall(startMode: .video)` and `presentCallScreen(startMode: .video)`, which opens the existing Element Call / embedded call route.
  - The private native direct-call path remains audio-only: the media protocol exposes audio APIs only, media state has audio phases only, the LiveKit direct-call client subscribes to remote audio only, and video intent is rejected before native media connection.
  - Native direct-call eligibility, activation, capability, and credential-authority surfaces are audio-scoped; non-audio intent is rejected before a native media credential request.
  - The observed self-view-only symptom is therefore most likely in the Element Call / MatrixRTC / embedded call video path, or in call-session matching, publish/subscribe, or remote renderer attachment, rather than in the proven native audio path.
  - No runtime code changed. Native direct-call video implementation, PushKit/APNs/background incoming, production/public rollout, broad internal rollout, Element Call replacement, signing/project changes, and global activation remain blocked.
- 2.41B hardens the foreground native incoming lifecycle after the one-device smoke:
  - Duplicate answered-call handling no longer creates a second media connection after the foreground authority path has already connected.
  - End is idempotent in the foreground incoming coordinator.
  - Local incoming state is cleared before async media teardown is awaited, reducing local cleanup delay risk.
  - Repeated foreground incoming calls reset local lifecycle state after End.
  - The repeating audio tick/click artifact is not yet proven fixed; the next physical smoke must verify whether it remains.
  - The peer-side cleanup delay is addressed locally but still needs physical smoke confirmation.
  - No PushKit runtime, APNs runtime, APNs/VoIP value registration, background incoming handling, signing/project setting change, Element Call route change, video, broad rollout, or production/public rollout is introduced.
- 2.41A-S completed: one-device foreground smoke passed with Simulator caller and physical iPhone callee. CallKit UI appeared, Answer worked, media connected, End cleared the call. Carry-forward issues: repeating audio tick/click artifact and peer-side end cleanup delay of approximately 10 seconds. Full two-physical-device smoke remains pending.
- 2.41A adds a foreground-only native incoming call E2E coordinator contract:
  - A foreground incoming ringing audio `DirectCallSession` can be validated and reported through the isolated CallKit UI adapter.
  - CallKit answer routes to `answerRequested`.
  - The foreground acceptance gate is required before media can be attempted.
  - Missing, denied, malformed, expired, and unverifiable authority decisions block media and fail closed.
  - Authorized authority allows only the injected media connector to run; media is not attempted before authorization.
  - End clears local incoming state and tears down started media through the injected connector.
  - Mute remains local/diagnostic-only.
  - Unit coverage verifies the foreground E2E coordinator path, redacted diagnostics, and absence of Element Call route action names.
  - No PushKit runtime, APNs runtime, APNs/VoIP value registration, background incoming handling, signing/project setting change, production UI, Element Call route change, LiveKit/MatrixRTC production path change, video, broad rollout, or production/public rollout is introduced.
- 2.40L adds a foreground-only acceptance gate after synthetic/local incoming CallKit answer routing:
  - Answer remains routed to `answerRequested`.
  - Media remains blocked until a mocked/test-safe foreground authority returns an authorized decision.
  - Missing, denied, malformed, expired, and unverifiable authority decisions fail closed.
  - Authorized decisions move only to `foregroundCredentialAuthorized`, a safe local state that does not connect media.
  - End clears local incoming/acceptance state, and mute remains local/diagnostic-only.
  - Unit coverage verifies direct gate behavior and isolated synthetic CallKit UI adapter callback-to-gate behavior.
  - No PushKit runtime, APNs runtime, APNs/VoIP value registration, background incoming handling, real server-issued media credential request, media connection, Matrix event emission, Element Call route change, LiveKit/MatrixRTC production path change, signing/project setting change, production UI, video, broad rollout, or production/public rollout is introduced.
- 2.40K adds a disabled local incoming-call state-machine action surface for synthetic CallKit answer/end/mute callbacks:
  - Answer routes to `answerRequested`, meaning the local incoming call is ready for the future server-issued media credential authority step.
  - End routes to local termination and clears the synthetic incoming state.
  - Mute remains local and diagnostic-only.
  - Unit coverage verifies direct coordinator routing and isolated synthetic CallKit UI adapter callback routing.
  - Diagnostics remain redacted, media credential request and media connection flags remain false, and Element Call route action names remain absent from proof diagnostics.
  - No PushKit runtime, APNs runtime, APNs/VoIP value registration, background incoming handling, server-issued media credential request, media connection, Matrix event emission, Element Call route change, LiveKit/MatrixRTC production path change, signing/project setting change, production UI, video, broad rollout, or production/public rollout is introduced.
- 2.40J-C closed: physical iPhone Debug build displayed the system CallKit incoming UI through the DEBUG-only Objective-C LLDB bridge. The proof remains synthetic/local-only; no PushKit/APNs/media/server credential/Element Call route/signing changes were added.
- Isolated synthetic CallKit UI proof adapter is added:
  - 2.40J-B adds `ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift`.
  - The adapter imports CallKit only inside the isolated proof boundary and accepts only safe local synthetic identity/display metadata from the disabled incoming-call contracts.
  - DEBUG-only local harness support can report one synthetic incoming call to the physical-device system call UI when explicitly invoked by a developer-only manual path.
  - Answer, end, and mute callbacks map only into disabled local callbacks and redacted diagnostics.
  - Unit coverage verifies safe display metadata rejection, injected reporter-only reporting, disabled answer/end/mute callback handling, unknown-handle fail-closed behavior, local state cleanup, and redacted diagnostics.
  - `docs/direct-call/SYNTHETIC_CALLKIT_UI_PROOF.md` records the physical-device proof boundary and manual proof steps.
  - No PushKit runtime, APNs runtime, push delivery, server fanout, media credential request, media connection, Element Call route change, native audio gate change, bundle/signing/entitlement/Info.plist/app.yml change, server change, video, or rollout expansion is introduced.
- Device-only synthetic CallKit proof surface is added:
  - 2.40J adds a disabled synthetic proof coordinator and safe display metadata contract for future native direct-audio CallKit work.
  - The synthetic path accepts only safe local incoming-call identity data from the disabled 2.40H contracts and maps report, answer, end, and mute actions into disabled local callbacks and redacted diagnostics.
  - Default behavior is fail-closed. Unit coverage verifies safe display metadata validation, disabled default blocking, safe local identity reporting, answer/end/mute local callbacks, unknown-handle blocking, local state cleanup, and redacted diagnostics.
  - `docs/direct-call/SYNTHETIC_CALLKIT_PROOF.md` records the device-only manual proof contract.
  - No PushKit runtime, APNs runtime, push credential registration, push delivery, server push, media credential request, media connection, background incoming behavior, missed-call UX, Element Call route change, native audio gate change, bundle/signing/project setting change, server change, video, or rollout expansion is introduced.
- Push and CallKit payload contract is documented:
  - 2.40I adds `docs/direct-call/PUSH_CALLKIT_PAYLOAD_CONTRACT.md`.
  - The contract defines future VoIP incoming native direct-audio invite payloads, optional normal APNs notification separation, server acknowledgement/invalidation payloads, local CallKit display metadata, terminal/stale handling, client validation, server requirements, redaction, failure matrix, test plan, and future phases.
  - Payloads remain minimal and opaque. They must not include raw identifiers, push credential values, media credentials, media-session names, Matrix event bodies, full request/response bodies, or credentialed URLs.
  - The push payload is never final authority. The server-issued media credential endpoint remains final authority after user answer.
  - No real CallKit, PushKit, APNs, push credential registration, system incoming UI, background incoming behavior, missed-call UX, media connection, Element Call route change, native audio gate change, bundle/signing/project setting change, server change, video, or rollout expansion is introduced.
- Disabled native incoming lifecycle contracts are added:
  - 2.40H adds inert Swift models, protocols, a fail-closed disabled lifecycle service, local test doubles, and redacted diagnostics for future native direct-audio incoming-call work.
  - The contract surface includes safe local incoming call handles, lifecycle states, fail-closed reasons, validation context, redacted diagnostics, state store, call reporting adapter, incoming push registry, timeout scheduler, and diagnostics recorder protocols.
  - Default behavior is no-op/fail-closed. Unit coverage verifies malformed, stale, duplicate, invalid room/trust/eligibility/session/dependency, and server-issued media credential rejection paths.
  - No real CallKit, PushKit, APNs, token registration, system incoming UI, background incoming behavior, missed-call UX, media connection, Element Call route change, native audio gate change, bundle/signing/project setting change, server change, video, or rollout expansion is introduced.
  - `docs/direct-call/NATIVE_INCOMING_CONTRACTS.md` records the disabled contract boundary.
- Native audio CallKit / PushKit / APNs planning is documented:
  - 2.40F physical-device signing readiness is complete with signed development entitlements for the main app and extension targets.
  - The development App Group is `group.kz.salemx.msg.dev`, and the main app development entitlement includes APNs environment support.
  - `docs/direct-call/CALLKIT_PUSHKIT_APNS_DESIGN.md` records the design-only baseline, Apple compliance assumptions, proposed incoming and outgoing call flows, token/device model, server requirements, future client components, risk register, redaction contract, fail-closed matrix, phased implementation plan, non-goals, and acceptance criteria.
  - Runtime CallKit, PushKit, APNs, background incoming, missed-call UX, video, Element Call replacement, native audio gating changes, signing changes, broad rollout, and production/public rollout remain blocked.
- SalemX call-service now pre-creates allocated LiveKit rooms through server-side RoomService `CreateRoom` before issuing participant tokens. Participant tokens remain scoped to room join/publish/subscribe, and room provision failures return a safe fail-closed error without issuing a token.
- Narrow non-engineering internal pilot preparation is documented, but execution is not yet approved:
  - Scope is limited to a future supervised 1-2 participant internal window, named accounts/devices only, staging call-service and staging LiveKit only, private native audio card only, foreground/open encrypted direct 1:1 rooms only, verified/trusted peers only, one active native 1:1 call at a time, and Element Call fallback visible/unchanged.
  - Participant expectations explicitly state that this is not production, calls work only while the encrypted direct chat is open, there is no background incoming call behavior, no CallKit incoming screen, no missed-call UX, and Element Call remains the fallback.
  - Required owners, preflight, app gates, backend gates, first-session matrix, stop criteria, rollback, and redacted report template are recorded.
  - The main non-engineering preparation path keeps `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset and uses the server-backed internal pilot activation path with token endpoint final authority.
  - Broad internal rollout, production/public rollout, CallKit, push/background incoming, missed-call UX, video, session restoration, and global activation remain blocked.
- Narrow non-engineering pilot execution remains blocked after 2.39C review:
  - The 2.39B runbook is sufficient for preparation, but actual owner labels, participant/device labels, explicit opt-in, fresh preflight, rollback presence, kill-switch verification, and redaction reviewer presence were not filled.
  - 2.39D adds a remediation checklist with owner and participant/device tables, opt-in statement, fresh preflight template, execution approval checklist, stop criteria, rollback, and re-review decision rule.
  - No pilot window may run until every checklist item is complete and a separate re-review approves execution.
- The 2.39F checklist completion attempt remains incomplete:
  - Required owner labels, participant/device labels, explicit opt-in, fresh green preflight, rollback operator presence, kill-switch verification, and redaction/report reviewer presence are still missing.
  - Execution remains blocked; no pilot may run.
- The 2.39G checklist completion follow-up is complete:
  - Owner labels, participant/device labels, explicit opt-in, fresh green preflight, rollback operator presence, kill-switch verification, and redaction/report reviewer presence are recorded with label-only data.
  - This permits proceeding to execution approval re-review only. It does not approve or execute the pilot.
  - Broad internal rollout, production/public rollout, CallKit, push/background incoming, missed-call UX, video, session restoration, Element Call replacement, and global activation remain blocked.
- The 2.39I supervised narrow non-engineering internal pilot window passed:
  - Exactly one supervised window ran with Participant A/B and Device A1/B1 labels only.
  - The main path used the server-backed internal pilot activation path with private dogfood and legacy fake/dry-run gates unset.
  - Preflight passed with readiness `ready=true`, `reason=ok`, Redis connected, storage key configured, LiveKit room provisioning configured, eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, no active session, Element Call fallback visible, and `internalPilotActivationDecision=activationAllowed`.
  - A -> B, B -> A, one repeated call, outgoing cancel, and timeout rows passed.
  - Timeout produced `outgoingTimeout` / `incomingTimeout`, then A/B returned idle/no active session with media failure `none`.
  - App-side kill-switch check passed: disabling internal rollout made dry-run report `wouldStart=false`, `activationSource=internalPilot`, `internalPilotActivationDecision=disabled`, and `internalPilotActivationReason=rolloutDisabled`, with no active session or media/LiveKit side effects.
  - Element Call fallback remained visible/unchanged, no stop criteria hit, no redaction issue was observed, and no app/backend code changed.
  - No additional non-engineering pilot window is approved by this result; continue only to post-window review.
- The 2.39R supervised non-engineering internal pilot window 3 passed:
  - Exactly one additional supervised window ran after the 2.39Q approval, with the same Participant A/B and Device A1/B1 labels only.
  - The main path used the server-backed internal pilot activation path with private dogfood and legacy fake/dry-run gates unset.
  - Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, no active session, Element Call fallback visible, `activationSource=internalPilot`, and `internalPilotActivationDecision=activationAllowed`.
  - A -> B, B -> A, one repeated A -> B call, outgoing cancel, timeout, app-side kill-switch, and Element Call fallback rows passed.
  - Active call rows reported `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, `liveKitRoomPrecreateAttempted=true`, LiveKit connect attempted, `productionLiveKitFailureReason=none`, and `productionMediaFailureReason=none`.
  - Timeout produced `outgoingTimeout` / `incomingTimeout`, cancel produced terminal `cancelled`, and A/B returned idle/no active session.
  - App-side kill-switch check blocked safely after internal rollout was unset and A/B relaunched, with no active session, token request, media connect, or LiveKit connect.
  - Element Call fallback remained visible/unchanged, no stop criteria hit, no redaction issue was observed, and no app/backend code changed.
  - No additional non-engineering pilot window is approved by this result; continue only to post-window review.
- Post-pilot hardening plan is recorded:
  - 2.39S paused additional non-engineering pilot windows after the clean 2.39R window.
  - The foreground-only supervised path is proven for approved named participants/devices under staging constraints, but further same-cap windows are not the next highest-value work.
  - Foreground limitation UX must clearly explain that native audio works only while the encrypted direct chat is open, with no background incoming, no CallKit incoming screen, and no missed-call UX yet. Element Call remains fallback.
  - In-card state polish must cover chat not open/listener unavailable, trust not ready, participant not eligible, service unavailable, timed out, cancelled, safely failed, retry, and dismiss states without raw backend/token/LiveKit details.
  - Mandatory monitoring remains redacted only: readiness booleans, activation source/decision/reason, token status/errcode/reason/issued, LiveKit pre-create and failure enum, media failure enum, session state/active boolean, terminal reason, and cleanup/disconnect booleans.
  - Operational monitoring automation should reduce runner-only dependency and alert on `tokenBackendRejected`, `liveKitNetworkFailed`, split-brain, stale active session, readiness not ready, and `tokenIssued=false` for an otherwise eligible call.
  - Additional non-engineering windows, participant/device expansion, broad internal rollout, production/public rollout, unsupervised dogfood, Element Call replacement, CallKit/push implementation, video, global activation, and `directOneToOneCallsEnabled` as the native audio gate remain blocked.
- Staging iOS private native audio smoke passed after LiveKit room pre-create:
  - A/B reached `productionSessionState=activeAudio`.
  - A/B had `productionEncryptionState=ready`.
  - A/B had media connect and LiveKit client connect attempted.
  - A/B reported `productionMediaFailureReason=none`.
  - Hangup returned both sides to idle with media disconnect and cleanup attempted.
  - The previous `liveKitURLUnreachable` / service-not-found-like blocker is resolved by server-side LiveKit room pre-create.
  - No iOS app code, Element Call route, CallKit, push, video, or global production activation changed.
- Controlled engineering dogfood is conditionally allowed on the staging path:
  - Named engineering operators only.
  - DEBUG/integration builds only.
  - Private native call card only.
  - Foreground/open-room encrypted direct 1:1 sessions only.
  - Verified/trusted peers only.
  - Existing Element Call toolbar path remains unchanged and available as fallback.
  - Broad internal dogfood, public rollout, CallKit, push, video, and global production activation remain out of scope.
- Controlled engineering dogfood matrix passed on the staging path:
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, and LiveKit room provisioning true.
  - A/B trust passed with `ownSessionVerified=true`, `crossSigningReady=true`, `peerTrustReady=true`, and `peerTrustReadiness=peerTrustReady`.
  - Happy path A -> B and reverse B -> A reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
  - Repeated calls, decline incoming, cancel outgoing, timeout, backend-off fail-closed, backend recovery, relaunch during active, relaunch during ringing, and listener-not-armed cases passed.
  - Backend-off failed closed with `tokenHTTPUnavailable`, no LiveKit client connect, and cleanup/disconnect attempted.
  - LiveKit-off fail-closed was not run because shared staging LiveKit should not be stopped during this dogfood session.
  - Final A/B status had no active session and no media failure.
  - Element Call route remained untouched and no code changed.
- Product-card-only staging smoke passed under the explicit private dogfood gate:
  - Without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation remained blocked with `appRolloutDisabled`.
  - The no-gate run produced no Matrix send, no token/media path, and no LiveKit client connect.
  - With `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation was enabled with dependencies ready, peer trust ready, and key wrapper available.
  - The legacy `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name was explicitly unset and was not used.
  - A started from the private product card, B reached incoming ringing, B accepted from the private product card, A/B reached `productionSessionState=activeAudio`, hangup returned A/B to `productionSessionState=idle`, and `productionMediaFailureReason=none`.
  - Encryption was ready, media connect and LiveKit client connect were attempted, and cleanup/disconnect ran after hangup.
  - Diagnostic runner use was limited to launch, status, activation, and trust polling; Start, Accept, and Hang up were manual private-card actions.
  - Element Call route remained untouched, with no CallKit, push, video, or global production activation.
  - Runtime issue fixed in `07256bf0a`: the private product card now prepares/arms the receiver listener from card status only when private dogfood activation is already enabled.
  - Listener preparation remains side-effect-limited: it does not start outgoing calls, request tokens, send Matrix events, or connect media.
- Controlled engineering dogfood pilot checkpoint is recorded:
  - Pilot is allowed only for named engineering operators on the staging path.
  - Required scope remains DEBUG/integration builds, foreground/open encrypted direct 1:1 rooms, verified/trusted peers, private native audio card, staging call-service, and staging LiveKit.
  - Required gates remain `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`, and the staging token base URL, with the diagnostic command gates for the DEBUG/integration harness.
  - The legacy fake/dry-run gate must remain unset for staging product-card-only proof and pilot sessions.
  - Required backend preflight includes `ready=true`, `reason=ok`, Redis allocation/rate-limit connectivity, storage key configured, LiveKit room provisioning configured, and Synapse validation smoke accepted or passing.
  - Required client preflight includes A/B trust ready, encrypted 1:1 DM open on both clients, listener/card available, and no stale active session.
  - Reports must stay pass/fail and redacted, limited to readiness/trust booleans, `productionSessionState`, `productionMediaFailureReason`, terminal reason enum, and cleanup/disconnect booleans.
  - Element Call remains the fallback path and must be smoked as unchanged during pilot sessions.
- Repeated-call split-brain regression runtime proof passed after the 2.27D post-answer failure fix:
  - Commit `38fa26586` made callee post-answer media/token setup failure emit a safe terminal signal to the caller before local cleanup.
  - Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, LiveKit room provisioning true, and A/B trust ready.
  - Required private dogfood gates were used, and the legacy fake/dry-run gate was unset.
  - Two normal repeated A -> B calls reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
  - A forced callee post-answer failure was simulated safely by launching B with an unavailable local token backend; B failed closed with `tokenHTTPUnavailable`.
  - A received the terminal path and did not remain `activeAudio`; A/B ended idle with no active session.
  - After restoring B to the normal staging URL, a recovery call reached A/B `activeAudio`, then hangup returned A/B to idle with cleanup/disconnect attempted and media failure `none`.
  - Element Call route remained untouched and no code changes were needed during the runtime proof.
- Controlled engineering dogfood pilot matrix rerun passed after the split-brain fix:
  - Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, LiveKit room provisioning true, and A/B trust ready.
  - Required private dogfood gates were used, and the legacy fake/dry-run gate was unset.
  - Happy path A -> B, reverse B -> A, and two repeated A -> B calls reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
  - The second repeated call had no stale session and no split-brain.
  - Decline, cancel, and timeout cleared A/B to idle with terminal `cancelled`, `outgoingTimeout`, or `incomingTimeout` as expected.
  - Backend-off immediate accept with the local staging call-service down failed closed with `connectingFailed`, `tokenHTTPUnavailable`, and no LiveKit client connect.
  - Backend recovery reached A/B `activeAudio`, then returned both sides to idle.
  - Relaunch during active audio and ringing restored no stale active session, no stale ringing session, and no media path.
  - Listener/open-room unavailable behavior remained user-safe with no active session and no unexpected media/token path.
  - LiveKit-off was not run because the staging LiveKit instance is shared.
  - Runner commands were used for matrix control/status; this is a controlled engineering dogfood matrix result, not a claim that every matrix case was manually product-card-only.
  - Final A/B status was idle/no active session with media failure `none`; Element Call route remained untouched and no code/docs changed during the runtime proof.
- Controlled dogfood operations checklist is recorded:
  - Every pilot window now requires a named operator, named participants, explicit staging call-service ownership, shared LiveKit ownership/skip confirmation, planned start/stop time, Element Call fallback confirmation, and no broad rollout scope.
  - The runbook documents local staging call-service start/stop, readiness checks, Redis readiness booleans, A/B gate checks, trust readiness, allowed redacted status fields, forbidden outputs, stop criteria, rollback, post-session report format, and security cleanup.
  - Security cleanup includes removing temporary SSH keys, removing disposable `/tmp/salemx-*.json` reports, rotating any password shared during diagnostics, and verifying ignored staging env files remain untracked and mode `600`.
  - The distinction remains explicit: 2.26E proved product-card-only happy path, while 2.27F is runner-assisted controlled matrix coverage.
- Operator-owned engineering expansion session 1 is recorded:
  - Session used redacted Operator A/B and Device A1/B1 labels only.
  - Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, and baseline A/B idle/no active session.
  - Required product UI, eligibility status, private dogfood, production start, and staging token base URL gates were set, and the legacy fake/dry-run gate was unset.
  - Runner/status-assisted happy path A -> B, reverse B -> A, repeated A -> B calls x2, decline, cancel, timeout, relaunch during ringing, listener/open-room unavailable, and post-listener recovery cases passed.
  - Timeout reported A `outgoingTimeout` and B `incomingTimeout`.
  - Backend-off recovery was not run because the local staging call-service stayed up for the session. LiveKit-off was not run because shared staging LiveKit requires owner approval before disruption.
  - Final A/B status was idle/no active session with media failure `none`, cleanup/disconnect attempted on both sides, no rollback used, no stop criteria triggered, and no redaction issue observed.
  - Element Call fallback stayed visible/unchanged, and no app/backend code changed during the runtime proof.
- Native audio internal pilot activation provider skeleton is added:
  - The app now has a native-audio-specific activation model with `disabled`, `unavailable`, `eligibleForStatusOnly`, and `activationAllowed` states.
  - Safe unavailable reasons are limited to `rolloutDisabled`, `capabilityMissing`, `accountNotEligible`, `peerNotEligible`, `roomNotEligible`, `trustNotReady`, `serviceUnavailable`, `unsupportedClient`, `dependenciesUnavailable`, and `unknown`.
  - The default provider returns disabled/fail-closed.
  - The status-only provider can combine future rollout/capability/eligibility/room/trust/dependency inputs but never returns `activationAllowed`.
  - Backend eligible alone, product UI alone, and eligibility status alone still do not activate native audio.
  - `directOneToOneCallsEnabled` remains unrelated to native audio activation.
  - Non-engineering internal dogfood is still not enabled.
- Native audio internal pilot activation no-activation runtime proof passed:
  - Session timestamp: 2026-05-25 00:26 +05.
  - Call-service readiness was `200`, `ready=true`, `reason=ok`, with Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
  - With product UI and eligibility status enabled but private dogfood unset, activation stayed blocked. With the encrypted direct 1:1 room open, the reason was `appRolloutDisabled`.
  - With production start enabled and private dogfood still unset, Start stayed blocked with `appRolloutDisabled`.
  - The no-private-dogfood runs had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
  - `directOneToOneCallsEnabled` separation was not toggled at runtime because no safe runner hook exists without changing Element Call settings; the 2.36C targeted tests cover the separation, and Element Call route behavior was not touched during the proof.
  - With private dogfood restored, A -> B reached `productionSessionState=activeAudio` with media failure `none`, media connect attempted, and LiveKit client connect attempted.
  - Hangup returned A/B to `productionSessionState=idle` with no active session, cleanup/disconnect attempted, and media failure `none`.
  - The legacy fake/dry-run gate remained unset, no code changed, no redaction issue was observed, and Element Call remained untouched.
- Server-backed internal pilot activation provider no-activation runtime proof passed:
  - Session timestamp: 2026-05-25 01:42 +05.
  - Call-service readiness was `200`, `ready=true`, `reason=ok`, with Redis allocation/rate-limit connected and storage key configured.
  - With product UI and eligibility status enabled, but private dogfood unset, activation stayed blocked with `appRolloutDisabled` once the encrypted direct 1:1 room was open.
  - With product UI, eligibility status, and production start enabled, but private dogfood still unset, Start stayed blocked with `appRolloutDisabled`.
  - The no-private-dogfood runs had no Matrix send, no token request, no media connect, no LiveKit client connect, no active session, and media failure `none`.
  - The internal pilot rollout source stayed default-off; backend eligibility/status did not enable runtime Start or Accept.
- Internal pilot activation dry-run status wiring is added:
  - `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ACTIVATION_DRY_RUN_ENABLED=1` is DEBUG/integration-only and default off.
  - The room-card provider boundary can now compute a redacted internal pilot activation dry-run status from product UI, internal rollout, backend eligibility, local encrypted direct 1:1 room state, trust readiness, dependency readiness, and active-session state.
  - The exposed dry-run contract is enum/boolean-only: `internalPilotActivationDryRunEnabled`, `internalPilotActivationDecision`, `internalPilotActivationReason`, and redacted readiness booleans.
  - Dry-run status does not enable Start or Accept; the private engineering path remains controlled by `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, and non-engineering internal dogfood remains blocked.
  - Tests cover dry-run gate-off behavior, rollout-off dry-run reporting, unit `activationAllowed` dry-run reporting without enabling Start, product UI/eligibility status insufficiency, side-effect boundaries, redaction, and Element Call separation.
  - With private dogfood restored, A/B trust and activation were ready, A -> B reached `productionSessionState=activeAudio`, and media failure stayed `none`.
  - Hangup returned A/B to `productionSessionState=idle` with no active session, cleanup/disconnect attempted, and media failure `none`.
  - Element Call route stayed untouched, no code changed, and no redaction issue was observed.
- Internal pilot activation dry-run runner observability is added:
  - The redacted `production-status` payload now carries `internalPilotActivationDryRunEnabled`, `internalPilotActivationDecision`, `internalPilotActivationReason`, `internalPilotRolloutEnabled`, `internalPilotEligibilityReady`, `internalPilotRoomReady`, `internalPilotTrustReady`, and `internalPilotDependenciesReady`.
  - The two-client diagnostic runner forwards `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ACTIVATION_DRY_RUN_ENABLED=1` and prints those fields as simple key/value output.
  - Runner-visible `internalPilotActivationDecision` values are safe enum strings: `disabled`, `unavailable`, `eligibleForStatusOnly`, `activationAllowed`, or `unknown`.
  - This is observability only. Start and Accept remain controlled by the existing private engineering dogfood path, and non-engineering internal dogfood remains blocked.
- Internal pilot activation dry-run runner observability runtime proof passed:
  - Session timestamp: 2026-05-25 16:22 +05.
  - Call-service readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
  - A/B trust diagnostics were ready with `ownSessionVerified=true`, `crossSigningReady=true`, `peerTrustReady=true`, and `peerTrustReadiness=peerTrustReady`.
  - With product UI, eligibility status, and internal pilot dry-run enabled but private dogfood unset, runner `production-status` exposed `internalPilotActivationDryRunEnabled=true`, `internalPilotActivationDecision=disabled`, and `internalPilotActivationReason=rolloutDisabled`.
  - The no-private-dogfood run had no active session, no Matrix send, no media connect, no LiveKit client connect, and media failure `none`.
  - With production start added and private dogfood still unset, Start remained blocked and no token/media/LiveKit path was attempted.
  - With private dogfood restored, A/B attached to the encrypted direct 1:1 room with listener started, A -> B reached `incomingRinging`, B accepted, A/B reached `activeAudio`, and media failure stayed `none`.
  - Hangup returned A/B to `idle` with no active session, cleanup/disconnect attempted, and terminal reason `hangup`.
  - Runner output stayed redacted and did not expose raw tokens, JWTs, secrets, raw room/user/device IDs, LiveKit room names, Redis credentials, Matrix event bodies, full request/response bodies, or backend URLs with credentials.
  - Element Call route stayed untouched, no code changed, and no redaction issue was observed.
- Internal pilot trigger dry-run observability alignment is complete:
  - Commit `f930f8f7a` aligned `production-trigger-dry-run` with the same redacted activation decision path used by `production-start-outgoing`.
  - Runner output now includes `activationSource`, `internalPilotActivationDecision`, and `internalPilotActivationReason`.
  - The runner forwards `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED` for DEBUG/integration proof runs.
  - Trigger dry-run remains side-effect-free: it does not send Matrix events, request participant tokens, allocate or pre-create LiveKit rooms, connect media, connect LiveKit, or create an active session.
  - Private dogfood compatibility was verified after the alignment: Start -> Accept reached `activeAudio`, Hangup returned A/B to `idle`, no active session remained, and media failure stayed `none`.
  - Element Call route stayed untouched, with no CallKit, push, video, production/public rollout, or global activation.
  - Validation passed: SwiftFormat, SwiftLint, targeted native-call tests 179/179, Release build with existing warnings only, runner `bash -n`, `git diff --check`, and changed-line forbidden scan.
- Engineering-only internal pilot activation soak plan is recorded:
  - The soak is specific to the server-backed internal pilot activation path, not the private dogfood path.
  - The main soak leaves `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset and uses `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED=1` with the existing DEBUG/integration diagnostics, product UI, eligibility status, internal-pilot dry-run, production start, and staging token base URL gates.
  - Scope remains engineering accounts only, named allowlisted A/B or named engineering pairs, staging call-service and staging LiveKit, private native audio card, foreground/open encrypted direct 1:1 rooms, verified/trusted peers, one active 1:1 call at a time, Element Call fallback visible/unchanged, and redacted reporting only.
  - The plan requires 3 clean sessions before the next readiness review.
  - Each session covers happy path, reverse path, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, post-listener recovery, token final-authority check when safe, and Element Call fallback.
  - Non-engineering internal dogfood, broad internal rollout, production/public rollout, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Engineering-only internal pilot activation soak session 1 passed:
  - The main soak used the server-backed internal pilot activation path with `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset and the legacy fake/dry-run gate unset.
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, baseline A/B idle/no active session, and Element Call fallback visible.
  - Runner trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
  - A -> B, B -> A, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, post-listener recovery, token final-authority check, and Element Call fallback rows passed with redacted output only.
  - Token final-authority used a temporary ineligible local fixture and blocked with safe reason `accountNotEligible` before media/LiveKit; normal allowlisted staging service was restored afterward.
  - Final A/B status was idle/no active session with media failure `none`; no rollback, stop criterion, runtime bug, or redaction issue was observed.
  - Soak progress: session 1 of 3 clean.
- Engineering-only internal pilot activation soak session 2 passed:
  - The main soak again used the server-backed internal pilot activation path with `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset and the legacy fake/dry-run gate unset.
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, baseline A/B idle/no active session, and Element Call fallback visible.
  - Runner trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
  - A -> B, B -> A, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, operator-assisted post-listener recovery, token final-authority check, and Element Call fallback rows passed with redacted output only.
  - Token final-authority used a temporary ineligible local fixture and blocked with safe reason `accountNotEligible` before media/LiveKit; normal allowlisted staging service was restored afterward.
  - Final A/B status was idle/no active session with media failure `none`; no rollback, stop criterion, runtime bug, or redaction issue was observed.
  - Soak progress: session 2 of 3 clean.
- Engineering-only internal pilot activation soak session 3 is paused after a repeated-call split-state blocker:
  - Preflight passed with backend readiness `ready=true`, `reason=ok`, Redis connected, LiveKit provisioning configured, eligibility/allowlist configured, private dogfood unset, legacy fake/dry-run unset, internal rollout active, A/B trust ready, A/B room attached, and dry-run `activationSource=internalPilot` with `internalPilotActivationDecision=activationAllowed`.
  - A -> B happy path, B -> A reverse path, and the first repeated call passed before the stop.
  - The repeated-call row then hit a split state after a timeout/retry sequence: A returned idle with `tokenBackendRejected` / `connectingFailed`, while B reported `activeAudio` with an active session.
  - Cleanup returned final A/B to idle/no active session; B cleanup/hangup succeeded, while A still reported media failure `tokenBackendRejected`.
  - Root cause: caller-side media/token setup failure after receiving a remote answer did not count as post-answer, so it failed locally without emitting a terminal event to the remote side. The callee-side protection already existed.
  - Commit `4ea9490ec` fixes this by tracking received remote answers and emitting one deduped hangup if caller media setup fails after the peer may have entered `activeAudio`.
  - `DirectCallEngineTests` now include caller `tokenBackendRejected` regression and manual-hangup race dedupe coverage; 37/37 passed.
  - Runtime proof after the fix passed for A -> B and repeated A -> B active-audio calls with clean hangup to A/B idle/no active session. The exact `tokenBackendRejected` split did not reproduce in runtime; the exact caller-failure-after-answer path is covered by the new unit regression.
  - Element Call route stayed untouched, with no CallKit, push, video, production/public rollout, broad internal rollout, or global activation.
  - 2.37E was not continued or recorded as passed. Soak progress remained 2 clean sessions of 3 until the 2.37F session 3 rerun passed.
- Engineering-only internal pilot activation soak session 3 rerun passed:
  - The rerun used the server-backed internal pilot activation path with `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset and the legacy fake/dry-run gate unset.
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, baseline A/B idle/no active session, and Element Call fallback visible.
  - Runner trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
  - A -> B, B -> A, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, post-listener recovery, and Element Call fallback rows passed with redacted output only.
  - Repeated-call split-state guard passed with no `tokenBackendRejected`, no `connectingFailed`, and no split state observed.
  - Token final-authority was not rerun in 2.37F because sessions 1 and 2 already covered the temporary ineligible fixture path.
  - Final A/B status was idle/no active session with media failure `none`; no rollback, stop criterion, runtime bug, or redaction issue was observed.
  - The 3-session engineering-only internal pilot activation soak is complete for the required runtime matrix.
- Controlled engineering dogfood pilot session 1 is recorded:
  - Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, LiveKit room provisioning true, and A/B trust ready.
  - Required private dogfood gates were used, and the legacy fake/dry-run gate was unset.
  - Manual private-card happy path A -> B, reverse B -> A, and repeated call reached `productionSessionState=activeAudio`, then returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
  - Manual private-card decline, cancel, timeout, and relaunch fail-closed cases returned A/B to a safe idle/no-active-session state.
  - Backend-off recovery was not repeated in this manual pilot because the local staging call-service stayed up for the session; backend-off remains covered by the 2.27F matrix.
  - LiveKit-off was not run because the staging LiveKit instance is shared.
  - Runner use was limited to launch, readiness/trust/status polling, and relaunch.
  - No stop criteria triggered, no rollback was needed, no runtime bug was observed, no redaction issue was found, and Element Call remained untouched.
- Controlled engineering dogfood pilot session 2 is recorded:
  - Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, LiveKit room provisioning true, and A/B trust ready.
  - Required private dogfood gates were used, and the legacy fake/dry-run gate was unset.
  - Manual private-card happy path A -> B and reverse B -> A reached `productionSessionState=activeAudio`, then returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
  - Two back-to-back repeated A -> B calls reached active audio and returned idle with no stale session and no split-brain.
  - Decline and cancel cleared A/B to idle with terminal `cancelled`; relaunch from an active session restored no active session and no media path.
  - Timeout was not repeated in session 2 because it is already covered by session 1 and the 2.27F matrix.
  - Backend-off recovery was not repeated in this manual pilot because the local staging call-service stayed up for the session; backend-off remains covered by the 2.27F matrix.
  - LiveKit-off was not run because the staging LiveKit instance is shared.
  - Runner use was limited to launch, readiness/trust/status polling, and relaunch.
  - No stop criteria triggered, no rollback was needed, no runtime bug was observed, no redaction issue was found, and Element Call remained untouched.
- Broader internal dogfood hardening plan is recorded:
  - Decision remains engineering-only; two passed controlled sessions do not approve broader internal dogfood or non-engineering users.
  - Smallest safe expansion remains more named engineering operators/devices on the same staging, foreground/open-room, verified-peer, private-card-only path.
  - Required hardening areas are activation/rollout model, UX/failure copy, incoming behavior and foreground limitation, monitoring/telemetry redaction, backend/staging operations, support/rollback, security review, and soak testing.
  - A future narrow non-engineering internal pilot requires a fail-closed internal rollout/allowlist model, non-engineering-safe UX, redacted telemetry, owned staging operations, Element Call fallback smoke, security review, and multi-operator/device soak.
- Native audio card UX/failure copy and monitoring status are hardened for the current engineering dogfood scope:
  - Private card failure states now map backend, LiveKit/audio, trust, invalid-room, listener/open-room, timeout, cancel, decline, ended, and unknown failures to user-safe copy.
  - A DEBUG-only redacted card status contract exposes only state/reason enums, listener/restoration enums, loading/action booleans, and no raw identifiers, tokens, URLs, Matrix event bodies, or LiveKit room names.
  - Product card rendering remains side-effect-free: rendering/status display does not send Matrix events, request tokens, connect media, or connect LiveKit.
  - This does not broaden activation; the private dogfood gate remains DEBUG/integration-only, and broad internal/non-engineering dogfood remains blocked.
- Redacted pilot monitoring contract is documented:
  - Allowed app/card, runner, backend readiness, backend error, and LiveKit/media fields are enumerated.
  - Raw Matrix access tokens, Synapse admin tokens, LiveKit API secrets, participant JWTs/tokens, media keys, raw room/user/peer/device IDs, Matrix event bodies, full request/response bodies, Redis credential URLs, and LiveKit room names remain forbidden.
  - Pilot reports remain pass/fail/not-run with readiness/trust booleans, session/terminal/media enums, cleanup/disconnect booleans, activation reason enum, and non-identifying timestamps/session numbers only.
- Native audio internal pilot eligibility contract skeleton is added:
  - `NativeDirectCallInternalPilotEligibility` models `eligible`, `unavailable(reason)`, `disabled`, `unsupported`, and `failClosed`.
  - User-safe unavailable reasons are limited to `accountNotEligible`, `peerNotEligible`, `roomNotEligible`, `trustNotReady`, `serviceUnavailable`, `capabilityMissing`, `unsupportedClient`, and `unknown`.
  - The payload shape carries only enums and booleans such as account, peer, room, trust, service, and client support readiness.
  - The default provider is fail-closed and returns disabled.
  - Account and peer not-eligible states map to existing safe private-card unavailable copy without exposing identifiers.
  - The skeleton is not wired to enable non-engineering dogfood; server allowlist/capability backing and runtime proof are still required.
- Native audio eligibility runtime/no-activation proof passed:
  - With `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1` and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`, but without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, an attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`.
  - The no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
  - With the explicit private dogfood gate restored, backend readiness passed with `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, A/B trust ready, and A/B activation enabled.
  - The runner-assisted A -> B happy path reached `productionSessionState=activeAudio` on both sides with `productionEncryptionState=ready`, media connect attempted, LiveKit client connect attempted, and `productionMediaFailureReason=none`.
  - Hangup returned A/B to `productionSessionState=idle` with no active session and media failure `none`.
  - The legacy fake/dry-run gate remained unset; Element Call route remained untouched.
- Call-service native audio eligibility endpoint skeleton is added:
  - `POST /_matrix/client/unstable/kz.salemx.direct_call/eligibility` validates Matrix bearer auth, optional device binding, and encrypted direct 1:1 room structure before returning a redacted enum/boolean eligibility response.
  - Native audio eligibility remains disabled by default. The static allowlist skeleton requires both caller and peer accounts when explicitly enabled by local deployment config.
  - Readiness now exposes only redacted eligibility booleans: `nativeAudioEligibilityConfigured` and `nativeAudioEligibilityAllowlistConfigured`.
  - The LiveKit token endpoint reuses the same eligibility policy before rate limiting, allocation, LiveKit room pre-create, or participant token issuance.
  - Eligibility rejection fails closed with no token, no allocation, and no LiveKit room pre-create.
  - This does not wire iOS non-engineering activation; controlled engineering dogfood remains on the explicit DEBUG/integration private dogfood gate.
- Native audio eligibility endpoint local route smoke passed:
  - Readiness returned `ready=true`, `reason=ok`, and included `nativeAudioEligibilityConfigured` plus `nativeAudioEligibilityAllowlistConfigured`.
  - Default fail-closed `/eligibility` returned `state=unavailable`, `reason=capabilityMissing`, and `capability_present=false`.
  - Default token endpoint enforcement returned `403` with `M_DIRECT_CALL_NOT_ELIGIBLE`, no allocation, no LiveKit room pre-create, and no participant token issuance.
  - Explicit allowlisted local fixture returned `/eligibility` `state=eligible`, `reason=null`; the token path proceeded with allocation, one LiveKit room pre-create, and token issuance, with token output redacted.
  - Negative cases passed: caller not allowlisted -> `accountNotEligible`, peer not allowlisted -> `peerNotEligible`, invalid room -> `roomNotEligible`, malformed request -> `400`, unsupported intent -> `M_DIRECT_CALL_UNSUPPORTED_INTENT`.
  - Smoke output stayed redacted: no raw tokens, JWTs, secrets, room IDs, user IDs, peer IDs, device IDs, Redis credential URLs, or LiveKit room names were printed.
- iOS native audio eligibility provider skeleton is added:
  - The app has a request DTO for the backend `/eligibility` endpoint with redacted descriptions for room, peer, and device identifiers.
  - The response payload now supports the backend `capability_present` / `capabilityPresent` boolean while keeping enum/boolean-only output.
  - The HTTP provider uses the existing Matrix bearer access-token provider and redacted direct-call HTTP transport.
  - Missing config/auth/transport, network failures, 5xx, malformed JSON, unknown enums, and unsupported intents fail closed.
  - The default provider remains disabled/fail-closed.
  - This provider is not wired into non-engineering activation; controlled engineering dogfood remains on the explicit DEBUG/integration private dogfood gate.
  - Element Call route, CallKit, push, video, and global production activation remain unchanged.
- iOS native audio eligibility provider no-activation runtime proof passed:
  - Without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, product UI/start gates stayed blocked with `appRolloutDisabled` in an attached encrypted direct 1:1 room.
  - The no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
  - The provider skeleton remains unwired for non-engineering activation; source inspection found app-side provider usage only in the provider/types and test boundary.
  - `directOneToOneCallsEnabled` remains separate from native audio activation and does not enable the native eligibility path.
  - With the explicit private dogfood gate restored, readiness passed, A/B trust was ready, A/B activation was enabled, and the runner-assisted A -> B happy path reached `activeAudio`.
  - Hangup returned A/B to `idle` with no active session, cleanup/disconnect attempted, and media failure `none`.
  - The legacy fake/dry-run gate remained unset, Element Call route remained untouched, and no code changes were needed during the runtime proof.
- Native audio eligibility status cache skeleton is added:
  - A new DEBUG/integration-only status gate, `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1`, allows room-card status to evaluate the backend eligibility provider for display/preflight only.
  - The gate is disabled by default, requires the diagnostic integration command harness, and does not enable private dogfood activation, production start, or non-engineering rollout.
  - Eligibility status is cached in memory only at room-flow scope, with separate positive and negative TTLs, redacted cache-key descriptions, manual refresh bypass, and cache clearing on room-flow setup.
  - Card-status merge is fail-closed and status-only: backend eligible never changes an unavailable card to `canStart`, local room/trust failures remain authoritative, and private dogfood activation remains unchanged.
  - Status refresh may only call `/eligibility`; rendering/status display still must not send Matrix events, request LiveKit tokens, allocate/pre-create rooms, connect media, connect LiveKit, or start outgoing calls.
  - Token-backend rejection invalidates the local eligibility status cache when the status path is wired.
  - This does not wire non-engineering internal pilot activation; the token endpoint remains the final enforcement boundary.
- Native audio eligibility status cache no-activation runtime proof passed:
  - Readiness passed with `ready=true`, `reason=ok`, Redis allocation/rate-limit connectivity, storage key configured, LiveKit room provisioning configured, and native audio eligibility plus allowlist configured.
  - With product UI and eligibility status gates enabled, but without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, an attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`.
  - With product UI, production start, and eligibility status gates enabled, but without the private dogfood gate, `production-start-outgoing` remained blocked with `appRolloutDisabled`.
  - The no-private-dogfood runs had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
  - A temporary blocker was diagnosed as Redis rate-limit store unavailability: token issuance failed closed with `M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE` / `503` until Redis connectivity was restored.
  - After Redis recovery, with the explicit private dogfood gate restored, A/B trust and activation were ready, A reached outgoing ringing, B reached incoming ringing, B accepted, and A/B reached `activeAudio`.
  - A/B had media connect and LiveKit client connect attempted, `productionMediaFailureReason=none`, and hangup returned A/B to `idle` with cleanup/disconnect attempted.
  - The legacy fake/dry-run gate remained unset, Element Call route remained untouched, and no code changes were needed during the runtime proof.
- Native audio eligibility status integration polish and runtime proof passed:
  - LiveKit room names are now redacted from production token response `description` and `debugDescription` output, matching the dogfood monitoring contract.
  - The two-client diagnostic runner now forwards `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1` to launched simulator processes and reports that status gate as enabled/disabled without printing env values.
  - With product UI, production start, and eligibility status gates enabled, but without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, an attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`.
  - The no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
  - With the explicit private dogfood gate restored, readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
  - A/B activation and trust were ready, the runner-assisted A -> B happy path reached `activeAudio`, media and LiveKit connect were attempted on both sides, and `productionMediaFailureReason=none`.
  - Hangup returned A/B to `idle` with no active session, cleanup/disconnect attempted, and media failure `none`.
  - A `wait-status incomingRinging` helper poll timed out before accept, but explicit accept and final status proved the incoming session, active audio, hangup, and cleanup path. This helper timeout is not a media/backend failure.
  - Negative backend eligibility reason mappings remain covered by unit tests and the 2.30F route smoke; this live run did not reconfigure the local staging allowlist for negative cases.
  - The legacy fake/dry-run gate remained unset and Element Call route remained untouched.
- Native audio eligibility status controlled engineering soak passed:
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
  - A/B activation and trust were ready under the explicit private dogfood gates with `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1`.
  - Runner-assisted happy path A -> B and reverse B -> A reached `activeAudio`, then hangup returned both sides to idle/no active session with media failure `none`.
  - Two repeated A -> B calls reached `activeAudio`, returned idle, and showed no stale session or split-brain.
  - Decline and cancel flows passed through the shared production hangup command: incoming ringing emitted `reject`, outgoing ringing emitted `cancel`, both sides returned idle, and terminal reason was `cancelled`.
  - Timeout passed with terminal reasons `outgoingTimeout` and `incomingTimeout`; both sides returned idle with media failure `none`.
  - Relaunch during ringing failed closed with no active session restored. Final post-relaunch status was `unavailable` because the encrypted 1:1 room was not re-opened, which is expected for the current foreground/open-room scope.
  - Final readiness remained `ready=true`, `reason=ok`.
  - Runner output did not include LiveKit room names, and Element Call route remained untouched.
  - No code changed during the soak.
- Narrow engineering expansion pilot runbook is recorded:
  - 2.33A allows a small engineering-only expansion, still staging-only and conditional.
  - The maximum safe next step is up to 4 named engineering operators and up to 8 named devices.
  - The first expanded window remains one active 1:1 native audio call at a time.
  - Participant/device and pair matrices use labels only and must not include raw user IDs, room IDs, peer IDs, device IDs, tokens, JWTs, secrets, Redis credential URLs, Matrix event bodies, or LiveKit room names.
  - Required gates include product UI, eligibility status, private dogfood, production start, staging token base URL, and the DEBUG/integration diagnostics gates; the legacy fake/dry-run gate remains unset.
  - Every new pair must run happy path, reverse, repeated x2, decline, cancel, timeout if practical, relaunch fail-closed, listener/open-room unavailable, Element Call fallback, and backend-off/recovery only when safe.
  - LiveKit-off remains not-run unless the shared staging LiveKit owner explicitly approves a disruption window.
  - Non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Timeout terminal cleanup fix is recorded:
  - The 2.33C expansion pilot paused because timeout terminal reasons were set while `productionHasActiveSession` stayed true until explicit cleanup.
  - Root cause: timeout paths transitioned to terminal states but left the active session owned until delayed cleanup.
  - Commit `1d9218057` makes DirectCallEngine timeout terminal paths disconnect and cleanup immediately.
  - Runtime timeout proof passed with A terminal `outgoingTimeout`, B terminal `incomingTimeout`, A/B `productionSessionState=idle`, A/B `productionHasActiveSession=false`, cleanup/disconnect attempted, and media failure `none`.
  - A next call after timeout reached A/B `activeAudio`, then hangup returned A/B to idle with no active session and media failure `none`.
  - Validation passed: DirectCallEngineTests 36/36, focused native subset 171 tests, Release build with existing warnings only, SwiftFormat/SwiftLint, `git diff --check`, and the direct-call forbidden scan.
- Narrow engineering expansion pilot session 1 rerun passed after the timeout cleanup fix:
  - Session used redacted A/B engineering labels only, staging call-service, staging LiveKit, required DEBUG/integration gates, eligibility status gate, private dogfood gate, production start gate, and the staging token base URL.
  - The legacy fake/dry-run gate stayed unset.
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
  - A/B trust was ready, and baseline status was idle/no active session.
  - Runner-assisted happy path A -> B, reverse B -> A, and repeated A -> B calls x2 reached `activeAudio`; hangup returned A/B to idle/no active session with media failure `none`.
  - Decline and cancel returned A/B to idle/no active session.
  - Timeout passed with A terminal `outgoingTimeout`, B terminal `incomingTimeout`, A/B idle/no active session, cleanup/disconnect attempted, and media failure `none`.
  - Relaunch during ringing returned A/B to idle/no active session.
  - Listener-unavailable behavior passed by stopping B before A started: A timed out fail-closed with `outgoingTimeout`, no active session, and media failure `none`; B relaunched idle/no active session.
  - Backend-off recovery was not run because the local staging call-service stayed up for the pilot. LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval.
  - Final A/B status was idle/no active session with media failure `none`, no rollback was needed, no stop criteria triggered, no redaction issue was observed, and Element Call route remained untouched.
- Engineering expansion soak plan is recorded:
  - 2.34A defines a 3-session engineering-only soak before any broader readiness review.
  - Scope remains up to 4 named engineering operators, up to 8 named devices, predeclared labels only, staging call-service, staging LiveKit, private native audio card only, foreground/open encrypted direct 1:1 rooms only, verified/trusted peers only, and one active 1:1 call at a time.
  - Each session must pass preflight, A -> B happy path, B -> A reverse, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, and Element Call fallback smoke.
  - Backend-off/recovery remains optional only when safe for the local staging setup; LiveKit-off remains not-run unless explicitly approved by the shared staging LiveKit owner.
  - Decision rule: 3 clean sessions lead to a readiness review for the next phase; any critical bug or stop criterion pauses the soak for diagnosis.
- Engineering expansion soak session 1 passed:
  - Session used redacted A/B engineering labels only, staging call-service, staging LiveKit, required DEBUG/integration gates, eligibility status gate, private dogfood gate, production start gate, and staging token base URL.
  - The legacy fake/dry-run gate stayed unset.
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session.
  - Runner-assisted A -> B happy path, B -> A reverse path, and repeated A -> B calls x2 reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`.
  - Decline, cancel, timeout, relaunch-ringing, listener-unavailable/open-room edge, and post-listener recovery passed.
  - Timeout reported A `outgoingTimeout` and B `incomingTimeout`; both sides returned idle/no active session with media failure `none`.
  - Backend-off recovery was not run because the local staging call-service stayed up for the session. LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval.
  - Final A/B status was idle/no active session with media failure `none`, cleanup/disconnect attempted on both sides, no rollback, no stop criteria, no redaction issue, and Element Call route untouched.
- Engineering expansion soak session 2 passed:
  - Session used redacted A/B engineering labels only, staging call-service, staging LiveKit, required DEBUG/integration gates, eligibility status gate, private dogfood gate, production start gate, and staging token base URL.
  - The legacy fake/dry-run gate stayed unset.
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session.
  - Runner-assisted A -> B happy path, B -> A reverse path, and repeated A -> B calls x2 reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`.
  - Decline, cancel, timeout, relaunch-ringing, listener-unavailable/open-room edge, and post-listener recovery passed.
  - Timeout reported A `outgoingTimeout` and B `incomingTimeout`; both sides returned idle/no active session with media failure `none`.
  - Backend-off recovery was not run because the local staging call-service stayed up for the session. LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval.
  - Final A/B status was idle/no active session with media failure `none`, cleanup/disconnect attempted on both sides, no rollback, no stop criteria, no redaction issue, and Element Call route untouched.
- Engineering expansion soak session 3 passed:
  - Session used redacted A/B engineering labels only, staging call-service, staging LiveKit, required DEBUG/integration gates, eligibility status gate, private dogfood gate, production start gate, and staging token base URL.
  - The legacy fake/dry-run gate stayed unset.
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session.
  - Runner-assisted A -> B happy path, B -> A reverse path, and repeated A -> B calls x2 reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`.
  - Decline, cancel, timeout, relaunch-ringing, listener-unavailable/open-room edge, and post-listener recovery passed.
  - Timeout reported A `outgoingTimeout` and B `incomingTimeout`; both sides returned idle/no active session with media failure `none`.
  - Backend-off recovery was not run because the local staging call-service stayed up for the session. LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval.
  - Final A/B status was idle/no active session with media failure `none`, cleanup/disconnect attempted on both sides, no rollback, no stop criteria, no redaction issue, and Element Call route untouched.
  - The planned 3-session engineering expansion soak is complete.
- Engineering expansion operations handoff is recorded:
  - Narrow engineering dogfood may continue without per-session Codex supervision only when named operators follow the handoff checklist.
  - Required ownership is explicit: session owner, backend readiness watcher, client operators, redaction reviewer, stop authority, and rollback owner.
  - The same staging-only cap remains: up to 4 named engineering operators, up to 8 named devices, predeclared pairs only, one active 1:1 native audio call at a time, private native audio card only, verified/trusted peers only, and redacted reporting only.
  - Monitoring baseline remains limited to readiness booleans, trust booleans, `productionSessionState`, `productionMediaFailureReason`, terminal reason enum, cleanup/disconnect booleans, pass/fail/not-run, and redacted backend reason enums.
  - Clean sessions follow a docs-only report path with redaction review and validation before commit.
- Call-service Redis readiness is hardened:
  - Redis-backed staging readiness now performs bounded live Redis pings at startup and on each readiness request for both allocation and rate-limit stores.
  - `allocationStoreConnected` and `rateLimitConnected` now reflect live Redis connectivity for Redis stores, not only config shape or implementation presence.
  - If allocation Redis is unreachable, readiness fails closed with `allocationStoreUnavailable` and `allocationStoreConnected=false`.
  - If rate-limit Redis is unreachable, readiness fails closed with `rateLimitStoreUnavailable` and `rateLimitConnected=false`.
  - Token endpoint behavior remains unchanged and still fails closed without issuing tokens on Redis store failure.
- Redis readiness recovery native audio smoke passed:
  - After `f4656983a`, Redis-up readiness returned `200`, `ready=true`, `reason=ok`, allocation/rate-limit connected true, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
  - A/B trust remained ready with own session verified, cross-signing ready, and peer trust ready.
  - Runner-assisted A -> B reached B `incomingRinging`, B accepted, and A/B reached `activeAudio` with encryption ready.
  - A/B had media connect and LiveKit client connect attempted, `productionMediaFailureReason=none`, and hangup returned both sides to `idle` with no active session.
  - Element Call route remained untouched and no code changes were needed during the runtime proof.
- Private dogfood activation is explicit and fail-closed by default:
  - `appRolloutDisabled` is produced by the production activation decision when `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` is absent.
  - `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1` can show the private card, and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1` can allow start actions, but neither gate enables rollout/capability readiness by itself.
  - The private dogfood gate is DEBUG/integration-only and requires `IS_RUNNING_INTEGRATION_TESTS=1`, `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`, and `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`.
  - The old `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name no longer enables the app-side activation model.
  - Product card and diagnostic runner use the same room-flow production activation/start decision.
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit media proof reached active.
- Production token DTOs, client, and transport seams exist.
- Backend token service skeleton exists.
- Synapse room validation skeleton exists.
- Local backend fake smoke exists.
- App production token client smoke test exists and is disabled by default.
- Production E2EE key wrapping seam inspection is complete:
  - The direct-call room-flow path has room and peer metadata plus a clean dependency injection point.
  - The custom direct-call Matrix event is sent through SDK room sending and is expected to be room-encrypted when the room is encrypted.
  - Room encryption is a necessary transport layer, but not sufficient as the production media-key wrapping design: the app still must not place unwrapped media key material in the event content handed to the SDK.
  - The current app Matrix crypto proxies expose identity/key status, but not a narrow per-call media-key wrapping primitive.
- App-side production key-wrapping seams exist and remain fail-closed:
  - `DirectCallMediaKeyWrappingProtocol` models wrap/unwrap requests around call, room, sender, recipient, device, intent, expiry, key ID, and an opaque envelope.
  - `FailClosedDirectCallMediaKeyWrapper` is the default wrapper and cannot wrap or unwrap.
  - `ProductionDirectCallEncryptionService` can use an injected wrapper plus a shared `DirectCallLiveKitMediaKeyStore`, but defaults to fail-closed with no production activation.
  - `NativeDirectCallProductionDependenciesFactory` can accept a future production key wrapper and shared media key store, while remaining disabled by default.
- Matrix SDK direct-call media key envelope crypto is proven locally and published through the Swift wrapper:
  - High-level SDK tests create Alice and Bob crypto clients with mocked Matrix crypto endpoints and encrypted room state.
  - Alice wraps a per-call media key for Bob; Bob unwraps it and receives the original key material only at the SDK consumer boundary.
  - The opaque envelope does not contain the test media key in plaintext, and debug output remains redacted.
  - Wrong call, room, sender, recipient, intent, and key ID metadata fail closed.
  - A non-recipient device cannot unwrap the envelope.
  - `OnlyTrustedDevices` rejects the current unverified test peer devices with `TrustViolation`.
  - A multi-device Bob envelope includes all eligible Bob devices and can be unwrapped by Bob's second device.
  - `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib` passes.
  - `cargo check -p matrix-sdk-ffi` passes.
- Wrapper publication and app pin are complete:
  - Full `MatrixSDKFFI.xcframework` was built for device and simulator targets.
  - The published artifact checksum was verified after download.
  - Generated Swift bindings expose `DirectCallMediaKeyWrapInfo`, `DirectCallMediaKeyUnwrapInfo`, `DirectCallMediaKeyEnvelope`, `DirectCallMediaKeyUnwrapResult`, `DirectCallMediaKeyEnvelopeError`, `wrapDirectCallMediaKey`, and `unwrapDirectCallMediaKeyEnvelope`.
  - Wrapper `swift package resolve` and `swift package describe` pass using the published URL and checksum.
  - App `project.yml`, generated Xcode project, and `compound-ios/Package.resolved` are pinned to wrapper commit `1e58d0a4317e3ff74c2d565cf532bc8d035bcc8f`.
  - Focused app unit tests and Release build pass after the pin.
- App-side async Matrix SDK key wrapper skeleton is complete:
  - Generated MatrixRustSDK bindings expose async `wrapDirectCallMediaKey(...)` and `unwrapDirectCallMediaKeyEnvelope(...)` methods on `EncryptionProtocol`.
  - `DirectCallMediaKeyWrappingProtocol` and `DirectCallEncryptionServiceProtocol` are now async at the key wrap/unwrap boundary.
  - `DirectCallEngine` awaits key generation and remote key consume in already-async call paths.
  - `MatrixSDKDirectCallMediaKeyWrapper` maps app wrap/unwrap request models to the generated SDK FFI models and maps SDK envelope results back to redacted app models.
  - Missing SDK encryption dependency still fails closed.
  - `FailClosedDirectCallMediaKeyWrapper` remains the default production wrapper.
  - The SDK-backed wrapper is not injected into production runtime.
  - Focused app unit tests and Release build pass after the async skeleton.
- Production SDK key wrapper injection seam is complete:
  - `NativeDirectCallProductionDependenciesFactory` can accept the narrow `MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol`.
  - The factory constructs `MatrixSDKDirectCallMediaKeyWrapper` from that narrow envelope wrapper only when production dependencies are explicitly enabled.
  - An explicitly provided `DirectCallMediaKeyWrappingProtocol` still takes precedence, preserving test and future injection flexibility.
  - Missing wrapper dependencies still fall back to `FailClosedDirectCallMediaKeyWrapper`.
  - No broad MatrixRustSDK client, room, timeline, or raw crypto API was exposed through app protocols.
  - Production direct calls remain disabled by default.
- Local backend HTTP smoke harness is fixed and proven:
  - `Tools/Scripts/run_direct_call_backend_smoke.sh` validates local fake backend reachability before running Xcode tests.
  - The script selects the dedicated `DirectCallBackendSmokeTests` Swift Testing suite instead of brittle method-level selectors.
  - Hosted simulator tests receive smoke configuration through a short-lived `/tmp/salemx-direct-call-backend-smoke.env` file that the script removes on exit.
  - Default runs skip the HTTP smoke tests when the smoke file/env is absent or stale.
  - Env-gated local smoke run proved both production token client and capability provider can call the local FastAPI fake backend over HTTP.
  - Output remains redacted and production direct calls remain disabled.
- Production activation dry-run enabled=true local fake pack is complete:
  - The env-gated local backend capability smoke fetches `kz.salemx.direct_call.native` from the FastAPI fake backend through `URLSessionDirectCallHTTPTransport`.
  - The smoke proves the capability provider performs only the authenticated `/capabilities` GET for the dry-run path and does not request a LiveKit token.
  - With fake rollout enabled, fake dependency readiness, and an encrypted direct 1:1 room eligibility model, the dry-run diagnostic returns `enabled=true`.
  - Default `DirectCallProductionConfiguration` remains disabled.
  - The dry-run proof verifies no key generation, key consume, key cleanup, or media engine construction occurs.
  - Production direct calls remain disabled by default; no visible UI, Element Call route, CallKit, push, listener start, media connect, or Matrix send behavior changed.
- Runtime private dogfood production activation harness is complete:
  - `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` is recognized only in DEBUG when the integration diagnostic command gates are also enabled.
  - The AppCoordinator dry-run provider factory can swap the production dry-run decision service to private dogfood rollout, private dogfood server capability, and production dependency readiness inputs for the dry-run/start model.
  - Fallback private dogfood dependencies are fail-closed if accidentally invoked and exist only to keep missing app dependencies from becoming public activation.
  - The two-client diagnostic runner passes the private dogfood flag to app launches through `SIMCTL_CHILD_NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED`.
  - Unit tests prove default runtime activation remains disabled, product UI/start gates alone do not enable dogfood activation, the legacy fake flag is ignored, and private dogfood activation can return `enabled=true` for an eligible encrypted direct 1:1 room.
  - No real production call activation, listener start, media engine construction, Matrix send, visible UI, Element Call route, CallKit, or push behavior changed.
  - Focused app unit tests and Release build pass after the injection seam.
- Runtime fake-enabled production activation dry-run proof is recorded:
  - A and B both reached app diagnostic signalling readiness with an active encrypted 1:1 room open.
  - `production-activation-dry-run A` returned `enabled=true`, `reason=none`, `capabilityPresent=true`, `dependenciesReady=true`, `roomEligible=true`, and `endpointAccepted=true`.
  - `production-activation-dry-run B` returned the same redacted enabled fields.
  - This was DEBUG/integration fake-enabled dry-run only.
  - No production call started.
  - No visible UI was activated.
  - No Element Call route, CallKit, push, listener start, Matrix send, or media connect was triggered.
- Internal production trigger dry-run command is complete:
  - `UITestsSignalling` supports a DEBUG/integration-only `nativeDirectCallProductionTriggerDryRun` request and redacted result.
  - The command routes through AppCoordinator, UserSessionFlowCoordinator, ChatsTabFlowCoordinator, and the active RoomFlowCoordinator.
  - The runner exposes `production-trigger-dry-run A|B` / `productionTriggerDryRun A|B`.
  - The trigger dry-run reads the current room-scoped production activation dry-run decision and returns `wouldStart=true` only when activation is already enabled.
  - Output is limited to redacted fields: `wouldStart`, enabled state, disabled reason, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
  - The command does not prepare controllers, start listeners, start outgoing calls, accept calls, request LiveKit tokens, wrap keys, construct media engines, or send Matrix events.
  - Focused app unit tests, Release build, runner syntax/dry-run checks, and forbidden scan pass after the command exposure.
- Runtime fake-enabled production trigger dry-run proof is recorded:
  - A and B both reached app diagnostic signalling readiness with an active encrypted 1:1 room open.
  - `production-trigger-dry-run A` returned `wouldStart=true`, `enabled=true`, `reason=none`, `capabilityPresent=true`, `dependenciesReady=true`, `roomEligible=true`, and `endpointAccepted=true`.
  - `production-trigger-dry-run B` returned the same redacted enabled fields.
  - This was DEBUG/integration fake-enabled dry-run only.
  - No production call started.
  - No visible UI was activated.
  - No Element Call route, CallKit, push, listener start, Matrix send, or media connect was intended.
- Internal production start command skeleton is complete:
  - `UITestsSignalling` supports a DEBUG/integration-only `nativeDirectCallProductionStartOutgoingAudioCall` request and redacted result.
  - The runner exposes `production-start-outgoing A|B` / `productionStartOutgoing A|B`.
  - The command is additionally gated by `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`, on top of the existing DEBUG/integration diagnostic command gates.
  - The command terminates at `RoomFlowCoordinator`, rechecks the current room-scoped production trigger dry-run decision, and only proceeds when activation is enabled.
  - The command uses a separate production owner factory seam and does not route through the diagnostic developer command router.
  - Default production owner construction remains nil/fail-closed, so the command blocks with a redacted reason unless a production-shaped owner is explicitly provided.
  - The command blocks when the dedicated start gate is missing, activation is disabled, no active room exists, a native direct-call session is already active, or the production owner is unavailable.
  - The fake started path in tests calls only an injected production owner spy and proves the diagnostic owner is not used.
  - Output is limited to redacted fields: outcome, blocked reason, trigger dry-run readiness fields, and non-identifying session summary booleans/enums.
  - No visible UI, Element Call route, `RoomScreenViewModel.displayCall`, `RoomScreenCoordinator.presentCallScreen`, `ElementCallService`, CallKit, push, global production feature activation, broad SDK raw API, credential logging, or key logging changed.
  - Focused app unit tests, Release build, runner syntax check, and the direct-call forbidden scan pass after the command skeleton.
- Internal production start command runtime proof is recorded:
  - Without `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`, `production-start-outgoing A` blocked with `productionStartDisabled`.
  - With the dedicated start gate enabled and fake-enabled activation inputs, `production-start-outgoing A` blocked with `productionOwnerUnavailable`.
  - Status remained idle with listener not started, no active session, no Matrix signal send, and no media connect.
  - No visible UI, Element Call route, CallKit, push, listener start, Matrix send, or media connect side effects occurred.
- Production owner wiring skeleton is complete:
  - `RoomFlowCoordinator` now creates and retains the production owner lazily only after the DEBUG/integration production start command gate and activation decision pass.
  - The production owner remains separate from the diagnostic owner; diagnostic owner state is checked only to block overlapping sessions.
  - `storeAndSubscribeToRoomProxy` no longer creates the production owner when a room opens, so normal room display and dry-run checks do not start listeners or build call runtime.
  - The internal production start command starts the production listener before outgoing start only after all command gates pass.
  - `AppCoordinator` can build a production-shaped owner from session runtime providers: `URLSessionDirectCallHTTPTransport`, Matrix access-token provider, narrow Matrix SDK key envelope provider, `LiveKitDirectCallClient`, and `ClientProxy` user/device metadata.
  - If production-shaped runtime dependencies are unavailable, the command now blocks with `dependenciesUnavailable` instead of the less precise `productionOwnerUnavailable`.
  - The production owner is reset with the room flow owner on room dismiss/reset.
  - No visible UI, Element Call route, `RoomScreenViewModel.displayCall`, `RoomScreenCoordinator.presentCallScreen`, `ElementCallService`, CallKit, push, global production activation, diagnostic secret/token use, broad SDK raw API, credential logging, or key logging changed.
  - Focused app unit tests, Release build, and the direct-call forbidden scan pass after the production owner wiring skeleton.
- Production runtime SDK key wrapper provider seam is complete:
  - `DirectCallMediaKeyEnvelopeWrappingProviding` exposes only a direct-call envelope wrapper provider, not a raw SDK client, raw SDK room, raw timeline, or raw crypto object.
  - Concrete `ClientProxy` can create `MatrixSDKDirectCallMediaKeyEnvelopeWrapperAdapter` from `client.encryption()` through that narrow provider seam.
  - `ClientProxyProtocol`, `RoomProxyProtocol`, and `TimelineProxyProtocol` remain unchanged.
  - `NativeDirectCallProductionDependenciesFactory` can use an explicit wrapper first, then an explicit SDK envelope wrapper, then the runtime provider, and finally the fail-closed wrapper.
  - The production factory does not ask the runtime provider while production direct-call configuration is disabled.
  - Missing provider/wrapper dependencies remain fail-closed.
  - Diagnostic direct-call encryption and LiveKit paths remain isolated behind DEBUG/integration gates.
  - Focused app unit tests, Release build, and forbidden scan pass after the provider seam.
- Disabled production direct-call dependency wiring is complete:
  - `NativeDirectCallProductionDependencyAssembly` can assemble production dependencies only from explicit production configuration and injected runtime providers.
  - Required providers are the production HTTP transport, Matrix access-token provider, LiveKit client, narrow SDK key envelope provider, own user ID, and optional shared media key store/sender device ID.
  - Missing production config or any required runtime provider returns disabled/fail-closed dependencies.
  - The assembly builds `ProductionDirectCallLiveKitTokenClient` from injected transport/auth only when explicitly configured.
  - Concrete `ClientProxy` now conforms to the narrow `DirectCallMatrixAccessTokenProviding` protocol without changing `ClientProxyProtocol`.
  - No runtime UI path, Element Call route, CallKit, push, diagnostic env, or production feature flag was activated.
  - Focused app unit tests, Release build, and forbidden scan pass after the disabled wiring seam.
- Production activation gate design inspection is complete:
  - `directOneToOneCallsEnabled` should not be reused as the native production activation switch because it currently belongs to the existing direct-call/Element Call placeholder path and logs that production signal transport is disabled.
  - The safest production gate is multi-factor: app rollout configuration, authenticated server capability, token endpoint discovery, runtime dependency readiness, room eligibility, and future UI/CallKit readiness.
  - The authoritative server signal should be a SalemX-specific Matrix client capability, not a developer option or diagnostic env.
  - Endpoint discovery should prefer an authenticated Matrix capability that advertises the native direct-call token endpoint as a same-origin relative path, with the current unstable path as the default contract.
  - `.well-known` can remain useful for pre-auth hints, but should not be sufficient to activate production direct calls.
  - Diagnostics remain separate and must not influence production activation.
- Production direct-call activation gate skeleton is complete:
  - `DirectCallProductionServerCapability` models the SalemX native direct-call capability `kz.salemx.direct_call.native`.
  - The capability requires version `1`, audio intent support, LiveKit media transport, E2EE required, and the Matrix SDK direct-call media key envelope scheme.
  - Token endpoint discovery is modeled as a same-origin relative endpoint path, with same-origin configured endpoint override support.
  - `DirectCallProductionRoomEligibility` models only redacted room eligibility booleans/count state: direct room, encrypted room, exactly two joined members, and peer availability.
  - `DirectCallProductionActivationGate` is disabled by default and returns redacted fail-closed reasons for missing rollout, capability, endpoint, dependencies, or room eligibility.
  - `directOneToOneCallsEnabled` remains unused for native production activation.
  - The gate is not wired into visible UI, Element Call routing, CallKit, push, or runtime production activation.
  - Focused app unit tests, Release build, and forbidden scan pass after the activation gate skeleton.
- Production direct-call server capability discovery seam skeleton is complete:
  - `DirectCallProductionCapabilityProviding` models an async, fail-closed source for the SalemX native direct-call server capability.
  - `FailClosedDirectCallProductionCapabilityProvider` is the default provider and returns `providerUnavailable`.
  - `DirectCallProductionCapabilityPayloadDecoder` decodes the authenticated Matrix capabilities envelope for `kz.salemx.direct_call.native`.
  - Missing or malformed capability payloads return redacted fail-closed discovery reasons.
  - The decoded capability feeds the existing `DirectCallProductionActivationGate`, which still owns same-origin endpoint validation and all activation decisions.
  - The current app/wrapper inspection found no existing narrow authenticated custom capability API beyond the separate `ClientProxy.isLiveKitRTCSupported` helper and pre-auth `.well-known` patterns.
  - No real network fetch, UI path, Element Call routing, CallKit, push, diagnostic env, or production runtime activation was added.
  - Focused app unit tests, Release build, and forbidden scan pass after the discovery seam skeleton.
- Production activation decision assembly skeleton is complete:
  - `DirectCallProductionActivationDeciding` models the narrow async activation decision boundary.
  - `DirectCallProductionActivationDecisionService` assembles app rollout configuration, server capability discovery, production dependency readiness, homeserver URL, and room eligibility into the existing `DirectCallProductionActivationGate`.
  - `NativeDirectCallProductionDependencyProviding` lets the decision service consume dependency readiness without constructing listeners, media engines, or room owners.
  - Default configuration remains disabled and does not query capability or dependency providers.
  - Missing or malformed capability discovery fails closed before dependency readiness is queried.
  - Unsupported capability fields, external endpoints, unavailable dependencies, and ineligible rooms all map to existing redacted disabled reasons.
  - The service is not wired into visible UI, Element Call routing, CallKit, push, diagnostics, or production runtime activation.
  - `directOneToOneCallsEnabled` remains unused for native production activation.
  - Focused app unit tests, Release build, and forbidden scan pass after the decision assembly skeleton.
- Production activation dry-run diagnostics are complete:
  - `DirectCallProductionActivationDryRunDiagnostic` reports only redacted activation booleans and disabled reason: enabled state, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
  - `DirectCallProductionActivationDryRunDiagnosing` exposes an internal async dry-run boundary on the existing decision service.
  - Dry-run uses the same `DirectCallProductionActivationGate` as the real decision path, avoiding a parallel activation model.
  - Default configuration remains disabled and does not query capability or dependency providers.
  - Missing or malformed capability discovery skips dependency readiness checks.
  - All-valid dry-run returns an enabled diagnostic model without generating keys, consuming keys, clearing keys, constructing a media engine, starting listeners, creating controllers, or sending Matrix events.
  - The dry-run surface is not wired into visible UI, Element Call routing, CallKit, push, diagnostics env, or production runtime activation.
  - Focused app unit tests, Release build, and forbidden scan pass after the dry-run diagnostics.
- Room-scoped production activation dry-run seam is complete:
  - `NativeDirectCallProductionActivationDryRunProviding` models a room-scoped provider for redacted production activation readiness.
  - `FailClosedNativeDirectCallProductionActivationDryRunProvider` is the default provider and returns disabled with `roomUnavailable`.
  - `NativeDirectCallProductionActivationDryRunProvider` delegates to `DirectCallProductionActivationDryRunDiagnosing` with an injected homeserver URL and room eligibility.
  - `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()` returns a redacted disabled diagnostic when no active room is available.
  - Once a room proxy is stored, `RoomFlowCoordinator` can delegate to an injected dry-run provider without preparing the native direct-call room owner.
  - Tests prove the room-scoped dry-run does not call prepare, start listener, outgoing call, accept, hangup, stop, reset, media, signalling, or Matrix send paths.
  - The seam is not wired into visible UI, Element Call routing, CallKit, push, diagnostic env, or production runtime activation.
  - Focused app unit tests, Release build, and forbidden scan pass after the room-scoped dry-run seam.
- Debug/internal production activation dry-run command exposure is complete:
  - `UITestsSignalling` now supports a DEBUG/integration-only `nativeDirectCallProductionActivationDryRun` request and redacted result.
  - The existing diagnostic harness routes the command through AppCoordinator, UserSessionFlowCoordinator, ChatsTabFlowCoordinator, and the active RoomFlowCoordinator dry-run seam.
  - The runner exposes `production-activation-dry-run A|B` / `productionActivationDryRun A|B`.
  - Output is limited to redacted fields: enabled state, disabled reason, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
  - The command does not prepare controllers, start listeners, start outgoing calls, accept calls, construct media engines, or send Matrix events.
  - The DEBUG/integration runtime provider uses the production dry-run decision service with default rollout disabled, so production remains fail-closed by default.
  - Focused app unit tests, Release build, runner syntax/dry-run checks, and forbidden scan pass after the command exposure.
- Production activation dry-run runtime proof is recorded:
  - A and B both reached app diagnostic signalling readiness.
  - A and B both responded to the normal status command.
  - `production-activation-dry-run A` returned `enabled=false`, `reason=appRolloutDisabled`, `capabilityPresent=false`, `dependenciesReady=false`, `roomEligible=true`, and `endpointAccepted=false`.
  - `production-activation-dry-run B` returned the same redacted fields.
  - No production call started.
  - No listener, media, or Matrix send side effects were triggered by the dry-run command.
  - The disabled production state is expected.
- App rollout/capability config source inspection is complete:
  - `DirectCallProductionConfiguration` should stay default-disabled and should not read diagnostic env, developer options, or `directOneToOneCallsEnabled`.
  - App rollout should come from an app-owned production config source, preferably an `AppSettings`/hook-backed non-user-facing value that defaults false and can later be remotely configured.
  - Server authority should come from authenticated Matrix `/capabilities` containing `kz.salemx.direct_call.native`, not `.well-known` alone.
  - `.well-known` may remain a pre-auth hint or remote settings input, but must never be sufficient to activate production native direct calls.
  - The current Swift Matrix SDK wrapper exposes specialized `isLiveKitRTCSupported`/versions helpers, but no narrow generic authenticated `/capabilities` fetch for the SalemX native direct-call capability.
  - A narrow `DirectCallHTTPTransportProtocol` + `DirectCallMatrixAccessTokenProviding` capability provider is the safest app-side source for now; it can fetch `/_matrix/client/v3/capabilities` and pass only response data into `DirectCallProductionCapabilityPayloadDecoder`.
  - Token endpoint discovery should continue to accept only same-origin relative paths from capability, with same-origin explicit overrides reserved for app configuration/tests.
  - Dependency readiness should be computed after an accepted token endpoint exists, or split into side-effect-free runtime-prerequisite readiness plus endpoint-specific dependency assembly.
  - Production remains disabled by default and no app code changed during this inspection.
- Fail-closed rollout and capability source skeleton is complete:
  - `DirectCallProductionRolloutProviding` models the app-owned rollout configuration source.
  - `FailClosedDirectCallProductionRolloutProvider` returns the default disabled `DirectCallProductionConfiguration`.
  - `HTTPDirectCallProductionCapabilityProvider` fetches authenticated Matrix `/_matrix/client/v3/capabilities` through injected `DirectCallHTTPTransportProtocol` and `DirectCallMatrixAccessTokenProviding`.
  - The provider decodes only the `kz.salemx.direct_call.native` capability through `DirectCallProductionCapabilityPayloadDecoder`.
  - Missing homeserver URL, invalid URL scheme, missing transport, missing access token, non-2xx HTTP responses, missing capability, or malformed capability all fail closed with redacted reasons.
  - The authenticated request uses `GET` with an Authorization bearer header, while request/provider descriptions redact the URL and bearer value.
  - `.well-known` is not used for production activation.
  - `directOneToOneCallsEnabled` remains unused for native production activation.
  - Capability-sourced absolute/external token endpoints are still rejected by the activation gate.
  - No runtime production path, visible UI, Element Call routing, CallKit, push, listener start, media engine construction, or Matrix send was added.
  - Focused app unit tests, Release build, and forbidden scan pass after the source skeleton.
- Production activation decision now uses rollout/capability providers:
  - `DirectCallProductionActivationDecisionService` stores a `DirectCallProductionRolloutProviding` and asks it for configuration at decision time.
  - Static configuration remains supported through a redacted static rollout provider wrapper.
  - Default providers remain fail-closed: rollout disabled, capability absent, and dependencies unavailable.
  - Disabled rollout short-circuits before querying capability or dependency providers.
  - Rollout-enabled decisions query the capability provider, then dependency readiness, then room eligibility in a side-effect-free sequence.
  - Capability provider failures remain redacted and map to `serverCapabilityUnavailable`.
  - All-valid fake inputs can produce an enabled dry-run decision without constructing listeners, controllers, media engines, or sending Matrix events.
  - Existing runner dry-run output remains redacted and unchanged.
  - No runtime production path, visible UI, Element Call routing, CallKit, push, listener start, media engine construction, or Matrix send was added.
  - Focused app unit tests, Release build, and forbidden scan pass after the provider-backed decision wiring.
- Production activation readiness pack is complete:
  - Consolidated tests prove the enabled model requires rollout enabled, valid server capability, accepted same-origin token endpoint, production dependencies ready, and encrypted direct 1:1 room eligibility.
  - Fail-closed coverage now includes disabled rollout, missing capability, malformed capability, external endpoint rejection, unavailable dependencies, unavailable room, unencrypted room, and non-1:1 room cases.
  - Dry-run signal encoding tests assert output remains redacted and excludes room IDs, peer IDs, endpoint values, credential-like fields, unwrapped key material, Matrix content, and encrypted payload values.
  - No-side-effect checks prove the readiness path does not generate keys, consume keys, clear keys, construct media engines, start listeners, or send Matrix events.
  - The runner command remains read-only and production direct calls remain disabled by default.
  - Focused app unit tests, Release build, and forbidden scan pass after the readiness pack.
- Local backend + app production token/capability integration smoke pack is complete:
  - Backend fake mode now exposes a local-only Matrix capabilities response for `kz.salemx.direct_call.native`.
  - The fake capabilities route exists only when `SALEMX_CALL_SERVICE_FAKE_MODE=1`.
  - The existing env-gated app token smoke still verifies `ProductionDirectCallLiveKitTokenClient` can consume the local fake token response through `URLSessionDirectCallHTTPTransport`.
  - A new env-gated app capability smoke verifies `HTTPDirectCallProductionCapabilityProvider` can fetch/decode the local fake capability response through `URLSessionDirectCallHTTPTransport`.
  - The smoke also proves default rollout still returns `appRolloutDisabled`, while an all-valid test-only model can produce an enabled dry-run decision without runtime activation.
  - Local smoke instructions are documented in `docs/direct-call/LOCAL_BACKEND_SMOKE.md`.
  - Production direct calls remain disabled by default.
- Local backend HTTP smoke harness is fixed and proven:
  - `Tools/Scripts/run_direct_call_backend_smoke.sh` validates local fake backend reachability before running Xcode tests.
  - The script selects the dedicated `DirectCallBackendSmokeTests` Swift Testing suite instead of brittle method-level selectors.
  - Hosted simulator tests receive smoke configuration through a short-lived `/tmp/salemx-direct-call-backend-smoke.env` file that the script removes on exit.
  - Default runs skip the HTTP smoke tests when the smoke file/env is absent or stale.
  - Env-gated local smoke run proved both production token client and capability provider can call the local FastAPI fake backend over HTTP.
  - Output remains redacted and production direct calls remain disabled.
- iOS internal production native direct-call activeAudio proof is recorded:
  - The proof used only the DEBUG/integration internal command path.
  - The proof used the local fake backend and local LiveKit dev server.
  - B `production-start-listener` succeeded.
  - A `production-start-outgoing` succeeded.
  - B received the production invite and entered `incomingRinging`.
  - B `production-accept` succeeded.
  - B emitted an answer and answer send succeeded.
  - A received the answer.
  - A and B both reached `productionSessionState=activeAudio`.
  - A and B both reported `productionEncryptionState=ready`.
  - A and B both reported `productionMediaConnectAttempted=true`.
  - A and B both reported `productionLiveKitClientConnectAttempted=true`.
  - A and B both reported `productionMediaFailureReason=none`.
  - No visible UI, Element Call route, CallKit, push, or global production activation changed.
- Internal production hangup command is complete:
  - `UITestsSignalling` supports a DEBUG/integration-only `nativeDirectCallProductionHangup` request and redacted result.
  - The runner exposes `production-hangup A|B` and aliases for the internal production command lane.
  - The command routes through AppCoordinator, UserSessionFlowCoordinator, ChatsTabFlowCoordinator, and the active RoomFlowCoordinator.
  - The command requires a retained production owner and an active non-terminal production session.
  - On success, it sends the production terminal signal through the production owner/controller path, then performs immediate terminal cleanup for the call.
  - Production status now reports the last terminal reason plus media disconnect and cleanup attempt booleans.
  - Media engines mark disconnect and cleanup attempts in redacted diagnostics.
  - The diagnostic owner remains separate and unaffected by the production hangup command tests.
  - No visible UI, Element Call route, RoomScreen call presentation, ElementCallService, CallKit, push, or global production activation changed.
- iOS internal production native direct-call full lifecycle proof is recorded:
  - The proof used only the DEBUG/integration internal command path.
  - The proof used the local fake backend and local LiveKit dev server.
  - B `production-start-listener` succeeded.
  - A `production-start-outgoing` succeeded.
  - B reached `incomingRinging`.
  - B `production-accept` succeeded.
  - A and B both reached `productionSessionState=activeAudio`.
  - A `production-hangup` succeeded with `outcome=hungUp`.
  - A emitted the hangup event and the send succeeded.
  - A cleared the active production session and returned to idle.
  - B received `directCallHangup`.
  - B cleared the active production session and returned to idle.
  - A and B both reported `productionMediaDisconnectAttempted=true`.
  - A and B both reported `productionMediaCleanupAttempted=true`.
  - A and B both reported `productionMediaFailureReason=none`.
  - No visible UI, Element Call route, CallKit, push, or global production activation changed.
- Internal native call room control panel skeleton is complete:
  - The panel is hidden by default and visible only in DEBUG/internal room context when `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`.
  - It uses a room-scoped provider that calls the existing production dry-run/status, listener, start, accept, and hangup methods.
  - The panel renders only redacted status fields and does not expose tokens, keys, SDK envelope contents, raw Matrix content, raw room IDs, or peer IDs.
  - It remains separate from the existing Element Call route, `RoomScreenViewModel.displayCall`, `RoomScreenCoordinator.presentCallScreen`, and `ElementCallService`.
  - No CallKit, push, global production activation, or public product UI activation was added.
- Internal native call panel layout/action polish is complete:
  - The panel now uses a compact two-row layout instead of one clipping-prone control row.
  - Action enablement is explicit: refresh/status is always safe, arm listener is available before listener setup or when idle, start depends on readiness, accept is limited to incoming ringing, and hangup is limited to ringing/connecting/active call states.
  - Rendering the panel remains side-effect-free and does not start listeners, send Matrix events, request media credentials, or connect media.
  - Existing Element Call phone/video buttons and routing remain unchanged.
- Internal native call panel runtime proof is recorded:
  - Without `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED`, the internal native call panel was hidden.
  - With `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`, the panel appeared in both open encrypted r1/r2 DMs.
  - Panel status output was redacted: no credential values or keys, JWTs, raw Matrix content, raw room IDs, or peer IDs were shown.
  - The runner fallback was used for actions because synthetic UI taps were unavailable in the runtime environment.
  - The runner exercised the same room-scoped production methods as the panel: listener, start, accept, and hangup.
  - Before hangup, A and B reached `activeAudio`, encryption was ready, media connect was attempted, LiveKit connect was attempted, and media failure was `none`.
  - After `production-hangup A`, A and B returned to idle with no active session.
  - A sent hangup successfully and B received `directCallHangup`.
  - Media disconnect and cleanup were attempted on both sides.
  - A and B reported media failure `none`.
  - Minor UI issue found: the control row is horizontally clipped at the trailing edge, so later controls require horizontal scrolling.
  - Scope remained DEBUG/internal only with no public UI activation, Element Call route changes, CallKit/push, or global production activation.
- Internal native call panel visual/action proof is recorded:
  - With `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`, the polished panel appeared in both A/B encrypted DM rooms.
  - The two-row layout was readable and no longer clipped.
  - Status text remained redacted: no credential values or keys, raw Matrix content, raw room IDs, or peer IDs.
  - Existing Element Call phone/video buttons remained unchanged.
  - Initial visual state was `notRefreshed`, with only Refresh enabled.
  - Runner dry-run confirmed readiness with `wouldStart=true`, `enabled=true`, and peer trust ready.
  - Runner fallback was used because synthetic UI taps were unavailable.
  - The fallback exercised the same room-scoped production methods as the panel: B listener, A start, B incoming, B accept, A/B active audio, A hangup, and A/B idle.
  - Media connected on both sides.
  - Cleanup and disconnect were attempted after hangup.
  - No code changes were needed during the runtime proof.
  - Scope remained DEBUG/internal only with no public UI activation, Element Call route changes, CallKit/push, or global production activation.
- Private native call room card seam is complete:
  - A product-shaped room card state model exists for hidden, unavailable, can start, outgoing ringing, incoming ringing, connecting, active audio, failed, and ended states.
  - User-safe unavailable/failure reasons cover native calls unavailable, server unsupported, room not encrypted, non-1:1 room, unverified device, peer trust unavailable, call service unavailable, LiveKit network failure, timeout, and unknown.
  - A typed room-card action model exists for refresh status, start audio, accept, decline, and hang up.
  - The room card uses a narrow room-scoped provider/handler seam over the already proven production room methods.
  - The card is hidden by default and appears only behind the separate DEBUG/integration product UI gate `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
  - The existing DEBUG/internal diagnostic panel remains gated separately by `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`.
  - Existing Element Call phone/video buttons, `displayCall`, `presentCallScreen`, and `ElementCallService` remain untouched.
- Private native call room card runtime proof is recorded:
  - With `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`, the private native call card appeared in A/B encrypted DM rooms.
  - Without `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, the card was hidden.
  - `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED` was not set, and the diagnostic panel did not appear.
  - The product card appeared independently through the product UI gate.
  - Existing Element Call phone/video buttons stayed visible and unchanged.
  - Card status and runner output were user-safe/redacted: no credential values, JWTs, keys, raw Matrix content, raw room IDs, or peer IDs were printed.
  - Runner fallback was used because synthetic UI taps were unavailable.
  - The underlying room-scoped production lifecycle succeeded: B listener, A outgoing, B incoming ringing, B accept, A/B active audio, A hangup, and A/B idle.
  - Before hangup, A and B reported active audio, encryption ready, media connect attempted, LiveKit connect attempted, and media failure `none`.
  - After hangup, A and B reported no active session, idle state, media disconnect attempted, media cleanup attempted, and media failure `none`.
  - A sent hangup successfully and B received `directCallHangup`.
  - No new visual clipping was observed.
  - Current UI nuance: the card initially shows `unavailable(nativeCallsUnavailable)` until refreshed, and live visual refresh was not verified without synthetic taps.
  - No code changes were needed during the runtime proof.
- Private native call card refresh and action delivery polish is complete:
  - The card performs a safe read-only appearance refresh so the initial state can become `canStart` without manual Refresh.
  - Passive follow-up refreshes do not start listeners, send Matrix events, connect media, request media credentials, or disable available actions.
  - Card actions report a redacted pending/action outcome path once the ViewModel receives the tap.
  - Stable accessibility identifiers exist for the private native call card actions.
  - The two-client runner now forwards `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED` into simulator launch as `SIMCTL_CHILD_NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, separate from the internal diagnostic panel gate.
- Private native call card manual lifecycle proof is recorded:
  - The private native call card was visible with `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
  - B production listener was armed.
  - Manual UI Start audio from A caused B to reach `incomingRinging`.
  - Manual UI Accept from B caused A and B to reach `activeAudio`.
  - Manual UI Hang up from A caused A and B to return to idle.
  - A emitted hangup and the send succeeded.
  - B received `directCallHangup`.
  - A and B reported production media connect attempted, LiveKit client connect attempted, and production media failure `none`.
  - A and B reported media disconnect and cleanup attempted after hangup.
  - Existing Element Call buttons remained untouched.
  - Scope remained private/internal product UI gate only, with no CallKit, push, or global production activation.
- Private native call card repeated-call and backend-off edge proof is recorded:
  - First manual private-card cycle succeeded: A Start audio, B Accept, A/B `activeAudio`, A Hang up, A/B idle.
  - Second manual private-card cycle succeeded: A Start audio again, B Accept again, A/B `activeAudio` again, B Hang up, A/B idle.
  - No stale active session or stale terminal state blocked the second call.
  - Production listener and owner remained safe across cycles.
  - Media disconnect and cleanup were attempted after hangups.
  - Production media failure remained `none` during successful cycles.
  - Reverse-direction signalling also worked: B started a call, A reached `incomingRinging`, A accepted and sent answer, and B received `directCallAnswer`.
  - With the local token backend unavailable during the reverse-direction media step, the media/token path failed closed with the user-safe `tokenHTTPUnavailable` reason.
  - A and B returned to idle with `connectingFailed`, media disconnect/cleanup attempted, and no active session remaining.
  - No raw token, JWT, key, endpoint, room ID, peer ID, or raw Matrix content was printed.
  - Scope remained private/internal product UI gate only, with no Element Call route change, CallKit, push, or global production activation.
- Private native call card backend-recovery and LiveKit-off edge proof is recorded:
  - Backend-off behavior failed closed with the user-safe `tokenHTTPUnavailable` reason.
  - A and B returned idle with no active session, and media disconnect/cleanup was attempted.
  - After the local fake backend was restarted, private-card Start/Accept recovered to `activeAudio` on A and B with encryption ready.
  - Hangup returned A and B to idle.
  - LiveKit-off behavior failed closed with the user-safe `liveKitNetworkFailed` reason.
  - A and B again returned idle with no stale active session, and media disconnect/cleanup was attempted.
  - After LiveKit was restarted, private-card Start/Accept recovered to `activeAudio` on A and B.
  - Final hangup succeeded: A emitted hangup and the send succeeded, B received `directCallHangup`, and both sides returned idle with cleanup/disconnect attempted.
  - No new UI issue was observed, and the existing Element Call route remained untouched.
  - Diagnostic nuance: `productionMediaFailureReason` can remain stale after recovery. `tokenHTTPUnavailable` remained visible during the backend-recovered active call, and `liveKitNetworkFailed` remained visible after the LiveKit-recovered active call. Treat this as a diagnostic/status cleanup issue, not a runtime call blocker.
- Stale media failure cleanup runtime proof is recorded:
  - Backend-off with the local fake backend stopped failed closed with the user-safe `tokenHTTPUnavailable` reason.
  - A and B returned idle with no active session, and media disconnect/cleanup was attempted.
  - After the local fake backend was restarted, private-card Start/Accept recovered to `activeAudio` on A and B.
  - `productionMediaFailureReason=none` on both sides, proving stale `tokenHTTPUnavailable` was cleared by the later successful media connection.
  - LiveKit-off with the backend still running failed closed with the user-safe `liveKitNetworkFailed` reason.
  - A and B returned idle with no active session, and media disconnect/cleanup was attempted.
  - After LiveKit was restarted, private-card Start/Accept recovered to `activeAudio` on A and B.
  - `productionMediaFailureReason=none` on both sides, proving stale `liveKitNetworkFailed` was cleared by the later successful media connection.
  - Final hangup succeeded: A returned idle after emitting hangup and sending successfully; B returned idle after receiving `directCallHangup`.
  - Cleanup and disconnect were attempted on both sides.
  - No UI issue was observed, no code changes were needed during the runtime proof, and the worktree was clean.
- Private native call card decline/cancel/retry/dismiss UX is complete and runtime-proven:
  - The private card supports explicit decline incoming, cancel outgoing, retry, and dismiss error actions.
  - Incoming ringing shows Accept and Decline; outgoing ringing shows Cancel; failed states now show Retry and Dismiss instead of a broad disabled action row.
  - Decline incoming proof passed: B received `incomingRinging`, B tapped Decline, B emitted reject and the send succeeded, A received `directCallReject`, and A/B returned idle with no active session.
  - Cancel outgoing proof passed: A started outgoing, A tapped Cancel before B accepted, A emitted cancel and the send succeeded, B received `directCallCancel`, and A/B returned idle with no active session.
  - Retry after `failed(callServiceUnavailable)` did not auto-start a call; A/B remained idle with no active session.
  - Dismiss cleared the local displayed error/outcome, returned the card to Ready to call, and showed the redacted last action as `dismissError:dismissed`.
  - `productionMediaFailureReason` remained `none` for decline/cancel proof paths.
  - Existing Element Call phone/video buttons remained untouched.
  - No CallKit, push, global production activation, or sensitive credential/key/Matrix-content logging was introduced.
- Private native call card rapid terminal-action proof is recorded:
  - 2.20C added a post-terminal Start Audio suppression after Hang up, Cancel, and Decline so a rapid second tap cannot immediately restart a call after the card returns to `canStart`.
  - Rapid Hang up passed: A/B returned idle with no active session, A emitted hangup, B received `directCallHangup`, cleanup/disconnect was attempted, and `productionMediaFailureReason=none`.
  - Rapid Cancel passed: A/B returned idle with no active session, A emitted cancel, B received `directCallCancel`, and `productionMediaFailureReason=none`.
  - Rapid Decline passed after relaunching B onto the current 2.20C build: B emitted reject, A received `directCallReject`, A/B returned idle with no active session, and `productionMediaFailureReason=none`.
  - No accidental `outgoingRinging`/`incomingRinging` restart occurred on the current build.
  - The earlier failed Decline rerun was explained by B still running the pre-fix app.
  - Existing Element Call route remained untouched.
  - No CallKit, push, or global production activation was introduced.
  - No code changes were needed during the runtime proof and the worktree remained clean.
  - Setup nuance: after relaunch, B needed the encrypted r1/r2 DM reopened and the receive listener armed.
- Private native call card timeout runtime proof is recorded:
  - The proof used the real configured ringing timeout of 45 seconds plus a small buffer.
  - No timeout hook and no code changes were used, and the worktree stayed clean.
  - Outgoing timeout passed: A started outgoing through the production room-scoped path, A entered `outgoingRinging`, B entered `incomingRinging`, and no accept/decline/cancel/hangup was sent.
  - After outgoing timeout, A returned idle with no active session, emitted `timeout`, and the send succeeded.
  - A reported terminal reason `outgoingTimeout`; B returned idle with no active session after receiving `directCallTimeout` and reported terminal reason `incomingTimeout`.
  - Reverse-direction timeout passed: B entered `outgoingRinging`, A entered `incomingRinging`, then B returned idle after emitting `timeout` with terminal reason `outgoingTimeout`.
  - A returned idle with no active session, reported terminal reason `incomingTimeout`, and reported no receive failure.
  - Media connect was not attempted for either timeout proof, and `productionMediaFailureReason` remained `none`.
  - Outgoing and incoming timers are both 45 seconds, so caller/callee timeout emission can race; runtime still proved both sides clear safely with user-safe timeout terminal reasons.
  - Existing Element Call route remained untouched, and no CallKit, push, or global production activation was introduced.
- Private native call UI typed snapshot/reducer cleanup is complete:
  - The private native call card now maps production status through typed redacted snapshot/reducer seams instead of relying on scattered string comparisons.
  - User-safe reason mapping is centralized for activation, trust, media, backend, and terminal reasons.
  - Current call session state remains separate from local card action/dismissal state.
  - Rendering/status refresh remains side-effect-free.
  - Existing Element Call phone/video buttons, `displayCall`, `presentCallScreen`, and `ElementCallService` remain untouched.
- Native call card reducer regression proof is recorded:
  - After the typed reducer cleanup, a runtime regression was found where idle state with retained `tokenHTTPUnavailable` incorrectly showed Ready/canStart instead of `failed(callServiceUnavailable)`.
  - Fix commit `8cdae55d4` restores failed-state mapping for idle/no active session plus retained backend/media failure diagnostics.
  - Runtime recheck confirmed the failed backend/token state shows Retry and Dismiss.
  - Retry remains read-only and does not auto-start a call.
  - Dismiss clears only the local displayed error/outcome.
  - The card returns to the safe Ready to call state after Dismiss.
  - Existing Element Call route remained untouched.
  - No CallKit, push, or global production activation was introduced.
- Private native call relaunch/listener lifecycle runtime proof is recorded:
  - Baseline lifecycle status included `productionListenerAvailable=true`, `productionRoomAttached=true`, and `productionSessionRestorationSupported=false`.
  - A and B had no owner, listener, active session, stale media failure, or raw room/peer IDs in output.
  - ActiveAudio relaunch proof passed: A/B reached `activeAudio` with encryption ready and media failure `none`, then after app relaunch and reopening the encrypted DM no stale `activeAudio` was restored.
  - After activeAudio relaunch, A/B reported `productionHasActiveSession=false`, `productionSessionRestorationSupported=false`, and a safe fail-closed state.
  - Ringing relaunch proof passed: before relaunch A was `outgoingRinging`, B was `incomingRinging`, media connect was not attempted, and media failure was `none`.
  - After ringing relaunch and reopening the DM, no stale outgoing/incoming session was restored; A/B reported `productionHasActiveSession=false`, `productionSessionState=unavailable`, and media failure `none`.
  - Room dismiss/reopen proof passed: B listener/owner was armed and idle, then after leaving and reopening the DM B owner/listener reset.
  - Final A/B status reported `productionListenerAvailable=true`, `productionRoomAttached=true`, `productionSessionRestorationSupported=false`, `productionHasActiveSession=false`, `productionSessionState=unavailable`, and `productionMediaFailureReason=none`.
  - No UI issue was observed, the existing Element Call route remained untouched, no CallKit/push/video/global production activation was introduced, no code changes were needed, and the worktree stayed clean.
- Private native audio engineering dogfood runbook is recorded:
  - `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md` defines the strict controlled engineering dogfood scope and guardrails.
  - Scope is DEBUG/integration only, private native card only, open encrypted direct 1:1 rooms only, foreground only, verified/trusted peers only, and local fake backend plus local LiveKit or a hardened staging equivalent.
  - Required gates are documented: `IS_RUNNING_INTEGRATION_TESTS=1`, `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`, `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`, `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`, and `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=...`.
  - Allowed flows, known limitations, fail-closed behavior, redaction checklist, rollback steps, explicit non-goals, staging blockers, success criteria, and stop conditions are documented.
  - The runbook keeps Element Call buttons unchanged and keeps CallKit, push, video, public rollout, Element Call replacement, `AllDevices` fallback, and global production activation out of scope.
- Listener availability status polish and runtime diagnostics proof are recorded:
  - 2.23C added typed listener/restoration availability status for the private native call card, including listener-not-armed, ready-to-receive, open-room-required, and restoration-unsupported states.
  - Fresh runtime relaunch showed an attached room with `productionListenerAvailable=true`, `productionOwnerAvailable=false`, and `productionListenerStarted=false`, mapping to listener-not-armed.
  - The same proof showed no side effects from passive status/rendering: no Matrix send, no media connect, no LiveKit connect, and no active session.
  - A receiver with `productionRoomAttached=false` mapped to open-room-required until room reattachment.
  - Explicit listener arm succeeded; A/B then reported owner available, listener available/started, room attached, restoration unsupported, no active session, and media failure `none`.
  - Incoming after listener arm still worked: A started outgoing, B reached `incomingRinging`, B rejected/declined, A received `directCallReject`, and A/B returned idle with no active session or media failure.
  - Final diagnostics kept listener available/started, cleanup/disconnect attempted, and media failure `none`.
  - Limitations: manual visual card text was not verified from the shell, and the literal leave-DM-to-chat-list/reopen gesture was not performed in this proof.
  - Existing Element Call route remained untouched, no CallKit/push/video/global production activation was introduced, no code changes were needed during the runtime proof, and the worktree stayed clean.
- Backend staging guardrails and Redis storage skeleton are complete:
  - 2.24B added explicit service modes, staging fail-closed preflight, fake-mode blocking in staging, and redacted health/readiness.
  - 2.24C added allocation store guardrails and blocked memory allocation in staging unless a test-only override is set.
  - 2.24D added rate-limit guardrails and blocked memory rate limiting in staging unless a test-only override is set.
  - 2.24E documented and ran the full FastAPI route-test environment.
  - 2.24G added HMAC-derived Redis allocation keys, Redis allocation create-or-reuse with `SET NX EX`, Redis rate limiting through atomic Lua check-and-record, and Redis readiness wiring.
- Redis local integration smoke is recorded:
  - A disposable `redis:7-alpine` container was started on local port `6380` and cleaned up after the smoke.
  - Redacted staging readiness returned `ready=true`, `reason=ok`, Redis allocation/rate-limit configured/shared/connected booleans true, and storage-key configured true.
  - Allocation create/reuse returned `200`, repeated requests reused the same allocation and LiveKit room, and caller/callee directions converged on the same LiveKit room.
  - Rate limiting returned `200` under limit, then `429` with `M_DIRECT_CALL_RATE_LIMITED` and `retry_after_ms` over limit, with no second token issued.
  - Redis keys and readiness output were checked for redaction and did not contain raw room IDs, peer IDs, user IDs, device IDs, bearer tokens, participant tokens, JWTs, Synapse admin tokens, or LiveKit API secrets.
  - Stopping Redis failed closed with `M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE` before token issuance, and the allocation-specific path failed closed with `M_DIRECT_CALL_ALLOCATION_FAILED` before token issuance.
  - This is a local Redis smoke only; deployed staging Redis smoke, real Synapse validation smoke, and LiveKit join smoke remain required before staging dogfood.
- Staging Synapse validation smoke harness is prepared:
  - Added an operator-local env template at `server/salemx-call-service/smoke/staging-synapse-smoke.env.example`.
  - Added `server/salemx-call-service/scripts/staging_synapse_smoke.sh` for redacted readiness, positive token, invalid bearer, wrong-device, and optional negative room-fixture checks.
  - The harness prints only HTTP status, errcode, readiness booleans, token response shape booleans, and pass/fail/skip.
  - The harness does not echo request JSON or env values and self-checks the report for known fixture values and token-shaped output before printing.
  - Operator-local smoke env files are ignored by git.
  - The harness does not run automatically and no real staging service was called in the prep phase.
- Staging call service deployment scaffold is prepared:
  - Added `server/salemx-call-service/deploy/staging.env.example` with placeholder-only staging service env values.
  - Added ignored local env coverage for `server/salemx-call-service/deploy/*.env` and `server/salemx-call-service/deploy/*.local`.
  - Added `server/salemx-call-service/scripts/run_staging_call_service_local.sh` to validate staging env guardrails and start `uvicorn` without printing env values.
  - Added `server/salemx-call-service/scripts/check_staging_readiness.sh` to query readiness and print only redacted readiness fields.
  - The deployment scaffold does not include real credentials, does not run automatically, and does not activate any iOS or public/native call route.

## Current Gate

- Controlled engineering dogfood pilot may continue on staging under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, including the product-card-only happy path, repeated-call split-brain regression proof, 2.27F controlled matrix rerun, 2.28B/2.28C pilot sessions, the 2.32C eligibility status soak, the 2.33D timeout cleanup proof, and the 2.33E engineering expansion pilot session 1 rerun.
- A narrow engineering expansion may continue under the 2.33B runbook, 2.34A soak plan, and 2.35B operations handoff: up to 4 named engineering operators, up to 8 named devices, predeclared pairs only, one active 1:1 native audio call at a time, named session ownership, named redaction review, and redacted reporting only.
- Soak progress: sessions 1, 2, and 3 of 3 are clean; the planned engineering expansion soak is complete, the post-soak readiness review allowed continued engineering expansion, the operations handoff is recorded, and the first operator-owned session is clean.
- Per-session Codex supervision is no longer required for clean engineering sessions, but Codex/engineering review remains required for bugs, stop criteria, scope changes, rollout changes, non-engineering access, or config changes.
- Server-backed internal pilot activation implementation is still default-off:
  - The iOS stack now has a native-audio-specific internal pilot rollout source that is disabled by default and DEBUG/integration-gated when environment-backed.
  - The concrete server-backed activation provider can return `activationAllowed` only when product UI, internal pilot rollout, backend eligibility, room eligibility, trust readiness, dependency readiness, and idle session state all pass.
  - The provider is not enabled for non-engineering runtime by default, and engineering private dogfood remains separate under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
  - 2.36G runtime proof confirmed product UI, eligibility status, and production start still do not activate native audio without private dogfood, while the private engineering dogfood path still reaches active audio.
  - 2.36I adds dry-run/status-only wiring for the provider behind `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ACTIVATION_DRY_RUN_ENABLED=1`; this can report a redacted decision but is not used to enable Start or Accept.
  - 2.36J runtime proof confirmed product UI, eligibility status, and internal pilot activation dry-run gates do not activate native audio without private dogfood.
  - 2.36J also confirmed product UI, eligibility status, production start, and dry-run gates together remain blocked without private dogfood, with no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
  - With private dogfood restored, A -> B reached `activeAudio`, then hangup returned A/B to `idle` with no active session and media failure `none`.
  - 2.36K adds direct runner observability for the internal-pilot dry-run enum/boolean fields in redacted `production-status` output. 2.36L proved those fields are visible at runtime and remain observability-only.
- Engineering-only internal pilot activation proof wiring is added:
  - `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED=1` can now be used with the existing DEBUG/integration proof gates to let the server-backed internal pilot activation provider make Start/Accept available for engineering proof runs only.
  - The proof path requires product UI, eligibility status, internal pilot dry-run, internal pilot rollout, production start, and staging token base URL gates. The main proof must leave `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset.
  - The provider must return `activationAllowed` from all gates: product UI, internal rollout, backend eligibility, encrypted direct 1:1 room, trust readiness, dependency readiness, and no stale active session.
  - Backend `/eligibility` and the token endpoint remain final enforcement; token rejection still blocks and invalidates cached eligibility before token/media/LiveKit setup.
  - Private engineering dogfood remains separate under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` and does not depend on the internal pilot rollout gate.
  - Default/Release remain fail-closed, product UI alone remains insufficient, eligibility status alone remains insufficient, backend eligible alone remains insufficient, and `directOneToOneCallsEnabled` remains unrelated.
  - This is not approval for non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, or global activation.
- Engineering-only server-backed internal pilot activation runtime proof passed for the allowlisted A/B path:
  - Commit `5fc30fe6a` wires the HTTP native audio internal pilot eligibility provider through `AppCoordinator`, `UserSessionFlowCoordinator`, `ChatsTabFlowCoordinator`, and `RoomFlowCoordinator`.
  - Default and Release behavior remain fail-closed.
  - The HTTP provider is selected only under the explicit DEBUG/integration proof gates, and private engineering dogfood remains separate and unchanged.
  - With `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset, internal rollout enabled, and backend allowlisted A/B, runner status reported internal-pilot `activationAllowed`.
  - A Start -> B Accept reached `activeAudio`; hangup returned A/B to `idle` with no active session and media failure `none`.
  - No raw identifiers, tokens, JWTs, secrets, LiveKit room names, Matrix event bodies, Redis credentials, or full request/response bodies were printed.
  - Element Call route stayed untouched, and no CallKit, push, video, global production activation, broad internal rollout, or non-engineering internal dogfood was enabled.
  - Validation for the code commit passed: SwiftFormat, SwiftLint, targeted tests 176/176, Release build with existing warnings only, `git diff --check`, and changed-line forbidden scan.
- Internal pilot trigger dry-run observability alignment passed:
  - Commit `f930f8f7a` aligns `production-trigger-dry-run` with the same redacted activation decision path used by `production-start-outgoing`.
  - Runner output now includes `activationSource`, `internalPilotActivationDecision`, and `internalPilotActivationReason`.
  - Runner forwards `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED` for explicit DEBUG/integration proof runs.
  - Trigger dry-run remains side-effect-free: no Matrix send, token request, allocation, LiveKit room pre-create, media connect, LiveKit client connect, outgoing call, or active session.
  - Private dogfood compatibility was rechecked and still reached `activeAudio`, then returned A/B to `idle` with no active session and media failure `none`.
  - Validation passed: SwiftFormat, SwiftLint, targeted native-call tests 179/179, Release build with existing warnings only, runner `bash -n`, `git diff --check`, and changed-line forbidden scan.
- Engineering-only internal pilot activation soak is complete for the required runtime matrix:
  - 2.37C and 2.37D passed as the first two clean soak sessions.
  - 2.37E session 3 was paused after a repeated-call split state; commit `4ea9490ec` fixed the caller media setup failure terminal path.
  - 2.37F reran session 3 after the fix with private dogfood unset, internal rollout enabled, and backend allowlisted engineering A/B.
  - Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, no stale active session, and Element Call fallback visible.
  - Trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
  - A -> B, B -> A, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, post-listener recovery, and Element Call fallback rows passed.
  - The repeated-call regression guard observed no `tokenBackendRejected`, no `connectingFailed`, and no split state.
  - Final A/B state was idle/no active session with media failure `none`; no rollback was used, no stop criteria triggered, no runtime bug was observed, and no redaction issue was found.
  - Token final-authority was not rerun in 2.37F because sessions 1 and 2 already covered the temporary ineligible fixture path.
- Internal pilot operational readiness and kill-switch plan is recorded:
  - 2.38A documents the decision that the server-backed activation path is stable for engineering accounts but does not approve non-engineering internal dogfood.
  - Required owners are pilot owner, backend owner, allowlist owner, redaction/report reviewer, rollback operator, and incident decision owner.
  - The kill-switch model covers app-side internal rollout disablement, backend eligibility disablement, allowlist clearing/removal, call-service restart when config-based, client relaunch, idle/no-active-session verification, `internalPilotActivationDecision` no-longer-allowed verification, Element Call fallback verification, and secret rotation on suspected leakage.
  - Allowlist operations require named users only, named devices only when supported, no wildcard/global entries, explicit change approval, redacted audit trail, and removal procedure.
  - Monitoring remains limited to readiness booleans, eligibility state/reason, activation source/decision/reason, production session/media/terminal enums, cleanup/disconnect booleans, and pass/fail/not-run.
  - Non-engineering internal dogfood remains blocked until this plan is implemented and proven by an operational proof/kill-switch rehearsal.
- Internal pilot operational proof and kill-switch rehearsal passed:
  - Enabled-state proof used the server-backed internal pilot activation path with private dogfood unset, internal rollout enabled, backend allowlisted engineering A/B, readiness `200`, `ready=true`, `reason=ok`, Redis connected, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, and no stale active session.
  - Trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
  - Positive proof reached `activeAudio`; hangup returned A/B to idle/no active session with media failure `none`.
  - App-side kill switch passed: removing `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED` blocked dry-run/start with `appRolloutDisabled` / `rolloutDisabled` and created no Matrix send, token/media path, LiveKit connect, or active session.
  - Backend allowlist kill switch passed: restarting the local staging call-service with eligibility enabled and an empty allowlist made activation unavailable with safe reason `serviceUnavailable`; diagnostic start blocked before media/LiveKit and A/B remained idle/no active session.
  - Restore proof passed after reopening the correct encrypted r1/r2 DM and restoring trust: backend readiness and allowlist returned to ready/configured, A/B dry-run returned `activationAllowed`, A Start -> B Accept reached `activeAudio`, and hangup returned A/B idle/no active session with media failure `none`.
  - Element Call phone/video fallback controls were visually confirmed visible and unchanged; the private native audio card remained separate.
  - No code changed and no redaction issue was observed.
- Redacted token/LiveKit failure observability is available:
  - Commit `d321b8f7b` adds safe token/backend and LiveKit setup diagnostics to backend responses, iOS media status, and runner `production-status` output.
  - The runner now redacts exact A/B simulator identifiers, generic UUID-shaped simulator identifiers, and `udid=<value>` fields before printing command output.
  - Runtime proof showed a positive A -> B call reaching `activeAudio`, with token diagnostics `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, `liveKitRoomPrecreateAttempted=true`, LiveKit connect attempted, LiveKit failure `none`, and media failure `none`.
  - A controlled negative token diagnostic against a temporary current-code local service returned safe fields only: `tokenStatus=401`, `tokenErrcode=M_UNKNOWN_TOKEN`, `tokenReason=authRejected`, and `tokenIssued=false`.
- Window 2 failure retry diagnostics passed without reproducing the failure:
  - 2.39N reran only the minimal failed paths, not a new non-engineering pilot window.
  - Preflight was green: backend readiness `ready=true`, `reason=ok`, Redis/storage/LiveKit/eligibility/allowlist configured, A/B trust ready, approved encrypted 1:1 DM open, A/B idle/no active session, and internal pilot activation `activationAllowed`.
  - A -> B reached `activeAudio`, reported `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, `liveKitRoomPrecreateAttempted=true`, LiveKit connect attempted, LiveKit failure `none`, and media failure `none`; hangup returned A/B idle/no active session.
  - B -> A reached `activeAudio` with the same safe token/LiveKit success classification; hangup returned A/B idle/no active session.
  - The original window 2 `tokenBackendRejected` / `liveKitNetworkFailed` failure did not reproduce, no split state appeared, no redaction issue was observed, and no app/backend code changed during the retry.
  - Root cause remains unproven; the evidence supports an environment-sensitive or transient failure rather than a confirmed app/backend defect.
  - Further non-engineering pilot execution remains paused until a separate approval review decides whether to run exactly one supervised recovery window.
- Supervised non-engineering recovery pilot window passed:
  - 2.39O approved exactly one supervised recovery window after the 2.39K failure and 2.39N clean retry diagnostics.
  - 2.39P ran a shorter recovery matrix only: A -> B happy path, B -> A reverse path, one repeated A -> B call, final idle/no active session check, and Element Call fallback visibility check.
  - Required gates were present, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` and `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` remained unset, backend readiness was `ready=true` / `reason=ok`, Redis/storage/LiveKit/eligibility/allowlist were configured, A/B trust was ready, the approved encrypted 1:1 DM was open, A/B were idle/no active session, and internal pilot activation was `activationAllowed`.
  - All three call rows reached `activeAudio`; each reported `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, `liveKitRoomPrecreateAttempted=true`, LiveKit connect attempted, `productionLiveKitFailureReason=none`, and `productionMediaFailureReason=none`.
  - Hangup returned A/B to idle/no active session after each row, with cleanup/disconnect attempted.
  - The 2.39K failure did not reproduce: no `tokenBackendRejected`, no `liveKitNetworkFailed`, no split state, no stale active session, and no redaction issue were observed.
  - Element Call fallback controls were visually confirmed visible and unchanged; the private native audio card remained separate.
  - No app/backend code changed during the recovery window. This result does not approve additional non-engineering windows, participant/device expansion, broad internal rollout, production/public rollout, CallKit, push/background incoming, missed-call UX, video, session restoration, Element Call replacement, or global activation.
- Foreground limitation UX polish is implemented:
  - The private native audio card now shows explicit, user-facing copy that native audio works only while the encrypted direct chat stays open.
  - The copy states there are no background incoming calls, no system incoming call screen, and no missed-call alerts yet, and keeps Element Call as the fallback.
  - Listener/open-room, trust, participant eligibility, service unavailable, timeout, cancelled, and safely failed states remain non-technical and do not mention backend, token, LiveKit, raw IDs, request/response details, or internal gates.
  - Accessibility summary now includes the foreground-only limitation for relevant private native audio card states.
  - This is UX polish only. It does not change Start/Accept eligibility, activation gates, Matrix send behavior, token requests, media/LiveKit setup, private dogfood, internal pilot activation, Element Call route, CallKit, push/background incoming, missed-call UX, video, session restoration, broad rollout, or production/public rollout.
- Foreground limitation UX runtime proof passed:
  - A/B were launched with product UI, eligibility status, internal pilot dry-run, internal pilot rollout, production start, and staging token base URL gates set; private dogfood and legacy fake/dry-run gates remained unset.
  - The private native audio card visibly showed the foreground/open-chat limitation copy in the approved encrypted direct 1:1 room on A/B.
  - The visible card copy did not expose backend, token, LiveKit, raw identifier, LiveKit room name, request/response, secret, JWT, or simulator identifier details.
  - Element Call phone/video fallback controls remained visible and unchanged; the private native audio card stayed separate.
  - Rendering/status refresh before the smoke path showed no Matrix send, no token request, no media connect, no LiveKit connect, and no active session on A/B.
  - A short internal-pilot A -> B smoke reached `activeAudio`; hangup/cleanup returned A/B to `idle` with no active session.
  - Smoke diagnostics reported token `200` / `issued`, token issued true, LiveKit room pre-create and connect attempted, LiveKit failure `none`, and media failure `none`.
  - No app/backend code changed during the proof. Additional non-engineering windows, participant/device expansion, broad internal rollout, production/public rollout, unsupervised dogfood, Element Call replacement, CallKit/push/background incoming, missed-call UX, video, session restoration, and global activation remain blocked.
- Native audio incoming-call lifecycle architecture contract is documented:
  - 2.40B records the target lifecycle for moving beyond foreground/open-chat-only native audio: receive a native direct-call invite signal, classify it safely, validate encrypted direct 1:1 room state, validate trusted peer/device state, validate rollout/eligibility/dependencies/idle session state, report to CallKit only after that safe boundary, accept through the native direct-call engine, request the participant token only on accept, connect LiveKit only after token and E2EE readiness, and fail closed on validation/media/terminal failures.
  - The future CallKit boundary must be a native audio adapter/protocol separate from `ElementCallService`, `displayCall`, and `presentCallScreen`. It maps CallKit UUIDs to validated native sessions, handles answer/end/mute/audio session callbacks, and cannot bypass trust, room eligibility, backend eligibility, rollout, or token endpoint enforcement.
  - The future PushKit/APNs boundary requires separate native audio pusher registration, minimal opaque payloads, local fetch/decrypt/classification when needed, and no raw room/user/peer/device IDs, tokens, JWTs, media keys, LiveKit room names, Matrix event bodies, request/response bodies, or credentialed URLs.
  - Signing remains a blocker: Push Notifications capability, APNs `aps-environment`, VoIP background mode, provisioning profiles, Apple Developer account capability, physical-device availability, and push gateway configuration must be proven before PushKit/APNs runtime work. Simulator-only proof is insufficient.
  - The backend must not centralize Matrix trust decisions. Matrix signalling remains the source of call semantics, while the call-service may provide opaque handles, eligibility, readiness, token final enforcement, and redacted observability only.
  - The fail-closed matrix covers malformed/expired push, decrypt/classify failure, invalid room shape, trust not ready, ineligible participants, disabled rollout, dependency failure, existing active session, locked/killed app without safe session state, token rejection, LiveKit failure, CallKit report failure, ambiguous terminal delivery, and unsafe Element Call conflict.
  - This is docs-only. It does not implement CallKit, PushKit, APNs, missed-call UX, background incoming, video, Element Call replacement, rollout expansion, or global activation.
- Apple Developer signing remediation checklist is documented:
  - 2.40D proved the project is not ready for native audio CallKit/PushKit/APNs implementation: the generic `iphoneos` build completed, but local signing identity inspection reported no valid local identities, signature verification reported an untrusted chain, embedded app/NSE/ShareExtension profiles expire on 2026-06-01, and `aps-environment` is missing.
  - The main app already has `UIBackgroundModes` including `audio`, `fetch`, `processing`, and `voip`; App Groups and Keychain Sharing are present for app and extensions.
  - The physical iPhone was visible but offline, so install/runtime proof could not run. Simulator proof remains insufficient for APNs, PushKit token issuance, background wake, or provisioning validation.
  - 2.40E records the required remediation: paid Apple Developer Program team, valid trusted Apple Development certificate, online registered physical iPhone, configured App IDs for main app/NSE/ShareExtension, App Group, Push Notifications for the main app, durable development provisioning profiles, redacted entitlement/profile inspection, and physical-device install proof.
  - NSE filtering entitlement remains absent and should be requested only if a later encrypted NSE-to-CallKit design chooses that path.
  - CallKit, PushKit/APNs, background incoming, missed-call UX, production/public rollout, broad rollout, participant/device expansion, Element Call replacement, video, and global activation remain blocked.
- 2.42D call-service foreground signaling endpoint prototype is implemented:
  - The call-service now exposes an authenticated foreground-only SSE stream at the SalemX direct-call foreground signaling path.
  - The stream emits a ready event and can deliver opaque foreground invite events through an internal fanout service.
  - Invite publishing remains an internal server boundary only; no public client publish route was added.
  - Invite receipt does not issue media credentials, connect media, emit Matrix events, add background incoming behavior, or implement PushKit/APNs.
  - Server diagnostics remain counters, booleans, and safe enums only. Raw routing identifiers, Matrix event content, credentialed URLs, media-session names, auth credential values, and full request/response bodies remain forbidden.
  - Remaining work: validated server invite source, stale invalidation, acknowledgement states, reconnect/resume semantics, shared delivery backing, and iOS disabled-by-default SSE transport integration.
- 2.42E iOS foreground SSE transport client is implemented as a disabled/configured boundary:
  - The app now has an SSE parser and transport that can consume `foreground.ready` and opaque `foreground.call.invite` events from an injected stream.
  - The URLSession-backed stream requires an injected request. No production server URL, auth header, or credential value is hardcoded.
  - The transport is disabled unless explicitly constructed with `isEnabled=true`; the default stream is no-op.
  - Valid invite payloads can feed the existing foreground signaling pipeline and `ForegroundCallInviteHandler`.
  - Ready, malformed, stale, unsupported, and unsafe events fail closed or are ignored; duplicates remain suppressed by the existing handler.
  - Invite receipt still does not request server-issued media credentials, connect media, emit Matrix events, register push values, add background incoming behavior, or alter Element Call routing.
  - Remaining work: runtime lifecycle ownership, safe endpoint configuration, authenticated request construction, reconnect/backoff, fallback coordination, and physical two-device repeat incoming smoke.
- 2.42I supervised foreground SSE smoke now has a DEBUG-only LLDB bridge:
  - `SalemXForegroundSSESmokeDebug` can configure the existing DEBUG SSE runtime owner with supervised placeholder values at runtime and start/stop it on a physical iPhone.
  - The bridge can also start from the Debug app's active `UserSession` via `startWithCurrentSessionURLString:` so the current app credential is inserted into the stream request internally without being printed, logged, written, or returned to LLDB.
  - The bridge emits grep-able `[SSE-SMOKE-DIAG]` one-line diagnostics for configured, started, connected, invite received, invite valid, incoming requested, fallback de-duped, and stopped states.
  - The bridge remains disabled unless explicitly configured in a Debug build. It does not hardcode production endpoints or credential values, request media credentials, connect media from invite receipt, emit Matrix events, add PushKit/APNs/background behavior, or change signing/project settings.
- 2.42I smoke diagnosis update:
  - `sse_connected=true` now requires the server `foreground.ready` SSE event or a valid invite event; starting the URLSession task alone no longer marks the smoke connected.
  - The supervised dev invite response includes redacted active/target subscriber counts and stable account/device hashes so same-session, stale-token, and target-mismatch cases can be distinguished without raw IDs.
  - The supervised smoke must use the same active Matrix bearer session for `/account/whoami`, the iOS SSE stream, and the dev invite POST. Any credential exposed during manual supervision must be treated as compromised and rotated outside docs.
- 2.42I stream-open diagnosis update:
  - The iOS URLSession SSE reader now preserves raw line breaks instead of relying on line iteration, so blank-line SSE delimiters can flush `foreground.ready`.
  - The server stream response now uses `Cache-Control: no-cache` and `X-Accel-Buffering: no`.
  - Redacted stream lifecycle logs cover `stream_auth_ok`, `stream_registered`, `ready_sent`, and `stream_closed` with safe status/count fields only.
- 2.42I DEBUG helper invocation diagnosis update:
  - The active-session LLDB bridge now emits redacted helper-start diagnostics before stream startup: `helper_invoked`, `active_session_available`, `access_token_available`, `device_id_available`, `homeserver_url_available`, `foreground_sse_start_requested`, and `foreground_sse_start_blocked_reason`.
  - The physical smoke must first prove `helper_invoked=true` and `foreground_sse_start_requested=true`; otherwise the failure is the installed Debug build, attached process, foreground app state, or helper invocation, not server fanout or invite parsing.
- Pilot sessions must follow the 2.27A checkpoint, 2.28A operations checklist, and 2.33B expansion runbook in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`, plus the 2.27E split-brain regression guardrail and 2.27F runner-assisted matrix caveat.
- Production rollout and server capability sources remain fail-closed by default.
- Broad internal dogfood, product beta, public rollout, and Element Call replacement remain blocked.
- Non-engineering internal dogfood remains blocked until the 2.29B hardening checklist is satisfied and a separate readiness review explicitly approves it.
- CallKit, push/background incoming, missed calls, video, session restoration, and global production activation remain out of scope.
- Receiver listener behavior remains foreground/open-room scoped.
- Operational ownership, monitoring, redaction checks, and secret-rotation readiness must remain explicit for any longer dogfood window.
- LiveKit-off fail-closed on shared staging was not run because stopping shared staging LiveKit could risk other users.
- No public production activation, Element Call route change, CallKit, or push integration exists yet.

## Next Recommended Phase

`2.48T-Physical2 — one-shot first controlled audio-connect physical attempt`

Goal: build and install the current HEAD Debug app, then perform exactly one operator-approved first controlled audio-connect physical attempt after receiver app session validation, terminal token validation, room validation, one sandbox APNs, green Answer, fresh credentials, enablement, operator approval, and future phase permission. Stop after the first connect result and preserve the no-camera/no-Matrix-event/no-full-flow boundaries.

## Do-Not-Touch Constraints

- No public visible UI activation yet.
- No Element Call route reuse.
- No CallKit or push yet.
- No production feature activation.
- No diagnostic secrets or tokens in production.
- No unencrypted key material in Matrix events.
- No raw JSON, `debugInfo`, `originalJSON`, or `originalJson` receive path.

## 2.44C1 status

APNs persisted-token lookup preflight is complete.

Current safe state:
- PushKit token registration route remains auth-gated
- APNs sandbox send control route is publicly exposed and auth-gated
- persisted PushKit token lookup now returns found
- token remains redacted
- APNs credentials/topic are not configured yet
- APNs provider was not requested
- VoIP push send was not attempted
- production APNs was not attempted
- real PushKit/background callback is not wired
- CallKit report is not wired from PushKit
- media credentials and media connection remain untouched

Current blocker:
- apns_voip_topic_unresolved
- APNs credentials unavailable

## 2.44D status

APNs VoIP sandbox credentials/topic preflight is complete.

Current safe state:
- persisted PushKit token lookup works
- APNs credentials are available in staging
- APNs VoIP topic is resolved
- APNs payload build path works
- APNs provider boundary is reached
- one controlled sandbox send attempt returned sandbox_failure_redacted
- real APNs HTTP/2 provider implementation remains pending
- PushKit background callback is not wired
- CallKit report is not wired from PushKit
- media credentials and media connection remain untouched

## 2.44E status

Real APNs VoIP sandbox HTTP/2 provider implementation is complete.

Current safe state:
- server APNs provider uses HTTP/2 against sandbox APNs
- APNs provider JWT creation is server-side only
- APNs key material, JWTs, auth headers, raw tokens, payloads, and response bodies remain unlogged and undocumented
- APNs send remains explicit and controlled
- production APNs is not attempted
- repeated pushes are not attempted
- physical Debug app upload smoke used lowercase hex token upload
- physical token upload returned http_success / registered
- server-side token persistence returned persisted
- internal token retrieval returned redacted_match
- route safety remains dev invite 404, unauthenticated foreground invite 401, unauthenticated stream 401, token registration 401, and APNs send control 401

Current blocker:
- token-store format inspection is blocked by restricted store permissions and non-interactive sudo policy
- matching Matrix access token for APNs dry-run was unavailable locally
- APNs dry-run was not run
- real APNs sandbox send was not attempted

Still not ready:
- sandbox_success has not been achieved
- physical iPhone VoIP push receipt has not been proven
- PushKit background callback remains unwired
- CallKit report remains unwired from PushKit
- media credentials and media connection remain untouched

## 2.44E1 status

APNs sandbox send verification is blocked before dry-run.

Current safe state:
- `salemx-call-service` active was verified
- public route safety remains dev invite 404, unauthenticated foreground invite 401, unauthenticated stream 401, token registration 401, and APNs send control 401
- APNs dry-run was not run
- real APNs sandbox send was not attempted
- production APNs was not attempted
- repeated pushes were not attempted

Current blocker:
- direct token-store metadata inspection is blocked by restricted permissions and the current sudo policy
- matching Matrix access token for APNs control was unavailable locally

## 2.44E2 status

Operator-assisted APNs sandbox send verification is blocked before dry-run.

Current safe state:
- `salemx-call-service` active was verified
- public route safety remains dev invite 404, unauthenticated foreground invite 401, unauthenticated stream 401, token registration 401, and APNs send control 401
- the hidden terminal token prompt was opened
- APNs dry-run was not run
- real APNs sandbox send was not attempted
- production APNs was not attempted
- repeated pushes were not attempted

Current blocker:
- matching Matrix access token was not provided to the hidden terminal prompt during this run

## 2.44E2 status

Operator-assisted APNs sandbox send verification passed.

Current state:
- real APNs VoIP sandbox HTTP/2 provider is operational
- persisted PushKit token lookup succeeds
- APNs credentials and sandbox topic are valid
- one controlled sandbox VoIP push send returned sandbox_success
- PushKit background receipt/callback proof is next
- PushKit background callback is not wired into call flow yet
- CallKit is not wired from PushKit yet
- media remains untouched

## 2.45C status

CallKit answer action proof is blocked before physical APNs send.

Current safe state:
- DEBUG-only PushKit/CallKit proof code can record a redacted CallKit answer action when `CXAnswerCallAction` is received
- targeted DirectCall tests passed
- fresh physical Debug build installed successfully
- public route safety remains dev invite 404, unauthenticated foreground invite 401, unauthenticated stream 401, token registration 401, and APNs send control 401
- no real sandbox APNs push was sent in this run
- production APNs was not attempted
- repeated pushes were not attempted

Current blockers:
- fresh physical PushKit upload smoke returned `pushkit_token_upload_http_failure`
- authenticated APNs dry-run returned HTTP 401, so the real APNs send was skipped
- CallKit answer action was not physically observed in this run

## 2.45C1 status

PushKit completion ordering fix is implemented and locally validated.

Current safe state:
- controlled sandbox PushKit proof now calls PushKit completion after recording the CallKit report result
- targeted DirectCall tests passed
- fresh physical Debug build installed successfully
- public route safety remains dev invite 404, unauthenticated foreground invite 401, unauthenticated stream 401, token registration 401, and APNs send control 401
- no real sandbox APNs push was sent in this run
- production APNs was not attempted
- repeated pushes were not attempted

Current blocker:
- fresh physical PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- APNs dry-run was not run
- CallKit answer action was not physically observed in this run

## 2.45C physical verification status

Physical CallKit answer action proof passed after authenticated app session refresh.

Verified redacted proof:
- PushKit token upload returned http_success / registered / persisted / redacted_match
- APNs dry-run returned HTTP 200, persisted token lookup found, result dry_run, and no blocker
- exactly one real sandbox APNs send returned HTTP 200, sandbox_success, and no APNs failure reason
- iPhone proof returned `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=sandbox_voip_smoke`, `callkit_report_requested=true`, `callkit_report_result=reported`, `pushkit_completion_called=true`, `callkit_answer_action_received=true`, `callkit_answer_action_fulfilled=true`, and `app_activation_observed=true`
- media credentials, media connection, Matrix events, and real call flow remained false

No production APNs push was attempted. No repeated push was attempted. No raw token, APNs key, JWT, authorization header, Matrix access token, raw payload, private log, or secret-bearing URL was recorded.

## 2.45D status

Controlled in-app activation proof passed after the CallKit answer action.

Verified redacted proof:
- PushKit token upload returned http_success / registered / persisted / redacted_match
- APNs dry-run returned HTTP 200, persisted token lookup found, result dry_run, and no blocker
- exactly one real sandbox APNs send returned HTTP 200, sandbox_success, and no blocker
- iPhone proof returned `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=sandbox_voip_smoke`, `callkit_report_requested=true`, `callkit_report_result=reported`, `pushkit_completion_called=true`, `callkit_answer_action_received=true`, `callkit_answer_action_fulfilled=true`, and `app_activation_observed=true`
- controlled in-app proof returned `controlled_in_app_activation_requested=true`, `controlled_in_app_activation_observed=true`, `controlled_in_app_screen_requested=true`, `controlled_in_app_screen_presented=true`, and `controlled_in_app_screen_source=callkit_answer_sandbox_voip_smoke`
- media credentials, media connection, Matrix events, and real call flow remained false

No production APNs push was attempted. No repeated push was attempted. No raw token, APNs key, JWT, authorization header, Matrix access token, raw payload, private log, or secret-bearing URL was recorded.

## 2.46A status

Real non-dev invite background payload mapping reached the controlled PushKit/CallKit proof chain, but stopped before Answer.

Verified redacted proof:
- Receiver PushKit token upload returned http_success / registered / persisted / redacted_match.
- The authenticated non-dev invite route was used; `dev/invite` was not used and remains disabled.
- The invite route requested one background APNs sandbox push and returned `background_apns_push_result=sandbox_success`, `persisted_pushkit_token_lookup_result=found`, and `blocked_reason=none`.
- iPhone proof returned `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=real_invite_controlled`, `real_invite_payload_mapping_observed=true`, `callkit_report_requested=true`, `callkit_report_result=reported`, and `pushkit_completion_called=true`.
- `callkit_answer_action_received=false`, so controlled in-app activation/screen proof did not run for the real invite payload.
- media credentials, media connection, Matrix events, and real call flow remained false.

Current blocker:
- `blocked_reason=callkit_answer_action_not_observed`

No production APNs push was attempted. No repeated push was attempted. No raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, private log, or secret-bearing URL was recorded.

## 2.46A1 status

Real-invite Answer observation now has a minimal code-side cleanup fix, but physical retry stopped before APNs.

Root cause/fix:
- Investigation found the `sandbox_voip_smoke` and `real_invite_controlled` payloads both use the same controlled synthetic CallKit report path.
- The controlled synthetic CallKit call was recorded as answered but not ended/cleared, allowing stale controlled CallKit state to survive into the next physical smoke.
- The DEBUG-only synthetic proof adapter now ends and clears the controlled synthetic CallKit call after recording Answer proof, and records redacted cleanup status.

Validation:
- SwiftFormat passed on the changed Swift/test files.
- SwiftLint passed on the changed Swift/test files with 0 violations.
- targeted DirectCall tests passed with 37 tests.
- fresh physical Debug build/install passed.

Physical close-out blocker:
- fresh physical PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- real non-dev invite/APNs retry was not run
- production APNs was not attempted
- repeated APNs was not attempted

No media credentials, media connection, Matrix event emission, or full direct-call flow was introduced. No raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, private log, or secret-bearing URL was recorded.

## 2.47A15 — Local background CallKit answerability isolation

Added and physically validated a DEBUG-only local background CallKit-only smoke that schedules the same controlled CallKit proof harness 5 seconds after the Developer Options tap. It writes only to `Documents/salemx-local-background-callkit-proof.txt` and does not use PushKit, APNs, server routes, media credentials, LiveKit, Matrix events, or full call flow.

Physical proof:
- `app_state_at_report=background`
- `local_background_report_result=reported`
- `local_background_first_action_kind=answer`
- `local_background_answer_action_delivered=true`
- `local_background_end_action_delivered=false`
- `blocked_reason=none`

Interpretation:
- local foreground CallKit-only Answer works
- local background CallKit-only Answer works
- background PushKit real-invite still records first action End
- remaining blocker is narrowed to the PushKit callback/report lifecycle, not generic CallKit configuration, delegate retention, or background app state

Safety:
- no APNs was sent for this proof
- no production APNs, no repeated APNs, no real media credentials request, no media connect, no LiveKit join, no Matrix event emission, and no full direct-call flow
- no raw tokens, JWTs, authorization headers, APNs payloads, invite bodies, IDs, call handles, LiveKit URLs, private logs, or secret-bearing URLs were recorded

## 2.47A17 status

APNs accepted the real-invite VoIP push but the SalemX debug receipt proof did not update.

Confirmed:
- PushKit upload smoke was green: upload http_success, registered, persisted, and redacted_match
- server invite/APNs correlation was green: fresh development hex token, matching upload/invite store key, sandbox_success, and blocked_reason=none
- installed app inspection showed bundle `kz.salemx.msg`, team `M639Y9MFR2`, `aps-environment=development`, and `voip` background mode
- app process was alive when inspected

Current blocker:
- dedicated VoIP receipt proof remained `physical_voip_push_received=false`, `pushkit_callback_invoked=false`, and `blocked_reason=voip_push_not_received`
- source inspection showed the existing startup `ElementCallService` owns a `.voIP` `PKPushRegistry`, while the SalemX debug registry is created by manual upload smoke

Diagnostic added:
- DEBUG-only Element Call PushKit detector records redacted SalemX payload interception before the normal Element Call payload parser can reject/log the payload
- if the startup registry receives the SalemX payload, the proof records `element_call_pushkit_registry_intercepted_salemx_payload` without CallKit, media, LiveKit, Matrix events, or full flow

Safety:
- no APNs was sent for this diagnostic change
- no production APNs, repeated APNs, real media credentials request, media connect, LiveKit join, Matrix event emission, or full direct-call flow was introduced
- no raw tokens, JWTs, authorization headers, APNs payloads, invite bodies, IDs, call handles, LiveKit URLs, private logs, or secret-bearing URLs were recorded

## 2.47A physical close-out

The controlled media credentials boundary is physically verified.

Proof:
- one sandbox real non-dev invite/APNs attempt reached the SalemX VoIP receipt path
- `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=real_invite_controlled`, and `real_invite_payload_mapping_observed=true`
- CallKit reported and delivered Answer first: `callkit_report_result=reported`, `callkit_first_action_kind=answer`, `callkit_answer_action_delivered=true`, `answer_action_uuid_matched=true`, and `answer_action_generation_matched=true`
- controlled in-app foreground handoff passed: `controlled_in_app_screen_presented=true`, `foreground_call_state=real_invite_pending_media`, and redacted stable correlation true
- controlled media boundary was reached as planner-only: `media_credentials_boundary_reached=true`, `media_credentials_request_planned=true`, `media_credentials_result=planned_redacted`, token/URL/payload redacted true
- media credentials remained not requested; media connect, LiveKit join, Matrix event emission, and full call flow stayed false
- `blocked_reason=none`

Additional callback-owner proof:
- `element_call_pushkit_callback_invoked=false`
- `element_call_salemx_payload_observed=false`
- the startup detector did not trigger in the successful path; SalemX PushKit receipt triggered and completed

Safety:
- no further APNs was sent after the passing proof
- no production APNs, repeated APNs, real media credentials request, media connect, LiveKit join, Matrix event emission, or full direct-call flow was introduced
- no raw tokens, JWTs, authorization headers, APNs payloads, invite bodies, IDs, call handles, LiveKit URLs, private logs, or secret-bearing URLs were recorded

## 2.46A3 status

Real-invite CallKit report pending state now has a minimal DEBUG-only safety fix.

Ready:
- `real_invite_controlled` now records a final CallKit report result and calls PushKit completion through a one-shot finalizer
- if the controlled CallKit report callback never returns, the proof records `timeout_redacted`, calls PushKit completion, and sets `blocked_reason=callkit_report_completion_timeout_redacted`
- the dedicated VoIP receipt proof remains split from the PushKit upload smoke proof
- SwiftFormat, changed-file SwiftLint, and targeted DirectCall tests passed
- fresh physical Debug build/install passed

Blocked:
- receiver PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- no real non-dev invite/APNs retry was attempted after the fix

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- dev invite remains disabled
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, or call handle recorded

## 2.47A9 status

Local CallKit-only answerability now passes, while the background PushKit real-invite path still delivers End first.

What passed:
- local DEBUG-only CallKit proof reported successfully and delivered Answer first
- local proof returned `local_callkit_only_first_action_kind=answer`, `local_callkit_only_answer_action_delivered=true`, and `blocked_reason=none`
- the same generic audio-only CallKit configuration and delegate path can therefore deliver `CXAnswerCallAction`

Background comparison:
- one authenticated real non-dev invite/APNs attempt returned sandbox success; `dev/invite` was not used
- dedicated iPhone receipt proof returned `physical_voip_push_received=true`, `pushkit_payload_kind=real_invite_controlled`, `callkit_report_result=reported`, `callkit_report_completion_observed=true`, and retained provider/delegate/active UUID proof
- background first action was still `callkit_first_action_kind=end` with `callkit_first_action_after_report_ms_bucket=>2000ms`
- local End request, provider invalidation, report-ended, and controlled timeout before Answer were all false

Current blocker:
- `blocked_reason=system_or_user_end_before_answer`
- this is now a local-vs-background CallKit surface/timing divergence, not a generic CallKit configuration/delegate failure

2.47A media success is still not closed. No production APNs push, repeated push, real media credentials request, media connection, LiveKit join, Matrix event emission, or full call flow was introduced. No raw tokens, JWTs, auth headers, payloads, IDs, call handles, LiveKit URLs/tokens, private logs, or secret-bearing URLs were recorded.

## 2.46A4 status

Real-invite controlled CallKit cleanup ordering is fixed and physically verified.

Root cause/fix:
- the controlled CallKit end event could be recorded before Answer proof, collapsing a reported real-invite call into cleanup before the user Answer action was observed
- the DEBUG-only proof recorder now records cleanup only after it has recorded an Answer event for the active controlled CallKit generation

Verified redacted proof:
- receiver PushKit upload smoke returned http_success / registered / persisted / redacted_match
- public route safety remained green: dev invite 404, unauthenticated non-dev invite 401, stream 401, token registration 401, and APNs send control 401
- exactly one authenticated non-dev invite/APNs attempt was run; dev invite was not used
- dedicated VoIP receipt proof returned `pushkit_payload_kind=real_invite_controlled`, `real_invite_payload_mapping_observed=true`, `callkit_report_requested=true`, `callkit_report_result=reported`, and `pushkit_completion_called=true`
- CallKit Answer proof returned `callkit_answer_action_received=true` and `callkit_answer_action_fulfilled=true`
- controlled in-app proof returned `controlled_in_app_screen_presented=true` and `controlled_in_app_screen_source=callkit_answer_real_invite_controlled`
- controlled cleanup proof returned `controlled_callkit_cleanup_requested=true` and `controlled_callkit_cleanup_result=ended`
- media credentials, media connection, Matrix events, and real call flow remained false

Safety:
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, call handle, private log, or secret-bearing URL recorded
