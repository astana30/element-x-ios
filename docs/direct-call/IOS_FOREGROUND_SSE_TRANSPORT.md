# iOS Foreground SSE Transport

## 2.42E - iOS Foreground SSE Transport Client

Status: implemented as a disabled/configured transport boundary.

## Scope

This phase adds an iOS foreground SSE transport client for the SalemX call-service foreground signaling stream:

```text
/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream
```

The implementation is a transport boundary only. It is not wired into default runtime, does not hardcode a server URL, and does not add a production rollout gate.

## Runtime Boundary

The transport is disabled unless explicitly constructed with `isEnabled=true` and a configured stream dependency.

The default stream is a no-op disabled stream. A URLSession-backed stream exists, but it requires an injected `URLRequest`; the transport does not construct production URLs or auth headers.

## Event Handling

The SSE parser accepts:

- `foreground.ready`, ignored as a non-invite readiness marker;
- `foreground.call.invite`, decoded as the minimal opaque invite payload.

The parser rejects malformed, stale, terminal-shaped, unsupported, or unsafe payloads before emitting a transport invite event.

Valid invite events are fed into the existing `ForegroundCallSignalingTransportPipeline`, which then uses `ForegroundCallInviteHandler` and the existing duplicate, stale, active-call, reportability, and validation guards.

## Safety Guarantees

Invite receipt does not:

- request server-issued media credentials;
- connect media;
- emit Matrix call events;
- replace or modify Element Call routing;
- register APNs or VoIP values;
- add background incoming behavior.

Answer still requires the existing foreground acceptance gate, and media can only be allowed later by the server-issued media credential authority.

## Redaction

Diagnostics expose only:

- started/stopped state;
- delivered invite count;
- latest safe event kind;
- latest safe result enum;
- real transport boolean.

Descriptions redact invite handles, timestamps, display metadata, requests, and stream contents. Docs and tests avoid raw runtime logs and private identifiers.

## Tests

Unit coverage verifies:

- disabled SSE transport does not start a stream;
- ready and malformed events are ignored;
- valid invite SSE payloads reach the foreground incoming/CallKit request abstraction;
- stale and unsupported invite payloads are ignored;
- duplicate invite payloads are suppressed by the existing handler;
- invite receipt does not request media credentials, connect media, emit Matrix events, or schedule timeout behavior.

## Remaining Work

Before physical/runtime use, the app still needs:

- explicit safe configuration for the call-service SSE endpoint;
- authenticated request construction without logging credential values;
- lifecycle ownership for app foreground start/stop;
- reconnect and backoff policy;
- fallback coordination with timeline/room-list events;
- physical two-device repeat incoming smoke.

## Next Phase

Recommended next phase: `2.42F - foreground SSE runtime wiring plan`.

That phase should decide where foreground session lifecycle owns the disabled-by-default SSE transport and how runtime configuration is supplied without hardcoded URLs or credential leakage.
