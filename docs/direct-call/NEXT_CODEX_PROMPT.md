# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48E implemented the disabled controlled-connect switch and proof gates. This remains no-connect only.

Closed prerequisites:
- 2.47C physical controlled media credentials request succeeded with no media connect.
- 2.47D physical credentials cleanup / expiry proof succeeded.
- 2.47E server-side allocation/token expiry verification succeeded without LiveKit join.
- 2.48A documented the future media-connect seam.
- 2.48B implemented the controlled media-connect preflight guard.
- 2.48C proved the guard physically after real invite/APNs/PushKit/CallKit Answer.
- 2.48D reviewed the server/client readiness gates and concluded controlled connect is not yet approved.
- 2.48E added the disabled DEBUG-only switch/proof gates and kept execution blocked.

2.48E expected proof fields:

```text
controlled_connect_switch_present=true
controlled_connect_switch_debug_only=true
controlled_connect_switch_enabled=false
controlled_connect_operator_approved=false
controlled_connect_execution_allowed=false
controlled_connect_blocked_reason=disabled_switch_no_connect
controlled_connect_blocked_before_engine=true
controlled_connect_blocked_before_livekit_join=true
controlled_connect_blocked_before_permissions=true
controlled_connect_blocked_before_matrix_events=true
media_connect_preflight_requested=true
media_connect_preflight_metadata_available=true
media_connect_preflight_credentials_available=true
media_connect_preflight_token_present=true
media_connect_preflight_url_present=true
media_connect_preflight_expires_at_present=true
media_connect_guard_enabled=true
media_connect_execution_allowed=false
media_connect_preflight_result=blocked_before_connect_redacted
media_connect_blocked_reason=disabled_switch_no_connect
media_connect_engine_invoked=false
livekit_connect_audio_invoked=false
```

Safety boundary must remain false:

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

`2.48F — review disabled controlled-connect switch proof gates, no enablement`

## Goal

Review or prove the 2.48E switch/gate layer while keeping controlled connect disabled. Do not enable media connect, do not call `connectAudio`, and do not join LiveKit.

## Required Behavior

- Keep the DEBUG-only switch disabled by default.
- Keep operator approval false unless a later explicitly approved phase changes it.
- Keep `controlled_connect_execution_allowed=false`.
- Keep `media_connect_execution_allowed=false`.
- Keep media engine invocation and LiveKit connect invocation false.
- Keep microphone/camera permission requests false.
- Keep Matrix event emission false.
- Keep full direct-call flow false.
- Preserve redacted proof only.
- Do not change server token scope, token TTL, allocation TTL, or room pre-create behavior.

## Required Tests

- Source/proof guard showing the switch remains DEBUG-only and disabled.
- Source/proof guard showing operator approval remains false.
- Source/proof guard showing disabled switch keeps execution blocked before media engine and LiveKit.
- Source/proof guard showing microphone/camera permission fields remain false.
- Source/proof guard showing Matrix event emission and full flow remain false.
- Privacy guard proving no raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer/user/device ID is written to proof/docs.

## Hard Constraints

- Do not use `dev/invite`.
- Do not send production APNs.
- Do not send APNs.
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
