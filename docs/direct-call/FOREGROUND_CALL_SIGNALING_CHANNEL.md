# Foreground Call Signaling Channel

## 2.42A - Foreground Call Signaling Channel Prototype

Status: implemented as an inert client boundary and contract.

## Problem

2.41G-A4/A5 added a current-room foreground observer and diagnostics for repeat incoming calls. Physical diagnostics showed the observer starts correctly and the fast path requests incoming CallKit once it sees a fresh candidate, but the candidate can already be delayed by more than 10 seconds when delivered. 2.41G-A6 found no safe existing app-side source earlier than Matrix sync, timeline materialization, or room-summary updates while PushKit/APNs/background behavior remains out of scope.

## Scope

This phase adds a foreground-only contract surface for a future server-originated call invite signal. It does not add a production WebSocket or other network transport.

The contract includes:

- `ForegroundCallInviteSignal`
- `ForegroundCallSignalingClientProtocol`
- `DisabledForegroundCallSignalingClient`
- `ForegroundCallInviteValidator`
- `ForegroundCallInviteHandler`
- redacted lifecycle diagnostics through the existing native incoming diagnostics recorder

## Runtime Boundary

The disabled client boundary is mockable and local only. A future production client may subscribe to an authenticated foreground signaling channel, but this phase intentionally does not create that transport.

The invite handler can request the existing foreground incoming/CallKit reporting abstraction after validation. It cannot request media credentials, connect media, emit Matrix events, or bypass the foreground acceptance gate.

Answer remains a separate state-machine action. After answer, the foreground acceptance gate still requires server-issued media credential authority before any future media connection is allowed.

## Validation Rules

The foreground invite validator rejects:

- malformed safe local handles
- unsupported call kind
- terminal invite state
- stale or expired invites
- missing safe display metadata

The handler additionally suppresses:

- duplicate invite handles
- already-seen local state
- invalid encrypted direct 1:1, trust, eligibility, session, dependency, login, or route context
- call reporting failures

## Redaction Contract

Allowed diagnostics remain booleans, safe lifecycle states, safe fail-closed enums, report attempted/succeeded flags, media credential requested flag, and media connect attempted flag.

Forbidden in diagnostics and docs:

- raw account, room, device, event, media-session, participant, or signing identifiers
- auth credential values
- push values
- media credential values
- credentialed URLs
- Matrix event bodies
- private runtime logs

## Server Requirements

A future server implementation must provide:

- authenticated foreground call-signaling subscription
- device/session-scoped delivery
- minimal opaque invite payloads
- invite expiry and stale invalidation
- duplicate suppression hints
- answer, decline, and end acknowledgement model
- no media credentials in invite payloads
- no raw identifiers in payloads or logs
- media credential endpoint remains final authority after user answer

## Test Coverage

Unit coverage verifies:

- disabled foreground signaling client is no-op and redacted
- foreground invite can request incoming call reporting
- duplicate, stale, terminal, malformed, unsupported, active-session, and reporting-failure cases fail closed
- invite receipt does not request media credentials or connect media
- answer still requires the foreground acceptance gate
- timeline or room-list fallback using the same local handle cannot duplicate incoming UI

## What Remains Blocked

- production foreground signaling transport
- PushKit/APNs/background incoming behavior
- media connection from invite receipt
- server-issued media credential bypass
- Element Call route replacement
- broad internal rollout
- production/public rollout

## Next Phase

Recommended next phase: `2.42B - foreground call signaling server contract`.

The next phase should define and prove the server-side foreground signaling API shape, authentication, payload expiry, duplicate handling, acknowledgement model, and redacted observability before wiring a real client transport.
