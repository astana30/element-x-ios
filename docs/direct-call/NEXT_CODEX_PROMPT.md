# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-ReceiverSenderConnectedSignalRepair` is committed.

It was a no-APNs/no-connect code and test repair for the Retry19 blocker:

```text
sender_livekit_room_connected=true
sender_connected_signal_received_by_receiver=false
receiver_sender_connected_window_overlap_observed=false
livekit_remote_participant_seen=false
```

New repair surface:

```text
sender_connected_signal_handoff_present=true
sender_connected_signal_handoff_debug_only=true
sender_connected_signal_emitted=<runtime_bool>
sender_connected_signal_emitted_after_runtime_join_success=<runtime_bool>
sender_connected_signal_opaque_correlation_present=<redacted_bool>
sender_connected_signal_handoff_raw_identifiers_logged=false
sender_connected_signal_raw_room_logged=false
sender_connected_signal_raw_call_logged=false
sender_connected_signal_raw_user_logged=false
sender_connected_signal_raw_device_logged=false

receiver_sender_connected_signal_wait_started=<redacted_bool>
receiver_sender_connected_signal_wait_completed=<redacted_bool>
receiver_sender_connected_signal_received=<redacted_bool>
receiver_sender_connected_signal_correlation_match=<redacted_bool>
receiver_sender_connected_signal_received_before_receiver_disconnect=<redacted_bool>
receiver_sender_connected_signal_received_after_receiver_disconnect=<redacted_bool>
receiver_sender_connected_signal_timeout=<redacted_bool>
receiver_sender_connected_signal_final_classification=<redacted_bucket>
```

The receiver can consume a sender-connected signal through the DEBUG-only `/direct-call/sender-connected-signal-handoff` hook using opaque correlation only. Classifications now distinguish:

```text
sender_connected_signal_received_redacted
sender_connected_signal_missing_redacted
sender_connected_signal_after_receiver_disconnect_redacted
sender_connected_signal_correlation_mismatch_redacted
receiver_window_closed_before_sender_signal_redacted
connected_window_overlap_observed_redacted
participant_event_timeout_after_sender_signal_redacted
```

Safety preserved:

```text
no APNs
no production APNs
no dev/invite
no physical media connect
no physical LiveKit join
no microphone/camera permission
no video
no Matrix event emit
no full direct-call flow
no raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room/call/user/device/pending-metadata logging
```

## Next Phase

`2.48Z-Physical2-Retry20 — one-shot real sender join with sender-connected signal handoff`

Goal:
Run one physical two-device proof that the sender runtime join success signal is propagated into the receiver proof before the receiver connected window closes.

Required proof focus:

```text
receiver_pushkit_received=true
receiver_callkit_answer_received=true
receiver_pending_metadata_fetch_result=success_redacted
receiver_media_credentials_result=success_redacted
receiver_controlled_connect_first_attempt_result=success_redacted
receiver_livekit_join_result=success_redacted

sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_executor_invoked=true
sender_runtime_join_runtime_result=success_redacted
sender_livekit_room_connected=true
sender_connected_signal_emitted=true

receiver_sender_connected_signal_received=true
receiver_sender_connected_signal_correlation_match=true
receiver_sender_connected_signal_received_before_receiver_disconnect=true
receiver_sender_connected_window_overlap_observed=true
```

If remote participant is seen:

```text
livekit_remote_participant_seen=true
receiver_remote_participant_observer_result=success_redacted
```

If participant event still times out after signal:

```text
receiver_sender_connected_window_overlap_observed=true
livekit_remote_participant_seen=false
receiver_remote_participant_observer_result=not_observed_redacted
remote_participant_observation_final_classification=participant_event_timeout_after_sender_signal_redacted
```

Hard limits:
- send at most one sandbox APNs after all preflight gates pass and explicit manual confirmation
- do not use production APNs or `dev/invite`
- do not repeat APNs, receiver connect, or sender join
- no video, camera permission, Matrix event emission, or full direct-call flow
- do not touch `SalemX.xcodeproj/project.pbxproj`, `app.yml`, `.entitlements`, or `Info.plist`
- do not expose raw tokens, URLs, room IDs, call IDs, user IDs, device IDs, call handles, APNs payloads, invite bodies, auth headers, or pending metadata contents
