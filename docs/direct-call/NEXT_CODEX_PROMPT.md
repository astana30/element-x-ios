# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.21C — native call card reducer runtime regression proof.

Current checkpoints:
- App code: 2.21C `Restore failed native call card retry dismiss mapping`
- Private card typed reducer cleanup: 2.21B typed snapshot/reducer/user-safe mapping cleanup landed.
- Private card reducer regression proof: 2.21C runtime recheck passed after commit `8cdae55d4`.
- Private card timeout proof: 2.20E private native call card timeout runtime proof passed with the real 45s ringing timeout.
- Private card rapid-action proof: 2.20D private native call card rapid Hang up / Cancel / Decline runtime proof passed on the current build.
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
- Manual UI actions were proven for the private card: Start audio, Accept, Hang up, Decline incoming, Cancel outgoing, Retry, and Dismiss.
- Repeated-call proof passed without relaunch.
- Reverse-direction call proof passed.
- Backend-off and LiveKit-off recovery proofs passed.
- Stale media failure cleanup is fixed and runtime-proven.
- Rapid terminal actions are hardened: rapid Hang up, Cancel, and Decline no longer accidentally restart calls.
- Outgoing and incoming timeout behavior is runtime-proven through the private native call card / production room-scoped path.
- The private native call UI now uses typed redacted snapshot/reducer/user-safe mapping seams.
- A 2.21C runtime regression was found after reducer cleanup: idle plus retained `tokenHTTPUnavailable` showed Ready/canStart instead of `failed(callServiceUnavailable)`.
- Commit `8cdae55d4` fixed the regression by restoring failed-state mapping for idle/no active session plus retained backend/media failure diagnostics.
- Runtime recheck confirmed the failed backend/token state shows Retry and Dismiss.
- Retry remains read-only and does not auto-start a call.
- Dismiss clears only the local displayed error/outcome.
- The card returns to the safe Ready to call state after Dismiss.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.21D — private native call UI state architecture follow-up.

Task:
Inspection/design first. Decide whether any additional state ownership cleanup is needed after the typed reducer cleanup and 2.21C regression fix.
Do not change Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Context:
The private native call card is now strongly runtime-proven and has typed UI state seams, but 2.21C showed that inactive-session failure diagnostics can be easy to regress. Before moving to an internal usable checkpoint, inspect whether the state architecture now clearly separates:
- current production session truth
- retained media/backend failure diagnostics
- terminal reasons
- activation/readiness
- ViewModel-local dismissed error/outcome state
- pending/cooldown action state
- diagnostic panel status

Questions:
1. Is the typed snapshot/reducer now sufficient, or should another follow-up split current session state from last failure/outcome more explicitly?
2. Should retained media failure diagnostics have a typed identity so Dismiss can hide only the exact dismissed failure while allowing fresh failures to reappear automatically?
3. Should the diagnostic panel consume the same typed snapshot, or remain separate to avoid coupling product UI and diagnostics?
4. Are there any remaining stringly typed production status fields that should be converted before internal usable checkpoint work?
5. Are current tests strong enough for inactive-session failure states, dismissed errors, retry, and recovery?
6. What additional runtime proof, if any, is needed before an internal usable checkpoint plan?

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

Expected output:
A. Files inspected.
B. Current state architecture assessment.
C. Any remaining reducer/state ownership risks.
D. Test coverage gaps.
E. Recommended next phase: either a small 2.21D implementation follow-up or 2.22A internal usable checkpoint plan.
