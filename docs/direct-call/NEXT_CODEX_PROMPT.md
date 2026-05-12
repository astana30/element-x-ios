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
After 2.10P — SDK direct-call media key envelope prototype.

Current app checkpoint:
cc1460f85 `Record Matrix SDK key wrapping seam inspection`

Phase:
2.10Q — SDK direct-call media key envelope cryptographic round-trip tests.

Task:
Harden the local Matrix Rust SDK direct-call media key envelope prototype with real cryptographic round-trip tests.
Do not publish wrapper artifacts yet.
Do not update the app dependency pin.
Do not activate production direct calls.
Do not modify visible UI, Element Call route, CallKit, push, or production feature flags.

Context:
- 2.10P added a local SDK prototype in `/Users/aibattt/salemx-sdk-work/matrix-rust-sdk`.
- The prototype adds direct-call-specific records:
  - `DirectCallMediaKeyWrapInfo`
  - `DirectCallMediaKeyUnwrapInfo`
  - `DirectCallMediaKeyEnvelope`
  - `DirectCallMediaKeyUnwrapResult`
  - `DirectCallMediaKeyEnvelopeError`
- The prototype adds `Encryption.wrap_direct_call_media_key(...)` and `Encryption.unwrap_direct_call_media_key_envelope(...)`.
- The prototype adds matching FFI records and async methods.
- The prototype compiles through `cargo check -p matrix-sdk-ffi`.
- Focused tests pass with `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib`.
- Existing tests only prove redaction and fail-closed metadata handling; they do not yet prove a full cryptographic wrap/unwrap through the new high-level API.

Goal:
Prove the prototype can wrap a media key for an eligible peer device, carry only an opaque envelope, and unwrap only on the intended recipient device using SDK crypto test machines/devices.

Inspect before editing:
1. `crates/matrix-sdk/src/encryption/direct_call.rs`
2. `crates/matrix-sdk/src/encryption/mod.rs`
3. `bindings/matrix-sdk-ffi/src/encryption.rs`
4. `crates/matrix-sdk-crypto/src/machine/tests/send_encrypted_to_device.rs`
5. `crates/matrix-sdk-crypto/src/machine/test_helpers.rs`
6. `crates/matrix-sdk/src/test_utils` or existing high-level SDK encryption tests, if available
7. Any existing mock room/encrypted-room setup helpers in `matrix-sdk` tests

Test goals:
- Wrap succeeds for an encrypted one-to-one room with an eligible peer device.
- Envelope does not contain plaintext media key material.
- Unwrap succeeds on the intended recipient device.
- Unwrap fails on a non-recipient device.
- Metadata mismatch fails closed: room ID, call ID, sender, recipient, intent, key ID, and expiry.
- Sender identity from SDK decryption metadata is validated, not only sender fields inside decrypted plaintext.
- Conservative trust policy rejects untrusted or unsigned devices.
- Multi-device peer envelope includes all eligible devices and excludes ineligible devices.
- No raw Matrix event JSON is exposed through the FFI API.
- No unencrypted key material appears in debug output, logs, or test failure messages.

Design questions to resolve:
A. Should `wrap_direct_call_media_key` require a live SDK room and encrypted room state, or should room eligibility be validated by the app/backend before calling the SDK key wrapper?
B. Should the opaque envelope include recipient device IDs inside the opaque payload, or should the SDK hide device selection even more strongly before FFI generation?
C. Should unwrap return raw media key material to the app service boundary, or should the SDK/wrapper eventually write directly into a key-store handle?
D. What minimal async adaptation is needed in app `DirectCallEncryptionServiceProtocol` after the SDK seam is proven?

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

Validation:
- `cargo fmt`
- `cargo check -p matrix-sdk-ffi`
- Focused Rust tests for the new direct-call envelope seam.
- FFI compile check.
- No Swift wrapper artifact publishing in this phase.
- Forbidden scan over changed files for the direct-call forbidden debug/secret terms.

Expected output:
1. SDK files changed.
2. Cryptographic round-trip tests added and results.
3. Whether the high-level SDK seam is fully proven or still blocked.
4. Exact blockers, if any.
5. Whether FFI still compiles.
6. Whether Swift bindings were generated; do not publish unless explicitly requested.
7. Whether app async protocol adaptation is required next.
8. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
