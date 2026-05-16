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

Required environment variables:

```text
SYNAPSE_BASE_URL
SYNAPSE_ADMIN_TOKEN
LIVEKIT_URL
LIVEKIT_API_KEY
LIVEKIT_API_SECRET
```

Optional environment variables:

```text
TOKEN_TTL_SECONDS=120
ALLOCATION_TTL_SECONDS=300
RATE_LIMIT_PER_MINUTE=30
LOG_LEVEL=INFO
```

`SYNAPSE_ADMIN_TOKEN` is intended for membership and room-state lookup only. `LIVEKIT_API_SECRET` stays server-side and must never be sent to clients.

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
SALEMX_CALL_SERVICE_FAKE_MODE=1 uvicorn salemx_call_service.app:app --host 127.0.0.1 --port 8088
```

Fake mode is off by default and must never be enabled in production. It accepts any non-empty local `Authorization: Bearer ...` value without validating it against Synapse, and never logs the bearer value. The fake response is app-shaped but not usable for real LiveKit media.

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
- `InMemoryAllocationStore` is suitable only for the skeleton and tests. Production should use a shared transactional store.
- Rate limiting is represented in config but not implemented yet.
- The service issues media transport credentials only. It does not know or transport media E2EE keys.
