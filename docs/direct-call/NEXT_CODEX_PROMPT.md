# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.20E — private native call card timeout runtime proof.

Current checkpoints:
- App code: 2.20C `Prevent accidental native call restart after hangup`
- Private card rapid-action proof: 2.20D private native call card rapid Hang up / Cancel / Decline runtime proof passed on the current build.
- Private card timeout proof: 2.20E private native call card timeout runtime proof passed with the real 45s ringing timeout.
- Private card UX code: 2.19D `Add private native call card decline cancel retry actions`
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
- Full internal lifecycle proof passed through runner commands and private-card manual actions: listener, outgoing, incoming ringing, accept, active audio, hangup, idle cleanup.
- Hidden DEBUG/internal native direct-call room control panel exists and remains hidden by default.
- Private product-shaped native call room card exists and remains hidden by default.
- The private card uses the separate gate `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- The diagnostic panel remains gated separately by `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`.
- Existing Element Call phone/video buttons remained visible and unchanged during runtime proofs.
- Card status and runner output are redacted: no credential values, JWTs, keys, raw Matrix content, raw room IDs, or peer IDs were printed.
- The private card performs a safe read-only appearance refresh so the initial state can become `canStart` without manual Refresh.
- Passive card refresh is side-effect-free and does not start listeners, send Matrix events, request media credentials, connect media, or disable available actions.
- Manual UI actions were proven for the private card:
  - Start audio caused the peer to reach `incomingRinging`.
  - Accept caused A/B to reach `activeAudio`.
  - Hang up caused A/B to return idle.
- Repeated-call proof passed without relaunch:
  - First cycle: A Start audio, B Accept, A/B `activeAudio`, A Hang up, A/B idle.
  - Second cycle: A Start audio again, B Accept again, A/B `activeAudio` again, B Hang up, A/B idle.
- No stale active session or stale terminal state blocked the second call.
- Backend-off and LiveKit-off recovery proofs passed:
  - Backend-off failed closed with `tokenHTTPUnavailable`, then backend recovery reached `activeAudio` with `productionMediaFailureReason=none`.
  - LiveKit-off failed closed with `liveKitNetworkFailed`, then LiveKit recovery reached `activeAudio` with `productionMediaFailureReason=none`.
- Stale media failure cleanup is fixed and runtime-proven.
- Decline incoming proof passed:
  - B received `incomingRinging`.
  - B tapped Decline.
  - B emitted reject and send succeeded.
  - A received `directCallReject`.
  - A/B returned idle with no active session.
  - `productionMediaFailureReason=none`.
- Cancel outgoing proof passed:
  - A started outgoing.
  - A tapped Cancel before B accepted.
  - A emitted cancel and send succeeded.
  - B received `directCallCancel`.
  - A/B returned idle with no active session.
  - `productionMediaFailureReason=none`.
- Failed-state Retry/Dismiss rendering is fixed and runtime-verified:
  - `failed(callServiceUnavailable)` shows Retry and Dismiss instead of a broad disabled action row.
  - Retry does not auto-start a call.
  - A/B remained idle with no active session after Retry.
  - Dismiss clears the local displayed error/outcome.
  - The card returns to Ready to call and reports `dismissError:dismissed`.
- 2.20C added post-terminal Start Audio suppression after Hang up, Cancel, and Decline so a rapid second tap cannot immediately restart a call after the card returns to `canStart`.
- 2.20D runtime proof passed:
  - Rapid Hang up returned A/B idle with no active session; A emitted hangup; B received `directCallHangup`; cleanup/disconnect was attempted; media failure remained `none`.
  - Rapid Cancel returned A/B idle with no active session; A emitted cancel; B received `directCallCancel`; media failure remained `none`.
  - Rapid Decline passed after relaunching B onto the current 2.20C build; B emitted reject; A received `directCallReject`; A/B returned idle with no active session; media failure remained `none`.
  - No accidental `outgoingRinging` or `incomingRinging` restart occurred on the current build.
- 2.20E timeout runtime proof passed:
  - The proof used the real configured ringing timeout of 45 seconds plus a small buffer.
  - A outgoing timeout returned A/B idle with no active session.
  - A emitted `timeout`; B received `directCallTimeout`.
  - A reported `outgoingTimeout`; B reported `incomingTimeout`.
  - Reverse-direction timeout returned A/B idle with no active session.
  - B emitted `timeout`; A reported `incomingTimeout`; no receive failure was reported.
  - Media connect was not attempted and `productionMediaFailureReason=none`.
  - Outgoing and incoming timers are both 45 seconds, so caller/callee timeout emission can race; runtime still proved both sides clear safely with user-safe timeout terminal reasons.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.21B — private native call UI typed snapshot/reducer cleanup.

Task:
Refactor private native call UI state mapping into typed, testable seams without changing runtime behavior.
Do not change Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Context:
2.21A inspection found the private card is runtime-proven enough for continued gated internal lab use, but state ownership is too duplicated/stringly typed for broader internal usability:
- engine session state
- production status diagnostics
- private product card state
- ViewModel local pending/dismissed/cooldown state
- diagnostic panel state

Goals:
1. Add a typed redacted room snapshot model, e.g. `NativeDirectCallRoomSnapshot`, as the UI-facing source of truth.
2. Replace string-based session/encryption mapping with typed redacted enums.
3. Extract a pure `NativeDirectCallRoomCardStateReducer` from the current card state mapping.
4. Extract a `NativeDirectCallUserSafeReasonMapper` for activation, trust, media, timeout, terminal, and backend reasons.
5. Keep current session state separate from last outcome/error state.
6. Keep dismissed errors as ViewModel-local UI overlay state, not a mutation of call truth.
7. Keep product actions explicit: start audio, accept, decline incoming, cancel outgoing, hang up, retry, dismiss error.
8. Preserve existing behavior and runtime gates.
9. Keep diagnostic panel and runner command paths unchanged unless a purely typed adapter is needed.

Hard constraints:
- No Element Call route changes.
- No `displayCall` / `presentCallScreen` behavior changes.
- No `ElementCallService` changes.
- No `directOneToOneCallsEnabled` usage.
- No CallKit/push.
- No global production activation.
- No raw token/JWT/key/envelope/Matrix content.
- No raw room ID or peer ID in UI/logs/docs.
- Do not weaken production E2EE or trust policy.

Tests:
- Snapshot maps activation enabled + idle to `canStart`.
- Snapshot maps outgoing/incoming/connecting/active states correctly.
- Snapshot maps timeout terminal reasons to user-safe `callTimedOut`.
- Snapshot maps media/backend failures to user-safe failure reasons.
- Dismissed error state remains local and does not mutate call truth.
- Retry remains read-only and does not auto-start.
- Post-terminal Start Audio suppression still prevents accidental restart.
- Existing Start/Accept/Hang up/Decline/Cancel rows and enablement remain unchanged.
- Existing Element Call button still emits `displayCall`.
- Native card actions never emit `displayCall` or `presentCallScreen`.
- Rendering/status refresh remains side-effect-free.
- Redaction tests continue to pass.

Validation:
- git diff --check
- swiftformat/swiftlint changed Swift files
- targeted tests:
  RoomScreenViewModel native card tests
  NativeDirectCallInternalControlPanelTests
  RoomFlowCoordinatorTests if touched
  DirectCallEngineTests if touched
- Release build
- forbidden scan

Commit only if tests/build pass.

Suggested commit:
Extract native call card typed state reducer
