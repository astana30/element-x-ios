# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-Physical6-MetadataCredentialsBoundaryRepair — Answer received, pending metadata/credentials boundary repaired, no physical connect` is complete.

This was a code/test repair phase only. No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, real LiveKit join, microphone/camera permission on device, Matrix event emission, video, or full call flow was performed.

The previous Physical6 attempt was answered but blocked before metadata/credentials:

```text
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
pending_metadata_fetch_requested=false
media_credentials_requested=false
controlled_connect_first_attempt_requested=false
blocked_reason=media_credentials_request_boundary_not_ready
```

The repair now makes the Answer path record the pending metadata boundary:

```text
foreground_pending_call_metadata_handoff_requested=true
foreground_pending_call_metadata_handoff_observed=true
pending_metadata_fetch_requested=true
```

If metadata is missing after Answer, the proof classifies the precise no-credentials state:

```text
pending_metadata_fetch_result=blocked_redacted
pending_metadata_fetch_failure_reason=missing_reference_after_answer
media_credentials_requested=false
media_credentials_result=blocked_redacted
blocked_reason=pending_metadata_missing_after_answer_no_credentials
```

If pending metadata succeeds, the credentials boundary can run:

```text
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
pending_metadata_fetch_errcode=none
media_credentials_request_planned=true
media_credentials_requested=true
media_credentials_request_authorized=true
```

The repair proof fields are present:

```text
metadata_credentials_boundary_repair_present=true
metadata_credentials_boundary_repair_debug_only=true
metadata_credentials_boundary_repair_requires_answer=true
metadata_credentials_boundary_repair_blocks_without_answer=true
metadata_credentials_boundary_repair_triggers_metadata_after_answer=true
metadata_credentials_boundary_repair_triggers_credentials_after_metadata=true
metadata_credentials_boundary_repair_blocks_connect_until_credentials=true
metadata_credentials_boundary_repair_does_not_consume_hook_before_credentials=true
metadata_credentials_boundary_repair_no_direct_connect_bypass=true
metadata_credentials_boundary_repair_raw_credentials_logged=false
```

The Physical6 hook is not consumed before metadata/credentials. Hook consumption remains one-shot and can happen only after Answer plus metadata success plus credentials eligibility reaches the controlled first-attempt gates. Default runtime remains no-connect.

## Phase

`2.48T-Physical7 — one-shot Answer -> metadata/credentials -> first controlled audio-connect physical attempt`

This is the next physical proof phase. Do not run repeated APNs or repeated connect. Run only one controlled physical attempt after fresh local-only inputs, fresh app readiness proof, local schema validation, explicit one-shot confirmation, and operator readiness.

## Task

Prepare the one-shot Physical7 proof using the repaired Answer -> metadata/credentials boundary.

Before any APNs attempt, activate the DEBUG one-shot hook locally:

```bash
open 'kz.salemx.msg://debug/direct-call/physical6-enable-controlled-audio-connect'
```

Then verify the hook is armed and side effects are still closed:

```text
physical6_runtime_enablement_url_hook_present=true
physical6_runtime_enablement_url_hook_debug_only=true
physical6_runtime_enablement_url_hook_default_disabled=true
physical6_runtime_enablement_url_hook_armed=true
physical6_runtime_enablement_url_hook_one_shot=true
physical6_runtime_enablement_url_hook_audio_only=true
physical6_runtime_enablement_url_hook_video_allowed=false
physical6_runtime_enablement_url_hook_matrix_events_allowed=false
physical6_runtime_enablement_url_hook_raw_credentials_logged=false
physical6_runtime_enablement_url_hook_consumed=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Send APNs only after fresh token/room/local-schema preflight passes, the hook is armed, explicit one-shot confirmation is reached, and the operator is ready to answer. After sandbox APNs success, do not send another APNs.

The future proof target should show Answer plus repaired metadata/credentials boundary before any first controlled connect attempt:

```text
physical_voip_push_received=true
callkit_report_result=reported
callkit_report_completion_observed=true
pushkit_completion_called=true
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
foreground_pending_call_metadata_handoff_requested=true
foreground_pending_call_metadata_handoff_observed=true
pending_metadata_fetch_requested=true
pending_metadata_fetch_result=success_redacted
media_credentials_requested=true
media_credentials_request_authorized=true
media_credentials_result=success_redacted
metadata_credentials_boundary_repair_present=true
metadata_credentials_boundary_repair_does_not_consume_hook_before_credentials=true
metadata_credentials_boundary_repair_no_direct_connect_bypass=true
controlled_connect_first_attempt_requested=true
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

If metadata is missing or blocked after Answer, stop and classify before credentials/connect. If credentials are blocked, stop and classify before connect. If CallKit Answer is not received, stop and classify before connect. If any repeated APNs/connect condition appears, stop as a safety regression.

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
- enable video
- start full call flow
- bypass CallKit Answer
- request credentials before Answer
- consume the Physical6 hook before Answer plus metadata plus credentials eligibility
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

- Physical7 classification
- proof generation
- whether PushKit was received
- whether CallKit report completed
- whether first action was `answer` or `none`
- whether pending metadata succeeded
- whether media credentials succeeded
- whether exactly one media connect was requested
- whether exactly one LiveKit audio join was requested
- whether camera permission stayed false
- whether Matrix event emit stayed false
- whether video stayed false
- whether full call flow stayed false
- final `git status --short --branch`
- explicit statement that no repeated APNs, no production APNs, no `dev/invite`, no repeated connect, no unauthorized LiveKit join, no unauthorized microphone/camera permission, no Matrix event emit, no video, and no full call flow were performed
