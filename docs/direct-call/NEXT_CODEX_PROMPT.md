# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderJoinHookActivationRepair` is complete.

This was a code/test/docs repair phase only. It did not send APNs and did not run a physical connect.

Key result:

```text
sender-side LiveKit join activation hook can now be explicitly armed/triggered once under DEBUG/test control
default runtime remains no-connect/no-join
receiver observer has distinct redacted sender-join and remote-participant buckets
```

New proof fields:

```text
sender_side_livekit_join_activation_present=true
sender_side_livekit_join_activation_debug_only=true
sender_side_livekit_join_activation_default_disabled=true
sender_side_livekit_join_activation_requires_sender_readiness=true
sender_side_livekit_join_activation_requires_same_room=true
sender_side_livekit_join_activation_audio_only=true
sender_side_livekit_join_activation_video_allowed=false
sender_side_livekit_join_activation_matrix_events_allowed=false
sender_side_livekit_join_activation_raw_identifiers_logged=false
sender_side_livekit_join_activation_armed=<redacted_bool>
sender_side_livekit_join_activation_triggered=<redacted_bool>
sender_side_livekit_join_activation_consumed=<redacted_bool>
sender_side_livekit_join_activation_repeated=<redacted_bool>
sender_side_livekit_join_activation_blocked_reason=<redacted_bucket>
```

Default-disabled state:

```text
sender_side_livekit_join_activation_armed=false
sender_side_livekit_join_activation_triggered=false
sender_side_livekit_join_activation_consumed=false
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_activation_blocked_reason=default_disabled_no_connect
sender_side_livekit_join_requested=false
sender_side_livekit_join_result=not_requested
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

When the DEBUG hook is armed in tests:

```text
sender_side_livekit_join_hook_armed=true
sender_side_livekit_join_activation_armed=true
sender_side_livekit_join_activation_triggered=<redacted_bool>
sender_side_livekit_join_activation_consumed=<redacted_bool>
sender_side_livekit_join_activation_repeated=<redacted_bool>
sender_side_livekit_join_requested=<redacted_bool>
sender_side_livekit_join_result=<redacted_bucket>
sender_side_livekit_join_error_bucket=<redacted_bucket>
```

Receiver observer buckets now include:

```text
sender_join_hook_not_armed_redacted
sender_join_not_requested_redacted
sender_join_blocked_redacted
sender_join_failed_redacted
sender_join_success_but_remote_missing_redacted
remote_participant_seen_redacted
remote_audio_track_missing_redacted
remote_liveness_not_observed_redacted
```

Safety from the repair phase:

```text
APNs_sent=false
dev_invite_used=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Next Phase

`2.48Z-Physical2-Retry3 — one-shot two-physical-device sender join activation / remote participant proof`

This is the next physical attempt only after fresh preflight and explicit one-shot confirmation.

Do not set the phase to general/full direct-call flow.

## Retry3 Goals

Run one two-physical-device proof that:

```text
uses the repaired sender-side join activation hook
arms sender readiness before APNs
arms sender-side join activation once
keeps sender join audio-only
observes whether receiver sees remote participant/audio/liveness
classifies result without raw identifiers
```

Required future proof fields:

```text
sender_side_livekit_join_activation_present=true
sender_side_livekit_join_activation_debug_only=true
sender_side_livekit_join_activation_default_disabled=false
sender_side_livekit_join_activation_requires_sender_readiness=true
sender_side_livekit_join_activation_requires_same_room=true
sender_side_livekit_join_activation_audio_only=true
sender_side_livekit_join_activation_video_allowed=false
sender_side_livekit_join_activation_matrix_events_allowed=false
sender_side_livekit_join_activation_raw_identifiers_logged=false
sender_side_livekit_join_activation_armed=true
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_activation_blocked_reason=<redacted_bucket>
sender_side_livekit_join_hook_armed=true
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=<redacted_bucket>
sender_side_livekit_join_error_bucket=<redacted_bucket>
sender_side_livekit_join_repeated=false
```

Receiver observer fields to classify:

```text
receiver_remote_participant_observer_result=<redacted_bucket>
receiver_remote_participant_observer_error_bucket=<redacted_bucket>
livekit_remote_participant_seen=<redacted_bool>
livekit_remote_audio_track_subscribed=<redacted_bool>
livekit_remote_audio_track_unmuted=<redacted_bool>
livekit_audio_liveness_observed=<redacted_bool>
livekit_audio_liveness_result=<redacted_bucket>
livekit_audio_liveness_error_bucket=<redacted_bucket>
```

Success path may classify as remote participant/audio/liveness observed. Failure paths must use one of the repaired buckets:

```text
sender_join_hook_not_armed_redacted
sender_join_not_requested_redacted
sender_join_blocked_redacted
sender_join_failed_redacted
sender_join_success_but_remote_missing_redacted
remote_participant_seen_redacted
remote_audio_track_missing_redacted
remote_liveness_not_observed_redacted
```

## Hard Limits

Do not:

* send APNs before fresh preflight and explicit one-shot confirmation
* send production APNs
* send repeated APNs
* run `dev/invite`
* run repeated connect
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Allowed physical side effects for Retry3 only after explicit confirmation:

```text
one sandbox APNs
one receiver Answer
one controlled receiver audio connect attempt
one receiver LiveKit audio join attempt
one sender-side join activation attempt
```

## Suggested Checks Before Physical Retry

Before any physical attempt, verify:

```bash
git status --short --branch
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run privacy scans over changed files/diff. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

* whether Retry3 preflight passed
* whether sender join activation was armed
* whether exactly one sandbox APNs was sent after confirmation
* whether receiver Answer was received
* whether sender join activation triggered/consumed once
* whether remote participant/audio/liveness was observed
* final classification
* final `git status --short --branch`
