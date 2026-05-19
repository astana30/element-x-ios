# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.18E — private native call card backend-recovery and LiveKit-off edge proof.

Current checkpoints:
- App code: 2.18B `Fix private native call card action delivery`
- Runner fix: 2.18C `Forward product native call UI gate to simulator launch`
- Runtime proof: 2.18E private native call card backend-recovery and LiveKit-off edge proof passed.
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
- Diagnostic nuance from 2.18E:
  - `productionMediaFailureReason` can remain stale after recovery.
  - `tokenHTTPUnavailable` remained visible during the backend-recovered active call.
  - `liveKitNetworkFailed` remained visible after the LiveKit-recovered active call.
  - Treat this as a diagnostic/status cleanup issue, not a runtime call blocker.
- No raw token, JWT, key, endpoint, room ID, peer ID, or raw Matrix content was printed.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.19B — private native call card stale media failure cleanup.

Task:
Diagnose and fix stale production media failure reporting after a later successful private native call card recovery.
Do not change Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Context:
2.18E proved backend recovery and LiveKit recovery at runtime, but `productionMediaFailureReason` can remain stale after a later successful media connection:
- `tokenHTTPUnavailable` remained visible during a backend-recovered `activeAudio` call.
- `liveKitNetworkFailed` remained visible after a LiveKit-recovered `activeAudio` call.
- Calls still reached `activeAudio`, hangup succeeded, and cleanup/disconnect was attempted.
- This is a diagnostic/status/card state cleanup issue, not a runtime call blocker.

Goals:
1. Inspect media failure state ownership and status mapping:
   - `NativeDirectCallRoomController` diagnostics.
   - `DirectCallEngine` media connect/recovery path.
   - `DirectCallMediaEngine` / LiveKit media diagnostics.
   - production status assembly in `RoomFlowCoordinator`.
   - private native call card state/reason mapping.

2. Fix stale failure reporting safely:
   - Clear or supersede `productionMediaFailureReason` when a later media connection succeeds.
   - Ensure active `activeAudio` with successful media connection does not surface an old failure reason.
   - Preserve terminal failure reason for the failed attempt when appropriate.
   - Keep final hangup/cleanup diagnostics intact.

3. Add tests:
   - token/backend failure records user-safe failure.
   - later successful media connect clears or supersedes stale media failure.
   - LiveKit network failure records user-safe failure.
   - later successful LiveKit connect clears or supersedes stale media failure.
   - activeAudio state maps to user-safe active state, not failed, after recovery.
   - cleanup/hangup preserves idle state without reintroducing stale failure.
   - redaction: no raw token/JWT/key/envelope/Matrix content, raw room ID, or peer ID.

4. Keep scope private/internal:
   - no public UI activation.
   - no Element Call route changes.
   - no CallKit/push.
   - no global production activation.

Hard constraints:
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
  - RoomFlowCoordinatorTests if production status mapping changes.
  - DirectCallMediaEngineTests / DirectCallEngineTests if media diagnostics change.
  - DirectCallProductionKeyWrappingTests only if touched.
- Release build if app source changes.
- Forbidden scan.
- Update docs after proof/fix.

Suggested commit:
Clear stale native call media failure after recovery
