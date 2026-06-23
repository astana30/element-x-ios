# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Y-Physical3` is complete and safely classified.

Conclusion:

```text
2.48Y-Physical3 = simulator-assisted remote peer context/liveness proof safely classified.
One sandbox APNs sent.
Remote peer context successfully reached runtime proof and survived PushKit plus Answer.
First controlled audio connect succeeded and LiveKit join succeeded once.
Remote audio/liveness was not observed because no remote LiveKit participant appeared.
Simulator-assisted limitation recorded.
No retry performed.
```

This was not a production-like two-physical-device remote audio proof:

```text
remote_peer_kind=ios_simulator_redacted
remote_peer_physical_device=false
simulator_assisted_remote_audio_proof=true
production_like_two_physical_device_proof=false
remote_audio_liveness_limitation=simulator_assisted_redacted
```

Phase-specific proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48y-physical3-simulator-context-liveness-polled.txt
```

Key proof fields:

```text
proof_generation=generation_15
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled

callkit_report_result=reported
callkit_report_completion_observed=true
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true

pending_metadata_fetch_requested=true
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx

media_credentials_requested=true
media_credentials_result=success_redacted

controlled_connect_first_attempt_requested=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_error_bucket=none

media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
livekit_join_result=success_redacted
livekit_cleanup_result=completed_redacted
```

The remote peer context handoff worked:

```text
remote_peer_context_handoff_present=true
remote_peer_context_handoff_debug_only=true
remote_peer_context_handoff_source=debug_hook_redacted
remote_peer_context_handoff_armed_before_apns=true
remote_peer_context_handoff_received_by_runtime=true
remote_peer_context_handoff_survived_pushkit=true
remote_peer_context_handoff_survived_answer=true
remote_peer_context_handoff_raw_identifiers_logged=false
```

Remote audio/liveness did not succeed:

```text
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
```

Safety stayed closed:

```text
local_audio_publish_result=not_required_redacted
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

No repeated APNs, no production APNs, no `dev/invite`, no repeated connect, no repeated LiveKit join, no video, no camera permission, no Matrix event emit, no full call flow, and no project/signing changes were performed.

## Next Phase

`2.48Z — two-physical-device remote audio proof readiness, no repeated connect`

Do not repeat the simulator-assisted Physical3 attempt. The next phase should prepare a real second physical iOS device or explicitly classify why it is not ready.

## Goal

Prepare for a production-like two-physical-device remote audio proof without sending APNs or starting another connect until the second physical device is verified ready and the task explicitly requests a one-shot proof.

Required readiness classification:

```text
remote_peer_kind=physical_ios_redacted
remote_peer_physical_device=true
simulator_assisted_remote_audio_proof=false
production_like_two_physical_device_proof=true
second_device_remote_audio_readiness=<ready_redacted_or_not_ready_redacted>
remote_audio_liveness_limitation=<none_or_redacted_reason>
```

If the second physical device is not available, stop and classify readiness only:

```text
second_device_remote_audio_readiness=not_ready_redacted
production_like_two_physical_device_proof=false
APNs_sent=false
media_connect_requested=false
livekit_join_requested=false
```

## Hard Limits

Do not:

- send APNs unless a new one-shot physical proof task explicitly asks for it
- run production APNs
- run repeated APNs
- use `dev/invite`
- retry media connect from Physical3
- retry LiveKit join from Physical3
- request camera permission
- enable video
- emit Matrix events
- start full direct-call flow
- log/document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`

## Required Checks Before Close

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

- second physical device readiness classification
- whether simulator-assisted proof is no longer being used for production-like success
- whether APNs remained unsent during readiness work
- whether no repeated connect or LiveKit join was performed
- whether camera/video/Matrix/full-flow safety stayed closed
- checks run
- final `git status --short --branch`
