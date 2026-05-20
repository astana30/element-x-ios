# Private Native Audio Call Engineering Dogfood

This runbook defines the only approved scope for controlled engineering dogfood of the private native audio call path.

The current decision is conditional yes for tightly controlled engineering dogfood only. This is not approved for broad internal dogfood, product beta, public rollout, or replacement of the existing Element Call buttons.

## Scope

- DEBUG/integration builds only.
- Private native call room card only.
- Open encrypted direct 1:1 rooms only.
- Foreground app only.
- Verified/trusted peer devices only.
- Local fake backend plus local LiveKit dev server, or a hardened staging equivalent with the same redaction and fail-closed guarantees.
- Existing Element Call phone/video buttons remain visible, unchanged, and available as the rollback call path.
- Audio only.

## Required Gates

All dogfood launches must set the following gates explicitly:

```sh
export IS_RUNNING_INTEGRATION_TESTS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS=1
export NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1
export NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=http://127.0.0.1:8088
```

`NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1` is required for the current fake-backed proof setup. Remove it only when a hardened staging capability and dependency path replaces the local fake proof.

Do not enable public or global production direct calls.

## Setup

1. Use trusted `r1` and `r2` engineering test accounts.
2. Verify the two devices/users trust each other before testing native calls.
3. Start the local fake call service with placeholder local credentials only:

```sh
cd server/salemx-call-service
SALEMX_CALL_SERVICE_MODE=local_fake \
SALEMX_CALL_SERVICE_FAKE_MODE=1 \
LIVEKIT_URL=ws://localhost:7880 \
LIVEKIT_API_KEY=<local-livekit-api-key> \
LIVEKIT_API_SECRET=<local-livekit-api-secret> \
python3 -m uvicorn salemx_call_service.app:app --host 127.0.0.1 --port 8088
```

4. Start a local LiveKit dev server:

```sh
docker run --rm \
  -p 7880:7880 \
  -p 7881:7881 \
  -p 7882:7882/udp \
  livekit/livekit-server \
  --dev \
  --bind 0.0.0.0
```

5. Launch A/B with the required gates.
6. Open the same encrypted direct 1:1 room on both clients.
7. Arm the receiver listener from the private card or the approved DEBUG/integration command path if required.
8. Confirm readiness through redacted status only before starting manual proof flows.

## Allowed Manual Flows

- Start audio, Accept, Hang up.
- Decline incoming.
- Cancel outgoing.
- Retry after a failed state.
- Dismiss local error state.
- Repeated calls after cleanup.
- Reverse-direction calls.
- Backend-off failure and recovery.
- LiveKit-off failure and recovery.
- Outgoing and incoming timeout.

## Known Limitations

- No background incoming calls.
- No CallKit.
- No push.
- No missed calls.
- No video.
- No call restoration after app relaunch.
- Receiver listener availability is open-room scoped and may require explicit arming.
- Current backend proof uses local fake mode and is not production-hardened.
- Existing Element Call remains the only non-dogfood call path.

## Fail-Closed Expectations

- Backend unavailable must fail closed with a user-safe call service or token HTTP failure.
- LiveKit unavailable must fail closed with a user-safe audio connection failure.
- Unverified peer devices must block before media-key wrapping.
- Invalid rooms must remain unavailable.
- App relaunch during ringing or active calls must not restore stale sessions.
- Room dismiss/reopen must not preserve stale production owner, listener, media, or active session state.

## Redaction Checklist

Before sharing logs, screenshots, runner output, or bug reports, verify they contain none of the following:

- Raw access tokens.
- Raw JWTs.
- Raw media keys.
- Raw Matrix event content.
- Raw room IDs.
- Raw peer IDs.
- Endpoint credentials.
- LiveKit API secrets.
- Matrix encrypted payload bodies.

Only share redacted booleans, enums, user-safe reasons, and non-identifying status fields.

## Rollback

1. Unset `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`.
2. Relaunch the app.
3. Keep using the existing Element Call buttons.
4. Stop the local fake backend if it is no longer needed.
5. Stop the local LiveKit dev server if it is no longer needed.
6. Collect only redacted `production-status` output for debugging.
7. Do not preserve raw backend request bodies, bearer tokens, LiveKit participant tokens, or Matrix event content.

## Explicit Non-Goals

- Public rollout.
- Product beta.
- Replacing the Element Call toolbar buttons.
- CallKit.
- Push or background incoming calls.
- Video.
- Missed calls.
- Production `AllDevices` trust fallback.
- Weakening `OnlyTrustedDevices` media-key wrapping.
- Public/global production activation.

## Staging Blockers

Before any staging dogfood replaces the local fake proof, the backend and deployment path need:

- Real Synapse validation.
- Shared call allocation store.
- Rate limiting.
- Explicit staging mode with fake mode disabled and redacted readiness returning `ok`.
- Token TTL and replay protection.
- TLS-backed LiveKit URL and certificates.
- Production-safe LiveKit API key management.
- Operational monitoring.
- Redacted incident/debug collection.
- Rollback plan.
- Capability rollout plan.
- Explicit owner for backend uptime during dogfood windows.

## Dogfood Session Success Criteria

- The private card appears only with `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- The diagnostic panel remains separately gated.
- Element Call buttons remain visible and unchanged.
- Start/Accept reaches active audio.
- Hangup/Decline/Cancel clear both sides.
- Retry does not auto-start.
- Dismiss is local-only.
- Backend and LiveKit failures return user-safe errors.
- Recovery after backend and LiveKit restart reaches active audio again.
- Timeout clears both sides.
- Relaunch during ringing or active calls fails closed with no stale active session.
- Output remains redacted.

## Stop Conditions

Stop dogfood immediately if any of the following occurs:

- A raw token, JWT, media key, Matrix event body, room ID, peer ID, or endpoint secret appears in UI, logs, runner output, or docs.
- Element Call buttons change behavior.
- A call starts without the product UI gate.
- A call starts in an invalid room or with untrusted peer readiness.
- A relaunch restores stale active or ringing call state.
- Backend or LiveKit failure leaves a stale active session.
- Media connects without encrypted key readiness.
