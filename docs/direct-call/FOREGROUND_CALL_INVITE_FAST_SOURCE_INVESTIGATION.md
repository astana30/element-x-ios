# Foreground Call Invite Fast Source Investigation

## 2.41G-A6 - Foreground Call Invite Fast Source Investigation

Status: documented; no safe faster source implemented in this phase.

2.41G-A4 added a foreground current-room observer for Element Call invite events in the open direct chat. 2.41G-A5 diagnostics showed that the observer and fast-path request work once the event reaches the native app, but repeated-call events can arrive at that observer already in the `over10s` delay bucket. Room-list fallback can also run later.

Conclusion: the current-room fast path is still fed by a late source. It does not fix the upstream delivery delay.

## Sources Inspected

- Current open-room timeline item provider updates.
- Direct room `JoinedRoomProxy.subscribeForUpdates()` flow.
- Room-list / room-summary fallback based on latest room event state.
- Existing Element Call incoming fallback and CallKit reporting path.
- Existing PushKit / VoIP handling for Element Call.
- Existing notification manager surfaces.
- Native direct-call Matrix timeline signal listener contracts.
- Room call event parsing from SDK timeline items and timeline item proxies.

## Findings

- The open-room flow already subscribes the room and live timeline before `ElementCallService.observeForegroundRoom(...)` attaches the current-room observer.
- The current-room observer reads the materialized timeline item provider. Physical diagnostics show this source can receive repeat-call invite events only after the delay has already exceeded the product target.
- Room-list fallback is not earlier. It depends on room-summary updates and latest-event resolution, so it also sits after Matrix sync / sliding-sync delivery.
- Notification manager surfaces are notification presentation/tap handling, not a foreground Matrix call invite stream.
- The existing Element Call PushKit path may report calls through CallKit, but using it would be PushKit/background work and is outside this phase.
- The native direct-call Matrix timeline signal listener can attach at the SDK timeline-diff level, but it is scoped to SalemX native direct-call custom signal envelopes. Reusing that pattern for Element Call would require a new Element Call invite listener/contract rather than a small local fast-path patch.
- No current app-side surface was found that observes Element Call invite/member events earlier than Matrix sync/timeline or room-summary materialization while staying within the no-PushKit/no-background constraints.

## Classification

The current-room observer remains useful for suppressing stale/duplicate events and for proving where delay occurs, but it is insufficient as the final repeat-call latency fix.

The missing piece is a true foreground call-invite source before timeline rendering and room-list fallback. That likely needs one of:

- a dedicated SDK/MatrixRTC foreground call-member or RTC notification stream;
- an Element Call invite observer built directly on SDK timeline diffs with safe event classification;
- a sliding-sync subscription/configuration change that delivers call invite/member events promptly for the currently open direct room.

Each option needs a separate design/proof phase with tests and redacted diagnostics. This phase does not change runtime behavior.

## Carry-Forward Requirements

- Keep the A4/A5 current-room observer diagnostics until a faster source is proven.
- Do not use PushKit/APNs/background delivery as the foreground repeat-call fix.
- Do not reuse private native direct-call signaling contracts for Element Call without a separate payload and redaction contract.
- Preserve the existing Element Call route.
- Keep active-call, duplicate, own-event, terminal/stale, and fallback suppression guards.
- Keep all diagnostics to safe enums, booleans, and duration buckets.

## Next Phase

Recommended next phase: `2.41G-B - Element Call foreground call invite source design`.

Goal: design and prove a safe foreground-only Element Call invite observer that receives call invite/member events before room-list fallback and before delayed timeline item rendering, without PushKit/APNs/background behavior.

Validation target for the next phase:

- Call #2 and Call #3 incoming/CallKit appear within 0-3 seconds in the open direct chat.
- No duplicate incoming UI for the same call.
- Stale terminal events remain suppressed.
- Existing Element Call route remains unchanged.
- No PushKit/APNs/token/background/signing/project changes.

Full runtime logs are intentionally omitted because they may contain private Matrix/runtime identifiers.
