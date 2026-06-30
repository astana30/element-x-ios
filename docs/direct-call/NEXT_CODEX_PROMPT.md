# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.49X-ZhanielkaAtomicHandoffTriggerBoundary` is implemented.

Receiver remains:
`iPhone PRO`

Sender remains:
`iPhone Жанелька`

Alpamys is unavailable and must not be required. Carpediem must not be required.

2.49W physical result:

```text
real_non_dev_invite_used=true
dev_invite_used=false
invite_http_code=200
background_apns_push_result=sandbox_success
APNs_sent=true
receiver_physical_voip_push_received=true
receiver_pending_metadata_fetch_result=success_redacted
receiver_callkit_answer_action_received=true
receiver_media_credentials_requested=true
receiver_media_credentials_result=success_redacted
receiver_media_connect_requested=false
receiver_livekit_join_requested=false
sender_debug_pending_metadata_file_handoff_seen=true
sender_debug_pending_metadata_file_handoff_consumed=true
sender_pending_metadata_memory_reference_present=true
sender_no_media_runtime_trigger_attempted=true
sender_no_media_runtime_trigger_result_bucket=pending_metadata_blocked_redacted
sender_runtime_boundary_blocked_reason=sender_pending_metadata_reference_sender_memory_missing_redacted
```

Interpretation:
- fresh invite/APNs/receiver readiness works
- sender file-backed pending metadata handoff reaches iPhone Жанелька and is consumed
- the later separate no-media trigger launch lost the in-memory sender pending metadata reference
- do not rerun 2.49W as-is

The app now has a DEBUG-only atomic sender pending metadata handoff plus no-media trigger file:

```text
salemx-debug-sender-pending-metadata-and-no-media-trigger.json
```

The atomic file is consumed from the sender app Documents container, shape-validated with marker `2.49X`, deleted on success, translated into the existing sender pending metadata memory reference, and immediately followed by the existing no-media sender trigger in the same app lifecycle.

Required proof fields:

```text
sender_debug_atomic_handoff_trigger_file_seen=<runtime>
sender_debug_atomic_handoff_trigger_shape_bucket=<runtime_redacted_bucket>
sender_debug_atomic_handoff_trigger_consumed=<runtime>
sender_debug_atomic_handoff_trigger_consume_result_bucket=<runtime_redacted_bucket>
sender_pending_metadata_memory_reference_present_before_trigger=<runtime>
sender_pending_metadata_memory_reference_present_at_trigger=<runtime>
sender_pending_metadata_raw_identifiers_logged=false
sender_no_media_runtime_trigger_attempted=<runtime>
sender_no_media_runtime_trigger_terminal_observed=<runtime>
sender_no_media_runtime_trigger_result_bucket=<runtime_redacted_bucket>
sender_call_state_after_answer_bucket=<runtime_redacted_bucket>
sender_media_credentials_gate_state=<runtime_redacted_bucket>
sender_media_credentials_requested=<runtime>
sender_media_credentials_request_seen=<runtime>
sender_media_credentials_http_status_bucket=<runtime_redacted_bucket>
sender_media_credentials_result_bucket=<runtime_redacted_bucket>
sender_media_credentials_failure_reason_bucket=<runtime_redacted_bucket>
sender_media_connect_gate_state=<runtime_redacted_bucket>
sender_media_connect_requested=false
sender_livekit_join_triggered=false
sender_permissions_requested=false
sender_runtime_boundary_blocked_reason=<runtime_redacted_bucket>
```

## New Phase

Start:

```text
2.49X-ZhanielkaAtomicHandoffTriggerBoundary — one-shot fresh invite plus atomic sender handoff/trigger, stop before media connect/LiveKit
```

Use helper:

```bash
/tmp/salemx_2_49x_zhanielka_atomic_handoff_trigger_boundary.command
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

1. Verify the repo HEAD matches the committed 2.49X repair.
2. Verify iPhone PRO and iPhone Жанелька are connected.
3. Preserve app containers; do not uninstall.
4. Build/install-over only as needed to run the current HEAD Debug app.
5. Launch both apps.
6. Verify Matrix tokens, distinct receiver/sender hashes, room membership, room encryption, and call-service reachability without printing raw values.
7. Stop at exact confirmation:

```text
SEND_2_49X_ZHANIELKA_ATOMIC_HANDOFF_TRIGGER_BOUNDARY
```

8. After exact confirmation, send exactly one real non-dev invite that creates pending metadata and requests one sandbox APNs.
9. Wait for receiver proof to reach VoIP receipt, pending metadata success, CallKit Answer, receiver credentials success, and guarded no-connect/no-LiveKit boundary.
10. Write the atomic DEBUG file into iPhone Жанелька app container.
11. Launch/foreground iPhone Жанелька and wait for atomic file consumed plus sender trigger terminal proof.
12. Print sender credentials/boundary result.
13. Stop before media connect/LiveKit.

## Success Classifications

```text
fresh_cycle_atomic_handoff_trigger_sender_credentials_success
fresh_cycle_atomic_handoff_trigger_consumed_credentials_not_requested
fresh_cycle_atomic_handoff_trigger_pending_metadata_blocked
fresh_cycle_atomic_handoff_trigger_not_seen
fresh_cycle_atomic_handoff_trigger_seen_not_consumed
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
* use URL dispatch for sender pending metadata handoff or trigger
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
* sender atomic handoff/trigger consumption result
* sender no-media credentials/boundary result
* final classification
* explicit safety statement
