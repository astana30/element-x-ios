# Native Incoming Call Contracts

Status: disabled contract surface only.

## Scope

2.40H adds inert Swift models, protocols, fail-closed state handling, local test doubles, and redacted diagnostics for future native direct-audio incoming-call work.

This phase does not implement real CallKit runtime, PushKit runtime, APNs runtime, token registration, background incoming behavior, missed-call UX, media connection, Element Call route changes, native audio gate changes, bundle ID changes, App Group changes, signing changes, server changes, video, or rollout expansion.

## Added Contract Surface

- Safe local incoming call handle model with redacted string output.
- Safe local incoming call identity model with redacted string output.
- Incoming lifecycle state enum covering idle, received, validating, reportable, reported, answered, connecting, active, ended, failed, stale, rejected, missed, and blocked states.
- Fail-closed reason enum covering malformed, stale, duplicate, unverifiable, invalid room shape, trust not ready, eligibility denied, dependency unavailable, existing active native session, logged out/session unavailable, call reporting unavailable, server-issued media credential rejection, media setup unavailable, route conflict, and unknown fallback.
- Validation context that maps unsafe local state to fail-closed reasons.
- Redacted diagnostic snapshot for lifecycle state, fail-closed reason, report attempt result, media credential request boolean, and media connect attempt boolean.
- Protocol boundaries for incoming state storage, call reporting adapter, incoming push registry, timeout scheduling, and diagnostics recording.
- Disabled lifecycle service whose default behavior is no-op/fail-closed.

## Redaction Contract

Descriptions and diagnostics expose only safe enum/boolean values and redacted placeholders. They must not expose raw room, user, peer, or device identifiers, push credentials, media credentials, event bodies, media-session names, Apple private data, or credentialed URLs.

## Runtime Boundary

No production app path instantiates real CallKit, PushKit, or APNs objects in this phase. The disabled service is not wired into `AppCoordinator`, `RoomFlowCoordinator`, Element Call routing, media setup, or native audio activation gates.

The server-issued media credential endpoint remains final authority for future media/session access.

## Tests

Unit coverage verifies default fail-closed behavior, malformed/stale/duplicate handle blocking, invalid trust/eligibility/session/dependency blocking, safe terminal diagnostics for server-issued media credential rejection, redacted call reporting test-double data, redacted incoming push registry test-double data, and absence of Element Call route action names in the contract diagnostics.
