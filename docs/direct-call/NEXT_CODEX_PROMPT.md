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
After 2.10T — production SDK key wrapper injection seam added.

Current app code checkpoint:
000d1f12d `Add production key wrapper injection seam`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.10U — production runtime SDK key wrapper provider seam inspection/skeleton.

Task:
Inspect and, if low-risk, add the narrow runtime provider seam needed to create a direct-call media key envelope wrapper from the Matrix SDK encryption object.
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
- App key wrapping and encryption service protocols are async.
- `MatrixSDKDirectCallMediaKeyWrapper` exists and maps app models to SDK FFI models.
- `NativeDirectCallProductionDependenciesFactory` can now accept `MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol` and construct the SDK-backed wrapper.
- The production factory still defaults to disabled/fail-closed behavior.
- No runtime session/client path currently supplies a Matrix SDK envelope wrapper to production dependency construction.
- `FailClosedDirectCallMediaKeyWrapper` remains the default production wrapper.

Inspect:
1. `MatrixSDKDirectCallMediaKeyWrapper`
2. `MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol`
3. `NativeDirectCallProductionDependenciesFactory`
4. `ClientProxy` / `ClientProxyProtocol`
5. `UserSession` / `UserSessionProtocol`
6. `JoinedRoomProxy` / native direct-call room controller construction
7. `RoomFlowCoordinator` and `NativeDirectCallRoomFlowOwner`
8. AppCoordinator production vs DEBUG/integration diagnostic dependency construction
9. MatrixRustSDK `Client.encryption()` and generated `EncryptionProtocol`
10. Existing SDK proxy naming and dependency injection conventions

Questions:
A. Where is the SDK encryption object available today without broadening app protocols?
B. Can a narrow provider be added that returns only `MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol`, not raw Matrix SDK client or raw crypto APIs?
C. Should the provider be session-scoped, client-scoped, or room-flow-scoped?
D. Can production dependencies remain disabled unless explicit production direct-call configuration is enabled?
E. How should missing SDK encryption dependency fail closed?
F. Should the initial trust policy remain `onlyTrustedDevices` with no UI override?
G. What tests prove the provider seam does not activate production calls by default?
H. What runtime path should eventually pass the provider into `NativeDirectCallRoomFlowOwner` without visible UI activation?

Allowed implementation if contained:
- Add a narrow protocol/adapter such as `DirectCallMediaKeyEnvelopeWrappingProviding` if needed.
- Add a method/property that returns only a direct-call media key envelope wrapper, not raw SDK crypto APIs.
- Wire the production dependencies factory or owner parameters to accept the provider dependency, but keep everything disabled by default.
- Add tests with fake providers/adapters proving default fail-closed behavior and explicit injection behavior.
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
  - `UnitTests/DirectCallEngineTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/RoomFlowCoordinatorTests` if room-flow/session injection changes
- Release build if production app files change
- Forbidden scan for raw/debug/secret terms

Expected output:
1. Files inspected.
2. Recommended runtime provider seam.
3. Whether code changed.
4. If changed: files/tests/build results.
5. Fail-closed/default-disabled behavior.
6. Whether production direct calls remain disabled.
7. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
