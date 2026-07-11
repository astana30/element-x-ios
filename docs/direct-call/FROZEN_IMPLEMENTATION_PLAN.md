# SalemX Secure Calls Plan v1.0

Status: frozen Stage 0 plan.

Baseline:
- Branch: `salemx-2.47a-controlled-media-credentials-boundary`
- Baseline HEAD before Stage 0 edits: `95ee90544faa2ea7d64993c8187deaa6f83e5537`
- Baseline commit subject: `Add deterministic direct-call proof state machine`

## Fixed Architecture

- SalemX keeps PushKit as the physical incoming-call ingress.
- SalemX keeps native CallKit for system incoming-call UI, answer, end, and lifecycle.
- SalemX keeps secure server metadata prepare/claim/send semantics: sender/device binding, expiry, anti-replay, authentication recheck, and redacted diagnostics.
- Normal production media moves to upstream embedded Element Call / MatrixRTC.
- MatrixRTC becomes the sole production call-state authority.
- Embedded Element Call becomes the sole production media and E2EE implementation.
- v1 is audio-only.
- v1 does not use a dynamic remote Element Call SPA.
- v1 does not keep a direct LiveKit production fallback.
- v1 does not include video or group calling.

## Stage Plan

### Stage 0: Freeze Current Implementation

Document the current implementation, ownership boundaries, race boundaries, and migration plan. Stage 0 is documentation-only and must not change runtime behavior.

### Stage 1: Define MatrixRTC Integration Contract

Define the SalemX-to-Element-Call handoff contract for incoming PushKit metadata, outgoing call intent, authenticated Matrix session, room selection, audio-only start mode, CallKit answer, hangup, and redacted diagnostics.

### Stage 2: Add Adapter Seam

Introduce the smallest adapter seam needed to route SalemX direct-call lifecycle events into embedded Element Call / MatrixRTC behind explicit disabled-by-default gates. Preserve the existing Element Call route and all current debug proof helpers.

### Stage 3: Move Metadata Authority Into The MatrixRTC Handoff

Bind prepared metadata and sender/device claim results to the MatrixRTC call context instead of custom direct LiveKit proof state. Keep server auth, expiry, anti-replay, and redacted failure buckets.

### Stage 4: Integrate Embedded Element Call Audio-Only Media

Use embedded Element Call as the audio and E2EE implementation for the controlled SalemX path. Do not enable camera, video, group calling, or a direct LiveKit production fallback.

### Stage 5: Migrate Incoming And Outgoing Lifecycles

Move incoming answer and outgoing start lifecycles onto MatrixRTC as the state authority. Keep PushKit and CallKit native, but remove duplicate media-state decisions from proof helpers.

### Stage 6: Retire Custom Direct LiveKit Production Path

After the physical acceptance matrix passes, remove the custom direct LiveKit production fallback. Keep only explicitly scoped DEBUG proofs that remain useful for diagnostics.

### Stage 7: Production Hardening And Rollout Gates

Finalize diagnostics, cleanup semantics, hangup behavior, recovery behavior, and rollout gates. Require the full physical acceptance matrix before production enablement.

## Acceptance Definition

The plan is complete only when the predefined physical acceptance matrix passes in full with redacted proof:
- PushKit delivery through SalemX ingress.
- CallKit report, answer, active UI retention, and end behavior.
- Secure metadata prepare/claim/send gates.
- MatrixRTC-controlled call state.
- Embedded Element Call audio and E2EE.
- Two-way audio.
- Hangup cleanup.
- No camera, video, group calling, Matrix call media event emission, production APNs from debug helpers, or direct LiveKit production fallback.

One successful physical call is not sufficient for completion.

## Stage Guardrails

- Do not skip or combine stages without an explicit change request.
- Use a narrow file allowlist for every stage.
- Make one logical commit per stage.
- Run targeted tests or report why they are unavailable.
- Stop on failed gates.
- Keep all logs and docs redacted.

## Current Server Gate

MatrixRTC server stabilization is complete as of Stage `1D-R4`:

- The authorization service is running the qualified healthfix image `salemx/lk-jwt-service:ac7d0de49060b0cabe25925c4b671d5e8f637567-healthfix1`.
- The public MatrixRTC authorization routes `/livekit/jwt/sfu/get` and `/livekit/jwt/sfu_webhook` are present.
- The SalemX foreground-signaling contract remains unchanged: production invite and stream routes reject unauthenticated probes, and the development invite route remains disabled.
- External Redis, LiveKit HTTP, and authorization ports were not reachable from outside the server.
- The nginx duplicate `matrix.mertis.kz` server-name warning is classified as cleanup recommended, not blocking.

Stage 2 embedded Element Call migration is unblocked by Stage `1D-R6` functional MatrixRTC server acceptance:

- Two upstream Element Call / MatrixRTC reference calls completed successfully.
- Each call had two participants.
- The room was cleaned up after the calls.
- No stale MatrixRTC membership or repeated-call trail was detected.
- Public webhook transport evidence is strong: 23 public webhook POSTs since the preflight cursor returned 2xx and none returned non-2xx.
- Redis delayed jobs were not applicable because delayed-event delegation was not used.

This does not accept or preserve custom SalemX direct LiveKit media. Stage 2 remains scoped to embedded Element Call migration only.

Production rollout remains blocked on a privacy-safe MatrixRTC webhook observability debt. A future narrow stage must add aggregate counters for webhook requests, signature-valid and signature-invalid requests, participant joins, participant leaves, and processing errors without exposing identifiers, tokens, request bodies, headers, or secrets.

## Stage 2A iOS Migration Boundary

Stage 2A audited the local iOS source and recorded the minimal embedded Element Call migration boundary in `docs/direct-call/IOS_EMBEDDED_ELEMENT_CALL_AUDIT.md`.

The selected seam is to keep SalemX secure metadata, PushKit and CallKit as bootstrap and OS presentation layers, then adapt the accepted CallKit answer path to call the existing embedded Element Call room-call entry point with a verified DM room and `startMode: .audio`.

The target path must use the pinned bundled `EmbeddedElementCall` package and MatrixRTC widget driver. It must not use a dynamic remote Element Call SPA, construct LiveKit JWTs on iOS, directly join LiveKit from SalemX code, keep `DirectCallEngine` as production state authority, or preserve a direct LiveKit production fallback.

Stage 2B may start with a compile-time seam only. It must not send APNs, connect media, request camera, enable video, or remove the old direct LiveKit code before the replacement path passes repeated-call acceptance.
