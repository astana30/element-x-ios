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
After 2.11C — debug/internal production activation dry-run command exposure complete.

Current app code checkpoint:
83c967478 `Expose production direct-call dry-run diagnostic command`

Current docs checkpoint:
Latest commit that updates `docs/direct-call` after 2.11C.

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.11D — production direct-call capability fetch transport inspection/skeleton.

Task:
Inspect and, if safe, add a fail-closed authenticated capability fetch provider that can obtain the Matrix capabilities response and feed `DirectCallProductionCapabilityPayloadDecoder`.
Keep production direct calls disabled by default.
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
- `DirectCallProductionActivationDryRunDiagnostic` exposes a redacted dry-run model over that same gate without starting listeners, media, signalling, controllers, or UI.
- `NativeDirectCallProductionActivationDryRunProviding` provides a room-scoped dry-run seam.
- `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()` can report a redacted disabled result before room activation or delegate to an injected room-scoped provider after room setup.
- DEBUG/integration diagnostics now expose `production-activation-dry-run A|B` through the runner and `nativeDirectCallProductionActivationDryRun` through `UITestsSignalling`.
- The dry-run command returns only redacted activation readiness fields and does not prepare native direct-call controllers, start listeners, start outgoing calls, accept calls, construct media engines, or send Matrix events.
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
1. `DirectCallProductionCapabilityProviding`
2. `DirectCallProductionCapabilityPayloadDecoder`
3. `DirectCallProductionActivationDecisionService`
4. `DirectCallProductionActivationGate`
5. `NativeDirectCallProductionActivationDryRunProviding`
6. `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()`
7. `UITestsSignalling` dry-run command exposure
8. `Tools/Scripts/run_native_direct_call_diagnostic_two_client.sh`
9. `DirectCallProductionConfiguration`
10. `NativeDirectCallProductionDependencyAssembly`
11. `ClientProxy` and `ClientProxyProtocol`
12. Existing Matrix SDK Swift bindings for client capabilities or `/capabilities`
13. Existing HTTP transport seams such as `DirectCallHTTPTransportProtocol`
14. Matrix auth provider seam `DirectCallMatrixAccessTokenProviding`
15. App settings, session construction, and existing remote settings patterns

Questions:
A. Is there an existing SDK-backed authenticated `/capabilities` fetch that can be wrapped narrowly?
B. If not, can `DirectCallHTTPTransportProtocol` plus `DirectCallMatrixAccessTokenProviding` safely support a direct Matrix capabilities fetch without broadening app APIs?
C. Should the provider be session-scoped, client-scoped, or homeserver-scoped?
D. Should it fetch only when production rollout config is enabled, or stay independent and fail closed by default?
E. How should request URL construction preserve same-origin behavior without duplicating activation-gate endpoint validation?
F. How should failures map to redacted discovery reasons?
G. How should the provider feed the room-scoped dry-run seam in a later phase without activating UI or runtime calls?
H. What tests prove no production activation, no diagnostic-env influence, and no secret logging?
I. What minimal code skeleton is safe now?

Allowed:
- Add a concrete fail-closed provider skeleton, for example `HTTPDirectCallProductionCapabilityProvider`, only if it stays unconstructed by default.
- Reuse `DirectCallHTTPTransportProtocol` and `DirectCallMatrixAccessTokenProviding` if safe.
- Add provider tests with fake transport/auth.
- Add tests proving default fail-closed behavior and no runtime activation.
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
- SwiftFormat/SwiftLint on changed files
- Targeted tests:
  - `UnitTests/DirectCallProductionKeyWrappingTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/DirectCallEngineTests` if protocol boundaries change
  - `UnitTests/RoomFlowCoordinatorTests` if room-flow dry-run wiring changes
- Release build if production app files change
- Direct-call forbidden scan

Expected output:
1. Files changed.
2. Capability fetch provider shape, or exact blocker if inspection-only.
3. Whether SDK-backed `/capabilities` fetch exists.
4. Fail-closed/default-disabled behavior.
5. Whether room-scoped dry-run remains side-effect-free.
6. Whether `directOneToOneCallsEnabled` remains unused for native production activation.
7. Tests/build results.
8. Whether production direct calls remain disabled.
9. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
