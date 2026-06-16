# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task — 2.45C2 authenticated CallKit answer proof retry

Continue after 2.45C1.

Latest state:
- DEBUG-only PushKit completion ordering fix exists.
- Controlled sandbox PushKit proof records the CallKit report result before recording/calling PushKit completion.
- Targeted DirectCall tests passed with 37 tests.
- SwiftFormat passed.
- SwiftLint passed on changed files with 0 violations.
- Fresh physical Debug build installed successfully.
- Route safety remained:
  - `dev/invite=404`
  - unauthenticated non-dev invite `401`
  - unauthenticated stream `401`
  - unauthenticated token registration `401`
  - unauthenticated APNs send control `401`

Current blocker:
- physical PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- APNs dry-run was not run
- real sandbox APNs send was not attempted
- CallKit answer action was not physically observed

Goal:
Restore/confirm an authenticated app session on the physical iPhone, rerun physical PushKit upload smoke, then run APNs dry-run. If dry-run is green, run exactly one real sandbox VoIP push and tap Accept once in CallKit.

Expected proof:

```text
callkit_report_requested=true
callkit_report_result=reported
pushkit_completion_called=true
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
app_activation_observed=true
media_credentials_requested=false
media_connect_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Hard constraints:
- do not print, log, document, or commit raw PushKit/APNs tokens, APNs key material, JWTs, authorization headers, Matrix access tokens, request payloads, private logs, raw user IDs, raw device IDs, room IDs, call handles, or secret-bearing URLs
- do not attempt production APNs
- do not send repeated pushes
- do not wire media
- do not emit Matrix events
- do not start full direct-call flow
- do not touch project/signing/entitlement/Info.plist/app.yml files
