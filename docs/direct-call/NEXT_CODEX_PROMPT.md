# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-Physical5 — one-shot CallKit surface/answer proof, no repeated connect` is complete.

One sandbox APNs was sent after fresh in-memory token/room preflight, corrected flat schema validation, and explicit one-shot confirmation. No repeated APNs, production APNs, or `dev/invite` was used.

Redacted preflight/send proof:

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
safe_to_send_apns=true
invite_send_attempted=true
invite_http_code=200
real_non_dev_invite_used=true
dev_invite_used=false
background_apns_push_requested=true
background_apns_push_result=sandbox_success
APNs_sent=true
```

The phase-specific proof generation was `generation_7`. The repaired CallKit report/surface/Answer path succeeded:

```text
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_report_requested=true
callkit_report_result=reported
callkit_report_completion_observed=true
pushkit_completion_called=true
callkit_surface_repair_provider_retention_verified=true
callkit_surface_repair_delegate_retention_verified=true
callkit_surface_repair_active_uuid_retention_verified=true
callkit_first_action_kind=answer
callkit_answer_action_delivered=true
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
callkit_event_order=report_completion_then_answer
app_activation_observed=true
controlled_in_app_activation_observed=true
```

This closes CallKit surface/Answer only. It is not a first controlled audio-connect proof. The answer-window safety completed after timeout before the late Answer action was observed:

```text
pushkit_completion_answerable_window_result=timeout_elapsed
callkit_surface_repair_pushkit_completion_safety_result=completed_after_answerable_window_timeout
```

Pending metadata, credentials, connect, LiveKit, permissions, Matrix events, and full flow stayed closed:

```text
pending_metadata_reference_present=false
pending_metadata_fetch_requested=false
pending_metadata_fetch_result=not_requested
media_credentials_requested=false
media_credentials_result=blocked_redacted
controlled_connect_enablement_enabled=false
controlled_connect_enablement_execution_allowed=false
controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
controlled_connect_first_attempt_requested=false
controlled_connect_first_attempt_allowed=false
controlled_connect_first_attempt_started=false
controlled_connect_first_attempt_completed=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=media_credentials_request_boundary_not_ready
```

## Phase

`2.48T-Physical6 — one-shot first controlled audio-connect physical attempt`

This is the next physical proof phase. Do not run repeated APNs or repeated connect. Run only one controlled physical attempt after fresh local-only inputs, fresh app readiness proof, local schema validation, explicit one-shot confirmation, and operator readiness.

## Task

Prepare the first controlled audio-connect physical attempt with fresh in-memory/local-only inputs. Send APNs only after preflight passes and explicit one-shot confirmation is reached. After sandbox APNs success, do not send another APNs.

The future proof target should show the CallKit Answer path plus exactly one controlled first connect attempt, while still preserving audio-only and no Matrix-event/full-flow boundaries:

```text
physical_voip_push_received=true
callkit_report_result=reported
callkit_report_completion_observed=true
pushkit_completion_called=true
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
pending_metadata_fetch_result=success_redacted
media_credentials_result=success_redacted
controlled_connect_first_attempt_requested=true
controlled_connect_first_attempt_allowed=true
controlled_connect_first_attempt_started=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
microphone_permission_requested=<phase-approved audio-only result>
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

If pending metadata or credentials fail, stop and classify before connect. If CallKit Answer is not received, stop and classify before connect. If any repeat APNs/connect condition appears, stop as a safety regression.

## Hard Limits

Do not:

- send APNs before fresh local preflight and explicit one-shot confirmation
- run production APNs
- run repeated APNs
- run `dev/invite`
- retry connect after the one controlled attempt
- join LiveKit before all controlled first-attempt gates are true
- request camera permission
- emit Matrix events
- start full call flow
- bypass CallKit Answer
- mark Answer as received unless CallKit actually delivers the answer action
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`
- log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID

## Required Checks Before Any Physical Attempt

Run focused checks for the touched DirectCall/CallKit/PushKit proof surface, plus:

```bash
git status --short --branch
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Privacy scan changed docs/diff for raw sensitive values. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- Physical6 classification
- proof generation
- whether PushKit was received
- whether CallKit report completed
- whether first action was `answer` or `none`
- whether pending metadata/credentials succeeded
- whether exactly one media connect was requested
- whether exactly one LiveKit audio join was requested
- whether camera permission stayed false
- whether Matrix event emit stayed false
- whether full call flow stayed false
- final `git status --short --branch`
- explicit statement that no repeated APNs, no production APNs, no `dev/invite`, no repeated connect, no unauthorized LiveKit join, no unauthorized microphone/camera permission, no Matrix event emit, and no full call flow were performed
