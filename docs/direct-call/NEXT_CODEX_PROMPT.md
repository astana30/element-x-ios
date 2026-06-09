# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.41g-element-call-matrixrtc-publish-subscribe-diagnosis

Next phase: 2.41G - Element Call MatrixRTC publish subscribe diagnosis.

Goal:
Add or collect safe Element Call / MatrixRTC-side diagnostics to identify why each side shows local video but remote participant video is not visible.

Context:
- Foreground native audio works on two physical iPhones.
- End/hangup cleanup is approximately 2 seconds on real devices.
- 2.41D inspected the video path and found that the normal room video button routes through Element Call / embedded call.
- 2.41E confirmed the native shell creates the expected Element Call route for normal room video.
- 2.41F added native-shell and web-view diagnostics using safe booleans, enums, elapsed buckets, and video renderer counts only.
- 2.41F diagnostics can tell whether the web view has zero, one, or multiple visible stream-backed video renderers.
- 2.41F diagnostics cannot yet prove MatrixRTC same-session, local publish, remote subscribe, grant, or participant-to-renderer mapping.

Scope:
- Inspect the embedded Element Call / MatrixRTC runtime surfaces.
- Add or collect redacted MatrixRTC diagnostics only if they avoid raw IDs, URLs, credentials, media-session names, track IDs, participant IDs, event bodies, and raw logs.
- Verify same-session matching using safe labels only.
- Verify local camera publish state using safe booleans/enums.
- Verify remote participant observation using safe labels only.
- Verify remote video publication/subscription state using safe booleans/enums.
- Verify remote renderer attachment using safe booleans/enums.
- Determine whether the issue is session mismatch, publish failure, subscribe failure, renderer binding, permission, or RTC transport credential/grant behavior.
- Keep foreground native audio as a regression guard only.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, or project settings.
- Do not replace Element Call routing.
- Do not change production rollout gates.
- Do not implement private native direct-call video in this phase.
- Do not add raw account, room, device, event, auth credential, push/media, Apple signing, media-session, track, participant, private runtime log, or credential-shaped fixture values.
- Do not paste full runtime logs into docs.

Expected output:
- Same-session result.
- Local camera publish result.
- Remote participant and remote video subscription result.
- Remote renderer attachment result.
- Suspected root cause.
- Whether a narrow Element Call/MatrixRTC fix is possible.
- Next implementation phase if a fix is required.
- Two-physical-iPhone smoke checklist.
