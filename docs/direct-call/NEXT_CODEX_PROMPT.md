# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderConnectPendingParityRepair` is complete.

The sender LiveKit connect proof now exposes DEBUG/test-controlled parity with the receiver-proven audio-only connect wrapper while keeping default runtime no-connect/no-join:

```text
sender_connect_parity_present=true
sender_connect_parity_debug_only=true
sender_connect_parity_raw_url_logged=false
sender_connect_parity_raw_token_logged=false
sender_connect_parity_raw_room_logged=false
sender_connect_parity_raw_identity_logged=false
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

The sender one-shot join and timeout classifications remain available:

```text
sender_side_livekit_join_activation one-shot
sender_side_livekit_join_repeated=false
sender_livekit_sdk_timeout_diagnostics_final_classification=sdk_connect_timeout_connect_call_pending_redacted
sender_join_success_but_remote_missing_redacted remains separate
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, video, microphone/camera permission, Matrix event emit, full call flow, or physical hook reset/re-arm was performed during the repair.

Previous physical result remains:

```text
2.48Z-Physical2-Retry10 =
safe sender SDK connect-call-pending timeout / remote participant not observed triage
```

This was not remote-audio success. Retry10 proof generation was:

```text
proof_generation=generation_16
```

## Next Phase

`2.48Z-Physical2-Retry11 — one-shot two-physical-device sender connect parity proof`

This is a physical one-shot proof only after both physical devices are ready.

Required preflight/proof expectations:

```text
receiver and sender are distinct accounts
both devices are in the same encrypted room
receiver app session is valid
sender app session is valid
sender_connect_parity_present=true
sender_connect_parity_uses_receiver_proven_connect_wrapper=true
sender_connect_parity_uses_audio_only=true
sender_connect_parity_room_retained_until_terminal=true
sender_connect_parity_delegate_retained_until_terminal=true
sender_connect_parity_state_observer_retained_until_terminal=true
sender_connect_parity_task_retained_until_terminal=true
sender_connect_parity_bounded_wait_used=true
sender_connect_parity_video_allowed=false
sender_connect_parity_matrix_events_allowed=false
sender_side_livekit_join_repeated=false
```

Physical proof should still classify safely if the sender connect remains pending:

```text
sender_livekit_sdk_timeline_connect_invoked=true
sender_livekit_sdk_timeline_connect_returned=false
sender_livekit_sdk_timeline_connect_threw=false
sender_livekit_sdk_timeline_task_cancelled=false
sender_livekit_sdk_timeout_diagnostics_connect_call_pending_at_timeout=true
sender_livekit_sdk_timeout_diagnostics_task_running_at_timeout=true
sender_livekit_sdk_timeout_diagnostics_task_cancelled_at_timeout=false
sender_livekit_sdk_timeout_diagnostics_delegate_attached=true
sender_livekit_sdk_timeout_diagnostics_state_observer_attached=true
sender_livekit_sdk_timeout_diagnostics_network_path_bucket=satisfied_redacted
sender_livekit_sdk_timeout_diagnostics_final_classification=sdk_connect_timeout_connect_call_pending_redacted
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

Success still requires remote participant/audio/liveness observation; otherwise classify, do not retry:

```text
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_remote_seen=false
receiver_remote_participant_observer_audio_track_seen=false
receiver_remote_participant_observer_liveness_seen=false
livekit_remote_participant_seen=false
livekit_remote_audio_track_subscribed=false
livekit_audio_liveness_result=not_observed_redacted
```

Safety must stay closed:

```text
APNs_sent_once_only=true
production_apns_sent=false
dev_invite_used=false
repeated_connect=false
repeated_livekit_join=false
video_allowed=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Hard Limits

Do not:

* send APNs
* run production APNs
* run repeated APNs
* run `dev/invite`
* repeat receiver connect
* repeat sender LiveKit join
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

Allowed SwiftLint warning: existing file-length warning only.

Run privacy scans over changed files/diff. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

* Retry11 classification
* whether parity fields are present
* whether sender connect invoked/returned/threw/task/delegate/state observer fields are coherent
* whether remote participant/audio/liveness was observed
* whether safety fields stayed closed
* proof generation and proof path
* final `git status --short --branch`
