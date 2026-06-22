# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-Physical4-MissedSurface — APNs delivered to PushKit, no CallKit answer surface/action, no connect` is complete.

This was a missed/no-answer/no-surface triage, not a first controlled audio-connect proof close.

APNs/send result:

```text
invite_send_attempted=true
invite_http_code=200
real_non_dev_invite_used=True
dev_invite_used=False
background_apns_push_requested=True
background_apns_push_result=sandbox_success
APNs_sent=true
blocked_reason=none
```

Physical proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48t-physical4-polled.txt
```

Physical proof classification:

```text
proof_generation=generation_3
proof_last_updated_by=voip_push_callback
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_report_requested=true
callkit_report_result=pending
callkit_report_completion_observed=false
pushkit_completion_called=false
callkit_first_action_kind=none
callkit_answer_action_received=false
```

Required conclusion:

```text
2.48T-Physical4 = APNs sent once and PushKit received, but first controlled audio-connect did not complete.
Reason: CallKit report remained pending, report completion was not observed, PushKit completion was not called, and no CallKit Answer action was received.
No pending metadata fetch.
No media credentials request.
No media connect.
No LiveKit join.
No microphone permission.
No camera permission.
No Matrix event emit.
No full call flow.
No retry performed.
```

Safety fields:

```text
pending_metadata_fetch_requested=false
pending_metadata_fetch_result=not_requested
media_credentials_requested=false
media_credentials_result=not_requested
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

No repeated APNs, production APNs, `dev/invite`, connect retry, LiveKit join, microphone/camera permission request, Matrix event emission, or full call flow was performed in the close-out.

## Phase

`2.48T-CallKitSurfaceRepair — fix CallKit report completion/surface before any APNs retry`

Do not set the next phase to another physical APNs attempt yet.

## Task

Investigate and repair why the physical proof recorded:

```text
callkit_report_requested=true
callkit_report_result=pending
callkit_report_completion_observed=false
pushkit_completion_called=false
callkit_first_action_kind=none
```

Target likely area:

```text
CallKit reportNewIncomingCall completion handling
provider/delegate retention while device is locked
PushKit completion timing
answerable-window handling when app is locked/minimized
CallKit surface observability
```

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
- enable uncontrolled connect behavior
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`
- log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID

## Required Work

- Reproduce the diagnosis from source and existing proof only; do not send APNs.
- Inspect CallKit report completion handling in the controlled PushKit proof path.
- Inspect provider/delegate/active-call retention while the device is locked/minimized.
- Inspect PushKit completion timing and any answerable-window timeout path.
- Add the smallest safe repair and/or diagnostics needed to make report completion/surface observable before any future APNs retry.
- Keep runtime defaults no-connect.
- Keep media credentials, media connect, LiveKit join, microphone/camera permission, Matrix events, and full direct-call flow blocked.

## Required Checks

Run focused tests for the touched CallKit/PushKit proof surface, plus:

```bash
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Privacy scan changed docs/diff for raw sensitive values. Allowed hits are field names, redacted labels, negative statements, and stable hashes only.

## Expected Output

Return:

- repair conclusion
- commit hash
- commit message
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no APNs, no production APNs, no repeated APNs, no `dev/invite`, no retry connect, no LiveKit join, no microphone/camera permission, no Matrix event emit, and no full call flow were performed
