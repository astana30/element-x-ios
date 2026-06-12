# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.42l-foreground-real-invite-token-guard`

Next phase: foreground real invite production configuration boundary.

## Context

- 2.42I passed and was committed as `a4d427f5b07e662695ce108530bbafc9bfdd9399` (`Validate supervised foreground SSE smoke`).
- 2.42J guardrails were committed as `c2fbc505dad52be2413d16fa23c55f9f7594632f` (`Harden supervised foreground SSE guardrails`).
- 2.42K passed and was committed as `00b7db4db914eed61bb45cc51fff7082d15da323` (`Validate supervised foreground real invite`).
- 2.42K proved the authenticated non-dev route `POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite` can deliver a foreground `foreground.call.invite` from one foreground sender device to one foreground receiver device through SSE.
- The dev routes stayed disabled during the 2.42K real-invite smoke. Do not use `dev/invite`, `dev/inject-active`, or `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1` outside controlled dev-route smokes.
- 2.42L adds a DEBUG-only sender-helper stale-token guard. If the first real-invite POST returns `http_unauthorized`, the helper asks the active session token provider for a value again and retries at most once. Diagnostics remain redacted:
  - `sender_token_refresh_needed`
  - `sender_token_refresh_attempted`
  - `sender_token_refresh_succeeded`
  - `sender_invite_retry_requested`
  - `sender_invite_retry_status`
- Physical Debug builds should use local command-line signing overrides only:
  - `DEVELOPMENT_TEAM=M639Y9MFR2`
  - `CODE_SIGN_STYLE=Automatic`
  - `-allowProvisioningUpdates`
  - `-allowProvisioningDeviceRegistration`
- Do not use old Team ID `83LGSC2QPV`.
- Do not persist signing changes.

## Goal

Design the smallest safe non-DEBUG configuration boundary for foreground-only SSE startup while preserving all proven 2.42I-2.42L guardrails.

## Constraints

- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, `Info.plist`, `app.yml`, `project.yml`, or project settings.
- Do not replace Element Call routing.
- Do not hardcode production server URLs or credential values.
- Do not bypass server-issued media credential authority.
- Do not request media credentials from invite receipt.
- Do not connect media from invite receipt.
- Do not emit Matrix call events from invite receipt.
- Do not add raw account, room, device, event, credential, push/media, Apple signing, media-session, track, participant, private runtime log, request payload, call handle, or credential-shaped fixture values.

## Expected Work

1. Inspect the existing DEBUG foreground SSE owner, active-session request construction, authenticated non-dev invite route, and redacted diagnostics.
2. Propose or implement a disabled-by-default non-DEBUG configuration boundary for foreground-only SSE startup.
3. Keep app runtime startup explicit and gated; do not enable broad rollout by default.
4. Preserve fallback de-duplication, duplicate/stale/terminal guards, and server-issued media credential authority.
5. Preserve the sender stale-token retry diagnostics without exposing token values.
6. Add tests for disabled-by-default behavior, redacted diagnostics, no media credential request/connect on invite receipt, no Matrix event emission, and no dev-route dependency.
7. Update docs/status/worklog with redacted results only.

## Validation

- SwiftFormat on changed Swift files.
- SwiftLint on changed Swift files.
- Targeted direct-call / foreground SSE tests.
- Server tests only if server files change.
- Python compileall only if server files change.
- `git diff --check`.
- Forbidden changed-file scan.
- Privacy scan.

## Server Safety

Before and after work, confirm:

```text
salemx-call-service active
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
```
