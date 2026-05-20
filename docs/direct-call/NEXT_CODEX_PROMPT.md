# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.24J-prep — staging Synapse smoke env/runbook harness.

Current checkpoints:
- App code: 2.23C `Polish native call listener availability status` (`bb7ae2557`).
- Backend staging preflight guardrails: 2.24B `Add call service staging preflight guardrails` (`c32f89fcc`).
- Allocation store guardrails: 2.24C `Add call service allocation store guardrails` (`69b56992a`).
- Rate limiting guardrails: 2.24D `Add call service rate limiting guardrails` (`ee7ea06ae`).
- FastAPI route test environment: 2.24E `Document call service full test environment` (`073c8da49`).
- Redis storage skeleton: 2.24G `Add Redis call service storage skeleton` (`98e153b7f`).
- Redis local integration smoke: 2.24H passed and is documented (`113945266`).
- Staging Synapse smoke harness: 2.24J-prep added an operator-local env template and redacted smoke script.
- Private native audio dogfood guardrails: `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven state:
- Production native audio call core works through the DEBUG/integration/private product-gated path.
- Private native call card works behind `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- Existing Element Call phone/video buttons remain visible and unchanged.
- Manual private-card actions were proven: Start audio, Accept, Hang up, Decline incoming, Cancel outgoing, Retry, and Dismiss.
- Repeated calls, reverse-direction calls, backend-off recovery, LiveKit-off recovery, stale media failure cleanup, rapid terminal actions, timeout, and relaunch fail-closed behavior are runtime-proven.
- Production Matrix SDK key envelope wrapping is integrated through a narrow provider seam and preserves `OnlyTrustedDevices` policy.
- Listener/owner lifecycle is fail-closed with `productionSessionRestorationSupported=false`.
- SalemX call service staging guardrails are in place: explicit service mode, fake-mode blocking, redacted readiness, Redis allocation/rate-limit config validation, memory store blocking in staging, and storage-key secret requirement.
- Redis local smoke passed with a disposable local Redis container and remained fully redacted.
- `server/salemx-call-service/scripts/staging_synapse_smoke.sh` now provides a redacted operator-local staging Synapse validation harness.
- `server/salemx-call-service/smoke/staging-synapse-smoke.env.example` documents required and optional fixture variables with placeholders only.
- Operator-local backend smoke env files are ignored by git.
- The staging Synapse smoke harness:
  - reads env from the operator shell or an optional local env file;
  - prints only missing variable names, never values;
  - runs readiness, positive token, invalid bearer, wrong-device, and optional negative room-fixture checks;
  - skips missing optional negative fixtures explicitly;
  - prints only HTTP status, errcode, readiness booleans, token response shape booleans, and pass/fail/skip;
  - avoids echoing request JSON;
  - self-checks the report for known fixture values and token-shaped output before printing.
- The harness has not been run against real staging yet because operator-local endpoint and fixtures are still required.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, existing call-service changes, CallKit, push, video, or global production activation has been added.

Required operator-local harness variables:
- `CALL_SERVICE_BASE_URL`
- `CALLER_MATRIX_ACCESS_TOKEN`
- `CALLER_DEVICE_ID`
- `STAGING_ENCRYPTED_DIRECT_ROOM_ID`
- `STAGING_PEER_USER_ID`

Optional negative fixture variables:
- `WRONG_DEVICE_ID`
- `NEGATIVE_UNENCRYPTED_ROOM_ID`
- `NEGATIVE_NON_1_TO_1_ROOM_ID`
- `NEGATIVE_PEER_NOT_JOINED_USER_ID`
- `NEGATIVE_CALLER_NOT_JOINED_ROOM_ID`

Phase:
2.24J — staging Synapse validation smoke execution.

Task:
Execute staging Synapse validation smoke using the redacted local-only harness. Do not modify code unless a test-only script/doc issue is found. Do not commit unless docs/scripts are changed and validation passes.

Context:
The previous execution attempt was blocked because staging endpoint and test fixtures were unavailable. The prep phase added a safe harness and env template so an operator can provide local fixtures without committing or printing secrets.

Goal:
Run staging smoke and report only redacted/pass-fail results.

Recommended command shape:

```bash
cp server/salemx-call-service/smoke/staging-synapse-smoke.env.example /tmp/staging-synapse-smoke.env
$EDITOR /tmp/staging-synapse-smoke.env
server/salemx-call-service/scripts/staging_synapse_smoke.sh --env-file /tmp/staging-synapse-smoke.env
```

If the operator has already exported local env vars, run:

```bash
server/salemx-call-service/scripts/staging_synapse_smoke.sh
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
- Positive case returns `200`.
- Required negative cases fail closed with expected errcode/status.
- Optional negative cases pass if fixtures are supplied, otherwise report skipped.
- No token issued for negative cases.
- Harness redaction self-check passes.
- Readiness remains redacted.
- Staging rate limit is high enough for the smoke burst, or cases are spaced so room-validation negatives are not masked by `M_DIRECT_CALL_RATE_LIMITED`.

If staging data is unavailable:
- Do not fake success.
- Report exactly which precondition is missing by variable name only.
- Keep report redacted.

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
