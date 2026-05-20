# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.23B — private native audio call engineering dogfood runbook.

Current checkpoints:
- App code: 2.22B `Harden native call listener lifecycle` (`16992e5e6`).
- Private card reducer regression fix: 2.21C `Restore failed native call card retry dismiss mapping` (`8cdae55d4`).
- Private card typed reducer cleanup: 2.21B typed snapshot/reducer/user-safe mapping cleanup landed.
- Private card timeout proof: 2.20E private native call card timeout runtime proof passed with the real 45s ringing timeout.
- Private card rapid-action proof: 2.20D private native call card rapid Hang up / Cancel / Decline runtime proof passed on the current build.
- Private card relaunch/listener lifecycle proof: 2.22C passed after 2.22B lifecycle hardening.
- Private native audio dogfood guardrails: 2.23B runbook added at `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
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
- 2.23A readiness review concluded conditional yes for controlled engineering dogfood only, not broad internal dogfood, product beta, public rollout, or Element Call replacement.
- 2.23B documents the strict engineering dogfood runbook and guardrails, including scope, gates, setup, allowed flows, limitations, fail-closed behavior, redaction, rollback, non-goals, staging blockers, success criteria, and stop conditions.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, ElementCallService changes, CallKit, push, video, or global production activation has been added.

Required dogfood gates:
- `IS_RUNNING_INTEGRATION_TESTS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1` for the current fake-backed proof setup
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=...`

Phase:
2.23C — private native call dogfood listener/status polish.

Task:
Inspect and, if safe, polish the private native call card/status handling for listener availability and open-room receiver readiness.
Do not change Element Call route.
Do not wire CallKit/push.
Do not add video.
Do not globally activate production direct calls.

Context:
The dogfood runbook allows controlled engineering dogfood only. Receiver availability remains open-room scoped and may require explicit listener arming. The next app-side usability gap is making that requirement obvious and user-safe without starting listeners or triggering call side effects from rendering.

Goals:
1. Make private-card state clearly communicate when incoming calls require the room to be open and the listener to be armed.
2. Surface redacted lifecycle fields where useful:
   - `productionListenerAvailable`
   - `productionListenerStarted`
   - `productionOwnerAvailable`
   - `productionRoomAttached`
   - `productionSessionRestorationSupported=false`
3. Keep status rendering side-effect-free:
   - no listener start
   - no Matrix send
   - no LiveKit token request
   - no media connect
   - no owner creation unless already part of a safe read-only status path
4. Preserve explicit user actions for Start, Accept, Decline, Cancel, Hang up, Retry, Dismiss, and any listener arming control already present.
5. Keep the diagnostic panel and private product card gates separate.
6. Keep all text user-safe and redacted.

Inspect:
- docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md
- docs/direct-call/STATUS.md
- docs/direct-call/WORKLOG.md
- RoomScreen.swift
- RoomScreenModels.swift
- RoomScreenViewModel.swift
- RoomFlowCoordinator.swift
- Native direct-call card reducer and snapshot models
- Native direct-call internal control panel tests
- RoomFlowCoordinator lifecycle/status tests

Questions:
1. Does the private card clearly distinguish ready-to-start from receiver-listener readiness?
2. Does the card explain the open-room/foreground limitation safely enough for controlled dogfood?
3. Can listener availability be represented without auto-starting the listener?
4. Should listener arming remain a separate internal control, or should the private card expose a safer explicit Arm receiver action under the product UI gate?
5. Are lifecycle status fields mapped through typed snapshot/reducer seams instead of stringly logic?
6. What tests are missing for listener availability and room attachment state?

Hard constraints:
- Do not modify `RoomScreenViewAction.displayCall` behavior.
- Do not modify `RoomScreenCoordinator.presentCallScreen` behavior.
- Do not change `ElementCallService`.
- Do not use `directOneToOneCallsEnabled`.
- No CallKit/push.
- No video.
- No public/global production activation.
- No raw token/JWT/key/envelope/Matrix content.
- No raw room ID or peer ID in UI/logs/docs.
- Do not weaken production E2EE or trust policy.
- Do not replace Element Call toolbar buttons.

Tests:
- Product card remains hidden without `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- Product card visible state remains side-effect-free.
- Listener availability/started/room attached/restoration unsupported fields map to user-safe state or copy.
- No listener starts from rendering/status refresh.
- No Matrix send from rendering/status refresh.
- No token request or media connect from rendering/status refresh.
- Existing Start/Accept/Hang up/Decline/Cancel/Retry/Dismiss behavior remains unchanged.
- Element Call button still emits `displayCall` unchanged.
- Native card actions never emit `displayCall` or `presentCallScreen`.
- Redaction tests cover new listener/status text.

Validation:
- git diff --check
- swiftformat/swiftlint changed Swift files
- targeted tests:
  RoomScreenViewModel native card tests
  NativeDirectCallInternalControlPanelTests if affected
  RoomFlowCoordinatorTests if touched
- Release build
- forbidden scan

Commit only if tests/build pass.

Suggested commit:
Polish native call dogfood listener status
