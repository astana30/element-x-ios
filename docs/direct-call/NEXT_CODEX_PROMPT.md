# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry10` is closed as:

```text
safe sender SDK connect-call-pending timeout / remote participant not observed triage
```

This is not remote-audio success.

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry10-sender-sdk-timeout-bucket-polled.txt
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

Sender join fired once and failed safely:

```text
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=transport_livekit_sdk_unknown_error_redacted
sender_side_livekit_join_repeated=false
```

Orchestration reached the required terminal state:

```text
sender_join_trigger_orchestration_apns_success_seen=true
sender_join_trigger_orchestration_receiver_answer_seen=true
sender_join_trigger_orchestration_receiver_connect_terminal_seen=true
sender_join_trigger_orchestration_sender_activation_armed=true
sender_join_trigger_orchestration_sender_trigger_required=true
sender_join_trigger_orchestration_sender_trigger_allowed=true
sender_join_trigger_orchestration_sender_trigger_started=true
sender_join_trigger_orchestration_sender_trigger_completed=true
sender_join_trigger_orchestration_poll_allowed=true
sender_join_trigger_orchestration_poll_blocked_reason=none
sender_join_trigger_orchestration_final_classification=sender_trigger_completed_sdk_timeline_terminal_redacted
```

Sender SDK timeline and timeout diagnostics narrowed the failure:

```text
sender_livekit_sdk_timeline_task_created=true
sender_livekit_sdk_timeline_task_started=true
sender_livekit_sdk_timeline_connect_invoked=true
sender_livekit_sdk_timeline_connect_returned=false
sender_livekit_sdk_timeline_connect_threw=false
sender_livekit_sdk_timeline_delegate_attached=true
sender_livekit_sdk_timeline_state_observer_attached=true
sender_livekit_sdk_timeline_connected_state_seen=false
sender_livekit_sdk_timeline_failed_state_seen=false
sender_livekit_sdk_timeline_disconnected_state_seen=false
sender_livekit_sdk_timeline_task_cancelled=false
sender_livekit_sdk_timeline_task_completed=false
sender_livekit_sdk_timeline_timeout_elapsed=true
sender_livekit_sdk_timeline_proof_written_after_terminal_state=true
sender_livekit_sdk_timeline_final_classification=sdk_connect_timeout_connect_call_pending_redacted
sender_livekit_sdk_timeout_diagnostics_connect_call_pending_at_timeout=true
sender_livekit_sdk_timeout_diagnostics_task_running_at_timeout=true
sender_livekit_sdk_timeout_diagnostics_task_cancelled_at_timeout=false
sender_livekit_sdk_timeout_diagnostics_delegate_attached=true
sender_livekit_sdk_timeout_diagnostics_state_observer_attached=true
sender_livekit_sdk_timeout_diagnostics_actor_context_available=true
sender_livekit_sdk_timeout_diagnostics_network_path_bucket=satisfied_redacted
sender_livekit_sdk_timeout_diagnostics_final_classification=sdk_connect_timeout_connect_call_pending_redacted
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

## Next Phase

`2.48Z-SenderConnectPendingParityRepair — align sender LiveKit connect with receiver-proven connect path, no APNs/connect`

Do not run another physical retry in this phase.

Focus on fixing the sender path, not adding narrower diagnostics:

```text
why receiver-controlled LiveKit join succeeds but sender-side connect call stays pending
whether sender-side connect uses the exact same LiveKit connect wrapper/options as receiver
whether sender is awaiting a different SDK API path than receiver
whether sender room/delegate/state observer retention differs from receiver
whether sender identity/participant naming conflicts with local receiver process/session context
whether sender connect should use the same bounded connect helper as receiver
whether sender connect is being invoked on the wrong actor/queue
whether sender join task needs an explicit retained room reference until connect returns
whether sender connect starts from the correct physical device app process
```

## Hard Limits

Do not:

* send APNs
* run production APNs
* run repeated APNs
* run `dev/invite`
* retry receiver connect
* retry sender LiveKit join
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
* whether sender connect now uses the receiver-proven path or why not
* whether sender room/delegate/state observer retention is repaired
* whether sender connect remains one-shot/default-disabled
* whether default runtime remains no-connect/no-join
* commit hash/message
* changed files
* checks run
* final `git status --short --branch`
