# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.17C — private native call room card runtime proof.

Current checkpoints:
- App code: 2.17B `Add private native call room card seam`
- Runtime proof: 2.17C private native call room card appeared and lifecycle succeeded through runner fallback.
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
- Private product-shaped native call room card seam exists and remains hidden by default.
- The private card uses the separate gate `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- The diagnostic panel remains gated separately by `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`.
- Existing Element Call phone/video buttons remained visible and unchanged during runtime proof.
- With `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`, the private native call card appeared in both A/B encrypted DM rooms.
- Without `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, the private native call card was hidden.
- Card status and runner output were redacted: no credential values, JWTs, keys, raw Matrix content, raw room IDs, or peer IDs were printed.
- Runner fallback was used because synthetic UI taps were unavailable.
- Runtime lifecycle through room-scoped production methods succeeded: B listener, A outgoing, B incoming ringing, B accept, A/B active audio, A hangup, and A/B idle.
- Before hangup, A/B reported active audio, encryption ready, media connect attempted, LiveKit connect attempted, and media failure `none`.
- After hangup, A/B reported no active session, idle state, media disconnect attempted, media cleanup attempted, and media failure `none`.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Known UI nuance:
- The private card initially shows `unavailable(nativeCallsUnavailable)` until refreshed.
- Live visual refresh/state binding was not verified without synthetic taps.
- No new visual clipping was observed.

Phase:
2.17D — private native call card refresh/state binding polish.

Task:
Polish the private product-shaped native call room card refresh/state binding so runtime state is easier to verify and less dependent on manual Refresh.
Keep it private and hidden by default.
Do not replace existing Element Call toolbar buttons.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Goal:
Make the private card reflect room-scoped production readiness/session state more naturally, while preserving side-effect-free rendering and explicit action side effects.

Inspect:
1. `RoomScreen.swift`
2. `RoomScreenModels.swift`
3. `RoomScreenViewModel.swift`
4. `RoomScreenCoordinator.swift`
5. `RoomFlowCoordinator.swift`
6. `NativeDirectCallRoomCardState`
7. `NativeDirectCallRoomCardAction`
8. `NativeDirectCallRoomStateProviding`
9. `NativeDirectCallRoomActionHandling`
10. Existing internal diagnostic control panel state refresh behavior
11. Production status/dry-run command methods used by the room card provider

Questions:
A. Should the card perform a one-shot safe refresh when it first appears?
B. Should the card refresh after explicit card actions complete?
C. Should the card observe an existing room-flow status publisher, or stay pull-based for now?
D. How can refresh remain side-effect-free and avoid listener/media/Matrix sends?
E. How should `unavailable(nativeCallsUnavailable)` map when trigger dry-run is ready but no manual Refresh has occurred?
F. Should the card show a distinct `notRefreshed` or `checking` private state instead of an unavailable reason?
G. What minimal state/action polish is safe without creating a public product UI?

Allowed:
- Add private/internal-only state refinements if needed, such as `notRefreshed` or `checking`.
- Refresh state on card appearance if the provider exists and product UI gate is enabled, provided the refresh is side-effect-free.
- Refresh state after explicit Start, Accept, Decline, and Hang up actions complete.
- Add focused tests for state refresh and action-result mapping.
- Keep runner command path unchanged unless a small runner-only issue is found.

Hard constraints:
- Keep card hidden by default.
- Keep `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1` as the private product card gate.
- Keep `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1` as the separate diagnostic panel gate.
- Do not replace existing Element Call phone/video buttons.
- Do not change `RoomScreenViewAction.displayCall` behavior.
- Do not change `RoomScreenCoordinator.presentCallScreen` behavior.
- Do not change `ElementCallService`.
- Do not use `directOneToOneCallsEnabled` for native production UI.
- No CallKit or push wiring.
- No public production activation.
- No listener start, media connect, Matrix send, key wrapping, or credential request from rendering/status refresh.
- No credential values, JWTs, keys, SDK envelope contents, raw Matrix content, raw room IDs, or peer IDs in UI/logs/docs.

Tests:
- Product card remains hidden by default.
- Product card remains hidden without `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`.
- Product card appears with gate/provider and does not require the diagnostic panel gate.
- Initial card state no longer misleadingly reports unavailable when it is merely not refreshed, or it performs a safe initial refresh.
- Refresh/status rendering has no side effects.
- Start/Accept/Decline/Hang up refresh state after the explicit action completes.
- Native card actions never emit Element Call `displayCall` or call `presentCallScreen`/`ElementCallService`.
- State/reason text remains redacted and user-safe.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint on changed Swift files
- Targeted tests:
  - `NativeDirectCallInternalControlPanelTests`
  - `RoomFlowCoordinatorTests` if touched
  - `DirectCallProductionKeyWrappingTests` if touched
- Release build
- Forbidden scan for credential/key/raw-content wording in changed lines

Suggested commit:
Polish private native call card state refresh
