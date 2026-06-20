# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48D completed the server/client readiness review before any controlled connect. This remains no-connect only.

Closed prerequisites:
- 2.47C physical controlled media credentials request succeeded with no media connect.
- 2.47D physical credentials cleanup / expiry proof succeeded.
- 2.47E server-side allocation/token expiry verification succeeded without LiveKit join.
- 2.48A documented the future media-connect seam.
- 2.48B implemented the controlled media-connect preflight guard.
- 2.48C proved the guard physically after real invite/APNs/PushKit/CallKit Answer.
- 2.48D reviewed the server/client readiness gates and concluded controlled connect is not yet approved.

2.48C proof generation:

```text
proof_generation=generation_8
```

The successful proof included:

```text
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
callkit_first_action_kind=answer
foreground_pending_call_metadata_handoff_observed=true
media_credentials_request_metadata_available=true
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_url_received=true
media_credentials_expires_at_present=true
media_credentials_cleanup_requested=true
media_credentials_cleanup_result=cleared
media_credentials_reuse_allowed=false
media_credentials_expiry_check_result=expired_or_not_reusable_redacted
media_connect_preflight_requested=true
media_connect_preflight_metadata_available=true
media_connect_preflight_credentials_available=true
media_connect_preflight_token_present=true
media_connect_preflight_url_present=true
media_connect_preflight_expires_at_present=true
media_connect_guard_enabled=true
media_connect_execution_allowed=false
media_connect_preflight_result=blocked_before_connect_redacted
media_connect_blocked_reason=controlled_preflight_no_connect
media_connect_engine_invoked=false
livekit_connect_audio_invoked=false
```

Safety boundary stayed false:

```text
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

2.48D readiness checklist:

```text
client_preflight_guard_present=true
client_default_connect_allowed=false
client_media_engine_invocation_proven_false=true
client_livekit_connect_audio_invocation_proven_false=true
client_mic_permission_boundary_identified=true
client_camera_permission_boundary_identified=true
client_matrix_event_emit_boundary_identified=true
server_token_expiry_verified=true
server_allocation_ttl_verified=true
server_rate_limit_no_allocation_verified=true
credentials_redaction_verified=true
cleanup_non_persistence_verified=true
rollback_kill_switch_required=true
controlled_connect_not_yet_approved=true
```

## Phase

`2.48E — implement disabled controlled-connect switch and proof gates, no LiveKit join`

## Goal

Add a disabled-by-default DEBUG-only controlled-connect switch and proof gates for a future connect attempt, while still preventing any media connect or LiveKit join in this phase.

This phase prepares the switch/guard surface only. It must not enable connect execution and must not call `connectAudio` or LiveKit.

## Required Behavior

- Add an explicit DEBUG-only connect switch that defaults to disabled.
- Add proof fields showing the switch exists and is disabled.
- Keep `media_connect_execution_allowed=false` unless a later phase explicitly changes it.
- Keep media engine invocation and LiveKit connect invocation false.
- Keep microphone/camera permission requests false.
- Keep Matrix event emission false.
- Keep full direct-call flow false.
- Preserve immediate rollback to the current no-connect behavior.
- Do not change server token scope, token TTL, allocation TTL, or room pre-create behavior.

Suggested proof fields:

```text
controlled_connect_switch_present=true
controlled_connect_switch_enabled=false
controlled_connect_operator_approval_required=true
controlled_connect_operator_approval_observed=false
controlled_connect_one_shot_required=true
controlled_connect_rollback_available=true
controlled_connect_video_disabled=true
controlled_connect_matrix_events_disabled=true
controlled_connect_audio_permission_deferred=true
controlled_connect_livekit_join_allowed=false
media_connect_execution_allowed=false
media_connect_engine_invoked=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

## Required Tests

- Source guard proving the switch is DEBUG-only and defaults disabled.
- Source guard proving disabled switch keeps `media_connect_execution_allowed=false`.
- Source guard proving media engine / LiveKit connect invocations remain false.
- Source guard proving microphone/camera permission fields remain false.
- Source guard proving Matrix event emission and full flow remain false.
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
