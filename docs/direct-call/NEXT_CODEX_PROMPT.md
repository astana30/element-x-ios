# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.41g-b-element-call-foreground-invite-source

Next phase: 2.41G-B - Element Call foreground call invite source design.

Goal:
Design and prove a foreground-only Element Call invite source that receives call invite/member events before delayed timeline item rendering or room-list fallback.

Context:
- Foreground audio uses the existing Embedded Element Call route.
- 2.41G-A4 added a foreground current-room observer and incoming/CallKit fast path.
- 2.41G-A5 diagnostics showed the current-room observer can receive fresh repeated-call candidates only after the delay is already `over10s`.
- Room-list fallback is also later and is not a faster source.
- 2.41G-A6 found no existing safe app-side source earlier than Matrix sync/timeline or room-summary materialization.
- The next phase must design a safe foreground-only Element Call invite source/contract, likely at SDK timeline-diff, MatrixRTC call-member, or sliding-sync subscription level.

Scope:
- Foreground only.
- Inspect SDK timeline-diff listener feasibility for Element Call call events.
- Inspect whether a MatrixRTC call-member stream or notification ID stream is available without PushKit/APNs/background behavior.
- Inspect whether sliding-sync/current-room subscription settings can prioritize call invite/member events for the open direct chat.
- Preserve active-call, duplicate, own-event, terminal/stale, and fallback suppression guards.
- Add redacted diagnostics if a safe source is implemented.
- Add unit tests proving repeat incoming uses the faster source and room-list fallback does not double-trigger.
- Keep logs/docs redacted.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, or project settings.
- Do not replace Element Call routing.
- Do not change production rollout gates.
- Do not implement private native direct-call video in this phase.
- Do not bypass server-issued credential authority.
- Do not add raw account, room, device, event, auth credential, push/media, Apple signing, media-session, track, participant, private runtime log, or credential-shaped fixture values.
- Do not paste full runtime logs into docs.

Expected output:
- Faster foreground invite source implemented with tests, or a design-only blocker if no safe source exists.
- Classification of the exact source inspected.
- Redacted diagnostics contract for source timing.
- Physical smoke checklist for Call #1, Call #2, and Call #3 incoming/CallKit latency in the open direct chat.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
