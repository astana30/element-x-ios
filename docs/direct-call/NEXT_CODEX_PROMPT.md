# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47C6 is committed as a targeted server fix for the pending metadata fetch `403 M_FORBIDDEN` blocker.

Root cause:
- Pending metadata was stored against the invite's requested receiver device.
- The real invite/APNs path sends to the latest receiver PushKit token for the receiver account.
- If the requested device is stale, APNs can still deliver to the physical receiver through the latest token, while the receiver's authenticated metadata fetch is denied.

Fix:
- Keep exact receiver-device binding only when the requested device token record is the same latest development PushKit token record APNs will use.
- Otherwise bind pending metadata to the receiver account.
- Wrong users remain forbidden; the exact-device path still forbids different receiver devices when the exact token is current.

No APNs was sent for the fix. No production APNs, repeated APNs, `dev/invite`, media connect, LiveKit join, microphone/camera permission request, Matrix event emission, full call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, or forbidden project/signing file change was introduced.

## Next Task

Start 2.47C6 physical close-out after the server fix is deployed. Run one controlled no-connect proof only.

Expected metadata proof:

```text
pending_metadata_fetch_result=success_redacted
foreground_pending_call_metadata_handoff_observed=true
foreground_pending_call_metadata_source=authenticated_pending_metadata_fetch
foreground_pending_call_metadata_has_call_identifier=true
foreground_pending_call_metadata_has_room_binding=true
foreground_pending_call_metadata_has_peer=true
foreground_pending_call_metadata_direction=incoming
foreground_pending_call_metadata_intent=audio
media_credentials_request_metadata_available=true
media_credentials_requested=true
media_credentials_token_request_seen=true
```

Expected credentials target after metadata succeeds:

```text
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
