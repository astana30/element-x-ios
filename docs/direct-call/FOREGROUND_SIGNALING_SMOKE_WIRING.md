# Foreground Signaling Smoke Wiring

## 2.42G - Supervised Foreground Signaling Smoke Wiring

Status: documented as supervised smoke wiring; no runtime app owner added.

## Decision

2.42G keeps the app runtime unchanged.

The iOS side already has the safe boundary needed for supervised smoke preparation:

- `ForegroundCallSignalingSSETransport`
- `URLSessionForegroundCallSignalingSSEStream`
- injected `URLRequest`
- `ForegroundCallSignalingTransportPipeline`
- existing `ForegroundCallInviteHandler`

The transport remains disabled unless explicitly constructed with `isEnabled=true`. The URLSession stream still requires an injected request and does not construct server URLs or auth headers.

No production runtime owner is added in this phase because the app does not yet have a safe foreground-session lifecycle owner for the SSE stream, authenticated request construction, reconnect/backoff, or fallback de-duplication. Adding that owner would be runtime app wiring rather than smoke setup documentation.

## Supervised Server Setup

For local or staging supervision only:

- start the call-service with the foreground SSE stream endpoint available;
- enable the dev invite route only for the supervised run;
- keep the dev route disabled outside the supervised window.

The SSE stream endpoint is:

```text
GET /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream
```

The supervised dev invite route is:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite
```

The dev invite route is registered only when:

```text
SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1
```

## Supervised iOS Setup

The iOS smoke must construct the SSE stream request through an injected `URLRequest` boundary. The request must be supplied by supervised runtime setup, not hardcoded in the app.

The request construction must:

- use the configured staging/local call-service base URL;
- target the foreground signaling stream path;
- include the active authenticated Matrix session through the existing secure auth boundary;
- avoid logging the full URL if it can contain credentials;
- avoid logging auth headers or raw response bodies.

The transport must remain disabled by default and started only for the supervised foreground run.

## Required Redacted Diagnostics

The smoke report should capture only safe booleans/enums:

- `sse_configured=true/false`
- `sse_connected=true/false`
- `invite_received=true/false`
- `invite_valid=true/false`
- `incoming_requested=true/false`
- `media_credential_requested_from_invite=false`
- `media_connect_attempted_from_invite=false`
- `matrix_event_emitted_from_invite=false`

Forbidden diagnostics remain raw account, room, device, event, auth credential, media-session, media backend, shared store, Apple signing, request body, response body, or private runtime values.

## Expected Smoke Flow

1. Launch the call-service in local or staging supervision.
2. Open the app in foreground on the callee device.
3. Start the iOS SSE transport through the injected request boundary.
4. Confirm `sse_configured=true`.
5. Confirm the stream connects and `sse_connected=true`.
6. Submit one opaque dev invite to the supervised route from the same active callee session.
7. Confirm `invite_received=true`.
8. Confirm `invite_valid=true`.
9. Confirm `incoming_requested=true`.
10. Confirm no media credential request or media connection occurs from invite receipt.
11. Confirm later Matrix room-list/timeline fallback does not duplicate incoming UI.

Full runtime logs must remain out of docs because they can contain private Matrix/runtime values.

## Blockers Before Runtime Smoke

Before a physical-device smoke can be run through the product app, the app still needs a disabled-by-default foreground SSE runtime owner that defines:

- foreground start/stop lifecycle;
- authenticated request construction;
- safe endpoint configuration source;
- reconnect and backoff behavior;
- coordination with timeline/room-list fallback;
- redacted diagnostics surfaced in the physical app path.

## Out Of Scope

This phase does not add:

- PushKit runtime;
- APNs or VoIP value registration;
- background incoming behavior;
- hardcoded production URLs;
- hardcoded credential values;
- media credential request from invite receipt;
- media connection from invite receipt;
- Matrix call event emission from invite receipt;
- Element Call route replacement;
- signing, entitlement, bundle, `Info.plist`, `app.yml`, or project setting changes.

## Next Phase

Recommended next phase: `2.42H - DEBUG foreground SSE runtime owner`.

That phase should add the smallest disabled-by-default DEBUG/dev runtime owner for physical smoke, including redacted diagnostics and explicit start/stop controls, while keeping production default disabled.
