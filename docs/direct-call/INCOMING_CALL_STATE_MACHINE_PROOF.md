# Incoming Call State Machine Proof

## 2.40K — Incoming CallKit Action Routing Proof

Status: implemented as a local contract proof.

This phase proves that the isolated synthetic CallKit UI proof callbacks can route into a native direct-audio incoming-call state-machine surface without enabling real background incoming calls.

The proof adds a disabled local action router for synthetic CallKit actions:

- answer routes to `answerRequested`, meaning the local incoming call is ready for the future server-issued media credential authority step.
- end routes to local termination and clears the synthetic incoming state.
- mute routes to local diagnostics only.

The proof remains inert:

- no PushKit runtime.
- no APNs runtime.
- no APNs or VoIP value registration.
- no background incoming-call handling.
- no server-issued media credential request.
- no media connection.
- no Matrix call event emission.
- no Element Call route change.
- no LiveKit or MatrixRTC production path change.
- no signing, bundle, entitlement, Info.plist, app.yml, or project setting change.
- no production UI.

## Contract Boundary

`NativeIncomingCallStateMachineActionRouting` is the local state-machine surface for future CallKit actions. It accepts only `NativeIncomingCallIdentity`, which contains a safe local opaque handle and redacted descriptions.

`NativeIncomingCallStateMachineSyntheticActionHandler` adapts the synthetic CallKit action callbacks into that surface. It does not own media, server authority, Matrix signalling, PushKit, APNs, or Element Call routing.

`DisabledNativeIncomingCallStateMachineActionRouter` records only safe lifecycle state and redacted diagnostics. It is a disabled proof router, not a production incoming-call service.

## Required Future Boundary

A future real incoming-call implementation must still validate the encrypted direct 1:1 room, trusted peer/device state, rollout/eligibility state, active-session state, and local session state before CallKit reportability.

Answering a future real CallKit call must still request the server-issued media credential only after user answer and only after local validation passes. The server-issued media credential endpoint remains final authority.

## Proof Coverage

Unit tests cover:

- synthetic answer routes to `answerRequested`.
- synthetic end clears local synthetic/incoming state.
- synthetic mute remains local and diagnostic-only.
- synthetic CallKit UI adapter callback routing reaches the state-machine surface.
- diagnostics remain redacted.
- media credential request and media connection flags remain false.
- Element Call route action names remain absent from proof diagnostics.

## Still Blocked

- PushKit runtime.
- APNs runtime.
- APNs or VoIP registration.
- background incoming calls.
- missed-call UX.
- media connection from background.
- server-issued media credential request from proof callbacks.
- Matrix event emission from proof callbacks.
- Element Call replacement.
- broad internal rollout.
- production/public rollout.
