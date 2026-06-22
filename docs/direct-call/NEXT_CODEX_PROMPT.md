# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48L-Retry2Plan prepared the next one-shot physical retry after receiver app session validation. This was docs-only: no APNs was sent, no retry invite was run, and the default remains no-connect.

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

2.48L-Retry2Plan conclusion:

```text
2.48L-Retry2Plan = ready for one explicit retry only after receiver app session validation
receiver app Matrix session validated=true
APNs not sent
default remains no-connect
```

Retry2 requirements:

```text
retry2_requires_receiver_app_session_validated=true
retry2_requires_fresh_debug_app_running=true
retry2_requires_terminal_tokens_valid=true
retry2_requires_room_validation_pass=true
retry2_requires_single_sandbox_apns=true
retry2_requires_operator_green_answer_ready=true
retry2_requires_post_answer_polling=true
retry2_rejects_stale_proof=true
retry2_forbids_media_connect=true
retry2_forbids_livekit_join=true
retry2_forbids_permissions=true
retry2_forbids_matrix_events=true
retry2_forbids_full_flow=true
```

Required success fields for the future retry:

```text
pending_metadata_fetch_result=success_redacted
foreground_pending_call_metadata_handoff_observed=true
media_credentials_result=success_redacted
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_enabled=false
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

Stop conditions:

```text
if APNs sent once, do not repeat automatically
if pending_metadata_fetch_result=blocked_redacted, stop and classify
if media_credentials_result=not_requested after Answer, stop and classify
if enablement fields missing, verify installed commit before any retry
if media_connect_requested=true, stop as safety regression
if livekit_join_requested=true, stop as safety regression
```

Receiver app session precondition carried forward:

```text
iphone_app_matrix_session_present=true
iphone_app_matrix_session_whoami_result=success_redacted
iphone_app_matrix_session_user_hash=497015f5745c933a
iphone_app_matrix_session_device_present=true
iphone_app_pending_metadata_auth_ready=true
```

## Phase

`2.48L-Retry2 — one-shot physical proof retry after app session validation, no LiveKit join`

## Goal

Execute exactly one explicit operator-approved physical retry after re-confirming the receiver app session, terminal tokens, room validation, and local schema. The retry must prove pending metadata fetch, foreground handoff, credentials, and default-off enablement guard without media connect or LiveKit join.

## Required Behavior

- Send at most one sandbox APNs only after preflight passes and explicit one-shot confirmation is reached.
- After `background_apns_push_result=sandbox_success`, do not send another APNs.
- Require the fresh Debug app to be running.
- Require terminal tokens to validate and room validation to pass.
- Require operator green Answer readiness and post-Answer polling before copying proof.
- Reject stale proof generations.
- Keep the distinction explicit: terminal invite tokens can send the real non-dev invite, but the iPhone app's own stored session performs pending metadata fetch.
- Do not mark 2.48L closed.
- Stop and classify on any blocked pending metadata fetch, missing credentials request after Answer, missing enablement fields, media-connect request, or LiveKit join request.

Required success fields:

```text
pending_metadata_fetch_result=success_redacted
foreground_pending_call_metadata_handoff_observed=true
media_credentials_result=success_redacted
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_enabled=false
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

## Required Checks

Run docs/checkpoint checks only unless code changes become necessary:

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
- Do not add production-enabled connect behavior.
- Do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, room names, key material, or secret-bearing URLs.
- Do not touch project/signing/entitlement/`Info.plist`/`app.yml` files.
- Do not stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.

## If Blocked

Report the blocker and the smallest next fix. Keep all no-connect safety fields false. Do not proceed to actual controlled connect.
