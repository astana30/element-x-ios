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

For Redis-backed staging stores, `allocationStoreConnected` and `rateLimitConnected` mean the call-service completed bounded live Redis pings for the readiness request. If either connected boolean is false, or `reason` is `allocationStoreUnavailable` / `rateLimitStoreUnavailable`, do not start a dogfood call.

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
- LiveKit room names;
- Redis URLs with credentials;
- Matrix event bodies;
- full backend request or response bodies.

### 2.29E Redacted Monitoring Contract

This contract is the only approved monitoring/status shape for controlled native-audio dogfood. It covers manual pilot notes, runner output, screenshots, bug reports, copied logs, and any summary pasted into chat or docs.

The contract is intentionally low-cardinality. It may describe what happened, but it must not identify the Matrix room, participants, devices, LiveKit room, credentials, request payload, Matrix event body, or backend response body.

#### App And Card Status

Allowed app/card fields:

- redacted card state enum: `hidden`, `unavailable`, `canStart`, `outgoingRinging`, `incomingRinging`, `connecting`, `activeAudio`, `failed`, `ended`;
- unavailable reason enum;
- failure reason enum;
- receiver availability enum;
- restoration availability enum;
- action availability booleans;
- loading boolean;
- user-safe card copy from the UI, when it does not contain identifiers.

Do not report card internals that are only useful for debugging the implementation, including raw last-action traces, raw action reasons, backend request payloads, Matrix event content, endpoint values, or any room/user/device identifier. If a screenshot is used, crop or redact anything outside the private native card that could identify the room or participants.

#### Runner And Production Status

Allowed runner/status fields:

- `productionSessionState`;
- `productionHasActiveSession`;
- `productionEncryptionState`;
- `productionMediaFailureReason`;
- `productionLastTerminalReason`;
- `productionMediaConnectAttempted`;
- `productionLiveKitClientConnectAttempted`;
- `productionMediaDisconnectAttempted`;
- `productionMediaCleanupAttempted`;
- `productionRoomAttached`;
- `productionListenerAvailable`;
- `productionListenerStarted`;
- `productionSessionRestorationSupported`;
- activation enabled boolean and disabled reason enum;
- pass/fail/not-run result per matrix row.

Runner output must not include raw room IDs, user IDs, peer IDs, device IDs, Matrix event bodies, LiveKit room names, tokens, JWTs, keys, backend response bodies, or credentialed endpoint values. If a runner command prints anything outside the fields above, stop and redact before sharing.

#### Backend Readiness

Allowed call-service readiness fields:

- HTTP status;
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

The readiness payload must not be expanded with URLs, Redis keys, raw Matrix identifiers, LiveKit room names, tokens, secrets, request bodies, response bodies, or credential values.

#### Backend Errors

Allowed backend failure reporting:

- HTTP status class or exact status;
- Matrix-style safe `errcode`;
- safe `retry_after_ms` presence/number for rate limiting;
- safe reason enum such as rate limited, allocation unavailable, room provisioning unavailable, unauthorized, forbidden, or invalid request;
- whether token issuance was blocked before a participant token was returned.

Do not paste full backend JSON if it contains request echo, identifiers, endpoint values, or token-shaped fields. Do not paste Authorization headers, Synapse admin tokens, Matrix access tokens, participant tokens, LiveKit API keys/secrets, Redis URLs, or LiveKit room names.

#### LiveKit And Media State

Allowed LiveKit/media reporting:

- media failure enum;
- LiveKit client connect attempted boolean;
- media connect attempted boolean;
- cleanup/disconnect attempted booleans;
- fail-closed result;
- shared LiveKit-off status as `not-run` with a safe reason.

Do not report participant JWTs, LiveKit API key/secret values, LiveKit room names, SDP, ICE candidates, media keys, server logs containing credentials, or full WebSocket/request/response bodies.

#### Too Diagnostic For Pilot Reports

These existing fields may help local engineering debugging, but they are too diagnostic for normal pilot reports unless they are already reduced to a safe enum/boolean:

- raw action reason strings;
- raw last-action traces;
- raw backend request/response bodies;
- endpoint URLs beyond a non-sensitive service label;
- token response shape dumps;
- decoded JWT claims;
- Redis allocation keys or values;
- LiveKit RoomService room names;
- Matrix event envelopes or encrypted payload bodies.

Use the smallest safe enum instead. For example, report `tokenHTTPUnavailable`, `liveKitNetworkFailed`, `connectingFailed`, `outgoingTimeout`, `incomingTimeout`, `cancelled`, `appRolloutDisabled`, or `none`.

#### Guard Tests And Scans

Before sharing or committing pilot material, run the applicable guards:

- `git diff --check`;
- docs-only diff review for docs changes;
- docs secret scan for token/JWT/key/secret-looking literals;
- `Tools/Scripts/verify_direct_call_forbidden_scan.sh`;
- targeted card/status tests when code changes affect the redacted contract.

Any monitoring expansion must add tests proving rendering/status refresh remains side-effect-free: no Matrix send, no token request, no media connect, and no LiveKit connect from rendering or status display.

### 2.30B Internal Pilot Eligibility Contract Skeleton

The native-audio internal pilot eligibility contract now exists as a typed, redacted app skeleton and a disabled-by-default call-service endpoint skeleton. It does not approve non-engineering users.

Eligibility states:

- `eligible`;
- `unavailable(reason)`;
- `disabled`;
- `unsupported`;
- `failClosed`.

Unavailable reasons:

- `accountNotEligible`;
- `peerNotEligible`;
- `roomNotEligible`;
- `trustNotReady`;
- `serviceUnavailable`;
- `capabilityMissing`;
- `unsupportedClient`;
- `unknown`.

The redacted payload shape may carry only enums and booleans:

```json
{
  "state": "unavailable",
  "reason": "accountNotEligible",
  "account_eligible": false,
  "peer_eligible": true,
  "room_eligible": true,
  "trust_ready": true,
  "service_available": true,
  "capability_present": true,
  "client_supported": true
}
```

The payload must never include raw Matrix user IDs, peer IDs, room IDs, device IDs, Matrix event bodies, LiveKit room names, endpoint credentials, tokens, JWTs, keys, secrets, or backend request/response echoes.

The current app default provider returns disabled/fail-closed. Account and peer not-eligible states map to existing safe private-card unavailable copy.

The call-service endpoint is:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/eligibility
```

It validates Matrix bearer auth, optional device binding, and encrypted direct 1:1 room structure before evaluating the eligibility policy. Backend eligibility is disabled by default; static allowlist mode requires both caller and peer accounts when explicitly enabled by local deployment config. The LiveKit token endpoint also reuses this policy before rate limiting, allocation, LiveKit room pre-create, or participant token issuance.

This contract is only preparation for a future internal pilot; the app does not call a backend eligibility endpoint from rendering, does not request tokens, does not connect media, does not connect LiveKit, and does not enable non-engineering dogfood.

### 2.30F Eligibility Endpoint Local Route Smoke

The local route smoke for the backend eligibility endpoint passed with redacted output only:

- readiness returned `ready=true`, `reason=ok`, and included the native audio eligibility readiness booleans;
- default `/eligibility` returned `state=unavailable`, `reason=capabilityMissing`, and `capability_present=false`;
- default token endpoint enforcement returned `403` with `M_DIRECT_CALL_NOT_ELIGIBLE`;
- default token endpoint enforcement performed no allocation, no LiveKit room pre-create, and no participant token issuance;
- explicit allowlisted local fixture returned `/eligibility` `state=eligible`, `reason=null`, then allowed token path progression with token output redacted;
- caller-not-allowlisted, peer-not-allowlisted, invalid-room, malformed-request, and unsupported-intent cases returned safe status/enums;
- no raw tokens, JWTs, secrets, room IDs, user IDs, peer IDs, device IDs, Redis credential URLs, or LiveKit room names were printed.

This smoke does not enable non-engineering users. Client-side consumption of the backend eligibility endpoint remains unwired.

### 2.30H iOS Eligibility Provider Skeleton

The iOS app now has a backend `/eligibility` provider skeleton for future internal-pilot work, but it is not wired into non-engineering activation.

- The request DTO carries only the backend-required fields at the HTTP boundary: version, room, peer, optional device, and `audio` intent.
- DTO descriptions and debug output redact room, peer, and device identifiers.
- The HTTP provider uses the existing redacted direct-call HTTP transport and Matrix bearer access-token provider.
- Responses decode only state/reason enums and booleans, including optional `capability_present` / `capabilityPresent`.
- Missing auth/config/transport, network errors, 5xx responses, malformed JSON, unknown enums, and unsupported intents fail closed.
- `404` maps to `capabilityMissing`; auth failures and 5xx map to `serviceUnavailable`.
- The default provider remains disabled/fail-closed.
- The provider does not send Matrix events, request LiveKit participant tokens, connect media, connect LiveKit, start outgoing calls, or arm non-engineering activation.

This skeleton is preparation only. Controlled engineering dogfood remains on the explicit DEBUG/integration private dogfood gate, and the token endpoint remains the final enforcement boundary.

### 2.31B Eligibility Status Cache Skeleton

The iOS app now has a side-effect-safe eligibility status cache skeleton for room-card preflight display. It is not a rollout gate and it does not approve non-engineering users.

- The optional status gate is `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1`.
- The status gate is DEBUG/integration-only and requires the same diagnostic command harness as the private dogfood gates.
- The gate is off by default and does not enable private dogfood activation, production start, or non-engineering internal pilot activation.
- Eligibility status is cached in memory at room-flow scope only; it is not persisted.
- Positive eligibility uses a short cache TTL, negative/network/fail-closed eligibility uses a shorter cache TTL, and manual Refresh/Retry bypasses the cache.
- Cache keys may contain raw IDs internally for local lookup only, but descriptions/debug output redact room, peer, and device identifiers.
- Backend `eligible` alone never changes the card to `canStart`; product UI/start gates remain insufficient without the explicit private dogfood activation gate.
- Local room and trust failures remain authoritative over backend eligibility.
- When the card is already enabled by private dogfood activation, eligibility status does not block or change that path.
- Token-backend rejection invalidates the local eligibility status cache when that status path is wired.

Eligibility status refresh may only call the backend `/eligibility` endpoint. It must not send Matrix events, request participant tokens, allocate or pre-create LiveKit rooms, connect media, connect LiveKit, start outgoing calls, or arm the listener unless the existing private dogfood activation path already allows listener preparation.

This is still preparation for a future internal pilot. Non-engineering dogfood remains blocked until server-side allowlist fixtures, client-side eligibility consumption, runtime no-activation proof, redacted monitoring, support/rollback, and security review are complete.

Before any future narrow non-engineering internal pilot, the eligibility contract still needs:

- runtime proof of the server-side allowlist endpoint under named internal-pilot fixtures;
- runtime proof that client-side eligibility status consumption remains fail-closed and side-effect-free;
- redacted readiness/monitoring coverage;
- support and rollback workflow;
- runtime proof across named pilot accounts/devices;
- security review confirming no raw identifiers or secrets are collected or reported.

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
- any LiveKit room name appears in output, screenshot, logs, docs, or chat;
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
- terminal reason:
- media connect attempted:
- LiveKit connect attempted:
- cleanup/disconnect:
- runtime bug:
- runner-assisted checks used:
- redaction issue: yes/no
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

## 2.30C Eligibility Runtime/No-Activation Proof

| Check | Result | Redacted reason |
| --- | --- | --- |
| Backend readiness | Pass | readiness `ready=true`, `reason=ok`, Redis/storage booleans true |
| Product UI gate alone | Pass | Attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled` |
| No private dogfood side effects | Pass | No Matrix send, no token request, no media connect, no LiveKit connect, no active session |
| Private dogfood activation | Pass | A/B activation enabled with dependencies ready, endpoint accepted, and A/B trust ready |
| Engineering happy path | Pass | Runner-assisted A -> B reached A/B `activeAudio`, media failure `none` |
| Hangup/final state | Pass | A/B returned to `idle`, no active session, cleanup/disconnect attempted, media failure `none` |
| Legacy fake gate | Pass | Explicitly unset and not used |
| Element Call separation | Pass | Existing Element Call route untouched; no Element Call presentation path used for native actions |

This proof confirms the 2.30B eligibility contract skeleton does not broaden activation. Non-engineering dogfood remains blocked until server-side allowlist/capability backing, token endpoint enforcement, and runtime proof for named pilot accounts/devices exist.

## 2.30I iOS Eligibility Provider No-Activation Proof

| Check | Result | Redacted reason |
| --- | --- | --- |
| Backend readiness | Pass | readiness `ready=true`, `reason=ok`, Redis/storage booleans true |
| Product UI/start gates without private dogfood | Pass | Attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled` |
| No private dogfood side effects | Pass | No Matrix send, no token request, no media connect, no LiveKit connect, no active session |
| Eligibility provider integration boundary | Pass | Provider skeleton remains unwired for non-engineering activation; no eligibility status/rendering path starts token/media work |
| `directOneToOneCallsEnabled` separation | Pass | Existing Element Call setting remains separate and does not enable native audio eligibility |
| Private dogfood activation | Pass | A/B activation enabled with dependencies ready, endpoint accepted, and A/B trust ready |
| Engineering happy path | Pass | Runner-assisted A -> B reached A/B `activeAudio`, media failure `none` |
| Hangup/final state | Pass | A/B returned to `idle`, no active session, cleanup/disconnect attempted, media failure `none` |
| Legacy fake gate | Pass | Explicitly unset and not used |
| Element Call separation | Pass | Existing Element Call route untouched; native commands did not use the Element Call presentation path |

This proof confirms the 2.30H iOS provider skeleton stays side-effect-safe and fail-closed unless the existing DEBUG/integration private dogfood gate is explicitly enabled. Non-engineering dogfood remains blocked until a separate server-backed eligibility integration phase is designed, implemented, and runtime-proven.

## 2.31C Eligibility Status Cache No-Activation Proof

| Check | Result | Redacted reason |
| --- | --- | --- |
| Backend readiness | Pass | readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, eligibility configured |
| Eligibility status gate without private dogfood | Pass | Attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled` |
| Product UI/start/status gates without private dogfood | Pass | `production-start-outgoing` stayed blocked with `appRolloutDisabled` |
| No private dogfood side effects | Pass | No Matrix send, no token request, no media connect, no LiveKit connect, no active session |
| Temporary backend blocker | Recovered | Token endpoint failed closed with `M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE` / `503` until Redis rate-limit connectivity was restored |
| Private dogfood activation | Pass | A/B activation enabled with dependencies ready, endpoint accepted, and A/B trust ready |
| Engineering happy path | Pass | Runner-assisted A -> B reached A/B `activeAudio`, media failure `none` |
| Media path | Pass | Media connect and LiveKit client connect attempted on both sides |
| Hangup/final state | Pass | A/B returned to `idle`, no active session, cleanup/disconnect attempted, media failure `none` |
| Legacy fake gate | Pass | Explicitly unset and not used |
| Element Call separation | Pass | Existing Element Call route untouched; native actions did not use the Element Call presentation path |

This proof confirms the 2.31B eligibility status cache remains status-only and fail-closed unless the existing DEBUG/integration private dogfood gate is explicitly enabled. Non-engineering dogfood remains blocked; eligibility status display is still not a rollout approval path.

## 2.32B Eligibility Status Integration Polish

| Check | Result | Redacted reason |
| --- | --- | --- |
| Redaction polish | Pass | Production LiveKit token response descriptions redact LiveKit room names, server URLs, and participant tokens |
| Runner eligibility status gate | Pass | Runner forwards `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1` and reports only enabled/disabled state |
| Backend readiness | Pass | readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, eligibility configured |
| Eligibility status without private dogfood | Pass | Attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled` |
| Product UI/start/status gates without private dogfood | Pass | `production-start-outgoing` stayed blocked with `appRolloutDisabled` |
| No private dogfood side effects | Pass | No Matrix send, no token request, no media connect, no LiveKit connect, no active session |
| Private dogfood activation | Pass | A/B activation enabled with dependencies ready, endpoint accepted, and A/B trust ready |
| Engineering happy path | Pass | Runner-assisted A -> B reached A/B `activeAudio`, media failure `none` |
| Media path | Pass | Media connect and LiveKit client connect attempted on both sides |
| Hangup/final state | Pass | A/B returned to `idle`, no active session, cleanup/disconnect attempted, media failure `none` |
| Runner caveat | Pass | `wait-status incomingRinging` timed out before accept, but explicit accept and final status proved incoming, active audio, hangup, and cleanup |
| Negative eligibility cases | Not rerun | Covered by unit tests and the 2.30F route smoke; local staging allowlist was not reconfigured during this live run |
| Legacy fake gate | Pass | Explicitly unset and not used |
| Element Call separation | Pass | Existing Element Call route untouched |

This proof confirms eligibility status remains status/copy-only and still does not authorize native audio activation. Backend eligible status alone is insufficient; the DEBUG/integration private dogfood gate remains required for engineering activation, and non-engineering internal dogfood remains blocked.

## 2.32C Eligibility Status Controlled Soak

| Check | Result | Redacted reason |
| --- | --- | --- |
| Backend preflight | Pass | readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, eligibility configured |
| A/B preflight | Pass | activation enabled only under explicit private dogfood gates; A/B trust ready |
| Happy path A -> B | Pass | A/B reached `activeAudio`, hangup -> idle, media failure `none` |
| Reverse B -> A | Pass | A/B reached `activeAudio`, hangup -> idle, media failure `none` |
| Repeated call 1 | Pass | A/B reached `activeAudio`, hangup -> idle, no stale session |
| Repeated call 2 | Pass | A/B reached `activeAudio`, hangup -> idle, no split-brain |
| Decline incoming | Pass | Incoming side emitted `reject`; A/B idle, terminal `cancelled`, media failure `none` |
| Cancel outgoing | Pass | Outgoing side emitted `cancel`; A/B idle, terminal `cancelled`, media failure `none` |
| Timeout | Pass | A/B idle with terminal `outgoingTimeout` / `incomingTimeout`, media failure `none` |
| Relaunch during ringing | Pass | Relaunch restored no active session; post-relaunch status was `unavailable` until the room is re-opened |
| Final backend readiness | Pass | readiness stayed `ready=true`, `reason=ok` |
| Runner use | Pass | Matrix was runner-assisted for controlled engineering soak; not a manual product-card-only claim |
| Redaction | Pass | No LiveKit room names were present in runner output; no tokens, secrets, raw IDs, event bodies, or Redis credentials were reported |
| Element Call separation | Pass | Existing Element Call route untouched |

This soak confirms the eligibility status gate can remain enabled during controlled engineering dogfood use without destabilising the staging native-audio path. It does not broaden activation: non-engineering dogfood remains blocked, and the explicit DEBUG/integration private dogfood gate is still required.

## 2.33B Narrow Engineering Expansion Pilot Runbook

The 2.33A readiness review allows a narrow engineering expansion pilot. This is still staging-only, conditional, and engineering-only. It is not broad internal dogfood, non-engineering dogfood, product beta, public rollout, production activation, or Element Call replacement.

### Expansion Scope

- Up to 4 named engineering operators.
- Up to 8 named engineering devices.
- Predeclared accounts/devices only.
- Staging call-service and staging LiveKit only.
- Private native audio card only.
- Foreground/open encrypted direct 1:1 rooms only.
- Verified/trusted peers only.
- One active 1:1 native audio call at a time during the first expanded window.
- Existing Element Call route must stay visible, unchanged, and available as fallback.
- No non-engineering users.
- No unmanaged devices.

### Ownership Window

Record the following internally before launch, using labels only:

| Field | Value |
| --- | --- |
| Pilot window | `<date/time range>` |
| Pilot operator | `<Operator Lead>` |
| Backup operator | `<Operator Backup>` |
| Staging call-service owner | `<Service Owner>` |
| Staging LiveKit owner | `<LiveKit Owner or shared/not-stopped>` |
| Redaction reviewer | `<Reviewer>` |
| Rollback owner | `<Rollback Owner>` |
| Element Call fallback smoke owner | `<Fallback Owner>` |

Do not record raw Matrix user IDs, room IDs, peer IDs, device IDs, tokens, JWTs, secrets, LiveKit room names, Matrix event bodies, or Redis credential URLs in this matrix.

### Participant And Device Matrix Template

Use labels only. Keep raw account and device identifiers in operator-local secure notes if needed; do not paste them into docs, chat, screenshots, runner output, or reports.

| Operator label | Account role label | Device label | Trust ready | Allowed pair labels | Notes |
| --- | --- | --- | --- | --- | --- |
| Operator A | Caller/Callee A | Device A1 | true/false | A-B, A-C | Redacted |
| Operator B | Caller/Callee B | Device B1 | true/false | A-B, B-C | Redacted |
| Operator C | Caller/Callee C | Device C1 | true/false | A-C, B-C | Redacted |
| Operator D | Caller/Callee D | Device D1 | true/false | A-D, C-D | Redacted |

Every listed device must pass trust readiness before it participates. If a device is not trusted, remove it from the allowed pairings for that window.

### Pair Matrix Template

Run the required smoke matrix once for each newly introduced pair before that pair is considered part of the expanded engineering pilot.

| Pair label | Caller direction | Reverse direction | Repeated x2 | Decline | Cancel | Timeout | Relaunch fail-closed | Listener/open-room | Element Call fallback | Backend-off/recovery | LiveKit-off |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A-B | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | not-run unless approved |
| A-C | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | not-run unless approved |
| B-C | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | not-run unless approved |
| C-D | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | pass/fail/not-run | not-run unless approved |

### Required Gates

Every expanded engineering pilot launch must set:

```sh
export IS_RUNNING_INTEGRATION_TESTS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1
export NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1
export NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging-call-service-base-url>
```

`NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` must remain unset for the expanded staging pilot.

### Backend Preflight

Before each expanded window and before each recovery retry:

- readiness `ready=true`;
- readiness `reason=ok`;
- Redis allocation store connected;
- Redis rate-limit store connected;
- `storageKeyConfigured=true`;
- `liveKitRoomProvisioningConfigured=true`;
- native audio eligibility and allowlist configured when the status/allowlist path is used;
- Synapse validation smoke passing or explicitly accepted as a blocking prerequisite.

If readiness reports `allocationStoreUnavailable`, `rateLimitStoreUnavailable`, or any disconnected Redis boolean, do not start calls.

### Client Preflight

Before each pair runs:

- app launch ready for both sides;
- trust ready for both sides;
- encrypted direct 1:1 DM open on both sides;
- private native audio card visible;
- no stale active or ringing native session;
- receiver listener/card available;
- Element Call fallback visible and unchanged.

### Required Smoke Matrix Per New Pair

For each new pair, run:

- A -> B happy path: Start, Accept, `activeAudio`, Hang up, idle.
- B -> A reverse path: Start, Accept, `activeAudio`, Hang up, idle.
- Repeated calls x2 with no stale session and no split-brain.
- Decline incoming.
- Cancel outgoing.
- Timeout if practical.
- Relaunch fail-closed during ringing or active, whichever is practical for the window.
- Listener/open-room unavailable behavior.
- Element Call fallback smoke.
- Backend-off/recovery only when safe for the local staging setup.
- LiveKit-off remains not-run unless the LiveKit owner explicitly approves a disruption window.

### Redacted Reporting Format

Report only:

- pass/fail/not-run;
- readiness booleans and safe `reason`;
- trust booleans;
- redacted card state/reason enums;
- activation reason enum;
- `productionSessionState`;
- `productionMediaFailureReason`;
- terminal reason enum;
- media/LiveKit connect attempted booleans;
- cleanup/disconnect attempted booleans;
- Element Call fallback pass/fail.

Do not report raw Matrix access tokens, Synapse admin tokens, LiveKit API secrets, participant tokens/JWTs, media keys, raw room IDs, raw user IDs, raw peer IDs, raw device IDs, LiveKit room names, Redis URLs with credentials, Matrix event bodies, or full backend request/response bodies.

### Expansion Stop Criteria

Stop the expanded pilot immediately if:

- any forbidden secret, token, JWT, key, raw identifier, LiveKit room name, credentialed endpoint, or Matrix event body appears in output, screenshots, logs, docs, chat, or reports;
- a call starts without the required gates;
- Element Call route behavior changes;
- an untrusted peer or device can connect;
- stale active or ringing state survives cleanup or relaunch;
- backend issues a token for invalid room, peer, trust, or membership;
- media failure does not fail closed;
- split-brain reappears;
- Redis readiness fails or the call-service reports disconnected allocation/rate-limit stores;
- shared staging LiveKit, Matrix, Redis, Nginx, firewall, or production services would need to be changed to continue.

### Expansion Rollback

1. Unset `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED`, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED`, and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED`.
2. Relaunch the apps.
3. Verify native direct-call status is idle/no active session.
4. Stop the local staging call-service if the window used a local service process.
5. Keep Element Call as the fallback route.
6. Remove expanded allowlist entries from local operator env when the window ends, if they were added only for the window.
7. Preserve only redacted pass/fail status in reports.
8. Rotate affected credentials if any leakage is suspected.

Rollback is complete only when no private native session is active, the private dogfood path is disabled, and Element Call remains available.

### Expanded Pilot Report Template

```text
Pilot window:
- session label:
- operator labels:
- device labels:
- pair labels:
- build type: DEBUG/integration
- staging call-service readiness: pass/fail
- Redis allocation/rate-limit: pass/fail
- LiveKit room provisioning: pass/fail
- eligibility/allowlist configured: pass/fail/not-used
- A/B trust: pass/fail
- required gates: pass/fail
- old fake/dry-run gate unset: pass/fail

Pair matrix:
- pair:
- happy path:
- reverse:
- repeated x2:
- decline:
- cancel:
- timeout:
- relaunch fail-closed:
- listener/open-room unavailable:
- Element Call fallback:
- backend-off/recovery:
- LiveKit-off:

Final:
- final session state:
- media failure:
- terminal reason:
- cleanup/disconnect:
- runtime bug:
- redaction issue:
- rollback used:
- decision: continue/pause
```

## 2.33D Timeout Terminal Cleanup Fix

The first 2.33C expansion attempt was paused when the timeout case produced safe terminal reasons but kept active session ownership until explicit cleanup. A reported `outgoingTimeout`, B reported `incomingTimeout`, and media failure stayed `none`, but `productionHasActiveSession` remained true during the delayed cleanup window.

Root cause: DirectCallEngine timeout paths transitioned to terminal states while leaving the active session owned until delayed cleanup.

Commit `1d9218057` fixes this by disconnecting and cleaning up immediately for timeout terminal paths. Normal hangup, decline, and cancel behavior remain unchanged.

Runtime proof after the fix:

| Check | Result | Redacted status |
| --- | --- | --- |
| Timeout terminal path | Pass | A `outgoingTimeout`, B `incomingTimeout` |
| Active session cleanup | Pass | A/B `productionSessionState=idle`, `productionHasActiveSession=false` |
| Media state | Pass | cleanup/disconnect attempted, media failure `none` |
| Next call after timeout | Pass | A/B reached `activeAudio`, then hangup returned A/B idle |
| Element Call separation | Pass | Existing Element Call route untouched |

Validation passed: DirectCallEngineTests 36/36, focused native subset 171 tests, Release build with existing warnings only, SwiftFormat/SwiftLint, `git diff --check`, and the direct-call forbidden scan.

## 2.33E Engineering Expansion Pilot Session 1 Rerun

Session date/time: `2026-05-24 21:49 +05`.

Operators and devices are recorded only as redacted A/B engineering labels. The session used the staging call-service, staging LiveKit, DEBUG/integration build gates, eligibility status gate, private dogfood gate, production start gate, and the staging token base URL. The legacy fake/dry-run gate stayed unset. One active 1:1 native audio call was exercised at a time.

Preflight passed:

| Check | Result | Redacted status |
| --- | --- | --- |
| Backend readiness | Pass | `200`, `ready=true`, `reason=ok` |
| Redis/storage | Pass | allocation/rate-limit connected, storage key configured |
| LiveKit provisioning | Pass | room provisioning configured |
| Eligibility | Pass | eligibility and allowlist configured |
| A/B trust | Pass | own session verified, cross-signing ready, peer trust ready |
| Baseline state | Pass | A/B idle, no active session |

Pilot matrix:

| Case | Result | Redacted status |
| --- | --- | --- |
| A -> B happy path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| B -> A reverse path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 1 | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 2 | Pass | A/B `activeAudio`, then idle/no active session, no split-brain, media failure `none` |
| Decline incoming | Pass | incoming ringing returned A/B idle/no active session |
| Cancel outgoing | Pass | outgoing ringing returned A/B idle/no active session |
| Timeout | Pass | A `outgoingTimeout`, B `incomingTimeout`, A/B idle, `productionHasActiveSession=false`, cleanup/disconnect attempted, media failure `none` |
| Relaunch during ringing | Pass | relaunch returned A/B idle/no active session |
| Listener unavailable/open-room edge | Pass | B stopped before A start; A timed out fail-closed with `outgoingTimeout`, no active session, media failure `none`; B relaunched idle/no active session |
| Backend-off recovery | Not run | local staging call-service stayed up for the pilot |
| LiveKit-off | Not run | shared staging LiveKit must not be stopped without owner approval |

Final status:

- A/B idle;
- A/B no active session;
- media failure `none`;
- no rollback used;
- no stop criteria triggered;
- no redaction issue observed;
- Element Call route stayed untouched.

Runner use: runner-assisted launch, status, trust, and matrix control were used for this engineering expansion rerun. The run did not invoke the Element Call route and did not change Element Call behavior. This is still an engineering-only staging pilot result, not product beta or non-engineering approval.

Dogfood decision: continue the narrow engineering expansion under the 2.33B runbook constraints. Non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.

Next expanded-pilot attempt should use `2.33F — narrow engineering expansion pilot session 2`.

## 2.34A Engineering Expansion Soak Plan

The 2.33E rerun passed, so the next safe step is a short engineering-only soak before any broader readiness review. This is still controlled staging dogfood, not non-engineering internal dogfood, product beta, public rollout, production activation, or Element Call replacement.

### Soak Scope

- Up to 4 named engineering operators.
- Up to 8 named engineering devices.
- Predeclared accounts/devices only.
- Staging call-service and staging LiveKit only.
- Private native audio card only.
- Foreground/open encrypted direct 1:1 rooms only.
- Verified/trusted peers only.
- One active 1:1 native audio call at a time.
- Element Call fallback visible and unchanged.
- Redacted reporting only.
- No non-engineering users.
- No unmanaged devices.

### 3-Session Schedule Template

Use labels only. Keep raw account and device identifiers in operator-local secure notes if needed; do not paste them into docs, chat, screenshots, runner output, or reports.

| Soak session | Planned window | Operator labels | Device labels | Pair labels | Session owner | Redaction reviewer | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Session 1 | `<date/time range>` | `<Operator A/B/...>` | `<Device A1/B1/...>` | `<Pair A-B/...>` | `<Owner>` | `<Reviewer>` | pass/fail/not-run |
| Session 2 | `<date/time range>` | `<Operator A/B/...>` | `<Device A1/B1/...>` | `<Pair A-B/...>` | `<Owner>` | `<Reviewer>` | pass/fail/not-run |
| Session 3 | `<date/time range>` | `<Operator A/B/...>` | `<Device A1/B1/...>` | `<Pair A-B/...>` | `<Owner>` | `<Reviewer>` | pass/fail/not-run |

### Participant And Device Labels

| Operator label | Account role label | Device label | Trust ready | Allowed pair labels | Notes |
| --- | --- | --- | --- | --- | --- |
| Operator A | Caller/Callee A | Device A1 | true/false | A-B | Redacted |
| Operator B | Caller/Callee B | Device B1 | true/false | A-B | Redacted |
| Operator C | Caller/Callee C | Device C1 | true/false | A-C, B-C | Redacted |
| Operator D | Caller/Callee D | Device D1 | true/false | A-D, C-D | Redacted |

Do not record raw Matrix user IDs, room IDs, peer IDs, device IDs, tokens, JWTs, secrets, LiveKit room names, Matrix event bodies, full request/response bodies, or Redis credential URLs.

### Required Gates

Every soak launch must set:

```sh
export IS_RUNNING_INTEGRATION_TESTS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1
export NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1
export NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging-call-service-base-url>
```

`NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` must remain unset for every staging soak session.

### Required Preflight

Backend preflight:

- readiness `ready=true`;
- readiness `reason=ok`;
- Redis allocation store connected;
- Redis rate-limit store connected;
- `storageKeyConfigured=true`;
- `liveKitRoomProvisioningConfigured=true`;
- native audio eligibility and allowlist configured when the status/allowlist path is used;
- Synapse validation smoke passing or explicitly accepted as a blocking prerequisite.

Client preflight:

- app launch ready for both sides;
- trust ready for both sides;
- encrypted direct 1:1 DM open on both sides;
- private native audio card visible;
- no stale active or ringing native session;
- receiver listener/card available;
- Element Call fallback visible and unchanged.

### Per-Session Matrix

Run this matrix once per soak session for each selected pair:

| Case | Required result |
| --- | --- |
| A -> B happy path | Start, Accept, A/B `activeAudio`, Hang up, A/B idle |
| B -> A reverse | Start, Accept, A/B `activeAudio`, Hang up, A/B idle |
| Repeated calls x2 | Two clean calls with no stale session and no split-brain |
| Decline | Incoming side declines; both sides return idle/no active session |
| Cancel | Outgoing side cancels; both sides return idle/no active session |
| Timeout | A `outgoingTimeout`, B `incomingTimeout`, A/B idle, `productionHasActiveSession=false`, media failure `none` |
| Relaunch fail-closed | Relaunch during ringing or active returns no stale active/ringing session |
| Listener/open-room unavailable | Unavailable side does not create unexpected token/media path; active side fails closed |
| Element Call fallback smoke | Existing Element Call route remains visible and unchanged |
| Backend-off/recovery | Run only if safe for the local staging setup; otherwise mark not-run |
| LiveKit-off | Not run unless explicitly approved by the shared staging LiveKit owner |

### Stop Criteria

Stop the soak immediately if:

- any forbidden secret, token, JWT, key, raw identifier, LiveKit room name, credentialed endpoint, Matrix event body, full request/response body, or Redis credential URL appears in output, screenshots, logs, docs, chat, or reports;
- a call starts without the required gates;
- Element Call route behavior changes;
- an untrusted peer or device can connect;
- stale active or ringing state survives cleanup or relaunch;
- backend issues a token for invalid room, peer, trust, or membership;
- media failure does not fail closed;
- split-brain reappears;
- Redis readiness fails or the call-service reports disconnected allocation/rate-limit stores;
- shared staging LiveKit, Matrix, Redis, Nginx, firewall, or production services would need to be changed to continue;
- any critical runtime bug is observed.

### Rollback

1. Unset `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED`, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED`, and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED`.
2. Relaunch the apps.
3. Verify native direct-call status is idle/no active session.
4. Stop the local staging call-service if the session used a local service process.
5. Keep Element Call as the fallback route.
6. Remove soak-only allowlist entries from local operator env when the session ends, if any were added.
7. Preserve only redacted pass/fail status in reports.
8. Rotate affected credentials if any leakage is suspected.

Rollback is complete only when no private native session is active, private dogfood gates are disabled, and Element Call remains available.

### Soak Report Template

```text
Soak session:
- session number:
- session date/time:
- operator labels:
- device labels:
- pair labels:
- build type: DEBUG/integration
- staging call-service readiness: pass/fail
- Redis allocation/rate-limit: pass/fail
- LiveKit room provisioning: pass/fail
- eligibility/allowlist configured: pass/fail/not-used
- A/B trust: pass/fail
- required gates: pass/fail
- old fake/dry-run gate unset: pass/fail

Matrix:
- A -> B happy path:
- B -> A reverse:
- repeated calls x2:
- decline:
- cancel:
- timeout:
- relaunch fail-closed:
- listener/open-room unavailable:
- Element Call fallback:
- backend-off/recovery:
- LiveKit-off:

Final:
- final session state:
- media failure:
- terminal reason:
- cleanup/disconnect:
- runtime bug:
- redaction issue:
- rollback used:
- decision: continue/pause
```

Allowed report fields are limited to pass/fail/not-run, readiness booleans and safe `reason`, trust booleans, redacted card state/reason enums, activation reason enum, `productionSessionState`, `productionMediaFailureReason`, terminal reason enum, media/LiveKit connect attempted booleans, cleanup/disconnect attempted booleans, and Element Call fallback pass/fail.

### Decision Rule

- 3 clean soak sessions: proceed to a readiness review for the next phase.
- Any critical bug or stop criterion: pause the soak, keep non-engineering internal dogfood blocked, and diagnose before continuing.
- Any non-critical not-run row must include a redacted safety reason and be accepted before the session can count as clean.

## 2.34B Engineering Expansion Soak Session 1

Session date/time: `2026-05-24 22:07 +05`.

Operators and devices are recorded only as redacted A/B engineering labels. The session used staging call-service, staging LiveKit, DEBUG/integration diagnostics, product UI, eligibility status, private dogfood, production start, and staging token base URL gates. The legacy fake/dry-run gate stayed unset. One active 1:1 native audio call was exercised at a time.

Preflight passed:

| Check | Result | Redacted status |
| --- | --- | --- |
| Backend readiness | Pass | `200`, `ready=true`, `reason=ok` |
| Redis/storage | Pass | allocation/rate-limit connected, storage key configured |
| LiveKit provisioning | Pass | room provisioning configured |
| Eligibility | Pass | eligibility and allowlist configured |
| A/B trust | Pass | own session verified, cross-signing ready, peer trust ready |
| Activation | Pass | enabled only under explicit private dogfood gates |
| Baseline state | Pass | A/B idle, no active session |

Soak matrix:

| Case | Result | Redacted status |
| --- | --- | --- |
| A -> B happy path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| B -> A reverse path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 1 | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 2 | Pass | A/B `activeAudio`, then idle/no active session, no split-brain, media failure `none` |
| Decline incoming | Pass | incoming ringing returned A/B idle/no active session |
| Cancel outgoing | Pass | outgoing ringing returned A/B idle/no active session |
| Timeout | Pass | A `outgoingTimeout`, B `incomingTimeout`, A/B idle/no active session, media failure `none` |
| Relaunch during ringing | Pass | relaunch returned A/B idle/no active session |
| Listener unavailable/open-room edge | Pass | B stopped before A start; A timed out fail-closed with `outgoingTimeout`, no active session, media failure `none`; B relaunched idle/no active session |
| Post-listener recovery | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Element Call fallback status | Pass | existing Element Call route remained visible/unchanged and was not invoked by the native soak |
| Backend-off recovery | Not run | local staging call-service stayed up for the session |
| LiveKit-off | Not run | shared staging LiveKit must not be stopped without owner approval |

Final status:

- A/B idle;
- A/B no active session;
- media failure `none`;
- media and LiveKit connect attempted on both sides during successful calls;
- cleanup/disconnect attempted on both sides;
- no rollback used;
- no stop criteria triggered;
- no redaction issue observed;
- Element Call route stayed untouched.

Runner use: runner-assisted launch, status, trust, and matrix control were used for this engineering soak session. The run did not invoke the Element Call route and did not change Element Call behavior. This is still an engineering-only staging soak result, not product beta or non-engineering approval.

Dogfood decision: continue the engineering-only soak. Session 1 of 3 is clean. Non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.

Next soak attempt should use `2.34C — engineering expansion soak session 2`.

## 2.34C Engineering Expansion Soak Session 2

Session date/time: `2026-05-24 22:22 +05`.

Operators and devices are recorded only as redacted A/B engineering labels. The session used staging call-service, staging LiveKit, DEBUG/integration diagnostics, product UI, eligibility status, private dogfood, production start, and staging token base URL gates. The legacy fake/dry-run gate stayed unset. One active 1:1 native audio call was exercised at a time.

Preflight passed:

| Check | Result | Redacted status |
| --- | --- | --- |
| Backend readiness | Pass | `200`, `ready=true`, `reason=ok` |
| Redis/storage | Pass | allocation/rate-limit connected, storage key configured |
| LiveKit provisioning | Pass | room provisioning configured |
| Eligibility | Pass | eligibility and allowlist configured |
| A/B trust | Pass | own session verified, cross-signing ready, peer trust ready |
| Activation | Pass | enabled only under explicit private dogfood gates |
| Baseline state | Pass | A/B idle, no active session |

Soak matrix:

| Case | Result | Redacted status |
| --- | --- | --- |
| A -> B happy path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| B -> A reverse path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 1 | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 2 | Pass | A/B `activeAudio`, then idle/no active session, no split-brain, media failure `none` |
| Decline incoming | Pass | incoming ringing returned A/B idle/no active session |
| Cancel outgoing | Pass | outgoing ringing returned A/B idle/no active session |
| Timeout | Pass | A `outgoingTimeout`, B `incomingTimeout`, A/B idle/no active session, media failure `none` |
| Relaunch during ringing | Pass | relaunch returned A/B idle/no active session |
| Listener unavailable/open-room edge | Pass | B stopped before A start; A timed out fail-closed with `outgoingTimeout`, no active session, media failure `none`; B relaunched idle/no active session |
| Post-listener recovery | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Element Call fallback status | Pass | existing Element Call route remained visible/unchanged and was not invoked by the native soak |
| Backend-off recovery | Not run | local staging call-service stayed up for the session |
| LiveKit-off | Not run | shared staging LiveKit must not be stopped without owner approval |

Final status:

- A/B idle;
- A/B no active session;
- media failure `none`;
- media and LiveKit connect attempted on both sides during successful calls;
- cleanup/disconnect attempted on both sides;
- no rollback used;
- no stop criteria triggered;
- no redaction issue observed;
- Element Call route stayed untouched.

Runner use: runner-assisted launch, status, trust, and matrix control were used for this engineering soak session. The run did not invoke the Element Call route and did not change Element Call behavior. This is still an engineering-only staging soak result, not product beta or non-engineering approval.

Dogfood decision: continue the engineering-only soak. Session 2 of 3 is clean. Non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.

Next soak attempt should use `2.34D — engineering expansion soak session 3`.

## 2.34D Engineering Expansion Soak Session 3

Session date/time: `2026-05-24 22:57 +05`.

Operators and devices are recorded only as redacted A/B engineering labels. The session used staging call-service, staging LiveKit, DEBUG/integration diagnostics, product UI, eligibility status, private dogfood, production start, and staging token base URL gates. The legacy fake/dry-run gate stayed unset. One active 1:1 native audio call was exercised at a time.

Preflight passed:

| Check | Result | Redacted status |
| --- | --- | --- |
| Backend readiness | Pass | `200`, `ready=true`, `reason=ok` |
| Redis/storage | Pass | allocation/rate-limit connected, storage key configured |
| LiveKit provisioning | Pass | room provisioning configured |
| Eligibility | Pass | eligibility and allowlist configured |
| A/B trust | Pass | own session verified, cross-signing ready, peer trust ready |
| Activation | Pass | enabled only under explicit private dogfood gates |
| Baseline state | Pass | A/B idle, no active session |

Soak matrix:

| Case | Result | Redacted status |
| --- | --- | --- |
| A -> B happy path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| B -> A reverse path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 1 | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 2 | Pass | A/B `activeAudio`, then idle/no active session, no split-brain, media failure `none` |
| Decline incoming | Pass | incoming ringing returned A/B idle/no active session |
| Cancel outgoing | Pass | outgoing ringing returned A/B idle/no active session |
| Timeout | Pass | A `outgoingTimeout`, B `incomingTimeout`, A/B idle/no active session, media failure `none` |
| Relaunch during ringing | Pass | relaunch returned A/B idle/no active session |
| Listener unavailable/open-room edge | Pass | B stopped before A start; A timed out fail-closed with `outgoingTimeout`, no active session, media failure `none`; B relaunched idle/no active session |
| Post-listener recovery | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Element Call fallback status | Pass | existing Element Call route remained visible/unchanged and was not invoked by the native soak |
| Backend-off recovery | Not run | local staging call-service stayed up for the session |
| LiveKit-off | Not run | shared staging LiveKit must not be stopped without owner approval |

Final status:

- A/B idle;
- A/B no active session;
- media failure `none`;
- media and LiveKit connect attempted on both sides during successful calls;
- cleanup/disconnect attempted on both sides;
- no rollback used;
- no stop criteria triggered;
- no redaction issue observed;
- Element Call route stayed untouched.

Runner use: runner-assisted status, trust, and matrix control were used for this engineering soak session. The run did not invoke the Element Call route and did not change Element Call behavior. This is still an engineering-only staging soak result, not product beta or non-engineering approval.

Dogfood decision: the engineering-only soak can continue only under the same narrow controls. Session 3 of 3 is clean, so the planned engineering expansion soak is complete and ready for a post-soak readiness review. Non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.

Next phase should use `2.35A — post-soak engineering expansion readiness review`.

## 2.36C Internal Pilot Activation Provider Skeleton

The iOS app now has a native-audio-specific internal pilot activation provider skeleton. It is disabled and fail-closed by default, and it is not wired to enable non-engineering Start or Accept.

The skeleton defines:

- activation states: `disabled`, `unavailable`, `eligibleForStatusOnly`, and `activationAllowed`;
- safe unavailable reasons: `rolloutDisabled`, `capabilityMissing`, `accountNotEligible`, `peerNotEligible`, `roomNotEligible`, `trustNotReady`, `serviceUnavailable`, `unsupportedClient`, `dependenciesUnavailable`, and `unknown`;
- a provider protocol for a future activation decision boundary;
- a fail-closed default provider;
- a status-only provider that can combine future rollout/capability/eligibility/room/trust/dependency inputs but never returns `activationAllowed`.

Current safety posture:

- non-engineering internal dogfood remains disabled;
- product UI gate alone remains insufficient;
- backend eligibility alone remains insufficient;
- eligibility status remains status/copy only;
- private engineering dogfood remains on `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` under DEBUG/integration gates;
- `directOneToOneCallsEnabled` remains unrelated to native audio activation;
- token endpoint remains final authority before rate-limit, allocation, LiveKit room pre-create, and token issuance.

This phase is a typed skeleton for a future server-backed activation implementation. It does not approve non-engineering users, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, or global activation.

## 2.36D Internal Pilot Activation Skeleton No-Activation Proof

Runtime proof timestamp: 2026-05-25 00:26 +05.

Preflight passed:

- call-service readiness `200`, `ready=true`, `reason=ok`;
- Redis allocation/rate-limit connected;
- storage key configured;
- LiveKit room provisioning configured;
- native audio eligibility and allowlist configured;
- legacy fake/dry-run gate unset.

No-activation proof:

- With product UI and eligibility status enabled, and `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset, activation stayed blocked.
- With the encrypted direct 1:1 room open, activation/trigger dry-run returned `appRolloutDisabled`.
- Adding `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1` while keeping private dogfood unset still blocked Start with `appRolloutDisabled`.
- The no-private-dogfood runs had no Matrix send, no token request, no media connect, no LiveKit client connect, no active session, and media failure `none`.
- `directOneToOneCallsEnabled` was not toggled at runtime because there is no safe runner hook for it without changing Element Call settings. The committed 2.36C tests cover that separation, and Element Call was not touched during this proof.

Private engineering dogfood compatibility proof:

- With `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` restored, A activation was enabled with dependencies ready, room eligible, endpoint accepted, peer trust ready, and key wrapper available.
- A -> B reached `productionSessionState=activeAudio` with encryption ready, media connect attempted, LiveKit client connect attempted, and `productionMediaFailureReason=none`.
- Hangup returned A/B to `productionSessionState=idle` with no active session, cleanup/disconnect attempted, and media failure `none`.

Element Call remained visible/available as fallback and the native path did not use the Element Call route. No app/backend code changed, no redaction issue was observed, and no runtime regression was found.

Next phase should use `2.36E — server-backed internal pilot activation integration plan`.

## 2.36G Internal Pilot Activation Provider No-Activation Proof

Runtime proof timestamp: 2026-05-25 01:42 +05.

Preflight passed:

- call-service readiness `200`, `ready=true`, `reason=ok`;
- Redis allocation/rate-limit connected;
- storage key configured;
- legacy fake/dry-run gate unset.

No-activation proof:

- With product UI and eligibility status enabled, and `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset, activation stayed blocked.
- With the encrypted direct 1:1 room open, activation/trigger dry-run returned `appRolloutDisabled`.
- The no-private-dogfood status showed no Matrix send, no token request, no media connect, no LiveKit client connect, no active session, and media failure `none`.
- Adding `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1` while keeping private dogfood unset still blocked Start with `appRolloutDisabled`.
- Backend eligibility/status and the default-off internal pilot rollout source did not enable runtime Start or Accept.
- `directOneToOneCallsEnabled` was not toggled at runtime because changing Element Call settings is out of scope. The committed server-backed activation-provider tests cover that separation, and Element Call was not touched during this proof.

Private engineering dogfood compatibility proof:

- With `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` restored, A/B trust was ready and A activation was enabled with dependencies ready, room eligible, endpoint accepted, peer trust ready, and key wrapper available.
- A preliminary start attempt timed out before accept because the generic runner wait helper was used; the timeout path cleaned up safely with A `outgoingTimeout`, B `incomingTimeout`, no active session, cleanup/disconnect attempted, and media failure `none`.
- The direct-accept happy path then reached A/B `productionSessionState=activeAudio` with encryption ready, media connect attempted, LiveKit client connect attempted, and `productionMediaFailureReason=none`.
- Hangup returned A/B to `productionSessionState=idle` with no active session, cleanup/disconnect attempted, and media failure `none`.

Element Call remained visible/available as fallback and the native path did not use the Element Call route. No app/backend code changed, no redaction issue was observed, and no runtime regression was found.

Next phase should use `2.36H — internal pilot activation rollout wiring readiness review`.

## 2.36I Internal Pilot Activation Dry-Run Status Wiring

The app now exposes a redacted, status-only internal pilot activation dry-run at the room-card provider boundary. This is diagnostic/status wiring only. It does not enable non-engineering Start or Accept.

Gate:

```sh
export NATIVE_DIRECT_CALL_INTERNAL_PILOT_ACTIVATION_DRY_RUN_ENABLED=1
```

The gate is DEBUG/integration-only and also requires the diagnostic integration harness gates. It is off in default and Release builds.

The dry-run evaluates only redacted model inputs:

- product UI gate;
- internal pilot rollout source;
- backend eligibility result;
- local encrypted direct 1:1 room eligibility;
- peer trust readiness;
- dependency readiness;
- active/stale session state.

Allowed dry-run output fields are:

- `internalPilotActivationDryRunEnabled`;
- `internalPilotActivationDecision` with safe enum values `disabled`, `unavailable`, `statusOnly`, or `activationAllowed`;
- `internalPilotActivationReason` with safe unavailable reasons only;
- redacted booleans for product UI, internal rollout, capability presence, room eligibility, peer trust, dependencies, and active session.

The dry-run must not output raw room IDs, raw user IDs, raw peer IDs, raw device IDs, LiveKit room names, tokens, JWTs, keys, backend URLs, Matrix event bodies, or full request/response bodies.

Side-effect boundary:

- Dry-run may use the existing status eligibility path.
- Dry-run must not send Matrix events.
- Dry-run must not request a LiveKit participant token.
- Dry-run must not rate-limit, allocate, or pre-create a LiveKit room.
- Dry-run must not connect media or LiveKit.
- Dry-run must not start an outgoing call.
- Dry-run must not arm the receiver listener unless the existing private dogfood activation path already allows it.

Activation remains unchanged:

- dry-run `activationAllowed` is report-only;
- Start and Accept remain controlled by the existing private engineering dogfood path;
- product UI alone remains insufficient;
- eligibility status alone remains insufficient;
- backend eligible alone remains insufficient;
- `directOneToOneCallsEnabled` remains unrelated;
- non-engineering internal dogfood remains blocked.

Next phase should use `2.36J — internal pilot activation dry-run no-activation runtime proof`.

## 2.35B Engineering Expansion Operations Handoff

The 3-session engineering expansion soak completed cleanly, so narrow engineering dogfood can continue without per-session Codex supervision only when a named engineering operator owns the session and this handoff checklist is followed. This is still staging-only engineering dogfood, not non-engineering internal dogfood, product beta, public rollout, production activation, or Element Call replacement.

### Current Allowed Scope

- Up to 4 named engineering operators.
- Up to 8 named devices.
- Predeclared pair labels only.
- Staging call-service and staging LiveKit only.
- Private native audio card only.
- Foreground/open encrypted direct 1:1 rooms only.
- Verified/trusted peers only.
- One active 1:1 native audio call at a time.
- Element Call fallback visible and unchanged.
- Redacted reporting only.
- No non-engineering users.
- No unmanaged devices.

### Operator-Owned Session Checklist

Use labels only. Do not record raw Matrix user IDs, room IDs, peer IDs, device IDs, tokens, JWTs, secrets, LiveKit room names, Matrix event bodies, full request/response bodies, or Redis credential URLs.

| Role | Required owner | Responsibility |
| --- | --- | --- |
| Session owner | `<Operator label>` | Confirms scope, gates, pair labels, one-call-at-a-time rule, and final decision |
| Backend readiness watcher | `<Operator label>` | Checks call-service readiness before the session and watches for readiness failures during the session |
| Client operator A/B | `<Operator labels>` | Runs private-card actions only inside predeclared encrypted 1:1 rooms |
| Redaction reviewer | `<Reviewer label>` | Reviews report text before it is committed or pasted into shared channels |
| Stop authority | `<Operator label>` | Can stop the session immediately when any stop criterion is met |
| Rollback owner | `<Operator label>` | Unsets gates, relaunches apps, stops session-local services, and records rollback outcome |

### Pre-Session Checklist

Backend:

- readiness `ready=true`;
- readiness `reason=ok`;
- Redis allocation store connected;
- Redis rate-limit store connected;
- `storageKeyConfigured=true`;
- `liveKitRoomProvisioningConfigured=true`;
- native audio eligibility and allowlist configured when used;
- Synapse validation smoke passing or explicitly accepted as a blocking prerequisite.

Clients:

- A/B app launch ready;
- A/B trust ready;
- encrypted direct 1:1 DM open on both clients;
- private native audio card visible;
- no stale active or ringing native session;
- Element Call fallback visible;
- old fake/dry-run gate unset.

### Required Gates

Every engineering expansion session must set:

```sh
export IS_RUNNING_INTEGRATION_TESTS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1
export NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1
export NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging-call-service-base-url>
```

`NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` must remain unset.

### Monitoring Baseline

Reports may include only:

- readiness booleans and safe readiness `reason`;
- trust readiness booleans;
- `productionSessionState`;
- `productionMediaFailureReason`;
- terminal reason enum;
- cleanup/disconnect attempted booleans;
- pass/fail/not-run;
- redacted backend reason enums.

Reports must not include:

- Matrix access tokens;
- Synapse admin token;
- LiveKit API secret;
- participant JWT/token;
- raw room IDs;
- raw user, peer, or device IDs;
- LiveKit room names;
- media keys;
- Matrix event bodies;
- Redis credentials;
- full request/response bodies.

### Stop Criteria

Stop immediately if:

- any raw secret, token, JWT, key, ID, LiveKit room name, Matrix event body, full request/response body, credentialed endpoint, or Redis credential URL appears in output, logs, screenshots, docs, chat, or reports;
- a call starts without the required gates;
- Element Call route behavior changes;
- an untrusted peer or device can connect;
- stale active or ringing state survives cleanup or relaunch;
- backend issues a token for invalid room, peer, trust, or membership;
- media failure does not fail closed;
- split-brain reappears;
- readiness is not `ready=true` / `reason=ok` before the session.

### Rollback

1. Unset `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED`, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED`, and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED`.
2. Relaunch the apps.
3. Verify native direct-call status is idle/no active session.
4. Stop the local staging call-service if the session used a session-local service process.
5. Keep Element Call as the fallback route.
6. Rotate affected credentials if any leakage is suspected.
7. Mark the session paused, not failed, when rollback completed cleanly and no product bug was proven.

### Redacted Report Intake

Record clean engineering sessions in this document and summarize them in `docs/direct-call/STATUS.md` / `docs/direct-call/WORKLOG.md` when they change the project decision. Keep reports docs-only unless an approved runtime bug fix is required.

```text
Engineering expansion session:
- session date/time:
- operator labels:
- device labels:
- pair labels:
- session owner:
- backend readiness watcher:
- redaction reviewer:
- required gates: pass/fail
- old fake/dry-run gate unset: pass/fail
- backend readiness: pass/fail
- Redis allocation/rate-limit: pass/fail
- LiveKit room provisioning: pass/fail
- eligibility/allowlist configured: pass/fail/not-used
- A/B trust: pass/fail
- Element Call fallback visible: pass/fail

Matrix:
- A -> B happy path:
- B -> A reverse:
- repeated calls x2:
- decline:
- cancel:
- timeout:
- relaunch fail-closed:
- listener/open-room unavailable:
- Element Call fallback:
- backend-off/recovery:
- LiveKit-off:

Final:
- final session state:
- media failure:
- terminal reason:
- cleanup/disconnect:
- runtime bug:
- redaction issue:
- rollback used:
- stop criteria triggered:
- decision: continue/pause
```

Before committing a clean session report:

- confirm the diff is docs-only;
- run `git diff --check`;
- run a docs secret scan;
- run the direct-call forbidden scan;
- verify no forbidden raw IDs, tokens, secrets, LiveKit room names, Redis credentials, Matrix event bodies, or full request/response bodies appear in the diff.

### Periodic Cadence

- Run at least one redacted engineering session weekly while the expansion remains active.
- Rerun the full matrix after native-call state-machine changes.
- Rerun the full matrix after backend token, eligibility, Redis readiness, allocation, rate-limit, or LiveKit room-provisioning changes.
- Rerun the full matrix after LiveKit staging config, proxy, TLS, or shared infrastructure changes that could affect media connect.
- Run a shorter A -> B / B -> A / repeated-call smoke after routine app rebuilds when no direct-call code changed.

### Expansion Decision Rule

- Continue engineering expansion if sessions remain clean and stop criteria do not trigger.
- Pause immediately if any stop criterion triggers.
- Keep the current cap unless a separate readiness review approves a change.
- Non-engineering internal dogfood remains blocked until a separate readiness review approves server-backed activation, support ownership, user-safe UX, monitoring, and rollback.

## 2.35C Operator-Owned Engineering Expansion Session 1

Session date/time: 2026-05-24 23:32 +05.

Operator/device labels:

- Operator A / Device A1.
- Operator B / Device B1.

Roles:

| Role | Label |
| --- | --- |
| Session owner | Operator A |
| Backend readiness watcher | Operator A |
| Client operators | Operator A / Operator B |
| Redaction reviewer | Operator B |
| Stop authority | Operator A |
| Rollback owner | Operator A |

Preflight:

| Check | Result | Redacted status |
| --- | --- | --- |
| Required gates | Pass | product UI, eligibility status, private dogfood, production start, and staging token base URL set |
| Old fake/dry-run gate | Pass | unset |
| Backend readiness | Pass | `ready=true`, `reason=ok` |
| Redis allocation/rate-limit | Pass | connected |
| Storage key | Pass | configured |
| LiveKit room provisioning | Pass | configured |
| Eligibility/allowlist | Pass | configured |
| A/B trust | Pass | own session verified, cross-signing ready, peer trust ready |
| A/B baseline | Pass | room attached, `productionSessionState=idle`, no active session, media failure `none` |
| Element Call fallback | Pass | visible/unchanged |

Matrix:

| Case | Result | Redacted status |
| --- | --- | --- |
| A -> B happy path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| B -> A reverse path | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 1 | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Repeated call 2 | Pass | A/B `activeAudio`, then idle/no active session, no split-brain, media failure `none` |
| Decline incoming | Pass | A/B idle/no active session |
| Cancel outgoing | Pass | A/B idle/no active session |
| Timeout | Pass | A `outgoingTimeout`, B `incomingTimeout` |
| Relaunch during ringing | Pass | relaunch returned A/B idle/no active session |
| Listener unavailable/open-room edge | Pass | A timed out fail-closed with `outgoingTimeout`; no active session |
| Post-listener recovery | Pass | A/B `activeAudio`, then idle/no active session, media failure `none` |
| Element Call fallback status | Pass | visible/unchanged; native session did not invoke the Element Call route |
| Backend-off recovery | Not run | local staging call-service stayed up for the session |
| LiveKit-off | Not run | shared staging LiveKit must not be stopped without owner approval |

Final status:

- A/B idle.
- A/B no active session.
- Media failure `none`.
- Cleanup/disconnect attempted on both sides.
- No rollback used.
- No stop criteria triggered.
- No redaction issue observed.
- Element Call route stayed untouched.
- No app/backend code changed.

Decision: continue engineering-only staging expansion under the 2.35B operations handoff. This operator-owned session confirms that named engineers can run the narrow staging flow with runner/status assistance and redacted reporting, but it does not approve non-engineering dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, video, session restoration, or global activation.

### Remaining Blockers After Expansion

Even if the expanded engineering pilot passes, the following remain blocked:

- non-engineering users;
- broad internal rollout;
- production/public rollout;
- Element Call replacement;
- CallKit;
- push/background incoming;
- missed calls;
- video;
- session restoration;
- foreground/open-room listener limitation removal;
- global production activation.

## 2.31F Redis Readiness Recovery Smoke

| Check | Result | Redacted reason |
| --- | --- | --- |
| Backend readiness after Redis restore | Pass | readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, eligibility configured |
| A/B trust | Pass | own session verified, cross-signing ready, peer trust ready |
| A -> B happy path | Pass | A started, B reached `incomingRinging`, B accepted, A/B reached `activeAudio` |
| Media path | Pass | Media connect and LiveKit client connect attempted on both sides, media failure `none` |
| Hangup/final state | Pass | A/B returned to `idle`, no active session, cleanup/disconnect attempted, media failure `none` |
| Element Call separation | Pass | Existing Element Call route untouched |

This smoke closes the post-restore check after request-time Redis readiness was fixed in `f4656983a`.

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

## 2.28B Pilot Session 1 Result

Session recorded: 2026-05-22, Asia/Almaty.

Operators and client devices are recorded only as redacted A/B engineering participants. The session used DEBUG/integration builds, the staging call-service, staging LiveKit, foreground/open encrypted direct 1:1 room context, verified/trusted peers, and the private native audio card. Element Call remained available as fallback and was not changed.

| Check | Result | Redacted reason |
| --- | --- | --- |
| Backend preflight | Pass | readiness `ready=true`, `reason=ok`, Redis/storage booleans true, LiveKit room provisioning true |
| Client preflight | Pass | A/B trust ready, private card available, no stale active session |
| Required gates | Pass | Product UI, private dogfood, production start, and staging token base were set; legacy fake/dry-run gate unset |
| Happy path A -> B | Pass | Manual private-card Start/Accept/Hang up; A/B `activeAudio` -> `idle`, media failure `none` |
| Reverse B -> A | Pass | Manual private-card Start/Accept/Hang up; A/B `activeAudio` -> `idle`, media failure `none` |
| Repeated call | Pass | Manual private-card call returned A/B to `idle`, no stale session, no split-brain |
| Decline | Pass | A/B `idle`, terminal `cancelled`, caller received reject |
| Cancel | Pass | A/B `idle`, terminal `cancelled`, callee received cancel |
| Timeout | Pass | A/B `idle`, terminal `outgoingTimeout` / `incomingTimeout` |
| Relaunch fail-closed | Pass | Relaunch from active session restored no active session and no media path |
| Backend-off recovery | Not run | Local staging call-service stayed up for the manual pilot; backend-off remains covered by the 2.27F matrix |
| LiveKit-off | Not run | Shared staging LiveKit; stopping it could affect other users |
| Element Call fallback | Pass | Existing Element Call route remained untouched and available as fallback |

Runner use in this pilot was limited to launch, readiness/trust/status polling, and relaunch. Start, Accept, Decline, Cancel, and Hang up were manual private-card actions.

No rollback was needed, no stop criteria triggered, no runtime bug was observed, and no redaction or secret-leakage issue was found. Final A/B status was idle/no active session with media failure `none`. Controlled engineering dogfood may continue on the same narrow staging path.

## 2.28C Pilot Session 2 Result

Session recorded: 2026-05-22, Asia/Almaty.

Operators and client devices are recorded only as redacted A/B engineering participants. The session used DEBUG/integration builds, the staging call-service, staging LiveKit, foreground/open encrypted direct 1:1 room context, verified/trusted peers, and the private native audio card. Element Call remained available as fallback and was not changed.

| Check | Result | Redacted reason |
| --- | --- | --- |
| Backend preflight | Pass | readiness `ready=true`, `reason=ok`, Redis/storage booleans true, LiveKit room provisioning true |
| Client preflight | Pass | A/B launched, A/B trust ready, listener armed, private card available, no stale active session |
| Required gates | Pass | Product UI, private dogfood, production start, and staging token base were set; legacy fake/dry-run gate unset |
| Happy path A -> B | Pass | Manual private-card Start/Accept/Hang up; A/B `activeAudio` -> `idle`, media failure `none` |
| Reverse B -> A | Pass | Manual private-card Start/Accept/Hang up; A/B `activeAudio` -> `idle`, media failure `none` |
| Repeated call 1 | Pass | Manual private-card call returned A/B to `idle`, no stale session |
| Repeated call 2 | Pass | Manual private-card call returned A/B to `idle`, no stale session, no split-brain |
| Decline | Pass | A/B `idle`, terminal `cancelled`, caller received reject |
| Cancel | Pass | A/B `idle`, terminal `cancelled`, callee received cancel |
| Relaunch fail-closed | Pass | Relaunch from active session restored no active session and no media path |
| Timeout | Not run | Optional in session 2; covered by session 1 and the 2.27F matrix |
| Backend-off recovery | Not run | Local staging call-service stayed up for the manual pilot; backend-off remains covered by the 2.27F matrix |
| LiveKit-off | Not run | Shared staging LiveKit; stopping it could affect other users |
| Element Call fallback | Pass | Existing Element Call route remained untouched and available as fallback |

Runner use in this pilot was limited to launch, readiness/trust/status polling, and relaunch. Start, Accept, Cancel, and Hang up were manual private-card actions.

No rollback was needed, no stop criteria triggered, no runtime bug was observed, and no redaction or secret-leakage issue was found. Final A/B status was idle/no active session with media failure `none`. Final readiness remained `ready=true`, `reason=ok`. Controlled engineering dogfood may continue on the same narrow staging path.

## 2.29B Broader Internal Dogfood Hardening Plan

The current decision remains engineering-only. The 2.28B and 2.28C sessions prove repeatability on the narrow staging path, but they do not approve broader internal dogfood or any non-engineering user pilot.

The smallest safe expansion before non-engineering users is still limited to named engineering operators, more engineering devices/pairs, the staging call-service, staging LiveKit, foreground/open encrypted direct 1:1 rooms, verified/trusted peers, private native audio card only, Element Call fallback visible, and redacted reporting.

Before a future narrow non-engineering internal pilot, complete the following hardening areas.

### Activation And Rollout Model

- Replace DEBUG/integration-only activation with an explicit internal-pilot rollout model that is still fail-closed by default.
- Add a server-side allowlist or capability source for named internal pilot accounts/devices.
- Keep product UI, start permission, rollout eligibility, dependency readiness, room eligibility, and trust eligibility as separate gates.
- Keep public/global production activation impossible until a separate release decision.
- Do not reuse the existing Element Call feature flag as the native dogfood rollout gate.

### UX And Failure Copy

- Replace engineering-only status dependence with user-safe in-app states for unavailable, connecting, failed, timed out, cancelled, declined, and recovered calls.
- Make backend/token unavailable, LiveKit/media unavailable, untrusted peer/device, and invalid room conditions understandable without exposing internal details.
- Make the foreground/open-room limitation visible before users rely on it.
- Add clear recovery actions: retry, fall back to Element Call, or dismiss.
- Keep raw IDs, tokens, Matrix event bodies, and backend response bodies out of UI and logs.

### Incoming Behavior And Foreground Limitation

- Keep non-engineering pilots blocked until incoming behavior is intentionally scoped.
- If foreground/open-room remains the pilot limitation, explain it in-product and in the pilot instructions.
- Treat CallKit, push/background incoming, missed calls, and session restoration as future blockers, not part of this hardening phase.
- Verify listener not armed, app relaunch, room switch, and timeout behavior remain fail-closed.

### Monitoring And Telemetry Redaction

- Replace runner-only observability with redacted app/backend telemetry suitable for a pilot owner.
- Allow only readiness booleans, trust booleans, terminal reason enums, media failure enums, cleanup/disconnect booleans, and aggregate counters.
- Add leak checks for tokens, JWTs, keys, room IDs, user IDs, peer IDs, device IDs, Matrix event bodies, and credentialed URLs before sharing reports.
- Preserve a redacted incident template for pilot reports.

### Backend And Staging Operations

- Give staging call-service an explicit owner, supervisor, start/stop path, and readiness dashboard/check.
- Keep Redis allocation/rate-limit health visible through redacted readiness only.
- Keep LiveKit room provisioning readiness visible without exposing keys, room names, or participant tokens.
- Decide whether a dedicated SalemX staging LiveKit instance is required before non-engineering users so LiveKit-off and failure-recovery tests can run without affecting shared users.
- Keep Synapse validation smoke available before each pilot window.

### Support And Rollback

- Define who can start, pause, and stop the pilot.
- Keep Element Call as the immediate fallback path and smoke it as unchanged.
- Provide non-engineering-safe rollback instructions: disable the native card gate, relaunch, use Element Call, and report only redacted status.
- Define escalation and incident ownership for failed calls, stale sessions, suspected leakage, and backend readiness failure.

### Security Review

- Review token issuance, room validation, Redis keying, rate limits, LiveKit room provisioning, and access-token handling before non-engineering users.
- Confirm trusted-device and E2EE behavior are not weakened.
- Confirm no secret, token, JWT, key, envelope plaintext, raw Matrix content, raw room ID, raw user ID, raw peer ID, or raw device ID appears in UI, logs, docs, screenshots, or reports.
- Keep ignored env files untracked and mode `600`.
- Define credential rotation triggers and owners.

### Soak Testing

- Run more engineering sessions across more devices, networks, app relaunch timings, and repeated-call windows.
- Include happy path, reverse, repeated calls, decline, cancel, timeout, backend-off recovery when safe, relaunch fail-closed, listener unavailable, and Element Call fallback checks.
- Record pass/fail/not-run only with redacted reason enums.
- Non-engineering pilot remains blocked until the soak has no stale active sessions, no split-brain, no redaction issues, and no unexplained media failures.

### Minimum Acceptance Checklist For Narrow Non-Engineering Internal Pilot

- Explicit internal-pilot rollout or allowlist model exists and is fail-closed by default.
- Non-engineering-safe UX exists for all expected failure states.
- Foreground/open-room limitation is documented and visible, or CallKit/push/background incoming is separately implemented and approved.
- Redacted telemetry/reporting replaces runner-only diagnostics for pilot monitoring.
- Staging call-service has an owned supervisor/start/stop path and readiness checks.
- Redis, Synapse validation, LiveKit room provisioning, and staging LiveKit health are checked before each session.
- Element Call fallback remains visible, unchanged, and smoke-tested.
- Security review passes for token issuance, room validation, E2EE/trust, logs, env files, and redaction.
- Soak matrix passes across multiple named engineering operators/devices without stale active sessions, split-brain, untrusted peer/device connection, or secret/raw ID leakage.

Until every item above is complete, broader internal dogfood and non-engineering pilot remain blocked.

## Reporting Format

Reports must be pass/fail only with redacted status fields. Allowed fields:

- readiness booleans;
- trust booleans;
- redacted card state/reason enums;
- listener availability booleans/enums;
- activation reason enum;
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
- LiveKit room names.
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
- redacted internal pilot activation dry-run enum/booleans when the dry-run gate is explicitly enabled;
- cleanup and disconnect booleans.

Do not capture raw backend request bodies, full response bodies, Matrix event bodies, bearer tokens, LiveKit participant tokens, JWTs, raw room IDs, raw user IDs, raw peer IDs, raw device IDs, LiveKit room names, Redis URLs with credentials, or LiveKit API secrets.

Rotate affected credentials if any secret, token, JWT, key, credentialed endpoint, raw identifier, or LiveKit room name appears in shared output, screenshots, logs, shell history, or docs. Pause the pilot until the leak source is removed and redaction is re-verified.

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

- Server-backed internal pilot activation remains default-off. The iOS activation provider can model `activationAllowed` for tests and dry-run/status output only when all gates pass, and 2.36G/2.36I keep runtime Start/Accept controlled by private dogfood; non-engineering Start/Accept is still not enabled until a separate rollout wiring implementation, runtime proof, and readiness review pass.
- The 2.36J dry-run runtime proof confirmed the dry-run gate does not activate Start/Accept without private dogfood, even when product UI, eligibility status, and production start are enabled. Private engineering dogfood still reached active audio and returned idle. Current runner diagnostics do not directly export the new dry-run enum fields, so operator-facing dry-run telemetry still needs a redacted runner/status signal before it is used for broader monitoring.
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
