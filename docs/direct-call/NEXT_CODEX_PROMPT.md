# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-RealPath — true one-shot audio-connect runtime path, default disabled, no APNs` is complete.

The app now has a DEBUG/test-controlled real-path gate that can reach the existing `DirectCallEngine.connectMediaIfReady` / `LiveKitDirectCallMediaEngine.connectAudio` boundary through the fake/test media seam when every gate is explicitly true. Runtime defaults remain no-connect.

Default real-path proof fields:

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

Default proof fields:

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

Runtime default remains:

```text
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

The fake/test path can reach the first-attempt boundary only when all gates are explicitly true in tests:

```text
controlled_connect_first_attempt_requested=true
controlled_connect_first_attempt_allowed=true
controlled_connect_first_attempt_started=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_error_bucket=none
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
```

No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, real LiveKit join, microphone/camera permission request, Matrix event emit, or full call flow was performed in 2.48T-RealPath.

## Phase

`2.48T-Physical2 — one-shot first controlled audio-connect physical attempt`

## Required Setup

Build, install, and launch the current HEAD Debug app on `iPhone PRO` before APNs. Do not use a stale installed app.

Before APNs, validate receiver app session:

```text
iphone_app_matrix_session_present=true
iphone_app_matrix_session_whoami_result=success_redacted
iphone_app_matrix_session_user_hash=497015f5745c933a
iphone_app_matrix_session_device_present=true
iphone_app_pending_metadata_auth_ready=true
APNs_sent=false
blocked_reason=none
```

Use in-memory or local-only token handling. Do not print token values.

Expected identity hashes:

```text
receiver/iPhone user hash = 497015f5745c933a
sender/caller user hash   = 7d434d7f252427fb
```

## Required Preflight Before APNs

Validate:

```text
receiver_token_found=true
sender_token_found=true
receiver_user_hash=497015f5745c933a
sender_user_hash=7d434d7f252427fb
sender_equals_receiver=false
receiver_device_present=true
room_validation_preflight=pass
local_schema_valid=true
iphone_app_pending_metadata_auth_ready=true
safe_to_send_apns=true
```

Use the corrected flat-schema invite body only.

Send exactly one real non-dev sandbox APNs only after explicit one-shot confirmation. After `background_apns_push_result=sandbox_success`, do not send another APNs.

## Required Physical Proof

Use a phase-specific proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48t-first-connect-polled.txt
```

Do not classify from stale generic proof files.

PushKit / CallKit / metadata / credentials must succeed:

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

Controlled gates must explicitly open for this one attempt:

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
controlled_connect_real_audio_path_can_reach_engine_when_all_gates_true=true
controlled_connect_enablement_enabled=true
controlled_connect_enablement_operator_approved=true
controlled_connect_enablement_future_phase_permitted=true
controlled_connect_enablement_execution_allowed=true
controlled_audio_connect_activation_allowed=true
controlled_audio_connect_execution_future_phase_permitted=true
controlled_audio_connect_execution_allowed=true
controlled_connect_real_audio_path_allowed=true
controlled_connect_real_audio_path_blocked_reason=none
controlled_connect_real_audio_path_blocked_before_engine=false
```

First attempt proof:

```text
controlled_connect_first_attempt_requested=true
controlled_connect_first_attempt_allowed=true
controlled_connect_first_attempt_started=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=<success_or_blocked_redacted>
controlled_connect_first_attempt_error_bucket=<none_or_redacted_bucket>
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
microphone_permission_requested=<true_if_required_or_false_if_not_required>
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Video and Matrix-event gates must remain disabled:

```text
controlled_connect_first_attempt_audio_only=true
controlled_connect_first_attempt_video_allowed=false
controlled_connect_first_attempt_matrix_events_allowed=false
controlled_connect_first_attempt_raw_credentials_logged=false
controlled_audio_connect_activation_video_allowed=false
controlled_connect_enablement_video_allowed=false
controlled_audio_connect_execution_video_allowed=false
controlled_audio_connect_activation_matrix_events_allowed=false
controlled_connect_enablement_matrix_events_allowed=false
controlled_audio_connect_execution_matrix_events_allowed=false
```

## Stop Conditions

Stop immediately and do not retry if any of these occur:

```text
APNs was sent once
media_connect_attempted=true
livekit_join_requested=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_result is present
camera_permission_requested=true
matrix_event_emit_requested=true
real_call_flow_started=true
repeated_apns=true
controlled_connect_first_attempt_repeated=true
raw credentials logged=true
```

Do not retry connect, LiveKit join, or APNs inside this task. Record the first result only.

## Hard Limits

- Do not use `dev/invite`.
- Do not send production APNs.
- Do not send repeated APNs.
- Do not perform more than one controlled media-connect attempt.
- Do not enable video.
- Do not request camera permission.
- Do not emit Matrix events.
- Do not start full direct-call flow.
- Do not retry LiveKit join after first result.
- Do not retry media connect after first result.
- Do not log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID.
- Do not modify `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`.

## Docs Close

If the first attempt includes a result, update only:

- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- `docs/direct-call/NEXT_CODEX_PROMPT.md`

If the first attempt succeeds, set next phase to:

`2.48U — first-connect result review and cleanup verification, no repeated connect`

If it fails safely, set next phase to:

`2.48T-ResultTriage — classify first controlled audio-connect result, no retry`

Do not set next phase to repeated connect.

## Required Checks Before Commit

```bash
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run a privacy scan over changed docs/diff for raw sensitive values. Allowed hits are field names, redacted labels, negative statements, and stable hashes only.
