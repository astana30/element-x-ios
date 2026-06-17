# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task - 2.47A14 isolate why background PushKit CallKit first action is End

Latest completed state:
- 2.47A13 split proof storage so local CallKit-only smoke no longer overwrites real VoIP PushKit receipt proof.
- Local CallKit-only proof writes `Documents/salemx-local-callkit-only-proof.txt` and passes:
  - `proof_source=local_callkit_only`
  - `local_callkit_only_report_result=reported`
  - `local_callkit_only_first_action_kind=answer`
  - `local_callkit_only_answer_action_delivered=true`
  - `local_callkit_only_end_action_delivered=false`
  - `blocked_reason=none`
- VoIP receipt proof writes `Documents/salemx-voip-push-receipt-proof.txt` and remains separated from the local proof:
  - `proof_source=voip_push_receipt`
  - `pushkit_payload_kind=real_invite_controlled`
  - `pushkit_completion_answerable_window_requested=true`
  - `pushkit_completion_answerable_window_result=first_action_observed`
  - `callkit_first_action_kind=end`
  - `callkit_answer_action_delivered=false`
  - `blocked_reason=background_callkit_end_before_operator_action`
- PushKit upload smoke remains separate at `Documents/salemx-pushkit-token-upload-smoke-proof.txt`.
- Media credentials, media connect, LiveKit join, Matrix event emission, and full call flow stayed false.

Goal:
- determine why the background PushKit CallKit surface produces `CXEndCallAction` as the first action even though local CallKit-only Answer works, proof files are separated, the answerable window observes a first action, and local code does not request media, LiveKit, Matrix events, or full call flow.
- do not move to media until the background path records `callkit_first_action_kind=answer`.

Safety:
- do not use `dev/invite`
- do not send production APNs
- do not repeat APNs pushes outside one planned physical attempt
- do not request real media credentials, connect media, join LiveKit, emit Matrix events, or start full direct-call flow
- do not print, log, document, or commit raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- do not touch project/signing/entitlement/Info.plist/app.yml files
