# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task — continue after 2.46A4

Latest completed state:
- real non-dev invite background APNs path physically reached `real_invite_controlled`
- PushKit callback proof, controlled CallKit report, PushKit completion, CallKit Answer, controlled in-app screen, and controlled cleanup all passed
- receiver PushKit upload smoke returned http_success / registered / persisted / redacted_match
- exactly one authenticated non-dev invite/APNs attempt was run; dev invite was not used
- dedicated VoIP receipt proof returned `callkit_report_result=reported`, `pushkit_completion_called=true`, `callkit_answer_action_received=true`, `callkit_answer_action_fulfilled=true`, `controlled_in_app_screen_presented=true`, `controlled_in_app_screen_source=callkit_answer_real_invite_controlled`, `controlled_callkit_cleanup_result=ended`, and `blocked_reason=none`
- media credentials, media connection, Matrix events, and full direct-call flow remain unwired

Safety:
- do not print, log, document, or commit raw PushKit/APNs tokens, APNs key material, JWTs, authorization headers, Matrix access tokens, request payloads, private logs, raw user IDs, raw device IDs, room IDs, call handles, or secret-bearing URLs
- do not attempt production APNs
- do not send repeated pushes
- do not use `dev/invite`
- do not wire media, emit Matrix events, or start full direct-call flow unless the next task explicitly scopes that work
- do not touch project/signing/entitlement/Info.plist/app.yml files
