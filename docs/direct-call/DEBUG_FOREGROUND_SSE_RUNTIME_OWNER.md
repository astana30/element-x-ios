# DEBUG Foreground SSE Runtime Owner

## 2.42H - DEBUG/dev Foreground SSE Runtime Owner

Status: implemented as a DEBUG-only runtime owner for supervised tests.

## Scope

2.42H adds a small DEBUG-only owner that can start and stop an injected foreground signaling transport during supervised foreground testing.

The owner is not wired into production app lifecycle. It does not construct URLs, auth headers, or credentials. It receives already-configured dependencies and stays disabled unless explicitly created with `isEnabled=true`.

## Runtime Owner

The owner is:

```text
DebugForegroundCallSignalingSSERuntimeOwner
```

It is compiled only in DEBUG builds and owns:

- configured/not-configured state
- authenticated session availability gate
- foreground start
- foreground stop
- single-shot transport lifecycle
- local fallback de-duplication by safe local call handle
- redacted diagnostics

The owner can be backed by the existing `ForegroundCallSignalingSSETransport` for physical smoke or by an in-memory transport in tests.

## Configuration Boundary

The owner requires injected dependencies:

- `ForegroundCallSignalingTransport`
- `ForegroundCallInviteHandler`
- optional validation context provider

For physical smoke, the transport may use `URLSessionForegroundCallSignalingSSEStream`, but request construction remains outside this owner and must supply an injected `URLRequest`.

This phase does not add hardcoded server URLs, auth header construction, credential storage, or app lifecycle installation.

## Redacted Diagnostics

The owner exposes only safe booleans:

- `sse_configured`
- `sse_started`
- `sse_connected`
- `invite_received`
- `invite_valid`
- `incoming_requested`
- `fallback_deduped`
- `transport_stopped`

Descriptions redact runtime values and state that the owner is DEBUG-only, has no hardcoded endpoint, and has no media-connect runtime.

## Invite Handling

When enabled and authenticated session state is available:

1. The owner starts the injected transport.
2. Valid invite events are passed into `ForegroundCallInviteHandler`.
3. The existing duplicate, stale, terminal, active-session, validation, and reporting guards remain authoritative.
4. A successfully reported invite records the safe local handle for fallback de-duplication.
5. A later timeline/room-list fallback with the same safe local handle is suppressed as duplicate.

Malformed, stale, terminal, duplicate, unsupported, or unverifiable invites fail closed through the existing handler and diagnostics.

## Safety Guarantees

Invite receipt does not:

- request server-issued media credentials;
- connect media;
- emit Matrix call events;
- register APNs or VoIP values;
- add background incoming behavior;
- replace Element Call routing.

The answer-time foreground authority gate remains the only path that may allow media later.

## Tests

Unit coverage verifies:

- disabled owner does not start transport;
- authenticated session availability is required before start;
- configured owner starts and stops the injected transport;
- valid SSE invite reaches foreground incoming reporting;
- stale, terminal, and duplicate invites fail closed;
- fallback after SSE delivery is de-duplicated;
- diagnostics remain redacted;
- invite receipt does not request media credentials, connect media, emit Matrix events, or alter Element Call routing.

## Remaining Work

Before a physical-device smoke can run through the app, a supervised harness still needs to provide:

- safe injected request construction;
- explicit start/stop trigger;
- redacted runtime log collection;
- local/staging server configuration;
- supervised dev invite injection.

## Next Phase

Recommended next phase: `2.42I - supervised foreground SSE physical smoke`.

That phase should use the DEBUG owner with an injected local/staging stream request, keep the dev invite route disabled outside the supervised window, and record only redacted timing/diagnostic results.
