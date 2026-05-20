# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.20D — private native call card rapid action runtime proof.

Current checkpoints:
- App code: 2.20C `Prevent accidental native call restart after hangup`
- Private card rapid-action proof: 2.20D private native call card rapid Hang up / Cancel / Decline runtime proof passed on the current build.
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
  - The earlier failed Decline rerun was explained by B still running the pre-fix app.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.20E — private native call card timeout runtime proof.

Task:
Runtime/manual proof only. Do not modify code unless a small test-only issue is found.
Do not change Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Context:
2.20C/2.20D proved rapid terminal actions no longer accidentally restart calls on the current build:
- Rapid Hang up returns A/B idle without a new invite.
- Rapid Cancel returns A/B idle without a new invite.
- Rapid Decline returns A/B idle without a new invite after B is relaunched onto the fixed build.

Goal:
Verify private native call card timeout behavior at runtime.

Required env:
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=http://127.0.0.1:8088`

Preconditions:
- local fake backend running
- local LiveKit dev server running
- r1/r2 trusted
- A/B launched with env
- A/B opened same encrypted DM
- Existing Element Call route untouched

Proof 1 — outgoing timeout:
1. Arm B production listener if needed.
2. Start from A private card.
3. Do not accept on B.
4. Wait for outgoing timeout or use an existing short-timeout/test hook if available.
5. Confirm:
   - A returns idle/ended with user-safe timeout terminal reason.
   - B clears incoming ringing if it was received.
   - No active session remains on either side.
   - Any timeout signal is redacted and user-safe.
   - `productionMediaFailureReason=none` unless a separate media setup was attempted and failed.

Proof 2 — incoming timeout:
1. Start from A private card.
2. Wait for B to reach `incomingRinging`.
3. Do not accept or decline on B.
4. Wait for incoming timeout or use an existing short-timeout/test hook if available.
5. Confirm:
   - B clears incoming session safely.
   - A observes terminal timeout/ended state if applicable.
   - A/B return idle or ended with no active session.
   - Card/user-safe state maps to `callTimedOut` or equivalent.

Report:
A. Outgoing timeout result.
B. Incoming timeout result.
C. Final production-status A/B.
D. Whether any stale active session remained.
E. Whether status/card output remained redacted.
F. Any UI issue.
G. Whether code changes were needed.

Hard constraints:
- No displayCall/presentCallScreen changes.
- No ElementCallService changes.
- No CallKit/push.
- No global production activation.
- No raw token/JWT/key/envelope/Matrix content.
- No raw room ID or peer ID in UI/logs/docs.
- Do not weaken production E2EE or trust policy.
