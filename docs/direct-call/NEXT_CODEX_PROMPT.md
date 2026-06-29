# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

Retry28 is final. Do not rerun it.

Retry28 sent exactly one sandbox APNs and achieved end-to-end two-device LiveKit participant proof:

```text
APNs_sent=true
background_apns_push_result=sandbox_success
receiver_post_answer_pending_metadata_fetch_result=success_redacted
receiver_post_answer_media_credentials_result=success_redacted
receiver_post_answer_controlled_connect_result=success_redacted
livekit_join_result=success_redacted
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_executor_invoked=true
sender_runtime_join_runtime_result=success_redacted
sender_livekit_room_connected=true
receiver_participant_event_callback_seen=true
livekit_remote_participant_seen=true
retry28_success=true
```

Safety remained preserved:

```text
no repeated APNs
no production APNs
no dev/invite
no repeated receiver connect
no repeated sender join
video=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Known Accounting Caveat

The Retry28 terminal helper/proof summary still reported stale overlap failure fields even though receiver participant presence was observed:

```text
receiver_sender_connected_window_overlap_observed=false
receiver_connected_session_lease_active_at_sender_signal=false
first_failed_phase=overlap_observed
livekit_remote_participant_seen=true
retry28_success=true
```

The stronger runtime evidence is participant callback success / `livekit_remote_participant_seen=true`. The stale overlap accounting must not make the final phase summary look failed once participant presence is proven.

## New Phase

Start:

```text
2.48Z-Retry28ParticipantSeenAccountingRepair
```

Goal:

Repair helper/proof phase accounting so receiver participant presence supersedes stale overlap failure:

```text
participant_seen=true
or livekit_remote_participant_seen=true
or receiver_participant_event_callback_seen=true
```

must make the participant/terminal success path win over stale:

```text
receiver_sender_connected_window_overlap_observed=false
receiver_connected_session_lease_active_at_sender_signal=false
first_failed_phase=overlap_observed
```

Expected accounting behavior after repair:

```text
retry28_success=true
phase_remote_participant_seen=true
phase_overlap_accounting_superseded_by_participant_seen=true
first_failed_phase=none
overlap_accounting_caveat_recorded=true
```

Use a redacted caveat field rather than deleting the diagnostic:

```text
receiver_overlap_accounting_caveat=participant_seen_supersedes_stale_overlap_redacted
```

## Scope

Allowed:
- small helper/proof accounting repair
- targeted tests/source guards
- compact docs update

Not allowed:
- APNs
- production APNs
- `dev/invite`
- physical media connect
- physical LiveKit join
- repeated receiver connect
- repeated sender join
- microphone/camera permission request
- video
- Matrix event emission
- full direct-call flow
- project/signing/entitlements/Info.plist/app.yml changes
- raw token, URL, room ID, call ID, user ID, device ID, APNs payload, invite body, auth header, pending metadata contents, or private log exposure

## Checks

Run targeted checks only:

```bash
swiftformat <changed Swift files>
swiftlint lint <changed Swift files>
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|.entitlements|Info.plist' && exit 1 || true
```

After this accounting repair is committed, move to:

```text
2.49A RemoteAudioTrackLivenessProof
```
