# Element Call Media Diagnostics

## 2.41F - Redacted Element Call Media Diagnostics

Status: diagnostics added; physical two-iPhone proof pending.

## Scope

This phase adds small, redacted diagnostics for the existing Element Call / embedded web view route used by the normal room video button.

This is not native direct-call video implementation. It does not change PushKit/APNs/background behavior, signing, project configuration, Element Call routing, or the foreground native audio path.

## Diagnostics Added

### Native Shell Stages

The call screen now records safe native-shell stage diagnostics:

- Element Call web URL generated: true/false.
- Start mode: audio/video.
- Direct room chrome active: true/false.
- Element Call content loaded: true/false.
- Media capture permission granted by safe capture kind.
- Widget media state for audio/video enabled booleans.

These diagnostics intentionally do not include room identifiers, user identifiers, device identifiers, URLs, credentials, Matrix event bodies, or raw widget messages.

### Web View Video Renderer Counts

A narrow injected web script posts a redacted payload to the native shell with:

- schema version.
- safe stage enum.
- elapsed time bucket.
- video element count.
- visible video element count.
- playing video element count.
- stream-backed video element count.
- muted video element count.
- derived remote-renderer-candidate boolean.

The payload includes counts and booleans only. It does not include element IDs, CSS class names, labels, media stream IDs, participant IDs, track IDs, URLs, or request/response bodies.

## What This Can Answer

- Whether the native shell requested video mode.
- Whether the embedded call web URL was generated.
- Whether media capture permission was granted.
- Whether Element Call content loaded.
- Whether the embedded web view contains zero, one, or multiple visible video renderers.
- Whether the visible video renderers are stream-backed and playing.

## What This Cannot Fully Answer Yet

The native shell cannot prove these MatrixRTC internals:

- Whether both devices joined the exact same media session.
- Whether local camera publication reached the SFU.
- Whether the peer subscribed to the remote video track.
- Whether Element Call internally classified a track as local or remote.
- Whether a remote renderer is attached to a particular participant.
- Whether an RTC credential/grant permits video publication/subscription.

Those require safe Element Call / MatrixRTC-side diagnostics or redacted web-runtime instrumentation in a later phase.

## Expected Two-iPhone Diagnostic Interpretation

If each device reports only one visible stream-backed video element, the most likely fail point is before remote renderer attachment. The next checks should focus on session matching, local publish, remote participant observation, and remote subscribe state.

If each device reports multiple visible stream-backed video elements but remote video is still not visible to the user, the likely fail point is renderer layout, tile visibility, z-ordering, or self/remote track classification inside Element Call.

If media capture permission is not granted, the likely fail point is web view permission/origin handling.

## Physical Smoke Checklist

- Two physical iPhones.
- Same encrypted direct room.
- Start video using the normal room video button.
- Confirm local self-view appears.
- Confirm safe native-shell diagnostics show `start_mode=video`.
- Confirm safe native-shell diagnostics show web URL generation and content loaded.
- Confirm media capture permission is granted for the expected safe kind.
- Confirm web video diagnostics on each device.
- Record only counts/booleans/stage names.
- Confirm audio still works.
- End from each side in separate runs.
- Confirm no app crash.
- Do not paste raw runtime logs into docs.

## Next Phase

`2.41G - Element Call MatrixRTC publish subscribe diagnosis`

Goal: add or collect safe Element Call / MatrixRTC-side diagnostics for same-session matching, local publish, remote participant observation, remote video subscription, and remote renderer attachment.

## Still Blocked

- Private native direct-call video implementation.
- PushKit runtime.
- APNs runtime.
- Background incoming calls.
- Production/public rollout.
- Broad internal rollout.
- Element Call route replacement.
- Signing, entitlement, bundle, or project setting changes.
