# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.19C — stale media failure cleanup runtime proof.

Current checkpoints:
- App code: 2.19B `Clear stale production media failure diagnostics`
- Runner fix: 2.18C `Forward product native call UI gate to simulator launch`
- Runtime proof: 2.19C stale media failure cleanup runtime proof passed.
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
- Full internal lifecycle proof passed through runner commands: B listener, A outgoing, B incoming ringing, B accept, A/B active audio, A hangup, A/B idle cleanup.
- Hidden DEBUG/internal native direct-call room control panel exists and remains hidden by default.
- Private product-shaped native call room card seam exists and remains hidden by default.
- The private card uses the separate gate `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- The diagnostic panel remains gated separately by `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`.
- The two-client runner forwards the product UI gate into simulator launch as `SIMCTL_CHILD_NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`.
- Existing Element Call phone/video buttons remained visible and unchanged during runtime proof.
- With `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`, the private native call card appeared in both A/B encrypted DM rooms.
- Without `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, the private native call card was hidden.
- Card status and runner output were redacted: no credential values, JWTs, keys, raw Matrix content, raw room IDs, or peer IDs were printed.
- The private card performs a safe read-only appearance refresh so the initial state can become `canStart` without manual Refresh.
- Passive card refresh is side-effect-free and does not start listeners, send Matrix events, request media credentials, connect media, or disable available actions.
- Manual UI actions were proven for the private card:
  - A Start audio caused B to reach `incomingRinging`.
  - B Accept caused A/B to reach `activeAudio`.
  - A Hang up caused A/B to return idle.
- Repeated-call proof passed without relaunch:
  - First cycle: A Start audio, B Accept, A/B `activeAudio`, A Hang up, A/B idle.
  - Second cycle: A Start audio again, B Accept again, A/B `activeAudio` again, B Hang up, A/B idle.
- No stale active session or stale terminal state blocked the second call.
- Production listener and owner remained safe across repeated cycles.
- Media disconnect and cleanup were attempted after hangups.
- Production media failure remained `none` during successful cycles.
- Reverse-direction/backend-off edge proof passed:
  - B started a call.
  - A reached `incomingRinging`.
  - A accepted and sent answer successfully.
  - B received `directCallAnswer`.
  - With the local token backend unavailable during media setup, the media/token path failed closed with user-safe `tokenHTTPUnavailable`.
  - A/B returned idle with `connectingFailed`, media disconnect/cleanup attempted, and no active session remaining.
- Backend recovery proof passed:
  - Backend-off behavior failed closed with `tokenHTTPUnavailable`.
  - A/B returned idle with no active session and media disconnect/cleanup attempted.
  - After the local fake backend was restarted, private-card Start/Accept recovered to `activeAudio` on A/B with encryption ready.
  - Hangup returned A/B idle.
- LiveKit-off and recovery proof passed:
  - LiveKit-off behavior failed closed with `liveKitNetworkFailed`.
  - A/B returned idle with no stale active session and media disconnect/cleanup attempted.
  - After LiveKit was restarted, private-card Start/Accept recovered to `activeAudio` on A/B.
  - Final hangup succeeded, A emitted hangup, B received `directCallHangup`, and A/B returned idle with cleanup/disconnect attempted.
- Stale media failure cleanup is fixed and runtime-proven:
  - 2.19B clears prior retryable media failure diagnostics when a new media connect attempt starts and after successful media recovery.
  - 2.19C backend-off reproduced `tokenHTTPUnavailable`, then backend recovery reached `activeAudio` on A/B with `productionMediaFailureReason=none` on both sides.
  - 2.19C LiveKit-off reproduced `liveKitNetworkFailed`, then LiveKit recovery reached `activeAudio` on A/B with `productionMediaFailureReason=none` on both sides.
  - Final hangup returned A/B idle with no active session and cleanup/disconnect attempted.
- No raw token, JWT, key, endpoint, room ID, peer ID, or raw Matrix content was printed.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.19D — private native call card decline/cancel/retry UX skeleton.

Task:
Add private/internal native call card UX skeletons for decline, cancel, and retry actions.
Keep the card hidden by default.
Do not change Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Context:
2.19C proved stale media failure diagnostics clear after successful backend and LiveKit recovery:
- Backend-off fails closed with `tokenHTTPUnavailable`.
- Backend recovery reaches `activeAudio` with `productionMediaFailureReason=none` on A/B.
- LiveKit-off fails closed with `liveKitNetworkFailed`.
- LiveKit recovery reaches `activeAudio` with `productionMediaFailureReason=none` on A/B.
- Final hangup returns A/B idle with cleanup/disconnect attempted.

Goals:
1. Add or complete private-card action/state support for user-safe edge actions:
   - Decline incoming ringing.
   - Cancel outgoing ringing.
   - Retry after a failed call.

2. Keep action availability explicit and user-safe:
   - Start audio available only from `canStart` or appropriate retry state.
   - Accept available only for `incomingRinging`.
   - Decline available only for `incomingRinging`.
   - Cancel available only for `outgoingRinging` / pre-active connecting states.
   - Hang up available for active/ringing/connecting states where terminal cleanup is valid.
   - Retry available only after failed/ended states where readiness still passes.

3. Route actions through the existing private room-scoped production methods or add narrow private-card handler methods if needed:
   - Do not use `displayCall`.
   - Do not use `presentCallScreen`.
   - Do not use `ElementCallService`.
   - Do not use `directOneToOneCallsEnabled`.

4. Preserve side-effect-free rendering and refresh:
   - Rendering and status refresh must not start listeners, send Matrix events, request LiveKit credentials, connect media, accept, decline, cancel, or hang up.

5. Add tests:
   - Decline action is enabled only for `incomingRinging`.
   - Cancel action is enabled only for outgoing/connecting pre-active states.
   - Retry action is available after failed recoverable states and maps to a safe start path.
   - Decline/cancel emit terminal cleanup through the native private-card handler, not Element Call routes.
   - Retry clears stale user-safe failure when a later successful media connect reaches `activeAudio`.
   - Existing Start/Accept/Hangup behavior remains unchanged.
   - Redaction: no raw token/JWT/key/envelope/Matrix content, raw room ID, or peer ID.

6. Optional runtime proof after implementation:
   - Incoming decline returns both sides to idle.
   - Outgoing cancel returns both sides to idle.
   - Failed backend-off or LiveKit-off state can retry after recovery and reach `activeAudio` with `productionMediaFailureReason=none`.

Hard constraints:
- No public visible UI activation.
- No Element Call route changes.
- No `displayCall` / `presentCallScreen` changes.
- No `ElementCallService` changes.
- No `directOneToOneCallsEnabled` use.
- No CallKit/push.
- No global production activation.
- No raw token/JWT/key/envelope/Matrix content.
- No raw room ID or peer ID in UI/logs/docs.
- Do not weaken production E2EE or trust policy.

Validation:
- `git diff --check`
- SwiftFormat/SwiftLint changed Swift files if code changes.
- Targeted tests:
  - RoomScreenViewModel native call tests if card mapping changes.
  - NativeDirectCallInternalControlPanelTests if shared internal action models change.
  - RoomFlowCoordinatorTests if production command/action handling changes.
  - DirectCallEngineTests / DirectCallMediaEngineTests if engine terminal or retry behavior changes.
- Release build if app source changes.
- Forbidden scan.
- Update docs after proof/fix.

Suggested commit:
Add private native call decline cancel retry skeleton
