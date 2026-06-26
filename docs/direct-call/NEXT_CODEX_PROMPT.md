# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry17` is closed as safe sender pending-metadata triage, not remote participant success.

Retry17 result:

```text
preflight_passed=true
manual_send_confirmation_entered=true
background_apns_push_result=sandbox_success
APNs_sent=true
receiver_pushkit_callkit_answer_passed=true
receiver_pending_metadata_success=true
receiver_media_credentials_success=true
receiver_controlled_connect_reached=true
receiver_pre_sender_gate_excludes_sender_runtime_fields=true
receiver_observation_lease_active_before_sender_join=true
sender_runtime_join_bridge_triggered=true
sender_runtime_join_bridge_consumed=true
sender_runtime_join_bridge_repeated=false
sender_runtime_join_uses_restored_matrix_session=false
sender_runtime_join_pending_metadata_fetch_result=blocked_redacted
sender_runtime_join_executor_invoked=false
sender_runtime_join_runtime_result=blocked_redacted
sender_runtime_join_runtime_error_bucket=pending_metadata_unavailable_redacted
receiver_sender_connected_window_overlap_observed=false
livekit_remote_participant_seen=false
remote_participant_observation_final_classification=opaque_correlation_mismatch_redacted
blocked_reason=sender_runtime_join_pending_metadata_reference_missing_redacted
```

Receiver proof:

```text
proof_generation=generation_41
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_repeated=false
livekit_join_result=success_redacted
receiver_connected_session_lease_acquired=true
receiver_connected_session_lease_room_retained=true
receiver_connected_session_lease_delegate_retained=true
receiver_connected_session_lease_observer_retained=true
receiver_room_retained_for_sender_observation=true
receiver_observer_attached_before_sender_join=true
remote_participant_observation_wait_started=true
remote_participant_observation_wait_completed=true
receiver_sender_connected_window_overlap_observed=false
remote_participant_observation_final_classification=opaque_correlation_mismatch_redacted
livekit_remote_participant_seen=false
```

Sender proof:

```text
proof_generation=generation_9
sender_runtime_join_bridge_triggered=true
sender_runtime_join_bridge_consumed=true
sender_runtime_join_bridge_repeated=false
sender_runtime_join_uses_restored_matrix_session=false
sender_runtime_join_pending_metadata_fetch_result=blocked_redacted
sender_runtime_join_credentials_result=not_requested
sender_runtime_join_executor_invoked=false
sender_runtime_join_runtime_result=blocked_redacted
sender_runtime_join_runtime_error_bucket=pending_metadata_unavailable_redacted
sender_runtime_join_query_outcome_ignored=true
blocked_reason=sender_runtime_join_pending_metadata_reference_missing_redacted
```

Interpretation:
- the corrected pre-sender gate worked
- the sender bridge was triggered exactly once
- sender did not reach credentials or connect because the sender runtime did not receive a pending metadata reference
- receiver classified the result as opaque correlation mismatch because sender-side pending metadata/correlation never materialized

Safety preserved:

```text
repeated_APNs=false
production_APNs=false
dev_invite_used=false
repeated_receiver_connect=false
repeated_sender_join=false
sender_credentials_requested=false
sender_executor_invoked=false
sender_livekit_join=false
video_allowed=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
raw URL/token/room/call/user/device IDs logged=false
```

## Next Phase

`2.48Z-SenderRuntimePendingMetadataReferenceRepair — make the real sender runtime bridge receive the APNs pending metadata reference`

Goal:
Repair the sender runtime bridge so the real sender device can fetch sender-view pending metadata for the same call after receiver APNs/Answer/connect, without query-selected outcomes and without any APNs/connect physical retry in this code phase.

Do not run APNs in this phase. Do not trigger sender runtime join physically.

Investigate:

1. How the receiver proof obtains `pending_metadata_reference` from the real non-dev invite/APNs payload.
2. How the pre-APNs sender readiness/correlation hook is supposed to carry or derive the same opaque reference for the sender runtime bridge.
3. Why Retry17 sender proof recorded:

   ```text
   sender_runtime_join_uses_restored_matrix_session=false
   sender_runtime_join_pending_metadata_fetch_result=blocked_redacted
   blocked_reason=sender_runtime_join_pending_metadata_reference_missing_redacted
   ```

4. Whether the sender runtime bridge currently requires a URL query parameter for pending metadata reference, uses stale proof state, or misses the receiver-provided sender readiness handoff.
5. Whether the server sender pending metadata endpoint is still correct and authenticated.

Required repair:

```text
sender_runtime_join_pending_metadata_reference_present=true
sender_runtime_join_pending_metadata_reference_redacted=true
sender_runtime_join_uses_restored_matrix_session=true
sender_runtime_join_pending_metadata_fetch_requested=true
sender_runtime_join_pending_metadata_fetch_authorized=true
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_metadata_direction=outgoing
sender_runtime_join_metadata_intent=audio
sender_runtime_join_metadata_has_call_identifier=true
sender_runtime_join_metadata_has_room_binding=true
sender_runtime_join_metadata_has_peer=true
```

The sender runtime bridge must still be:

```text
debug_only=true
default_disabled=true
one_shot=true
query_selected_join_outcomes_allowed=false
runtime_derived=true
```

Keep default no-connect/no-join. Do not request sender credentials or invoke the shared executor in this repair unless a targeted unit test uses fake/test doubles.

## Tests

Add/update targeted tests only:

```text
sender runtime bridge receives pending metadata reference from runtime handoff, not query-selected proof
sender runtime bridge uses restored Matrix session when reference is present
sender pending metadata fetch succeeds with fake/test authenticated boundary
missing reference remains blocked_redacted
query parameters cannot set pending metadata/result/timeline fields
one-shot semantics remain enforced
default runtime remains no-connect/no-join
no video/camera/Matrix/full-flow
no raw identifiers in proof
existing receiver path remains unchanged
```

Run only targeted checks:

```bash
swiftformat <changed Swift files>
swiftlint lint <changed Swift files>
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests' Tools/Scripts/verify_direct_call_unit.sh
git diff --check
git diff --cached --check
forbidden project/signing file scan
privacy scan
```

## Hard Limits

Do not:

* send APNs
* run production APNs
* run repeated APNs
* run `dev/invite`
* physically trigger sender runtime join
* repeat receiver connect
* repeat sender runtime join
* request camera or video
* emit Matrix events
* start full direct-call flow
* log raw tokens, JWTs, auth headers, APNs payloads, invite bodies, LiveKit URLs, room IDs, call IDs, user IDs, device IDs, or call handles
* touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`
* stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`
