# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.26B — controlled staging dogfood checklist updated.

Current checkpoints:
- App code: 2.23C `Polish native call listener availability status` (`bb7ae2557`).
- Backend staging preflight guardrails: 2.24B `Add call service staging preflight guardrails` (`c32f89fcc`).
- Allocation store guardrails: 2.24C `Add call service allocation store guardrails` (`69b56992a`).
- Rate limiting guardrails: 2.24D `Add call service rate limiting guardrails` (`ee7ea06ae`).
- FastAPI route test environment: 2.24E `Document call service full test environment` (`073c8da49`).
- Redis storage skeleton: 2.24G `Add Redis call service storage skeleton` (`98e153b7f`).
- Redis local integration smoke: 2.24H passed and is documented (`113945266`).
- Staging Synapse smoke harness: 2.24J-prep `Add staging Synapse smoke harness template` (`565699e15`).
- Staging deployment scaffold: 2.24K prepared helper scripts and placeholder-only env templates.
- Call-service LiveKit room pre-create: 2.25E implemented server-side RoomService `CreateRoom` before participant token issuance.
- Staging iOS activeAudio smoke: 2.25F passed after room pre-create.
- Controlled dogfood runbook: 2.26B updated gates, preflight, rollback, redaction, and session matrix.
- Private native audio dogfood guardrails: `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven/prepared state:
- Production native audio call core works through the DEBUG/integration/private product-gated path.
- Private native call card works behind `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- Existing Element Call phone/video buttons remain visible and unchanged.
- Manual private-card actions were proven: Start audio, Accept, Hang up, Decline incoming, Cancel outgoing, Retry, and Dismiss.
- Repeated calls, reverse-direction calls, backend-off recovery, LiveKit-off recovery, stale media failure cleanup, rapid terminal actions, timeout, and relaunch fail-closed behavior are runtime-proven.
- Production Matrix SDK key envelope wrapping is integrated through a narrow provider seam and preserves `OnlyTrustedDevices` policy.
- Listener/owner lifecycle is fail-closed with `productionSessionRestorationSupported=false`.
- SalemX call service staging guardrails are in place: explicit service mode, fake-mode blocking, redacted readiness, Redis allocation/rate-limit config validation, memory store blocking in staging, and storage-key secret requirement.
- Redis local smoke passed with a disposable local Redis container and remained fully redacted.
- `server/salemx-call-service/deploy/staging.env.example` now documents placeholder-only staging service env values.
- Operator-local deploy env files are ignored by git.
- `server/salemx-call-service/scripts/run_staging_call_service_local.sh` validates staging guardrails and starts `uvicorn` from an operator-local env file without printing env values.
- `server/salemx-call-service/scripts/check_staging_readiness.sh` queries readiness and prints only redacted readiness fields.
- `server/salemx-call-service/scripts/staging_synapse_smoke.sh` provides the redacted operator-local staging Synapse validation harness.
- Staging Synapse/LiveKit setup has passed readiness, signalling, media connect, active audio, and hangup cleanup smoke through the private native audio card.
- The previous `liveKitURLUnreachable` / service-not-found-like blocker is resolved by server-side LiveKit room pre-create.
- Controlled engineering dogfood is conditionally allowed for named engineers on the staging path only.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, existing call-service changes, CallKit, push, video, or global production activation has been added.

Required operator-local staging service env file:
- Copy `server/salemx-call-service/deploy/staging.env.example` to `server/salemx-call-service/deploy/staging.env` or another ignored local path.
- Fill values locally only. Do not commit or paste the real file.

Required operator-local smoke env file:
- Copy `server/salemx-call-service/smoke/staging-synapse-smoke.env.example` to `server/salemx-call-service/smoke/staging-synapse-smoke.env` or another ignored local path.
- Fill values locally only. Do not commit or paste the real file.

Phase:
2.26C — controlled staging dogfood session matrix execution.

Task:
Run the controlled staging dogfood session matrix from `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md` and record redacted pass/fail results. Do not modify iOS behavior unless a small diagnostics-only issue is found. Do not change Element Call, CallKit, push, video, shared LiveKit config, or global production activation.

Context:
The A/B staging iOS smoke after backend commit `33e95e7b1` reached active audio and returned to idle after hangup. 2.26B updated the dogfood runbook with the conditional yes, required gates, operational preflight, session matrix, redaction format, stop conditions, and rollback path.

Goal:
Execute the first controlled engineering dogfood matrix on the staging path while preserving redaction and existing Element Call behavior.

Recent 2.25F proof:

- A/B diagnostic launch succeeded.
- A/B reached `productionSessionState=activeAudio`.
- A/B had `productionEncryptionState=ready`.
- A/B had media connect and LiveKit client connect attempted.
- A/B had `productionMediaFailureReason=none`.
- Hangup returned A/B to `productionSessionState=idle`.
- A/B had media disconnect and cleanup attempted.
- No iOS app code changed.
- Element Call route remained untouched.
- Dogfood runbook now allows only named-engineer, DEBUG/integration, staging, foreground/open-room, encrypted 1:1, verified-peer sessions.

Hard redaction rules:
- Never print Matrix access tokens.
- Never print `SYNAPSE_ADMIN_TOKEN`.
- Never print LiveKit participant token/JWT.
- Never print LiveKit API secret.
- Never print Redis URL with credentials.
- Never print raw room IDs.
- Never print raw peer/user IDs.
- Never print device IDs.
- Never print raw Matrix event/state bodies.
- Never print full request or response bodies.

Allowed report fields:
- HTTP status.
- Readiness booleans.
- A/B lifecycle enums.
- Redacted token response shape booleans.
- Backend redacted reason enums.
- Media failure enum.

Pass criteria:
- Each attempted matrix case reports pass/fail only with allowed redacted fields.
- The happy path and reverse direction reach active audio and return to idle.
- Failure cases fail closed without stale active sessions.
- Element Call buttons and route remain unchanged.
- No CallKit, push, video, or global production activation is added.
- No token/JWT/secret/raw ID leakage.

If staging data is unavailable:
- Do not fake success.
- Report exactly which precondition is missing by variable name only.
- Keep report redacted.

Rollback:
- Stop the `uvicorn` process.
- Stop local Redis if used: `docker stop salemx-call-service-staging-redis`.
- Do not commit or paste local env files.
- Keep iOS private native call gates unchanged.

Report:
A. Operational preflight result.
B. Session matrix pass/fail table.
C. Stop/rollback triggers encountered, if any.
D. Redaction self-check.
E. Element Call fallback status.
F. Whether code/docs changed.
G. Whether controlled staging dogfood remains allowed.

Suggested commit only if docs/scripts changed:
Record controlled staging dogfood matrix
