# Native Direct-Call Status

## Current Phase

After 2.12B — local backend + app production token/capability integration pack complete.

## Latest App Code Checkpoint

This commit: `Add local production token integration smoke harness`

## Latest Code Checkpoint

This commit: `Add local production token integration smoke harness`

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
- Production activation gate design inspection is complete:
  - `directOneToOneCallsEnabled` should not be reused as the native production activation switch because it currently belongs to the existing direct-call/Element Call placeholder path and logs that production signal transport is disabled.
  - The safest production gate is multi-factor: app rollout configuration, authenticated server capability, token endpoint discovery, runtime dependency readiness, room eligibility, and future UI/CallKit readiness.
  - The authoritative server signal should be a SalemX-specific Matrix client capability, not a developer option or diagnostic env.
  - Endpoint discovery should prefer an authenticated Matrix capability that advertises the native direct-call token endpoint as a same-origin relative path, with the current unstable path as the default contract.
  - `.well-known` can remain useful for pre-auth hints, but should not be sufficient to activate production direct calls.
  - Diagnostics remain separate and must not influence production activation.
- Production direct-call activation gate skeleton is complete:
  - `DirectCallProductionServerCapability` models the SalemX native direct-call capability `kz.salemx.direct_call.native`.
  - The capability requires version `1`, audio intent support, LiveKit media transport, E2EE required, and the Matrix SDK direct-call media key envelope scheme.
  - Token endpoint discovery is modeled as a same-origin relative endpoint path, with same-origin configured endpoint override support.
  - `DirectCallProductionRoomEligibility` models only redacted room eligibility booleans/count state: direct room, encrypted room, exactly two joined members, and peer availability.
  - `DirectCallProductionActivationGate` is disabled by default and returns redacted fail-closed reasons for missing rollout, capability, endpoint, dependencies, or room eligibility.
  - `directOneToOneCallsEnabled` remains unused for native production activation.
  - The gate is not wired into visible UI, Element Call routing, CallKit, push, or runtime production activation.
  - Focused app unit tests, Release build, and forbidden scan pass after the activation gate skeleton.
- Production direct-call server capability discovery seam skeleton is complete:
  - `DirectCallProductionCapabilityProviding` models an async, fail-closed source for the SalemX native direct-call server capability.
  - `FailClosedDirectCallProductionCapabilityProvider` is the default provider and returns `providerUnavailable`.
  - `DirectCallProductionCapabilityPayloadDecoder` decodes the authenticated Matrix capabilities envelope for `kz.salemx.direct_call.native`.
  - Missing or malformed capability payloads return redacted fail-closed discovery reasons.
  - The decoded capability feeds the existing `DirectCallProductionActivationGate`, which still owns same-origin endpoint validation and all activation decisions.
  - The current app/wrapper inspection found no existing narrow authenticated custom capability API beyond the separate `ClientProxy.isLiveKitRTCSupported` helper and pre-auth `.well-known` patterns.
  - No real network fetch, UI path, Element Call routing, CallKit, push, diagnostic env, or production runtime activation was added.
  - Focused app unit tests, Release build, and forbidden scan pass after the discovery seam skeleton.
- Production activation decision assembly skeleton is complete:
  - `DirectCallProductionActivationDeciding` models the narrow async activation decision boundary.
  - `DirectCallProductionActivationDecisionService` assembles app rollout configuration, server capability discovery, production dependency readiness, homeserver URL, and room eligibility into the existing `DirectCallProductionActivationGate`.
  - `NativeDirectCallProductionDependencyProviding` lets the decision service consume dependency readiness without constructing listeners, media engines, or room owners.
  - Default configuration remains disabled and does not query capability or dependency providers.
  - Missing or malformed capability discovery fails closed before dependency readiness is queried.
  - Unsupported capability fields, external endpoints, unavailable dependencies, and ineligible rooms all map to existing redacted disabled reasons.
  - The service is not wired into visible UI, Element Call routing, CallKit, push, diagnostics, or production runtime activation.
  - `directOneToOneCallsEnabled` remains unused for native production activation.
  - Focused app unit tests, Release build, and forbidden scan pass after the decision assembly skeleton.
- Production activation dry-run diagnostics are complete:
  - `DirectCallProductionActivationDryRunDiagnostic` reports only redacted activation booleans and disabled reason: enabled state, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
  - `DirectCallProductionActivationDryRunDiagnosing` exposes an internal async dry-run boundary on the existing decision service.
  - Dry-run uses the same `DirectCallProductionActivationGate` as the real decision path, avoiding a parallel activation model.
  - Default configuration remains disabled and does not query capability or dependency providers.
  - Missing or malformed capability discovery skips dependency readiness checks.
  - All-valid dry-run returns an enabled diagnostic model without generating keys, consuming keys, clearing keys, constructing a media engine, starting listeners, creating controllers, or sending Matrix events.
  - The dry-run surface is not wired into visible UI, Element Call routing, CallKit, push, diagnostics env, or production runtime activation.
  - Focused app unit tests, Release build, and forbidden scan pass after the dry-run diagnostics.
- Room-scoped production activation dry-run seam is complete:
  - `NativeDirectCallProductionActivationDryRunProviding` models a room-scoped provider for redacted production activation readiness.
  - `FailClosedNativeDirectCallProductionActivationDryRunProvider` is the default provider and returns disabled with `roomUnavailable`.
  - `NativeDirectCallProductionActivationDryRunProvider` delegates to `DirectCallProductionActivationDryRunDiagnosing` with an injected homeserver URL and room eligibility.
  - `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()` returns a redacted disabled diagnostic when no active room is available.
  - Once a room proxy is stored, `RoomFlowCoordinator` can delegate to an injected dry-run provider without preparing the native direct-call room owner.
  - Tests prove the room-scoped dry-run does not call prepare, start listener, outgoing call, accept, hangup, stop, reset, media, signalling, or Matrix send paths.
  - The seam is not wired into visible UI, Element Call routing, CallKit, push, diagnostic env, or production runtime activation.
  - Focused app unit tests, Release build, and forbidden scan pass after the room-scoped dry-run seam.
- Debug/internal production activation dry-run command exposure is complete:
  - `UITestsSignalling` now supports a DEBUG/integration-only `nativeDirectCallProductionActivationDryRun` request and redacted result.
  - The existing diagnostic harness routes the command through AppCoordinator, UserSessionFlowCoordinator, ChatsTabFlowCoordinator, and the active RoomFlowCoordinator dry-run seam.
  - The runner exposes `production-activation-dry-run A|B` / `productionActivationDryRun A|B`.
  - Output is limited to redacted fields: enabled state, disabled reason, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
  - The command does not prepare controllers, start listeners, start outgoing calls, accept calls, construct media engines, or send Matrix events.
  - The DEBUG/integration runtime provider uses the production dry-run decision service with default rollout disabled, so production remains fail-closed by default.
  - Focused app unit tests, Release build, runner syntax/dry-run checks, and forbidden scan pass after the command exposure.
- Production activation dry-run runtime proof is recorded:
  - A and B both reached app diagnostic signalling readiness.
  - A and B both responded to the normal status command.
  - `production-activation-dry-run A` returned `enabled=false`, `reason=appRolloutDisabled`, `capabilityPresent=false`, `dependenciesReady=false`, `roomEligible=true`, and `endpointAccepted=false`.
  - `production-activation-dry-run B` returned the same redacted fields.
  - No production call started.
  - No listener, media, or Matrix send side effects were triggered by the dry-run command.
  - The disabled production state is expected.
- App rollout/capability config source inspection is complete:
  - `DirectCallProductionConfiguration` should stay default-disabled and should not read diagnostic env, developer options, or `directOneToOneCallsEnabled`.
  - App rollout should come from an app-owned production config source, preferably an `AppSettings`/hook-backed non-user-facing value that defaults false and can later be remotely configured.
  - Server authority should come from authenticated Matrix `/capabilities` containing `kz.salemx.direct_call.native`, not `.well-known` alone.
  - `.well-known` may remain a pre-auth hint or remote settings input, but must never be sufficient to activate production native direct calls.
  - The current Swift Matrix SDK wrapper exposes specialized `isLiveKitRTCSupported`/versions helpers, but no narrow generic authenticated `/capabilities` fetch for the SalemX native direct-call capability.
  - A narrow `DirectCallHTTPTransportProtocol` + `DirectCallMatrixAccessTokenProviding` capability provider is the safest app-side source for now; it can fetch `/_matrix/client/v3/capabilities` and pass only response data into `DirectCallProductionCapabilityPayloadDecoder`.
  - Token endpoint discovery should continue to accept only same-origin relative paths from capability, with same-origin explicit overrides reserved for app configuration/tests.
  - Dependency readiness should be computed after an accepted token endpoint exists, or split into side-effect-free runtime-prerequisite readiness plus endpoint-specific dependency assembly.
  - Production remains disabled by default and no app code changed during this inspection.
- Fail-closed rollout and capability source skeleton is complete:
  - `DirectCallProductionRolloutProviding` models the app-owned rollout configuration source.
  - `FailClosedDirectCallProductionRolloutProvider` returns the default disabled `DirectCallProductionConfiguration`.
  - `HTTPDirectCallProductionCapabilityProvider` fetches authenticated Matrix `/_matrix/client/v3/capabilities` through injected `DirectCallHTTPTransportProtocol` and `DirectCallMatrixAccessTokenProviding`.
  - The provider decodes only the `kz.salemx.direct_call.native` capability through `DirectCallProductionCapabilityPayloadDecoder`.
  - Missing homeserver URL, invalid URL scheme, missing transport, missing access token, non-2xx HTTP responses, missing capability, or malformed capability all fail closed with redacted reasons.
  - The authenticated request uses `GET` with an Authorization bearer header, while request/provider descriptions redact the URL and bearer value.
  - `.well-known` is not used for production activation.
  - `directOneToOneCallsEnabled` remains unused for native production activation.
  - Capability-sourced absolute/external token endpoints are still rejected by the activation gate.
  - No runtime production path, visible UI, Element Call routing, CallKit, push, listener start, media engine construction, or Matrix send was added.
  - Focused app unit tests, Release build, and forbidden scan pass after the source skeleton.
- Production activation decision now uses rollout/capability providers:
  - `DirectCallProductionActivationDecisionService` stores a `DirectCallProductionRolloutProviding` and asks it for configuration at decision time.
  - Static configuration remains supported through a redacted static rollout provider wrapper.
  - Default providers remain fail-closed: rollout disabled, capability absent, and dependencies unavailable.
  - Disabled rollout short-circuits before querying capability or dependency providers.
  - Rollout-enabled decisions query the capability provider, then dependency readiness, then room eligibility in a side-effect-free sequence.
  - Capability provider failures remain redacted and map to `serverCapabilityUnavailable`.
  - All-valid fake inputs can produce an enabled dry-run decision without constructing listeners, controllers, media engines, or sending Matrix events.
  - Existing runner dry-run output remains redacted and unchanged.
  - No runtime production path, visible UI, Element Call routing, CallKit, push, listener start, media engine construction, or Matrix send was added.
  - Focused app unit tests, Release build, and forbidden scan pass after the provider-backed decision wiring.
- Production activation readiness pack is complete:
  - Consolidated tests prove the enabled model requires rollout enabled, valid server capability, accepted same-origin token endpoint, production dependencies ready, and encrypted direct 1:1 room eligibility.
  - Fail-closed coverage now includes disabled rollout, missing capability, malformed capability, external endpoint rejection, unavailable dependencies, unavailable room, unencrypted room, and non-1:1 room cases.
  - Dry-run signal encoding tests assert output remains redacted and excludes room IDs, peer IDs, endpoint values, credential-like fields, unwrapped key material, Matrix content, and encrypted payload values.
  - No-side-effect checks prove the readiness path does not generate keys, consume keys, clear keys, construct media engines, start listeners, or send Matrix events.
  - The runner command remains read-only and production direct calls remain disabled by default.
  - Focused app unit tests, Release build, and forbidden scan pass after the readiness pack.
- Local backend + app production token/capability integration smoke pack is complete:
  - Backend fake mode now exposes a local-only Matrix capabilities response for `kz.salemx.direct_call.native`.
  - The fake capabilities route exists only when `SALEMX_CALL_SERVICE_FAKE_MODE=1`.
  - The existing env-gated app token smoke still verifies `ProductionDirectCallLiveKitTokenClient` can consume the local fake token response through `URLSessionDirectCallHTTPTransport`.
  - A new env-gated app capability smoke verifies `HTTPDirectCallProductionCapabilityProvider` can fetch/decode the local fake capability response through `URLSessionDirectCallHTTPTransport`.
  - The smoke also proves default rollout still returns `appRolloutDisabled`, while an all-valid test-only model can produce an enabled dry-run decision without runtime activation.
  - Local smoke instructions are documented in `docs/direct-call/LOCAL_BACKEND_SMOKE.md`.
  - Production direct calls remain disabled by default.

## Current Blocker

- Production backend is still skeleton/fake mode.
- Production E2EE Matrix crypto key wrapping now has narrow provider, disabled assembly, activation gate, capability discovery, decision assembly, provider-backed rollout/capability inputs, room-scoped dry-run seams, and a consolidated readiness test pack, but the assembly is not yet threaded into the real session/room-flow runtime for activation.
- The production activation decision can consume an app rollout provider and an injectable authenticated `/capabilities` fetch provider, but these providers are not yet wired into real session/room-flow runtime construction by default.
- The current production dependency readiness path is still coupled to explicit `DirectCallProductionConfiguration.tokenEndpointBaseURL`, so capability-sourced endpoints need a two-stage readiness/assembly path before dry-run can report dependencies ready from server capability alone.
- The room-flow dry-run seam can now be queried by the DEBUG/integration runner command and has a runtime proof for A/B; there is still no visible UI or production runtime activation.
- No production runtime path yet passes activation-approved assembled dependencies into `NativeDirectCallRoomFlowOwner`.
- The default app path remains fail-closed unless future production configuration and dependency assembly explicitly enable native direct-call dependencies.
- The production trust policy for peer devices is not finalized; the safest initial policy should fail closed on unknown or unverifiable device trust.
- No production activation, visible UI, CallKit, or push integration exists yet.

## Next Recommended Phase

`2.12C — endpoint-aware production dependency readiness inspection/skeleton`

Goal: split side-effect-free runtime prerequisite readiness from endpoint-specific dependency assembly, or make dependency readiness receive an activation-accepted token endpoint, without activating visible UI or production direct calls.

## Do-Not-Touch Constraints

- No visible UI yet.
- No Element Call route reuse.
- No CallKit or push yet.
- No production feature activation.
- No diagnostic secrets or tokens in production.
- No unencrypted key material in Matrix events.
- No raw JSON, `debugInfo`, `originalJSON`, or `originalJson` receive path.
