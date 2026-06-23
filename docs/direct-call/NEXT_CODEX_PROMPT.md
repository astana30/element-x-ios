# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48X-RemoteAudioLivenessDiagnostics — add redacted remote audio/liveness proof fields, no APNs/connect` is complete.

This was a code/test diagnostics phase. No APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, LiveKit join on device, video, microphone/camera permission on device, Matrix event emission, or full call flow was performed.

## Diagnostics Added

The VoIP proof now emits DEBUG-only redacted remote audio/liveness diagnostics:

```text
remote_audio_liveness_diagnostics_present=true
remote_audio_liveness_diagnostics_debug_only=true
remote_audio_liveness_diagnostics_audio_only=true
remote_audio_liveness_diagnostics_video_allowed=false
remote_audio_liveness_diagnostics_matrix_events_allowed=false
remote_audio_liveness_diagnostics_raw_identifiers_logged=false
livekit_join_result=<success_redacted_or_failed_redacted_or_not_requested>
livekit_join_error_bucket=<none_or_redacted_bucket>
livekit_room_connected=<redacted_bool>
livekit_room_disconnected=<redacted_bool>
livekit_local_participant_present=<redacted_bool>
local_audio_publish_requested=<redacted_bool>
local_audio_publish_started=<redacted_bool>
local_audio_publish_result=<success_redacted_or_failed_redacted_or_not_requested>
local_audio_publish_error_bucket=<none_or_redacted_bucket>
microphone_permission_requested=<redacted_bool>
microphone_permission_result=<requested_redacted_or_not_requested_or_not_required_redacted>
microphone_permission_not_required_reason=<redacted_reason>
audio_route_available=<redacted_bool>
audio_route_result=<available_redacted_or_not_observed_redacted>
livekit_remote_participant_seen=<redacted_bool>
livekit_remote_participant_count_bucket=<redacted_bucket>
livekit_remote_audio_track_subscribed=<redacted_bool>
livekit_remote_audio_track_unmuted=<redacted_bool>
livekit_remote_audio_level_observed=<redacted_bool>
livekit_audio_liveness_observed=<redacted_bool>
livekit_audio_liveness_result=<success_redacted_or_not_observed_redacted>
livekit_audio_liveness_error_bucket=<none_or_redacted_bucket>
livekit_cleanup_requested=<redacted_bool>
livekit_cleanup_completed=<redacted_bool>
livekit_cleanup_result=<completed_redacted_or_not_completed_redacted_or_not_requested>
```

Missing remote audio must classify as `not_observed_redacted`, not success.

## Preserved Safety

```text
default_runtime_no_connect=true
one_shot_hook_consumed=true
first_attempt_repeated=false
credentials_non_reusable=true
no_repeated_media_connect=true
video_disabled=true
camera_permission_false=true
matrix_event_emit_false=true
full_call_flow_false=true
raw_identifiers_logged=false
```

## Next Phase

`2.48Y — one-shot second-device remote audio/liveness physical proof`

This is a single physical proof attempt only after fresh preflight and explicit confirmation. It is not a repeated-connect phase.

## Required Future Proof Fields

The future 2.48Y proof must capture and classify:

```text
proof_generation
physical_voip_push_received
pushkit_callback_invoked
callkit_report_result
callkit_answer_action_received
pending_metadata_fetch_result
media_credentials_result
controlled_connect_first_attempt_result
controlled_connect_first_attempt_repeated
remote_audio_liveness_diagnostics_present
livekit_join_requested
livekit_connect_audio_invoked
livekit_join_result
livekit_join_error_bucket
livekit_room_connected
livekit_room_disconnected
livekit_local_participant_present
local_audio_publish_requested
local_audio_publish_started
local_audio_publish_result
microphone_permission_requested
microphone_permission_result
microphone_permission_not_required_reason
audio_route_available
audio_route_result
livekit_remote_participant_seen
livekit_remote_participant_count_bucket
livekit_remote_audio_track_subscribed
livekit_remote_audio_track_unmuted
livekit_remote_audio_level_observed
livekit_audio_liveness_observed
livekit_audio_liveness_result
livekit_audio_liveness_error_bucket
livekit_cleanup_requested
livekit_cleanup_completed
livekit_cleanup_result
camera_permission_requested
matrix_event_emit_requested
real_call_flow_started
blocked_reason
```

## Hard Limits

Do not:

- send APNs before fresh preflight passes and explicit one-shot confirmation is reached
- send production APNs
- send repeated APNs
- run `dev/invite`
- perform repeated connect
- perform repeated LiveKit join
- enable video
- request camera permission
- emit Matrix events
- start full call flow
- reset or re-arm the one-shot hook after it is consumed
- bypass CallKit Answer
- request credentials before metadata fetch success
- log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`

After a single sandbox APNs succeeds, do not send another APNs automatically. After one controlled connect/LiveKit attempt, do not retry connect.

## Required Checks Before Any Commit

Run:

```bash
git status --short --branch
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Privacy scan changed files/diff for raw sensitive values. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- 2.48Y proof classification
- proof generation reviewed
- whether LiveKit join result is explicit
- whether local audio publish result is explicit
- whether microphone requested/not-required state is explicit
- whether remote participant/audio track/liveness result is explicit
- whether LiveKit/audio cleanup result is explicit
- whether one-shot hook stayed consumed
- whether first attempt repeated=false
- whether credentials stayed non-reusable
- whether media connect was not repeated
- changed files if docs were updated
- checks run
- final `git status --short --branch`
- explicit statement that no repeated APNs, production APNs, `dev/invite`, repeated connect, video, camera permission, Matrix event emit, or full call flow were performed
