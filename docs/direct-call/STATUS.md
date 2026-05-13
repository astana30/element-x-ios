# Native Direct-Call Status

## Current Phase

After 2.10V — disabled production direct-call dependency wiring added.

## Latest App Code Checkpoint

e9a1c8d1f `Add disabled production direct-call dependency wiring`

## Latest Code Checkpoint

e9a1c8d1f `Add disabled production direct-call dependency wiring`

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
- App-side async Matrix SDK key wrapper skeleton is complete:
  - Generated MatrixRustSDK bindings expose async `wrapDirectCallMediaKey(...)` and `unwrapDirectCallMediaKeyEnvelope(...)` methods on `EncryptionProtocol`.
  - `DirectCallMediaKeyWrappingProtocol` and `DirectCallEncryptionServiceProtocol` are now async at the key wrap/unwrap boundary.
  - `DirectCallEngine` awaits key generation and remote key consume in already-async call paths.
  - `MatrixSDKDirectCallMediaKeyWrapper` maps app wrap/unwrap request models to the generated SDK FFI models and maps SDK envelope results back to redacted app models.
  - Missing SDK encryption dependency still fails closed.
  - `FailClosedDirectCallMediaKeyWrapper` remains the default production wrapper.
  - The SDK-backed wrapper is not injected into production runtime.
  - Focused app unit tests and Release build pass after the async skeleton.
- Production SDK key wrapper injection seam is complete:
  - `NativeDirectCallProductionDependenciesFactory` can accept the narrow `MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol`.
  - The factory constructs `MatrixSDKDirectCallMediaKeyWrapper` from that narrow envelope wrapper only when production dependencies are explicitly enabled.
  - An explicitly provided `DirectCallMediaKeyWrappingProtocol` still takes precedence, preserving test and future injection flexibility.
  - Missing wrapper dependencies still fall back to `FailClosedDirectCallMediaKeyWrapper`.
  - No broad MatrixRustSDK client, room, timeline, or raw crypto API was exposed through app protocols.
  - Production direct calls remain disabled by default.
  - Focused app unit tests and Release build pass after the injection seam.
- Production runtime SDK key wrapper provider seam is complete:
  - `DirectCallMediaKeyEnvelopeWrappingProviding` exposes only a direct-call envelope wrapper provider, not a raw SDK client, raw SDK room, raw timeline, or raw crypto object.
  - Concrete `ClientProxy` can create `MatrixSDKDirectCallMediaKeyEnvelopeWrapperAdapter` from `client.encryption()` through that narrow provider seam.
  - `ClientProxyProtocol`, `RoomProxyProtocol`, and `TimelineProxyProtocol` remain unchanged.
  - `NativeDirectCallProductionDependenciesFactory` can use an explicit wrapper first, then an explicit SDK envelope wrapper, then the runtime provider, and finally the fail-closed wrapper.
  - The production factory does not ask the runtime provider while production direct-call configuration is disabled.
  - Missing provider/wrapper dependencies remain fail-closed.
  - Diagnostic direct-call encryption and LiveKit paths remain isolated behind DEBUG/integration gates.
  - Focused app unit tests, Release build, and forbidden scan pass after the provider seam.
- Disabled production direct-call dependency wiring is complete:
  - `NativeDirectCallProductionDependencyAssembly` can assemble production dependencies only from explicit production configuration and injected runtime providers.
  - Required providers are the production HTTP transport, Matrix access-token provider, LiveKit client, narrow SDK key envelope provider, own user ID, and optional shared media key store/sender device ID.
  - Missing production config or any required runtime provider returns disabled/fail-closed dependencies.
  - The assembly builds `ProductionDirectCallLiveKitTokenClient` from injected transport/auth only when explicitly configured.
  - Concrete `ClientProxy` now conforms to the narrow `DirectCallMatrixAccessTokenProviding` protocol without changing `ClientProxyProtocol`.
  - No runtime UI path, Element Call route, CallKit, push, diagnostic env, or production feature flag was activated.
  - Focused app unit tests, Release build, and forbidden scan pass after the disabled wiring seam.

## Current Blocker

- Production backend is still skeleton/fake mode.
- Production E2EE Matrix crypto key wrapping now has narrow provider and disabled assembly seams, but the assembly is not yet threaded into the real session/room-flow runtime.
- No production runtime path yet passes assembled dependencies into `NativeDirectCallRoomFlowOwner`.
- The default app path remains fail-closed unless future production configuration and dependency assembly explicitly enable native direct-call dependencies.
- The production trust policy for peer devices is not finalized; the safest initial policy should fail closed on unknown or unverifiable device trust.
- No production activation, visible UI, CallKit, or push integration exists yet.

## Next Recommended Phase

`2.10W — guarded production room-flow dependency injection inspection/skeleton`

Goal: inspect and, if safe, add a disabled-by-default runtime injection seam that can thread `NativeDirectCallProductionDependencyAssembly` into session/room-flow construction and provide dependencies to `NativeDirectCallRoomFlowOwner` only when explicit production config and runtime providers are present, without activating visible UI or production direct calls.

## Do-Not-Touch Constraints

- No visible UI yet.
- No Element Call route reuse.
- No CallKit or push yet.
- No production feature activation.
- No diagnostic secrets or tokens in production.
- No unencrypted key material in Matrix events.
- No raw JSON, `debugInfo`, `originalJSON`, or `originalJson` receive path.
