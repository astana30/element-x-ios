# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.27F — controlled dogfood pilot matrix rerun passed.

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
- Controlled dogfood pilot matrix rerun: 2.27F passed after the split-brain fix.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven/prepared state:
- Product-card-only staging happy path passed under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation remains blocked with `appRolloutDisabled`, with no Matrix send, token/media path, or LiveKit client connect.
- The legacy `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name was explicitly unset and not used for the product-card-only proof, 2.27E runtime proof, or 2.27F matrix rerun.
- Manual private-card Start, Accept, and Hang up passed on staging in 2.26E: A/B reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- Receiver listener preparation is limited to private-card status after activation is already enabled; it does not start outgoing calls, request tokens, send Matrix events, or connect media.
- 2.27D fixed the split-brain state where callee could emit answer, fail media/token setup, and leave caller active.
- 2.27E runtime proof passed:
  - preflight readiness/trust passed;
  - two normal repeated A -> B calls reached `activeAudio`, then hangup returned A/B to `idle`;
  - forced callee post-answer token/backend failure made B fail closed with `tokenHTTPUnavailable`;
  - A received the terminal path and did not remain `activeAudio`;
  - recovery after restoring B to the normal staging URL reached A/B `activeAudio`, then hangup returned A/B to `idle`;
  - Element Call route remained untouched and no code changed during the runtime proof.
- 2.27F controlled dogfood matrix rerun passed:
  - preflight readiness/trust passed;
  - happy path, reverse direction, repeated calls, decline, cancel, timeout, backend-off, backend recovery, relaunch active, relaunch ringing, and listener/open-room unavailable cases passed;
  - backend-off immediate accept failed closed with `connectingFailed`, `tokenHTTPUnavailable`, and no LiveKit client connect;
  - LiveKit-off was not run because the staging LiveKit instance is shared;
  - runner commands were used for matrix control/status, so this is not a claim that every matrix case was manually product-card-only;
  - final A/B status was idle/no active session with media failure `none`;
  - Element Call route remained untouched and no code changed during the runtime proof.
- Element Call route remains unchanged and must stay available as fallback.
- No CallKit, push/background incoming, missed calls, video, session restoration, broad internal rollout, public rollout, production activation, or global activation exists.

Pilot decision:
- Controlled engineering dogfood may continue on the narrow staging path.
- This is not broad internal dogfood, product beta, public rollout, production activation, or Element Call replacement.

Required pilot scope:
- Named engineering operators only.
- DEBUG/integration builds only.
- Staging call-service and staging LiveKit only.
- Foreground/open encrypted direct 1:1 rooms only.
- Verified/trusted peers only.
- Private native audio card only.
- Runner-assisted matrix checks are allowed when explicitly reported.
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
- Do not set `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` for staging pilot proof.

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
2.28A — controlled dogfood operational hardening and pilot monitoring.

Task:
Create or update docs only for operational hardening of the controlled private native audio dogfood pilot. Do not modify app code. Do not modify backend code unless docs/scripts only are explicitly requested. Do not change Element Call route. Do not wire CallKit, push, missed calls, video, session restoration, or global production activation.

Goal:
Prepare the operating model for longer controlled pilot windows now that 2.27F passed. Define exactly how named engineers start, monitor, stop, report, and roll back dogfood sessions while preserving redaction and fail-closed behavior.

Required updates:
- Operator ownership and session sign-off checklist.
- Pre-session backend/client readiness checklist.
- Redacted monitoring checklist during sessions.
- Allowed report fields and forbidden output.
- Failure triage matrix for token/backend, LiveKit/media, trust, signalling, relaunch, timeout, stale-session, and Element Call fallback issues.
- Stop criteria and escalation path.
- Secret-leak response and rotation triggers.
- Rollback commands/procedure for local staging call-service, app relaunch, and gates.
- Clear distinction between product-card-only happy path proof and runner-assisted matrix coverage.
- Remaining blockers for broader internal dogfood and production.

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

Validation:
- `git diff --check`.
- Docs-only diff.
- Docs secret scan.
- Direct-call forbidden scan.

Suggested commit:
Add controlled dogfood operational hardening guide
