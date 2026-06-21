# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48G documented the controlled-connect activation plan and rollback design. Controlled connect is still not approved, physical connect has not been performed, and the default remains no-connect.

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

2.48G activation checklist:

```text
activation_requires_debug_only_switch=true
activation_requires_operator_approval=true
activation_requires_one_shot_physical_run=true
activation_audio_only=true
activation_video_disabled=true
activation_matrix_events_disabled=true
activation_requires_fresh_credentials=true
activation_requires_expiry_check=true
activation_requires_rollback_plan=true
activation_requires_redacted_proof=true
activation_requires_no_raw_token_logging=true
activation_requires_tests_before_physical=true
```

2.48G rollback plan:

```text
rollback_disable_switch=true
rollback_operator_approval_false=true
rollback_restore_execution_allowed_false=true
rollback_keep_media_engine_invoked_false=true
rollback_keep_livekit_join_requested_false=true
rollback_keep_permissions_unrequested=true
rollback_keep_matrix_events_false=true
```

Planned future first controlled-connect proof fields:

```text
controlled_connect_switch_enabled=true
controlled_connect_operator_approved=true
controlled_connect_execution_allowed=true
controlled_connect_activation_scope=audio_only_redacted
controlled_connect_video_allowed=false
controlled_connect_matrix_events_allowed=false
controlled_connect_raw_credentials_logged=false
controlled_connect_rollback_available=true
```

Hard stop fields must remain false unless a future phase explicitly allows them:

```text
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Phase

`2.48H — implement controlled-connect activation switch wiring, default disabled, no physical connect`

## Goal

Implement the controlled-connect activation switch wiring without running a physical connect. The switch must remain DEBUG-only, default disabled, and operator approval must remain false unless a future explicitly approved physical phase changes it.

## Required Behavior

- Add only the smallest activation-switch wiring needed for a future controlled connect.
- Keep the DEBUG-only switch disabled by default.
- Keep operator approval false by default.
- Keep `controlled_connect_execution_allowed=false` by default.
- Keep `media_connect_execution_allowed=false` by default.
- Keep media engine invocation and LiveKit connect invocation false in default proof.
- Keep microphone/camera permission requests false in default proof.
- Keep Matrix event emission false.
- Keep full direct-call flow false.
- Preserve redacted proof only.
- Do not change server token scope, token TTL, allocation TTL, or room pre-create behavior.
- Preserve rollback to the 2.48F no-connect state: disabled switch, operator approval false, execution allowed false, media engine not invoked, LiveKit join not requested, permissions unrequested, Matrix events false.
- Do not enable the controlled-connect switch or operator approval outside tests.

## Required Tests

- Source/proof guard showing the switch remains DEBUG-only and disabled by default.
- Source/proof guard showing operator approval remains false by default.
- Source/proof guard showing disabled switch keeps execution blocked before media engine and LiveKit.
- Source/proof guard showing rollback restores disabled/no-connect proof.
- Source/proof guard showing microphone/camera permission fields remain false by default.
- Source/proof guard showing Matrix event emission and full flow remain false by default.
- If adding a test-only approved path, prove it is DEBUG/test-only and does not run physical APNs, LiveKit join, permissions, Matrix events, or full flow.
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
