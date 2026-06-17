# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task — 2.47A10 background PushKit CallKit surface timing isolation

Latest completed state:
- 2.47A9 added a DEBUG-only local CallKit-only answerability smoke.
- Local CallKit-only proof passed without APNs or PushKit:
  - `local_callkit_only_report_result=reported`
  - `local_callkit_only_first_action_kind=answer`
  - `local_callkit_only_answer_action_delivered=true`
  - `local_callkit_only_end_action_delivered=false`
  - `blocked_reason=none`
- One authenticated real non-dev invite/APNs background comparison still delivered End first:
  - `pushkit_payload_kind=real_invite_controlled`
  - `callkit_report_result=reported`
  - `callkit_report_completion_observed=true`
  - provider/delegate/active UUID retained
  - `callkit_first_action_kind=end`
  - `callkit_first_action_after_report_ms_bucket=>2000ms`
  - local End request, provider invalidation, report-ended, and controlled timeout before Answer were false
  - `blocked_reason=system_or_user_end_before_answer`

Goal:
- determine why the same controlled CallKit provider/config/action path is answerable locally but End-first when invoked from the background PushKit real-invite path
- do not move to media until the background path records `callkit_first_action_kind=answer`

Inspect first:
- app lifecycle/background state at report completion and first action
- whether the background path needs an explicit app activation/foreground observation before operator Answer can be tapped
- whether the incoming UI surface differs between local DEBUG CallKit-only and background PushKit report
- whether CallKit audio/session activation is absent only on the background path
- whether operator-intent marker should be set immediately before the background attempt to distinguish UI absence from delayed Answer

Safety:
- do not use `dev/invite`
- do not send production APNs
- do not repeat APNs pushes
- do not request real media credentials, connect media, join LiveKit, emit Matrix events, or start full direct-call flow
- do not print, log, document, or commit raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- do not touch project/signing/entitlement/Info.plist/app.yml files
