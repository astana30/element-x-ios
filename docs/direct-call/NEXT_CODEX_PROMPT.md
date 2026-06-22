# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48I-Triage classified the one-shot 2.48I physical disabled-activation proof as incomplete before the Answer pipeline. APNs was sent once and the physical proof recorded push receipt plus activation wiring fields on-device, but CallKit report remained pending, no Answer action reached the pipeline, media credentials were not requested, and media-connect preflight was not requested. 2.48I is not closed. Controlled connect is still not approved, physical connect has not been performed, and the default remains no-connect.

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

2.48I-Triage conclusion:

```text
2.48I physical attempt = incomplete
APNs sent once
push received
activation wiring fields present
CallKit Answer did not reach pipeline
media credentials not requested
media-connect preflight not requested
2.48I not closed
no repeat APNs performed
```

2.48I-Triage safety boundary:

```text
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

2.48I-Triage on-device activation fields present:

```text
controlled_connect_activation_wiring_present=true
controlled_connect_activation_debug_only=true
controlled_connect_activation_default_disabled=true
controlled_connect_activation_requires_operator_approval=true
controlled_connect_activation_rollback_available=true
controlled_connect_activation_scope=planned_audio_only_redacted
controlled_connect_video_allowed=false
controlled_connect_matrix_events_allowed=false
controlled_connect_raw_credentials_logged=false
```

## Phase

`2.48I-RetryPlan — one-shot Answer-path retry plan with explicit operator approval, no immediate APNs`

## Goal

Prepare the next one-shot Answer-path retry plan after the incomplete 2.48I physical attempt. This planning phase must not send APNs. It should define the smallest safe retry steps that ensure the operator is ready, the proof copy is phase-specific, the proof generation is verified, and any later APNs send still requires fresh explicit inputs, helper preflight, and one-shot confirmation.

## Required Behavior

- Do not send APNs in this retry-planning phase.
- Record that the prior 2.48I attempt sent APNs once, received the push, proved activation fields, and stopped before Answer.
- Require a phase-specific future proof copy path, not `/tmp/salemx-voip-push-receipt-proof-current.txt`.
- Require future proof generation verification before classification.
- Require an explicit operator-ready step before any later send.
- Require future helper preflight and one-shot confirmation before any later sandbox APNs send.
- Keep the DEBUG-only activation switch disabled unless a later phase explicitly approves otherwise.
- Keep operator approval false unless a later phase explicitly approves otherwise.
- Keep `controlled_connect_execution_allowed=false`.
- Keep `media_connect_execution_allowed=false`.
- Keep media engine invocation and LiveKit connect invocation false.
- Keep microphone/camera permission requests false.
- Keep Matrix event emission false.
- Keep full direct-call flow false.
- Preserve redacted proof only.
- Do not change server token scope, token TTL, allocation TTL, or room pre-create behavior.
- Preserve rollback to the 2.48F no-connect state: disabled switch, operator approval false, execution allowed false, media engine not invoked, LiveKit join not requested, permissions unrequested, Matrix events false.
- Do not enable the controlled-connect switch or operator approval.

## Required Tests

- Docs/checkpoint-only changes should run `git diff --check`, forbidden project/signing scans, and a privacy scan over changed docs/diff.
- If Swift/test files change, run SwiftFormat/SwiftLint on the touched scope and the targeted DirectCall tests.
- Any future physical retry must first rerun the targeted DirectCall source/proof guard tests.
- Any future physical retry proof must include the activation wiring fields with default disabled values.
- Any future physical retry proof must keep media engine invocation and LiveKit connect invocation false.
- Any future physical retry proof must keep microphone/camera permission fields false.
- Any future physical retry proof must keep Matrix event emission and full flow false.
- Privacy guard proving no raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID is written to proof/docs.

## Hard Constraints

- Do not send APNs in the 2.48I-RetryPlan phase.
- Do not use `dev/invite`.
- Do not send production APNs.
- Do not send repeated APNs.
- Send at most one future sandbox APNs attempt only in a later explicitly approved physical retry phase, with fresh inputs, passing preflight, and one-shot confirmation.
- Do not connect media.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full call flow.
- Do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, room names, key material, or secret-bearing URLs.
- Do not touch project/signing/entitlement/`Info.plist`/`app.yml` files.
- Do not stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.

## If Blocked

Report the blocker and the smallest next fix. Keep all no-connect safety fields false. Do not proceed to a real call flow.
