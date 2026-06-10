# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42f-foreground-sse-runtime-wiring-plan

Next phase: 2.42F - foreground SSE runtime wiring plan.

Goal:
Decide and design where the disabled-by-default iOS foreground SSE transport should be owned in runtime lifecycle, and how safe endpoint configuration should be supplied.

Context:
- Element Call room-list/timeline delivery can delay repeat incoming calls by 10-30 seconds.
- 2.42A added a foreground invite signal contract, validator, handler, and fail-closed tests.
- 2.42B added a disabled/default transport boundary, in-memory transport, transport diagnostics, and pipeline.
- 2.42D added a call-service foreground-only SSE stream endpoint.
- 2.42E added an iOS SSE parser and transport boundary.
- The iOS SSE transport is disabled unless explicitly constructed with `isEnabled=true`.
- The URLSession-backed stream requires an injected request; no production URL or credential value is hardcoded.
- Invite receipt remains side-effect-free for media and Matrix events.

Scope:
- Inspect app/session foreground lifecycle ownership points.
- Decide where an enabled foreground SSE transport may be started and stopped.
- Define safe endpoint configuration and authenticated request construction.
- Define reconnect/backoff and stream completion behavior.
- Define coordination with timeline/room-list fallback to avoid duplicate incoming UI.
- Keep answer-time foreground authority as the only path that can allow media later.
- Keep logs/docs redacted.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, or project settings.
- Do not replace Element Call routing.
- Do not hardcode production server URLs or credential values.
- Do not bypass server-issued media credential authority.
- Do not connect media from invite receipt.
- Do not emit Matrix call events from invite receipt.
- Do not add raw account, room, device, event, auth credential, push/media, Apple signing, media-session, track, participant, private runtime log, or credential-shaped fixture values.

Expected output:
- Runtime wiring plan or smallest disabled-by-default runtime owner if safe.
- Tests for start/stop ownership, disabled default, reconnect state, fallback de-duplication, and no media side effects.
- Updated docs/status/worklog/next prompt.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
