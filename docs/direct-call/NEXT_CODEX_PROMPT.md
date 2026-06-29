# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-ReceiverVoIPPushDeliveryRegressionTriage` is committed.

Retry23 is closed as APNs accepted / receiver VoIP PushKit callback missing triage. It is not participant observer propagation validation and not remote participant success.

Retry23 physical result:

```text
room_validation_preflight=pass
invite_http_status_bucket=2xx
background_apns_push_requested=true
background_apns_push_result=sandbox_success
APNs_sent=true
pending_metadata_reference_present=true
physical_voip_push_received=false
callkit_answer_action_received=false
controlled_connect_first_attempt_result=not_requested
livekit_join_result=not_requested
sender_connected_signal_received_by_receiver=false
sender_runtime_join_triggered=false
blocked_reason=voip_push_not_received
```

Root cause narrowed:

```text
sandbox APNs was accepted, but receiver proof did not observe PushKit callback or CallKit report.
```

New DEBUG-only delivery triage proof surface:

```text
receiver_voip_push_delivery_triage_present=true
receiver_voip_push_delivery_triage_debug_only=true
receiver_voip_push_delivery_triage_raw_identifiers_logged=false
receiver_pushkit_token_present_before_apns=<redacted_bool>
receiver_pushkit_token_upload_attempted_before_apns=<redacted_bool>
receiver_pushkit_token_upload_result_bucket=success_redacted|failed_redacted|not_requested|unknown
receiver_pushkit_token_server_store_result_bucket=persisted_redacted|failed_redacted|not_requested|unknown
receiver_pushkit_token_environment_bucket=development|production|mismatch_possible_redacted|unknown
receiver_pushkit_token_device_binding_expected_bucket=expected_redacted|mismatch_possible_redacted|not_requested|unknown
receiver_app_lifecycle_state_before_apns_bucket=foreground|background|inactive|unknown
receiver_app_proof_generation_before_apns=<redacted_generation_or_unknown>
receiver_app_proof_generation_after_apns_changed=<redacted_bool>
receiver_voip_push_callback_seen_after_apns=<redacted_bool>
receiver_callkit_report_requested_after_apns=<redacted_bool>
receiver_callkit_answer_available_after_apns=<redacted_bool>
apns_provider_acceptance_result_bucket=2xx|non_2xx|not_requested|unknown
apns_delivery_callback_missing_after_acceptance=<redacted_bool>
receiver_voip_push_delivery_final_classification=<redacted_classification>
```

Classifications:

```text
receiver_pushkit_token_missing_before_apns_redacted
receiver_pushkit_token_upload_failed_before_apns_redacted
receiver_pushkit_token_environment_mismatch_possible_redacted
receiver_pushkit_token_device_binding_unknown_redacted
apns_accepted_but_receiver_callback_missing_redacted
receiver_callkit_not_reported_after_apns_redacted
receiver_voip_push_received_redacted
```

Safety preserved:

```text
no APNs during repair
no repeated APNs
no production APNs
no dev/invite
no physical media connect during repair
no physical LiveKit join during repair
no microphone/camera permission
no video
no Matrix event emit
no full direct-call flow
no raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room/call/user/device/pending-metadata logging
```

## Next Phase

`2.48Z-Physical2-Retry24 — one-shot receiver VoIP push delivery triage, receiver iPhone PRO, sender Carpediem`

Goal:
Run one physical proof to classify why APNs acceptance did not produce a receiver PushKit callback in Retry23. Do not move back to participant observer validation until receiver PushKit/CallKit delivery is proven again.

Required devices:

```text
receiver=iPhone PRO
sender=Carpediem
do not use iPhone Жанелька unless roles are explicitly changed
do not use Simulator
```

Before APNs:

```text
current_head_matches_expected=true
receiver_device_connected=true
sender_device_connected=true
receiver_app_matrix_session_whoami_result=success_redacted
sender_app_matrix_session_whoami_result=success_redacted
room_validation_preflight=pass
receiver_voip_push_delivery_triage_present=true
receiver_voip_push_delivery_triage_debug_only=true
receiver_voip_push_delivery_triage_raw_identifiers_logged=false
receiver_pushkit_token_present_before_apns=true
receiver_pushkit_token_upload_attempted_before_apns=true
receiver_pushkit_token_upload_result_bucket=success_redacted
receiver_pushkit_token_server_store_result_bucket=persisted_redacted
receiver_pushkit_token_environment_bucket=development
receiver_app_lifecycle_state_before_apns_bucket=foreground|background|inactive
APNs_sent=false
```

If token/upload preflight is not green, stop before APNs and report the redacted blocker.

After exactly one explicit manual confirmation, send at most one sandbox APNs.

Expected success path:

```text
background_apns_push_result=sandbox_success
APNs_sent=true
receiver_app_proof_generation_after_apns_changed=true
receiver_voip_push_callback_seen_after_apns=true
physical_voip_push_received=true
receiver_callkit_report_requested_after_apns=true
callkit_answer_action_received=true
receiver_voip_push_delivery_final_classification=receiver_voip_push_received_redacted
```

If APNs is accepted but no receiver callback is observed:

```text
apns_provider_acceptance_result_bucket=2xx
apns_delivery_callback_missing_after_acceptance=true
receiver_app_proof_generation_after_apns_changed=false
receiver_voip_push_callback_seen_after_apns=false
receiver_callkit_report_requested_after_apns=false
receiver_voip_push_delivery_final_classification=apns_accepted_but_receiver_callback_missing_redacted
```

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

Commit only if Retry24 narrows the blocker further or restores receiver PushKit/CallKit delivery with useful redacted proof.
