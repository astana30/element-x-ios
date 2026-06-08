# Synthetic CallKit Proof

Status: disabled synthetic proof surface only. No PushKit runtime, APNs runtime, push credential registration, push delivery, server push, media credential request, media connection, background incoming behavior, missed-call UX, Element Call route change, native audio gate change, signing change, project setting change, video, or rollout behavior is added by this phase.

## Scope

2.40J adds a local synthetic CallKit proof contract for native direct audio. The proof is intentionally not connected to push delivery or media setup.

The synthetic path accepts only a safe local incoming call identity from the disabled 2.40H contracts and safe display metadata. It maps report, answer, end, and mute events into disabled local callbacks and redacted diagnostics.

## Synthetic Trigger

The proof trigger is local and developer-only:

1. Create a safe local incoming call identity with an opaque local handle.
2. Validate safe display metadata.
3. Call the disabled synthetic proof coordinator with the safe identity.
4. On a future physical-device harness, swap the injected reporter for a narrow CallKit reporter.
5. Keep PushKit/APNs delivery absent.
6. Keep media credential requests absent.
7. Keep media connection absent.

No public product UI is added. No normal production user path can reach this proof surface.

## Callback Mapping

Synthetic callbacks are intentionally inert:

- report incoming call: records safe report attempted/succeeded diagnostics.
- answer: records a safe local answered callback only.
- end: records a safe local ended callback, clears local synthetic state, and emits safe terminal diagnostics.
- mute: records a safe mute callback only.

These callbacks do not send Matrix events, do not request media credentials, do not connect media, do not register push credentials, and do not route through Element Call.

## Fail-Closed Behavior

The synthetic proof fails closed when:

- the proof coordinator is disabled.
- the local handle is malformed or unknown.
- the safe display metadata is missing or unsafe.
- a duplicate synthetic report is attempted.
- the injected reporter fails.

Fail-closed diagnostics expose only safe enum/boolean values.

## Manual Device Proof Steps

When a physical-device harness is explicitly approved later:

1. Use a development-signed app with the existing 2.40F entitlements.
2. Ensure the synthetic proof gate is disabled by default.
3. Enable only the local developer trigger for the current run.
4. Trigger one synthetic native direct-audio incoming call using a safe local handle and safe display label.
5. Confirm the system call UI appears only for the synthetic call.
6. Tap Answer and confirm only the disabled answer callback is recorded.
7. Tap Mute and confirm only the disabled mute callback is recorded.
8. End the call and confirm local synthetic state is cleared.
9. Confirm no push delivery, push credential registration, media credential request, media connection, Element Call route change, or production activation occurred.

Report only pass/fail booleans, safe enums, and redacted local labels.

## Validation

Unit tests cover:

- safe display metadata validation.
- disabled default fail-closed behavior.
- safe local identity reporting.
- answer callback without media credential request.
- answer callback without media connection.
- unknown handle fail-closed behavior.
- end callback clearing local state.
- mute callback as diagnostic-only behavior.
- redacted diagnostics and descriptions.

## Remaining Blockers

- Real PushKit registration remains blocked.
- Real APNs registration remains blocked.
- Real push delivery remains blocked.
- Server push fanout remains blocked.
- Background incoming behavior remains blocked.
- Missed-call UX remains blocked.
- Media credential request on answer remains blocked until a later approved phase.
- Media connection remains blocked in this phase.
- Element Call replacement remains blocked.
- Broad internal, production, and public rollout remain blocked.
