# PushKit Entitlement Change Proposal

Status: 2.43S staging deploy smoke is blocked by SSH timeout after the 2.43R local fake-token registration smoke. No entitlement, `Info.plist`, `app.yml`, APNs registration, real PushKit token upload, durable token persistence, VoIP push delivery, media, or production background behavior is changed by this document.

## 1. Current Tracked State

Tracked entitlement files:

- `ElementX/SupportingFiles/ElementX.entitlements` belongs to the main `SalemX` app target through `ElementX/SupportingFiles/target.yml` and `SalemX.xcodeproj/project.pbxproj`.
- `NSE/SupportingFiles/NSE.entitlements` belongs to the Notification Service Extension target.
- `ShareExtension/SupportingFiles/ShareExtension.entitlements` belongs to the Share Extension target.

Current entitlement contents from tracked files:

- The main app entitlement file contains `aps-environment=development`, app group, network client, and keychain access groups.
- The NSE entitlement file contains app group and keychain access groups.
- The Share Extension entitlement file contains app group and keychain access groups.
- No tracked entitlement file contains `com.apple.developer.pushkit.unrestricted-voip`.
- No other tracked PushKit/VoIP-specific entitlement key was found in the app, NSE, or Share Extension entitlement files.

Tracked `Info.plist` and XcodeGen state:

- `ElementX/SupportingFiles/Info.plist` contains `UIBackgroundModes` with `audio`, `fetch`, `processing`, and `voip`.
- `ElementX/SupportingFiles/target.yml` also declares `UIBackgroundModes` with `voip` and the main app entitlements path `ElementX.entitlements`.
- `NSE/SupportingFiles/target.yml` references `NSE.entitlements`.
- `ShareExtension/SupportingFiles/target.yml` references `ShareExtension.entitlements`.
- `SalemX.xcodeproj/project.pbxproj` references all three entitlement files and uses `CODE_SIGN_ENTITLEMENTS` for the app, NSE, and Share Extension targets.

Tracked signing/team state:

- `app.yml` contains `DEVELOPMENT_TEAM: 83LGSC2QPV`.
- `SalemX.xcodeproj/project.pbxproj` generated references that previously used `83LGSC2QPV` now use `M639Y9MFR2`.
- `SalemX.xcodeproj/project.pbxproj` also contains target settings that refer to `$(DEVELOPMENT_TEAM)` and inherit the project-level value.
- Current physical Debug work must use `M639Y9MFR2`.
- The old team ID `83LGSC2QPV` must not be used for future PushKit physical smokes.

Runtime state:

- 2.43I adds only a disabled-by-default native direct-call PushKit registrar scaffold.
- No native direct-call PushKit registration is enabled.
- No native direct-call PushKit token request is wired to app startup.
- Existing Element Call PushKit/VoIP code remains a separate product path and is not this native direct-call background implementation.

## 2.43L Applied Minimum Tracked Capability Readiness Changes

2.43L applies only the narrow tracked project signing-reference change needed before a future controlled physical PushKit registration smoke:

- `SalemX.xcodeproj/project.pbxproj` generated `DevelopmentTeam` references that were set to `83LGSC2QPV` now use `M639Y9MFR2`.
- Project-level generated `DEVELOPMENT_TEAM` build settings that were set to `83LGSC2QPV` now use `M639Y9MFR2`.

No entitlement or plist capability key was added in 2.43L because the current tracked app state already contains:

- `ElementX/SupportingFiles/ElementX.entitlements` with development `aps-environment`.
- `ElementX/SupportingFiles/Info.plist` and `ElementX/SupportingFiles/target.yml` with `UIBackgroundModes` including `voip`.

No `com.apple.developer.pushkit.unrestricted-voip` key was added. That key remains absent because the current proposal does not prove it is required for this app ID/account, and speculative entitlement keys can break signing or reviewability.

`app.yml` still contains the old team value and was intentionally not edited in 2.43L because the task's allowed-file audit did not permit `app.yml` changes. Do not regenerate the Xcode project from `app.yml` for PushKit physical smoke readiness until a separate explicit task authorizes the source XcodeGen config/signing remediation.

## 2.43M Build/Profile Validation

2.43M validated the checked-in 2.43L capability/signing state with an iPhoneOS Debug build using the approved physical Debug team override:

```text
DEVELOPMENT_TEAM=M639Y9MFR2
CODE_SIGN_STYLE=Automatic
```

The physical-device build succeeded for the generic iOS device destination. The resulting signed app bundle showed only redacted/safe capability facts:

- Effective Team ID / App Identifier prefix class: `M639Y9MFR2`.
- Bundle ID class: `kz.salemx.msg`.
- Effective app entitlements include development `aps-environment`.
- Effective app entitlements include the expected app group and keychain access group classes.
- Effective `UIBackgroundModes` includes `voip`.
- No unexpected unrestricted VoIP entitlement was present.
- The old team ID `83LGSC2QPV` was not present in the built app bundle.

Physical install was not validated in 2.43M because CoreDevice listed the available physical phones as unavailable. This is an install-availability blocker, not evidence that signing or capabilities failed.

Real native direct-call PushKit registration remains disabled by default. No PushKit/APNs token was requested, logged, persisted, or uploaded. No APNs registration, real PushKit/background callback wiring, media credential request, media connection, Matrix event emission, Element Call route replacement, or production background behavior was introduced.

## 2.43N Physical Install/Launch Validation

2.43N resumed the physical install capability validation after Developer Mode was enabled manually on the physical iPhone and the device was restarted, unlocked, trusted, and reconnected. Xcode/CoreDevice then listed the physical iPhone as available.

The checked-in 2.43L capability/signing state was rebuilt for the physical iPhone with the approved physical Debug team:

```text
DEVELOPMENT_TEAM=M639Y9MFR2
CODE_SIGN_STYLE=Automatic
```

The physical Debug build, install, and launch all succeeded. The resulting signed app bundle showed only redacted/safe capability facts:

- Effective Team ID / App Identifier prefix class: `M639Y9MFR2`.
- Bundle ID class: `kz.salemx.msg`.
- Effective app entitlements include development `aps-environment`.
- Effective app entitlements include the expected app group and keychain access group classes.
- Effective `UIBackgroundModes` includes `voip`.
- No unexpected unrestricted VoIP entitlement was present.
- The old team ID `83LGSC2QPV` was not present in the built app bundle.

This was install/launch capability validation only. No physical PushKit registration smoke was run. Real native direct-call PushKit registration remains disabled by default. No PushKit/APNs token was requested, logged, persisted, or uploaded. No APNs registration, real PushKit/background callback wiring, media credential request, media connection, Matrix event emission, Element Call route replacement, or production background behavior was introduced.

## 2.43O Controlled Local PushKit Registration Smoke

2.43O used the existing capability/signing state and a DEBUG-only manual smoke trigger to request PushKit registration locally on the physical iPhone.

Redacted smoke proof reached:

```text
pushkit_registration_requested=true
pushkit_feature_gate_enabled=true
pushkit_registry_create_requested=true
pushkit_token_update_received=true
pushkit_registration_result=token_received
pushkit_token_persistence_requested=false
pushkit_token_upload_requested=false
apns_registration_requested=false
media_credentials_requested=false
media_connect_requested=false
matrix_event_emit_requested=false
```

No raw PushKit/APNs token was copied, logged, pasted, persisted, uploaded, recorded, documented, or committed. No APNs registration was requested, no real PushKit/background payload callback was wired into the native direct-call flow, and no media credential request, media connection, Matrix event emission, Element Call route replacement, or production background behavior was introduced.

Real native direct-call PushKit registration remains disabled by default outside the controlled local DEBUG smoke path. Server token registration, token invalidation, VoIP provider credentials, and push delivery remain separate future work.

## 2.43P PushKit Token Registration Contract

2.43P adds only a safe app-side contract/client seam for future native direct-call PushKit token registration:

- The client can receive token bytes internally but only emits redacted token-present/upload-status diagnostics.
- The default client does not upload because no real transport is configured.
- Tests use a fake transport with a synthetic token and verify that the request remains redacted.
- Empty tokens are rejected before any upload attempt.
- Fake transport failures return redacted failure classes.
- Token persistence and real network upload remain absent.

No raw PushKit/APNs token is logged, persisted, uploaded, recorded, documented, or committed. No APNs registration is requested, no real PushKit/background callback is wired, no server VoIP push delivery is attempted, and no entitlement, `Info.plist`, `app.yml`, signing, provisioning, project, media, Matrix, or Element Call route behavior is changed.

## 2.43Q Server PushKit Token Registration Contract

2.43Q adds a server-side native direct-call PushKit token registration route contract:

- `POST /_matrix/client/unstable/kz.salemx.direct_call/pushkit/token` is auth-gated and non-dev.
- Tests use synthetic token payloads only.
- Successful responses expose redacted status classes such as `registered` and `not_persisted`.
- Malformed payloads fail closed without exposing raw token values.
- The route does not depend on the foreground dev invite flag, and no dev token route is added.
- No durable token storage, APNs provider call, VoIP push send, media credential request, media connection, or Matrix event emission is introduced.

No real app-runtime PushKit token upload is enabled. No raw PushKit/APNs token is logged, persisted, uploaded from runtime, recorded, documented, or committed. No APNs registration is requested, no real PushKit/background callback is wired, no server VoIP push delivery is attempted, and no entitlement, `Info.plist`, `app.yml`, signing, provisioning, project, media, Matrix, or Element Call route behavior is changed.

## 2.43R Fake-Token App/Server Registration Smoke

2.43R validates the token-registration seam against the local changed server app only:

- Client-side redacted proof reached `pushkit_token_upload_result=http_success`.
- Server-side redacted proof reached `pushkit_token_registration_result=registered`.
- The server kept `pushkit_token_store_requested=false` and `pushkit_token_store_result=not_persisted`.
- No real PushKit token was used; the smoke used a synthetic fixture only.
- Live staging token registration still requires server deployment before it can return the local 2.43Q/2.43R route behavior.

No token is logged, persisted as raw, uploaded from actual PushKit runtime, recorded, documented, or committed. No APNs provider is requested, no VoIP push delivery is attempted, no real PushKit/background callback is wired, and no entitlement, `Info.plist`, `app.yml`, signing, provisioning, project, media, Matrix, or Element Call route behavior is changed.

## 2.43S Staging Deploy Smoke Blocker

2.43S pre-deploy checks passed locally, but staging deploy access was blocked by SSH timeout before any server deployment or restart. Redacted blocker: `staging_deploy_blocked_by_ssh_timeout`.

Live staging token registration still returns `404`, so the 2.43Q/2.43R endpoint is not validated on staging. No staging synthetic-token pass is claimed. The next attempt must first restore deploy SSH access, then deploy only the call-service token endpoint changes and rerun route safety.

## 2. Minimum Future Changes Required

These changes are proposed for a later explicit task only. Do not apply them without user approval to touch forbidden files.

Likely app-side tracked file changes:

- `app.yml`: replace or override the old tracked team ID so physical Debug signing uses `M639Y9MFR2`, or document an explicit non-persistent command-line override if the tracked file is intentionally left unchanged.
- `SalemX.xcodeproj/project.pbxproj`: regenerate or update from XcodeGen only after the signing/team and entitlement plan is approved; expect project serialization noise risk.
- `ElementX/SupportingFiles/target.yml` and generated `ElementX/SupportingFiles/Info.plist`: confirm `UIBackgroundModes` includes `voip`; current tracked state already includes it, so no edit should be needed unless Apple/Xcode validation requires a different form.
- `ElementX/SupportingFiles/target.yml` and generated `ElementX/SupportingFiles/ElementX.entitlements`: confirm APNs and any required VoIP/PushKit capability key for the approved Apple account and app identifier.
- `.entitlements`: add a PushKit/VoIP-specific entitlement only if Apple Developer portal and Xcode capability validation explicitly require it for the current account/app ID. Do not add speculative entitlement keys.

Apple Developer and provisioning work:

- Enable or verify Push Notifications for the main app identifier.
- Enable or verify VoIP/PushKit/background capability support for the main app identifier.
- Regenerate development provisioning profiles for the main app using team `M639Y9MFR2`.
- Install or refresh the profile on the local machine and physical device workflow.
- Confirm the physical device is registered, trusted, unlocked, and online.

Build and smoke readiness:

- Keep the 2.43I registrar feature gate disabled by default.
- Allow a later task to enable the registrar only in a controlled local smoke path.
- Do not request APNs tokens as part of this native direct-call PushKit smoke unless a separate task explicitly scopes normal APNs behavior.
- Do not wire native direct-call PushKit registration to app startup until a later rollout plan approves it.

Server readiness:

- Native direct-call token registration and token invalidation endpoints remain separate future work.
- VoIP provider credentials remain server-side and must not be copied into source, docs, or app logs.
- Real push delivery should not start until token storage, invalidation, provider credentials, and redacted logging are reviewed.

## 3. Risks

- Xcode project noise can modify `SalemX.xcodeproj/project.pbxproj` beyond the intended signing/capability change.
- Using old team `83LGSC2QPV` can select the wrong App ID, profile, or entitlement set.
- A stale provisioning profile can compile but fail install, registration, or token issuance.
- APNs environment mismatch can produce a token that the server cannot use with the intended provider environment.
- A missing or unsupported VoIP capability can prevent PushKit token delivery.
- Apple policy requires VoIP pushes to be used for real incoming calls and reported through CallKit promptly; testing must stay narrow and compliant.
- Mixing entitlement changes with foreground real-invite changes can regress the validated foreground path.
- Logging or documenting token values, payloads, raw identifiers, private logs, or secret-bearing URLs would be a release blocker.

## 4. Validation Gates Before Applying Future Changes

Before any future task edits entitlement, project, signing, provisioning, `Info.plist`, or `app.yml` files:

- The user explicitly authorizes touching the specific forbidden files.
- Git status is clean except the intentionally untracked `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.
- `SalemX.xcodeproj/project.pbxproj` is clean before edits.
- The proposed file list is stated before edits.
- Targeted iOS tests pass before and after the change where practical.
- Privacy scan passes.
- Physical device is trusted, unlocked, online, and visible to Xcode/CoreDevice.
- Apple Developer account and app profile readiness for team `M639Y9MFR2` is verified.
- The old team `83LGSC2QPV` is not used.
- Route-level server safety remains:
  - `dev/invite=404`
  - unauthenticated non-dev invite `401`
  - unauthenticated stream `401`
- Rollback plan is prepared and documented.

## 5. Rollback Plan

If a future entitlement/provisioning change fails or needs rollback:

- Disable the native direct-call PushKit registrar feature gate.
- Revert only the approved entitlement, project, signing, `Info.plist`, and `app.yml` changes.
- Regenerate the Xcode project from approved XcodeGen config if XcodeGen files were the source of truth.
- Confirm no native direct-call PushKit registration is requested after rollback.
- Confirm no PushKit/APNs token is logged, persisted, uploaded, or documented.
- Confirm route-level safety remains `dev/invite=404`, unauthenticated non-dev invite `401`, and unauthenticated stream `401`.
- Run targeted tests and privacy scans.
- Run foreground real-invite smoke again only if the future change touched runtime paths that can affect the validated foreground route.

## 6. Future Task Authorization Boundary

A future entitlement/provisioning task may proceed only if the user explicitly authorizes touching one or more of:

```text
.entitlements
Info.plist
SalemX.xcodeproj/project.pbxproj
app.yml
signing/provisioning settings
```

Without that explicit authorization, the next task must remain docs/test-only and must not apply project, signing, capability, profile, entitlement, or `Info.plist` changes.
