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
After 2.10V — disabled production direct-call dependency wiring added.

Current app code checkpoint:
e9a1c8d1f `Add disabled production direct-call dependency wiring`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.10W — guarded production room-flow dependency injection inspection/skeleton.

Task:
Inspect and, if low-risk, add a guarded runtime injection seam that can pass disabled-by-default production direct-call dependencies into room-flow/native direct-call ownership.
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
- `DirectCallMediaKeyEnvelopeWrappingProviding` exists.
- Concrete `ClientProxy` can provide a narrow SDK envelope wrapper backed by `client.encryption()`.
- Concrete `ClientProxy` can provide a narrow Matrix access-token provider through `DirectCallMatrixAccessTokenProviding`.
- `NativeDirectCallProductionDependencyAssembly` can assemble dependencies from explicit production config, HTTP transport, Matrix access-token provider, LiveKit client, shared media key store, and key-envelope provider.
- Missing config/provider returns disabled/fail-closed dependencies.
- Production direct calls remain disabled/fail-closed by default.

Inspect:
1. `NativeDirectCallProductionDependencyAssembly`
2. `NativeDirectCallProductionDependenciesFactory`
3. `DirectCallProductionConfiguration`
4. `URLSessionDirectCallHTTPTransport`
5. `LiveKitDirectCallClient`
6. `DirectCallLiveKitMediaKeyStore`
7. `ClientProxy` access-token and key-envelope provider conformances
8. `UserSession` / `UserSessionFlowCoordinator`
9. `ChatsTabFlowCoordinator`
10. `RoomFlowCoordinator`
11. `JoinedRoomProxy` and native direct-call room-controller creation
12. `NativeDirectCallRoomFlowOwner`
13. DEBUG/integration diagnostic owner path in `AppCoordinator`
14. Existing AppSettings/server configuration patterns

Questions:
A. Where should `NativeDirectCallProductionDependencyAssembly` be created in runtime without activating UI?
B. Should the assembly be session-scoped, room-flow-scoped, or created by a higher-level app/session factory?
C. How can explicit production config stay disabled/nil by default?
D. Where can future real `URLSessionDirectCallHTTPTransport`, `LiveKitDirectCallClient`, shared media key store, and `ClientProxy` providers be supplied without broadening app protocols?
E. Can assembled dependencies be passed to `NativeDirectCallRoomFlowOwner` while still disabled unless config is explicitly enabled?
F. How should the diagnostic DEBUG/integration path remain separate and take precedence only in diagnostics?
G. What tests prove the production injection path remains disabled by default and does not start listeners or media globally?
H. What future phase should introduce the actual guarded production config source?

Allowed implementation if contained:
- Add optional production dependency assembly parameters or closures to session/room-flow construction if they default to disabled.
- Add a test-only or fake-provider seam proving assembled dependencies can be threaded to `NativeDirectCallRoomFlowOwner` without visible UI activation.
- Add tests proving default app/session/room construction remains disabled/fail-closed.
- Keep actual production config unset by default.
- Keep diagnostic path isolated behind DEBUG/integration gates.
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
- Do not activate production feature flags or `directOneToOneCallsEnabled`.
- Do not wire CallKit or push.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint on changed files
- Targeted tests:
  - `UnitTests/DirectCallProductionKeyWrappingTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/RoomFlowCoordinatorTests`
  - `UnitTests/ChatsTabFlowCoordinatorTests` if session/chat seams change
- Release build if production app files change
- Forbidden scan for raw/debug/secret terms

Expected output:
1. Files inspected.
2. Recommended guarded production injection seam.
3. Whether code changed.
4. If changed: files/tests/build results.
5. Fail-closed/default-disabled behavior.
6. Whether production direct calls remain disabled.
7. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
