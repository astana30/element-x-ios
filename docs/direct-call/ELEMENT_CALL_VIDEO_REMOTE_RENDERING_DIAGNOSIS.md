# Element Call Video Remote Rendering Diagnosis

## 2.41E - Element Call Video Remote Rendering Diagnosis

Status: inspected and documented; no runtime fix applied.

## Observed Symptom

Two physical iPhones can start the normal room video call surface. Each device shows local video/self view, but remote participant video is not visible.

Full runtime logs are intentionally omitted because they may contain private Matrix/runtime identifiers.

## Path Classification

### Room Video Button

The normal room video button sends `displayCall(startMode: .video)` from `RoomScreen`.

The action flows through:

- `RoomScreenViewModel`
- `RoomScreenCoordinator`
- `RoomFlowCoordinator`
- `UserSessionFlowCoordinator.presentCallScreen(roomProxy:startMode:)`
- `CallScreenCoordinator`
- `CallScreenViewModel`
- `ElementCallWidgetDriver`
- `CallScreen.CallView` hosting the embedded Element Call web view

Classification: the observed video path is the existing Element Call / embedded call route.

### Element Call Configuration

`UserSessionFlowCoordinator` builds an `ElementCallConfiguration.roomCall` with:

- the joined room proxy
- the client proxy
- the app bundle identifier as client ID
- the embedded Element Call base URL or developer override
- the current color scheme
- `startMode: .video`

`CallScreenViewModel` obtains the room widget driver through `roomProxy.elementCallWidgetDriver(deviceID:)` and configures the driver start mode.

`ElementCallWidgetDriver.start(...)` creates the virtual Element Call widget with `newVirtualElementCallWidget`, generates the web view URL with `generateWebviewUrl`, and creates the Matrix widget driver with `makeWidgetDriver`.

Classification: the app creates a Matrix widget-backed embedded Element Call session. It does not create native camera tracks or native remote video renderers.

### Direct-Room Video Intent

For direct rooms, `RoomProtocol.joinCallIntent(for: .video)` maps to the SDK direct-message video call intent. Audio maps to the distinct direct-message voice call intent.

Classification: the app-side room video path is not intentionally using the audio-only direct-message voice intent.

### Embedded Call URL Parameters

For direct room calls, the app mirrors these parameters into the query and fragment:

- `controlledAudioDevices=false`
- `header=none`
- `showControls=false`
- `hideScreensharing=true`
- `autoLeave=true`

Classification: these parameters hide app-replaced controls and screensharing, but there is no app-side URL parameter that explicitly disables remote video.

### Web View And Media Permissions

`CallScreen.CallView` loads the embedded Element Call web view and grants media capture only for the local embedded origin or the loaded call origin. The embedded web view remains visible for direct video calls; only direct audio mode hides the embedded call view.

Classification: the native shell allows the embedded video surface to render. It does not attach a native remote video renderer.

### RTC Transport Setup

For room calls, `CallScreenViewModel` injects an RTC transport script that exposes a LiveKit transport service URL to Element Call and authorizes Matrix RTC transport requests against the homeserver origin.

Classification: Element Call is responsible for requesting transport credentials, joining the media session, publishing camera media, subscribing to remote media, and rendering remote video inside the web view.

## Answers

1. Which exact code path handles normal room video button?
   - `RoomScreen` sends `displayCall(.video)`, then room and user-session coordinators present `CallScreen` with `ElementCallConfiguration.roomCall`.

2. Which object/service creates the Element Call URL or embedded widget?
   - `ElementCallWidgetDriver` creates the virtual widget, generates the web view URL, and runs the Matrix widget driver.

3. Do both participants join the same Element Call session?
   - Not proven from static inspection. The app passes the same Matrix room context into the widget path, but session equality must be verified from Element Call / MatrixRTC runtime diagnostics using redacted labels only.

4. Is local video publish enabled?
   - App state starts video mode with `isVideoEnabled=true`, and the direct-room video intent is used. Actual camera track publication happens inside Element Call and is not proven by this Swift inspection.

5. Is remote video subscription enabled?
   - Not proven. Remote video subscription is inside Element Call / MatrixRTC, not the native shell.

6. Is remote video renderer attached?
   - Not proven. The native shell hosts the web view; Element Call attaches any remote video renderer internally.

7. Is this a token/grant issue?
   - Not proven. The native direct-call credential endpoint is not used by this route. Element Call obtains RTC transport credentials through the injected Matrix RTC transport path, so credential or grant issues must be diagnosed in the Element Call / homeserver RTC transport flow.

8. Is this a MatrixRTC room/session mismatch?
   - Possible and unproven. It is one of the highest-value next checks because both devices showing only self-view can be caused by mismatched session identity or separate media sessions.

9. Is the embedded Element Call configured audio-only?
   - No app-side audio-only configuration was found for normal room video. The direct room video button uses video start mode and the SDK direct-message video call intent.

10. Is video disabled by feature flag/config?
    - No app-side video-disabled flag was found on this route. Screensharing is hidden for direct room calls, but video itself is not explicitly disabled by the app shell.

11. Is it expected that current native direct-call path is audio-only?
    - Yes. The private native direct-call path remains audio-only and rejects native video intent before media connection. That is separate from the normal room video button.

## Suspected Root Cause

The most likely failure domain is Element Call / MatrixRTC runtime behavior, not the private native direct-call audio path.

Most likely candidates:

- Both devices are not joining the same Element Call / MatrixRTC session.
- Local camera preview is active, but local video track publication fails.
- Local video publishes, but the peer does not subscribe to the remote video track.
- Remote video subscription succeeds, but the Element Call web UI does not attach or display the remote renderer.
- The RTC transport credential/grant allows joining but does not permit the expected video publication/subscription path.
- Embedded Element Call 0.17.0 has a direct-room video rendering regression with the current app wrapper or MatrixRTC transport setup.

## Decision

No narrow Swift runtime fix is safe in 2.41E. The native shell is creating the expected embedded Element Call route and does not own remote video rendering.

The next phase should capture redacted Element Call / MatrixRTC runtime diagnostics from two physical iPhones before changing Element Call integration code.

## Recommended Next Phase

`2.41F - redacted Element Call media diagnostics`

Scope:

- Capture safe web-side media diagnostics from Element Call on both devices.
- Verify same session using safe labels only.
- Verify local camera publish state.
- Verify remote participant presence.
- Verify remote video publication/subscription state.
- Verify remote renderer attachment.
- Determine whether the issue is session mismatch, publish failure, subscribe failure, renderer binding, permission, or credential/grant.
- Keep private native direct-call video implementation out of scope.

## Two-iPhone Smoke Checklist

- Two physical iPhones.
- Same encrypted direct room.
- Start video using the normal room video button.
- Confirm the Element Call / embedded call route opens.
- Confirm the call URL path is generated on both devices.
- Confirm local preview appears on both devices.
- Confirm both devices report the same safe session label.
- Confirm each device observes the remote participant with a safe participant label.
- Confirm each device publishes local camera media.
- Confirm each device subscribes to remote video.
- Confirm each device attaches a remote renderer.
- Confirm whether remote video becomes visible.
- Confirm audio still works.
- End from each side in separate runs.
- Confirm no app crash.
- Confirm foreground native audio remains unaffected.
- Keep notes and diagnostics redacted.

## Still Blocked

- Private native direct-call video implementation.
- PushKit runtime.
- APNs runtime.
- Background incoming calls.
- Production/public rollout.
- Broad internal rollout.
- Element Call route replacement.
- Signing, entitlement, bundle, or project setting changes.
