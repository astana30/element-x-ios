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
After 2.10S — async app-side Matrix SDK direct-call key wrapper skeleton added.

Current app code checkpoint:
9882b6ffa `Add async Matrix SDK direct-call key wrapper`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.10T — production SDK key wrapper injection seam inspection/skeleton.

Task:
Inspect and, if low-risk, add the narrow app dependency injection seam needed to provide `MatrixSDKDirectCallMediaKeyWrapper` to production direct-call dependencies.
Keep production direct calls disabled and fail-closed by default.
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
- App key wrapping and encryption service protocols are now async.
- `MatrixSDKDirectCallMediaKeyWrapper` exists and maps app models to SDK FFI models.
- `MatrixSDKDirectCallMediaKeyWrapper` is not injected into production runtime.
- `FailClosedDirectCallMediaKeyWrapper` remains the default production wrapper.

Inspect:
1. `MatrixSDKDirectCallMediaKeyWrapper`
2. `DirectCallMediaKeyWrappingProtocol`
3. `ProductionDirectCallEncryptionService`
4. `NativeDirectCallProductionDependenciesFactory`
5. `DirectCallProductionConfiguration`
6. `ClientProxyProtocol` / `ClientProxy`
7. `UserSession` / `UserSessionProtocol`
8. `JoinedRoomProxy` / room-flow direct-call construction
9. MatrixRustSDK `Client.encryption()` and generated `EncryptionProtocol`
10. Existing SDK proxy naming and dependency injection conventions

Questions:
A. What is the narrowest safe app seam for obtaining MatrixRustSDK `EncryptionProtocol` or a direct-call envelope wrapper adapter?
B. Should the seam live on `ClientProxyProtocol`, `UserSessionProtocol`, or the production direct-call dependency factory parameters?
C. Can this be done without exposing broad Matrix crypto/raw APIs?
D. Can production dependencies remain disabled unless explicit production direct-call configuration is enabled?
E. How should missing SDK encryption dependency fail closed?
F. How should trust policy be configured initially: `onlyTrustedDevices` by default, with no UI override yet?
G. What tests prove the production factory can receive an SDK-backed wrapper but does not activate by default?
H. What runtime path should eventually pass the wrapper into `NativeDirectCallRoomFlowOwner` without visible UI activation?

Allowed implementation if contained:
- Add a narrow protocol/adapter such as `DirectCallMediaKeyEnvelopeWrappingProvider` if needed.
- Add a method/property that returns only the direct-call media key envelope wrapper, not raw crypto APIs.
- Wire the production dependencies factory to accept the wrapper dependency, but keep it disabled by default.
- Add tests with fake providers/adapters proving default fail-closed behavior and explicit injection behavior.
- Do not wire the production dependency factory into visible UI or runtime feature flags.

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
  - `UnitTests/DirectCallEngineTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/RoomFlowCoordinatorTests` if room-flow injection changes
- Release build if production app files change
- Forbidden scan for raw/debug/secret terms

Expected output:
1. Files inspected.
2. Recommended injection seam.
3. Whether code changed.
4. If changed: files/tests/build results.
5. Fail-closed/default-disabled behavior.
6. Whether production direct calls remain disabled.
7. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
