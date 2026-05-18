# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.14E — iOS internal production native direct-call activeAudio proof.

Current code checkpoints:
- App: 2.14C `Add production LiveKit connect failure diagnostics`
- Backend: 2.14E `Fix fake backend LiveKit dev token grants`
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`

Current proven state:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit active proof passed.
- Production token DTO/client/transport/config seams exist and remain disabled by default.
- Backend token service skeleton exists with local fake mode for internal proof.
- Production Matrix SDK key envelope wrapping is integrated through a narrow provider seam.
- Production activation gate, dry-run, trigger dry-run, start command, receive listener, incoming invite handling, accept command, and media failure diagnostics exist on the DEBUG/integration internal command path.
- Local fake backend plus local LiveKit dev server reached `activeAudio` on both iOS clients through the internal production command lane.
- A and B both reported `productionEncryptionState=ready`, `productionMediaConnectAttempted=true`, `productionLiveKitClientConnectAttempted=true`, and `productionMediaFailureReason=none`.
- This proof did not add visible UI, did not change the Element Call route, did not wire CallKit/push, and did not globally activate production direct calls.

Phase:
2.15A — internal production call cleanup/hangup command.

Task:
Add a DEBUG/integration-only production hangup/end-call command for internal native direct-call sessions.
Do not add visible UI.
Do not modify the Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Goal:
Allow the runner to cleanly terminate active or ringing production native direct-call sessions created by the internal command lane, and prove both sides return to terminal/idle state with redacted diagnostics.

Suggested command shape:
- UITestsSignalling request: `nativeDirectCallProductionHangup` or `nativeDirectCallProductionEndCall`
- Runner command: `production-hangup A|B` or `production-end-call A|B`

Expected behavior:
1. Requires DEBUG/integration diagnostics.
2. Requires the dedicated production start command gate if that is the current safety model.
3. Requires a production owner for the active room.
4. If there is no active/ringing production session, return a redacted blocked/no-op result.
5. If there is an active/ringing session, send the production hangup or cancel terminal signal as appropriate.
6. Stop or disconnect media if connected.
7. Clear the production media key handle/store for the call.
8. Leave the receive listener state explicit: either retained for the current room or stopped if the owner is reset, but document and test the choice.
9. Return a redacted status summary.
10. Keep diagnostic and production owners separate.

Hard constraints:
- No visible UI.
- No `RoomScreenViewModel.displayCall` changes.
- No `RoomScreenCoordinator.presentCallScreen` changes.
- No Element Call route changes.
- No `ElementCallService` changes.
- No `directOneToOneCallsEnabled` use.
- No CallKit/push.
- No global production runtime activation.
- No broad Matrix SDK raw APIs.
- Do not print or store credentials, bearer values, participant credentials, media-key material, SDK envelope contents, Matrix event content, or copied secret-bearing logs.

Tests:
- Command is unavailable outside DEBUG/integration diagnostics.
- Command blocks/no-ops with no production owner.
- Command blocks/no-ops with no active production session.
- Command terminates outgoing ringing sessions.
- Command terminates incoming ringing sessions.
- Command terminates active audio sessions.
- Terminal signal send diagnostics are redacted.
- Media cleanup is invoked when media was connected.
- Media key cleanup is invoked and idempotent.
- Repeated hangup is idempotent and redacted.
- Remote side can observe the terminal signal and leave active/ringing state.
- Diagnostic owner remains unaffected.
- No visible UI, Element Call route, CallKit, push, or global activation behavior changes.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint on changed Swift files.
- Runner `bash -n` if scripts change.
- Targeted tests:
  - `RoomFlowCoordinatorTests`
  - `DirectCallEngineTests`
  - `DirectCallEngineSignalTransportTests`
  - `DirectCallMediaEngineTests`
  - `DirectCallProductionKeyWrappingTests`
- Release build.
- Forbidden scan for credential/key/logging regressions.

Expected report:
A. Files changed.
B. Command name and routing path.
C. Cleanup/hangup behavior.
D. Whether terminal Matrix signal is sent and redacted.
E. Media/key cleanup behavior.
F. Tests/build results.
G. Runtime command sequence to prove cleanup after `activeAudio`.
H. Commit hash.
