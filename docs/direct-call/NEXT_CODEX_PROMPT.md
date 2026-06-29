# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

Retry26 sent exactly one sandbox APNs and proved the receiver reached VoIP PushKit and CallKit report submission/completion, but it did not reach CallKit Answer or any post-answer media continuation.

```text
receiver_pushkit_token_readiness_final_classification=receiver_pushkit_token_ready_before_apns_redacted
room_validation_preflight=pass
background_apns_push_result=sandbox_success
APNs_sent=true
physical_voip_push_received=true
receiver_voip_push_callback_seen_after_apns=true
receiver_callkit_report_requested_after_apns=true
receiver_callkit_report_submitted_after_apns=true
receiver_callkit_report_result_bucket=reported
receiver_callkit_report_completion_observed=true
receiver_callkit_provider_retained_for_answer=true
receiver_callkit_delegate_retained_for_answer=true
receiver_callkit_active_call_uuid_retained=true
receiver_callkit_operator_ready_to_answer_before_report=false
receiver_callkit_ui_surface_observed_by_operator=false
receiver_callkit_answer_available_after_apns=false
receiver_callkit_answer_action_received_after_apns=false
receiver_callkit_answer_window_started=true
receiver_callkit_answer_window_completed=false
receiver_callkit_answer_window_timeout=false
receiver_callkit_answer_availability_final_classification=receiver_callkit_report_submitted_but_ui_missing_redacted
receiver_post_answer_continuation_started=false
receiver_post_answer_media_credentials_requested=false
receiver_post_answer_controlled_connect_requested=false
receiver_post_answer_livekit_join_requested=false
sender_runtime_join_triggered=false
```

This narrows the blocker to receiver CallKit surface/operator readiness before Answer. It is not a media credentials, receiver connect, sender runtime join, or participant observation result.

## New Repair In HEAD

`2.48Z-ReceiverCallKitSurfaceOperatorReadinessRepair`

New DEBUG-only surface:

```text
kz.salemx.msg://debug/direct-call/receiver-callkit-operator-ready?expected_surface=<foreground|banner|fullscreen|lockscreen>
```

New redacted proof fields:

```text
receiver_callkit_surface_operator_readiness_repair_present=true
receiver_callkit_surface_operator_readiness_repair_debug_only=true
receiver_callkit_surface_operator_readiness_repair_raw_identifiers_logged=false
receiver_callkit_operator_ready_marker_requested_before_apns=<bool>
receiver_callkit_operator_ready_marker_recorded_before_report=<bool>
receiver_callkit_expected_surface_bucket=<foreground|banner|fullscreen|lockscreen|unknown>
receiver_callkit_receiver_app_state_before_apns_bucket=<foreground|background|inactive|unknown>
receiver_callkit_receiver_app_state_at_report_bucket=<foreground|background|inactive|unknown>
receiver_callkit_report_submitted_after_apns=<bool>
receiver_callkit_report_completion_observed=<bool>
receiver_callkit_answer_window_started=<bool>
receiver_callkit_answer_window_extended_for_ui_surface=<bool>
receiver_callkit_answer_window_timeout=<bool>
receiver_callkit_ui_surface_observed_by_operator=<bool>
receiver_callkit_answer_action_received_after_apns=<bool>
receiver_callkit_surface_operator_readiness_final_classification=<redacted_bucket>
```

Known classifications:

```text
receiver_callkit_surface_ready_for_answer_redacted
receiver_callkit_operator_marker_missing_redacted
receiver_callkit_report_submitted_but_ui_missing_redacted
receiver_callkit_foreground_state_requires_in_app_answer_redacted
receiver_callkit_answer_window_timeout_redacted
receiver_callkit_action_received_without_ui_marker_redacted
receiver_callkit_report_failed_before_answer_redacted
```

## Next Phase

`2.48Z-Physical2-Retry27 — one-shot CallKit surface/operator readiness validation, receiver iPhone PRO, sender Carpediem`

Goal:
Validate that the receiver helper arms the CallKit operator-ready marker before APNs, CallKit report completion produces an answerable surface/action, and only then allows post-answer media continuation. Do not send APNs until all preflight fields are green and explicit manual confirmation is entered.

Before APNs, require:

```text
current_head_matches_expected=true
receiver_device_connected=true
sender_device_connected=true
receiver_app_matrix_session_whoami_result=success_redacted
sender_app_matrix_session_whoami_result=success_redacted
room_validation_preflight=pass
receiver_pushkit_token_readiness_final_classification=receiver_pushkit_token_ready_before_apns_redacted
receiver_callkit_surface_operator_readiness_repair_present=true
receiver_callkit_surface_operator_readiness_repair_debug_only=true
receiver_callkit_surface_operator_readiness_repair_raw_identifiers_logged=false
receiver_callkit_operator_ready_marker_requested_before_apns=true
receiver_callkit_expected_surface_bucket=foreground
APNs_sent=false
```

After the single APNs/Answer attempt, require:

```text
physical_voip_push_received=true
receiver_callkit_report_submitted_after_apns=true
receiver_callkit_report_completion_observed=true
receiver_callkit_operator_ready_marker_recorded_before_report=true
receiver_callkit_answer_window_started=true
receiver_callkit_answer_window_extended_for_ui_surface=true
receiver_callkit_answer_action_received_after_apns=true
callkit_answer_action_received=true
receiver_callkit_surface_operator_readiness_final_classification=receiver_callkit_surface_ready_for_answer_redacted
```

If Answer succeeds, continue to the existing post-answer continuation proof. If the UI/action is still missing, stop after the one attempt and report the redacted `receiver_callkit_surface_operator_readiness_final_classification`.

Hard limits:

```text
do not send production APNs
do not send repeated APNs
do not use dev/invite
do not perform repeated receiver connect
do not perform repeated LiveKit join
do not request microphone/camera permission
do not enable video
do not emit Matrix events
do not start full flow
do not touch project/signing files
do not log raw token, URL, room ID, call ID, user ID, device ID, APNs payload, invite body, auth header, pending metadata contents
```
