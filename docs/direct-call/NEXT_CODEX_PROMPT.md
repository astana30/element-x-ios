# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42h-debug-foreground-sse-runtime-owner

Next phase: 2.42H - DEBUG foreground SSE runtime owner.

Goal:
Add the smallest disabled-by-default DEBUG/dev runtime owner needed to start and stop the iOS foreground SSE transport for a supervised physical-device smoke.

Context:
- 2.42D added the authenticated call-service foreground SSE stream endpoint.
- 2.42E added the disabled/configured iOS SSE transport client boundary.
- 2.42F added the disabled-by-default supervised dev invite source.
- 2.42G documented the smoke wiring and confirmed that no app runtime owner exists yet.
- The iOS transport already requires an injected `URLRequest` and does not hardcode server URLs or auth headers.

Scope:
- Add a DEBUG/dev-only runtime owner or harness that can start and stop the existing foreground SSE transport.
- Keep default production behavior disabled.
- Provide safe endpoint/request injection without hardcoded production URLs or credential values.
- Surface redacted diagnostics only:
  - `sse_configured`
  - `sse_connected`
  - `invite_received`
  - `invite_valid`
  - `incoming_requested`
- Feed valid invites into the existing foreground incoming/CallKit request abstraction.
- Coordinate with timeline/room-list fallback to avoid duplicate incoming UI where possible.
- Keep answer-time server-issued media credential authority as the only path that may allow media later.

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
- Minimal DEBUG/dev-only runtime owner or documented blocker if no safe owner can be added.
- Tests for disabled default, configured start/stop, safe diagnostics, valid invite forwarding, and no media side effects.
- Updated docs/status/worklog/next prompt.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
