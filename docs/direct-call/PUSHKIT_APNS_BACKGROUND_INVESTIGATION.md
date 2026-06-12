# PushKit/APNs Background Incoming-Call Investigation

Status: 2.43C intake seam added; production PushKit/APNs/background behavior remains unimplemented.

This document records what is currently present in tracked Element X / SalemX code and what would be needed to move from the validated foreground real-invite baseline to background incoming-call support. It does not implement PushKit/APNs production behavior.

## Baseline

The validated foreground real-invite token-guard baseline was consolidated in 2.42O. The 2.42M physical two-device foreground real-invite smoke passed at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`, and 2.42N guarded the DEBUG smoke tooling release surface at `26e520b6f6ec0220ce118051f5acac36ed40bfba`.

Foreground real invite behavior must remain unchanged while PushKit/APNs/background incoming-call work is scoped separately. The M1-M4 smoke controls and bridges are local DEBUG tooling only and are not production call behavior.

## 2.43B Payload Contract Seam

2.43B adds only a safe background invite payload contract/parser seam for future native direct-call PushKit/APNs work. It does not register PushKit, request a VoIP token, register APNs, change entitlements, change provisioning, touch project files, report CallKit automatically, request media credentials, connect media, emit Matrix events, or change production call behavior.

The parser accepts a minimal dictionary-shaped payload with:

- `type`
- `version`
- `call_handle`
- `call_kind`
- `created_at_ms`
- `expires_at_ms`
- `display_label`

The parser returns either a redacted valid payload value or a redacted failure class. Timestamp validation matches the foreground invite guardrail: current invites and small future clock skew are accepted, expired invites are rejected, excessive future timestamps are rejected, and malformed timestamp ordering is rejected.

Allowed diagnostic classes are limited to:

```text
valid
missing_required_field
invalid_type
invalid_timestamp
expired
future_timestamp_excessive
unsupported_version
malformed_payload
redacted
```

The parser must not include raw access tokens, authorization headers, Matrix user IDs, device IDs, room IDs, call handles, request payloads, private logs, or secret-bearing URLs in descriptions, diagnostics, docs, or tests.

## 2.43C Background Invite Intake Seam

2.43C adds only a safe intake seam that consumes the 2.43B parser result and returns a redacted internal decision for future native direct-call background incoming-call handling. It does not register PushKit, request a VoIP token, register APNs, change entitlements, change provisioning, touch project files, report CallKit, request media credentials, connect media, emit Matrix events, persist payload data, or change production call behavior.

The intake seam can classify parsed payload outcomes as:

- `ignore_invalid_payload`
- `ignore_expired_payload`
- `ignore_future_timestamp_excessive`
- `requires_authenticated_session`
- `prepare_foreground_equivalent_incoming`
- `requires_callkit_report_later`

Diagnostics are limited to redacted booleans/status classes:

```text
intake_invoked=true/false
payload_parse_status=valid/<redacted_failure_class>
intake_decision=<redacted_decision_class>
callkit_report_requested=false
media_credentials_requested=false
media_connect_requested=false
matrix_event_emit_requested=false
blocked_reason=<redacted_class>
```

The intake seam deliberately models what a later background owner should do without doing it. No CallKit report occurs in 2.43C; a future 2.43D may design or implement a CallKit reporting adapter seam for background invite decisions, still without PushKit registration unless that is explicitly allowed. Any future PushKit/APNs registration, entitlement, signing, provisioning, project, `Info.plist`, or `app.yml` change requires a separate explicit task.

## Current State From Tracked Code

### Existing PushKit Surface

Tracked code already contains PushKit registration and VoIP push handling in the existing Element Call service path, not in the SalemX native direct-call foreground real-invite path.

`ElementCallService` owns a `PKPushRegistry`, sets `.voIP` as the desired push type, stores the current VoIP push token in memory, and registers a Matrix pusher through the existing notification gateway settings. Its VoIP push delegate extracts an Element Call payload, reports an incoming CallKit call, and coordinates with the Element Call session path.

The notification service extension also has an Element Call handoff path for RTC notification payloads. That path can ask CallKit to surface a VoIP push payload for the main app to continue processing.

These existing paths are important references, but they are not a ready SalemX native direct-call background implementation. They include Element Call-specific payloads, routing, and lifecycle assumptions.

### Existing Normal APNs Surface

Normal APNs registration already exists for notifications. `AppDelegate` receives the normal device token callback, `AppCoordinator` forwards it, and `NotificationManager` registers a Matrix APNs pusher using the app notification settings.

This is separate from a future direct-call VoIP push registration contract.

### Tracked Capability Assumptions

Tracked app files already contain APNs/background assumptions:

- `ElementX/SupportingFiles/ElementX.entitlements` includes `aps-environment` for development plus app group, network client, and keychain access groups.
- `ElementX/SupportingFiles/Info.plist` and tracked target configuration include `UIBackgroundModes` entries including `voip`.
- `NSE/SupportingFiles/NSE.entitlements` contains extension app group/keychain access configuration.

No signing, provisioning, project, `Info.plist`, `app.yml`, or entitlement file is changed by this investigation. Any future capability or provisioning change needs a separate explicit task.

### Existing Native Direct-Call Surface

The native direct-call code has an inert push-registration seam through `NativeIncomingPushRegistryManaging` and `NativeIncomingPushRegistrationCredential`. The credential type is redacted in descriptions and tests cover that redaction.

The current SalemX native foreground real-invite path is foreground-only. It uses the authenticated non-dev foreground signaling route and the existing native foreground incoming/CallKit reporting abstraction. It does not register a native direct-call PushKit registry and does not process native direct-call VoIP push payloads.

The synthetic/native CallKit proof adapter can report an incoming call through CallKit and can be a useful implementation reference, but a production background path would need a separate background-safe owner, PushKit completion handling, session restoration, duplicate handling, CallKit action routing, and fail-closed lifecycle decisions.

## Investigation Questions

1. Does the fork currently contain any PushKit registration code?

Yes. Existing PushKit registration lives in the Element Call service path. It creates a `PKPushRegistry`, requests `.voIP`, receives VoIP token updates, and registers a Matrix pusher for Element Call. There is no separate production SalemX native direct-call PushKit registry implementation.

2. Does the fork currently contain any VoIP push handling code?

Yes, for Element Call. The main app handles `PKPushPayload` through the Element Call service, and the notification service extension has an Element Call RTC notification handoff path. Native direct-call background VoIP push handling is not implemented.

3. Does the fork currently contain APNs token registration for normal notifications?

Yes. Normal APNs token registration flows through `AppDelegate`, `AppCoordinator`, and `NotificationManager`, which registers an APNs Matrix pusher with existing notification settings.

4. Does the current app target have any tracked PushKit/VoIP entitlement files?

Tracked app configuration already includes APNs and background-mode assumptions, including development APNs entitlement and `voip` background mode entries. There is no new entitlement or provisioning change in this investigation. Actual Apple Developer capabilities and profiles still need deliberate verification before production background direct-call work.

5. Does current CallKit code support reporting incoming calls when app is foreground only, or can it be reused for background?

The native direct-call proof path can report incoming calls through CallKit in the foreground smoke context. Existing Element Call code has its own background VoIP-to-CallKit path. A future native direct-call background path can reuse concepts and some abstractions, but it must not simply treat the DEBUG smoke proof or Element Call route as production native direct-call behavior.

6. What would be required to safely map a VoIP push payload to the existing foreground invite pipeline?

A future design needs a minimal payload contract, auth/session restoration, target-device validation, duplicate and expiry handling, redacted diagnostics, and a bridge into the existing native incoming-call pipeline. It must coordinate with foreground SSE delivery so the same invite is not reported twice. It also needs a clear CallKit ownership model and completion handling that fits PushKit timing requirements.

7. What must not happen inside a PushKit callback?

The callback must not request media credentials, connect media, emit Matrix call events from invite receipt, use dev routes, expose raw payloads or identifiers, perform unbounded work before completion, or make foreground smoke tooling part of production behavior. It should wake/report an incoming call and hand off to a safe, fail-closed call pipeline.

8. Where should token registration live?

Native direct-call VoIP registration should live in a production app/session service boundary, not in DEBUG smoke helpers. It should be injected and testable, probably near notification/session coordination or a dedicated native direct-call push service, with clear separation from Element Call routing.

9. What server-side support is required to send VoIP pushes?

The server side needs a production VoIP push provider configuration, a minimal redacted payload contract, device/session targeting, expiry/priority policy, delivery observability, and compatibility with Apple APNs requirements. Real non-dev routes must remain auth-gated and dev routes must remain disabled.

10. What additional Apple Developer / provisioning capability risks exist?

PushKit/APNs work can fail if bundle identifiers, APNs environment, VoIP push capability, background modes, certificates/keys, or provisioning profiles do not match. App Store policy also expects VoIP pushes to promptly report incoming calls through CallKit. Any signing or entitlement change must be separately approved and reviewed.

11. Which work can be done without touching signing/project files?

Docs, server contract design, redacted payload models, protocol seams, unit tests around parsing/redaction, and disabled-by-default abstractions can be prepared without signing/project edits. These should remain fail-closed and must not register live PushKit production behavior.

12. Which work is blocked until entitlements/profiles are deliberately changed?

Any production native direct-call VoIP registration proof, APNs provider setup tied to app capabilities, provisioning-profile validation, physical background delivery smoke, or target/project capability update is blocked until a separate signing/provisioning task explicitly allows those changes.

## Required Future Guardrails

- 2.42O remains the foreground real-invite baseline.
- PushKit/APNs/background incoming is not implemented yet for SalemX native direct-call.
- 2.43B adds only the background invite payload contract/parser seam.
- 2.43C adds only the background invite intake seam.
- PushKit registration and APNs registration are still not implemented for native direct-call.
- Foreground real-invite behavior must remain unchanged.
- PushKit/APNs work must be separately scoped from foreground smoke tooling.
- Entitlements, provisioning, project settings, `Info.plist`, and `app.yml` are not changed by this investigation.
- Future entitlement or signing changes require a separate explicit task.
- No media credentials or media connection should be introduced during PushKit receipt.
- PushKit should only wake/report incoming call and coordinate safely with the call pipeline.
- No CallKit reporting is performed by the 2.43C intake seam.
- Dev routes must remain disabled.
- Real non-dev routes must remain auth-gated.
- DEBUG smoke tooling is not production behavior.
- A future 2.43D may design or implement a CallKit reporting adapter seam for background invite decisions, still without PushKit registration unless explicitly allowed.
- Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
