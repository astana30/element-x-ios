# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.22C — private native call relaunch/listener lifecycle runtime proof.

Current checkpoints:
- App code: 2.22B `Harden native call listener lifecycle` (`16992e5e6`).
- Private card reducer regression fix: 2.21C `Restore failed native call card retry dismiss mapping` (`8cdae55d4`).
- Private card typed reducer cleanup: 2.21B typed snapshot/reducer/user-safe mapping cleanup landed.
- Private card timeout proof: 2.20E private native call card timeout runtime proof passed with the real 45s ringing timeout.
- Private card rapid-action proof: 2.20D private native call card rapid Hang up / Cancel / Decline runtime proof passed on the current build.
- Private card relaunch/listener lifecycle proof: 2.22C passed after 2.22B lifecycle hardening.
- Backend: 2.14E `Fix fake backend LiveKit dev token grants`.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

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
- 2.22B added fail-closed listener/owner lifecycle behavior and redacted lifecycle status fields.
- 2.22C runtime proof confirmed baseline status includes `productionListenerAvailable=true`, `productionRoomAttached=true`, and `productionSessionRestorationSupported=false`.
- ActiveAudio relaunch proof passed: after A/B reached `activeAudio`, relaunching both apps and reopening the encrypted DM did not restore stale `activeAudio` or an active session.
- Ringing relaunch proof passed: after A `outgoingRinging` and B `incomingRinging`, relaunching both apps and reopening the encrypted DM did not restore stale outgoing or incoming sessions.
- Room dismiss/reopen proof passed: an armed idle B listener/owner reset after leaving and reopening the DM.
- Final lifecycle status after proof: A/B `productionListenerAvailable=true`, `productionRoomAttached=true`, `productionSessionRestorationSupported=false`, `productionHasActiveSession=false`, `productionSessionState=unavailable`, and `productionMediaFailureReason=none`.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, video, or global production activation has been added.

Phase:
2.23A — private native audio call internal dogfood readiness review.

Task:
Inspection/design only. Do not modify code. Do not commit.

Goal:
Decide whether the gated private native audio call path is ready for controlled internal dogfood, and identify the remaining must-fix items before any broader internal rollout.

Inspect:
- docs/direct-call/STATUS.md
- docs/direct-call/WORKLOG.md
- RoomScreen.swift
- RoomScreenModels.swift
- RoomScreenViewModel.swift
- RoomFlowCoordinator.swift
- DirectCallEngine.swift
- DirectCallModels.swift
- DirectCallMediaEngineProtocol.swift
- LiveKitDirectCallMediaEngine.swift
- production token/backend configuration docs
- private native call card tests
- RoomFlowCoordinator lifecycle tests

Questions:
1. What is proven enough for controlled internal dogfood behind `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`?
2. What must still be fixed before dogfood?
3. What must remain explicitly out of scope?
4. Are listener lifecycle and session restoration semantics clear enough for internal users?
5. Are app relaunch, room reopen, repeated call, reverse call, timeout, backend failure, LiveKit failure, and rapid action behaviors sufficiently covered?
6. What user-facing copy/error states still need product polish before dogfood?
7. What backend/config hardening remains for a non-local environment?
8. What tests or runtime proofs should be added before dogfood starts?
9. What rollback/disable switches should be documented for internal dogfood?
10. What is the safest next implementation phase after the review?

Hard constraints:
- Do not modify code.
- Do not commit.
- Do not propose replacing Element Call toolbar buttons yet.
- Do not use `directOneToOneCallsEnabled`.
- No CallKit/push.
- No video.
- No public/global production activation.
- No raw token/JWT/key/envelope/Matrix content.
- No raw room ID or peer ID in UI/logs/docs.
- Do not weaken production E2EE or trust policy.

Expected output:
A. Files inspected.
B. Internal dogfood readiness assessment.
C. Must-fix blockers.
D. Explicit out-of-scope items.
E. Risk matrix.
F. Test/runtime proof gaps.
G. Rollback/disable plan.
H. Recommended next implementation phase.
