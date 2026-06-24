# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderJoinTriggerOrchestrationRepair` is complete.

The proof now has a DEBUG-only redacted sender join trigger orchestration guard that prevents early terminal polling before the sender trigger and sender SDK timeline reach terminal classification.

New proof fields:

```text
sender_join_trigger_orchestration_present=true
sender_join_trigger_orchestration_debug_only=true
sender_join_trigger_orchestration_raw_identifiers_logged=false
sender_join_trigger_orchestration_apns_success_seen=<redacted_bool>
sender_join_trigger_orchestration_receiver_answer_seen=<redacted_bool>
sender_join_trigger_orchestration_receiver_connect_terminal_seen=<redacted_bool>
sender_join_trigger_orchestration_sender_activation_armed=<redacted_bool>
sender_join_trigger_orchestration_sender_trigger_required=true
sender_join_trigger_orchestration_sender_trigger_allowed=<redacted_bool>
sender_join_trigger_orchestration_sender_trigger_started=<redacted_bool>
sender_join_trigger_orchestration_sender_trigger_completed=<redacted_bool>
sender_join_trigger_orchestration_sender_trigger_missing_classified=<redacted_bool>
sender_join_trigger_orchestration_poll_allowed=<redacted_bool>
sender_join_trigger_orchestration_poll_blocked_reason=<redacted_bucket>
sender_join_trigger_orchestration_final_classification=<redacted_bucket>
```

Safe defaults:

```text
sender_join_trigger_orchestration_present=true
sender_join_trigger_orchestration_debug_only=true
sender_join_trigger_orchestration_raw_identifiers_logged=false
sender_join_trigger_orchestration_sender_trigger_required=true
sender_join_trigger_orchestration_sender_trigger_allowed=false
sender_join_trigger_orchestration_poll_allowed=false
```

Redacted classifications:

```text
sender_trigger_waiting_for_answer_redacted
sender_trigger_waiting_for_receiver_connect_redacted
sender_trigger_activation_not_armed_redacted
sender_trigger_required_but_not_started_redacted
sender_trigger_started_not_completed_redacted
sender_trigger_completed_waiting_for_sdk_timeline_redacted
sender_trigger_completed_sdk_timeline_terminal_redacted
sender_trigger_poll_blocked_until_sender_terminal_redacted
```

Boundary results:

```text
early_proof_polling_blocked_until_sender_trigger_terminal=true
receiver_terminal_fields_alone_can_close_phase=false
not_requested_classified_as_missing_sender_trigger_when_required=true
sender_sdk_timeline_terminal_required_before_final_poll=true
default_runtime_no_connect=true
default_runtime_no_join=true
```

No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, video, microphone/camera permission, Matrix event emit, full call flow, or physical hook reset/re-arm was performed.

## Next Phase

`2.48Z-Physical2-Retry9 — one-shot two-physical-device sender SDK timeline proof with trigger-orchestration guard`

Retry9 target:

```text
sender_join_trigger_orchestration_apns_success_seen=true
sender_join_trigger_orchestration_receiver_answer_seen=true
sender_join_trigger_orchestration_receiver_connect_terminal_seen=true
sender_join_trigger_orchestration_sender_activation_armed=true
sender_join_trigger_orchestration_sender_trigger_required=true
sender_join_trigger_orchestration_sender_trigger_allowed=true
sender_join_trigger_orchestration_sender_trigger_started=true
sender_join_trigger_orchestration_sender_trigger_completed=true
sender_join_trigger_orchestration_poll_allowed=true only after sender SDK timeline terminal classification
sender_join_trigger_orchestration_final_classification=sender_trigger_completed_sdk_timeline_terminal_redacted
```

Stop/classify if:

```text
sender_join_trigger_orchestration_final_classification=sender_trigger_waiting_for_answer_redacted
sender_join_trigger_orchestration_final_classification=sender_trigger_waiting_for_receiver_connect_redacted
sender_join_trigger_orchestration_final_classification=sender_trigger_activation_not_armed_redacted
sender_join_trigger_orchestration_final_classification=sender_trigger_required_but_not_started_redacted
sender_join_trigger_orchestration_final_classification=sender_trigger_started_not_completed_redacted
sender_join_trigger_orchestration_final_classification=sender_trigger_completed_waiting_for_sdk_timeline_redacted
sender_join_trigger_orchestration_poll_allowed=false
sender_join_trigger_orchestration_poll_blocked_reason=sender_trigger_poll_blocked_until_sender_terminal_redacted
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

* send APNs unless the explicit one-shot Retry9 helper confirmation is reached
* run production APNs
* run repeated APNs
* run `dev/invite`
* start repeated physical media connect
* start repeated real LiveKit join
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
* whether trigger orchestration guard allows final poll only after sender terminal classification
* whether receiver terminal fields alone did not close the sender path
* whether default runtime remains no-connect/no-join
* commit hash/message
* changed files
* checks run
* final `git status --short --branch`
