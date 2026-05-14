# Local Backend Smoke Pack

This pack verifies the app-side production token and capability seams against the local SalemX call service fake mode. It is disabled by default and must not be used as production activation.

## What It Proves

- The local FastAPI fake service can return an app-shaped LiveKit token response.
- `ProductionDirectCallLiveKitTokenClient` can consume that response through `URLSessionDirectCallHTTPTransport`.
- `HTTPDirectCallProductionCapabilityProvider` can fetch and decode the fake Matrix capabilities response.
- The activation dry-run remains disabled with the default rollout provider.
- An enabled dry-run decision is possible only in test code when rollout, capability, dependency readiness, and room eligibility are all valid.

## What It Does Not Do

- It does not activate production direct calls.
- It does not start native direct-call listeners.
- It does not send Matrix call signalling.
- It does not construct or connect media engines.
- It does not add visible UI.
- It does not use Element Call, CallKit, or push.
- It does not use real Matrix credentials or production LiveKit credentials.

## Start Local Fake Backend

Run from the repository root:

```bash
cd server/salemx-call-service
SALEMX_CALL_SERVICE_FAKE_MODE=1 \
SALEMX_CALL_SERVICE_FAKE_ACCESS_TOKEN=<fake-local-access-credential> \
python3 -m uvicorn salemx_call_service.app:app --host 127.0.0.1 --port 8088
```

The fake service exposes:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/livekit/token
GET /_matrix/client/v3/capabilities
```

Both are local-only smoke endpoints. Fake mode is off by default.

## Run App Smoke Tests

In another shell, run the env-gated smoke wrapper against the local fake service:

```bash
SALEMX_DIRECTCALL_BACKEND_SMOKE=1 \
SALEMX_DIRECTCALL_BACKEND_BASE_URL=http://127.0.0.1:8088 \
SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN=<same-fake-local-access-credential> \
Tools/Scripts/run_direct_call_backend_smoke.sh
```

The script verifies both fake backend endpoints are reachable, runs the Swift Testing suites that contain the token and capability smoke tests, and fails unless both smoke tests are reported as passed. It intentionally does not print the fake access credential or response bodies.

The script writes a short-lived local smoke config file to `/tmp/salemx-direct-call-backend-smoke.env` so hosted simulator tests can read the fake backend settings reliably. The file is removed when the script exits and is ignored by default test runs when absent or stale.

If you need to run the underlying Xcode command manually, use suite-level selectors rather than method-level selectors. Swift Testing method selection through `xcodebuild -only-testing` can report zero selected tests in some setups.

```bash
SALEMX_DIRECTCALL_BACKEND_SMOKE=1 \
SALEMX_DIRECTCALL_BACKEND_BASE_URL=http://127.0.0.1:8088 \
SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN=<same-fake-local-access-credential> \
xcodebuild test \
  -project SalemX.xcodeproj \
  -scheme UnitTests \
  -destination 'platform=iOS Simulator,id=183D9DAD-0CB6-49DE-ABFD-53BFA7B724CB' \
  -only-testing:UnitTests/DirectCallBackendSmokeTests
```

Without `SALEMX_DIRECTCALL_BACKEND_SMOKE=1`, the local HTTP smoke tests are skipped. The wrapper script treats that as a configuration error because its purpose is to prove the smoke actually ran.

## Redaction Rules

- Do not use real Matrix access credentials.
- Do not use real LiveKit participant credentials.
- Do not paste backend admin credentials into commands.
- Do not print response bodies from real services.
- Keep fake local values local and disposable.

The Swift tests assert that smoke environment, token client, connection info, and dry-run diagnostics remain redacted in descriptions.
