# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderConnectExecutorUnificationRepair` is complete.

The receiver controlled connect path now calls a shared `DirectCallLiveKitConnectExecutor`, and the sender join proof boundary is bound to the same executor model instead of only reporting parity.

Required proof/source-guard fields are now available:

```text
sender_connect_executor_unification_present=true
sender_connect_executor_unification_debug_only=true
sender_connect_executor_unification_receiver_executor_shared=true
sender_connect_executor_unification_sender_executor_shared=true
sender_connect_executor_unification_same_connect_options_shape=true
sender_connect_executor_unification_same_room_retention_model=true
sender_connect_executor_unification_same_delegate_retention_model=true
sender_connect_executor_unification_same_state_observer_model=true
sender_connect_executor_unification_same_bounded_wait_model=true
sender_connect_executor_unification_audio_only=true
sender_connect_executor_unification_video_allowed=false
sender_connect_executor_unification_matrix_events_allowed=false
sender_connect_executor_unification_raw_url_logged=false
sender_connect_executor_unification_raw_token_logged=false
sender_connect_executor_unification_raw_room_logged=false
sender_connect_executor_unification_raw_identity_logged=false
```

The previous physical result remains:

```text
2.48Z-Physical2-Retry11 =
safe sender connect parity timeout / remote participant not observed triage, not remote-audio success
```

Retry11 receiver path succeeded once:

```text
physical_voip_push_received=true
callkit_report_result=reported
callkit_first_action_kind=answer
pending_metadata_fetch_result=success_redacted
media_credentials_result=success_redacted
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_repeated=false
livekit_join_result=success_redacted
```

Retry11 sender path still timed out before this repair:

```text
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_result=failed_redacted
sender_livekit_sdk_timeline_final_classification=sdk_connect_timeout_connect_call_pending_redacted
sender_livekit_sdk_timeout_diagnostics_final_classification=sdk_connect_timeout_connect_call_pending_redacted
receiver_remote_participant_observer_result=not_observed_redacted
livekit_audio_liveness_result=not_observed_redacted
```

Safety remains:

```text
sender join remains one-shot
repeated sender join remains blocked/classified
sender_livekit_sdk_timeout_diagnostics_final_classification=<redacted_bucket>
sender_join_success_but_remote_missing_redacted remains separate
default_runtime_no_connect=true
default_runtime_no_join=true
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, video, microphone/camera permission, Matrix event emit, full call flow, or physical hook reset/re-arm was performed during the repair.

## Next Phase

`2.48Z-Physical2-Retry12 — one-shot two-physical-device shared sender connect executor proof`

This is a physical one-shot proof with two physical iOS devices.

Do not run this until both physical devices are available, both Debug apps are freshly installed/launched from the latest repair commit, and both Matrix sessions are valid.

Required preflight/proof expectations:

```text
receiver and sender are distinct accounts
both devices are in the same encrypted room
receiver app session is valid
sender app session is valid
sender_connect_executor_unification_present=true
sender_connect_executor_unification_receiver_executor_shared=true
sender_connect_executor_unification_sender_executor_shared=true
sender_connect_executor_unification_same_connect_options_shape=true
sender_connect_executor_unification_same_room_retention_model=true
sender_connect_executor_unification_same_delegate_retention_model=true
sender_connect_executor_unification_same_state_observer_model=true
sender_connect_executor_unification_same_bounded_wait_model=true
sender_connect_executor_unification_audio_only=true
sender_connect_executor_unification_video_allowed=false
sender_connect_executor_unification_matrix_events_allowed=false
sender_connect_executor_unification_raw_url_logged=false
sender_connect_executor_unification_raw_token_logged=false
sender_connect_executor_unification_raw_room_logged=false
sender_connect_executor_unification_raw_identity_logged=false
sender_side_livekit_join_repeated=false
```

If the sender connect still times out, classify with the existing timeout diagnostics:

```text
sender_livekit_sdk_timeline_connect_invoked=true
sender_livekit_sdk_timeline_connect_returned=false
sender_livekit_sdk_timeline_connect_threw=false
sender_livekit_sdk_timeout_diagnostics_final_classification=<redacted_bucket>
sender_join_trigger_orchestration_final_classification=sender_trigger_completed_sdk_timeline_terminal_redacted
```

Success still requires remote participant/audio/liveness observation:

```text
receiver_remote_participant_observer_result=success_redacted
livekit_remote_participant_seen=true
livekit_remote_audio_track_subscribed=true
livekit_audio_liveness_result=success_redacted
```

If remote participant/audio/liveness is not observed, classify and do not retry automatically.

## Hard Limits

Do not:

* send APNs until the one-shot helper reaches explicit confirmation
* run production APNs
* run repeated APNs
* run `dev/invite`
* repeat receiver connect
* repeat sender LiveKit join
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized SDK error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Suggested Checks

Before any future docs commit, run:

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

* Retry12 classification
* whether executor-unification fields are present
* whether sender and receiver share the same executor model in proof
* sender connect result
* receiver remote participant/audio/liveness result
* whether safety fields stayed closed
* proof generation and proof path
* final `git status --short --branch`
