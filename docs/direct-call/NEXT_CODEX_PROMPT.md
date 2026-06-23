# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48V — controlled audio session lifecycle review, no repeated connect` is complete.

This was a docs-only review of the existing Physical8 proof. No APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, new LiveKit join, video, microphone/camera permission, Matrix event emission, or full call flow was performed.

Latest 2.48U close-out commit:

```text
41acb79d9b2c3c7670bc150062fb741a7cff64ad Close first-connect cleanup verification
```

## Physical8 Proof Reviewed

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48t-physical8-first-audio-connect-polled.txt
```

Classification:

```text
2.48V result = audio session lifecycle sufficient for next cleanup/lifecycle phase
```

First controlled audio-connect result:

```text
proof_generation=generation_14
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_error_bucket=none
controlled_connect_first_attempt_repeated=false
physical6_runtime_enablement_url_hook_consumed=true
```

The already-closed Physical8 media and LiveKit activity stayed limited to one audio-only attempt:

```text
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
```

CallKit/provider audio-session lifecycle fields were sufficient:

```text
callkit_provider_did_activate_audio_session=true
callkit_audio_session_did_activate=true
callkit_provider_did_deactivate_audio_session=true
callkit_audio_session_did_deactivate=true
audio_session_did_activate_before_first_action=false
audio_session_did_deactivate_before_first_action=false
```

Cleanup and credentials non-reuse remained verified:

```text
controlled_callkit_cleanup_requested=true
controlled_callkit_cleanup_result=ended
media_credentials_cleanup_requested=true
media_credentials_cleanup_result=cleared
media_credentials_reuse_allowed=false
```

Safety fields stayed closed:

```text
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## 2.48V Conclusion

```text
first controlled audio-connect already succeeded
no repeated APNs
no repeated connect
one-shot hook consumed
credentials non-reusable
video disabled
microphone permission false
camera permission false
Matrix event emit false
full call flow false
```

Audio session lifecycle proof is sufficient. Do not run another APNs helper or another connect attempt for this result.

## Next Phase

`2.48W — controlled disconnect/end-call cleanup review, no repeated connect`

This is a review/planning phase only unless a later prompt explicitly authorizes narrow code changes. Do not set up another physical APNs/connect attempt yet.

Suggested scope:

```text
review_controlled_disconnect_cleanup_after_first_connect=true
review_callkit_end_cleanup_observability=true
review_media_disconnect_teardown_state=true
review_credentials_cleanup_persistence=true
review_no_repeated_connect_regression=true
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

Privacy scan changed docs/diff for raw sensitive values. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- 2.48W review result
- proof generation reviewed
- whether disconnect/end-call cleanup fields are sufficient or incomplete
- whether one-shot hook stayed consumed
- whether first attempt repeated=false
- whether credentials stayed non-reusable
- whether media connect was not repeated
- commit hash if docs or code were updated
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, video, microphone/camera permission, Matrix event emit, or full call flow was performed
