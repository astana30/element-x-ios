# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.39X — operational monitoring automation design.

Task:
Inspection/design only. Do not modify app/backend code. Do not commit unless a docs-only decision update is explicitly requested.

Context:
- 2.39T added the post-pilot hardening plan and paused additional non-engineering pilot windows.
- 2.39V implemented foreground/open-chat limitation UX polish for the private native audio card.
- 2.39W proved the UX polish at runtime:
  - the foreground/open-chat limitation copy was visible on A/B;
  - no backend/token/LiveKit/raw-ID/request/response wording appeared in visible copy;
  - Element Call phone/video fallback controls remained visible and unchanged;
  - rendering/status refresh alone did not send Matrix events, request tokens, connect media, connect LiveKit, or create an active session;
  - a short internal-pilot A -> B smoke reached active audio and returned A/B idle/no active session with media failure none.
- Additional non-engineering pilot windows, participant/device expansion, broad internal rollout, production/public rollout, unsupervised dogfood, CallKit/push/background incoming, missed-call UX, video, session restoration, Element Call replacement, and global activation remain blocked.

Goal:
Design the redacted operational monitoring automation workstream that should replace or augment runner/report-only monitoring before any future pilot expansion is reconsidered.

Inspect:
- docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md
- docs/direct-call/STATUS.md
- docs/direct-call/WORKLOG.md
- server/salemx-call-service/docs/STAGING_SMOKE_2026-05-21.md
- Tools/Scripts/run_native_direct_call_diagnostic_two_client.sh
- ElementX/Sources/FlowCoordinators/RoomFlowCoordinator.swift
- ElementX/Sources/Screens/RoomScreen/RoomScreenModels.swift
- ElementX/Sources/Services/DirectCall if needed
- server/salemx-call-service/salemx_call_service service/config/eligibility/token paths if needed

Questions:
1. Which runner/status fields should become the minimum redacted monitoring contract?
2. Which fields should remain runner-only and not become product telemetry?
3. What dashboard/log-safe telemetry shape is acceptable without raw room/user/device IDs, tokens, JWTs, LiveKit room names, media keys, Redis credentials, Matrix event bodies, backend URLs with credentials, or request/response bodies?
4. What alert-worthy states should be automated first?
5. How should incidents be correlated without raw identifiers?
6. What local, staging, and future production boundaries are required?
7. What tests and runtime proof are required before implementing monitoring automation?
8. What should remain blocked until monitoring automation exists?

Candidate safe fields:
- readiness booleans
- activationSource
- internalPilotActivationDecision
- internalPilotActivationReason
- tokenStatus
- tokenErrcode
- tokenReason
- tokenIssued
- liveKitRoomPrecreateAttempted
- productionLiveKitFailureReason
- productionMediaFailureReason
- productionSessionState
- productionHasActiveSession
- terminal reason enum
- cleanup/disconnect booleans

Alert-worthy states:
- `tokenBackendRejected`
- `liveKitNetworkFailed`
- split-brain
- stale active session
- readiness not `ready=true reason=ok`
- `tokenIssued=false` for an otherwise eligible call
- media failure not fail-closed
- redaction leak

Hard constraints:
- Do not approve additional non-engineering pilot windows.
- Do not approve participant/device expansion.
- Do not approve broad internal rollout.
- Do not approve production/public rollout.
- Do not approve unsupervised dogfood.
- Do not replace Element Call toolbar.
- Do not implement CallKit/push/background incoming in this phase.
- Do not add video.
- Do not globally activate production direct calls.
- Do not weaken trusted-device/E2EE behavior.
- Do not use `directOneToOneCallsEnabled` as the native audio gate.
- Token endpoint remains final authority.
- No raw IDs/secrets/tokens in reports or proposed telemetry.

Expected output:
A. Files inspected.
B. Recommended monitoring contract.
C. Alert model.
D. Redaction/correlation strategy.
E. Required tests.
F. Required runtime proof.
G. Recommended next implementation phase.
