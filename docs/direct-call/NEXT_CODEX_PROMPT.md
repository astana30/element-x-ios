# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Latest implementation commit:
`1cac40bffc472b68f44a284e0383ac35b6265d3e`
`Add 2.48Q activation path`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48R physically proved the 2.48Q first-run controlled audio-connect activation path on-device after one corrected flat-schema sandbox APNs, PushKit receipt, CallKit Answer, authenticated pending metadata, media credentials, and media-connect preflight.

Result:

```text
2.48R = physical proof succeeded
proof_file=/tmp/salemx-voip-push-receipt-proof-2.48r-polled.txt
proof_generation=generation_8
first-run controlled audio-connect activation path present on-device
activation path DEBUG-only
activation one-shot
activation default disabled
requires receiver session
requires fresh credentials
requires enablement
requires operator approval
requires future phase permission
audio-only=true
video allowed=false
Matrix events allowed=false
raw credentials logged=false
rollback available
activation allowed=false
blocked reason=activation_path_disabled_no_connect
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

Invite/APNs result:

```text
receiver_token_found=true
sender_token_found=true
receiver_user_hash=497015f5745c933a
sender_user_hash=7d434d7f252427fb
sender_equals_receiver=false
room_validation_preflight=pass
local_schema_valid=true
invite_send_attempted=true
invite_http_code=200
background_apns_push_result=sandbox_success
blocked_reason=none
```

Successful proof fields:

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
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

## Phase

`2.48S — final pre-connect operator gate, no physical connect`

## Goal

Implement or document the final operator-controlled pre-connect gate needed before any future physical connect attempt. This phase must not perform physical connect, LiveKit join, media connect, permission request, Matrix event emission, or full call flow.

## Required Behavior

- Preserve the 2.48R proof as the latest physical no-connect proof.
- Do not send APNs.
- Do not send production APNs.
- Do not send repeated APNs.
- Do not use `dev/invite`.
- Do not start media connect.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full direct-call flow.
- Do not enable controlled-connect switch by default.
- Do not enable operator approval by default unless the task explicitly scopes inert gate wiring only.
- Do not enable future physical-connect permission by default.
- Do not add production-enabled connect behavior.
- Do not log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID.

## 2.48S Acceptance Shape

Record a final pre-connect operator gate that is DEBUG/test-scoped, one-shot, default-off, rollback-ready, and explicit about the final future-connect requirements:

```text
final_preconnect_operator_gate_present=true
final_preconnect_operator_gate_debug_only=true
final_preconnect_operator_gate_one_shot=true
final_preconnect_operator_gate_default_off=true
final_preconnect_operator_gate_requires_receiver_session=true
final_preconnect_operator_gate_requires_fresh_credentials=true
final_preconnect_operator_gate_requires_enablement=true
final_preconnect_operator_gate_requires_operator_approval=true
final_preconnect_operator_gate_requires_future_phase_permission=true
final_preconnect_operator_gate_audio_only=true
final_preconnect_operator_gate_video_allowed=false
final_preconnect_operator_gate_matrix_events_allowed=false
final_preconnect_operator_gate_raw_credentials_logged=false
final_preconnect_operator_gate_rollback_available=true
final_preconnect_operator_gate_allows_connect=false
final_preconnect_operator_gate_blocked_reason=operator_gate_disabled_no_connect
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
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
