# Native Direct-Call Status

## Current Phase

After 2.10Q — SDK direct-call media key envelope cryptographic round-trip tests.

## Latest App Checkpoint

344395f1d `Record SDK direct-call key envelope prototype`

## Latest Code Checkpoint

407adede3 `Add production direct-call key wrapping seams`

## Latest SDK Checkpoint

f7c2cfe5c `Add direct-call media key envelope crypto tests`

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
  - The Rust SDK has lower-level custom encrypted to-device capabilities in source, but the current Swift app/wrapper does not expose a direct-call key wrapping API suitable for the room-timeline signal path.
- App-side production key-wrapping seams exist and remain fail-closed:
  - `DirectCallMediaKeyWrappingProtocol` models wrap/unwrap requests around call, room, sender, recipient, device, intent, expiry, key ID, and an opaque envelope.
  - `FailClosedDirectCallMediaKeyWrapper` is the default wrapper and cannot wrap or unwrap.
  - `ProductionDirectCallEncryptionService` can use an injected wrapper plus a shared `DirectCallLiveKitMediaKeyStore`, but defaults to fail-closed with no production activation.
  - `NativeDirectCallProductionDependenciesFactory` can accept a future production key wrapper and shared media key store, while remaining disabled by default.
- Matrix SDK key wrapping seam inspection is complete:
  - Rust crypto can encrypt arbitrary custom to-device content for devices using Olm, with trust-aware device filtering.
  - The higher-level SDK has an `encrypt_and_send_raw_to_device` path used by widget support, but it sends immediately and is not currently exposed through Swift FFI.
  - The lower-level SDK can produce encrypted to-device requests, but the previous public/FFI APIs did not return an app-consumable opaque direct-call envelope for room signalling.
  - Current Swift bindings expose identity/trust status, but not device enumeration plus custom encrypted payload wrap/unwrap.
  - The recommended production transport remains a room direct-call signal carrying an SDK-produced opaque per-device envelope, not a separate production to-device command path.
- The local Matrix SDK prototype now has cryptographic coverage:
  - Added direct-call-specific SDK/FFI models and async methods for wrapping and unwrapping media-key envelopes.
  - High-level SDK tests create Alice and Bob crypto clients with mocked Matrix crypto endpoints and encrypted room state.
  - Alice wraps a per-call media key for Bob; Bob unwraps it and receives the original key material only at the SDK consumer boundary.
  - The opaque envelope does not contain the test media key in plaintext, and debug output remains redacted.
  - Wrong call, room, sender, recipient, intent, and key ID metadata fail closed.
  - A non-recipient device cannot unwrap the envelope.
  - `OnlyTrustedDevices` rejects the current unverified test peer devices with `TrustViolation`.
  - A multi-device Bob envelope includes all eligible Bob devices and can be unwrapped by Bob's second device.
  - `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib` passes.
  - `cargo check -p matrix-sdk-ffi` passes.

## Current Blocker

- Production backend is still skeleton/fake mode.
- Production E2EE Matrix crypto key wrapping is not implemented in the app; the app seam is only a fail-closed skeleton.
- The SDK prototype is committed locally in the SDK workspace, but is not tagged, published, generated into the Swift wrapper, or app-pinned.
- The app-side `DirectCallMediaKeyWrappingProtocol` and `DirectCallEncryptionServiceProtocol` are synchronous today, while the SDK wrapping seam is async.
- The production trust policy for peer devices is not finalized; the safest initial policy should fail closed on unknown or unverifiable device trust.
- No production activation, visible UI, CallKit, or push integration exists yet.

## Next Recommended Phase

`2.10R — publish Matrix SDK direct-call key envelope wrapper artifact`

After that, plan `2.10S — app async production key wrapper integration`.

## Do-Not-Touch Constraints

- No visible UI yet.
- No Element Call route reuse.
- No CallKit or push yet.
- No production feature activation.
- No diagnostic secrets or tokens in production.
- No unencrypted key material in Matrix events.
- No raw JSON, `debugInfo`, `originalJSON`, or `originalJson` receive path.
