# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderPendingMetadataReferenceHandoffRepair` is closed as a no-APNs code/test repair.

The Retry17 blocker was:

```text
sender_runtime_join_pending_metadata_fetch_result=blocked_redacted
sender_runtime_join_credentials_result=not_requested
sender_runtime_join_executor_invoked=false
blocked_reason=sender_runtime_join_pending_metadata_reference_missing_redacted
```

Repair now in place:

```text
sender_pending_metadata_reference_handoff_present=<redacted_bool>
sender_pending_metadata_reference_handoff_debug_only=true
sender_pending_metadata_reference_handoff_armed_before_sender_trigger=<redacted_bool>
sender_pending_metadata_reference_handoff_received_by_sender_runtime=<redacted_bool>
sender_pending_metadata_reference_handoff_source=invite_response_redacted
sender_pending_metadata_reference_handoff_raw_reference_logged=false
sender_pending_metadata_reference_handoff_raw_metadata_logged=false
sender_pending_metadata_reference_handoff_raw_room_logged=false
sender_pending_metadata_reference_handoff_raw_call_logged=false
sender_pending_metadata_reference_handoff_raw_user_logged=false
sender_pending_metadata_reference_handoff_raw_device_logged=false
```

Runtime trigger behavior:
- the sender runtime join trigger consumes the opaque pending metadata reference from the DEBUG-only in-memory handoff
- the sender runtime trigger does not read `pending_metadata_reference` from its own query parameters
- missing handoff blocks before sender credentials and before shared executor invocation
- sender-view metadata fetch success must happen before sender credentials
- query-selected sender outcomes remain disabled

Server safety:
- real invite creates and returns an opaque pending metadata reference when `pending_metadata` is supplied
- sender-view pending metadata route is authenticated
- wrong sender and unauthenticated sender access are rejected

Safety preserved:

```text
APNs_sent=false
dev_invite_used=false
physical_media_connect=false
physical_livekit_join=false
microphone_permission_requested=false
camera_permission_requested=false
video_allowed=false
matrix_event_emit_requested=false
real_call_flow_started=false
raw URL/token/room/call/user/device IDs logged=false
```

## Next Phase

`2.48Z-Physical2-Retry18 — one-shot real sender join with pending metadata reference handoff`

Goal:
Run one physical two-device proof where the helper captures the real non-dev invite response's opaque `pending_metadata_reference`, arms the sender app with it, then triggers the real sender runtime join once after the receiver connect pre-sender gate passes.

Required flow:

1. Build/install/launch Debug app before hook arming.
2. Restore and prove receiver and sender Matrix sessions.
3. Arm receiver controlled audio connect, remote-peer context, and sender readiness/correlation hooks.
4. Validate room membership/encryption and distinct accounts.
5. Send at most one sandbox APNs via the real non-dev invite route.
6. Capture the invite-created `pending_metadata_reference` in memory only; never print it.
7. Arm sender with:

   ```text
   kz.salemx.msg://debug/direct-call/sender-pending-metadata-reference-handoff?source=invite_response&pending_metadata_reference=<opaque_in_memory_only>
   ```

8. Do not relaunch/reinstall sender after arming the sender reference handoff.
9. After receiver Answer and controlled connect terminal proof, trigger:

   ```text
   kz.salemx.msg://debug/direct-call/sender-runtime-livekit-join?confirm=RUN_2_48Z_REAL_SENDER_RUNTIME_JOIN
   ```

10. Do not include `pending_metadata_reference` on the runtime trigger URL.
11. Poll separate receiver and sender proof files.

Expected sender success proof:

```text
sender_pending_metadata_reference_handoff_present=true
sender_pending_metadata_reference_handoff_debug_only=true
sender_pending_metadata_reference_handoff_armed_before_sender_trigger=true
sender_pending_metadata_reference_handoff_received_by_sender_runtime=true
sender_pending_metadata_reference_handoff_source=invite_response_redacted
sender_pending_metadata_reference_handoff_raw_reference_logged=false
sender_pending_metadata_reference_handoff_raw_metadata_logged=false
sender_pending_metadata_reference_handoff_raw_room_logged=false
sender_pending_metadata_reference_handoff_raw_call_logged=false
sender_pending_metadata_reference_handoff_raw_user_logged=false
sender_pending_metadata_reference_handoff_raw_device_logged=false

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
sender_runtime_join_query_outcome_ignored=true
```

If missing handoff:

```text
sender_runtime_join_pending_metadata_fetch_result=blocked_redacted
sender_runtime_join_credentials_requested=false
sender_runtime_join_executor_invoked=false
blocked_reason=sender_pending_metadata_reference_sender_memory_missing_redacted
```

Hard limits:
- do not use `dev/invite`
- do not send production APNs
- do not repeat APNs
- do not repeat receiver connect or sender runtime join
- do not enable video
- do not request camera
- do not emit Matrix events
- do not start full direct-call flow
- do not log raw tokens, JWTs, auth headers, APNs payloads, invite bodies, LiveKit URLs, room IDs, call IDs, user IDs, device IDs, call handles, or pending metadata contents
- do not touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`
