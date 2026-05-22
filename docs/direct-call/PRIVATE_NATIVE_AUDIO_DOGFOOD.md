# Private Native Audio Call Engineering Dogfood

This runbook defines the only approved scope for controlled engineering dogfood of the private native audio call path.

The current decision is yes, conditional, for tightly controlled engineering dogfood on the staging path. This is not approved for broad internal dogfood, product beta, public rollout, or replacement of the existing Element Call buttons.

## Current Proof

The 2.25F staging iOS smoke passed after backend commit `33e95e7b1` added server-side LiveKit room pre-create before participant token issuance.

- A/B reached `productionSessionState=activeAudio`.
- A/B had `productionEncryptionState=ready`.
- A/B had media connect and LiveKit client connect attempted.
- A/B had `productionMediaFailureReason=none`.
- Hangup returned A/B to `productionSessionState=idle`.
- A/B had media disconnect and cleanup attempted.
- The previous `liveKitURLUnreachable` / service-not-found-like blocker is resolved by server-side LiveKit room pre-create.
- No iOS app code, Element Call route, CallKit, push, video, shared LiveKit config, or global production activation changed.

The 2.26C controlled engineering dogfood matrix passed through the redacted diagnostics runner on the real staging media/token/LiveKit path:

- Preflight passed with call-service readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, and `liveKitRoomProvisioningConfigured=true`.
- A/B trust passed with `ownSessionVerified=true`, `crossSigningReady=true`, `peerTrustReady=true`, and `peerTrustReadiness=peerTrustReady`.
- Happy path, reverse direction, repeated calls, decline incoming, cancel outgoing, timeout, backend-off fail-closed, backend recovery, relaunch during active, relaunch during ringing, and listener-not-armed cases passed.
- LiveKit-off fail-closed was not run because the staging LiveKit instance is shared and stopping it could risk other users.
- Final A/B status had no active session and no media failure.
- Element Call route remained untouched and no code changed.

The 2.26D activation cleanup replaced the older DEBUG fake rollout/capability shim with an explicit private dogfood gate, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.

The 2.26E product-card-only staging smoke passed under that explicit gate:

- Without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation stayed blocked with `appRolloutDisabled`.
- The blocked run performed no Matrix send, no token/media path, and no LiveKit client connect.
- With `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation was enabled with dependencies ready, peer trust ready, and key wrapper available.
- The legacy `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name was explicitly unset and was not used.
- A started from the private product card.
- B reached incoming ringing.
- B accepted from the private product card.
- A/B reached `productionSessionState=activeAudio`.
- Hangup returned A/B to `productionSessionState=idle`.
- Encryption was ready, media connect and LiveKit client connect were attempted, and `productionMediaFailureReason=none`.
- Diagnostic runner use was limited to launch, redacted status, activation, and trust polling.
- Element Call route remained untouched, with no CallKit, push, video, or global production activation.
- Commit `07256bf0a` fixed the receiver listener preparation gap by arming the listener from card status only when private dogfood activation is already enabled.
- Listener preparation remains side-effect-limited: it does not start outgoing calls, request tokens, send Matrix events, or connect media.

The 2.27D/2.27E repeated-call split-brain regression is fixed and runtime-proven:

- Commit `38fa26586` made callee post-answer media/token setup failure send a safe terminal signal to the caller before local cleanup.
- Two normal repeated A -> B calls reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- A forced callee post-answer failure made B fail closed with `tokenHTTPUnavailable`.
- A received the terminal path and did not remain `activeAudio`.
- A/B ended idle with no active session.
- After restoring B to the normal staging URL, a recovery call reached A/B `activeAudio`, then hangup returned A/B to idle with cleanup/disconnect attempted and media failure `none`.
- Element Call route remained untouched and no code changed during the runtime proof.

The 2.27F controlled dogfood pilot matrix rerun passed after the split-brain fix:

- Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, LiveKit room provisioning true, and A/B trust ready.
- Happy path, reverse direction, repeated calls, decline, cancel, timeout, backend-off fail-closed, backend recovery, relaunch during active, relaunch during ringing, and listener/open-room unavailable cases passed.
- Backend-off immediate accept with the local staging call-service down failed closed with `connectingFailed`, `tokenHTTPUnavailable`, and no LiveKit client connect.
- LiveKit-off was not run because the staging LiveKit instance is shared and stopping it could affect other users.
- Runner commands were used for matrix control/status, so this is not a claim that every matrix case was manually product-card-only.
- Product-card-only happy path remains separately proven by 2.26E.
- Element Call route remained untouched and no code changed during the runtime proof.

## 2.27A Pilot Checkpoint

Controlled engineering dogfood pilot is allowed, conditional, and narrow.

This approval is only for named engineering operators on the staging path with the explicit gates below. It is not broad internal dogfood, product beta, public rollout, production activation, or replacement of the existing Element Call route.

The checkpoint depends on the full proof chain:

- 2.25F proved staging active audio after call-service LiveKit room pre-create.
- 2.26C proved the redacted controlled matrix on the real staging media/token/LiveKit path.
- 2.26D commit `76f2064ca` made private dogfood activation explicit through `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- 2.26E commit `07256bf0a` prepared the receiver listener from private-card status only after activation is already enabled.
- 2.26E product-card-only smoke proved manual private-card Start, Accept, and Hang up on staging without the legacy fake/dry-run gate.

Before every pilot session, an operator must name the participating engineers, confirm the staging backend and client preflight below, keep Element Call available as fallback, and collect only the redacted reporting fields listed in this runbook.

## Allowed Scope

- Named engineering operators only.
- DEBUG/integration builds only.
- Staging call-service and staging LiveKit path only.
- Private native call room card only.
- Foreground app only.
- Open encrypted direct 1:1 rooms only.
- Verified/trusted peer devices only.
- Receiver listener must be available or explicitly armed.
- Existing Element Call phone/video buttons remain visible, unchanged, and available as the rollback call path.
- Audio only.

Anything outside this scope is not approved by this checkpoint.

## Required Gates

All dogfood launches must set the following gates explicitly:

```sh
export IS_RUNNING_INTEGRATION_TESTS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1
export NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging-call-service-base-url>
```

Use the staging call-service base URL for `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL`; in the current local-run staging setup this is the local loopback service endpoint. Do not set public or global production direct-call activation.

`NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` is DEBUG/integration-only and requires the diagnostic command gates above. `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1` shows the private card, and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1` allows start actions, but neither gate enables the production activation decision by itself. Do not use the old `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name for new dogfood sessions.

The old fake/dry-run gate must remain unset for staging product-card-only proof and pilot sessions.

## Operational Preflight

Complete this checklist before every dogfood session:

- Staging call-service readiness is `ready=true`, `reason=ok`.
- Redis allocation store is configured, shared, and connected.
- Redis rate-limit store is configured, shared, and connected.
- `storageKeyConfigured=true`.
- `liveKitRoomProvisioningConfigured=true`.
- Synapse validation smoke is available and passing, or the session is blocked until it is explicitly accepted as a prerequisite by the operator.
- Token TTL and allocation TTL remain bounded.
- Staging env files are ignored by git and mode `600`.
- A/B app launch succeeds through the diagnostic runner.
- A/B trust diagnostics are ready.
- The encrypted direct 1:1 DM is open on both clients.
- Receiver listener is available or armed.
- No stale active native direct-call session is present.
- Existing Element Call toolbar path is visible and available as fallback.

## 2.28A Operations Checklist

Use this checklist for every controlled engineering pilot window. A pilot window must have one named operator who owns start, monitoring, stop, cleanup, and the final redacted report.

### Operator Sign-Off

Before launch, record internally:

- named operator;
- named participants;
- staging call-service owner;
- staging LiveKit owner or explicit confirmation that LiveKit is shared and must not be stopped;
- planned start and stop time;
- confirmation that Element Call remains the fallback path;
- confirmation that no broad internal, public, CallKit, push, video, missed-call, background, or production/global activation scope is included.

Do not record raw room IDs, user IDs, peer IDs, device IDs, tokens, JWTs, secrets, or Matrix event bodies in the sign-off.

### Staging Call-Service Procedure

For the current local staging setup, start the call-service from the repo root with the operator-local env file:

```sh
PATH=server/salemx-call-service/.venv/bin:$PATH \
server/salemx-call-service/scripts/run_staging_call_service_local.sh \
  --env-file server/salemx-call-service/deploy/staging.env \
  --host 127.0.0.1 \
  --port 8088
```

The script validates staging guardrails and prints only redacted startup information. Keep the process attached to an operator terminal during the pilot, or make its supervisor ownership explicit before the session starts.

Stop local staging call-service only when the pilot uses a local service process:

```sh
lsof -tiTCP:8088 -sTCP:LISTEN
kill -TERM <pid>
```

Do not stop shared staging LiveKit, Matrix, Redis, Nginx, firewall, or server services as part of a normal dogfood session. LiveKit-off checks remain not run unless a separate owner explicitly approves a disruption window.

### Readiness Checks

Call-service readiness must pass before start and after any recovery:

```sh
curl -sS http://127.0.0.1:8088/_matrix/client/unstable/kz.salemx.direct_call/readiness
```

Record only these redacted fields:

- `ready`;
- `reason`;
- `allocationStoreConfigured`;
- `allocationStoreShared`;
- `allocationStoreConnected`;
- `rateLimitConfigured`;
- `rateLimitShared`;
- `rateLimitConnected`;
- `storageKeyConfigured`;
- `liveKitRoomProvisioningConfigured`.

Required result:

- `ready=true`;
- `reason=ok`;
- Redis allocation store configured/shared/connected true;
- Redis rate-limit store configured/shared/connected true;
- `storageKeyConfigured=true`;
- `liveKitRoomProvisioningConfigured=true`.

If readiness fails, do not start a dogfood call. Record only the failing boolean or safe reason enum, then stop the session or recover the local service.

### Client Gate Checks

Launch DEBUG/integration clients only with the required gates:

```sh
export IS_RUNNING_INTEGRATION_TESTS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1
export NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging-call-service-base-url>
unset NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED
```

Before calling, verify:

- A/B app diagnostic signalling ready;
- encrypted direct 1:1 DM open on both clients;
- `ownSessionVerified=true`;
- `crossSigningReady=true`;
- `peerTrustReady=true`;
- `peerTrustReadiness=peerTrustReady`;
- `productionSessionState=idle`;
- `productionHasActiveSession=false`;
- private native card visible/available;
- Element Call fallback buttons still visible and unchanged.

### Redacted Monitoring

During the session, monitor only:

- readiness booleans and `reason`;
- trust booleans;
- `productionSessionState`;
- `productionMediaFailureReason`;
- terminal reason enum;
- media connect attempted boolean;
- LiveKit client connect attempted boolean;
- cleanup attempted boolean;
- disconnect attempted boolean.

Allowed failure/reason examples include `tokenHTTPUnavailable`, `connectingFailed`, `outgoingTimeout`, `incomingTimeout`, `cancelled`, `appRolloutDisabled`, and `none`.

Never capture or share:

- access tokens;
- Synapse admin tokens;
- LiveKit API keys or secrets;
- participant tokens or JWTs;
- passwords;
- media keys;
- raw room IDs;
- raw user IDs;
- raw peer IDs;
- raw device IDs;
- Redis URLs with credentials;
- Matrix event bodies;
- full backend request or response bodies.

### Failure Triage

| Symptom | Allowed report | First action |
| --- | --- | --- |
| Readiness fails | failing readiness boolean and `reason` | Do not start calls; recover local call-service or stop session |
| Redis unavailable | allocation/rate-limit connected false | Stop session; do not issue token attempts |
| Token/backend failure | `tokenHTTPUnavailable` or safe backend error enum | Confirm fail-closed idle/no active session; recover backend before retry |
| LiveKit/media failure | `productionMediaFailureReason` enum only | Confirm cleanup/disconnect attempted; do not stop shared LiveKit without owner approval |
| Trust failure | trust booleans and readiness enum | Stop session for that pair until trust is ready |
| Signalling failure | terminal enum and session state only | Confirm both sides idle; keep Element Call fallback available |
| Relaunch behavior | state and active-session boolean | Stop if stale ringing/active session survives relaunch |
| Split-brain risk | A/B state comparison only | Stop if one side remains `activeAudio` after the other failed closed |
| Element Call fallback issue | pass/fail only | Stop native dogfood immediately |

### Stop Criteria

Stop the pilot immediately if:

- any forbidden secret, token, key, raw identifier, or Matrix event body appears in output, screenshot, logs, docs, or chat;
- a call starts without the required gates;
- Element Call route behavior changes;
- an untrusted peer or device can connect;
- a stale active or ringing session survives cleanup or relaunch;
- backend issues a token for invalid room, peer, trust, or membership;
- media failure leaves either side stuck active;
- caller remains `activeAudio` after callee fails closed;
- shared LiveKit, Matrix, Redis, Nginx, firewall, or production services would need to be changed to continue.

### Rollback

1. Unset `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED`, and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED`.
2. Relaunch the apps.
3. Verify `productionSessionState=idle` and `productionHasActiveSession=false`.
4. Stop the local staging call-service if it was started only for the session.
5. Keep Element Call as the fallback route.
6. Preserve only redacted pass/fail status for reporting.
7. Rotate affected credentials if any leak is suspected.

### Post-Session Report Template

```text
Session:
- operator:
- participants:
- build type: DEBUG/integration
- staging call-service: ready=true/false
- Redis allocation/rate-limit/storage: pass/fail
- LiveKit room provisioning: pass/fail
- A/B trust: pass/fail
- required gates: pass/fail
- old fake/dry-run gate unset: pass/fail

Matrix:
- happy path:
- reverse:
- repeated calls:
- decline:
- cancel:
- timeout:
- backend-off:
- backend recovery:
- relaunch active:
- relaunch ringing:
- listener/open-room unavailable:
- LiveKit-off: not-run/pass/fail + safe reason
- Element Call fallback: pass/fail

Final:
- A state:
- B state:
- media failure:
- cleanup/disconnect:
- runtime bug:
- runner-assisted checks used:
- decision: continue/pause
```

### Security Cleanup

After every pilot or diagnostic session:

- remove temporary SSH keys such as `/tmp/salemx_codex_tmp` and `/tmp/salemx_codex_tmp.pub`;
- remove temporary JSON reports such as `/tmp/salemx-*.json` when they are known to be disposable;
- rotate any password that was shared or entered during diagnostics;
- verify `server/salemx-call-service/deploy/staging.env` is ignored, untracked, and mode `600`;
- verify `server/salemx-call-service/smoke/staging-synapse-smoke.env` is ignored, untracked, and mode `600` when present;
- keep real secrets only in local operator env files or server-local secret files;
- do not commit env, log, tmp, backup, token, JWT, or secret files;
- keep Element Call fallback available until broader rollout blockers are explicitly closed.

## Session Matrix

Run each row with redacted output only. Record pass/fail plus the allowed fields listed below.

| Case | Flow | Expected |
| --- | --- | --- |
| Happy path | A start -> B accept -> active audio -> hangup | A/B active audio, then idle; media failure `none` |
| Reverse direction | B start -> A accept -> active audio -> hangup | A/B active audio, then idle; media failure `none` |
| Repeated calls | Complete two calls in the same room after cleanup | Second call starts cleanly; no stale active session |
| Decline incoming | A start -> B decline | A/B clear to idle; no media connect leak |
| Cancel outgoing | A start -> A cancel before accept | A/B clear to idle; no media connect leak |
| Timeout | Start without accept until timeout | A/B clear to idle with terminal timeout reason |
| Backend-off fail closed | Stop or block local staging call-service, then start | User-safe token/service failure; no participant token issued |
| Backend recovery | Restore call-service, repeat happy path | Active audio can be reached again |
| LiveKit-off fail closed | Stop/block LiveKit path for a controlled session | User-safe media failure; no stale active session |
| LiveKit recovery | Restore LiveKit path, repeat happy path | Active audio can be reached again |
| Relaunch during ringing | Relaunch one side while ringing | No stale ringing/active session restored |
| Relaunch during active | Relaunch one side while active | No stale active session restored |
| Listener not armed / room not open | Start without receiver listener availability | Fail closed or no incoming presentation; no stale session |
| Element Call fallback smoke | Use the existing Element Call route outside native-card actions | Existing route remains available and unchanged |

## 2.26C Matrix Result

| Case | Result | Redacted reason |
| --- | --- | --- |
| Happy path A -> B | Pass | A/B `activeAudio`, hangup -> `idle`, media failure `none` |
| Reverse B -> A | Pass | A/B `activeAudio`, hangup -> `idle`, media failure `none` |
| Repeated calls | Pass | Two clean calls, no stale active session |
| Decline incoming | Pass | A/B `idle`, terminal `cancelled`, media failure `none` |
| Cancel outgoing | Pass | A/B safe `idle` / `unavailable`, terminal `cancelled`, media failure `none` |
| Timeout | Pass | A/B `idle`, terminal `outgoingTimeout` / `incomingTimeout` |
| Backend-off fail closed | Pass | `tokenHTTPUnavailable`, no LiveKit connect, cleanup/disconnect true |
| Backend recovery | Pass | Recovered to A/B `activeAudio`, then `idle` |
| LiveKit-off fail closed | Not run | Shared staging LiveKit; stopping it could risk other users |
| Relaunch during active | Pass | No stale active session after relaunch |
| Relaunch during ringing | Pass | No stale ringing/active session after relaunch |
| Listener not armed | Pass | B had no active session; A cancel cleaned up safely |

## 2.26E Product-Card-Only Result

| Check | Result | Redacted reason |
| --- | --- | --- |
| No private dogfood gate | Pass | `appRolloutDisabled`; no Matrix send, token/media path, or LiveKit connect |
| Private dogfood gate | Pass | Activation enabled; dependencies ready; peer trust ready; key wrapper available |
| Legacy fake gate | Pass | Explicitly unset and not used |
| Product-card happy path | Pass | A Start -> B incoming -> B Accept -> A/B `activeAudio` -> hangup -> A/B `idle` |
| Media state | Pass | Encryption ready; media and LiveKit connect attempted; media failure `none` |
| Runner fallback | Pass | Only launch/status/activation/trust polling; no fallback Start/Accept/Hang up |
| Element Call separation | Pass | Existing Element Call route untouched |
| Listener preparation safety | Pass | No auto-start without the private dogfood gate; no token request, Matrix send, outgoing start, or media connect from preparation |

## 2.27E Split-Brain Regression Result

| Check | Result | Redacted reason |
| --- | --- | --- |
| Preflight | Pass | readiness `ready=true`, `reason=ok`, Redis/storage booleans true, LiveKit room provisioning true, A/B trust ready |
| Required gates | Pass | Product UI, private dogfood, production start, and staging token base were set; legacy fake/dry-run gate unset |
| Repeated call 1 | Pass | A -> B reached `activeAudio`, hangup -> A/B `idle`, media failure `none` |
| Repeated call 2 | Pass | A -> B reached `activeAudio`, hangup -> A/B `idle`, no stale active session |
| Forced callee post-answer failure | Pass | B failed closed with `tokenHTTPUnavailable`; A received terminal path and did not remain `activeAudio` |
| Recovery | Pass | Restored normal staging URL; recovery call reached A/B `activeAudio`, then hangup -> A/B `idle` |
| Element Call separation | Pass | Existing Element Call route untouched |

## 2.27F Controlled Matrix Rerun Result

| Check | Result | Redacted reason |
| --- | --- | --- |
| Preflight | Pass | readiness `ready=true`, `reason=ok`, Redis/storage booleans true, LiveKit room provisioning true, A/B trust ready |
| Required gates | Pass | Product UI, private dogfood, production start, and staging token base were set; legacy fake/dry-run gate unset |
| Happy path A -> B | Pass | A/B `activeAudio` -> hangup -> `idle`, media failure `none` |
| Reverse B -> A | Pass | A/B `activeAudio` -> hangup -> `idle`, media failure `none` |
| Repeated call 1 | Pass | A/B `activeAudio` -> `idle`, no stale session |
| Repeated call 2 | Pass | A/B `activeAudio` -> `idle`, no split-brain |
| Decline | Pass | A/B `idle`, terminal `cancelled`, caller received reject |
| Cancel | Pass | A/B `idle`, terminal `cancelled`, callee received cancel |
| Timeout | Pass | A/B `idle`, terminal `outgoingTimeout` / `incomingTimeout` |
| Backend-off | Pass | Immediate accept with backend down failed closed: `connectingFailed`, `tokenHTTPUnavailable`, no LiveKit connect |
| Backend recovery | Pass | Restored backend; A/B `activeAudio`, then `idle` |
| Relaunch active | Pass | Relaunch during `activeAudio` left no active session restored |
| Relaunch ringing | Pass | Relaunch during ringing left A/B `idle`, no media path |
| Listener/open-room unavailable | Pass | No active session and no unexpected media/token path |
| LiveKit-off | Not run | Shared staging LiveKit; stopping it could affect other users |

2.27F used runner commands for matrix control/status. This is acceptable for controlled engineering dogfood matrix coverage, but it is not a claim that every matrix case was manually product-card-only.

## Reporting Format

Reports must be pass/fail only with redacted status fields. Allowed fields:

- readiness booleans;
- trust booleans;
- `productionSessionState`;
- `productionMediaFailureReason`;
- terminal reason enum;
- media connect attempted boolean;
- LiveKit client connect attempted boolean;
- cleanup attempted boolean;
- disconnect attempted boolean.

Do not include raw request or response bodies.

A pilot report should include only:

- pass/fail per matrix row;
- redacted preflight booleans;
- redacted final A/B status;
- whether any fallback runner command was used;
- whether Element Call remained available as fallback;
- whether the session should continue or pause.

## Redaction Checklist

Before sharing logs, screenshots, runner output, or bug reports, verify they contain none of the following:

- Raw access tokens.
- Raw JWTs.
- Raw media keys.
- Raw Matrix event content.
- Raw room IDs.
- Raw user IDs.
- Raw peer IDs.
- Raw device IDs.
- Endpoint credentials.
- LiveKit API secrets.
- Redis URLs with credentials.
- Matrix encrypted payload bodies.

Only share redacted booleans, enums, user-safe reasons, and non-identifying status fields.

## Monitoring And Secret Rotation

During each pilot session, monitor only redacted surfaces:

- call-service readiness booleans and reason;
- Redis allocation/rate-limit connected booleans;
- LiveKit room provisioning configured boolean;
- client trust booleans;
- `productionSessionState`;
- `productionMediaFailureReason`;
- terminal reason enum;
- cleanup and disconnect booleans.

Do not capture raw backend request bodies, full response bodies, Matrix event bodies, bearer tokens, LiveKit participant tokens, JWTs, raw room IDs, raw user IDs, raw peer IDs, raw device IDs, Redis URLs with credentials, or LiveKit API secrets.

Rotate affected credentials if any secret, token, JWT, key, credentialed endpoint, or raw identifier appears in shared output, screenshots, logs, shell history, or docs. Pause the pilot until the leak source is removed and redaction is re-verified.

## Stop Conditions

Stop dogfood immediately if any of the following occurs:

- A raw token, JWT, key, room ID, user ID, peer ID, device ID, endpoint credential, or Matrix event body appears in UI, logs, runner output, docs, or screenshots.
- Element Call buttons or route behavior changes.
- A call starts without the required gates.
- A call starts in an invalid room.
- An untrusted peer or device connects.
- A stale active session survives cleanup or relaunch.
- Backend returns a token for an invalid room, peer, trust, or membership condition.
- Media connects without encryption readiness.
- A media failure is not fail-closed or leaves a stale active session.

## Rollback

1. Unset `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED`, and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED`.
2. Relaunch the apps.
3. Stop the local staging call-service if the session uses a local service process.
4. Stop local Redis if the session uses a disposable local Redis container.
5. Keep using the existing Element Call toolbar path.
6. Collect only redacted `production-status` output for debugging.
7. Rotate affected secrets if leakage is suspected.
8. Do not preserve raw backend request bodies, bearer tokens, LiveKit participant tokens, Matrix event content, room IDs, user IDs, peer IDs, or device IDs.

Rollback is complete only when the app relaunches without the private card path active, native direct-call status is idle/no active session, and Element Call remains available.

## Explicit Non-Goals

- Broad internal dogfood.
- Public rollout.
- Product beta.
- Replacing the Element Call toolbar buttons.
- CallKit.
- Push or background incoming calls.
- Missed calls.
- Video.
- Production `AllDevices` trust fallback.
- Weakening `OnlyTrustedDevices` media-key wrapping.
- Public/global production activation.

## Remaining Blockers

These block broader internal dogfood and production, but not the controlled engineering dogfood scope above:

- No CallKit.
- No push or background incoming calls.
- No missed calls.
- No video.
- Receiver listener remains foreground/open-room scoped.
- Session restoration is unsupported by design.
- The product-card-only happy path, split-brain regression proof, and controlled matrix rerun are proven under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`; broader or longer dogfood must follow the 2.27A pilot checkpoint and have explicit operator ownership.
- Operational ownership and monitoring must be explicit for any longer dogfood window.
- Secret rotation and incident response must remain ready before each session.

## Success Criteria

- The private card appears only with `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- The diagnostic panel remains separately gated.
- Element Call buttons remain visible and unchanged.
- Start/Accept reaches active audio.
- Hangup/Decline/Cancel clear both sides.
- Retry does not auto-start.
- Dismiss is local-only.
- Backend and LiveKit failures return user-safe errors.
- Recovery after backend and LiveKit restoration reaches active audio again.
- Timeout clears both sides.
- Relaunch during ringing or active calls fails closed with no stale active session.
- Output remains redacted.
