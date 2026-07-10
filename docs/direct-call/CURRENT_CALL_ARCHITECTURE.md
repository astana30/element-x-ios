# Current SalemX Call Architecture

Status: frozen Stage 0 map. This document describes the current implementation as observed in code and repository docs. It does not change behavior.

Baseline:
- Branch: `salemx-2.47a-controlled-media-credentials-boundary`
- Baseline HEAD before Stage 0 edits: `95ee90544faa2ea7d64993c8187deaa6f83e5537`
- Baseline commit subject: `Add deterministic direct-call proof state machine`

## Code Paths

### Native PushKit And CallKit

- `ElementX/Sources/Services/ElementCall/ElementCallService.swift` owns the normal Element Call PushKit registry and CallKit provider delegate.
- The PushKit token update path records a DEBUG SalemX token upload proof, then calls the normal VoIP pusher registration flow.
- The incoming PushKit callback first lets the SalemX DEBUG bridge consume SalemX proof payloads when enabled. Otherwise it parses the normal Element Call payload, opens a CallKit session, reports an incoming call, and completes the PushKit callback.
- `CXAnswerCallAction` fulfills the system answer action, ends the temporary CallKit session after a short delay, then emits `.startCall(roomID:startMode:)` so the app opens the embedded Element Call screen.
- `CXEndCallAction`, provider reset, and audio session activation/deactivation remain in the Element Call service boundary.

### Embedded Element Call Route

- `ElementX/Sources/Services/ElementCall/ElementCallConfiguration.swift` models generic call links and internal room calls with `ElementCallStartMode`.
- `ElementX/Sources/Screens/CallScreen/CallScreenViewModel.swift` builds the embedded Element Call widget URL and calls `setupCallSession`.
- `ElementX/Sources/Screens/CallScreen/View/CallScreen.swift` hosts `EmbeddedElementCall` in a `WKWebView` and overlays native direct-room audio or video chrome based on start mode.
- The embedded Element Call path already exists and must remain intact during migration.

### Custom Direct-Call Engine

- `ElementX/Sources/Services/Calls/DirectCallEngine.swift` owns a custom `DirectCallSession`, transitions session state, emits invite/answer/reject/cancel/hangup/timeout signals, requests media credentials, connects media when encryption and answer state are ready, and schedules cleanup.
- `ElementX/Sources/Services/Calls/DirectCallSignalTransport.swift` encodes and decodes custom direct-call Matrix room signals and provides Matrix-backed and in-memory transports.
- `ElementX/Sources/Services/Calls/DirectCallMediaEngineProtocol.swift` defines the custom media engine contract: prepare audio, connect audio, microphone, remote playback, speaker, disconnect, cleanup, and media credential boundary.
- `ElementX/Sources/Services/Calls/LiveKitDirectCallMediaEngine.swift` implements that contract over direct LiveKit credentials and a direct LiveKit client.
- `ElementX/Sources/Services/Calls/LiveKitDirectCallClient.swift` owns the direct LiveKit room, E2EE context, remote participant snapshot, remote audio subscription, disconnect, and cleanup.
- `ElementX/Sources/Services/Calls/MatrixSDKDirectCallMediaKeyWrapper.swift` wraps Matrix SDK media keys for the custom direct-call E2EE path.

### DEBUG Physical Proof Adapter

- `ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift` is the large DEBUG proof surface for SalemX physical direct-call work.
- It owns CallKit proof events, PushKit receipt proof, prepared metadata proof, sender claim and media credential proof, direct LiveKit join proof, sender and receiver local audio proof, remote subscription proof, active UI retention proof, and hangup cleanup proof.
- It now contains `SalemXDirectCallProofStateMachine`, a small internal proof-state model with sender LiveKit join, sender local audio publish pending/published/failed, receiver answer, receiver LiveKit join, receiver local audio published, sender visibility, two-way audio, and hangup cleanup buckets.
- Repository status/worklog docs show the latest fragile areas were receiver local publish, sender local publish, remote subscription, receiver lease retention, and visibility/cleanup ordering.

### Physical Helpers

- Historical `/tmp` helpers and `/Users/aibattt/salemx-helpers/` backups are not source-of-truth production code.
- They orchestrate physical-device proof runs, manual SEND gates, token/session checks, receiver idle checks, APNs max-one gates, and redacted proof collection.
- Stage 0 did not run any physical helper.

### Server Boundary

- The repo-side iOS code assumes a SalemX call service that prepares metadata, binds sender and device claims, rechecks auth, sends at most one sandbox APNs in gated helpers, and serves media credentials.
- Server implementation is outside the allowed Stage 0 file set and was not modified.

### Dependencies

- `project.yml` pins `EmbeddedElementCall` by exact version.
- `project.yml` pins direct `LiveKit` by exact version for the current custom direct media path.
- `project.yml` pins `MatrixRustSDK` by revision.
- `Package.resolved` exists and was not modified.

## Current Flow

1. Sender-side helper or app context resolves Matrix sessions and a shared room.
2. Server prepare/claim flow creates redacted pending metadata and binds sender/device identity.
3. Sender media credentials are requested before SEND in the controlled proof path.
4. A manual SEND gate allows exactly one sandbox APNs in physical helpers.
5. PushKit delivers the VoIP payload to the receiver app.
6. Receiver CallKit report creates the answer window.
7. Receiver answer action is observed by CallKit.
8. Receiver metadata and media credentials are resolved.
9. Custom direct LiveKit joins and local audio publishes are driven by DEBUG proof and direct media paths.
10. Remote audio subscription is detected through direct LiveKit snapshots/callbacks.
11. Active UI retention and hangup cleanup are validated by DEBUG proof buckets.
12. Cleanup tears down local audio, remote subscription, direct LiveKit room, CallKit state, and proof leases.

## Ownership Map

| State or action | Current owner/path | Boundary risk |
| --- | --- | --- |
| PushKit token registration | `ElementCallService` plus DEBUG SalemX bridge | Two registries/proof paths have existed historically; current normal owner is Element Call service. |
| PushKit receipt proof | DEBUG bridge and proof adapter | Proof payload interception is separate from normal Element Call payload parsing. |
| CallKit report/answer/end | `ElementCallService` and `NativeIncomingSyntheticCallKitUIProofAdapter` | Normal CallKit service and DEBUG proof adapter both classify call lifecycle. |
| Prepared metadata and sender claim | Server boundary plus DEBUG helper/proof adapter | iOS proof state depends on redacted server buckets and helper gates. |
| Sender local publish | Direct LiveKit client/proof adapter | Latest failure class shows sender publish can be missing while receiver publish succeeds. |
| Receiver local publish | Direct LiveKit client/proof adapter | Hydration and dispatch are proven in recent work but still tracked outside MatrixRTC. |
| Receiver lease release | DEBUG proof adapter | Lease release is coupled to visibility, terminal failure, and cleanup buckets. |
| Both-local gate | DEBUG proof adapter | Gate can be affected by stale or competing sender/receiver proof buckets. |
| Sender remote subscribe | Direct LiveKit client snapshots/callbacks and proof adapter | Subscription readiness can race with publication visibility and retained room binding. |
| Final classification | Physical helper plus DEBUG proof summary | Final status is derived from many proof buckets rather than a production call-state authority. |
| Hangup cleanup | `DirectCallEngine`, `LiveKitDirectCallMediaEngine`, `LiveKitDirectCallClient`, `ElementCallService`, DEBUG proof adapter | Multiple cleanup owners can classify or trigger teardown. |

## Race And Ownership Boundaries

- Direct-call state authority is split between `DirectCallEngine`, `LiveKitDirectCallMediaEngine`, `LiveKitDirectCallClient`, `ElementCallService`, physical helpers, and the DEBUG proof adapter.
- The embedded Element Call path exists, but the SalemX secure-call proof path still has a separate custom direct LiveKit media implementation.
- Local audio publish and remote subscribe are not owned by MatrixRTC today; they are inferred from direct LiveKit effects and proof buckets.
- Receiver lease retention is a proof-layer concept and can race sender visibility, remote subscription, terminal failure, and cleanup.
- CallKit answer flows exist both in normal Element Call service and in the DEBUG synthetic proof adapter.
- Matrix room direct-call signal transport exists alongside Element Call / MatrixRTC call event handling.
- Hangup cleanup can be reached through direct engine terminal events, direct media cleanup, LiveKit client cleanup, CallKit end, and DEBUG proof cleanup.
- Current worklog/status evidence shows the failure moved among receiver publish rendezvous, metadata hydration, receiver lease retention, both-local gate, sender local publish, sender remote subscribe, UI retention, and hangup cleanup.

## Migration Boundary

The minimal migration target is not another proof-bucket patch. The production call state should move to MatrixRTC through embedded Element Call while SalemX retains PushKit ingress, native CallKit, secure metadata claim, and redacted diagnostics.

Unknowns that require later stages:
- Exact embedded Element Call / MatrixRTC API seam for SalemX metadata claim handoff.
- Exact MatrixRTC event surface needed for audio-only direct-call state.
- Exact cleanup mapping from current direct LiveKit proof buckets to Element Call / MatrixRTC lifecycle.
- Whether every DEBUG proof helper should remain after the custom direct LiveKit production path is removed.
