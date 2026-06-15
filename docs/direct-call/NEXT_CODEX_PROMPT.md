# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.44a-controlled-physical-pushkit-token-upload-smoke`

Next phase: continue after controlled physical PushKit token upload passed. Do not move to VoIP push delivery yet. The next safe step should define durable token storage/invalidation with fake-token and redaction tests first.

## Baseline

Foreground real-invite baseline:

```text
e7b9428db20892a3e3cb27c15933b786883757f4 Consolidate foreground token guard baseline
bf9996ae0665ad3953fac3d7a838bfb619349dd1 Validate foreground real invite token guard smoke
26e520b6f6ec0220ce118051f5acac36ed40bfba Guard debug foreground smoke surface
```

PushKit/background preparation chain:

```text
5fa4d24e288273bcc824496ec4276777d3893280 Document PushKit APNs background call investigation
9e76108e096d90f0586047c4d017cb699fae3a05 Add background invite payload contract
9cd5279ffd1a32898568a25cdded380404d09fcc Add background invite intake seam
fc2881eea7ee2f1398d66ce325c7caee956d3db7 Add background CallKit reporting seam
0ac6a1c86d6315205b3bcf49a42877feb0f5180d Add background CallKit adapter boundary
e8ae7be8d13c93d57ec414dd472e19fd93dfb5f0 Add controlled real CallKit adapter
3266e567f7ff2ff4a6839e5d79794e077658cd9a Add PushKit lifecycle abstraction seam
ac0fa9ef32333fce7bfc3685a5088ef64a33323a Document PushKit readiness plan
0862f4ad00538658e73fe87f5515d49079fe542e Add gated PushKit registrar scaffold
6d78104ab4a13a2df58a5c6171b84383a3bd754b Document PushKit capability readiness verification
f8ad35ee1130b2a9eae6a7db8dfa9f8bb7242e66 Document PushKit entitlement change proposal
adbabef9c1866a82c5e5e3b4ca787a510b3a98b4 Apply minimal PushKit capability files
11f64583b8be7aa505e3e7014f5fb7d2edc5927d Validate PushKit capability build profile
a12fb1f3206ce2e9cc68205d3995a983643c7503 Validate physical install capability state
2823ae0ad3227c061c0ab3e2bf695075edac5ebf Validate controlled local PushKit registration smoke
6c2f44b21a9b38a78a7a19f1f918534ae741e44f Add PushKit token registration contract
5b6312451f9569f536cef05db25038d96926f603 Add server PushKit token registration contract
42e4e466eccb784b67e002c60dbdb742c8eae745 Validate fake-token PushKit registration smoke
63abcf838b030a480ef1a3b5c855db41cb2df371 Validate public token route proxy smoke
```

## 2.43S Result

2.43S attempted staging deployment and smoke for the token-registration endpoint:

- Pre-deploy server tests passed: `139 passed`.
- Python compileall passed.
- Staging deploy was blocked before any deployment by SSH timeout.
- Redacted blocker: `staging_deploy_blocked_by_ssh_timeout`.
- Live staging token registration still returns `404`, so no staging synthetic-token pass is claimed.

No real PushKit token was used. No raw PushKit/APNs token is logged, durably persisted, uploaded from actual PushKit runtime, recorded, documented, or committed. No APNs registration is requested. No real PushKit/background callback is wired. No server VoIP push delivery, media credentials, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or production background behavior was introduced.

## 2.43T Result

2.43T investigated staging deploy access:

- Tracked repo docs/scripts document local staging harnesses and route-level smokes, but no complete remote deployment recipe was found.
- The local SSH configuration contains a staging deploy alias using a non-standard SSH port.
- The configured identity file is present.
- Bounded connectivity checks to both the configured alias port and port 22 failed before authentication or host-key negotiation.
- A bounded SSH probe through the configured alias timed out before `systemctl` could run.
- Redacted blocker remains `staging_deploy_blocked_by_ssh_timeout`.
- No server deployment, restart, synthetic-token staging smoke, environment-variable change, or route activation was performed.
- Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
- Direct `salemx-call-service active` status is not verified.

## 2.43U Result

2.43U retried the staging deploy access validation with the corrected SSH port:

- The staging SSH alias resolves to port `71`.
- Port `22` is not the primary deploy check for this environment.
- A bounded port `71` connectivity check failed before authentication or host-key negotiation.
- A bounded SSH probe through the alias timed out before `systemctl` could run.
- Redacted blocker: `staging_deploy_blocked_by_firewall_or_network_path`.
- No server deployment, restart, synthetic-token staging smoke, environment-variable change, or route activation was performed.
- Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
- Direct `salemx-call-service active` status is not verified.

## 2.43V Result

2.43V prepared a manual deployment package/runbook only:

- Added `docs/direct-call/PUSHKIT_STAGING_MANUAL_DEPLOY_RUNBOOK.md`.
- The package lists runtime files `server/salemx-call-service/salemx_call_service/app.py` and `server/salemx-call-service/salemx_call_service/pushkit_tokens.py`.
- The package lists `server/salemx-call-service/tests/test_service.py` as the validation test file.
- The runbook covers safe manual deployment options, pre-deploy checks, post-deploy route checks, synthetic-token staging proof, forbidden data, rollback, and next prompt choices.
- No server deployment, restart, live smoke, environment-variable change, or route activation was performed.
- Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
- Direct `salemx-call-service active` status is not verified.

## 2.43W Result

2.43W retried staging deploy after manual fail2ban unban:

- The staging SSH alias resolves to port `71`.
- Bounded port `71` connectivity is now open.
- A bounded SSH probe reached authentication but was rejected before any remote command could run.
- Redacted blocker: `staging_deploy_blocked_by_auth`.
- No server deployment, restart, synthetic-token staging smoke, environment-variable change, or route activation was performed.
- Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
- Direct `salemx-call-service active` status is not verified.

Resumed 2.43W after SSH auth recovery:

- SSH publickey auth on port `71` succeeded.
- Local compileall passed.
- Local server tests passed: `139 passed`.
- Runtime files `app.py` and `pushkit_tokens.py` were copied to staging.
- Remote compileall for `salemx_call_service` passed.
- Restarting only `salemx-call-service` was blocked by service restart authorization.
- Redacted blocker: `staging_deploy_blocked_by_restart_auth`.
- Direct `salemx-call-service active` status was verified, but it is still the pre-restart process.
- Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.
- Synthetic-token staging smoke was not run.

## 2.43X Result

2.43X attempted to activate the copied runtime files:

- SSH access on port `71` still works.
- Direct `systemctl is-active salemx-call-service` returned `active`.
- Direct `systemctl restart salemx-call-service` is blocked by interactive authentication.
- `sudo -n systemctl restart salemx-call-service` is blocked because sudo requires a password.
- Redacted blocker: `staging_restart_blocked_by_sudo_password_required`.
- No restart, additional deploy, synthetic-token staging smoke, environment-variable change, or route activation was performed.
- Live route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

## 2.43Y Result

2.43Y verified post-restart route state:

- Narrow sudo restart/status access for `salemx-call-service` was added manually before the phase.
- Direct service active status after restart is verified.
- Staging localhost token registration returns unauthenticated `401`, so the endpoint is active and auth-gated inside the service process.
- Public staging token registration still returns unauthenticated `404`.
- Redacted blocker: `staging_token_registration_route_still_missing_after_restart`.
- Synthetic-token staging smoke was not run.
- Public route status remains `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `404`.

## 2.43Z Result

2.43Z fixed public token route exposure and ran synthetic-token staging registration:

- Staging localhost token registration remained unauthenticated `401`.
- Public staging token registration changed from unauthenticated `404` to `401`.
- Public `dev/invite=404`, unauthenticated non-dev invite `401`, and unauthenticated stream `401` remained intact.
- The public reverse proxy token route was mapped to the same `salemx-call-service` upstream used by foreground signaling.
- nginx syntax validation passed, nginx was reloaded, and nginx active status was verified after reload.
- Synthetic-token public staging registration passed.
- Client proof reached `pushkit_token_registration_invoked=true`, `pushkit_token_present=true`, `pushkit_token_upload_requested=true`, `pushkit_token_persistence_requested=false`, `pushkit_token_upload_result=http_success`, `apns_registration_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
- Server proof reached `pushkit_token_registration_invoked=true`, `pushkit_token_present=true`, `pushkit_token_store_requested=false`, `pushkit_token_store_result=not_persisted`, `pushkit_token_registration_result=registered`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, and `matrix_event_emit_requested=false`.
- No real PushKit/APNs token was used, logged, persisted, uploaded, or recorded.

## 2.44A Result

2.44A ran a controlled physical-device PushKit token upload smoke:

- Public route safety remained `dev/invite=404`, unauthenticated non-dev invite `401`, unauthenticated stream `401`, and unauthenticated token registration `401`.
- Physical device availability, Debug build, install, and launch were verified with the current `M639Y9MFR2` signing state.
- PushKit registration and upload were invoked only through explicit DEBUG/manual smoke controls, not app startup or normal runtime.
- A real PushKit VoIP token was received and uploaded once to the public staging token-registration endpoint.
- The raw token was never printed, logged, copied into docs, persisted locally, durably stored by the server, recorded, or committed.
- Redacted proof reached `physical_device_available=true`, `pushkit_registration_manual_invoked=true`, `pushkit_token_received=true`, `pushkit_token_redacted=true`, `pushkit_token_upload_requested=true`, `pushkit_token_upload_result=http_success`, and `pushkit_token_registration_result=registered`.
- Redacted proof kept `pushkit_token_local_persistence_requested=false`, `pushkit_token_server_store_requested=false`, `pushkit_token_server_store_result=not_persisted`, `voip_push_send_requested=false`, `apns_provider_requested=false`, `media_credentials_requested=false`, `media_connect_requested=false`, `matrix_event_emit_requested=false`, and `real_pushkit_background_callback_wired=false`.
- No standard APNs token request, APNs provider request, server VoIP push delivery, real PushKit/background callback wiring, media credential request, media connection, Matrix event emission, Element Call route replacement, entitlement/project/signing/`Info.plist` change, `app.yml` regeneration, or production startup registration was introduced.

## Suggested Next Task

Start:

- `2.44B - PushKit token storage/invalidation contract`

Goal: define durable server token storage and invalidation semantics with fake-token tests and strict redaction before any VoIP push delivery work.

The next task must keep separate:

- server token storage/invalidation contract
- provider credential readiness
- later VoIP push delivery smoke

Do not proceed with durable real-token persistence, provider push delivery, or background payload callback wiring unless that authorization is explicit.

Required guardrails:

- Do not wire PushKit registration to app startup by default.
- Do not request an APNs token unless separately scoped.
- Do not persist, upload, print, log, document, or commit raw PushKit/APNs tokens.
- Do not upload another real PushKit token unless the task explicitly authorizes it.
- Do not send a server VoIP push yet.
- Do not use `dev/invite`, `dev/inject-active`, port `8090`, or `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1`.
- Do not request media credentials or connect media.
- Do not emit Matrix events from invite receipt.
- Do not change Element Call route replacement logic.
- Do not regenerate the project from `app.yml`.
- Do not edit entitlement, `Info.plist`, project, signing, or provisioning files unless separately authorized.

Required route-level server safety:

- `dev/invite=404`
- unauthenticated non-dev invite `401`
- unauthenticated stream `401`
- unauthenticated token registration `401`

Only claim direct `salemx-call-service active` if `systemctl` or an equivalent direct service check is actually verified. If SSH is blocked or times out, report it separately from route-level safety.

## Do-Not-Touch Constraints

- Do not stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.
- Do not log raw tokens, raw identifiers, request payloads, private logs, or secret-bearing URLs.
- Do not use old Team ID `83LGSC2QPV`; physical Debug work must use `M639Y9MFR2`.
