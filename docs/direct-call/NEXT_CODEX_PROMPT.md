# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-Physical6EnablementHook — add DEBUG-only one-shot physical connect enablement hook, no APNs` is complete.

This was code/test prep only. No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, real LiveKit join, microphone/camera permission, Matrix event emission, or full direct-call flow was performed.

The DEBUG local URL hook is present and default-disabled:

```text
kz.salemx.msg://debug/direct-call/physical6-enable-controlled-audio-connect
physical6_runtime_enablement_url_hook_present=true
physical6_runtime_enablement_url_hook_debug_only=true
physical6_runtime_enablement_url_hook_default_disabled=true
physical6_runtime_enablement_url_hook_armed=false
physical6_runtime_enablement_url_hook_one_shot=true
physical6_runtime_enablement_url_hook_audio_only=true
physical6_runtime_enablement_url_hook_video_allowed=false
physical6_runtime_enablement_url_hook_matrix_events_allowed=false
physical6_runtime_enablement_url_hook_raw_credentials_logged=false
physical6_runtime_enablement_url_hook_consumed=false
physical6_runtime_enablement_url_hook_blocked_reason=default_disabled_no_connect
```

The credentials/connect preflight now uses the armed one-shot hook state instead of hard-coding default-disabled:

```text
physical6_runtime_enablement_url_hook_present=true
credentials_connect_preflight_uses_default_disabled=false
```

After the local URL hook is opened, the expected pre-APNs proof should show the hook armed and no side effects:

```text
physical6_runtime_enablement_url_hook_armed=true
physical6_runtime_enablement_url_hook_consumed=false
physical6_runtime_enablement_url_hook_blocked_reason=armed_waiting_for_one_incoming_answer
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

The default runtime still blocks with no connect until the hook is armed and the future incoming Answer pipeline reaches pending metadata and media credentials. A future first attempt must consume the hook once:

```text
physical6_runtime_enablement_url_hook_consumed=true
controlled_connect_first_attempt_repeated=false
```

## Phase

`2.48T-Physical6 — one-shot first controlled audio-connect physical attempt`

This is the next physical proof phase. Do not run repeated APNs or repeated connect. Run only one controlled physical attempt after fresh local-only inputs, fresh app readiness proof, local schema validation, explicit one-shot confirmation, and operator readiness.

## Task

Prepare the first controlled audio-connect physical attempt with fresh in-memory/local-only inputs.

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
physical6_runtime_enablement_url_hook_blocked_reason=armed_waiting_for_one_incoming_answer
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Send APNs only after fresh preflight passes, the hook is armed, local schema validation passes, explicit one-shot confirmation is reached, and the operator is ready to answer. After sandbox APNs success, do not send another APNs.

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
