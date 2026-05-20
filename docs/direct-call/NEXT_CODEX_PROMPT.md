# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.24H — Redis local integration smoke.

Current checkpoints:
- App code: 2.23C `Polish native call listener availability status` (`bb7ae2557`).
- Backend staging preflight guardrails: 2.24B `Add call service staging preflight guardrails` (`c32f89fcc`).
- Allocation store guardrails: 2.24C `Add call service allocation store guardrails` (`69b56992a`).
- Rate limiting guardrails: 2.24D `Add call service rate limiting guardrails` (`ee7ea06ae`).
- FastAPI route test environment: 2.24E `Document call service full test environment` (`073c8da49`).
- Redis storage skeleton: 2.24G `Add Redis call service storage skeleton` (`98e153b7f`).
- Redis local integration smoke: 2.24H passed and is documented.
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
- Redis local smoke passed with a disposable local Redis container:
  - readiness reported Redis allocation/rate-limit configured/shared/connected booleans true and `reason=ok`;
  - allocation create/reuse returned `200` and caller/callee directions converged on the same LiveKit room;
  - rate limiting returned `200` under limit and `429 M_DIRECT_CALL_RATE_LIMITED` with `retry_after_ms` over limit;
  - no second token was issued after the rate limit was exceeded;
  - Redis keys/readiness output remained redacted;
  - stopped Redis failed closed with rate-limit store unavailable and allocation failed errors before token issuance.
- Redis local smoke is not staging approval. Deployed Redis smoke, real Synapse validation smoke, and LiveKit join smoke remain required before staging dogfood.
- No public UI activation, Element Call route changes, RoomScreen call presentation changes, existing call-service changes, CallKit, push, video, or global production activation has been added.

Required dogfood gates:
- `IS_RUNNING_INTEGRATION_TESTS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1` for the current fake-backed proof setup
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=...`

Phase:
2.24I — staging Synapse validation and LiveKit join smoke plan.

Task:
Inspection/design only. Do not modify code. Do not commit.

Context:
Local Redis integration smoke now covers Redis allocation and Redis rate limiting against a real local Redis container. The backend is still not approved for staging dogfood because real deployed Redis, Synapse validation, and LiveKit join smoke have not been completed.

Goal:
Design the safest staging smoke path for Synapse validation and LiveKit join, building on the Redis guardrails and local Redis proof without changing iOS behavior or weakening fail-closed activation.

Inspect:
- `server/salemx-call-service/README.md`
- `server/salemx-call-service/salemx_call_service/config.py`
- `server/salemx-call-service/salemx_call_service/app.py`
- `server/salemx-call-service/salemx_call_service/service.py`
- `server/salemx-call-service/salemx_call_service/room_validation.py`
- `server/salemx-call-service/salemx_call_service/livekit_tokens.py`
- `server/salemx-call-service/salemx_call_service/allocation.py`
- `server/salemx-call-service/salemx_call_service/rate_limiting.py`
- `server/salemx-call-service/tests/`
- `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`

Questions:
1. What exact staging Synapse validation smoke is needed before dogfood?
2. What Matrix users/rooms/devices can be used without exposing raw identifiers in logs/docs?
3. What staging LiveKit join smoke proves token compatibility without printing JWTs or API secrets?
4. How should deployed Redis readiness and Redis key redaction be checked in staging?
5. What request/response/log captures are allowed and what must be redacted?
6. What rollback should operators perform if staging Synapse, Redis, or LiveKit fails?
7. What should remain blocked after the smoke?
8. What should be the next implementation or operations phase?

Hard constraints:
- Do not modify code.
- Do not commit.
- Do not use real credentials in prompts, docs, or logs.
- Do not print Matrix access tokens, LiveKit JWTs, Synapse admin tokens, LiveKit API secrets, Redis URLs with credentials, raw room IDs, raw peer/user IDs, device IDs, or Matrix event bodies.
- Do not weaken Synapse authentication or room validation.
- Do not weaken `OnlyTrustedDevices`.
- No fallback from trusted-device media-key policy.
- Do not change iOS app behavior.
- Do not change Element Call route.
- No CallKit, push, video, public rollout, or global production activation.

Expected output:
A. Files inspected.
B. Staging Synapse validation smoke plan.
C. Staging LiveKit join smoke plan.
D. Deployed Redis smoke plan.
E. Redaction/observability checklist.
F. Rollback plan.
G. Remaining blockers.
H. Recommended next phase.
