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
After 2.10X — production direct-call activation gate skeleton complete.

Current app code checkpoint:
dfdd74d62 `Add production direct-call activation gate`

Current docs checkpoint:
Latest commit that updates `docs/direct-call` after 2.10X.

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.10Y — production direct-call server capability discovery seam skeleton.

Task:
Inspect and, if safe, add a fail-closed app-side seam for discovering the SalemX native direct-call server capability used by `DirectCallProductionActivationGate`.
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
- `DirectCallProductionActivationGate` now models app rollout, server capability, same-origin token endpoint, dependency readiness, and encrypted direct 1:1 room eligibility.
- The activation gate is disabled by default and is not wired into visible UI or runtime production activation.
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
1. `DirectCallProductionServerCapability`
2. `DirectCallProductionActivationGate`
3. `DirectCallProductionConfiguration`
4. `NativeDirectCallProductionDependencyAssembly`
5. `ClientProxyProtocol.isLiveKitRTCSupported`
6. `ClientProxy` homeserver/server access
7. Existing Matrix capabilities or well-known APIs exposed by MatrixRustSDK Swift bindings
8. `RemoteSettingsHook` and app remote settings patterns
9. `AppSettings` and server configuration patterns
10. Existing unit tests around production direct-call configuration and dependency assembly

Questions:
A. Is there an existing authenticated Matrix client capabilities API available through `ClientProxy` or MatrixRustSDK bindings?
B. If not, what narrow app-side protocol should represent native direct-call capability discovery?
C. Should discovery be session-scoped, client-scoped, or homeserver-scoped?
D. How should capability discovery stay fail-closed by default?
E. How should same-origin endpoint validation remain centralized in `DirectCallProductionActivationGate`?
F. Should `.well-known` be represented only as a pre-auth hint, not activation authority?
G. What tests prove no production activation and no diagnostic-env influence?
H. What minimal code skeleton is safe now?

Allowed:
- Add a protocol such as `DirectCallProductionCapabilityProviding` or `DirectCallServerCapabilityProviding`.
- Add a fail-closed default provider.
- Add DTO/parser tests if they do not require real network.
- Add fake-provider tests showing the activation gate can consume discovered capability data.
- Keep runtime UI/room-flow production activation disabled.
- Update docs.

Do not:
- Add visible UI.
- Change RoomScreenViewModel.displayCall.
- Change RoomScreenCoordinator.presentCallScreen.
- Modify Element Call route.
- Activate `directOneToOneCallsEnabled`.
- Wire CallKit/push.
- Start native direct-call listeners globally.
- Use diagnostic env/secret/token in production.
- Expose broad Matrix SDK raw APIs.
- Expose raw Matrix event JSON, `debugInfo`, `originalJSON`, or `originalJson`.
- Log unwrapped media-key material, tokens, JWTs, encrypted payload values, or raw Matrix content.
- Run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint on changed files
- Targeted tests:
  - `UnitTests/DirectCallProductionKeyWrappingTests`
  - `UnitTests/DirectCallMediaEngineTests`
  - `UnitTests/DirectCallEngineTests` if protocol boundaries change
- Release build if production app files change
- Direct-call forbidden scan

Expected output:
1. Files changed.
2. Capability discovery seam shape.
3. Whether an existing SDK capability API is available.
4. Fail-closed/default-disabled behavior.
5. Whether `directOneToOneCallsEnabled` remains unused for native production activation.
6. Tests/build results.
7. Whether production direct calls remain disabled.
8. Update `docs/direct-call/STATUS.md`, `WORKLOG.md`, and `NEXT_CODEX_PROMPT.md` when done.
