# Server-Backed Foreground Signaling

## 2.42C - Server-Backed Foreground Signaling Transport

Status: blocked on server endpoint availability; documented as a server contract and client-boundary checkpoint.

## Decision

2.42C inspected the existing SalemX call-service and app client boundaries. No safe foreground call-signaling endpoint or app runtime configuration exists yet.

Because no endpoint exists, this phase does not add a production WebSocket, SSE, long-poll, or hardcoded server URL. The app remains at the 2.42B boundary: a disabled/default transport plus an in-memory test transport that can feed safe invite events into `ForegroundCallInviteHandler`.

## Files Inspected

- `server/salemx-call-service/salemx_call_service/app.py`
- `server/salemx-call-service/salemx_call_service/service.py`
- `server/salemx-call-service/salemx_call_service/dto.py`
- `server/salemx-call-service/salemx_call_service/config.py`
- `ElementX/Sources/Services/Calls/DirectCallModels.swift`
- `ElementX/Sources/Services/Calls/DirectCallMediaEngineProtocol.swift`
- `ElementX/Sources/Services/Calls/DirectCallMediaModels.swift`
- `docs/direct-call/FOREGROUND_CALL_SIGNALING_CHANNEL.md`
- `docs/direct-call/FOREGROUND_SIGNALING_TRANSPORT_PROTOTYPE.md`

## Current Server Surface

The call-service currently exposes:

- redacted health
- redacted readiness
- native audio eligibility
- server-issued media credential allocation
- local fake capability discovery in local fake mode

It does not expose:

- foreground call invite subscription
- foreground call invite fanout
- foreground call acknowledgement
- foreground call stale invalidation stream
- reconnect or resume cursor semantics
- server-backed invite transport configuration for the app

## Client Boundary State

The 2.42A/2.42B app boundary is ready for a future endpoint:

- `ForegroundCallInviteSignal`
- `ForegroundCallInviteValidator`
- `ForegroundCallInviteHandler`
- `ForegroundCallSignalingTransport`
- `DisabledForegroundCallSignalingTransport`
- `InMemoryForegroundCallSignalingTransport`
- `ForegroundCallSignalingTransportPipeline`

The executable proof remains local and inert by default. Invite receipt does not request media credentials, connect media, emit Matrix call events, bypass foreground acceptance, or alter Element Call routing.

## Required Server Endpoint Contract

A future server-backed transport needs an authenticated foreground-only signaling channel, for example a WebSocket or SSE route under the SalemX direct-call namespace.

Required properties:

- authenticated subscription bound to the active app session
- device/session scoped delivery
- foreground-only lifecycle; no background wake behavior
- minimal opaque invite payload
- server-side stale invalidation
- duplicate suppression guidance
- acknowledgement model for received, displayed, answered, declined, ended, and stale outcomes
- reconnect, retry, and resume behavior
- redacted diagnostics only
- no media credentials in invite payloads
- media credential endpoint remains final authority after answer
- timeline call card remains secondary/history

## Minimal Invite Payload Contract

Allowed payload classes:

- schema version
- opaque local call handle
- call kind
- invite state
- creation and expiry timestamps
- safe display label reference
- validation hint enum

Forbidden payload contents:

- raw account identifiers
- raw room identifiers
- raw device identifiers
- raw Matrix event identifiers
- Matrix event bodies
- media credentials
- media-session names
- credentialed URLs
- full request or response bodies

## Client Transport Expectations

A future real transport must:

- stay disabled unless explicitly configured
- parse only the minimal opaque schema
- fail closed on malformed, stale, duplicate, terminal, unsupported, or unverifiable invites
- feed valid invites into `ForegroundCallInviteHandler`
- avoid media credential requests before user answer
- avoid media connection from invite receipt
- avoid Matrix call event emission from invite receipt
- avoid duplicate incoming UI when timeline fallback later observes the same call
- keep all diagnostics redacted

## Redacted Diagnostics

Allowed diagnostics:

- started/stopped booleans
- safe stage enums
- safe result enums
- delivered invite count
- stale/duplicate/malformed counters
- reconnect status class
- elapsed time bucket
- fallback used boolean

Forbidden diagnostics:

- raw account, room, device, event, media-session, participant, signing, credential, URL, request body, response body, or private runtime values

## Blockers

- No server foreground invite endpoint exists.
- No server fanout source is defined for foreground invite delivery before Matrix timeline or room-list materialization.
- No foreground invite acknowledgement endpoint exists.
- No stale invalidation stream exists.
- No reconnect/resume cursor contract exists.
- No app runtime configuration exists for a server-backed foreground invite transport.

## Validation Scope

Because this phase is docs-only, no Swift runtime path changed. The existing 2.42B in-memory transport tests remain the executable proof that an immediate invite can reach the handler without requesting media credentials, connecting media, or emitting Matrix call events.

## Next Phase

Recommended next phase: `2.42D - foreground signaling server endpoint prototype`.

That phase should implement or mock the server endpoint contract in the call-service first, then add an app transport only behind explicit disabled-by-default configuration.

## 2.42D - SalemX Call-Service Foreground Signaling Endpoint

Status: implemented as a server-side foreground-only SSE subscription prototype.

2.42D adds an authenticated call-service stream endpoint:

```text
GET /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream
```

The endpoint returns a foreground stream with a `foreground.ready` event followed by validated opaque `foreground.call.invite` events. The active subscriber registry and invite fanout live in `ForegroundCallSignalingService`.

The current phase intentionally keeps invite publishing as an internal server boundary rather than a public HTTP publish route. A future validated server source must perform membership, eligibility, freshness, and target checks before fanout.

Invite receipt remains side-effect-free for media:

- no media credentials in invite payloads;
- no media credential issuance from stream receipt;
- no media connection from stream receipt;
- no Matrix event emission from stream receipt;
- no background incoming behavior;
- no PushKit/APNs implementation.

Server diagnostics remain redacted to booleans, counters, and safe enums. The payload and logs must not include raw routing identifiers, Matrix event content, credentialed URLs, media-session names, auth credential values, or full request/response bodies.

The server-issued media credential endpoint remains final authority after user answer and local foreground validation.

Remaining server work includes validated call invite source, stale invalidation, acknowledgement states, reconnect/resume semantics, rate limiting, multi-worker/shared delivery backing, and redacted operational dashboards.

Detailed server notes are in `server/salemx-call-service/docs/FOREGROUND_SIGNALING_ENDPOINT.md`.

Recommended next phase: `2.42E - iOS foreground signaling SSE transport integration`.

## 2.42F - Supervised Dev-Only Foreground Invite Source

Status: implemented as a disabled-by-default call-service route for local and staging smoke tests.

2.42F adds a supervised dev route:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite
```

The route is registered only when `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1` is set. With the flag unset, the route is absent.

The route authenticates the active session, validates the existing opaque foreground invite payload, and publishes through the same `ForegroundCallSignalingService` fanout used by the SSE stream.

To avoid raw routing values in request bodies, the dev route targets only the authenticated foreground subscriber for the same active session/device. It is a supervised self-injection path for testing stream delivery, not a production invite API.

The route does not issue media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, add background incoming behavior, or replace Element Call routing. The server-issued media credential endpoint remains final authority after answer-time foreground validation.

Detailed server notes are in `server/salemx-call-service/docs/FOREGROUND_SIGNALING_DEV_INVITE.md`.

Recommended next phase: `2.42G - supervised foreground SSE smoke`.
