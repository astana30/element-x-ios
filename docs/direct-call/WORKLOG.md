# Native Direct-Call Worklog

This file records durable phase-level progress for future Codex and strategy sessions.

## Milestones

- Hardened foreground native incoming audio lifecycle after the one-device smoke.
- Added the foreground native incoming call E2E coordinator contract.
- Recorded supervised narrow non-engineering pilot window 1.
- Completed the label-only pilot checklist for execution approval re-review.
- Recorded the incomplete pilot checklist completion attempt.
- Documented the blocked non-engineering pilot execution approval and remediation checklist.
- Added the narrow non-engineering internal pilot preparation runbook.
- Recorded the internal pilot operational proof and kill-switch rehearsal.
- Added the internal pilot operational readiness and kill-switch plan.
- Recorded engineering-only internal pilot activation soak session 3 rerun.
- Recorded the 2.37E-blocker caller media setup failure split-state fix.
- Recorded engineering-only internal pilot activation soak session 2.
- Recorded engineering-only internal pilot activation soak session 1.
- Added the engineering-only internal pilot activation soak plan.
- Recorded the internal pilot trigger dry-run observability alignment.
- Recorded the engineering-only internal pilot activation runtime proof.
- Recorded the internal pilot activation skeleton no-activation runtime proof.
- Added the native audio internal pilot activation provider skeleton.
- Recorded the first operator-owned engineering expansion session.
- Added the engineering expansion operations handoff and monitoring baseline.
- Completed the 3-session engineering expansion soak.
- Recorded engineering expansion soak session 3.
- Recorded engineering expansion soak session 2.
- Recorded engineering expansion soak session 1.
- Added the short engineering expansion soak plan after the 2.33E pilot rerun.
- Recorded the narrow engineering expansion pilot session 1 rerun after the timeout cleanup fix.
- Recorded the direct-call timeout cleanup fix and runtime proof.
- Polished native audio eligibility status redaction and recorded the runtime proof.
- Added the narrow engineering expansion pilot runbook and participant/device matrix.
- Recorded the eligibility status controlled engineering soak.
- Hardened call-service readiness so Redis connected booleans require bounded live Redis pings in staging.
- Recorded the Redis readiness recovery native audio smoke.
- Added the iOS native audio eligibility provider skeleton for the backend `/eligibility` endpoint.
- Recorded the eligibility contract runtime/no-activation proof.
- Added the fail-closed internal pilot eligibility contract skeleton.
- Documented the redacted pilot monitoring/status contract.
- Hardened private native audio card failure copy and DEBUG-only redacted card status.
- Recorded the controlled engineering dogfood matrix result on the staging media/token/LiveKit path.
- Recorded the broader internal dogfood hardening plan.
- Recorded controlled engineering dogfood pilot session 2.
- Recorded controlled engineering dogfood pilot session 1.
- Added the controlled dogfood operations and monitoring checklist.
- Recorded the controlled dogfood pilot matrix rerun after the split-brain fix.
- Recorded the repeated-call split-brain regression runtime proof after the post-answer callee media failure fix.
- Added the final controlled engineering dogfood pilot checkpoint.
- Recorded the product-card-only staging smoke under the explicit private dogfood gate.
- Replaced the unclear DEBUG fake rollout/capability shim with an explicit private dogfood activation gate.
- Updated the controlled engineering dogfood runbook and staging session matrix after the 2.25F activeAudio pass.
- Proved staging iOS private native audio can reach active audio through the product-gated private card.
- Added server-side LiveKit room pre-create in SalemX call-service before participant token issuance.
- Added Matrix SDK-backed custom content accessor for direct-call message-like events.
- Added and pinned the SDK custom timeline filter so the native direct-call receive path can observe the custom message-like signal event without changing the visible RoomScreen timeline.
- Hardened receive semantics so historical timeline reset/backlog direct-call events are ignored and only live post-baseline events are delivered to the engine.
- Proved two-client Matrix signalling end-to-end: invite, incoming ringing, accept, answer, and hangup/cleanup diagnostics.
- Proved diagnostic LiveKit media path can reach active under DEBUG/integration-only gates.
- Added production-shaped dependency seams for token, encryption, and media dependencies while keeping them fail-closed and inactive by default.
- Drafted the backend LiveKit token API contract for native direct calls.
- Added the SalemX call service backend skeleton for LiveKit token allocation.
- Added Synapse-backed room validation skeleton for requester/peer membership, encrypted room eligibility, and one-to-one validation.
- Added local backend fake smoke mode for the call service.
- Added app-side production token backend smoke coverage through an env-gated, disabled-by-default test harness.
- Added fail-closed app-side production media-key wrapping seams and shared LiveKit E2EE key-store injection hooks.
- Inspected Matrix Rust SDK crypto and FFI surfaces for a narrow production direct-call media-key wrapping seam.

### 2.41A-S — One-device foreground native incoming smoke

Ran a supervised foreground smoke using an iOS Simulator caller and a physical iPhone callee. The callee app was open in foreground. The physical iPhone displayed the system CallKit incoming-call UI, Answer worked, media connected, and End cleared the call. No app crash was observed.

Observed follow-up items:
- Repeating audio tick/click artifact during connected media.
- Peer-side call cleanup delay of approximately 10 seconds after End.
- Full two-physical-device smoke remains pending.

No raw runtime logs were added because they may contain private Matrix/runtime identifiers.

### 2.41B — Foreground audio and call lifecycle hardening

Implemented scoped lifecycle hardening for the foreground native incoming call path.

Changes:
- Duplicate answered-call handling no longer creates duplicate media connections once the call is already active.
- A second connect attempt while media connection is already in progress fails closed with a safe local reason.
- End is idempotent.
- Local incoming state is cleared before async media teardown is awaited.
- Repeated foreground incoming calls reset lifecycle state after End.

The repeating audio tick/click artifact is not yet proven fixed. The next physical smoke must verify whether the lifecycle hardening removes it or whether a deeper audio route/session/WebRTC investigation is required.

The peer-side cleanup delay is addressed locally in the foreground coordinator, but still needs physical smoke confirmation.

No PushKit/APNs runtime, APNs/VoIP value registration, background incoming handling, server-issued media credential bypass, Matrix event emission, Element Call route change, LiveKit/MatrixRTC production path rewrite, signing change, bundle change, entitlement change, project setting change, video, broad rollout, or production/public rollout was added.

## 2026-06-09 — 2.41A Foreground Native Incoming Call E2E

- Added a foreground-only native incoming call E2E coordinator contract.
- The coordinator accepts foreground incoming ringing audio sessions, safe CallKit display metadata, a validation context, the isolated CallKit adapter, the foreground acceptance gate, an injected media connector, and redacted diagnostics.
- The CallKit UI path is requested only for valid foreground incoming ringing audio sessions.
- CallKit answer routes to `answerRequested`, then the foreground acceptance gate must authorize before media can be attempted.
- Missing, denied, malformed, expired, and unverifiable authority decisions fail closed and block media.
- Authorized authority allows only the injected media connector to run; unit coverage verifies media is not attempted before authorization.
- End clears local state and tears down started media through the injected connector.
- Mute remains local and diagnostic-only.
- Added `docs/direct-call/FOREGROUND_NATIVE_INCOMING_E2E.md` with a physical-device smoke checklist for a later supervised proof.
- No PushKit/APNs runtime, value registration, background incoming handling, Element Call route change, LiveKit/MatrixRTC production path change, signing/project setting change, production UI, video, broad rollout, or production/public rollout was added.

## 2026-05-28 — 2.39I Supervised Narrow Non-Engineering Pilot Window 1

- Ran exactly one supervised non-engineering internal pilot window under the 2.39H constraints.
- Used label-only participants/devices: Participant A/B and Device A1/B1.
- Main path kept `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` and `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` unset.
- Backend readiness passed with `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and eligibility/allowlist configured.
- A/B trust was ready after the approved encrypted direct 1:1 DM was opened on both clients.
- Preflight reported no stale active session, Element Call fallback visible, `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
- A -> B happy path passed: A/B reached `activeAudio`, media failure stayed `none`, and hangup returned A/B idle/no active session.
- B -> A reverse path passed with the same active-audio and clean-hangup result.
- Repeated call once passed with no stale active session and no split state.
- Decline/cancel row was run as outgoing cancel because the runner does not expose a distinct decline command; A sent terminal `cancelled`, B received cancel, and A/B returned idle/no active session.
- Timeout row passed: A reported `outgoingTimeout`, B reported `incomingTimeout`, and A/B returned idle/no active session with media failure `none`.
- Planned app-side kill-switch check passed: relaunching with internal rollout disabled made dry-run report `wouldStart=false`, `activationSource=internalPilot`, `internalPilotActivationDecision=disabled`, and `internalPilotActivationReason=rolloutDisabled`; no active session or media/LiveKit side effects were present.
- Element Call fallback visibility was confirmed pass by the operator; normal Element Call controls remained visible/unchanged and separate from the private native audio card.
- Stop criteria hit: no. Redaction issue: no. Runtime bug: no. Emergency rollback: no.
- No app/backend code changed.
- Decision: pause for post-window review. No additional non-engineering pilot window is approved by this run.
- Recommended next phase: `2.39J — narrow non-engineering pilot window 1 post-run review`.

## 2026-05-28 — 2.39G Pilot Checklist Completion Follow-Up

- Recorded the label-only operational data for the narrow non-engineering pilot checklist.
- Owner labels are filled for pilot owner, backend owner, allowlist owner, rollback operator, redaction/report reviewer, and incident decision owner.
- Participant/device labels are filled for Participant A/B and Device A/B.
- Explicit opt-in is recorded as yes for both participants.
- Participant expectations are acknowledged: not production, foreground/open encrypted DM only, no background incoming, no CallKit system incoming screen, no missed-call UX, Element Call fallback, and participants can stop anytime.
- Fresh preflight is recorded green: readiness `ready=true`, `reason=ok`, Redis connected, storage key configured, LiveKit room provisioning configured, eligibility/allowlist configured, trust ready, encrypted direct 1:1 DM open, no active session, Element Call fallback visible, and `internalPilotActivationDecision=activationAllowed`.
- Kill-switch readiness is recorded: app rollout disable verified, backend allowlist removal verified, rollback operator present, and redaction reviewer present.
- No raw user IDs, device IDs, room IDs, tokens, JWTs, LiveKit room names, Redis credentials, or secrets are recorded.
- Checklist is complete enough to proceed to execution approval re-review only.
- No pilot was executed, and execution is not approved in this phase.
- Recommended next phase: `2.39H — one-window non-engineering pilot execution approval`.

## 2026-05-28 — 2.39F Pilot Checklist Completion Attempt

- Reviewed the 2.39D blocker-remediation checklist for label-only completion.
- Execution remains blocked because the required operational data is still not filled in.
- Missing blockers remain: owner labels, participant/device labels, explicit opt-in, fresh green preflight, rollback operator presence, kill-switch verification, and redaction/report reviewer presence.
- No pilot was executed, and no execution approval was granted.
- Broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed-call UX, video, session restoration, and global activation remain blocked.
- No app or backend code changed.
- Recommended next phase: `2.39G — pilot checklist completion follow-up`.

## 2026-05-28 — 2.39D Non-Engineering Pilot Blocker Remediation Checklist

- Recorded the 2.39C decision that the first narrow non-engineering pilot window remains blocked.
- Reason: the preparation runbook is sufficient, but execution approval criteria are not filled with actual owner labels, participant/device labels, explicit opt-in, fresh preflight, and execution-time support/rollback readiness.
- Added a label-only owner table for pilot owner, backend owner, allowlist owner, rollback operator, redaction/report reviewer, and incident decision owner.
- Added a label-only participant/device table for Participant A/B, Device A/B, account allowed yes/no, device trusted yes/no, and explicit opt-in yes/no.
- Added the required opt-in statement: pilot is not production, foreground/open encrypted DM only, no background incoming, no CallKit system incoming screen, no missed-call UX, Element Call fallback, and participant can stop anytime.
- Added a fresh preflight template requiring readiness `ready=true`, `reason=ok`, Redis connected, storage key configured, LiveKit room provisioning configured, eligibility/allowlist configured, trusted encrypted 1:1 room, no active session, Element Call fallback visible, and `internalPilotActivationDecision=activationAllowed` before any call.
- Added an execution approval checklist: owners filled, participants filled, opt-in recorded, preflight green, rollback operator present, kill switch verified, and redaction reviewer present.
- Kept stop criteria and rollback explicit: leakage, untrusted device, stale active session, split-brain, media failure not fail-closed, Element Call route change, and participant confusion about foreground-only behavior all stop the pilot.
- No app or backend code changed. Pilot execution remains blocked until the checklist is complete and a separate re-review passes.
- Recommended next phase: `2.39E — narrow non-engineering pilot execution approval re-review`.

## 2026-05-28 — 2.39B Narrow Non-Engineering Internal Pilot Preparation Runbook

- Added a docs-only preparation runbook for a future very narrow non-engineering internal pilot window.
- Recorded the decision from 2.39A: preparation may proceed, but execution is not yet approved.
- Scope is limited to 1-2 named non-engineering internal participants, named accounts/devices only, staging call-service and staging LiveKit only, private native audio card only, foreground/open encrypted direct 1:1 rooms only, verified/trusted peers only, one active native 1:1 call at a time, Element Call fallback visible/unchanged, no unmanaged devices, and no public or broad rollout.
- Added participant consent and expectation text covering internal-pilot status, foreground/open-chat limitation, no background incoming calls, no CallKit incoming screen, no missed-call UX, Element Call fallback, and redacted pass/fail reporting.
- Added required owners: pilot owner, backend owner, allowlist owner, rollback operator, redaction/report reviewer, and incident decision owner.
- Added required preflight, app gates, backend gates, first-session matrix, stop criteria, rollback procedure, and redacted report template.
- Re-stated forbidden report content: Matrix access tokens, Synapse admin token, LiveKit API secret, participant JWT/token, raw room/user/peer/device IDs, LiveKit room names, media keys, Matrix event bodies, Redis credentials, full request/response bodies, and backend URLs with credentials.
- Remaining blockers stay explicit: no CallKit, no push/background incoming, no missed-call UX, no session restoration, no video, no production/public rollout, no broad internal rollout, monitoring remains runner/report based, and support/rollback is not yet proven with non-engineering participants.
- No app or backend code changed, and execution of the pilot remains blocked pending `2.39C — narrow non-engineering pilot execution readiness approval`.

## 2026-05-28 — 2.38B Internal Pilot Operational Proof And Kill-Switch Rehearsal

- Ran the engineering-only operational proof for the server-backed internal pilot activation path and kill-switch rollback model.
- Enabled-state proof passed with private dogfood unset, internal rollout enabled, backend allowlisted engineering A/B, readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, and an encrypted direct 1:1 DM open.
- Trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
- Positive proof passed: A Start -> B Accept reached `activeAudio`; A hangup returned A/B to idle with `productionHasActiveSession=false` and media failure `none`.
- App-side kill switch passed: unsetting `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED` made dry-run/start block with `appRolloutDisabled` / `rolloutDisabled`; A/B remained without active session, Matrix send, media connect, or LiveKit connect.
- Backend allowlist kill switch passed: restarting the local staging call-service with eligibility enabled and an empty allowlist kept readiness redacted and made the app report internal-pilot activation unavailable with safe reason `serviceUnavailable`; diagnostic start blocked before media/LiveKit and A/B remained idle/no active session.
- Restore proof passed after the correct encrypted r1/r2 DM and trust state were restored: readiness returned `ready=true`, allowlist configured true, A/B dry-run returned `activationAllowed`, A Start -> B Accept reached `activeAudio`, and hangup returned A/B idle/no active session with media failure `none`.
- Element Call fallback was visually confirmed visible and unchanged; the private native audio card remained separate.
- No raw IDs, secrets, LiveKit room names, request/response bodies, Redis credentials, tokens, or JWTs were recorded. No code changed.
- Non-engineering internal dogfood, broad internal rollout, production/public rollout, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.38C — internal pilot operational readiness completion review`.

## 2026-05-26 — 2.38A Internal Pilot Operational Readiness And Kill-Switch Plan

- Recorded the post-soak operational decision: the server-backed internal pilot activation path is stable for engineering accounts, but non-engineering internal dogfood remains blocked.
- Added required operational roles: pilot owner, backend owner, allowlist owner, redaction/report reviewer, rollback operator, and incident decision owner.
- Documented a kill-switch model that can remove activation by disabling the app-side internal rollout gate, disabling backend eligibility, clearing/removing allowlist entries, restarting call-service if needed, relaunching clients, verifying idle/no active session, verifying `internalPilotActivationDecision` no longer reports `activationAllowed`, and preserving Element Call fallback.
- Added allowlist operation requirements: named users only, named devices only when supported, no wildcard/global entries, change approval, redacted audit trail, removal procedure, and no raw IDs in shared reports.
- Added a monitoring baseline restricted to readiness booleans, eligibility state/reason enum, `activationSource`, `internalPilotActivationDecision`, `internalPilotActivationReason`, `productionSessionState`, `productionMediaFailureReason`, terminal reason enum, cleanup/disconnect booleans, and pass/fail/not-run.
- Re-stated forbidden outputs: tokens, JWTs, secrets, raw room/user/peer/device IDs, LiveKit room names, media keys, Matrix event bodies, Redis credentials, full request/response bodies, and credentialed backend URLs.
- Added stop criteria, rollback procedure, and a redacted incident report template.
- Listed remaining blockers for non-engineering readiness: no CallKit/push/background incoming, foreground/open-room limitation, no missed-call UX, no session restoration, runner/report-based monitoring, support/rollback not proven with non-engineers, no production rollout/capability governance, shared staging LiveKit destructive-test limits, and non-engineering-safe UX still needing review.
- Recommended next phase: `2.38B — internal pilot operational proof and kill-switch rehearsal`.

## 2026-05-26 — 2.37F Engineering-Only Internal Pilot Activation Soak Session 3 Rerun

- Reran the third engineering-only soak session for the server-backed internal pilot activation path after `4ea9490ec`.
- The main soak kept `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset and kept the legacy fake/dry-run gate unset.
- Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, no stale active session, and Element Call fallback visible.
- Trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
- A -> B, B -> A, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, post-listener recovery, and Element Call fallback rows passed with redacted output only.
- The repeated-call split-state guard passed: `tokenBackendRejected` did not appear, `connectingFailed` did not appear, and no split state was observed.
- Timeout reported A `outgoingTimeout` and B `incomingTimeout`; A/B returned idle with no active session.
- Listener/open-room unavailable behavior passed with B stopped: A timed out fail-closed, returned idle/no active session, and did not connect media/LiveKit. After B relaunched, post-listener recovery reached `activeAudio` and returned A/B to idle.
- Token final-authority was not rerun in this restored allowlisted pass because sessions 1 and 2 already covered the temporary ineligible fixture path.
- Final A/B state was idle/no active session with media failure `none`; no rollback was used, no stop criteria triggered, no runtime bug was observed, and no redaction issue was found.
- The 3-session engineering-only soak for the server-backed internal pilot activation path is complete for the required runtime matrix.
- Non-engineering internal dogfood, broad internal rollout, production/public rollout, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.37G — internal pilot activation post-soak readiness review`.

## 2026-05-26 — 2.37E-blocker Caller Media Setup Failure Split-State Fix

- Recorded the blocker that paused the third engineering-only internal pilot activation soak session.
- The paused 2.37E session had already passed backend readiness, Redis, LiveKit provisioning, eligibility/allowlist, internal rollout activation, A/B trust, room attachment, A -> B happy path, B -> A reverse path, and the first repeated call.
- During the repeated-call row, one attempt timed out safely, then retry hit a split state: A returned idle with `tokenBackendRejected` / `connectingFailed`, while B reported `activeAudio` with an active session.
- Cleanup returned final A/B to idle/no active session; B cleanup/hangup succeeded, while A still reported media failure `tokenBackendRejected`.
- Root cause: caller-side media/token setup failure after receiving a remote answer did not count as post-answer, so it failed locally without emitting a terminal event to the remote side. Callee-side post-answer failure already had this protection.
- Commit `4ea9490ec` updates `DirectCallEngine` to track received remote answers and emit one deduped hangup if caller media setup fails after the peer may have entered `activeAudio`.
- `DirectCallEngineTests` now cover caller `tokenBackendRejected` after answer and the manual-hangup race dedupe path; 37/37 passed.
- Runtime proof after the fix passed for A -> B and repeated A -> B active-audio calls, with hangup returning A/B to idle/no active session and media failure `none`.
- The exact `tokenBackendRejected` split did not reproduce in runtime; the exact caller-failure-after-answer path is covered by the new unit regression.
- Validation for the code fix passed: SwiftFormat, SwiftLint changed files, `DirectCallEngineTests` 37/37, Release build with existing warnings only, `git diff --check`, and direct-call forbidden scan.
- Element Call route stayed untouched. No CallKit, push, video, production/public rollout, broad internal rollout, non-engineering dogfood, or global activation was enabled.
- 2.37E soak session 3 was not continued or recorded as passed. At this point, soak progress remained 2 clean sessions of 3.
- Recommended next phase at the time: `2.37F — rerun internal pilot activation soak session 3 after caller failure fix`.

## 2026-05-26 — 2.37D Engineering-Only Internal Pilot Activation Soak Session 2

- Ran and recorded the second engineering-only soak session for the server-backed internal pilot activation path.
- The main soak kept `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset and kept the legacy fake/dry-run gate unset.
- Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, no stale active session, and Element Call fallback visible.
- Trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
- A -> B, B -> A, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, post-listener recovery, token final-authority, and Element Call fallback rows passed with redacted output only.
- Timeout reported A `outgoingTimeout` and B `incomingTimeout`; A/B returned idle with no active session.
- Relaunch fail-closed returned A/B to an unavailable/no-owner window with no active session and no media/LiveKit path. The operator reopened the encrypted DM before the recovery call, which then reached `activeAudio` and returned A/B to idle.
- Token final-authority used a temporary ineligible local fixture and blocked with safe reason `accountNotEligible` before media/LiveKit. The normal allowlisted staging service was restored afterward.
- Final A/B state was idle/no active session with media failure `none`; no rollback was used, no stop criteria triggered, no runtime bug was observed, and no redaction issue was found.
- Soak progress is now 2 clean sessions of 3 required before the next readiness review.
- Non-engineering internal dogfood, broad internal rollout, production/public rollout, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.37E — engineering-only internal pilot activation soak session 3`.

## 2026-05-26 — 2.37C Engineering-Only Internal Pilot Activation Soak Session 1

- Ran and recorded the first engineering-only soak session for the server-backed internal pilot activation path.
- The main soak kept `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset and kept the legacy fake/dry-run gate unset.
- Preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, encrypted direct 1:1 DM open, no stale active session, and Element Call fallback visible.
- Trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, and `internalPilotActivationReason=none`.
- A -> B, B -> A, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, post-listener recovery, token final-authority, and Element Call fallback rows passed with redacted output only.
- Timeout reported A `outgoingTimeout` and B `incomingTimeout`; A/B returned idle with no active session.
- Token final-authority used a temporary ineligible local fixture and blocked with safe reason `accountNotEligible` before media/LiveKit. The normal allowlisted staging service was restored afterward.
- Final A/B state was idle/no active session with media failure `none`; no rollback was used, no stop criteria triggered, no runtime bug was observed, and no redaction issue was found.
- Soak progress is now 1 clean session of 3 required before the next readiness review.
- Non-engineering internal dogfood, broad internal rollout, production/public rollout, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.37D — engineering-only internal pilot activation soak session 2`.

## 2026-05-26 — 2.37B Engineering-Only Internal Pilot Activation Soak Plan

- Added a docs-only soak plan for the server-backed internal pilot activation path using engineering accounts only.
- The main soak path leaves `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset and uses the internal pilot rollout gate with the existing DEBUG/integration diagnostics, product UI, eligibility status, internal-pilot activation dry-run, production start, and staging token base URL gates.
- Scope remains named allowlisted engineering A/B or named engineering pairs only, staging call-service and staging LiveKit only, private native audio card only, foreground/open encrypted direct 1:1 rooms only, verified/trusted peers only, one active 1:1 call at a time, Element Call fallback visible/unchanged, and redacted reporting only.
- Backend requirements are explicit: native audio eligibility enabled, allowlist containing only named engineering accounts, readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, LiveKit room provisioning configured, and eligibility/allowlist readiness configured.
- The plan requires 3 clean sessions before the next readiness review.
- Each session must cover A -> B happy path, B -> A reverse, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, post-listener recovery, token final-authority check when safe, and Element Call fallback.
- Stop criteria now explicitly include accidental private dogfood gate use in the main internal-pilot soak and token final-authority check failure.
- Rollback unsets the internal pilot rollout gate, clears production/eligibility gates if needed, removes/clears the backend allowlist, restarts call-service if required, relaunches apps, confirms A/B idle/no active session, and keeps Element Call fallback available.
- Non-engineering internal dogfood, broad internal rollout, production/public rollout, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.37C — engineering-only internal pilot activation soak session 1`.

## 2026-05-26 — 2.36P Internal Pilot Trigger Dry-Run Observability Alignment

- Recorded commit `f930f8f7a`, which aligns `production-trigger-dry-run` with the same redacted activation decision path used by `production-start-outgoing`.
- Runner output now includes `activationSource`, `internalPilotActivationDecision`, and `internalPilotActivationReason`.
- The two-client diagnostic runner forwards `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED` for DEBUG/integration internal-pilot proof runs.
- Dry-run remains side-effect-free: no Matrix send, token request, allocation, LiveKit room pre-create, media connect, LiveKit client connect, outgoing call, or active session is created by the dry-run command.
- Private dogfood compatibility was verified after the alignment: Start -> Accept reached `activeAudio`, Hangup returned A/B to `idle`, no active session remained, and media failure stayed `none`.
- Element Call route remained untouched, with no CallKit, push, video, global activation, production/public rollout, or non-engineering internal dogfood enablement.
- Validation passed: SwiftFormat, SwiftLint, targeted native-call tests 179/179, Release build with existing warnings only, runner `bash -n`, `git diff --check`, and changed-line forbidden scan.
- Server-backed internal pilot activation proof path now works for engineering accounts, and internal pilot dry-run observability is aligned.
- Non-engineering internal dogfood, broad internal rollout, and production/public rollout remain blocked.
- Recommended next phase: `2.37A — internal pilot activation engineering proof completion review`.

## 2026-05-24 — 2.36C Internal Pilot Activation Provider Skeleton

- Added a native-audio-specific internal pilot activation model with `disabled`, `unavailable`, `eligibleForStatusOnly`, and `activationAllowed` states.
- Added safe activation unavailable reasons: `rolloutDisabled`, `capabilityMissing`, `accountNotEligible`, `peerNotEligible`, `roomNotEligible`, `trustNotReady`, `serviceUnavailable`, `unsupportedClient`, `dependenciesUnavailable`, and `unknown`.
- Added an activation provider protocol plus a fail-closed default provider.
- Added a status-only provider that can combine future rollout/capability/eligibility/room/trust/dependency inputs but never returns `activationAllowed`.
- Added tests proving default activation remains disabled, backend eligible alone does not activate, product UI / eligibility status alone do not activate, `directOneToOneCallsEnabled` does not activate native audio, local room/trust/dependency failures fail closed, and activation output remains redacted.
- Engineering private dogfood remains on `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` under DEBUG/integration gates.
- Non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.36D — internal pilot activation skeleton no-activation proof`.

## 2026-05-25 — 2.36D Internal Pilot Activation Skeleton No-Activation Proof

- Ran the runtime no-activation proof for commit `3b0e6b5db`.
- Readiness passed with `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
- Launched A/B with product UI and eligibility status enabled while keeping `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset.
- Confirmed activation stayed blocked and side-effect-free. With the encrypted direct 1:1 room open, the activation and trigger reason was `appRolloutDisabled`.
- Relaunched with product UI, eligibility status, and production start enabled while keeping private dogfood unset; Start stayed blocked with `appRolloutDisabled`.
- Confirmed the no-private-dogfood runs had no Matrix send, no token request, no media connect, no LiveKit client connect, no active session, and media failure `none`.
- Did not toggle `directOneToOneCallsEnabled` at runtime because there is no safe runner hook for it without changing Element Call settings. The 2.36C targeted tests cover this separation, and Element Call was not touched during the runtime proof.
- Relaunched with private dogfood restored and the legacy fake/dry-run gate unset. A -> B reached `activeAudio` with encryption ready, media connect attempted, LiveKit client connect attempted, and media failure `none`.
- Hangup returned A/B to idle with no active session, cleanup/disconnect attempted, and media failure `none`.
- Runner-assisted production status/control was used for this proof. A legacy diagnostic wait-status poll did not observe production incoming state and was not used as a pass criterion; production accept/status showed the happy path correctly.
- No code changed, no redaction issue was observed, no runtime regression was found, and Element Call route stayed untouched.
- Recommended next phase: `2.36E — server-backed internal pilot activation integration plan`.

## 2026-05-24 — 2.35B Engineering Expansion Operations Handoff

- Added a docs-only operations handoff for continuing narrow engineering expansion without per-session Codex supervision.
- Kept the scope unchanged: up to 4 named engineering operators, up to 8 named devices, predeclared pairs only, staging-only, one active 1:1 native audio call at a time, private native audio card only, foreground/open encrypted direct 1:1 rooms only, verified/trusted peers only, Element Call fallback visible/unchanged, and redacted reporting only.
- Added explicit operator-owned roles: session owner, backend readiness watcher, client operators, redaction reviewer, stop authority, and rollback owner.
- Re-stated required preflight: readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured when used, A/B trust ready, encrypted 1:1 DM open, no stale active session, Element Call fallback visible, and legacy fake/dry-run gate unset.
- Re-stated required gates, including DEBUG/integration diagnostics, product UI, eligibility status, private dogfood, production start, and staging token base URL.
- Added a monitoring baseline limited to readiness booleans, trust booleans, `productionSessionState`, `productionMediaFailureReason`, terminal reason enum, cleanup/disconnect booleans, pass/fail/not-run, and redacted backend reason enums.
- Added stop criteria, rollback, redacted report intake, validation expectations, periodic cadence, and expansion decision rules.
- Non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.35C — operator-owned engineering expansion session report`.

## 2026-05-24 — 2.35C Operator-Owned Engineering Expansion Session 1

- Ran the first operator-owned engineering expansion session under the 2.35B operations handoff.
- Session used redacted Operator A/B and Device A1/B1 labels only, staging call-service, staging LiveKit, DEBUG/integration diagnostics, product UI, eligibility status, private dogfood, production start, and staging token base URL gates. The legacy fake/dry-run gate stayed unset.
- Preflight passed: readiness returned `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session.
- Runner/status-assisted happy path A -> B, reverse B -> A, and repeated A -> B calls x2 reached A/B `activeAudio`; hangup returned A/B to idle/no active session with media failure `none`.
- Decline and cancel returned A/B to idle/no active session.
- Timeout passed with A terminal `outgoingTimeout`, B terminal `incomingTimeout`, and no stale active session.
- Relaunch during ringing returned A/B to idle/no active session.
- Listener-unavailable/open-room edge passed by stopping B before A started: A timed out fail-closed with `outgoingTimeout` and no active session; post-listener recovery reached A/B `activeAudio`, then returned idle/no active session with media failure `none`.
- Backend-off recovery was not run because the local staging call-service stayed up for the session. LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval.
- Element Call fallback stayed visible/unchanged; the native session did not invoke or change the Element Call route.
- Final A/B status was idle/no active session with media failure `none`, cleanup/disconnect attempted on both sides, no rollback used, no stop criteria triggered, no redaction issue observed, and no app/backend code changed.
- Dogfood decision: continue engineering-only staging expansion under the 2.35B handoff. Non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.35D — operator-owned engineering expansion session 2`.

## 2026-05-24 — 2.34D Engineering Expansion Soak Session 3

- Ran the third engineering expansion soak session under the 2.34A plan.
- Session used redacted A/B engineering labels only, staging call-service, staging LiveKit, DEBUG/integration diagnostics, product UI, eligibility status, private dogfood, production start, and staging token base URL gates. The legacy fake/dry-run gate stayed unset.
- Preflight passed: readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session.
- Runner-assisted happy path A -> B, reverse B -> A, and repeated A -> B calls x2 reached A/B `activeAudio`; hangup returned A/B to idle/no active session with media failure `none`.
- Decline and cancel returned A/B to idle/no active session.
- Timeout passed with A terminal `outgoingTimeout`, B terminal `incomingTimeout`, A/B idle/no active session, and media failure `none`.
- Relaunch during ringing returned A/B to idle/no active session.
- Listener-unavailable/open-room edge passed by stopping B before A started: A timed out fail-closed with `outgoingTimeout`, no active session, and media failure `none`; B relaunched idle/no active session.
- A post-listener recovery happy path reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`.
- Backend-off recovery was not run because the local staging call-service stayed up for the session. LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval.
- Element Call fallback status remained unchanged; the native soak did not invoke the Element Call route.
- Final A/B status was idle/no active session with media failure `none`, media/LiveKit connect attempted on both sides, and cleanup/disconnect attempted on both sides.
- No rollback was needed, no stop criteria triggered, no redaction issue was observed, and no code changed during the runtime proof.
- Dogfood decision: the engineering-only soak can continue only under the same narrow controls, and the planned 3-session soak is complete. Non-engineering internal dogfood and production/public rollout remain blocked pending readiness review.
- Recommended next phase: `2.35A — post-soak engineering expansion readiness review`.

## 2026-05-24 — 2.34C Engineering Expansion Soak Session 2

- Ran the second engineering expansion soak session under the 2.34A plan.
- Session used redacted A/B engineering labels only, staging call-service, staging LiveKit, DEBUG/integration diagnostics, product UI, eligibility status, private dogfood, production start, and staging token base URL gates. The legacy fake/dry-run gate stayed unset.
- Preflight passed: readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session.
- Runner-assisted happy path A -> B, reverse B -> A, and repeated A -> B calls x2 reached A/B `activeAudio`; hangup returned A/B to idle/no active session with media failure `none`.
- Decline and cancel returned A/B to idle/no active session.
- Timeout passed with A terminal `outgoingTimeout`, B terminal `incomingTimeout`, A/B idle/no active session, and media failure `none`.
- Relaunch during ringing returned A/B to idle/no active session.
- Listener-unavailable/open-room edge passed by stopping B before A started: A timed out fail-closed with `outgoingTimeout`, no active session, and media failure `none`; B relaunched idle/no active session.
- A post-listener recovery happy path reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`.
- Backend-off recovery was not run because the local staging call-service stayed up for the session. LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval.
- Element Call fallback status remained unchanged; the native soak did not invoke the Element Call route.
- Final A/B status was idle/no active session with media failure `none`, media/LiveKit connect attempted on both sides, and cleanup/disconnect attempted on both sides.
- No rollback was needed, no stop criteria triggered, no redaction issue was observed, and no code changed during the runtime proof.
- Dogfood decision: continue the engineering-only soak. Two of three planned soak sessions are clean; non-engineering internal dogfood and production/public rollout remain blocked.
- Recommended next phase: `2.34D — engineering expansion soak session 3`.

## 2026-05-24 — 2.34B Engineering Expansion Soak Session 1

- Ran the first engineering expansion soak session under the 2.34A plan.
- Session used redacted A/B engineering labels only, staging call-service, staging LiveKit, DEBUG/integration diagnostics, product UI, eligibility status, private dogfood, production start, and staging token base URL gates. The legacy fake/dry-run gate stayed unset.
- Preflight passed: readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session.
- Runner-assisted happy path A -> B, reverse B -> A, and repeated A -> B calls x2 reached A/B `activeAudio`; hangup returned A/B to idle/no active session with media failure `none`.
- Decline and cancel returned A/B to idle/no active session.
- Timeout passed with A terminal `outgoingTimeout`, B terminal `incomingTimeout`, A/B idle/no active session, and media failure `none`.
- Relaunch during ringing returned A/B to idle/no active session.
- Listener-unavailable/open-room edge passed by stopping B before A started: A timed out fail-closed with `outgoingTimeout`, no active session, and media failure `none`; B relaunched idle/no active session.
- A post-listener recovery happy path reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`.
- Backend-off recovery was not run because the local staging call-service stayed up for the session. LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval.
- Element Call fallback status remained unchanged; the native soak did not invoke the Element Call route.
- Final A/B status was idle/no active session with media failure `none`, media/LiveKit connect attempted on both sides, and cleanup/disconnect attempted on both sides.
- No rollback was needed, no stop criteria triggered, no redaction issue was observed, and no code changed during the runtime proof.
- Dogfood decision: continue the engineering-only soak. One of three planned soak sessions is clean; non-engineering internal dogfood and production/public rollout remain blocked.
- Recommended next phase: `2.34C — engineering expansion soak session 2`.

## 2026-05-24 — 2.34A Engineering Expansion Soak Plan

- Added a 3-session engineering expansion soak plan before any broader readiness review.
- Kept the soak within the existing controlled staging scope: up to 4 named engineering operators, up to 8 named devices, private native audio card only, foreground/open encrypted direct 1:1 rooms only, verified/trusted peers only, one active 1:1 call at a time, Element Call fallback visible, and redacted reporting only.
- Added a session schedule template with label-only operator/device/pair fields and no raw user IDs, room IDs, peer IDs, device IDs, tokens, JWTs, secrets, Redis credential URLs, Matrix event bodies, or LiveKit room names.
- Required every soak session to use the existing gates and preflight: DEBUG/integration diagnostics, product UI, eligibility status, private dogfood, production start, staging token base URL, Redis readiness, LiveKit room provisioning, eligibility/allowlist configuration when used, A/B trust ready, encrypted 1:1 DM open, no stale active session, and Element Call fallback visible.
- Required each session matrix to cover A -> B happy path, B -> A reverse, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, and Element Call fallback smoke.
- Kept backend-off/recovery optional only when safe for the local staging setup and kept LiveKit-off not-run unless explicitly approved by the shared staging LiveKit owner.
- Added stop criteria, rollback, a redacted report template, and the decision rule: 3 clean sessions lead to a readiness review for the next phase; any critical bug pauses the soak for diagnosis.
- Confirmed non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.34B — engineering expansion soak session 1`.

## 2026-05-24 — 2.33E Narrow Engineering Expansion Pilot Session 1 Rerun

- Reran the first narrow engineering expansion pilot window after the 2.33D timeout cleanup fix.
- Session used redacted A/B engineering labels only, staging call-service, staging LiveKit, DEBUG/integration gates, eligibility status gate, private dogfood gate, production start gate, and the staging token base URL. The legacy fake/dry-run gate stayed unset.
- Preflight passed: readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured. A/B trust was ready and baseline status was idle/no active session.
- Runner-assisted happy path A -> B, reverse B -> A, and repeated A -> B calls x2 all reached A/B `activeAudio`; hangup returned both sides to idle/no active session with media failure `none`.
- Decline and cancel passed through the native terminal path: incoming ringing and outgoing ringing both returned A/B to idle/no active session.
- Timeout now passed after `1d9218057`: A reported terminal `outgoingTimeout`, B reported terminal `incomingTimeout`, A/B returned to `idle`, A/B reported `productionHasActiveSession=false`, cleanup/disconnect were attempted, and media failure remained `none`.
- Relaunch during ringing passed: relaunch returned A/B to idle/no active session.
- Listener unavailable/open-room edge passed by stopping B before A started: A timed out fail-closed with `outgoingTimeout`, no active session, and media failure `none`; B relaunched idle/no active session.
- Backend-off recovery was not run in this session because the local staging call-service stayed up for the pilot. LiveKit-off was not run because shared staging LiveKit should not be stopped without explicit owner approval.
- Final A/B status was idle/no active session with media failure `none`. No rollback was needed, no stop criteria triggered, no redaction issue was observed, and Element Call route remained untouched.
- No code changed during the runtime proof.
- Dogfood decision: continue the narrow engineering expansion under the 2.33B runbook constraints; non-engineering internal dogfood and production/public rollout remain blocked.
- Recommended next phase: `2.33F — narrow engineering expansion pilot session 2`.

## 2026-05-24 — 2.33D Timeout Terminal Cleanup Fix

- Paused the 2.33C narrow engineering expansion pilot because timeout terminal reasons were set while `productionHasActiveSession` stayed true until explicit cleanup.
- Root cause: timeout paths transitioned to terminal states but left the active session owned until delayed cleanup.
- Fixed in `1d9218057` by making DirectCallEngine timeout terminal paths disconnect and cleanup immediately.
- Runtime timeout proof passed: A reported terminal `outgoingTimeout`, B reported terminal `incomingTimeout`, A/B returned to `productionSessionState=idle`, A/B reported `productionHasActiveSession=false`, cleanup/disconnect were attempted, and media failure remained `none`.
- Next-call-after-timeout proof passed: a new A -> B call after timeout reached A/B `activeAudio`, then hangup returned A/B to idle with no active session and media failure `none`.
- Element Call route remained untouched, with no CallKit, push, video, or global production activation.
- Validation passed: DirectCallEngineTests 36/36, focused native subset 171 tests, Release build with existing warnings only, SwiftFormat/SwiftLint, `git diff --check`, and the direct-call forbidden scan.
- Recommended next phase: `2.33E — narrow engineering expansion pilot session 1 rerun after timeout cleanup fix`.

## 2026-05-24 — 2.33B Narrow Engineering Expansion Pilot Runbook

- Added an engineering-only expansion runbook for the first narrow staging expansion window.
- Capped the next expansion at up to 4 named engineering operators and up to 8 named devices.
- Kept the first expanded window to one active 1:1 native audio call at a time.
- Added ownership-window, participant/device, and pair-matrix templates that use labels only and exclude raw user IDs, room IDs, peer IDs, device IDs, tokens, JWTs, secrets, Matrix event bodies, Redis credential URLs, and LiveKit room names.
- Required product UI, eligibility status, private dogfood, production start, staging token base URL, and DEBUG/integration diagnostics gates, with the legacy fake/dry-run gate unset.
- Required every new pair to run happy path, reverse, repeated x2, decline, cancel, timeout if practical, relaunch fail-closed, listener/open-room unavailable, Element Call fallback, and backend-off/recovery only when safe.
- Kept LiveKit-off not-run unless the shared staging LiveKit owner explicitly approves a disruption window.
- Kept non-engineering users, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation blocked.
- Recommended next phase: `2.33C — narrow engineering expansion pilot session 1`.

## 2026-05-24 — 2.32B Eligibility Status Integration Polish and Runtime Proof

- Polished production LiveKit token response descriptions so LiveKit room names are redacted alongside server URLs and participant tokens.
- Updated the two-client diagnostic runner to forward `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1` into simulator launches and to report the status gate without printing env values.
- Confirmed local staging call-service readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
- Launched A/B with product UI, production start, and eligibility status gates enabled, but without the private dogfood gate.
- Confirmed an attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`.
- Confirmed the no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
- Relaunched with the explicit private dogfood gate restored and the legacy fake/dry-run gate unset.
- Confirmed A/B activation and trust ready, then ran a runner-assisted A -> B happy path: B listener armed, A started, B accepted, and A/B reached `activeAudio`.
- Confirmed media connect and LiveKit client connect were attempted on both sides, `productionMediaFailureReason=none`, and hangup returned A/B to idle/no active session with cleanup/disconnect attempted.
- Observed a `wait-status incomingRinging` helper timeout before accept, but explicit accept and final status proved the incoming session and media path. The timeout is a runner polling caveat, not a backend/media failure.
- Negative backend eligibility reason mappings remain covered by unit tests and the 2.30F route smoke; this live staging run did not reconfigure the local allowlist for negative cases.
- Element Call route remained untouched.
- Recommended next phase: `2.32C — eligibility status controlled engineering soak`.

## 2026-05-24 — 2.32C Eligibility Status Controlled Engineering Soak

- Ran a controlled engineering soak with product UI, eligibility status, private dogfood, production start, and staging token base URL gates enabled.
- Kept the legacy fake/dry-run gate unset.
- Confirmed backend readiness before and after the soak: `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
- Confirmed A/B activation and trust ready before the soak.
- Ran runner-assisted happy path A -> B and reverse B -> A; both reached `activeAudio`, then hangup returned A/B to idle/no active session with media failure `none`.
- Ran two repeated A -> B calls; both reached `activeAudio`, returned idle, and showed no stale session or split-brain.
- Ran decline and cancel through the shared production hangup command. Incoming ringing emitted `reject`, outgoing ringing emitted `cancel`, both sides returned idle, and terminal reason was `cancelled`.
- Ran timeout; A ended with `outgoingTimeout`, B ended with `incomingTimeout`, both returned idle, and media failure remained `none`.
- Ran relaunch during ringing; relaunch cleared both apps to no active session. Final post-relaunch status was `unavailable` because the encrypted 1:1 room was not re-opened, matching the current foreground/open-room limitation.
- Runner output did not include LiveKit room names.
- Element Call route remained untouched; no code changed during the soak.
- Recommended next phase: `2.32D — eligibility status negative-case runtime fixture proof`.

## 2026-05-24 — 2.31D Live Redis Readiness Check Hardening

- Hardened call-service startup and request-time readiness for Redis-backed staging stores.
- `allocationStoreConnected` and `rateLimitConnected` now require bounded live Redis pings instead of only config shape/runtime implementation presence.
- Added safe readiness reasons `allocationStoreUnavailable` and `rateLimitStoreUnavailable`.
- Preserved local fake/memory readiness behavior for explicit local/test modes.
- Preserved token endpoint fail-closed behavior: Redis rate-limit failure still returns `M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE` and no token is issued.
- Updated backend tests for Redis ping success/failure and readiness redaction without printing Redis URLs or credentials.
- Recommended next phase: `2.31E — eligibility status cache controlled engineering soak`.

## 2026-05-24 — 2.31F Redis Readiness Recovery Native Audio Smoke

- Ran the post-restore native audio smoke after `f4656983a`.
- Confirmed local call-service readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected true, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
- Confirmed A/B trust ready with own session verified, cross-signing ready, and peer trust ready.
- Ran a runner-assisted A -> B happy path after Redis restore: A started, B reached `incomingRinging`, B accepted, and A/B reached `activeAudio` with encryption ready.
- Confirmed media connect and LiveKit client connect were attempted, `productionMediaFailureReason=none`, and hangup returned A/B to idle/no active session with cleanup/disconnect attempted.
- Element Call route remained untouched; no code changed during the runtime proof.
- Recommended next phase: `2.31G — eligibility status cache controlled engineering soak`.

## 2026-05-23 — 2.30C Eligibility Contract Runtime/No-Activation Proof

- Ran the runtime proof after `db5c4fd72` to confirm the new eligibility contract skeleton remains fail-closed by default.
- Confirmed local staging call-service readiness returned `ready=true`, `reason=ok`, and Redis allocation/rate-limit/storage booleans true.
- Launched A/B with product UI and production start gates enabled but without the private dogfood gate.
- Confirmed an attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`.
- Confirmed the no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
- Relaunched A/B with `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, kept the legacy fake/dry-run gate unset, and confirmed A/B trust ready plus activation enabled.
- Ran a runner-assisted A -> B happy path: A started, B reached incoming ringing, B accepted, and A/B reached `activeAudio` with encryption ready, media connect attempted, LiveKit client connect attempted, and media failure `none`.
- Hangup returned A/B to idle/no active session with cleanup/disconnect attempted and media failure `none`.
- Element Call route remained untouched; no code changed during the runtime proof.
- Recommended next phase: `2.30D — backend internal pilot allowlist provider design` for server-side allowlist/capability backing before any non-engineering users.

## 2026-05-23 — 2.30B Internal Pilot Eligibility Contract Skeleton

- Added a fail-closed internal pilot eligibility contract skeleton for future native-audio rollout work.
- Added `NativeDirectCallInternalPilotEligibility` with `eligible`, `unavailable(reason)`, `disabled`, `unsupported`, and `failClosed` states.
- Added user-safe unavailable reasons: `accountNotEligible`, `peerNotEligible`, `roomNotEligible`, `trustNotReady`, `serviceUnavailable`, `capabilityMissing`, `unsupportedClient`, and `unknown`.
- Added a redacted payload shape that carries only enums and booleans for account, peer, room, trust, service, and client support readiness.
- Added a default fail-closed provider that returns disabled.
- Mapped account and peer not-eligible states to existing safe private-card unavailable copy without exposing identifiers.
- Confirmed the skeleton does not enable non-engineering dogfood, does not reuse `directOneToOneCallsEnabled`, and does not change Element Call, CallKit, push, video, or global production activation.
- Documented the backend eligibility response shape and reiterated that the token endpoint remains the final enforcement boundary.
- Regenerated `SalemX.xcodeproj` to include the new eligibility test suite.
- Validation passed: SwiftFormat/SwiftLint on changed Swift files, targeted native-call unit tests, Release build with existing warnings only, `git diff --check`, docs secret scan, and the direct-call forbidden scan.
- Recommended next phase: `2.30C — backend internal pilot allowlist provider design`.

## 2026-05-22 — 2.29E Redacted Pilot Monitoring Contract

- Documented the controlled dogfood monitoring contract for app/card status, runner output, backend readiness, backend errors, and LiveKit/media state.
- Allowed only low-cardinality booleans/enums: readiness, trust, card state/reasons, listener/restoration availability, action availability, activation reason, session state, terminal reason, media failure, media/LiveKit connect attempts, cleanup/disconnect attempts, and pass/fail/not-run.
- Marked diagnostic-only fields as too sensitive for normal pilot reports, including raw last-action traces, backend request/response bodies, decoded token/JWT details, Redis allocation keys/values, LiveKit room names, and Matrix event envelopes.
- Added LiveKit room names to forbidden pilot output because they may be correlatable.
- Updated the pilot report template with terminal reason, media/LiveKit connect attempts, and redaction issue status.
- Kept broader internal dogfood and non-engineering users blocked.
- Recommended next phase: `2.30A — fail-closed internal pilot rollout and allowlist design`.

## 2026-05-22 — 2.29D Native Audio Card Failure Copy Hardening

- Hardened private native audio room-card copy for backend unavailable, LiveKit/audio unavailable, trust unavailable, invalid room, listener/open-room required, timeout, cancel, decline, ended, and unknown failure states.
- Added a DEBUG-only redacted card status contract that exposes state/reason enums, listener/restoration enums, loading/action booleans, and no raw identifiers, tokens, URLs, Matrix event bodies, or LiveKit room names.
- Removed raw last-action status text from the product card UI and kept it out of normal pilot reporting.
- Added product-card previews for main states and focused tests covering safe copy, redacted status, and side-effect-free rendering/status refresh.
- Confirmed the change did not broaden activation, replace Element Call, add CallKit/push/video, or enable global production direct calls.
- Commit: `71056f143`.

## 2026-05-22 — 2.29B Broader Internal Dogfood Hardening Plan

- Recorded the decision that two successful controlled engineering dogfood sessions are not enough for broader internal dogfood or non-engineering users.
- Kept controlled engineering dogfood allowed only on the narrow staging path with named engineering operators, DEBUG/integration builds, foreground/open encrypted direct 1:1 rooms, verified/trusted peers, private native audio card, and Element Call fallback.
- Defined the smallest safe expansion as more named engineering operators/devices on the same staging path, with redacted reporting and explicit session ownership.
- Added hardening areas required before any future narrow non-engineering internal pilot: activation/rollout model, UX and failure copy, incoming behavior and foreground limitation, monitoring and telemetry redaction, backend/staging operations, support/rollback, security review, and soak testing.
- Required a fail-closed internal rollout or allowlist model before non-engineering users.
- Required non-engineering-safe UX for unavailable, connecting, failed, timed out, cancelled, declined, and recovered calls.
- Kept CallKit, push/background incoming, missed calls, video, session restoration, Element Call replacement, public rollout, production rollout, and global production activation out of scope.
- Recommended next phase: `2.29C — native audio internal pilot rollout and UX hardening design`.

## 2026-05-22 — 2.28C Controlled Dogfood Pilot Session 2

- Recorded the second controlled engineering dogfood pilot session under the 2.28A operations checklist.
- Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, LiveKit room provisioning true, A/B launched, and A/B trust ready.
- Used the required private dogfood gates and kept the legacy fake/dry-run gate unset.
- Ran manual private-card happy path A -> B and reverse B -> A; each reached `productionSessionState=activeAudio` and returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- Ran two back-to-back repeated A -> B calls; both reached active audio and returned idle with no stale session and no split-brain.
- Ran decline and cancel; both returned A/B to idle with terminal `cancelled`.
- Ran relaunch fail-closed from an active session; relaunch restored no active session and no media path.
- Timeout was not repeated in session 2 because it is already covered by session 1 and the 2.27F matrix.
- Backend-off recovery was not repeated in this manual pilot because the local staging call-service stayed up for the session; backend-off remains covered by the 2.27F matrix.
- LiveKit-off was not run because the staging LiveKit instance is shared.
- Runner use was limited to launch, readiness/trust/status polling, and relaunch.
- No rollback was needed, no stop criteria triggered, no runtime bug was observed, no redaction issue was found, and Element Call remained untouched.
- Dogfood decision: continue controlled engineering dogfood on the narrow staging path.
- Recommended next phase: `2.28D — controlled dogfood pilot session 3 / longer monitoring follow-up`.

## 2026-05-22 — 2.28B Controlled Dogfood Pilot Session 1

- Recorded the first controlled engineering dogfood pilot session under the 2.28A operations checklist.
- Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, LiveKit room provisioning true, and A/B trust ready.
- Used the required private dogfood gates and kept the legacy fake/dry-run gate unset.
- Ran manual private-card happy path A -> B, reverse B -> A, and repeated call; each reached `productionSessionState=activeAudio` and returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- Ran manual private-card decline and cancel; both returned A/B to idle with terminal `cancelled`.
- Ran timeout; A/B returned idle with terminal `outgoingTimeout` / `incomingTimeout`.
- Ran relaunch fail-closed from an active session; relaunch restored no active session and no media path.
- Backend-off recovery was not repeated in this manual pilot because the local staging call-service stayed up for the session; backend-off remains covered by the 2.27F matrix.
- LiveKit-off was not run because the staging LiveKit instance is shared.
- Runner use was limited to launch, readiness/trust/status polling, and relaunch; Start, Accept, Decline, Cancel, and Hang up were manual private-card actions.
- No rollback was needed, no stop criteria triggered, no runtime bug was observed, no redaction issue was found, and Element Call remained untouched.
- Dogfood decision: continue controlled engineering dogfood on the narrow staging path.
- Recommended next phase: `2.28C — controlled dogfood pilot session 2 / monitoring follow-up`.

## 2026-05-22 — 2.28A Controlled Dogfood Operational Hardening

- Added a controlled dogfood operations checklist to the private native audio dogfood runbook.
- Required every pilot window to have a named operator, named participants, staging call-service owner, shared LiveKit owner/skip confirmation, planned start/stop time, Element Call fallback confirmation, and explicit no-broad-rollout scope.
- Documented local staging call-service start and stop procedure using the operator-local env file without printing env values.
- Documented readiness checks for call-service, Redis allocation store, Redis rate-limit store, storage key, and LiveKit room provisioning.
- Documented A/B client gate checks, trust readiness checks, private card availability, no stale active session, and Element Call fallback visibility.
- Tightened redacted monitoring to readiness booleans, trust booleans, `productionSessionState`, `productionMediaFailureReason`, terminal reason enum, and cleanup/disconnect booleans.
- Added a failure triage matrix covering readiness, Redis, token/backend, LiveKit/media, trust, signalling, relaunch, split-brain, and Element Call fallback issues.
- Added stop criteria, rollback procedure, and a post-session report template.
- Added security cleanup guidance for temporary SSH keys, disposable `/tmp/salemx-*.json` reports, password rotation if shared during diagnostics, ignored env file tracking/mode checks, and no env/log/tmp/backup/token/JWT/secret commits.
- Kept the distinction explicit: 2.26E is the product-card-only happy path proof; 2.27F is runner-assisted controlled matrix coverage.
- Recommended next phase: `2.28B — monitored controlled dogfood pilot window`.

## 2026-05-22 — 2.27F Controlled Dogfood Pilot Matrix Rerun

- Recorded the controlled engineering dogfood pilot matrix rerun after the 2.27D split-brain fix and 2.27E runtime proof.
- Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, LiveKit room provisioning true, and A/B trust ready.
- Used the required private dogfood gates and kept the legacy fake/dry-run gate unset.
- Happy path A -> B and reverse B -> A reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- Two repeated A -> B calls reached active audio and returned idle with no stale session and no split-brain.
- Decline, cancel, and timeout returned A/B to idle with terminal `cancelled`, `outgoingTimeout`, or `incomingTimeout` as expected.
- Backend-off immediate accept with the local staging call-service down failed closed with `connectingFailed`, `tokenHTTPUnavailable`, and no LiveKit client connect.
- Backend recovery reached A/B active audio and then idle after hangup.
- Relaunch during active audio and ringing restored no stale active/ringing session and no unexpected media path.
- Listener/open-room unavailable behavior remained safe with no active session and no unexpected media/token path.
- LiveKit-off was not run because the staging LiveKit instance is shared.
- Runner commands were used for matrix control/status; this is acceptable for controlled engineering dogfood matrix coverage, but it is not a claim that every matrix case was manually product-card-only.
- Product-card-only happy path remains separately proven by 2.26E.
- Confirmed Element Call route remained untouched, no code/docs changed during the runtime proof, and the worktree stayed clean.
- Dogfood decision: continue controlled engineering dogfood on the narrow staging path.
- Recommended next phase: `2.28A — controlled dogfood operational hardening and pilot monitoring`.

## 2026-05-22 — 2.27E Repeated-Call Split-Brain Regression Runtime Proof

- Recorded the runtime proof after commit `38fa26586` fixed post-answer callee media failure propagation.
- Preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, LiveKit room provisioning true, and A/B trust ready.
- Used the required private dogfood gates: product UI, private dogfood, production start, and staging token base URL.
- Kept the legacy fake/dry-run gate unset.
- Proved two normal repeated A -> B calls reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- Forced a safe callee post-answer token/backend failure by launching B with an unavailable local token backend.
- Confirmed B failed closed with `tokenHTTPUnavailable`, A received the terminal path, A did not remain `activeAudio`, and A/B ended idle with no active session.
- Restored B to the normal staging URL and confirmed a recovery call reached A/B `activeAudio`, then hangup returned A/B to idle with cleanup/disconnect attempted and media failure `none`.
- Confirmed Element Call route remained untouched and no code changes were needed during the runtime proof.
- Recommended next phase: `2.27F — controlled dogfood pilot matrix rerun after split-brain fix`.

## 2026-05-22 — 2.27A Controlled Engineering Dogfood Pilot Checkpoint

- Recorded the final pilot readiness decision: controlled engineering dogfood pilot is allowed, conditional, and narrow.
- Kept the approval limited to named engineering operators, DEBUG/integration builds, staging call-service, staging LiveKit, foreground/open encrypted direct 1:1 rooms, verified/trusted peers, private native audio card, and audio only.
- Kept broad internal dogfood, product beta, public rollout, production activation, Element Call replacement, CallKit, push/background incoming, missed calls, video, and session restoration blocked.
- Clarified the proof chain: 2.25F staging active audio, 2.26C controlled matrix, 2.26D explicit private dogfood gate in `76f2064ca`, and 2.26E product-card-only smoke plus listener preparation in `07256bf0a`.
- Documented that the old `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name must remain unset for staging product-card-only proof and pilot sessions.
- Added pilot requirements for backend readiness, Redis allocation/rate-limit connectivity, storage-key configuration, LiveKit room provisioning, Synapse validation smoke, A/B trust, encrypted 1:1 room availability, listener/card availability, and no stale active session.
- Added Element Call fallback smoke to the pilot matrix.
- Tightened pilot reporting to pass/fail and redacted status fields only.
- Added explicit stop and rollback criteria for leakage, missing gates, Element Call route changes, untrusted peer/device connection, stale active session survival, invalid token issuance, and non-fail-closed media failures.
- Recommended next phase: `2.27B — controlled engineering dogfood pilot execution report`.

## 2026-05-22 — 2.26E Product-Card-Only Staging Smoke

- Ran the private product-card-only staging happy path under the explicit DEBUG/integration-only `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` gate.
- Confirmed the old `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name was explicitly unset and not used.
- Confirmed activation stayed blocked with `appRolloutDisabled` when the private dogfood gate was absent, with no Matrix send, token/media path, or LiveKit client connect.
- Confirmed activation enabled with dependencies ready, peer trust ready, and key wrapper available when the private dogfood gate was present.
- Proved A Start from the private card -> B incoming ringing -> B Accept from the private card -> A/B `activeAudio` -> hangup -> A/B `idle`.
- Confirmed encryption ready, media connect attempted, LiveKit client connect attempted, and `productionMediaFailureReason=none`.
- Used the runner only for launch, status, activation, and trust polling; Start, Accept, and Hang up were manual product-card taps.
- Fixed the receiver listener preparation gap in commit `07256bf0a`: card status now prepares/arms the listener only when private dogfood activation is already enabled.
- Confirmed listener preparation does not start outgoing calls, request tokens, send Matrix events, or connect media, and does not run without the private dogfood gate.
- Kept Element Call route, CallKit, push, video, and global production activation unchanged.
- Validation passed: `RoomFlowCoordinatorTests` 92 tests, `NativeDirectCallInternalControlPanelTests` 34 tests, Release build, SwiftFormat/SwiftLint with existing file-length warnings only, `git diff --check`, and direct-call forbidden scan.
- Recommended next phase: `2.27A — controlled engineering dogfood pilot runbook/final checkpoint`.

## 2026-05-22 — 2.26D Private Dogfood Activation Gate Cleanup

- Replaced the app-side `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` activation shim with the explicit `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` gate.
- Kept the new gate DEBUG/integration-only; it requires `IS_RUNNING_INTEGRATION_TESTS=1`, `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`, and `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`.
- Confirmed `appRolloutDisabled` is still the default activation result when the private dogfood gate is absent.
- Confirmed `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1` and `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1` do not enable rollout/capability readiness by themselves.
- Updated the two-client diagnostic runner to pass `SIMCTL_CHILD_NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` to simulator launches.
- Kept Element Call routing, CallKit, push, video, trust policy, and global production activation unchanged.
- Updated the dogfood runbook/status docs to require the explicit private dogfood gate; the product-card-only proof was completed later in 2.26E.
- Recommended the then-next phase: `2.26E — product-card-only staging dogfood smoke under explicit private dogfood gate`.

## 2026-05-22 — 2.26C Controlled Staging Dogfood Matrix

- Ran the controlled engineering dogfood matrix on the staging path with redacted output only.
- Preflight passed with call-service readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit/storage booleans true, and LiveKit room provisioning true.
- A/B trust passed with `ownSessionVerified=true`, `crossSigningReady=true`, `peerTrustReady=true`, and `peerTrustReadiness=peerTrustReady`.
- Happy path A -> B, reverse B -> A, and repeated calls reached `productionSessionState=activeAudio`, then returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- Decline incoming, cancel outgoing, and timeout all cleared safely with terminal reasons `cancelled`, `outgoingTimeout`, or `incomingTimeout`.
- Backend-off failed closed with `tokenHTTPUnavailable`, no LiveKit client connect, and cleanup/disconnect attempted; backend recovery reached `activeAudio` again.
- Relaunch during active and relaunch during ringing restored no stale active or ringing session.
- Listener-not-armed behavior was safe: B had no active session and A cancel cleaned up safely.
- LiveKit-off fail-closed was not run because shared staging LiveKit should not be stopped during this session.
- Element Call route remained untouched and no code changed.
- Caveat: the runner path required the existing DEBUG rollout/capability shim gate to avoid `appRolloutDisabled`; media, token issuance, and LiveKit were real staging, but this is not yet a clean product-card-only dogfood proof.
- Recommended next phase: `2.26D — native direct-call activation gate cleanup / product-card-only dogfood readiness`.

## 2026-05-22 — 2.26B Controlled Staging Dogfood Checklist

- Updated the private native audio dogfood runbook from local-fake proof wording to the current staging path truth.
- Recorded the conditional yes for named-engineer, DEBUG/integration, foreground/open-room, encrypted 1:1, verified-peer staging dogfood.
- Added the required staging gates, operational preflight checklist, redacted reporting format, stop conditions, rollback path, and dogfood session matrix.
- Kept broader dogfood blockers explicit: no CallKit, push/background incoming, missed calls, video, session restoration, broad internal rollout, public rollout, or Element Call replacement.
- Confirmed the runbook keeps Element Call as the fallback path and keeps token/JWT/secret/raw ID redaction mandatory.

## 2026-05-22 — 2.25F Staging iOS ActiveAudio Smoke

- Re-ran the A/B iOS private native audio staging smoke after backend commit `33e95e7b1`.
- Confirmed A/B diagnostic launch succeeded with the staging token base URL and private product UI gate.
- Confirmed A/B reached `productionSessionState=activeAudio` with `productionEncryptionState=ready`.
- Confirmed A/B attempted media connect and LiveKit client connect, with `productionMediaFailureReason=none`.
- Confirmed hangup returned A/B to `productionSessionState=idle`, cleared active sessions, and attempted media disconnect and cleanup.
- Confirmed the previous `liveKitURLUnreachable` / service-not-found-like blocker is resolved by server-side LiveKit room pre-create.
- No iOS app code, Element Call route, CallKit, push, video, shared LiveKit config, or global production activation changed.

## 2026-05-22 — 2.25E Call-Service LiveKit Room Pre-Create

- Added a `LiveKitRoomProvisionerProtocol` boundary and a production/staging RoomService implementation for `CreateRoom`.
- Kept participant tokens narrow: `roomJoin`, publish, and subscribe only, with no `roomAdmin` or participant `roomCreate` grant.
- Wired room pre-create after Redis allocation and before token issuance so failure returns `M_DIRECT_CALL_LIVEKIT_ROOM_UNAVAILABLE` and no participant token is issued.
- Treated LiveKit already-exists responses as success so caller/callee reuse and concurrent retries converge on the allocated room.
- Added local fake/no-op provisioning and focused backend tests for success, ordering, failure, idempotency, rate-limit ordering, readiness redaction, and RoomService request shape.
- Did not change iOS behavior, Element Call routes, CallKit, push, video, shared LiveKit config, or global production activation.
- Staging iOS smoke later proved the private card reaches active audio against the pre-create path.

## 2026-05-12 — 2.10M Production E2EE Key Wrapping Seam Inspection

- Inspected `DirectCallEncryptionServiceProtocol`, `ProductionDirectCallEncryptionService`, diagnostic encryption, signal payload models, engine key lifecycle, LiveKit E2EE key store, and production dependency factory wiring.
- Confirmed production encryption remains intentionally fail-closed and is not connected to Matrix crypto or the LiveKit media key store.
- Confirmed the room-flow path already has the required room and peer metadata plus an existing injection point through `NativeDirectCallRoomFlowOwner`.
- Confirmed current app Matrix crypto proxies expose identity/key status only; they do not expose a narrow safe primitive for per-call media-key wrapping.
- Confirmed SDK room sending should encrypt the custom direct-call message-like event in encrypted rooms, but room encryption alone is not the production media-key wrapping design because the app must still hand only opaque wrapped key material to Matrix signalling.
- Found Rust SDK source has lower-level custom encrypted to-device support, but the current Swift app/wrapper does not expose an API that returns or consumes an opaque direct-call key envelope for the existing room-timeline signal path.
- Recommended the production key-exchange payload keep call, room, sender, key identifier, algorithm/version, sender device, recipient user, expiry, and opaque ciphertext fields, with per-device details hidden inside the opaque SDK-produced envelope where possible.
- Recommended multi-device handling wrap to all eligible peer devices and fail closed on unknown or unverifiable trust until UX/product policy exists.
- Identified that production key wrapping likely needs an async service boundary because Matrix crypto/device lookup is asynchronous.
- Recommended the next implementation phase as a fail-closed app seam skeleton that introduces a narrow key-wrapping protocol and shared media key-store bridge without real SDK crypto or production activation.

## 2026-05-12 — 2.10N Production E2EE App Key-Wrapping Seam Skeleton

- Added production-shaped media key wrap/unwrap request and envelope models that carry call, room, sender, recipient, device, intent, expiry, key ID, and opaque envelope metadata with redacted descriptions.
- Added `DirectCallMediaKeyWrappingProtocol` and a default `FailClosedDirectCallMediaKeyWrapper` that cannot wrap or unwrap and never stores key material.
- Extended `ProductionDirectCallEncryptionService` so future production Matrix crypto wrapping can plug in with a shared `DirectCallLiveKitMediaKeyStore`.
- Kept the default production encryption path fail-closed when no wrapper, key store, own user metadata, or valid wrapped envelope is available.
- Updated `NativeDirectCallProductionDependenciesFactory` to accept a future key wrapper, own user/device metadata, and shared media key store while remaining disabled by default.
- Added focused production key-wrapping tests covering fail-closed behavior, fake wrapper generation/consume, metadata mismatch rejection, idempotent cleanup, and shared key-store factory wiring.
- Confirmed diagnostic encryption remains isolated and the production factory does not reference diagnostic-only types.
- Regenerated `SalemX.xcodeproj` so the new test file is part of the UnitTests target.
- Recommended next phase: prototype the narrow Matrix SDK/wrapper key wrapping seam that can replace the fail-closed wrapper without exposing raw Matrix JSON or media keys.

## 2026-05-12 — 2.10O Matrix SDK Narrow Key Wrapping Seam Inspection

- Inspected Rust SDK crypto, device, to-device, room send, widget, FFI, and generated Swift binding surfaces in the local SDK and wrapper workspaces.
- Confirmed the Rust crypto layer can encrypt arbitrary custom to-device content for a device using Olm via `Device::encrypt_event_raw`.
- Confirmed the Rust crypto layer has multi-device support via `OlmMachine::encrypt_content_for_devices`, including trust-aware filtering through `CollectStrategy`.
- Confirmed the high-level SDK exposes an `encrypt_and_send_raw_to_device` helper behind the experimental custom to-device feature, and widget support already uses this path for encrypted custom to-device traffic.
- Confirmed the current Swift FFI bindings expose identity and trust state, but not a direct-call-specific wrapper that returns or consumes an opaque media-key envelope.
- Confirmed a separate production to-device key message is possible, but the safer next design keeps the existing room direct-call signal as the deterministic carrier and places only an SDK-produced opaque per-device envelope in that signal.
- Recommended a narrow SDK/FFI API that wraps the per-call media key into a redacted direct-call envelope and unwraps it on the recipient device without exposing Matrix event JSON or broad raw APIs.
- Identified that a real implementation will need async app integration because device lookup, session setup, and envelope generation/decryption are asynchronous.
- Recommended next phase: implement a local SDK prototype for `wrapDirectCallMediaKey` and `unwrapDirectCallMediaKeyEnvelope`, with focused Rust/FFI tests before publishing a wrapper artifact.

## 2026-05-12 — 2.10P SDK Direct-Call Media Key Envelope Prototype

- Prototyped a narrow Matrix Rust SDK direct-call media-key envelope seam in the local SDK workspace.
- Added a direct-call-specific SDK module that models wrap info, unwrap info, an opaque envelope, unwrap result, trust policy, and redacted error cases.
- Added prototype SDK methods on `Encryption` for wrapping a per-call media key into an opaque envelope and unwrapping that envelope on an intended recipient device.
- Added FFI records and async methods that mirror the SDK API shape without exposing Matrix event JSON, device maps, or Olm internals to the app.
- Kept the existing direct-call room signal as the deterministic carrier; the prototype places only an SDK-produced opaque per-device envelope into that signal.
- Validated envelope metadata, expiry, intended recipient, event type, and SDK decryption sender metadata on unwrap before returning media key material to the app encryption boundary.
- Added focused SDK tests for redacted debug output, malformed envelope handling, metadata mismatch, and expiry fail-closed behavior.
- Confirmed `cargo check -p matrix-sdk-ffi` passes for the prototype.
- Confirmed `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib` passes.
- Did not publish wrapper artifacts, update the app dependency pin, modify app production code, or activate production direct calls.
- Identified the next blocker: add full cryptographic SDK round-trip tests using real test devices before generating Swift bindings or publishing an artifact.

## 2026-05-12 — 2.10Q SDK Direct-Call Media Key Envelope Crypto Tests

- Added high-level Matrix SDK tests that prove the direct-call media key envelope can be wrapped and unwrapped cryptographically through the prototype SDK API.
- Used `MatrixMockServer` crypto helpers to create Alice and Bob clients with mocked Matrix crypto endpoints, device keys, one-time-key claiming, and encrypted room state.
- Proved Alice can wrap a per-call media key into an opaque envelope for Bob and Bob can unwrap it back to the original key material.
- Proved the opaque envelope serialization and debug output do not contain the test media key material.
- Added fail-closed coverage for wrong call ID, room ID, sender, recipient, intent, and key ID.
- Added non-recipient coverage showing a third client cannot unwrap an Alice-to-Bob envelope.
- Added conservative trust-policy coverage showing `OnlyTrustedDevices` rejects the current unverified test peer device set with `TrustViolation`.
- Added multi-device coverage showing envelopes include all eligible Bob devices and Bob's second device can unwrap the envelope.
- Confirmed `cargo test -p matrix-sdk --features experimental-send-custom-to-device direct_call --lib` passes.
- Confirmed `cargo check -p matrix-sdk-ffi` passes.
- Committed the SDK prototype and crypto tests as `f7c2cfe5c Add direct-call media key envelope crypto tests`.
- Did not publish wrapper artifacts, update the app dependency pin, modify app production code, or activate production direct calls.
- Recommended next phase: build/publish the Swift wrapper artifact from the proven SDK commit, then adapt the app key-wrapping seam to async SDK-backed wrapping in a later phase.

## 2026-05-12 — 2.10R Matrix SDK Direct-Call Key Envelope Wrapper Publication

- Revalidated the SDK commit `f7c2cfe5c Add direct-call media key envelope crypto tests` with `cargo check -p matrix-sdk-ffi` and focused `direct_call` SDK tests.
- Created and pushed SDK tag `salemx-direct-call-key-envelope-f7c2cfe5c`.
- Built a full Release `MatrixSDKFFI.xcframework` for iOS device and simulator targets from the proven SDK commit.
- Published the reproducible artifact at the Matrix SDK release URL and verified the downloaded checksum: `654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e`.
- Regenerated the Swift wrapper bindings so MatrixRustSDK exposes the direct-call media key envelope records and async wrap/unwrap methods.
- Updated wrapper `Package.swift` to use the real release asset URL and checksum, with no local binary target path.
- Validated wrapper `swift package resolve`, `swift package describe`, API presence, path scan, and `git diff --check`.
- Committed wrapper changes as `1e58d0a Add direct-call media key envelope bindings` and tagged `salemx-matrix-rust-components-swift-26.03.10-salemx.3`.
- Pinned the app to wrapper commit `1e58d0a4317e3ff74c2d565cf532bc8d035bcc8f` in `project.yml`, the generated Xcode project, and `compound-ios/Package.resolved`.
- Ran focused app unit tests for production key wrapping and media engine coverage after the pin.
- Ran the app Release build after the pin.
- Kept production direct calls disabled; no visible UI, Element Call route, CallKit, push, or production feature activation was changed.
- Recommended next phase: adapt the app production key-wrapping seam to the async SDK envelope API while preserving fail-closed default behavior.

## 2026-05-12 — 2.10S App Async Matrix SDK Key Wrapper Skeleton

- Inspected the generated MatrixRustSDK Swift API from the pinned wrapper artifact.
- Confirmed the direct-call media key envelope SDK methods are async on `EncryptionProtocol`:
  - `wrapDirectCallMediaKey(info:)`
  - `unwrapDirectCallMediaKeyEnvelope(info:envelope:)`
- Confirmed the generated SDK models carry call, room, sender, recipient, intent, key ID, expiry, and opaque ciphertext metadata without exposing raw Matrix event JSON.
- Migrated the app key wrapping boundary to async in `DirectCallMediaKeyWrappingProtocol`.
- Migrated `DirectCallEncryptionServiceProtocol` key generation and remote key consume methods to async, with `DirectCallEngine` awaiting them in already-async call paths.
- Added `MatrixSDKDirectCallMediaKeyWrapper`, a production-shaped adapter that maps app wrap/unwrap request models to the generated SDK FFI models and maps SDK envelopes/results back to app models.
- Kept the SDK-backed wrapper fail-closed when no SDK encryption dependency is injected.
- Kept `FailClosedDirectCallMediaKeyWrapper` as the default production wrapper and did not inject the SDK-backed wrapper into runtime production dependencies.
- Added tests with a fake SDK adapter proving request mapping, envelope/result mapping, SDK failure mapping, redacted descriptions, and fail-closed missing dependency behavior.
- Confirmed diagnostic encryption remains compatible with the async protocol and still isolated behind DEBUG/integration gates.
- Ran focused app unit tests for production key wrapping, direct-call engine, and media engine coverage.
- Ran the app Release build.
- Committed app changes as `9882b6ffa Add async Matrix SDK direct-call key wrapper`.
- Recommended next phase: inspect or add the narrow production dependency injection seam that supplies a Matrix SDK direct-call key envelope wrapper to the production factory while keeping runtime activation disabled.

## 2026-05-12 — 2.10T Production SDK Key Wrapper Injection Seam

- Inspected the app-side async `MatrixSDKDirectCallMediaKeyWrapper`, production encryption service, production dependency factory, room-flow ownership path, and SDK proxy boundaries.
- Chose a narrow dependency seam on `NativeDirectCallProductionDependenciesFactory` instead of exposing `MatrixRustSDK.EncryptionProtocol` or raw SDK client access through app-wide room/client protocols.
- Added support for passing `MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol` into the production dependencies factory.
- The factory now constructs `MatrixSDKDirectCallMediaKeyWrapper` from that narrow envelope wrapper when production dependencies are explicitly enabled.
- Preserved explicit `DirectCallMediaKeyWrappingProtocol` precedence so tests and future runtime integration can override the SDK wrapper cleanly.
- Preserved default fail-closed behavior: missing production config or missing wrapper still leaves production dependencies disabled or backed by `FailClosedDirectCallMediaKeyWrapper`.
- Added tests proving the factory can construct and use the SDK-backed wrapper from the narrow envelope seam, and that an explicit wrapper prevents SDK wrapper use.
- Confirmed no visible UI, Element Call route, CallKit, push, production feature flag, broad raw API, or diagnostic secret/token path changed.
- Ran focused direct-call and RoomFlow unit tests, Release build, SwiftFormat/SwiftLint on changed files, `git diff --check`, and the direct-call forbidden scan.
- Committed app changes as `000d1f12d Add production key wrapper injection seam`.
- Recommended next phase: inspect/add a runtime provider seam that can obtain the SDK encryption object from the session/client layer and expose only a direct-call envelope wrapper to production dependency construction.

## 2026-05-12 — 2.10U Production Runtime SDK Key Wrapper Provider Seam

- Inspected the SDK-backed key wrapper, production dependency factory, `ClientProxy`, room-flow construction path, and existing SDK encryption usage.
- Added `DirectCallMediaKeyEnvelopeWrappingProviding`, a narrow provider protocol that exposes only a direct-call media key envelope wrapper.
- Kept broad app protocols unchanged: `ClientProxyProtocol`, `RoomProxyProtocol`, and `TimelineProxyProtocol` do not expose raw MatrixRustSDK client, room, timeline, event JSON, or crypto APIs.
- Made concrete `ClientProxy` provide `MatrixSDKDirectCallMediaKeyEnvelopeWrapperAdapter` from its private `client.encryption()` dependency.
- Updated `NativeDirectCallProductionDependenciesFactory` to use dependencies in safe precedence order:
  - explicit `DirectCallMediaKeyWrappingProtocol`
  - explicit `MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol`
  - runtime `DirectCallMediaKeyEnvelopeWrappingProviding`
  - `FailClosedDirectCallMediaKeyWrapper`
- Ensured the factory does not ask the runtime provider while production configuration is disabled.
- Added tests proving provider-absent fail-closed behavior, provider-backed SDK wrapper construction, and explicit wrapper precedence.
- Confirmed diagnostic direct-call encryption and LiveKit paths remain unaffected.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and RoomFlow unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `2f8bc409a Add production key envelope provider seam`.
- Recommended next phase: inspect/add a disabled production dependency assembly seam that can combine production config, token transport/auth, LiveKit client, shared media key store, and the key envelope provider without activating UI or production direct calls.

## 2026-05-13 — 2.10V Disabled Production Direct-Call Dependency Wiring

- Inspected production direct-call dependency construction across the production configuration, token client, HTTP transport, Matrix access-token provider, LiveKit client, SDK key envelope provider, and room-flow ownership seams.
- Added `NativeDirectCallProductionDependencyAssembly`, a disabled-by-default assembly seam that combines explicit production configuration with injected runtime providers.
- The assembly requires production config, HTTP transport, Matrix access-token provider, LiveKit client, key envelope provider, and own user ID before creating production dependencies.
- Missing configuration or any required runtime provider returns disabled/fail-closed dependencies.
- The assembly creates `ProductionDirectCallLiveKitTokenClient` from injected transport/auth only when explicitly configured, preserving the no-real-network-by-default behavior.
- Added narrow `ClientProxy` conformance to `DirectCallMatrixAccessTokenProviding` so future runtime wiring can provide the Matrix access token without broadening `ClientProxyProtocol`.
- Added tests proving default-disabled behavior, missing-provider fail-closed behavior, and fully injected assembly behavior using fake HTTP/auth/LiveKit/key-envelope providers.
- Confirmed diagnostic direct-call encryption and LiveKit paths remain isolated behind DEBUG/integration gates.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and RoomFlow unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `e9a1c8d1f Add disabled production direct-call dependency wiring`.
- Recommended next phase: inspect/add a guarded production room-flow injection seam that can pass assembled production dependencies to native direct-call room ownership without activating visible UI or production direct calls.

## 2026-05-13 — 2.10W Production Activation Gate Design Inspection

- Inspected `AppSettings`, existing feature flags, `directOneToOneCallsEnabled`, remote settings hooks, Element well-known handling, client/server capability surfaces, AppCoordinator session setup, flow coordinator injection, and native direct-call production dependency assembly.
- Confirmed `directOneToOneCallsEnabled` should not be reused as the native production activation switch because it currently belongs to the existing direct-call/Element Call placeholder path and explicitly logs that production signal transport is disabled.
- Recommended a multi-factor activation model: app rollout configuration, authenticated server capability, token endpoint discovery, production dependency readiness, encrypted 1:1 room eligibility, and future UI/CallKit readiness.
- Recommended a SalemX-specific Matrix client capability as the authoritative production server gate, instead of a local Developer Options toggle or diagnostic environment variable.
- Recommended endpoint discovery through an authenticated capability that advertises a same-origin relative token endpoint, with the existing unstable token path as the default contract.
- Recommended `.well-known` only for pre-auth hints or account/provider policy, not as sufficient production activation authority.
- Confirmed diagnostics must remain separate: DEBUG/integration env gates and runner tokens/secrets must not affect production activation.
- Did not modify app code, activate production direct calls, add UI, change Element Call routing, or wire CallKit/push.
- Recommended next phase: add a fail-closed production activation gate/configuration skeleton and capability DTOs/tests without threading it into visible runtime behavior.

## 2026-05-13 — 2.10X Production Direct-Call Activation Gate Skeleton

- Added `DirectCallProductionServerCapability` to model the SalemX native direct-call capability `kz.salemx.direct_call.native`.
- Modeled the supported production capability shape as version `1`, audio intent support, LiveKit media transport, E2EE required, and Matrix SDK direct-call media key envelope support.
- Added same-origin token endpoint resolution from a relative server-advertised path, plus a same-origin configured endpoint override for future controlled rollout.
- Added `DirectCallProductionRoomEligibility` with redacted room eligibility fields for encrypted direct 1:1 room checks.
- Added `DirectCallProductionActivationGate`, which is disabled by default and requires app rollout, server capability, same-origin endpoint, production dependency readiness, and room eligibility before returning enabled.
- Added redacted activation decisions and fail-closed disabled reasons for each modeled prerequisite.
- Added unit tests proving default-disabled behavior, capability decoding/redaction, every modeled fail-closed prerequisite, same-origin endpoint handling, and the fully modeled enabled decision.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `dfdd74d62 Add production direct-call activation gate`.
- Recommended next phase: add or inspect a fail-closed server capability discovery seam that can feed the activation gate without activating production direct calls.

## 2026-05-13 — 2.10Y Production Direct-Call Server Capability Discovery Seam

- Inspected the activation gate, production configuration, dependency assembly, `ClientProxy.isLiveKitRTCSupported`, `.well-known` handling, and existing server/client capability surfaces.
- Found no existing narrow authenticated Matrix client capability API for the SalemX native direct-call capability; the existing LiveKit RTC support helper and `.well-known` patterns are separate and not sufficient for production activation.
- Added `DirectCallProductionCapabilityProviding`, an async provider seam that can eventually supply the SalemX native direct-call capability to the activation gate.
- Added `FailClosedDirectCallProductionCapabilityProvider`, which is the default provider and returns a redacted `providerUnavailable` result.
- Added `DirectCallProductionCapabilityPayloadDecoder` to decode the Matrix capabilities envelope for `kz.salemx.direct_call.native`, while failing closed for missing or malformed payloads.
- Kept same-origin endpoint validation centralized in `DirectCallProductionActivationGate` rather than duplicating activation decisions in discovery.
- Added tests for valid capability discovery, missing capability, malformed capability, unsupported capability fields flowing into activation-gate failures, and redacted descriptions.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, real network fetch, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `e18c9ff9f Add production direct-call capability discovery seam`.
- Recommended next phase: inspect or add a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder from session/client networking without activating production direct calls.

## 2026-05-13 — 2.10Z Production Activation Decision Assembly Skeleton

- Added `DirectCallProductionActivationDeciding` as the narrow async production activation decision boundary.
- Added `DirectCallProductionActivationDecisionService` to assemble app rollout configuration, server capability discovery, production dependency readiness, homeserver URL, and room eligibility through `DirectCallProductionActivationGate`.
- Added `NativeDirectCallProductionDependencyProviding` so dependency readiness can be supplied or faked without constructing listeners, media engines, room owners, or visible runtime behavior.
- Kept default behavior disabled: default configuration returns `appRolloutDisabled` and does not query capability or dependency providers.
- Kept capability failures fail-closed: missing or malformed capability discovery returns `serverCapabilityUnavailable` and skips dependency readiness checks.
- Added tests for disabled config, missing/malformed capability, unsupported capability, external endpoint, unavailable dependencies, ineligible room, fully valid enabled decision, provider call counts, and redaction.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, real network fetch, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `39c5b5dc4 Add production direct-call activation decision assembly`.
- Recommended next phase: add or inspect a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder from session/client networking without activating production direct calls.

## 2026-05-13 — 2.11A Production Activation Dry-Run Diagnostics

- Added `DirectCallProductionActivationDryRunDiagnostic`, a redacted diagnostic model for activation status, disabled reason, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
- Added `DirectCallProductionActivationDryRunDiagnosing` on the existing activation decision service.
- Kept the final answer delegated to `DirectCallProductionActivationGate`, so dry-run diagnostics share the same fail-closed activation logic as the production decision path.
- Kept default behavior disabled: default configuration returns `appRolloutDisabled` and does not query capability or dependency providers.
- Kept missing capability fail-closed: capability discovery failure returns `serverCapabilityUnavailable` and skips dependency readiness checks.
- Added tests proving bad room eligibility is redacted, all-valid input returns an enabled dry-run model, and no key generation, key consume, key cleanup, media engine construction, listener start, controller creation, signalling, or Matrix send work happens.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, real network fetch, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `5d58718ac Add production direct-call activation dry-run diagnostics`.
- Recommended next phase: add or inspect a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder and dry-run decision from session/client networking without activating production direct calls.

## 2026-05-13 — 2.11B Room-Scoped Production Activation Dry-Run Seam

- Added `NativeDirectCallProductionActivationDryRunProviding` as a room-scoped seam for redacted production native direct-call activation readiness.
- Added `FailClosedNativeDirectCallProductionActivationDryRunProvider`, which returns disabled with `roomUnavailable` before a room is active or when no provider is injected.
- Added `NativeDirectCallProductionActivationDryRunProvider`, which delegates to `DirectCallProductionActivationDryRunDiagnosing` with injected homeserver URL and room eligibility.
- Added `RoomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()` so future internal/debug tooling can ask for the current room's production activation readiness without starting listeners, controllers, media, signalling, Matrix sends, or UI.
- Threaded a dry-run provider factory alongside the existing native direct-call room-flow owner factory, defaulting to fail-closed and clearing it when the room owner resets.
- Added room-flow tests for no-active-room fail-closed behavior, active-room delegation, missing capability redaction, and no side effects on prepare/start/outgoing/accept/hangup/stop/reset paths.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env, real network fetch, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and room-flow unit tests, Release build, and a direct-call forbidden scan over added lines.
- Committed app changes as `8535cfb0d Add room-scoped production direct-call dry-run seam`.
- Recommended next phase: add or inspect a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder and room-scoped dry-run decision from session/client networking without activating production direct calls.

## 2026-05-13 — 2.11C Debug/Internal Production Activation Dry-Run Command Exposure

- Added a DEBUG/integration-only `nativeDirectCallProductionActivationDryRun` signal and redacted result to `UITestsSignalling`.
- Routed the dry-run command through AppCoordinator, UserSessionFlowCoordinator, ChatsTabFlowCoordinator, and the current RoomFlowCoordinator room-scoped dry-run provider.
- Added `production-activation-dry-run A|B` / `productionActivationDryRun A|B` to the two-client diagnostic runner.
- Kept the command read-only: it does not prepare native direct-call controllers, start listeners, start outgoing calls, accept calls, construct media engines, or send Matrix events.
- Limited output to redacted activation readiness fields: enabled state, disabled reason, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
- Added tests for signal encoding/redaction and ChatsTab room-scoped dry-run delegation without call side effects.
- Confirmed production direct calls remain disabled by default; `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env influence on production decisions, raw Matrix payloads, credentials, or key material were added.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, runner syntax/dry-run checks, focused direct-call and room-flow unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `83c967478 Expose production direct-call dry-run diagnostic command`.
- Recommended next phase: add or inspect a fail-closed authenticated capability fetch transport/provider seam that can feed the decoder and room-scoped dry-run decision from session/client networking without activating production direct calls.

## 2026-05-13 — 2.11D Production Activation Dry-Run Runtime Proof

- Ran the DEBUG/integration diagnostic harness against both clients after app diagnostic signalling readiness.
- Confirmed A and B both responded to the normal status command before the production activation dry-run query.
- `production-activation-dry-run A` returned the redacted disabled result: `enabled=false`, `reason=appRolloutDisabled`, `capabilityPresent=false`, `dependenciesReady=false`, `roomEligible=true`, and `endpointAccepted=false`.
- `production-activation-dry-run B` returned the same redacted disabled result.
- Confirmed no production call started and the dry-run did not trigger listener, media, or Matrix send side effects.
- Confirmed the disabled state is expected because production rollout remains off by default.
- No app code changed for this phase.
- Recommended next phase: inspect where app rollout configuration and authenticated server capability discovery should be sourced and threaded so dry-run checks can move beyond `appRolloutDisabled` without activating production direct calls.

## 2026-05-13 — 2.11E App Rollout and Capability Config Source Inspection

- Inspected `AppSettings`, `AppSettingsHook`, `RemoteSettingsHook`, `RemotePreference`, AppCoordinator session construction, ClientProxy capability helpers, production direct-call configuration, activation gate, activation decision service, dependency assembly, and room-scoped dry-run seams.
- Confirmed `directOneToOneCallsEnabled` remains the wrong activation source for native production direct calls because it belongs to the existing direct-call/Element Call placeholder path and must remain separate.
- Recommended a separate app-owned production rollout source that defaults false, is not user-facing, and is not diagnostic-env backed; `AppSettings` plus hook/remote-preference style configuration is the natural app-level home.
- Recommended authenticated Matrix `/capabilities` as the authoritative server capability source for `kz.salemx.direct_call.native`.
- Confirmed `.well-known` should remain at most a pre-auth hint or remote settings input and must never activate production direct calls by itself.
- Found the current app/Swift SDK surface has `ClientProxy.isLiveKitRTCSupported` and versions helpers, but no narrow generic authenticated `/capabilities` fetch for the SalemX native direct-call capability.
- Recommended a narrow provider using `DirectCallHTTPTransportProtocol` and `DirectCallMatrixAccessTokenProviding` to fetch `/_matrix/client/v3/capabilities`, avoid broad Matrix SDK exposure, and pass only response data into `DirectCallProductionCapabilityPayloadDecoder`.
- Recommended keeping token endpoint discovery same-origin and relative by default; absolute/external endpoints remain rejected unless a future explicit same-origin app override is provided.
- Found a sequencing issue: dependency readiness currently depends on `DirectCallProductionConfiguration.tokenEndpointBaseURL`, but production activation should usually derive the token endpoint from server capability. The next code phase should split side-effect-free runtime prerequisite readiness from endpoint-specific dependency assembly, or assemble dependencies after the activation gate accepts an endpoint.
- No app code changed and production direct calls remain disabled/fail-closed.
- Recommended next phase: add a default-disabled rollout configuration provider and fail-closed authenticated capabilities provider skeleton, then thread them toward dry-run decision construction without starting listeners, media, Matrix sends, UI, Element Call, CallKit, or push.

## 2026-05-13 — 2.11F Fail-Closed Rollout and Capability Source Skeleton

- Added `DirectCallProductionRolloutProviding` as the app-owned rollout configuration source boundary for native production direct-call activation.
- Added `FailClosedDirectCallProductionRolloutProvider`, which returns the default disabled `DirectCallProductionConfiguration` and does not read diagnostic env, developer options, or `directOneToOneCallsEnabled`.
- Added `HTTPDirectCallProductionCapabilityProvider`, a fail-closed authenticated Matrix `/capabilities` provider backed by injected `DirectCallHTTPTransportProtocol` and `DirectCallMatrixAccessTokenProviding`.
- The provider fetches `/_matrix/client/v3/capabilities`, decodes only `kz.salemx.direct_call.native`, and maps missing config, auth, transport, non-2xx responses, missing capability, and malformed payloads to redacted fail-closed results.
- Added a `GET` request helper for direct-call HTTP transport that carries the bearer header without exposing URL or credential values in descriptions.
- Added a rollout-provider convenience initializer on `DirectCallProductionActivationDecisionService` so future dry-run construction can consume app-owned rollout config without coupling to diagnostics.
- Added focused tests proving default rollout disabled, authenticated capability fetch behavior, missing-token/missing-transport fail-closed behavior, `.well-known` non-use, external endpoint rejection by the activation gate, and redaction of bearer values and response bodies.
- Confirmed `directOneToOneCallsEnabled` remains unused for native production activation.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env influence, listener start, media engine construction, Matrix send, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call unit tests, Release build, and the direct-call forbidden scan.
- Recommended next phase: inspect/add endpoint-aware production dependency readiness so capability-sourced same-origin token endpoints can feed dependency assembly without starting calls or UI.

## 2026-05-14 — 2.11G Activation Decision Uses Rollout and Capability Providers

- Refactored `DirectCallProductionActivationDecisionService` so it stores a `DirectCallProductionRolloutProviding` and asks the provider for rollout configuration at decision time.
- Added a redacted static rollout provider wrapper to preserve the existing static-configuration initializer path for tests and compatibility.
- Kept default activation behavior fail-closed: default rollout remains disabled, capability remains absent, and dependency readiness remains unavailable.
- Confirmed disabled rollout short-circuits before capability or dependency providers are queried.
- Confirmed rollout-enabled decisions query capability first, then dependency readiness, then room eligibility, with capability provider failures mapped to redacted `serverCapabilityUnavailable`.
- Added tests for default providers, rollout-enabled/capability-missing, valid-capability/dependencies-missing, dependencies-ready/room-ineligible, all-valid enabled dry-run, provider failure redaction, and no listener/media/signal side effects.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env influence, listener start, media engine construction, Matrix send, or production runtime activation changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and room-flow unit tests, Release build, and the direct-call forbidden scan.
- Recommended next phase: add endpoint-aware production dependency readiness so an activation-accepted same-origin token endpoint can feed dependency assembly without starting calls or UI.

## 2026-05-14 — 2.11I Production Activation Readiness Pack

- Added consolidated readiness tests proving production activation can only return enabled when rollout, authenticated capability, same-origin endpoint, dependency readiness, and encrypted direct 1:1 room eligibility are all valid.
- Extended fail-closed coverage for disabled rollout, missing capability, malformed capability, external endpoint rejection, unavailable dependencies, unavailable room, unencrypted room, and non-1:1 room cases.
- Strengthened dry-run signal redaction tests so encoded output excludes room IDs, peer IDs, endpoint values, credential-like fields, unwrapped key material, Matrix content, and encrypted payload values.
- Added no-side-effect checks proving the readiness path does not generate keys, consume keys, clear keys, construct media engines, start listeners, or send Matrix events.
- Confirmed production direct calls remain disabled by default and no visible UI, Element Call route, CallKit, push, listener start, media connect, or Matrix send behavior changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and room-flow unit tests, Release build, and the direct-call forbidden scan.
- Recommended next phase: inspect/add endpoint-aware production dependency readiness so activation-accepted capability endpoints can feed dependency assembly while the runtime remains disabled by default.

## 2026-05-14 — 2.12B Local Backend And App Production Token/Capability Smoke Pack

- Added a local-only fake Matrix capabilities response to the SalemX call service fake mode.
- Kept the fake capabilities endpoint gated behind `SALEMX_CALL_SERVICE_FAKE_MODE=1`; production-like service construction does not register it.
- Added backend tests for the fake capability payload and fake-only route registration.
- Added an env-gated app capability smoke test that uses `URLSessionDirectCallHTTPTransport` to fetch the local fake capability response through `HTTPDirectCallProductionCapabilityProvider`.
- Confirmed the existing env-gated token smoke continues to cover `ProductionDirectCallLiveKitTokenClient` against the local fake token endpoint.
- Added local smoke instructions in `docs/direct-call/LOCAL_BACKEND_SMOKE.md`.
- Confirmed default rollout still fails closed as `appRolloutDisabled`, and all-valid model inputs can only enable a dry-run decision in test code without runtime activation.
- Confirmed no visible UI, Element Call route, CallKit, push, listener start, media connect, Matrix send, or production activation changed.

## 2026-05-14 — 2.12C Local Backend HTTP Smoke Harness Fixed

- Fixed the local backend smoke path so the smoke tests actually execute when `SALEMX_DIRECTCALL_BACKEND_SMOKE=1` is set for the wrapper script.
- Added `Tools/Scripts/run_direct_call_backend_smoke.sh` to validate local fake backend token/capability endpoints, run the dedicated Swift Testing smoke suite, and fail if either HTTP smoke is skipped.
- Moved the local token and capability HTTP smoke tests into a dedicated `DirectCallBackendSmokeTests` suite inside an already-included test source file.
- Added a short-lived `/tmp/salemx-direct-call-backend-smoke.env` handoff because hosted simulator tests do not reliably inherit plain shell env.
- Proved default no-env behavior skips both HTTP smokes, and proved env-gated local smoke passes against the FastAPI fake backend.
- Confirmed no visible UI, Element Call route, CallKit, push, listener start, media connect, Matrix send, or production activation changed.

## 2026-05-14 — 2.12D Production Dry-Run Enabled True Local Fake Pack

- Strengthened the env-gated local backend capability smoke so it proves the authenticated fake `/capabilities` response can feed a production activation dry-run diagnostic with `enabled=true` when all model gates are valid.
- Confirmed the enabled proof requires fake rollout enabled, valid fake server capability, same-origin token endpoint acceptance, fake dependency readiness, and encrypted direct 1:1 room eligibility.
- Added request counting around `URLSessionDirectCallHTTPTransport` for the capability smoke so the dry-run path proves it performs only the capability GET and does not request a LiveKit token.
- Added side-effect assertions proving the enabled dry-run does not generate keys, consume keys, clear keys, or construct a media engine.
- Reconfirmed default production configuration remains disabled and the fail-closed rollout provider still prevents capability/dependency queries.
- Confirmed no visible UI, Element Call route, CallKit, push, listener start, media connect, Matrix send, or production activation changed.

## 2026-05-14 — 2.12E Runtime Fake-Enabled Production Activation Dry-Run

- Added the DEBUG/integration-only `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1` gate.
- Gated the fake path behind the existing integration diagnostic command requirements so the flag cannot affect Release builds or normal production runtime.
- Added an AppCoordinator dry-run provider factory branch that supplies fake rollout, fake server capability, and fake dependency readiness inputs only for the production activation dry-run diagnostic.
- Kept fake dependency objects fail-closed if accidentally invoked; they exist only so the activation model can report dependency readiness in dry-run.
- Updated the two-client diagnostic runner to pass the fake dry-run flag through `SIMCTL_CHILD_NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` without printing secrets.
- Added unit tests proving default runtime dry-run remains disabled, fake-enabled dry-run can return `enabled=true` for an eligible room, and the env gate requires integration diagnostics.
- Confirmed no visible UI, Element Call route, CallKit, push, listener start, media connect, Matrix send, or production activation changed.

## 2026-05-14 — 2.12E Runtime Fake-Enabled Production Activation Dry-Run Proof

- Ran the DEBUG/integration diagnostic harness with the fake-enabled production activation dry-run gate.
- Confirmed A and B app diagnostic signalling were ready with an active encrypted 1:1 room open.
- `production-activation-dry-run A` returned `enabled=true`, `reason=none`, `capabilityPresent=true`, `dependenciesReady=true`, `roomEligible=true`, and `endpointAccepted=true`.
- `production-activation-dry-run B` returned the same redacted enabled fields.
- Confirmed this was DEBUG/integration fake-enabled dry-run only and did not start a production call.
- Confirmed no visible UI, Element Call route, CallKit, push, listener start, Matrix send, or media connect was triggered.
- Recommended next phase: inspect the first safe internal iOS native direct-call trigger model without activating production calls or adding visible UI.

## 2026-05-14 — 2.13B Internal Production Trigger Dry-Run Command

- Added a DEBUG/integration-only `nativeDirectCallProductionTriggerDryRun` signal and redacted result to `UITestsSignalling`.
- Routed the trigger dry-run command through AppCoordinator, UserSessionFlowCoordinator, ChatsTabFlowCoordinator, and the current RoomFlowCoordinator room-scoped activation dry-run seam.
- Added `production-trigger-dry-run A|B` / `productionTriggerDryRun A|B` to the two-client diagnostic runner.
- Kept the command read-only: it checks the current production activation dry-run decision and returns `wouldStart=true` only when activation is already enabled.
- Limited output to redacted fields: `wouldStart`, enabled state, disabled reason, capability presence, dependency readiness, room eligibility, and endpoint acceptance.
- Confirmed the command does not prepare controllers, start listeners, start outgoing calls, accept calls, request LiveKit tokens, wrap keys, construct media engines, or send Matrix events.
- Confirmed no visible UI, Element Call route, CallKit, push, diagnostic env influence on production decisions, raw Matrix payloads, credentials, or key material were added.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, runner syntax/dry-run checks, focused direct-call and room-flow unit tests, Release build, and the direct-call forbidden scan.
- Committed app changes as `94b31aec8 Add internal production direct-call trigger dry-run command`.

## 2026-05-14 — 2.13C Production Trigger Dry-Run Runtime Proof

- Ran the DEBUG/integration diagnostic harness with the fake-enabled production dry-run gate.
- Confirmed A and B app diagnostic signalling were ready with an active encrypted 1:1 room open.
- `production-trigger-dry-run A` returned `wouldStart=true`, `enabled=true`, `reason=none`, `capabilityPresent=true`, `dependenciesReady=true`, `roomEligible=true`, and `endpointAccepted=true`.
- `production-trigger-dry-run B` returned the same redacted enabled fields.
- Confirmed this was DEBUG/integration fake-enabled dry-run only and did not start a production call.
- Confirmed no visible UI, Element Call route, CallKit, push, listener start, Matrix send, or media connect was intended by the dry-run.
- Recommended next phase: inspect the first internal production start command shape before allowing any DEBUG/integration command to start native direct-call runtime work.

## 2026-05-14 — 2.13E Internal Production Start Command Skeleton

- Added a DEBUG/integration-only `nativeDirectCallProductionStartOutgoingAudioCall` signal and redacted result to `UITestsSignalling`.
- Added `production-start-outgoing A|B` / `productionStartOutgoing A|B` to the two-client diagnostic runner.
- Added the dedicated `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1` gate; the command remains unavailable unless the existing integration diagnostic command gates are also enabled.
- Routed the command through AppCoordinator, UserSessionFlowCoordinator, ChatsTabFlowCoordinator, and the current RoomFlowCoordinator, terminating at the room-scoped production start seam.
- Kept the production start lane separate from `NativeDirectCallRoomDeveloperCommandRouter` so diagnostic dependencies are not accidentally used for production-shaped starts.
- Added a production owner factory seam that defaults nil/fail-closed and must be explicitly injected before any production-shaped owner can be used.
- The command rechecks the current production trigger dry-run decision immediately before starting and blocks with redacted reasons when the start gate is missing, activation is disabled, the room is unavailable, a non-terminal native direct-call session already exists, or the production owner is unavailable.
- Added a fake started path in tests that proves the command calls only the injected production owner and not the diagnostic owner.
- Kept output redacted: outcome, blocked reason, activation readiness booleans, and non-identifying session summary fields only.
- Confirmed no visible UI, Element Call route, RoomScreen call presentation, ElementCallService, CallKit, push, global production activation, Matrix content logging, credential logging, or key logging changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, runner syntax check, focused direct-call and room-flow unit tests, Release build, and the direct-call forbidden scan.
- Recommended next phase: runtime proof for `production-start-outgoing` in fail-closed and controlled fake-enabled contexts, without adding visible UI or public production activation.

## 2026-05-14 — 2.13F Internal Production Start Command Runtime Proof

- Ran the DEBUG/integration production start command path in controlled runtime.
- Confirmed `production-trigger-dry-run A` could report `wouldStart=true` with fake-enabled activation inputs in an active encrypted 1:1 room.
- Confirmed `production-start-outgoing A` blocks with `productionStartDisabled` when `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1` is absent.
- Confirmed `production-start-outgoing A` then blocked with `productionOwnerUnavailable` when the start gate was enabled but no production owner was assembled.
- Confirmed status remained idle: listener not started, no active session, no Matrix signal send, and no media connect.
- Confirmed no visible UI, Element Call route, CallKit, push, listener start, Matrix send, or media connect side effects occurred.

## 2026-05-14 — 2.13G Production Owner Wiring Inspection/Skeleton

- Replaced the always-unavailable production owner path with a lazy room-scoped production owner creation path in `RoomFlowCoordinator`.
- Kept the production owner separate from the diagnostic owner and retained it only after the DEBUG/integration start command gate and activation decision pass.
- Kept room open and dry-run behavior side-effect-free: opening a room no longer creates a production owner, starts a listener, sends Matrix events, or constructs media.
- Added production-shaped owner assembly from AppCoordinator using session runtime providers: URLSession HTTP transport, Matrix access-token provider, narrow Matrix SDK key envelope provider, LiveKit client, and client user/device metadata.
- Added precise fail-closed blocking with `dependenciesUnavailable` when production-shaped runtime dependencies cannot be assembled.
- Updated room-flow tests to cover dependency-unavailable blocking, production-owner started path, and listener-before-outgoing sequencing.
- Confirmed no visible UI, Element Call route, RoomScreen call presentation, ElementCallService, CallKit, push, global production activation, diagnostic secret/token use, broad SDK raw API, credential logging, or key logging changed.
- Ran `git diff --check`, SwiftFormat/SwiftLint on changed Swift files, focused direct-call and room-flow unit tests, Release build, and the direct-call forbidden scan.
- Recommended next phase: runtime proof for `production-start-outgoing` after production owner wiring, expecting either a redacted start attempt or a more precise production dependency/media/key/token failure than `productionOwnerUnavailable`.

## 2026-05-18 — 2.14E iOS Internal Production ActiveAudio Proof

- Recorded the first iOS internal production native direct-call `activeAudio` proof.
- Confirmed the proof used only the DEBUG/integration internal command path.
- Confirmed the proof used the local fake backend and local LiveKit dev server.
- B `production-start-listener` succeeded.
- A `production-start-outgoing` succeeded.
- B received the production invite and entered `incomingRinging`.
- B `production-accept` succeeded.
- B emitted an answer and answer send succeeded.
- A received the answer.
- A and B both reached `productionSessionState=activeAudio`.
- A and B both reported `productionEncryptionState=ready`.
- A and B both reported `productionMediaConnectAttempted=true` and `productionLiveKitClientConnectAttempted=true`.
- A and B both reported `productionMediaFailureReason=none`.
- Confirmed no visible UI, Element Call route, CallKit, push, or global production activation changed.
- Recommended next phase: `2.15A — internal production call cleanup/hangup command`.

## 2026-05-18 — 2.15A Internal Production Hangup Command

- Added a DEBUG/integration-only `nativeDirectCallProductionHangup` request and redacted result to `UITestsSignalling`.
- Added `production-hangup A|B` plus aliases to the two-client diagnostic runner.
- Routed the command through AppCoordinator, UserSessionFlowCoordinator, ChatsTabFlowCoordinator, and the active RoomFlowCoordinator production command lane.
- Required a retained production owner and active non-terminal production session before attempting hangup.
- On success, the command sends the terminal production signal through the production owner/controller path, then immediately runs terminal cleanup for the call.
- Extended production status with redacted terminal and media cleanup fields: last terminal reason, media disconnect attempted, and media cleanup attempted.
- Updated no-op and LiveKit media engines to record disconnect and cleanup attempts in diagnostics without exposing credentials or media-key material.
- Added tests for missing owner, missing active production session, successful hangup and cleanup, redacted engine failure, diagnostic owner isolation, and production status cleanup fields.
- Confirmed no visible UI, Element Call route, RoomScreen call presentation, ElementCallService, CallKit, push, or global production activation changed.
- Recommended next phase: `2.15B — internal production hangup runtime proof`.

## 2026-05-18 — 2.15B iOS Internal Production Full Lifecycle Proof

- Recorded the first iOS internal production native direct-call full lifecycle proof.
- Confirmed the proof used only the DEBUG/integration internal command path.
- Confirmed the proof used the local fake backend and local LiveKit dev server.
- B `production-start-listener` succeeded.
- A `production-start-outgoing` succeeded.
- B reached `incomingRinging`.
- B `production-accept` succeeded.
- A and B both reached `productionSessionState=activeAudio`.
- A `production-hangup` succeeded with `outcome=hungUp`.
- A emitted hangup and the send succeeded.
- A cleared its active production session and returned to idle.
- B received `directCallHangup`.
- B cleared its active production session and returned to idle.
- A and B both reported media disconnect and cleanup attempts.
- A and B both reported no production media failure.
- Confirmed no visible UI, Element Call route, CallKit, push, or global production activation changed.
- Recommended next phase: `2.16A — internal production call UI design inspection`.

## 2026-05-18 — 2.16C Internal Native Call Panel Runtime Proof

- Recorded runtime proof for the hidden DEBUG/internal native direct-call room control panel.
- Confirmed the panel was hidden without `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED`.
- Confirmed the panel appeared in both open encrypted r1/r2 DMs with `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`.
- Confirmed panel output/status remained redacted: no credential values or keys, JWTs, raw Matrix content, raw room IDs, or peer IDs.
- Used runner fallback actions because synthetic UI taps were unavailable in the runtime environment.
- Confirmed the runner exercised the same room-scoped production methods used by the panel: listener, start, accept, and hangup.
- Before hangup, A and B reached `activeAudio`, encryption was ready, media connect was attempted, LiveKit connect was attempted, and media failure was `none`.
- After `production-hangup A`, A and B returned to idle with no active session.
- A sent hangup successfully and B received `directCallHangup`.
- A and B reported media disconnect and cleanup attempts, with media failure `none`.
- Found a minor internal UI issue: the control row is horizontally clipped at the trailing edge, so later controls require horizontal scrolling.
- Kept scope DEBUG/internal only: no public UI activation, Element Call route changes, CallKit/push, or global production activation.
- Added and committed a runner-only fix so `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED` is forwarded into simulator launch.
- Recommended next phase: `2.16D — internal native call panel layout/action polish`.

## 2026-05-18 — 2.16D Internal Native Call Panel Layout/Action Polish

- Replaced the clipping-prone single control row with a compact two-row DEBUG/internal panel layout.
- Added explicit action enablement for Refresh, Arm listener, Start audio, Accept, and Hang up based on redacted native direct-call state.
- Kept status rendering side-effect-free: it does not start listeners, send Matrix events, request credentials, create media, or connect LiveKit.
- Confirmed the existing Element Call phone/video route remains untouched and separate from native direct-call controls.
- Added focused panel state tests for hidden-by-default behavior, gated visibility, action row grouping, button enablement, side-effect-free refresh/status rendering, and redaction.
- Committed app changes as `76b69aa27 Polish internal native call panel layout`.

## 2026-05-18 — 2.16E Internal Native Call Panel Runtime Visual/Action Proof

- Recorded runtime visual/action proof for the polished hidden DEBUG/internal native direct-call room panel.
- Confirmed the panel appeared in both A/B encrypted DM rooms with `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED=1`.
- Confirmed the two-row layout was readable and not clipped.
- Confirmed status text was redacted: no credential values or keys, raw Matrix content, raw room IDs, or peer IDs were shown.
- Confirmed existing Element Call phone/video buttons remained unchanged.
- Observed the initial visual state as `notRefreshed`, with only Refresh enabled.
- Confirmed runner dry-run readiness reported `wouldStart=true`, `enabled=true`, and peer trust ready.
- Used runner fallback because synthetic UI taps were unavailable.
- Confirmed the fallback exercised the same room-scoped production methods as the panel: B listener, A start, B incoming, B accept, A/B active audio, A hangup, and A/B idle.
- Confirmed media connected on both sides before hangup.
- Confirmed cleanup and disconnect were attempted after hangup.
- Confirmed no code changes were needed for the runtime proof.
- Kept scope DEBUG/internal only: no public UI activation, Element Call route changes, CallKit/push, or global production activation.
- Recommended next phase: `2.17A — internal native call product UI transition plan`.

## 2026-05-18 — 2.17C Private Native Call Room Card Runtime Proof

- Recorded runtime proof for the private product-shaped native direct-call room card.
- Confirmed the card appeared in A/B encrypted DM rooms with `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- Confirmed the card was hidden without `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED`.
- Confirmed `NATIVE_DIRECT_CALL_INTERNAL_UI_ENABLED` was not set and the diagnostic panel did not appear.
- Confirmed the product card appeared independently through the product UI gate.
- Confirmed existing Element Call phone/video buttons stayed visible and unchanged.
- Confirmed card status and runner output were user-safe/redacted: no credential values, JWTs, keys, raw Matrix content, raw room IDs, or peer IDs were printed.
- Used runner fallback because synthetic UI taps were unavailable.
- Confirmed the underlying room-scoped production lifecycle succeeded: B listener, A outgoing, B incoming ringing, B accept, A/B active audio, A hangup, and A/B idle.
- Before hangup, A and B reported active audio, encryption ready, media connect attempted, LiveKit connect attempted, and media failure `none`.
- After hangup, A and B reported no active session, idle state, media disconnect attempted, media cleanup attempted, and media failure `none`.
- Confirmed A sent hangup successfully and B received `directCallHangup`.
- Observed no new visual clipping.
- Noted current UI nuance: the card initially shows `unavailable(nativeCallsUnavailable)` until refreshed, and live visual refresh was not verified without synthetic taps.
- Confirmed no code changes were needed for the runtime proof.
- Recommended next phase: `2.17D — private native call card refresh/state binding polish`.

## 2026-05-19 — 2.18C Private Native Call Card Manual Lifecycle Proof

- Recorded manual runtime proof for the private product-shaped native direct-call room card.
- Confirmed the private native call card was visible with `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`.
- Confirmed B production listener was armed before the manual start flow.
- Manual UI Start audio from A caused B to reach `incomingRinging`.
- Manual UI Accept from B caused A and B to reach `activeAudio`.
- Manual UI Hang up from A caused A and B to return to idle.
- Confirmed A emitted hangup and the send succeeded.
- Confirmed B received `directCallHangup`.
- Confirmed A and B reported production media connect attempted and LiveKit client connect attempted.
- Confirmed A and B reported media disconnect and cleanup attempted after hangup.
- Confirmed A and B reported production media failure `none`.
- Confirmed existing Element Call buttons remained untouched.
- Kept scope private/internal product UI gate only: no CallKit, push, global production activation, or Element Call route change.
- Recommended next phase: `2.18D — private native call card repeated-call and edge-state proof`.

## 2026-05-19 — 2.18D Private Native Call Card Repeated-Call and Backend-Off Edge Proof

- Recorded repeated manual runtime proof for the private product-shaped native direct-call room card.
- First cycle succeeded from the private card: A Start audio, B Accept, A/B `activeAudio`, A Hang up, and A/B idle.
- Second cycle succeeded without relaunch: A Start audio again, B Accept again, A/B `activeAudio` again, B Hang up, and A/B idle.
- Confirmed no stale active session blocked the second call.
- Confirmed no stale terminal state blocked the second call.
- Confirmed the production listener and owner remained safe across cycles.
- Confirmed media disconnect and cleanup were attempted after hangups.
- Confirmed production media failure remained `none` during successful cycles.
- Recorded reverse-direction/backend-off edge behavior: B started a call, A reached `incomingRinging`, A accepted and sent answer successfully, and B received `directCallAnswer`.
- With the local token backend unavailable during the reverse-direction media step, the media/token path failed closed with user-safe `tokenHTTPUnavailable`.
- Confirmed A and B returned idle with `connectingFailed`, media disconnect/cleanup attempted, and no active session remaining.
- Confirmed no raw token, JWT, key, endpoint, room ID, peer ID, or raw Matrix content was printed.
- Kept scope private/internal product UI gate only: local fake backend / local LiveKit dev setup, no Element Call route change, no CallKit/push, and no global production activation.
- Recommended next phase: `2.18E — private native call card backend-recovery and LiveKit-off edge proof`, or `2.19A — private native call UI hardening plan` if edge coverage is considered sufficient.

## 2026-05-19 — 2.18E Private Native Call Card Backend-Recovery and LiveKit-Off Edge Proof

- Recorded runtime edge proof for backend recovery and LiveKit-off handling through the private product-shaped native direct-call room card.
- Backend-off behavior failed closed with the user-safe `tokenHTTPUnavailable` reason.
- Confirmed A and B returned idle with no active session.
- Confirmed media disconnect and cleanup were attempted.
- Confirmed output remained redacted.
- After the local fake backend was restarted, private-card Start/Accept recovered to `activeAudio` on A and B.
- Confirmed the recovered call reported encryption ready.
- Confirmed hangup returned A and B to idle.
- LiveKit-off behavior failed closed with the user-safe `liveKitNetworkFailed` reason.
- Confirmed A and B returned idle with no stale active session.
- Confirmed media disconnect and cleanup were attempted.
- After LiveKit was restarted, private-card Start/Accept recovered to `activeAudio` on A and B.
- Confirmed final hangup succeeded.
- Final production status showed A idle with no active session after emitting hangup and sending successfully.
- Final production status showed B idle with no active session after receiving `directCallHangup`.
- Confirmed cleanup and disconnect were attempted on both sides.
- Confirmed no new UI issue was observed and the existing Element Call route remained untouched.
- Noted a diagnostic nuance for the next phase: `productionMediaFailureReason` can remain stale after recovery. `tokenHTTPUnavailable` remained visible during the backend-recovered active call, and `liveKitNetworkFailed` remained visible after the LiveKit-recovered active call.
- Treat the stale media failure value as a diagnostic/status cleanup issue, not a runtime call blocker.
- Confirmed no code changes were needed.
- Recommended next phase: `2.19B — private native call card stale media failure cleanup`.

## 2026-05-19 — 2.19C Stale Media Failure Cleanup Runtime Proof

- Recorded runtime proof for stale production media failure cleanup after backend and LiveKit recovery.
- Backend-off with the local fake backend stopped failed closed with the user-safe `tokenHTTPUnavailable` reason.
- Confirmed A and B returned idle with no active session.
- Confirmed media disconnect and cleanup were attempted.
- After the local fake backend was restarted, private-card Start/Accept recovered to `activeAudio` on A and B.
- Confirmed `productionMediaFailureReason=none` on A and B, proving stale `tokenHTTPUnavailable` was cleared after the successful retry.
- LiveKit-off with the backend still running failed closed with the user-safe `liveKitNetworkFailed` reason.
- Confirmed A and B returned idle with no active session.
- Confirmed media disconnect and cleanup were attempted.
- After LiveKit was restarted, private-card Start/Accept recovered to `activeAudio` on A and B.
- Confirmed `productionMediaFailureReason=none` on A and B, proving stale `liveKitNetworkFailed` was cleared after the successful retry.
- Confirmed final hangup succeeded: A returned idle after emitting hangup and sending successfully, and B returned idle after receiving `directCallHangup`.
- Confirmed cleanup and disconnect were attempted on both sides after final hangup.
- Confirmed no UI issue was observed.
- Confirmed no code changes were needed during the runtime proof and the worktree was clean.
- Kept scope private/internal product UI gate only, with no Element Call route change, CallKit/push, or global production activation.
- Recommended next phase: `2.19D — private native call card decline/cancel/retry UX skeleton`.

## 2026-05-19 — 2.19E Private Native Call Card Decline/Cancel/Retry/Dismiss Runtime Proof

- Recorded runtime proof for private native call card decline, cancel, retry, and dismiss actions.
- Decline incoming proof passed: B received `incomingRinging`, B tapped Decline, B emitted reject, and the send succeeded.
- Confirmed A received `directCallReject`.
- Confirmed A and B returned idle with no active session after decline.
- Confirmed `productionMediaFailureReason=none` after the decline proof.
- Cancel outgoing proof passed: A started outgoing, A tapped Cancel before B accepted, A emitted cancel, and the send succeeded.
- Confirmed B received `directCallCancel`.
- Confirmed A and B returned idle with no active session after cancel.
- Confirmed `productionMediaFailureReason=none` after the cancel proof.
- Verified failed-state Retry/Dismiss rendering after the 2.19E fix: `failed(callServiceUnavailable)` now shows Retry and Dismiss instead of the broad disabled action row.
- Confirmed Retry did not auto-start a call.
- Confirmed A and B remained idle with no active session after Retry.
- Confirmed Dismiss cleared the local displayed error/outcome.
- Confirmed the card returned to Ready to call and the last action showed `dismissError:dismissed`.
- Confirmed existing Element Call phone/video buttons remained untouched.
- Confirmed no CallKit, push, or global production activation was introduced.
- Confirmed no raw token, JWT, key, envelope, or Matrix content was printed.
- Recommended next phase: `2.20A — private native call card timeout/rapid-tap hardening`.

## 2026-05-20 — 2.20D Private Native Call Card Rapid Action Runtime Proof

- Recorded runtime proof for rapid private native call card terminal actions after the 2.20C restart-prevention fix.
- Rapid Hang up proof passed: A and B returned idle with no active session.
- Confirmed A emitted hangup and B received `directCallHangup`.
- Confirmed cleanup and disconnect were attempted after rapid Hang up.
- Confirmed `productionMediaFailureReason=none` after rapid Hang up.
- Rapid Cancel proof passed: A and B returned idle with no active session.
- Confirmed A emitted cancel and B received `directCallCancel`.
- Confirmed `productionMediaFailureReason=none` after rapid Cancel.
- Rapid Decline proof passed after relaunching B onto the current 2.20C build.
- Confirmed B emitted reject and A received `directCallReject`.
- Confirmed A and B returned idle with no active session after rapid Decline.
- Confirmed `productionMediaFailureReason=none` after rapid Decline.
- Confirmed no accidental `outgoingRinging` or `incomingRinging` restart occurred on the current build.
- Explained the earlier failed Decline rerun as B still running the pre-fix app.
- Confirmed the existing Element Call route remained untouched.
- Confirmed no CallKit, push, or global production activation was introduced.
- Confirmed no code changes were needed and the worktree remained clean.
- Noted setup nuance: after relaunch, B needed the encrypted r1/r2 DM reopened and the production receive listener armed.
- Recommended next phase: `2.20E — private native call card timeout runtime proof`, or `2.21A — private native call UI internal-hardening plan` if timeout proof is deferred.

## 2026-05-20 — 2.20E Private Native Call Card Timeout Runtime Proof

- Recorded timeout runtime proof through the private native call card / production room-scoped path.
- Used the real configured ringing timeout of 45 seconds plus a small buffer.
- Confirmed no timeout hook and no code changes were used.
- Confirmed the worktree stayed clean during the proof.
- Outgoing timeout proof passed: A started an outgoing call through the production room-scoped path, A entered `outgoingRinging`, and B entered `incomingRinging`.
- Confirmed no accept, decline, cancel, or hangup command was sent during the timeout window.
- After timeout, A returned idle with no active session.
- Confirmed A emitted `timeout` and the send succeeded.
- Confirmed A reported terminal reason `outgoingTimeout`.
- Confirmed B returned idle with no active session after receiving `directCallTimeout`.
- Confirmed B reported terminal reason `incomingTimeout`.
- Confirmed media connect was not attempted and `productionMediaFailureReason` remained `none`.
- Repeated the proof in reverse direction from B to A.
- Confirmed B entered `outgoingRinging` and A entered `incomingRinging`.
- After timeout, B returned idle with no active session, emitted `timeout`, and reported terminal reason `outgoingTimeout`.
- Confirmed A returned idle with no active session, reported terminal reason `incomingTimeout`, and reported no receive failure.
- Confirmed `productionMediaFailureReason` remained `none` for the reverse timeout proof.
- Noted that outgoing and incoming timers are both 45 seconds, so caller/callee timeout emission can race.
- Confirmed runtime still proved both sides clear safely with user-safe timeout terminal reasons.
- Confirmed no new UI issue was observed.
- Confirmed the existing Element Call route remained untouched.
- Confirmed no CallKit, push, or global production activation was introduced.
- Recommended next phase: `2.21B — private native call UI typed snapshot/reducer cleanup`.

## 2026-05-20 — 2.21C Native Call Card Reducer Runtime Regression Proof

- Recorded runtime regression proof after the private native call card typed reducer cleanup.
- Found a regression where idle state with retained `tokenHTTPUnavailable` incorrectly showed Ready/canStart instead of `failed(callServiceUnavailable)`.
- Fixed the reducer mapping in commit `8cdae55d4` (`Restore failed native call card retry dismiss mapping`).
- Confirmed runtime recheck after the fix:
  - The failed backend/token state shows Retry and Dismiss.
  - Retry does not auto-start a call.
  - Dismiss clears only the local displayed error/outcome.
  - The card returns to the safe Ready to call state after Dismiss.
- Confirmed the existing Element Call route remained untouched.
- Confirmed no CallKit, push, or global production activation was introduced.
- Recommended next phase: `2.21D — private native call UI state architecture follow-up`, or `2.22A — internal usable checkpoint plan` if the architecture follow-up finds no additional cleanup needed.

## 2026-05-20 — 2.22C Private Native Call Relaunch/Listener Lifecycle Runtime Proof

- Recorded runtime proof for private native call relaunch and listener lifecycle behavior after 2.22B lifecycle hardening.
- Baseline lifecycle status included `productionListenerAvailable=true`, `productionRoomAttached=true`, and `productionSessionRestorationSupported=false`.
- Confirmed A and B had no owner, listener, active session, stale media failure, or raw room/peer IDs in output.
- ActiveAudio relaunch proof passed: A and B reached `activeAudio` with encryption ready and media failure `none`.
- After app relaunch and reopening the encrypted DM, no stale `activeAudio` was restored.
- Confirmed after activeAudio relaunch that `productionHasActiveSession=false`, `productionSessionRestorationSupported=false`, and the state was safe/fail-closed.
- Ringing relaunch proof passed: before relaunch A reported `outgoingRinging`, B reported `incomingRinging`, media connect was not attempted, and media failure was `none`.
- After relaunch and reopening the DM, no stale outgoing/incoming session was restored.
- Confirmed after ringing relaunch that `productionHasActiveSession=false`, `productionSessionState=unavailable`, and media failure was `none`.
- Room dismiss/reopen proof passed: B listener/owner was armed and idle, then after leaving and reopening the DM the B owner/listener reset.
- Confirmed final A/B status reported `productionListenerAvailable=true`, `productionRoomAttached=true`, `productionSessionRestorationSupported=false`, `productionHasActiveSession=false`, `productionSessionState=unavailable`, and `productionMediaFailureReason=none`.
- Confirmed no UI issue was observed.
- Confirmed the existing Element Call route remained untouched.
- Confirmed no CallKit, push, video, or global production activation was introduced.
- Confirmed no code changes were needed and the worktree stayed clean.
- Recommended next phase: `2.23A — private native audio call internal dogfood readiness review`.

## 2026-05-20 — 2.23B Private Native Audio Dogfood Runbook

- Added `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md` as the controlled engineering dogfood runbook and guardrail document.
- Recorded the dogfood decision as conditional engineering-only scope, not broad internal dogfood, product beta, public rollout, or Element Call replacement.
- Documented the allowed scope: DEBUG/integration only, private native card only, open encrypted direct 1:1 room only, foreground app only, verified/trusted peers only, and local fake backend plus local LiveKit or a hardened staging equivalent.
- Documented required gates: `IS_RUNNING_INTEGRATION_TESTS=1`, `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`, `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`, `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`, `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`, `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1`, and `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=...`.
- Documented setup for trusted `r1`/`r2` accounts, local fake backend, local LiveKit dev server, A/B launches, encrypted DM opening, and receiver listener arming when required.
- Documented allowed manual flows: Start/Accept/Hang up, Decline, Cancel, Retry/Dismiss, repeated calls, backend-off recovery, LiveKit-off recovery, and timeout.
- Documented known limitations: no background incoming, CallKit, push, missed calls, video, call restoration after relaunch, or production-hardened backend proof.
- Documented fail-closed behavior for backend unavailable, LiveKit unavailable, unverified peer, invalid room, app relaunch during ringing/active calls, and room dismiss/reopen.
- Documented redaction checklist, rollback steps, explicit non-goals, staging blockers, dogfood success criteria, and stop conditions.
- Confirmed the runbook keeps existing Element Call buttons unchanged and keeps CallKit, push, video, public rollout, `AllDevices` fallback, and global production activation out of scope.
- Recommended next phase: `2.23C — private native call dogfood listener/status polish`.

## 2026-05-20 — 2.23D Listener Availability Runtime Diagnostics Proof

- Recorded runtime diagnostics proof for listener availability status after 2.23C.
- After fresh relaunch, A reported `productionRoomAttached=true`, `productionListenerAvailable=true`, `productionOwnerAvailable=false`, and `productionListenerStarted=false`, mapping to listener-not-armed.
- Confirmed no passive side effects were observed: no Matrix send, no media connect, no LiveKit connect, and no active session.
- B initially reported `productionRoomAttached=false`, mapping to open-room-required until room reattachment.
- Explicit listener arm succeeded.
- After listener arm, A/B reported `productionOwnerAvailable=true`, `productionListenerAvailable=true`, `productionListenerStarted=true`, `productionRoomAttached=true`, and `productionSessionRestorationSupported=false`.
- Confirmed A/B had no active session and `productionMediaFailureReason=none` after listener arm.
- Incoming after listener arm worked: A started outgoing, B reached `incomingRinging`, B rejected/declined, A received `directCallReject`, and A/B returned idle with no active session.
- Final status showed A/B idle, no active session, listener available/started, A received `directCallReject`, B emitted reject and sent successfully, media cleanup/disconnect attempted, and media failure `none`.
- Confirmed existing Element Call route remained untouched.
- Confirmed no CallKit, push, video, or global production activation was introduced.
- Confirmed no code changes were needed and the worktree stayed clean.
- Limitations: manual visual card text was not verified from this shell, and the literal leave-DM-to-chat-list/reopen gesture was not performed.
- Treat this as runtime diagnostics proof, not full visual/manual UI proof.
- Recommended next phase: `2.24A — staging backend and LiveKit hardening plan`.

## 2026-05-20 — 2.24H Redis Local Integration Smoke

- Ran local Redis integration smoke for the SalemX call service Redis allocation store and Redis rate limiter.
- Started a disposable `redis:7-alpine` container on local port `6380` and verified it responded to `PING`.
- Used the pinned backend test environment and ASGI route harness with mocked Synapse validation; no real external Synapse credentials were used.
- Redacted staging readiness returned `ready=true`, `reason=ok`, `allocationStoreConfigured=true`, `allocationStoreShared=true`, `allocationStoreConnected=true`, `rateLimitConfigured=true`, `rateLimitShared=true`, `rateLimitConnected=true`, and `storageKeyConfigured=true`.
- Allocation smoke passed: first request returned `200`, repeat request returned `200`, incoming/callee request returned `200`, repeat requests reused the same allocation and LiveKit room, and caller/callee directions converged on the same LiveKit room.
- Rate-limit smoke passed: under-limit request returned `200`, over-limit request returned `429` with `M_DIRECT_CALL_RATE_LIMITED` and `retry_after_ms`, and no second token was issued after the limit was exceeded.
- Redaction verification passed: Redis keys/readiness output did not contain raw room IDs, peer IDs, user IDs, device IDs, bearer tokens, LiveKit participant tokens, JWTs, Synapse admin tokens, or LiveKit API secrets.
- Fail-closed smoke passed after stopping Redis: the rate-limit path returned `503` with `M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE` before token issuance, and the allocation-specific path returned `503` with `M_DIRECT_CALL_ALLOCATION_FAILED` before token issuance.
- Cleaned up the disposable Redis container; only the existing local LiveKit dev container remained running.
- Documented that this is local Redis smoke only. Deployed staging Redis smoke, real Synapse validation smoke, and LiveKit join smoke remain required before staging dogfood.
- Confirmed no iOS app behavior, Element Call route, CallKit, push, video, or global production direct-call activation changed.
- Recommended next phase: `2.24I — staging Synapse validation and LiveKit join smoke plan`.

## 2026-05-20 — 2.24J-prep Staging Synapse Smoke Harness

- Added a redacted operator-local staging Synapse validation smoke harness template.
- Added `server/salemx-call-service/smoke/staging-synapse-smoke.env.example` with placeholder-only required and optional fixture variables.
- Added `server/salemx-call-service/scripts/staging_synapse_smoke.sh`.
- The harness reads environment variables from the operator shell or an optional local env file and never prints env values.
- The harness reports missing required variable names only, then exits without calling staging if required fixtures are unavailable.
- The harness runs readiness, positive token request, invalid bearer, and optional negative room/device cases when fixtures are present.
- Negative fixtures can be omitted; missing optional cases are reported as skipped rather than failing the whole smoke.
- Output is restricted to HTTP status, errcode, readiness booleans, token response shape booleans, and pass/fail/skip.
- The harness avoids echoing request JSON and self-checks its redacted report for known fixture values and token-shaped output before printing.
- Added gitignore coverage for operator-local backend smoke env files while preserving committed `.env.example` templates.
- Updated backend README and private dogfood docs to reference the harness and reiterate that real env files with credentials must not be committed.
- No real staging smoke was run in this prep phase.
- Confirmed no iOS app behavior, Element Call route, CallKit, push, video, or global production direct-call activation changed.
- Recommended next phase: `2.24J — staging Synapse validation smoke execution` once operator-local fixtures are available.

## 2026-05-20 — 2.24K Staging Call Service Deployment Preparation

- Added staging deployment scaffolding for the SalemX call service without adding real credentials or running staging smoke.
- Added `server/salemx-call-service/deploy/staging.env.example` with placeholder-only staging service env values.
- Added gitignore coverage for operator-local `server/salemx-call-service/deploy/*.env` and `server/salemx-call-service/deploy/*.local` files.
- Added `server/salemx-call-service/scripts/run_staging_call_service_local.sh` to validate staging guardrails and start the call service from an operator-local env file.
- The run helper checks staging mode, fake mode disabled, `wss://` LiveKit URL, Redis allocation/rate-limit store config, storage-key secret presence, TTL bounds, and rate-limit config, while printing only variable names for missing/invalid values.
- Added `server/salemx-call-service/scripts/check_staging_readiness.sh` to query readiness and print only redacted readiness fields.
- Documented the operator workflow: create ignored local env files, start Redis or use managed Redis, start the call service, check readiness, fill the staging Synapse smoke env, then run the redacted Synapse smoke harness.
- Documented that only redacted helper output may be shared and real env files/logs must not be pasted.
- Confirmed this scaffold does not include real secrets, raw room IDs, raw user IDs, raw device IDs, or real staging URLs.
- Confirmed no iOS app behavior, Element Call route, CallKit, push, video, or global production direct-call activation changed.
- Staging dogfood remains blocked until staging readiness, Synapse validation smoke, and LiveKit token join smoke pass.
- Recommended next phase: `2.24J — staging Synapse validation smoke execution` when operator-local env values are available.

## 2026-05-23 — 2.30E Call-Service Native Audio Eligibility Endpoint Skeleton

- Added a backend-first native audio eligibility policy boundary to `salemx-call-service`.
- Added a disabled-by-default eligibility policy and an explicit static allowlist skeleton. Static allowlist mode requires both caller and peer accounts when enabled by local deployment config.
- Added `POST /_matrix/client/unstable/kz.salemx.direct_call/eligibility`.
- The endpoint validates Matrix bearer auth, optional device binding, and encrypted direct 1:1 room structure before returning redacted eligibility.
- Eligibility responses are limited to `state`, `reason`, and enum/boolean fields for account, peer, room, trust, service, capability, and client support.
- Added redacted readiness booleans: `nativeAudioEligibilityConfigured` and `nativeAudioEligibilityAllowlistConfigured`.
- Reused the eligibility policy in the LiveKit token endpoint before rate limiting, allocation, LiveKit room pre-create, or participant token issuance.
- Eligibility rejection now fails closed without allocation, LiveKit room pre-create, or token issuance.
- Local fake and existing backend proof paths use an explicit always-eligible test/fake policy; staging/internal pilot remains explicit and fail-closed by default.
- Updated backend tests for default fail-closed eligibility, caller/peer allowlist outcomes, valid eligible outcome, invalid room outcome, redacted endpoint response, readiness redaction, and token endpoint enforcement order.
- Updated server and dogfood docs. This does not wire iOS non-engineering activation, does not change Element Call, and does not add CallKit, push, video, or global activation.
- Recommended next phase: `2.30F — native audio eligibility endpoint runtime/no-activation proof`.

## 2026-05-23 — 2.30F Eligibility Endpoint Local Route Smoke

- Ran a local in-memory FastAPI/ASGI route smoke for the native audio eligibility endpoint and token endpoint enforcement.
- Readiness returned `ready=true`, `reason=ok`, and included the redacted native audio eligibility readiness booleans.
- Default fail-closed `/eligibility` returned `state=unavailable`, `reason=capabilityMissing`, and `capability_present=false`.
- Default token endpoint enforcement returned `403` with `M_DIRECT_CALL_NOT_ELIGIBLE`; no allocation, LiveKit room pre-create, or participant token issuance occurred.
- Explicit allowlisted local fixture returned `/eligibility` `state=eligible`, `reason=null`; the token path proceeded with allocation, one LiveKit room pre-create, and token issuance, with token output redacted.
- Negative route cases passed for caller not allowlisted, peer not allowlisted, invalid room, malformed request, and unsupported intent.
- Smoke output stayed redacted: no raw tokens, JWTs, secrets, room IDs, user IDs, peer IDs, device IDs, Redis credential URLs, or LiveKit room names were printed.
- Ran backend tests with FastAPI route tests enabled, compileall, `git diff --check`, docs secret scan, and the direct-call forbidden scan.
- No app code or backend code changed during the smoke. This does not wire iOS non-engineering activation, does not change Element Call, and does not add CallKit, push, video, or global activation.
- Recommended next phase: `2.30G — native audio eligibility endpoint staging proof plan`.

## 2026-05-23 — 2.30H iOS Native Audio Eligibility Provider Skeleton

- Added an iOS request DTO for the backend native-audio `/eligibility` endpoint.
- Kept DTO descriptions and debug output redacted for room, peer, and device identifiers.
- Extended the redacted eligibility response payload to decode optional `capability_present` / `capabilityPresent`.
- Added an HTTP eligibility provider that uses the existing Matrix bearer access-token provider and redacted direct-call HTTP transport.
- Mapped missing config/auth/transport, malformed payloads, unknown enums, unsupported intents, and non-success HTTP statuses to fail-closed or user-safe unavailable states.
- Kept the default eligibility provider disabled/fail-closed.
- Added tests for request encoding, redaction, eligible and unavailable responses, `capability_present`, missing access token, HTTP/network failure mapping, malformed payloads, unsupported intent, `directOneToOneCallsEnabled`, and existing private dogfood gates.
- This skeleton is not wired into non-engineering activation; controlled engineering dogfood remains on `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` under DEBUG/integration.
- Confirmed no Element Call route, CallKit, push, video, or global production activation changes are part of this phase.
- Recommended next phase: `2.30I — iOS eligibility provider fail-closed runtime proof`.

## 2026-05-23 — 2.30I iOS Eligibility Provider Fail-Closed Runtime Proof

- Ran the runtime no-activation proof after the iOS native audio eligibility provider skeleton.
- Confirmed staging call-service readiness returned `ready=true`, `reason=ok`, and Redis/storage readiness booleans true.
- Launched A/B with product UI and production start gates enabled, but without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Confirmed the attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`.
- Confirmed the no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
- Confirmed the eligibility provider skeleton remains unwired for non-engineering activation; app-side provider usage is limited to provider/types and tests.
- Confirmed `directOneToOneCallsEnabled` remains separate from native audio activation and does not enable the native eligibility path.
- Relaunched with the explicit private dogfood gate, verified A/B trust ready, and confirmed A/B activation enabled with dependencies ready and endpoint accepted.
- Ran a runner-assisted A -> B happy path on staging: B reached `incomingRinging`, B accepted, and A/B reached `activeAudio` with media failure `none`.
- Hangup returned A/B to `idle` with no active session, cleanup/disconnect attempted, and media failure `none`.
- The legacy fake/dry-run gate remained unset, Element Call route remained untouched, no redaction issue was observed, and no code changes were needed.
- Recommended next phase: `2.30J — server-backed eligibility integration boundary design`.

## 2026-05-23 — 2.31B Side-Effect-Safe Eligibility Status Cache Skeleton

- Added a disabled-by-default DEBUG/integration gate, `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1`, for eligibility status display/preflight only.
- Added a room-flow scoped in-memory eligibility status cache with short positive and negative TTLs, redacted cache-key descriptions, manual refresh bypass, and cache clearing on room-flow setup.
- Merged backend eligibility into private native audio room-card status only when the base card is already unavailable.
- Kept backend `eligible` status insufficient to enable native audio; product UI/start gates still do not activate without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Kept local room/trust failures authoritative over backend eligibility.
- Kept the private dogfood activation path unchanged; status eligibility does not block or alter a card that is already enabled by private dogfood activation.
- Added token-backend-rejection cache invalidation for the status path when wired.
- Updated room-card status refresh so manual Refresh/Retry bypasses the eligibility cache while automatic status refreshes can reuse it.
- Added tests for the new status gate, no-activation behavior, safe copy mapping, local-failure precedence, cache reuse/manual bypass, private dogfood compatibility, redacted cache keys, and cache invalidation/clearing.
- This does not enable non-engineering internal pilot activation, does not change Element Call, and does not add CallKit, push, video, or global activation.
- Recommended next phase: `2.31C — eligibility status cache no-activation runtime proof`.

## 2026-05-24 — 2.31C Eligibility Status Cache No-Activation Runtime Proof

- Ran the runtime proof for the side-effect-safe eligibility status cache.
- Confirmed call-service readiness returned `ready=true`, `reason=ok`, Redis allocation/rate-limit connectivity, storage key configured, LiveKit room provisioning configured, and native audio eligibility plus allowlist configured.
- Confirmed `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1` with product UI enabled, but without the private dogfood gate, stayed blocked with `appRolloutDisabled`.
- Confirmed product UI, production start, and eligibility status gates together still do not activate native audio without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Confirmed the no-private-dogfood runs had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session.
- Diagnosed a temporary happy-path blocker as Redis rate-limit store unavailability: the token endpoint failed closed with `M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE` / `503` until Redis connectivity was restored.
- After Redis recovery, relaunched with product UI, private dogfood, production start, eligibility status, and staging token base URL gates.
- Verified A/B trust ready, activation enabled, A outgoing ringing, B incoming ringing, B accept, and A/B `activeAudio` with media failure `none`.
- Verified media connect and LiveKit client connect were attempted on both sides.
- Hangup returned A/B to `idle` with no active session, cleanup/disconnect attempted, and media failure `none`.
- The legacy fake/dry-run gate remained unset, Element Call route remained untouched, no redaction issue was observed, and no code changes were needed.
- Recommended next phase: `2.31D — eligibility status cache controlled engineering soak`.

## 2026-05-25 — 2.36F Server-Backed Internal Pilot Activation Provider

- Added a native-audio-specific internal pilot rollout abstraction that is disabled by default.
- Added a DEBUG/integration-only environment rollout gate, `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED=1`, for future proofing and tests.
- Added a concrete server-backed internal pilot activation provider that can return `activationAllowed` only when product UI, internal pilot rollout, capability, backend eligibility, encrypted direct 1:1 room eligibility, trusted peer readiness, dependency readiness, and idle session state all pass.
- Kept the existing status-only provider status/copy-only; it still never returns `activationAllowed`.
- Kept engineering private dogfood separate under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`; the internal pilot rollout source does not enable private dogfood or production start.
- Added tests for default-off rollout, DEBUG/integration rollout gating, fail-closed single-gate behavior, all-gates unit activation, local room/trust/dependency/session override behavior, safe reason mapping, redaction, and `directOneToOneCallsEnabled` separation.
- This does not enable non-engineering internal dogfood, does not change Element Call, and does not add CallKit, push, missed calls, video, or global activation.
- Recommended next phase: `2.36G — internal pilot activation provider no-activation proof`.

## 2026-05-25 — 2.36G Internal Pilot Activation Provider No-Activation Runtime Proof

- Ran the runtime/no-activation proof after the server-backed internal pilot activation provider.
- Confirmed call-service readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, and storage key configured.
- Launched A/B with product UI and eligibility status enabled, but without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- With the encrypted direct 1:1 room open, activation stayed blocked with `appRolloutDisabled`.
- Confirmed the no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, no active session, and media failure `none`.
- Relaunched with product UI, eligibility status, and production start enabled while still leaving private dogfood unset.
- Confirmed Start stayed blocked with `appRolloutDisabled`, with no token/media/LiveKit path and no active session.
- Confirmed the internal pilot rollout source remained default-off at runtime; backend eligibility/status did not enable Start or Accept without a future rollout implementation and proof.
- `directOneToOneCallsEnabled` was not toggled at runtime because changing Element Call settings is out of scope; the committed activation-provider tests continue to cover that separation.
- Restored the explicit private dogfood gate with product UI, eligibility status, production start, and staging token base URL gates.
- Verified A/B trust ready and activation enabled with dependencies ready, room eligible, endpoint accepted, peer trust ready, and key wrapper available.
- A preliminary start attempt timed out before accept because the generic runner wait helper was used; the timeout path cleaned up safely with A `outgoingTimeout`, B `incomingTimeout`, no active session, cleanup/disconnect attempted, and media failure `none`.
- Reran the happy path with direct B accept: A -> B reached `productionSessionState=activeAudio`, media connect and LiveKit client connect were attempted, and media failure stayed `none`.
- Hangup returned A/B to `productionSessionState=idle` with no active session, cleanup/disconnect attempted, and media failure `none`.
- The legacy fake/dry-run gate remained unset, Element Call route stayed untouched, no redaction issue was observed, and no code changes were needed.
- Recommended next phase: `2.36H — internal pilot activation rollout wiring readiness review`.

## 2026-05-25 — 2.36I Internal Pilot Activation Dry-Run Status Wiring

- Added a DEBUG/integration-only dry-run status gate, `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ACTIVATION_DRY_RUN_ENABLED=1`.
- Wired the server-backed internal pilot activation provider into the private native audio room-card provider boundary as redacted status only.
- The dry-run combines product UI, internal pilot rollout, backend eligibility, encrypted direct 1:1 room eligibility, peer trust readiness, dependency readiness, and active-session state.
- Exposed only enum/boolean output: `internalPilotActivationDryRunEnabled`, `internalPilotActivationDecision`, `internalPilotActivationReason`, product UI, internal rollout, capability presence, room eligibility, peer trust, dependency, and active-session booleans.
- Kept Start/Accept availability unchanged. A dry-run `activationAllowed` result is report-only and does not enable native audio without the existing private dogfood path.
- Preserved private engineering dogfood separation under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`; product UI, eligibility status, backend eligible, production start, and `directOneToOneCallsEnabled` remain insufficient by themselves.
- Added tests for gate-off output, rollout-off dry-run reporting, unit `activationAllowed` dry-run reporting without enabling Start, safe redacted status descriptions, side-effect boundaries, and Element Call separation.
- This does not enable non-engineering internal dogfood, does not change Element Call, and does not add CallKit, push, missed calls, video, or global activation.
- Recommended next phase: `2.36J — internal pilot activation dry-run no-activation runtime proof`.

## 2026-05-25 — 2.36J Internal Pilot Activation Dry-Run No-Activation Runtime Proof

- Ran the runtime/no-activation proof after internal pilot activation dry-run status wiring.
- Confirmed staging readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
- Launched A/B with product UI, eligibility status, and the internal pilot activation dry-run gate enabled, while leaving private dogfood unset.
- Confirmed activation remained blocked with safe reasons and no active session.
- Confirmed the no-private-dogfood runs had no Matrix send, no token request, no media connect, no LiveKit client connect, and media failure `none`.
- Relaunched with product UI, eligibility status, production start, and dry-run gates enabled while still leaving private dogfood unset.
- Confirmed production start remained blocked without private dogfood; no token/media/LiveKit path was attempted and no active session was created.
- Restored private dogfood with product UI, eligibility status, production start, dry-run, and staging token base URL gates enabled.
- Verified A/B trust ready, activation enabled, dependencies ready, room eligible, endpoint accepted, peer trust ready, and key wrapper available.
- A first runner sequence used the generic diagnostic `wait-status` helper against the production path and timed out before accept; timeout cleanup remained safe with A/B idle, no active session, cleanup/disconnect attempted, and media failure `none`.
- Reran the happy path with production-status polling: A -> B reached `incomingRinging`, B accepted, A/B reached `activeAudio`, media and LiveKit client connect were attempted, and media failure stayed `none`.
- Hangup returned A/B to `idle` with no active session, cleanup/disconnect attempted, and media failure `none`.
- Runner-visible output stayed redacted and did not include raw tokens, JWTs, secrets, raw room/user/device IDs, LiveKit room names, Redis credentials, Matrix event bodies, or full request/response bodies.
- Current runner diagnostics do not directly export the new internal-pilot dry-run enum fields from the room-card status contract. The no-activation runtime safety proof passed, but direct dry-run enum observability should be added before relying on runner output as operator-facing dry-run telemetry.
- No code changed during the runtime proof, and Element Call route stayed untouched.
- Recommended next phase: `2.36K — internal pilot activation dry-run runner observability`.

## 2026-05-25 — 2.36K Internal Pilot Activation Dry-Run Runner Observability

- Added the internal pilot activation dry-run status to the redacted native direct-call `production-status` diagnostic payload.
- The payload now exposes `internalPilotActivationDryRunEnabled`, `internalPilotActivationDecision`, `internalPilotActivationReason`, `internalPilotRolloutEnabled`, `internalPilotEligibilityReady`, `internalPilotRoomReady`, `internalPilotTrustReady`, and `internalPilotDependenciesReady`.
- Updated the two-client diagnostic runner to forward `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ACTIVATION_DRY_RUN_ENABLED=1` and print those fields as simple `key=value` output.
- Kept the runner-visible decision enum safe and status-only: `disabled`, `unavailable`, `eligibleForStatusOnly`, `activationAllowed`, or `unknown`.
- Preserved activation behavior. Dry-run `activationAllowed` remains report-only, Start/Accept remain controlled by the private engineering dogfood path, and non-engineering internal dogfood remains blocked.
- Added tests for the new redacted production-status fields and the activationAllowed dry-run side-effect boundary.
- Recommended next phase: `2.36L — internal pilot activation dry-run runner observability proof`.

## 2026-05-25 — 2.36L Internal Pilot Dry-Run Observability Runtime Proof

- Ran the runtime proof for runner-visible internal pilot activation dry-run fields.
- Confirmed staging readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured.
- Confirmed A/B trust ready with `ownSessionVerified=true`, `crossSigningReady=true`, `peerTrustReady=true`, and `peerTrustReadiness=peerTrustReady`.
- Launched A/B with product UI, eligibility status, and internal pilot dry-run enabled while leaving private dogfood unset.
- Confirmed runner `production-status` exposed `internalPilotActivationDryRunEnabled=true`, `internalPilotActivationDecision=disabled`, and `internalPilotActivationReason=rolloutDisabled`.
- Confirmed the no-private-dogfood run had no active session, no Matrix send, no media connect, no LiveKit client connect, and media failure `none`.
- Relaunched with production start added and private dogfood still unset; Start remained blocked and no token/media/LiveKit path was attempted.
- Restored private dogfood and confirmed A/B attached to the encrypted direct 1:1 room with listeners started.
- Ran A -> B using production-status polling: B reached `incomingRinging`, B accepted, A/B reached `activeAudio`, media connect and LiveKit client connect were attempted, and media failure stayed `none`.
- Hangup returned A/B to `idle` with no active session, cleanup/disconnect attempted, and terminal reason `hangup`.
- Runner output stayed redacted, Element Call route stayed untouched, no runtime regression was found, and no app/backend code changed.
- Recommended next phase: `2.36M — internal pilot activation rollout readiness review`.

## 2026-05-25 — 2.36N Engineering-Only Internal Pilot Activation Proof Wiring

- Wired the server-backed internal pilot activation provider into private native audio Start/Accept availability for an engineering-only runtime proof path.
- Kept the wiring behind explicit DEBUG/integration proof gates: product UI, eligibility status, internal pilot activation dry-run, internal pilot rollout, production start, and staging token base URL. The main proof path leaves `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset.
- Added the runtime bridge that can convert an internal pilot dry-run `activationAllowed` decision into an enabled production trigger only after backend eligibility, encrypted direct 1:1 room eligibility, trust readiness, dependency readiness, and idle-session checks pass.
- Updated room-card status so an internal pilot `activationAllowed` decision can make the private native audio card show Start for the engineering proof path, while backend ineligible or local room/trust failures stay unavailable with safe copy.
- Preserved private engineering dogfood separation: `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` still works independently and does not depend on the internal pilot rollout gate.
- Preserved fail-closed defaults: product UI alone, eligibility status alone, internal rollout alone, backend eligible alone, malformed/missing eligibility, and `directOneToOneCallsEnabled` do not activate native audio.
- Added tests proving Start and Accept can proceed without private dogfood only when all internal pilot proof gates pass, backend ineligible blocks, rendering/status refresh has no Matrix/token/media/LiveKit side effects, and Element Call route remains untouched.
- Validation run so far: `RoomFlowCoordinatorTests` passed 104/104; `DirectCallInternalPilotEligibilityTests` plus `NativeDirectCallInternalControlPanelTests` passed 70/70.
- Non-engineering internal dogfood, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.36O — engineering-only internal pilot activation runtime proof`.

## 2026-05-26 — 2.36O Engineering-Only Internal Pilot Activation Runtime Proof

- Recorded the engineering-only server-backed internal pilot activation proof after the HTTP eligibility provider wiring fix.
- Commit `5fc30fe6a` wires the HTTP native audio internal pilot eligibility provider through `AppCoordinator`, `UserSessionFlowCoordinator`, `ChatsTabFlowCoordinator`, and `RoomFlowCoordinator`.
- Default and Release behavior remain fail-closed. The HTTP provider is selected only under explicit DEBUG/integration proof gates.
- Private engineering dogfood remains separate and unchanged; the main internal-pilot proof kept `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset.
- With internal rollout enabled and backend allowlisted A/B, runner status reported internal-pilot `activationAllowed`.
- A Start -> B Accept reached `activeAudio`; hangup returned A/B to idle with no active session and media failure `none`.
- Element Call route stayed untouched. No CallKit, push, video, global production activation, broad internal rollout, or non-engineering internal dogfood was enabled.
- Runtime output stayed redacted and did not print raw identifiers, tokens, JWTs, secrets, LiveKit room names, Matrix event bodies, Redis credentials, or full request/response bodies.
- Validation for the code commit passed: SwiftFormat, SwiftLint, targeted tests 176/176, Release build with existing warnings only, `git diff --check`, and changed-line forbidden scan.
- Caveat at the time: legacy `production-trigger-dry-run` still reported the older `appRolloutDisabled` path while `production-start-outgoing` used the internal-pilot activation bridge and passed. This was resolved in 2.36P.
- Recommended next phase: `2.36P — internal pilot trigger dry-run observability alignment`.

## 2026-05-28 — 2.39M Redacted Token/LiveKit Failure Observability

- Added redacted token/backend and LiveKit setup diagnostics for the failure class seen during non-engineering pilot window 2.
- Backend token diagnostics now classify token request seen, HTTP status, safe errcode/reason, eligibility allowed, rate limit, allocation attempted, LiveKit room pre-create attempted, and token issued without exposing request bodies, raw identifiers, tokens, JWTs, secrets, or LiveKit room names.
- iOS media diagnostics and runner `production-status` now expose safe token and LiveKit fields: `tokenStatus`, `tokenErrcode`, `tokenReason`, `tokenIssued`, `liveKitRoomPrecreateAttempted`, `productionLiveKitFailureReason`, and related booleans.
- Fixed runner redaction after simulator identifiers leaked from launch/relaunch output. The runner now redacts exact A/B simulator identifiers, generic UUID-shaped simulator identifiers, and `udid=<value>` fields before printing.
- Runtime observability proof passed: a positive A -> B call reached `activeAudio`, then hangup returned A/B idle/no active session with token `200` / `issued`, token issued true, LiveKit room pre-create attempted, LiveKit connect attempted, LiveKit failure `none`, and media failure `none`.
- Controlled negative token proof used a temporary current-code local service and returned only safe diagnostics: `tokenStatus=401`, `tokenErrcode=M_UNKNOWN_TOKEN`, `tokenReason=authRejected`, and `tokenIssued=false`.
- Element Call route stayed untouched, no CallKit/push/video/global activation was added, and non-engineering pilot execution remained paused.

## 2026-05-28 — 2.39N Window 2 Failure Retry Diagnostics

- Reran only the minimal failed window-2 call paths using the new redacted token/LiveKit observability. This was not a new non-engineering pilot window and did not approve further execution.
- Preflight passed with backend readiness `ready=true`, `reason=ok`, Redis/storage/LiveKit/eligibility/allowlist configured, A/B trust ready, approved encrypted 1:1 DM open, no active session, and internal pilot activation `activationAllowed`.
- A -> B retry passed: Start/Accept reached `activeAudio`; token diagnostics reported `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, and `liveKitRoomPrecreateAttempted=true`; LiveKit connect was attempted with failure reason `none`; media failure stayed `none`; hangup returned A/B idle/no active session.
- B -> A retry passed with the same safe token/LiveKit success classification and final A/B idle/no active session.
- The original window 2 failure did not reproduce: no `tokenBackendRejected`, no `liveKitNetworkFailed`, no split state, no stale active session, and no redaction issue were observed.
- Root cause remains unproven. With the clean retry and new diagnostics, the best classification is transient or environment-sensitive unless the failure reappears with safe fields.
- No app/backend code changed during 2.39N. Recommendation: proceed only to a separate approval review for exactly one supervised window 2 recovery attempt; otherwise non-engineering pilot execution remains paused.

## 2026-05-28 — 2.39P Supervised Non-Engineering Recovery Pilot Window

- Ran the single supervised recovery window approved by 2.39O. This did not approve additional windows, participant/device expansion, broad internal rollout, production/public rollout, or unsupervised dogfood.
- Session time recorded as 2026-05-28 16:51:34 +0500.
- Participant/device labels remained Participant A / Device A1 and Participant B / Device B1 only.
- Preflight passed: backend readiness `ready=true`, `reason=ok`, Redis/storage/LiveKit/eligibility/allowlist configured, participant opt-in still valid by the existing 2.39G checklist, A/B trust ready, approved encrypted 1:1 DM open, no stale active session, Element Call fallback visible, `activationSource=internalPilot`, and `internalPilotActivationDecision=activationAllowed`.
- Required app gates were present; `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` and `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` remained unset.
- Recovery matrix was intentionally shorter than 2.39K: A -> B happy path, B -> A reverse path, one repeated A -> B call, final idle/no active session, and Element Call fallback check.
- A -> B passed: reached `activeAudio`, then hangup returned A/B idle/no active session.
- B -> A passed: reached `activeAudio`, then hangup returned A/B idle/no active session.
- One repeated A -> B call passed: reached `activeAudio`, then hangup returned A/B idle/no active session.
- Every call row reported safe token/LiveKit fields: `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, `liveKitRoomPrecreateAttempted=true`, LiveKit connect attempted, `productionLiveKitFailureReason=none`, and `productionMediaFailureReason=none`.
- Cleanup/disconnect were attempted after each hangup, and final A/B state was idle/no active session.
- Stop criteria hit: no. No `tokenBackendRejected`, no `liveKitNetworkFailed`, no split-brain, no stale active session, no participant confusion, and no redaction issue.
- Rollback was not used. Element Call fallback controls were visually confirmed visible and unchanged, and the private native audio card remained separate.
- No app/backend code changed during the recovery window.
- Decision: continue to post-recovery review; no additional non-engineering pilot window is approved by this result.

## 2026-05-28 — 2.39R Supervised Non-Engineering Pilot Window 3

- Ran exactly one additional supervised non-engineering internal pilot window after the 2.39Q approval. This did not approve additional windows, participant/device expansion, broad internal rollout, production/public rollout, or unsupervised dogfood.
- Session time recorded as 2026-05-28 17:31:30 +0500.
- Participant/device labels remained Participant A / Device A1 and Participant B / Device B1 only.
- Scope stayed unchanged: staging call-service and staging LiveKit only, foreground/open encrypted direct 1:1 DM only, private native audio card only, verified/trusted peers only, one active native 1:1 call at a time, Element Call fallback visible/unchanged, and redacted reporting only.
- Preflight passed: backend readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, eligibility/allowlist configured, participant opt-in still valid by the existing 2.39G checklist, A/B trust ready, approved encrypted 1:1 DM open, no stale active session, Element Call fallback visible, `activationSource=internalPilot`, and `internalPilotActivationDecision=activationAllowed`.
- Required app gates were present; `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` and `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` remained unset.
- A -> B happy path passed: Start/Accept reached `activeAudio`; token diagnostics reported `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, `tokenIssued=true`, and `liveKitRoomPrecreateAttempted=true`; LiveKit connect was attempted with `productionLiveKitFailureReason=none`; `productionMediaFailureReason=none`; hangup returned A/B idle/no active session after the bounded post-hangup status check.
- B -> A reverse path passed with the same safe token/LiveKit success classification; hangup returned A/B idle/no active session.
- One repeated A -> B call passed with the same safe token/LiveKit success classification; hangup returned A/B idle/no active session.
- Outgoing cancel passed: caller emitted `cancel`, A/B returned idle/no active session, terminal reason was `cancelled`, and no token/LiveKit/media failure was observed.
- Timeout passed: A reported `outgoingTimeout`, B reported `incomingTimeout`, both returned idle/no active session, cleanup/disconnect were attempted, and media failure stayed `none`.
- App-side kill-switch check passed as a safe block after `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED` was unset and A/B relaunched: activation was not allowed, no active session existed, no token request was made, and no media/LiveKit connection was attempted.
- Element Call fallback controls were visually confirmed visible and unchanged; the private native audio card remained separate.
- Stop criteria hit: no. No `tokenBackendRejected`, no `liveKitNetworkFailed`, no split-brain, no stale active session, no participant confusion, and no redaction issue were observed.
- Rollback was not needed beyond the planned app-side kill-switch row. No app/backend code changed during the window.
- Decision: continue to a post-window readiness review; no additional non-engineering pilot window is approved by this result.

## 2026-05-28 — 2.39T Post-Pilot Hardening Plan

- Recorded the 2.39S decision to pause additional non-engineering pilot windows after the clean 2.39R window.
- Confirmed the valid claims: server-backed internal pilot activation works for approved named participants/devices under staging gates; token diagnostics were `tokenStatus=200`, `tokenErrcode=none`, `tokenReason=issued`, and `tokenIssued=true`; LiveKit/media diagnostics were clean; cancel, timeout, hangup, final idle/no active session, app-side kill-switch, and Element Call fallback passed.
- Documented foreground limitation UX requirements: native audio works only while the encrypted direct chat is open; no background incoming, CallKit system incoming screen, or missed-call UX exists yet; Element Call remains fallback.
- Documented in-card state polish requirements for listener unavailable, trust not ready, participant not eligible, service unavailable, timed out, cancelled, safely failed, retry, and dismiss states.
- Locked the mandatory monitoring baseline to redacted readiness, activation, token, LiveKit/media, session, terminal, and cleanup/disconnect fields only.
- Added operational monitoring automation requirements and alert-worthy states: `tokenBackendRejected`, `liveKitNetworkFailed`, split-brain, stale active session, readiness not ready, and `tokenIssued=false` for an otherwise eligible call.
- Added support/rollback requirements covering operator procedure, kill-switch checklist, allowlist removal, app relaunch, idle/no active session verification, incident template, and secret rotation trigger.
- Kept additional non-engineering windows, participant/device expansion, broad internal rollout, production/public rollout, Element Call replacement, CallKit/push implementation, video, global activation, and `directOneToOneCallsEnabled` as a native audio gate blocked.
- Recommended next phase: `2.39U — post-pilot hardening workstream selection`.

## 2026-05-28 — 2.39V Foreground Limitation UX Polish

- Implemented the first post-pilot hardening slice selected by 2.39U: foreground/open-chat limitation UX polish for the private native audio card.
- Added explicit user-facing copy that native audio works only while the encrypted direct chat stays open, with no background incoming calls, no system incoming call screen, no missed-call alerts yet, and Element Call as fallback.
- Polished existing safe card copy for listener/open-room availability, incoming calls, timeout, and safe failure states.
- Added the foreground-only limitation to the card accessibility summary for relevant non-active states.
- Added previews for additional unavailable, listener unavailable, cancelled, and failure states.
- Added tests covering the foreground limitation copy, user-facing redaction against backend/token/LiveKit/request/response/raw-ID wording, and unchanged safe state copy coverage.
- This is UX/copy polish only: no activation gates, Start/Accept availability, Matrix send path, token request path, media/LiveKit setup, private dogfood, internal pilot activation, Element Call route, CallKit, push/background incoming, missed-call UX, video, global activation, broad rollout, or production/public rollout changed.
- Recommended next phase: `2.39W — foreground limitation UX no-activation proof`.

## 2026-05-28 — 2.39W Foreground Limitation UX Runtime Proof

- Ran the foreground/open-chat UX runtime proof for the 2.39V private native audio card polish.
- A/B were launched with product UI, eligibility status, internal pilot dry-run, internal pilot rollout, production start, and staging token base URL gates set; `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` and `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` remained unset.
- The private native audio card visibly showed the foreground/open-chat limitation copy on A/B: native audio works only while the encrypted direct chat stays open, there is no background incoming call behavior or system incoming call screen yet, missed-call alerts are not present yet, and Element Call remains fallback.
- Redaction check passed: the visible card copy did not expose backend, token, LiveKit, raw identifier, LiveKit room name, request/response, secret, JWT, or simulator identifier details.
- Element Call phone/video fallback controls were visually confirmed visible and unchanged; the private native audio card remained separate.
- Rendering/status refresh before any call action had no Matrix send, no token request, no media connect, no LiveKit connect, and no active session on A/B.
- Optional internal-pilot A -> B smoke passed: Start/Accept reached `activeAudio`; hangup/cleanup returned A/B to `idle` with no active session.
- Smoke diagnostics were clean: token `200` / `issued`, token issued true, LiveKit room pre-create and connect attempted, LiveKit failure `none`, and media failure `none`.
- No app/backend code changed. No regression was observed. Additional non-engineering windows, participant/device expansion, broad internal rollout, production/public rollout, unsupervised dogfood, Element Call replacement, CallKit/push/background incoming, missed-call UX, video, session restoration, and global activation remain blocked.
- Recommended next phase: `2.39X — operational monitoring automation design`.

## 2026-05-28 — 2.40B Native Audio Incoming-Call Lifecycle Architecture Contract

- Documented the architecture contract for moving native direct audio beyond foreground/open-chat-only behavior.
- The current limitation remains unchanged: native audio is available only in foreground/open encrypted direct 1:1 rooms, with no CallKit, no PushKit/APNs background incoming, no missed-call UX, no video, no session restoration, and Element Call as fallback.
- Defined the target lifecycle: receive a native direct-call invite signal, classify safely, validate encrypted direct 1:1 room state, validate trusted peer/device state, validate rollout/eligibility/dependency/idle-session gates, report incoming to CallKit only after that safe boundary, accept through the native direct-call engine, request the token only on accept, connect LiveKit only after token and E2EE readiness, and fail closed on validation/media/terminal failures.
- Defined the native CallKit boundary as a future adapter/protocol separate from Element Call routing. It maps CallKit UUIDs to validated native sessions, handles answer/end/mute/audio session callbacks, and cannot bypass trust, eligibility, rollout, or token endpoint enforcement.
- Defined the PushKit/APNs boundary: separate native audio pusher registration, minimal opaque payloads, local fetch/decrypt/classification when needed, token endpoint final authority, and no raw room/user/peer/device IDs, tokens, JWTs, media keys, LiveKit room names, Matrix event bodies, request/response bodies, or credentialed URLs.
- Recorded NSE/encrypted-payload handling requirements: fail closed if decrypt/classify is unavailable or ambiguous, and never log raw event bodies or decrypted payloads.
- Recorded signing blockers: Push Notifications capability, APNs `aps-environment`, VoIP background mode, provisioning profiles, Apple Developer account capability, physical-device proof, and push gateway configuration must be proven before PushKit/APNs work. Simulator-only proof is insufficient.
- Recorded backend constraints: Matrix signalling remains the source of call semantics; backend services must not centralize trust decisions; call-service may provide opaque handles, eligibility, readiness, token final enforcement, and redacted observability only.
- Added a fail-closed matrix covering malformed/expired push, decrypt/classify failure, invalid room shape, trust not ready, ineligible participants, disabled rollout, dependency failure, existing active session, locked/killed app without safe session state, token rejection, LiveKit failure, CallKit report failure, ambiguous terminal delivery, and unsafe Element Call conflict.
- Recommended phased implementation: 2.40C signing/entitlement readiness audit, 2.40D disabled native incoming service and CallKit adapter protocols/mocks, 2.40E push/NSE classification dry-run, 2.40F device-only synthetic CallKit incoming proof, 2.40G PushKit/APNs registration dry-run, 2.40H supervised device E2E incoming proof, then missed/decline/cancel/background/killed-app tests.
- No app or backend code changed. No CallKit, PushKit, APNs, missed-call UX, background incoming, video, Element Call replacement, rollout expansion, or global activation was implemented.
- Recommended next phase: `2.40C — native audio signing and entitlement readiness audit`.

## 2026-05-28 — 2.40E Apple Developer Signing Remediation Checklist

- Documented the remediation checklist required before native audio CallKit/PushKit/APNs implementation can start.
- The 2.40D audit found that a generic `iphoneos` build completed, but signing readiness is blocked: local signing identity inspection reported no valid local identities, signature verification reported an untrusted chain, embedded profiles expire on 2026-06-01, and `aps-environment` is missing from main app/NSE/ShareExtension profiles.
- Confirmed existing positives: the main app has `UIBackgroundModes` with `audio`, `fetch`, `processing`, and `voip`; App Groups and Keychain Sharing are configured for the app, NSE, and ShareExtension.
- Confirmed physical-device proof did not run because the physical iPhone was visible but offline. Simulator-only proof remains insufficient for APNs, PushKit token issuance, background wake, or provisioning validation.
- Recorded the required Apple Developer state: paid Apple Developer Program team, valid trusted Apple Development certificate, registered online physical iPhone, and Xcode build/sign/install proof on that device.
- Recorded the required App IDs: main app `kz.salemx.msg`, NSE `kz.salemx.msg.nse`, ShareExtension `kz.salemx.msg.shareextension`, and App Group `group.kz.salemx.msg`.
- Recorded required capabilities and profiles: Push Notifications for the main app producing `aps-environment`, App Groups, Keychain Sharing, background mode with `voip`, durable development profiles for app/NSE/ShareExtension, and NSE filtering entitlement only if a later encrypted NSE-to-CallKit path chooses it.
- Recorded redacted local verification checks for signing identities, embedded profiles, signed entitlements, `aps-environment`, App Group, Keychain Sharing, physical-device install, and `voip` background mode.
- No entitlements, bundle IDs, app code, backend code, Element Call route, CallKit, PushKit, APNs, video, or rollout settings changed.
- Recommended next phase: `2.40F — physical-device signing remediation execution` if the paid team/device/certificate are available, otherwise `2.40F — paid Apple Developer account setup and profile regeneration`.

## 2026-06-08 — 2.40G PushKit / APNs / CallKit Design Plan

- Added `docs/direct-call/CALLKIT_PUSHKIT_APNS_DESIGN.md` after the successful 2.40F physical-device signing proof.
- Recorded the baseline: physical-device signing readiness passed, the main app has development APNs entitlement, app and extensions use `group.kz.salemx.msg.dev`, and runtime CallKit/PushKit/APNs implementation has not started.
- Documented Apple compliance assumptions: PushKit VoIP pushes are only for real incoming calls, regular chat/message notifications must not use PushKit, and valid incoming calls must be reported to CallKit quickly.
- Proposed future incoming and outgoing native direct-audio flows while preserving token endpoint final authority and keeping Element Call separate.
- Documented the token/device model, server requirements, future client components, risk register, redaction contract, fail-closed matrix, and phased implementation plan.
- Kept this phase design-only: no app/backend runtime code, bundle IDs, App Group IDs, signing/provisioning settings, LiveKit, MatrixRTC, Element Call route, native audio gating, CallKit, PushKit, APNs, video, broad rollout, or production/public rollout changed.
- Recommended next phase: `2.40H — native incoming lifecycle contracts and mocks`.

## 2026-06-08 — 2.40H Native Incoming Lifecycle Contracts And Mocks

- Added a disabled native incoming-call contract surface for future CallKit / PushKit / APNs work.
- Added safe local incoming call handle and identity models with redacted descriptions.
- Added lifecycle state and fail-closed reason models, validation context, redacted diagnostics, and protocol boundaries for state storage, call reporting, incoming push registry, timeout scheduling, and diagnostics recording.
- Added a disabled lifecycle service whose default behavior is no-op/fail-closed and whose test-enabled path only talks to local test doubles.
- Added unit coverage for default fail-closed behavior, malformed/stale/duplicate handles, invalid local validation context, server-issued media credential rejection diagnostics, call reporting redaction, incoming push registry redaction, and Element Call route action name absence in diagnostics.
- Added `docs/direct-call/NATIVE_INCOMING_CONTRACTS.md`.
- No real CallKit, PushKit, APNs, token registration, system incoming UI, background incoming behavior, missed-call UX, media connection, Element Call route change, native audio gate change, bundle ID, App Group, signing/provisioning/project setting, server, video, broad rollout, or production/public rollout changed.
- Recommended next phase: `2.40I — push and call reporting payload contract`.

## 2026-06-08 — 2.40I Push And CallKit Payload Contract

- Added `docs/direct-call/PUSH_CALLKIT_PAYLOAD_CONTRACT.md`.
- Documented the contract-only payload classes for future VoIP incoming native direct-audio invites, optional normal APNs notification separation, server acknowledgement/invalidation payloads, local CallKit display metadata, and terminal/stale call handling.
- Defined the future VoIP incoming payload as minimal and opaque: schema version, opaque local call handle, native direct-audio call kind, timestamps, safe display label reference, and validation hint enum only.
- Documented client validation: reject malformed, unsupported, stale, duplicate, missing-label, unsupported-kind, unavailable-session, dependency, trust, eligibility, active-session, and route-conflict cases before reportability.
- Documented that push payloads are never final authority and cannot request media credentials or connect media on receipt. Server-issued media credential authority remains after user answer.
- Documented server requirements, safe display metadata rules, redacted diagnostics, failure matrix, and test plan.
- Kept this phase docs-only: no app/backend runtime code, CallKit, PushKit, APNs, push credential registration, system incoming UI, background incoming behavior, missed-call UX, media connection, LiveKit, MatrixRTC, Element Call route, native audio gating, bundle ID, App Group, signing/provisioning/project setting, server, video, broad rollout, or production/public rollout changed.
- Recommended next phase: `2.40J — device-only synthetic CallKit proof`.

## 2026-06-08 — 2.40J Device-Only Synthetic CallKit Proof

- Added a disabled synthetic CallKit proof coordinator for future native direct-audio incoming-call work.
- Added safe CallKit display metadata validation that rejects empty, oversized, or raw-looking labels.
- The synthetic proof accepts only safe local incoming-call identity data from the disabled 2.40H contracts.
- Report, answer, end, and mute actions map only into injected disabled local callbacks and redacted diagnostics.
- Added unit coverage for disabled default fail-closed behavior, safe local identity reporting, answer/end/mute callback mapping, unknown-handle fail-closed behavior, local state cleanup, and redacted diagnostics.
- Added `docs/direct-call/SYNTHETIC_CALLKIT_PROOF.md` with device-only manual proof steps.
- Kept this phase disabled and local: no PushKit runtime, APNs runtime, push credential registration, push delivery, server push, media credential request, media connection, LiveKit, MatrixRTC, Element Call route, native audio gating, bundle ID, App Group, signing/provisioning/project setting, server, video, broad rollout, or production/public rollout changed.
- Recommended next phase: `2.40K — PushKit registration dry run planning`.

## 2026-06-08 — 2.40J-B Isolated Physical-Device Synthetic CallKit UI Proof Adapter

- Added an isolated synthetic CallKit UI proof adapter under `ElementX/Sources/Services/Calls/SyntheticCallKitProof/`.
- Kept the CallKit import inside the isolated proof-only file; no CallKit runtime was added to `DirectCallModels.swift`, app coordinators, Element Call, media setup, or feature gating.
- Added a DEBUG-only local harness boundary for a developer-controlled physical-device synthetic incoming-call UI proof.
- The adapter accepts only safe local incoming-call identity/display metadata and maps CallKit report, answer, end, and mute callbacks into disabled local callbacks plus redacted diagnostics.
- Added unit coverage for unsafe display metadata rejection, injected reporter-only reporting, disabled answer/end/mute callbacks, unknown-handle fail-closed behavior, local state cleanup, and redacted diagnostics.
- Added `docs/direct-call/SYNTHETIC_CALLKIT_UI_PROOF.md`.
- Project-file changes are limited to adding the isolated proof Swift file to the app target. No bundle ID, App Group, signing, entitlement, Info.plist, app.yml, production distribution, Element Call, LiveKit, MatrixRTC, native audio gate, push delivery, server fanout, media credential request, media connection, video, broad rollout, or production/public rollout changed.
- Recommended next phase: `2.40K — PushKit registration dry run planning`.

## 2026-06-09 — 2.40J-C Physical Synthetic CallKit UI Proof

Confirmed on a physical iPhone Debug build that the isolated synthetic CallKit proof path can display the system CallKit incoming-call UI. The trigger used the DEBUG-only Objective-C runtime bridge via LLDB runtime lookup. Full runtime logs were intentionally omitted because they contain private Matrix/runtime identifiers. No PushKit/APNs runtime, token registration, server-issued media credential request, LiveKit/MatrixRTC media connection, Matrix event emission, Element Call route change, signing change, bundle change, entitlement change, or project setting change was added by this proof path.

## 2026-06-09 — 2.40K Incoming Call State Machine Routing Proof

- Added a disabled local incoming-call state-machine action surface for synthetic CallKit answer/end/mute callbacks.
- Answer now routes through a synthetic action handler into `answerRequested`, which is the safe local state before any future server-issued media credential authority step.
- End routes through the same local surface and clears the synthetic incoming state.
- Mute remains local and diagnostic-only.
- Added unit coverage for direct synthetic coordinator routing and isolated synthetic CallKit UI adapter callback routing.
- The proof records only redacted lifecycle diagnostics; media credential request and media connection flags remain false.
- No PushKit runtime, APNs runtime, APNs/VoIP value registration, background incoming handling, server-issued media credential request, media connection, Matrix event emission, Element Call route change, LiveKit/MatrixRTC production path change, signing change, bundle change, entitlement change, project setting change, production UI, video, broad rollout, or production/public rollout was added.
- Added `docs/direct-call/INCOMING_CALL_STATE_MACHINE_PROOF.md`.

## 2026-06-09 — 2.40L Foreground Incoming Acceptance Gate

- Added a foreground-only acceptance gate after synthetic/local incoming CallKit answer routing.
- The local incoming state still moves to `answerRequested` on answer.
- The acceptance gate keeps media blocked until a mocked/test-safe foreground authority returns an authorized decision.
- Missing, denied, malformed, expired, and unverifiable authority decisions fail closed.
- An authorized decision moves only to `foregroundCredentialAuthorized`; it does not connect media, request real server-issued media credentials, or emit Matrix call events.
- End clears local incoming/acceptance state, and mute remains local and diagnostic-only.
- Added unit coverage for direct gate behavior and isolated synthetic CallKit UI adapter callback-to-gate behavior.
- No PushKit runtime, APNs runtime, APNs/VoIP value registration, background incoming handling, real server-issued media credential request, media connection, Matrix event emission, Element Call route change, LiveKit/MatrixRTC production path change, signing change, bundle change, entitlement change, project setting change, production UI, video, broad rollout, or production/public rollout was added.
- Added `docs/direct-call/FOREGROUND_INCOMING_ACCEPTANCE_GATE.md`.

## 2026-06-09 - 2.41D Video Path Inspection And Remote Rendering Diagnosis

- Inspected the video path after a two-physical-iPhone smoke showed local video on both devices but no visible remote participant video.
- Classified the standard room video button as the existing Element Call / embedded call route: room UI sends `displayCall(startMode: .video)`, coordinators forward `presentCallScreen(startMode: .video)`, and the user-session coordinator builds an Element Call configuration.
- Confirmed the private native direct-call path remains audio-only: direct-call media protocol exposes audio APIs only, media state has audio phases only, native LiveKit direct-call client subscribes to remote audio only, and native video intent fails closed before media connection.
- Confirmed native direct-call eligibility, activation, capability, and credential-authority surfaces are audio-scoped; non-audio intent is rejected before a native media credential request.
- Documented that the observed self-view-only symptom is most likely in Element Call / MatrixRTC / embedded call remote rendering, call-session matching, publish/subscribe, or renderer attachment, not in the proven native audio path.
- No app/runtime code changed. No PushKit/APNs runtime, background incoming, signing/project change, native direct-call video implementation, Element Call replacement, broad rollout, production/public rollout, or global activation was added.
- Added `docs/direct-call/VIDEO_REMOTE_RENDERING_INSPECTION.md`.
- Recommended next phase: `2.41E - Element Call video remote rendering diagnosis`.

## 2026-06-09 - 2.41E Element Call Video Remote Rendering Diagnosis

- Inspected the Element Call / embedded call video path after the two-physical-iPhone smoke where both devices showed local video but no remote participant video.
- Confirmed the normal room video button flows through `displayCall(startMode: .video)`, `presentCallScreen(startMode: .video)`, `ElementCallConfiguration.roomCall`, `CallScreenViewModel`, `ElementCallWidgetDriver`, and the embedded Element Call web view.
- Confirmed direct room video uses the SDK direct-message video call intent, while direct room audio uses the distinct voice intent.
- Found no app-side audio-only configuration for the Element Call video route: direct-room URL parameters hide app-replaced controls and screensharing, but do not disable video.
- Confirmed the native shell hosts the web view and grants media capture for the embedded call origin; local camera publish, remote video subscription, and remote renderer attachment are Element Call / MatrixRTC responsibilities inside the web view.
- Classified the suspected root cause as Element Call / MatrixRTC session matching, local publish, remote subscribe, renderer attachment, or RTC transport credential/grant behavior.
- No app/runtime code changed. No PushKit/APNs runtime, background incoming, signing/project change, Element Call route replacement, private native direct-call video implementation, broad rollout, production/public rollout, or global activation was added.
- Added `docs/direct-call/ELEMENT_CALL_VIDEO_REMOTE_RENDERING_DIAGNOSIS.md`.
- Recommended next phase: `2.41F - redacted Element Call media diagnostics`.

## 2026-06-09 - 2.41F Redacted Element Call Media Diagnostics

- Added redacted native-shell diagnostics for the existing Element Call / embedded call route.
- The call screen records safe stage booleans/enums for Element Call URL generation, start mode, direct-room chrome, content loaded, media capture permission kind, and widget media state.
- Added a narrow injected web-view diagnostic payload that reports only schema, safe stage, elapsed bucket, video element counts, visible/playing/stream-backed/muted counts, and a derived remote-renderer-candidate boolean.
- Added unit coverage for diagnostic payload schema rejection, count clamping, and redacted description output.
- The diagnostics can identify whether the web view has only a self-view renderer or multiple video renderer candidates, but they do not yet prove MatrixRTC same-session, publish, subscribe, grant, or participant-to-renderer mapping.
- No PushKit/APNs runtime, background incoming, signing/project change, Element Call route replacement, private native direct-call video implementation, broad rollout, production/public rollout, or global activation was added.
- Added `docs/direct-call/ELEMENT_CALL_MEDIA_DIAGNOSTICS.md`.
- Recommended next phase: `2.41G - Element Call MatrixRTC publish subscribe diagnosis`.

## 2026-06-10 - 2.41G-A Repeat-call Audio Stutter And Lifecycle Stabilization

- Investigated repeat-call stutter/hesitation on the existing Embedded Element Call audio route.
- Confirmed the scoped native-shell path remains the Call screen / Element Call widget route with audio start mode; video remote rendering is a separate investigation.
- Added an idempotent embedded web content reset from `CallScreenViewModel` when the call screen stops or begins local termination.
- The reset stops active audio/video element tracks, detaches stream-backed media, clears media sources, and stops the page load before the next call can reuse stale WebContent media state.
- Kept existing widget hangup, Matrix termination request, and Element Call service teardown behavior.
- Added unit coverage for End and stop cleanup, including one-shot reset behavior and existing hangup/termination/teardown behavior.
- Added `docs/direct-call/REPEAT_CALL_AUDIO_STUTTER_INVESTIGATION.md`.
- Physical two-iPhone repeat-call smoke remains required to prove whether the stutter is fixed or only narrowed.
- No PushKit/APNs runtime, background incoming, signing/project change, Element Call route replacement, private native video implementation, credential-authority bypass, broad rollout, production/public rollout, or global activation was added.

## 2026-06-10 - 2.41G-A6 Foreground Call Invite Fast Source Investigation

- Investigated why the foreground current-room fast path can still request incoming/CallKit only after repeated-call delays have already exceeded the target.
- Confirmed the open-room flow already subscribes the room and live timeline before `ElementCallService` observes the foreground room.
- Confirmed the current-room observer is still fed by materialized timeline updates, and physical diagnostics showed this source can receive fresh incoming candidates in the `over10s` bucket.
- Confirmed room-list fallback is not a faster source because it depends on room-summary/latest-event updates.
- Inspected existing notification, Element Call PushKit, and native direct-call SDK timeline listener surfaces. PushKit is out of scope, notification manager is not a foreground Matrix call invite stream, and the native direct-call timeline listener is scoped to SalemX native direct-call custom envelopes.
- Classified the missing piece as a new foreground-only Element Call invite source/contract, likely at SDK timeline-diff, MatrixRTC call-member, or sliding-sync subscription level.
- Kept this phase docs-only. No PushKit/APNs runtime, background incoming, signing/project change, Element Call route replacement, media behavior change, private native video implementation, broad rollout, production/public rollout, or global activation was added.
- Added `docs/direct-call/FOREGROUND_CALL_INVITE_FAST_SOURCE_INVESTIGATION.md`.

## 2026-06-10 - 2.42A Foreground Call Signaling Channel Prototype

- Added an inert foreground call signaling channel contract and client boundary for future server-originated foreground call invites.
- Added safe local invite models, a disabled mockable signaling client, an invite validator, and an invite handler that can request the existing foreground incoming/CallKit reporting abstraction.
- The handler suppresses duplicate, stale, terminal, malformed, unsupported, active-session, and reporting-failure cases with redacted diagnostics.
- Invite receipt does not request media credentials, connect media, emit Matrix events, or bypass the foreground acceptance gate.
- Unit coverage verifies foreground invite reporting, duplicate/stale/terminal/malformed suppression, authority-gate separation after answer, and timeline fallback duplicate suppression.
- Added `docs/direct-call/FOREGROUND_CALL_SIGNALING_CHANNEL.md`.
- No production signaling transport, PushKit/APNs runtime, background incoming, signing/project change, Element Call route replacement, media behavior change, broad rollout, production/public rollout, or global activation was added.

## 2026-06-10 - 2.42B Foreground Signaling Transport Prototype

- Added a mockable foreground signaling transport boundary on top of the 2.42A invite contract.
- Added a disabled/default no-op transport, an in-memory test transport, safe transport event/diagnostic models, and a pipeline that feeds transport invite events into `ForegroundCallInviteHandler`.
- The in-memory transport can deliver a safe invite immediately in tests without waiting for Matrix room-list or timeline materialization.
- The pipeline preserves duplicate, stale, terminal, malformed, active-session, and reporting-failure guards.
- Invite receipt still does not request media credentials, connect media, emit Matrix call events, or bypass the foreground acceptance gate.
- Unit coverage verifies disabled/no-op transport behavior, immediate in-memory delivery, pipeline reporting, unsafe invite suppression, no credential/media side effects, and answer gate separation.
- Added `docs/direct-call/FOREGROUND_SIGNALING_TRANSPORT_PROTOTYPE.md`.
- No production WebSocket/SSE transport, PushKit/APNs runtime, background incoming, signing/project change, Element Call route replacement, media behavior change, broad rollout, production/public rollout, or global activation was added.
