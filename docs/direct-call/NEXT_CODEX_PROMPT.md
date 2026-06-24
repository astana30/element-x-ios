# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry11-SenderConnectParityTimeoutTriage` is complete.

The one-shot two-physical-device sender connect parity proof is safely classified as sender SDK connect-call-pending timeout / remote participant not observed triage, not remote-audio success.

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry11-sender-connect-parity-polled.txt
```

Proof generation:

```text
proof_generation=generation_16
```

Receiver path succeeded once:

```text
physical_voip_push_received=true
callkit_report_result=reported
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
pending_metadata_fetch_result=success_redacted
media_credentials_result=success_redacted
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_repeated=false
livekit_join_result=success_redacted
```

Sender connect parity was present:

```text
sender_connect_parity_present=true
sender_connect_parity_uses_receiver_proven_connect_wrapper=true
sender_connect_parity_uses_audio_only=true
sender_connect_parity_video_allowed=false
sender_connect_parity_matrix_events_allowed=false
sender_connect_parity_room_retained_until_terminal=true
sender_connect_parity_delegate_retained_until_terminal=true
sender_connect_parity_state_observer_retained_until_terminal=true
sender_connect_parity_task_retained_until_terminal=true
sender_connect_parity_bounded_wait_used=true
```

Sender join fired once but the SDK connect stayed pending until terminal timeout:

```text
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=transport_livekit_sdk_unknown_error_redacted
sender_side_livekit_join_repeated=false
sender_livekit_sdk_timeline_connect_invoked=true
sender_livekit_sdk_timeline_connect_returned=false
sender_livekit_sdk_timeline_connect_threw=false
sender_livekit_sdk_timeline_task_cancelled=false
sender_livekit_sdk_timeline_final_classification=sdk_connect_timeout_connect_call_pending_redacted
sender_livekit_sdk_timeout_diagnostics_connect_call_pending_at_timeout=true
sender_livekit_sdk_timeout_diagnostics_task_running_at_timeout=true
sender_livekit_sdk_timeout_diagnostics_delegate_attached=true
sender_livekit_sdk_timeout_diagnostics_state_observer_attached=true
sender_livekit_sdk_timeout_diagnostics_network_path_bucket=satisfied_redacted
sender_livekit_sdk_timeout_diagnostics_final_classification=sdk_connect_timeout_connect_call_pending_redacted
sender_join_trigger_orchestration_final_classification=sender_trigger_completed_sdk_timeline_terminal_redacted
```

Remote participant/audio/liveness were not observed:

```text
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_error_bucket=sender_join_failed_redacted
receiver_remote_participant_observer_remote_seen=false
receiver_remote_participant_observer_audio_track_seen=false
receiver_remote_participant_observer_liveness_seen=false
livekit_remote_participant_seen=false
livekit_remote_audio_track_subscribed=false
livekit_audio_liveness_result=not_observed_redacted
```

Safety stayed closed:

```text
no_repeated_apns=true
no_production_apns=true
dev_invite_used=false
no_repeated_connect=true
no_repeated_livekit_join=true
video_enabled=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

No repeated APNs, production APNs, `dev/invite`, repeated connect, repeated LiveKit join, video, camera permission, Matrix event emit, or full call flow was performed during close-out.

## Next Phase

`2.48Z-SenderLiveKitConnectPendingRuntimeRepair — investigate sender SDK connect-call-pending despite parity, no APNs/connect`

This is a no-APNs/no-physical-connect repair phase.

Do not run another physical APNs attempt yet.

Investigate why the sender-side LiveKit SDK connect remains pending despite:

```text
sender_connect_parity_uses_receiver_proven_connect_wrapper=true
sender_connect_parity_room_retained_until_terminal=true
sender_connect_parity_delegate_retained_until_terminal=true
sender_connect_parity_state_observer_retained_until_terminal=true
sender_connect_parity_task_retained_until_terminal=true
sender_connect_parity_bounded_wait_used=true
sender_livekit_sdk_timeline_connect_invoked=true
sender_livekit_sdk_timeline_connect_returned=false
sender_livekit_sdk_timeline_connect_threw=false
sender_livekit_sdk_timeline_connected_state_seen=false
sender_livekit_sdk_timeline_failed_state_seen=false
sender_livekit_sdk_timeline_disconnected_state_seen=false
sender_livekit_sdk_timeout_diagnostics_task_running_at_timeout=true
sender_livekit_sdk_timeout_diagnostics_delegate_attached=true
sender_livekit_sdk_timeout_diagnostics_state_observer_attached=true
sender_livekit_sdk_timeout_diagnostics_network_path_bucket=satisfied_redacted
```

Suggested repair targets:

```text
sender-side LiveKit connect call lifecycle
sender room/task retention beyond timeout
delegate/state observer callback delivery
audio-session/capture readiness assumptions on the sender
sender-side app lifecycle while receiver CallKit flow is active
whether the sender hook should launch/foreground the sender device directly
whether SDK connect requires different sequencing than the receiver path
```

Required outcome:

```text
new or refined redacted diagnostics for sender connect pending
raw SDK errors/logs remain redacted
default runtime remains no-connect/no-join
no physical APNs attempt
```

Do not set the next phase to another physical APNs attempt unless the repair adds a concrete new discriminator or behavior fix for the sender connect pending state.

## Hard Limits

Do not:

* send APNs
* run production APNs
* run repeated APNs
* run `dev/invite`
* run physical media connect
* run physical LiveKit join
* request microphone permission
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized SDK error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Suggested Checks

Run:

```bash
git status --short --branch
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run the DirectCall subset if Swift code changes:

```bash
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
```

Allowed SwiftLint warning: existing file-length warning only.

Run privacy scans over changed files/diff. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

* implementation summary
* whether the repair adds a new discriminator or behavior fix for sender connect pending
* whether default runtime remains no-connect/no-join
* checks run
* commit hash/message
* final `git status --short --branch`
* explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, physical connect, LiveKit join, video, microphone/camera permission, Matrix event emit, or full call flow were performed
