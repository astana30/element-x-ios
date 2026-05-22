# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.26C — controlled staging dogfood matrix recorded.

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
- The 2.26C runner path required the existing DEBUG rollout/capability shim gate to avoid `appRolloutDisabled`. Media, token issuance, and LiveKit were real staging, but this is not yet a clean product-card-only dogfood proof.
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
2.26D — native direct-call activation gate cleanup / product-card-only dogfood readiness.

Task:
Inspect and clean up the staging activation gate path so controlled dogfood can move from diagnostic-runner activation to a clean private product-card-only proof. Do not globally activate production direct calls. Do not change Element Call routing. Do not add CallKit, push, missed calls, video, or session restoration.

Context:
2.26C proved the staging media/token/LiveKit path across the controlled dogfood matrix. However, the runner path required the DEBUG rollout/capability shim gate to avoid `appRolloutDisabled`. That means controlled engineering diagnostic dogfood may continue, but broader/product-card-only claims should pause until this mismatch is fixed or explicitly documented.

Goal:
Decide and implement the smallest safe staging-only activation cleanup that lets the private product card use real staging token and LiveKit plumbing without depending on misleading fake rollout/capability naming, while preserving fail-closed behavior and redaction.

Hard constraints:
- No raw tokens, JWTs, keys, Matrix access tokens, Synapse admin tokens, room IDs, user IDs, peer IDs, device IDs, Redis credentials, Matrix event bodies, or full request/response bodies in output or docs.
- No Element Call route changes.
- No CallKit, push/background incoming, missed calls, video, session restoration, public rollout, broad internal rollout, or global production activation.
- Do not weaken trusted-device/E2EE behavior.
- Do not touch shared LiveKit server config unless separately approved.
- Keep env files ignored and local-only.

Inspection targets:
- `ElementX/Sources/Application/AppCoordinator.swift`
- `ElementX/Sources/Other/Extensions/ProcessInfo.swift`
- `ElementX/Sources/Services/Calls/DirectCallMediaEngineProtocol.swift`
- `ElementX/Sources/Services/Calls/DirectCallMediaEngineFactory.swift`
- `ElementX/Sources/FlowCoordinators/RoomFlowCoordinator.swift`
- `ElementX/Sources/Screens/RoomScreen/RoomScreenModels.swift`
- `Tools/Scripts/run_native_direct_call_diagnostic_two_client.sh`
- `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`

Questions to answer:
A. Which exact gate currently requires the DEBUG rollout/capability shim during staging dogfood?
B. Is the shim only naming/diagnostic plumbing, or does it affect runtime behavior beyond capability/rollout readiness?
C. What is the smallest staging-only replacement that keeps production fail-closed?
D. What tests prove default production remains disabled and staging dogfood remains explicit?
E. What manual or runner smoke should prove product-card-only readiness after cleanup?

Validation:
- Focused Swift tests for any changed gate/config code.
- `git diff --check`.
- Secret/forbidden scan on changed files.
- Docs updated only if needed, with no secrets or raw IDs.

Suggested commit if code/docs change:
Clean up native audio staging activation gate
