# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.15B — iOS internal production native direct-call full lifecycle proof.

Current checkpoints:
- App code: 2.15A `Add production direct-call hangup command`
- Docs: 2.15B `Record iOS production direct-call lifecycle proof`
- Backend: 2.14E `Fix fake backend LiveKit dev token grants`
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`

Current proven state:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit active proof passed.
- Production token DTO/client/transport/config seams exist and remain disabled by default.
- Backend token service skeleton exists with local fake mode for internal proof.
- Production Matrix SDK key envelope wrapping is integrated through a narrow provider seam.
- Production activation gate, dry-run, trigger dry-run, start command, receive listener, incoming invite handling, accept command, media failure diagnostics, and hangup command exist on the DEBUG/integration internal command path.
- Local fake backend plus local LiveKit dev server reached `activeAudio` on both iOS clients through the internal production command lane.
- The full internal lifecycle proof passed: B listener, A outgoing, B incoming ringing, B accept, A/B active audio, A hangup, A/B idle cleanup.
- A emitted hangup and send succeeded.
- B received `directCallHangup` and cleared its active production session.
- A and B both reported media disconnect and cleanup attempts, with production media failure reason `none`.
- No visible UI, Element Call route, RoomScreen call presentation, ElementCallService, CallKit, push, or global production activation has been added.

Phase:
2.16A — internal production call UI design inspection.

Task:
Inspection/design only. Do not modify code. Do not commit unless docs-only tracking is explicitly requested.
Design the first safe internal iOS UI surface for native direct calls.
Do not add visible product UI yet.
Do not modify the Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Goal:
Decide how native direct-call UI should be introduced after the internal command lane has proven full lifecycle locally, while preserving the existing Element Call route and production activation safety gates.

Inspect:
1. `RoomScreenViewModel`
2. `RoomScreenCoordinator`
3. `RoomScreen`
4. `RoomFlowCoordinator`
5. `NativeDirectCallRoomFlowOwner`
6. `NativeDirectCallRoomController`
7. Existing call button/action paths
8. Existing Element Call route and `ElementCallService`
9. Existing RoomScreen call presentation methods
10. Existing feature flags, developer diagnostics, and production activation gates
11. Existing incoming call UI patterns, if any
12. Existing media/call screen components that could be reused without coupling to Element Call

Questions:
A. What is the safest first UI surface: internal debug affordance, hidden developer option, room toolbar experiment, or separate native call screen skeleton?
B. Should the first UI remain DEBUG/integration-only, or can it be behind app rollout plus server capability gates?
C. How should UI query production activation readiness without starting listeners, media, or Matrix sends?
D. How should outgoing start require activation enabled, peer trust ready, production dependencies ready, and no active session?
E. How should incoming ringing be represented before CallKit/push exists?
F. What state should the native call screen show for ringing, connecting, active audio, failed, and terminal states?
G. How can Element Call route remain untouched until native UI is intentionally launched?
H. Which existing command-lane diagnostics should become internal UI state, and which should remain developer-only?
I. What should be tested before any visible button is added?
J. What minimal next implementation phase is safe?

Hard constraints:
- No code changes in this inspection phase.
- No visible product UI.
- No `RoomScreenViewModel.displayCall` changes.
- No `RoomScreenCoordinator.presentCallScreen` changes.
- No Element Call route changes.
- No `ElementCallService` changes.
- No `directOneToOneCallsEnabled` use.
- No CallKit/push.
- No global production runtime activation.
- No broad Matrix SDK raw APIs.
- Do not print or store credentials, bearer values, participant credentials, media-key material, SDK envelope contents, Matrix event content, or copied secret-bearing logs.

Expected output:
1. Files inspected.
2. Recommended first UI surface.
3. Why Element Call route remains untouched.
4. Required activation and trust checks.
5. Proposed UI state model.
6. Incoming call behavior before CallKit/push.
7. Test plan.
8. Minimal next implementation phase.
9. Risks/blockers.
