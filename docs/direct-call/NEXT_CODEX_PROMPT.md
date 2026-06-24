# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry8` is complete and closed as safe sender-join-not-requested / remote participant not observed triage, not remote-audio success.

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry8-sender-sdk-timeline-polled.txt
```

Proof generation:

```text
proof_generation=generation_17
```

Receiver path succeeded once:

```text
physical_voip_push_received=true
callkit_report_result=reported
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
pending_metadata_fetch_result=success_redacted
media_credentials_result=success_redacted
controlled_connect_first_attempt_result=success_redacted
controlled_connect_first_attempt_repeated=false
livekit_join_result=success_redacted
```

Sender-side join and SDK timeline stayed not requested:

```text
sender_side_livekit_join_activation_triggered=false
sender_side_livekit_join_activation_consumed=false
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_requested=false
sender_side_livekit_join_result=not_requested
sender_side_livekit_join_error_bucket=none
sender_side_livekit_join_repeated=false
sender_livekit_sdk_failure_surface_present=true
sender_livekit_sdk_failure_surface_final_classification=not_requested
sender_livekit_sdk_timeline_present=true
sender_livekit_sdk_timeline_final_classification=not_requested
```

Remote participant/audio/liveness was not observed:

```text
receiver_remote_participant_observer_present=true
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_remote_seen=false
receiver_remote_participant_observer_audio_track_seen=false
receiver_remote_participant_observer_liveness_seen=false
livekit_remote_participant_seen=false
livekit_remote_audio_track_subscribed=false
livekit_audio_liveness_result=not_observed_redacted
```

Safety remained closed:

```text
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
no_repeated_apns=true
no_production_apns=true
dev_invite_used=false
no_repeated_connect=true
no_repeated_livekit_join=true
video_enabled=false
```

Conclusion:

```text
Retry8 proved the receiver controlled audio path can complete once after APNs/Answer, but the sender-side LiveKit join safe point was not triggered before terminal observer classification. Because terminal fields were already present, no sender hook retry or repeated connect was performed.
```

## Next Phase

`2.48Z-SenderJoinSafePointRepair — trigger sender-side LiveKit join after receiver Answer/credentials without repeated connect`

Repair target:

```text
sender-side LiveKit join should be triggered only after receiver Answer, pending metadata success, media credentials success, and controlled receiver connect eligibility are established
sender-side join must remain one-shot
sender-side join must not be triggered before APNs
sender-side join must not be retried after any result/classification
receiver remote participant/liveness observer should run after sender join classification is available
```

Required repaired proof fields should make a future one-shot distinguish:

```text
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=<success_redacted_or_failed_redacted_or_blocked_redacted>
sender_livekit_sdk_timeline_final_classification=<redacted_timeline_bucket_or_success_redacted>
receiver_remote_participant_observer_result=<success_redacted_or_not_observed_redacted>
```

Keep existing safety:

```text
default_runtime_no_connect=true
default_runtime_no_join=true
no_repeated_apns=true
no_repeated_connect=true
no_repeated_livekit_join=true
video_enabled=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
raw_error_url_token_room_identity_logged=false
```

## Hard Limits

Do not:

* send APNs
* run production APNs
* run repeated APNs
* run `dev/invite`
* start physical media connect
* start real LiveKit join
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Suggested Checks

Run:

```bash
git status --short --branch
git diff --check
git diff --cached --check
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
swiftformat ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
swiftlint lint ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Allowed SwiftLint warning: existing file-length warning only.

Run privacy scans over changed files/diff. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

* implementation summary
* whether sender join safe point is after Answer/metadata/credentials
* whether sender join remains one-shot
* whether observer waits for sender join classification
* whether default runtime remains no-connect/no-join
* commit hash/message
* changed files
* checks run
* final `git status --short --branch`
