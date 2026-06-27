# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-ReceiverConnectedWindowRetentionRepair` is committed.

Retry21 is closed as sender runtime join bridge state repair success / receiver connected window closed before sender signal triage, not remote participant success.

Retry21 physical result:

```text
APNs_sent=true
background_apns_push_result=sandbox_success
physical_voip_push_received=true
callkit_answer_action_received=true
controlled_connect_first_attempt_result=success_redacted
livekit_join_result=success_redacted
sender_runtime_join_bridge_trigger_generation_matches_arm=true
sender_runtime_join_bridge_stale_generation_detected=false
sender_runtime_join_bridge_repeated_only_after_consumed=true
sender_runtime_join_bridge_triggered=true
sender_runtime_join_bridge_consumed=true
sender_runtime_join_executor_invoked=true
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_runtime_result=success_redacted
sender_livekit_room_connected=true
sender_connected_signal_received_by_receiver=true
receiver_sender_connected_signal_received=true
receiver_sender_connected_window_overlap_observed=false
receiver_sender_connected_window_overlap_final_classification=sender_connected_signal_after_receiver_disconnect_redacted
livekit_remote_participant_seen=false
receiver_remote_participant_observer_result=not_observed_redacted
```

Root cause:

```text
sender runtime joined successfully, but the receiver connected LiveKit room/session lease closed before the sender-connected signal overlapped with the retained receiver room.
```

Repair:

```text
receiver_connected_window_retention_repair_present=true
receiver_connected_window_retention_repair_debug_only=true
receiver_connected_window_retention_repair_raw_identifiers_logged=false
receiver_connected_session_lease_active_before_sender_trigger=<redacted_bool>
receiver_connected_session_lease_active_after_sender_trigger=<redacted_bool>
receiver_connected_session_lease_active_at_sender_signal=<redacted_bool>
receiver_connected_session_lease_released_after_terminal=<redacted_bool>
receiver_disconnect_observed_before_sender_signal=<redacted_bool>
receiver_disconnect_observed_after_sender_signal=<redacted_bool>
receiver_participant_observation_after_overlap_started=<redacted_bool>
receiver_participant_observation_after_overlap_completed=<redacted_bool>
receiver_participant_observation_after_overlap_timeout=<redacted_bool>
```

The DEBUG receiver path now keeps the connected lease alive through one bounded sender-connected-signal wait. Once the signal is received, it resets the participant observation window and keeps the receiver room alive for the bounded post-overlap participant event wait. Cleanup runs only after terminal classification. Audio track liveness is not required for participant presence.

Safety preserved:

```text
no APNs during repair
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

`2.48Z-Physical2-Retry22 — one-shot receiver connected window retention validation, sender Жанелька, receiver iPhone PRO`

Goal:
Run one physical two-device proof that the receiver connected lease remains active until the sender-connected signal arrives, then remains alive for a bounded participant-observation window.

Required devices:

```text
receiver=iPhone PRO
sender=iPhone Жанелька
do not use Carpediem
do not use Simulator
```

Required preflight:

```text
current_head_matches_expected=true
receiver_device_connected=true
second_physical_device_connected=true
receiver_app_matrix_session_whoami_result=success_redacted
sender_app_matrix_session_whoami_result=success_redacted
room_validation_preflight=pass
receiver_controlled_audio_connect_armed=true
receiver_remote_peer_context_armed=true
receiver_sender_readiness_context_armed=true
sender_runtime_join_bridge_state_repair_present=true
sender_connected_signal_handoff_present=true
receiver_connected_window_retention_repair_present=true
receiver_connected_window_retention_repair_debug_only=true
receiver_connected_window_retention_repair_raw_identifiers_logged=false
safe_to_send_apns=true
APNs_sent=false
```

After one explicit manual confirmation, send at most one sandbox APNs.

Required sender proof focus:

```text
sender_runtime_join_bridge_trigger_generation_matches_arm=true
sender_runtime_join_bridge_stale_generation_detected=false
sender_runtime_join_bridge_repeated_only_after_consumed=true
sender_runtime_join_bridge_triggered=true
sender_runtime_join_bridge_consumed=true
sender_runtime_join_executor_invoked=true
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_runtime_result=success_redacted
sender_livekit_room_connected=true
```

Required receiver proof focus:

```text
physical_voip_push_received=true
callkit_answer_action_received=true
controlled_connect_first_attempt_result=success_redacted
livekit_join_result=success_redacted
receiver_connected_session_lease_acquired=true
receiver_connected_session_lease_room_retained=true
receiver_connected_session_lease_delegate_retained=true
receiver_connected_session_lease_observer_retained=true
receiver_connected_session_lease_task_retained=true
receiver_connected_session_lease_active_before_sender_trigger=true
receiver_connected_session_lease_active_after_sender_trigger=true
receiver_connected_session_lease_active_at_sender_signal=true
receiver_cleanup_deferred_until_observation_terminal=true
receiver_cleanup_started_before_sender_terminal=false
receiver_disconnect_observed_before_sender_signal=false
sender_connected_signal_received_by_receiver=true
receiver_sender_connected_signal_received=true
receiver_sender_connected_window_overlap_observed=true
receiver_sender_connected_window_overlap_final_classification=receiver_connected_window_overlap_observed_redacted
receiver_participant_observation_after_overlap_started=true
```

Success if participant presence is observed:

```text
livekit_remote_participant_seen=true
remote_participant_observation_final_classification=remote_participant_seen_via_retained_window_redacted
```

Acceptable narrowed blocker if participant event still times out after overlap:

```text
receiver_sender_connected_window_overlap_observed=true
receiver_participant_observation_after_overlap_started=true
receiver_participant_observation_after_overlap_completed=true
receiver_participant_observation_after_overlap_timeout=true
remote_participant_observation_final_classification=participant_observation_timeout_after_overlap_redacted
```

Hard limits:
- do not use production APNs or `dev/invite`
- do not repeat APNs, receiver connect, or sender join
- no video, camera permission, Matrix event emission, or full direct-call flow
- do not touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`
- do not expose raw tokens, URLs, room IDs, call IDs, user IDs, device IDs, call handles, APNs payloads, invite bodies, auth headers, or pending metadata contents
