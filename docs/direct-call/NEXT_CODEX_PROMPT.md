# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderRuntimeJoinBridgeStateRepair` is committed.

Retry20 is closed as receiver controlled connect success / sender runtime bridge stale one-shot state triage, not remote participant success.

Retry20 physical result:

```text
room_validation_preflight=pass
background_apns_push_result=sandbox_success
APNs_sent=true
receiver_path=pushkit_callkit_answer_metadata_credentials_controlled_connect_livekit_success_redacted
sender_runtime_join_trigger_requested=true
sender_runtime_join_bridge_triggered=false
sender_runtime_join_bridge_consumed=false
sender_runtime_join_bridge_repeated=true
sender_pending_metadata_reference_handoff_received_by_sender_runtime=true
sender_runtime_join_pending_metadata_fetch_result=not_requested
sender_runtime_join_credentials_result=not_requested
sender_runtime_join_executor_invoked=false
sender_runtime_join_runtime_result=not_requested
sender_livekit_room_connected=false
```

Root cause:

```text
sender runtime bridge stale consumed latch blocked current-generation trigger
```

Repair:

```text
sender_runtime_join_bridge_state_repair_present=true
sender_runtime_join_bridge_state_repair_debug_only=true
sender_runtime_join_bridge_state_repair_raw_identifiers_logged=false
sender_runtime_join_bridge_arm_generation_changed=<redacted_bool>
sender_runtime_join_bridge_trigger_generation_matches_arm=<redacted_bool>
sender_runtime_join_bridge_stale_generation_detected=<redacted_bool>
sender_runtime_join_bridge_repeated_only_after_consumed=<redacted_bool>
sender_runtime_join_bridge_state_classification=<redacted_bucket>
```

The DEBUG bridge now increments an arm generation for a fresh pending metadata reference, clears stale consumed state for that generation, and treats a trigger as repeated only when the consumed generation matches the active arm generation.

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

`2.48Z-Physical2-Retry21 — one-shot sender runtime join bridge state repair validation, no reinstall unless required`

Goal:
Run one physical two-device proof that a fresh sender pending-metadata reference arms a new bridge generation and the sender runtime join executes instead of being skipped as repeated.

Required preflight:

```text
receiver_device_connected=true
second_physical_device_connected=true
receiver_app_matrix_session_whoami_result=success_redacted
sender_app_matrix_session_whoami_result=success_redacted
room_validation_preflight=pass
receiver_controlled_audio_connect_armed=true
receiver_remote_peer_context_armed=true
receiver_sender_readiness_context_armed=true
sender_connected_signal_handoff_present=true
sender_runtime_join_bridge_state_repair_present=true
sender_runtime_join_bridge_state_repair_debug_only=true
sender_runtime_join_bridge_state_repair_raw_identifiers_logged=false
safe_to_send_apns=true
APNs_sent=false
```

After one explicit manual confirmation, send at most one sandbox APNs.

Required sender proof focus:

```text
sender_runtime_join_bridge_arm_generation_changed=true
sender_runtime_join_bridge_trigger_generation_matches_arm=true
sender_runtime_join_bridge_repeated_only_after_consumed=true
sender_runtime_join_bridge_triggered=true
sender_runtime_join_bridge_consumed=true
sender_runtime_join_bridge_repeated=false
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_executor_invoked=true
sender_runtime_join_runtime_result=success_redacted
sender_livekit_room_connected=true
sender_runtime_join_bridge_state_classification=sender_runtime_join_connected_redacted
```

Required receiver proof focus:

```text
receiver_pushkit_received=true
receiver_callkit_answer_received=true
receiver_pending_metadata_fetch_result=success_redacted
receiver_media_credentials_result=success_redacted
receiver_controlled_connect_first_attempt_result=success_redacted
receiver_livekit_join_result=success_redacted
receiver_sender_connected_signal_received=<redacted_bool>
receiver_sender_connected_window_overlap_observed=<redacted_bool>
livekit_remote_participant_seen=<redacted_bool>
```

If the sender bridge still does not execute:

```text
sender_runtime_join_bridge_triggered=false
sender_runtime_join_bridge_consumed=false
sender_runtime_join_bridge_repeated=<redacted_bool>
sender_runtime_join_bridge_stale_generation_detected=<redacted_bool>
sender_runtime_join_bridge_state_classification=<redacted_bucket>
blocked_reason=sender_runtime_join_bridge_state_repair_failed_redacted
```

Hard limits:
- do not use production APNs or `dev/invite`
- do not repeat APNs, receiver connect, or sender join
- no video, camera permission, Matrix event emission, or full direct-call flow
- do not touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`
- do not expose raw tokens, URLs, room IDs, call IDs, user IDs, device IDs, call handles, APNs payloads, invite bodies, auth headers, or pending metadata contents
