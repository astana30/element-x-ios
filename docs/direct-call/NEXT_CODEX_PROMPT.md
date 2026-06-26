# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry19` is closed as:

```text
real sender pending-metadata handoff + credentials + runtime join success /
receiver connected window closed before sender-connected signal /
remote participant not observed triage
```

This is not remote participant success.

Key proof:

```text
APNs_sent=true
APNs_repeated=false
production_APNs_used=false
dev_invite_used=false

receiver_physical_voip_push_received=true
receiver_callkit_first_action_kind=answer
receiver_pending_metadata_fetch_result=success_redacted
receiver_media_credentials_result=success_redacted
receiver_controlled_connect_first_attempt_result=success_redacted
receiver_controlled_connect_first_attempt_repeated=false
receiver_livekit_join_result=success_redacted
receiver_livekit_room_connected=true
receiver_livekit_remote_participant_seen=false

sender_pending_metadata_reference_handoff_received_by_sender_runtime=true
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_executor_invoked=true
sender_runtime_join_runtime_result=success_redacted
sender_runtime_join_runtime_error_bucket=none
sender_livekit_room_connected=true
sender_runtime_join_query_outcome_ignored=true

receiver_connected_window_closed_before_sender_connected=true
sender_connected_signal_received_by_receiver=false
receiver_sender_connected_window_overlap_observed=false
receiver_sender_connected_window_overlap_final_classification=receiver_overlap_wait_timeout_redacted
```

Safety preserved:

```text
no repeated APNs
no production APNs
no dev/invite
no repeated receiver connect
no repeated sender runtime join
no video
no camera permission
no Matrix event emit
no full direct-call flow
no raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room/call/user/device/pending-metadata logging
```

## Next Phase

`2.48Z-ReceiverSenderConnectedSignalRepair`

Goal:
Receiver must consume the sender-connected signal before closing the connected-window lease. The observation window must not terminate solely on remote participant event timeout while sender runtime join is still in progress or before the sender-connected signal has been processed.

Investigate:
- why sender proof has `sender_livekit_room_connected=true` but receiver has `sender_connected_signal_received_by_receiver=false`
- whether sender-connected signal is written only to sender proof and not propagated to receiver proof
- whether the helper copies receiver proof before propagating sender terminal state
- whether receiver connected-window timeout is too short relative to sender runtime join
- whether receiver overlap wait should start after sender trigger, not before
- whether receiver should wait for sender terminal signal first, then participant event timeout
- whether receiver lease cleanup ignores pending sender terminal state

Implement:
- sender-connected signal handoff from sender proof/helper/runtime into receiver observation proof using opaque correlation only
- receiver observation lease waits for sender-connected signal or sender terminal failure before closing for participant timeout
- once `sender_connected_signal_received_by_receiver=true`, keep receiver room alive for a bounded participant-event wait
- classify separately:
  ```text
  sender_connected_signal_missing_redacted
  sender_connected_signal_late_redacted
  receiver_window_closed_before_sender_signal_redacted
  participant_event_timeout_after_sender_signal_redacted
  connected_window_overlap_observed_redacted
  ```
- do not require audio track for participant presence
- deterministic cleanup after terminal result
- no raw token/URL/room/user/device/call IDs

Tests:
- sender connected signal reaches receiver proof
- receiver cannot close window before sender signal when sender trigger is pending
- sender signal after receiver close is classified
- overlap observed when receiver alive + sender connected
- participant timeout after sender signal is separate from no-overlap
- cleanup deterministic
- one-shot APNs/connect/sender join semantics preserved
- video/camera/Matrix/full-flow false
- default no-connect/no-join

Hard limits:
- no APNs
- no physical connect
- no LiveKit join
- no microphone/camera permissions
- no Matrix events
- no full call flow
- do not touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`

After repair:
`2.48Z-Physical2-Retry20 — one-shot real sender join with sender-connected signal handoff`
