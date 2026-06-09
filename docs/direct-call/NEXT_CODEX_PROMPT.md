# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.41f-redacted-element-call-media-diagnostics

Next phase: 2.41F - redacted Element Call media diagnostics.

Goal:
Capture safe Element Call / MatrixRTC media diagnostics on two physical iPhones to identify why each side shows local video but remote participant video is not visible.

Context:
- Foreground native audio works on two physical iPhones.
- End/hangup cleanup is approximately 2 seconds on real devices.
- 2.41D inspected the video path and found that the normal room video button routes through Element Call / embedded call.
- 2.41E confirmed the native shell creates the expected Element Call route for normal room video.
- Direct room video uses the SDK direct-message video call intent, not the voice-only intent.
- The app-side embedded call URL hides app-replaced controls and screensharing, but does not disable video.
- The native shell hosts the embedded web view and grants media capture for the embedded call origin.
- Local camera publish, remote participant observation, remote video subscription, and remote renderer attachment are owned by Element Call / MatrixRTC inside the web view.
- No app/runtime code changed in 2.41E.

Scope:
- Add or run redacted Element Call / MatrixRTC diagnostics only if they can avoid raw IDs, credentials, media-session names, and raw logs.
- Verify same-session matching with safe labels only.
- Verify local camera publish state.
- Verify remote participant presence.
- Verify remote video publication/subscription state.
- Verify remote renderer attachment.
- Determine whether the issue is session mismatch, publish failure, subscribe failure, renderer binding, media permission, or RTC transport credential/grant behavior.
- Keep foreground native audio as a regression guard only.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, or project settings.
- Do not replace Element Call routing.
- Do not change production rollout gates.
- Do not implement private native direct-call video in this phase.
- Do not add raw account, room, device, event, auth credential, push/media, Apple signing, media-session, private runtime log, or credential-shaped fixture values.
- Do not paste full runtime logs into docs.

Expected output:
- Safe diagnostics fields captured or documented as unavailable.
- Same-session result.
- Local camera publish result.
- Remote participant and remote video subscription result.
- Remote renderer attachment result.
- Suspected root cause.
- Whether a narrow Element Call/MatrixRTC fix is possible.
- Next implementation phase if a fix is required.
- Two-physical-iPhone smoke checklist.
