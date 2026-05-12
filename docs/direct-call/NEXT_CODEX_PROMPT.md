# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current checkpoint:
e92c60c6a Add env-gated production token backend smoke test

Phase:
2.10M — production E2EE key wrapping seam inspection.

Task:
Inspection only. Do not modify code. Do not commit.

Goal:
Identify how to replace the fail-closed `ProductionDirectCallEncryptionService` skeleton with Matrix-crypto-backed key wrapping for native direct calls without exposing unencrypted key material.

Context:
Completed:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit media proof reached active.
- Production token DTOs/client/transport exist.
- Backend token service skeleton exists.
- Synapse room validation skeleton exists.
- Local backend fake smoke exists.
- App production token client smoke test exists and is disabled by default.

Current blockers:
- Production E2EE Matrix crypto key wrapping is not implemented.
- Production backend is still skeleton/fake mode.
- No production activation, visible UI, CallKit, or push integration exists yet.

Inspect:
1. `ProductionDirectCallEncryptionService`.
2. `DirectCallEncryptionServiceProtocol`.
3. `DirectCallEncryptedKeyExchangePayload`.
4. `DirectCallMediaKeyHandle` and media key store flow.
5. Matrix Rust SDK crypto APIs exposed through the Swift wrapper.
6. Existing room/session/device identity and encrypted event capabilities.
7. Existing direct-call diagnostic encryption service only for comparison, not production reuse.
8. Direct-call signal models and receive/send path.
9. Cleanup paths on hangup, timeout, room leave, and reset.

Questions:
A. Which Matrix crypto API should wrap per-call media keys for a peer/device?
B. Does the app have enough peer device identity context at room-flow scope?
C. What production payload fields are needed for opaque encrypted key exchange?
D. How should generated media keys map to `DirectCallMediaKeyHandle` without exposing unencrypted key material?
E. How should remote key consume/decrypt validate call ID, room, sender, and device metadata?
F. What SDK/wrapper seams are missing, if any?
G. What tests are needed before implementing production E2EE?
H. What is the smallest safe next implementation phase?

Hard constraints:
- Do not modify code.
- Do not commit.
- Do not add visible UI.
- Do not change Element Call route.
- Do not wire CallKit or push.
- Do not activate production direct calls.
- Do not use diagnostic secret/env/token as production.
- Do not place unencrypted key material in Matrix events.
- Do not log credentials, key material, raw Matrix content, or raw encrypted payload values.
- Do not expose broad raw APIs on RoomProxyProtocol or TimelineProxyProtocol.

Report:
1. Files inspected.
2. Existing crypto/key capabilities.
3. Missing SDK/wrapper seams.
4. Recommended production key wrapping design.
5. Required app service/protocol changes.
6. Cleanup/lifecycle design.
7. Tests needed.
8. Risks/blockers.
9. Recommended next implementation phase.
