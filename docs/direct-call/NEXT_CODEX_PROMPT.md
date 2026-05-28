# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.39U — post-pilot hardening workstream selection.

Task:
Inspection/decision review only. Do not modify app/backend code. Do not execute another pilot window. Do not approve additional non-engineering windows, participant/device expansion, broad internal rollout, production/public rollout, or unsupervised dogfood.

Context:
- 2.39I, 2.39P, and 2.39R supervised non-engineering foreground-only windows passed under strict staging constraints.
- 2.39K failed closed with `tokenBackendRejected` / `liveKitNetworkFailed`; after 2.39M redacted token/LiveKit observability, the failure did not reproduce in 2.39N, 2.39P, or 2.39R.
- 2.39R passed A -> B, B -> A, one repeated A -> B, outgoing cancel, timeout, app-side kill-switch, final idle/no active session, and Element Call fallback checks.
- 2.39R token diagnostics were clean: `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`.
- 2.39R LiveKit/media diagnostics were clean: `liveKitRoomPrecreateAttempted=true`, `productionLiveKitFailureReason=none`, and `productionMediaFailureReason=none`.
- 2.39S review paused additional non-engineering pilot windows. Another same-cap supervised window has diminishing value compared with product and operational hardening.
- 2.39T recorded the post-pilot hardening plan.

Hardening areas recorded in 2.39T:
- foreground limitation UX;
- in-card state polish;
- redacted monitoring baseline;
- operational monitoring automation;
- support/rollback procedure;
- incident reporting and secret rotation triggers;
- future CallKit/push/background incoming planning readiness.

Current blockers:
- foreground/open-room-only limitation;
- no CallKit;
- no push/background incoming;
- no missed-call UX;
- no video;
- no session restoration;
- monitoring still runner/report based;
- support/rollback process is not product-grade;
- no production/public rollout governance.

Goal:
Choose the next implementation workstream after the post-pilot hardening plan.

Options:
A. foreground UX polish implementation;
B. operational monitoring automation;
C. CallKit/push/background incoming planning;
D. audio controls polish;
E. defer implementation and prepare another readiness review.

Inspect:
- `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- `docs/direct-call/NEXT_CODEX_PROMPT.md`
- `server/salemx-call-service/docs/STAGING_SMOKE_2026-05-21.md`

Questions:
1. Which workstream should be implemented first?
2. What is the smallest safe implementation slice?
3. What must stay blocked?
4. What tests and runtime proof are required?
5. Should any new pilot window be considered before hardening? Default answer should be no unless fully justified.
6. What is the recommended next phase?

Hard constraints:
- Do not approve additional non-engineering pilot windows.
- Do not approve participant/device expansion.
- Do not approve broad internal rollout.
- Do not approve production/public rollout.
- Do not approve unsupervised dogfood.
- Do not replace Element Call toolbar.
- Do not add CallKit/push/background incoming implementation in this phase.
- Do not add video.
- Do not globally activate production direct calls.
- Token endpoint remains final authority.
- No raw IDs/secrets/tokens in reports.

Expected output:
A. Files inspected.
B. Workstream decision.
C. Smallest safe implementation slice.
D. Must-remain-blocked items.
E. Required tests.
F. Required runtime proof.
G. Recommended next phase.

Suggested next phase:
2.39V — foreground limitation UX polish
