# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48C physically proved the DEBUG-only controlled media-connect preflight guard after successful credentials receipt. This is still no-connect only.

Closed prerequisites:
- 2.47C physical controlled media credentials request succeeded with no media connect.
- 2.47D physical credentials cleanup / expiry proof succeeded.
- 2.47E server-side allocation/token expiry verification succeeded without LiveKit join.
- 2.48A documented the future media-connect seam.
- 2.48B implemented the controlled media-connect preflight guard.
- 2.48C proved the guard physically after real invite/APNs/PushKit/CallKit Answer.

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

## Phase

`2.48D — server/client readiness review before any controlled connect`

## Goal

Review the server and iOS client readiness before allowing any future controlled media-connect attempt.

This phase is review/planning only. Do not run APNs, do not connect media, and do not join LiveKit.

## Review Targets

- Confirm the server allocation/token lifecycle is ready for a short controlled connect attempt without changing token scope, token TTL, or allocation expiry.
- Confirm the iOS `DirectCallMediaConnectionInfo` path is the only credentials consumer before connect.
- Confirm the connect entrypoint remains gated behind an explicit DEBUG-only operator action and proof guard.
- Confirm microphone/camera permission prompts remain blocked until a separately approved connect phase.
- Confirm Matrix event emission and full direct-call flow remain blocked.
- Define rollback/kill-switch steps before enabling any connect path.
- Define exact proof fields required for the first controlled connect attempt.
- Define the minimal tests required before that attempt.

## Required Output

- Readiness findings with code references.
- A go/no-go checklist for 2.48E or the next explicitly approved controlled connect phase.
- Required proof fields for any future connect attempt.
- Required rollback/kill-switch behavior.
- Required targeted tests.
- Docs update only unless a concrete readiness bug is found.

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

Report the blocker and the smallest next fix. Keep all no-connect safety fields false.
