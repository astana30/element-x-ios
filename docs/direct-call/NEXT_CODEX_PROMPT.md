# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderLiveKitReadinessHookRepair` is complete.

The DEBUG/test-controlled sender LiveKit readiness hook now exists and is default-disabled/no-connect:

```text
sender_livekit_readiness_hook_present=true
sender_livekit_readiness_hook_debug_only=true
sender_livekit_readiness_hook_default_disabled=true
sender_livekit_readiness_hook_armed=false
sender_livekit_readiness_hook_audio_only=true
sender_livekit_readiness_hook_video_allowed=false
sender_livekit_readiness_hook_matrix_events_allowed=false
sender_livekit_readiness_hook_raw_identifiers_logged=false
sender_livekit_readiness_hook_blocked_reason=default_disabled_no_connect
```

It can be armed from redacted pre-APNs inputs only:

```text
sender_matrix_session_ready=true
sender_expected_hash_matches=true
sender_same_room_ready=true
```

When armed with the validated second physical sender readiness, the proof can classify:

```text
sender_livekit_readiness_hook_armed=true
sender_livekit_readiness_hook_matrix_session_ready=true
sender_livekit_readiness_hook_expected_user_matched=true
sender_livekit_readiness_hook_same_room_ready=true
sender_livekit_readiness_hook_blocked_reason=armed_waiting_for_future_sender_join

second_physical_sender_livekit_readiness_matrix_session_ready=true
second_physical_sender_livekit_readiness_same_room_ready=true
```

The sender join path remains present but default-disabled/audio-only:

```text
second_physical_sender_livekit_join_path_present=true
second_physical_sender_livekit_join_path_default_disabled=true
second_physical_sender_livekit_join_path_audio_only=true
second_physical_sender_livekit_join_path_video_allowed=false
second_physical_sender_livekit_join_path_matrix_events_allowed=false
second_physical_sender_livekit_join_path_raw_credentials_logged=false
```

The repair was code/test diagnostics only. No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, real-device LiveKit join, video, microphone/camera permission, Matrix event emit, or full call flow was performed.

## Next Phase

`2.48Z-Physical2-Retry1 — one-shot two-physical-device sender-join/remote-participant proof`

This is the next physical attempt only after fresh operator confirmation.

## Required Safety Limits

Do not send APNs until all preflight gates pass and the explicit one-shot confirmation is reached.

Do not run production APNs. Do not send repeated APNs. Do not use `dev/invite`. Do not retry connect. Do not enable video. Do not request camera permission. Do not emit Matrix events. Do not start a full call flow.

The next proof may perform at most one sandbox APNs, one operator Answer, and one controlled audio-only sender/receiver LiveKit attempt after all gates pass.

## Preflight Requirements

Before APNs, verify without raw values:

```text
receiver_token_found=true
sender_token_found=true
receiver_user_hash=497015f5745c933a
sender_user_hash=7d434d7f252427fb
sender_equals_receiver=false
room_validation_preflight=pass
local_schema_valid=true
corrected_flat_schema_used=true
nested_invite_body_used=false
```

Verify both physical app sessions are ready:

```text
receiver_iphone_matrix_session_whoami_result=success_redacted
receiver_iphone_matrix_session_user_hash=497015f5745c933a
receiver_iphone_pending_metadata_auth_ready=true
second_physical_device_matrix_session_whoami_result=success_redacted
second_physical_device_matrix_session_user_hash=7d434d7f252427fb
second_physical_device_matrix_session_user_hash_matches_expected=true
second_physical_device_pending_metadata_auth_ready=true
```

Arm the sender readiness hook before APNs using only redacted booleans and confirm:

```text
sender_livekit_readiness_hook_armed=true
sender_livekit_readiness_hook_matrix_session_ready=true
sender_livekit_readiness_hook_expected_user_matched=true
sender_livekit_readiness_hook_same_room_ready=true
sender_livekit_readiness_hook_video_allowed=false
sender_livekit_readiness_hook_matrix_events_allowed=false
sender_livekit_readiness_hook_raw_identifiers_logged=false
sender_livekit_readiness_hook_blocked_reason=armed_waiting_for_future_sender_join

second_physical_sender_livekit_readiness_matrix_session_ready=true
second_physical_sender_livekit_readiness_same_room_ready=true
second_physical_sender_livekit_join_path_default_disabled=true
```

Continue only if:

```text
safe_to_send_apns=true
APNs_sent=false
```

After `background_apns_push_result=sandbox_success`, do not send another APNs. The operator should press green Answer once and then copy/poll the phase-specific proof.

## Expected Proof Close Fields

Classify the result using redacted proof fields:

```text
physical_voip_push_received
pushkit_callback_invoked
callkit_report_result
callkit_answer_action_received
pending_metadata_fetch_result
media_credentials_result
physical6_runtime_enablement_url_hook_consumed
controlled_connect_first_attempt_result
controlled_connect_first_attempt_repeated
media_connect_requested
media_connect_attempted
livekit_join_requested
livekit_connect_audio_invoked
livekit_join_result
livekit_remote_participant_seen
livekit_remote_audio_track_subscribed
livekit_audio_liveness_result
receiver_remote_participant_observer_result
microphone_permission_requested
camera_permission_requested
matrix_event_emit_requested
real_call_flow_started
blocked_reason
```

Stop and classify if any safety regression appears:

```text
controlled_connect_first_attempt_repeated=true
camera_permission_requested=true
matrix_event_emit_requested=true
real_call_flow_started=true
```

Run docs/code checks only after the physical proof is classified; do not set the next phase to production or broader rollout.
