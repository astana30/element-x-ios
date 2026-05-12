# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

SDK workspace:
/Users/aibattt/salemx-sdk-work/matrix-rust-sdk

Wrapper workspace:
/Users/aibattt/salemx-sdk-work/matrix-rust-components-swift

Branch:
salemx-native-direct-calls

Current phase:
After 2.10N — production E2EE app key-wrapping seam skeleton.

Phase:
2.10O — Matrix SDK narrow direct-call key wrapping seam prototype.

Task:
Prototype or design the narrow Matrix SDK/wrapper seam needed to replace the app-side fail-closed `DirectCallMediaKeyWrappingProtocol` with Matrix-crypto-backed production key wrapping.
Do not activate production direct calls.
Do not modify visible UI.
Do not modify the Element Call route.
Do not wire CallKit or push.

Context:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit media proof reached active.
- Production backend token DTO/client/transport/config seams exist.
- Backend token service skeleton and Synapse room validation skeleton exist.
- App-side production key-wrapping seams now exist:
  - `DirectCallMediaKeyWrappingProtocol`
  - `DirectCallMediaKeyWrapRequest`
  - `DirectCallMediaKeyUnwrapRequest`
  - `DirectCallWrappedMediaKeyEnvelope`
  - `FailClosedDirectCallMediaKeyWrapper`
  - `ProductionDirectCallEncryptionService` with injectable wrapper and shared `DirectCallLiveKitMediaKeyStore`
  - `NativeDirectCallProductionDependenciesFactory` injection hooks for future wrapper/store/user/device metadata
- The app seam remains fail-closed by default.
- Diagnostic encryption remains DEBUG/integration-only and must not become production.
- Backend issues LiveKit transport credentials only and must never know raw media keys.

Goal:
Find the smallest SDK/wrapper seam that can wrap and unwrap per-call media key material for a peer in an encrypted 1:1 room, returning only an opaque envelope suitable for the existing direct-call Matrix signalling payload.

Inspect:
1. `/Users/aibattt/salemx-sdk-work/matrix-rust-sdk`
   - room crypto APIs
   - device/user identity APIs
   - to-device encryption APIs
   - custom encrypted event or secret-send helpers
   - existing FFI patterns for crypto-bound operations
2. `/Users/aibattt/salemx-sdk-work/matrix-rust-components-swift`
   - generated Swift binding patterns
   - binary artifact workflow
3. App-side seams:
   - `DirectCallEncryptionDesign.swift`
   - `DirectCallModels.swift`
   - `DirectCallMediaEngineFactory.swift`
   - `DirectCallLiveKitMediaKeyStore`
   - `ProductionDirectCallEncryptionService`

Questions:
A. Is there an existing Matrix Rust SDK primitive that can encrypt opaque payloads to all eligible devices for a room peer?
B. Is there an existing primitive that can decrypt/verify such an opaque direct-call media-key envelope?
C. Should the SDK seam operate through room encryption, to-device encryption, Megolm/Olm helpers, or a purpose-built direct-call secret envelope?
D. Can the seam avoid exposing raw Matrix event JSON and avoid broad raw room/timeline APIs?
E. What metadata should the SDK verify before unwrap:
   - room ID
   - call ID
   - sender user ID
   - recipient user ID
   - sender device ID
   - key ID
   - expiry
   - intent/audio
F. How should multi-device peers be handled in the opaque envelope?
G. What trust policy should the prototype enforce initially?
H. Does the app-side `DirectCallEncryptionServiceProtocol` need to become async for a real SDK-backed wrapper?
I. What Rust tests and Swift wrapper tests are needed?
J. What app tests should change once the real wrapper is available?

Preferred seam shape:
- A narrow Rust/FFI API with direct-call-specific naming, for example:
  - `wrapDirectCallMediaKey(...) -> DirectCallMediaKeyEnvelope`
  - `unwrapDirectCallMediaKeyEnvelope(...) -> DirectCallMediaKey`
- Inputs include room/call/sender/recipient/device/intent/expiry/key metadata.
- Outputs include only opaque envelope bytes/string and safe metadata.
- No raw Matrix event JSON.
- No broad raw send/receive APIs.
- No LiveKit tokens or URLs.
- No raw media key in logs/descriptions.

Hard constraints:
- Do not use diagnostic encryption secret/env as production.
- Do not put raw media key material in Matrix event content.
- Do not log unencrypted media key material.
- Do not expose raw Matrix event JSON.
- Do not use `debugInfo`, `originalJSON`, or `originalJson`.
- Do not put LiveKit token, URL, or API secret in Matrix signalling.
- Do not add visible UI.
- Do not change Element Call route.
- Do not activate production feature flags.
- Do not wire CallKit or push.
- Do not broaden `RoomProxyProtocol` or `TimelineProxyProtocol` raw APIs.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Expected output:
1. Files inspected.
2. Existing SDK crypto capability summary.
3. Recommended SDK/FFI seam shape.
4. Whether a prototype implementation is feasible now.
5. Required Rust tests.
6. Required Swift wrapper tests.
7. Required app integration changes for the follow-up phase.
8. Risks/blockers.
9. Recommended next implementation phase.
10. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
