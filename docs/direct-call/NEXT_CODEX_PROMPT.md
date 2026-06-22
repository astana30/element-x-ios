# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48P prepared the first controlled audio-connect activation plan after the 2.48O physical no-connect proof. No physical connect was performed, controlled connect was not enabled, and the default remains no-connect.

Closed prerequisites:
- 2.47C physical controlled media credentials request succeeded with no media connect.
- 2.47D physical credentials cleanup / expiry proof succeeded.
- 2.47E server-side allocation/token expiry verification succeeded without LiveKit join.
- 2.48A documented the future media-connect seam.
- 2.48B implemented the controlled media-connect preflight guard.
- 2.48C proved the guard physically after real invite/APNs/PushKit/CallKit Answer.
- 2.48D reviewed the server/client readiness gates and concluded controlled connect was not yet approved.
- 2.48E added the disabled DEBUG-only switch/proof gates and kept execution blocked.
- 2.48F physically proved the disabled switch on-device after real non-dev invite/APNs/PushKit/CallKit Answer and controlled credentials success, with no media connect or LiveKit join.
- 2.48G documented the activation checklist, rollback plan, future first controlled-connect proof fields, and hard-stop fields without physical connect or code changes.
- 2.48H added the DEBUG-only activation configuration wrapper, default-disabled proof fields, rollback proof support, and targeted source-guard tests without physical connect.
- 2.48H-QA fixed stale source-guard expectations only and passed the broader selected DirectCall command across `DirectCallEngineTests` and `NativeIncomingCallLifecycleContractTests`.
- 2.48I-Retry physically closed the disabled activation proof on the one-shot retry with Answer, credentials, preflight guard, and no media connect.
- 2.48J documented the narrow enablement implementation plan.
- 2.48K implemented the DEBUG-only one-shot enablement proof mechanics and tests while preserving default no-connect.
- 2.48L-SessionRepair validated the iPhone app Matrix session before any retry; no APNs was sent.
- 2.48L-Retry2 physically closed the post-session-repair proof with credentials success and no media connect.
- 2.48M completed the first-run readiness gate and found no blocker for the next no-physical-connect implementation phase.
- 2.48N implemented the first controlled audio-connect execution gate, default disabled, no physical connect.
- 2.48O physically proved the controlled audio-connect execution gate appears on-device and remains default-blocked after Answer.
- 2.48P prepared the first controlled audio-connect activation plan, no physical connect.

2.48O proof summary:

```text
2.48O = physical proof succeeded
proof_file=/tmp/salemx-voip-push-receipt-proof-2.48o-polled.txt
proof_generation=generation_8
controlled audio-connect execution gate present on-device
execution gate DEBUG-only
audio-only=true
video allowed=false
Matrix events allowed=false
raw credentials logged=false
future phase permitted=false
execution allowed=false
blocked reason=future_phase_not_permitted_no_connect
blocked before engine
blocked before LiveKit join
blocked before permissions
blocked before Matrix events
no media connect
no LiveKit join
no mic/camera permission
no Matrix events
no full call flow
```

2.48O successful proof fields:

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
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_enabled=false
controlled_connect_enablement_operator_approved=false
controlled_connect_enablement_future_phase_permitted=false
controlled_connect_enablement_execution_allowed=false
controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
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
media_connect_preflight_requested=true
media_connect_preflight_result=blocked_before_connect_redacted
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

2.48P activation plan:

```text
2.48P = first controlled audio-connect activation plan
physical connect not performed
controlled connect not enabled
default remains no-connect
```

First controlled audio-connect activation requirements:

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

Allowed future scope:

```text
allow_audio_connect_attempt=true
allow_livekit_join_attempt=true
allow_microphone_permission_request=only_if_required_for_audio_connect
allow_camera_permission_request=false
allow_matrix_event_emit=false
allow_full_call_flow=false
allow_repeated_apns=false
```

Stop conditions:

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

Future first controlled connect proof fields:

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

Rollback expectations:

```text
rollback_disable_enablement=true
rollback_clear_operator_approval=true
rollback_clear_future_phase_permission=true
rollback_restore_execution_allowed_false=true
rollback_restore_no_connect_default=true
```

Readiness conclusion:

```text
2.48P result = ready to implement first controlled audio-connect activation path, no physical connect performed
```

## Phase

`2.48Q — implement first controlled audio-connect activation path, default disabled, no physical connect`

## Goal

Implement the first controlled audio-connect activation path while keeping it default-disabled and proof/test gated. This is not a physical connect phase: do not send APNs, do not connect media, do not join LiveKit, and do not request permissions. Do not set the next phase to physical connect yet.

## Required Behavior

- Do not send APNs.
- Do not send production APNs.
- Do not send repeated APNs.
- Do not run `dev/invite`.
- Do not start media connect.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full direct-call flow.
- Do not enable controlled-connect switch by default.
- Do not enable operator approval by default.
- Do not enable future physical-connect permission by default.
- Do not add production-enabled connect behavior.
- Preserve 2.48O as the latest physical no-connect proof.

The implementation should preserve the 2.48P plan and add only code/test wiring needed for a future explicit one-shot attempt:

```text
first_connect_requires_enablement_enabled=true
first_connect_requires_operator_approved=true
first_connect_requires_future_phase_permitted=true
first_connect_requires_fresh_credentials=true
first_connect_audio_only=true
first_connect_video_allowed=false
first_connect_matrix_events_allowed=false
first_connect_raw_credentials_logged=false
first_connect_rollback_available=true
first_connect_one_shot_only=true
```

Default 2.48Q proof fields should remain blocked:

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
default remains no-connect
physical connect not performed
```

If implementation is completed, keep the next handoff as a no-physical-connect follow-up unless the user gives a new explicit physical-proof instruction:

```text
2.48R — first controlled audio-connect activation implementation review, no physical connect
```

## Required Checks

For docs-only close-out, run:

```bash
git diff --check
git diff --cached --check
```

Run forbidden project/signing scans:

```bash
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run a privacy scan over changed docs/diff for raw:

```text
token
JWT
Authorization
APNs payload
invite body
LiveKit URL
roomID
callID
peerUserID
userID
deviceID
```

Allowed safe hits are field names, redacted labels, negative statements, and existing stable receiver/sender hashes only.

## Hard Constraints

- Do not send APNs.
- Do not send production APNs.
- Do not send repeated APNs.
- Do not use `dev/invite`.
- Do not connect media.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full call flow.
- Do not enable controlled connect by default.
- Do not enable controlled-connect operator approval by default.
- Do not enable future physical-connect permission by default.
- Do not add production-enabled connect behavior.
- Do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, room names, key material, or secret-bearing URLs.
- Do not touch project/signing/entitlement/`Info.plist`/`app.yml` files.
- Do not stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.

## If Blocked

Report the blocker and the smallest next fix. Keep all no-connect safety fields false. Do not proceed to actual controlled connect.
