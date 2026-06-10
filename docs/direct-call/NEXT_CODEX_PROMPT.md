# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42d-foreground-signaling-server-endpoint

Next phase: 2.42D - foreground signaling server endpoint prototype.

Goal:
Implement or mock the call-service endpoint contract needed by the 2.42B foreground signaling transport before wiring a production app transport.

Context:
- Element Call room-list/timeline delivery can still delay repeat incoming calls by 10-30 seconds.
- 2.42A added a foreground invite signal contract, validator, handler, and fail-closed tests.
- 2.42B added a disabled/default transport boundary, in-memory transport, transport diagnostics, and a pipeline that feeds safe invite events into the existing handler.
- 2.42C inspected the current call-service and found no foreground invite subscription, fanout, acknowledgement, stale invalidation, reconnect/resume, or app endpoint configuration.
- The existing call-service still only exposes redacted health/readiness, native audio eligibility, server-issued media credential allocation, and local fake capability discovery.

Scope:
- Add a server endpoint prototype or a fully mocked endpoint contract in `server/salemx-call-service`.
- Keep the endpoint authenticated and foreground-only.
- Define device/session-scoped subscription semantics.
- Emit only minimal opaque invite payloads.
- Define expiry, stale invalidation, duplicate handling, and acknowledgement behavior.
- Define reconnect/retry/resume expectations.
- Define redacted server and client diagnostics.
- Keep timeline call cards as secondary/history.
- Keep the media credential endpoint as final authority after answer.
- Do not wire a production app transport until the server endpoint contract is proven.

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
- Server endpoint prototype or explicit mocked contract.
- Safe payload schema and acknowledgement model.
- Tests for malformed, stale, duplicate, terminal, and valid invite behavior.
- Redacted diagnostics and operational alert states.
- Updated docs/status/worklog/next prompt.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
