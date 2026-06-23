# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48T-Physical8 — one-shot Answer -> metadata reference -> credentials -> first controlled audio-connect physical attempt` is complete.

This was a one-shot physical proof. Exactly one sandbox APNs was sent after explicit confirmation; do not repeat it. No production APNs, repeated APNs, `dev/invite`, repeated connect, repeated LiveKit join, video, camera permission, Matrix event emit, or full call flow was performed.

Before the successful send, the first helper run blocked safely before APNs because staging still served stale foreground-signaling diagnostics. Only the repaired call-service runtime `app.py` was deployed to staging. Remote compileall passed, `salemx-call-service` restarted successfully, direct service status returned active, and public route safety remained:

```text
dev/invite=404
unauthenticated_non_dev_invite=401
unauthenticated_stream=401
unauthenticated_foreground_livekit_token=401
```

The app session proof and DEBUG-only one-shot hook proof were refreshed after the server repair and before the successful one-shot helper run.

## Physical8 Proof Result

Phase-specific proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48t-physical8-first-audio-connect-polled.txt
```

Proof summary:

```text
proof_generation=generation_14
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

Pending metadata and credentials:

```text
pending_metadata_reference_present=true
pending_metadata_reference_repair_reference_observed_by_pushkit=true
pending_metadata_reference_repair_reference_handed_to_answer_pipeline=true
pending_metadata_fetch_requested=true
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
pending_metadata_fetch_errcode=none
foreground_pending_call_metadata_handoff_observed=true
media_credentials_requested=true
media_credentials_request_authorized=true
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_url_received=true
```

First controlled audio-connect attempt:

```text
physical6_runtime_enablement_url_hook_consumed=true
controlled_connect_real_bridge_allowed=true
controlled_connect_first_attempt_requested=true
controlled_connect_first_attempt_allowed=true
controlled_connect_first_attempt_started=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_error_bucket=none
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
```

Safety fields stayed closed:

```text
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
controlled_connect_first_attempt_audio_only=true
controlled_connect_first_attempt_video_allowed=false
controlled_connect_first_attempt_matrix_events_allowed=false
controlled_connect_first_attempt_raw_credentials_logged=false
blocked_reason=none
```

## Phase

`2.48U — first-connect result review and cleanup verification, no repeated connect`

This is a review/cleanup phase only. Do not send APNs, do not retry media connect, and do not start another LiveKit join.

## Suggested 2.48U Scope

Review the Physical8 result and verify cleanup/follow-up safety:

```text
physical8_result_classification=success_first_controlled_audio_connect_redacted
single_apns_send_preserved=true
single_connect_attempt_preserved=true
single_livekit_join_attempt_preserved=true
hook_consumed_after_metadata_and_credentials=true
no_repeated_connect_after_success=true
video_remained_disabled=true
camera_permission_remained_false=true
matrix_event_emit_remained_false=true
full_call_flow_remained_false=true
raw_credentials_logged=false
```

If code changes are needed, keep them narrow and default-off. Do not use the physical helper again unless a later prompt explicitly authorizes a new one-shot phase.

## Hard Limits

Do not:

- send APNs
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
- consume the DEBUG hook before metadata plus credentials eligibility
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

- Physical8 close status
- next phase
- commit hash if docs or code were updated
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no repeated APNs, no production APNs, no `dev/invite`, no repeated connect, no video, no camera permission, no Matrix event emit, and no full call flow were performed
