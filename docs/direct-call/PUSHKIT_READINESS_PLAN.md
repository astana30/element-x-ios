# PushKit Readiness Plan

Status: 2.43J PushKit capability readiness verification documented. No PushKit/APNs registration is enabled by default, and no entitlement, provisioning, project, signing, media, or production background behavior is implemented by this document.

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

The 2.43I registrar scaffold imports PushKit through an isolated real registry factory, but its feature gate defaults disabled and it is not wired to app startup. There is no enabled native direct-call PushKit registration, no native direct-call APNs token request, and no native direct-call PushKit/background callback wiring. Entitlements, provisioning, project files, signing settings, `Info.plist`, and `app.yml` have not been changed for the native direct-call background path. No media credentials, media connection, Matrix event emission from invite receipt, Element Call route replacement, or production background behavior has been added.

Existing Element Call PushKit/VoIP surfaces remain a separate product path and are not the SalemX native direct-call background implementation.

## 2.43J Capability Readiness Verification Matrix

This matrix records tracked-source and local route-level evidence for whether the current app/account/build environment is ready for a controlled native direct-call PushKit registration smoke. It is verification-only: no entitlement, project, signing, provisioning, `Info.plist`, `app.yml`, PushKit registration, APNs registration, token request, media, or production background behavior is changed.

| Area | Status | Evidence | Next action | Risk |
| --- | --- | --- | --- | --- |
| Foreground real invite baseline | verified | 2.42M physical two-device foreground real-invite smoke passed at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`; 2.42O consolidated the baseline. | Keep foreground path unchanged while background work stays separately scoped. | Regression risk if PushKit work is mixed into foreground signaling or smoke tooling. |
| Background parser/intake/planner/adapters | scaffolded | 2.43B-F provide parser, intake, planner, fake adapter, and controlled real CallKit adapter seams with redacted diagnostics and tests. | Continue using these seams as the only future background invite pipeline entry. | Bypassing seams could expose raw identifiers or trigger media/Matrix side effects. |
| Gated PushKit registrar scaffold | scaffolded | 2.43I adds `DirectCallPushKitRegistrar`; the feature gate defaults disabled, no startup wiring exists, and tests use fake registries. | Keep disabled by default until a separately authorized physical smoke task. | Enabling without profile/capability readiness can fail token issuance or create confusing device state. |
| Actual PushKit runtime registration | blocked | `DirectCallRealPushKitRegistryFactory` exists behind the 2.43I boundary, but no app-start owner wires it and no real token request is allowed in normal runtime. | Require explicit task approval and capability/profile readiness before any controlled registration smoke. | Accidental runtime registration could request a VoIP token without approved entitlements/profiles. |
| APNs/VoIP entitlements | not verified | Tracked `ElementX/SupportingFiles/ElementX.entitlements` contains development `aps-environment`; tracked `ElementX/SupportingFiles/Info.plist` includes `UIBackgroundModes` with `voip`. Apple Developer portal/profile state was not verified. | Verify Apple Developer capabilities and generated profiles before real PushKit smoke. | Tracked settings alone do not prove the installed app/profile can receive VoIP pushes. |
| Provisioning profile readiness | not verified | No provisioning profiles were modified or inspected as an authoritative readiness source in 2.43J. | Perform a separately authorized profile/certificate/device readiness check. | A local build may compile but fail device token issuance or install capability checks. |
| Physical Debug Team ID | blocked | Current physical Debug requirement is `M639Y9MFR2`, but tracked `app.yml` still references old `DEVELOPMENT_TEAM: 83LGSC2QPV`; 2.43J does not edit signing config. | Use only explicit physical build overrides or a separately authorized signing remediation task before device smoke. | Accidentally using `83LGSC2QPV` can produce the wrong profile/capability context. |
| Server token registration endpoint | not implemented | Docs contain only the planned server token registration contract; no native direct-call token upload endpoint is evidenced by this iOS verification. | Design/authenticate a server token registration contract in a separate task. | Without token registration, a VoIP provider cannot target native direct-call devices. |
| Server VoIP push provider credentials | not verified | No server provider credential check was performed, and credentials must not be copied into docs or source. | Verify provider key/certificate handling out of band with redacted evidence only. | Misconfigured provider credentials can block delivery even if app registration succeeds. |
| Route-level safety | verified | Live route checks returned `dev/invite=404`, unauthenticated non-dev invite `401`, and unauthenticated stream `401`. | Keep this as the fallback server safety check when direct service status is unavailable. | Route safety does not prove direct `systemctl` service status or push provider readiness. |
| Direct service status | not verified | SSH to port 22 timed out in the latest direct service probes, so `systemctl` was not verified. | Only claim `salemx-call-service active` after a successful direct service check. | Overstating service-active status can hide host/auth/network failures. |
| Privacy/logging policy | verified | 2.43B-I diagnostics are redacted; 2.43J changed docs only and privacy scans must reject raw PushKit/APNs tokens, identifiers, request payloads, private logs, and secret-bearing URLs. | Continue privacy scans on changed docs/code before every commit. | Token or payload leakage in logs/docs would be a release blocker. |
| Rollback strategy | ready | The 2.43H rollback plan requires disabling the registrar gate, preserving foreground behavior, deleting/invalidation server tokens, route-safety checks, and privacy scans. | Keep future real registration behind a kill switch and reversible server token state. | No clean rollback exists if registration is wired directly at startup without a gate. |

Readiness conclusion: a controlled real PushKit registration smoke is still blocked. The current code has only a disabled native direct-call registrar scaffold, tracked entitlement/config evidence is not equivalent to Apple Developer/profile readiness, the tracked team setting still needs explicit remediation or build overrides, and server token/provider readiness is not implemented or verified.

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

### 2.43J - Controlled Physical Registrar Smoke

Only after explicit approval and entitlement/profile readiness, run a local physical smoke for the gated registrar. This phase may prove whether capability/profile state is sufficient on a device, but it must remain controlled and reversible.

### 2.43K - Token Lifecycle Server Contract

Design or implement a server-side token registration endpoint or Matrix-backed metadata strategy. It must be authenticated, device-scoped, redacted in logs, and reversible. This phase should not send VoIP pushes until token storage, invalidation, and deletion are proven.

### 2.43L+ - VoIP Push Delivery Smoke

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
