# PushKit Readiness Plan

Status: 2.47B5 physically validates the safe authenticated pending-metadata fetch handoff needed before a real media credentials request from the PushKit-controlled Answer path. The proof records only redacted fetch status and metadata presence/safe direction/intent classes; no raw call ID, room ID, peer ID, call handle, token, URL, request body, media connection, LiveKit join, Matrix event emission, or production background behavior is implemented by this document.

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
- 2.43W port 71 reaches SSH auth; resumed 2.43W copies runtime files but is blocked at service restart authorization.
- 2.43X service restart activation is blocked by sudo password policy.
- 2.43Y verifies service restart/status access and local token route activation, but public token route remains `404`.
- 2.43Z maps the public token route through the reverse proxy, reloads nginx, and validates public synthetic-token registration.
- 2.44A validates a controlled physical PushKit token upload smoke against the public staging token-registration endpoint.
- 2.44B implements a controlled server-side token store and deploys it to staging.
- 2.44B1 reruns the controlled physical token upload smoke and verifies redacted persisted storage.
- 2.44C adds a controlled APNs VoIP sandbox send scaffold and records the redacted staging blocker before APNs.
- 2.47A6 verifies the real-invite/APNs path reaches CallKit report completion, then narrows the blocker to CallKit delivering End before Answer.
- 2.47A7 adds operator-observed Answer/End intent timing markers to the dedicated VoIP receipt proof; the latest physical proof still delivered End first in 500-2000ms before operator intent was marked.
- 2.47A10 proves the local CallKit-only path can deliver Answer, while the background PushKit path completes the CallKit report and PushKit completion in `<100ms`, stays foreground, exposes no local End cause, and then receives system/user-unknown End more than `2000ms` later before the operator observes an answerable surface.
- 2.47A13 splits local CallKit-only proof from VoIP PushKit receipt proof. Local proof now records `proof_source=local_callkit_only` and Answer success in `Documents/salemx-local-callkit-only-proof.txt`; VoIP receipt proof records `proof_source=voip_push_receipt`, answerable-window first-action observation, and the continuing background blocker in `Documents/salemx-voip-push-receipt-proof.txt`.
- 2.47A15 adds a scheduled local background CallKit-only proof in `Documents/salemx-local-background-callkit-proof.txt`; physical proof reports `app_state_at_report=background`, `local_background_first_action_kind=answer`, and `blocked_reason=none`. This rules out generic CallKit config and background app state as the cause of the PushKit path's first-action End.
- 2.47B validates the controlled media credentials request lifecycle as a safe blocked boundary: the proof reaches `foreground_call_state=real_invite_pending_media`, records `media_credentials_boundary_reached=true`, `media_credentials_requested=false`, `media_credentials_result=blocked_redacted`, token/URL/payload redaction booleans, and `blocked_reason=media_credentials_request_boundary_not_ready`.
- 2.47B1 records the real foreground pending-call metadata handoff from `DirectCallSession` using only redacted presence booleans and safe direction/intent classes. Synthetic receipt proof still blocks before credential request when metadata is unavailable.
- 2.47B5 physically proves the PushKit-controlled Answer path can fetch authenticated pending metadata by opaque APNs reference, record redacted handoff proof, reach `media_credentials_request_metadata_available=true`, and still defer real media credentials to the next phase.

The 2.43I registrar scaffold imports PushKit through an isolated real registry factory, but its feature gate defaults disabled and it is not wired to app startup. 2.43O used a DEBUG-only manual smoke trigger to request local PushKit registration once and receive a redacted `token_received` result. 2.43P adds only an inert token registration contract/client seam with fake transport tests. 2.43Q adds only an auth-gated server endpoint/contract tested with synthetic tokens; it returns redacted status classes and does not durably persist tokens or send VoIP pushes. 2.43R validates a local fake-token app/server smoke against the changed server app only. 2.43S attempted staging deploy validation but was blocked by `staging_deploy_blocked_by_ssh_timeout`, so live staging token registration still requires deployment. 2.43T verified that the local staging SSH alias and identity file exist. 2.43U confirmed the alias resolves to port `71`, the corrected deploy port for this environment, but the port 71 path still timed out before auth/host-key negotiation. 2.43V documents the manual deploy package and runbook for the 2.43Q/2.43R endpoint without deploying it. 2.43W confirms port `71` connectivity, then resumed 2.43W verifies SSH publickey auth, copies the two endpoint runtime files, and remote compileall passes. 2.43X records the restart-auth blocker. 2.43Y verifies the manually restored restart/status path and confirms the token route is active on staging localhost. 2.43Z maps the public token route through the reverse proxy, reloads nginx, and validates public synthetic-token registration with redacted success. 2.44A uses a controlled DEBUG/manual physical smoke to receive a real PushKit token and upload it once to the public staging token-registration endpoint; the proof is fully redacted and the server does not persist the token. 2.44B adds controlled server-side persistence and deploys it to staging. 2.44B1 reruns the physical smoke on a connected iPhone and verifies redacted `persisted` storage plus `pushkit_token_retrieval_internal_check=redacted_match`. 2.44C adds a controlled server-side APNs VoIP sandbox send scaffold, deploys it to staging, and verifies it fails closed before APNs for the available staging credential with `persisted_pushkit_token_missing`; later phases prove the matched real-invite APNs path can send sandbox pushes successfully. 2.47A6 narrows the active blocker to CallKit delivering End before Answer after successful report. 2.47A7 adds redacted operator-intent/timing proof. 2.47A10 narrows further: local CallKit-only Answer works, but background PushKit completes the report, calls PushKit completion in `<100ms`, remains foreground, exposes no local End cause, and then receives End after `>2000ms` before an answerable UI surface is observed. 2.47A13 removes the local-proof/VoIP-receipt storage collision and proves the answerable-window first action is still End. 2.47B5 physically proves the redacted authenticated metadata fetch bridge for the existing media token boundary, but does not request credentials or connect media. There is still no default-enabled native direct-call PushKit registration, no production APNs send, no repeated push in this commit step, no real media credential request, no media connection, no LiveKit join, no Matrix event emission, and no full direct-call flow. Entitlements, provisioning, project files, signing settings, `Info.plist`, and `app.yml` have not been changed by this work.

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
| Server token registration endpoint | persisted real-token smoke verified | 2.43Q adds `POST /_matrix/client/unstable/kz.salemx.direct_call/pushkit/token`, auth-gated through the existing Matrix bearer validator and tested with synthetic tokens only. 2.43R validates local fake-token app/server registration against the changed server app with redacted `http_success` and `registered` proofs. 2.43W copied the endpoint runtime files to staging. 2.43Y verifies the service is active after restart and localhost token registration returns unauthenticated `401`. 2.43Z maps the public token route through the reverse proxy; public unauthenticated token registration is now `401`, and synthetic-token public staging registration passes with `http_success` and `registered`. 2.44A uses a DEBUG/manual physical smoke to upload one real PushKit token to the staging endpoint with redacted `http_success` and `registered` proof. 2.44B adds a file-backed server token store with hashed identity keys and restricted file permissions, deploys it to staging, and verifies route safety. 2.44B1 reruns the physical smoke and reaches `pushkit_token_server_store_result=persisted`, `pushkit_token_retrieval_internal_check=redacted_match`, and `pushkit_token_api_exposes_raw_token=false`. The API does not return tokens, logs remain redacted, and no VoIP push is sent. | Design token invalidation/replacement observability next. Do not move to VoIP push delivery until invalidation and provider readiness are explicitly scoped. | Raw token storage now exists server-side by design for future internal APNs send code, so invalidation, retention, and operational access controls need explicit follow-up before push delivery. |
| Server VoIP push provider credentials | not verified | No server provider credential check was performed, and credentials must not be copied into docs or source. | Verify provider key/certificate handling out of band with redacted evidence only. | Misconfigured provider credentials can block delivery even if app registration succeeds. |
| APNs VoIP sandbox send scaffold | scaffolded; blocked before APNs | 2.44C adds an auth-gated server scaffold route for explicit sandbox VoIP send control. Local tests verify disabled-by-default behavior, sandbox-only enforcement, missing-token and missing-credential failures, dry-run, fake-provider success, redaction, and route safety. Staging deploy/restart succeeded, but the live scaffold invocation returned `persisted_pushkit_token_lookup_result=missing` and `blocked_reason=persisted_pushkit_token_missing` for the available staging credential; APNs credentials/topic were not configured. | Provide an authenticated smoke path for the same physical app user/device and configure sandbox APNs credentials/topic through server-local secrets only, then rerun a single explicit sandbox send. | Using the wrong authenticated identity cannot retrieve the stored token. Real APNs sends must stay one-shot, sandbox-only, and redacted. |
| Route-level safety | verified with token route exposed and auth-gated | Public route checks returned `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401` after the 2.43Z proxy reload. | Keep route safety in every future server/token task. | Route safety does not prove provider readiness, durable storage, or real push delivery. |
| Direct service status | verified active after restart | 2.43Y verified `salemx-call-service` is active after the manually authorized restart path. | Keep using direct status only as service-process evidence; public route checks still decide whether the endpoint is reachable. | Service active status does not prove reverse-proxy route exposure. |
| Privacy/logging policy | verified | 2.43B-I diagnostics are redacted; 2.43J changed docs only and privacy scans must reject raw PushKit/APNs tokens, identifiers, request payloads, private logs, and secret-bearing URLs. | Continue privacy scans on changed docs/code before every commit. | Token or payload leakage in logs/docs would be a release blocker. |
| Rollback strategy | ready | The 2.43H rollback plan requires disabling the registrar gate, preserving foreground behavior, deleting/invalidation server tokens, route-safety checks, and privacy scans. | Keep future real registration behind a kill switch and reversible server token state. | No clean rollback exists if registration is wired directly at startup without a gate. |

Readiness conclusion: build/profile/codesign/install/launch capability validation is ready for the checked-in project state, and 2.43O proved local PushKit token receipt through a DEBUG-only manual smoke trigger. 2.43P adds only the redacted client contract seam for future token registration. 2.43Q adds only the server-side token registration endpoint contract with synthetic-token tests. 2.43R validates the local fake-token app/server registration path against the changed server app only. 2.43Z confirms the staging service has the token endpoint exposed publicly and auth-gated, and validates synthetic-token registration without persistence or push delivery. 2.44A confirms a controlled physical real-token upload can reach the staging endpoint with redacted `http_success` and `registered` proof. 2.44B adds and deploys controlled server-side persistence. 2.44B1 confirms a physical real-token upload reaches the persisted staging store and reports only redacted `persisted` / `redacted_match` proof. 2.44C adds the APNs VoIP sandbox scaffold but the live scaffold smoke is blocked before APNs by authenticated-token lookup mismatch and missing APNs configuration. 2.47B5 physically proves a redacted authenticated metadata fetch bridge for the existing media token boundary, but does not request credentials or connect media. The current app code still keeps native direct-call PushKit registration disabled by default in normal runtime, `app.yml` remains a regeneration risk, and token invalidation, matching-auth smoke, provider credentials, and production VoIP push delivery are not implemented or verified.

## 2.44B Controlled Server-Side PushKit Token Persistence

2.44B adds minimal controlled server-side persistence for uploaded PushKit tokens:

- Storage is file-backed at `/tmp/salemx-call-service-pushkit-token-store/pushkit-tokens.json`.
- The store creates its directory with `0700` and the token file with `0600`.
- Store keys are hashes of authenticated Matrix user/device/environment values, not raw identifiers.
- The raw token is stored only internally for future APNs send code.
- API responses never return the raw token and include `pushkit_token_api_exposes_raw_token=false`.
- Internal retrieval is represented only by the redacted status class `pushkit_token_retrieval_internal_check=redacted_match`.

Local server validation passed with compileall and `142 passed`. The updated `app.py` and `pushkit_tokens.py` runtime files were deployed to staging, remote compileall passed, `salemx-call-service` was restarted, and active status was verified after restart. Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.

2.44B1 reran the controlled physical real-token persistence smoke after a physical iPhone became available. The first post-install trigger failed closed with `pushkit_token_upload_blocked_by_auth` before session restoration and did not upload. After normal app launch restored the session, the DEBUG/manual smoke reached redacted `pushkit_token_upload_result=http_success`, `pushkit_token_registration_result=registered`, `pushkit_token_server_store_requested=true`, `pushkit_token_server_store_result=persisted`, `pushkit_token_retrieval_internal_check=redacted_match`, and `pushkit_token_api_exposes_raw_token=false`.

The raw token was not printed, logged, copied into docs, persisted locally on iOS, returned by API, recorded, or committed. Token retrieval remains internal-only.

No iOS local token persistence, standard APNs token request, APNs provider request, server VoIP push delivery, real PushKit/background callback wiring into call flow, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or default startup registration was introduced.

## 2.44A Controlled Physical PushKit Token Upload Smoke

2.44A validates a real PushKit token upload only in a controlled physical DEBUG/manual smoke path:

- Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.
- A physical iPhone was available; Debug build, install, and launch succeeded with the current `M639Y9MFR2` signing state.
- The first launch-triggered smoke attempt failed closed before session restoration with redacted `pushkit_token_upload_blocked_by_auth`; it did not request PushKit registration or upload.
- A later manual trigger after session restoration received a PushKit token and uploaded it once to the public staging token-registration endpoint.
- Redacted proof reached `pushkit_token_received=true`, `pushkit_token_redacted=true`, `pushkit_token_upload_requested=true`, `pushkit_token_upload_result=http_success`, and `pushkit_token_registration_result=registered`.
- Redacted proof kept `pushkit_token_local_persistence_requested=false`, `pushkit_token_server_store_requested=false`, `pushkit_token_server_store_result=not_persisted`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, and `real_pushkit_background_callback_wired=false`.

The raw PushKit token was never printed, logged, copied into docs, persisted locally, durably stored by the server, recorded, or committed. No standard APNs token request, APNs provider request, server VoIP push delivery, real PushKit/background callback wiring into call flow, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or default startup registration was introduced.

The next safe step is token storage/invalidation contract design with fake-token and redaction tests first. Do not move directly to server VoIP push delivery.

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

## 2.43Z Public Token Route Proxy Smoke

2.43Z exposed and validated the public staging token route.

Evidence:

- Localhost token registration remained unauthenticated `401`.
- Public token registration changed from unauthenticated `404` to `401`.
- Public `dev/invite=404`, unauthenticated non-dev invite `401`, and unauthenticated stream `401` remained intact.
- The public reverse proxy token route was mapped to the same `salemx-call-service` upstream used by foreground signaling.
- nginx syntax validation passed, nginx was reloaded, and nginx active status was verified after reload.
- Synthetic-token public staging registration passed with client `pushkit_token_upload_result=http_success` and server `pushkit_token_registration_result=registered`.
- Server proof kept `pushkit_token_store_requested=false`, `pushkit_token_store_result=not_persisted`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.

No real PushKit/APNs token was used, logged, persisted, uploaded, or recorded. No APNs provider request, VoIP push delivery, real PushKit/background callback wiring, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, or `app.yml` regeneration was introduced.

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

Resumed 2.43W after SSH auth recovery:

- SSH publickey auth on port `71` succeeded.
- Local pre-deploy compileall passed.
- Local server tests passed: `139 passed`.
- Runtime files `app.py` and `pushkit_tokens.py` were copied to staging.
- Remote compileall for `salemx_call_service` passed.
- Restarting only `salemx-call-service` was blocked by service restart authorization.
- Redacted blocker: `staging_deploy_blocked_by_restart_auth`.
- Direct `salemx-call-service active` status was verified, but it is still the pre-restart process.
- Live route checks remain `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

No synthetic-token staging smoke was run because unauthenticated token registration is still `404`.

## 2.43X Staging Service Restart Activation Smoke

2.43X attempted to activate the already-copied 2.43Q/2.43R runtime files by restarting only `salemx-call-service`.

Evidence:

- SSH access on port `71` still works.
- Direct `systemctl is-active salemx-call-service` returned `active`.
- Direct `systemctl restart salemx-call-service` is blocked by interactive authentication.
- `sudo -n systemctl restart salemx-call-service` is blocked because sudo requires a password.
- Redacted blocker: `staging_restart_blocked_by_sudo_password_required`.

No restart, additional deploy, synthetic-token staging smoke, server environment change, or route activation was performed. Live route checks remain:

```text
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
unauthenticated token registration=404
```

The token route remains inactive because the service process has not loaded the copied runtime files.

## 2.43Y Staging Token Endpoint Post-Restart Smoke

2.43Y verified the manually restored restart/status path and checked route activation.

Evidence:

- Narrow sudo restart/status access for `salemx-call-service` was added manually before this phase.
- Direct service active status after restart is verified.
- Staging localhost route checks show unauthenticated token registration returns `401`, so the service process has loaded the endpoint and it is auth-gated locally.
- Public live route checks still show unauthenticated token registration returns `404`.
- Redacted blocker: `staging_token_registration_route_still_missing_after_restart`.

No synthetic-token staging smoke was run because the public token route remains `404`. Public route checks remain:

```text
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
unauthenticated token registration=404
```

The next required staging step is public reverse-proxy/path mapping for the token route, not iOS code or server app code.

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

## 2.44C1 readiness update

Ready:
- physical PushKit token upload works
- server-side token persistence works
- internal redacted token retrieval works
- public APNs sandbox send control route is auth-gated
- APNs control can find the persisted PushKit token

Not ready yet:
- APNs VoIP topic is unresolved
- APNs credentials are unavailable
- sandbox VoIP push send has not been attempted
- PushKit background callback is not wired into call flow
- CallKit is not wired from PushKit
- media is not connected

## 2.44D readiness update

Ready:
- server can locate the persisted PushKit token
- server APNs credentials are configured
- server resolves the sandbox VoIP topic
- server builds the sandbox VoIP payload
- server reaches the APNs provider boundary

Not ready yet:
- real APNs HTTP/2 provider is not implemented
- sandbox_success has not been achieved
- physical iPhone VoIP push receipt has not been proven
- PushKit background callback remains unwired
- CallKit remains unwired from PushKit

## 2.44E readiness update

Ready:
- real controlled APNs VoIP sandbox HTTP/2 provider is implemented
- sandbox-only environment is enforced
- APNs provider JWT creation is server-side and redacted
- APNs response handling returns only safe status/failure classes
- physical Debug app upload smoke uses lowercase hex token upload
- real PushKit token upload returned http_success / registered
- server token persistence returned persisted
- internal retrieval returned redacted_match
- public route safety remains intact

Not ready yet:
- token-store format inspection needs approved redacted server-side access
- authenticated APNs dry-run needs a matching Matrix access token for the same staging identity
- real APNs sandbox send was not attempted in 2.44E
- sandbox_success has not been achieved
- physical iPhone VoIP push receipt has not been proven
- PushKit background callback remains unwired
- CallKit remains unwired from PushKit
- media credentials and media connection remain untouched

## 2.44E1 readiness update

Still blocked:
- redacted token-store format inspection needs an approved non-interactive path
- APNs control invocation needs a matching Matrix access token for the same staging identity
- APNs dry-run has not run
- real APNs sandbox send has not been attempted

Still safe:
- public route safety remains intact
- no production APNs push was attempted
- no repeated push was attempted
- PushKit background callback remains unwired
- CallKit remains unwired from PushKit
- media credentials and media connection remain untouched

## 2.44E2 readiness update

Still blocked:
- operator did not provide the matching Matrix access token to the hidden terminal prompt in this run
- APNs dry-run has not run
- real APNs sandbox send has not been attempted

Still safe:
- public route safety remains intact
- no production APNs push was attempted
- no repeated push was attempted
- PushKit background callback remains unwired
- CallKit remains unwired from PushKit
- media credentials and media connection remain untouched

## 2.44E2 readiness update

Ready:
- real APNs VoIP sandbox HTTP/2 provider
- persisted PushKit token lookup
- APNs sandbox credentials/topic
- controlled sandbox VoIP push send path

Next:
- prove physical iPhone receives the VoIP push
- prove PushKit background callback is invoked
- then plan CallKit reporting from PushKit callback

Still not wired:
- PushKit background callback into call flow
- CallKit report from PushKit
- media credentials/media connection

## 2.45A readiness update

Ready:
- APNs dry-run is green against the persisted staging PushKit token
- exactly one controlled sandbox VoIP push send returned sandbox_success
- physical iPhone PushKit receipt proof is green for the redacted sandbox_voip_smoke payload
- PushKit completion is called promptly

Still not wired:
- PushKit receipt into full call flow
- CallKit report from PushKit
- media credentials/media connection
- Matrix event emission from PushKit receipt

Safety:
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, or raw payload recorded

## 2.45B readiness update

Ready:
- APNs dry-run remains green against the persisted staging PushKit token
- exactly one controlled sandbox VoIP push send returned sandbox_success
- physical iPhone PushKit receipt proof is green for the redacted sandbox_voip_smoke payload
- PushKit completion is called promptly
- controlled synthetic CallKit report from the PushKit callback returned reported

Still not wired:
- PushKit receipt into full direct-call flow
- media credentials/media connection
- Matrix event emission from PushKit receipt

Safety:
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw payload, user ID, device ID, room ID, or call handle recorded

## 2.45C readiness update

Ready:
- DEBUG-only CallKit answer action proof path exists
- answer action fulfillment can be recorded with redacted fields only
- targeted DirectCall tests, SwiftFormat, and changed-file SwiftLint passed
- route safety remains intact

Blocked:
- fresh physical PushKit upload smoke returned `pushkit_token_upload_http_failure`
- authenticated APNs dry-run returned HTTP 401
- real sandbox APNs send was skipped
- physical CallKit answer action proof was not observed

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw payload, user ID, device ID, room ID, or call handle recorded

## 2.45C1 readiness update

Ready:
- DEBUG-only PushKit completion ordering fix exists
- controlled CallKit report result is recorded before PushKit completion is recorded/called
- targeted DirectCall tests, SwiftFormat, and changed-file SwiftLint passed
- route safety remains intact

Blocked:
- fresh physical PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- APNs dry-run was not run
- real sandbox APNs send was not attempted
- physical CallKit answer action proof was not observed

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw payload, user ID, device ID, room ID, or call handle recorded

## 2.45C physical verification readiness update

Ready:
- authenticated physical PushKit token upload smoke returned http_success / registered / persisted / redacted_match
- APNs dry-run returned HTTP 200 and dry_run with no blocker
- exactly one real sandbox APNs send returned sandbox_success
- physical iPhone proof showed PushKit callback, controlled CallKit report, PushKit completion, CallKit answer action received/fulfilled, and app activation observed

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw payload, user ID, device ID, room ID, or call handle recorded

## 2.45D readiness update

Ready:
- authenticated physical PushKit token upload smoke returned http_success / registered / persisted / redacted_match
- APNs dry-run returned HTTP 200 and dry_run with no blocker
- exactly one real sandbox APNs send returned sandbox_success
- physical iPhone proof showed PushKit callback, controlled CallKit report, PushKit completion, CallKit answer action received/fulfilled, app activation observed, and controlled in-app screen presented

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw payload, user ID, device ID, room ID, or call handle recorded

## 2.46A readiness update

Ready:
- authenticated non-dev real invite route can request one background sandbox APNs push using the persisted receiver PushKit token
- iPhone PushKit proof recognizes the redacted `real_invite_controlled` payload mapping
- controlled CallKit report returns `reported`

Blocked:
- CallKit Answer action was not observed for the real-invite controlled payload in the single allowed physical push
- controlled in-app activation/screen proof did not run for this payload

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- dev invite remains disabled
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, or call handle recorded

## 2.47A9 readiness update

Ready:
- local DEBUG-only CallKit-only proof can report an incoming call and receive Answer first
- local proof returned `local_callkit_only_report_result=reported`, `local_callkit_only_first_action_kind=answer`, and `local_callkit_only_answer_action_delivered=true`
- generic CallKit configuration, provider/delegate retention, and action delivery are not the blocker

Blocked:
- one background real non-dev invite/APNs comparison still delivered `callkit_first_action_kind=end`
- timing bucket was `>2000ms`
- app-side local End request, provider invalidation, report-ended, and controlled timeout before Answer were false
- current blocker remains `system_or_user_end_before_answer`

Do not move to media until the background PushKit/real-invite CallKit surface delivers `callkit_first_action_kind=answer`.

Still not wired:
- real media credential request
- media connection
- LiveKit join
- Matrix event emission
- full direct-call flow

Safety:
- no production APNs push
- no repeated APNs push
- no `dev/invite`
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, call handle, LiveKit URL/token, private log, or secret-bearing URL recorded

## 2.46B Readiness Update

Ready:
- real non-dev invite background APNs reaches `real_invite_controlled` PushKit receipt, controlled CallKit report, Answer action, controlled in-app screen, controlled cleanup, and redacted foreground pending-call state
- foreground pending-call proof records `foreground_call_state=real_invite_pending_media`
- foreground state source is `callkit_answer_real_invite_controlled`
- state payload remains redacted and records only stable redacted correlation presence

Verified:
- receiver PushKit upload smoke returned http_success / registered / persisted / redacted_match
- route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, stream `401`, token registration `401`, and APNs send control `401`
- exactly one authenticated non-dev invite/APNs attempt was run; dev invite was not used
- iPhone proof returned `foreground_call_state_handoff_requested=true`, `foreground_call_state_handoff_observed=true`, `foreground_call_state_payload_redacted=true`, `foreground_call_state_has_stable_redacted_correlation=true`, and `blocked_reason=none`

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, or call handle recorded

## 2.47A Readiness Update

Ready:
- controlled DEBUG proof reaches a planner-only media credentials boundary after the real-invite foreground pending state
- proof records `media_credentials_result=planned_redacted`
- proof records token, URL, and payload redaction booleans without requesting or exposing credentials
- media connect, LiveKit join, Matrix events, and full direct-call flow remain false

Verified:
- changed-file SwiftFormat passed
- changed-file SwiftLint passed with 0 violations
- targeted DirectCall tests passed with 37 tests
- physical Debug build/install passed
- route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, stream `401`, token registration `401`, and APNs send control `401`

Blocked:
- physical close-out stopped before APNs because PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`

Safety:
- no production APNs push
- no repeated APNs push
- no raw LiveKit token, LiveKit URL, PushKit token, APNs token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, or call handle recorded

## 2.46A1 readiness update

Ready:
- controlled synthetic CallKit proof now ends and clears its controlled call after Answer proof
- cleanup is DEBUG-only and limited to the synthetic proof surface
- changed-file SwiftFormat, changed-file SwiftLint, targeted DirectCall tests, and physical Debug build/install passed

Blocked:
- receiver PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- real non-dev invite/APNs retry was not run

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- dev invite remains disabled
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, or call handle recorded

## 2.46A3 readiness update

Ready:
- real-invite-controlled PushKit receipt can no longer remain permanently pending without PushKit completion
- controlled CallKit report result is finalized as reported, failed_redacted, or timeout_redacted
- timeout fallback records only redacted blocker state and still calls PushKit completion
- dedicated VoIP receipt proof remains separate from upload smoke proof
- changed-file SwiftFormat, changed-file SwiftLint, targeted DirectCall tests, and physical Debug build/install passed

Blocked:
- receiver PushKit upload smoke returned `pushkit_token_upload_blocked_by_auth`
- real non-dev invite/APNs retry was not run after the fix

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- dev invite remains disabled
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, or call handle recorded

## 2.46A4 readiness update

Ready:
- real non-dev invite background APNs now reaches `real_invite_controlled` PushKit receipt, controlled CallKit report, Answer action, controlled in-app screen, and controlled cleanup
- cleanup ordering is guarded so pre-Answer end events do not overwrite the waiting-for-Answer proof
- dedicated VoIP receipt proof remains separate from PushKit upload proof

Verified:
- receiver PushKit upload smoke returned http_success / registered / persisted / redacted_match
- exactly one authenticated non-dev invite/APNs attempt was run; dev invite was not used
- iPhone proof returned `callkit_report_result=reported`, `pushkit_completion_called=true`, `callkit_answer_action_received=true`, `callkit_answer_action_fulfilled=true`, `controlled_in_app_screen_presented=true`, `controlled_in_app_screen_source=callkit_answer_real_invite_controlled`, and `controlled_callkit_cleanup_result=ended`

Still not wired:
- media credentials/media connection
- Matrix event emission
- full direct-call flow

Safety:
- dev invite remains disabled
- no production APNs push
- no repeated APNs push
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, or call handle recorded

## 2.47A17 readiness update

The current blocker is before CallKit/media: APNs sandbox accepted a real-invite VoIP push using the same fresh development token uploaded by the iPhone, but the SalemX VoIP receipt proof did not record a PushKit callback.

Readiness findings:
- physical app entitlements/profile are consistent with sandbox VoIP delivery: bundle `kz.salemx.msg`, team `M639Y9MFR2`, `aps-environment=development`, and `voip` background mode
- upload smoke remains the precondition for fresh token storage
- source inspection shows the app-wide `ElementCallService` owns a startup `.voIP` registry, while the SalemX debug registry is upload-smoke scoped

Next proof:
- DEBUG-only Element Call detector will prove whether the startup registry receives SalemX `salemx_direct_call` payloads
- if it does, the dedicated VoIP proof records `element_call_pushkit_registry_intercepted_salemx_payload`
- if neither proof updates after a single sandbox_success APNs, the blocker remains APNs accepted but physical callback not observed

Safety:
- no APNs was sent for this diagnostic change
- no production APNs, repeated APNs, real media credentials request, media connect, LiveKit join, Matrix event emission, or full direct-call flow was introduced
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, call handle, LiveKit URL, or private log recorded

## 2.47A readiness close-out

Ready:
- real non-dev invite/APNs now reaches SalemX VoIP receipt, CallKit report, Answer action, foreground pending-call handoff, and planner-only media credentials boundary
- dedicated proof returned `callkit_first_action_kind=answer`, `foreground_call_state=real_invite_pending_media`, `media_credentials_boundary_reached=true`, and `media_credentials_result=planned_redacted`
- the startup Element Call detector stayed false in the passing path: `element_call_pushkit_callback_invoked=false`

Still not wired:
- real media credentials request
- media connection
- LiveKit join
- Matrix event emission
- full direct-call flow

Safety:
- no further APNs was sent after the passing proof
- no production APNs, repeated APNs, real media credentials request, media connect, LiveKit join, Matrix event emission, or full direct-call flow was introduced
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, call handle, LiveKit URL, or private log recorded

## 2.47B readiness update

Ready:
- real non-dev invite/APNs still reaches SalemX VoIP receipt, CallKit report, Answer action, controlled in-app screen, and foreground pending-call handoff
- the controlled media credentials lifecycle now records a safe blocked request boundary rather than planner-only success
- proof records `media_credentials_boundary_reached=true`, `media_credentials_request_planned=false`, `media_credentials_requested=false`, `media_credentials_request_authorized=false`, `media_credentials_result=blocked_redacted`, `media_credentials_token_received=false`, `media_credentials_token_redacted=true`, `media_credentials_url_received=false`, `media_credentials_url_redacted=true`, `media_credentials_payload_redacted=true`, `media_credentials_local_persistence_requested=false`, `media_credentials_cleanup_requested=false`, and `media_credentials_cleanup_result=not_requested`

Current blocker:
- `media_credentials_request_boundary_not_ready`
- the proof path has not yet handed the existing media token endpoint its required raw request metadata through a safe internal foreground state

Still not wired:
- real media credentials request
- media connection
- LiveKit join
- Matrix event emission
- full direct-call flow

Safety:
- no APNs was sent after the passing proof
- no production APNs, repeated APNs, real media credentials request, media connect, LiveKit join, Matrix event emission, or full direct-call flow was introduced
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, call handle, LiveKit URL, or private log recorded

## 2.47B2 readiness update

Ready:
- foreground pending-call metadata can now be handed to the existing media credentials/token boundary through a DEBUG-only controlled request
- success proof will record `media_credentials_requested=true`, `media_credentials_request_authorized=true`, `media_credentials_result=success_redacted`, token/URL received booleans, redaction booleans, no local persistence, and cleanup cleared
- blocked proof remains redacted as `blocked_redacted`
- token request/response descriptions redact call ID, room ID, peer/user metadata, token, URL, and allocation identifiers

Still not wired:
- media connection
- LiveKit join
- microphone/camera request
- Matrix event emission
- full direct-call flow

Safety:
- no APNs was sent for this code checkpoint
- no production APNs or repeated APNs was introduced
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, call ID, call handle, LiveKit URL/token, or private log recorded
- forbidden project/signing/entitlement/`Info.plist`/`app.yml` files remain untouched

## 2.47B4 readiness update

Ready:
- real non-dev invite can now create an authenticated pending metadata source for the PushKit-controlled Answer path
- server stores real call/room/peer metadata behind an opaque reference
- VoIP APNs payload carries only the opaque metadata reference and redaction proof
- authenticated fetch is receiver/device-bound and expires with the invite
- iOS receipt proof records pending metadata reference/fetch booleans without raw metadata

Still not wired:
- iOS does not yet fetch pending metadata after Answer
- real media credentials request remains blocked until fetched metadata is handed to the existing credentials boundary
- media connection, LiveKit join, microphone/camera request, Matrix event emission, and full call flow remain disabled

Safety:
- no APNs was sent for this code checkpoint
- no production APNs or repeated APNs was introduced
- no raw token, APNs key, JWT, authorization header, Matrix access token, raw APNs payload, raw invite body, user ID, device ID, room ID, call ID, call handle, LiveKit URL/token, or private log recorded
- forbidden project/signing/entitlement/`Info.plist`/`app.yml` files remain untouched
