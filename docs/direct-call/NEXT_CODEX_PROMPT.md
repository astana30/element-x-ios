# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task — 2.46A3 physical real-invite Answer retry after auth refresh

Continue after 2.46A3 fixed the real-invite-controlled CallKit report pending state, but physical retry stopped before APNs because the receiver app auth was unavailable.

Latest redacted result:
- root cause/fix: the real-invite-controlled receipt could stay at `callkit_report_result=pending` with `pushkit_completion_called=false`; 2.46A3 now finalizes reported/failed/timeout result and calls PushKit completion exactly once
- timeout fallback is redacted as `callkit_report_completion_timeout_redacted`
- stale controlled synthetic CallKit harness state is cleared before reporting a new controlled call
- SwiftFormat, changed-file SwiftLint, and targeted DirectCall tests passed
- fresh physical Debug build/install passed
- PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- real non-dev invite/APNs retry was not run

Next safe step:
After refreshing the receiver app auth/session, rerun PushKit upload smoke. Only if it returns http_success / registered / persisted / redacted_match, run exactly one authenticated non-dev real invite/APNs attempt and observe the real-invite-controlled Answer proof.

Hard constraints:
- do not print, log, document, or commit raw PushKit/APNs tokens, APNs key material, JWTs, authorization headers, Matrix access tokens, request payloads, private logs, raw user IDs, raw device IDs, room IDs, call handles, or secret-bearing URLs
- do not attempt production APNs
- do not send repeated pushes
- do not wire media
- do not emit Matrix events
- do not start full direct-call flow
- do not touch project/signing/entitlement/Info.plist/app.yml files
