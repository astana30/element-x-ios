# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-Physical7-PendingMetadataReferenceRepair — real invite pending metadata reference boundary, no APNs` is complete.

This was a code/test repair phase only. It did not send APNs, run production APNs, repeat APNs, use `dev/invite`, start physical media connect, join real LiveKit, request microphone/camera permission on device, emit Matrix events, enable video, or start full call flow.

The Physical7 attempt was previously answered but stopped safely because the invite lacked a pending metadata reference:

```text
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
pending_metadata_reference_present=false
pending_metadata_fetch_requested=true
pending_metadata_fetch_result=blocked_redacted
pending_metadata_fetch_failure_reason=missing_reference_after_answer
media_credentials_requested=false
media_connect_requested=false
livekit_join_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
physical6_runtime_enablement_url_hook_consumed=false
```

The repair now makes missing pending metadata fail closed before APNs:

```text
pending_metadata_reference_present=false
safe_to_send_apns=false
APNs_sent=false
blocked_reason=pending_metadata_reference_missing_before_apns
```

When valid pending metadata is supplied, the real non-dev invite path creates a durable opaque reference and includes only the redacted reference in the APNs payload:

```text
pending_metadata_source_created=true
pending_metadata_reference_present=true
pending_metadata_payload_redacted=true
pending_metadata_has_call_identifier=true
pending_metadata_has_room_binding=true
pending_metadata_has_peer=true
pending_metadata_reference_repair_reference_created_before_apns=true
pending_metadata_reference_repair_reference_present_in_apns_payload=true
```

The iOS PushKit/Answer proof now records reference observation and Answer handoff:

```text
pending_metadata_reference_repair_present=true
pending_metadata_reference_repair_debug_only=true
pending_metadata_reference_repair_real_invite_required=true
pending_metadata_reference_repair_reference_created_before_apns=true
pending_metadata_reference_repair_reference_present_in_apns_payload=true
pending_metadata_reference_repair_reference_observed_by_pushkit=true
pending_metadata_reference_repair_reference_handed_to_answer_pipeline=true
pending_metadata_reference_repair_blocks_apns_without_reference=true
pending_metadata_reference_repair_blocks_credentials_without_metadata_success=true
pending_metadata_reference_repair_no_direct_credentials_bypass=true
pending_metadata_reference_repair_no_connect_bypass=true
pending_metadata_reference_repair_raw_metadata_logged=false
```

Default runtime remains no-connect unless the future one-shot gates prove Answer, metadata fetch success, credentials eligibility/success, and explicit hook consumption:

```text
media_credentials_requested=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Phase

`2.48T-Physical8 — one-shot Answer -> metadata reference -> credentials -> first controlled audio-connect physical attempt`

This is the next physical proof phase. Use one explicit sandbox APNs only after fresh preflight proves both Matrix tokens, room validation, local schema, receiver app session readiness, and pending metadata reference creation. Do not use stale proof.

## Required Physical8 Proof Targets

The next one-shot proof must establish:

```text
pending_metadata_reference_present=true
pending_metadata_reference_repair_reference_observed_by_pushkit=true
pending_metadata_reference_repair_reference_handed_to_answer_pipeline=true
pending_metadata_fetch_requested=true
pending_metadata_fetch_result=success_redacted
media_credentials_requested=true
media_credentials_result=success_redacted
physical6_runtime_enablement_url_hook_consumed=true
controlled_connect_first_attempt_requested=true
controlled_connect_first_attempt_started=true
controlled_connect_first_attempt_repeated=false
```

Stop and classify instead of retrying if any earlier gate fails.

## Hard Limits

Do not:

- send APNs without fresh token/room/schema/session/pending-metadata-reference preflight
- send production APNs
- send repeated APNs
- run `dev/invite`
- retry media connect
- retry LiveKit join
- enable video
- request camera permission
- emit Matrix events
- start full call flow
- bypass CallKit Answer
- request credentials before metadata fetch success
- consume the Physical6/Physical7 hook before metadata plus credentials eligibility
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`
- log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID

## Required Checks Before Any Commit

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

- Physical8 classification
- proof generation
- whether PushKit was received
- whether CallKit report completed
- whether first action was `answer`
- pending metadata reference observation/handoff result
- pending metadata fetch result
- media credentials result
- first controlled connect attempt result bucket
- first controlled connect attempt error bucket
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
