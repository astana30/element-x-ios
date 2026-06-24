# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderSDKConnectTimeoutRepair` is complete.

Sender LiveKit SDK connect timeouts now expose DEBUG/test-controlled redacted timeout diagnostics without raw SDK error, URL, token, room, identity, APNs payload, auth header, invite body, Matrix user/device ID, or localized raw error text.

New proof fields:

```text
sender_livekit_sdk_timeout_diagnostics_present=true
sender_livekit_sdk_timeout_diagnostics_debug_only=true
sender_livekit_sdk_timeout_diagnostics_raw_error_logged=false
sender_livekit_sdk_timeout_diagnostics_raw_url_logged=false
sender_livekit_sdk_timeout_diagnostics_raw_token_logged=false
sender_livekit_sdk_timeout_diagnostics_raw_room_logged=false
sender_livekit_sdk_timeout_diagnostics_raw_identity_logged=false
sender_livekit_sdk_timeout_diagnostics_wait_window_bucket=<redacted_bucket>
sender_livekit_sdk_timeout_diagnostics_connect_invoked=<redacted_bool>
sender_livekit_sdk_timeout_diagnostics_connect_call_pending_at_timeout=<redacted_bool>
sender_livekit_sdk_timeout_diagnostics_task_running_at_timeout=<redacted_bool>
sender_livekit_sdk_timeout_diagnostics_task_cancelled_at_timeout=<redacted_bool>
sender_livekit_sdk_timeout_diagnostics_delegate_attached=<redacted_bool>
sender_livekit_sdk_timeout_diagnostics_state_observer_attached=<redacted_bool>
sender_livekit_sdk_timeout_diagnostics_state_event_count_bucket=<redacted_bucket>
sender_livekit_sdk_timeout_diagnostics_delegate_event_count_bucket=<redacted_bucket>
sender_livekit_sdk_timeout_diagnostics_app_state_bucket=<redacted_bucket>
sender_livekit_sdk_timeout_diagnostics_actor_context_available=<redacted_bool>
sender_livekit_sdk_timeout_diagnostics_network_path_bucket=<redacted_bucket>
sender_livekit_sdk_timeout_diagnostics_final_classification=<redacted_timeout_bucket>
```

Redacted timeout classifications:

```text
sdk_connect_timeout_no_state_events_redacted
sdk_connect_timeout_delegate_missing_redacted
sdk_connect_timeout_state_observer_missing_redacted
sdk_connect_timeout_task_suspended_redacted
sdk_connect_timeout_task_running_no_callback_redacted
sdk_connect_timeout_connect_call_pending_redacted
sdk_connect_timeout_network_pending_redacted
sdk_connect_timeout_auth_pending_redacted
sdk_connect_timeout_app_lifecycle_interrupted_redacted
sdk_connect_timeout_actor_isolation_suspected_redacted
sdk_connect_timeout_wait_window_too_short_redacted
sdk_connect_timeout_unknown_pending_redacted
```

Mapping:

```text
sender_livekit_sdk_timeline_final_classification=<specific_redacted_timeout_bucket>
sender_livekit_sdk_failure_surface_final_classification=<specific_redacted_timeout_bucket>
sender_transport_error_surface_final_classification=<specific_redacted_timeout_bucket>
sender_transport_failure_diagnostics_classification=<specific_redacted_timeout_bucket>
sender_side_livekit_join_error_bucket=<specific_redacted_timeout_bucket>
sender_side_livekit_join_result=failed_redacted
```

Safety and compatibility:

```text
existing_sdk_timeline_buckets_remain_intact=true
existing_sdk_failure_surface_buckets_remain_intact=true
existing_sender_transport_diagnostics_remain_intact=true
sender_join_success_but_remote_missing_separate=true
sdk_timeline_internal_pending_remains_non_terminal=true
new_timeout_buckets_are_sender_trigger_orchestration_terminal=true
default_runtime_no_connect=true
default_runtime_no_join=true
raw_error_url_token_room_identity_logged=false
```

No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, video, microphone/camera permission, Matrix event emit, full call flow, or physical hook reset/re-arm was performed in the repair phase.

## Next Phase

`2.48Z-Physical2-Retry10 — one-shot two-physical-device sender SDK timeout-bucket proof`

Retry10 target:

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
sender_join_trigger_orchestration_final_classification=sender_trigger_completed_sdk_timeline_terminal_redacted
sender_livekit_sdk_timeout_diagnostics_present=true
sender_livekit_sdk_timeout_diagnostics_final_classification=<specific_redacted_timeout_bucket>
sender_livekit_sdk_timeline_final_classification=<specific_redacted_timeout_bucket>
sender_livekit_sdk_failure_surface_final_classification=<specific_redacted_timeout_bucket>
sender_transport_error_surface_final_classification=<specific_redacted_timeout_bucket>
sender_transport_failure_diagnostics_classification=<specific_redacted_timeout_bucket>
sender_side_livekit_join_error_bucket=<specific_redacted_timeout_bucket>
sender_side_livekit_join_result=failed_redacted
```

Remote audio success still requires explicit receiver remote participant/audio/liveness observation:

```text
receiver_remote_participant_observer_result=observed_redacted
livekit_remote_participant_seen=true
livekit_remote_audio_track_subscribed=true
livekit_audio_liveness_result=observed_redacted
```

If remote participant/audio/liveness is not observed, close as triage with the specific sender timeout bucket. Do not fake success.

## Hard Limits

Do not:

* send APNs unless the explicit one-shot Retry10 helper confirmation is reached
* run production APNs
* run repeated APNs
* run `dev/invite`
* start repeated physical media connect
* start repeated real LiveKit join
* request microphone permission outside the controlled audio-only proof boundary
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Suggested Checks

Run before any physical helper:

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

* Retry10 preflight result
* whether exactly one sandbox APNs was sent, if confirmation was reached
* proof generation
* specific sender timeout bucket
* whether sender trigger orchestration reached terminal classification
* whether remote participant/audio/liveness was observed
* whether camera permission stayed false
* whether Matrix event emit stayed false
* whether full call flow stayed false
* final `git status --short --branch`
