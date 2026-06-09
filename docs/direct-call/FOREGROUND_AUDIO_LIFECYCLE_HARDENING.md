# Foreground Audio And Call Lifecycle Hardening

## 2.41B — Foreground Audio And Call Lifecycle Hardening

Status: implemented as scoped foreground lifecycle hardening; physical smoke still required.

This phase follows the one-device 2.41A-S smoke where the foreground incoming native call path connected media, but carried two hardening items:

- A repeating audio tick/click artifact was heard during connected media.
- End cleared immediately on one side and after approximately 10 seconds on the peer side.

The implementation keeps the proven foreground-only boundary: no PushKit runtime, no APNs runtime, no background incoming calls, no Element Call route change, no signing change, and no media connection before the foreground authority decision allows it.

## Implemented Hardening

- Duplicate answered foreground incoming calls now return the already-active local result instead of creating a second media connection.
- A second connect attempt while a media connection is already in progress fails closed with a safe local reason.
- End is idempotent for the local foreground incoming coordinator.
- Local incoming state is cleared before awaiting media teardown, so local UI/status cleanup is not delayed by async media cleanup.
- Repeated foreground incoming calls with new safe local handles reset lifecycle state and can connect after the previous call ends.
- Redacted diagnostics include only safe lifecycle counts and booleans.

## Audio Artifact Assessment

The tick/click artifact was not conclusively fixed in this phase. The available smoke evidence is not enough to distinguish between simulator audio behavior, route/session configuration, duplicate render/connect behavior, mixed-device WebRTC behavior, or physical route behavior.

The lifecycle changes reduce one plausible cause: accidental duplicate media connection after repeated answer/connect handling. Further physical-device smoke is required to determine whether the artifact remains.

## Peer Cleanup Assessment

The local foreground incoming coordinator now clears local state before awaiting media teardown and treats repeated End as a safe no-op result. This addresses local cleanup timing in the foreground incoming path.

The reported peer-side delay of approximately 10 seconds still needs a follow-up physical smoke. If it persists, investigate terminal-event delivery timing, peer polling/status refresh, and teardown propagation outside the local coordinator boundary.

## Next Physical Smoke Checklist

- Simulator caller plus physical iPhone callee.
- Physical iPhone callee open in foreground.
- CallKit incoming UI appears.
- Answer.
- Confirm media connects only after foreground authority approval.
- Listen for repeating tick/click artifact.
- End from each side in separate runs.
- Confirm both sides clear promptly.
- Repeat call 2-3 times.
- Validate mute/unmute.
- Validate speaker/earpiece route where available.
- Run one 30-60 second call.
- Prepare for a later 5-10 minute foreground call.
- Confirm no crash.
- Confirm Element Call fallback remains visible and unchanged.

## Still Blocked

- PushKit runtime.
- APNs runtime.
- APNs or VoIP value registration.
- Background incoming calls.
- Killed-app incoming calls.
- Production/public rollout.
- Broad internal rollout.
- Element Call route replacement.
- Video.
