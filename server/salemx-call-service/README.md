# SalemX Call Service Skeleton

Minimal backend skeleton for issuing short-lived LiveKit participant tokens for SalemX native direct calls.

This service is intentionally separate from the iOS app and is not deployed automatically. It is designed to be reverse-proxied under the Matrix client namespace:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/livekit/token
```

## Security Model

The service:

- validates the caller's Matrix access token against Synapse;
- validates that the caller and peer are the only joined members of an encrypted room;
- allocates or reuses an opaque LiveKit room for `(room_id, call_id, intent)`;
- issues a short-lived participant token scoped to that one LiveKit room;
- never receives or handles media E2EE raw keys.

The service must never log:

- Matrix access tokens;
- LiveKit participant tokens;
- LiveKit API secrets;
- raw Matrix event content;
- media E2EE raw keys;
- full request or response bodies.

## Configuration

Required mode:

```text
SALEMX_CALL_SERVICE_MODE=local_fake|staging
```

If `SALEMX_CALL_SERVICE_MODE` is absent, the service defaults to `staging` and fails closed until staging config is present. `production` is reserved and currently fails closed as unsupported.

Required staging environment variables:

```text
SYNAPSE_BASE_URL
SYNAPSE_ADMIN_TOKEN
LIVEKIT_URL
LIVEKIT_API_KEY
LIVEKIT_API_SECRET
SALEMX_CALL_SERVICE_ALLOCATION_STORE=redis
SALEMX_CALL_SERVICE_ALLOCATION_STORE_URL=<shared-store-url>
SALEMX_CALL_SERVICE_RATE_LIMIT_STORE=redis
SALEMX_CALL_SERVICE_RATE_LIMIT_STORE_URL=<shared-rate-limit-store-url>
SALEMX_CALL_SERVICE_STORAGE_KEY_SECRET=<storage-key-hmac-secret>
```

Optional environment variables:

```text
TOKEN_TTL_SECONDS=120
ALLOCATION_TTL_SECONDS=300
SALEMX_CALL_SERVICE_RATE_LIMIT_PER_MINUTE=30
LOG_LEVEL=INFO
```

`SYNAPSE_ADMIN_TOKEN` is intended for membership and room-state lookup only. `LIVEKIT_API_SECRET` stays server-side and must never be sent to clients.
`SALEMX_CALL_SERVICE_ALLOCATION_STORE_URL` must be supplied through secret-managed deployment config and must not be logged.
`SALEMX_CALL_SERVICE_RATE_LIMIT_STORE_URL` must also be supplied through secret-managed deployment config and must not be logged.
`SALEMX_CALL_SERVICE_STORAGE_KEY_SECRET` is used only to derive HMAC-backed Redis keys and must not be logged, returned by readiness, or shared with clients.

Staging preflight refuses to start when:

- `SALEMX_CALL_SERVICE_FAKE_MODE=1` is set;
- Synapse configuration is missing;
- LiveKit configuration is missing;
- `LIVEKIT_URL` is not `wss://...`;
- `LIVEKIT_URL` points at the local smoke placeholder;
- `TOKEN_TTL_SECONDS` is outside the bounded staging range.
- shared allocation store config is missing;
- `SALEMX_CALL_SERVICE_ALLOCATION_STORE=memory` is used without an explicit test override;
- `SALEMX_CALL_SERVICE_ALLOCATION_STORE` is not `redis` for staging (except memory with an explicit test override);
- rate-limit config is missing or invalid;
- `SALEMX_CALL_SERVICE_RATE_LIMIT_STORE=memory` is used without an explicit test override;
- `SALEMX_CALL_SERVICE_RATE_LIMIT_STORE` is not `redis` for staging (except memory with an explicit test override);
- Redis-backed allocation or rate limiting is configured without `SALEMX_CALL_SERVICE_STORAGE_KEY_SECRET`;
- `ALLOCATION_TTL_SECONDS` is shorter than `TOKEN_TTL_SECONDS`.

For tests only, `SALEMX_CALL_SERVICE_ALLOW_INSECURE_LIVEKIT_URL=1` allows an insecure LiveKit URL. Do not set this in staging.
For tests only, `SALEMX_CALL_SERVICE_ALLOW_MEMORY_ALLOCATION_STORE=1` allows the in-memory allocation store in staging mode. Do not set this in staging dogfood.
For tests only, `SALEMX_CALL_SERVICE_ALLOW_MEMORY_RATE_LIMITER=1` allows the in-memory rate limiter in staging mode. Do not set this in staging dogfood.

## Health and Readiness

The service exposes redacted health and readiness endpoints:

```text
GET /_matrix/client/unstable/kz.salemx.direct_call/health
GET /_matrix/client/unstable/kz.salemx.direct_call/readiness
```

The payload reports only mode, readiness, redacted reason, and configuration-presence booleans. It never includes tokens, secrets, URLs, Matrix room IDs, peer IDs, request bodies, or response bodies.
`allocationStoreConnected` and `rateLimitConnected` mean a non-memory runtime implementation is wired for the selected store kind; they are not a substitute for the required deployed Redis smoke test.

Readiness reasons:

- `ok`
- `fakeModeForbidden`
- `missingSynapseConfig`
- `missingLiveKitConfig`
- `insecureLiveKitURL`
- `placeholderLiveKitURL`
- `invalidTokenTTL`
- `missingAllocationStoreConfig`
- `memoryAllocationStoreForbidden`
- `unsupportedAllocationStore`
- `invalidRateLimitConfig`
- `missingStorageKeySecret`
- `unsupportedMode`

Redis-backed staging storage derives keys with `SALEMX_CALL_SERVICE_STORAGE_KEY_SECRET` and HMAC-SHA256. Redis keys and values must not contain raw Matrix room IDs, peer IDs, user IDs, device IDs, access tokens, LiveKit JWTs, Synapse admin tokens, or LiveKit API secrets.

## Request

```json
{
  "version": 1,
  "call_id": "opaque-call-id",
  "room_id": "!room:example.org",
  "peer_user_id": "@peer:example.org",
  "intent": "audio",
  "direction": "outgoing",
  "device_id": "DEVICEID",
  "client_transaction_id": "txn-1"
}
```

## Response

```json
{
  "version": 1,
  "livekit": {
    "server_url": "wss://livekit.example.org",
    "room_name": "salemx-dc-opaque-allocation",
    "participant_token": "short-lived-participant-token",
    "expires_at": "2026-05-12T12:00:00Z"
  },
  "allocation": {
    "id": "opaque-allocation-id",
    "call_id": "opaque-call-id",
    "intent": "audio"
  }
}
```

## Error Response

```json
{
  "errcode": "M_DIRECT_CALL_RATE_LIMITED",
  "error": "Direct-call token request rate limited.",
  "retry_after_ms": 30000
}
```

If the allocated LiveKit room cannot be prepared, the service fails closed before issuing a participant token:

```json
{
  "errcode": "M_DIRECT_CALL_LIVEKIT_ROOM_UNAVAILABLE",
  "error": "Unable to prepare media room."
}
```

## Local Run

Create an isolated Python environment, install requirements, and run Uvicorn:

```bash
cd server/salemx-call-service
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn salemx_call_service.app:app --host 127.0.0.1 --port 8088
```

The default app entrypoint requires production-like environment variables. Unit tests use fakes and do not connect to real Synapse or LiveKit.

## Local Fake Smoke Mode

For a local endpoint smoke without real Synapse or LiveKit credentials, enable the explicit fake mode:

```bash
cd server/salemx-call-service
SALEMX_CALL_SERVICE_FAKE_MODE=1 \
SALEMX_CALL_SERVICE_MODE=local_fake \
LIVEKIT_URL=ws://localhost:7880 \
LIVEKIT_API_KEY=<local-livekit-api-key> \
LIVEKIT_API_SECRET=<local-livekit-api-secret> \
uvicorn salemx_call_service.app:app --host 127.0.0.1 --port 8088
```

Fake mode is off by default, requires `SALEMX_CALL_SERVICE_MODE=local_fake`, and must never be enabled in staging or production. It accepts any non-empty local `Authorization: Bearer ...` value without validating it against Synapse, and never logs the bearer value. Without local LiveKit signing configuration, the fake response is app-shaped but not usable for real LiveKit media. Local fake mode uses in-memory allocation and rate limiting only for local proof.

If `LIVEKIT_URL` is set in fake mode, the fake response uses it as `livekit.server_url`. If it is absent or blank, fake mode falls back to the local smoke placeholder URL.

If `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` are both set in fake mode, the fake response contains a short-lived LiveKit-compatible participant JWT signed for the allocated room. This is intended only for local media smoke tests against a local LiveKit dev server. If either value is absent, fake mode keeps returning a placeholder participant token for response-shape tests. Fake mode must not log these values or the issued participant token.

Fake mode also serves a local Matrix capabilities response at:

```text
GET /_matrix/client/v3/capabilities
```

The fake capability advertises `kz.salemx.direct_call.native` with the same relative token endpoint path used by the app-side production capability provider. This route exists only in fake mode and is intended for local app integration smoke tests.

Smoke request shape:

```bash
curl -sS \
  -H 'Authorization: Bearer local-smoke-token' \
  -H 'Content-Type: application/json' \
  -d '{"version":1,"call_id":"call-smoke","room_id":"!local-smoke:example.test","peer_user_id":"@bob:local.test","intent":"audio","direction":"outgoing","device_id":"DEVICEA","client_transaction_id":"txn-smoke"}' \
  http://127.0.0.1:8088/_matrix/client/unstable/kz.salemx.direct_call/livekit/token
```

Do not paste real Matrix access tokens, LiveKit tokens, or admin tokens into local smoke logs.

## Tests

Full backend validation, including FastAPI/ASGI route tests, requires the pinned backend dependencies:

```bash
cd server/salemx-call-service
python3 -m venv /tmp/salemx-call-service-test-venv
/tmp/salemx-call-service-test-venv/bin/python -m pip install -r requirements.txt
PYTHONPYCACHEPREFIX=/tmp/salemx-call-service-pycache \
  /tmp/salemx-call-service-test-venv/bin/python -m unittest discover tests
PYTHONPYCACHEPREFIX=/tmp/salemx-call-service-pycache \
  /tmp/salemx-call-service-test-venv/bin/python -m compileall -q salemx_call_service tests
```

Running tests with an interpreter that does not have FastAPI installed may skip the FastAPI-dependent app route checks.
The venv command above is the expected full route-validation path and does not connect to real Synapse or LiveKit.

## Local Redis Integration Smoke

After Redis allocation and rate-limit wiring changes, run a local Redis smoke before attempting any staging deployment. Use a disposable Redis container and a throwaway local storage key secret only.

Example container setup:

```bash
docker run -d --rm --name salemx-call-redis-smoke -p 6380:6379 redis:7-alpine
docker exec salemx-call-redis-smoke redis-cli ping
```

The 2.24H local smoke used the pinned backend test environment and ASGI route harness with mocked Synapse validation. It verified:

- redacted staging readiness returned `ready=true`, `reason=ok`, `allocationStoreConfigured=true`, `allocationStoreShared=true`, `allocationStoreConnected=true`, `rateLimitConfigured=true`, `rateLimitShared=true`, `rateLimitConnected=true`, and `storageKeyConfigured=true`;
- Redis allocation create/reuse returned `200` and reused the same allocation and LiveKit room for repeat requests;
- caller/callee directions converged on the same LiveKit room;
- Redis rate limiting allowed the under-limit request, returned `429` with `M_DIRECT_CALL_RATE_LIMITED` and `retry_after_ms` over limit, and did not issue a second token;
- Redis keys/readiness output did not contain raw room IDs, peer IDs, user IDs, device IDs, bearer tokens, LiveKit participant tokens, JWTs, Synapse admin tokens, or LiveKit API secrets;
- stopping Redis failed closed with `M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE` before token issuance, and the allocation-specific path failed closed with `M_DIRECT_CALL_ALLOCATION_FAILED` before token issuance.

Clean up the disposable container after the smoke:

```bash
docker stop salemx-call-redis-smoke
```

This local Redis smoke is not staging approval by itself. Controlled staging dogfood now requires the full operational preflight from the private native audio dogfood runbook, including redacted readiness, Redis allocation/rate-limit connectivity, real Synapse validation, LiveKit room provisioning, and the staging active-audio path.

## Staging Deployment Preparation

The repository includes a placeholder-only staging env template:

```bash
cp server/salemx-call-service/deploy/staging.env.example server/salemx-call-service/deploy/staging.env
$EDITOR server/salemx-call-service/deploy/staging.env
```

`server/salemx-call-service/deploy/staging.env` is ignored by git. Keep real Synapse tokens, LiveKit secrets, storage-key secrets, Redis URLs with credentials, Matrix access tokens, room IDs, user IDs, and device IDs out of the repository and out of shared logs.

For a local staging-shaped run against real staging Synapse/LiveKit and Redis, use:

```bash
docker run -d --rm --name salemx-call-service-staging-redis -p 6380:6379 redis:7-alpine
server/salemx-call-service/scripts/run_staging_call_service_local.sh \
  --env-file server/salemx-call-service/deploy/staging.env \
  --host 127.0.0.1 \
  --port 8088
```

The run helper validates guardrails before starting:

- `SALEMX_CALL_SERVICE_MODE=staging`;
- `SALEMX_CALL_SERVICE_FAKE_MODE=0`;
- `LIVEKIT_URL` starts with `wss://`;
- Redis allocation and rate-limit store kinds are `redis`;
- Redis store URLs, storage-key secret, Synapse config, LiveKit config, TTLs, and rate limit are present;
- `ALLOCATION_TTL_SECONDS` is not shorter than `TOKEN_TTL_SECONDS`.

The helper prints missing or invalid variable names only and never prints values.

## LiveKit Room Provisioning

In staging mode, the service pre-creates the allocated LiveKit room before issuing a participant token. This uses the LiveKit RoomService `CreateRoom` API with a short-lived server-side token carrying only `roomCreate`; participant tokens remain scoped to `roomJoin`, publish, and subscribe for one allocated room.

The provisioner derives the RoomService URL from `LIVEKIT_URL`, converting `wss://` to `https://` for the server API. It treats LiveKit already-exists responses as success so caller/callee requests and concurrent retries converge on the Redis allocation. If room creation fails, the request returns `M_DIRECT_CALL_LIVEKIT_ROOM_UNAVAILABLE` and no participant token is issued.

Readiness exposes only the redacted boolean `liveKitRoomProvisioningConfigured`; it never exposes the LiveKit API key, API secret, participant tokens, room names, or endpoint credentials.

In a second shell, check redacted readiness:

```bash
server/salemx-call-service/scripts/check_staging_readiness.sh \
  --env-file server/salemx-call-service/deploy/staging.env
```

Allowed output is limited to HTTP status, readiness reason, and readiness booleans. Do not paste raw env files or raw service logs into shared threads.

## Staging Synapse Validation Smoke Harness

The repository includes a redacted operator-local harness for staging Synapse validation:

```bash
cp server/salemx-call-service/smoke/staging-synapse-smoke.env.example /tmp/staging-synapse-smoke.env
$EDITOR /tmp/staging-synapse-smoke.env
server/salemx-call-service/scripts/staging_synapse_smoke.sh --env-file /tmp/staging-synapse-smoke.env
```

The env file with real values must stay outside the repo or in an ignored local path. Do not commit real access tokens, room IDs, user IDs, device IDs, Redis URLs with credentials, Synapse admin tokens, LiveKit secrets, or participant tokens.

Required harness variables:

```text
CALL_SERVICE_BASE_URL
CALLER_MATRIX_ACCESS_TOKEN
CALLER_DEVICE_ID
STAGING_ENCRYPTED_DIRECT_ROOM_ID
STAGING_PEER_USER_ID
```

Optional negative-case fixture variables:

```text
WRONG_DEVICE_ID
NEGATIVE_UNENCRYPTED_ROOM_ID
NEGATIVE_NON_1_TO_1_ROOM_ID
NEGATIVE_PEER_NOT_JOINED_USER_ID
NEGATIVE_CALLER_NOT_JOINED_ROOM_ID
```

The harness prints only redacted case summaries: HTTP status, Matrix-style errcode, readiness booleans, token-response shape booleans, and pass/fail/skip. It does not echo request JSON or environment values. Missing optional negative fixtures are reported as skipped.

Use a staging rate limit high enough for the whole smoke burst, or run cases with enough delay for the rate-limit window to clear. Room-validation negative cases run after authenticated rate-limit checks, so an intentionally low staging limit can produce `M_DIRECT_CALL_RATE_LIMITED` before the room-validation assertion is reached.

Staging Synapse validation passes only when readiness is `ok`, the positive encrypted 1:1 token request succeeds, required negative cases fail closed, no token is issued for negative cases, and the harness redaction self-check passes.

Recommended staging setup order:

1. Copy and fill `deploy/staging.env` locally.
2. Start Redis or point the env file at an operator-managed staging Redis.
3. Start the call service with `run_staging_call_service_local.sh`.
4. Run `check_staging_readiness.sh`.
5. Copy and fill the smoke env locally:

```bash
cp server/salemx-call-service/smoke/staging-synapse-smoke.env.example server/salemx-call-service/smoke/staging-synapse-smoke.env
$EDITOR server/salemx-call-service/smoke/staging-synapse-smoke.env
```

6. Run `staging_synapse_smoke.sh`.
7. Share only the redacted script output.

Rollback:

```bash
docker stop salemx-call-service-staging-redis
```

Also stop the `uvicorn` process and unset/close any operator-local env files. The iOS private native call path remains gated separately and is not activated by these backend helpers.

## Reverse Proxy Example

Example Nginx location:

```nginx
location = /_matrix/client/unstable/kz.salemx.direct_call/livekit/token {
    proxy_pass http://127.0.0.1:8088/_matrix/client/unstable/kz.salemx.direct_call/livekit/token;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Current Limitations

- `SynapseRoomValidator` uses Synapse admin-style room member/state endpoints:
  - `GET /_synapse/admin/v1/rooms/{room_id}/members`
  - `GET /_synapse/admin/v1/rooms/{room_id}/state`
  Verify these response shapes against the deployed Synapse version before production use.
- `InMemoryAllocationStore` is suitable only for local fake mode and tests. Staging preflight now rejects memory allocation unless a temporary test override is set.
- `redis` allocation store mode is wired through a shared store implementation with HMAC-derived keys and atomic `SET NX EX` create-or-reuse behavior. Local Redis container smoke passed; deployed staging Redis smoke is still required before staging dogfood.
- `redis` rate-limit store mode is wired through a shared limiter implementation with HMAC-derived keys and an atomic Lua check-and-record operation. Local Redis container smoke passed; deployed staging Redis smoke is still required before staging dogfood.
- `postgres` allocation and rate-limit store modes remain unsupported/fail-closed skeletons until a real implementation is added.
- In-memory rate limiting is suitable only for local fake mode and tests. Staging preflight rejects it unless a temporary test override is set.
- Staging dogfood remains blocked until Redis allocation/rate limiting, Synapse validation, and LiveKit join are deployed and smoke-tested together.
- The service issues media transport credentials only. It does not know or transport media E2EE keys.
