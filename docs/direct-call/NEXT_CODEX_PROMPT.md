# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.19E — private native call card decline/cancel/retry/dismiss runtime proof.

Current checkpoints:
- App code: 2.19E `Show retry dismiss actions for failed native call card`
- Private card UX code: 2.19D `Add private native call card decline cancel retry actions`
- Runtime proof: 2.19E private native call card decline/cancel/retry/dismiss runtime proof passed.
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
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.20A — private native call card timeout/rapid-tap hardening.

Task:
Harden private native call card behavior for timeouts and repeated rapid taps.
Do not change Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Context:
2.19E proved private-card decline, cancel, retry, and dismiss behavior:
- Decline incoming returns both sides idle through a reject terminal event.
- Cancel outgoing returns both sides idle through a cancel terminal event.
- Failed state renders Retry and Dismiss only.
- Retry is read-only and does not auto-start a call.
- Dismiss clears local displayed error/outcome only.
- Existing Element Call buttons remained untouched.

Goals:
1. Inspect and harden rapid-tap behavior:
   - Start audio tapped repeatedly.
   - Accept tapped repeatedly.
   - Decline tapped repeatedly.
   - Cancel tapped repeatedly.
   - Hang up tapped repeatedly.
   - Retry/Dismiss tapped repeatedly.

2. Ensure action deduplication or loading-state gating is correct:
   - No duplicate Matrix invite/answer/reject/cancel/hangup sends.
   - No duplicate media connect attempts.
   - No duplicate active sessions.
   - No stale loading state after success/failure.

3. Add or improve timeout handling if missing:
   - Outgoing ringing timeout returns local and remote state to idle/ended safely.
   - Incoming ringing timeout returns local state to idle/ended safely.
   - Terminal reason is user-safe, e.g. `callTimedOut`.
   - Timeout cleanup does not leak tokens, keys, envelopes, raw Matrix content, room IDs, or peer IDs.

4. Keep rendering and refresh side-effect-free:
   - Rendering/status refresh must not start listeners, send Matrix events, request LiveKit credentials, connect media, accept, decline, cancel, or hang up.

5. Preserve existing behavior:
   - Start/Accept/Hangup lifecycle still reaches `activeAudio` and cleans up.
   - Decline incoming and cancel outgoing still return both sides idle.
   - Retry remains read-only.
   - Dismiss remains local-only.
   - Element Call phone/video buttons remain untouched.

Tests:
- Rapid repeated Start audio invokes the native start action at most once while loading/session state is pending.
- Rapid repeated Accept invokes accept at most once.
- Rapid repeated Decline/Cancel/Hangup do not emit duplicate terminal sends.
- Retry remains read-only and does not auto-start, request token, send Matrix events, or connect media.
- Dismiss remains local-only and has no engine/session side effects.
- Timeout maps to user-safe `callTimedOut` or equivalent.
- Timed-out outgoing and incoming states clear active session safely.
- Existing canStart, incomingRinging, outgoingRinging, activeAudio, failed, ended state/action tests still pass.
- Redaction: no raw token/JWT/key/envelope/Matrix content, raw room ID, or peer ID.

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
  - DirectCallEngineTests / DirectCallMediaEngineTests if engine timeout or terminal behavior changes.
- Release build if app source changes.
- Forbidden scan.
- Update docs after proof/fix.

Suggested commit:
Harden private native call card rapid taps and timeouts
