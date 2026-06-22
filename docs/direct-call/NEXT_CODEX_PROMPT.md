# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48I-RetryPlan prepared the next one-shot Answer-path retry plan. No APNs was sent in the planning checkpoint. The prior 2.48I physical attempt remains incomplete: APNs was sent once, push was received, activation wiring fields were present, CallKit Answer did not reach the pipeline, media credentials were not requested, media-connect preflight was not requested, 2.48I was not closed, and no repeat APNs was performed. Controlled connect is still not approved, physical connect has not been performed, and the default remains no-connect.

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
- 2.48I-Triage classified the first physical disabled-activation proof attempt as incomplete before the Answer pipeline, with APNs sent once, push received, activation wiring fields present, credentials/preflight not requested, and no repeat APNs.
- 2.48I-RetryPlan defined the safest one-shot retry requirements and moved the next phase to one explicit operator-approved retry only.

2.48I-RetryPlan conclusion:

```text
2.48I-RetryPlan = ready for one explicit operator-approved retry only
```

Retry checklist:

```text
retry_requires_fresh_debug_install=true
retry_requires_current_head_confirmed=true
retry_requires_single_sandbox_apns=true
retry_requires_operator_answer_ready=true
retry_requires_green_answer_tap=true
retry_requires_post_answer_polling=true
retry_rejects_stale_generation=true
retry_requires_activation_fields=true
retry_requires_answer_pipeline_fields=true
retry_requires_credentials_fields=true
retry_requires_preflight_block_fields=true
retry_forbids_connect=true
retry_forbids_livekit_join=true
retry_forbids_permissions=true
retry_forbids_matrix_events=true
retry_forbids_full_flow=true
```

Required success fields for the retry:

```text
callkit_first_action_kind=answer
callkit_answer_action_delivered=true
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
media_credentials_result=success_redacted
media_connect_preflight_requested=true
controlled_connect_activation_wiring_present=true
controlled_connect_execution_allowed=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

Retry stop conditions:

```text
if APNs sent once, do not repeat automatically
if callkit_first_action_kind=none, stop and classify
if activation fields missing, verify installed commit before any retry
if credentials not requested after Answer, stop and classify
if media_connect_requested=true, stop as safety regression
if livekit_join_requested=true, stop as safety regression
```

## Phase

`2.48I-Retry — one-shot physical proof retry, no LiveKit join`

## Goal

Execute exactly one future physical proof retry only when fresh local inputs are present, helper preflight passes, and explicit one-shot confirmation is reached. The retry should prove the disabled activation wiring can reach CallKit Answer, controlled credentials, and the media-connect preflight guard while still blocking before any connect, LiveKit join, microphone/camera permission, Matrix event emission, or full call flow.

## Required Behavior

- Before any APNs send, confirm a fresh Debug app from current HEAD is installed and the installed commit matches current HEAD.
- Before any APNs send, confirm the intended app foreground/background state and do not send if that state is unknown.
- Before any APNs send, confirm the operator is ready to watch for the system CallKit UI and tap the green Answer button once.
- Use the local env file only if the next prompt supplies one; do not print token values.
- Send at most one sandbox APNs only after helper preflight passes and explicit one-shot confirmation is reached.
- After the sandbox APNs result, do not send another APNs.
- After green Answer, poll long enough for Answer, metadata handoff, credentials, and media-connect preflight-block fields to update before copying proof.
- Copy proof to a phase-specific path and verify the new proof generation before classification.
- Reject stale proof generations, including stale `/tmp/salemx-voip-push-receipt-proof-current.txt` content unless independently verified for the current run.
- Keep the DEBUG-only activation switch disabled.
- Keep controlled-connect operator approval false. The retry's operator approval is procedural approval for the one-shot physical proof, not approval to connect media.
- Keep `controlled_connect_execution_allowed=false`.
- Keep `media_connect_execution_allowed=false`.
- Keep media engine invocation and LiveKit connect invocation false.
- Keep microphone/camera permission requests false.
- Keep Matrix event emission false.
- Keep full direct-call flow false.
- Preserve redacted proof only.
- Do not change server token scope, token TTL, allocation TTL, or room pre-create behavior.
- Preserve rollback to the 2.48F no-connect state: disabled switch, operator approval false, execution allowed false, media engine not invoked, LiveKit join not requested, permissions unrequested, Matrix events false.
- Do not enable the controlled-connect switch or controlled-connect operator approval.

## Required Tests

- If Swift/test files change, run SwiftFormat/SwiftLint on the touched scope and the targeted DirectCall tests.
- Before physical retry, rerun the targeted DirectCall source/proof guard tests.
- Physical retry proof must include the activation wiring fields with default disabled values.
- Physical retry proof must include the Answer pipeline fields, credentials success fields, and preflight-block fields listed above.
- Physical retry proof must keep media engine invocation and LiveKit connect invocation false.
- Physical retry proof must keep microphone/camera permission fields false.
- Physical retry proof must keep Matrix event emission and full flow false.
- Privacy guard proving no raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID is written to proof/docs.

## Hard Constraints

- Do not use `dev/invite`.
- Do not send production APNs.
- Do not send repeated APNs.
- Send at most one sandbox APNs attempt, only with fresh inputs, passing preflight, and one-shot confirmation.
- Do not connect media.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full call flow.
- Do not enable the controlled-connect switch.
- Do not enable controlled-connect operator approval.
- Do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, room names, key material, or secret-bearing URLs.
- Do not touch project/signing/entitlement/`Info.plist`/`app.yml` files.
- Do not stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.

## If Blocked

Report the blocker and the smallest next fix. If APNs was already sent once for the retry, do not repeat automatically. Keep all no-connect safety fields false. Do not proceed to a real call flow.
