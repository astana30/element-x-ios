# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-ReceiverConnectedWindowOverlapRepair` is complete as a code/test phase.

Retry15 is closed as:

```text
real sender runtime join success
receiver connected-window overlap not observed
remote participant not observed triage
```

Retry15 proof showed:

```text
receiver_livekit_join_result=success_redacted
sender_runtime_join_runtime_result=success_redacted
sender_runtime_join_executor_invoked=true
receiver_room_retained_for_sender_observation=false
receiver_observer_attached_before_sender_join=true
receiver_observer_active_during_sender_join=false
receiver_cleanup_deferred_until_observation_terminal=true
receiver_cleanup_started_before_sender_terminal=false
receiver_sender_connected_window_overlap_observed=false
remote_participant_observation_final_classification=remote_participant_event_timeout_redacted
```

The repair adds a DEBUG-only receiver connected-session lease in the real receiver controlled-connect runtime path:

```text
receiver_connected_session_lease_present=true
receiver_connected_session_lease_debug_only=true
receiver_connected_session_lease_acquired=<runtime_bool>
receiver_connected_session_lease_room_retained=<runtime_bool>
receiver_connected_session_lease_delegate_retained=<runtime_bool>
receiver_connected_session_lease_observer_retained=<runtime_bool>
receiver_connected_session_lease_task_retained=<runtime_bool>
receiver_connected_session_lease_released=<terminal_bool>
receiver_connected_session_lease_release_reason=<redacted_bucket>
```

The lease retains the actual receiver LiveKit client, delegate/observer, E2EE context, key store, and cleanup task until one terminal condition:

```text
remote participant observed
sender runtime terminal failure
bounded receiver observation timeout
```

The physical helper now waits after receiver Answer/connect until the receiver lease and observation window are active before triggering sender runtime join.

Safety preserved during the repair:

```text
APNs_sent=false
dev_invite_used=false
production_APNs_sent=false
physical_media_connect_performed=false
physical_livekit_join_performed=false
microphone_permission_requested=false
camera_permission_requested=false
video_allowed=false
matrix_event_emit_requested=false
real_call_flow_started=false
raw URL/token/room/call/user/device IDs logged=false
```

## Next Phase

`2.48Z-Physical2-Retry16 — one-shot real sender join after receiver observation lease becomes active`

Goal:
Run one physical two-device proof using the existing one-shot receiver APNs/Answer/connect path and the real sender runtime bridge, but trigger the sender only after the receiver proof shows:

```text
receiver_connected_session_lease_acquired=true
receiver_connected_session_lease_room_retained=true
receiver_connected_session_lease_delegate_retained=true
receiver_connected_session_lease_observer_retained=true
receiver_connected_session_lease_task_retained=true
receiver_room_retained_for_sender_observation=true
receiver_observer_attached_before_sender_join=true
remote_participant_observation_wait_started=true
```

Do not run APNs until preflight is green and the operator explicitly confirms the one-shot send.

Required preflight:

```text
receiver_iphone_matrix_session_whoami_result=success_redacted
receiver_iphone_pending_metadata_auth_ready=true
second_physical_device_matrix_session_whoami_result=success_redacted
second_physical_device_pending_metadata_auth_ready=true
room_validation_preflight=pass
sender_connect_executor_unification_present=true
sender_runtime_join_bridge_present=true
sender_runtime_join_bridge_default_disabled=true
sender_runtime_join_bridge_one_shot=true
sender_runtime_join_query_outcome_ignored=true
remote_participant_observation_timing_repair_present=true
remote_participant_observation_timing_repair_bounded_window=true
safe_to_send_apns=true
```

Expected receiver proof after one APNs/Answer/connect and one sender runtime join:

```text
receiver_connected_session_lease_acquired=true
receiver_room_retained_for_sender_observation=true
receiver_observer_attached_before_sender_join=true
receiver_observer_active_during_sender_join=true
receiver_cleanup_deferred_until_observation_terminal=true
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

Close Retry16 as real sender runtime join plus receiver remote participant observed. Next phase should inspect audio publish/subscription readiness without repeating connect.

If sender join succeeds but receiver still does not see a participant, do not retry. Classify using the receiver lease, connected-window overlap, sender terminal, and remote participant observation fields.

## Hard Limits

Do not:

* send APNs before explicit one-shot confirmation
* run production APNs
* run repeated APNs
* run `dev/invite`
* repeat receiver connect
* repeat sender runtime join
* request camera or video
* emit Matrix events
* start full direct-call flow
* log raw tokens, JWTs, auth headers, APNs payloads, invite bodies, LiveKit URLs, room IDs, call IDs, user IDs, device IDs, or call handles
* touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`
* stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`
