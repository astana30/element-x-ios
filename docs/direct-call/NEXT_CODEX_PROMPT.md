# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47C controlled real media credentials request is physically closed as a no-connect proof.

Final proof:

```text
pending_metadata_fetch_result=success_redacted
foreground_pending_call_metadata_handoff_observed=true
media_credentials_request_metadata_available=true
media_credentials_boundary_reached=true
media_credentials_requested=true
media_credentials_request_authorized=true
media_credentials_token_request_seen=true
media_credentials_token_http_status_bucket=2xx
media_credentials_token_reason=issued
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_url_received=true
media_credentials_expires_at_present=true
media_credentials_cleanup_requested=true
media_credentials_cleanup_result=cleared
blocked_reason=none
```

Safety remained:

```text
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

No production APNs, repeated APNs, `dev/invite`, media connect, LiveKit join, microphone/camera permission request, Matrix event emission, full call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, or forbidden project/signing file change was introduced.

## Next Task

Start 2.47D — credentials cleanup / expiry proof.

Goal:
- Prove issued credentials are not persisted locally beyond the controlled no-connect proof.
- Prove cleanup clears the in-memory credential material.
- Prove expiry metadata is present and bounded.
- Do not connect media.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full call flow.

Expected proof direction:

```text
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_url_received=true
media_credentials_expires_at_present=true
media_credentials_expiry_bounded=true
media_credentials_local_persistence_requested=false
media_credentials_cleanup_requested=true
media_credentials_cleanup_result=cleared
media_credentials_post_cleanup_token_available=false
media_credentials_post_cleanup_url_available=false
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
