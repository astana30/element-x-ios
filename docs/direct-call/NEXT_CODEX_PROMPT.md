# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderLiveKitSDKTimelineRepair` is complete.

This was a no-APNs/no-connect diagnostics repair after `2.48Z-Physical2-Retry7` closed as safe sender SDK internal unknown / remote participant not observed triage, not remote-audio success.

Retry7 proved:

```text
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=transport_livekit_sdk_unknown_error_redacted
sender_livekit_sdk_failure_surface_connect_call_started=true
sender_livekit_sdk_failure_surface_connect_call_returned=false
sender_livekit_sdk_failure_surface_connect_call_threw=false
sender_livekit_sdk_failure_surface_connected_state_observed=false
sender_livekit_sdk_failure_surface_failed_state_observed=false
sender_livekit_sdk_failure_surface_disconnected_before_connected=false
sender_livekit_sdk_failure_surface_delegate_failure_observed=false
sender_livekit_sdk_failure_surface_final_classification=sdk_internal_unknown_redacted
```

## Repair Result

The sender SDK connect lifecycle now has a redacted DEBUG/test-controlled timeline:

```text
sender_livekit_sdk_timeline_present=true
sender_livekit_sdk_timeline_debug_only=true
sender_livekit_sdk_timeline_raw_error_logged=false
sender_livekit_sdk_timeline_raw_url_logged=false
sender_livekit_sdk_timeline_raw_token_logged=false
sender_livekit_sdk_timeline_raw_room_logged=false
sender_livekit_sdk_timeline_raw_identity_logged=false
sender_livekit_sdk_timeline_trigger_received=<redacted_bool>
sender_livekit_sdk_timeline_task_created=<redacted_bool>
sender_livekit_sdk_timeline_task_started=<redacted_bool>
sender_livekit_sdk_timeline_connect_invoked=<redacted_bool>
sender_livekit_sdk_timeline_connect_returned=<redacted_bool>
sender_livekit_sdk_timeline_connect_threw=<redacted_bool>
sender_livekit_sdk_timeline_delegate_attached=<redacted_bool>
sender_livekit_sdk_timeline_state_observer_attached=<redacted_bool>
sender_livekit_sdk_timeline_connected_state_seen=<redacted_bool>
sender_livekit_sdk_timeline_failed_state_seen=<redacted_bool>
sender_livekit_sdk_timeline_disconnected_state_seen=<redacted_bool>
sender_livekit_sdk_timeline_task_cancelled=<redacted_bool>
sender_livekit_sdk_timeline_task_completed=<redacted_bool>
sender_livekit_sdk_timeline_timeout_elapsed=<redacted_bool>
sender_livekit_sdk_timeline_proof_written_after_terminal_state=<redacted_bool>
sender_livekit_sdk_timeline_final_classification=<redacted_timeline_bucket>
```

Timeline classifications:

```text
sdk_timeline_task_not_created_redacted
sdk_timeline_task_created_not_started_redacted
sdk_timeline_task_cancelled_before_connect_redacted
sdk_timeline_connect_invoked_no_return_redacted
sdk_timeline_connect_timeout_redacted
sdk_timeline_delegate_not_attached_redacted
sdk_timeline_state_observer_not_attached_redacted
sdk_timeline_callback_not_observed_redacted
sdk_timeline_proof_written_before_terminal_state_redacted
sdk_timeline_app_lifecycle_interrupted_redacted
sdk_timeline_actor_isolation_lost_callback_redacted
sdk_timeline_internal_pending_redacted
```

Mapping:

```text
sender_livekit_sdk_failure_surface_final_classification=<redacted_sdk_or_timeline_bucket>
sender_transport_error_surface_final_classification=<specific_redacted_transport_bucket>
sender_transport_failure_diagnostics_classification=<specific_redacted_transport_bucket>
sender_side_livekit_join_error_bucket=<specific_redacted_transport_bucket>
sender_side_livekit_join_result=failed_redacted
existing_sdk_transport_buckets_remain_intact=true
sender_join_success_but_remote_missing_separate=true
```

Safety remains:

```text
default_runtime_no_connect=true
default_runtime_no_join=true
raw_error_url_token_room_identity_logged=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Next Phase

`2.48Z-Physical2-Retry8 — one-shot two-physical-device sender SDK timeline proof`

Use this phase to run exactly one physical proof only after the usual one-shot preflight and explicit confirmation gates pass. The proof should classify the prior sender SDK internal unknown using the new timeline fields.

## Hard Limits

Do not:

* send APNs before the one-shot helper reaches explicit confirmation
* run production APNs
* run repeated APNs
* run `dev/invite`
* retry receiver connect outside the one-shot proof
* retry sender LiveKit join outside the one-shot proof
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Suggested Checks

Before any future physical attempt:

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

* physical proof classification
* sender SDK timeline final classification
* whether raw values stayed unlogged
* whether sender join success-but-remote-missing remains separate
* whether no repeated APNs/connect/LiveKit join occurred
* final `git status --short --branch`
