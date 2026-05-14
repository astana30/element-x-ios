# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.12E — runtime fake-enabled production activation dry-run proof.

Current app code checkpoint:
8b329dbc4 `Add fake-enabled production dry-run runtime harness`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.13A — internal iOS native direct-call trigger design inspection.

Task:
Inspection/design only. Do not modify app code. Do not commit unless docs-only tracking update is explicitly needed.

Goal:
Design the first safe internal iOS trigger path for native direct calls after the fake-enabled production activation dry-run can prove `enabled=true` at runtime, without adding visible UI or activating production behavior.

Context:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit active proof passed.
- Backend token service skeleton exists and local fake mode can serve token and capability smoke responses.
- Production token DTO/client/transport/config seams exist and remain inactive by default.
- SDK and Swift wrapper expose async direct-call media key envelope APIs.
- Production key wrapper/provider seams exist but are not activated.
- `DirectCallProductionRolloutProviding` exists with `FailClosedDirectCallProductionRolloutProvider`, defaulting rollout off.
- `HTTPDirectCallProductionCapabilityProvider` exists and fetches authenticated Matrix `/_matrix/client/v3/capabilities` through injected `DirectCallHTTPTransportProtocol` and `DirectCallMatrixAccessTokenProviding`.
- `DirectCallProductionActivationDecisionService` uses rollout and capability providers in a side-effect-free sequence.
- `DirectCallProductionActivationGate` models app rollout, authenticated server capability, same-origin token endpoint, dependency readiness, and encrypted direct 1:1 room eligibility.
- Room-scoped `production-activation-dry-run` exists through the DEBUG/integration diagnostic command path.
- Runtime fake-enabled dry-run proof passed for A and B in an active encrypted 1:1 room:
  - `enabled=true`
  - `reason=none`
  - `capabilityPresent=true`
  - `dependenciesReady=true`
  - `roomEligible=true`
  - `endpointAccepted=true`
- The fake-enabled dry-run path is DEBUG/integration-only and gated by `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1` plus the existing integration diagnostic command gates.
- The runtime proof did not start a production call, show visible UI, use Element Call routing, touch CallKit/push, start a listener, send Matrix events, connect media, request a LiveKit token, or wrap media keys.
- Production remains disabled by default.
- `directOneToOneCallsEnabled` remains unused for native production activation.

Design questions:
A. What should be the first internal trigger surface for native direct-call start/accept experiments?
B. Should the trigger remain inside the DEBUG/integration diagnostic command path, or should there be a separate internal-only service seam?
C. What activation decision must be checked immediately before any internal trigger is allowed to prepare/start native direct-call runtime?
D. How should the trigger avoid visible UI and Element Call route changes?
E. How should it avoid CallKit, push, and production feature activation?
F. What are the minimum side effects that an internal trigger phase may allow, and what must remain forbidden?
G. Should the next implementation target an internal outgoing trigger, incoming accept trigger, or endpoint-aware dependency readiness first?
H. What additional redacted diagnostics are needed before allowing any internal trigger to start listeners or media?
I. What tests are required to prove the trigger remains internal-only and fail-closed by default?
J. What blockers remain before user-visible UI can be considered?

Inspect:
1. `NativeDirectCallRoomFlowOwner`
2. `NativeDirectCallRoomController`
3. `NativeDirectCallRoomDeveloperCommandRouter`
4. `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()`
5. `DirectCallProductionActivationDecisionService`
6. `NativeDirectCallProductionDependencyAssembly`
7. `DirectCallProductionConfiguration`
8. `AppCoordinator` DEBUG/integration diagnostic construction
9. `UITestsSignalling` command routing
10. `Tools/Scripts/run_native_direct_call_diagnostic_two_client.sh`
11. Existing tests around dry-run, signalling, and diagnostic commands

Hard constraints:
- No visible UI.
- No `RoomScreenViewModel.displayCall` changes.
- No `RoomScreenCoordinator.presentCallScreen` changes.
- No Element Call route changes.
- No `directOneToOneCallsEnabled` activation or reuse.
- No CallKit/push.
- No production runtime activation.
- No native direct-call listener start unless a future phase explicitly scopes it as DEBUG/integration-only and side-effect audited.
- No production Matrix send.
- No media engine construction during design inspection.
- No diagnostic env/secret/token use in production activation.
- No broad Matrix SDK raw APIs.
- No raw Matrix event JSON, `debugInfo`, `originalJSON`, or `originalJson`.
- No logging unwrapped media-key material, credentials, bearer values, JWTs, encrypted-payload values, or Matrix event content.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Expected output:
1. Files inspected.
2. Recommended first internal trigger model.
3. Required activation checks before trigger execution.
4. Allowed and forbidden side effects for the next phase.
5. Whether endpoint-aware dependency readiness should happen before trigger implementation.
6. Test plan.
7. Risks/blockers.
8. Recommended next implementation phase.
9. Docs update if useful.
