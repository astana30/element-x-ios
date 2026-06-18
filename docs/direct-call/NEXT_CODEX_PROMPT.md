# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest completed state

2.47B1 foreground pending-call metadata handoff is implemented as a redacted DEBUG bridge from the existing `DirectCallSession`.

Latest proven physical baseline before 2.47B1:
- real non-dev invite/APNs reached SalemX VoIP receipt: `physical_voip_push_received=true`, `pushkit_callback_invoked=true`, `pushkit_payload_kind=real_invite_controlled`
- CallKit reported and Answer was first action: `callkit_report_result=reported`, `callkit_first_action_kind=answer`, `callkit_answer_action_delivered=true`
- foreground handoff passed: `foreground_call_state=real_invite_pending_media`, source `callkit_answer_real_invite_controlled`, redacted stable correlation true
- media credentials boundary reached an explicit safe blocked request lifecycle: `media_credentials_boundary_reached=true`, `media_credentials_request_planned=false`, `media_credentials_requested=false`, `media_credentials_request_authorized=false`, `media_credentials_result=blocked_redacted`
- token/URL/payload redaction proof was true while no token or URL was received: `media_credentials_token_received=false`, `media_credentials_token_redacted=true`, `media_credentials_url_received=false`, `media_credentials_url_redacted=true`, `media_credentials_payload_redacted=true`
- local persistence and cleanup stayed inert: `media_credentials_local_persistence_requested=false`, `media_credentials_cleanup_requested=false`, `media_credentials_cleanup_result=not_requested`
- `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `matrix_event_emit_requested=false`, `real_call_flow_started=false`
- `blocked_reason=media_credentials_request_boundary_not_ready`

Callback-owner note:
- `element_call_pushkit_callback_invoked=false`
- `element_call_salemx_payload_observed=false`
- the startup detector did not trigger in the successful path; SalemX PushKit receipt triggered directly and completed

2.47B1 code state:
- the foreground production accept path records `foreground_pending_call_metadata_handoff_observed=true` from the returned `DirectCallSession`
- proof records only redacted metadata presence booleans plus safe direction/intent classes
- synthetic PushKit proof remains blocked with `media_credentials_request_metadata_available=false` when no real session metadata exists
- no real media credentials request, media connection, LiveKit join, Matrix event emission, or full call flow is wired

## Next task

Start a new phase only when explicitly authorized.

Recommended next phase:
`2.47B2 — controlled media credentials request using handed-off metadata`

Goal:
- do not put raw room IDs, call IDs, call handles, user IDs, device IDs, tokens, URLs, or request bodies into proof files or logs
- request credentials only through the existing token boundary if the handed-off metadata is present and authorized
- immediately redact token, URL, identifiers, and request/response payloads
- do not connect media, join LiveKit, emit Matrix events, or start full call flow

Safety:
- do not use `dev/invite`
- do not send production APNs
- do not repeat APNs outside one planned physical attempt
- do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- do not touch project/signing/entitlement/Info.plist/app.yml files
