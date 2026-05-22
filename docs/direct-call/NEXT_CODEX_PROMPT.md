# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.26D — private dogfood activation gate clarified.

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
- Call-service LiveKit room pre-create: 2.25E implemented server-side RoomService `CreateRoom` before participant token issuance (`33e95e7b1`).
- Staging iOS activeAudio smoke: 2.25F passed after room pre-create.
- Controlled dogfood runbook: 2.26B updated gates, preflight, rollback, redaction, and session matrix.
- Controlled dogfood matrix: 2.26C passed on the staging media/token/LiveKit path, with caveat below.
- Private dogfood activation gate cleanup: 2.26D replaced the older fake rollout/capability shim with `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Private native audio dogfood guardrails: `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven/prepared state:
- Production native audio call core works through the DEBUG/integration/private product-gated path.
- Private native call card works behind `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- Existing Element Call phone/video buttons remain visible and unchanged.
- Staging call-service readiness passed with `ready=true`, Redis allocation/rate-limit/storage booleans true, and LiveKit room provisioning true.
- A/B trust passed with `ownSessionVerified=true`, `crossSigningReady=true`, `peerTrustReady=true`, and `peerTrustReadiness=peerTrustReady`.
- 2.26C dogfood matrix passed:
  - Happy path A -> B and reverse B -> A reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
  - Repeated calls completed cleanly with no stale active session.
  - Decline incoming, cancel outgoing, and timeout cleared safely with terminal reasons `cancelled`, `outgoingTimeout`, or `incomingTimeout`.
  - Backend-off failed closed with `tokenHTTPUnavailable`, no LiveKit client connect, and cleanup/disconnect attempted.
  - Backend recovery reached A/B `activeAudio` again.
  - Relaunch during active and relaunch during ringing restored no stale active or ringing session.
  - Listener-not-armed behavior was safe: B had no active session and A cancel cleaned up safely.
  - LiveKit-off fail-closed was not run because shared staging LiveKit should not be stopped during this session.
- The 2.26D cleanup made activation explicit: `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` is DEBUG/integration-only, requires the diagnostic command gates, and is separate from the product UI and production start gates.
- Product UI/start gates alone do not enable activation and still return `appRolloutDisabled`.
- The legacy `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name no longer enables the app-side activation model.
- Media, token issuance, and LiveKit were real staging in 2.26C, but clean product-card-only dogfood still needs a fresh staging proof under the new explicit gate.
- Controlled engineering diagnostic dogfood may continue for named engineers on staging only.
- Broad internal dogfood, public beta, public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global production activation remain blocked.
- Production Matrix SDK key envelope wrapping is integrated through a narrow provider seam and preserves `OnlyTrustedDevices` policy.
- SalemX call-service staging guardrails are in place: explicit service mode, fake-mode blocking, redacted readiness, Redis allocation/rate-limit config validation, memory store blocking in staging, and storage-key secret requirement.
- Operator-local deploy and smoke env files are ignored by git and must not be committed or pasted.

Required operator-local staging service env file:
- Copy `server/salemx-call-service/deploy/staging.env.example` to `server/salemx-call-service/deploy/staging.env` or another ignored local path.
- Fill values locally only. Do not commit or paste the real file.

Required operator-local smoke env file:
- Copy `server/salemx-call-service/smoke/staging-synapse-smoke.env.example` to `server/salemx-call-service/smoke/staging-synapse-smoke.env` or another ignored local path.
- Fill values locally only. Do not commit or paste the real file.

Phase:
2.26E — product-card-only staging dogfood smoke under explicit private dogfood gate.

Task:
Run a controlled product-card-only staging smoke with the explicit private dogfood activation gate. Do not globally activate production direct calls. Do not change Element Call routing. Do not add CallKit, push, missed calls, video, or session restoration.

Context:
2.26C proved the staging media/token/LiveKit path across the controlled dogfood matrix. 2.26D replaced the unclear DEBUG fake rollout/capability shim with `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, while preserving fail-closed defaults and keeping product UI/start gates separate.

Goal:
Verify the private product card can start, accept, reach active audio, and hang up on the real staging token/LiveKit path with `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, without relying on the legacy fake-shim name or diagnostic fallback actions.

Hard constraints:
- No raw tokens, JWTs, keys, Matrix access tokens, Synapse admin tokens, room IDs, user IDs, peer IDs, device IDs, Redis credentials, Matrix event bodies, or full request/response bodies in output or docs.
- No Element Call route changes.
- No CallKit, push/background incoming, missed calls, video, session restoration, public rollout, broad internal rollout, or global production activation.
- Do not weaken trusted-device/E2EE behavior.
- Do not touch shared LiveKit server config unless separately approved.
- Keep env files ignored and local-only.

Required gates:
- `IS_RUNNING_INTEGRATION_TESTS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging call-service>`

Required proof:
A. Readiness and trust are ready.
B. Private card is visible in the encrypted direct 1:1 room.
C. A taps Start audio from the product card.
D. B taps Accept from the product card.
E. A/B reach `productionSessionState=activeAudio` with `productionMediaFailureReason=none`.
F. Hangup returns A/B to idle with cleanup/disconnect attempted.
G. No diagnostic fallback action is used except redacted status polling.
H. Element Call route remains untouched.

Validation:
- Focused Swift tests for any changed gate/config code.
- `git diff --check`.
- Secret/forbidden scan on changed files.
- Docs updated only if needed, with no secrets or raw IDs.

Suggested commit if code/docs change:
Record product-card-only staging dogfood smoke
