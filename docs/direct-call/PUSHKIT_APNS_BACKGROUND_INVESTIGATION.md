# PushKit/APNs Background Incoming-Call Investigation

Status: 2.43W confirms port 71 is reachable after fail2ban unban, but staging deploy is blocked by SSH authentication while production PushKit/APNs/background behavior remains disabled by default and unwired.

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

## 2.43D Background CallKit Report Request Seam

2.43D adds only a safe planner that maps a valid 2.43C background invite intake decision to a redacted internal CallKit report request model. It does not register PushKit, request a VoIP token, register APNs, change entitlements, change provisioning, touch project files, call a real CallKit provider, report from a PushKit callback, request media credentials, connect media, emit Matrix events, persist payload data, or change production call behavior.

The planner can classify outcomes as:

- `not_reportable_invalid_payload`
- `not_reportable_expired_payload`
- `not_reportable_future_timestamp_excessive`
- `not_reportable_requires_authenticated_session`
- `reportable_incoming_call_request`

Diagnostics are limited to redacted booleans/status classes:

```text
callkit_planner_invoked=true/false
intake_decision=<redacted_decision_class>
callkit_report_decision=<redacted_decision_class>
callkit_report_requested=true/false
media_credentials_requested=false
media_connect_requested=false
matrix_event_emit_requested=false
blocked_reason=<redacted_class>
```

The report request model may carry safe internal identity and display metadata for a later adapter, but its descriptions remain redacted and it is not handed to a real `CXProvider` in 2.43D. Any future PushKit/APNs registration, entitlement, signing, provisioning, project, `Info.plist`, or `app.yml` change requires a separate explicit task.

## 2.43E Background CallKit Adapter Boundary

2.43E adds only a safe CallKit adapter boundary and fake/test reporting seam that can accept the 2.43D report request model. It does not register PushKit, request a VoIP token, register APNs, change entitlements, change provisioning, touch project files, wire a real PushKit/background callback, request media credentials, connect media, emit Matrix events, persist payload data, or change production call behavior.

The adapter boundary can classify outcomes as:

- `not_reported_not_reportable`
- `not_reported_missing_authenticated_context`
- `report_attempt_recorded`
- `report_failed_redacted`

Diagnostics are limited to redacted booleans/status classes:

```text
callkit_adapter_invoked=true/false
callkit_report_attempted=true/false
callkit_report_result=<redacted_result_class>
media_credentials_requested=false
media_connect_requested=false
matrix_event_emit_requested=false
pushkit_registration_requested=false
apns_registration_requested=false
blocked_reason=<redacted_class>
```

The default adapter remains inert unless a fake/test closure is injected. Tests can record a fake report attempt, but no real `CXProvider.reportNewIncomingCall` is called by this boundary and no PushKit/background callback is wired.

## 2.43F Controlled Real CallKit Adapter

2.43F adds only a controlled real CallKit adapter implementation behind the existing 2.43E boundary. It can translate a safe 2.43D background CallKit report request model into a CallKit-compatible provider report request, but it is not wired to PushKit/APNs/background callbacks, app launch, or production background behavior.

The real adapter uses an injected provider protocol, so tests exercise the path with fakes. The iOS provider implementation can build a `CXCallUpdate` from already-safe display metadata and a redacted internal UUID, then hand it to CallKit when explicitly invoked by a future owner. No PushKit registration, VoIP token request, APNs registration, entitlement change, project/signing edit, media credential request, media connection, Matrix event emission, payload persistence, or Element Call route replacement is introduced by this task.

Diagnostics are limited to redacted booleans/status classes:

```text
real_callkit_adapter_invoked=true/false
callkit_provider_report_attempted=true/false
callkit_provider_report_result=<redacted_result_class>
provider_failure_class=<redacted_class>
media_credentials_requested=false
media_connect_requested=false
matrix_event_emit_requested=false
pushkit_registration_requested=false
apns_registration_requested=false
blocked_reason=<redacted_class>
```

Provider failures are reported only as redacted classes. The adapter must not expose raw access tokens, authorization headers, Matrix user IDs, device IDs, room IDs, call handles, request payloads, private logs, secret-bearing URLs, or provider-private error details.

## 2.43G PushKit Lifecycle Abstraction Seam

2.43G adds only a safe PushKit lifecycle abstraction and fake/test manager for future native direct-call background incoming handling. It defines redacted lifecycle events for registration requests, token updates, token invalidation, payload receipt, and registration-unavailable states without creating a real `PKPushRegistry`, requesting PushKit/APNs tokens, wiring app startup, wiring background callbacks, or changing production behavior.

For fake payload receipt, the seam composes the existing 2.43B-F pipeline:

- The 2.43B parser validates the payload and timestamp guardrails.
- The 2.43C intake seam classifies the parsed payload and session state.
- The 2.43D planner builds or suppresses a CallKit report request.
- The 2.43F adapter can be invoked only through an injected fake/test provider.

Token update and invalidation events produce redacted decisions only. Raw PushKit/APNs tokens are not logged, persisted, sent to a server, or exposed in diagnostics.

Diagnostics are limited to redacted booleans/status classes:

```text
pushkit_lifecycle_invoked=true/false
pushkit_registration_requested=false
apns_registration_requested=false
token_update_received=true/false
token_invalidated=true/false
payload_received=true/false
payload_parse_status=valid/<redacted_failure_class>
intake_decision=<redacted_decision_class>
callkit_report_decision=<redacted_decision_class>
callkit_report_attempted=true/false
media_credentials_requested=false
media_connect_requested=false
matrix_event_emit_requested=false
blocked_reason=<redacted_class>
```

No PushKit registration, APNs registration, entitlement change, project/signing edit, media credential request, media connection, Matrix event emission, payload persistence, real PushKit/background callback, real app-start lifecycle wiring, or Element Call route replacement is introduced by this task.

## 2.43H PushKit Readiness Plan

2.43H adds only a docs-first readiness plan for the first real native direct-call PushKit/APNs registration step. It does not create a real `PKPushRegistry`, request PushKit/APNs tokens, wire app startup, wire background callbacks, change entitlements, change provisioning, touch project files, alter signing, request media credentials, connect media, emit Matrix events, or change production behavior.

The concrete plan lives in `docs/direct-call/PUSHKIT_READINESS_PLAN.md` and covers:

- Current safe baseline after the validated foreground real-invite path and 2.43B-G seams.
- Apple capability, APNs, VoIP/background, development team, provisioning, certificate, and signing prerequisites.
- A staged app-side plan: 2.43I registrar design, 2.43J token redaction/lifecycle tests, 2.43K controlled physical registration smoke, 2.43L server token registration contract, and 2.43M+ delivery smoke.
- Server-side token registration, invalidation, provider credential, redacted logging, payload mapping, and rollback requirements.
- Security/privacy constraints for raw PushKit/APNs tokens, identifiers, payloads, dev routes, auth gates, media, and Matrix events.
- Validation gates before any real PushKit task.
- Rollback requirements that keep the validated foreground path unaffected.

Future 2.43I may design a real native direct-call PushKit registrar behind an explicit feature gate, still without touching entitlements, project files, signing, provisioning, `Info.plist`, or `app.yml` unless the task separately authorizes those changes.

## 2.43I Gated PushKit Registrar Scaffold

2.43I adds only a real native direct-call PushKit registrar scaffold behind an explicit disabled-by-default feature gate. The scaffold includes a registrar, gate/configuration seam, redacted diagnostics, fakeable registry factory/protocol boundary, and an isolated real PushKit registry factory. It does not enable PushKit registration by default, wire registration to app startup, request APNs tokens, change entitlements, change provisioning, touch project files, alter signing, request media credentials, connect media, emit Matrix events, or change production behavior.

Default configuration stays disabled and does not create a registry or request a token. Enabled tests use a fake registry only. Token update and invalidation handling produces redacted diagnostics only; raw PushKit/APNs tokens are not logged, persisted, uploaded, documented, or exposed in descriptions.

Future 2.43J may run a controlled local physical PushKit registrar smoke only after explicit approval and entitlement/profile readiness. Any future entitlement, signing, provisioning, project, `Info.plist`, or `app.yml` change requires a separate explicit task.

## 2.43J PushKit Capability Readiness Verification

2.43J adds only a docs-first readiness verification matrix for the first controlled native direct-call PushKit registration smoke. It does not enable PushKit registration, wire registration to app startup, request PushKit/APNs tokens, modify entitlements, modify provisioning profiles, touch project files, alter signing, request media credentials, connect media, emit Matrix events, or change production behavior.

The matrix records that the foreground real-invite baseline is verified, the 2.43B-F parser/intake/planner/adapter chain is scaffolded, and the 2.43I registrar is scaffolded but disabled by default. Real PushKit runtime registration remains blocked until explicit approval, Apple Developer capability/profile readiness, and signing/team readiness are verified.

Tracked-source evidence shows `ElementX/SupportingFiles/ElementX.entitlements` contains development `aps-environment` and `ElementX/SupportingFiles/Info.plist` contains `UIBackgroundModes` including `voip`, but that is not the same as verifying Apple Developer portal capabilities or the active installed provisioning profile. Tracked `app.yml` still references old `DEVELOPMENT_TEAM: 83LGSC2QPV`, while physical Debug work must use `M639Y9MFR2`; 2.43J does not edit signing config.

Server token registration and server VoIP push provider readiness remain not implemented or not verified from this iOS docs-first step. Live route-level safety remains the fallback server check: `dev/invite=404`, unauthenticated non-dev invite `401`, and unauthenticated stream `401`. Direct `systemctl` service status must not be claimed unless it is actually verified.

## 2.43K PushKit Entitlement Change Proposal

2.43K adds only a docs-first proposal for the minimum future project, entitlement, signing, and provisioning changes that may be needed before a controlled native direct-call PushKit registration smoke. It does not apply those changes and does not touch `.entitlements`, `Info.plist`, `SalemX.xcodeproj/project.pbxproj`, `app.yml`, signing settings, provisioning profiles, bundle IDs, PushKit registration, APNs registration, token requests, media, Matrix events, or production background behavior.

The detailed proposal lives in:

```text
docs/direct-call/PUSHKIT_ENTITLEMENT_CHANGE_PROPOSAL.md
```

Current tracked evidence remains: the main app entitlement file has development `aps-environment`; main app `Info.plist`/target config includes `UIBackgroundModes` with `voip`; no tracked entitlement file has `com.apple.developer.pushkit.unrestricted-voip`; and tracked signing config still references old `83LGSC2QPV` while physical Debug work must use `M639Y9MFR2`.

A future implementation task must explicitly authorize touching `.entitlements`, `Info.plist`, `SalemX.xcodeproj/project.pbxproj`, `app.yml`, and signing/provisioning settings before any such edit is made.

## 2.43L Minimal PushKit Capability Files

2.43L applies only the minimum tracked project signing-reference readiness change for future controlled physical PushKit registration smoke. It updates generated `SalemX.xcodeproj/project.pbxproj` Development Team references from old `83LGSC2QPV` to `M639Y9MFR2`.

No entitlement or plist capability keys were changed because the tracked app state already has development `aps-environment` in `ElementX/SupportingFiles/ElementX.entitlements` and `UIBackgroundModes` with `voip` in `ElementX/SupportingFiles/Info.plist` / target config. No `com.apple.developer.pushkit.unrestricted-voip` key was added, and extension entitlements were not touched.

`app.yml` remains unchanged and still contains the old team value. Do not regenerate the Xcode project from that source config for PushKit physical smoke readiness until a separate explicit task authorizes `app.yml` signing remediation.

Real native direct-call PushKit registration remains disabled by default, no token is requested, no APNs registration is added, no real PushKit/background callback is wired, and no media credential, media connection, Matrix event emission, Element Call route replacement, or production background behavior is introduced.

## 2.43M-N Capability Build/Profile And Physical Install Validation

2.43M validates the checked-in `M639Y9MFR2` signing/capability state with a physical iOS Debug build. The built app bundle showed development `aps-environment`, `UIBackgroundModes` including `voip`, bundle ID class `kz.salemx.msg`, and no unexpected unrestricted VoIP entitlement. 2.43N then validated physical install and launch after the physical iPhone became available.

These phases did not request PushKit/APNs tokens, enable native direct-call PushKit registration by default, wire background callbacks, change app/runtime code, request media credentials, connect media, emit Matrix events, send server pushes, or change Element Call routing.

## 2.43O Controlled Local PushKit Registration Smoke

2.43O used the existing gated registrar through a DEBUG-only manual local smoke trigger on a physical iPhone. The smoke reached redacted `pushkit_registration_result=token_received` while keeping `pushkit_token_persistence_requested=false`, `pushkit_token_upload_requested=false`, `apns_registration_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.

No raw PushKit/APNs token was copied, logged, persisted, uploaded, recorded, documented, or committed. Real native direct-call PushKit registration remains disabled by default outside the local smoke path, and no real PushKit/background payload callback is wired into the native direct-call flow.

## 2.43P PushKit Token Registration Client Contract

2.43P adds only an app-side token registration contract/client seam. The client can receive token bytes internally, but diagnostics expose only redacted token-present/upload-status/failure classes. The default client has no real transport and does not upload. Tests inject a fake transport and synthetic token only.

No real token upload, token persistence, APNs registration, server VoIP push delivery, media credential request, media connection, Matrix event emission, background callback wiring, entitlement/project/signing/`Info.plist` change, or production behavior is introduced.

## 2.43Q Server PushKit Token Registration Contract

2.43Q adds only an auth-gated server endpoint/contract for future native direct-call PushKit token registration:

- `POST /_matrix/client/unstable/kz.salemx.direct_call/pushkit/token` is non-dev and uses the existing Matrix bearer-token validator.
- Tests use synthetic token payloads only.
- Successful responses return redacted status classes and keep `pushkit_token_store_requested=false`, `pushkit_token_store_result=not_persisted`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
- Malformed payloads fail closed.
- No dev token route is added, and foreground dev invite routes remain disabled unless their existing explicit dev flag is enabled.

No real app-runtime token upload is enabled. No raw PushKit/APNs token is logged, durably persisted, uploaded from runtime, recorded, documented, or committed. No APNs registration, VoIP push delivery, real PushKit/background callback wiring, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or production background behavior is introduced.

## 2.43R Fake-Token App/Server Registration Smoke

2.43R validates the local client/server token-registration seam against the changed FastAPI app using only a synthetic token fixture. The smoke reaches client-side `pushkit_token_upload_result=http_success` and server-side `pushkit_token_registration_result=registered`.

The server still does not durably store tokens and reports `pushkit_token_store_requested=false` and `pushkit_token_store_result=not_persisted`. Side-effect diagnostics remain false for APNs provider requests, VoIP push sends, media credentials, media connection, and Matrix event emission.

No real PushKit token is used, logged, persisted as raw, uploaded from actual PushKit runtime, recorded, documented, or committed. The smoke does not deploy to live staging, send VoIP pushes, request APNs tokens, wire real PushKit/background callbacks, request media credentials, connect media, emit Matrix events, change entitlement/project/signing/`Info.plist` files, or change production behavior.

## 2.43S Staging PushKit Token Endpoint Deploy Smoke

2.43S attempted staging deployment for the 2.43Q/2.43R token-registration endpoint after local tests passed. SSH to the configured staging alias timed out before any deploy or restart could run. Redacted blocker: `staging_deploy_blocked_by_ssh_timeout`.

Live staging still returns `404` for the token-registration route, so the endpoint remains locally validated only. No staging synthetic-token pass, service-active status, VoIP push delivery, APNs provider request, real token upload, media credential request, media connection, Matrix event emission, or production background behavior is claimed.

## 2.43T Staging Deploy Access Remediation

2.43T investigated the deploy access blocker. Tracked docs/scripts document local staging harnesses but no complete remote deployment recipe. The local staging SSH alias and identity file are present, but bounded connectivity to the configured alias path still times out before authentication or host-key negotiation; port 22 does not recover access from this machine.

No `systemctl` service status was verified, no deploy was run, and no synthetic-token staging smoke was attempted. Redacted blocker remains `staging_deploy_blocked_by_ssh_timeout`. Live staging route checks remain `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

## 2.43U Staging SSH/Network Deploy Path Recovery

2.43U retried access validation using the corrected staging SSH port. The staging alias resolves to port `71`, and port `22` is not the primary deploy path for this environment. A bounded port `71` connectivity check and bounded SSH probe through the alias both failed before authentication or host-key negotiation.

No `systemctl` service status was verified, no deploy was run, and no synthetic-token staging smoke was attempted. Redacted blocker is `staging_deploy_blocked_by_firewall_or_network_path`. Live staging route checks remain `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

## 2.43V Manual Staging Deploy Package

2.43V creates a manual staging deploy package/runbook at `docs/direct-call/PUSHKIT_STAGING_MANUAL_DEPLOY_RUNBOOK.md`.

The package lists only the 2.43Q/2.43R call-service endpoint files, documents pre-deploy validation, post-deploy route safety, synthetic-token smoke proof, forbidden data, and rollback, and explicitly keeps VoIP push delivery and real app-runtime token upload out of scope.

No deploy, restart, synthetic-token staging smoke, server environment change, route activation, APNs registration, APNs provider request, media credential request, media connection, Matrix event emission, or production background behavior is performed by 2.43V.

## 2.43W Fail2ban-Aware Staging Deploy Smoke

2.43W retried staging deploy access after the operator manually cleared fail2ban. Port `71` connectivity is now open, but the controlled SSH probe reached authentication and was rejected before `systemctl`, deployment, or restart could run.

No staging synthetic-token smoke was attempted. Redacted blocker is `staging_deploy_blocked_by_auth`. Live staging route checks remain `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

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
- 2.43D adds only the background CallKit report request/planner seam.
- 2.43E adds only the background CallKit adapter boundary and fake/test reporting seam.
- 2.43F adds only a controlled real CallKit adapter behind that boundary.
- 2.43G adds only a PushKit lifecycle abstraction/fake seam.
- 2.43H adds only a PushKit entitlement/provisioning/server readiness plan.
- 2.43I adds only a gated PushKit registrar scaffold.
- PushKit registration and APNs registration are still not implemented for native direct-call.
- No real `PKPushRegistry` is created by the native direct-call path.
- Raw PushKit/APNs tokens are not logged or persisted.
- Foreground real-invite behavior must remain unchanged.
- PushKit/APNs work must be separately scoped from foreground smoke tooling.
- Entitlements, provisioning, project settings, `Info.plist`, and `app.yml` are not changed by this investigation.
- Future entitlement or signing changes require a separate explicit task.
- No media credentials or media connection should be introduced during PushKit receipt.
- PushKit should only wake/report incoming call and coordinate safely with the call pipeline.
- No real CallKit reporting is wired from PushKit/APNs/background callbacks.
- Dev routes must remain disabled.
- Real non-dev routes must remain auth-gated.
- DEBUG smoke tooling is not production behavior.
- A future 2.43J may run a controlled local physical PushKit registrar smoke only after explicit approval and entitlement/profile readiness.
- Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.
