# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48W-DisconnectCleanupDiagnostics — add/verify controlled disconnect cleanup proof, no APNs/connect` is complete.

This was a code/test diagnostics phase. No APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, new LiveKit join, video, microphone/camera permission on device, Matrix event emission, or full call flow was performed.

Latest 2.48W close-out commit before this phase:

```text
646c8ad1ab1d6e4e7aee84007f4112ea5aaf6c1d Classify disconnect cleanup proof gap
```

## Diagnostics Implemented

The VoIP proof now emits DEBUG-only redacted disconnect cleanup diagnostics:

```text
disconnect_cleanup_diagnostics_present=true
disconnect_cleanup_diagnostics_debug_only=true
disconnect_cleanup_diagnostics_callkit_cleanup_requested=<redacted_bool>
disconnect_cleanup_diagnostics_callkit_cleanup_result=<redacted_result>
disconnect_cleanup_diagnostics_end_action_expected=<redacted_bool>
disconnect_cleanup_diagnostics_end_action_delivered=<redacted_bool>
disconnect_cleanup_diagnostics_end_action_fulfilled=<redacted_bool>
disconnect_cleanup_diagnostics_end_action_origin=<redacted_origin>
disconnect_cleanup_diagnostics_end_action_uuid_matched=<redacted_bool>
disconnect_cleanup_diagnostics_end_action_generation_matched=<redacted_bool>
disconnect_cleanup_diagnostics_end_action_source_matched=<redacted_bool>
disconnect_cleanup_diagnostics_provider_end_reported=<redacted_bool>
disconnect_cleanup_diagnostics_local_cleanup_completed=<redacted_bool>
disconnect_cleanup_diagnostics_audio_session_deactivated=<redacted_bool>
disconnect_cleanup_diagnostics_livekit_cleanup_requested=<redacted_bool>
disconnect_cleanup_diagnostics_livekit_cleanup_completed=<redacted_bool>
disconnect_cleanup_diagnostics_one_shot_consumed=<redacted_bool>
disconnect_cleanup_diagnostics_no_repeated_connect=true
disconnect_cleanup_diagnostics_no_matrix_events=true
disconnect_cleanup_diagnostics_no_video=true
disconnect_cleanup_diagnostics_raw_identifiers_logged=false
disconnect_cleanup_diagnostics_end_timing_classification=<redacted_bucket>
disconnect_cleanup_diagnostics_result=<redacted_result>
```

Provider/local cleanup without an expected CallKit End action is now classified explicitly:

```text
disconnect_cleanup_diagnostics_end_action_expected=false
disconnect_cleanup_diagnostics_end_action_delivered=false
disconnect_cleanup_diagnostics_local_cleanup_completed=true
disconnect_cleanup_diagnostics_provider_end_reported=true
disconnect_cleanup_diagnostics_result=local_or_provider_cleanup_sufficient_redacted
```

If a CallKit End action is expected, success requires delivery, fulfillment, UUID/generation/source matching, and non-unknown timing:

```text
disconnect_cleanup_diagnostics_end_action_expected=true
disconnect_cleanup_diagnostics_end_action_delivered=true
disconnect_cleanup_diagnostics_end_action_fulfilled=true
disconnect_cleanup_diagnostics_end_action_uuid_matched=true
disconnect_cleanup_diagnostics_end_action_generation_matched=true
disconnect_cleanup_diagnostics_end_action_source_matched=true
```

Unknown End action timing is classified as `end_action_timing_unknown_redacted`, not success.

## Preserved Safety

```text
default_runtime_no_connect=true
one_shot_hook_consumed=true
first_attempt_repeated=false
credentials_non_reusable=true
no_repeated_media_connect=true
no_livekit_rejoin=true
video_disabled=true
camera_permission_false=true
matrix_event_emit_false=true
full_call_flow_false=true
raw_identifiers_logged=false
```

## Next Phase

`2.48X — second-device remote audio/liveness readiness review, no repeated connect`

This is a readiness/review phase only unless a later prompt explicitly authorizes narrow code changes. Do not set up another physical APNs/connect attempt yet.

Suggested scope:

```text
review_second_device_remote_audio_liveness_readiness=true
review_first_connect_success_constraints=true
review_disconnect_cleanup_diagnostics_before_remote_liveness=true
review_no_repeated_connect_regression=true
review_no_video_camera_matrix_full_flow_regression=true
```

## Hard Limits

Do not:

- send APNs
- send production APNs
- send repeated APNs
- run `dev/invite`
- retry media connect
- retry LiveKit join
- enable video
- request microphone permission
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
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

If code changes are made, also run the focused DirectCall subset:

```bash
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
```

Privacy scan changed docs/diff for raw sensitive values. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- 2.48X readiness review result
- whether disconnect cleanup diagnostics remain sufficient
- whether one-shot hook stayed consumed
- whether first attempt repeated=false
- whether credentials stayed non-reusable
- whether media connect was not repeated
- commit hash if docs or code were updated
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, video, microphone/camera permission, Matrix event emit, or full call flow was performed
