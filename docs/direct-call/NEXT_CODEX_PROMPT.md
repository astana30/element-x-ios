# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.26E — product-card-only staging smoke passed under the explicit private dogfood gate.

Current checkpoints:
- App code: 2.26E `Enable private dogfood card listener preparation` (`07256bf0a`).
- Call-service LiveKit room pre-create: 2.25E implemented server-side RoomService `CreateRoom` before participant token issuance (`33e95e7b1`).
- Staging iOS activeAudio smoke: 2.25F passed after room pre-create.
- Controlled dogfood runbook: 2.26B updated gates, preflight, rollback, redaction, and session matrix.
- Controlled dogfood matrix: 2.26C passed on the staging media/token/LiveKit path.
- Private dogfood activation gate cleanup: 2.26D replaced the older fake rollout/capability shim with `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Product-card-only staging smoke: 2.26E passed under the explicit private dogfood gate.
- Private native audio dogfood guardrails: `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven/prepared state:
- Production native audio call core works through the DEBUG/integration/private product-gated staging path.
- Private native call card works behind `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- Existing Element Call phone/video buttons remain visible and unchanged.
- Staging call-service readiness passed with `ready=true`, Redis allocation/rate-limit/storage booleans true, and LiveKit room provisioning true.
- A/B trust passed with `ownSessionVerified=true`, `crossSigningReady=true`, `peerTrustReady=true`, and `peerTrustReadiness=peerTrustReady`.
- 2.26C controlled dogfood matrix passed:
  - Happy path A -> B and reverse B -> A reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
  - Repeated calls completed cleanly with no stale active session.
  - Decline incoming, cancel outgoing, and timeout cleared safely with terminal reasons `cancelled`, `outgoingTimeout`, or `incomingTimeout`.
  - Backend-off failed closed with `tokenHTTPUnavailable`, no LiveKit client connect, and cleanup/disconnect attempted.
  - Backend recovery reached A/B `activeAudio` again.
  - Relaunch during active and relaunch during ringing restored no stale active or ringing session.
  - Listener-not-armed behavior was safe: B had no active session and A cancel cleaned up safely.
  - LiveKit-off fail-closed was not run because shared staging LiveKit should not be stopped during this session.
- 2.26D made activation explicit:
  - `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` is DEBUG/integration-only.
  - It requires `IS_RUNNING_INTEGRATION_TESTS=1`, `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`, and `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`.
  - Product UI/start gates alone do not enable activation and still return `appRolloutDisabled`.
  - The legacy `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name no longer enables the app-side activation model.
- 2.26E proved product-card-only staging happy path:
  - Without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation stayed blocked with `appRolloutDisabled`.
  - The blocked run performed no Matrix send, no token/media path, and no LiveKit client connect.
  - With the private dogfood gate, activation enabled with dependencies ready, peer trust ready, and key wrapper available.
  - A Start from the private card -> B incoming ringing -> B Accept from the private card -> A/B `activeAudio` -> hangup -> A/B `idle`.
  - Encryption was ready, media connect and LiveKit client connect were attempted, and `productionMediaFailureReason=none`.
  - Diagnostic runner use was limited to launch, status, activation, and trust polling.
  - Start, Accept, and Hang up were manual product-card taps.
  - Element Call route remained untouched.
- Runtime issue fixed in `07256bf0a`:
  - The private product card now prepares/arms the receiver listener from card status only when private dogfood activation is already enabled.
  - Listener preparation does not start outgoing calls, request tokens, send Matrix events, or connect media.
  - Listener preparation does not run without the private dogfood gate.
- Controlled engineering dogfood may continue for named engineers on staging only.
- Broad internal dogfood, public beta, public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global production activation remain blocked.
- Production Matrix SDK key envelope wrapping is integrated through a narrow provider seam and preserves `OnlyTrustedDevices` policy.
- SalemX call-service staging guardrails are in place: explicit service mode, fake-mode blocking, redacted readiness, Redis allocation/rate-limit config validation, memory store blocking in staging, storage-key secret requirement, and LiveKit room pre-create.
- Operator-local deploy and smoke env files are ignored by git and must not be committed or pasted.

Phase:
2.27A — controlled engineering dogfood pilot runbook/final checkpoint.

Task:
Prepare the final controlled engineering dogfood pilot checkpoint for the private native audio staging path. This is inspection/docs-first unless a small runbook correction is needed. Do not modify app or backend code unless explicitly approved.

Goal:
Turn the proven 2.25F, 2.26C, 2.26D, and 2.26E results into a narrow pilot-ready checklist with clear ownership, gates, stop criteria, monitoring/redaction checks, rollback, and reporting format.

Hard constraints:
- No raw tokens, JWTs, keys, Matrix access tokens, Synapse admin tokens, room IDs, user IDs, peer IDs, device IDs, Redis credentials, Matrix event bodies, or full request/response bodies in output or docs.
- No Element Call route changes.
- No CallKit, push/background incoming, missed calls, video, session restoration, public rollout, broad internal rollout, or global production activation.
- Do not weaken trusted-device/E2EE behavior.
- Do not touch shared LiveKit server config unless separately approved.
- Keep env files ignored and local-only.

Required pilot scope:
- Named engineering operators only.
- DEBUG/integration builds only.
- Foreground/open encrypted direct 1:1 rooms only.
- Verified/trusted peers only.
- Private native audio card only.
- Staging call-service and staging LiveKit only.
- Existing Element Call route remains visible and available as fallback.

Required gates:
- `IS_RUNNING_INTEGRATION_TESTS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging call-service>`

Required output:
A. Pilot readiness decision.
B. Operator preflight checklist.
C. Allowed pilot session matrix.
D. Required redacted reporting fields.
E. Stop criteria.
F. Rollback path.
G. Monitoring and secret-rotation checklist.
H. Remaining blockers before broader dogfood or production.
I. Whether docs/code changed.

Validation if docs change:
- `git diff --check`.
- Docs-only diff.
- Docs secret scan.
- Direct-call forbidden scan.

Suggested commit if docs change:
Prepare native audio dogfood pilot checkpoint
