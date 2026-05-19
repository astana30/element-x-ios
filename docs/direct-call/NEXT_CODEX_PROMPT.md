# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.18D — private native call card repeated-call and backend-off edge proof.

Current checkpoints:
- App code: 2.18B `Fix private native call card action delivery`
- Runner fix: 2.18C `Forward product native call UI gate to simulator launch`
- Runtime proof: 2.18D private native call card repeated-call and backend-off edge proof passed.
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
- No raw token, JWT, key, endpoint, room ID, peer ID, or raw Matrix content was printed.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.18E — private native call card backend-recovery and LiveKit-off edge proof.

Task:
Runtime/manual proof and light diagnostics only. Do not modify code unless a small UI-only/test-only issue is found.
Do not change Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Goal:
Prove the private native call card recovers after the backend/token failure edge and reports LiveKit-off media failure safely.
If this edge coverage is considered sufficient instead, move to `2.19A — private native call UI hardening plan` as inspection/design only.

Required env:
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=http://127.0.0.1:8088`

Preconditions:
- r1/r2 trusted.
- A/B launched with env.
- A/B opened same encrypted DM.
- Private native call card visible.
- Local fake backend and local LiveKit dev server can be started/stopped safely.

Proof 1 — backend recovery:
1. Start or restart the local fake backend.
2. Confirm A/B private card can return to a startable/readiness state after the previous `tokenHTTPUnavailable` failure.
3. Start a call from the private card.
4. Accept from the private card.
5. Confirm A/B reach `activeAudio` again.
6. Hang up and confirm A/B idle.
7. Confirm media disconnect/cleanup attempted and production media failure returns to `none` for the recovered happy path.

Proof 2 — LiveKit off:
1. Keep the fake backend running.
2. Stop the local LiveKit dev server/container.
3. Start/accept a call from the private card until media connect is attempted.
4. Confirm the UI/status reports a user-safe media failure, expected around `liveKitNetworkFailed`, `liveKitConnectFailed`, or equivalent redacted connection failure.
5. Confirm no raw LiveKit token, JWT, endpoint, key, room ID, peer ID, or raw Matrix content is printed.
6. Confirm A/B end idle or can be cleaned up with Hang up.
7. Restart LiveKit after proof.

Optional Proof 3 — move to hardening plan:
If backend recovery and LiveKit-off are already sufficient or not worth additional runtime churn, perform inspection/design only for `2.19A — private native call UI hardening plan`.

Hard constraints:
- No Element Call route changes.
- No `displayCall` / `presentCallScreen` changes.
- No `ElementCallService` changes.
- No CallKit/push.
- No global production activation.
- No raw token/JWT/key/envelope/Matrix content.
- No raw room ID or peer ID in UI/logs/docs.

Expected report:
A. Backend recovery result.
B. LiveKit-off result.
C. Final production-status A/B.
D. Any UI issue.
E. Whether code changes were needed.
F. Whether next phase should be 2.18F additional edge proof or 2.19A hardening plan.

Validation if docs/code changes are made:
- `git diff --check`
- Docs secret scan for docs-only updates.
- SwiftFormat/SwiftLint and focused tests if Swift changes.
- `bash -n` if runner changes.
- Release build if app source changes.

Suggested docs commit after proof:
Record private native call backend recovery proof
