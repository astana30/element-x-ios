# Foreground Signaling Dev Invite

## 2.42F - Supervised Dev-Only Foreground Invite Source

Status: implemented as a disabled-by-default supervised route for local and staging smoke tests.

## Scope

The dev invite route exists only to prove that an active foreground SSE subscriber can receive an opaque call invite before Matrix room-list or timeline materialization catches up.

It is not a production caller-to-callee API. It does not add PushKit, APNs, background incoming behavior, media credential issuance, Matrix event emission, media connection, Element Call route changes, or rollout activation.

## Route

The authenticated supervised route is:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite
```

The local-only supervised self-injection route is:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/inject-active
```

Both routes are registered only when this explicit flag is enabled:

```text
SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1
```

With the flag unset, the routes are absent and return the framework default not-found response.

## Delivery Model

The route authenticates the active Matrix session through the existing call-service auth boundary, validates the opaque foreground invite payload, and publishes through the existing `ForegroundCallSignalingService` fanout.

To keep the request body free of raw routing values, the dev route targets only the authenticated foreground subscriber for the same active session/device. Supervised smoke can therefore inject an invite into the callee device by calling the route from that callee session while the SSE stream is open.

The local-only self-injection route exists for supervised smoke when copying an app credential outside the app is unsafe or unreliable. It requires no Matrix auth header, accepts the same safe opaque payload, and publishes only when the server currently has exactly one active foreground SSE subscriber. If the active subscriber count is zero or greater than one, it fails closed and does not fan out an invite.

The self-injection route is guarded by the same explicit flag and by a localhost request check. It is intended to be called only on the call-service host, for example against `127.0.0.1:8091`, during the supervised smoke window.

## Accepted Payload

The accepted payload is the same opaque invite model emitted by the foreground stream:

- event type
- schema version
- safe opaque call handle
- call kind
- creation timestamp
- expiry timestamp
- safe display label

The route rejects malformed, stale, unsupported, or unsafe payloads. Expired invites are dropped by the existing fanout boundary before delivery.

## Redaction

The route does not log request bodies. Route diagnostics are limited to:

- subscriber available boolean
- delivered boolean
- dropped boolean
- call kind enum
- active subscriber count
- target subscriber count
- redacted authenticated account hash
- redacted authenticated device hash
- redacted target account hash
- redacted target device hash
- active subscriber count for local self-injection

Forbidden values remain raw account, room, device, event, media-session, participant, signing, auth credential, request body, response body, credentialed URL, or private runtime values.

The redacted hashes and counters are included only to debug supervised smoke mismatch cases where the SSE stream is connected with one active session/device but the dev invite is submitted with another active session/device or a stale bearer. They must not be used as production routing values.

## Final Authority

The dev invite route does not issue media credentials, allocate media rooms, connect media, or imply call acceptance.

The server-issued media credential endpoint remains the final authority after the user answers and the app passes local foreground validation.

## Supervised Smoke Outline

1. Start the call-service with the dev invite flag enabled only in local or staging supervision.
2. Open the iOS foreground SSE stream from the callee session.
3. Prefer submitting one safe opaque dev invite through the local-only self-injection route while exactly one foreground SSE subscriber is connected.
4. Verify the SSE stream emits a `foreground.call.invite` event.
5. Verify the iOS app requests the foreground incoming/CallKit path.
6. Verify no media credential request or media connection occurs from invite receipt alone.

Full runtime logs must stay out of docs because they can contain private Matrix/runtime values.

## 2.42I-S Physical Smoke Result

The local-only self-injection route was verified during a supervised physical iPhone smoke:

- one active foreground SSE subscriber was registered;
- the local-only route returned `active_subscriber_count=1`, `delivered=true`, and `dropped=false`;
- server diagnostics recorded `invite_enqueued=true`, `invite_yielded=true`, and `sse_event_type=foreground.call.invite`;
- iOS diagnostics recorded `invite_parse_succeeded=true`, `pipeline_delivered=true`, `invite_received=true`, `invite_valid=true`, and `incoming_requested=true`;
- the dev route was disabled after the run and the public dev route returned not found.

The smoke did not request media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, add background incoming behavior, or replace Element Call routing. Raw runtime logs remain intentionally omitted.

## Validation

Unit coverage verifies:

- route absent when disabled;
- valid dev invite delivery to an authenticated foreground subscriber;
- valid local-only self-injection delivery to exactly one active foreground subscriber;
- local-only self-injection fail-closed behavior when the active subscriber count is not exactly one;
- local-only self-injection rejection from non-local requests;
- stale invite drop without fanout;
- malformed invite rejection;
- route logs omit subscriber routing values;
- dev invite route does not issue media credentials.

## Next Phase

Recommended next phase: `2.42J - foreground SSE repeat-call validation and integration hardening`.

That phase should validate repeated foreground invite delivery and fallback de-duplication without enabling PushKit/APNs/background behavior or production SSE activation.
