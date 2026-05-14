# Native Direct-Call Worklog

This file records durable phase-level progress for future Codex and strategy sessions.

## Milestones

- Added Matrix SDK-backed custom content accessor for direct-call message-like events.
- Added and pinned the SDK custom timeline filter so the native direct-call receive path can observe the custom message-like signal event without changing the visible RoomScreen timeline.
- Hardened receive semantics so historical timeline reset/backlog direct-call events are ignored and only live post-baseline events are delivered to the engine.
- Proved two-client Matrix signalling end-to-end: invite, incoming ringing, accept, answer, and hangup/cleanup diagnostics.
- Proved diagnostic LiveKit media path can reach active under DEBUG/integration-only gates.
- Added production-shaped dependency seams for token, encryption, and media dependencies while keeping them fail-closed and inactive by default.
- Drafted the backend LiveKit token API contract for native direct calls.
- Added the SalemX call service backend skeleton for LiveKit token allocation.
- Added Synapse-backed room validation skeleton for requester/peer membership, encrypted room eligibility, and one-to-one validation.
- Added local backend fake smoke mode for the call service.
- Added app-side production token backend smoke coverage through an env-gated, disabled-by-default test harness.
- Added fail-closed app-side production media-key wrapping seams and shared LiveKit E2EE key-store injection hooks.
- Inspected Matrix Rust SDK crypto and FFI surfaces for a narrow production direct-call media-key wrapping seam.

## 2026-05-12 — 2.10M Production E2EE Key Wrapping Seam Inspection

- Inspected `DirectCallEncryptionServiceProtocol`, `ProductionDirectCallEncryptionService`, diagnostic encryption, signal payload models, engine key lifecycle, LiveKit E2EE key store, and production dependency factory wiring.
- Confirmed production encryption remains intentionally fail-closed and is not connected to Matrix crypto or the LiveKit media key store.
- Confirmed the room-flow path already has the required room and peer metadata plus an existing injection point through `NativeDirectCallRoomFlowOwner`.
- Confirmed current app Matrix crypto proxies expose identity/key status only; they do not expose a narrow safe primitive for per-call media-key wrapping.
- Confirmed SDK room sending should encrypt the custom direct-call message-like event in encrypted rooms, but room encryption alone is not the production media-key wrapping design because the app must still hand only opaque wrapped key material to Matrix signalling.
- Found Rust SDK source has lower-level custom encrypted to-device support, but the current Swift app/wrapper does not expose an API that returns or consumes an opaque direct-call key envelope for the existing room-timeline signal path.
- Recommended the production key-exchange payload keep call, room, sender, key identifier, algorithm/version, sender device, recipient user, expiry, and opaque ciphertext fields, with per-device details hidden inside the opaque SDK-produced envelope where possible.
- Recommended multi-device handling wrap to all eligible peer devices and fail closed on unknown or unverifiable trust until UX/product policy exists.
- Identified that production key wrapping likely needs an async service boundary because Matrix crypto/device lookup is asynchronous.
- Recommended the next implementation phase as a fail-closed app seam skeleton that introduces a narrow key-wrapping protocol and shared media key-store bridge without real SDK crypto or production activation.

## 2026-05-12 — 2.10N Production E2EE App Key-Wrapping Seam Skeleton

- Added production-shaped media key wrap/unwrap request and envelope models that carry call, room, sender, recipient, device, intent, expiry, key ID, and opaque envelope metadata with redacted descriptions.
- Added `DirectCallMediaKeyWrappingProtocol` and a default `FailClosedDirectCallMediaKeyWrapper` that cannot wrap or unwrap and never stores key material.
- Extended `ProductionDirectCallEncryptionService` so future production Matrix crypto wrapping can plug in with a shared `DirectCallLiveKitMediaKeyStore`.
- Kept the default production encryption path fail-closed when no wrapper, key store, own user metadata, or valid wrapped envelope is available.
- Updated `NativeDirectCallProductionDependenciesFactory` to accept a future key wrapper, own user/device metadata, and shared media key store while remaining disabled by default.
- Added focused production key-wrapping tests covering fail-closed behavior, fake wrapper generation/consume, metadata mismatch rejection, idempotent cleanup, and shared key-store factory wiring.
- Confirmed diagnostic encryption remains isolated and the production factory does not reference diagnostic-only types.
- Regenerated `SalemX.xcodeproj` so the new test file is part of the UnitTests target.
- Recommended next phase: prototype the narrow Matrix SDK/wrapper key wrapping seam that can replace the fail-closed wrapper without exposing raw Matrix JSON or media keys.

## 2026-05-12 — 2.10O Matrix SDK Narrow Key Wrapping Seam Inspection

- Inspected Rust SDK crypto, device, to-device, room send, widget, FFI, and generated Swift binding surfaces in the local SDK and wrapper workspaces.
- Confirmed the Rust crypto layer can encrypt arbitrary custom to-device content for a device using Olm via `Device::encrypt_event_raw`.
- Confirmed the Rust crypto layer has multi-device support via `OlmMachine::encrypt_content_for_devices`, including trust-aware filtering through `CollectStrategy`.
- Confirmed the high-level SDK exposes an `encrypt_and_send_raw_to_device` helper behind the experimental custom to-device feature, and widget support already uses this path for encrypted custom to-device traffic.
- Confirmed the current Swift FFI bindings expose identity and trust state, but not a direct-call-specific wrapper that returns or consumes an opaque media-key envelope.
- Confirmed a separate production to-device key message is possible, but the safer next design keeps the existing room direct-call signal as the deterministic carrier and places only an SDK-produced opaque per-device envelope in that signal.
- Recommended a narrow SDK/FFI API that wraps the per-call media key into a redacted direct-call envelope and unwraps it on the recipient device without exposing Matrix event JSON or broad raw APIs.
- Identified that a real implementation will need async app integration because device lookup, session setup, and envelope generation/decryption are asynchronous.
- Recommended next phase: implement a local SDK prototype for `wrapDirectCallMediaKey` and `unwrapDirectCallMediaKeyEnvelope`, with focused Rust/FFI tests before publishing a wrapper artifact.

## 2026-05-12 — 2.10P SDK Direct-Call Media Key Envelope Prototype

- Prototyped a narrow Matrix Rust SDK direct-call media-key envelope seam in the local SDK workspace.
- Added a direct-call-specific SDK module that models wrap info, unwrap info, an opaque envelope, unwrap result, trust policy, and redacted error cases.
- Added prototype SDK methods on `Encryption` for wrapping a per-call media key into an opaque envelope and unwrapping that envelope on an intended recipient device.
- Added FFI records and async methods that mirror the SDK API shape without exposing Matrix event JSON, device maps, or Olm internals to the app.
- Kept the existing direct-call room signal as the deterministic carrier; the prototype places only an SDK-produced opaque per-device envelope into that signal.
- Validated envelope metadata, expiry, intended recipient, event type, and SDK decryption sender metadata on unwrap before returning media key material to the app encryption boundary.
- Added focused SDK tests for redacted debug output, malformed envelope handling, metadata mismatch, and expiry fail-closed behavior.
- Confirmed `cargo check -p matrix-sdk-ffi` passes for the prototype.
- Confirmed `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib` passes.
- Did not publish wrapper artifacts, update the app dependency pin, modify app production code, or activate production direct calls.
- Identified the next blocker: add full cryptographic SDK round-trip tests using real test devices before generating Swift bindings or publishing an artifact.

## 2026-05-12 — 2.10Q SDK Direct-Call Media Key Envelope Crypto Tests

- Added high-level Matrix SDK tests that prove the direct-call media key envelope can be wrapped and unwrapped cryptographically through the prototype SDK API.
- Used `MatrixMockServer` crypto helpers to create Alice and Bob clients with mocked Matrix crypto endpoints, device keys, one-time-key claiming, and encrypted room state.
- Proved Alice can wrap a per-call media key into an opaque envelope for Bob and Bob can unwrap it back to the original key material.
- Proved the opaque envelope serialization and debug output do not contain the test media key material.
- Added fail-closed coverage for wrong call ID, room ID, sender, recipient, intent, and key ID.
- Added non-recipient coverage showing a third client cannot unwrap an Alice-to-Bob envelope.
- Added conservative trust-policy coverage showing `OnlyTrustedDevices` rejects the current unverified test peer device set with `TrustViolation`.
- Added multi-device coverage showing envelopes include all eligible Bob devices and Bob's second device can unwrap the envelope.
- Confirmed `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib` passes.
- Confirmed `cargo check -p matrix-sdk-ffi` passes.
- Committed the SDK prototype and crypto tests as `f7c2cfe5c Add direct-call media key envelope crypto tests`.
- Did not publish wrapper artifacts, update the app dependency pin, modify app production code, or activate production direct calls.
- Recommended next phase: build/publish the Swift wrapper artifact from the proven SDK commit, then adapt the app key-wrapping seam to async SDK-backed wrapping in a later phase.

## 2026-05-12 — 2.10R Matrix SDK Direct-Call Key Envelope Wrapper Publication

- Revalidated the SDK commit `f7c2cfe5c Add direct-call media key envelope crypto tests` with `cargo check -p matrix-sdk-ffi` and focused `direct_call` SDK tests.
- Created and pushed SDK tag `salemx-direct-call-key-envelope-f7c2cfe5c`.
- Built a full Release `MatrixSDKFFI.xcframework` for iOS device and simulator targets from the proven SDK commit.
- Published the reproducible artifact at the Matrix SDK release URL and verified the downloaded checksum: `654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e`.
- Regenerated the Swift wrapper bindings so MatrixRustSDK exposes the direct-call media key envelope records and async wrap/unwrap methods.
- Updated wrapper `Package.swift` to use the real release asset URL and checksum, with no local binary target path.
- Validated wrapper `swift package resolve`, `swift package describe`, API presence, path scan, and `git diff --check`.
- Committed wrapper changes as `1e58d0a Add direct-call media key envelope bindings` and tagged `salemx-matrix-rust-components-swift-26.03.10-salemx.3`.
- Pinned the app to wrapper commit `1e58d0a4317e3ff74c2d565cf532bc8d035bcc8f` in `project.yml`, the generated Xcode project, and `compound-ios/Package.resolved`.
- Ran focused app unit tests for production key wrapping and media engine coverage after the pin.
- Ran the app Release build after the pin.
- Kept production direct calls disabled; no visible UI, Element Call route, CallKit, push, or production feature activation was changed.
- Recommended next phase: adapt the app production key-wrapping seam to the async SDK envelope API while preserving fail-closed default behavior.

## 2026-05-12 — 2.10S App Async Matrix SDK Key Wrapper Skeleton

- Inspected the generated MatrixRustSDK Swift API from the pinned wrapper artifact.
- Confirmed the direct-call media key envelope SDK methods are async on `EncryptionProtocol`:
  - `wrapDirectCallMediaKey(info:)`
  - `unwrapDirectCallMediaKeyEnvelope(info:envelope:)`
- Confirmed the generated SDK models carry call, room, sender, recipient, intent, key ID, expiry, and opaque ciphertext metadata without exposing raw Matrix event JSON.
- Migrated the app key wrapping boundary to async in `DirectCallMediaKeyWrappingProtocol`.
- Migrated `DirectCallEncryptionServiceProtocol` key generation and remote key consume methods to async, with `DirectCallEngine` awaiting them in already-async call paths.
- Added `MatrixSDKDirectCallMediaKeyWrapper`, a production-shaped adapter that maps app wrap/unwrap request models to the generated SDK FFI models and maps SDK envelopes/results back to app models.
- Kept the SDK-backed wrapper fail-closed when no SDK encryption dependency is injected.
- Kept `FailClosedDirectCallMediaKeyWrapper` as the default production wrapper and did not inject the SDK-backed wrapper into runtime production dependencies.
- Added tests with a fake SDK adapter proving request mapping, envelope/result mapping, SDK failure mapping, redacted descriptions, and fail-closed missing dependency behavior.
- Confirmed diagnostic encryption remains compatible with the async protocol and still isolated behind DEBUG/integration gates.
- Ran focused app unit tests for production key wrapping, direct-call engine, and media engine coverage.
- Ran the app Release build.
- Committed app changes as `9882b6ffa Add async Matrix SDK direct-call key wrapper`.
- Recommended next phase: inspect or add the narrow production dependency injection seam that supplies a Matrix SDK direct-call key envelope wrapper to the production factory while keeping runtime activation disabled.

## 2026-05-12 — 2.10T Production SDK Key Wrapper Injection Seam

- Inspected the app-side async `MatrixSDKDirectCallMediaKeyWrapper`, production encryption service, production dependency factory, room-flow ownership path, and SDK proxy boundaries.
- Chose a narrow dependency seam on `NativeDirectCallProductionDependenciesFactory` instead of exposing `MatrixRustSDK.EncryptionProtocol` or raw SDK client access through app-wide room/client protocols.
- Added support for passing `MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol` into the production dependencies factory.
- The factory now constructs `MatrixSDKDirectCallMediaKeyWrapper` from that narrow envelope wrapper when production dependencies are explicitly enabled.
- Preserved explicit `DirectCallMediaKeyWrappingProtocol` precedence so tests and future runtime integration can override the SDK wrapper cleanly.
- Preserved default fail-closed behavior: missing production config or missing wrapper still leaves production dependencies disabled or backed by `FailClosedDirectCallMediaKeyWrapper`.
- Added tests proving the factory can construct and use the SDK-backed wrapper from the narrow envelope seam, and that an explicit wrapper prevents SDK wrapper use.
- Confirmed no visible UI, Element Call route, CallKit, push, production feature flag, broad raw API, or diagnostic secret/token path changed.
- Ran focused direct-call and RoomFlow unit tests, Release build, SwiftFormat/SwiftLint on changed files, `git diff --check`, and the direct-call forbidden scan.
- Committed app changes as `000d1f12d Add production key wrapper injection seam`.
- Recommended next phase: inspect/add a runtime provider seam that can obtain the SDK encryption object from the session/client layer and expose only a direct-call envelope wrapper to production dependency construction.

## 2026-05-12 — 2.10U Production Runtime SDK Key Wrapper Provider Seam

- Inspected the SDK-backed key wrapper, production dependency factory, `ClientProxy`, room-flow construction path, and existing SDK encryption usage.
- Added `DirectCallMediaKeyEnvelopeWrappingProviding`, a narrow provider protocol that exposes only a direct-call media key envelope wrapper.
- Kept broad app protocols unchanged: `ClientProxyProtocol`, `RoomProxyProtocol`, and `TimelineProxyProtocol` do not expose raw MatrixRustSDK client, room, timeline, event JSON, or crypto APIs.
- Made concrete `ClientProxy` provide `MatrixSDKDirectCallMediaKeyEnvelopeWrapperAdapter` from its private `client.encryption()` dependency.
- Updated `NativeDirectCallProductionDependenciesFactory` to use dependencies in safe precedence order:
  - explicit `DirectCallMediaKeyWrappingProtocol`
  - explicit `MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol`
  - runtime `DirectCallMediaKeyEnvelopeWrappingProviding`
  - `FailClosedDirectCallMediaKeyWrapper`
- Ensured the factory does not ask the runtime provider while production configuration is disabled.
- Added tests proving provider-absent fail-closed behavior, provider-backed SDK wrapper construction, and explicit wrapper precedence.
- Confirmed diagnostic direct-call encryption and LiveKit paths remain unaffected.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and RoomFlow unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `2f8bc409a Add production key envelope provider seam`.
- Recommended next phase: inspect/add a disabled production dependency assembly seam that can combine production config, token transport/auth, LiveKit client, shared media key store, and the key envelope provider without activating UI or production direct calls.

## 2026-05-13 — 2.10V Disabled Production Direct-Call Dependency Wiring

- Inspected production direct-call dependency construction across the production configuration, token client, HTTP transport, Matrix access-token provider, LiveKit client, SDK key envelope provider, and room-flow ownership seams.
- Added `NativeDirectCallProductionDependencyAssembly`, a disabled-by-default assembly seam that combines explicit production configuration with injected runtime providers.
- The assembly requires production config, HTTP transport, Matrix access-token provider, LiveKit client, key envelope provider, and own user ID before creating production dependencies.
- Missing configuration or any required runtime provider returns disabled/fail-closed dependencies.
- The assembly creates `ProductionDirectCallLiveKitTokenClient` from injected transport/auth only when explicitly configured, preserving the no-real-network-by-default behavior.
- Added narrow `ClientProxy` conformance to `DirectCallMatrixAccessTokenProviding` so future runtime wiring can provide the Matrix access token without broadening `ClientProxyProtocol`.
- Added tests proving default-disabled behavior, missing-provider fail-closed behavior, and fully injected assembly behavior using fake HTTP/auth/LiveKit/key-envelope providers.
- Confirmed diagnostic direct-call encryption and LiveKit paths remain isolated behind DEBUG/integration gates.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and RoomFlow unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `e9a1c8d1f Add disabled production direct-call dependency wiring`.
- Recommended next phase: inspect/add a guarded production room-flow injection seam that can pass assembled production dependencies to native direct-call room ownership without activating visible UI or production direct calls.

## 2026-05-13 — 2.10W Production Activation Gate Design Inspection

- Inspected `AppSettings`, existing feature flags, `directOneToOneCallsEnabled`, remote settings hooks, Element well-known handling, client/server capability surfaces, AppCoordinator session setup, flow coordinator injection, and native direct-call production dependency assembly.
- Confirmed `directOneToOneCallsEnabled` should not be reused as the native production activation switch because it currently belongs to the existing direct-call/Element Call placeholder path and explicitly logs that production signal transport is disabled.
- Recommended a multi-factor activation model: app rollout configuration, authenticated server capability, token endpoint discovery, production dependency readiness, encrypted 1:1 room eligibility, and future UI/CallKit readiness.
- Recommended a SalemX-specific Matrix client capability as the authoritative production server gate, instead of a local Developer Options toggle or diagnostic environment variable.
- Recommended endpoint discovery through an authenticated capability that advertises a same-origin relative token endpoint, with the existing unstable token path as the default contract.
- Recommended `.well-known` only for pre-auth hints or account/provider policy, not as sufficient production activation authority.
- Confirmed diagnostics must remain separate: DEBUG/integration env gates and runner tokens/secrets must not affect production activation.
- Did not modify app code, activate production direct calls, add UI, change Element Call routing, or wire CallKit/push.
- Recommended next phase: add a fail-closed production activation gate/configuration skeleton and capability DTOs/tests without threading it into visible runtime behavior.

## 2026-05-13 — 2.10X Production Direct-Call Activation Gate Skeleton

- Added `DirectCallProductionServerCapability` to model the SalemX native direct-call capability `kz.salemx.direct_call.native`.
- Modeled the supported production capability shape as version `1`, audio intent support, LiveKit media transport, E2EE required, and Matrix SDK direct-call media key envelope support.
- Added same-origin token endpoint resolution from a relative server-advertised path, plus a same-origin configured endpoint override for future controlled rollout.
- Added `DirectCallProductionRoomEligibility` with redacted room eligibility fields for encrypted direct 1:1 room checks.
- Added `DirectCallProductionActivationGate`, which is disabled by default and requires app rollout, server capability, same-origin endpoint, production dependency readiness, and room eligibility before returning enabled.
- Added redacted activation decisions and fail-closed disabled reasons for each modeled prerequisite.
- Added unit tests proving default-disabled behavior, capability decoding/redaction, every modeled fail-closed prerequisite, same-origin endpoint handling, and the fully modeled enabled decision.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `dfdd74d62 Add production direct-call activation gate`.
- Recommended next phase: add or inspect a fail-closed server capability discovery seam that can feed the activation gate without activating production direct calls.

## 2026-05-13 — 2.10Y Production Direct-Call Server Capability Discovery Seam

- Inspected the activation gate, production configuration, dependency assembly, `ClientProxy.isLiveKitRTCSupported`, `.well-known` handling, and existing server/client capability surfaces.
- Found no existing narrow authenticated Matrix client capability API for the SalemX native direct-call capability; the existing LiveKit RTC support helper and `.well-known` patterns are separate and not sufficient for production activation.
- Added `DirectCallProductionCapabilityProviding`, an async provider seam that can eventually supply the SalemX native direct-call capability to the activation gate.
- Added `FailClosedDirectCallProductionCapabilityProvider`, which is the default provider and returns a redacted `providerUnavailable` result.
- Added `DirectCallProductionCapabilityPayloadDecoder` to decode the Matrix capabilities envelope for `kz.salemx.direct_call.native`, while failing closed for missing or malformed payloads.
- Kept same-origin endpoint validation centralized in `DirectCallProductionActivationGate` rather than duplicating activation decisions in discovery.
- Added tests for valid capability discovery, missing capability, malformed capability, unsupported capability fields flowing into activation-gate failures, and redacted descriptions.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, real network fetch, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `e18c9ff9f Add production direct-call capability discovery seam`.
- Recommended next phase: inspect or add a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder from session/client networking without activating production direct calls.

## 2026-05-13 — 2.10Z Production Activation Decision Assembly Skeleton

- Added `DirectCallProductionActivationDeciding` as the narrow async production activation decision boundary.
- Added `DirectCallProductionActivationDecisionService` to assemble app rollout configuration, server capability discovery, production dependency readiness, homeserver URL, and room eligibility through `DirectCallProductionActivationGate`.
- Added `NativeDirectCallProductionDependencyProviding` so dependency readiness can be supplied or faked without constructing listeners, media engines, room owners, or visible runtime behavior.
- Kept default behavior disabled: default configuration returns `appRolloutDisabled` and does not query capability or dependency providers.
- Kept capability failures fail-closed: missing or malformed capability discovery returns `serverCapabilityUnavailable` and skips dependency readiness checks.
- Added tests for disabled config, missing/malformed capability, unsupported capability, external endpoint, unavailable dependencies, ineligible room, fully valid enabled decision, provider call counts, and redaction.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, real network fetch, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `39c5b5dc4 Add production direct-call activation decision assembly`.
- Recommended next phase: add or inspect a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder from session/client networking without activating production direct calls.

## 2026-05-13 — 2.11A Production Activation Dry-Run Diagnostics

- Added `DirectCallProductionActivationDryRunDiagnostic`, a redacted diagnostic model for activation status, disabled reason, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
- Added `DirectCallProductionActivationDryRunDiagnosing` on the existing activation decision service.
- Kept the final answer delegated to `DirectCallProductionActivationGate`, so dry-run diagnostics share the same fail-closed activation logic as the production decision path.
- Kept default behavior disabled: default configuration returns `appRolloutDisabled` and does not query capability or dependency providers.
- Kept missing capability fail-closed: capability discovery failure returns `serverCapabilityUnavailable` and skips dependency readiness checks.
- Added tests proving bad room eligibility is redacted, all-valid input returns an enabled dry-run model, and no key generation, key consume, key cleanup, media engine construction, listener start, controller creation, signalling, or Matrix send work happens.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, real network fetch, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `5d58718ac Add production direct-call activation dry-run diagnostics`.
- Recommended next phase: add or inspect a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder and dry-run decision from session/client networking without activating production direct calls.

## 2026-05-13 — 2.11B Room-Scoped Production Activation Dry-Run Seam

- Added `NativeDirectCallProductionActivationDryRunProviding` as a room-scoped seam for redacted production native direct-call activation readiness.
- Added `FailClosedNativeDirectCallProductionActivationDryRunProvider`, which returns disabled with `roomUnavailable` before a room is active or when no provider is injected.
- Added `NativeDirectCallProductionActivationDryRunProvider`, which delegates to `DirectCallProductionActivationDryRunDiagnosing` with injected homeserver URL and room eligibility.
- Added `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()` so future internal/debug tooling can ask for the current room's production activation readiness without starting listeners, controllers, media, signalling, Matrix sends, or UI.
- Threaded a dry-run provider factory alongside the existing native direct-call room-flow owner factory, defaulting to fail-closed and clearing it when the room owner resets.
- Added room-flow tests for no-active-room fail-closed behavior, active-room delegation, missing capability redaction, and no side effects on prepare/start/outgoing/accept/hangup/stop/reset paths.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, real network fetch, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and room-flow unit tests, Release build, and a direct-call forbidden scan over added lines.
- Committed app changes as `8535cfb0d Add room-scoped production direct-call dry-run seam`.
- Recommended next phase: add or inspect a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder and room-scoped dry-run decision from session/client networking without activating production direct calls.

## 2026-05-13 — 2.11C Debug/Internal Production Activation Dry-Run Command Exposure

- Added a DEBUG/integration-only `nativeDirectCallProductionActivationDryRun` signal and redacted result to `UITestsSignalling`.
- Routed the dry-run command through AppCoordinator, UserSessionFlowCoordinator, ChatsTabFlowCoordinator, and the current RoomFlowCoordinator room-scoped dry-run provider.
- Added `production-activation-dry-run A|B` / `productionActivationDryRun A|B` to the two-client diagnostic runner.
- Kept the command read-only: it does not prepare native direct-call controllers, start listeners, start outgoing calls, accept calls, construct media engines, or send Matrix events.
- Limited output to redacted activation readiness fields: enabled state, disabled reason, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
- Added tests for signal encoding/redaction and ChatsTab room-scoped dry-run delegation without call side effects.
- Confirmed production direct calls remain disabled by default; `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env influence on production decisions, raw Matrix payloads, credentials, or key material were added.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, runner syntax/dry-run checks, focused direct-call and room-flow unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `83c967478 Expose production direct-call dry-run diagnostic command`.
- Recommended next phase: add or inspect a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder and room-scoped dry-run decision from session/client networking without activating production direct calls.

## 2026-05-13 — 2.11D Production Activation Dry-Run Runtime Proof

- Ran the DEBUG/integration diagnostic harness against both clients after app diagnostic signalling readiness.
- Confirmed A and B both responded to the normal status command before the production activation dry-run query.
- `production-activation-dry-run A` returned the redacted disabled result: `enabled=false`, `reason=appRolloutDisabled`, `capabilityPresent=false`, `dependenciesReady=false`, `roomEligible=true`, and `endpointAccepted=false`.
- `production-activation-dry-run B` returned the same redacted disabled result.
- Confirmed no production call started and the dry-run did not trigger listener, media, or Matrix send side effects.
- Confirmed the disabled state is expected because production rollout remains off by default.
- No app code changed for this phase.
- Recommended next phase: inspect where app rollout configuration and authenticated server capability discovery should be sourced and threaded so dry-run checks can move beyond `appRolloutDisabled` without activating production direct calls.

## 2026-05-13 — 2.11E App Rollout and Capability Config Source Inspection

- Inspected `AppSettings`, `AppSettingsHook`, `RemoteSettingsHook`, `RemotePreference`, AppCoordinator session construction, ClientProxy capability helpers, production direct-call configuration, activation gate, activation decision service, dependency assembly, and room-scoped dry-run seams.
- Confirmed `directOneToOneCallsEnabled` remains the wrong activation source for native production direct calls because it belongs to the existing direct-call/Element Call placeholder path and must remain separate.
- Recommended a separate app-owned production rollout source that defaults false, is not user-facing, and is not diagnostic-env backed; `AppSettings` plus hook/remote-preference style configuration is the natural app-level home.
- Recommended authenticated Matrix `/capabilities` as the authoritative server capability source for `kz.salemx.direct_call.native`.
- Confirmed `.well-known` should remain at most a pre-auth hint or remote settings input and must never activate production direct calls by itself.
- Found the current app/Swift SDK surface has `ClientProxy.isLiveKitRTCSupported` and versions helpers, but no narrow generic authenticated `/capabilities` fetch for the SalemX native direct-call capability.
- Recommended a narrow provider using `DirectCallHTTPTransportProtocol` and `DirectCallMatrixAccessTokenProviding` to fetch `/_matrix/client/v3/capabilities`, avoid broad Matrix SDK exposure, and pass only response data into `DirectCallProductionCapabilityPayloadDecoder`.
- Recommended keeping token endpoint discovery same-origin and relative by default; absolute/external endpoints remain rejected unless a future explicit same-origin app override is provided.
- Found a sequencing issue: dependency readiness currently depends on `DirectCallProductionConfiguration.tokenEndpointBaseURL`, but production activation should usually derive the token endpoint from server capability. The next code phase should split side-effect-free runtime prerequisite readiness from endpoint-specific dependency assembly, or assemble dependencies after the activation gate accepts an endpoint.
- No app code changed and production direct calls remain disabled/fail-closed.
- Recommended next phase: add a default-disabled rollout configuration provider and fail-closed authenticated capabilities provider skeleton, then thread them toward dry-run decision construction without starting listeners, media, Matrix sends, UI, Element Call, CallKit, or push.

## 2026-05-13 — 2.11F Fail-Closed Rollout and Capability Source Skeleton

- Added `DirectCallProductionRolloutProviding` as the app-owned rollout configuration source boundary for native production direct-call activation.
- Added `FailClosedDirectCallProductionRolloutProvider`, which returns the default disabled `DirectCallProductionConfiguration` and does not read diagnostic env, developer options, or `directOneToOneCallsEnabled`.
- Added `HTTPDirectCallProductionCapabilityProvider`, a fail-closed authenticated Matrix `/capabilities` provider backed by injected `DirectCallHTTPTransportProtocol` and `DirectCallMatrixAccessTokenProviding`.
- The provider fetches `/_matrix/client/v3/capabilities`, decodes only `kz.salemx.direct_call.native`, and maps missing config, auth, transport, non-2xx responses, missing capability, and malformed payloads to redacted fail-closed results.
- Added a `GET` request helper for direct-call HTTP transport that carries the bearer header without exposing URL or credential values in descriptions.
- Added a rollout-provider convenience initializer on `DirectCallProductionActivationDecisionService` so future dry-run construction can consume app-owned rollout config without coupling to diagnostics.
- Added focused tests proving default rollout disabled, authenticated capability fetch behavior, missing-token/missing-transport fail-closed behavior, `.well-known` non-use, external endpoint rejection by the activation gate, and redaction of bearer values and response bodies.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env influence, listener start, media engine construction, Matrix send, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Recommended next phase: inspect/add endpoint-aware production dependency readiness so capability-sourced same-origin token endpoints can feed dependency assembly without starting calls or UI.

## 2026-05-14 — 2.11G Activation Decision Uses Rollout and Capability Providers

- Refactored `DirectCallProductionActivationDecisionService` so it stores a `DirectCallProductionRolloutProviding` and asks the provider for rollout configuration at decision time.
- Added a redacted static rollout provider wrapper to preserve the existing static-configuration initializer path for tests and compatibility.
- Kept default activation behavior fail-closed: default rollout remains disabled, capability remains absent, and dependency readiness remains unavailable.
- Confirmed disabled rollout short-circuits before capability or dependency providers are queried.
- Confirmed rollout-enabled decisions query capability first, then dependency readiness, then room eligibility, with capability provider failures mapped to redacted `serverCapabilityUnavailable`.
- Added tests for default providers, rollout-enabled/capability-missing, valid-capability/dependencies-missing, dependencies-ready/room-ineligible, all-valid enabled dry-run, provider failure redaction, and no listener/media/signal side effects.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env influence, listener start, media engine construction, Matrix send, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and room-flow unit tests, Release build, and the direct-call forbidden scan.
- Recommended next phase: add endpoint-aware production dependency readiness so an activation-accepted same-origin token endpoint can feed dependency assembly without starting calls or UI.

## 2026-05-14 — 2.11I Production Activation Readiness Pack

- Added consolidated readiness tests proving production activation can only return enabled when rollout, authenticated capability, same-origin endpoint, dependency readiness, and encrypted direct 1:1 room eligibility are all valid.
- Extended fail-closed coverage for disabled rollout, missing capability, malformed capability, external endpoint rejection, unavailable dependencies, unavailable room, unencrypted room, and non-1:1 room cases.
- Strengthened dry-run signal redaction tests so encoded output excludes room IDs, peer IDs, endpoint values, credential-like fields, unwrapped key material, Matrix content, and encrypted payload values.
- Added no-side-effect checks proving the readiness path does not generate keys, consume keys, clear keys, construct media engines, start listeners, or send Matrix events.
- Confirmed production direct calls remain disabled by default and no visible UI, Element Call route, CallKit, push, listener start, media connect, or Matrix send behavior changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and room-flow unit tests, Release build, and the direct-call forbidden scan.
- Recommended next phase: inspect/add endpoint-aware production dependency readiness so activation-accepted capability endpoints can feed dependency assembly while the runtime remains disabled by default.

## 2026-05-14 — 2.12B Local Backend And App Production Token/Capability Smoke Pack

- Added a local-only fake Matrix capabilities response to the SalemX call service fake mode.
- Kept the fake capabilities endpoint gated behind `SALEMX_CALL_SERVICE_FAKE_MODE=1`; production-like service construction does not register it.
- Added backend tests for the fake capability payload and fake-only route registration.
- Added an env-gated app capability smoke test that uses `URLSessionDirectCallHTTPTransport` to fetch the local fake capability response through `HTTPDirectCallProductionCapabilityProvider`.
- Confirmed the existing env-gated token smoke continues to cover `ProductionDirectCallLiveKitTokenClient` against the local fake token endpoint.
- Added local smoke instructions in `docs/direct-call/LOCAL_BACKEND_SMOKE.md`.
- Confirmed default rollout still fails closed as `appRolloutDisabled`, and all-valid model inputs can only enable a dry-run decision in test code without runtime activation.
- Confirmed no visible UI, Element Call route, CallKit, push, listener start, media connect, Matrix send, or production activation changed.

## 2026-05-14 — 2.12C Local Backend HTTP Smoke Harness Fixed

- Fixed the local backend smoke path so the smoke tests actually execute when `SALEMX_DIRECTCALL_BACKEND_SMOKE=1` is set for the wrapper script.
- Added `Tools/Scripts/run_direct_call_backend_smoke.sh` to validate local fake backend token/capability endpoints, run the dedicated Swift Testing smoke suite, and fail if either HTTP smoke is skipped.
- Moved the local token and capability HTTP smoke tests into a dedicated `DirectCallBackendSmokeTests` suite inside an already-included test source file.
- Added a short-lived `/tmp/salemx-direct-call-backend-smoke.env` handoff because hosted simulator tests do not reliably inherit plain shell env.
- Proved default no-env behavior skips both HTTP smokes, and proved env-gated local smoke passes against the FastAPI fake backend.
- Confirmed no visible UI, Element Call route, CallKit, push, listener start, media connect, Matrix send, or production activation changed.
