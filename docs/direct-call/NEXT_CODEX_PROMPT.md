# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-Physical7-MissingMetadataResult — answered, missing pending metadata, no connect` is complete.

This was a physical one-shot attempt. It reached PushKit, CallKit report completion, and a real Answer action, then stopped safely before credentials/connect because the incoming invite did not contain a pending metadata reference.

Phase-specific proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48t-physical7-first-audio-connect-polled.txt
```

Observed proof:

```text
proof_generation=generation_7
proof_last_updated_by=voip_push_callback
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_report_requested=true
callkit_report_result=reported
callkit_report_completion_observed=true
pushkit_completion_called=true
callkit_first_action_kind=answer
callkit_answer_action_delivered=true
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
```

The repaired Answer boundary ran:

```text
metadata_credentials_boundary_repair_present=true
metadata_credentials_boundary_repair_requires_answer=true
metadata_credentials_boundary_repair_triggers_metadata_after_answer=true
metadata_credentials_boundary_repair_triggers_credentials_after_metadata=true
metadata_credentials_boundary_repair_blocks_connect_until_credentials=true
metadata_credentials_boundary_repair_no_direct_connect_bypass=true
metadata_credentials_boundary_repair_raw_credentials_logged=false
foreground_pending_call_metadata_handoff_requested=true
foreground_pending_call_metadata_handoff_observed=true
```

The result blocked before credentials/connect:

```text
pending_metadata_reference_present=false
pending_metadata_fetch_requested=true
pending_metadata_fetch_result=blocked_redacted
pending_metadata_fetch_http_status_bucket=not_requested
pending_metadata_fetch_failure_reason=missing_reference_after_answer
media_credentials_requested=false
media_credentials_result=blocked_redacted
controlled_connect_first_attempt_requested=false
controlled_connect_first_attempt_started=false
controlled_connect_first_attempt_completed=false
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=not_requested
controlled_connect_first_attempt_error_bucket=none
blocked_reason=pending_metadata_missing_after_answer_no_credentials
```

Safety remained closed:

```text
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

The pre-send hook proof showed the DEBUG hook was armed and audio-only before APNs. The final callback proof did not consume the hook because metadata/credentials failed closed first:

```text
physical6_runtime_enablement_url_hook_present=true
physical6_runtime_enablement_url_hook_consumed=false
```

## Phase

`2.48T-ResultTriage — classify first controlled audio-connect result, no retry`

This is a no-retry triage phase. Do not send APNs. Do not retry connect. Do not run `dev/invite`.

## Task

Investigate why the Physical7 real invite reached Answer without a pending metadata reference:

```text
pending_metadata_reference_present=false
pending_metadata_fetch_failure_reason=missing_reference_after_answer
blocked_reason=pending_metadata_missing_after_answer_no_credentials
```

Focus on the non-dev invite path and pending metadata reference propagation. Determine whether the sender helper/server response omitted the reference, the PushKit payload mapper dropped it, or the receipt parser failed to preserve it. Keep the work docs-only unless a narrow code/test repair is explicitly required by local source evidence.

If a code repair is needed, keep it limited to the pending metadata reference propagation boundary and add source guards/tests proving:

```text
real_invite_controlled includes pending metadata reference when available
PushKit receipt preserves pending metadata reference
Answer path fetches metadata only when reference is present
missing reference blocks credentials/connect
no direct connect bypass
no hook consumption before metadata and credentials
```

## Hard Limits

Do not:

- send APNs
- run production APNs
- run repeated APNs
- run `dev/invite`
- retry media connect
- retry LiveKit join
- enable video
- request camera permission
- emit Matrix events
- start full call flow
- bypass CallKit Answer
- request credentials before Answer
- consume the Physical6 hook before metadata plus credentials eligibility
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`
- log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID

## Required Checks Before Commit

Run:

```bash
git status --short --branch
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

If code changes are made, also run the focused DirectCall subset:

```bash
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
```

Privacy scan changed docs/diff for raw sensitive values. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- Physical7 classification
- proof generation
- whether PushKit was received
- whether CallKit report completed
- whether first action was `answer`
- pending metadata result
- media credentials result
- first attempt result bucket
- first attempt error bucket
- whether media connect was requested/attempted
- whether LiveKit join was requested
- whether microphone permission was requested
- whether camera permission stayed false
- whether Matrix event emit stayed false
- whether full call flow stayed false
- whether the hook was consumed
- commit hash if docs or code were updated
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no repeated APNs, no production APNs, no `dev/invite`, no repeated connect, no video, no camera permission, no Matrix event emit, and no full call flow were performed
