# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.28A — controlled dogfood operations checklist recorded.

Current checkpoints:
- App split-brain fix: 2.27D `Fail closed caller when callee media setup fails after answer` (`38fa26586`).
- App activation gate cleanup: 2.26D `Clarify native call private dogfood activation gate` (`76f2064ca`).
- App listener preparation: 2.26E `Enable private dogfood card listener preparation` (`07256bf0a`).
- Product-card-only staging smoke documentation: 2.26E `Record product-card-only staging smoke` (`01e8dc1cb`).
- Call-service LiveKit room pre-create: 2.25E implemented server-side RoomService `CreateRoom` before participant token issuance (`33e95e7b1`).
- Staging iOS activeAudio smoke: 2.25F passed after room pre-create.
- Controlled dogfood pilot checkpoint: 2.27A recorded in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- Repeated-call split-brain regression runtime proof: 2.27E passed after the 2.27D fix.
- Controlled dogfood pilot matrix rerun: 2.27F passed after the split-brain fix.
- Controlled dogfood operations checklist: 2.28A recorded in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven/prepared state:
- Product-card-only staging happy path passed under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation remains blocked with `appRolloutDisabled`, with no Matrix send, token/media path, or LiveKit client connect.
- The legacy `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name was explicitly unset and not used for staging pilot proof.
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
- 2.28A operations checklist is recorded:
  - named operator and participant sign-off;
  - staging call-service ownership and local start/stop procedure;
  - Redis/call-service readiness checks;
  - A/B gate, trust, private-card, and stale-session checks;
  - redacted monitoring fields and forbidden outputs;
  - failure triage matrix;
  - stop criteria and rollback;
  - post-session report template;
  - security cleanup for temporary SSH keys, disposable reports, password rotation, and ignored env files.
- Element Call route remains unchanged and must stay available as fallback.
- No CallKit, push/background incoming, missed calls, video, session restoration, broad internal rollout, public rollout, production activation, or global activation exists.

Pilot decision:
- Controlled engineering dogfood may continue on the narrow staging path under the 2.28A operations checklist.
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
2.28B — monitored controlled dogfood pilot window.

Task:
Run or record a monitored controlled engineering dogfood pilot window using the 2.28A operations checklist. Do not modify app code or backend code unless a real runtime bug is found and explicitly approved. Do not change Element Call route. Do not wire CallKit, push, missed calls, video, session restoration, or global production activation.

Goal:
Exercise a longer controlled pilot window with explicit operator ownership, redacted monitoring, and post-session cleanup. Decide whether controlled engineering dogfood may continue, needs narrower constraints, or should pause.

Required report:
A. Operator sign-off summary, redacted.
B. Backend readiness result.
C. Redis/readiness result.
D. A/B gate and trust result.
E. Pilot cases run and pass/fail/not-run table.
F. Redacted monitoring observations.
G. Any stop criteria triggered.
H. Rollback or cleanup performed.
I. Security cleanup result.
J. Element Call fallback status.
K. Runtime bug, if any.
L. Decision: continue / continue with constraints / pause.

Allowed report fields:
- readiness booleans;
- trust booleans;
- `productionSessionState`;
- `productionMediaFailureReason`;
- terminal reason enum;
- cleanup/disconnect booleans;
- pass/fail/not-run;
- safe owner/session labels without raw identifiers.

Forbidden output:
- raw tokens;
- JWTs;
- keys;
- Matrix access tokens;
- Synapse admin tokens;
- LiveKit API secrets;
- participant tokens;
- passwords;
- raw room IDs;
- raw user IDs;
- raw peer IDs;
- raw device IDs;
- Redis URLs with credentials;
- Matrix event bodies;
- full request or response bodies.

Stop immediately if:
- any raw secret, token, JWT, key, room ID, user ID, peer ID, device ID, endpoint credential, or Matrix event body appears in output;
- a call starts without required gates;
- Element Call route behavior changes;
- an untrusted peer or device can connect;
- a stale active session survives relaunch or cleanup;
- backend issues a token for invalid room, peer, trust, or membership;
- media failure is not fail-closed or leaves stale state;
- caller remains `activeAudio` after callee has failed closed.

Validation if docs change:
- `git diff --check`.
- Docs-only diff.
- Docs secret scan.
- Direct-call forbidden scan.

Suggested commit if docs change:
Record monitored dogfood pilot window
