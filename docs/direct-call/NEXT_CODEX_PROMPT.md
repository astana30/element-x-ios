# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Y — one-shot second-device remote audio/liveness physical proof` is complete and safely classified.

This was a physical one-shot proof. One sandbox APNs reached PushKit, one green Answer was received, pending metadata succeeded, media credentials succeeded, and exactly one controlled audio-only media connect / LiveKit join attempt completed. The second-device side used the simulator, and remote participant/audio/liveness was not observed. Do not treat this as remote-audio success.

Phase-specific proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48y-remote-audio-liveness-polled.txt
```

Reviewed proof generation:

```text
proof_generation=generation_12
```

## 2.48Y Classification

PushKit and CallKit Answer succeeded:

```text
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_report_result=reported
callkit_report_completion_observed=true
pushkit_completion_called=true
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
```

Metadata and credentials succeeded:

```text
pending_metadata_reference_present=true
pending_metadata_reference_redacted=true
pending_metadata_fetch_requested=true
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
pending_metadata_fetch_errcode=none
media_credentials_requested=true
media_credentials_request_authorized=true
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_url_received=true
media_credentials_expires_at_present=true
media_credentials_payload_redacted=true
```

One controlled audio-only connect attempt completed:

```text
physical6_runtime_enablement_url_hook_consumed=true
controlled_connect_first_attempt_requested=true
controlled_connect_first_attempt_allowed=true
controlled_connect_first_attempt_started=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_error_bucket=none
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
livekit_join_result=success_redacted
livekit_join_error_bucket=none
livekit_room_connected=true
livekit_local_participant_present=true
```

Remote audio/liveness did not succeed and was classified safely:

```text
remote_audio_liveness_diagnostics_present=true
remote_audio_liveness_diagnostics_debug_only=true
remote_audio_liveness_diagnostics_audio_only=true
remote_audio_liveness_diagnostics_video_allowed=false
remote_audio_liveness_diagnostics_matrix_events_allowed=false
remote_audio_liveness_diagnostics_raw_identifiers_logged=false
local_audio_publish_requested=false
local_audio_publish_started=false
local_audio_publish_result=not_requested
microphone_permission_requested=false
microphone_permission_result=not_requested_or_not_required_redacted
microphone_permission_not_required_reason=receive_only_audio_session_redacted
audio_route_available=false
audio_route_result=not_observed_redacted
livekit_remote_participant_seen=false
livekit_remote_participant_count_bucket=0
livekit_remote_audio_track_subscribed=false
livekit_remote_audio_track_unmuted=false
livekit_remote_audio_level_observed=false
livekit_audio_liveness_observed=false
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=none
livekit_cleanup_requested=true
livekit_cleanup_completed=true
livekit_cleanup_result=completed_redacted
```

Safety stayed closed:

```text
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

## Next Phase

`2.48Y-RemoteAudioPublishLivenessRepair — fix local publish and simulator remote liveness observability before any APNs retry`

This is a code/test diagnostics and repair phase only.

Do not send APNs in this phase.
Do not perform another physical connect in this phase.
Do not re-arm the one-shot hook in this phase.

## Goal

Investigate and fix why the one-shot proof reached LiveKit join success but still recorded:

```text
local_audio_publish_requested=false
audio_route_available=false
livekit_remote_participant_seen=false
livekit_remote_audio_track_subscribed=false
livekit_audio_liveness_result=not_observed_redacted
```

The repair should make a future simulator-backed or true-second-device proof able to distinguish:

```text
local publish not wired
local publish intentionally receive-only
simulator peer not actually joined
remote participant missing
remote audio track missing
remote audio muted
remote level/liveness not observed
cleanup completed
```

Do not fake remote liveness success.

## Hard Limits

Do not:

- send APNs
- run production APNs
- send repeated APNs
- run `dev/invite`
- perform physical media connect
- perform physical LiveKit join
- retry connect
- retry LiveKit join
- enable video
- request camera permission
- emit Matrix events
- start full direct-call flow
- reset or re-arm the consumed one-shot hook
- bypass CallKit Answer
- log or document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`

Allowed:

- Minimal Swift diagnostics/repair code.
- Minimal simulator/test-controlled liveness seams.
- Targeted DirectCall tests.
- Docs updates:
  - `docs/direct-call/STATUS.md`
  - `docs/direct-call/WORKLOG.md`
  - `docs/direct-call/NEXT_CODEX_PROMPT.md`

## Required Checks Before Commit

Run:

```bash
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
- whether local publish is now explicitly classified
- whether audio route is now explicitly classified
- whether simulator-backed remote peer readiness is explicit
- whether remote participant/audio track/liveness not-observed cases are explicit
- whether cleanup remains explicit
- whether default runtime remains no-connect
- commit hash
- commit message
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, repeated connect, video, camera permission, Matrix event emit, or full call flow were performed
