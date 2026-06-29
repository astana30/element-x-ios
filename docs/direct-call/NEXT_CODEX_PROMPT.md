# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

Retry28 is final. Do not rerun it and do not send another APNs for Retry28.

Retry28 achieved end-to-end two-device LiveKit participant proof:

```text
APNs_sent=true
physical_voip_push_received=true
callkit_answer_action_received=true
receiver_post_answer_pending_metadata_fetch_result=success_redacted
receiver_post_answer_media_credentials_result=success_redacted
receiver_post_answer_controlled_connect_result=success_redacted
receiver_post_answer_livekit_join_result=success_redacted
controlled_connect_first_attempt_result=success_redacted
livekit_join_result=success_redacted
receiver_connected_session_lease_acquired=true
sender_runtime_join_executor_invoked=true
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_runtime_result=success_redacted
sender_livekit_room_connected=true
receiver_participant_event_callback_seen=true
livekit_remote_participant_seen=true
livekit_remote_participant_count_bucket=1
receiver_remote_participant_observer_result=remote_participant_seen_via_callback_redacted
remote_participant_observation_final_classification=remote_participant_seen_via_callback_redacted
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

## Accounting Repair Completed

Retry28 had stale overlap accounting:

```text
sender_connected_signal_received_by_receiver=true
receiver_connected_session_lease_active_at_sender_signal=false
receiver_sender_connected_window_overlap_observed=false
phase_participant_seen=true
first_failed_phase=overlap_observed
```

Repo inspection found no committed Retry28 helper/phase-summary implementation to patch; the stale logic lived in the one-off `/tmp` helper. Future helpers must apply this terminal accounting rule:

```text
if livekit_remote_participant_seen=true
or receiver_participant_event_callback_seen=true
or receiver_participant_snapshot_seen=true:
  phase_participant_seen=true
  phase_overlap_accounting_superseded_by_participant_seen=true
  first_failed_phase=none
  retry_success=true
  receiver_overlap_accounting_caveat=participant_seen_supersedes_stale_overlap_redacted
```

Preserve stale overlap fields as caveat diagnostics, not terminal failure, once participant presence is proven.

## New Phase

Start:

```text
2.49A RemoteAudioTrackLivenessProof
```

Goal:

Validate remote audio track/liveness after the already-proven participant path:

```text
receiver LiveKit connected
sender LiveKit connected
receiver remote participant seen
remote audio track subscribed/unmuted/liveness observed
```

Primary proof targets:

```text
livekit_remote_participant_seen=true
livekit_remote_audio_track_subscribed=true
livekit_remote_audio_track_unmuted=true
livekit_remote_audio_level_observed=true
livekit_audio_liveness_observed=true
livekit_audio_liveness_result=success_redacted
remote_audio_liveness_result=success_redacted
```

Guardrails:

```text
no video
no camera permission request
no Matrix event emit
no full production flow
no raw token, URL, room ID, call ID, user ID, device ID, APNs payload, invite body, auth header, pending metadata contents, or private log exposure
```

Do not run APNs or physical LiveKit proof until after inspection and a fresh validation plan.

## Suggested Investigation

Inspect existing remote-audio proof fields and LiveKit observer callbacks:

```bash
rg -n "remote_audio|audio_liveness|livekit_remote_audio|RemoteParticipant|TrackPublication|audio_track|subscribed|unmuted|participant_seen|receiver_remote_participant_observer" \
  ElementX/Sources/Services/Calls \
  UnitTests/Sources/DirectCallEngineTests.swift \
  UnitTests/Sources/NativeIncomingCallLifecycleContractTests.swift
```

Prefer the smallest DEBUG-only proof extension that observes remote audio track state after `livekit_remote_participant_seen=true`.

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
