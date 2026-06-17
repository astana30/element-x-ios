# PushKit/APNs Background Incoming-Call Investigation

Status: 2.44C adds a controlled APNs VoIP sandbox send scaffold, but the live scaffold smoke is blocked before APNs by `persisted_pushkit_token_missing` for the available staging credential. Production PushKit/APNs/background behavior remains disabled by default and unwired.

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

After SSH auth recovery, resumed 2.43W copied the two runtime endpoint files to staging and remote compileall passed. Restarting only `salemx-call-service` is blocked by service restart authorization, so live staging still serves the pre-restart process. Redacted blocker is `staging_deploy_blocked_by_restart_auth`. Live staging route checks remain `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

## 2.43X Staging Service Restart Activation Smoke

2.43X attempted to activate the already-copied runtime files by restarting only `salemx-call-service`. Direct service status is `active`, but direct restart is blocked by interactive authentication, and non-interactive sudo restart is blocked because sudo requires a password.

No synthetic-token staging smoke was attempted. Redacted blocker is `staging_restart_blocked_by_sudo_password_required`. Live staging route checks remain `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

## 2.43Y Staging Token Endpoint Post-Restart Smoke

2.43Y verified direct service active status after the manually authorized restart path. Staging localhost route checks show unauthenticated token registration returns `401`, so the service process has loaded the endpoint and it is auth-gated locally. Public live route checks still show unauthenticated token registration returns `404`.

No synthetic-token staging smoke was attempted. Redacted blocker is `staging_token_registration_route_still_missing_after_restart`. Public staging route checks remain `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

## 2.43Z Public Token Route Proxy Smoke

2.43Z verified the route split was caused by public reverse-proxy exposure. Localhost token registration returned unauthenticated `401`, while public token registration returned unauthenticated `404` before the proxy change.

The public reverse proxy already forwarded foreground signaling to the `salemx-call-service` upstream. 2.43Z added the token-registration path to that same upstream, validated nginx syntax, reloaded only nginx, and verified nginx active after reload.

After reload, public route safety passed: `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.

The synthetic-token public staging smoke passed with redacted client proof `pushkit_token_upload_result=http_success` and server proof `pushkit_token_registration_result=registered`. Server diagnostics kept `pushkit_token_store_requested=false`, `pushkit_token_store_result=not_persisted`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.

No real PushKit/APNs token was used, logged, persisted, uploaded, or recorded. No APNs provider request, VoIP push delivery, real PushKit/background callback wiring, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.

## 2.44A Controlled Physical PushKit Token Upload Smoke

2.44A performed a controlled physical-device smoke through explicit DEBUG/manual tooling. A real PushKit VoIP token was received and uploaded once to the public staging token-registration endpoint, but the token was never printed, logged, copied into docs, persisted locally, durably stored by the server, recorded, or committed.

The redacted proof reached `physical_device_available=true`, `pushkit_registration_manual_invoked=true`, `pushkit_token_received=true`, `pushkit_token_redacted=true`, `pushkit_token_upload_requested=true`, `pushkit_token_upload_result=http_success`, and `pushkit_token_registration_result=registered`.

The same proof kept `pushkit_token_local_persistence_requested=false`, `pushkit_token_server_store_requested=false`, `pushkit_token_server_store_result=not_persisted`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, and `real_pushkit_background_callback_wired=false`.

Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.

This does not implement production native direct-call PushKit behavior. Registration remains disabled by default, no standard APNs token is requested, no APNs provider or VoIP push delivery is attempted, no PushKit/background payload callback is wired into the call flow, and no media credentials, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or production background behavior is introduced.

## 2.44B Controlled Server-Side Token Persistence

2.44B adds controlled server-side persistence for PushKit token registration. The store is file-backed at `/tmp/salemx-call-service-pushkit-token-store/pushkit-tokens.json`, creates its directory with `0700`, writes the file with `0600`, and uses hashed authenticated user/device/environment keys rather than raw Matrix identifiers.

The raw token is retained only inside the server-side store for future APNs send code. It is not returned by API, logged, printed, copied into docs, or exposed in diagnostics. Redacted diagnostics include `pushkit_token_store_requested=true`, `pushkit_token_store_result=persisted`, `pushkit_token_retrieval_internal_check=redacted_match`, and `pushkit_token_api_exposes_raw_token=false` when persistence is enabled.

Local server validation passed with compileall and `142 passed`. The updated runtime files were deployed to staging, remote compileall passed, `salemx-call-service` was restarted, and active status was verified after restart. Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.

2.44B1 reran the controlled physical real-token persistence smoke after the iPhone became available through CoreDevice/Xcode. The first post-install URL trigger failed closed before session restoration with `pushkit_token_upload_blocked_by_auth` and did not upload. After normal launch restored the session, the DEBUG/manual smoke received a real PushKit token, redacted it, uploaded it to staging, and verified server persistence.

Redacted proof reached `pushkit_token_upload_result=http_success`, `pushkit_token_registration_result=registered`, `pushkit_token_server_store_requested=true`, `pushkit_token_server_store_result=persisted`, `pushkit_token_retrieval_internal_check=redacted_match`, and `pushkit_token_api_exposes_raw_token=false`.

The raw token was not printed, logged, copied into docs, persisted locally on iOS, returned by API, recorded, or committed. Token retrieval remains internal-only.

No APNs provider request, VoIP push delivery, standard APNs token request, iOS local token persistence, real PushKit/background callback wiring, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or production background behavior is introduced.

## 2.44C Controlled APNs VoIP Sandbox Send Scaffold

2.44C adds a server-side APNs VoIP sandbox scaffold for future one-shot provider smoke work. The scaffold is auth-gated, explicit, disabled for real sends by default, sandbox-only, and redacted. It looks up the persisted PushKit token internally, builds only a minimal test-safe VoIP payload, and reports status classes without exposing the token, APNs auth material, payload contents, user IDs, device IDs, room IDs, call handles, media credentials, or secret-bearing URLs.

Local server validation passed with compileall and `151 passed`. The updated runtime files `app.py` and `apns_voip.py` were deployed to staging, remote compileall passed, `salemx-call-service` was restarted, and active status was verified after restart. Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.

The controlled staging scaffold invocation over localhost returned redacted `persisted_pushkit_token_lookup_result=missing` and `blocked_reason=persisted_pushkit_token_missing` for the available staging credential. It kept `apns_provider_requested=false`, `apns_credentials_available=false`, `apns_voip_push_send_requested=false`, `apns_voip_push_send_result=not_run`, `voip_push_repeated_send_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, and `real_pushkit_background_callback_wired=false`.

No APNs credentials, JWTs, authorization headers, raw PushKit/APNs tokens, private keys, or request payloads were printed, logged, recorded, documented, or committed. No production APNs push, real sandbox APNs push, repeated push, standard APNs token request, real PushKit/background callback wiring, CallKit report from PushKit, media credential request, media connection, Matrix event emission, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or production behavior was introduced.

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

## 2.44C1 APNs preflight update

The APNs scaffold now successfully locates the persisted PushKit token through the controlled user/environment lookup path. This resolves the earlier Web-session device mismatch where APNs control lookup returned missing because the PushKit token was stored under the physical iPhone device identity.

Redacted outcome:
- persisted_pushkit_token_lookup_result=found
- pushkit_token_redacted=true
- apns_credentials_available=false
- apns_topic_resolved=false
- apns_provider_requested=false
- apns_voip_push_send_requested=false
- blocked_reason=apns_voip_topic_unresolved

No APNs send was attempted in this step.

## 2.44D APNs provider boundary result

The staging APNs control route now reaches the APNs provider boundary with:
- persisted_pushkit_token_lookup_result=found
- apns_credentials_available=true
- apns_topic_resolved=true
- apns_voip_payload_built=true
- apns_provider_requested=true
- apns_voip_push_send_requested=true

The send result was sandbox_failure_redacted because the current APNs provider implementation is still the disabled/redacted scaffold provider. Real APNs HTTP/2 provider implementation remains a follow-up.

## 2.44E APNs HTTP/2 provider result

The server now has a controlled APNs VoIP sandbox HTTP/2 provider:
- sandbox APNs host only
- HTTP/2 client boundary
- ES256 provider JWT creation from server-local key material
- redacted APNs response handling
- safe APNs failure class reporting only

The provider remains explicit and controlled. It is not wired to normal app startup, PushKit background callbacks, CallKit reporting, Matrix event emission, media credentials, or media connection.

The physical iPhone upload smoke was rerun with a fresh Debug build that uploads the PushKit token as lowercase hex. Redacted proof reached:
- pushkit_token_upload_result=http_success
- pushkit_token_registration_result=registered
- pushkit_token_server_store_result=persisted
- pushkit_token_retrieval_internal_check=redacted_match

The APNs dry-run/send close-out is still blocked:
- restricted token-store permissions prevented direct redacted token-format inspection through the current non-interactive SSH policy
- no matching Matrix access token was available locally for the authenticated APNs dry-run
- APNs dry-run was not run
- real APNs sandbox send was not attempted

No raw PushKit token, APNs token, `.p8` contents, APNs key material, JWT, authorization header, request payload, private log, user ID, device ID, room ID, call handle, or secret-bearing URL was recorded.

## 2.44E1 APNs sandbox send verification

Verification stopped before APNs dry-run because the required gates were not available:
- route safety remained green
- `salemx-call-service` active was verified
- direct token-store format inspection was blocked by restricted permissions/current sudo policy
- no matching Matrix access token was available locally for the authenticated APNs control route

No APNs dry-run, real sandbox send, production send, repeated send, PushKit background callback wiring, CallKit-from-PushKit wiring, media credential request, or media connection was performed.

## 2.44E2 Operator-assisted APNs sandbox send verification

The operator-assisted verification stopped before APNs dry-run:
- route safety remained green
- `salemx-call-service` active was verified
- the hidden terminal prompt for the matching Matrix access token was opened
- no token was provided during this run

No APNs dry-run, real sandbox send, production send, repeated send, PushKit background callback wiring, CallKit-from-PushKit wiring, media credential request, or media connection was performed.

## 2.44E2 APNs sandbox send verification

The operator-assisted APNs sandbox send verification reached sandbox_success.

Redacted APNs result:
- persisted_pushkit_token_lookup_result=found
- pushkit_token_redacted=true
- apns_credentials_available=true
- apns_environment=sandbox
- apns_topic_resolved=true
- apns_provider_requested=true
- apns_voip_push_send_requested=true
- apns_voip_push_send_result=sandbox_success
- apns_failure_reason=none
- blocked_reason=none

This verifies the server-side APNs sandbox provider path. It does not yet prove physical iPhone PushKit background callback receipt.

## 2.45A Physical VoIP push receipt proof

The controlled physical receipt proof passed on a fresh Debug build.

Redacted proof:
- manual PushKit token upload returned http_success / registered / persisted / redacted_match
- APNs dry-run returned HTTP 200 with persisted token lookup found, sandbox credentials available, topic resolved, result dry_run, and no blocker
- exactly one real sandbox VoIP push send returned sandbox_success with no APNs failure reason
- iPhone proof returned physical_voip_push_received=true, pushkit_callback_invoked=true, pushkit_payload_redacted=true, pushkit_payload_version=1, pushkit_payload_kind=sandbox_voip_smoke, and pushkit_completion_called=true
- CallKit, media, Matrix events, and real call flow remained false

This proves receipt of the minimal sandbox VoIP push payload only. It does not wire PushKit receipt into CallKit reporting, Matrix event emission, media credentials, media connection, or full call flow.

## 2.45B PushKit callback controlled CallKit report proof

The controlled CallKit report proof passed from the physical PushKit sandbox callback.

Redacted proof:
- manual PushKit token upload returned http_success / registered / persisted / redacted_match
- APNs dry-run returned HTTP 200 with persisted token lookup found, sandbox credentials available, topic resolved, result dry_run, and no blocker
- exactly one real sandbox VoIP push send returned sandbox_success with no APNs failure reason
- iPhone proof returned pushkit_callback_invoked=true, pushkit_payload_redacted=true, pushkit_payload_kind=sandbox_voip_smoke, pushkit_completion_called=true, callkit_report_requested=true, and callkit_report_result=reported
- media credentials, media connection, Matrix events, and real call flow remained false

This proves only that the PushKit callback can request a controlled synthetic CallKit report. It does not wire Matrix event emission, media credentials, media connection, or full direct-call flow.

## 2.45C CallKit answer action proof

The DEBUG-only CallKit answer action proof path was added, but the physical smoke was blocked before a real APNs send.

Redacted result:
- answer-action proof can record `callkit_answer_action_received=true`, `callkit_answer_action_fulfilled=true`, and `app_activation_observed=true`
- fresh physical Debug build installed successfully
- route safety remained green
- fresh physical PushKit upload smoke returned `pushkit_token_upload_http_failure`
- APNs dry-run returned HTTP 401
- real sandbox APNs send was skipped
- CallKit answer action was not physically observed

No production APNs push was attempted. No repeated push was attempted. No raw token, APNs credential, JWT, authorization header, Matrix access token, raw payload, private log, or secret-bearing URL was recorded. Media, Matrix events, and full direct-call flow remain unwired.

## 2.45C1 PushKit completion ordering fix

The controlled DEBUG PushKit sandbox proof now records the CallKit report result before recording/calling PushKit completion.

Redacted result:
- source guard tests cover the completion ordering shape
- targeted DirectCall tests passed
- fresh physical Debug build installed successfully
- route safety remained green
- physical PushKit upload smoke stopped with `pushkit_token_upload_blocked_by_auth`
- APNs dry-run was not run
- real sandbox APNs send was not attempted
- CallKit answer action was not physically observed

No production APNs push was attempted. No repeated push was attempted. No raw token, APNs credential, JWT, authorization header, Matrix access token, raw payload, private log, or secret-bearing URL was recorded. Media, Matrix events, and full direct-call flow remain unwired.

## 2.45C Physical CallKit answer action proof

The physical CallKit answer proof passed after authenticated app session refresh.

Redacted proof:
- token upload returned http_success / registered / persisted / redacted_match
- APNs dry-run returned HTTP 200, persisted token lookup found, result dry_run, and no blocker
- exactly one real sandbox APNs send returned HTTP 200 and sandbox_success
- physical iPhone proof returned PushKit callback received, controlled CallKit report reported, PushKit completion called, CallKit answer action received and fulfilled, and app activation observed
- media credentials, media connection, Matrix events, and real call flow remained false

No production APNs push was attempted. No repeated push was attempted. No raw token, APNs credential, JWT, authorization header, Matrix access token, raw payload, private log, or secret-bearing URL was recorded.

## 2.45D Controlled in-app activation proof

The controlled in-app activation/screen proof passed after the physical PushKit callback, controlled CallKit report, and CallKit answer action.

Redacted proof:
- token upload returned http_success / registered / persisted / redacted_match
- APNs dry-run returned HTTP 200, persisted token lookup found, result dry_run, and no blocker
- exactly one real sandbox APNs send returned HTTP 200 and sandbox_success
- physical iPhone proof returned PushKit callback received, controlled CallKit report reported, PushKit completion called, CallKit answer action received and fulfilled, and app activation observed
- controlled in-app activation and screen proof returned requested and observed/presented with source `callkit_answer_sandbox_voip_smoke`
- media credentials, media connection, Matrix events, and real call flow remained false

No production APNs push was attempted. No repeated push was attempted. No raw token, APNs credential, JWT, authorization header, Matrix access token, raw payload, private log, or secret-bearing URL was recorded.

## 2.46A Real invite background mapping

The authenticated non-dev foreground invite route now maps into the existing APNs sandbox provider with a redacted `real_invite_controlled` payload kind.

Redacted proof:
- receiver token upload returned http_success / registered / persisted / redacted_match
- real non-dev invite was used and dev invite was not used
- background APNs push was requested once and returned sandbox_success
- iPhone PushKit proof observed `pushkit_payload_kind=real_invite_controlled` and `real_invite_payload_mapping_observed=true`
- controlled CallKit report returned `reported`
- Answer action was not observed, leaving controlled in-app activation false for this run

Current blocker:
- `callkit_answer_action_not_observed`

No production push, repeated push, raw APNs payload, raw invite body, token, JWT, authorization header, Matrix access token, media request, Matrix event, or full call flow was introduced.

## 2.46A1 Real invite Answer observation fix

The real-invite payload path uses the same controlled CallKit report helper as the sandbox smoke path. The likely blocker was stale controlled synthetic CallKit state: answered controlled calls were not ended or cleared after proof.

Fix:
- after Answer proof is recorded, the DEBUG-only synthetic proof adapter ends and clears only the controlled synthetic CallKit call
- redacted cleanup fields are written to proof output
- production call flow, media, Matrix events, and APNs provider code are unchanged

Validation:
- changed-file SwiftFormat and SwiftLint passed
- targeted DirectCall tests passed
- physical Debug build/install passed

Blocked:
- receiver PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- no real non-dev invite/APNs retry was attempted in this run

No production push, repeated push, raw APNs payload, raw invite body, token, JWT, authorization header, Matrix access token, media request, Matrix event, or full call flow was introduced.

## 2.46A3 Real invite pending-state fix

The latest dedicated VoIP receipt proof showed the real-invite-controlled PushKit callback reached `callkit_report_requested=true` but stayed at `callkit_report_result=pending` and `pushkit_completion_called=false`.

Fix:
- the controlled receipt path now uses a one-shot finalizer for CallKit report success/failure/timeout
- PushKit completion is recorded and called after the final report result is recorded
- timeout fallback is redacted as `callkit_report_completion_timeout_redacted`
- stale controlled CallKit harness state is cleared before reporting a new controlled call

Validation:
- changed-file SwiftFormat and SwiftLint passed
- targeted DirectCall tests passed
- physical Debug build/install passed

Blocked:
- receiver PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- no real non-dev invite/APNs retry was attempted after this fix

No production push, repeated push, raw APNs payload, raw invite body, token, JWT, authorization header, Matrix access token, media request, Matrix event, or full call flow was introduced.
