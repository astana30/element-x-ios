# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task — 2.45C1 CallKit answer action proof retry

Continue after 2.45C.

Latest state:
- DEBUG-only CallKit answer-action proof code exists.
- `CXAnswerCallAction` is fulfilled promptly and can record:
  - `callkit_answer_action_received=true`
  - `callkit_answer_action_fulfilled=true`
  - `app_activation_observed=true`
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
- physical PushKit upload smoke returned `pushkit_token_upload_http_failure`
- authenticated APNs dry-run returned HTTP 401
- real sandbox APNs send was skipped
- CallKit answer action was not physically observed

Goal:
Recover the matching authenticated staging session/token path, rerun physical PushKit upload smoke, then run APNs dry-run. If dry-run is green, run exactly one real sandbox VoIP push and tap Accept once in CallKit. Prove:

```text
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
