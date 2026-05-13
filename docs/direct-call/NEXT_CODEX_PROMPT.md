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
After 2.11D — production activation dry-run runtime proof recorded.

Current app code checkpoint:
83c967478 `Expose production direct-call dry-run diagnostic command`

Current docs checkpoint:
Latest commit that updates `docs/direct-call` after 2.11D.

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.11E — app rollout/capability config source inspection.

Task:
Inspect where app rollout configuration and authenticated server capability discovery should be sourced and threaded for production native direct-call activation dry-run.
Inspection/design first. Do not activate production direct calls.
Do not add visible UI.
Do not modify Element Call route.
Do not wire CallKit/push.

Context:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit active proof passed.
- Backend token service skeleton exists but remains fake/skeleton for production.
- App production token DTO/client/transport/config seams exist and remain inactive by default.
- SDK high-level crypto tests proved direct-call media key envelope wrap/unwrap.
- Swift wrapper commit `1e58d0a` exposes async direct-call key envelope APIs.
- App dependency is pinned to that wrapper commit.
- `NativeDirectCallProductionDependencyAssembly` can assemble dependencies from explicit production config, HTTP transport, Matrix auth provider, LiveKit client, shared media key store, and key-envelope provider.
- `DirectCallProductionActivationGate` models app rollout, server capability, same-origin token endpoint, dependency readiness, and encrypted direct 1:1 room eligibility.
- `DirectCallProductionCapabilityProviding`, `FailClosedDirectCallProductionCapabilityProvider`, and `DirectCallProductionCapabilityPayloadDecoder` exist.
- `DirectCallProductionActivationDecisionService` assembles rollout config, capability discovery, dependency readiness, homeserver URL, and room eligibility into the activation gate.
- `NativeDirectCallProductionActivationDryRunProviding` provides a room-scoped dry-run seam.
- DEBUG/integration diagnostics expose `production-activation-dry-run A|B` through the runner and `nativeDirectCallProductionActivationDryRun` through `UITestsSignalling`.
- Runtime proof for A and B shows app diagnostics ready, status commands respond, and production activation dry-run returns the expected disabled result:
  `enabled=false`, `reason=appRolloutDisabled`, `capabilityPresent=false`, `dependenciesReady=false`, `roomEligible=true`, `endpointAccepted=false`.
- No production call started.
- The dry-run did not trigger listener, media, or Matrix send side effects.
- The disabled production state is expected.
- `directOneToOneCallsEnabled` remains separate and must not be reused for native production activation.
- Diagnostics remain separate and must not influence production activation.

Current activation capability model:
- Capability name: `kz.salemx.direct_call.native`
- Version: `1`
- Intent: `audio`
- Media transport: `livekit`
- E2EE required: `true`
- Key envelope: `matrix_sdk_direct_call_media_key_envelope_v1`
- Token endpoint: same-origin relative path, defaulting to `/_matrix/client/unstable/kz.salemx.direct_call/livekit/token`

Inspect:
1. `DirectCallProductionConfiguration`
2. `DirectCallProductionActivationDecisionService`
3. `DirectCallProductionActivationGate`
4. `DirectCallProductionCapabilityProviding`
5. `DirectCallProductionCapabilityPayloadDecoder`
6. `NativeDirectCallProductionDependencyAssembly`
7. `NativeDirectCallProductionActivationDryRunProviding`
8. `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()`
9. `AppSettings.swift`
10. Existing app rollout, feature flag, server capability, and remote settings patterns
11. `ClientProxy` and any existing Matrix capabilities or versions APIs
12. `DirectCallHTTPTransportProtocol`
13. `DirectCallMatrixAccessTokenProviding`
14. Existing homeserver URL/session construction paths

Questions:
A. Where should `DirectCallProductionConfiguration` be sourced from for app rollout without using diagnostic env?
B. Should rollout be local build config, remote app config, server capability, or a combination?
C. Where should authenticated server capability discovery be fetched from?
D. Is there an existing Matrix capabilities API in the SDK wrapper or app proxies that can be reused narrowly?
E. If not, should a `DirectCallHTTPTransportProtocol` provider fetch `/_matrix/client/v3/capabilities` with Matrix auth?
F. How should the provider be threaded into the room-scoped dry-run path without constructing listeners, media engines, or production room owners?
G. What conditions should move the dry-run result past `appRolloutDisabled` while still keeping production disabled by default?
H. How should missing rollout config, missing capability, invalid endpoint, missing dependencies, and ineligible room remain redacted?
I. What tests prove no production activation, no diagnostic-env influence, and no secret logging?
J. What minimal code skeleton is safe after inspection?

Allowed:
- Inspection/design only.
- Add a small fail-closed config/capability source skeleton only if it is obviously safe and remains unused by default.
- Reuse existing HTTP/auth seams if safe.
- Add tests with fake providers if code changes.
- Keep `.well-known` as a future pre-auth hint only, not activation authority.
- Update docs.

Do not:
- Add visible UI.
- Change `RoomScreenViewModel.displayCall`.
- Change `RoomScreenCoordinator.presentCallScreen`.
- Modify Element Call route.
- Activate `directOneToOneCallsEnabled`.
- Wire CallKit/push.
- Start native direct-call listeners globally.
- Use diagnostic env/secret/token in production.
- Expose broad Matrix SDK raw APIs.
- Expose raw Matrix event JSON, `debugInfo`, `originalJSON`, or `originalJson`.
- Log unwrapped media-key material, credentials, bearer values, JWTs, encrypted payload values, or Matrix event content.
- Run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint on changed files if code changes
- Targeted tests if code changes:
  - `UnitTests/DirectCallProductionKeyWrappingTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/DirectCallEngineTests` if protocol boundaries change
  - `UnitTests/RoomFlowCoordinatorTests` if room-flow dry-run wiring changes
- Release build if production app files change
- Direct-call forbidden scan

Expected output:
1. Files inspected.
2. Recommended rollout config source.
3. Recommended authenticated capability discovery source.
4. Whether an SDK-backed capabilities fetch exists.
5. Whether a code skeleton was added or inspection-only.
6. Fail-closed/default-disabled behavior.
7. Whether room-scoped dry-run remains side-effect-free.
8. Whether `directOneToOneCallsEnabled` remains unused for native production activation.
9. Tests/build results if code changes.
10. Whether production direct calls remain disabled.
11. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
