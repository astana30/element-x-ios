# Foreground Signaling Endpoint

## 2.42D - SalemX Call-Service Foreground Signaling Endpoint

Status: implemented as a foreground-only SSE subscription prototype with an internal invite fanout boundary.

## Scope

This phase adds the smallest server-side surface needed by the iOS foreground signaling transport work:

- authenticated foreground stream subscription;
- opaque invite payload model;
- in-memory active subscriber registry;
- internal invite fanout API for future validated server call sources;
- redacted delivery diagnostics;
- tests for validation, delivery, authentication, and redaction.

This phase does not add PushKit, APNs, background incoming behavior, media credential issuance from invite receipt, Matrix event emission from invite receipt, production rollout, or Element Call route changes.

## Endpoint

The prototype stream endpoint is:

```text
GET /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream
```

The route authenticates the active Matrix session through the existing call-service auth validator and returns `text/event-stream`.

The initial event is a readiness marker:

```text
event: foreground.ready
data: {"ready":true}
```

Invite events use:

```text
event: foreground.call.invite
```

The endpoint is foreground-only. It does not wake a background app and does not replace future PushKit/APNs design.

## Invite Payload

The emitted invite payload is minimal and opaque:

- schema version;
- safe local call handle;
- call kind;
- creation timestamp;
- expiry timestamp;
- safe display label.

The invite payload does not contain media credentials, Matrix event content, credentialed URLs, media-session names, or raw routing identifiers.

## Internal Fanout Boundary

`ForegroundCallSignalingService` owns active foreground subscriptions and exposes an internal `publish_invite` API.

The current implementation intentionally does not expose a public HTTP publish endpoint. A future server source must validate call membership, eligibility, freshness, and target delivery before calling the internal fanout API.

If no active foreground subscriber exists, the service returns a redacted unavailable result. It does not fall back to background delivery.

Expired invites are dropped before fanout and reported only as a safe stale result.

## Redaction

Allowed server diagnostics are:

- subscriber count;
- delivered invite count;
- dropped invite count;
- latest safe result enum;
- subscriber available boolean;
- delivered boolean;
- dropped boolean;
- call kind enum.

Forbidden diagnostics remain raw account, room, device, event, media-session, participant, signing, auth credential, request body, response body, or credentialed URL values.

## Final Authority

Foreground invite receipt is not media authorization. The server-issued media credential endpoint remains the final authority after a user answers and the app passes local foreground validation.

The stream endpoint does not issue media credentials, allocate media rooms, pre-create media rooms, connect media, or imply call acceptance.

## Remaining Server Work

Before production use, the call-service still needs:

- validated server-side call invite source;
- stale invalidation event;
- received/displayed/answered/declined/ended acknowledgement model;
- reconnect and resume semantics;
- rate limiting for subscription churn and fanout;
- multi-worker/shared subscriber store or broker;
- operational dashboards with redacted counters only;
- deployment configuration for the iOS server-backed foreground transport.

## Validation

Unit coverage verifies:

- safe opaque payload validation;
- malformed, unsupported, and expired-shape payload rejection;
- stale invite drop before fanout;
- delivery to an active foreground subscriber;
- SSE event output excludes routing-only subscriber values;
- stream route rejects unauthenticated subscription;
- stream route subscribes, emits the ready event, and unsubscribes on disconnect.

## Next Phase

Recommended next phase: `2.42E - iOS foreground signaling SSE transport integration`.

The next phase should wire the iOS transport to this endpoint behind explicit disabled-by-default configuration, keep invite receipt side-effect-free, and prove that media credentials and media connection remain blocked until answer-time foreground authority approval.
