# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48L-Metadata401 classified the physical enablement default-off proof attempt as incomplete. APNs was already sent once and succeeded; PushKit and CallKit Answer reached; 2.48K enablement fields were present/default-off; pending metadata fetch failed with `401 M_UNKNOWN_TOKEN`; credentials and media-connect preflight were not requested. No repeat APNs was performed.

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

2.48L-Metadata401 conclusion:

```text
2.48L physical attempt = incomplete
APNs sent once
PushKit received
CallKit Answer reached
2.48K enablement fields present/default-off
pending metadata fetch failed with 401 M_UNKNOWN_TOKEN
credentials not requested
media-connect preflight not requested
2.48L not closed
no repeat APNs performed
```

One-shot invite/APNs result:

```text
invite_http_code=200
background_apns_push_result=sandbox_success
APNs_sent=true
```

Physical proof classification:

```text
proof_generation=generation_7
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
controlled_connect_enablement_wiring_present=true
controlled_connect_enablement_default_off=true
controlled_connect_enablement_execution_allowed=false
controlled_connect_enablement_blocked_reason=enablement_disabled_no_connect
pending_metadata_fetch_requested=true
pending_metadata_fetch_authorized=true
pending_metadata_fetch_result=blocked_redacted
pending_metadata_fetch_http_status_bucket=401
pending_metadata_fetch_errcode=M_UNKNOWN_TOKEN
pending_metadata_fetch_failure_reason=auth_rejected
foreground_pending_call_metadata_handoff_observed=false
media_credentials_requested=false
media_connect_preflight_requested=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=pending_metadata_fetch_http_failure_redacted
```

Likely cause:

```text
likely_iPhone_app_matrix_session_invalid_or_stale=true
terminal_invite_tokens_are_not_sufficient_for_iPhone_pending_metadata_fetch=true
receiver_app_session_must_be_valid_before_retry=true
```

## Phase

`2.48L-SessionRepair — refresh/validate iPhone app Matrix session before any APNs retry, no APNs`

## Goal

Refresh or validate the iPhone app's stored/authenticated Matrix session before any future APNs retry. This is a no-APNs diagnostic/session-repair phase only.

## Required Behavior

- Do not send APNs in this phase.
- Do not run a retry invite.
- Validate that the freshly installed iPhone app is logged in as the expected receiver account and has a valid authenticated Matrix session before any future physical retry is planned.
- If local app state is stale, refresh the receiver app session through normal app login/session repair only; do not work around it by using terminal tokens inside the app proof path.
- Keep the distinction explicit: terminal invite tokens can send the real non-dev invite, but the iPhone app's own stored session performs pending metadata fetch.
- Do not mark 2.48L closed.
- Do not set the next phase to a retry until receiver app session validity is proven.

Required session-repair conclusion fields:

```text
2.48L-SessionRepair = complete
receiver_app_session_validated=true
receiver_app_session_matches_expected_hash=true
pending_metadata_retry_precondition_app_session_valid=true
APNs_sent=false
retry_not_performed=true
next_phase_after_sessionrepair=not_selected_until_explicit_operator_approval
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

- Do not send APNs in 2.48L-SessionRepair.
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
