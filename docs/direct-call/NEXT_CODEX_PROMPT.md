# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-ReceiverSenderConnectedWindowOverlapRepair` is committed as a no-APNs code/test repair for the Retry18 receiver observation timing blocker.

What changed:

```text
receiver_sender_connected_overlap_repair_present=true
receiver_sender_connected_overlap_repair_debug_only=true
receiver_sender_connected_overlap_repair_raw_identifiers_logged=false
receiver_connected_window_opened=<runtime_bool>
receiver_connected_window_closed=<runtime_bool>
receiver_connected_window_close_reason=<redacted_reason>
receiver_connected_window_closed_before_sender_connected=<runtime_bool>
receiver_connected_window_retained_until_sender_terminal=<runtime_bool>
sender_connected_signal_received_by_receiver=<runtime_bool>
sender_connected_signal_source=sender_runtime_livekit_join_redacted|unknown_redacted|none
sender_connected_signal_before_receiver_disconnect=<runtime_bool>
sender_connected_signal_after_receiver_disconnect=<runtime_bool>
sender_connected_signal_raw_identifiers_logged=false
receiver_sender_connected_window_overlap_wait_started=<runtime_bool>
receiver_sender_connected_window_overlap_wait_completed=<runtime_bool>
receiver_sender_connected_window_overlap_wait_timeout=<runtime_bool>
receiver_sender_connected_window_overlap_final_classification=<redacted_bucket>
```

New receiver overlap classifications:

```text
connected_window_overlap_observed_redacted
receiver_disconnected_before_sender_connected_redacted
sender_connected_after_receiver_disconnect_redacted
sender_connected_signal_missing_redacted
receiver_observer_bound_to_stale_room_redacted
receiver_overlap_wait_timeout_redacted
receiver_cleanup_released_lease_early_redacted
```

Safety preserved:

```text
APNs_sent=false
dev_invite_used=false
production_APNs_used=false
physical_connect_run=false
physical_LiveKit_join_run=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
raw URL/token/room/call/user/device IDs/pending metadata logged=false
```

## Next Phase

`2.48Z-Physical2-Retry19 — one-shot real sender join with receiver/sender connected-window overlap proof`

Goal:
Run one physical two-device proof and determine whether the receiver connected window now overlaps the sender runtime connected state.

Roles:
- receiver: `iPhone PRO`
- sender: the currently authenticated second physical device for hash `7d434d7f252427fb`
- do not use Simulator unless explicitly requested
- do not use iPhone Жанелька unless explicitly requested

Before APNs:
- install/launch current Debug build on required devices as needed
- verify both app Matrix sessions with redacted whoami proofs
- verify both users are distinct and joined to the same encrypted Matrix room
- arm receiver controlled audio connect, remote peer context, and sender readiness context
- verify receiver connected-window overlap repair fields are present/debug-only/raw-identifiers-false
- verify sender runtime bridge is present, debug-only, default disabled, one-shot, and query-selected outcomes are disabled
- require `safe_to_send_apns=true`

Run:
- exactly one sandbox APNs real non-dev invite after manual confirmation
- receiver taps Answer once
- trigger sender runtime join once
- do not retry APNs, receiver connect, or sender join

Expected success classification:

```text
receiver_connected_window_opened=true
sender_connected_signal_received_by_receiver=true
sender_connected_signal_source=sender_runtime_livekit_join_redacted
sender_connected_signal_before_receiver_disconnect=true
sender_connected_signal_after_receiver_disconnect=false
receiver_connected_window_retained_until_sender_terminal=true
sender_room_connected_during_receiver_window=true
receiver_sender_connected_window_overlap_observed=true
receiver_sender_connected_window_overlap_final_classification=connected_window_overlap_observed_redacted
```

Remote participant presence remains separate:
- if `livekit_remote_participant_seen=true`, close Retry19 as real sender join plus receiver remote participant success
- if overlap is true but participant remains false, close as connected-window success / remote participant observation not seen and move to participant propagation repair
- missing audio track alone is not sender-join failure

Hard limits:
- no `dev/invite`
- no production APNs
- no repeated APNs
- no repeated receiver connect
- no repeated sender runtime join
- no video
- no camera permission
- no Matrix event emit
- no full direct-call flow
- no raw tokens, URLs, room IDs, call IDs, user IDs, device IDs, APNs payloads, invite bodies, pending metadata, or auth headers in logs/docs/commits
- do not touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`
