# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Next task - 2.47A17 prove PushKit callback owner after APNs accepted

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
- The latest server-side real invite/APNs correlation was green:
  - `real_non_dev_invite_used=true`
  - `dev_invite_used=false`
  - `background_apns_push_result=sandbox_success`
  - upload/invite store key matched
- The latest iPhone SalemX VoIP receipt proof did not update:
  - `proof_source=voip_push_receipt`
  - `physical_voip_push_received=false`
  - `pushkit_callback_invoked=false`
  - `pushkit_payload_kind=none`
  - `blocked_reason=voip_push_not_received`
- 2.47A17 added a DEBUG-only detector in the startup `ElementCallService` PushKit delegate. If that app-wide registry receives a SalemX payload, the dedicated VoIP proof records:
  - `element_call_pushkit_callback_invoked=true`
  - `element_call_salemx_payload_observed=true`
  - `element_call_payload_kind=real_invite_controlled`
  - `blocked_reason=element_call_pushkit_registry_intercepted_salemx_payload`
- Media credentials, media connect, LiveKit join, Matrix event emission, and full call flow stayed false.

Goal:
- run one controlled real non-dev invite/APNs attempt to determine which PushKit owner receives the accepted sandbox push.
- do not move back to CallKit/media until the physical PushKit callback owner is proven.

Investigate:
- whether the existing startup `ElementCallService` `.voIP` registry receives the SalemX APNs payload.
- whether the manual SalemX debug PushKit registry receives it instead.
- whether neither local proof updates despite sandbox_success, which would keep the blocker at APNs accepted but physical callback not observed.
- keep proof output redacted only.

Safety:
- do not use `dev/invite`
- do not send production APNs
- do not repeat APNs pushes outside one planned physical attempt
- do not request real media credentials, connect media, join LiveKit, emit Matrix events, or start full direct-call flow
- do not print, log, document, or commit raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- do not touch project/signing/entitlement/Info.plist/app.yml files
