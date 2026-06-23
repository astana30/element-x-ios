# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SecondPhysicalDeviceSetup` is complete.

Conclusion:

```text
2.48Z-SecondPhysicalDeviceSetup result = ready for one-shot two-physical-device remote audio proof
second_physical_device_available=true
second_physical_device_app_session_ready=true
distinct_accounts_validated=true
same_encrypted_room_validated=true
```

Physical device and app readiness:

```text
primary_receiver_device_present=true
second_physical_device_present=true
second_physical_device_kind=iphone
second_physical_device_app_installed=true
second_physical_device_app_launched=true
```

Redacted app-session proofs:

```text
second_physical_device_matrix_session_present=true
second_physical_device_matrix_session_whoami_result=success_redacted
second_physical_device_matrix_session_user_hash=7d434d7f252427fb
second_physical_device_matrix_session_user_hash_matches_expected=true
second_physical_device_matrix_session_device_present=true
second_physical_device_pending_metadata_auth_ready=true

receiver_iphone_matrix_session_present=true
receiver_iphone_matrix_session_whoami_result=success_redacted
receiver_iphone_matrix_session_user_hash=497015f5745c933a
receiver_iphone_matrix_session_device_present=true
receiver_iphone_pending_metadata_auth_ready=true
```

Room readiness passed using in-memory tokens only:

```text
receiver_token_found=true
sender_token_found=true
receiver_user_hash=497015f5745c933a
sender_user_hash=7d434d7f252427fb
sender_equals_receiver=false
sender_room_membership=join
receiver_room_membership=join
room_encryption_algorithm_present=true
distinct_accounts_validated=true
same_encrypted_room_validated=true
room_validation_preflight=pass
safe_for_future_two_physical_proof=true
APNs_sent=false
```

No APNs, no production APNs, no repeated APNs, no `dev/invite`, no connect, no LiveKit join, no video, no microphone/camera permission, no Matrix event emit, no full call flow, no one-shot hook reset/re-arm, and no physical call attempt were performed during setup.

## Next Phase

`2.48Z-Physical1 — one-shot two-physical-device remote audio/liveness proof`

This is the first future production-like two-physical-device remote audio/liveness proof. It must be one-shot only and must not begin until fresh preflight and explicit phase confirmation are complete.

## Goal

Run exactly one two-physical-device physical proof using:

```text
iPhone PRO = real receiver / PushKit / CallKit / Answer
second physical iPhone = remote peer / sender-side physical participant
remote_peer_kind=physical_ios_redacted
remote_peer_physical_device=true
simulator_assisted_remote_audio_proof=false
production_like_two_physical_device_proof=true
```

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
APNs_sent=false
safe_to_send_apns=true
```

Send exactly one sandbox APNs only after explicit phase-specific confirmation. After `background_apns_push_result=sandbox_success`, do not send another APNs.

Required proof should classify:

```text
pending_metadata_fetch_result=<success_redacted_or_blocked_redacted>
media_credentials_result=<success_redacted_or_not_requested_or_blocked_redacted>
controlled_connect_first_attempt_repeated=false
livekit_join_result=<success_redacted_or_failed_redacted_or_not_requested>
remote_peer_kind=physical_ios_redacted
remote_peer_physical_device=true
simulator_assisted_remote_audio_proof=false
production_like_two_physical_device_proof=true
livekit_remote_participant_seen=<true_or_false>
livekit_remote_audio_track_subscribed=<true_or_false>
livekit_audio_liveness_result=<success_redacted_or_not_observed_redacted_or_failed_redacted>
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Do not fake remote audio success. If remote participant/audio/liveness is missing, classify it as not observed.

## Hard Limits

Do not:

- send APNs before explicit one-shot confirmation
- run production APNs
- run repeated APNs
- use `dev/invite`
- run more than one media connect attempt
- run more than one LiveKit join attempt
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
- whether pending metadata and media credentials succeeded
- first attempt result and repeated=false
- LiveKit join result
- physical remote peer classification
- remote participant/audio/liveness result
- whether camera/video/Matrix/full-flow safety stayed closed
- commit hash if docs were updated
- commit message
- changed files
- checks run
- final `git status --short --branch`
