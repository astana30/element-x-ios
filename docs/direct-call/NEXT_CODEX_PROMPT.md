# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry7` is closed as:

```text
safe sender SDK internal unknown / remote participant not observed triage
```

This is not remote-audio success.

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry7-sender-livekit-sdk-failure-source-polled.txt
```

Proof generation:

```text
proof_generation=generation_18
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

Sender join failed safely after one activation:

```text
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=transport_livekit_sdk_unknown_error_redacted
sender_side_livekit_join_repeated=false
```

Sender transport diagnostics:

```text
sender_transport_failure_diagnostics_transport_attempted=true
sender_transport_failure_diagnostics_transport_started=true
sender_transport_failure_diagnostics_transport_completed=true
sender_transport_failure_diagnostics_transport_result=failed_redacted
sender_transport_failure_diagnostics_error_bucket=transport_livekit_sdk_unknown_error_redacted
sender_transport_failure_diagnostics_classification=transport_livekit_sdk_unknown_error_redacted
sender_transport_failure_diagnostics_livekit_url_present=true
sender_transport_failure_diagnostics_token_present=true
sender_transport_failure_diagnostics_room_binding_present=true
sender_transport_failure_diagnostics_same_livekit_room=true
sender_transport_failure_diagnostics_same_token_authority=true
sender_transport_failure_diagnostics_receiver_sender_room_match=true
sender_transport_failure_diagnostics_receiver_sender_token_authority_match=true
```

SDK failure surface:

```text
sender_livekit_sdk_failure_surface_present=true
sender_livekit_sdk_failure_surface_raw_error_logged=false
sender_livekit_sdk_failure_surface_raw_url_logged=false
sender_livekit_sdk_failure_surface_raw_token_logged=false
sender_livekit_sdk_failure_surface_raw_room_logged=false
sender_livekit_sdk_failure_surface_raw_identity_logged=false
sender_livekit_sdk_failure_surface_connect_call_started=true
sender_livekit_sdk_failure_surface_connect_call_returned=false
sender_livekit_sdk_failure_surface_connect_call_threw=false
sender_livekit_sdk_failure_surface_connected_state_observed=false
sender_livekit_sdk_failure_surface_failed_state_observed=false
sender_livekit_sdk_failure_surface_disconnected_before_connected=false
sender_livekit_sdk_failure_surface_delegate_failure_observed=false
sender_livekit_sdk_failure_surface_room_already_connected=false
sender_livekit_sdk_failure_surface_identity_conflict_observed=false
sender_livekit_sdk_failure_surface_token_identity_match=true
sender_livekit_sdk_failure_surface_audio_session_ready=true
sender_livekit_sdk_failure_surface_permission_required=false
sender_livekit_sdk_failure_surface_capture_started=true
sender_livekit_sdk_failure_surface_final_classification=sdk_internal_unknown_redacted
```

Observer/liveness:

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

Conclusion:

```text
Retry7 proved sender-side LiveKit join reached SDK connect start, but did not return, throw, reach connected, failed state, delegate failure, or disconnected-before-connected. Token identity matched, audio session was ready, no permission/capture block was detected, and receiver/sender room/token authority matched. Final SDK bucket is sdk_internal_unknown_redacted.
```

Safety stayed closed:

```text
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
no_repeated_apns=true
no_production_apns=true
dev_invite_used=false
no_repeated_connect=true
no_repeated_livekit_join=true
video_enabled=false
```

## Next Phase

`2.48Z-SenderLiveKitSDKTimelineRepair — add redacted sender SDK connect lifecycle timeline, no APNs/connect`

Investigate why the sender proof recorded:

```text
sender_livekit_sdk_failure_surface_connect_call_started=true
sender_livekit_sdk_failure_surface_connect_call_returned=false
sender_livekit_sdk_failure_surface_connect_call_threw=false
sender_livekit_sdk_failure_surface_connected_state_observed=false
sender_livekit_sdk_failure_surface_failed_state_observed=false
sender_livekit_sdk_failure_surface_disconnected_before_connected=false
sender_livekit_sdk_failure_surface_delegate_failure_observed=false
sender_livekit_sdk_failure_surface_final_classification=sdk_internal_unknown_redacted
```

Repair direction:

```text
add_redacted_sender_sdk_connect_lifecycle_timeline=true
classify_connect_task_cancelled_or_suspended=true
classify_helper_exit_before_async_completion=true
classify_proof_written_before_sdk_callback=true
classify_bounded_wait_for_state_transition=true
classify_wrong_device_or_process_lifecycle_context=true
classify_delegate_or_state_callback_not_retained=true
classify_actor_task_isolation_callback_gap=true
```

## Hard Limits

Do not:

* send APNs
* run production APNs
* run `dev/invite`
* retry receiver connect
* retry sender LiveKit join
* request microphone/camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized error
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

* implementation summary
* whether sender SDK timeline remains redacted
* whether default runtime remains no-APNs/no-connect/no-join
* checks run
* commit hash/message
* changed files
* final `git status --short --branch`
