# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.41e-element-call-video-remote-rendering-diagnosis

Next phase: 2.41E - Element Call video remote rendering diagnosis.

Goal:
Diagnose why two physical iPhones each show local video but do not show remote participant video when starting video from the normal room video button.

Context:
- Foreground native audio works on two physical iPhones.
- End/hangup cleanup is approximately 2 seconds on real devices.
- Previous long peer-side cleanup delay and tick/click audio artifact appear Simulator-related.
- 2.41D inspected the video path and found that the normal room video button routes through Element Call / embedded call.
- The private native direct-call media path remains audio-only and rejects native video intent before media connection.
- Native direct-call eligibility, activation, capability, and credential-authority surfaces are audio-scoped.
- The video self-view-only issue is likely in Element Call / MatrixRTC / embedded call session matching, publish/subscribe, or renderer attachment.
- Full runtime logs must remain omitted or redacted because they may contain private runtime identifiers.

Scope:
- Confirm the failing smoke uses the Element Call route.
- Verify both devices join the same call session using safe labels only.
- Verify local camera publish state.
- Verify remote participant publication and subscription state.
- Verify remote renderer attachment.
- Determine whether the issue is session mismatch, publish failure, subscribe failure, track selection, renderer binding, permissions, or media lifecycle.
- Keep native audio End/hangup and audio quality as regression checks only.
- Keep native direct-call video implementation out of scope unless separately approved.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, or project settings.
- Do not replace Element Call routing.
- Do not change production rollout gates.
- Do not add raw account, room, device, event, auth credential, push/media, Apple signing, private runtime log, or credential-shaped fixture values.

Expected output:
- Path classification.
- Redacted publish/subscribe/rendering diagnosis.
- Suspected root cause.
- Whether a narrow Element Call/MatrixRTC fix is possible.
- Next implementation phase if a fix is required.
- Two-physical-iPhone smoke checklist.
