# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderLiveKitSDKUnknownErrorRepair` is complete.

Sender-side LiveKit SDK unknown failures now have a DEBUG/test-controlled redacted SDK failure surface. It breaks down the previous broad `transport_livekit_sdk_unknown_error_redacted` bucket into specific redacted SDK buckets and maps the refined classification into:

```text
sender_transport_error_surface_final_classification
sender_transport_failure_diagnostics_classification
sender_side_livekit_join_error_bucket
sender_side_livekit_join_result
```

New proof fields:

```text
sender_livekit_sdk_failure_surface_present=true
sender_livekit_sdk_failure_surface_debug_only=true
sender_livekit_sdk_failure_surface_raw_error_logged=false
sender_livekit_sdk_failure_surface_raw_url_logged=false
sender_livekit_sdk_failure_surface_raw_token_logged=false
sender_livekit_sdk_failure_surface_raw_room_logged=false
sender_livekit_sdk_failure_surface_raw_identity_logged=false
sender_livekit_sdk_failure_surface_connect_call_started=<redacted_bool>
sender_livekit_sdk_failure_surface_connect_call_returned=<redacted_bool>
sender_livekit_sdk_failure_surface_connect_call_threw=<redacted_bool>
sender_livekit_sdk_failure_surface_connected_state_observed=<redacted_bool>
sender_livekit_sdk_failure_surface_failed_state_observed=<redacted_bool>
sender_livekit_sdk_failure_surface_disconnected_before_connected=<redacted_bool>
sender_livekit_sdk_failure_surface_delegate_failure_observed=<redacted_bool>
sender_livekit_sdk_failure_surface_room_already_connected=<redacted_bool>
sender_livekit_sdk_failure_surface_identity_conflict_observed=<redacted_bool>
sender_livekit_sdk_failure_surface_token_identity_match=<redacted_bool>
sender_livekit_sdk_failure_surface_audio_session_ready=<redacted_bool>
sender_livekit_sdk_failure_surface_permission_required=<redacted_bool>
sender_livekit_sdk_failure_surface_capture_started=<redacted_bool>
sender_livekit_sdk_failure_surface_final_classification=<redacted_sdk_bucket>
```

Specific redacted SDK buckets:

```text
sdk_connect_call_threw_redacted
sdk_connect_returned_without_connected_redacted
sdk_delegate_failed_before_connected_redacted
sdk_disconnected_before_connected_redacted
sdk_state_failed_redacted
sdk_room_already_connected_redacted
sdk_identity_conflict_redacted
sdk_token_identity_mismatch_redacted
sdk_audio_session_blocked_redacted
sdk_permission_or_capture_blocked_redacted
sdk_network_transport_error_redacted
sdk_internal_unknown_redacted
```

Safety and separation remain:

```text
raw_sdk_error_logged=false
raw_livekit_url_logged=false
raw_token_logged=false
raw_room_logged=false
raw_identity_logged=false
existing_transport_buckets_remain_intact=true
sender_join_success_but_remote_missing_separate=true
default_runtime_no_connect=true
```

Checks completed in the repair phase:

```text
swiftformat_passed=true
swiftlint_expected_file_length_warning_only=true
direct_call_subset_passed=true
direct_call_subset_tests=156
```

## Next Phase

`2.48Z-Physical2-Retry7 — one-shot two-physical-device sender LiveKit SDK failure-source proof`

Use this phase to run exactly one future physical proof that captures the new sender SDK failure surface. Do not treat the prior Retry6 result as remote-audio success.

## Hard Limits

Do not:

* send APNs until the future one-shot helper reaches explicit confirmation
* send production APNs
* send repeated APNs
* run `dev/invite`
* run repeated connect
* run repeated LiveKit join
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Retry7 Requirements

Before any future APNs send, verify:

```text
two_physical_devices_connected=true
receiver_app_session_ready=success_redacted
sender_app_session_ready=success_redacted
receiver_sender_distinct=true
same_encrypted_room_validated=true
corrected_flat_schema_used=true
sender_livekit_sdk_failure_surface_present=true
safe_to_send_apns=true
```

After the operator presses Answer once, copy/poll the phase-specific proof and classify these fields:

```text
sender_livekit_sdk_failure_surface_connect_call_started
sender_livekit_sdk_failure_surface_connect_call_returned
sender_livekit_sdk_failure_surface_connect_call_threw
sender_livekit_sdk_failure_surface_connected_state_observed
sender_livekit_sdk_failure_surface_failed_state_observed
sender_livekit_sdk_failure_surface_disconnected_before_connected
sender_livekit_sdk_failure_surface_delegate_failure_observed
sender_livekit_sdk_failure_surface_room_already_connected
sender_livekit_sdk_failure_surface_identity_conflict_observed
sender_livekit_sdk_failure_surface_token_identity_match
sender_livekit_sdk_failure_surface_audio_session_ready
sender_livekit_sdk_failure_surface_permission_required
sender_livekit_sdk_failure_surface_capture_started
sender_livekit_sdk_failure_surface_final_classification
sender_transport_error_surface_final_classification
sender_transport_failure_diagnostics_classification
sender_side_livekit_join_error_bucket
sender_side_livekit_join_result
```

Stop conditions:

```text
if APNs sent once, do not repeat automatically
if sender_livekit_sdk_failure_surface_final_classification=not_requested after sender join requested, stop and classify
if raw_error_logged=true, stop as privacy regression
if raw_url_logged=true, stop as privacy regression
if raw_token_logged=true, stop as privacy regression
if raw_room_logged=true, stop as privacy regression
if raw_identity_logged=true, stop as privacy regression
if repeated_apns_observed=true, stop as safety regression
if repeated_livekit_join_observed=true, stop as safety regression
if camera_permission_requested=true, stop as safety regression
if matrix_event_emit_requested=true, stop as safety regression
if real_call_flow_started=true, stop as safety regression
```

## Suggested Checks

Before and after edits or close-out:

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

* current phase conclusion
* whether sender SDK failure surface classified into a specific redacted bucket
* whether raw error/URL/token/room/identity stayed unlogged
* whether existing transport buckets remained intact
* whether sender join success-but-remote-missing stayed separate
* whether default runtime remained no-connect
* checks run
* final `git status --short --branch`
