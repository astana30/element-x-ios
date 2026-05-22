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

The 2.26D activation cleanup replaced the older DEBUG fake rollout/capability shim with an explicit private dogfood gate, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`. Product-card-only dogfood still needs a fresh staging smoke under this explicit gate before it can be claimed cleanly.

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

## Operational Preflight

Complete this checklist before every dogfood session:

- Staging call-service readiness is `ready=true`, `reason=ok`.
- Redis allocation store is configured, shared, and connected.
- Redis rate-limit store is configured, shared, and connected.
- `storageKeyConfigured=true`.
- `liveKitRoomProvisioningConfigured=true`.
- Synapse validation smoke is available and passing.
- Token TTL and allocation TTL remain bounded.
- Staging env files are ignored by git and mode `600`.
- A/B app launch succeeds through the diagnostic runner.
- A/B trust diagnostics are ready.
- The encrypted direct 1:1 DM is open on both clients.
- Receiver listener is available or armed.
- Existing Element Call toolbar path is visible and available as fallback.

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

## Rollback

1. Unset `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`, `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED`, and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED`.
2. Relaunch the apps.
3. Stop the local staging call-service if the session uses a local service process.
4. Stop local Redis if the session uses a disposable local Redis container.
5. Keep using the existing Element Call toolbar path.
6. Collect only redacted `production-status` output for debugging.
7. Rotate affected secrets if leakage is suspected.
8. Do not preserve raw backend request bodies, bearer tokens, LiveKit participant tokens, Matrix event content, room IDs, user IDs, peer IDs, or device IDs.

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
- Clean product-card-only dogfood remains pending until the staging matrix is rerun through the private card with `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
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
