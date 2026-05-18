# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.16E — internal native call panel runtime visual/action proof.

Current checkpoints:
- App code: 2.16D `Polish internal native call panel layout`
- Runner fix: 2.16C `Forward internal native call UI gate to simulator launch`
- Docs: 2.16E `Record internal native call panel runtime proof`
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
- Full internal lifecycle proof passed: B listener, A outgoing, B incoming ringing, B accept, A/B active audio, A hangup, A/B idle cleanup.
- Hidden DEBUG/internal native direct-call room control panel exists and remains hidden by default.
- With the internal UI gate enabled, the polished panel appears in both A/B encrypted DM rooms.
- The panel now uses a readable two-row layout and is not clipped.
- Initial panel visual state is `notRefreshed`, with only Refresh enabled.
- Panel status output is redacted: no tokens, keys, raw Matrix content, raw room IDs, or peer IDs.
- Existing Element Call phone/video buttons remained unchanged during runtime proof.
- Runtime proof used runner fallback actions because synthetic UI taps were unavailable, and the runner exercised the same room-scoped production methods as the panel.
- The runtime flow succeeded: B listener, A start, B incoming, B accept, A/B active audio, A hangup, A/B idle.
- Media connected on both sides, and cleanup/disconnect was attempted after hangup.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.17A — internal native call product UI transition plan.

Task:
Inspection/design only. Do not modify code. Do not commit.

Goal:
Design the safe transition from the hidden DEBUG/internal native direct-call panel toward a future product-facing native direct-call UI in encrypted 1:1 rooms, without changing existing Element Call behavior yet.

Inspect:
1. `RoomScreen.swift`
2. `RoomScreenModels.swift`
3. `RoomScreenViewModel.swift`
4. `RoomScreenCoordinator.swift`
5. `RoomFlowCoordinator.swift`
6. `RoomFlowCoordinatorAction`
7. Existing Element Call phone/video button handling
8. `JoinCallButton` and related room call toolbar/menu surfaces
9. `NativeDirectCallRoomFlowOwner` and production room-scoped command methods
10. Production activation dry-run and trigger dry-run providers
11. Internal native call panel provider and state model
12. Any existing feature flag, app rollout, server capability, and room eligibility models
13. Current analytics/event tracking around call actions if relevant

Questions:
A. What should the first product-facing native direct-call entry point be?
B. Should it be a separate native call affordance or eventually replace one existing 1:1 call affordance under a server capability gate?
C. How should the app keep Element Call routing untouched until native production readiness is complete?
D. Which activation checks must pass before any product UI shows Start/Accept/Hang up controls?
E. How should incoming ringing be surfaced before CallKit/push exists?
F. How should product UI represent unavailable states such as rollout disabled, capability missing, peer trust unavailable, or backend unavailable?
G. What state model should be promoted from the internal panel into production UI?
H. What user-visible copy will be needed later, and where should it live?
I. What tests are required before implementing a product-facing native direct-call UI?
J. What is the minimal safe implementation phase after this inspection?

Hard constraints:
- Do not modify code in this phase.
- Do not commit in this phase unless explicitly asked for docs-only tracking.
- No public production activation.
- No existing Element Call route changes.
- No `RoomScreenViewModel.displayCall` behavior changes.
- No `RoomScreenCoordinator.presentCallScreen` behavior changes.
- No `ElementCallService` changes.
- No `directOneToOneCallsEnabled` reuse for native production UI.
- No CallKit or push wiring.
- No broad Matrix SDK raw APIs.
- Do not print or store credentials, bearer values, participant credentials, media-key material, SDK envelope contents, Matrix event content, or copied secret-bearing logs.

Expected output:
1. Files inspected.
2. Recommended first product UI entry point.
3. Feature/capability/eligibility gate model.
4. State model for Start, Accept, Hang up, ringing, active, failed, and ended states.
5. How Element Call route remains untouched.
6. User-visible copy/localisation plan.
7. Test plan.
8. Risks/blockers.
9. Minimal next implementation phase.
