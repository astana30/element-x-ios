# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48L-Retry2 physically succeeded after receiver app session validation. Pending metadata fetch succeeded, credentials were requested and received, 2.48K enablement wiring was present/default-off on-device, and media-connect preflight reached the guard and blocked before connect. No media connect, LiveKit join, microphone/camera permission, Matrix event emission, or full call flow occurred.

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

2.48L-Retry2 conclusion:

```text
2.48L-Retry2 = physical proof succeeded
proof_generation=generation_14
receiver app session validation held
pending metadata fetch succeeded
credentials requested and received
enablement wiring present on-device
enablement default off
execution allowed=false
blocked reason=enablement_disabled_no_connect
no media connect
no LiveKit join
no mic/camera permission
no Matrix events
no full call flow
```

PushKit and CallKit Answer succeeded:

```text
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_first_action_kind=answer
callkit_answer_action_delivered=true
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
```

Pending metadata and credentials succeeded:

```text
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
pending_metadata_fetch_errcode=none
pending_metadata_fetch_failure_reason=none
foreground_pending_call_metadata_handoff_observed=true
media_credentials_request_metadata_available=true
media_credentials_boundary_reached=true
media_credentials_requested=true
media_credentials_request_authorized=true
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_url_received=true
media_credentials_expires_at_present=true
media_credentials_payload_redacted=true
```

Enablement remained default-off:

```text
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_debug_only=true
controlled_connect_enablement_default_off=true
controlled_connect_enablement_operator_approval_required=true
controlled_connect_enablement_one_shot=true
controlled_connect_enablement_fresh_credentials_required=true
controlled_connect_enablement_audio_only=true
controlled_connect_enablement_video_allowed=false
controlled_connect_enablement_matrix_events_allowed=false
controlled_connect_enablement_raw_credentials_logged=false
controlled_connect_enablement_rollback_available=true
controlled_connect_enablement_enabled=false
controlled_connect_enablement_operator_approved=false
controlled_connect_enablement_future_phase_permitted=false
controlled_connect_enablement_execution_allowed=false
controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
```

Media-connect preflight reached the guard and blocked before connect:

```text
media_connect_preflight_requested=true
media_connect_preflight_metadata_available=true
media_connect_preflight_credentials_available=true
media_connect_preflight_token_present=true
media_connect_preflight_url_present=true
media_connect_preflight_expires_at_present=true
media_connect_execution_allowed=false
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

`2.48M — controlled-connect first-run readiness gate, no physical connect`

## Goal

Prepare the first controlled-connect readiness gate without performing physical connect. This is not a physical APNs task, not a media-connect task, and not a LiveKit join task.

## Required Behavior

- Do not send APNs.
- Do not run `dev/invite`.
- Do not start media connect.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full direct-call flow.
- Do not enable controlled-connect switch by default.
- Do not enable operator approval by default.
- Do not enable future physical-connect permission by default.
- Preserve the 2.48L-Retry2 success as the latest physical no-connect proof.
- Build a readiness gate/plan for the future first controlled-connect run that explicitly requires a fresh operator confirmation before any later physical connect.

Carry forward these 2.48L-Retry2 proof fields:

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
