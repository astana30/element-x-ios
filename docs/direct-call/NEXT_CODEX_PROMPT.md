# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderReadinessRuntimeHandoffRepair` is complete.

This was a code/test diagnostics repair only. No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, video, microphone/camera permission, Matrix event emission, or full call flow was performed.

The repair adds runtime proof fields for sender readiness handoff:

```text
sender_readiness_runtime_handoff_present=true
sender_readiness_runtime_handoff_debug_only=true
sender_readiness_runtime_handoff_armed_before_apns=<redacted_bool>
sender_readiness_runtime_handoff_received_by_runtime=<redacted_bool>
sender_readiness_runtime_handoff_survived_pushkit=<redacted_bool>
sender_readiness_runtime_handoff_survived_answer=<redacted_bool>
sender_readiness_runtime_handoff_matrix_session_ready=<redacted_bool>
sender_readiness_runtime_handoff_same_room_ready=<redacted_bool>
sender_readiness_runtime_handoff_expected_user_matched=<redacted_bool>
sender_readiness_runtime_handoff_raw_identifiers_logged=false
sender_readiness_runtime_handoff_missing_classified=<redacted_bool>
```

Expected future safe values after pre-APNs sender readiness is armed, PushKit is received, and Answer is handled:

```text
sender_readiness_runtime_handoff_armed_before_apns=true
sender_readiness_runtime_handoff_received_by_runtime=true
sender_readiness_runtime_handoff_survived_pushkit=true
sender_readiness_runtime_handoff_survived_answer=true
sender_readiness_runtime_handoff_matrix_session_ready=true
sender_readiness_runtime_handoff_same_room_ready=true
sender_readiness_runtime_handoff_expected_user_matched=true
sender_readiness_runtime_handoff_raw_identifiers_logged=false

sender_livekit_readiness_hook_armed=true
sender_livekit_readiness_hook_matrix_session_ready=true
sender_livekit_readiness_hook_expected_user_matched=true
sender_livekit_readiness_hook_same_room_ready=true
second_physical_sender_livekit_readiness_matrix_session_ready=true
second_physical_sender_livekit_readiness_same_room_ready=true
```

Missing sender readiness is now explicit and not a remote-audio success:

```text
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_error_bucket=sender_readiness_context_missing_redacted
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=sender_readiness_context_missing_redacted
```

Sender-side LiveKit join classification exists and is default-disabled:

```text
sender_side_livekit_join_hook_present=true
sender_side_livekit_join_hook_debug_only=true
sender_side_livekit_join_hook_default_disabled=true
sender_side_livekit_join_hook_armed=false
sender_side_livekit_join_hook_audio_only=true
sender_side_livekit_join_hook_video_allowed=false
sender_side_livekit_join_hook_matrix_events_allowed=false
sender_side_livekit_join_hook_raw_credentials_logged=false
sender_side_livekit_join_requested=false
sender_side_livekit_join_result=not_requested
sender_side_livekit_join_error_bucket=none
sender_side_livekit_join_repeated=false
```

Receiver observer classification now distinguishes:

```text
sender_readiness_context_missing_redacted
sender_not_joined_redacted
remote_participant_missing_redacted
remote_audio_track_missing_redacted
remote_liveness_not_observed_redacted
```

Checks passed:

```bash
swiftformat ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
swiftlint lint ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
```

SwiftLint reported only the existing `file_length` warning for `NativeIncomingSyntheticCallKitUIProofAdapter.swift`. DirectCall subset passed with 151 tests.

## Next Phase

`2.48Z-Physical2-Retry2 — one-shot two-physical-device sender readiness handoff / remote participant proof`

This is the next physical proof. It is not a planning-only phase.

## Hard Limits

Do not:

* send APNs before all preflight gates pass and explicit one-shot confirmation is reached
* send production APNs
* send repeated APNs
* use `dev/invite`
* run more than one receiver controlled connect
* run more than one receiver LiveKit join
* run more than one sender-side join trigger
* enable video
* request camera permission
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/roomID/callID/peerUserID/userID/deviceID
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Required Preflight

Use local/in-memory inputs only. Do not print raw token values.

Validate:

```text
receiver_token_found=true
sender_token_found=true
receiver_user_hash=497015f5745c933a
sender_user_hash=7d434d7f252427fb
sender_equals_receiver=false
sender_room_membership=join
receiver_room_membership=join
room_encryption_algorithm_present=true
room_validation_preflight=pass
corrected_flat_schema_used=true
nested_invite_body_used=false
second_physical_sender_app_session_ready=true
second_physical_sender_same_room_ready=true
sender_readiness_runtime_handoff_armed_before_apns=true
sender_side_livekit_join_hook_default_disabled=true
safe_to_send_apns=true
APNs_sent=false
```

## One-Shot Physical Proof

Only after preflight passes and explicit confirmation is reached:

1. Send exactly one sandbox APNs with the corrected flat schema and non-dev invite.
2. Stop sending APNs after `background_apns_push_result=sandbox_success`.
3. Operator presses green Answer once on the receiver.
4. Allow exactly one receiver audio-only controlled connect / LiveKit join attempt.
5. Allow the sender-side join trigger classification to run at most once, without video and without Matrix events.
6. Poll the phase-specific proof.

## Required Future Proof Fields

The proof should show sender readiness survived into runtime and Answer:

```text
sender_readiness_runtime_handoff_armed_before_apns=true
sender_readiness_runtime_handoff_received_by_runtime=true
sender_readiness_runtime_handoff_survived_pushkit=true
sender_readiness_runtime_handoff_survived_answer=true
sender_readiness_runtime_handoff_matrix_session_ready=true
sender_readiness_runtime_handoff_same_room_ready=true
sender_readiness_runtime_handoff_expected_user_matched=true
sender_readiness_runtime_handoff_raw_identifiers_logged=false
sender_readiness_runtime_handoff_missing_classified=false

sender_livekit_readiness_hook_armed=true
sender_livekit_readiness_hook_matrix_session_ready=true
sender_livekit_readiness_hook_expected_user_matched=true
sender_livekit_readiness_hook_same_room_ready=true
second_physical_sender_livekit_readiness_matrix_session_ready=true
second_physical_sender_livekit_readiness_same_room_ready=true
```

The sender-side join classification should identify whether the sender actually joined:

```text
sender_side_livekit_join_hook_present=true
sender_side_livekit_join_hook_debug_only=true
sender_side_livekit_join_hook_audio_only=true
sender_side_livekit_join_hook_video_allowed=false
sender_side_livekit_join_hook_matrix_events_allowed=false
sender_side_livekit_join_hook_raw_credentials_logged=false
sender_side_livekit_join_requested=<redacted_bool>
sender_side_livekit_join_result=<success_redacted_or_blocked_redacted_or_failed_redacted_or_not_requested>
sender_side_livekit_join_error_bucket=<none_or_redacted_bucket>
sender_side_livekit_join_repeated=false
```

Receiver observer/liveness classification must remain explicit:

```text
receiver_remote_participant_observer_result=<success_redacted_or_not_observed_redacted>
receiver_remote_participant_observer_error_bucket=<none_or_sender_not_joined_redacted_or_remote_participant_missing_redacted_or_remote_audio_track_missing_redacted_or_remote_liveness_not_observed_redacted>
livekit_remote_participant_seen=<redacted_bool>
livekit_remote_audio_track_subscribed=<redacted_bool>
livekit_audio_liveness_result=<success_redacted_or_not_observed_redacted>
```

Safety must remain:

```text
controlled_connect_first_attempt_repeated=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Stop Conditions

Stop and classify instead of retrying if:

```text
APNs_sent=true
background_apns_push_result=sandbox_success
```

Stop if any of these are observed:

```text
sender_readiness_runtime_handoff_received_by_runtime=false
sender_readiness_runtime_handoff_missing_classified=true
sender_side_livekit_join_repeated=true
controlled_connect_first_attempt_repeated=true
camera_permission_requested=true
matrix_event_emit_requested=true
real_call_flow_started=true
```

Expected next output after the physical attempt:

* proof generation
* whether sender readiness reached runtime and survived Answer
* whether sender matrix/same-room readiness remained true in final proof
* sender-side join result classification
* receiver remote participant/audio/liveness classification
* safety fields
* final recommendation: close as remote-audio success, sender-not-joined triage, remote-missing triage, or repair before retry
