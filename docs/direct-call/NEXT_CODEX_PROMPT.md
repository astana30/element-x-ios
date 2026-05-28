# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.39O — supervised pilot window 2 recovery approval review.

Task:
Inspection/decision review only. Do not modify app/backend code. Do not execute a pilot window in this phase. Do not approve broad internal rollout. Do not approve production/public rollout.

Context:
- 2.39K supervised non-engineering pilot window 2 did not pass. A saw `tokenBackendRejected` / `connectingFailed`; B saw `liveKitNetworkFailed`; both failed closed to idle/no active session; no split-brain or redaction issue occurred.
- 2.39M added redacted token/backend and LiveKit setup observability and fixed runner simulator-identifier redaction.
- 2.39M positive proof reached `activeAudio` and returned idle with safe token diagnostics `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, `liveKitRoomPrecreateAttempted=true`, LiveKit connect attempted, LiveKit failure `none`, and media failure `none`.
- 2.39M controlled negative token proof returned safe diagnostics only: `tokenStatus=401`, `tokenErrcode=M_UNKNOWN_TOKEN`, `tokenReason=authRejected`, `tokenIssued=false`.
- 2.39N retried only the minimal failed paths, not a new pilot window.
- 2.39N A -> B and B -> A both reached `activeAudio`, then hangup returned A/B idle/no active session. Token diagnostics were `200` / `issued`, token issued true, LiveKit room pre-create attempted, LiveKit connect attempted, LiveKit failure `none`, and media failure `none`.
- The original window 2 failure did not reproduce. Root cause remains unproven and is currently classified as transient or environment-sensitive unless it reappears with safe fields.
- Non-engineering pilot execution remains paused pending this approval review.

Goal:
Decide whether exactly one supervised window 2 recovery attempt may be run, or whether non-engineering pilot execution must remain paused.

Inspect:
- `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- `docs/direct-call/NEXT_CODEX_PROMPT.md`
- `server/salemx-call-service/docs/STAGING_SMOKE_2026-05-21.md`

Decision criteria:
- The retry diagnostics must be clean and redacted.
- A/B must be idle/no active session at the end of retry.
- Token/LiveKit classification must be sufficient to diagnose future repeats.
- No code change must be required before a recovery attempt.
- Owners, participant labels, opt-in, rollback operator, redaction reviewer, kill switch, and fresh preflight must still be available.

If approved:
- Approve exactly one supervised window 2 recovery attempt.
- Same participant/device cap as 2.39I/2.39K.
- Staging only.
- Foreground/open encrypted direct 1:1 room only.
- Private native audio card only.
- Element Call fallback visible and unchanged.
- No CallKit, push/background incoming, missed-call UX, video, broad rollout, production/public, or global activation.
- Redacted reporting only.

If blocked:
- Keep non-engineering pilot execution paused.
- List missing blockers.

Expected output:
A. Files inspected.
B. Readiness decision: approve exactly one recovery window / remain paused.
C. Valid claims from 2.39M/2.39N.
D. Remaining risks.
E. Constraints if approved.
F. Stop criteria.
G. Rollback checklist.
H. Recommended next phase.

Suggested next phase if approved:
2.39P — supervised window 2 recovery attempt

Suggested next phase if blocked:
2.39P — window 2 recovery blocker remediation
