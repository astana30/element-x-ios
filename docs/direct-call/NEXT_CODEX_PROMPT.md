# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48J completed the controlled-connect enablement implementation plan as a docs-only phase. Physical connect was not performed, controlled connect was not enabled, and the default remains no-connect.

Closed prerequisites:
- 2.47C physical controlled media credentials request succeeded with no media connect.
- 2.47D physical credentials cleanup / expiry proof succeeded.
- 2.47E server-side allocation/token expiry verification succeeded without LiveKit join.
- 2.48A documented the future media-connect seam.
- 2.48B implemented the controlled media-connect preflight guard.
- 2.48C proved the guard physically after real invite/APNs/PushKit/CallKit Answer.
- 2.48D reviewed the server/client readiness gates and concluded controlled connect is not yet approved.
- 2.48E added the disabled DEBUG-only switch/proof gates and kept execution blocked.
- 2.48F physically proved the disabled switch on-device after real non-dev invite/APNs/PushKit/CallKit Answer and controlled credentials success, with no media connect or LiveKit join.
- 2.48G documented the activation checklist, rollback plan, future first controlled-connect proof fields, and hard-stop fields without physical connect or code changes.
- 2.48H added the DEBUG-only activation configuration wrapper, default-disabled proof fields, rollback proof support, and targeted source-guard tests without physical connect.
- 2.48H-QA fixed stale source-guard expectations only and passed the broader selected DirectCall command across `DirectCallEngineTests` and `NativeIncomingCallLifecycleContractTests`.
- 2.48I-Retry physically closed the disabled activation proof on the one-shot retry with Answer, credentials, preflight guard, and no media connect.
- 2.48J documented the narrow enablement implementation plan for the next code phase.

2.48J conclusion:

```text
2.48J = controlled-connect enablement implementation plan
physical connect not performed
controlled connect not yet enabled
default remains no-connect
```

Investigation conclusion:
- `DirectCallEngine.requestMediaCredentials` remains the credentials-only boundary and must not connect media.
- `DirectCallEngine.connectMediaIfReady` remains the private media boundary and must stay unreached by the 2.48K enablement proof path.
- `LiveKitDirectCallMediaEngine.connectAudio` remains the first real media-connect boundary and must stay uninvoked in 2.48K.
- `NativeIncomingSyntheticCallKitUIProofAdapter.swift` already owns the DEBUG-only proof surface for the controlled switch, activation configuration, media-connect preflight guard, and rollback proof support.
- `DirectCallEngineTests.swift` already contains source guards for the disabled switch/activation proof and should be extended for enablement fields and rollback expectations.

## Phase

`2.48K — implement explicit one-shot controlled-connect enablement, default off, no physical connect`

## Goal

Implement explicit controlled-connect enablement mechanics without enabling controlled connect by default and without performing a physical connect. The result should make the future one-shot enablement state observable in DEBUG proof output while preserving the no-connect default.

## Required Behavior

- Add the narrowest DEBUG-only enablement configuration/proof layer around the existing controlled-connect switch and activation proof surface.
- Keep enablement default off and operator approval false by default.
- Require fresh credentials and audio-only scope before execution can ever be considered.
- Keep video disabled.
- Keep Matrix event emission disabled.
- Keep raw credential logging disabled.
- Keep rollback available and prove it restores the no-connect default.
- Keep `DirectCallEngine.requestMediaCredentials` as a credentials-only boundary.
- Do not call or wire `DirectCallEngine.connectMediaIfReady` from the proof adapter.
- Do not call or wire `LiveKitDirectCallMediaEngine.connectAudio` from the proof adapter.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start the full direct-call flow.

2.48K required enablement defaults:

```text
enablement_debug_only=true
enablement_default_enabled=false
enablement_operator_approval_default=false
enablement_requires_fresh_credentials=true
enablement_requires_audio_only_scope=true
enablement_video_disabled=true
enablement_matrix_events_disabled=true
enablement_raw_credentials_logged=false
enablement_rollback_available=true
enablement_tests_required_before_physical=true
```

2.48K must add or prove these future proof fields:

```text
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_debug_only=true
controlled_connect_enablement_default_off=true
controlled_connect_enablement_operator_approval_required=true
controlled_connect_enablement_audio_only=true
controlled_connect_enablement_video_allowed=false
controlled_connect_enablement_matrix_events_allowed=false
controlled_connect_enablement_raw_credentials_logged=false
controlled_connect_enablement_rollback_available=true
controlled_connect_enablement_execution_allowed=false
```

2.48K stop/safety fields must remain false:

```text
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Rollback expectations:

```text
rollback_disables_enablement=true
rollback_clears_operator_approval=true
rollback_restores_execution_allowed_false=true
rollback_preserves_no_connect=true
```

## Expected Code Scope

Likely files:
- `ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift`
- `UnitTests/Sources/DirectCallEngineTests.swift`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- `docs/direct-call/NEXT_CODEX_PROMPT.md`

Avoid touching:
- `SalemX.xcodeproj/project.pbxproj`
- `app.yml`
- `.entitlements`
- `Info.plist`

Do not stage:
- `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Required Tests

Before committing 2.48K, run:

```bash
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
git diff --check
git diff --cached --check
```

Also run forbidden project/signing scans:

```bash
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run a privacy scan over changed Swift/docs/diff for raw:

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

Allowed safe hits are field names, redacted labels, negative statements, and existing stable receiver/sender hashes.

## Hard Constraints

- Do not send APNs.
- Do not use `dev/invite`.
- Do not send production APNs.
- Do not send repeated APNs.
- Do not connect media.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full call flow.
- Do not enable the controlled-connect switch by default.
- Do not enable controlled-connect operator approval by default.
- Do not add production-enabled connect behavior.
- Do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, room names, key material, or secret-bearing URLs.
- Do not touch project/signing/entitlement/`Info.plist`/`app.yml` files.
- Do not stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.

## If Blocked

Report the blocker and the smallest next fix. Keep all no-connect safety fields false. Do not proceed to a real call flow.
