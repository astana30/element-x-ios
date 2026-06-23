# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-RemoteParticipantPresenceRepair` is complete.

The previous physical proof was closed as:

```text
2.48Z-Physical1 = two-physical-device remote audio/liveness safely classified, not remote-audio success
LiveKit join result=success_redacted
remote audio/liveness result=not_observed_redacted
remote liveness blocker=remote_participant_missing_redacted
no retry performed
```

The repair added redacted diagnostics for the next proof:

```text
remote_participant_presence_repair_present=true
remote_participant_presence_repair_debug_only=true
remote_participant_presence_repair_requires_two_physical_devices=true
remote_participant_presence_repair_requires_same_room=true
remote_participant_presence_repair_requires_sender_livekit_readiness=true
remote_participant_presence_repair_sender_join_path_present=true
remote_participant_presence_repair_sender_join_default_disabled=true
remote_participant_presence_repair_receiver_observer_present=true
remote_participant_presence_repair_same_livekit_room_required=true
remote_participant_presence_repair_classifies_sender_not_joined=true
remote_participant_presence_repair_classifies_remote_missing=true
remote_participant_presence_repair_classifies_remote_seen=true
remote_participant_presence_repair_no_video=true
remote_participant_presence_repair_no_matrix_events=true
remote_participant_presence_repair_raw_identifiers_logged=false
```

Sender-side readiness/join-path proof fields are now present and default-disabled:

```text
second_physical_sender_livekit_readiness_present=true
second_physical_sender_livekit_readiness_debug_only=true
second_physical_sender_livekit_readiness_default_disabled=true
second_physical_sender_livekit_readiness_matrix_session_ready=<redacted_bool>
second_physical_sender_livekit_readiness_same_room_ready=<redacted_bool>
second_physical_sender_livekit_readiness_credentials_ready=false
second_physical_sender_livekit_join_path_present=true
second_physical_sender_livekit_join_path_default_disabled=true
second_physical_sender_livekit_join_path_audio_only=true
second_physical_sender_livekit_join_path_video_allowed=false
second_physical_sender_livekit_join_path_matrix_events_allowed=false
second_physical_sender_livekit_join_path_raw_credentials_logged=false
```

Receiver observer fields can now classify sender-not-joined/remote-missing, remote seen, audio-track missing, liveness missing, or success:

```text
receiver_remote_participant_observer_present=true
receiver_remote_participant_observer_debug_only=true
receiver_remote_participant_observer_started=<redacted_bool>
receiver_remote_participant_observer_result=<success_or_not_observed_redacted>
receiver_remote_participant_observer_error_bucket=<none_or_redacted_bucket>
receiver_remote_participant_observer_timeout_bucket=<none_or_not_observed_redacted>
receiver_remote_participant_observer_remote_seen=<redacted_bool>
receiver_remote_participant_observer_audio_track_seen=<redacted_bool>
receiver_remote_participant_observer_liveness_seen=<redacted_bool>
receiver_remote_participant_observer_raw_identifiers_logged=false
```

Default runtime remains no-connect:

```text
second_physical_sender_livekit_join_path_default_disabled=true
second_physical_sender_livekit_readiness_credentials_ready=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Checks from the repair:

```text
swiftformat changed Swift files: passed
swiftlint changed Swift files: passed with existing file-length warning only
DirectCall subset: 149 tests passed
```

No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, video, microphone/camera permission on device, Matrix event emit, full call flow, physical hook reset/re-arm, or physical call attempt was performed during the repair.

## Next Phase

`2.48Z-Physical2 — one-shot two-physical-device sender-join/remote-participant proof`

This is the next physical proof. It is not a repeated Physical1 connect. It must be one-shot only and must not begin until fresh preflight and explicit phase confirmation are complete.

## Goal

Run exactly one two-physical-device proof that can classify whether the second physical iPhone joins the same LiveKit room as the receiver and whether receiver-side remote participant/audio/liveness is observed.

Before APNs, validate again:

```text
receiver_token_found=true
sender_token_found=true
receiver_user_hash=497015f5745c933a
sender_user_hash=7d434d7f252427fb
sender_equals_receiver=false
receiver_room_membership=join
sender_room_membership=join
room_encryption_algorithm_present=true
room_validation_preflight=pass
receiver_iphone_pending_metadata_auth_ready=true
second_physical_device_pending_metadata_auth_ready=true
remote_participant_presence_repair_present=true
second_physical_sender_livekit_readiness_present=true
receiver_remote_participant_observer_present=true
APNs_sent=false
safe_to_send_apns=true
```

Send exactly one sandbox APNs only after explicit phase-specific confirmation:

```text
SEND_2_48Z_PHYSICAL2
```

After `background_apns_push_result=sandbox_success`, do not send another APNs.

The future proof must classify:

```text
second_physical_sender_livekit_readiness_matrix_session_ready=<true_or_false>
second_physical_sender_livekit_readiness_same_room_ready=<true_or_false>
second_physical_sender_livekit_readiness_credentials_ready=<true_or_false>
second_physical_sender_livekit_join_path_present=true
second_physical_sender_livekit_join_path_default_disabled=<true_or_false_after_explicit_phase_gate>
second_physical_sender_livekit_join_path_audio_only=true
second_physical_sender_livekit_join_path_video_allowed=false
second_physical_sender_livekit_join_path_matrix_events_allowed=false
receiver_remote_participant_observer_result=<success_or_not_observed_redacted>
receiver_remote_participant_observer_error_bucket=<none_or_redacted_bucket>
receiver_remote_participant_observer_remote_seen=<true_or_false>
receiver_remote_participant_observer_audio_track_seen=<true_or_false>
receiver_remote_participant_observer_liveness_seen=<true_or_false>
livekit_remote_participant_seen=<true_or_false>
livekit_remote_audio_track_subscribed=<true_or_false>
livekit_audio_liveness_result=<success_redacted_or_not_observed_redacted_or_failed_redacted>
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Do not fake sender join or remote audio success. If the sender does not join or the receiver does not observe the remote participant/audio, classify the exact redacted bucket and stop.

## Hard Limits

Do not:

- send APNs before explicit one-shot confirmation
- run production APNs
- run repeated APNs
- use `dev/invite`
- run more than one media connect attempt
- run more than one LiveKit join attempt per controlled path
- retry media connect after the first result
- retry LiveKit join after the first result
- request camera permission
- enable video
- emit Matrix events
- start full direct-call flow
- log/document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`

## Required Checks Before Close

Run:

```bash
git diff --check
git diff --cached --check
```

Run forbidden project/signing scans:

```bash
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Privacy scan changed docs/diff for raw sensitive values.

Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- physical proof classification
- proof generation number if available
- sender-side LiveKit readiness classification
- sender-side join path result
- receiver remote participant observer result
- remote participant/audio/liveness result
- whether same LiveKit room requirement was satisfied
- whether two-physical-device requirement was satisfied
- whether camera/video/Matrix/full-flow safety stayed closed
- commit hash if docs were updated
- commit message
- changed files
- checks run
- final `git status --short --branch`
