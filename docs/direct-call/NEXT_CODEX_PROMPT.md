# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48N implemented the first controlled audio-connect execution gate in the existing DEBUG proof surface. It is default-disabled and blocked before media execution. No physical connect was performed. Controlled connect, operator approval, and future physical-connect permission remain disabled by default, and the default remains no-connect.

Closed prerequisites:
- 2.47C physical controlled media credentials request succeeded with no media connect.
- 2.47D physical credentials cleanup / expiry proof succeeded.
- 2.47E server-side allocation/token expiry verification succeeded without LiveKit join.
- 2.48A documented the future media-connect seam.
- 2.48B implemented the controlled media-connect preflight guard.
- 2.48C proved the guard physically after real invite/APNs/PushKit/CallKit Answer.
- 2.48D reviewed the server/client readiness gates and concluded controlled connect was not yet approved.
- 2.48E added the disabled DEBUG-only switch/proof gates and kept execution blocked.
- 2.48F physically proved the disabled switch on-device after real non-dev invite/APNs/PushKit/CallKit Answer and controlled credentials success, with no media connect or LiveKit join.
- 2.48G documented the activation checklist, rollback plan, future first controlled-connect proof fields, and hard-stop fields without physical connect or code changes.
- 2.48H added the DEBUG-only activation configuration wrapper, default-disabled proof fields, rollback proof support, and targeted source-guard tests without physical connect.
- 2.48H-QA fixed stale source-guard expectations only and passed the broader selected DirectCall command across `DirectCallEngineTests` and `NativeIncomingCallLifecycleContractTests`.
- 2.48I-Retry physically closed the disabled activation proof on the one-shot retry with Answer, credentials, preflight guard, and no media connect.
- 2.48J documented the narrow enablement implementation plan.
- 2.48K implemented the DEBUG-only one-shot enablement proof mechanics and tests while preserving default no-connect.
- 2.48L-SessionRepair validated the iPhone app Matrix session before any retry; no APNs was sent.
- 2.48L-Retry2 physically closed the post-session-repair proof with credentials success and no media connect.
- 2.48M completed the first-run readiness gate and found no blocker for the next no-physical-connect implementation phase.
- 2.48N implemented the first controlled audio-connect execution gate, default disabled, no physical connect.

2.48N conclusion:

```text
2.48N = first controlled audio-connect execution path, default disabled, no physical connect
controlled connect not enabled by default
operator approval not enabled by default
future physical-connect permission remains false
execution allowed=false
default remains no-connect
```

2.48N default execution gate fields:

```text
controlled_audio_connect_execution_gate_present=true
controlled_audio_connect_execution_debug_only=true
controlled_audio_connect_execution_audio_only=true
controlled_audio_connect_execution_video_allowed=false
controlled_audio_connect_execution_matrix_events_allowed=false
controlled_audio_connect_execution_raw_credentials_logged=false
controlled_audio_connect_execution_requires_enablement=true
controlled_audio_connect_execution_requires_operator_approval=true
controlled_audio_connect_execution_requires_future_phase_permission=true
controlled_audio_connect_execution_future_phase_permitted=false
controlled_audio_connect_execution_allowed=false
controlled_audio_connect_execution_blocked_reason=future_phase_not_permitted_no_connect
controlled_audio_connect_execution_blocked_before_engine=true
controlled_audio_connect_execution_blocked_before_livekit_join=true
controlled_audio_connect_execution_blocked_before_permissions=true
controlled_audio_connect_execution_blocked_before_matrix_events=true
```

Carry forward the latest physical no-connect proof fields:

```text
pending_metadata_fetch_result=success_redacted
foreground_pending_call_metadata_handoff_observed=true
media_credentials_result=success_redacted
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_enabled=false
controlled_connect_enablement_operator_approved=false
controlled_connect_enablement_future_phase_permitted=false
controlled_connect_enablement_execution_allowed=false
controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
media_connect_preflight_requested=true
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

## Phase

`2.48O — physical proof of audio-connect execution gate default-blocked, no LiveKit join`

## Goal

Physically prove that the 2.48N controlled audio-connect execution gate appears in the on-device proof and remains default-blocked after the Answer path reaches credentials and media-connect preflight. This is not actual controlled connect.

## Required Behavior

- Use a one-shot physical proof only after local preflight passes and explicit operator confirmation is reached.
- Do not send repeated APNs.
- Do not send production APNs.
- Do not run `dev/invite`.
- Do not start media connect.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full direct-call flow.
- Do not enable controlled-connect switch by default.
- Do not enable operator approval by default.
- Do not enable future physical-connect permission by default.
- Do not add production-enabled connect behavior.
- Preserve 2.48L-Retry2 as the latest physical no-connect proof until the new 2.48O proof succeeds.

Required successful 2.48O proof fields:

```text
pending_metadata_fetch_result=success_redacted
foreground_pending_call_metadata_handoff_observed=true
media_credentials_result=success_redacted
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_enabled=false
controlled_connect_enablement_operator_approved=false
controlled_connect_enablement_future_phase_permitted=false
controlled_connect_enablement_execution_allowed=false
controlled_audio_connect_execution_gate_present=true
controlled_audio_connect_execution_debug_only=true
controlled_audio_connect_execution_audio_only=true
controlled_audio_connect_execution_video_allowed=false
controlled_audio_connect_execution_matrix_events_allowed=false
controlled_audio_connect_execution_raw_credentials_logged=false
controlled_audio_connect_execution_requires_enablement=true
controlled_audio_connect_execution_requires_operator_approval=true
controlled_audio_connect_execution_requires_future_phase_permission=true
controlled_audio_connect_execution_future_phase_permitted=false
controlled_audio_connect_execution_allowed=false
controlled_audio_connect_execution_blocked_reason=future_phase_not_permitted_no_connect
controlled_audio_connect_execution_blocked_before_engine=true
controlled_audio_connect_execution_blocked_before_livekit_join=true
controlled_audio_connect_execution_blocked_before_permissions=true
controlled_audio_connect_execution_blocked_before_matrix_events=true
media_connect_preflight_requested=true
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

Stop conditions:

```text
if APNs sent once, do not repeat automatically
if pending_metadata_fetch_result=blocked_redacted, stop and classify
if media_credentials_result=not_requested after Answer, stop and classify
if controlled_audio_connect_execution_gate_present is missing, verify installed commit before any retry
if controlled_audio_connect_execution_allowed=true, stop as safety regression
if media_connect_requested=true, stop as safety regression
if livekit_join_requested=true, stop as safety regression
```

## Required Checks

Run docs/checkpoint checks for the close-out, plus any targeted validation needed for the proof helper:

```bash
git diff --check
git diff --cached --check
```

Run forbidden project/signing scans:

```bash
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run a privacy scan over changed docs/diff for raw:

```text
token
JWT
Authorization
APNs payload
invite body
LiveKit URL
roomID
callID
peerUserID
userID
deviceID
```

Allowed safe hits are field names, redacted labels, negative statements, and existing stable receiver/sender hashes only.

## Hard Constraints

- Do not send production APNs.
- Do not send repeated APNs.
- Do not use `dev/invite`.
- Do not connect media.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full call flow.
- Do not enable controlled connect by default.
- Do not enable controlled-connect operator approval by default.
- Do not enable future physical-connect permission by default.
- Do not add production-enabled connect behavior.
- Do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, room names, key material, or secret-bearing URLs.
- Do not touch project/signing/entitlement/`Info.plist`/`app.yml` files.
- Do not stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.

## If Blocked

Report the blocker and the smallest next fix. Keep all no-connect safety fields false. Do not proceed to actual controlled connect.
