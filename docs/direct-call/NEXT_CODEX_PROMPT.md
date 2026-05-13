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
After 2.10W — production activation gate design inspection complete.

Current app code checkpoint:
e9a1c8d1f `Add disabled production direct-call dependency wiring`

Current docs checkpoint:
Uncommitted docs update from 2.10W inspection, unless a later session commits it.

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.10X — production direct-call activation gate skeleton.

Task:
Add a fail-closed production activation gate/configuration skeleton for native direct calls.
Do not activate production direct calls.
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
- `NativeDirectCallProductionDependencyAssembly` can assemble dependencies from explicit production config, HTTP transport, Matrix access-token provider, LiveKit client, shared media key store, and key-envelope provider.
- Missing config/provider returns disabled/fail-closed dependencies.
- 2.10W inspection recommended a multi-factor production activation gate.
- `directOneToOneCallsEnabled` should not be reused because it is coupled to the existing direct-call/Element Call placeholder path.
- Diagnostics remain separate and must not influence production activation.

Recommended activation model:
- App rollout configuration must allow native direct calls.
- Authenticated homeserver capability must advertise SalemX native direct-call support.
- Token endpoint must resolve to the expected same-origin Matrix client endpoint, preferably from a relative path advertised by capability.
- Production dependency assembly must report dependency readiness.
- Room must be encrypted, direct, 1:1, and eligible.
- Future visible UI/CallKit/push gates must stay separate and disabled for now.

Inspect:
1. `DirectCallProductionConfiguration`
2. `NativeDirectCallProductionDependencyAssembly`
3. `NativeDirectCallProductionDependencies`
4. `AppSettings` feature flag and remote preference patterns
5. `RemoteSettingsHook` and Element well-known handling
6. `ClientProxyProtocol.isLiveKitRTCSupported`
7. `ClientProxy` homeserver/server access
8. Existing capability/proxy patterns in Matrix SDK bindings
9. Room direct/encrypted metadata available to `RoomFlowCoordinator` / `JoinedRoomProxy`
10. Existing tests around production dependency factory and room-flow owner defaults

Implementation goals:
1. Add a production activation decision model, e.g. `DirectCallProductionActivationGate` or `DirectCallProductionActivationPolicy`.
2. Add capability/config DTOs for a SalemX-specific capability, e.g. `kz.salemx.direct_call.native`, but do not fetch it from a real backend yet unless an existing safe client capability seam already exists.
3. The gate should return disabled by default.
4. The gate should require all modeled conditions before returning enabled:
   - app rollout enabled
   - server capability enabled
   - valid same-origin token endpoint or configured endpoint
   - dependency readiness
   - room eligibility
5. Do not read diagnostic env.
6. Do not use `directOneToOneCallsEnabled` for production native activation.
7. Do not start listeners, construct visible UI affordances, or alter Element Call routes.
8. Add tests for each fail-closed condition and the fully modeled enabled decision using fakes.
9. Update docs when done.

Hard constraints:
- Do not expose raw Matrix event JSON.
- Do not use `debugInfo`, `originalJSON`, or `originalJson`.
- Do not log media key material.
- Do not place unencrypted media key material in Matrix event content.
- Do not expose broad raw APIs on app room/timeline/client protocols.
- Do not put LiveKit credentials or server allocation details in Matrix signalling.
- Do not use diagnostic encryption secrets or diagnostic LiveKit tokens in production paths.
- Do not modify visible UI.
- Do not change Element Call route.
- Do not activate production feature flags or `directOneToOneCallsEnabled`.
- Do not wire CallKit or push.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint on changed files
- Targeted tests:
  - `UnitTests/DirectCallProductionKeyWrappingTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/RoomFlowCoordinatorTests` if room eligibility helpers are touched
- Release build if production app files change
- Forbidden scan for raw/debug/secret terms

Expected output:
1. Files changed.
2. Activation gate model.
3. Capability/config shape.
4. Whether `directOneToOneCallsEnabled` remains unused for native production activation.
5. Fail-closed/default-disabled behavior.
6. Tests/build results.
7. Whether production direct calls remain disabled.
8. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
