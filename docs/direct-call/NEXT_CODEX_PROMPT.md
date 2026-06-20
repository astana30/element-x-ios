# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47C7 is committed as a targeted server fix for the media credentials `eligibilityRejected` blocker.

Latest physical proof before the fix:
- APNs sandbox, PushKit, CallKit report, Answer, foreground pending state, pending metadata fetch, and metadata handoff all passed.
- The token request reached the server and failed safely with:

```text
media_credentials_token_http_status_bucket=403
media_credentials_token_reason=eligibilityRejected
media_credentials_eligibility_allowed=false
media_credentials_allocation_attempted=false
media_credentials_livekit_room_precreate_attempted=false
media_credentials_token_issued=false
blocked_reason=media_credentials_request_failed_redacted
```

Root cause:
- Incoming receiver credentials requests authenticate as the receiver.
- Pending metadata correctly sets `peer_user_id` to the caller.
- The static eligibility policy required that caller peer's exact user ID to be allowlisted, even though the encrypted 1:1 room validation already proves the peer relationship.

Fix:
- Keep the authenticated receiver account allowlist gate.
- Keep encrypted 1:1 room validation.
- For incoming direction, accept the room-validated peer without requiring the peer exact user ID in the static user allowlist.
- Keep configured homeserver allowlists applied to the incoming peer homeserver.

No APNs was sent for this fix. No production APNs, repeated APNs, `dev/invite`, media connect, LiveKit join, microphone/camera permission request, Matrix event emission, full call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, or forbidden project/signing file change was introduced.

## Next Task

Start 2.47C7 physical close-out after the server fix is deployed. Run one controlled no-connect proof only.

Expected success:

```text
pending_metadata_fetch_result=success_redacted
foreground_pending_call_metadata_handoff_observed=true
media_credentials_request_metadata_available=true
media_credentials_requested=true
media_credentials_request_authorized=true
media_credentials_token_request_seen=true
media_credentials_token_http_status_bucket=2xx
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_url_received=true
media_credentials_expires_at_present=true
blocked_reason=none
```

Safety must remain:

```text
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Do not:
- use `dev/invite`
- send production APNs
- repeat APNs
- connect media
- join LiveKit
- request microphone/camera permissions
- emit Matrix events
- start full call flow
- expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- touch project/signing/entitlement/`Info.plist`/`app.yml` files
