# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.23D — listener availability runtime diagnostics proof.

Current checkpoints:
- App code: 2.23C `Polish native call listener availability status` (`bb7ae2557`).
- Listener availability diagnostics proof: 2.23D passed through redacted production status/runtime diagnostics.
- Private native audio dogfood guardrails: 2.23B runbook added at `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- Listener lifecycle hardening: 2.22B `Harden native call listener lifecycle` (`16992e5e6`).
- Private card reducer regression fix: 2.21C `Restore failed native call card retry dismiss mapping` (`8cdae55d4`).
- Backend: 2.14E `Fix fake backend LiveKit dev token grants`.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven state:
- Production native audio call core works through the DEBUG/integration/private product-gated path.
- Private native call card works behind `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- Existing Element Call phone/video buttons remain visible and unchanged.
- Manual private-card actions were proven: Start audio, Accept, Hang up, Decline incoming, Cancel outgoing, Retry, and Dismiss.
- Repeated calls, reverse-direction calls, backend-off recovery, LiveKit-off recovery, stale media failure cleanup, rapid terminal actions, timeout, and relaunch fail-closed behavior are runtime-proven.
- Production Matrix SDK key envelope wrapping is integrated through a narrow provider seam and preserves `OnlyTrustedDevices` policy.
- Local fake backend plus local LiveKit dev server reached `activeAudio` on both iOS clients through private card and runner-backed flows.
- Listener/owner lifecycle is fail-closed with `productionSessionRestorationSupported=false`.
- 2.23C added typed listener/restoration availability status for the private native call card:
  - listener-not-armed
  - ready-to-receive
  - open-room-required
  - restoration-unsupported
- 2.23D runtime diagnostics proof confirmed:
  - Fresh relaunch on an attached room reported listener available, owner unavailable, listener not started, and no active session, mapping to listener-not-armed.
  - Passive status/rendering had no side effects: no Matrix send, no media connect, no LiveKit connect, and no active session.
  - A receiver with room not attached mapped to open-room-required until room reattachment.
  - Explicit listener arm succeeded and reported owner available, listener available/started, room attached, restoration unsupported, no active session, and media failure `none`.
  - Incoming after listener arm worked: A started outgoing, B reached `incomingRinging`, B rejected/declined, A received `directCallReject`, and A/B returned idle with no active session or media failure.
- 2.23D limitations:
  - Manual visual card text was not verified from the shell.
  - The literal leave-DM-to-chat-list/reopen gesture was not performed in that proof.
  - Treat 2.23D as runtime diagnostics proof, not full visual/manual UI proof.
- Card status and runner output remain redacted: no credential values, JWTs, keys, raw Matrix content, raw room IDs, or peer IDs are printed.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, video, or global production activation has been added.

Required dogfood gates:
- `IS_RUNNING_INTEGRATION_TESTS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1` for the current fake-backed proof setup
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=...`

Phase:
2.24A — staging backend and LiveKit hardening plan.

Task:
Inspection/design only. Do not modify code. Do not commit.

Context:
Private native audio calls are conditionally ready for controlled engineering proofing only under strict gates. The iOS private-card path is strongly proven with local fake backend and local LiveKit dev server, but the backend/LiveKit stack is not staging-hardened. The next step is to define what must be true before replacing the local fake setup with a controlled staging equivalent.

Goal:
Design the staging backend and LiveKit hardening plan for private native audio call engineering dogfood, without changing app code or weakening fail-closed activation.

Inspect:
- docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md
- docs/direct-call/STATUS.md
- docs/direct-call/WORKLOG.md
- server/salemx-call-service/README.md
- server/salemx-call-service/salemx_call_service/
- server/salemx-call-service/tests/
- docs/direct-call/LOCAL_BACKEND_SMOKE.md
- Direct-call production token client/configuration code if needed
- LiveKit token DTO/client/transport code if needed

Questions:
1. What backend pieces are still local-fake-only?
2. What is required for a staging token endpoint?
3. What Synapse authentication and room validation behavior must be real before staging dogfood?
4. What shared allocation/session store is needed beyond local process memory?
5. What LiveKit staging deployment requirements remain:
   - TLS/WSS URL
   - API key/secret handling
   - room grants
   - token TTL
   - TURN/network reachability
   - E2EE compatibility
6. What rate limiting, replay protection, and audit logging are required?
7. What redacted diagnostics should staging expose for token/backend/LiveKit failures?
8. What operational runbook is needed for rollback and incident handling?
9. What must remain out of scope for staging dogfood?
10. What is the safest next implementation phase?

Hard constraints:
- Do not modify code.
- Do not commit.
- Do not propose public rollout.
- Do not propose replacing Element Call toolbar buttons.
- No CallKit/push/background incoming yet.
- No video yet.
- Do not weaken `OnlyTrustedDevices`.
- No `AllDevices` fallback.
- No global production activation.
- No raw token/JWT/key/envelope/Matrix content.
- No raw room ID or peer ID in UI/logs/docs.
- No endpoint secrets or LiveKit API secrets in docs.

Expected output:
A. Files inspected.
B. Current backend/LiveKit readiness assessment.
C. Staging backend requirements.
D. Staging LiveKit requirements.
E. Security/privacy guardrails.
F. Operational runbook gaps.
G. Risk matrix.
H. Recommended next implementation phase.
