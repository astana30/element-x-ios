# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task — continue 2.47A physical close-out

Latest completed state:
- 2.47A added a DEBUG-only planner media credentials boundary after `foreground_call_state=real_invite_pending_media`
- planned proof fields are `media_credentials_boundary_reached=true`, `media_credentials_request_planned=true`, `media_credentials_result=planned_redacted`, `media_credentials_token_redacted=true`, `media_credentials_url_redacted=true`, and `media_credentials_payload_redacted=true`
- media credential request, media connection, LiveKit join, Matrix events, and full direct-call flow remain unwired
- changed-file SwiftFormat, changed-file SwiftLint, targeted DirectCall tests, and physical Debug build/install passed
- route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, stream `401`, token registration `401`, and APNs send control `401`
- physical close-out stopped before APNs because PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`

Next action:
- refresh iPhone auth/session
- rerun PushKit upload smoke until http_success / registered / persisted / redacted_match
- run exactly one authenticated real non-dev invite/APNs attempt
- read `Documents/salemx-voip-push-receipt-proof.txt` and confirm the planner media credentials boundary fields

Safety:
- do not print, log, document, or commit raw PushKit/APNs tokens, APNs key material, JWTs, authorization headers, Matrix access tokens, request payloads, private logs, raw user IDs, raw device IDs, room IDs, call handles, or secret-bearing URLs
- do not attempt production APNs
- do not send repeated pushes
- do not use `dev/invite`
- do not wire media, emit Matrix events, or start full direct-call flow unless the next task explicitly scopes that work
- do not touch project/signing/entitlement/Info.plist/app.yml files
