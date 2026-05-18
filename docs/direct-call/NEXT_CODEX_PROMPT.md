# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.16C — internal native call panel runtime proof.

Current checkpoints:
- App code: 2.16B `Add internal native direct-call room control panel`
- Runner fix: 2.16C `Forward internal native call UI gate to simulator launch`
- Docs: 2.16C `Record internal native call panel runtime proof`
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
- Hidden DEBUG/internal native direct-call room control panel exists.
- Without `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED`, the panel is hidden.
- With `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`, the panel appeared in both open encrypted r1/r2 DMs.
- Panel status output is redacted: no tokens, keys, JWTs, raw Matrix content, raw room IDs, or peer IDs.
- Runtime proof used runner fallback actions because synthetic UI taps were unavailable, and the runner exercised the same room-scoped production methods as the panel.
- Before hangup, A and B reached `activeAudio`, encryption ready, media connect attempted, LiveKit connect attempted, and media failure `none`.
- After hangup, A and B returned to idle with no active session; A sent hangup and B received `directCallHangup`; media disconnect/cleanup was attempted; media failure remained `none`.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.16D — internal native call panel layout/action polish.

Task:
Polish the hidden DEBUG/internal native direct-call room control panel after runtime proof.
Do not activate public production direct calls.
Do not change the Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Context:
2.16C runtime proof found one minor UI issue:
- The control row is horizontally clipped at the trailing edge, so later controls require horizontal scrolling.

Goals:
1. Inspect the panel layout in `RoomScreen.swift`, `RoomScreenModels.swift`, `RoomScreenViewModel.swift`, `RoomFlowCoordinator.swift`, and existing room composer/inset layout.
2. Improve the internal panel layout so all controls are reachable and readable in the active room width.
3. Keep the panel hidden by default and visible only under DEBUG/internal gate plus provider.
4. Preserve redacted status text only:
   - availability/state
   - activation reason
   - peer trust readiness
   - session state
   - encryption state
   - media failure reason
   - terminal reason
   - last action
5. Preserve existing Element Call toolbar behavior and route.
6. Keep runner command path unchanged unless a small test-only issue is found.
7. Add or update tests for layout/state behavior if feasible:
   - panel hidden by default
   - panel visible only with provider/gate path
   - status refresh has no side effects
   - action buttons map to provider calls
   - no displayCall/presentCallScreen/ElementCallService calls
   - no raw token/key/JWT/envelope/Matrix content in descriptions

Hard constraints:
- No public visible UI activation.
- No `RoomScreenViewModel.displayCall` changes.
- No `RoomScreenCoordinator.presentCallScreen` changes.
- No Element Call route changes.
- No `ElementCallService` changes.
- No `directOneToOneCallsEnabled` use.
- No CallKit/push.
- No global production runtime activation.
- No broad Matrix SDK raw APIs.
- Do not print or store credentials, bearer values, participant credentials, media-key material, SDK envelope contents, Matrix event content, or copied secret-bearing logs.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint on changed Swift files if Swift changes
- targeted tests:
  - `RoomScreenViewModelTests`
  - `RoomFlowCoordinatorTests`
  - `DirectCallMediaEngineTests` if touched
- Release build if app source changes
- forbidden scan

Commit only if validation passes.

Suggested commit:
Polish internal native call panel layout
