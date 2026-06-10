# Foreground Signaling Dev Invite

## 2.42F - Supervised Dev-Only Foreground Invite Source

Status: implemented as a disabled-by-default supervised route for local and staging smoke tests.

## Scope

The dev invite route exists only to prove that an active foreground SSE subscriber can receive an opaque call invite before Matrix room-list or timeline materialization catches up.

It is not a production caller-to-callee API. It does not add PushKit, APNs, background incoming behavior, media credential issuance, Matrix event emission, media connection, Element Call route changes, or rollout activation.

## Route

The supervised route is:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite
```

The route is registered only when this explicit flag is enabled:

```text
SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1
```

With the flag unset, the route is absent and returns the framework default not-found response.

## Delivery Model

The route authenticates the active Matrix session through the existing call-service auth boundary, validates the opaque foreground invite payload, and publishes through the existing `ForegroundCallSignalingService` fanout.

To keep the request body free of raw routing values, the dev route targets only the authenticated foreground subscriber for the same active session/device. Supervised smoke can therefore inject an invite into the callee device by calling the route from that callee session while the SSE stream is open.

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

Forbidden values remain raw account, room, device, event, media-session, participant, signing, auth credential, request body, response body, credentialed URL, or private runtime values.

## Final Authority

The dev invite route does not issue media credentials, allocate media rooms, connect media, or imply call acceptance.

The server-issued media credential endpoint remains the final authority after the user answers and the app passes local foreground validation.

## Supervised Smoke Outline

1. Start the call-service with the dev invite flag enabled only in local or staging supervision.
2. Open the iOS foreground SSE stream from the callee session.
3. Submit one safe opaque dev invite from the same callee session.
4. Verify the SSE stream emits a `foreground.call.invite` event.
5. Verify the iOS app requests the foreground incoming/CallKit path.
6. Verify no media credential request or media connection occurs from invite receipt alone.

Full runtime logs must stay out of docs because they can contain private Matrix/runtime values.

## Validation

Unit coverage verifies:

- route absent when disabled;
- valid dev invite delivery to an authenticated foreground subscriber;
- stale invite drop without fanout;
- malformed invite rejection;
- route logs omit subscriber routing values;
- dev invite route does not issue media credentials.

## Next Phase

Recommended next phase: `2.42G - supervised foreground SSE smoke`.

That phase should run a local or staging smoke with one active iOS SSE subscriber, inject one supervised dev invite, and confirm foreground incoming/CallKit delivery timing without enabling PushKit/APNs/background behavior.
