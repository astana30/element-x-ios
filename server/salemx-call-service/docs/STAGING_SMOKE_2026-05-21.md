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

## Next Step

Run app-side smoke for SalemX private native audio calls using the staging call-service and `wss://rtc.mertis.kz`.
