# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42c-foreground-signaling-server-contract

Next phase: 2.42C - foreground signaling server endpoint contract.

Goal:
Define and prove the server endpoint contract required by the 2.42B foreground signaling transport prototype before wiring a production client transport.

Context:
- Element Call room-list/timeline delivery can still delay repeat incoming calls by 10-30 seconds.
- 2.42A added a foreground invite signal contract, validator, handler, and fail-closed tests.
- 2.42B added a disabled/default transport boundary, in-memory transport, transport diagnostics, and a pipeline that feeds safe invite events into the existing handler.
- 2.42B intentionally did not add production WebSocket/SSE transport or hardcoded server URLs.

Scope:
- Define authenticated foreground call-signaling endpoint shape.
- Define device/session-scoped subscription semantics.
- Define minimal opaque invite payload schema.
- Define expiry, stale invalidation, duplicate handling, and acknowledgement behavior.
- Define answer, decline, and end acknowledgement model.
- Define reconnect/retry/backoff expectations.
- Define redacted client/server observability and alert-worthy states.
- Keep timeline call cards as secondary/history.
- Keep media credential endpoint as final authority after answer.

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
- Server endpoint contract and payload schema.
- Client transport expectations for auth, reconnect, stale handling, duplicate suppression, and acknowledgement.
- Redacted diagnostics and operational alert states.
- Tests or docs-only proof depending on endpoint readiness.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
