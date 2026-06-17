# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task - 2.47A12 controlled PushKit completion delay / answerable window

Latest completed state:
- 2.47A10 narrowed the remaining blocker to the background PushKit/CallKit surface lifecycle.
- Local CallKit-only proof still passes without APNs or PushKit:
  - `local_callkit_only_first_action_kind=answer`
  - `local_callkit_only_answer_action_delivered=true`
  - `local_callkit_only_end_action_delivered=false`
  - `blocked_reason=none`
- One authenticated real non-dev invite/APNs attempt still auto-ended before an operator-observed answerable UI surface:
  - `background_apns_push_result=sandbox_success`
  - `pushkit_payload_kind=real_invite_controlled`
  - `callkit_report_result=reported`
  - `callkit_report_completion_observed=true`
  - `pushkit_completion_called=true`
  - `pushkit_completion_after_report_ms_bucket=<100ms`
  - `callkit_end_after_pushkit_completion_ms_bucket=>2000ms`
  - `app_state_at_pushkit_receipt=foreground`
  - `app_state_at_report_completion=foreground`
  - `app_state_at_first_callkit_action=foreground`
  - valid generic audio-only CallKit update/config proof
  - provider/delegate/active UUID retained
  - provider reset and audio activation/deactivation were not observed before first action
  - local End request, provider invalidation, report-ended, and controlled timeout before Answer were false
  - `callkit_ui_surface_observed_by_operator=false`
  - `callkit_first_action_kind=end`
  - `blocked_reason=background_callkit_end_before_operator_action`

Hypothesis:
- PushKit completion may be called too soon after `reportNewIncomingCall`, causing iOS to end the background CallKit surface before an answerable operator window exists.

Goal:
- test a controlled, bounded DEBUG-only PushKit completion delay / answerable-window proof
- determine whether delaying PushKit completion long enough for an answerable window changes the first action from `end` to `answer`
- do not move to media until the background path records `callkit_first_action_kind=answer`

Safety:
- do not use `dev/invite`
- do not send production APNs
- do not repeat APNs pushes outside one planned physical attempt
- do not request real media credentials, connect media, join LiveKit, emit Matrix events, or start full direct-call flow
- do not print, log, document, or commit raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- do not touch project/signing/entitlement/Info.plist/app.yml files
