# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

Retry25 proved receiver PushKit token readiness, one sandbox APNs delivery, VoIP PushKit callback, CallKit report, and CallKit Answer availability. It did not reach controlled media connect or sender runtime join.

```text
receiver_pushkit_token_readiness_final_classification=receiver_pushkit_token_ready_before_apns_redacted
background_apns_push_result=sandbox_success
APNs_sent=true
physical_voip_push_received=true
receiver_callkit_report_requested_after_apns=true
receiver_callkit_report_submitted_after_apns=true
receiver_callkit_report_result_bucket=reported
receiver_callkit_answer_available_after_apns=true
receiver_callkit_answer_action_received_after_apns=true
callkit_answer_action_received=true
receiver_callkit_answer_availability_final_classification=receiver_callkit_answer_available_redacted
controlled_connect_first_attempt_result=not_requested
livekit_join_result=not_requested
media_connect_requested=false
livekit_join_requested=false
sender_runtime_join_triggered=false
blocked_reason=media_credentials_request_deferred_until_next_phase
```

This proves Retry25 restored APNs/PushKit/CallKit Answer, and the remaining blocker is the post-answer controlled media continuation.

## Next Phase

`2.48Z-Physical2-Retry26 — one-shot post-answer media credentials continuation validation, receiver iPhone PRO, sender Carpediem`

Goal:
Validate that after real VoIP push and CallKit Answer the DEBUG-only controlled receiver path continues through authenticated pending metadata, media credentials, controlled receiver LiveKit connect, retained receiver connected session lease, sender runtime join trigger, and overlap/participant observation. Do not require remote audio track liveness yet.

Required devices:

```text
receiver=iPhone PRO
sender=Carpediem
do not use iPhone Жанелька unless roles are explicitly changed
do not use Simulator
```

Before APNs, require:

```text
current_head_matches_expected=true
receiver_device_connected=true
sender_device_connected=true
receiver_app_matrix_session_whoami_result=success_redacted
sender_app_matrix_session_whoami_result=success_redacted
room_validation_preflight=pass
receiver_pushkit_token_readiness_repair_present=true
receiver_pushkit_token_readiness_repair_debug_only=true
receiver_pushkit_token_readiness_repair_raw_identifiers_logged=false
receiver_pushkit_registration_requested_before_apns=true
receiver_pushkit_token_callback_seen_before_apns=true
receiver_pushkit_token_present_before_apns=true
receiver_pushkit_token_upload_attempted_before_apns=true
receiver_pushkit_token_upload_result_bucket=success_redacted
receiver_pushkit_token_server_store_result_bucket=persisted_redacted
receiver_pushkit_token_environment_bucket=development
receiver_pushkit_token_device_binding_expected_bucket=expected_redacted
receiver_pushkit_token_readiness_wait_started=true
receiver_pushkit_token_readiness_wait_completed=true
receiver_pushkit_token_readiness_wait_timeout=false
receiver_pushkit_token_readiness_final_classification=receiver_pushkit_token_ready_before_apns_redacted
receiver_post_answer_media_credentials_continuation_repair_present=true
receiver_post_answer_media_credentials_continuation_repair_debug_only=true
receiver_post_answer_media_credentials_continuation_repair_raw_identifiers_logged=false
APNs_sent=false
```

After Answer, require:

```text
receiver_post_answer_continuation_started=true
receiver_post_answer_pending_metadata_reference_present=true
receiver_post_answer_pending_metadata_fetch_requested=true
receiver_post_answer_pending_metadata_fetch_result=success_redacted
receiver_post_answer_pending_metadata_authorized=true
receiver_post_answer_media_credentials_requested=true
receiver_post_answer_media_credentials_result=success_redacted
receiver_post_answer_media_credentials_expires_present=true
receiver_post_answer_controlled_connect_requested=true
receiver_post_answer_controlled_connect_result=success_redacted
receiver_post_answer_livekit_join_requested=true
receiver_post_answer_livekit_join_result=success_redacted
receiver_post_answer_final_classification=receiver_post_answer_livekit_join_success_redacted
controlled_connect_first_attempt_result=success_redacted
livekit_join_result=success_redacted
receiver_connected_session_lease_acquired=true
sender_runtime_join_triggered=true
```

If any post-answer step fails, stop after the single attempt and report the redacted `receiver_post_answer_final_classification`.

Only after a green readiness proof and explicit manual confirmation may a future helper send exactly one sandbox APNs.

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

Commit only if Retry24B narrows token readiness further or restores the green receiver PushKit token readiness proof.
