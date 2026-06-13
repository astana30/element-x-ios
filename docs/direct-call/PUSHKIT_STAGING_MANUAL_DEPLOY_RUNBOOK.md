# PushKit Staging Manual Deploy Runbook

Status: 2.43V prepares a manual deployment package and operator runbook only. Normal SSH deploy remains blocked by the network/firewall path, and no staging deploy or live smoke is performed by this document.

## 1. Current Blocker

Staging deployment is blocked by:

```text
staging_deploy_blocked_by_firewall_or_network_path
```

The expected staging SSH port for this environment is `71`. Port `22` is not the primary deploy path. The existing staging alias resolves to port `71`, but bounded connectivity and SSH probes still time out before authentication or host-key negotiation.

Live route state remains:

```text
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
unauthenticated token registration=404
```

Token registration is still `404` because the 2.43Q/2.43R server endpoint is not deployed to staging. Normal deploy cannot proceed until the network, VPN, firewall, or bastion path to the port `71` staging deploy endpoint is restored or replaced with an approved admin channel.

## 2. Server Files To Deploy

Deploy only the server-side token-registration endpoint changes from 2.43Q/2.43R.

Runtime files:

```text
server/salemx-call-service/salemx_call_service/app.py
server/salemx-call-service/salemx_call_service/pushkit_tokens.py
```

Test file:

```text
server/salemx-call-service/tests/test_service.py
```

The test file is included in this package manifest so an operator can run the exact validation suite, but it is not required at runtime unless the staging host keeps tests with the deployment checkout.

Do not deploy iOS project files, entitlement files, `Info.plist`, signing settings, `app.yml`, media code, or Element Call route replacement changes as part of this package.

## 3. Manual Deployment Options

Allowed recovery options:

- Restore SSH/VPN/firewall access to the existing staging deploy path on port `71`.
- Use an approved provider console, bastion, or admin channel that can update only `server/salemx-call-service`.
- Manually copy the changed server files listed above, or deploy a reviewed artifact containing only the call-service server changes.
- Rebuild/restart only `salemx-call-service`.

Forbidden during this package deploy:

- Do not touch iOS project files.
- Do not modify live server environment variables unless a separate task explicitly requires and documents it.
- Do not enable dev routes.
- Do not enable `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1`.
- Do not use port `8090`.
- Do not deploy unrelated app, media, signing, provisioning, or Element Call changes.

## 4. Pre-Deploy Checks

Run from the repository before packaging or copying files:

```bash
cd /Users/aibattt/Movies/element-x-ios/server/salemx-call-service
.venv/bin/python -m pytest tests/test_service.py
.venv/bin/python -m compileall salemx_call_service tests
cd /Users/aibattt/Movies/element-x-ios
git diff --check
```

Run a privacy scan over changed files and operator notes. Confirm no raw token, authorization value, private SSH material, user identifier, device identifier, room identifier, call handle, request payload, private log, or secret-bearing URL is present.

## 5. Post-Deploy Route Checks

After deploying and restarting only `salemx-call-service`, verify live route safety:

```text
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
unauthenticated token registration=401
```

Interpretation:

- `401` for unauthenticated token registration means the endpoint is deployed and auth-gated.
- `404` for unauthenticated token registration means the endpoint is still not deployed or the reverse proxy does not route it.
- Do not run synthetic-token staging smoke until unauthenticated token registration is `401`.

Only claim direct service-active status if `systemctl` or an equivalent direct service check actually succeeds.

## 6. Synthetic-Token Smoke After Deploy

Run this only after the route checks are correct.

Use a synthetic/fake token only. Do not use a real PushKit token.

Required redacted proof:

```text
pushkit_token_registration_invoked=true
pushkit_token_present=true
pushkit_token_upload_requested=true
pushkit_token_persistence_requested=false
pushkit_token_upload_result=http_success
pushkit_token_registration_result=registered
voip_push_send_requested=false
apns_provider_requested=false
media_credentials_requested=false
media_connect_requested=false
matrix_event_emit_requested=false
```

No server VoIP push delivery, APNs provider call, media credential request, media connection, Matrix event emission, real PushKit/background callback wiring, or real app-runtime token upload is part of this smoke.

## 7. Forbidden Data

Do not log, paste, document, commit, or retain:

```text
raw PushKit token
raw APNs token
access token
authorization header
user ID
device ID
room ID
recipient
call handle
request payload
private logs
secret-bearing URL
private SSH key
```

Reports should use only redacted status classes and route status codes.

## 8. Rollback

If deployment causes unexpected behavior:

- Restore the previous server files or previous reviewed deployment artifact.
- Restart only `salemx-call-service`.
- Confirm token registration returns the expected previous behavior, or confirm route removal was intentional.
- Confirm foreground route safety still holds:

```text
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
```

No iOS rollback is needed unless unrelated iOS changes were deployed, which this runbook forbids.

## 9. Next Prompt

The next task should be one of:

- `2.43W - staging deploy using restored access`, if network/VPN/firewall/bastion access is restored but the endpoint is not deployed yet.
- `2.43W - synthetic-token staging registration smoke after manual deploy`, if an operator manually deploys the endpoint and unauthenticated token registration returns `401`.

The next task must not move to VoIP push delivery. It should not use real PushKit tokens, persist tokens, request APNs tokens, send server VoIP pushes, or wire real PushKit/background callbacks unless a later prompt explicitly authorizes that exact scope.
