# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Y-RemotePeerContextHandoffRepair` is complete.

Conclusion:

```text
2.48Y-RemotePeerContextHandoffRepair = redacted simulator remote-peer context can be armed before APNs, copied into the runtime PushKit proof, survive Answer, and classify missing context as remote-audio non-success.
No APNs/connect was run for this repair.
```

Required future proof fields are now present:

```text
remote_peer_context_handoff_present=true
remote_peer_context_handoff_debug_only=true
remote_peer_context_handoff_source=debug_hook_redacted
remote_peer_context_handoff_armed_before_apns=true
remote_peer_context_handoff_received_by_runtime=true
remote_peer_context_handoff_survived_pushkit=true
remote_peer_context_handoff_survived_answer=true
remote_peer_context_handoff_raw_identifiers_logged=false

remote_peer_kind=ios_simulator_redacted
remote_peer_physical_device=false
simulator_assisted_remote_audio_proof=true
production_like_two_physical_device_proof=false
second_device_remote_audio_readiness=ready_redacted
remote_audio_liveness_limitation=simulator_assisted_redacted
```

Missing context is now explicit non-success:

```text
remote_peer_context_handoff_received_by_runtime=false
remote_peer_kind=unknown_redacted
simulator_assisted_remote_audio_proof=false
remote_audio_liveness_result=not_observed_redacted
remote_audio_liveness_error_bucket=remote_peer_context_missing_redacted
```

Safe defaults remain:

```text
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Next Phase

`2.48Y-Physical3 — one-shot simulator-assisted remote peer context/liveness proof`

This is a physical one-shot proof only after fresh preflight and explicit confirmation.

Do not send APNs until preflight passes and the operator confirms the phase-specific send token.

## Goal

Prove whether the redacted simulator remote-peer context reaches the iPhone runtime proof during the next one-shot physical attempt, and classify remote participant/audio liveness without treating simulator-assisted absence as production-like remote-audio success.

Required success/context fields to capture:

```text
remote_peer_context_handoff_present=true
remote_peer_context_handoff_debug_only=true
remote_peer_context_handoff_source=debug_hook_redacted
remote_peer_context_handoff_armed_before_apns=true
remote_peer_context_handoff_received_by_runtime=true
remote_peer_context_handoff_survived_pushkit=true
remote_peer_context_handoff_survived_answer=true
remote_peer_context_handoff_raw_identifiers_logged=false

remote_peer_kind=ios_simulator_redacted
remote_peer_physical_device=false
simulator_assisted_remote_audio_proof=true
production_like_two_physical_device_proof=false
second_device_remote_audio_readiness=ready_redacted
remote_audio_liveness_limitation=simulator_assisted_redacted

livekit_join_result=success_redacted
livekit_remote_participant_seen=<true_or_false>
livekit_remote_audio_track_subscribed=<true_or_false>
livekit_audio_liveness_result=<success_redacted_or_not_observed_redacted>
livekit_audio_liveness_error_bucket=<none_or_redacted_reason>
livekit_cleanup_result=completed_redacted
```

If no runtime context is present, stop and classify:

```text
remote_peer_context_handoff_received_by_runtime=false
remote_audio_liveness_result=not_observed_redacted
remote_audio_liveness_error_bucket=remote_peer_context_missing_redacted
```

If simulator context is present but no remote participant is observed, classify safely:

```text
remote_peer_context_handoff_received_by_runtime=true
simulator_assisted_remote_audio_proof=true
livekit_remote_participant_seen=false
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=remote_participant_missing_redacted
production_like_two_physical_device_proof=false
```

## Hard Limits

Do not:

- send APNs before explicit one-shot confirmation
- run production APNs
- run repeated APNs
- use `dev/invite`
- run more than one media connect attempt
- run more than one LiveKit join attempt
- request camera permission
- enable video
- emit Matrix events
- start full direct-call flow
- log/document raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
- modify `SalemX.xcodeproj/project.pbxproj`
- modify `app.yml`
- modify `.entitlements`
- modify `Info.plist`

## Required Preflight

Before any APNs send:

```text
receiver_token_found=true
sender_token_found=true
sender_equals_receiver=false
room_validation_preflight=pass
local_schema_valid=true
corrected_flat_schema_used=true
pending_metadata_reference_present=true
physical6_runtime_enablement_url_hook_armed=true
remote_peer_context_handoff_armed_before_apns=true
second_device_remote_audio_readiness=ready_redacted
safe_to_send_apns=true
APNs_sent=false
```

## Required Checks Before Close

Run:

```bash
git diff --check
git diff --cached --check
```

Run forbidden project/signing scans:

```bash
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Privacy scan changed docs/diff for raw sensitive values.

Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

- whether simulator remote peer context reached runtime proof
- whether missing context was avoided or classified
- whether remote participant was observed
- whether remote audio track was observed
- whether simulator limitation remained classified
- whether production-like two-physical-device proof remained false
- whether default safety stayed closed for camera/video/Matrix/full-flow
- checks run
- final `git status --short --branch`
