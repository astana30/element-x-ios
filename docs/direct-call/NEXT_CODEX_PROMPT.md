# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry18` is closed as sender pending-metadata handoff + real sender runtime join success / receiver connected-window overlap not observed triage.

One sandbox APNs was sent after explicit confirmation:

```text
background_apns_push_result=sandbox_success
APNs_sent=true
APNs_repeated=false
production_APNs_used=false
dev_invite_used=false
```

Receiver proof:

```text
proof_generation=generation_17
physical_voip_push_received=true
callkit_report_result=reported
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
pending_metadata_fetch_result=success_redacted
media_credentials_result=success_redacted
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_repeated=false
livekit_join_result=success_redacted
livekit_room_connected=true
livekit_room_disconnected=true
livekit_remote_participant_seen=false
```

Sender proof:

```text
proof_generation=generation_7
sender_runtime_join_bridge_triggered=true
sender_runtime_join_bridge_consumed=true
sender_runtime_join_bridge_repeated=false
sender_runtime_join_uses_restored_matrix_session=true
sender_pending_metadata_reference_handoff_received_by_sender_runtime=true
sender_runtime_join_pending_metadata_reference_present=true
sender_runtime_join_pending_metadata_reference_redacted=true
sender_runtime_join_pending_metadata_reference_matches_invite_sender_memory=true
sender_runtime_join_pending_metadata_reference_matches_sender_view_route=true
sender_runtime_join_pending_metadata_fetch_requested=true
sender_runtime_join_pending_metadata_fetch_authorized=true
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_pending_metadata_fetch_error_bucket=none
sender_runtime_join_pending_metadata_call_binding_present=true
sender_runtime_join_pending_metadata_room_binding_present=true
sender_runtime_join_pending_metadata_peer_binding_present=true
sender_runtime_join_pending_metadata_direction_valid=true
sender_runtime_join_pending_metadata_intent_audio=true
sender_runtime_join_credentials_requested=true
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_executor_invoked=true
sender_runtime_join_runtime_result=success_redacted
sender_runtime_join_runtime_error_bucket=none
sender_livekit_room_connected=true
sender_livekit_room_disconnected=false
sender_cleanup_result=deferred_for_receiver_observation_redacted
sender_runtime_join_runtime_derived=true
sender_runtime_join_query_outcome_ignored=true
```

Remaining blocker:

```text
receiver_connected_session_lease_task_retained=false
receiver_observer_active_during_sender_join=false
sender_join_terminal_seen_by_receiver=false
sender_room_connected_during_receiver_window=false
receiver_sender_connected_window_overlap_observed=false
remote_participant_observation_wait_completed=true
remote_participant_observation_final_classification=remote_participant_event_timeout_redacted
```

Safety preserved:

```text
repeated_APNs=false
production_APNs=false
dev_invite_used=false
repeated_receiver_connect=false
repeated_sender_runtime_join=false
video_allowed=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
raw URL/token/room/call/user/device IDs/pending metadata logged=false
```

## Next Phase

`2.48Z-ReceiverSenderConnectedWindowOverlapRepair — preserve receiver observation lease through sender connected window`

Goal:
Fix the receiver observation/cleanup timing so the receiver room remains connected and its observation lease task remains retained while the sender runtime join reaches connected state.

Do not send APNs for this repair. Do not run physical media connect or LiveKit join during code repair.

Investigate:

1. Why `receiver_connected_session_lease_task_retained` becomes `false` even though the pre-sender gate saw the lease/task retained.
2. Why `receiver_observer_active_during_sender_join=false` after sender runtime join was triggered.
3. Why `livekit_room_disconnected=true` on the receiver before `sender_room_connected_during_receiver_window` can become true.
4. Whether receiver cleanup starts or LiveKit disconnects before sender terminal state is propagated.
5. Whether the helper needs a post-sender-trigger polling order change, or the app must keep the receiver lease alive until sender connected/terminal propagation.

Required repair behavior:

```text
receiver_connected_session_lease_acquired=true
receiver_connected_session_lease_room_retained=true
receiver_connected_session_lease_delegate_retained=true
receiver_connected_session_lease_observer_retained=true
receiver_connected_session_lease_task_retained=true
receiver_room_retained_for_sender_observation=true
receiver_observer_attached_before_sender_join=true
receiver_observer_active_during_sender_join=true
receiver_cleanup_deferred_until_observation_terminal=true
receiver_cleanup_started_before_sender_terminal=false
sender_join_terminal_seen_by_receiver=true
sender_room_connected_during_receiver_window=true
receiver_sender_connected_window_overlap_observed=true
remote_participant_observation_wait_started=true
remote_participant_observation_wait_completed=true
remote_participant_observation_final_classification=<redacted_bucket>
```

Tests required:

- receiver lease task remains retained through sender connected/terminal propagation
- receiver cleanup cannot disconnect before sender terminal or bounded observation timeout
- sender runtime connected state can mark `sender_room_connected_during_receiver_window=true`
- receiver observer active during sender join is runtime-derived
- connected-window overlap is only true when receiver and sender room-connected windows overlap
- timeout still cleans up deterministically
- one-shot receiver connect and sender runtime join remain enforced
- video/camera/Matrix/full-flow stay false
- no raw identifiers, tokens, URLs, room IDs, call IDs, user IDs, device IDs, APNs payloads, invite bodies, or pending metadata are logged

Hard limits:

- do not use `dev/invite`
- do not send production APNs
- do not send APNs during the repair
- do not repeat receiver connect or sender runtime join
- do not enable video
- do not request camera
- do not emit Matrix events
- do not start full direct-call flow
- do not touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`
