# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry3-SenderJoinFailedTriage` is complete.

This was a one-shot two-physical-device proof close-out. It must be treated as sender-join-failed / remote participant not observed triage, not remote-audio success.

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry3-sender-join-activation-polled.txt
```

APNs audit:

```text
APNs_sent=true
background_apns_push_result=sandbox_success
```

One sandbox APNs was sent by the operator-run one-shot helper after explicit confirmation for this phase. Do not send another APNs for this proof.

Receiver path reached Answer, metadata, credentials, controlled connect, and receiver LiveKit join:

```text
proof_generation=generation_16
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_report_result=reported
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
media_credentials_requested=true
media_credentials_result=success_redacted
controlled_connect_first_attempt_requested=true
controlled_connect_first_attempt_allowed=true
controlled_connect_first_attempt_started=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_error_bucket=none
livekit_join_result=success_redacted
```

Sender readiness reached runtime and survived Answer:

```text
sender_readiness_runtime_handoff_present=true
sender_readiness_runtime_handoff_armed_before_apns=true
sender_readiness_runtime_handoff_received_by_runtime=true
sender_readiness_runtime_handoff_survived_pushkit=true
sender_readiness_runtime_handoff_survived_answer=true
sender_readiness_runtime_handoff_matrix_session_ready=true
sender_readiness_runtime_handoff_same_room_ready=true
sender_readiness_runtime_handoff_expected_user_matched=true
sender_readiness_runtime_handoff_raw_identifiers_logged=false
```

Sender-side join activation triggered and consumed once:

```text
sender_side_livekit_join_activation_armed=true
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
```

Sender-side LiveKit join failed and receiver remote participant/audio/liveness was not observed:

```text
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=sender_join_failed_redacted
sender_side_livekit_join_repeated=false
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_error_bucket=sender_join_failed_redacted
receiver_remote_participant_observer_remote_seen=false
receiver_remote_participant_observer_audio_track_seen=false
receiver_remote_participant_observer_liveness_seen=false
livekit_remote_participant_seen=false
livekit_remote_participant_count_bucket=0
livekit_remote_audio_track_subscribed=false
livekit_remote_audio_track_unmuted=false
livekit_audio_liveness_observed=false
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=remote_participant_missing_redacted
```

Safety remained closed:

```text
No repeated APNs.
No production APNs.
No dev/invite.
No repeated connect.
No repeated LiveKit join.
No video.
No camera permission.
No Matrix event emit.
No full call flow.
```

## Next Phase

`2.48Z-SenderJoinFailureDiagnostics — diagnose sender-side LiveKit join failure before any APNs retry, no APNs/connect`

Do not set the phase to another physical APNs retry yet.

## Diagnostic Goals

Investigate why sender-side join activation reached the runtime and was consumed once but ended in:

```text
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=sender_join_failed_redacted
receiver_remote_participant_observer_error_bucket=sender_join_failed_redacted
```

Focus on local/code diagnostics only:

```text
sender-side LiveKit token/credentials handoff shape
sender-side join path runtime dependency availability
audio-only sender join preconditions
redacted join error bucket mapping
receiver observer wait/classification timing
default-disabled and one-shot protections
```

## Hard Limits

Do not:

* send APNs
* send production APNs
* send repeated APNs
* run `dev/invite`
* run physical media connect
* join LiveKit on device
* request microphone permission
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Suggested Checks

Before and after edits:

```bash
git status --short --branch
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run privacy scans over changed files/diff. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

* sender join failure diagnostic conclusion
* whether default no-connect/no-join remains preserved
* whether one-shot protections remain preserved
* changed files
* checks run
* final `git status --short --branch`
