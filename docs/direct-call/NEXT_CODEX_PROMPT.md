# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task — 2.46A2 physical real-invite Answer retry after auth refresh

Continue after 2.46A1 added controlled synthetic CallKit cleanup after Answer, but physical retry stopped before APNs because the receiver app auth was unavailable.

Latest redacted result:
- root cause/fix: stale controlled synthetic CallKit calls were not ended/cleared after Answer; 2.46A1 now ends and clears only the DEBUG controlled synthetic call and records redacted cleanup status
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
