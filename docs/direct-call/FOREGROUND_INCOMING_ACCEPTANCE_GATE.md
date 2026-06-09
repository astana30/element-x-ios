# Foreground Incoming Acceptance Gate

## 2.40L — Foreground Incoming-Call Acceptance Gate

Status: implemented as a local contract proof.

This phase adds a foreground-only acceptance gate between a synthetic/local incoming CallKit answer and any future native media allowance.

This is not PushKit/APNs work, not background incoming-call work, and not production incoming-call rollout.

## Proven Behavior

- A synthetic/local incoming CallKit answer routes to `answerRequested`.
- Media remains blocked while the local state is only `answerRequested`.
- A foreground acceptance authority decision is required before the local proof can move to `foregroundCredentialAuthorized`.
- Missing authority fails closed.
- Denied authority fails closed.
- Malformed authority fails closed.
- Expired authority fails closed.
- Unverifiable authority fails closed.
- An authorized decision moves only to a safe local authorized state.
- End clears the local incoming/acceptance state.
- Mute remains local and diagnostic-only.

## Contract Boundary

`DisabledNativeIncomingForegroundAcceptanceGate` is a local proof gate. It accepts only `NativeIncomingCallIdentity`, reads/writes only the local incoming state store, and records only redacted diagnostics.

`NativeIncomingForegroundAcceptanceAuthorizing` is the mocked/test-safe authority boundary for this phase. It returns safe enum decisions only. It does not perform network I/O, does not contact the server-issued media credential endpoint, and does not connect media.

`foregroundCredentialAuthorized` means only that the local foreground gate has accepted the call for the future authority handoff. It is not an active call state and does not imply LiveKit, MatrixRTC, or Matrix signalling.

## Diagnostics Contract

Allowed diagnostics remain safe booleans/enums only:

- lifecycle state.
- fail-closed reason.
- report attempted/succeeded booleans.
- media credential requested boolean for the mocked authority surface.
- media connect attempted boolean.

The proof keeps `mediaConnectAttempted=false` in every acceptance-gate path.

## Still Blocked

- PushKit runtime.
- APNs runtime.
- APNs or VoIP registration.
- background incoming calls.
- real server-issued media credential request from this proof.
- automatic LiveKit or MatrixRTC media connection.
- Matrix call event emission.
- Element Call routing changes.
- production UI.
- broad internal rollout.
- production/public rollout.
