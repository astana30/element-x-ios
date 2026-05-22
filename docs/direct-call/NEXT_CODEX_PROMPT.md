# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.27E — repeated-call split-brain regression runtime proof passed.

Current checkpoints:
- App split-brain fix: 2.27D `Fail closed caller when callee media setup fails after answer` (`38fa26586`).
- App activation gate cleanup: 2.26D `Clarify native call private dogfood activation gate` (`76f2064ca`).
- App listener preparation: 2.26E `Enable private dogfood card listener preparation` (`07256bf0a`).
- Product-card-only staging smoke documentation: 2.26E `Record product-card-only staging smoke` (`01e8dc1cb`).
- Call-service LiveKit room pre-create: 2.25E implemented server-side RoomService `CreateRoom` before participant token issuance (`33e95e7b1`).
- Staging iOS activeAudio smoke: 2.25F passed after room pre-create.
- Controlled dogfood matrix: 2.26C passed on the staging media/token/LiveKit path.
- Controlled engineering dogfood pilot checkpoint: 2.27A recorded in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- Repeated-call split-brain regression runtime proof: 2.27E passed after the 2.27D fix.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven/prepared state:
- Product-card-only staging happy path passed under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation remains blocked with `appRolloutDisabled`, with no Matrix send, token/media path, or LiveKit client connect.
- The legacy `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name was explicitly unset and not used for the product-card-only proof or 2.27E runtime proof.
- Manual private-card Start, Accept, and Hang up passed on staging: A/B reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- Receiver listener preparation is limited to private-card status after activation is already enabled; it does not start outgoing calls, request tokens, send Matrix events, or connect media.
- 2.26C controlled matrix passed happy path, reverse direction, repeated calls, decline, cancel, timeout, backend-off fail-closed, backend recovery, relaunch fail-closed, and listener-not-armed behavior.
- 2.27D fixed the split-brain state where callee could emit answer, fail media/token setup, and leave caller active.
- 2.27E runtime proof passed:
  - preflight readiness/trust passed;
  - two normal repeated A -> B calls reached `activeAudio`, then hangup returned A/B to `idle`;
  - forced callee post-answer token/backend failure made B fail closed with `tokenHTTPUnavailable`;
  - A received the terminal path and did not remain `activeAudio`;
  - recovery after restoring B to the normal staging URL reached A/B `activeAudio`, then hangup returned A/B to `idle`;
  - Element Call route remained untouched and no code changed during the runtime proof.
- LiveKit-off fail-closed remains not run because the staging LiveKit instance is shared.
- Element Call route remains unchanged and must stay available as fallback.
- No CallKit, push/background incoming, missed calls, video, session restoration, broad internal rollout, public rollout, production activation, or global activation exists.

Pilot approval:
- Controlled engineering dogfood pilot may continue, conditional, and narrow.
- This is not broad internal dogfood, product beta, public rollout, production activation, or Element Call replacement.

Required pilot scope:
- Named engineering operators only.
- DEBUG/integration builds only.
- Staging call-service and staging LiveKit only.
- Foreground/open encrypted direct 1:1 rooms only.
- Verified/trusted peers only.
- Private native audio card only.
- Audio only.
- Existing Element Call route remains visible and available as fallback.

Required gates:
- `IS_RUNNING_INTEGRATION_TESTS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging call-service>`
- Do not set `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` for staging product-card-only pilot proof.

Required backend preflight:
- readiness `ready=true`
- readiness `reason=ok`
- Redis allocation store connected
- Redis rate-limit store connected
- storage key configured
- LiveKit room provisioning configured
- Synapse validation smoke passing or explicitly accepted as a blocking prerequisite before the session starts

Required client preflight:
- A/B trust ready
- encrypted 1:1 DM open on both clients
- listener/card available
- no stale active session
- Element Call fallback visible

Phase:
2.27F — controlled dogfood pilot matrix rerun after split-brain fix.

Task:
Rerun the controlled engineering dogfood pilot matrix after the 2.27D split-brain fix and 2.27E runtime proof. Do not modify app code or backend code unless a real runtime bug is found and explicitly approved. Do not change Element Call route. Do not wire CallKit, push, missed calls, video, session restoration, or global production activation.

Pilot matrix:
- Happy path A -> B
- Reverse direction B -> A
- Repeated calls
- Decline incoming
- Cancel outgoing
- Timeout
- Backend-off recovery, if safe for the local staging setup
- Relaunch fail-closed
- Listener not armed / room not open behavior
- Element Call fallback smoke

Regression focus:
- Repeated calls must not leave caller/callee split state.
- If a callee post-answer token/media failure occurs, caller must receive a terminal path and must not remain `activeAudio`.
- If the failure does not reproduce, normal repeated calls must still pass cleanly.

Reporting format:
- Pass/fail/not-run only.
- Redacted statuses only.
- Allowed fields: readiness booleans, trust booleans, `productionSessionState`, `productionMediaFailureReason`, terminal reason enum, cleanup/disconnect booleans.
- No raw tokens, JWTs, keys, Matrix access tokens, Synapse admin tokens, room IDs, user IDs, peer IDs, device IDs, Redis credentials, Matrix event bodies, full request bodies, or full response bodies.

Stop immediately if:
- Any raw secret, token, JWT, key, room ID, user ID, peer ID, device ID, endpoint credential, or Matrix event body appears in output.
- A call starts without required gates.
- Element Call route behavior changes.
- An untrusted peer or device can connect.
- A stale active session survives relaunch or cleanup.
- Backend issues a token for invalid room, peer, trust, or membership.
- Media failure is not fail-closed or leaves stale state.
- Caller remains `activeAudio` after callee has failed closed.

Rollback:
- Unset product/private dogfood/start gates.
- Relaunch apps.
- Stop local staging call-service if local.
- Keep Element Call as fallback.
- Rotate secrets if leakage is suspected.

Expected output:
A. Pilot preflight result.
B. Pilot matrix result table.
C. Split-brain regression result.
D. Final A/B redacted status.
E. Element Call fallback result.
F. Any runtime bug.
G. Whether fallback runner commands were used.
H. Whether code/docs changed.
I. Decision: continue controlled pilot / pause.

Validation if docs change:
- `git diff --check`.
- Docs-only diff.
- Docs secret scan.
- Direct-call forbidden scan.

Suggested commit if docs change:
Record controlled dogfood rerun after split-brain fix
