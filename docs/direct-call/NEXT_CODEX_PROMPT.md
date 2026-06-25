# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-RemoteParticipantObservationTimingRepair` is complete as a code/test phase.

Retry13 classified as:

```text
real sender runtime join success
receiver remote participant not observed
```

Receiver proof generation `generation_27` showed PushKit, CallKit Answer, pending metadata, credentials, controlled receiver connect, and receiver LiveKit join succeeded, but:

```text
livekit_remote_participant_seen=false
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_error_bucket=sender_readiness_context_missing_redacted
```

Sender proof generation `generation_12` showed the real sender runtime bridge was triggered and consumed once, used the restored Matrix session, fetched sender pending metadata, requested sender credentials, invoked the shared `DirectCallLiveKitConnectExecutor`, and produced:

```text
sender_runtime_join_runtime_result=success_redacted
sender_runtime_join_runtime_error_bucket=none
sender_runtime_join_runtime_derived=true
sender_runtime_join_query_outcome_ignored=true
```

The repair adds DEBUG-only bounded receiver observation timing proof:

```text
remote_participant_observation_timing_repair_present=true
remote_participant_observation_timing_repair_debug_only=true
remote_participant_observation_timing_repair_bounded_window=true
remote_participant_observation_timing_repair_raw_identifiers_logged=false
receiver_room_retained_for_sender_observation=<redacted_bool>
receiver_observer_attached_before_sender_join=<redacted_bool>
receiver_observer_active_during_sender_join=<redacted_bool>
receiver_cleanup_deferred_until_observation_terminal=<redacted_bool>
receiver_cleanup_started_before_sender_terminal=<redacted_bool>
sender_join_terminal_seen_by_receiver=<redacted_bool>
sender_room_connected_during_receiver_window=<redacted_bool>
sender_cleanup_started_before_receiver_observation=<redacted_bool>
receiver_sender_connected_window_overlap_observed=<redacted_bool>
sender_readiness_context_present_during_observation=<redacted_bool>
opaque_call_correlation_present=<redacted_bool>
opaque_call_correlation_match=<redacted_bool>
remote_participant_observation_wait_started=<redacted_bool>
remote_participant_observation_wait_completed=<redacted_bool>
remote_participant_observation_timeout_bucket=<redacted_bucket>
remote_participant_observation_final_classification=<redacted_bucket>
```

Runtime receiver LiveKit delegate callbacks can now close the window as:

```text
remote_participant_observation_final_classification=remote_participant_seen_redacted
```

Otherwise the bounded timeout classifies one of:

```text
receiver_disconnected_before_sender_join_redacted
receiver_observer_attached_late_redacted
receiver_observer_not_active_during_sender_join_redacted
sender_readiness_context_missing_redacted
opaque_correlation_mismatch_redacted
no_receiver_sender_connected_overlap_redacted
sender_disconnected_before_observation_redacted
remote_participant_event_timeout_redacted
```

Missing audio track is not sender-join failure; classify participant presence first.

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

`2.48Z-Physical2-Retry14 — one-shot real sender join with retained receiver observation window`

Goal:
Run one physical two-device proof using the existing one-shot receiver APNs/Answer/connect path and the real sender runtime bridge, then verify whether the retained receiver observation window sees the sender as a LiveKit remote participant.

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

If receiver remote participant is observed:

```text
livekit_remote_participant_seen=true
remote_participant_observation_final_classification=remote_participant_seen_redacted
```

Close Retry14 as real sender runtime join plus receiver remote participant observed. Next phase should inspect audio publish/subscription readiness without repeating connect.

If sender join succeeds but receiver still does not see a participant, do not retry. Classify using the new receiver observation timing fields and close as a narrowed timing blocker.

## Hard Limits

Do not:

* send APNs before explicit one-shot confirmation
* run production APNs
* run repeated APNs
* run `dev/invite`
* repeat receiver connect
* repeat sender LiveKit join
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized SDK error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`
