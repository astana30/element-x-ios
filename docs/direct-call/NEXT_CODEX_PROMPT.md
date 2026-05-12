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
After 2.10R — Matrix SDK direct-call media key envelope wrapper artifact published and app dependency pinned.

Current app code checkpoint:
06fdf5f28 `Pin Matrix SDK direct-call key envelope bindings`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.10S — app async production key wrapper integration inspection/skeleton.

Task:
Inspect and, if low-risk, add the app-side async production key wrapper integration skeleton for the published Matrix SDK direct-call media key envelope API.
Keep production direct calls disabled and fail-closed by default.
Do not add visible UI.
Do not modify Element Call route.
Do not wire CallKit/push.

Context:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit active proof passed.
- Backend token service skeleton exists but remains fake/skeleton for production.
- App production token DTO/client/transport/config seams exist and remain inactive by default.
- App production key-wrapping seams exist but remain fail-closed.
- SDK high-level crypto tests proved direct-call media key envelope wrap/unwrap.
- Swift wrapper commit `1e58d0a` exposes the generated direct-call envelope API.
- App dependency is pinned to that wrapper commit.
- The SDK API is async; current app key-wrapping and encryption service protocols are synchronous.

Inspect:
1. `DirectCallMediaKeyWrappingProtocol`
2. `ProductionDirectCallEncryptionService`
3. `DirectCallEncryptionServiceProtocol`
4. `DirectCallEngine` key-generation and remote-key-consume call sites
5. `DirectCallLiveKitMediaKeyStore`
6. `NativeDirectCallProductionDependenciesFactory`
7. `JoinedRoomProxy` and MatrixRustSDK `Encryption` access points
8. Generated MatrixRustSDK direct-call envelope API names and async signatures
9. Existing async patterns in app service protocols and tests

Questions:
A. Should `DirectCallMediaKeyWrappingProtocol` become async now?
B. Does `DirectCallEncryptionServiceProtocol` also need async, or can a small adapter isolate the async SDK call?
C. What is the smallest contained protocol migration that keeps diagnostic encryption tests passing?
D. Where should the SDK-backed wrapper obtain MatrixRustSDK `Encryption` without broad raw APIs?
E. What metadata should be passed from the app wrap/unwrap request into SDK wrap/unwrap info?
F. How should SDK trust-policy failures map to redacted app E2EE failure reasons?
G. How should the shared `DirectCallLiveKitMediaKeyStore` be populated only after successful wrap/unwrap?
H. What tests prove fail-closed default behavior and no production activation?

Allowed implementation if contained:
- Make app key wrapping/encryption methods async only if the required call-site changes are small and testable.
- Add a production SDK-backed wrapper type that remains unused unless explicitly injected.
- Keep `FailClosedDirectCallMediaKeyWrapper` as default.
- Add tests with fake async wrappers before wiring any SDK runtime dependency.
- Do not wire the production dependency factory into visible UI or runtime feature flags.

Hard constraints:
- Do not expose raw Matrix event JSON.
- Do not use `debugInfo`, `originalJSON`, or `originalJson`.
- Do not log media key material.
- Do not place unencrypted media key material in Matrix event content.
- Do not expose broad raw APIs on app room/timeline protocols.
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
  - `UnitTests/RoomFlowCoordinatorTests` if call sites change
- Release build if production app files change
- Forbidden scan for raw/debug/secret terms

Expected output:
1. Files inspected.
2. Async protocol migration recommendation.
3. SDK-backed wrapper injection point.
4. Metadata mapping design.
5. Fail-closed behavior.
6. Tests/build results if code changes.
7. Whether production direct calls remain disabled.
8. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
