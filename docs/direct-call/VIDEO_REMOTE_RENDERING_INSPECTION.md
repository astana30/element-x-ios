# Video Remote Rendering Inspection

## 2.41D - Video Path Inspection And Remote Rendering Diagnosis

Status: inspected and documented; no runtime fix applied.

## Observed Symptom

Two physical iPhones were used after the foreground native audio path passed its two-device smoke. Starting video appeared to create a call surface and show local camera preview on each device, but each side appeared to see only itself. Remote participant video was not visible.

Full runtime logs are intentionally omitted because they may contain private Matrix/runtime identifiers.

## Inspected Paths

### Existing Room Video Button

The room toolbar video button sends `displayCall(startMode: .video)`. Room coordinators forward that to `presentCallScreen(startMode: .video)`, and the user-session coordinator builds an `ElementCallConfiguration` for the existing Element Call flow.

Classification: standard room video UI uses the existing Element Call / embedded call route, not the private native direct-call audio card.

### Native Direct-Call Engine

The native direct-call engine has a `DirectCallIntent.video` model value and a `startOutgoingVideoCall` entry point, but media connection remains audio-scoped:

- `DirectCallMediaEngineProtocol` exposes audio session, audio connect, microphone, speaker, and remote-audio playback APIs only.
- `DirectCallMediaPhase` has audio phases only.
- `DirectCallMediaState` tracks microphone, speaker, E2EE readiness, and remote-audio playback readiness only.
- `DirectCallEngine.connectMediaIfReady` rejects non-audio intent with `unsupportedIntent` before media connection.
- Unit coverage already verifies unsupported video intent does not connect audio media.

Classification: native direct-call video is a model/signalling placeholder only. It is not an implemented media path.

### Native LiveKit Client

The native LiveKit client is configured for audio:

- It connects with microphone disabled initially.
- It exposes microphone enable/disable and remote-audio subscription toggling.
- It subscribes only to remote audio publications.
- It does not create camera capture.
- It does not publish a local video track.
- It does not subscribe to remote video publications.
- It does not attach a video renderer.

Classification: the native LiveKit direct-call client cannot currently render remote video.

### Eligibility, Capability, And Credential Authority

The native direct-call rollout and credential authority surfaces are audio-scoped:

- Internal-pilot eligibility rejects unsupported intent before HTTP.
- Production activation gate defaults to audio intent.
- Production capability fixtures and decoding expect audio intent support.
- Production credential client rejects non-audio intent before calling the authority endpoint.
- Media engine rejects video sessions before credential request.

Classification: native video does not receive a native direct-call media credential today. Any observed local video preview is not coming from the native direct-call LiveKit media path.

## Answers

1. Which path is used for video?
   - The standard room video button uses the existing Element Call / embedded call route. The native direct-call video entry point exists but fails closed before media.

2. Is local video track created?
   - Not by the native direct-call LiveKit path. The observed local preview is most consistent with the Element Call route.

3. Is local video track published?
   - Not by the native direct-call LiveKit path. Element Call publish behavior needs separate focused inspection.

4. Does the peer subscribe to remote video track?
   - Not in the native direct-call LiveKit client; it subscribes to remote audio only. Element Call subscribe behavior remains unproven in this inspection.

5. Does the UI attach a renderer for remote video?
   - Not in the native direct-call UI/card. Element Call remote rendering remains the likely inspection target.

6. Are media credentials/grants audio-only or video-capable?
   - Native direct-call authority surfaces are audio-only at present. Non-audio intent is rejected before credential request.

7. Do both participants join the same media room/session?
   - Not proven from redacted inspection. If the observed video route is Element Call, the next phase must verify whether both devices join the same call session and whether remote tracks are published/subscribed/rendered.

8. Are participant identities/session names mismatched?
   - Not proven. Mismatch remains a candidate for the Element Call/MatrixRTC path.

9. Is remote video intentionally disabled by feature flag?
   - Native direct-call video is intentionally unsupported by code and capability gates. Element Call video is not intentionally disabled by this native audio workstream.

10. Is video blocked by current audio-only product scope?
    - Yes for the native direct-call path. The private native direct-call product path remains audio-only. The observed video issue should be investigated as Element Call / MatrixRTC / embedded call remote rendering unless a separate native video scope is approved.

## Suspected Root Cause

There is no evidence of a small native direct-call video rendering bug. The likely cause is one of:

- The smoke used the Element Call video route, where local preview works but remote track publish/subscribe/rendering failed.
- The two devices joined mismatched Element Call sessions.
- Remote media was published but not subscribed.
- Remote media was subscribed but not attached to a renderer.
- The native direct-call path was invoked with video intent, which is currently unsupported and should fail closed rather than render remote video.

## Decision

No small runtime fix is safe in 2.41D. Implementing native video would require a broader design and implementation phase covering camera capture, video publication, remote video subscription, renderer attachment, credential/capability support, tests, redaction, and physical-device proof.

The next safest step is a focused Element Call / MatrixRTC remote-rendering inspection before deciding whether to fix existing Element Call video behavior or design native direct-call video as a separate product scope.

## Next Fix Phase

`2.41E - Element Call video remote rendering diagnosis`

Goals:

- Confirm whether the failing video smoke used the Element Call route.
- Verify both devices join the same call session.
- Verify local camera publish.
- Verify remote participant publication/subscription.
- Verify remote renderer attachment.
- Keep native audio as a regression guard only.
- Keep PushKit/APNs/background incoming out of scope.
- Keep private native direct-call video out of scope unless separately approved.

## Physical Smoke Checklist

- Two physical iPhones.
- Same encrypted direct 1:1 room.
- Start video using the normal room video button.
- Confirm whether Element Call route opens.
- Confirm local preview on both devices.
- Confirm whether each device joins the same call session.
- Confirm whether remote participant appears in participant list.
- Confirm whether remote video track is published.
- Confirm whether remote video track is subscribed.
- Confirm whether remote renderer is attached.
- Confirm whether each side still sees only local self-view.
- End call from each side in separate runs.
- Confirm audio End/hangup cleanup remains approximately 2 seconds.
- Confirm no app crash.
- Keep proof notes redacted.

## Still Blocked

- Native direct-call video implementation.
- PushKit runtime.
- APNs runtime.
- Background incoming calls.
- Production/public rollout.
- Broad internal rollout.
- Element Call route replacement.
- Signing, entitlement, bundle, or project setting changes.
