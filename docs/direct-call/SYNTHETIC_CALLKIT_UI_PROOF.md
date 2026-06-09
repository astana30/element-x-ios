# Synthetic CallKit UI Proof

Status: isolated physical-device synthetic CallKit UI proof adapter only. This phase does not add PushKit runtime, APNs runtime, push delivery, server fanout, media credential requests, media connection, Element Call route changes, native audio gate changes, signing changes, project-generation changes beyond proof file inclusion, background incoming behavior, missed-call UX, video, or rollout behavior.

## Scope

2.40J-B adds an isolated CallKit proof adapter for native direct audio. The adapter can report a local synthetic incoming call to the iOS system call UI on a physical iPhone when a developer explicitly invokes the DEBUG-only harness.

The proof accepts only the safe local incoming-call identity and safe display metadata from the 2.40H/2.40J-A contracts. It maps report, answer, end, and mute events into disabled local callbacks and redacted diagnostics.

This is not a real incoming-call path. It does not receive pushes, does not register push values, does not create server invitations, does not request media credentials, and does not connect media.

## Adapter Boundary

The CallKit import is isolated to:

- `ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift`

The adapter exposes:

- safe report events.
- safe answer events.
- safe end events.
- safe mute events.
- safe fail-closed events.

The adapter does not depend on LiveKit, MatrixRTC, Element Call, the direct-call media engine, app coordinators, push registration, APNs delivery, or server clients.

## Synthetic Trigger

The trigger is DEBUG-only and local:

1. Create `NativeIncomingSyntheticCallKitUIProofReporter`.
2. Create `NativeIncomingSyntheticCallKitUIProofAdapter` with disabled local action and diagnostic recorders.
3. Create `NativeIncomingSyntheticCallKitUIProofHarness`.
4. Call `reportSyntheticIncomingCall()` from a developer-only manual hook or debugger-controlled local expression.
5. Confirm the system incoming-call UI appears for the synthetic local call only.

No public product UI is added. No normal production user path can reach this proof surface.

## Manual Physical-Device Proof Steps

1. Use the development-signed physical iPhone setup proven in 2.40F.
2. Confirm the app launches normally and Element Call fallback behavior is unchanged.
3. Confirm PushKit/APNs delivery remains unused.
4. Invoke the DEBUG-only local synthetic harness with a safe local handle and safe display label.
5. Confirm the iOS system incoming-call UI appears.
6. Tap Answer and confirm only the disabled local answer callback is recorded.
7. Toggle mute, if available, and confirm only the disabled mute callback is recorded.
8. End the call and confirm local synthetic state is cleared.
9. Confirm no media credential request, media connection, Matrix event emission, Element Call routing, push registration, or server call fanout occurred.
10. Record only pass/fail booleans and safe event names.

Do not include device identifiers, Apple account identifiers, certificate data, profile identifiers, raw logs, screenshots with private data, push values, media credentials, or internal Matrix event bodies in reports.

## Fail-Closed Behavior

The adapter fails closed when:

- the adapter is disabled.
- display metadata is empty or unsafe.
- a duplicate synthetic handle is reported.
- a CallKit report fails.
- an action arrives for an unknown local call handle.

Fail-closed diagnostics expose only safe enum and boolean values.

## Validation

Unit coverage verifies:

- empty and unsafe display labels are rejected.
- report uses only the injected proof reporter.
- answer callback records only a disabled local callback.
- end callback clears local synthetic state.
- mute callback is diagnostic-only.
- unknown handle fails closed.
- diagnostics and descriptions stay redacted.

## Remaining Blockers

- Real PushKit registration remains blocked.
- Real APNs registration remains blocked.
- Real push delivery remains blocked.
- Server push fanout remains blocked.
- Real background incoming behavior remains blocked.
- Missed-call UX remains blocked.
- Media credential request on answer remains blocked until a later approved phase.
- Media connection remains blocked in this phase.
- Element Call replacement remains blocked.
- Broad internal, production, and public rollout remain blocked.
