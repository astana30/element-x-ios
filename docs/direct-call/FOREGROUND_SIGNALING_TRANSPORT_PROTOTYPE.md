# Foreground Signaling Transport Prototype

## 2.42B - Foreground Signaling Transport Prototype

Status: implemented as a disabled/default transport boundary plus an in-memory test transport.

## Problem

The Element Call room-list and timeline path can deliver repeat incoming calls late. 2.41G-A diagnostics showed that the current-room observer starts, but fresh incoming candidates may already be delayed by more than 10 seconds when observed. The room-list fallback is also later and 30-second sync cycles remain visible.

2.42A added the foreground call invite contract and handler. This phase adds the smallest transport layer that can feed those safe invite signals into the handler without waiting for Matrix room-list or timeline materialization.

## Scope

This phase adds:

- `ForegroundCallSignalingTransport`
- `DisabledForegroundCallSignalingTransport`
- `InMemoryForegroundCallSignalingTransport`
- `ForegroundCallSignalingTransportEvent`
- `ForegroundCallSignalingTransportDiagnostics`
- `ForegroundCallSignalingTransportPipeline`

The implementation is foreground-only and inert by default. The in-memory transport exists for tests and simulated proof only.

## Runtime Boundary

The disabled/default transport does not emit invites.

The in-memory transport can emit a safe `ForegroundCallInviteSignal` immediately to a local subscriber. The pipeline feeds that event into `ForegroundCallInviteHandler`, which performs validation, duplicate/stale/terminal guards, and incoming/CallKit reporting through the existing local abstraction.

Invite receipt still does not:

- request media credentials
- connect media
- emit Matrix call events
- alter Element Call routing
- add PushKit/APNs/background behavior

Answer remains separate and must still pass through the foreground acceptance gate and server-issued media credential authority before media can be allowed later.

## Diagnostics

Transport diagnostics are redacted and limited to:

- started/stopped state
- delivered invite count
- latest safe event kind
- latest safe result
- real transport boolean

Diagnostics do not include raw account, room, device, event, media-session, participant, signing, credential, URL, or private runtime values.

## Server Requirements

A future production transport must be backed by a server contract that provides:

- authenticated foreground call-signaling channel
- device/session scoped subscription
- minimal opaque invite payload
- stale, timeout, and duplicate handling
- answer, decline, and end acknowledgement model
- no media credentials in invite payloads
- no raw identifiers in payloads or logs
- media credential endpoint remains final authority after answer

Future PushKit/APNs/FCM delivery can reuse the same server-side invite model later, but this phase does not implement push delivery or background incoming behavior.

## Test Coverage

Unit coverage verifies:

- disabled transport emits no invite
- in-memory transport delivers an invite immediately
- stopped in-memory transport ignores invite events
- transport pipeline reports a valid invite through the existing incoming/CallKit abstraction
- duplicate, stale, terminal, and malformed invite paths fail closed
- invite receipt does not request media credentials or connect media
- invite receipt does not emit Matrix call events
- answer still requires the foreground acceptance gate

## What Remains Blocked

- production WebSocket/SSE or equivalent transport
- server endpoint contract
- reconnect/retry/backoff behavior
- authenticated subscription binding
- push/background incoming behavior
- media connection from invite receipt
- server-issued media credential bypass
- Element Call route replacement
- broad internal rollout
- production/public rollout

## Next Phase

Recommended next phase: `2.42C - foreground signaling server endpoint contract`.

The next phase should define the server endpoint, authentication model, payload schema, expiry/duplicate/acknowledgement semantics, and redacted observability before a real client transport is wired into app runtime.
