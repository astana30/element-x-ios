# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-CallKitSurfaceRepair — fix CallKit report completion/surface before any APNs retry` is complete.

This was a code/test repair phase only. It did not send APNs, repeat APNs, run production APNs, use `dev/invite`, retry connect, join LiveKit, request microphone/camera permission, emit Matrix events, or start full call flow.

The preceding `2.48T-Physical4` physical result remains classified as missed/no-answer/no-surface triage, not as first controlled audio-connect proof close:

```text
callkit_report_requested=true
callkit_report_result=pending
callkit_report_completion_observed=false
pushkit_completion_called=false
callkit_first_action_kind=none
callkit_answer_action_received=false
```

The repair adds explicit redacted proof fields:

```text
callkit_surface_repair_present=true
callkit_surface_repair_debug_only=true
callkit_surface_repair_provider_retention_verified=<retention proof>
callkit_surface_repair_delegate_retention_verified=<retention proof>
callkit_surface_repair_active_uuid_retention_verified=<retention proof>
callkit_surface_repair_report_completion_watchdog_present=true
callkit_surface_repair_report_completion_timeout_classified=<timeout classification>
callkit_surface_repair_pushkit_completion_safety_present=true
callkit_surface_repair_pushkit_completion_safety_result=<redacted safety result>
callkit_surface_repair_background_task_requested=<debug repair state>
callkit_surface_repair_background_task_ended=<debug repair state>
callkit_surface_repair_blocks_connect_without_answer=true
callkit_surface_repair_blocks_metadata_without_answer=true
callkit_surface_repair_no_direct_answer_bypass=true
callkit_surface_repair_no_media_connect_on_no_answer=true
```

Report completion success can now record:

```text
callkit_report_result=reported
callkit_report_completion_observed=true
pushkit_completion_called=true
```

Missing report completion is classified safely:

```text
callkit_report_result=timeout_or_pending_redacted
callkit_report_completion_observed=false
callkit_surface_repair_report_completion_timeout_classified=true
callkit_surface_repair_pushkit_completion_safety_result=completed_after_report_timeout
callkit_first_action_kind=none
```

Default no-answer behavior remains closed:

```text
pending_metadata_fetch_requested=false
media_credentials_requested=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Phase

`2.48T-Physical5 — one-shot CallKit surface/answer proof, no repeated connect`

This is the next physical proof phase. Do not set the phase to repeated audio-connect. First prove CallKit surface/report completion and one CallKit Answer action after the surface repair.

## Task

Prepare and run exactly one controlled Physical5 proof only when fresh local-only inputs and preflight pass.

The proof target is:

```text
callkit_report_requested=true
callkit_report_result=reported
callkit_report_completion_observed=true
pushkit_completion_called=true
callkit_first_action_kind=answer
callkit_answer_action_received=true
```

If the surface still does not appear or no Answer action is received, classify it without retrying APNs or connect.

## Hard Limits

Do not:

- send APNs before fresh local preflight and explicit one-shot confirmation
- run production APNs
- run repeated APNs
- run `dev/invite`
- retry connect
- join LiveKit unless the future phase explicitly permits and gates it
- request microphone permission unless the future phase explicitly permits and gates it
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

## Required Checks Before Any Physical Retry

Run focused checks for the touched CallKit/PushKit proof surface, plus:

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

- Physical5 classification
- proof generation
- whether PushKit was received
- whether CallKit report completed
- whether first action was `answer` or `none`
- whether pending metadata/credentials ran
- whether media connect was requested
- whether LiveKit join was requested
- whether camera permission stayed false
- whether Matrix event emit stayed false
- whether full call flow stayed false
- final `git status --short --branch`
- explicit statement that no repeated APNs, no production APNs, no `dev/invite`, no unauthorized retry connect, no unauthorized LiveKit join, no unauthorized microphone/camera permission, no Matrix event emit, and no full call flow were performed
