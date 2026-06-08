# Push And CallKit Payload Contract

Status: design and validation contract only. No PushKit, APNs, CallKit runtime, push credential registration, system incoming UI, media connection, Element Call routing, native audio gating, signing, project setting, or rollout behavior is changed by this document.

## Scope

This contract defines the future payload classes, validation boundaries, display metadata rules, redacted diagnostics, and fail-closed outcomes for native direct-audio incoming-call work.

This phase does not implement real PushKit or APNs receipt, real CallKit reporting, background incoming behavior, missed-call UX, server fanout, media credential requests, media setup, video, production rollout, public rollout, or Element Call replacement.

The server-issued media credential endpoint remains final authority after a user answers a validated call.

## Payload Classes

### VoIP Incoming Native Direct-Audio Invite

Future VoIP incoming payload for a real native direct-audio call invitation. It is only a wake and classification hint. It must be minimal, opaque, and insufficient to connect media by itself.

### Normal APNs Notification

If normal notification support is needed later, it must remain separate from VoIP incoming-call handling. Regular chat or message notifications must not use the VoIP path.

### Server Acknowledgement Or Invalidation

Future server-side acknowledgement or invalidation messages may mark a previously delivered call handle as stale, expired, cancelled, or no longer reportable. They must be opaque and redacted.

### Local CallKit Display Metadata

Future local display metadata maps a validated native incoming call to safe user-facing labels. It must not carry internal identifiers or media/session names.

### Terminal Or Stale Call Handling

Terminal state handling must end local incoming-call state safely when a call is stale, rejected, missed, invalidated, failed, or already handled elsewhere.

## VoIP Incoming Payload Fields

Allowed abstract fields:

- schema version
- opaque local call handle
- call kind, limited to native direct audio
- creation timestamp
- expiry timestamp
- safe display label reference
- validation hint enum
- optional stale/invalidation class

Forbidden fields:

- raw room, user, peer, or device identifiers
- push credential values
- media credentials
- media-session names
- Matrix event bodies
- media keys
- full request or response bodies
- credentialed URLs

Sender, device, and room information must be represented only as opaque hints or local lookup references. The payload must never include raw identifiers for those entities.

## Client Validation Contract

The client must reject payloads before reportability when any of these checks fail:

- malformed schema
- unsupported schema version
- missing or invalid opaque local call handle
- stale or expired timestamps
- duplicate local call handle
- unsupported call kind
- missing safe display label reference
- unavailable local account or app session state
- unavailable dependency state

After the initial payload shape passes, the client must classify the call only through local trusted state:

- encrypted direct 1:1 room validation
- peer/device trust readiness
- rollout and eligibility readiness
- no existing active native session
- no Element Call route conflict

The push payload is never final authority. It may only move a future disabled or background-aware service toward a reportable state after local validation. The server-issued media credential endpoint remains final authority after user answer.

No media credential request may happen on payload receipt. No media connection may happen on payload receipt.

## Server Contract

The server side must:

- validate notification eligibility before fanout where safely possible
- send only minimal opaque payloads
- avoid raw identifiers in payloads
- avoid media credentials in payloads
- support stale call invalidation
- support credential registration state without logging raw credential values
- keep push delivery separate from media credential issuance
- keep server logs and operator reports redacted

The server must not centralize on-device trust decisions. Local encrypted-room and trusted-device validation remain client-side boundaries.

## CallKit Display Metadata Contract

Future CallKit display metadata may include only:

- app-approved display name
- safe participant label
- generic fallback label
- call kind label

It must not include:

- raw room, user, peer, or device identifiers
- opaque payload handles
- media/session names
- internal routing names
- credential values
- request or response details

When display metadata is uncertain, the client must use a generic safe fallback label or fail closed before reporting.

## Redaction And Logging Contract

Allowed diagnostics:

- booleans
- safe enums
- status classes
- duration buckets
- redacted local handle labels
- report attempted true/false
- report succeeded true/false
- invalidation received true/false

Forbidden diagnostics:

- raw identifiers
- credential values
- push credential values
- Matrix event bodies
- media-session names
- full request or response bodies
- credentialed URLs
- provisioning private data

Descriptions, debug output, tests, docs, and incident reports must use safe enum names and redacted placeholders only.

## Failure Matrix

The client must fail closed for:

- malformed payload
- expired payload
- duplicate handle
- unsupported call kind
- unavailable local session
- not encrypted direct 1:1
- trust not ready
- eligibility denied
- dependency unavailable
- existing active native session
- call reporting unavailable
- server-issued media credential rejected
- stale invalidation received
- route conflict
- unknown fallback

Fail-closed behavior means no system incoming UI when validation has not crossed the safe reporting boundary, no media credential request before answer, no media connection, safe terminal diagnostics, and cleared local state when appropriate.

## Test Plan

Future payload contract tests should prove:

- parser accepts only the minimal safe schema
- malformed schema is rejected
- stale and expired payloads are rejected
- duplicate handles are rejected
- unsupported call kinds are rejected
- raw-looking identifiers are rejected
- credential-looking values are rejected
- logs and descriptions remain redacted
- CallKit display metadata remains safe
- no media credential request occurs before user answer
- no media connection occurs from payload receipt
- Element Call route remains untouched

Fixtures must use clearly fake safe labels and must not contain realistic credential shapes, raw identifiers, Matrix event bodies, media-session names, or credentialed URLs.

## Future Phases

- `2.40J — device-only synthetic CallKit proof`
- `2.40K — PushKit registration dry run`
- `2.40L — APNs/PushKit delivery dry run`
- `2.40M — supervised device E2E incoming proof`

Each future phase must keep Element Call separate, preserve token endpoint final authority, maintain redacted reporting, and require explicit approval before execution.
