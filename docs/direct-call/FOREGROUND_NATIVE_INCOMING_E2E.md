# Foreground Native Incoming E2E

## 2.41A — Foreground Native Incoming Call E2E

Status: implemented as a foreground-only contract path.

This phase connects the existing foreground incoming native-call contracts into one product-relevant local flow:

1. A foreground incoming native audio session is received while the callee app is already open.
2. The incoming session is validated as foreground, incoming, ringing, audio-only, and safe for local report.
3. The isolated CallKit UI adapter is asked to report the incoming call.
4. A CallKit answer routes to `answerRequested`.
5. The foreground acceptance gate asks the server-issued media credential authority boundary for a safe decision.
6. Media connection is attempted only after an authorized foreground decision.
7. End clears local incoming state and tears down started media through the injected connector.

This is not PushKit work, not APNs work, not background incoming work, and not production/public rollout.

## Implementation Boundary

`ForegroundNativeIncomingCallE2ECoordinator` is a foreground-only coordinator contract. It accepts a foreground incoming `DirectCallSession`, safe CallKit display metadata, local validation context, an isolated CallKit adapter, the foreground acceptance gate, an injected media connector, and redacted diagnostics.

The coordinator does not own server networking, Matrix event emission, PushKit, APNs, background wake, Element Call routing, signing, bundle settings, or production UI.

The injected media connector is the only place where future native media setup may be allowed. Unit tests use a local spy connector. The coordinator records `mediaConnectAttempted=true` only after the acceptance gate returns an authorized decision.

## Proven Behavior

- Incoming foreground native call state is created safely.
- The CallKit UI path is requested only for foreground incoming ringing audio sessions.
- CallKit answer routes to `answerRequested`.
- Missing authority blocks media.
- Denied authority blocks media.
- Malformed authority blocks media.
- Expired authority blocks media.
- Unverifiable authority blocks media.
- Authorized authority allows the injected media connector to run.
- Media is not attempted before authorization.
- Media setup failure after authorization fails closed.
- End clears local incoming state and tears down started media through the injected connector.
- Mute remains local and diagnostic-only.
- Diagnostics stay redacted and route-free.

## Physical-Device Smoke Checklist

Pending for a later supervised device proof:

- iPhone A caller.
- iPhone B callee app foreground/open in the approved encrypted direct 1:1 chat.
- Start native audio call from A.
- B sees iOS CallKit incoming UI.
- B answers.
- Audio connects only after authority approval.
- Talk for 30-60 seconds.
- End the call from either side.
- A/B return idle with no active session.
- No crash.
- Element Call fallback remains visible and unchanged.

## 2.41A-S — One-Device Foreground Native Incoming Smoke

Status: completed with follow-up hardening items.

Smoke setup:

- Caller: iOS Simulator using a separate test user.
- Callee: physical iPhone using a separate test user.
- Callee state: SalemX open in foreground.
- Background incoming calls were not tested.
- PushKit/APNs were not tested.

Observed result:

- The physical iPhone displayed the iOS system CallKit incoming-call UI.
- The Answer action worked.
- Media connected after the foreground incoming path.
- The End action cleared the call immediately on one side and after approximately 10 seconds on the peer side.
- No app crash was observed.
- Audio connected, but a repeating tick/click artifact was heard.

Conclusion:

The foreground native incoming call E2E path is physically smoke-tested with one physical iPhone and one iOS Simulator.

Carry-forward items for `2.41B — foreground audio and call lifecycle hardening`:

- Investigate and fix the repeating audio tick/click artifact.
- Investigate peer-side end cleanup delay of approximately 10 seconds.
- Repeat smoke with two physical iPhones when available.
- Validate mute/unmute, speaker/earpiece/Bluetooth routing, repeated calls, and longer 5-10 minute calls.

Full runtime logs are intentionally omitted because they may contain private Matrix/runtime identifiers.

## Still Blocked

- PushKit runtime.
- APNs runtime.
- APNs or VoIP value registration.
- Background incoming calls.
- Killed-app incoming calls.
- Unsupervised incoming-call dogfood.
- Production/public rollout.
- Element Call route replacement.
- Video.
- Broad internal rollout.
