# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-Physical6-MetadataCredentialsBoundaryTriage — answered / metadata-credentials boundary blocked / no-connect triage` is complete.

This was not a first controlled audio-connect proof close.

One sandbox APNs was sent after explicit `SEND_2_48T_PHYSICAL6`. PushKit received the invite, CallKit report completed, PushKit completion was called, and CallKit Answer action was received and fulfilled.

Phase-specific proof:

```text
proof_generation=generation_12
physical_voip_push_received=true
pushkit_callback_invoked=true
callkit_report_result=reported
callkit_report_completion_observed=true
pushkit_completion_called=true
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
```

The flow stopped before pending metadata and credentials:

```text
pending_metadata_fetch_requested=false
pending_metadata_fetch_result=not_requested
media_credentials_requested=false
media_credentials_result=blocked_redacted
blocked_reason=media_credentials_request_boundary_not_ready
```

The Physical6 enablement hook was not consumed, and no controlled first attempt started:

```text
physical6_runtime_enablement_url_hook_consumed=false
controlled_connect_first_attempt_requested=false
media_connect_requested=false
livekit_join_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

No repeated APNs, production APNs, `dev/invite`, repeated connect, unauthorized LiveKit join, microphone/camera permission, Matrix event emit, video, or full call flow was performed.

## Phase

`2.48T-Physical6-MetadataCredentialsBoundaryRepair — Answer received, pending metadata/credentials not requested, no connect`

Do not set this phase to another physical APNs attempt yet.

## Task

Investigate and repair why, after real CallKit Answer:

```text
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
```

the flow still recorded:

```text
pending_metadata_fetch_requested=false
media_credentials_requested=false
media_credentials_result=blocked_redacted
blocked_reason=media_credentials_request_boundary_not_ready
physical6_runtime_enablement_url_hook_consumed=false
controlled_connect_first_attempt_requested=false
```

Target likely areas:

```text
CallKit Answer -> foreground pending metadata handoff
CallKit Answer -> pending metadata fetch trigger
pending metadata availability before media credentials
media credentials boundary readiness
Physical6 hook consumption after Answer + fresh metadata/credentials
controlled connect first-attempt request trigger
```

The repair must preserve default no-connect behavior unless the one-shot Physical6 hook is armed and the Answer + pending metadata + credentials gates all succeed. Keep the repair covered by focused DirectCall/CallKit/PushKit tests and redacted proof fields.

## Hard Limits

Do not:

- send APNs
- run production APNs
- run repeated APNs
- run `dev/invite`
- retry connect
- join LiveKit
- request microphone permission
- request camera permission
- emit Matrix events
- start full call flow
- enable video
- bypass CallKit Answer
- consume the Physical6 hook before pending metadata and credentials are ready
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`
- log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID

## Required Checks

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

- repair conclusion
- commit hash
- commit message
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, retry connect, LiveKit join, microphone/camera permission, Matrix event emit, video, or full call flow were performed
