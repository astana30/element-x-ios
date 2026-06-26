# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry16` is closed as safe pre-sender-gate triage, not remote participant success.

Retry16 result:

```text
preflight_passed=true
manual_send_confirmation_entered=true
background_apns_push_result=sandbox_success
APNs_sent=true
receiver_pushkit_callkit_answer_passed=true
receiver_pending_metadata_success=true
receiver_media_credentials_success=true
receiver_controlled_connect_reached=true
sender_runtime_join_triggered=false
remote_participant_observed=false
blocked_reason=receiver_observation_lease_not_active_before_sender_join
```

The sender was not triggered because the helper incorrectly required:

```text
receiver_observer_active_during_sender_join=true
```

before sender join was launched. That field is sender-runtime-derived and cannot be true before sender join starts. The receiver observation window timed out first.

Retry16 proof still showed the receiver path reached connect:

```text
receiver_connected_session_lease_acquired=true
receiver_connected_session_lease_room_retained=true
receiver_connected_session_lease_delegate_retained=true
receiver_connected_session_lease_observer_retained=true
receiver_room_retained_for_sender_observation=true
receiver_observer_attached_before_sender_join=true
remote_participant_observation_wait_started=true
receiver_cleanup_deferred_until_observation_terminal=true
receiver_cleanup_started_before_sender_terminal=false
receiver_connected_session_lease_release_reason=remote_participant_event_timeout_redacted
```

Safety preserved:

```text
repeated_APNs=false
production_APNs=false
dev_invite_used=false
late_sender_trigger_after_timeout=false
repeated_receiver_connect=false
repeated_livekit_join=false
video_allowed=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
raw URL/token/room/call/user/device IDs logged=false
```

## Helper Fix To Preserve

The fixed helper behavior for the next physical attempt:

```text
receiver_pre_sender_gate_excludes_sender_runtime_fields=true
```

The pre-sender gate must require only fields that can be true before sender launch:

```text
receiver_connected_session_lease_acquired=true
receiver_connected_session_lease_room_retained=true
receiver_connected_session_lease_delegate_retained=true
receiver_connected_session_lease_observer_retained=true
receiver_connected_session_lease_task_retained=true
receiver_room_retained_for_sender_observation=true
receiver_observer_attached_before_sender_join=true
receiver_cleanup_deferred_until_observation_terminal=true
receiver_cleanup_started_before_sender_terminal=false
remote_participant_observation_wait_started=true
remote_participant_observation_wait_completed=false
```

Do not require these until after sender trigger/runtime observation:

```text
receiver_observer_active_during_sender_join
receiver_sender_connected_window_overlap_observed
sender_join_terminal_seen_by_receiver
```

The helper must also keep `APNs_sent=true` after the sandbox APNs send succeeds, even if later receiver/sender checks block.

## Next Phase

`2.48Z-Physical2-Retry17 — one-shot real sender join with corrected pre-sender gate`

Goal:
Run one physical two-device proof using the existing one-shot receiver APNs/Answer/connect path and the real sender runtime bridge, triggering the sender only after the corrected receiver pre-sender lease gate is active.

Use physical devices only. Do not use Simulator, Alpamys, or iPhone Жанелька unless the operator explicitly reassigns roles.

Required preflight before manual send:

```text
receiver_iphone_matrix_session_whoami_result=success_redacted
receiver_iphone_pending_metadata_auth_ready=true
second_physical_device_matrix_session_whoami_result=success_redacted
second_physical_device_pending_metadata_auth_ready=true
matrix_accounts_distinct=true
room_validation_preflight=pass
receiver_controlled_audio_connect_armed=true
receiver_remote_peer_context_armed=true
receiver_sender_readiness_context_armed=true
sender_connect_executor_unification_present=true
sender_runtime_join_bridge_present=true
sender_runtime_join_bridge_default_disabled=true
sender_runtime_join_bridge_one_shot=true
sender_runtime_join_query_outcome_ignored=true
remote_participant_observation_timing_repair_present=true
remote_participant_observation_timing_repair_bounded_window=true
safe_to_send_apns=true
APNs_sent=false
```

After one APNs/Answer/connect, require the corrected pre-sender gate:

```text
receiver_connected_session_lease_acquired=true
receiver_connected_session_lease_room_retained=true
receiver_connected_session_lease_delegate_retained=true
receiver_connected_session_lease_observer_retained=true
receiver_connected_session_lease_task_retained=true
receiver_room_retained_for_sender_observation=true
receiver_observer_attached_before_sender_join=true
receiver_cleanup_deferred_until_observation_terminal=true
receiver_cleanup_started_before_sender_terminal=false
remote_participant_observation_wait_started=true
remote_participant_observation_wait_completed=false
receiver_pre_sender_gate_excludes_sender_runtime_fields=true
```

Then trigger the real sender runtime join exactly once.

Expected receiver proof after sender runtime join:

```text
receiver_observer_active_during_sender_join=true
sender_join_terminal_seen_by_receiver=true
sender_room_connected_during_receiver_window=true
receiver_sender_connected_window_overlap_observed=true
remote_participant_observation_wait_completed=true
```

If receiver remote participant is observed:

```text
livekit_remote_participant_seen=true
remote_participant_observation_final_classification=remote_participant_seen_redacted
```

Close Retry17 as real sender runtime join plus receiver remote participant observed. Next phase should inspect audio publish/subscription readiness without repeating connect.

If sender join succeeds but receiver still does not see a participant, do not retry. Classify using the receiver lease, connected-window overlap, sender terminal, and remote participant observation fields.

## Hard Limits

Do not:

* send APNs before explicit one-shot confirmation
* run production APNs
* run repeated APNs
* run `dev/invite`
* trigger sender after the receiver observation window has timed out
* repeat receiver connect
* repeat sender runtime join
* request camera or video
* emit Matrix events
* start full direct-call flow
* log raw tokens, JWTs, auth headers, APNs payloads, invite bodies, LiveKit URLs, room IDs, call IDs, user IDs, device IDs, or call handles
* touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`
* stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`
