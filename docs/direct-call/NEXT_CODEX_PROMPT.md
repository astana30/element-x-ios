# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42i-supervised-foreground-sse-physical-smoke

Next phase: 2.42I - supervised foreground SSE physical smoke.

Goal:
Run a supervised foreground SSE smoke using the DEBUG/dev runtime owner, a local or staging call-service stream, and the disabled-by-default dev invite route.

Context:
- 2.42D added the authenticated call-service foreground SSE stream endpoint.
- 2.42E added the disabled/configured iOS SSE transport client boundary.
- 2.42F added the disabled-by-default supervised dev invite source.
- 2.42G documented supervised smoke wiring.
- 2.42H added `DebugForegroundCallSignalingSSERuntimeOwner`.
- The DEBUG owner starts only when explicitly enabled and an authenticated session is available.
- The owner does not construct URLs, auth headers, credentials, or production configuration.

Scope:
- Start the call-service in local or staging supervision.
- Enable the dev invite route only for the supervised window.
- Inject a safe `URLRequest` into the iOS SSE stream setup.
- Start the DEBUG foreground SSE runtime owner while the callee app is foreground.
- Submit one safe opaque dev invite from the same active callee session.
- Confirm redacted diagnostics:
  - `sse_configured=true`
  - `sse_started=true`
  - `sse_connected=true`
  - `invite_received=true`
  - `invite_valid=true`
  - `incoming_requested=true`
  - `fallback_deduped` result if timeline fallback later appears
- Confirm invite receipt does not request media credentials, connect media, or emit Matrix events.
- Keep full runtime logs out of docs.

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
- Redacted physical smoke report.
- Timing for SSE connect, invite receipt, and incoming/CallKit request.
- Whether fallback de-duplication occurred.
- Whether media credential request and media connection stayed blocked before answer.
- Updated docs/status/worklog/next prompt.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
