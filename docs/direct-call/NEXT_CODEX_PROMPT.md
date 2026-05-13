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
After 2.11E — app rollout/capability config source inspection complete.

Current app code checkpoint:
83c967478 `Expose production direct-call dry-run diagnostic command`

Current docs checkpoint:
Latest commit that updates `docs/direct-call` after 2.11E.

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.11F — fail-closed rollout and capability source skeleton.

Task:
Add default-disabled app rollout configuration and fail-closed authenticated Matrix capability provider skeletons for production native direct-call activation dry-run.
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
- `DirectCallProductionActivationGate` models app rollout, server capability, same-origin token endpoint, dependency readiness, and encrypted direct 1:1 room eligibility.
- `DirectCallProductionCapabilityProviding`, `FailClosedDirectCallProductionCapabilityProvider`, and `DirectCallProductionCapabilityPayloadDecoder` exist.
- `DirectCallProductionActivationDecisionService` assembles rollout config, capability discovery, dependency readiness, homeserver URL, and room eligibility into the activation gate.
- `NativeDirectCallProductionActivationDryRunProviding` provides a room-scoped dry-run seam.
- DEBUG/integration diagnostics expose `production-activation-dry-run A|B` through the runner and `nativeDirectCallProductionActivationDryRun` through `UITestsSignalling`.
- Runtime proof for A and B shows the dry-run returns expected disabled state with `reason=appRolloutDisabled` and no listener, media, or Matrix send side effects.
- 2.11E inspection concluded rollout and server authority must stay separate:
  - App rollout should come from a separate app-owned production config source, not diagnostic env, developer options, or `directOneToOneCallsEnabled`.
  - Authenticated Matrix `/capabilities` should be the authoritative server capability source for `kz.salemx.direct_call.native`.
  - `.well-known` can remain a pre-auth hint or remote settings input only; it must not activate production direct calls by itself.
  - Current Swift SDK/app surface exposes specialized `isLiveKitRTCSupported` and versions helpers, but no narrow generic authenticated `/capabilities` fetch for the SalemX native direct-call capability.
  - A narrow `DirectCallHTTPTransportProtocol` + `DirectCallMatrixAccessTokenProviding` provider is the safest app-side capability fetch path for now.
  - Dependency readiness currently depends on `DirectCallProductionConfiguration.tokenEndpointBaseURL`, but production should normally derive the token endpoint from server capability. The code needs a two-stage readiness/assembly path or endpoint-aware dependency provider before dry-run can report dependencies ready from server capability alone.
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

Goals:
1. Add a default-disabled production rollout config provider, for example:
   - `DirectCallProductionConfigurationProviding`
   - `FailClosedDirectCallProductionConfigurationProvider`
   - optional `AppSettings`/hook-backed provider if safe

2. Add a fail-closed authenticated capability provider skeleton, for example:
   - `HTTPDirectCallProductionCapabilityProvider`
   - uses `DirectCallHTTPTransportProtocol`
   - uses `DirectCallMatrixAccessTokenProviding`
   - fetches `/_matrix/client/v3/capabilities`
   - feeds response data into `DirectCallProductionCapabilityPayloadDecoder`
   - redacts URL, bearer value, and response body in descriptions/logging

3. Keep default runtime disabled:
   - no provider constructed by default unless explicitly injected
   - no production UI path
   - no listener start
   - no media engine construction
   - no Matrix send

4. Inspect and, if safe, adjust dependency readiness modelling:
   - either split side-effect-free runtime prerequisite readiness from endpoint-specific dependency assembly
   - or allow dependency assembly/readiness to receive the activation gate's accepted token endpoint
   - do not start calls or construct media engines during dry-run

5. Keep token endpoint validation same-origin:
   - capability endpoint path must be relative and same-origin under the homeserver
   - absolute/external endpoints fail closed
   - configured endpoint override, if any, must also be same-origin

Inspect:
1. `DirectCallProductionConfiguration`
2. `DirectCallProductionActivationDecisionService`
3. `DirectCallProductionActivationGate`
4. `DirectCallProductionCapabilityProviding`
5. `DirectCallProductionCapabilityPayloadDecoder`
6. `NativeDirectCallProductionDependencyAssembly`
7. `DirectCallHTTPTransportProtocol`
8. `DirectCallHTTPTransportRequest`
9. `DirectCallMatrixAccessTokenProviding`
10. `ClientProxy` access-token provider conformance
11. `AppSettings.swift`
12. `AppSettingsHook`
13. `RemoteSettingsHook`
14. `NativeDirectCallProductionActivationDryRunProviding`
15. `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()`

Tests:
- Default rollout provider returns disabled/default configuration.
- App rollout provider, if added, defaults disabled and does not use diagnostic env.
- Capability provider fails closed with missing access token.
- Capability provider fails closed with missing/invalid homeserver URL.
- Capability provider sends authenticated GET to `/_matrix/client/v3/capabilities` with redacted request descriptions.
- Valid capabilities response maps to `DirectCallProductionCapabilityDiscoveryResult.available`.
- Missing/malformed capability maps to existing redacted fail-closed discovery reasons.
- HTTP 401/403/404/429/500 map fail-closed without logging response body.
- Direct-call dry-run remains side-effect-free and default-disabled.
- `directOneToOneCallsEnabled` remains unused for native production activation.
- No diagnostic env/secret/token is read by production config/capability sources.

Hard constraints:
- No visible UI.
- No `RoomScreenViewModel.displayCall` changes.
- No `RoomScreenCoordinator.presentCallScreen` changes.
- No Element Call route changes.
- No `directOneToOneCallsEnabled` activation or reuse.
- No CallKit/push.
- No native direct-call listener start.
- No production Matrix send.
- No media engine construction during dry-run.
- No diagnostic env/secret/token use in production.
- No broad Matrix SDK raw APIs.
- No raw Matrix event JSON, `debugInfo`, `originalJSON`, or `originalJson`.
- No logging unwrapped media-key material, credentials, bearer values, JWTs, encrypted payload values, or Matrix event content.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint on changed Swift files
- Targeted tests:
  - `UnitTests/DirectCallProductionKeyWrappingTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/DirectCallEngineTests` if protocol boundaries change
  - `UnitTests/RoomFlowCoordinatorTests` if room-flow dry-run wiring changes
- Release build if production app files change
- Direct-call forbidden scan
- Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md`

Expected output:
1. Files changed.
2. Rollout config provider behavior.
3. Capability fetch provider behavior.
4. Whether dependency readiness was split or left for a later phase.
5. Fail-closed/default-disabled behavior.
6. Whether room-scoped dry-run remains side-effect-free.
7. Whether `directOneToOneCallsEnabled` remains unused for native production activation.
8. Tests/build results.
9. Whether production direct calls remain disabled.
10. Commit hash if committed.
