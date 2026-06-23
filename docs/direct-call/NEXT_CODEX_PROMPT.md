# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48U — first-connect result review and cleanup verification, no repeated connect` is complete.

This was a docs-only review of the existing Physical8 proof. No APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, new LiveKit join, video, camera permission, Matrix event emission, or full call flow was performed.

Latest Physical8 close commit before 2.48U:

```text
ac1b94e91 Close Physical8 first audio connect proof
```

## Physical8 Proof Reviewed

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48t-physical8-first-audio-connect-polled.txt
```

First controlled audio-connect result:

```text
proof_generation=generation_14
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_error_bucket=none
controlled_connect_first_attempt_repeated=false
physical6_runtime_enablement_url_hook_consumed=true
```

Credentials cleanup and non-reuse:

```text
media_credentials_cleanup_requested=true
media_credentials_cleanup_result=cleared
media_credentials_post_cleanup_token_present=false
media_credentials_post_cleanup_url_present=false
media_credentials_post_cleanup_expires_at_present=false
media_credentials_post_cleanup_payload_present=false
media_credentials_reuse_attempted=false
media_credentials_reuse_allowed=false
media_credentials_expiry_check_requested=true
media_credentials_expiry_check_result=expired_or_not_reusable_redacted
```

The already-closed Physical8 media/LiveKit activity stayed limited to one audio-only attempt:

```text
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
controlled_connect_first_attempt_audio_only=true
controlled_connect_first_attempt_video_allowed=false
```

Safety fields stayed closed:

```text
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
controlled_connect_first_attempt_matrix_events_allowed=false
controlled_connect_first_attempt_raw_credentials_logged=false
blocked_reason=none
```

## 2.48U Conclusion

```text
2.48U = first-connect result review and cleanup verification completed
Physical8 first controlled audio-connect succeeded
one-shot hook consumed
first attempt repeated=false
credentials not reusable
no repeated APNs
no repeated connect
no video
no camera permission
no Matrix event emit
no full call flow
```

Cleanup / one-shot verification is sufficient. Do not run another APNs helper or another connect attempt for this result.

## Next Phase

`2.48V — controlled audio session lifecycle review, no repeated connect`

This is a review/planning phase only unless a later prompt explicitly authorizes narrow code changes. Do not set up another physical APNs/connect attempt yet.

Suggested scope:

```text
review_audio_session_lifecycle_after_first_connect=true
review_connect_success_teardown_observability=true
review_one_shot_hook_consumption_persistence=true
review_credentials_cleanup_lifecycle=true
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
- reset the one-shot hook to perform another connect
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

- Physical8 result review
- cleanup / one-shot verification status
- whether the hook was consumed
- whether first attempt repeated=false
- whether credentials are non-reusable
- next phase
- commit hash if docs or code were updated
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, video, camera permission, Matrix event emit, or full call flow was performed
