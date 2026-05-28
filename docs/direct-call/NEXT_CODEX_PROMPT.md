# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.39W — foreground limitation UX no-activation proof.

Task:
Run or record a no-activation proof for the foreground/open-chat limitation UX polish added in 2.39V. Do not modify app/backend code unless a real runtime bug is found and explicitly approved. Do not execute another non-engineering pilot window. Do not approve additional windows, participant/device expansion, broad internal rollout, production/public rollout, or unsupervised dogfood.

Context:
- 2.39V implemented foreground/open-chat limitation UX polish for the private native audio card.
- The card now states native audio works only while the encrypted direct chat stays open, there are no background incoming calls, no system incoming call screen, no missed-call alerts yet, and Element Call remains fallback.
- Listener/open-room, trust, eligibility, service unavailable, timeout, cancelled, and safely failed states remain non-technical.
- This was UX/copy polish only. It did not change Start/Accept eligibility, activation gates, Matrix send behavior, token requests, media/LiveKit setup, private dogfood, internal pilot activation, Element Call route, CallKit, push/background incoming, missed-call UX, video, session restoration, broad rollout, or production/public rollout.

Goal:
Prove that the UX polish is visible and safe without activating or changing native audio behavior.

Proof checklist:
1. Launch with product UI/status gates needed to render the private native audio card.
2. Confirm the foreground/open-chat limitation copy is visible in the card for an available state and an unavailable/listener state.
3. Confirm accessibility/status text contains only safe user-facing wording.
4. Confirm UI/accessibility output does not include backend, token, LiveKit, request/response details, raw room IDs, raw user IDs, raw device IDs, tokens, JWTs, secrets, LiveKit room names, or simulator UDIDs.
5. Confirm rendering/status refresh does not send Matrix events, request a participant token, allocate/pre-create a room, connect media, connect LiveKit, or create an active session.
6. Confirm Start/Accept availability remains controlled by the existing private dogfood/internal pilot gates and is unchanged by copy rendering.
7. Confirm Element Call phone/video fallback controls remain visible and unchanged.

Optional positive sanity check:
- If the approved engineering/internal pilot proof environment is already running, one A -> B call may be used only to confirm copy did not break the existing proven path. This is not a new non-engineering pilot window.

Report:
A. Files/build inspected.
B. Copy visibility result.
C. Redaction result.
D. No-activation/side-effect result.
E. Element Call fallback result.
F. Any regression.
G. Whether code changed.
H. Recommended next phase.

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
- No backend/token/LiveKit wording in UI/accessibility output.

Expected output:
If passed with no code changes, create a docs-only proof commit.

Suggested commit:
Record foreground limitation UX proof
