# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48H implemented controlled-connect activation switch wiring with the default disabled. Controlled connect is still not approved, physical connect has not been performed, and the default remains no-connect.

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

2.48H default proof fields:

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
controlled_connect_switch_enabled=false
controlled_connect_operator_approved=false
controlled_connect_execution_allowed=false
controlled_connect_blocked_reason=disabled_switch_no_connect
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

## Phase

`2.48I — physical proof of activation wiring disabled, no LiveKit join`

## Goal

Physically prove the 2.48H activation wiring is present on-device while still disabled. This phase may exercise only the existing disabled proof path; it must not enable controlled connect, connect media, join LiveKit, request microphone/camera permission, emit Matrix events, or start full call flow.

## Required Behavior

- Keep the DEBUG-only activation switch disabled.
- Keep operator approval false.
- Prove the 2.48H activation wiring fields are present in physical redacted proof.
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

- Run the 2.48H targeted DirectCall source/proof guard tests before any physical proof.
- Physical proof must include the 2.48H activation wiring fields with default disabled values.
- Physical proof must keep media engine invocation and LiveKit connect invocation false.
- Physical proof must keep microphone/camera permission fields false.
- Physical proof must keep Matrix event emission and full flow false.
- Privacy guard proving no raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID is written to proof/docs.

## Hard Constraints

- Do not use `dev/invite`.
- Do not send production APNs.
- Do not send repeated APNs.
- Send at most one sandbox APNs attempt only if the explicit 2.48I disabled-wiring physical proof inputs and operator approval are present.
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
