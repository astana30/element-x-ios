# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47D credentials cleanup / expiry proof is physically closed as a DEBUG-only no-connect proof.

Final proof:

```text
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
callkit_first_action_kind=answer
callkit_answer_action_delivered=true
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
foreground_call_state=real_invite_pending_media
foreground_pending_call_metadata_handoff_observed=true
foreground_pending_call_metadata_source=authenticated_pending_metadata_fetch
foreground_pending_call_metadata_has_call_identifier=true
foreground_pending_call_metadata_has_room_binding=true
foreground_pending_call_metadata_has_peer=true
foreground_pending_call_metadata_direction=incoming
foreground_pending_call_metadata_intent=audio
media_credentials_request_metadata_available=true
media_credentials_boundary_reached=true
media_credentials_requested=true
media_credentials_request_authorized=true
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_token_redacted=true
media_credentials_url_received=true
media_credentials_url_redacted=true
media_credentials_expires_at_present=true
media_credentials_payload_redacted=true
media_credentials_cleanup_requested=true
media_credentials_cleanup_result=cleared
media_credentials_post_cleanup_token_present=false
media_credentials_post_cleanup_url_present=false
media_credentials_post_cleanup_expires_at_present=false
media_credentials_post_cleanup_payload_present=false
media_credentials_reuse_attempted=false
media_credentials_reuse_allowed=false
media_credentials_expiry_reference_present=true
media_credentials_expiry_check_requested=true
media_credentials_expiry_check_result=expired_or_not_reusable_redacted
media_credentials_token_request_seen=true
media_credentials_token_http_status_bucket=2xx
media_credentials_token_reason=issued
media_credentials_eligibility_allowed=true
media_credentials_rate_limited=false
media_credentials_allocation_attempted=true
media_credentials_livekit_room_precreate_attempted=true
media_credentials_token_issued=true
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

No APNs was sent after the passing proof. No production APNs, repeated APNs, `dev/invite`, media connect, LiveKit join, microphone/camera permission request, Matrix event emission, full call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, or forbidden project/signing file change was introduced.

## Next Task

Start 2.47E — server-side allocation/token expiry verification, no LiveKit join.

Goal:
- Verify server-issued controlled media credentials expire or become non-reusable server-side.
- Verify allocation/token cleanup behavior with redacted diagnostics only.
- Use server/direct tests before any physical path.
- Do not connect media.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full call flow.

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
