# PushKit Readiness Plan

Status: 2.43W confirms the corrected port 71 staging path is reachable after manual fail2ban unban, but SSH authentication blocks deployment. PushKit registration remains disabled by default, and no real app-runtime token upload, APNs registration, durable token persistence, VoIP push delivery, media, or production background behavior is implemented by this document.

## 1. Current Safe Baseline

The foreground real-invite path is validated. The 2.42M physical two-device foreground real-invite smoke passed at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`, and 2.42O consolidated the current foreground token-guard baseline.

The 2.43B-I background chain exists only as safe seams:

- 2.43B payload contract/parser.
- 2.43C intake decision seam.
- 2.43D CallKit report request planner.
- 2.43E fake/test CallKit adapter boundary.
- 2.43F controlled real CallKit adapter behind the boundary.
- 2.43G fake/test PushKit lifecycle abstraction.
- 2.43H entitlement/provisioning/server readiness plan.
- 2.43I gated PushKit registrar scaffold.
- 2.43J capability readiness verification.
- 2.43K entitlement/provisioning change proposal.
- 2.43L minimal tracked capability-file readiness update.
- 2.43M build/profile/codesign capability validation.
- 2.43N physical install/launch capability validation.
- 2.43O controlled local PushKit registration smoke.
- 2.43P token registration contract/client seam.
- 2.43Q server token registration endpoint/contract.
- 2.43R fake-token app/server registration smoke.
- 2.43S staging deploy smoke blocked by SSH timeout.
- 2.43T staging deploy access remediation also blocked by SSH timeout.
- 2.43U corrected-port staging SSH recovery still blocked on port 71.
- 2.43V manual staging deploy package/runbook documented.
- 2.43W port 71 reaches SSH auth, but deployment is blocked by authentication.

The 2.43I registrar scaffold imports PushKit through an isolated real registry factory, but its feature gate defaults disabled and it is not wired to app startup. 2.43O used a DEBUG-only manual smoke trigger to request local PushKit registration once and receive a redacted `token_received` result. 2.43P adds only an inert token registration contract/client seam with fake transport tests. 2.43Q adds only an auth-gated server endpoint/contract tested with synthetic tokens; it returns redacted status classes and does not durably persist tokens or send VoIP pushes. 2.43R validates a local fake-token app/server smoke against the changed server app only. 2.43S attempted staging deploy validation but was blocked by `staging_deploy_blocked_by_ssh_timeout`, so live staging token registration still requires deployment. 2.43T verified that the local staging SSH alias and identity file exist. 2.43U confirmed the alias resolves to port `71`, the corrected deploy port for this environment, but the port 71 path still timed out before auth/host-key negotiation. 2.43V documents the manual deploy package and runbook for the 2.43Q/2.43R endpoint without deploying it. 2.43W confirms the operator-cleared fail2ban state lets port `71` accept connections, but SSH authentication now blocks deployment. There is still no default-enabled native direct-call PushKit registration, no native direct-call APNs token request, no real PushKit token upload from runtime, and no native direct-call PushKit/background payload callback wiring. Entitlements, provisioning, project files, signing settings, `Info.plist`, and `app.yml` have not been changed by 2.43O-W. No media credentials, media connection, Matrix event emission from invite receipt, Element Call route replacement, or production background behavior has been added.

Existing Element Call PushKit/VoIP surfaces remain a separate product path and are not the SalemX native direct-call background implementation.

## 2.43J Capability Readiness Verification Matrix

This matrix records tracked-source and local route-level evidence for whether the current app/account/build environment is ready for a controlled native direct-call PushKit registration smoke. It is verification-only: no entitlement, project, signing, provisioning, `Info.plist`, `app.yml`, PushKit registration, APNs registration, token request, media, or production background behavior is changed.

| Area | Status | Evidence | Next action | Risk |
| --- | --- | --- | --- | --- |
| Foreground real invite baseline | verified | 2.42M physical two-device foreground real-invite smoke passed at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`; 2.42O consolidated the baseline. | Keep foreground path unchanged while background work stays separately scoped. | Regression risk if PushKit work is mixed into foreground signaling or smoke tooling. |
| Background parser/intake/planner/adapters | scaffolded | 2.43B-F provide parser, intake, planner, fake adapter, and controlled real CallKit adapter seams with redacted diagnostics and tests. | Continue using these seams as the only future background invite pipeline entry. | Bypassing seams could expose raw identifiers or trigger media/Matrix side effects. |
| Gated PushKit registrar scaffold | scaffolded | 2.43I adds `DirectCallPushKitRegistrar`; the feature gate defaults disabled, no startup wiring exists, and tests use fake registries. | Keep disabled by default until a separately authorized physical smoke task. | Enabling without profile/capability readiness can fail token issuance or create confusing device state. |
| Actual PushKit runtime registration | verified for controlled local DEBUG smoke only | `DirectCallRealPushKitRegistryFactory` exists behind the 2.43I boundary. 2.43O triggered it manually from DEBUG-only diagnostics and reached redacted `token_received`; no app-start owner wires it and no real token request is allowed in normal runtime. | Keep registration disabled by default; design token registration/upload separately before any server push work. | Accidental startup registration could request a VoIP token outside the approved smoke path. |
| APNs/VoIP entitlements | verified for built Debug app | 2.43M signed an iPhoneOS Debug app whose effective entitlements include development `aps-environment`; the built app `Info.plist` includes `UIBackgroundModes` with `voip`; no speculative unrestricted VoIP entitlement was present. | Keep registration disabled until a controlled physical install/registration smoke is explicitly approved. | Build/profile capability presence does not prove token issuance until a physical install/registration smoke runs. |
| Provisioning profile readiness | verified for physical Debug install and local token receipt | 2.43N rebuilt, installed, and launched the signed Debug app on a physical iPhone after Developer Mode was enabled. 2.43O then used the DEBUG-only manual registrar smoke and received a redacted `token_received` result. | Keep registration disabled by default; next server token work must be separately scoped and must not record raw tokens. | Local token receipt does not prove token upload, invalidation, server provider credentials, or VoIP push delivery. |
| Physical Debug Team ID | verified for checked-in project build | Current physical Debug requirement is `M639Y9MFR2`; 2.43L updates generated project signing references from `83LGSC2QPV` to `M639Y9MFR2`; 2.43M signed the Debug app with effective Team ID / prefix `M639Y9MFR2`. Tracked `app.yml` still references old `DEVELOPMENT_TEAM: 83LGSC2QPV` and was not edited. | Do not regenerate from `app.yml` until a separate source-config remediation task is approved. | Regenerating the project from stale XcodeGen config can reintroduce the wrong team. |
| Server token registration endpoint | locally verified; staging deploy auth-blocked; manual package documented | 2.43Q adds `POST /_matrix/client/unstable/kz.salemx.direct_call/pushkit/token`, auth-gated through the existing Matrix bearer validator and tested with synthetic tokens only. 2.43R validates local fake-token app/server registration against the changed server app with redacted `http_success` and `registered` proofs. 2.43S pre-deploy checks passed, but SSH to staging timed out before deployment. 2.43T confirmed the local staging SSH alias and identity file are present. 2.43U confirmed the alias resolves to port `71`, but the port 71 path still timed out before auth/host-key negotiation. 2.43V documents a manual deploy runbook listing the runtime files and validation steps. 2.43W confirms port `71` connectivity is open after fail2ban unban, but SSH authentication blocks deploy; live staging still returns `404` for the token route. The endpoint does not durably persist tokens, does not log raw tokens, and does not send VoIP pushes. | Restore/authorize the SSH key or approved admin channel for the port 71 staging alias, then deploy the server endpoint and rerun staging synthetic-token smoke before storage/provider work. | Without staging deployment, durable storage, and invalidation, a VoIP provider still cannot target native direct-call devices. |
| Server VoIP push provider credentials | not verified | No server provider credential check was performed, and credentials must not be copied into docs or source. | Verify provider key/certificate handling out of band with redacted evidence only. | Misconfigured provider credentials can block delivery even if app registration succeeds. |
| Route-level safety | verified with token route still missing on staging | Live route checks returned `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`. The token route remains missing because staging deployment is still blocked. | Keep this as the fallback server safety check when direct service status is unavailable; require token registration `401` only after successful deploy. | Route safety does not prove direct `systemctl` service status or push provider readiness. |
| Direct service status | not verified | 2.43W bounded SSH probe reached authentication on the port 71 staging alias but was rejected before `systemctl` could run. | Only claim `salemx-call-service active` after a successful direct service check. | Overstating service-active status can hide host/auth/network failures. |
| Privacy/logging policy | verified | 2.43B-I diagnostics are redacted; 2.43J changed docs only and privacy scans must reject raw PushKit/APNs tokens, identifiers, request payloads, private logs, and secret-bearing URLs. | Continue privacy scans on changed docs/code before every commit. | Token or payload leakage in logs/docs would be a release blocker. |
| Rollback strategy | ready | The 2.43H rollback plan requires disabling the registrar gate, preserving foreground behavior, deleting/invalidation server tokens, route-safety checks, and privacy scans. | Keep future real registration behind a kill switch and reversible server token state. | No clean rollback exists if registration is wired directly at startup without a gate. |

Readiness conclusion: build/profile/codesign/install/launch capability validation is ready for the checked-in project state, and 2.43O proved local PushKit token receipt through a DEBUG-only manual smoke trigger. 2.43P adds only the redacted client contract seam for future token registration. 2.43Q adds only the server-side token registration endpoint contract with synthetic-token tests. 2.43R validates the local fake-token app/server registration path against the changed server app only. 2.43S, 2.43T, and 2.43U captured the staging SSH/network blockers; 2.43V documents a manual deploy package; 2.43W confirms port 71 is reachable after fail2ban unban but SSH auth blocks deploy. The current app code still has only a disabled-by-default native direct-call registrar scaffold for normal runtime, `app.yml` remains a regeneration risk, and staging deployment, durable token storage, invalidation, provider credentials, and VoIP push delivery are not implemented or verified.

## 2.43K Entitlement Change Proposal

The reviewable proposal for future entitlement/provisioning changes lives in:

```text
docs/direct-call/PUSHKIT_ENTITLEMENT_CHANGE_PROPOSAL.md
```

It records the current tracked state:

- The main app, NSE, and Share Extension entitlement files exist and are referenced by tracked target configuration/project files.
- The main app entitlement file contains development `aps-environment`.
- The NSE and Share Extension entitlement files contain app group and keychain access groups, but no APNs entitlement.
- No tracked entitlement file contains `com.apple.developer.pushkit.unrestricted-voip` or another PushKit/VoIP-specific entitlement key.
- The main app `Info.plist`/target config already includes `UIBackgroundModes` with `voip`.
- `app.yml` still references old team `83LGSC2QPV`; the checked-in project is updated in 2.43L, and physical Debug work must use `M639Y9MFR2`.

The proposal does not apply any of those changes. A future task may edit `.entitlements`, `Info.plist`, `SalemX.xcodeproj/project.pbxproj`, `app.yml`, or signing/provisioning settings only after explicit user approval naming those files/settings.

## 2.43L Minimal Capability Files Applied

2.43L applies the minimum tracked capability-file readiness change that is safe from the 2.43K proposal:

- Updated only `SalemX.xcodeproj/project.pbxproj` generated `DevelopmentTeam` / project-level `DEVELOPMENT_TEAM` references from `83LGSC2QPV` to `M639Y9MFR2`.
- Left `ElementX/SupportingFiles/ElementX.entitlements` unchanged because development `aps-environment` is already present.
- Left `ElementX/SupportingFiles/Info.plist` unchanged because `UIBackgroundModes` already includes `voip`.
- Did not add `com.apple.developer.pushkit.unrestricted-voip` or any speculative PushKit/VoIP-specific entitlement key.
- Did not edit extension entitlements.
- Did not edit `app.yml`; it still contains the old team value and requires a separate explicit source-config remediation task before XcodeGen regeneration.

Real PushKit registration remains disabled by default and is not wired to app startup. The next step should be controlled build/profile validation against the checked-in project and Apple Developer/profile state, not token registration.

## 2.43M Build/Profile Capability Validation

2.43M validates the 2.43L checked-in project state without changing code or capability files:

- The iPhoneOS Debug build succeeded for the generic physical iOS destination using `DEVELOPMENT_TEAM=M639Y9MFR2`, `CODE_SIGN_STYLE=Automatic`, `-allowProvisioningUpdates`, and `-allowProvisioningDeviceRegistration`.
- Effective Team ID / App Identifier prefix class is `M639Y9MFR2`.
- Effective bundle ID class is `kz.salemx.msg`.
- Effective app entitlements include development `aps-environment`.
- Effective app entitlements include the expected app group and keychain access group classes.
- Effective `UIBackgroundModes` includes `audio`, `fetch`, `processing`, and `voip`.
- No speculative unrestricted VoIP entitlement was present.
- The old team ID `83LGSC2QPV` was not present in the built app bundle.
- Physical install was blocked because CoreDevice listed the available physical phones as unavailable.

This is build/profile/codesign validation only. Real native direct-call PushKit registration remains disabled by default; no PushKit/APNs token was requested, logged, persisted, or uploaded; no APNs registration was added; no real PushKit/background callback was wired; and no media credential request, media connection, Matrix event emission, Element Call route replacement, or production background behavior was introduced.

`app.yml` remains a regeneration risk because it still contains the old team value. Do not regenerate the Xcode project from `app.yml` for PushKit work until a separate source-config signing remediation task is explicitly approved.

## 2.43N Physical Install Capability Validation

2.43N validates the 2.43L checked-in project state on a physical iPhone after the previous CoreDevice blocker was cleared:

- Developer Mode was enabled manually on the physical iPhone; the device was restarted, unlocked, trusted, reconnected, and listed as available by Xcode/CoreDevice.
- The iPhoneOS Debug build succeeded for the physical iPhone using `DEVELOPMENT_TEAM=M639Y9MFR2`, `CODE_SIGN_STYLE=Automatic`, `-allowProvisioningUpdates`, and `-allowProvisioningDeviceRegistration`.
- Physical install succeeded.
- App launch succeeded.
- Effective Team ID / App Identifier prefix class is `M639Y9MFR2`.
- Effective bundle ID class is `kz.salemx.msg`.
- Effective app entitlements include development `aps-environment`.
- Effective app entitlements include the expected app group and keychain access group classes.
- Effective `UIBackgroundModes` includes `audio`, `fetch`, `processing`, and `voip`.
- No speculative unrestricted VoIP entitlement was present.
- The old team ID `83LGSC2QPV` was not present in the built app bundle.

This is physical install/launch capability validation only. No physical PushKit registration smoke was run. Real native direct-call PushKit registration remains disabled by default; no PushKit/APNs token was requested, logged, persisted, or uploaded; no APNs registration was added; no real PushKit/background callback was wired; and no media credential request, media connection, Matrix event emission, Element Call route replacement, or production background behavior was introduced.

The next step can be a separately authorized controlled local PushKit registrar smoke using the existing disabled-by-default gate, but only if the task explicitly permits enabling that gate locally and still keeps server token registration, production rollout wiring, media, and foreground signaling changes out of scope.

## 2.43O Controlled Local PushKit Registration Smoke

2.43O validates the current `M639Y9MFR2` physical Debug signing/capability state by requesting PushKit registration only from a DEBUG-only manual local smoke control:

- Physical Debug build, install, and launch succeeded on the physical iPhone.
- The local smoke control requested registration with `pushkit_feature_gate_enabled=true`.
- Redacted diagnostics reached `pushkit_registry_create_requested=true`, `pushkit_token_update_received=true`, and `pushkit_registration_result=token_received`.
- Token handling diagnostics kept `pushkit_token_persistence_requested=false` and `pushkit_token_upload_requested=false`.
- APNs registration remained `apns_registration_requested=false`.
- Media and Matrix side-effect diagnostics remained `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
- No raw PushKit/APNs token was copied, logged, pasted, persisted, uploaded, recorded, documented, or committed.
- No real PushKit/background payload callback was wired into the native direct-call flow.

Real native direct-call PushKit registration remains disabled by default outside this local DEBUG smoke path. The next step should be a separately scoped token registration contract or upload-seam design; it must not send server VoIP pushes until token storage, invalidation, provider credentials, and redacted logging are approved.

## 2.43P PushKit Token Registration Contract

2.43P adds only an app-side token registration contract/client seam for future server work:

- The client accepts token bytes internally but exposes only redacted diagnostics such as token presence, fake upload status, and failure classes.
- The default client has no transport and returns a redacted `transport_unavailable` result without upload.
- Tests inject a fake transport to verify one redacted registration request for a synthetic token.
- Empty tokens are rejected before upload is attempted.
- Fake transport failures return `transport_failed_redacted` without exposing response bodies or payload details.
- Token persistence remains `pushkit_token_persistence_requested=false`.
- APNs registration, media credentials, media connection, Matrix event emission, real PushKit/background callback wiring, and server VoIP push delivery remain absent.

This seam does not upload a real PushKit token and does not record raw PushKit/APNs token values.

## 2.43Q Server PushKit Token Registration Contract

2.43Q adds only a server-side native direct-call PushKit token registration endpoint/contract:

- `POST /_matrix/client/unstable/kz.salemx.direct_call/pushkit/token` is a non-dev route.
- The route is auth-gated through the existing Matrix bearer-token validator.
- The request contract accepts versioned synthetic token payloads for tests and reduces server responses to redacted status classes.
- The endpoint does not durably persist tokens; `pushkit_token_store_requested=false` and `pushkit_token_store_result=not_persisted`.
- Server diagnostics keep `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
- Tests cover unauthenticated `401`, authenticated synthetic-token success, malformed payload rejection, disabled dev invite route behavior, redacted logs/diagnostics, and existing route-safety checks.

No real app-runtime PushKit token upload is enabled. No raw PushKit/APNs token is logged, persisted, uploaded from runtime, recorded, documented, or committed. No APNs registration, VoIP push delivery, real PushKit/background callback wiring, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or production background behavior is introduced.

## 2.43R Fake-Token App/Server Registration Smoke

2.43R validates the 2.43P/2.43Q seam using the local changed FastAPI app and a synthetic token fixture only:

- Client-side redacted proof reached `pushkit_token_registration_invoked=true`, `pushkit_token_present=true`, `pushkit_token_upload_requested=true`, `pushkit_token_persistence_requested=false`, and `pushkit_token_upload_result=http_success`.
- Server-side redacted proof reached `pushkit_token_registration_invoked=true`, `pushkit_token_present=true`, `pushkit_token_store_requested=false`, `pushkit_token_store_result=not_persisted`, and `pushkit_token_registration_result=registered`.
- Side-effect diagnostics remained `apns_registration_requested=false`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
- Local route safety remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.

The smoke uses no real PushKit token and does not deploy server code to live staging. No token is logged, persisted as raw, uploaded from actual PushKit runtime, or recorded. No VoIP push delivery, APNs provider request, APNs token request, real PushKit/background callback wiring, media credential request, media connection, Matrix event emission, entitlement/project/signing/`Info.plist` change, or production background behavior is introduced.

## 2.43S Staging PushKit Token Endpoint Deploy Smoke

2.43S attempted to deploy the 2.43Q/2.43R token-registration endpoint to staging.

Pre-deploy validation passed locally:

- server tests: `139 passed`
- Python compileall: passed
- `git diff --check`: passed
- allowed-file audit: passed
- repeat diagnostics check: `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` remained untracked

Deployment was blocked before any server change by SSH timeout to the configured staging alias. Redacted blocker: `staging_deploy_blocked_by_ssh_timeout`.

No staging deploy, restart, or synthetic-token staging smoke was performed. Live staging token registration still returns `404`; no staging pass is claimed. The next step must restore/verify staging deploy access, then deploy the endpoint and rerun route safety plus synthetic-token staging smoke.

## 2.43T Staging Deploy Access Remediation

2.43T investigated the blocked staging deploy path without changing app, server, entitlement, signing, or media behavior.

Evidence:

- Existing repo docs/scripts describe local staging harnesses and route-level smokes, but no complete remote deployment recipe was found in tracked files.
- The local SSH config contains a staging deploy alias with a non-standard SSH port, and the configured identity file is present.
- Bounded connectivity checks to the configured alias port and port 22 both failed from this machine before authentication or host-key negotiation.
- A bounded SSH probe to the configured staging alias timed out before `systemctl is-active salemx-call-service` could run.
- Redacted blocker: `staging_deploy_blocked_by_ssh_timeout`.

No deploy, restart, synthetic-token staging smoke, server environment change, or route activation was performed. Live staging route safety remains:

```text
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
unauthenticated token registration=404
```

The token registration route is still missing on staging because the 2.43Q/2.43R server code is not deployed there. The next attempt must first restore network/firewall/VPN/bastion access to the staging deploy alias or provide a verified replacement deploy path. Only after unauthenticated token registration changes from `404` to auth-gated `401` should synthetic-token staging registration be attempted.

## 2.43U Staging SSH/Network Deploy Path Recovery

2.43U retried access validation using the corrected staging SSH port:

- The staging SSH alias resolves to port `71`.
- Port `22` is not the primary deploy check for this environment.
- A bounded port `71` connectivity check failed before authentication or host-key negotiation.
- A bounded SSH probe through the port `71` alias timed out before `systemctl is-active salemx-call-service` could run.
- Redacted blocker: `staging_deploy_blocked_by_firewall_or_network_path`.

No deploy, restart, synthetic-token staging smoke, server environment change, or route activation was performed. Live staging route safety remains:

```text
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
unauthenticated token registration=404
```

The token registration route is still missing on staging because the 2.43Q/2.43R server code is not deployed there. The next attempt must restore network/firewall/VPN/bastion access to the port 71 staging alias or provide a verified replacement deploy path before deployment can proceed.

## 2.43V Manual Staging Deploy Package

2.43V documents a manual deployment package and operator runbook at:

```text
docs/direct-call/PUSHKIT_STAGING_MANUAL_DEPLOY_RUNBOOK.md
```

The runbook lists only the 2.43Q/2.43R call-service files needed for endpoint deployment:

```text
server/salemx-call-service/salemx_call_service/app.py
server/salemx-call-service/salemx_call_service/pushkit_tokens.py
server/salemx-call-service/tests/test_service.py
```

It separates runtime files from tests, documents safe deployment options, pre-deploy checks, post-deploy route checks, synthetic-token staging proof, forbidden data, rollback, and the next prompt. It explicitly keeps VoIP push delivery, APNs provider requests, real app-runtime token upload, iOS project changes, media behavior, and production background callback wiring out of scope.

No deploy, restart, live smoke, server environment change, route activation, or physical PushKit smoke is performed by 2.43V. Live route state remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

## 2.43W Fail2ban-Aware Staging Deploy Smoke

2.43W retried staging deploy access after the operator manually cleared fail2ban.

Evidence:

- The staging SSH alias resolves to port `71`.
- Bounded port `71` connectivity is now open.
- A bounded SSH probe reached authentication but was rejected before any remote command could run.
- Redacted blocker: `staging_deploy_blocked_by_auth`.

No deploy, restart, synthetic-token staging smoke, server environment change, or route activation was performed. Live staging route safety remains:

```text
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
unauthenticated token registration=404
```

The token registration route is still missing on staging because the 2.43Q/2.43R server code is not deployed there. The next attempt must fix SSH key authorization or use the approved manual deploy channel from the runbook before deployment can proceed.

## 2. Apple Capability And Provisioning Requirements

Real PushKit registration can work only after Apple capability and provisioning requirements are deliberately verified and approved.

Required assumptions to validate before any real registration task:

- The app identifier must have the necessary APNs capability.
- The app must have the required VoIP/background capability profile support for PushKit use.
- The active development team for physical Debug work must be `M639Y9MFR2`.
- The old team ID `83LGSC2QPV` must not be used.
- Development and distribution provisioning profiles must match the exact bundle identifier, APNs environment, and background capability set.
- Push provider credentials, certificates, or keys must be handled outside app logs/docs and must not be copied into source.

The following files/settings remain forbidden unless a later task explicitly authorizes them:

- `SalemX.xcodeproj/project.pbxproj`
- signing settings
- `app.yml`
- `Info.plist`
- entitlements
- provisioning profile configuration

Any Apple Developer portal, profile, certificate, entitlement, signing, or project-file change must be a separate explicit task with its own rollback and validation plan.

## 3. App-Side Implementation Plan

Future work should stay staged and reversible:

### 2.43I - Gated PushKit Registrar Scaffold

Add a real native direct-call registrar scaffold behind an explicit feature gate. The gate defaults disabled. The scaffold must not be wired at app startup by default. It should expose only redacted diagnostics and keep raw token values out of logs, descriptions, docs, and tests. Enabled tests must use fake registry/fake delegate only.

### 2.43J - Controlled Build/Profile Validation

Validate the checked-in project, signing team, effective entitlements, embedded profile summary, and built app background modes without launching the app or requesting tokens.

### 2.43K - Controlled Physical Registrar Smoke

Only after explicit approval and entitlement/profile readiness, run a local physical smoke for the gated registrar. This phase may prove whether capability/profile state is sufficient on a device, but it must remain controlled and reversible.

### 2.43L - Token Lifecycle Server Contract

Design or implement a server-side token registration endpoint or Matrix-backed metadata strategy. It must be authenticated, device-scoped, redacted in logs, and reversible. This phase should not send VoIP pushes until token storage, invalidation, and deletion are proven.

### 2.43M+ - VoIP Push Delivery Smoke

Only after token registration and provider credentials are approved, map a real foreground-equivalent invite to the 2.43B payload contract and deliver a VoIP push to a physical device. The push callback should parse, intake, plan, and report through the existing seams without media connection or Matrix event emission from receipt.

## 4. Server-Side Requirements

The server side needs an explicit native direct-call push contract before delivery smoke:

- A token registration endpoint or Matrix-backed device metadata strategy.
- Token invalidation handling for logout, app reinstall, APNs invalidation, and account/device removal.
- Push provider credential management with no raw credential exposure in app logs/docs.
- Redacted server logs only; raw PushKit/APNs tokens must not be logged.
- A mapping from invite event to the 2.43B payload contract.
- Payload expiry, versioning, and unsupported-version handling.
- Device/session targeting that avoids leaking raw user, device, room, or call identifiers in diagnostics.
- Route/auth behavior that keeps dev routes disabled and real non-dev routes auth-gated.
- A deletion/rollback path for registered tokens.

The push payload must not contain media credentials, media URLs, access tokens, authorization headers, request payload dumps, private logs, or secret-bearing URLs.

## 5. Security And Privacy Constraints

Future PushKit/APNs work must keep these constraints:

- Raw PushKit/APNs tokens must not be logged, printed, documented, or committed.
- Raw user IDs, device IDs, room IDs, call handles, recipients, request payloads, private logs, and secret-bearing URLs must not appear in diagnostics.
- Payload diagnostics must stay redacted to status classes and booleans.
- Dev routes remain disabled.
- Real non-dev routes remain auth-gated.
- Push payloads must not include media credentials.
- Push callbacks must not request media credentials.
- Push callbacks must not connect media.
- Push callbacks must not emit Matrix events.
- DEBUG foreground smoke tooling is not production PushKit behavior.

## 6. Validation Gates Before Real PushKit Work

Before any task that performs real native direct-call PushKit registration:

- Git status is clean except the intentionally untracked `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.
- `SalemX.xcodeproj/project.pbxproj` is clean.
- Forbidden-file scans show no project, signing, `app.yml`, `Info.plist`, or entitlement drift unless the task explicitly authorizes those changes.
- Targeted tests pass.
- Privacy scan passes.
- Physical device is unlocked, trusted, online, and visible to Xcode/CoreDevice.
- Apple Development provisioning is valid for team `M639Y9MFR2`.
- Old team `83LGSC2QPV` is not used.
- There is explicit approval to touch entitlements/project/signing if the task requires it.
- Route-level server safety remains:
  - `dev/invite=404`
  - unauthenticated non-dev invite `401`
  - unauthenticated stream `401`

Only claim direct service-active status when `systemctl` or an equivalent direct service check is actually verified. If SSH is blocked by host-key or auth, report that separately from route-level safety.

## 7. Rollback Plan

Any real PushKit registrar must have a feature gate or kill switch that can disable registration without changing the validated foreground path.

Rollback requirements:

- Disable the real native direct-call PushKit registrar.
- Confirm no native direct-call PushKit registration is requested after disablement.
- Confirm foreground real invite behavior remains unchanged.
- Confirm DEBUG smoke controls remain DEBUG-only and are not broadened into production behavior.
- Delete or invalidate server-side token registrations for the rolled-back client/device scope.
- Confirm route-level safety: dev invite `404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`.
- Confirm privacy scan shows no raw token, user, device, room, call, request payload, private log, or secret-bearing URL.
- Confirm no media credential request, media connection, or Matrix event emission occurs from push receipt.
- Confirm project, signing, entitlement, `Info.plist`, and `app.yml` state matches the approved rollback target.
