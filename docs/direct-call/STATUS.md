# Native Direct-Call Status

## Current Phase

After 2.10P — SDK direct-call media key envelope prototype.

## Latest App Checkpoint

cc1460f85 `Record Matrix SDK key wrapping seam inspection`

## Latest Code Checkpoint

407adede3 `Add production direct-call key wrapping seams`

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
- App-side production key-wrapping seams now exist and remain fail-closed:
  - `DirectCallMediaKeyWrappingProtocol` models wrap/unwrap requests around call, room, sender, recipient, device, intent, expiry, key ID, and an opaque envelope.
  - `FailClosedDirectCallMediaKeyWrapper` is the default wrapper and cannot wrap or unwrap.
  - `ProductionDirectCallEncryptionService` can use an injected wrapper plus a shared `DirectCallLiveKitMediaKeyStore`, but defaults to fail-closed with no production activation.
  - `NativeDirectCallProductionDependenciesFactory` can accept a future production key wrapper and shared media key store, while remaining disabled by default.
- Matrix SDK key wrapping seam inspection is complete:
  - Rust crypto can encrypt arbitrary custom to-device content for devices using Olm, with trust-aware device filtering.
  - The higher-level SDK has an `encrypt_and_send_raw_to_device` path used by widget support, but it sends immediately and is not currently exposed through Swift FFI.
  - The lower-level SDK can produce encrypted to-device requests, but current public/FFI APIs do not return an app-consumable opaque direct-call envelope for room signalling.
  - Current Swift bindings expose identity/trust status, but not device enumeration plus custom encrypted payload wrap/unwrap.
  - The recommended production transport remains a room direct-call signal carrying an SDK-produced opaque per-device envelope, not a separate production to-device command path.
- A local SDK prototype exists in `/Users/aibattt/salemx-sdk-work/matrix-rust-sdk` and is not published or app-pinned:
  - Added a direct-call-specific SDK module with `DirectCallMediaKeyWrapInfo`, `DirectCallMediaKeyUnwrapInfo`, `DirectCallMediaKeyEnvelope`, `DirectCallMediaKeyUnwrapResult`, and redacted `DirectCallMediaKeyEnvelopeError`.
  - Added prototype `Encryption.wrap_direct_call_media_key(...)` and `Encryption.unwrap_direct_call_media_key_envelope(...)` methods behind the existing custom to-device feature.
  - Added FFI records and async methods mirroring the SDK API shape.
  - The prototype packages encrypted per-device content into one opaque envelope string for the existing room direct-call signal.
  - The unwrap path validates envelope metadata, expiry, intended recipient, event type, and SDK decryption sender metadata before returning media key material to the app encryption boundary.
  - Focused SDK tests currently cover redaction and fail-closed metadata handling, not yet a full two-device cryptographic wrap/unwrap round trip through the new API.
  - `cargo check -p matrix-sdk-ffi` passes.
  - `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib` passes.

## Current Blocker

- Production backend is still skeleton/fake mode.
- Production E2EE Matrix crypto key wrapping is not implemented in the app; the app seam is only a fail-closed skeleton.
- The SDK prototype is not committed, tagged, published, or generated into the Swift wrapper.
- The SDK prototype still needs full cryptographic round-trip tests with real SDK/crypto test devices before it should be treated as production-ready.
- The production trust policy for peer devices is not finalized; the safest initial policy should fail closed on unknown or unverifiable device trust.
- `DirectCallEncryptionServiceProtocol` is synchronous today; production Matrix crypto wrapping is async because it needs SDK crypto/device lookup.
- No production activation, visible UI, CallKit, or push integration exists yet.

## Next Recommended Phase

`2.10Q — SDK direct-call media key envelope cryptographic round-trip tests`

## Do-Not-Touch Constraints

- No visible UI yet.
- No Element Call route reuse.
- No CallKit or push yet.
- No production feature activation.
- No diagnostic secrets or tokens in production.
- No unencrypted key material in Matrix events.
- No raw JSON, `debugInfo`, `originalJSON`, or `originalJson` receive path.
