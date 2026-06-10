# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42b-foreground-call-signaling-server-contract

Next phase: 2.42B - foreground call signaling server contract.

Goal:
Define and prove the server-side contract required by the 2.42A foreground call signaling channel prototype before adding any production client transport.

Context:
- 2.41G-A4/A5 proved the current-room fast path can request incoming/CallKit, but only after the call event is already delayed.
- 2.41G-A6 found no safe existing app-side source earlier than Matrix sync, timeline materialization, or room-summary updates while PushKit/APNs/background remain out of scope.
- 2.42A added an inert foreground signaling client boundary with `ForegroundCallInviteSignal`, validator, handler, duplicate/stale/terminal guards, redacted diagnostics, and unit coverage.
- 2.42A intentionally did not add a production WebSocket or other network transport.

Scope:
- Design the authenticated foreground call-signaling API.
- Define device/session-scoped subscription behavior.
- Define minimal opaque invite payloads.
- Define invite expiry, stale invalidation, duplicate handling, and acknowledgement behavior.
- Define redacted server/client observability.
- Keep answer and media credential authority separate.
- Keep timeline call cards as secondary/history.
- Add client/server contract tests or docs-only proof if no endpoint is ready.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, or project settings.
- Do not replace Element Call routing.
- Do not bypass server-issued media credential authority.
- Do not connect media from invite receipt.
- Do not add raw account, room, device, event, auth credential, push/media, Apple signing, media-session, track, participant, private runtime log, or credential-shaped fixture values.
- Keep logs/docs redacted.

Expected output:
- Server contract for the foreground signaling channel.
- Payload shape and validation rules.
- Client retry/reconnect/stale handling expectations.
- Redacted diagnostics and alert-worthy states.
- Tests or docs-only proof, depending on endpoint readiness.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
