# Native Audio CallKit / PushKit / APNs Design Plan

Status: design only. No CallKit, PushKit, APNs runtime, native audio gating, Element Call routing, LiveKit, MatrixRTC, bundle ID, App Group, signing, or production rollout change is made by this plan.

## Baseline

- 2.40F physical-device signing proof is complete.
- The signed main app has `aps-environment=development`.
- The app, NSE, and ShareExtension use App Group `group.kz.salemx.msg.dev`.
- Keychain access groups are present in signed app and extension entitlements.
- Native direct audio remains foreground/open encrypted direct 1:1 only.
- CallKit, PushKit, APNs runtime, background incoming, missed-call UX, video, and production/public rollout have not started.
- Element Call remains a separate fallback route and must not be replaced by native direct audio.

## Apple Compliance Assumptions

- PushKit VoIP pushes are only for real incoming calls.
- VoIP push handling must report valid incoming calls to CallKit quickly.
- Regular chat/message notifications must not use PushKit.
- CallKit provides the system call UI and user actions for answer, end, mute, and audio session coordination.
- Native direct audio must fail closed rather than showing a system incoming call for ambiguous, stale, invalid, or unverifiable call state.

## Proposed Incoming Call Flow

1. A native direct-call invitation is created through the approved signalling path.
2. The server validates the call is eligible to notify, using only server-side checks appropriate for push fanout.
3. The server sends a VoIP push with a minimal opaque call handle.
4. The app receives the VoIP push.
5. The app creates a local call identity that is not a raw room, user, peer, device, token, or media-session identifier.
6. The app validates or fetches enough local state to classify the incoming call as native direct audio.
7. The app validates encrypted direct 1:1 shape, trusted peer/device readiness, rollout/eligibility gates, dependency readiness, and no stale active session.
8. Only after the safe validation boundary passes, the app reports the incoming call to CallKit.
9. When the user answers, the app asks the final authority token endpoint for the media/session credential.
10. The native audio engine connects only after token success and E2EE/media readiness.
11. The call becomes active.
12. End, reject, miss, timeout, stale, or local failure states propagate terminal state safely and clear local active session state.

The push payload is never final authority. The token endpoint remains final authority for media/session access.

## Proposed Outgoing Call Flow

1. The user starts a native 1:1 audio call from the foreground app and approved native audio card.
2. The app validates local room, trust, rollout, eligibility, dependency, and idle-session gates.
3. The app creates a CallKit outgoing transaction for the native direct audio call.
4. The app requests the media/session credential from the final authority token endpoint.
5. The native audio engine connects only after token success and E2EE/media readiness.
6. The call becomes active.
7. End, cancel, timeout, or local failure states end the CallKit call and clear local active session state.

Element Call routing, toolbar actions, and fallback behavior remain untouched.

## Token And Device Model

- The app should manage a normal APNs token for regular notification flows.
- The app should manage a separate PushKit VoIP token for native incoming-call notification only.
- Tokens must be registered through a secure server registration client.
- Token registration logs and reports must be redacted.
- Token rotation must update server registration and invalidate stale registration safely.
- Logout, device removal, session reset, or account switch must remove or invalidate relevant push registrations.
- Push and VoIP tokens must never be printed in logs, reports, diagnostics, screenshots, or docs.
- Device labels in reports stay label-only; raw device identifiers stay forbidden.

## Server Requirements

- APNs provider authentication/key/certificate ownership must be assigned and operationally controlled.
- A native VoIP push endpoint is required for real incoming native direct audio calls.
- A normal APNs endpoint may be required for non-VoIP notification classes; those notifications must not use PushKit.
- Server-side push fanout must create only minimal opaque call handles.
- The server must support stale call invalidation.
- The server must validate membership and notification eligibility before push fanout where it can do so safely.
- The backend must not centralize E2EE trust decisions that belong on-device.
- Push delivery and payload content are not final authority for media access.
- Token issuance remains gated by the final authority token endpoint after accept and client validation.
- Server logs must remain redacted and must not contain raw identifiers, media credentials, event bodies, credentialed URLs, or media-session names.

## Client Components To Design Later

- PushRegistry manager for VoIP token registration and lifecycle.
- CallKit provider/coordinator protocol with mocks.
- Incoming native call state store.
- Call timeout and stale-call manager.
- Native audio bridge between CallKit actions and the existing direct-call engine.
- Secure token registration client.
- Redacted logging and diagnostic layer for call lifecycle events.
- Background-safe validation boundary for incoming call classification.
- Test doubles for push receipt, CallKit report/answer/end, timeout, stale calls, and fail-closed terminal delivery.

## Risk Register

- Apple rejection risk if PushKit is used for anything other than real incoming calls.
- Missing the CallKit report deadline after a VoIP push.
- Stale, duplicate, delayed, or replayed pushes.
- APNs or VoIP token desynchronization after rotation, reinstall, logout, or account switch.
- User logged out, app locked, or session unavailable when push arrives.
- Encrypted room/call membership race between push delivery and local validation.
- App killed or backgrounded with insufficient safe state to classify the call.
- Privacy or log leakage from payloads, diagnostics, or incident reports.
- Conflict with Element Call route, toolbar, notification handling, or existing call surfaces.
- Terminal delivery ambiguity if local setup fails after the peer may have entered active audio.
- Split state or stale active session after timeout, decline, app relaunch, or media setup failure.

## Privacy And Redaction Contract

Allowed diagnostics:

- safe booleans
- safe enum reasons
- HTTP status classes or safe status values
- activation source/decision/reason
- token issued true/false
- media failure safe enum
- CallKit report/answer/end pass/fail booleans
- cleanup/disconnect attempted booleans

Forbidden in logs, docs, payload reports, and user-visible output:

- raw room, user, peer, or device identifiers
- push, VoIP, APNs, media, or session credentials
- media keys
- Matrix event bodies
- credentialed URLs
- provisioning private data
- Apple private keys or certificates
- LiveKit media-session names
- full request or response bodies

CallKit display metadata must be safe and follow the app's user-visible display-name policy without exposing internal identifiers.

## Fail-Closed Matrix

The app must not report or must immediately end the native CallKit call when any required validation or setup boundary fails:

- malformed, expired, stale, duplicate, or replayed push
- missing or ambiguous opaque call handle
- cannot fetch, decrypt, or classify call state safely
- room is not encrypted direct 1:1
- peer/device trust is not ready
- account, peer, or device is not eligible
- rollout or local feature gate disabled
- dependency readiness unavailable
- existing active native session
- user logged out or app session unavailable
- app locked with no safe session state
- CallKit report failure
- user declines, cancels, or times out
- token endpoint rejection
- media setup failure
- terminal delivery ambiguous
- Element Call conflict or route ambiguity

## Recommended Implementation Phases

### 2.40H — Native Incoming Lifecycle Contracts And Mocks

- Add disabled protocols and models only.
- Define CallKit adapter protocol, PushKit registry protocol, incoming call state store protocol, and redacted diagnostics types.
- Add tests for fail-closed state mapping.
- No runtime registration, no system UI, no push handling.

### 2.40I — Push And CallKit Payload Contract

- Define server/client opaque payload contract.
- Define token registration contract and logout/removal behavior.
- Define redacted observability schema.
- Add backend/client tests around payload shape and redaction.
- No APNs or PushKit runtime send/receive yet.

### 2.40J — Device-Only Synthetic CallKit Proof

- On a physical device, report a synthetic validated native incoming call to CallKit from a test harness.
- Prove answer/end/mute callbacks are mapped to disabled test doubles.
- No PushKit/APNs receipt and no media connection.

### 2.40K — PushKit Registration Dry Run

- Register for VoIP token on physical device.
- Register token with a safe staging endpoint.
- Prove token rotation/logout removal behavior with redacted logs.
- Do not send production pushes.

### 2.40L — APNs/PushKit Delivery Dry Run

- Deliver a safe staging VoIP push for a synthetic native call handle.
- Classify and fail closed or report to CallKit only after validation.
- No broad rollout and no production/public use.

### 2.40M — Supervised Device E2E Incoming Proof

- One supervised staging device proof: push -> validate -> CallKit -> answer -> token endpoint -> native audio active -> hangup.
- Named participants/devices only.
- Redacted reporting only.
- Element Call fallback remains visible and unchanged.

Later phases must cover missed, decline, cancel, timeout, app killed, app backgrounded, logout, stale push, duplicate push, and network failure matrices before any expansion.

## Non-Goals For 2.40G

- No CallKit runtime implementation.
- No PushKit runtime implementation.
- No APNs runtime implementation.
- No video.
- No production rollout.
- No public TestFlight rollout.
- No broad internal rollout.
- No replacement of Element Call route.
- No changes to token endpoint authority.
- No changes to bundle IDs, App Group IDs, signing, provisioning, LiveKit, MatrixRTC, native audio engine, or native audio gating.

## 2.40G Acceptance Criteria

- This design doc exists.
- The 2.40F physical-device signing proof is summarized.
- Future code phases are listed.
- Security, privacy, compliance, and fail-closed gates are listed.
- No Swift runtime call code changed.
- No CallKit, PushKit, APNs, LiveKit, MatrixRTC, Element Call route, native audio gating, bundle ID, App Group, signing, or provisioning setting changed.
- No secrets, raw identifiers, push tokens, VoIP tokens, APNs tokens, media credentials, event bodies, media-session names, certificates, private keys, or provisioning private data are included.
