# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.13C — runtime fake-enabled production trigger dry-run proof.

Current app code checkpoint:
94b31aec8 `Add internal production direct-call trigger dry-run command`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.13D — internal production start command inspection.

Task:
Inspection/design only. Do not modify app code. Do not commit unless docs-only tracking update is explicitly needed.

Goal:
Design the first safe DEBUG/integration-only internal command that could start the production-shaped native direct-call path after `production-trigger-dry-run` reports `wouldStart=true`, without adding visible UI or activating production behavior.

Context:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit active proof passed.
- Backend token service skeleton exists and local fake mode can serve token and capability smoke responses.
- Production token DTO/client/transport/config seams exist and remain inactive by default.
- SDK and Swift wrapper expose async direct-call media key envelope APIs.
- Production key wrapper/provider seams exist but are not activated.
- Production dependency assembly exists and remains disabled by default.
- `DirectCallProductionActivationGate` models app rollout, authenticated server capability, same-origin token endpoint, dependency readiness, and encrypted direct 1:1 room eligibility.
- Room-scoped `production-activation-dry-run` exists through the DEBUG/integration diagnostic command path.
- Room-scoped `production-trigger-dry-run` exists through the DEBUG/integration diagnostic command path.
- Runtime fake-enabled `production-activation-dry-run` proof passed for A and B in an active encrypted 1:1 room.
- Runtime fake-enabled `production-trigger-dry-run` proof passed for A and B in an active encrypted 1:1 room:
  - `wouldStart=true`
  - `enabled=true`
  - `reason=none`
  - `capabilityPresent=true`
  - `dependenciesReady=true`
  - `roomEligible=true`
  - `endpointAccepted=true`
- The fake-enabled dry-run path is DEBUG/integration-only and gated by `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1` plus the existing integration diagnostic command gates.
- The runtime proofs did not start a production call, show visible UI, use Element Call routing, touch CallKit/push, start a listener, send Matrix events, connect media, request a LiveKit token, or wrap media keys.
- Production remains disabled by default.
- `directOneToOneCallsEnabled` remains unused for native production activation.

Design questions:
A. What should the first internal production start command be named and where should it live?
B. Should the first start command be outgoing-only, accept-only, or split into explicit outgoing/accept commands?
C. What activation decision must be checked immediately before any command is allowed to prepare/start native direct-call runtime?
D. Should the command reuse `NativeDirectCallRoomDeveloperCommandRouter`, or should production-shaped start commands have a separate router to avoid diagnostic/prod confusion?
E. What minimum side effects may the next phase allow under DEBUG/integration only?
F. What side effects must remain forbidden until later phases?
G. Does endpoint-aware dependency assembly need to be completed before any start command can be meaningful?
H. How should the command avoid visible UI and Element Call route changes?
I. How should it avoid CallKit, push, and global production feature activation?
J. What redacted diagnostics should be returned if the command is blocked after the activation check?
K. What tests are required to prove the command is internal-only, fail-closed by default, and side-effect audited?
L. What blockers remain before user-visible UI can be considered?

Inspect:
1. `NativeDirectCallRoomFlowOwner`
2. `NativeDirectCallRoomController`
3. `NativeDirectCallRoomDeveloperCommandRouter`
4. `RoomFlowCoordinator.nativeDirectCallProductionTriggerDryRunDiagnostic()`
5. `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()`
6. `DirectCallProductionActivationDecisionService`
7. `NativeDirectCallProductionDependencyAssembly`
8. `DirectCallProductionConfiguration`
9. `AppCoordinator` DEBUG/integration diagnostic construction
10. `UITestsSignalling` command routing
11. `Tools/Scripts/run_native_direct_call_diagnostic_two_client.sh`
12. Existing tests around trigger dry-run, activation dry-run, signalling, and diagnostic commands

Hard constraints:
- No visible UI.
- No `RoomScreenViewModel.displayCall` changes.
- No `RoomScreenCoordinator.presentCallScreen` changes.
- No Element Call route changes.
- No `directOneToOneCallsEnabled` activation or reuse.
- No CallKit/push.
- No production runtime activation.
- No production Matrix send during inspection.
- No listener start during inspection.
- No media engine construction during inspection.
- No diagnostic env/secret/token use in production activation.
- No broad Matrix SDK raw APIs.
- No raw Matrix event JSON, `debugInfo`, `originalJSON`, or `originalJson`.
- No logging unwrapped media-key material, credentials, bearer values, JWTs, encrypted-payload values, or Matrix event content.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Expected output:
1. Files inspected.
2. Recommended first internal production start command model.
3. Required activation checks before command execution.
4. Allowed and forbidden side effects for the next implementation phase.
5. Whether endpoint-aware dependency assembly must happen before start command implementation.
6. Redacted result/diagnostic model recommendation.
7. Test plan.
8. Risks/blockers.
9. Recommended next implementation phase.
10. Docs update if useful.
