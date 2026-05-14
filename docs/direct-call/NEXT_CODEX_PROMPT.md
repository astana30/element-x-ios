# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.11G — activation decision uses rollout/capability providers complete.

Current app code checkpoint:
This commit: `Wire production direct-call activation providers`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.11H — endpoint-aware production dependency readiness inspection/skeleton.

Task:
Inspect and, if safe, add a fail-closed endpoint-aware production dependency readiness seam for native direct calls.
Keep production direct calls disabled by default.
Do not add visible UI.
Do not modify Element Call route.
Do not wire CallKit/push.

Context:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit active proof passed.
- Backend token service skeleton exists but remains fake/skeleton for production.
- Production token DTO/client/transport/config seams exist and remain inactive by default.
- SDK and Swift wrapper expose async direct-call media key envelope APIs.
- Production key wrapper/provider seams exist but are not activated.
- `DirectCallProductionActivationGate` models app rollout, authenticated server capability, same-origin token endpoint, dependency readiness, and encrypted direct 1:1 room eligibility.
- `DirectCallProductionRolloutProviding` exists with `FailClosedDirectCallProductionRolloutProvider`, defaulting rollout off.
- `HTTPDirectCallProductionCapabilityProvider` exists and fetches authenticated Matrix `/_matrix/client/v3/capabilities` through injected `DirectCallHTTPTransportProtocol` and `DirectCallMatrixAccessTokenProviding`.
- `DirectCallProductionActivationDecisionService` now stores a rollout provider and asks it for configuration at decision time.
- Disabled rollout short-circuits before querying capability or dependency providers.
- Rollout-enabled decisions query capability, then dependency readiness, then room eligibility.
- Capability provider failures remain redacted and map to `serverCapabilityUnavailable`.
- All-valid fake inputs can produce an enabled dry-run diagnostic without listener, controller, media engine, or Matrix send side effects.
- `.well-known` is not used for activation.
- `directOneToOneCallsEnabled` remains unused for native production activation.
- Production remains disabled by default and no runtime wiring starts listeners, media, or Matrix sends.

Known sequencing issue:
- Production dependency readiness currently depends on `DirectCallProductionConfiguration.tokenEndpointBaseURL` / explicit configuration.
- Production should normally derive the token endpoint from authenticated server capability after the activation gate accepts a same-origin relative endpoint.
- Dry-run can now fetch/decode capability and consume provider-backed rollout config, but dependencies cannot become ready from a capability-sourced endpoint without either:
  - splitting side-effect-free runtime prerequisite readiness from endpoint-specific dependency assembly, or
  - making dependency readiness/assembly receive the accepted token endpoint from the activation decision path.

Goals:
1. Inspect current dependency assembly/readiness:
   - `NativeDirectCallProductionDependencyAssembly`
   - `NativeDirectCallProductionDependencyProviding`
   - `DirectCallProductionActivationDecisionService`
   - `DirectCallProductionActivationGate`
   - `DirectCallProductionConfiguration`
   - `ProductionDirectCallLiveKitTokenClient`
   - `DirectCallHTTPTransportProtocol`
   - `DirectCallMatrixAccessTokenProviding`
   - `DirectCallMediaKeyEnvelopeWrappingProviding`

2. Decide the safest model:
   - side-effect-free runtime prerequisite readiness separate from endpoint-specific dependency construction, or
   - endpoint-aware dependency provider called only after activation gate accepts the capability endpoint.

3. If safe, add a small fail-closed skeleton:
   - no production activation;
   - no listener/controller/media engine construction during dry-run;
   - no Matrix sends;
   - no visible UI path;
   - dependencies stay unavailable by default;
   - explicit fake tests can prove all-valid readiness when an accepted endpoint is supplied.

4. Keep token endpoint validation same-origin:
   - server capability token endpoint must be relative/same-origin under homeserver;
   - absolute/external endpoints fail closed;
   - configured overrides, if any, must be same-origin.

5. Update docs:
   - `docs/direct-call/STATUS.md`
   - `docs/direct-call/WORKLOG.md`
   - `docs/direct-call/NEXT_CODEX_PROMPT.md`

Tests:
- Default dependency readiness remains disabled/fail-closed.
- Runtime prerequisite readiness can be true only when required runtime providers are injected.
- Endpoint-specific dependency assembly receives an accepted same-origin endpoint, not a raw capability string.
- External endpoint remains rejected before dependency assembly.
- Dry-run remains side-effect-free and does not construct listeners, controllers, media engines, or send Matrix events.
- `directOneToOneCallsEnabled` remains unused.
- No diagnostic env/secret/token is read by production dependency readiness.
- Redacted descriptions do not include bearer values, tokens, endpoint URLs, room IDs, peer IDs, or key material.

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
  - `UnitTests/DirectCallProductionCapabilitySourceTests`
  - `UnitTests/DirectCallProductionKeyWrappingTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/RoomFlowCoordinatorTests` if room-flow dry-run wiring changes
- Release build if production app files change
- Direct-call forbidden scan

Expected output:
1. Files changed.
2. Dependency readiness model chosen.
3. Endpoint-aware assembly/readiness behavior.
4. Fail-closed/default-disabled behavior.
5. Whether room-scoped dry-run remains side-effect-free.
6. Whether `directOneToOneCallsEnabled` remains unused for native production activation.
7. Tests/build results.
8. Whether production direct calls remain disabled.
9. Commit hash if committed.
