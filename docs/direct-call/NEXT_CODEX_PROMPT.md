# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task — 2.47A8 keep CallKit incoming UI answerable past first-action window

Latest completed state:
- 2.47A6 added redacted CallKit timing/config diagnostics and narrowed the physical blocker
- 2.47A7 added redacted operator-intent fields and Internal diagnostics controls for Answer-vs-End validation
- one authenticated real non-dev invite/APNs attempt returned `background_apns_push_result=sandbox_success`; `dev/invite` was not used
- dedicated VoIP receipt proof reached `callkit_report_result=reported`, `callkit_report_completion_observed=true`, `callkit_provider_retained_for_answer=true`, `callkit_delegate_retained_for_answer=true`, and `callkit_active_call_uuid_retained=true`
- first delivered CallKit action was `end`, not `answer`
- latest `callkit_first_action_after_report_ms_bucket=500-2000ms`
- operator UI/Answer intent was not marked: `callkit_ui_surface_observed_by_operator=false`, `callkit_operator_intended_action=unknown`, and `callkit_operator_action_timing_bucket=unknown`
- local app End request, provider invalidation, report-ended, and controlled timeout before Answer were all false
- current blocker: `system_end_before_answer_window`
- media credential request, media connection, LiveKit join, Matrix events, and full direct-call flow remain unwired
- new proof fields for the next physical attempt: `callkit_ui_surface_observed_by_operator`, `callkit_operator_intended_action`, and `callkit_operator_action_timing_bucket`

Goal:
- investigate why CallKit produces `CXEndCallAction` within 500-2000ms before operator intent can be marked
- keep the CallKit incoming UI answerable long enough to deliver `CXAnswerCallAction`
- do not move to media until `CXAnswerCallAction` is actually delivered and recorded

Next investigation:
- inspect whether the controlled incoming CallKit call is missing configuration required to stay answerable beyond the first-action window
- inspect app lifecycle/background state around report completion and the 500-2000ms End
- inspect whether CallKit is expiring the incoming call because no UI/action state is kept active enough
- do not send another APNs push until a concrete validation plan or minimal fix is ready

Safety:
- do not print, log, document, or commit raw PushKit/APNs tokens, APNs key material, JWTs, authorization headers, Matrix access tokens, request payloads, private logs, raw user IDs, raw device IDs, room IDs, call handles, or secret-bearing URLs
- do not attempt production APNs
- do not send repeated pushes
- do not use `dev/invite`
- do not request real media credentials, connect media, join LiveKit, emit Matrix events, or start full direct-call flow
- do not touch project/signing/entitlement/Info.plist/app.yml files
