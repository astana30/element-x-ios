# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry9-SenderTimelineTimeoutTriage` is complete.

The one-shot two-physical-device sender SDK timeline proof is closed as safe sender SDK timeline timeout / remote participant not observed triage. This is not remote-audio success.

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry9-sender-sdk-timeline-orchestrated-polled.txt
```

Proof generation:

```text
proof_generation=generation_20
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
controlled_connect_first_attempt_error_bucket=none
livekit_join_result=success_redacted
```

Sender trigger orchestration reached terminal sender timeline classification:

```text
sender_join_trigger_orchestration_present=true
sender_join_trigger_orchestration_apns_success_seen=true
sender_join_trigger_orchestration_receiver_answer_seen=true
sender_join_trigger_orchestration_receiver_connect_terminal_seen=true
sender_join_trigger_orchestration_sender_activation_armed=true
sender_join_trigger_orchestration_sender_trigger_required=true
sender_join_trigger_orchestration_sender_trigger_allowed=true
sender_join_trigger_orchestration_sender_trigger_started=true
sender_join_trigger_orchestration_sender_trigger_completed=true
sender_join_trigger_orchestration_sender_trigger_missing_classified=false
sender_join_trigger_orchestration_poll_allowed=true
sender_join_trigger_orchestration_poll_blocked_reason=none
sender_join_trigger_orchestration_final_classification=sender_trigger_completed_sdk_timeline_terminal_redacted
```

Sender-side LiveKit join was triggered once and failed with the SDK timeline timeout bucket:

```text
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=transport_livekit_sdk_unknown_error_redacted
sender_side_livekit_join_repeated=false
sender_livekit_sdk_timeline_present=true
sender_livekit_sdk_timeline_connect_invoked=true
sender_livekit_sdk_timeline_connect_returned=false
sender_livekit_sdk_timeline_connected_state_seen=false
sender_livekit_sdk_timeline_failed_state_seen=false
sender_livekit_sdk_timeline_timeout_elapsed=true
sender_livekit_sdk_timeline_final_classification=sdk_timeline_connect_timeout_redacted
```

Receiver remote participant/audio/liveness was not observed:

```text
receiver_remote_participant_observer_present=true
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_error_bucket=sender_join_failed_redacted
receiver_remote_participant_observer_remote_seen=false
receiver_remote_participant_observer_audio_track_seen=false
receiver_remote_participant_observer_liveness_seen=false
livekit_remote_participant_seen=false
livekit_remote_audio_track_subscribed=false
livekit_audio_liveness_result=not_observed_redacted
remote_audio_liveness_result=not_observed_redacted
remote_audio_liveness_error_bucket=remote_participant_missing_redacted
```

Safety stayed closed:

```text
no_repeated_apns=true
no_production_apns=true
dev_invite_used=false
no_repeated_connect=true
no_repeated_livekit_join=true
video_enabled=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Next Phase

`2.48Z-SenderSDKConnectTimeoutRepair — diagnose sender SDK connect timeout after orchestrated trigger, no APNs/connect`

Goal:

```text
diagnose_sender_sdk_connect_timeout=true
no_physical_apns_retry=true
no_physical_connect_retry=true
no_sender_livekit_join_retry=true
preserve_receiver_success_once=true
preserve_sender_trigger_orchestration_guard=true
preserve_raw_error_url_token_room_identity_logged_false=true
```

Investigate the sender SDK timeout path without physical side effects:

```text
sender_livekit_sdk_timeline_connect_invoked=true
sender_livekit_sdk_timeline_connect_returned=false
sender_livekit_sdk_timeline_connected_state_seen=false
sender_livekit_sdk_timeline_failed_state_seen=false
sender_livekit_sdk_timeline_timeout_elapsed=true
sender_livekit_sdk_timeline_final_classification=sdk_timeline_connect_timeout_redacted
sender_transport_error_surface_final_classification=transport_livekit_sdk_unknown_error_redacted
sender_join_failure_diagnostics_classification=transport_failed_redacted
```

Suggested repair areas:

```text
sender LiveKit Room/connect task lifetime
sender app lifecycle while triggered from DEBUG hook
LiveKit delegate/state observer attachment before connect
audio session readiness before sender connect
token authority and room-binding comparison redacted diagnostics
timeout classification versus SDK thrown/failed/disconnected callbacks
```

## Hard Limits

Do not:

* send APNs
* run production APNs
* run repeated APNs
* run `dev/invite`
* retry physical media connect
* retry real LiveKit join
* request microphone permission
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not re-run any `2.48Z-Physical2-Retry9` one-shot APNs, sender trigger, or poll helper except for read-only proof inspection.

## Suggested Checks

Run:

```bash
git status --short --branch
git diff --check
git diff --cached --check
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
swiftformat ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
swiftlint lint ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Allowed SwiftLint warning: existing file-length warning only.

Run privacy scans over changed files/diff. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

* implementation summary
* whether sender SDK timeout diagnostics are more specific without raw values
* whether trigger orchestration guard remains intact
* whether default runtime remains no-connect/no-join
* commit hash/message
* changed files
* checks run
* final `git status --short --branch`
