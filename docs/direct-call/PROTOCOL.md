# SalemX Native Direct-Call Protocol

## Status

This document defines the cross-platform protocol target for SalemX native 1:1 direct calls. iOS and Android must use the same Matrix signalling event type, content schema, key-envelope format, backend token contract, timeout semantics, and fail-closed rules before production activation.

Production direct calls remain disabled by default in the iOS app at the time this document was written.

## Overview

Native direct calls use four cooperating pieces:

- Matrix signalling: call control events are sent in the encrypted Matrix DM room.
- LiveKit media: audio media uses a backend-allocated LiveKit room.
- Media E2EE key envelope: the per-call media key is wrapped by Matrix SDK crypto into an opaque envelope.
- Backend-issued LiveKit credentials: the app requests scoped short-lived LiveKit join credentials from a SalemX backend endpoint.

The backend issues media transport credentials only. It must not receive, derive, store, or log unencrypted media-key material.

## Protocol Version

The current native direct-call signalling version is `1`.

Any incompatible schema change must increment the version and both platforms must fail closed for unsupported versions.

## Matrix Signalling Event

- Event type: `kz.salemx.direct_call.signal`
- Event class: message-like custom Matrix event.
- Room requirement: encrypted 1:1 DM room.
- Receive path: the native direct-call receive source must include this custom message-like event type without making it visible in the normal room timeline UI.
- Content access: clients must use SDK-backed content accessors, not raw event JSON.
- Historical backlog: initial reset/backlog events must not be delivered to the call engine.
- Live baseline: only live events observed after the listener baseline is established may be delivered to the engine.
- Own events: events sent by the local user are ignored on receive.
- Duplicate events: duplicate event IDs are ignored.
- Recipient mismatch: events addressed to another user are ignored.
- Invalid metadata or content: fail closed and do not start a call.

## Signal Content Schema

The content schema below is normative for cross-platform production behavior. Field names are snake_case in Matrix event content.

```json
{
  "version": 1,
  "type": "invite",
  "call_id": "opaque-call-id",
  "room_id": "matrix-room-id-binding",
  "sender": "matrix-user-id",
  "recipient": "matrix-user-id",
  "intent": "audio",
  "created_at": "iso-8601-or-millisecond-timestamp",
  "expires_at": "iso-8601-or-millisecond-timestamp",
  "key_id": "opaque-key-id",
  "key_exchange": {
    "version": 1,
    "algorithm": "matrix_sdk_direct_call_media_key_envelope_v1",
    "envelope": "opaque-sdk-produced-envelope"
  }
}
```

### Required Common Fields

- `version`: protocol version. Current value is `1`.
- `type`: signal kind.
- `call_id`: stable opaque call identifier for the call attempt.
- `room_id`: Matrix room binding. The receiver must verify it matches the room that delivered the event.
- `sender`: Matrix user ID of the sender. The receiver must verify it matches Matrix event metadata.
- `recipient`: intended Matrix user ID recipient.
- `intent`: current production intent. Initial supported value is `audio`.
- `created_at`: sender creation time for diagnostics, expiry checks, and replay hardening.
- `expires_at`: signal/key-envelope expiry. Expired signals fail closed.
- `key_id`: opaque media-key handle ID.

### Invite

`invite` starts an outgoing call attempt and must include `key_exchange`.

The invite receiver must validate:

- room is encrypted;
- room is eligible direct 1:1;
- event sender matches `sender`;
- local user matches `recipient`;
- `call_id`, `room_id`, `sender`, `recipient`, `intent`, `key_id`, and expiry match the key-envelope metadata;
- SDK unwrap succeeds for the local device;
- unwrapped key material can be stored in the local media key store.

If any validation fails, the receiver remains idle or moves to a terminal failure state without exposing sensitive details.

### Answer

`answer` accepts an invite for the same `call_id` and indicates that the callee is ready to connect media.

Initial v1 behavior uses the invite key envelope as the media E2EE source. If a future version adds answer-side key material, it must use the same opaque envelope rules and versioning.

### Hangup

`hangup` terminates an active or ringing call. It should include a redacted terminal reason enum, not free-form user content.

Recommended terminal reasons:

- `local_hangup`
- `remote_hangup`
- `reject`
- `cancel`
- `incoming_timeout`
- `outgoing_timeout`
- `connecting_failed`
- `media_failed`
- `e2ee_failed`
- `unknown`

### Cancel, Reject, And Timeout

The iOS state machine currently models `cancel`, `reject`, and `timeout` as terminal signal kinds. Android must implement compatible terminal behavior even if product UI later chooses a smaller visible set.

- `cancel`: caller ends the outgoing ringing attempt before answer.
- `reject`: callee declines the incoming call.
- `timeout`: ringing or connecting timeout occurred.

All terminal events must be scoped to `call_id` and must be ignored if they do not match the active session.

## Key Envelope

The key envelope is SDK-produced opaque data suitable for inclusion in the Matrix signal. It is not a LiveKit credential and not media-key plaintext.

Envelope requirements:

- The envelope must be produced by the Matrix SDK direct-call media-key envelope API or a cross-platform equivalent with the same cryptographic semantics.
- The event content must not contain unwrapped media-key material.
- The event content must not contain LiveKit join credentials.
- The event content must not contain a LiveKit server URL.
- The event content must not contain backend service secrets.
- The envelope must bind to `call_id`, `room_id`, sender, recipient, `intent`, `key_id`, and expiry.
- The receiver must fail closed if any bound metadata differs from the expected Matrix event and room context.
- The receiver must fail closed if the local device is not an intended recipient.
- Device trust policy must be explicit. The safest production default is fail-closed for unknown or unverifiable peer devices.

## Backend Token Endpoint

Preferred endpoint:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/livekit/token
```

Authentication:

- Matrix bearer authentication from the logged-in client session.
- The app must not contain a LiveKit API secret.

Backend validation:

- Authenticated user is joined to the room.
- Peer user is joined to the same room.
- Room has exactly two joined members for the direct-call eligibility check.
- Room is encrypted.
- Requested peer is the only other joined member.
- `intent` is supported. Initial supported value is `audio`.

Backend allocation:

- LiveKit room allocation is keyed by `room_id + call_id + intent`.
- Caller and callee independently obtain credentials for the same allocation.
- LiveKit room names must be opaque. Do not use the Matrix room ID as the LiveKit room name.
- Credentials are scoped to one LiveKit room and short-lived.
- Backend logs must not include Matrix bearer credentials, LiveKit join credentials, LiveKit API secrets, Matrix event bodies, or media-key material.

The backend must never receive media E2EE key material. E2EE key exchange is handled by Matrix signalling and the SDK key envelope.

## LiveKit Media Rules

- LiveKit is the media transport for v1 native audio calls.
- The app requests a backend-issued credential after the call flow reaches the media-connect stage.
- The LiveKit credential is never sent through Matrix signalling.
- The LiveKit server URL is never sent through Matrix signalling.
- The LiveKit API secret is never present in the app.
- The LiveKit E2EE context is built from the unwrapped Matrix key-envelope result stored in the platform media key store.
- Microphone capture must not be published before explicit user action.
- A diagnostic or pre-UI connect proof may connect with microphone publishing disabled and without remote audio expectations.

## State Machine

Both platforms should use equivalent user-visible and diagnostic phases:

- `idle`: no active call session.
- `outgoingRinging`: local user sent invite and is waiting for answer or terminal event.
- `incomingRinging`: local user received a valid live invite and can accept or reject.
- `connecting`: signalling accepted and media connection is being established.
- `active`: media connection is established for the call intent.
- `failed` or terminal: call ended, was cancelled, timed out, or failed closed.

Current iOS defaults:

- Incoming ringing timeout: 45 seconds.
- Outgoing ringing timeout: 45 seconds.
- Connecting timeout: 20 seconds.
- Cleanup delay: 2 seconds.

Android should match these semantics unless a future protocol version changes them for both platforms.

## Cross-Platform Compatibility Rules

- iOS and Android must use `kz.salemx.direct_call.signal`.
- iOS and Android must use the same signal schema version.
- iOS and Android must use the same key-envelope version and metadata binding.
- iOS and Android must use the same backend token endpoint contract.
- iOS and Android must use the same timeout and terminal reason semantics.
- iOS and Android must ignore historical backlog and deliver only live post-baseline events to the call engine.
- iOS and Android must fail closed for unsupported versions, unsupported intents, missing key envelope, metadata mismatch, room ineligibility, token failure, key unwrap failure, and media setup failure.
- Diagnostics may expose booleans and enums, but not credentials, event bodies, or media-key material.

## Non-Goals For This Protocol

- No visible UI contract.
- No Element Call route reuse.
- No CallKit or push contract.
- No group calling.
- No video until a future protocol version defines it.
- No plaintext media fallback.
