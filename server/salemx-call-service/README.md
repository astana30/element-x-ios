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
SALEMX_CALL_SERVICE_ALLOCATION_STORE=redis|postgres
SALEMX_CALL_SERVICE_ALLOCATION_STORE_URL=<shared-store-url>
```

Optional environment variables:

```text
TOKEN_TTL_SECONDS=120
ALLOCATION_TTL_SECONDS=300
RATE_LIMIT_PER_MINUTE=30
LOG_LEVEL=INFO
```

`SYNAPSE_ADMIN_TOKEN` is intended for membership and room-state lookup only. `LIVEKIT_API_SECRET` stays server-side and must never be sent to clients.
`SALEMX_CALL_SERVICE_ALLOCATION_STORE_URL` must be supplied through secret-managed deployment config and must not be logged.

Staging preflight refuses to start when:

- `SALEMX_CALL_SERVICE_FAKE_MODE=1` is set;
- Synapse configuration is missing;
- LiveKit configuration is missing;
- `LIVEKIT_URL` is not `wss://...`;
- `LIVEKIT_URL` points at the local smoke placeholder;
- `TOKEN_TTL_SECONDS` is outside the bounded staging range.
- shared allocation store config is missing;
- `SALEMX_CALL_SERVICE_ALLOCATION_STORE=memory` is used without an explicit test override;
- `SALEMX_CALL_SERVICE_ALLOCATION_STORE` is not one of `memory`, `redis`, or `postgres`.

For tests only, `SALEMX_CALL_SERVICE_ALLOW_INSECURE_LIVEKIT_URL=1` allows an insecure LiveKit URL. Do not set this in staging.
For tests only, `SALEMX_CALL_SERVICE_ALLOW_MEMORY_ALLOCATION_STORE=1` allows the in-memory allocation store in staging mode. Do not set this in staging dogfood.

## Health and Readiness

The service exposes redacted health and readiness endpoints:

```text
GET /_matrix/client/unstable/kz.salemx.direct_call/health
GET /_matrix/client/unstable/kz.salemx.direct_call/readiness
```

The payload reports only mode, readiness, redacted reason, and configuration-presence booleans. It never includes tokens, secrets, URLs, Matrix room IDs, peer IDs, request bodies, or response bodies.

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
- `unsupportedMode`

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

Fake mode is off by default, requires `SALEMX_CALL_SERVICE_MODE=local_fake`, and must never be enabled in staging or production. It accepts any non-empty local `Authorization: Bearer ...` value without validating it against Synapse, and never logs the bearer value. Without local LiveKit signing configuration, the fake response is app-shaped but not usable for real LiveKit media.

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

The unit tests use only the Python standard library:

```bash
cd server/salemx-call-service
python3 -m unittest discover tests
```

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
- `redis` and `postgres` allocation store modes currently validate configuration shape and install a fail-closed skeleton. A real shared transactional implementation still needs to be connected before staging dogfood can issue tokens successfully.
- Rate limiting is represented in config but not implemented yet.
- Staging dogfood remains blocked until real shared allocation storage and rate limiting are implemented, deployed, and smoke-tested.
- The service issues media transport credentials only. It does not know or transport media E2EE keys.
