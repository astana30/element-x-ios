# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.49Y-SenderPendingMetadataAuthDiagnostics` is implemented.

Receiver remains:
`iPhone PRO`

Sender remains:
`iPhone Жанелька`

Alpamys is unavailable and must not be required. Carpediem must not be required.

2.49X physical result:

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
sender_debug_atomic_handoff_trigger_file_seen=true
sender_debug_atomic_handoff_trigger_shape_bucket=valid_sender_atomic_handoff_trigger_redacted
sender_debug_atomic_handoff_trigger_consumed=true
sender_debug_atomic_handoff_trigger_consume_result_bucket=deleted_redacted
sender_pending_metadata_memory_reference_present_before_trigger=true
sender_pending_metadata_memory_reference_present_at_trigger=true
sender_pending_metadata_memory_reference_present=true
sender_no_media_runtime_trigger_attempted=true
sender_no_media_runtime_trigger_terminal_observed=true
sender_no_media_runtime_trigger_result_bucket=pending_metadata_blocked_redacted
sender_media_credentials_requested=false
sender_media_credentials_result_bucket=not_requested
sender_runtime_boundary_blocked_reason=sender_pending_metadata_fetch_unauthorized_redacted
```

Interpretation:
- fresh invite/APNs/receiver readiness works
- atomic file-backed sender handoff/trigger works
- sender memory reference is present at trigger time
- the remaining blocker is sender authorization/scope for the pending metadata reference created for the receiver incoming/APNs path
- do not rerun 2.49X as-is
- do not connect media or LiveKit

## New Phase

Start:

```text
2.49Y-SenderPendingMetadataAuthDiagnostics — inspect sender metadata authorization and choose sender-safe source, no APNs
```

Use helper:

```bash
/tmp/salemx_2_49y_sender_pending_metadata_auth_diagnostics.command
```

The helper is diagnostic-only. It must not prompt for tokens, send APNs, create an invite, create pending metadata, use `dev/invite`, connect media, join LiveKit, request microphone/camera permission, enable microphone, emit Matrix events, start video, or start full flow.

## Required Devices

```text
receiver_device=iPhone PRO
sender_device=iPhone Жанелька
alpamys_required=false
carpediem_required=false
```

Device detection must handle the Unicode sender name `iPhone Жанелька`, prefer `devicectl` JSON parsing via `deviceProperties.name` and `connectionProperties.tunnelState`, and ignore Alpamys/Carpediem if visible.

## Diagnostic Fields

The app and helper should print these redacted fields:

```text
pending_metadata_reference_role_bucket=<runtime_redacted_bucket>
pending_metadata_reference_scope_bucket=<runtime_redacted_bucket>
receiver_pending_metadata_fetch_auth_bucket=<runtime_or_helper_redacted_bucket>
sender_pending_metadata_fetch_auth_bucket=<runtime_redacted_bucket>
sender_pending_metadata_fetch_http_status_bucket=<runtime_redacted_bucket>
sender_pending_metadata_fetch_failure_reason_bucket=<runtime_redacted_bucket>
sender_is_invite_creator_bucket=<runtime_redacted_bucket>
sender_is_room_member_bucket=<runtime_redacted_bucket>
sender_is_peer_of_metadata_bucket=<runtime_redacted_bucket>
sender_authorized_metadata_source_available=<runtime>
sender_local_invite_state_available=<runtime>
sender_can_request_credentials_without_receiver_pending_fetch=<runtime>
sender_credentials_request_blocked_reason=<runtime_redacted_bucket>
recommended_next_fix_bucket=<runtime_redacted_bucket>
```

## Expected Classification

For the 2.49X proof already captured, the likely diagnostic close is:

```text
recommended_next_fix_bucket=provide_sender_authorized_metadata_source_redacted
sender_authorized_metadata_source_available=false
sender_local_invite_state_available=false
sender_can_request_credentials_without_receiver_pending_fetch=false
```

That means the next code phase should choose one of:
- sender-owned invite/local state as the credentials session source
- a dedicated sender-authorized server endpoint/reference
- server authorization that explicitly allows sender/creator access to the existing reference

Do not broaden receiver metadata access blindly and do not fake success.

## Safety Fields

The helper must always print:

```text
APNs_sent=false
pending_metadata_created=false
valid_invite_sent=false
background_apns_push_requested=false
media_connect_requested=false
physical_connect_performed=false
livekit_join_triggered=false
permissions_requested=false
matrix_call_media_event_emitted=false
full_flow_started=false
```

## Hard Limits

Do not:

* send APNs
* send production APNs
* send repeated APNs
* send another valid invite
* create new pending metadata
* use `dev/invite`
* connect media
* join LiveKit
* request microphone permission
* request camera permission
* enable microphone
* start video
* emit Matrix call/media events
* start full flow
* uninstall apps
* reset app containers
* print raw tokens, JWTs, auth headers, APNs payloads, invite bodies, LiveKit URLs/tokens, room IDs, call IDs, user IDs, device IDs, pending metadata, or secrets
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Required Checks

Run:

```bash
git status --short --branch
python3 -m py_compile /tmp/salemx_2_49y_sender_pending_metadata_auth_diagnostics.command
git diff --check
git diff --cached --check
```

If Swift changed, run:

```bash
swiftformat ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
swiftlint lint ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
```

Also run forbidden project/signing scans and a privacy scan over changed files/helper.

## Expected Output

Return:

* diagnostic conclusion
* helper path
* exact helper command
* recommended_next_fix_bucket
* commit hash/message if code was committed
* changed files
* checks run
* final `git status --short --branch`
* explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, new invite/pending metadata creation, media connect, LiveKit join, microphone/camera permission, microphone enablement, video, Matrix event emit, full flow, uninstall/container reset, or raw-value logging was performed
