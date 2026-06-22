# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48M completed the controlled-connect first-run readiness gate. The result is ready for the first controlled audio-only connect implementation phase, with no physical connect performed. Controlled connect was not enabled, operator approval was not enabled, future physical-connect permission was not enabled, and the default remains no-connect.

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
- 2.48L-Metadata401 classified the failed pending metadata auth boundary after the one-shot physical attempt; 2.48L is not closed.
- 2.48L-SessionRepair validated the iPhone app Matrix session before any retry; no APNs was sent.
- 2.48L-Retry2Plan prepared the one-shot retry checklist after receiver app session validation; no APNs was sent.
- 2.48L-Retry2 physically closed the post-session-repair proof with credentials success and no media connect.
- 2.48M completed the readiness gate and found no blocker for the next no-physical-connect implementation phase.

2.48M conclusion:

```text
2.48M = controlled-connect first-run readiness gate
physical connect not performed
controlled connect not enabled
default remains no-connect
2.48M result = ready for first controlled audio-only connect implementation phase, no physical connect performed
```

Readiness checklist:

```text
readiness_pushkit_apns_path_proved=true
readiness_callkit_answer_path_proved=true
readiness_pending_metadata_fetch_proved=true
readiness_receiver_app_session_validated=true
readiness_media_credentials_proved=true
readiness_credentials_cleanup_proved=true
readiness_server_token_expiry_proved=true
readiness_enablement_default_off_proved=true
readiness_enablement_one_shot_proved=true
readiness_audio_only_scope_proved=true
readiness_video_disabled=true
readiness_matrix_events_disabled=true
readiness_raw_credentials_not_logged=true
readiness_rollback_available=true
readiness_tests_passed=true
readiness_physical_connect_not_yet_approved=true
```

Blockers before any first controlled connect:

```text
block_if_receiver_app_session_invalid=true
block_if_terminal_tokens_invalid=true
block_if_room_validation_fails=true
block_if_credentials_fail=true
block_if_enablement_not_default_off=true
block_if_video_enabled=true
block_if_matrix_events_enabled=true
block_if_raw_credentials_logged=true
block_if_rollback_missing=true
block_if_tests_fail=true
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

`2.48N — implement first controlled audio-connect execution path, default disabled, no physical connect`

## Goal

Implement the first controlled audio-connect execution path behind the existing DEBUG-only switch/activation/enablement gates while preserving default-disabled behavior. This is a code implementation phase only; it is not a physical APNs task, not a physical media-connect task, not a LiveKit join task, and not a real call task.

## Required Behavior

- Do not send APNs.
- Do not run `dev/invite`.
- Do not start physical media connect.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full direct-call flow.
- Do not enable controlled-connect switch by default.
- Do not enable operator approval by default.
- Do not enable future physical-connect permission by default.
- Do not add production-enabled connect behavior.
- Preserve 2.48L-Retry2 as the latest physical no-connect proof.
- Preserve 2.48M as the go/no-go readiness gate.
- Keep the implementation default-disabled unless a later explicit physical phase provides fresh operator confirmation.

The 2.48N implementation must keep these fields false/default-off:

```text
controlled_connect_enablement_enabled=false
controlled_connect_enablement_operator_approved=false
controlled_connect_enablement_future_phase_permitted=false
controlled_connect_enablement_execution_allowed=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Implementation Notes

- Keep `DirectCallEngine.requestMediaCredentials` as the credentials-only boundary.
- Keep `DirectCallEngine.connectMediaIfReady` as the private media boundary that is callable only after an explicitly allowed controlled path exists.
- Keep `LiveKitDirectCallMediaEngine.connectAudio` as the first real media-connect boundary; do not invoke it physically in 2.48N.
- Use the existing DEBUG proof adapter fields to prove default-off behavior and no-connect safety.
- Preserve audio-only scope, video disabled, Matrix events disabled, raw credentials not logged, and rollback available.

## Required Checks

Run relevant changed-file/targeted DirectCall checks for any code changes, plus:

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
- Do not connect media physically.
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

Report the blocker and the smallest next fix. Keep all no-connect safety fields false. Do not proceed to actual physical connect.
