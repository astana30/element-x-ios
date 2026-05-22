# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.27A — controlled engineering dogfood pilot checkpoint recorded.

Current checkpoints:
- App activation gate cleanup: 2.26D `Clarify native call private dogfood activation gate` (`76f2064ca`).
- App listener preparation: 2.26E `Enable private dogfood card listener preparation` (`07256bf0a`).
- Product-card-only staging smoke documentation: 2.26E `Record product-card-only staging smoke` (`01e8dc1cb`).
- Call-service LiveKit room pre-create: 2.25E implemented server-side RoomService `CreateRoom` before participant token issuance (`33e95e7b1`).
- Staging iOS activeAudio smoke: 2.25F passed after room pre-create.
- Controlled dogfood matrix: 2.26C passed on the staging media/token/LiveKit path.
- Controlled engineering dogfood pilot checkpoint: 2.27A recorded in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven/prepared state:
- Product-card-only staging happy path passed under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation remains blocked with `appRolloutDisabled`, with no Matrix send, token/media path, or LiveKit client connect.
- The legacy `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name was explicitly unset and not used for the product-card-only proof.
- Manual private-card Start, Accept, and Hang up passed on staging: A/B reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- Receiver listener preparation is now limited to private-card status after activation is already enabled; it does not start outgoing calls, request tokens, send Matrix events, or connect media.
- 2.26C controlled matrix passed happy path, reverse direction, repeated calls, decline, cancel, timeout, backend-off fail-closed, backend recovery, relaunch fail-closed, and listener-not-armed behavior.
- LiveKit-off fail-closed remains not run because the staging LiveKit instance is shared.
- Element Call route remains unchanged and must stay available as fallback.
- No CallKit, push/background incoming, missed calls, video, session restoration, broad internal rollout, public rollout, production activation, or global activation exists.

Pilot approval:
- Controlled engineering dogfood pilot is allowed, conditional, and narrow.
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
2.27B — controlled engineering dogfood pilot execution report.

Task:
Run or record a narrow controlled engineering dogfood pilot session using the 2.27A checkpoint. Do not modify app code or backend code unless a real runtime bug is found and explicitly approved. Do not change Element Call route. Do not wire CallKit, push, missed calls, video, session restoration, or global production activation.

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

Rollback:
- Unset product/private dogfood/start gates.
- Relaunch apps.
- Stop local staging call-service if local.
- Keep Element Call as fallback.
- Rotate secrets if leakage is suspected.

Expected output:
A. Pilot preflight result.
B. Pilot matrix result table.
C. Final A/B redacted status.
D. Element Call fallback result.
E. Any runtime bug.
F. Whether fallback runner commands were used.
G. Whether code/docs changed.
H. Decision: continue controlled pilot / pause.

Validation if docs change:
- `git diff --check`.
- Docs-only diff.
- Docs secret scan.
- Direct-call forbidden scan.

Suggested commit if docs change:
Record native audio dogfood pilot result
