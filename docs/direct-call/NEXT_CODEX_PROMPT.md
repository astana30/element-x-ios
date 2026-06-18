# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest completed state

2.47A controlled media credentials boundary is physically closed.

Successful proof:
- real non-dev invite/APNs reached SalemX VoIP receipt: `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=real_invite_controlled`
- CallKit reported and Answer was first action: `callkit_report_result=reported`, `callkit_first_action_kind=answer`, `callkit_answer_action_delivered=true`
- foreground handoff passed: `foreground_call_state=real_invite_pending_media`, source `callkit_answer_real_invite_controlled`, redacted stable correlation true
- media credentials boundary was planner-only: `media_credentials_boundary_reached=true`, `media_credentials_request_planned=true`, `media_credentials_result=planned_redacted`
- token/URL/payload redaction proof was true
- `media_credentials_requested=false`, `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `matrix_event_emit_requested=false`, `real_call_flow_started=false`
- `blocked_reason=none`

Callback-owner note:
- `element_call_pushkit_callback_invoked=false`
- `element_call_salemx_payload_observed=false`
- the startup detector did not trigger in the successful path; SalemX PushKit receipt triggered directly and completed

## Next task

Start a new phase only when explicitly authorized.

Recommended next phase:
`2.47B — controlled real media credentials request`

Goal:
- move from planner-only boundary to a real authenticated media-credentials request through the existing boundary
- redact token, URL, room/call identifiers, and request/response payloads
- do not connect media, join LiveKit, emit Matrix events, or start full call flow

Safety:
- do not use `dev/invite`
- do not send production APNs
- do not repeat APNs outside one planned physical attempt
- do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- do not touch project/signing/entitlement/Info.plist/app.yml files
