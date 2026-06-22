# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48I-Retry physically proved the disabled activation wiring on-device after the one-shot Answer-path retry. The retry reached PushKit, CallKit Answer, authenticated pending metadata handoff, controlled credentials success, and the media-connect preflight guard while still blocking before connect. Controlled connect is still not approved, physical connect has not been performed, and the default remains no-connect.

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
- 2.48I-Retry physically closed the disabled activation proof on the one-shot retry with Answer, credentials, preflight guard, and no media connect.

2.48I-Retry conclusion:

```text
2.48I-Retry = physical proof succeeded
activation wiring present on-device
Answer pipeline reached
credentials requested and received
media-connect preflight reached guard
execution_allowed=false
blocked reason=disabled_switch_no_connect
no media connect
no LiveKit join
no mic/camera permission
no Matrix events
no full call flow
```

Key proof fields:

```text
proof_generation=generation_8
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
callkit_first_action_kind=answer
callkit_answer_action_delivered=true
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
foreground_pending_call_metadata_handoff_observed=true
foreground_pending_call_metadata_source=authenticated_pending_metadata_fetch
media_credentials_result=success_redacted
media_connect_preflight_requested=true
controlled_connect_activation_wiring_present=true
controlled_connect_execution_allowed=false
controlled_connect_blocked_reason=disabled_switch_no_connect
media_connect_preflight_result=blocked_before_connect_redacted
media_connect_blocked_reason=disabled_switch_no_connect
media_connect_engine_invoked=false
livekit_connect_audio_invoked=false
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

`2.48J — controlled-connect enablement implementation plan, no physical connect`

## Goal

Prepare the implementation plan for controlled-connect enablement after the successful disabled proof. This phase is planning only: no physical connect, no APNs, no media engine invocation, no LiveKit join, no microphone/camera permission request, no Matrix event emission, and no full direct-call flow.

## Required Behavior

- Produce a narrow enablement implementation plan, not an execution.
- Keep the current runtime default disabled and no-connect.
- Identify the exact code/config seams that would need to change in a later implementation phase.
- Preserve the two-key activation model: DEBUG-only controlled switch plus explicit operator approval.
- Preserve rollback to the 2.48F/2.48I no-connect state.
- Define proof fields required for any future first controlled-connect implementation and physical proof.
- Define hard stops for video, Matrix event emission, raw credentials logging, production APNs, repeated APNs, and unsupervised rollout.
- Do not enable controlled connect in this phase.
- Do not request or use microphone/camera permissions in this phase.
- Do not change server token scope, token TTL, allocation TTL, or room pre-create behavior unless the plan explicitly documents a later reviewed phase.

## Required Tests

- Docs-only planning should run `git diff --check`, forbidden project/signing scans, and a privacy scan over changed docs/diff.
- If Swift/test files change, run SwiftFormat/SwiftLint on the touched scope and the targeted DirectCall tests.
- If enablement code is planned but not implemented, list the tests required for the later implementation phase instead of running a physical proof.
- Privacy guard proving no raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID is written to proof/docs.

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
- Do not enable the controlled-connect switch.
- Do not enable controlled-connect operator approval.
- Do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, room names, key material, or secret-bearing URLs.
- Do not touch project/signing/entitlement/`Info.plist`/`app.yml` files.
- Do not stage `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.

## If Blocked

Report the blocker and the smallest next fix. Keep all no-connect safety fields false. Do not proceed to a real call flow.
