# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.18C — private native call card manual lifecycle proof.

Current checkpoints:
- App code: 2.18B `Fix private native call card action delivery`
- Runner fix: 2.18C `Forward product native call UI gate to simulator launch`
- Runtime proof: 2.18C private native call card manual Start/Accept/Hang up lifecycle passed.
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
- The private card now performs a safe read-only appearance refresh so the initial state can become `canStart` without manual Refresh.
- Passive card refresh is side-effect-free and does not start listeners, send Matrix events, request media credentials, connect media, or disable available actions.
- Manual UI actions were proven:
  - B production listener was armed.
  - Manual UI Start audio from A caused B to reach `incomingRinging`.
  - Manual UI Accept from B caused A/B to reach `activeAudio`.
  - Manual UI Hang up from A caused A/B to return to idle.
- A emitted hangup and send succeeded.
- B received `directCallHangup`.
- A/B reported production media connect attempted, LiveKit client connect attempted, media disconnect attempted after hangup, media cleanup attempted after hangup, and production media failure `none`.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, or global production activation has been added.

Phase:
2.18D — private native call card repeated-call and edge-state proof.

Task:
Runtime proof first. Do not modify code unless a small UI-only or runner-only issue is found.
Do not change Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Goal:
Prove the private native call card remains stable across repeated manual call cycles and important edge states in an open encrypted 1:1 room.

Required env:
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=http://127.0.0.1:8088`

Preconditions:
- Local fake backend running.
- Local LiveKit dev server running.
- r1/r2 trusted.
- A/B launched with env.
- A/B opened same encrypted DM.
- Private native call card visible.

Checks:
1. Repeated lifecycle:
   - Arm B listener.
   - Start audio from A using the private card.
   - Accept on B using the private card.
   - Confirm A/B `activeAudio`.
   - Hang up from A using the private card.
   - Confirm A/B idle.
   - Repeat the same cycle at least once more without relaunch if feasible.

2. Edge states:
   - Start audio is not enabled while already ringing/active.
   - Accept is enabled only on B while `incomingRinging`.
   - Hang up is enabled during outgoing ringing, incoming ringing, connecting, or active audio.
   - Hang up from ringing state clears local/remote state correctly if feasible.
   - No active session remains after hangup.
   - Media disconnect/cleanup are attempted after hangup.
   - Production media failure remains `none` for the happy path.

3. Redaction and separation:
   - Card status remains user-safe/redacted.
   - Runner output remains redacted.
   - Existing Element Call phone/video buttons remain unchanged.
   - No `displayCall`, `presentCallScreen`, or `ElementCallService` involvement.
   - No CallKit, push, or global production activation.

Validation if code changes are needed:
- `git diff --check`
- SwiftFormat/SwiftLint on changed Swift files, or `bash -n` if only scripts change.
- Targeted tests relevant to touched files.
- Release build if app source changes.
- Forbidden scan for credential/key/raw-content wording in changed lines.

Expected report:
A. Whether repeated manual lifecycle passed.
B. Button enablement observations for Start, Accept, and Hang up.
C. Edge-state results.
D. Final production-status A/B.
E. Whether runner fallback was used.
F. Any UI issue.
G. Whether code changes were needed.

Suggested commit if docs-only proof is recorded later:
Record private native call card repeated-call proof
