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
After 2.10O — Matrix SDK narrow direct-call key wrapping seam inspection.

Current checkpoint:
407adede3 `Add production direct-call key wrapping seams`

Phase:
2.10P — SDK direct-call media key envelope prototype.

Task:
Implement a local Matrix Rust SDK prototype for a narrow direct-call media-key envelope seam, then generate Swift bindings only if the Rust prototype and tests pass.
Do not publish an artifact or update the app pin in this phase unless explicitly requested.
Do not activate production direct calls.
Do not modify visible UI, Element Call route, CallKit, push, or production feature flags.

Context:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit media proof reached active.
- App-side production key wrapping seams exist and remain fail-closed:
  - `DirectCallMediaKeyWrappingProtocol`
  - `DirectCallMediaKeyWrapRequest`
  - `DirectCallMediaKeyUnwrapRequest`
  - `DirectCallWrappedMediaKeyEnvelope`
  - `FailClosedDirectCallMediaKeyWrapper`
  - `ProductionDirectCallEncryptionService` with injectable wrapper and shared `DirectCallLiveKitMediaKeyStore`
- 2.10O inspection found:
  - Rust crypto can encrypt arbitrary custom to-device content for devices using Olm.
  - `OlmMachine::encrypt_content_for_devices` can produce encrypted to-device requests for multiple devices with trust-aware filtering.
  - The high-level SDK has `encrypt_and_send_raw_to_device`, used by widget support, but it sends immediately and is not exposed through Swift FFI.
  - Current Swift FFI exposes identity/trust status but not a direct-call-specific wrap/unwrap envelope API.
  - The recommended transport is still the existing direct-call room signal carrying only an SDK-produced opaque per-device envelope.

Goal:
Prototype a narrow SDK/FFI seam that can:
- wrap per-call media key material for eligible devices of a peer in an encrypted 1:1 room;
- return an opaque envelope suitable for the existing direct-call room signal payload;
- unwrap that envelope only on an intended recipient device;
- validate direct-call metadata before returning unwrapped media key material to the app service layer.

Preferred Rust/FFI API shape:
- Add direct-call-specific records, for example:
  - `DirectCallMediaKeyWrapInfo`
  - `DirectCallMediaKeyUnwrapInfo`
  - `DirectCallMediaKeyEnvelope`
  - `DirectCallMediaKeyUnwrapResult`
  - `DirectCallMediaKeyEnvelopeError`
- Add narrow methods on an appropriate SDK/FFI object, likely room- or encryption-scoped:
  - `wrap_direct_call_media_key(...) -> DirectCallMediaKeyEnvelope`
  - `unwrap_direct_call_media_key_envelope(...) -> DirectCallMediaKeyUnwrapResult`
- Inputs should include room ID, call ID, sender user ID, recipient user ID, optional sender/recipient device ID, intent, expiry, key ID, and media key bytes/string.
- Outputs should expose only safe metadata plus opaque encrypted envelope data.
- The app should not receive Matrix event JSON, recipient device maps, Olm internals, or broad raw APIs.

Recommended implementation direction:
- Use existing Matrix Rust SDK custom encrypted to-device primitives internally.
- For wrapping, collect eligible peer devices, enforce the selected trust policy, encrypt a direct-call-specific plaintext object for each recipient device, and package the encrypted per-device contents into one opaque room-signal envelope.
- For unwrapping, select the current device's entry from the opaque envelope, decrypt it through the SDK crypto machine, validate all direct-call metadata, and return only the media key and key ID to the wrapper layer.
- Keep room transport separate: the caller still sends the direct-call room signal through the existing Matrix signalling path.
- Do not introduce a generic custom to-device or raw JSON API for the app.

Trust policy for prototype:
- Start fail-closed by default.
- Prefer trusted/cross-signed devices only if the SDK can enforce this cleanly.
- If product policy is still unclear, expose a narrow enum with a conservative default and tests for untrusted/unsigned device rejection.
- Surface failures as redacted enum cases only.

Inspect before editing:
1. SDK Rust:
   - `crates/matrix-sdk-crypto/src/identities/device.rs`
   - `crates/matrix-sdk-crypto/src/machine/mod.rs`
   - `crates/matrix-sdk-crypto/src/machine/tests/send_encrypted_to_device.rs`
   - `crates/matrix-sdk/src/encryption/mod.rs`
   - `crates/matrix-sdk/src/widget/matrix.rs`
   - `bindings/matrix-sdk-ffi/src/encryption.rs`
   - `bindings/matrix-sdk-ffi/src/room/mod.rs`
2. Swift wrapper:
   - generated `matrix_sdk_ffi.swift`
   - package/artifact workflow, but do not publish yet.
3. App reference only:
   - `DirectCallEncryptionDesign.swift`
   - `DirectCallMediaEngineFactory.swift`
   - `DirectCallLiveKitMediaKeyStore`

Hard constraints:
- Do not put unencrypted media key material in Matrix event content.
- Do not log media key material.
- Do not expose Matrix event JSON to the app.
- Do not use `debugInfo`, `originalJSON`, or `originalJson`.
- Do not put LiveKit token, URL, or API secret in Matrix signalling.
- Do not expose broad raw APIs on app room or timeline protocols.
- Do not modify visible UI.
- Do not change Element Call route.
- Do not activate production feature flags.
- Do not wire CallKit or push.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Rust tests to add:
- wrapping succeeds for an encrypted 1:1 room with eligible peer device(s).
- envelope contains no plaintext media key material.
- unwrapping succeeds on the intended recipient device.
- unwrapping fails on a non-recipient device.
- metadata mismatch fails closed: room ID, call ID, sender, recipient, intent, key ID, expiry.
- untrusted/unsigned device policy fails closed for the conservative policy.
- multi-device peer envelope includes all eligible devices and excludes ineligible devices.

Swift wrapper checks:
- generated bindings expose the new direct-call records and async methods.
- Swift API names follow style: `ID`, `URL`, `configuration`, not `Id`, `Url`, or `config`.
- generated descriptions or debug output do not include key material.

Validation:
- SDK targeted Rust tests for the new seam.
- FFI compile check.
- Swift binding generation check if FFI changes compile.
- No app build required unless app files are touched.
- Forbidden scan over changed files for secret/key/debug/raw JSON terms.

Expected output:
1. SDK files changed, if a prototype is implemented.
2. Proposed final API shape.
3. Whether Rust tests pass.
4. Whether Swift bindings generate.
5. Whether app `DirectCallMediaKeyWrappingProtocol` needs async adaptation next.
6. Risks/blockers.
7. Recommended next phase.
8. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
