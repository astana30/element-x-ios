# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry4-SenderTransportFailedTriage` is complete.

This was a one-shot two-physical-device proof close-out. It must be treated as sender transport-failed / remote participant not observed triage, not remote-audio success.

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry4-sender-join-failure-bucket-polled.txt
```

APNs audit:

```text
APNs_sent=true
background_apns_push_result=sandbox_success
```

One sandbox APNs was sent by the operator-run one-shot helper after explicit confirmation for this phase. Do not send another APNs for this proof.

Receiver path reached Answer, metadata, credentials, controlled connect, and receiver LiveKit join:

```text
proof_generation=generation_18
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
sender_readiness_runtime_handoff_received_by_runtime=true
sender_readiness_runtime_handoff_survived_pushkit=true
sender_readiness_runtime_handoff_survived_answer=true
sender_readiness_runtime_handoff_matrix_session_ready=true
sender_readiness_runtime_handoff_same_room_ready=true
sender_readiness_runtime_handoff_expected_user_matched=true
```

Sender-side join activation triggered and consumed once:

```text
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=transport_failed_redacted
sender_side_livekit_join_repeated=false
```

Sender diagnostics classified the failure:

```text
sender_join_failure_diagnostics_present=true
sender_join_failure_diagnostics_credentials_present=true
sender_join_failure_diagnostics_token_present=true
sender_join_failure_diagnostics_url_present=true
sender_join_failure_diagnostics_room_binding_present=true
sender_join_failure_diagnostics_same_livekit_room=true
sender_join_failure_diagnostics_transport_attempted=true
sender_join_failure_diagnostics_transport_result=failed_redacted
sender_join_failure_diagnostics_error_bucket=transport_failed_redacted
sender_join_failure_diagnostics_classification=transport_failed_redacted
```

Receiver remote participant/audio/liveness was not observed:

```text
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_error_bucket=sender_join_failed_redacted
receiver_remote_participant_observer_remote_seen=false
receiver_remote_participant_observer_audio_track_seen=false
receiver_remote_participant_observer_liveness_seen=false
livekit_remote_participant_seen=false
livekit_remote_audio_track_subscribed=false
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=remote_participant_missing_redacted
```

Safety remained closed:

```text
controlled_connect_first_attempt_repeated=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
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

`2.48Z-SenderJoinTransportFailureRepair — investigate sender-side LiveKit transport failure before any APNs retry, no APNs/connect`

Do not set the phase to another physical APNs retry yet.

## Diagnostic Goals

Investigate why sender readiness and same-room proof were true, sender join activation consumed once, but the sender join diagnostics ended as:

```text
sender_join_failure_diagnostics_transport_attempted=true
sender_join_failure_diagnostics_transport_result=failed_redacted
sender_join_failure_diagnostics_classification=transport_failed_redacted
```

Focus on local/code diagnostics only:

```text
sender-side LiveKit transport dependency availability
sender-side LiveKit URL/token handoff shape, redacted only
audio-only sender join transport preconditions
same LiveKit room proof vs transport join target
redacted transport failure bucket mapping
receiver observer classification timing
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
