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

## Next Step

Continue with gated app-side staging dogfood hardening and keep output redacted.
