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
After 2.10U — production runtime SDK key wrapper provider seam added.

Current app code checkpoint:
2f8bc409a `Add production key envelope provider seam`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.10V — production direct-call dependency assembly inspection/skeleton.

Task:
Inspect and, if low-risk, add a disabled-by-default production dependency assembly seam for native direct calls.
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
- App key wrapping and encryption service protocols are async.
- `MatrixSDKDirectCallMediaKeyWrapper` maps app models to SDK FFI models.
- `NativeDirectCallProductionDependenciesFactory` can accept explicit key wrappers or a runtime provider.
- `DirectCallMediaKeyEnvelopeWrappingProviding` exists.
- Concrete `ClientProxy` can provide a narrow SDK envelope wrapper backed by `client.encryption()`.
- `ClientProxyProtocol`, `RoomProxyProtocol`, and `TimelineProxyProtocol` remain unchanged.
- Production direct calls remain disabled/fail-closed by default.

Inspect:
1. `NativeDirectCallProductionDependenciesFactory`
2. `DirectCallProductionConfiguration`
3. `ProductionDirectCallLiveKitTokenClient`
4. `DirectCallHTTPTransportProtocol`
5. `DirectCallMatrixAccessTokenProviding`
6. `URLSessionDirectCallHTTPTransport`
7. `DirectCallLiveKitMediaEngineFactory`
8. `LiveKitDirectCallClient`
9. `DirectCallLiveKitMediaKeyStore`
10. `DirectCallMediaKeyEnvelopeWrappingProviding`
11. `ClientProxy` provider conformance
12. `UserSession` / `UserSessionFlowCoordinator`
13. `RoomFlowCoordinator` and `NativeDirectCallRoomFlowOwner`
14. `AppCoordinator` production vs DEBUG/integration diagnostic dependency construction

Questions:
A. Where should production native direct-call dependency assembly live without activating UI?
B. Should assembly be session-scoped, room-flow-scoped, or app-coordinator-scoped?
C. How should it receive production token endpoint configuration, HTTP transport, Matrix access-token provider, LiveKit client, shared media key store, and key envelope provider?
D. Can the assembly remain nil/fail-closed unless explicit production config is enabled?
E. Can the seam be added without reading diagnostic env, using `directOneToOneCallsEnabled`, or changing visible routes?
F. How should missing backend config, access token provider, HTTP transport, LiveKit client, or key envelope provider fail closed?
G. What tests prove production runtime remains disabled by default?
H. What future phase should actually thread production dependencies into a guarded native direct-call room-flow path?

Allowed implementation if contained:
- Add a small production dependency assembler/factory wrapper if it only returns nil/fail-closed by default.
- Add initializer parameters or closure seams for production token transport/auth/key-envelope provider dependencies.
- Add tests with fakes proving disabled defaults and explicit config assembly behavior.
- Keep actual runtime UI/room-flow activation disabled.
- Update docs when done.

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
- Do not activate production feature flags.
- Do not wire CallKit or push.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint on changed files
- Targeted tests:
  - `UnitTests/DirectCallProductionKeyWrappingTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/DirectCallEngineTests`
  - `UnitTests/RoomFlowCoordinatorTests` if room-flow/session seams change
- Release build if production app files change
- Forbidden scan for raw/debug/secret terms

Expected output:
1. Files inspected.
2. Recommended production dependency assembly seam.
3. Whether code changed.
4. If changed: files/tests/build results.
5. Fail-closed/default-disabled behavior.
6. Whether production direct calls remain disabled.
7. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
