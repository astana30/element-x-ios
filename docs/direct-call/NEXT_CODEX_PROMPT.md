# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Latest completed physical proof commit before the final gate:
`98c30289c363c40c85c61c2f916594b3ead336fc`
`Record 2.48R physical proof`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48S documented the final pre-connect operator gate. It did not perform physical connect, did not enable controlled connect, and preserved the default no-connect state.

Conclusion:

```text
2.48S = final pre-connect operator gate
physical connect not performed
controlled connect not enabled
default remains no-connect
2.48S result = ready for one-shot first controlled audio-connect physical attempt
```

Final go/no-go checklist:

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

Allowed future first-connect scope:

```text
allow_one_controlled_audio_connect_attempt=true
allow_livekit_join_attempt=true
allow_microphone_permission_request=only_if_required_for_audio_connect
allow_camera_permission_request=false
allow_matrix_event_emit=false
allow_full_call_flow=false
allow_repeated_apns=false
```

Final stop conditions:

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

## Phase

`2.48T — one-shot first controlled audio-connect physical attempt`

## Goal

Run exactly one first controlled audio-connect physical attempt after the final operator gate passes. This phase may attempt one sandbox APNs, one green Answer, one controlled audio connect, and one LiveKit join attempt only within the allowed audio-only scope. Stop after the first connect result.

## Required Preflight

Before any APNs send or connect attempt:

```text
receiver_app_session_validated=true
terminal_tokens_valid=true
room_validation_pass=true
local_schema_valid=true
controlled_connect_enablement_enabled=true
controlled_connect_enablement_operator_approved=true
controlled_connect_enablement_future_phase_permitted=true
safe_to_send_single_sandbox_apns=true
explicit_one_shot_confirmation_reached=true
```

If any preflight field fails or cannot be proved, stop before APNs and classify the blocker.

## Permitted Once

- Send exactly one sandbox APNs after preflight and explicit confirmation.
- Allow the operator to press green Answer once.
- Attempt one controlled audio connect after pending metadata, credentials, enablement, operator approval, and future phase permission all pass.
- Allow one LiveKit join attempt only as part of the controlled audio connect attempt.
- Request microphone permission only if required for the audio connect attempt.
- Stop after the first connect result, whether success or blocked.

## Hard Limits

- Do not use `dev/invite`.
- Do not send production APNs.
- Do not send repeated APNs.
- Do not start video.
- Do not request camera permission.
- Do not emit Matrix events.
- Do not start full direct-call flow.
- Do not continue after the first connect result.
- Do not log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID.
- Do not modify `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`.

## Required Proof For Future First Controlled Connect

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

## Stop Conditions

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

## Required Checks

Run before committing any close-out docs:

```bash
git diff --check
git diff --cached --check
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
