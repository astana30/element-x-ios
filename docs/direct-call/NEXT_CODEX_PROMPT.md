# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48X — second-device remote audio/liveness readiness review, no repeated connect` is complete.

Classification:

```text
2.48X result = remote audio/liveness proof incomplete; targeted diagnostics needed
```

This was a docs-only review of the existing Physical8 proof:

```text
/tmp/salemx-voip-push-receipt-proof-2.48t-physical8-first-audio-connect-polled.txt
```

No APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, new LiveKit join, video, microphone/camera permission on device, Matrix event emission, or full call flow was performed.

## What Physical8 Already Proves

Reviewed proof generation:

```text
proof_generation=generation_14
```

The first controlled audio-only connect completed once:

```text
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_error_bucket=none
controlled_connect_first_attempt_repeated=false
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
```

The one-shot and safety boundaries remained closed:

```text
physical6_runtime_enablement_url_hook_consumed=true
media_credentials_reuse_allowed=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
controlled_connect_first_attempt_video_allowed=false
controlled_connect_first_attempt_matrix_events_allowed=false
```

Audio-session activation/deactivation is present through existing CallKit proof fields:

```text
callkit_audio_session_did_activate=true
callkit_audio_session_did_deactivate=true
```

## Proof Gaps

The existing Physical8 proof and current proof surface do not explicitly prove second-device remote audio/liveness. Missing or insufficient fields include:

```text
livekit_join_result
livekit_join_error_bucket
livekit_room_connected
livekit_room_disconnected
livekit_local_participant_present
livekit_remote_participant_seen
livekit_remote_participant_count_bucket
livekit_remote_audio_track_subscribed
livekit_remote_audio_track_unmuted
livekit_remote_audio_level_observed
livekit_audio_liveness_observed
livekit_audio_liveness_result
livekit_audio_liveness_error_bucket
local_audio_publish_requested
local_audio_publish_started
local_audio_publish_result
microphone_permission_result
audio_route_available
```

The current code can emit disconnect cleanup diagnostics for future captures, but the Physical8 proof predates those fields:

```text
disconnect_cleanup_diagnostics_present=<missing in Physical8 proof>
disconnect_cleanup_diagnostics_livekit_cleanup_requested=<missing in Physical8 proof>
disconnect_cleanup_diagnostics_livekit_cleanup_completed=<missing in Physical8 proof>
```

## Next Phase

`2.48X-RemoteAudioLivenessDiagnostics — add redacted remote audio/liveness proof fields, no APNs/connect`

This is a code/test diagnostics phase only. Do not perform another physical APNs/connect attempt.

## Goal

Add redacted proof fields and tests so a future one-shot second-device proof can safely answer:

```text
did LiveKit join actually succeed
did local audio publish start
did remote participant become visible
did remote audio track subscribe
did remote audio become audible / liveness observed
did microphone permission become required or remain unnecessary
did audio route stay valid
did disconnect cleanup clean LiveKit/audio state
```

## Required Fields

Add or verify DEBUG-only redacted proof fields covering:

```text
remote_audio_liveness_diagnostics_present
remote_audio_liveness_diagnostics_debug_only
livekit_join_result
livekit_join_error_bucket
livekit_room_connected
livekit_room_disconnected
livekit_local_participant_present
livekit_remote_participant_seen
livekit_remote_participant_count_bucket
livekit_remote_audio_track_subscribed
livekit_remote_audio_track_unmuted
livekit_remote_audio_level_observed
livekit_audio_liveness_observed
livekit_audio_liveness_result
livekit_audio_liveness_error_bucket
local_audio_publish_requested
local_audio_publish_started
local_audio_publish_result
microphone_permission_requested
microphone_permission_result
audio_session_did_activate
audio_session_did_deactivate
audio_route_available
disconnect_cleanup_diagnostics_livekit_cleanup_requested
disconnect_cleanup_diagnostics_livekit_cleanup_completed
remote_audio_liveness_raw_identifiers_logged
```

Default safe expectations:

```text
remote_audio_liveness_diagnostics_present=true
remote_audio_liveness_diagnostics_debug_only=true
remote_audio_liveness_raw_identifiers_logged=false
controlled_connect_first_attempt_repeated=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Do not fake remote audio/liveness success. If the runtime cannot observe a value, classify it explicitly as missing/not_observed/not_requested.

## Hard Limits

Do not:

- send APNs
- send production APNs
- send repeated APNs
- run `dev/invite`
- retry media connect
- retry LiveKit join
- enable video
- request microphone permission on device
- request camera permission
- emit Matrix events
- start full call flow
- reset or re-arm the one-shot hook
- perform another physical call attempt
- bypass CallKit Answer
- request credentials before metadata fetch success
- consume the DEBUG hook before metadata plus credentials eligibility
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`
- log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID

## Required Checks Before Any Commit

Run:

```bash
git status --short --branch
swiftformat <changed Swift files>
swiftlint lint <changed Swift files>
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Privacy scan changed files/diff for raw sensitive values. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- implementation summary
- whether LiveKit join result is now explicit
- whether local audio publish result is now explicit
- whether remote participant/audio track/liveness result is now explicit
- whether microphone permission state is explicit
- whether audio route availability is explicit
- whether disconnect cleanup covers LiveKit/audio cleanup
- whether one-shot hook stayed consumed
- whether first attempt repeated=false
- whether credentials stayed non-reusable
- commit hash
- commit message
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, video, microphone/camera permission on device, Matrix event emit, or full call flow was performed
