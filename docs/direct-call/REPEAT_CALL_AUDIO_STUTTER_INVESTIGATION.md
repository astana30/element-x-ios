# Repeat-Call Audio Stutter Investigation

## 2.41G-A - Repeat-call audio stutter and lifecycle stabilization

Status: lifecycle cleanup added; physical two-iPhone repeat-call smoke pending.

## Symptom

Two-device foreground audio calls work, and End/hangup cleanup is acceptable on real devices. The remaining audio issue is repeat-call stutter or hesitation after the first Embedded Element Call audio call.

Recent diagnostics show:

- Foreground audio uses the existing Embedded Element Call route.
- Direct audio call URL generation uses voice intent.
- Native-shell diagnostics report `start_mode=audio`.
- Widget media state reports `audio_enabled=true` and `video_enabled=false`.
- Repeated call startup can show existing timeline subscription warnings.
- WebContent audio component errors may appear around embedded call startup.
- Video remote rendering is a separate Element Call / MatrixRTC investigation.

Full raw logs are intentionally omitted because they may contain private Matrix/runtime identifiers.

## Suspected Causes Inspected

- Embedded Element Call call-screen lifecycle around audio start/end/repeat.
- `CallScreenViewModel` setup, stop, and local termination paths.
- Element Call widget hangup handling.
- Element Call service teardown and ongoing call session cleanup.
- Web view reuse and stale WebContent media state after End.
- Audio-only direct-room mode remaining distinct from video mode.

## Change Added

`CallScreenViewModel` now performs an idempotent embedded web content reset when the call screen stops or begins local termination. The reset asks the embedded page to:

- stop active audio/video element tracks;
- detach stream-backed media from audio/video elements;
- clear media element sources;
- stop the current web page load.

The existing widget hangup, Matrix termination request, and Element Call service teardown paths remain in place. This is a narrow foreground lifecycle cleanup intended to prevent stale WebContent media state from carrying into the next call.

## Scope Preserved

- Element Call route remains unchanged.
- Audio calls remain audio-only.
- Video behavior is not changed.
- No PushKit/APNs/background behavior is added.
- No signing, bundle, entitlement, Info.plist, app.yml, or project settings are changed.
- No server-issued credential authority behavior is bypassed.
- Diagnostics remain redacted.

## Physical Smoke Checklist

- Two physical iPhones.
- Call #1 audio.
- Answer.
- Talk for 30 seconds.
- End.
- Wait 2 seconds.
- Call #2 audio.
- Answer.
- Measure audio connection delay.
- Check for stutter/hesitation.
- Repeat 3 times.
- Check for crash.
- Confirm Element Call route is unaffected.

## Carry-forward

If stutter remains after this cleanup, the next investigation should classify whether the remaining source is web-view reload timing, WebContent audio session behavior, Element Call audio component startup, or remote media startup timing.
