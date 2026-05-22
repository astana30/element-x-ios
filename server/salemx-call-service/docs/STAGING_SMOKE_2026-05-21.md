# SalemX call-service staging smoke - 2026-05-21

## Summary

SalemX call-service staging smoke passed against `https://matrix.mertis.kz` and the staging LiveKit endpoint `wss://rtc.mertis.kz`.

No tokens, JWTs, passwords, shared secrets, authorization header values, or LiveKit participant tokens are recorded in this document.

## Results

| Check | Result |
| --- | --- |
| Call-service readiness | `200`, `ready=true` |
| Synapse Admin `/members` | `200` |
| Synapse Admin `/state` | `200` |
| Call-service token POST | `200` |
| LiveKit participant token | Issued, redacted |
| iOS private native audio staging smoke | `activeAudio`, then `idle` after hangup |
| Controlled engineering dogfood matrix | Passed |
| Product-card-only staging smoke | Passed under explicit private dogfood gate |
| Controlled engineering pilot checkpoint | Allowed, conditional, staging-only |
| Repeated-call split-brain regression proof | Passed |
| Controlled dogfood pilot matrix rerun | Passed |
| Dogfood operations checklist | Recorded |

## Root Cause

The previous staging failure was caused by using a regular MAS/client token as `SYNAPSE_ADMIN_TOKEN`. That token authenticated successfully for `whoami`, but Synapse rejected Admin API calls because it did not carry Synapse admin privileges.

## Fix

Created a dedicated service account:

```text
@salemx-call-service:mertis.kz
```

Issued a MAS compatibility token with Synapse admin privileges for the service account and replaced only `SYNAPSE_ADMIN_TOKEN` in the operator-local staging environment.

## Safety Notes

- `server/salemx-call-service/deploy/staging.env` is ignored by git and mode `600`.
- `server/salemx-call-service/smoke/staging-synapse-smoke.env` is covered by gitignore and should remain mode `600` whenever present.
- The smoke verified the positive private native audio path only.
- No LiveKit, Nginx, firewall, Synapse config, SQLite, TURN, or `macaroon_secret_key` changes were required for this fix.
- App-side staging smoke after backend room pre-create reached active audio with encryption ready, media connect attempted, LiveKit client connect attempted, and media failure `none`.
- Hangup returned both sides to idle, with media disconnect and cleanup attempted.
- The previous service-not-found-like LiveKit blocker is resolved by server-side LiveKit room pre-create in the call-service.
- No iOS app code, Element Call route, CallKit, push, video, or global production activation changed.
- The 2.26C controlled engineering dogfood matrix passed happy path, reverse direction, repeated calls, decline, cancel, timeout, backend-off fail-closed, backend recovery, relaunch fail-closed, and listener-not-armed cases on the real staging media/token/LiveKit path.
- LiveKit-off fail-closed was not run because the staging LiveKit instance is shared.
- The 2.26D app-side cleanup replaces the older DEBUG rollout/capability shim with the explicit `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` gate.
- The 2.26E product-card-only staging smoke proved the private card under that explicit gate: without the gate activation stayed blocked with `appRolloutDisabled`, and with the gate A Start -> B incoming -> B Accept -> A/B active audio -> hangup -> A/B idle passed with media failure `none`.
- The old `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name was explicitly unset and not used during the 2.26E proof.
- Commit `07256bf0a` fixed the receiver listener preparation gap by preparing/arming the listener from card status only when private dogfood activation is already enabled. That preparation does not start outgoing calls, request tokens, send Matrix events, or connect media.
- The 2.27A checkpoint allows only a narrow controlled engineering dogfood pilot: named operators, DEBUG/integration builds, staging call-service and LiveKit, foreground/open encrypted direct 1:1 rooms, verified/trusted peers, private native audio card, and Element Call fallback available.
- Commit `38fa26586` fixed the post-answer callee media/token failure split-brain risk by sending a safe terminal path to the caller.
- The 2.27E runtime proof passed: two repeated A -> B calls reached active audio and returned idle, a forced callee post-answer `tokenHTTPUnavailable` failure did not leave the caller active, and a recovery call reached active audio again after restoring the normal staging URL.
- The 2.27F controlled dogfood pilot matrix rerun passed after the split-brain fix, including happy path, reverse, repeated calls, decline, cancel, timeout, backend-off fail-closed, backend recovery, relaunch fail-closed, and listener/open-room unavailable behavior.
- Backend-off immediate accept with the local staging call-service down failed closed with `connectingFailed`, `tokenHTTPUnavailable`, and no LiveKit client connect.
- LiveKit-off remained not run because shared staging LiveKit should not be stopped during this dogfood pass.
- Runner commands were used for matrix control/status, so 2.27F is not a claim that every matrix case was manually product-card-only. Product-card-only happy path remains separately proven by 2.26E.
- The 2.28A operations checklist documents named operator sign-off, local staging call-service start/stop, readiness checks, Redis checks, A/B gate/trust checks, redacted monitoring, forbidden outputs, stop criteria, rollback, post-session reporting, and security cleanup.
- Security cleanup includes removing temporary SSH keys, rotating any password shared during diagnostics, keeping ignored env files untracked and mode `600`, and preserving Element Call fallback.
- Controlled engineering dogfood may continue under the same narrow staging-only constraints.

## Next Step

Controlled engineering dogfood may continue on the staging path under the private native audio runbook constraints:

- named engineering operators only;
- DEBUG/integration builds only;
- foreground/open-room encrypted direct 1:1 sessions only;
- verified/trusted peers only;
- private native audio card only;
- Element Call toolbar path unchanged and available as fallback;
- no CallKit, push, video, broad internal rollout, public rollout, or global production activation.

Next, run `2.28B — monitored controlled dogfood pilot window` while keeping controlled dogfood narrow and redacted.
