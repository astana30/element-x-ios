# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42e-ios-foreground-signaling-sse-transport

Next phase: 2.42E - iOS foreground signaling SSE transport integration.

Goal:
Wire the iOS foreground signaling transport to the 2.42D call-service SSE endpoint behind explicit disabled-by-default configuration.

Context:
- Element Call room-list/timeline delivery can delay repeat incoming calls by 10-30 seconds.
- 2.42A added a foreground invite signal contract, validator, handler, and fail-closed tests.
- 2.42B added a disabled/default transport boundary, in-memory transport, transport diagnostics, and a pipeline that feeds safe invite events into the existing handler.
- 2.42C documented that no server endpoint existed yet.
- 2.42D added an authenticated foreground-only call-service SSE stream and internal server fanout boundary.
- The stream endpoint emits `foreground.ready` and opaque `foreground.call.invite` events.
- Invite publishing remains internal to the server boundary until a validated server call source exists.

Scope:
- Add an iOS SSE client transport behind explicit disabled-by-default configuration.
- Parse only the minimal opaque invite schema.
- Feed valid invites into the existing foreground invite handler.
- Keep duplicate, stale, terminal, malformed, unsupported, and active-call guards.
- Keep timeline fallback as secondary/history and prevent duplicate incoming UI.
- Keep answer-time foreground authority as the only path that can allow media later.
- Add redacted diagnostics for connect, ready, invite received, validation result, disconnect, retry, and fallback.
- Add tests with a fake SSE stream/client boundary.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, or project settings.
- Do not replace Element Call routing.
- Do not bypass server-issued media credential authority.
- Do not connect media from invite receipt.
- Do not emit Matrix call events from invite receipt.
- Do not add raw account, room, device, event, auth credential, push/media, Apple signing, media-session, track, participant, private runtime log, or credential-shaped fixture values.
- Keep logs/docs redacted.

Expected output:
- Disabled-by-default iOS foreground signaling SSE transport.
- Tests for valid invite, malformed invite, stale invite, duplicate invite, stream disconnect, retry state, and no media side effects.
- Updated docs/status/worklog/next prompt.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
