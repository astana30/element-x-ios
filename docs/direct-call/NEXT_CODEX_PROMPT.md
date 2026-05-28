# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.39Q — post-recovery non-engineering pilot review.

Task:
Inspection/decision review only. Do not modify app/backend code. Do not execute another pilot window. Do not approve broad internal rollout. Do not approve production/public rollout.

Context:
- 2.39K supervised non-engineering pilot window 2 failed but failed closed: A saw `tokenBackendRejected` / `connectingFailed`, B saw `liveKitNetworkFailed`, both returned idle/no active session, no split-brain, and no redaction issue.
- 2.39M added redacted token/backend and LiveKit setup observability and fixed runner simulator identifier redaction.
- 2.39N retried the minimal failed paths. A -> B and B -> A both reached `activeAudio`, token diagnostics were `200` / `issued`, token issued true, LiveKit room pre-create and connect were attempted, LiveKit failure was `none`, media failure was `none`, and final A/B state was idle/no active session. The 2.39K failure did not reproduce.
- 2.39O approved exactly one supervised recovery window.
- 2.39P ran the approved shorter recovery window with the same participant/device cap and no expansion.
- 2.39P passed A -> B, B -> A, and one repeated A -> B call. Every row reached `activeAudio`, then hangup returned A/B idle/no active session.
- Every 2.39P row reported `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, `liveKitRoomPrecreateAttempted=true`, LiveKit connect attempted, `productionLiveKitFailureReason=none`, and `productionMediaFailureReason=none`.
- Element Call fallback controls were visible and unchanged.
- No stop criteria, redaction issue, rollback, or app/backend code change occurred.
- No additional non-engineering pilot window is approved by 2.39P.

Goal:
Decide what the recovery window proves, whether any further supervised non-engineering window may be considered, and what remains blocked before broader internal readiness.

Inspect:
- `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- `docs/direct-call/NEXT_CODEX_PROMPT.md`
- `server/salemx-call-service/docs/STAGING_SMOKE_2026-05-21.md`

Questions:
1. Can 2.39P be considered a clean recovery window?
2. What claims are now valid after 2.39M, 2.39N, and 2.39P?
3. What claims remain invalid?
4. Is another supervised non-engineering window justified, or should execution pause for owner/product review?
5. Should the next workstream be monitoring automation, foreground UX polish, CallKit/push planning, or additional supervised windows?
6. What remains blocked before broad internal rollout?
7. What remains blocked before production/public rollout?

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
B. Recovery window result decision.
C. Valid claims.
D. Invalid claims / still blocked.
E. Remaining risks.
F. Recommendation on additional windows.
G. Recommended next phase.

Suggested next phase if another supervised window is allowed:
2.39R — supervised non-engineering pilot window 3 approval

Suggested next phase if execution should pause:
2.39R — post-pilot hardening plan
