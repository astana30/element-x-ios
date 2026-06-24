# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry2` is closed as:

```text
safe sender-not-joined / remote participant not observed triage, not remote-audio success
```

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry2-sender-readiness-remote-participant-polled.txt
```

Proof generation:

```text
proof_generation=generation_18
```

Receiver-side result:

```text
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_report_result=reported
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
foreground_pending_call_metadata_handoff_observed=true
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
media_credentials_requested=true
media_credentials_result=success_redacted
controlled_connect_real_bridge_present=true
controlled_connect_real_bridge_allowed=true
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
```

Sender readiness result:

```text
sender_livekit_readiness_hook_present=true
sender_livekit_readiness_hook_armed=true
sender_livekit_readiness_hook_matrix_session_ready=true
sender_livekit_readiness_hook_same_room_ready=true
sender_livekit_readiness_hook_credentials_ready=true
sender_readiness_runtime_handoff_present=true
sender_readiness_runtime_handoff_armed_before_apns=true
sender_readiness_runtime_handoff_received_by_runtime=true
sender_readiness_runtime_handoff_survived_pushkit=true
sender_readiness_runtime_handoff_survived_answer=true
sender_readiness_runtime_handoff_matrix_session_ready=true
sender_readiness_runtime_handoff_same_room_ready=true
sender_readiness_runtime_handoff_expected_user_matched=true
sender_readiness_runtime_handoff_raw_identifiers_logged=false
sender_readiness_runtime_handoff_missing_classified=false
```

Sender-side join hook result:

```text
sender_side_livekit_join_hook_present=true
sender_side_livekit_join_hook_armed=false
sender_side_livekit_join_requested=false
sender_side_livekit_join_result=not_requested
sender_side_livekit_join_error_bucket=none
sender_side_livekit_join_repeated=false
```

Receiver observer/liveness result:

```text
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_error_bucket=sender_not_joined_redacted
livekit_remote_participant_seen=false
livekit_remote_participant_count_bucket=0
livekit_remote_audio_track_subscribed=false
livekit_remote_audio_track_unmuted=false
livekit_audio_liveness_observed=false
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=remote_participant_missing_redacted
```

Safety:

```text
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

APNs audit:

```text
APNs_sent=true
background_apns_push_result=sandbox_success
possible_repeated_apns_observed=true
repeated_apns_observed=unknown
```

The local phase marker proves at least one sandbox APNs success. The terminal transcript reported an `APNs_sent=true` block before a restored session and then another `SEND_2_48Z_PHYSICAL2_RETRY2` helper confirmation. The retained local marker cannot distinguish whether those were the same helper session or two separate sends, so the close-out records possible repeated APNs explicitly. Do not send APNs again for this phase.

Key conclusion:

```text
Receiver-side controlled connect succeeded again.
Receiver LiveKit join was invoked.
Remote participant was not observed.
The receiver observer classified the result as sender_not_joined_redacted.
The sender LiveKit readiness hook was armed, but the sender-side LiveKit join hook was not armed/requested.
No remote audio/liveness success.
No video.
No camera permission.
No Matrix event emit.
No full call flow.
```

## Next Phase

`2.48Z-SenderJoinHookActivationRepair — make sender-side LiveKit join hook explicitly arm/trigger once, no APNs/connect`

This is a repair phase only. Do not set the next phase to another physical APNs/connect attempt.

## Investigation Targets

Investigate and repair:

```text
why sender_side_livekit_join_hook_armed=false despite sender readiness hook armed=true
why sender_side_livekit_join_requested=false
whether a separate DEBUG sender join hook must be activated after receiver Answer
whether sender-side join requires its own metadata/credentials/token allocation
whether sender-side LiveKit join is currently only classified, not executable
whether receiver observer is correctly waiting long enough for sender join result
```

Expected repair outcome:

```text
sender-side LiveKit join hook can be explicitly armed/triggered once under DEBUG/test control
default runtime remains no-connect/no-join
no video
no camera permission
no Matrix event emit
no full call flow
raw tokens/JWTs/auth headers/APNs payloads/invite bodies/LiveKit URLs/room IDs/call IDs/peer user IDs/user IDs/device IDs are not logged
```

## Hard Limits

Do not:

* send APNs
* run production APNs
* run repeated APNs
* run `dev/invite`
* retry receiver connect
* retry sender LiveKit join on device
* request microphone/camera permission
* enable video
* emit Matrix events
* start full call flow
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Suggested Checks

Run focused format/lint/tests appropriate to the files changed. If Swift proof code or DirectCall tests change, run:

```bash
swiftformat ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
swiftlint lint ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
```

Also run:

```bash
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run privacy scans over changed files/diff. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

* implementation summary
* whether sender-side join hook can now be explicitly armed once
* whether sender-side join remains default-disabled before the hook
* whether no APNs/connect/LiveKit/device permissions/full flow were performed
* checks run
* commit hash/message
* changed files
* final `git status --short --branch`
