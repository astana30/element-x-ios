# PushKit Readiness Plan

Status: 2.43H readiness plan only. No PushKit/APNs registration, entitlement, provisioning, project, signing, media, or production background behavior is implemented by this document.

## 1. Current Safe Baseline

The foreground real-invite path is validated. The 2.42M physical two-device foreground real-invite smoke passed at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`, and 2.42O consolidated the current foreground token-guard baseline.

The 2.43B-G background chain exists only as safe seams:

- 2.43B payload contract/parser.
- 2.43C intake decision seam.
- 2.43D CallKit report request planner.
- 2.43E fake/test CallKit adapter boundary.
- 2.43F controlled real CallKit adapter behind the boundary.
- 2.43G fake/test PushKit lifecycle abstraction.

There is no real native direct-call PushKit registration, no native direct-call APNs token request, and no native direct-call PushKit/background callback wiring. Entitlements, provisioning, project files, signing settings, `Info.plist`, and `app.yml` have not been changed for the native direct-call background path. No media credentials, media connection, Matrix event emission from invite receipt, Element Call route replacement, or production background behavior has been added.

Existing Element Call PushKit/VoIP surfaces remain a separate product path and are not the SalemX native direct-call background implementation.

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

### 2.43I - Real PushKit Registrar Design

Design a real native direct-call registrar class behind an explicit feature gate. It should not be wired at app startup by default. It should depend on the 2.43G lifecycle seam, expose only redacted diagnostics, and keep raw token values out of logs, descriptions, docs, and tests.

### 2.43J - Token Lifecycle Redaction Tests

Add tests for token update, token invalidation, failed registration, duplicate token handling, and no-token persistence. If server token upload is not explicitly in scope, tests must prove the token is not sent anywhere.

### 2.43K - Controlled Physical PushKit Registration Smoke

Run only after entitlements, profiles, and the physical Debug team are approved. The smoke should verify registration lifecycle and redacted diagnostics on a trusted physical device without sending native direct-call VoIP pushes yet.

### 2.43L - Server Token Registration Contract

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
