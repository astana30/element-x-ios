# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48K implemented explicit one-shot controlled-connect enablement mechanics with the default still off. Physical connect was not performed, controlled connect was not enabled by default, operator approval was not enabled by default, future physical-connect permission remains false, and the default remains no-connect.

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

2.48K conclusion:

```text
2.48K = explicit one-shot controlled-connect enablement, default off
physical connect not performed
controlled connect not enabled by default
operator approval not enabled by default
future physical-connect permission remains false
default remains no-connect
```

New default proof fields:

```text
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_debug_only=true
controlled_connect_enablement_default_off=true
controlled_connect_enablement_operator_approval_required=true
controlled_connect_enablement_one_shot=true
controlled_connect_enablement_fresh_credentials_required=true
controlled_connect_enablement_audio_only=true
controlled_connect_enablement_video_allowed=false
controlled_connect_enablement_matrix_events_allowed=false
controlled_connect_enablement_raw_credentials_logged=false
controlled_connect_enablement_rollback_available=true
controlled_connect_enablement_enabled=false
controlled_connect_enablement_operator_approved=false
controlled_connect_enablement_future_phase_permitted=false
controlled_connect_enablement_execution_allowed=false
controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
```

Hard safety fields must remain false:

```text
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Phase

`2.48L — physical proof of enablement default-off, no LiveKit join`

## Goal

Plan and run only the next supervised physical proof that the 2.48K enablement wiring is present on-device and still default-off. This is not actual controlled connect. The proof must stop before media engine invocation, LiveKit join, microphone/camera permission, Matrix event emission, and full direct-call flow.

## Required Behavior

- Use the existing one-shot physical proof discipline from the 2.48I-Retry success.
- Prove the new 2.48K enablement fields are present on-device.
- Prove enablement remains off by default.
- Prove operator approval remains false by default.
- Prove future physical-connect permission remains false.
- Prove execution remains false and blocked with `enablement_disabled_no_connect`.
- Prove the existing media-connect preflight still stops before engine invocation.
- Do not perform actual controlled connect.
- Do not enable controlled connect by default.
- Do not enable operator approval by default.
- Do not add production-enabled connect behavior.

Required success fields:

```text
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_debug_only=true
controlled_connect_enablement_default_off=true
controlled_connect_enablement_operator_approval_required=true
controlled_connect_enablement_one_shot=true
controlled_connect_enablement_fresh_credentials_required=true
controlled_connect_enablement_audio_only=true
controlled_connect_enablement_video_allowed=false
controlled_connect_enablement_matrix_events_allowed=false
controlled_connect_enablement_raw_credentials_logged=false
controlled_connect_enablement_rollback_available=true
controlled_connect_enablement_enabled=false
controlled_connect_enablement_operator_approved=false
controlled_connect_enablement_future_phase_permitted=false
controlled_connect_enablement_execution_allowed=false
controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
media_connect_engine_invoked=false
livekit_connect_audio_invoked=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Required Tests Before Any Physical Proof

Run the targeted DirectCall checks from the latest 2.48K commit before installing/running any app proof:

```bash
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
git diff --check
git diff --cached --check
```

Run forbidden project/signing scans:

```bash
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run a privacy scan over changed files/diff for raw:

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

Allowed safe hits are field names, redacted labels, negative statements, and synthetic test values only.

## Hard Constraints

- Do not send APNs unless a future 2.48L prompt provides local-only inputs, preflight passes, and an explicit one-shot confirmation is reached.
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
- Do not add production-enabled connect behavior.
- Do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, room names, key material, or secret-bearing URLs.
- Do not touch project/signing/entitlement/`Info.plist`/`app.yml` files.
- Do not stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.

## If Blocked

Report the blocker and the smallest next fix. Keep all no-connect safety fields false. Do not proceed to actual controlled connect.
