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
After 2.10Q — SDK direct-call media key envelope cryptographic round-trip tests.

Current app checkpoint:
344395f1d `Record SDK direct-call key envelope prototype`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Phase:
2.10R — publish Matrix SDK direct-call key envelope wrapper artifact.

Task:
Turn the proven local SDK direct-call media key envelope seam into a reproducible Swift wrapper dependency.
Do not activate production direct calls.
Do not add visible UI.
Do not modify Element Call route.
Do not wire CallKit/push.
Do not publish fake or simulator-only artifacts.

Context:
- 2.10Q proved the high-level SDK direct-call envelope seam cryptographically:
  - Alice/Bob high-level SDK crypto clients were created with mocked Matrix crypto endpoints and encrypted room state.
  - Alice wrapped a per-call media key for Bob.
  - Bob unwrapped the envelope and recovered the original key material at the SDK consumer boundary.
  - The opaque envelope did not contain the test media key in plaintext.
  - Wrong metadata and non-recipient devices fail closed.
  - `OnlyTrustedDevices` rejects unverified peer devices.
  - Multi-device Bob envelopes include all eligible devices.
- SDK commit is local only:
  - `f7c2cfe5c Add direct-call media key envelope crypto tests`
- The app production key wrapping seam remains fail-closed.
- The app sync protocols still need future async adaptation; do not solve that unless explicitly scoped.

SDK validation to repeat first:
- `git status --short`
- `cargo check -p matrix-sdk-ffi`
- `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib`
- changed-file formatting check for the SDK direct-call/FFI files
- forbidden scan over changed SDK files for raw/debug/secret terms

Wrapper/publishing goals:
1. Build a full reproducible `MatrixSDKFFI.xcframework` from SDK commit `f7c2cfe5c`.
2. Do not use a simulator-only artifact.
3. Regenerate Swift bindings so the wrapper exposes:
   - `DirectCallMediaKeyWrapInfo`
   - `DirectCallMediaKeyUnwrapInfo`
   - `DirectCallMediaKeyEnvelope`
   - `DirectCallMediaKeyUnwrapResult`
   - `DirectCallMediaKeyEnvelopeError`
   - `Encryption.wrapDirectCallMediaKey(...)`
   - `Encryption.unwrapDirectCallMediaKeyEnvelope(...)`
4. Update `/Users/aibattt/salemx-sdk-work/matrix-rust-components-swift` with the generated Swift and full binary artifact.
5. Publish the artifact to a real stable release URL; do not fake the URL.
6. Update wrapper `Package.swift` checksum and URL.
7. Validate wrapper package resolution/description.
8. Commit and tag the wrapper if production-resolvable.
9. Do not update the app dependency pin unless the wrapper artifact is real and tests pass; if app pin update is included, keep production direct calls disabled and do not wire runtime usage.

Hard constraints:
- Do not expose raw Matrix event JSON.
- Do not use `debugInfo`, `originalJSON`, or `originalJson`.
- Do not log media key material.
- Do not place unencrypted media key material in Matrix event content.
- Do not expose broad raw APIs on app room/timeline protocols.
- Do not put LiveKit URL, participant token, JWT, or API secret in Matrix signalling.
- Do not use diagnostic encryption secrets or diagnostic LiveKit tokens in production paths.
- Do not modify visible UI.
- Do not change Element Call route.
- Do not activate production feature flags.
- Do not wire CallKit or push.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Expected output:
1. SDK commit/tag used.
2. Full xcframework build result.
3. Wrapper files changed.
4. Generated Swift API shape.
5. Artifact URL/checksum/tag, if published.
6. Wrapper validation results.
7. App dependency pin result, if updated.
8. Tests/build results.
9. Forbidden scan result.
10. Commit hashes.
11. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
