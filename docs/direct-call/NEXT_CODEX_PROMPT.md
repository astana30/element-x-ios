# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.15A — internal production call cleanup/hangup command.

Current code checkpoints:
- App: 2.15A `Add production direct-call hangup command`
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
- The new `production-hangup A|B` runner command routes through the production owner path and performs immediate terminal cleanup after a successful terminal signal.
- Production status exposes redacted terminal reason, media disconnect attempted, and media cleanup attempted fields.
- No visible UI, Element Call route, RoomScreen call presentation, ElementCallService, CallKit, push, or global production activation has been added.

Phase:
2.15B — internal production hangup runtime proof.

Task:
Run a DEBUG/integration runtime proof for `production-hangup` after an internal production native direct call reaches `activeAudio`.
Do not modify app code unless a runner-only bug is found.
Do not add visible UI.
Do not modify the Element Call route.
Do not wire CallKit/push.
Do not globally activate production direct calls.

Goal:
Prove the internal production command lane can cleanly terminate an active local fake-backend/native LiveKit proof call and return both sides to no active production session with redacted terminal and media cleanup diagnostics.

Suggested runtime sequence:
1. Start the local fake SalemX call service and local LiveKit dev server using the existing local smoke instructions.
2. Launch A/B diagnostic harness with the existing DEBUG/integration gates for fake-enabled activation and production start.
3. Open the same encrypted 1:1 room on A and B.
4. Run `production-start-listener B`.
5. Run `production-start-outgoing A`.
6. Run `production-status A` and `production-status B` until B shows `incomingRinging`.
7. Run `production-accept B`.
8. Run `production-status A` and `production-status B` until both show `activeAudio` and media failure reason `none`.
9. Run `production-hangup A`.
10. After a short wait, run `production-status A` and `production-status B`.

Expected result:
- `production-hangup A` returns `outcome=hungUp`, `reason=none`, and redacted status fields.
- A sends a production terminal event and reports signal send attempted/succeeded.
- A reports no active production session after cleanup.
- A reports a terminal reason and media disconnect/cleanup attempted where applicable.
- B receives the terminal event and reports no active production session.
- B reports the receive event kind/terminal reason if surfaced by existing diagnostics.
- No visible UI, Element Call route, CallKit, push, public activation, or product call route is involved.

Hard constraints:
- No app code changes unless a runner-only issue blocks the proof.
- No visible UI.
- No `RoomScreenViewModel.displayCall` changes.
- No `RoomScreenCoordinator.presentCallScreen` changes.
- No Element Call route changes.
- No `ElementCallService` changes.
- No `directOneToOneCallsEnabled` use.
- No CallKit/push.
- No global production runtime activation.
- No broad Matrix SDK raw APIs.
- Do not print or store credentials, bearer values, participant credentials, media-key material, SDK envelope contents, Matrix event content, or copied secret-bearing logs.

Validation:
- Runner syntax check if touched.
- `git diff --check` if anything changes.
- Docs secret scan if docs are updated.
- Commit only runner/docs fixes if required and validated.

Expected report:
A. Runtime command sequence used.
B. A/B activeAudio status before hangup.
C. `production-hangup` result.
D. A/B production status after hangup.
E. Whether terminal signal send/receive was observed.
F. Whether media disconnect/cleanup was observed.
G. Whether any code changes were needed.
H. Commit hash if a fix/docs update was committed.
