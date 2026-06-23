# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical1-RemoteParticipantMissingTriage` is complete and safely classified, not remote-audio success.

Conclusion:

```text
2.48Z-Physical1 = two-physical-device remote audio/liveness safely classified, not remote-audio success
first controlled audio connect attempted
LiveKit join result=success_redacted
remote audio/liveness result=not_observed_redacted
remote liveness blocker=remote_participant_missing_redacted
no retry performed
```

One sandbox APNs was sent after explicit confirmation:

```text
confirmation_reached=true
invite_send_attempted=true
invite_http_code=200
real_non_dev_invite_used=true
dev_invite_used=false
background_apns_push_requested=true
background_apns_push_result=sandbox_success
APNs_sent=true
```

Receiver physical proof:

```text
proof_generation=generation_13
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_report_result=reported
callkit_report_completion_observed=true
pushkit_completion_called=true
callkit_first_action_kind=answer
callkit_answer_action_delivered=true
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
media_credentials_requested=true
media_credentials_request_authorized=true
media_credentials_result=success_redacted
controlled_connect_first_attempt_requested=true
controlled_connect_first_attempt_allowed=true
controlled_connect_first_attempt_started=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=success_redacted
livekit_join_requested=true
livekit_join_result=success_redacted
```

Physical remote peer context survived into runtime:

```text
remote_peer_context_handoff_present=true
remote_peer_context_handoff_debug_only=true
remote_peer_context_handoff_armed_before_apns=true
remote_peer_context_handoff_received_by_runtime=true
remote_peer_context_handoff_survived_pushkit=true
remote_peer_context_handoff_survived_answer=true
remote_peer_context_handoff_raw_identifiers_logged=false
remote_peer_kind=physical_ios_redacted
remote_peer_physical_device=true
simulator_assisted_remote_audio_proof=false
production_like_two_physical_device_proof=true
second_device_remote_audio_readiness=ready_redacted
```

Remote participant/audio/liveness was not observed:

```text
livekit_room_connected=true
livekit_room_disconnected=true
livekit_local_participant_present=true
local_audio_publish_requested=false
local_audio_publish_result=not_required_redacted
microphone_permission_requested=false
microphone_permission_result=not_requested_or_not_required_redacted
livekit_remote_participant_seen=false
livekit_remote_participant_count_bucket=0
livekit_remote_audio_track_subscribed=false
livekit_remote_audio_track_unmuted=false
livekit_remote_audio_level_observed=false
livekit_audio_liveness_observed=false
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=remote_participant_missing_redacted
remote_audio_liveness_result=not_observed_redacted
remote_audio_liveness_error_bucket=remote_participant_missing_redacted
livekit_cleanup_requested=true
livekit_cleanup_completed=true
livekit_cleanup_result=completed_redacted
```

Safety stayed closed:

```text
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

No repeated APNs, no production APNs, no `dev/invite`, no repeated connect, no repeated LiveKit join, no video, no camera permission, no Matrix event emit, no full call flow, and no project/signing changes were performed.

## Next Phase

`2.48Z-RemoteParticipantPresenceRepair — enable/classify second physical device LiveKit participant presence, no APNs/connect`

This phase is diagnostics/planning only unless a narrow code-level diagnostic repair is required. Do not run another physical APNs or connect attempt.

## Goal

Explain why `2.48Z-Physical1` reached a successful receiver-side LiveKit join but did not observe the second physical device as a remote participant, then design the narrow boundary needed to enable/classify second-device participant presence without an APNs/connect retry.

Investigate only local code/docs/log-safe artifacts and existing redacted proof fields. Focus likely areas:

```text
remote peer only represented as receiver-side DEBUG context, not an actual sender-side LiveKit participant
caller/sender app did not join LiveKit
receive-only connect path did not publish local audio and did not require microphone permission
LiveKit room/token participant identity expectations
server invite/credentials path creates receiver credentials only
missing caller-side controlled join trigger
DEBUG-only second-device remote peer join hook
same LiveKit room/token allocation verification
```

Required diagnostic questions:

```text
did_second_physical_device_join_livekit=false_or_unknown
was_sender_side_livekit_token_requested=false_or_unknown
was_sender_side_livekit_join_requested=false_or_unknown
was_remote_peer_context_only_diagnostic=true_or_false
is_receiver_receive_only_path_expected_to_see_remote_participant_without_sender_join=true_or_false
next_required_boundary=<redacted_plan>
```

## Hard Limits

Do not:

- send APNs
- run production APNs
- run repeated APNs
- use `dev/invite`
- retry media connect
- retry LiveKit join
- start a physical call attempt
- request microphone permission
- request camera permission
- enable video
- emit Matrix events
- start full direct-call flow
- log/document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`

## Required Checks Before Commit

Run:

```bash
git diff --check
git diff --cached --check
```

Run forbidden project/signing scans:

```bash
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Privacy scan changed docs/diff for raw sensitive values.

Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- diagnostic conclusion
- whether a sender-side LiveKit participant was actually expected from 2.48Z-Physical1
- whether remote peer context was diagnostic-only
- next required boundary/repair
- commit hash if docs/code were updated
- commit message
- changed files
- checks run
- final `git status --short --branch`
