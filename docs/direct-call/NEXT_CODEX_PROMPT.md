# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.49W-ZhanielkaFreshInviteFileBackedSenderHandoff` is implemented.

Receiver remains:
`iPhone PRO`

Sender is now:
`iPhone Жанелька`

Alpamys is unavailable and must not be required. Carpediem must not be required. Treat this as a controlled sender swap, not a feature change.

The app now has a DEBUG-only file-backed sender pending metadata handoff:

```text
sender_debug_pending_metadata_file_handoff_seen=<runtime>
sender_debug_pending_metadata_file_handoff_shape_bucket=<runtime_redacted_bucket>
sender_debug_pending_metadata_file_handoff_consumed=<runtime>
sender_debug_pending_metadata_file_handoff_consume_result_bucket=<runtime_redacted_bucket>
sender_pending_metadata_memory_reference_present=<runtime>
sender_pending_metadata_handoff_result_bucket=<runtime_redacted_bucket>
sender_pending_metadata_raw_identifiers_logged=false
```

The handoff file:

```text
salemx-debug-sender-pending-metadata-handoff.json
```

is consumed from the sender app Documents container, shape-validated with marker `2.49W`, deleted on success, and translated into the existing sender pending metadata memory reference. It does not use URL dispatch and does not itself start APNs, invite sending, no-media trigger execution, media connect, LiveKit, microphone/camera permission, Matrix events, or full flow.

The existing file-backed sender no-media trigger remains the separate one-shot action:

```text
salemx-debug-sender-no-media-runtime-trigger.json
```

## New Phase

Start:

```text
2.49W-ZhanielkaFreshInviteFileBackedSenderHandoff — one-shot fresh invite plus file-backed sender metadata handoff, stop before media connect/LiveKit
```

Use helper:

```bash
/tmp/salemx_2_49w_zhanielka_fresh_invite_file_backed_sender_handoff.command
```

The helper must prompt locally for:

```text
Homeserver base URL
Call-service base URL
Receiver Matrix access token
Sender Matrix access token
Encrypted Matrix room ID
```

The call-service base URL may be entered as:

```text
https://matrix.mertis.kz
```

## Required Device Roles

```text
receiver_device=iPhone PRO
sender_device=iPhone Жанелька
alpamys_required=false
carpediem_required=false
```

Device detection must handle the Unicode sender name `iPhone Жанелька`, prefer `devicectl` JSON parsing via `deviceProperties.name` and `connectionProperties.tunnelState`, and ignore Alpamys/Carpediem if visible.

## One-Shot Flow

1. Verify the repo HEAD matches the committed 2.49W repair.
2. Verify iPhone PRO and iPhone Жанелька are connected.
3. Preserve app containers; do not uninstall.
4. Build/install-over only as needed to run the current HEAD Debug app.
5. Launch both apps.
6. Verify Matrix tokens, distinct receiver/sender hashes, room membership, room encryption, and call-service reachability without printing raw values.
7. Stop at exact confirmation:

```text
SEND_2_49W_ZHANIELKA_FRESH_INVITE_FILE_BACKED_SENDER_HANDOFF
```

8. After exact confirmation, send exactly one real non-dev invite that creates pending metadata and requests one sandbox APNs.
9. Wait for the receiver proof to reach VoIP receipt, pending metadata success, CallKit Answer, receiver credentials success, and guarded no-connect/no-LiveKit boundary.
10. Write the pending metadata reference into iPhone Жанелька via the DEBUG-only app-container file handoff.
11. Launch/foreground iPhone Жанелька and wait for handoff consumption proof.
12. Write the existing DEBUG file-backed sender no-media trigger into iPhone Жанелька.
13. Launch/foreground iPhone Жанелька and wait for terminal sender credentials/boundary proof.
14. Stop before media connect/LiveKit.

## Required Sender Proof Fields

```text
sender_pending_metadata_memory_reference_present
sender_debug_pending_metadata_file_handoff_consumed
sender_no_media_runtime_trigger_attempted
sender_no_media_runtime_trigger_terminal_observed
sender_no_media_runtime_trigger_result_bucket
sender_call_state_after_answer_bucket
sender_media_credentials_gate_state
sender_media_credentials_requested
sender_media_credentials_request_seen
sender_media_credentials_http_status_bucket
sender_media_credentials_result_bucket
sender_media_credentials_failure_reason_bucket
sender_media_connect_gate_state
sender_media_connect_requested
sender_livekit_join_triggered
sender_permissions_requested
sender_runtime_boundary_blocked_reason
```

## Success Classifications

```text
fresh_cycle_sender_pending_handoff_consumed_credentials_success
fresh_cycle_sender_pending_handoff_consumed_credentials_not_requested
fresh_cycle_sender_pending_handoff_not_seen
fresh_cycle_sender_pending_handoff_seen_not_consumed
fresh_cycle_sender_trigger_terminal_pending_metadata_blocked
fresh_cycle_receiver_not_ready
fresh_cycle_invite_or_apns_failed
repo_bug_required
```

## Safety Fields

The helper must always print explicit safety fields:

```text
APNs_sent=<true only after exact SEND>
pending_metadata_created=<true only for one real invite>
valid_invite_sent=<true only for real non-dev invite 2xx>
background_apns_push_requested=<true only after SEND>
media_connect_requested=false
physical_connect_performed=false
livekit_join_triggered=false
permissions_requested=false
matrix_call_media_event_emitted=false
full_flow_started=false
```

## Hard Limits

Do not:

* send APNs before the exact SEND confirmation
* send more than one APNs
* send production APNs
* use `dev/invite`
* use URL dispatch for sender pending metadata handoff
* connect LiveKit
* join LiveKit
* request microphone permission
* request camera permission
* enable microphone
* emit Matrix call/media events
* start full flow
* uninstall apps or reset app containers
* require Alpamys
* require Carpediem
* log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/user ID/device ID/pending metadata
* modify signing, project settings, `app.yml`, entitlements, bundle IDs, provisioning, or Xcode project files

## Expected Output

Return:

* whether iPhone PRO and iPhone Жанелька were detected
* whether app build/install/launch succeeded
* preflight result
* APNs result after exact SEND
* receiver readiness result
* sender handoff consumption result
* sender no-media credentials/boundary result
* final classification
* explicit safety statement
