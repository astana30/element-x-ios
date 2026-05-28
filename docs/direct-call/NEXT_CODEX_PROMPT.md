# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.39S — post-window 3 non-engineering pilot review.

Task:
Inspection/decision review only. Do not modify app/backend code. Do not execute another pilot window. Do not approve broad internal rollout. Do not approve production/public rollout. Do not approve unsupervised dogfood or participant/device expansion.

Context:
- 2.39K supervised non-engineering pilot window 2 failed but failed closed: A saw `tokenBackendRejected` / `connectingFailed`, B saw `liveKitNetworkFailed`, both returned idle/no active session, no split-brain, and no redaction issue.
- 2.39M added redacted token/backend and LiveKit setup observability and fixed runner simulator identifier redaction.
- 2.39N retried the minimal failed paths. A -> B and B -> A both reached `activeAudio`, token diagnostics were `200` / `issued`, token issued true, LiveKit room pre-create and connect were attempted, LiveKit failure was `none`, media failure was `none`, and final A/B state was idle/no active session. The 2.39K failure did not reproduce.
- 2.39P ran the approved shorter recovery window with the same participant/device cap and no expansion. A -> B, B -> A, and one repeated A -> B call reached `activeAudio`; every row reported `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, `liveKitRoomPrecreateAttempted=true`, LiveKit connect attempted, `productionLiveKitFailureReason=none`, and `productionMediaFailureReason=none`.
- 2.39Q approved exactly one additional supervised non-engineering pilot window with the same participant/device cap.
- 2.39R ran that approved window. A -> B, B -> A, and one repeated A -> B call reached `activeAudio`; outgoing cancel returned A/B idle/no active session with terminal `cancelled`; timeout returned A/B idle/no active session with A `outgoingTimeout` and B `incomingTimeout`; app-side kill-switch blocked safely after internal rollout was unset; Element Call fallback remained visible and unchanged.
- 2.39R active call rows reported `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, `liveKitRoomPrecreateAttempted=true`, LiveKit connect attempted, `productionLiveKitFailureReason=none`, and `productionMediaFailureReason=none`.
- No `tokenBackendRejected`, no `liveKitNetworkFailed`, no split-brain, no stale active session, no participant confusion, no redaction issue, and no app/backend code change occurred during 2.39R.
- No additional non-engineering pilot window is approved by 2.39R.

Goal:
Decide what the clean 2.39R window proves, what remains blocked, and whether the safest next workstream is another supervised window, foreground UX polish, CallKit/push planning, operational monitoring automation, or broader readiness documentation.

Inspect:
- `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- `docs/direct-call/NEXT_CODEX_PROMPT.md`
- `server/salemx-call-service/docs/STAGING_SMOKE_2026-05-21.md`

Questions:
1. What can be claimed after 2.39R?
2. What claims remain invalid?
3. Should non-engineering pilot execution pause for product/operational hardening?
4. Is any further supervised non-engineering window justified, or should the next workstream be monitoring automation, foreground UX polish, CallKit/push planning, or broader readiness docs?
5. Should participant/device count remain unchanged?
6. What monitoring fields remain mandatory?
7. What remains blocked before broad internal rollout?
8. What remains blocked before production/public rollout?

Hard constraints:
- Do not approve broad internal rollout.
- Do not approve production/public rollout.
- Do not approve unsupervised dogfood.
- Do not expand participant/device count.
- Do not replace Element Call toolbar.
- Do not add CallKit/push/background incoming.
- Do not add missed-call UX or video.
- Do not globally activate production direct calls.
- Token endpoint remains final authority.
- No raw IDs/secrets/tokens in reports.

Expected output:
A. Files inspected.
B. Post-window readiness decision.
C. Valid claims.
D. Invalid claims / still blocked.
E. Remaining risks.
F. Recommended next workstream.
G. Recommended next phase.

Suggested next phase if execution pauses for hardening:
2.39T — post-pilot hardening plan

Suggested next phase if exactly one more supervised window is justified:
2.39T — supervised non-engineering pilot window 4 approval
