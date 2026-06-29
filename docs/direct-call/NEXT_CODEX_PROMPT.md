# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

Retry24 preflight stopped before APNs because receiver PushKit token readiness was not green.

```text
receiver_app_session_restored=true
sender_app_session_restored=true
receiver_controlled_audio_connect_armed=true
receiver_remote_peer_context_armed=true
receiver_sender_readiness_context_armed=true
participant_observer_propagation_repair_present=true
receiver_connected_window_retention_repair_present=true
sender_runtime_join_bridge_state_repair_present=true
receiver_voip_push_delivery_triage_present=true
receiver_app_lifecycle_state_before_apns_bucket=foreground
receiver_pushkit_token_present_before_apns=false
receiver_pushkit_token_upload_attempted_before_apns=false
receiver_pushkit_token_upload_result_bucket=not_requested
receiver_pushkit_token_server_store_result_bucket=not_requested
receiver_pushkit_token_environment_bucket=development
receiver_pushkit_token_device_binding_expected_bucket=not_requested
APNs_sent=false
sender_runtime_join_triggered=false
```

This proves the blocker is before APNs delivery: the receiver app had not completed the redacted PushKit token registration/upload/store readiness proof.

## Next Phase

`2.48Z-Physical2-Retry24B — one-shot receiver PushKit token readiness validation before APNs, receiver iPhone PRO, sender Carpediem`

Goal:
Validate the receiver PushKit token readiness repair before any APNs send. Do not send APNs unless the readiness proof is green.

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
APNs_sent=false
```

If token readiness is not green, stop before APNs and report the redacted blocker.

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
