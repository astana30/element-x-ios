# Native Direct-Call Status

## Current Phase

After 2.10R — Matrix SDK direct-call media key envelope wrapper artifact published and app dependency pinned.

## Latest App Code Checkpoint

06fdf5f28 `Pin Matrix SDK direct-call key envelope bindings`

## Latest Code Checkpoint

407adede3 `Add production direct-call key wrapping seams`

## Latest SDK Checkpoint

f7c2cfe5c `Add direct-call media key envelope crypto tests`

SDK tag: `salemx-direct-call-key-envelope-f7c2cfe5c`

## Latest Wrapper Checkpoint

1e58d0a `Add direct-call media key envelope bindings`

Wrapper tag: `salemx-matrix-rust-components-swift-26.03.10-salemx.3`

## Published Artifact

- URL: https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip
- Checksum: `654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e`

## Proven Checkpoints

- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit media proof reached active.
- Production token DTOs, client, and transport seams exist.
- Backend token service skeleton exists.
- Synapse room validation skeleton exists.
- Local backend fake smoke exists.
- App production token client smoke test exists and is disabled by default.
- Production E2EE key wrapping seam inspection is complete:
  - The direct-call room-flow path has room and peer metadata plus a clean dependency injection point.
  - The custom direct-call Matrix event is sent through SDK room sending and is expected to be room-encrypted when the room is encrypted.
  - Room encryption is a necessary transport layer, but not sufficient as the production media-key wrapping design: the app still must not place unwrapped media key material in the event content handed to the SDK.
  - The current app Matrix crypto proxies expose identity/key status, but not a narrow per-call media-key wrapping primitive.
- App-side production key-wrapping seams exist and remain fail-closed:
  - `DirectCallMediaKeyWrappingProtocol` models wrap/unwrap requests around call, room, sender, recipient, device, intent, expiry, key ID, and an opaque envelope.
  - `FailClosedDirectCallMediaKeyWrapper` is the default wrapper and cannot wrap or unwrap.
  - `ProductionDirectCallEncryptionService` can use an injected wrapper plus a shared `DirectCallLiveKitMediaKeyStore`, but defaults to fail-closed with no production activation.
  - `NativeDirectCallProductionDependenciesFactory` can accept a future production key wrapper and shared media key store, while remaining disabled by default.
- Matrix SDK direct-call media key envelope crypto is proven locally and published through the Swift wrapper:
  - High-level SDK tests create Alice and Bob crypto clients with mocked Matrix crypto endpoints and encrypted room state.
  - Alice wraps a per-call media key for Bob; Bob unwraps it and receives the original key material only at the SDK consumer boundary.
  - The opaque envelope does not contain the test media key in plaintext, and debug output remains redacted.
  - Wrong call, room, sender, recipient, intent, and key ID metadata fail closed.
  - A non-recipient device cannot unwrap the envelope.
  - `OnlyTrustedDevices` rejects the current unverified test peer devices with `TrustViolation`.
  - A multi-device Bob envelope includes all eligible Bob devices and can be unwrapped by Bob's second device.
  - `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib` passes.
  - `cargo check -p matrix-sdk-ffi` passes.
- Wrapper publication and app pin are complete:
  - Full `MatrixSDKFFI.xcframework` was built for device and simulator targets.
  - The published artifact checksum was verified after download.
  - Generated Swift bindings expose `DirectCallMediaKeyWrapInfo`, `DirectCallMediaKeyUnwrapInfo`, `DirectCallMediaKeyEnvelope`, `DirectCallMediaKeyUnwrapResult`, `DirectCallMediaKeyEnvelopeError`, `wrapDirectCallMediaKey`, and `unwrapDirectCallMediaKeyEnvelope`.
  - Wrapper `swift package resolve` and `swift package describe` pass using the published URL and checksum.
  - App `project.yml`, generated Xcode project, and `compound-ios/Package.resolved` are pinned to wrapper commit `1e58d0a4317e3ff74c2d565cf532bc8d035bcc8f`.
  - Focused app unit tests and Release build pass after the pin.

## Current Blocker

- Production backend is still skeleton/fake mode.
- Production E2EE Matrix crypto key wrapping is not integrated in the app runtime; the app seam is still fail-closed by default.
- The app-side `DirectCallMediaKeyWrappingProtocol` and `DirectCallEncryptionServiceProtocol` are synchronous today, while the published SDK wrapping seam is async.
- A production SDK-backed app wrapper must bridge the new MatrixRustSDK API into the existing production key-store path without exposing unencrypted key material in logs, diagnostics, or Matrix signal content.
- The production trust policy for peer devices is not finalized; the safest initial policy should fail closed on unknown or unverifiable device trust.
- No production activation, visible UI, CallKit, or push integration exists yet.

## Next Recommended Phase

`2.10S — app async production key wrapper integration inspection/skeleton`

Goal: adapt the app-side production key wrapping seam for the async Matrix SDK envelope API and add a fail-closed SDK-backed wrapper skeleton without activating production direct calls.

## Do-Not-Touch Constraints

- No visible UI yet.
- No Element Call route reuse.
- No CallKit or push yet.
- No production feature activation.
- No diagnostic secrets or tokens in production.
- No unencrypted key material in Matrix events.
- No raw JSON, `debugInfo`, `originalJSON`, or `originalJson` receive path.
