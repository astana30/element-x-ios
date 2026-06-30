# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.49Z-ZhanielkaSenderAuthorizedMetadataBoundary` is implemented.

Receiver remains:
`iPhone PRO`

Sender remains:
`iPhone Жанелька`

Alpamys is unavailable and must not be required. Carpediem must not be required.

2.49Y confirmed blocker:

```text
pending_metadata_reference_role_bucket=receiver_invite_pending_metadata_reference_redacted
pending_metadata_reference_scope_bucket=not_sender_authorized_redacted
receiver_pending_metadata_fetch_auth_bucket=success_redacted
sender_pending_metadata_fetch_auth_bucket=auth_rejected_redacted
sender_pending_metadata_fetch_http_status_bucket=401_or_auth_rejected_redacted
sender_pending_metadata_fetch_failure_reason_bucket=auth_rejected
sender_authorized_metadata_source_available=false
sender_local_invite_state_available=false
sender_can_request_credentials_without_receiver_pending_fetch=false
sender_credentials_request_blocked_reason=sender_pending_metadata_fetch_unauthorized_redacted
recommended_next_fix_bucket=provide_sender_authorized_metadata_source_redacted
diagnostic_conclusion=sender_pending_metadata_authorization_scope_blocked_redacted
```

2.49Z repair:
- call-service creates a separate sender-only metadata reference on real invite success
- receiver/APNs pending metadata reference remains receiver-only and is still the only APNs metadata reference
- `/pending-metadata/{receiver_reference}/sender` rejects receiver/APNs references
- `/pending-metadata/{sender_authorized_reference}/sender` is available only to the authenticated invite creator
- invite response includes `sender_authorized_metadata_reference` plus redacted source/scope fields
- DEBUG atomic sender handoff-and-trigger file uses `sender_authorized_metadata_reference` with marker `2.49Z`
- sender no-media trigger still stops before media connect/LiveKit

## New Phase

Start:

```text
2.49Z-ZhanielkaSenderAuthorizedMetadataBoundary — one-shot fresh invite with sender-authorized metadata source, stop before media connect/LiveKit
```

Use helper:

```bash
/tmp/salemx_2_49z_zhanielka_sender_authorized_metadata_boundary.command
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

1. Verify repo HEAD matches the committed 2.49Z repair.
2. Verify iPhone PRO and iPhone Жанелька are connected.
3. Preserve app containers; do not uninstall.
4. Build/install-over current HEAD Debug app only as needed.
5. Launch both apps.
6. Verify Matrix tokens, distinct receiver/sender hashes, room membership, room encryption, and call-service reachability without printing raw values.
7. Stop at exact confirmation:

```text
SEND_2_49Z_ZHANIELKA_SENDER_AUTHORIZED_METADATA_BOUNDARY
```

8. After exact confirmation, send exactly one real non-dev invite that creates receiver pending metadata, creates sender-authorized metadata, and requests one sandbox APNs.
9. Wait for receiver proof to reach VoIP receipt, pending metadata success, CallKit Answer, receiver credentials success, and guarded no-connect/no-LiveKit boundary.
10. Capture `sender_authorized_metadata_reference` from the invite response. Do not print it.
11. Write the DEBUG atomic file into iPhone Жанелька app container using only `sender_authorized_metadata_reference`, not `pending_metadata_reference`.
12. Launch/foreground iPhone Жанелька and wait for atomic file consumed plus sender trigger terminal proof.
13. Print sender credentials/boundary result.
14. Stop before media connect/LiveKit.

## Required Proof Fields

```text
sender_authorized_metadata_source_available=<runtime>
sender_authorized_metadata_source_role_bucket=<runtime_redacted_bucket>
sender_authorized_metadata_source_scope_bucket=<runtime_redacted_bucket>
sender_uses_receiver_pending_metadata_reference=false
sender_pending_metadata_fetch_auth_bucket=<runtime_redacted_bucket>
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
sender_pending_metadata_raw_identifiers_logged=false
```

## Success Classifications

```text
fresh_cycle_sender_authorized_metadata_credentials_success
fresh_cycle_sender_authorized_metadata_credentials_failed
fresh_cycle_sender_authorized_metadata_source_missing
fresh_cycle_sender_still_used_receiver_pending_metadata
fresh_cycle_receiver_not_ready
fresh_cycle_invite_or_apns_failed
repo_bug_required
```

## Safety Fields

The helper must always print:

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

* send APNs before exact SEND confirmation
* send more than one APNs
* send production APNs
* use `dev/invite`
* use receiver/APNs `pending_metadata_reference` for the sender atomic handoff
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
* print raw tokens, JWTs, auth headers, APNs payloads, invite bodies, LiveKit URLs/tokens, room IDs, call IDs, user IDs, device IDs, pending metadata references, or secrets
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Required Checks

Run:

```bash
git status --short --branch
python3 -m py_compile /tmp/salemx_2_49z_zhanielka_sender_authorized_metadata_boundary.command
git diff --check
git diff --cached --check
```

If Swift changed, run:

```bash
swiftformat ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
swiftlint lint ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
```

If server code changed, run the relevant server tests from `server/salemx-call-service`.

Also run forbidden project/signing scans and a privacy scan over changed files/helper.

## Expected Output

Return:

* changed files
* old HEAD and new HEAD
* commit hash/message
* tests run
* helper path
* exact helper command
* APNs_sent=false during creation/checks
* final `git status --short --branch`
* explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, media connect, LiveKit join, microphone/camera permission, microphone enablement, video, Matrix event emit, full flow, uninstall/container reset, or raw-value logging was performed
