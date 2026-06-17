# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task — 2.47A7 controlled CallKit Answer-vs-End interaction validation

Latest completed state:
- 2.47A6 added redacted CallKit timing/config diagnostics and narrowed the physical blocker
- one authenticated real non-dev invite/APNs attempt returned `background_apns_push_result=sandbox_success`; `dev/invite` was not used
- dedicated VoIP receipt proof reached `callkit_report_result=reported`, `callkit_report_completion_observed=true`, `callkit_provider_retained_for_answer=true`, `callkit_delegate_retained_for_answer=true`, and `callkit_active_call_uuid_retained=true`
- first delivered CallKit action was `end`, not `answer`
- `callkit_first_action_after_report_ms_bucket=>2000ms`
- local app End request, provider invalidation, report-ended, and controlled timeout before Answer were all false
- current blocker: `system_or_user_end_before_answer`
- media credential request, media connection, LiveKit join, Matrix events, and full direct-call flow remain unwired

Goal:
- distinguish whether End-before-Answer is caused by user/UI interaction path, CallKit system behavior, expired/invalid incoming UI state, wrong CallKit surface/action being tapped, or timing between report and operator Answer
- do not move to media until `CXAnswerCallAction` is actually delivered and recorded

Safety:
- do not print, log, document, or commit raw PushKit/APNs tokens, APNs key material, JWTs, authorization headers, Matrix access tokens, request payloads, private logs, raw user IDs, raw device IDs, room IDs, call handles, or secret-bearing URLs
- do not attempt production APNs
- do not send repeated pushes
- do not use `dev/invite`
- do not request real media credentials, connect media, join LiveKit, emit Matrix events, or start full direct-call flow
- do not touch project/signing/entitlement/Info.plist/app.yml files
