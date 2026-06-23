# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z` is complete and blocked at second physical device setup/session readiness.

Conclusion:

```text
2.48Z = two-physical-device readiness blocked
reason=second_device_session_not_ready_redacted
no APNs
no connect
no LiveKit join
no permissions
```

Readiness review found a second physical iPhone and the app is installed, but the app did not produce the redacted Matrix session proof after the DEBUG `/whoami` URL trigger:

```text
second_physical_device_available=true
second_physical_device_kind=iphone
second_physical_device_app_installed=true
second_physical_device_matrix_session_ready=false
second_physical_device_expected_user_hash=7d434d7f252427fb
second_physical_device_same_room_ready=false
second_physical_device_livekit_remote_peer_ready=false
second_physical_device_session_proof_requested=true
second_physical_device_session_proof_available=false
second_physical_device_session_proof_failure=proof_file_missing_redacted
```

Because the second physical app-session proof was unavailable, this phase did not freshly validate distinct accounts, same encrypted room readiness, or LiveKit remote peer readiness:

```text
distinct_accounts_validated=false
same_encrypted_room_readiness_validated=false
production_like_two_physical_device_proof=false
second_device_remote_audio_readiness=not_ready_redacted
```

No APNs, no production APNs, no repeated APNs, no `dev/invite`, no repeated connect, no LiveKit join, no video, no microphone/camera permission, no Matrix event emit, no full call flow, no one-shot hook reset/re-arm, and no physical call attempt were performed.

## Next Phase

`2.48Z-SecondPhysicalDeviceSetup — prepare second physical device remote peer, no APNs/connect`

This is setup/readiness only. Do not run APNs or any media/connect path.

## Goal

Prepare the second physical iOS device as the future remote peer for a production-like two-physical-device remote audio/liveness proof.

Required setup target:

```text
second_physical_device_available=true
second_physical_device_kind=iphone
second_physical_device_app_installed=true
second_physical_device_matrix_session_ready=true
second_physical_device_expected_user_hash=7d434d7f252427fb
second_physical_device_same_room_ready=true
second_physical_device_livekit_remote_peer_ready=true
remote_peer_kind=physical_ios_redacted
remote_peer_physical_device=true
simulator_assisted_remote_audio_proof=false
production_like_two_physical_device_proof=true
second_device_remote_audio_readiness=ready_redacted
```

Allowed readiness-only work:

- verify the second physical device is connected and online
- install or launch the Debug app on the second physical device if needed
- run redacted app-session `/whoami` proof on the second physical device
- validate distinct account hashes using redacted/stable hashes only
- validate same encrypted room membership using local-only tokens if supplied by the user
- classify readiness without sending APNs

If the second physical device session still cannot be validated, stop and classify:

```text
2.48Z-SecondPhysicalDeviceSetup = blocked
reason=second_device_session_not_ready_redacted
APNs_sent=false
media_connect_requested=false
livekit_join_requested=false
```

If the second physical device is ready, set next phase to:

```text
2.48Z-Physical1 — one-shot two-physical-device remote audio/liveness proof
```

Do not set the next phase to a physical APNs attempt unless the second physical device session and room readiness are both validated.

## Hard Limits

Do not:

- send APNs
- run production APNs
- run repeated APNs
- use `dev/invite`
- start media connect
- join LiveKit
- request microphone permission
- request camera permission
- enable video
- emit Matrix events
- start full direct-call flow
- reset or re-arm the one-shot physical connect hook
- perform another physical call attempt
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

- second physical device setup classification
- whether second physical app/session is ready
- whether distinct accounts are validated
- whether same encrypted room readiness is validated
- whether APNs remained unsent
- whether no connect or LiveKit join was performed
- whether camera/video/Matrix/full-flow safety stayed closed
- commit hash if docs were updated
- commit message
- changed files
- checks run
- final `git status --short --branch`
