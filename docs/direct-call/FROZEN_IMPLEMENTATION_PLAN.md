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

Stage 2B added the compile-time seam `EmbeddedElementCallHandoff` and the conservative production adapter `EmbeddedElementCallProductionHandoff`.

- `startNew` maps to the existing embedded Element Call room-call presentation path with `ElementCallStartMode.audio`.
- `presentExisting` is allowed only when the existing Element Call service state already reports the same room.
- `joinExisting` is explicitly unsupported until a proven programmatic incoming MatrixRTC join operation is wired; it must never fall back to starting a new call.
- The seam exposes no LiveKit URLs, JWTs, room aliases, participant identities, media keys, Matrix access tokens, widget URLs, or remote SPA URLs.
- The seam is not wired to PushKit or CallKit answer handling, and the current SalemX direct LiveKit production route remains unchanged.

Stage 2C should bind authenticated SalemX metadata and a verified DM room into this seam without changing the join semantics or reintroducing direct LiveKit media.

Stage 2C added `SalemXAuthenticatedMatrixRTCHandoff` as a narrow authenticated metadata-to-room adapter.

Stage 2C-R2 also repaired the MatrixRustSDK packaging contract without changing the binary payloads or regenerated bindings. The verified `packagingfix1` XCFramework asset is pinned through wrapper commit `a4d568701a249bb7d1e8019ed6fef9ebf4a2c461`, with release asset hash `f9ace1c50d7facf73c80feae349e8317de4d229ee21b53e91e2083e25124669c`. Release governance remains open because the release metadata is not immutable, but the build and focused handoff tests now pass against the repaired artifact.

```text
release_asset_published=true
release_asset_hash_verified=true
release_metadata_immutable=false
release_immutability_debt=open
```

- The adapter accepts already-claimed SalemX MatrixRTC metadata containing only the redacted-bound room/user/device shape needed for room validation.
- The local authenticated Matrix user must match the claimed local user before any room lookup is attempted.
- The target room must resolve to a joined room, match the claimed room ID, be a one-to-one direct room, and contain both local and peer users.
- Valid metadata delegates to the Stage 2B `EmbeddedElementCallHandoff` with the caller-supplied handoff intent; unsupported incoming `joinExisting` semantics remain unchanged and never fall back to `startNew`.
- The adapter does not request media credentials, construct LiveKit URLs or JWTs, touch PushKit or CallKit answer handling, load a remote Element Call SPA, or emit Matrix call media events.
- Metadata and adapter result descriptions redact room IDs, user IDs, and device IDs.

Stage 2D bridges CallKit answer to this adapter behind `embeddedMatrixRTCAnswerBridgeEnabled=false` by default. The actual production answer entry point is `ElementCallService.provider(_:perform: CXAnswerCallAction)`, which previously fulfilled the action before sending the legacy `.startCall(roomID:startMode:)` route. With the gate enabled only in tests, Stage 2D resolves an already-claimed `VerifiedIncomingCallBootstrap`, requires CallKit UUID, room, authenticated user, device and active MatrixRTC evidence to match, then calls `SalemXMatrixRTCHandoff` only with `.presentExisting`.

The typed answer result distinguishes presentation success, already-presented success, missing authenticated session, identity mismatch, device mismatch, DM lookup failures, missing active MatrixRTC call, unsupported incoming join, bootstrap absence or mismatch, timeout, cancellation and failure. `presentationAccepted` and `alreadyPresented` fulfill the CallKit answer exactly once; every typed failure, timeout or cancellation fails exactly once. Duplicate answer actions for the same UUID share one in-flight task and cannot present twice.

Stage 2D does not claim metadata again, trust raw PushKit payload room IDs, request direct LiveKit credentials, join LiveKit, send APNs, connect media, request microphone or camera permission, enable video, synthesize connected state from CallKit, change PushKit ingress or remove the old direct-call implementation. The bridge uses audio-only `EmbeddedElementCallPreparation.audio` and leaves media readiness to upstream MatrixRTC / embedded Element Call.

Stage 2E synchronized local CallKit End and upstream MatrixRTC terminal lifecycle behind the same disabled-by-default gate. The actual production End entry point is `ElementCallService.provider(_:perform: CXEndCallAction)`. With `embeddedMatrixRTCAnswerBridgeEnabled=false`, the legacy End route remains unchanged. With the gate enabled only in tests, the service resolves the already-verified bootstrap for the CallKit UUID, invokes `SalemXEmbeddedCallEndBridge`, and delegates accepted termination to the existing embedded Element Call termination route through `ElementCallService.requestCallTermination(roomID:)`.

The typed End result distinguishes accepted termination, already terminated, missing or mismatched bootstrap, missing authenticated session, unavailable DM room, no active MatrixRTC call, unsupported termination, timeout, cancellation and failure. Accepted or already-terminated results fulfill `CXEndCallAction` exactly once; typed failure, timeout or cancellation fails exactly once. Duplicate End actions share one bounded in-flight guard, racing local/remote terminal events report CallKit ended at most once, and provider reset releases guards and clears verified bootstrap state idempotently.

Remote and local upstream terminal events are accepted only from existing Element Call / MatrixRTC observation paths: widget hangup/close, ongoing call timeline termination events and ongoing call room-info disappearance. CallKit does not synthesize MatrixRTC connected or ended state from answer fulfillment, screen presentation, CallKit UI disappearance or audio-session interruption. Embedded End does not send manual Matrix hangup events, invoke legacy direct LiveKit hangup, request microphone or camera permission, start media, send APNs, access the server, alter PushKit ingress, or enable the bridge by default.

Stage 2F may start only after the Stage 2E gate remains disabled by default, legacy answer and End routes are proven unchanged when disabled, incoming answer still selects `presentExisting` and never `startNew`, local End invokes upstream embedded termination, remote End reports CallKit ended once, duplicate and racing End events are idempotent, provider reset cleanup is safe, no manual Matrix hangup or direct LiveKit hangup occurs, and the UnitTests target compile, Stage 2E focused tests, Stage 2D answer-bridge regression and Stage 2C handoff regression all pass.

## Stage 2F-SIM-R2D Foreground-Only Server Contract

Stage 2F-SIM remains an intermediate simulator-to-device signaling proof only. It has not passed yet, and it does not replace the later two-physical-device Stage 2F audio proof.

The first controlled Stage 2F-SIM attempt used the real authenticated foreground-signaling invite route and sent exactly one invite, but the production foreground invite endpoint also invoked sandbox APNs even when foreground stream delivery succeeded. That made the no-APNs Stage 2F-SIM acceptance impossible with the existing server contract. The result was classified as a server/API contract gap, not a stale marker, and no authenticated invite was sent during R2, R2B, R2C or R2D.

R2 adds an explicit authenticated `delivery_mode` request field to `POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite`:

```text
missing delivery_mode=foreground_and_apns
delivery_mode=foreground_and_apns preserves legacy foreground plus APNs behavior
delivery_mode=foreground_only delivers only to the validated foreground stream
```

`foreground_only` requires an active foreground stream bound to the exact validated recipient user, recipient device and current stream lease. If no exact stream is present, the route fails closed with a conflict/precondition response, does not attempt foreground delivery, does not request APNs, does not invoke the APNs provider and never falls back to APNs. If the stream disappears after metadata claim, the server returns a typed delivery failure, consumes the metadata through the existing single-claim/anti-replay boundary, does not make metadata reusable and still does not invoke APNs.

The response now contains a privacy-safe server-generated `delivery_attempt_id`. It is random, opaque, not derived from user, room, metadata or device identifiers, has no security authority and exists only for request-scoped proof. Successful `foreground_only` diagnostics must report foreground delivery success with `apns_requested=false`, `apns_provider_invoked=false`, `apns_provider_accepted=false` and `APNs_sent=false`.

The iOS DEBUG Stage 2F-SIM sender explicitly requests `delivery_mode=foreground_only`. Release/default clients preserve the legacy behavior by omitting the field unless intentionally migrated later. The embedded MatrixRTC answer bridge remains disabled by default and is enabled only by explicit DEBUG override for the controlled receiver.

Validation and deployment evidence:

```text
server_tests=181_passed
ios_focused_tests=62_passed
local_app_matches_deployed=true
local_foreground_signaling_matches_deployed=true
local_pending_metadata_matches_deployed=true
deployed_app_py_sha256=2ed83fc6c1416526b94f79715d3e034c25bcc220bd7c6f97ee1bf7d6e7089746
deployed_foreground_signaling_py_sha256=edbc7437923df7cba5114d79b6c7d44376227f7dd5d1791e2ba461e22c19c2bf
deployed_pending_call_metadata_py_sha256=aeaf6ab120598e0f1c893c7466f107e543793b2abd06fb6510aeafe4efe11cb0
```

The first privileged deployment rolled back because of a validator bug: a brittle post-static assertion looked for the legacy-default enum in the wrong file. The second deployment passed candidate/static validation and changed the three call-service files, but reported failure because localhost readiness was probed before port `8091` opened. Delayed R2C/R2D acceptance proved the candidate remained deployed and healthy; systemd became active before Uvicorn opened the socket, with an observed readiness gap of approximately two seconds. The corrected local deployment validator now uses bounded readiness polling, explicit curl failure handling and rollback readiness verification. The old R2B archive still contains macOS extended-attribute headers and must not be reused.

Aborted Stage 2F-SIM cleanup was checked before accepting R2D. The sender simulator showed no active call UI, iPhone PRO was connected and unlocked, no LiveKit/call-service sockets were established, and existing client stale-membership markers were false. Unprivileged LiveKit admin room listing was not available without reading secrets, so no raw room or participant identifiers were inspected or printed.

Current Stage 2F status after R2D:

```text
foreground_only_contract_created=true
legacy_default_preserved=true
exact_foreground_stream_required=true
no_stream_fails_closed=true
apns_fallback_disabled=true
request_scoped_delivery_id_present=true
stage_2f_simulator_signaling_passed=false
physical_two_way_audio_proven=false
physical_stage_2f_still_required=true
stage_2g_ready=false
```
