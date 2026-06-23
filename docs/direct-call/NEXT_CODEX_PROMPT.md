# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Y-RemoteAudioPublishLivenessRepair — repair/classify local audio publish and remote liveness path, no APNs/connect` is complete.

This was a code/test repair phase only. No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, microphone/camera permission on device, Matrix event emission, full call flow, or hook reset/re-arm was performed.

The previous physical proof remains:

```text
2.48Y result = safely classified, not remote-audio success
proof_generation=generation_12
livekit_join_result=success_redacted
local_audio_publish_result=not_requested
livekit_audio_liveness_result=not_observed_redacted
```

## Repair Added

The proof now emits repair guard fields:

```text
remote_audio_publish_liveness_repair_present=true
remote_audio_publish_liveness_repair_debug_only=true
remote_audio_publish_liveness_repair_requires_livekit_join_success=true
remote_audio_publish_liveness_repair_classifies_publish_not_requested=true
remote_audio_publish_liveness_repair_classifies_publish_success=true
remote_audio_publish_liveness_repair_classifies_publish_failure=true
remote_audio_publish_liveness_repair_classifies_simulator_peer=true
remote_audio_publish_liveness_repair_classifies_remote_missing=true
remote_audio_publish_liveness_repair_classifies_remote_track_missing=true
remote_audio_publish_liveness_repair_classifies_liveness_observed=true
remote_audio_publish_liveness_repair_no_video=true
remote_audio_publish_liveness_repair_no_matrix_events=true
remote_audio_publish_liveness_repair_raw_identifiers_logged=false
```

After successful LiveKit audio join, the current receive-only bridge now classifies local publish explicitly:

```text
local_audio_publish_requested=false
local_audio_publish_started=false
local_audio_publish_result=not_required_redacted
local_audio_publish_not_required_reason=receive_only_audio_connect_redacted
```

If LiveKit join is not successful, publish/liveness now fail closed:

```text
local_audio_publish_result=blocked_redacted
local_audio_publish_error_bucket=livekit_join_not_success_redacted
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=livekit_join_not_success_redacted
```

Remote peer and limitation fields are available:

```text
remote_peer_kind=<ios_simulator_redacted_or_physical_ios_redacted_or_unknown_redacted>
remote_peer_physical_device=<true_or_false_or_unknown>
simulator_assisted_remote_audio_proof=<true_or_false>
production_like_two_physical_device_proof=<true_or_false>
remote_audio_liveness_limitation=<simulator_assisted_redacted_or_redacted_bucket>
```

Remote liveness not-observed buckets now distinguish:

```text
livekit_audio_liveness_error_bucket=remote_participant_missing_redacted
livekit_audio_liveness_error_bucket=remote_audio_track_missing_redacted
```

Safety remains:

```text
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
controlled_connect_first_attempt_repeated=false
media_credentials_reuse_allowed=false
```

## Next Phase

`2.48Y-Physical2 — one-shot simulator-assisted remote audio/liveness proof`

This is a single physical proof attempt only after fresh preflight and explicit confirmation. It is not a repeated-connect phase and it is not a production-like two-physical-device proof.

If a true second physical iOS device becomes available instead, classify:

```text
remote_peer_kind=physical_ios_redacted
remote_peer_physical_device=true
simulator_assisted_remote_audio_proof=false
production_like_two_physical_device_proof=true
```

If the simulator is used, classify:

```text
remote_peer_kind=ios_simulator_redacted
remote_peer_physical_device=false
simulator_assisted_remote_audio_proof=true
production_like_two_physical_device_proof=false
remote_audio_liveness_limitation=simulator_assisted_redacted
```

Do not fake remote audio/liveness success.

## Hard Limits

Do not:

- run `dev/invite`
- run production APNs
- send repeated APNs after one successful sandbox APNs send
- perform more than one media-connect attempt
- perform more than one LiveKit join attempt per controlled path
- enable video
- request camera permission
- emit Matrix events
- start full direct-call flow
- retry media connect after the first result
- retry LiveKit join after the first result
- log/document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`

Allowed in this phase only:

```text
one DEBUG-only enablement hook activation
one sandbox APNs send
one green Answer
one pending metadata fetch
one media credentials request
one controlled audio-only media connect attempt
one LiveKit audio connect/join attempt
remote audio/liveness observation
microphone permission request only if required for audio
```

Forbidden even in this phase:

```text
camera_permission_requested=true
matrix_event_emit_requested=true
real_call_flow_started=true
controlled_connect_first_attempt_repeated=true
repeated_apns=true
repeated_connect_attempt=true
video_enabled=true
```

## Required Proof Fields

Use phase-specific proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48y-physical2-remote-audio-liveness-polled.txt
```

Require:

```text
proof_generation
physical_voip_push_received=true
pushkit_callback_invoked=true
callkit_report_result=reported
callkit_answer_action_received=true
pending_metadata_fetch_result=success_redacted
media_credentials_result=success_redacted
controlled_connect_first_attempt_result=<success_or_blocked_redacted>
controlled_connect_first_attempt_repeated=false
physical6_runtime_enablement_url_hook_consumed=true
remote_audio_publish_liveness_repair_present=true
livekit_join_result=<success_redacted_or_failed_redacted_or_not_requested>
local_audio_publish_result=<success_redacted_or_failed_redacted_or_not_required_redacted_or_blocked_redacted>
local_audio_publish_not_required_reason=<redacted_bucket_or_none>
remote_peer_kind=<ios_simulator_redacted_or_physical_ios_redacted_or_unknown_redacted>
remote_peer_physical_device=<true_or_false_or_unknown>
simulator_assisted_remote_audio_proof=<true_or_false>
production_like_two_physical_device_proof=<true_or_false>
remote_audio_liveness_limitation=<redacted_bucket_or_none>
livekit_remote_participant_seen=<true_or_false>
livekit_remote_audio_track_subscribed=<true_or_false>
livekit_remote_audio_track_unmuted=<true_or_false>
livekit_audio_liveness_result=<success_redacted_or_not_observed_redacted>
livekit_audio_liveness_error_bucket=<none_or_redacted_bucket>
livekit_cleanup_result=<completed_redacted_or_not_completed_redacted_or_not_requested>
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Required Checks Before Commit

Run:

```bash
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Privacy scan changed docs/diff for raw sensitive values. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- whether remote audio/liveness proof succeeded or was safely classified
- proof generation number
- CallKit report result
- pending metadata result
- media credentials result
- first attempt result bucket
- LiveKit join result
- local audio publish result and not-required reason if present
- remote peer kind / simulator limitation classification
- remote participant/audio track/liveness result
- cleanup result
- whether camera permission remained false
- whether Matrix event emit remained false
- whether full call flow remained false
- whether first attempt repeated=false
- whether hook was consumed
- commit hash if docs were updated
- commit message
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no repeated APNs, production APNs, `dev/invite`, repeated connect, repeated LiveKit join, video, camera permission, Matrix event emit, or full call flow were performed
