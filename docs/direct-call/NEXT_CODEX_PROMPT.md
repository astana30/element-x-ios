# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.24K — staging call service deployment preparation.

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
- The staging deployment scaffold has not been run against real staging yet because operator-local endpoint/secrets/fixtures are still required.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, existing call-service changes, CallKit, push, video, or global production activation has been added.

Required operator-local staging service env file:
- Copy `server/salemx-call-service/deploy/staging.env.example` to `server/salemx-call-service/deploy/staging.env` or another ignored local path.
- Fill values locally only. Do not commit or paste the real file.

Required operator-local smoke env file:
- Copy `server/salemx-call-service/smoke/staging-synapse-smoke.env.example` to `server/salemx-call-service/smoke/staging-synapse-smoke.env` or another ignored local path.
- Fill values locally only. Do not commit or paste the real file.

Phase:
2.24J — staging Synapse validation smoke execution.

Task:
Start/check the staging call service using the deployment scaffold, then execute staging Synapse validation smoke using the redacted local-only harness. Do not modify code unless a test-only script/doc issue is found. Do not commit unless docs/scripts are changed and validation passes.

Context:
Previous execution attempts were blocked because staging endpoint and test fixtures were unavailable. The prep phases added safe local env templates and helper scripts so an operator can provide local values without committing or printing secrets.

Goal:
Run staging readiness and Synapse validation smoke and report only redacted/pass-fail results.

Suggested setup commands:

```bash
cp server/salemx-call-service/deploy/staging.env.example server/salemx-call-service/deploy/staging.env
$EDITOR server/salemx-call-service/deploy/staging.env

docker run -d --rm --name salemx-call-service-staging-redis -p 6380:6379 redis:7-alpine

server/salemx-call-service/scripts/run_staging_call_service_local.sh \
  --env-file server/salemx-call-service/deploy/staging.env \
  --host 127.0.0.1 \
  --port 8088
```

In a second shell:

```bash
server/salemx-call-service/scripts/check_staging_readiness.sh \
  --env-file server/salemx-call-service/deploy/staging.env

cp server/salemx-call-service/smoke/staging-synapse-smoke.env.example server/salemx-call-service/smoke/staging-synapse-smoke.env
$EDITOR server/salemx-call-service/smoke/staging-synapse-smoke.env

server/salemx-call-service/scripts/staging_synapse_smoke.sh \
  --env-file server/salemx-call-service/smoke/staging-synapse-smoke.env
```

Smoke cases:
1. Readiness:
   - expect `ready=true`, `reason=ok`
   - allocation/rate-limit configured/shared/connected true
   - `storageKeyConfigured=true`
2. Positive token request:
   - valid caller bearer
   - matching device ID
   - encrypted direct 1:1 room
   - caller joined
   - peer joined
   - expect HTTP `200`
3. Invalid bearer:
   - expect `401 M_UNKNOWN_TOKEN`
   - no token issued
4. Wrong device ID when fixture is present:
   - expect `403 M_FORBIDDEN`
   - no token issued
5. Room not encrypted when fixture is present:
   - expect `403 M_ROOM_NOT_ENCRYPTED`
   - no token issued
6. Non-1:1 room when fixture is present:
   - expect `403 M_DIRECT_CALL_NOT_1_TO_1`
   - no token issued
7. Peer not joined / peer mismatch when fixture is present:
   - expect `403 M_DIRECT_CALL_PEER_MISMATCH`
   - no token issued
8. Caller not joined when fixture is present:
   - expect `403 M_NOT_JOINED`
   - no token issued

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
- Matrix-style errcode.
- Readiness booleans.
- Pass/fail/skip per case.
- Redacted token response shape booleans.
- Backend redacted reason enums.

Pass criteria:
- Readiness check passes.
- Positive case returns `200`.
- Required negative cases fail closed with expected errcode/status.
- Optional negative cases pass if fixtures are supplied, otherwise report skipped.
- No token issued for negative cases.
- Harness redaction self-check passes.
- Staging rate limit is high enough for the smoke burst, or cases are spaced so room-validation negatives are not masked by `M_DIRECT_CALL_RATE_LIMITED`.

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
A. Readiness result.
B. Positive case result.
C. Negative case matrix.
D. Harness redaction self-check result.
E. Any deviations.
F. Whether code/docs changed.
G. Whether staging Synapse validation is pass/fail/blocked.

Suggested commit only if docs/scripts changed:
Document staging Synapse validation smoke result
