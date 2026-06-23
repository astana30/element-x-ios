# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48W — controlled disconnect/end-call cleanup review, no repeated connect` is complete and classified as incomplete.

This was a docs-only review of the existing Physical8 proof. No APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, new LiveKit join, video, microphone/camera permission, Matrix event emission, or full call flow was performed.

Latest 2.48V close-out commit:

```text
1961e09edca46a62377daf442de9cb1db7ad555e Close audio session lifecycle review
```

## Physical8 Proof Reviewed

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48t-physical8-first-audio-connect-polled.txt
```

Classification:

```text
2.48W result = controlled disconnect/end-call cleanup proof incomplete; targeted diagnostics needed
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

The already-closed Physical8 media and LiveKit activity stayed limited to one audio-only attempt:

```text
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
```

Controlled CallKit cleanup was requested and marked ended, but End action observability was incomplete:

```text
controlled_callkit_cleanup_requested=true
controlled_callkit_cleanup_result=ended
callkit_end_after_pushkit_completion_ms_bucket=unknown
callkit_end_action_delivered=false
end_action_uuid_matched=false
end_action_generation_matched=false
end_action_source_matched=false
end_action_fulfilled=false
end_action_origin=none
```

Audio-session deactivation remained valid:

```text
callkit_provider_did_deactivate_audio_session=true
callkit_audio_session_did_deactivate=true
audio_session_did_deactivate_before_first_action=false
```

Credentials stayed non-reusable:

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

Safety fields stayed closed:

```text
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
controlled_connect_first_attempt_video_allowed=false
```

## 2.48W Conclusion

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

Disconnect/end-call cleanup proof is incomplete because CallKit End action delivery/matching/fulfillment was not observed. Do not run another APNs helper or another connect attempt for this result.

## Next Phase

`2.48W-DisconnectCleanupDiagnostics — add/verify controlled disconnect cleanup proof, no APNs/connect`

This is a targeted diagnostics phase. It should improve or verify controlled disconnect/end-call cleanup observability without APNs, without a physical call, and without any media/LiveKit retry.

Suggested scope:

```text
diagnose_callkit_end_action_observability=true
verify_cleanup_result_maps_to_callkit_end_action=true
verify_end_action_uuid_generation_source_matching=true
verify_end_action_fulfillment_recorded=true
verify_audio_session_deactivation_after_cleanup=true
preserve_no_repeated_connect=true
```

Do not set the next phase to another APNs/connect attempt.

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

- diagnostics implementation/review summary
- whether CallKit End action observability is now sufficient
- whether audio-session deactivation remains valid
- whether one-shot hook stayed consumed
- whether credentials stayed non-reusable
- whether media connect was not repeated
- commit hash if docs or code were updated
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no APNs, production APNs, repeated APNs, `dev/invite`, repeated connect, video, microphone/camera permission, Matrix event emit, or full call flow was performed
