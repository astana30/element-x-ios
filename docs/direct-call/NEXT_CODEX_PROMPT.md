# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task - 2.47A16 isolate PushKit callback/report lifecycle

Latest completed state:
- Proof files are separated:
  - `Documents/salemx-voip-push-receipt-proof.txt`
  - `Documents/salemx-local-callkit-only-proof.txt`
  - `Documents/salemx-local-background-callkit-proof.txt`
  - `Documents/salemx-pushkit-token-upload-smoke-proof.txt`
- Store-key correlation is green: upload and invite lookup keys match; records are fresh, development, and hex.
- Local foreground CallKit-only proof delivers Answer.
- Local background scheduled CallKit-only proof delivers Answer:
  - `app_state_at_report=background`
  - `local_background_report_result=reported`
  - `local_background_first_action_kind=answer`
  - `local_background_answer_action_delivered=true`
  - `local_background_end_action_delivered=false`
  - `blocked_reason=none`
- Background real-invite PushKit proof still reports End as the first action:
  - `proof_source=voip_push_receipt`
  - `pushkit_payload_kind=real_invite_controlled`
  - `pushkit_completion_answerable_window_requested=true`
  - `pushkit_completion_answerable_window_result=first_action_observed`
  - `callkit_first_action_kind=end`
  - `callkit_answer_action_delivered=false`
  - `blocked_reason=background_callkit_end_before_operator_action`
- Media credentials, media connect, LiveKit join, Matrix event emission, and full call flow stayed false.

Goal:
- determine why reporting from the PushKit callback produces `CXEndCallAction` first while the same local CallKit path is answerable from both foreground and background app state.
- do not move to media until the background PushKit path records `callkit_first_action_kind=answer`.

Investigate:
- exact PushKit callback lifecycle around `reportNewIncomingCall` and completion.
- whether reporting inside the PushKit callback differs from the scheduled local background report.
- whether deferring report submission out of the PushKit callback, while still safely completing PushKit, changes the first CallKit action.
- provider/delegate/harness ownership across PushKit callback return.
- app state, queue, generation, and proof-writer differences between local background and VoIP receipt paths.
- any system-driven End signal that only appears for reports created inside the PushKit callback.

Safety:
- do not use `dev/invite`
- do not send production APNs
- do not repeat APNs pushes outside one planned physical attempt
- do not request real media credentials, connect media, join LiveKit, emit Matrix events, or start full direct-call flow
- do not print, log, document, or commit raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- do not touch project/signing/entitlement/Info.plist/app.yml files
