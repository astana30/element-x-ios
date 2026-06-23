# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Y-Physical2-SimulatorLivenessTriage` is complete.

Classification:

```text
2.48Y-Physical2 = simulator-assisted remote audio/liveness proof safely classified.
The first controlled audio connect succeeded again, LiveKit join succeeded, and cleanup completed.
Remote audio/liveness did not succeed because the remote simulator peer was not observed as a LiveKit remote participant.
The final runtime proof did not preserve the helper's simulator peer classification.
No retry performed.
```

One sandbox APNs was sent after explicit `SEND_2_48Y_PHYSICAL2` confirmation. Do not repeat APNs.

Helper preflight was ready before APNs:

```text
receiver_token_found=true
sender_token_found=true
sender_equals_receiver=false
room_validation_preflight=pass
pending_metadata_reference_present=true
physical6_runtime_enablement_url_hook_armed=true
second_device_remote_audio_readiness=ready_redacted
remote_peer_kind=ios_simulator_redacted
remote_peer_physical_device=false
simulator_assisted_remote_audio_proof=true
safe_to_send_apns=true
APNs_sent=false
```

APNs send result:

```text
invite_send_attempted=true
invite_http_code=200
real_non_dev_invite_used=true
dev_invite_used=false
background_apns_push_result=sandbox_success
APNs_sent=true
```

Reviewed proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48y-physical2-simulator-remote-liveness-polled.txt
```

Reviewed proof result:

```text
proof_generation=generation_12
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled

callkit_report_result=reported
callkit_report_completion_observed=true
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true

pending_metadata_fetch_requested=true
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx

media_credentials_requested=true
media_credentials_result=success_redacted

controlled_connect_first_attempt_requested=true
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
livekit_room_disconnected=true
livekit_local_participant_present=true

local_audio_publish_requested=false
local_audio_publish_started=false
local_audio_publish_result=not_required_redacted
local_audio_publish_error_bucket=none
local_audio_publish_not_required_reason=receive_only_audio_connect_redacted

microphone_permission_requested=false
microphone_permission_result=not_requested_or_not_required_redacted
microphone_permission_not_required_reason=receive_only_audio_session_redacted

remote_peer_kind=unknown_redacted
remote_peer_physical_device=unknown
simulator_assisted_remote_audio_proof=false
production_like_two_physical_device_proof=false

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

camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

## Next Phase

`2.48Y-RemotePeerContextHandoffRepair — carry simulator/remote peer readiness into runtime proof and classify remote participant absence, no APNs/connect`

This is a code/test repair phase. It is not a physical APNs task, not a media-connect task, not a LiveKit join task, not a repeated call task, and not a full call flow task.

## Goal

Repair or sharply classify the handoff gap between helper-side simulator readiness and the iPhone runtime proof.

The helper knew before APNs:

```text
remote_peer_kind=ios_simulator_redacted
remote_peer_physical_device=false
simulator_assisted_remote_audio_proof=true
second_device_remote_audio_readiness=ready_redacted
```

But the final runtime proof recorded:

```text
remote_peer_kind=unknown_redacted
remote_peer_physical_device=unknown
simulator_assisted_remote_audio_proof=false
production_like_two_physical_device_proof=false
```

The repair should determine whether the runtime proof can preserve remote peer context, whether the simulator actually joined the same LiveKit room as a remote participant, and whether receive-only local publish mode means simulator-assisted liveness must remain safely classified rather than successful.

## Hard Limits

Do not:

- send APNs
- run production APNs
- run repeated APNs
- run `dev/invite`
- retry media connect
- retry LiveKit join
- request microphone permission
- request camera permission
- enable video
- emit Matrix events
- start full direct-call flow
- reset or re-arm the one-shot hook
- perform another physical call attempt
- log/document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`

## Investigate Target Area

Inspect and minimally patch:

```text
NativeIncomingSyntheticCallKitUIProofAdapter.swift
SalemXPushKitRegistrationSmokeDebugBridge remote peer proof summary fields
2.48Y helper-side simulator readiness fields
remote peer context handoff into runtime proof
remote participant observer / liveness observer classification
LiveKitDirectCallMediaEngine connect/audio diagnostics
receive-only local publish classification
```

Questions to answer:

```text
how helper-side simulator readiness is passed or not passed into the iPhone runtime proof
why final proof records remote_peer_kind=unknown_redacted
why final proof records simulator_assisted_remote_audio_proof=false
whether simulator actually joined the same LiveKit room as a remote participant
whether the iPhone proof can observe remote participant lifecycle events
whether receive-only local publish mode prevents remote liveness by design
whether two-physical-device proof is required for real audio liveness
```

## Required Implementation

Add or repair redacted proof context so future physical proof can distinguish:

```text
remote_peer_context_handoff_repair_present=true
remote_peer_context_handoff_repair_debug_only=true
remote_peer_context_handoff_repair_raw_identifiers_logged=false
remote_peer_context_source=<helper_preflight_redacted_or_runtime_observer_redacted_or_unknown_redacted>
remote_peer_kind=<ios_simulator_redacted_or_physical_ios_redacted_or_unknown_redacted>
remote_peer_physical_device=<true_or_false_or_unknown>
simulator_assisted_remote_audio_proof=<true_or_false>
production_like_two_physical_device_proof=<true_or_false>
second_device_remote_audio_readiness=<ready_redacted_or_not_ready_redacted_or_unknown_redacted>
remote_audio_liveness_limitation=<simulator_assisted_redacted_or_remote_participant_missing_redacted_or_receive_only_redacted_or_none>
```

If the helper context cannot be trusted by the app runtime, classify explicitly:

```text
remote_peer_context_source=unknown_redacted
remote_peer_context_handoff_result=not_available_redacted
remote_audio_liveness_limitation=remote_peer_context_not_handed_off_redacted
```

If a simulator peer is intended but no remote participant is observed after LiveKit join, classify explicitly:

```text
remote_peer_kind=ios_simulator_redacted
simulator_assisted_remote_audio_proof=true
livekit_remote_participant_seen=false
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=remote_participant_missing_redacted
remote_audio_liveness_limitation=simulator_remote_participant_not_observed_redacted
```

Default runtime must remain no-connect.

## Required Tests

Add targeted Swift tests proving:

1. Remote peer context handoff fields exist and are redacted.
2. Default runtime remains no-connect.
3. Helper-side simulator peer context can be represented without raw IDs.
4. Simulator peer readiness can be classified as ready/not-ready/unknown.
5. Final proof does not default simulator-assisted proof to false when helper context says simulator.
6. Remote participant missing after LiveKit join maps to a redacted error bucket.
7. Remote audio track missing maps to a different redacted error bucket.
8. Receive-only local publish remains `not_required_redacted`.
9. Video remains disabled.
10. Camera permission remains false.
11. Matrix event emit remains false.
12. Full call flow remains false.
13. Raw identifiers are not logged.
14. No APNs/connect/LiveKit retry wiring is added.

## Required Docs

Update only if code/tests change:

- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- `docs/direct-call/NEXT_CODEX_PROMPT.md`

Set next phase to a readiness or physical proof only after the repair is complete. Do not set next phase to another APNs/connect attempt unless the repair proves the context handoff and remote participant readiness path.

## Required Checks Before Commit

Run:

```bash
swiftformat ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
swiftlint lint ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
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
- whether remote peer context handoff fields are present
- whether simulator-assisted peer context can be preserved in proof
- whether remote participant missing is classified
- whether receive-only local publish remains not-required
- whether default runtime remains no-connect
- commit hash
- commit message
- changed files
- checks run
- final `git status --short --branch`
- explicit statement that no APNs, no production APNs, no repeated APNs, no `dev/invite`, no repeated connect, no LiveKit join retry, no video, no camera permission, no Matrix event emit, and no full call flow were performed
