# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47C code is committed as a DEBUG-only no-connect credentials request checkpoint. After authenticated pending metadata fetch succeeds, the PushKit-controlled Answer proof path requests media credentials through the existing `DirectCallLiveKitTokenProvider` boundary and records only redacted token/URL/result proof. Physical 2.47C proof has not run yet.

Proven:
- iOS stores the opaque `pending_metadata_reference` from the real-invite VoIP payload
- after CallKit Answer, iOS requests authenticated pending metadata with existing app auth
- fetched metadata is reduced to redacted handoff proof booleans/classes
- `media_credentials_request_metadata_available=true`
- code now attempts the controlled media credentials request after metadata success
- media connection, LiveKit join, microphone/camera permission request, Matrix event emission, and full call flow remain blocked

Validation:
- changed-file SwiftFormat passed
- changed-file SwiftLint passed with only the existing file-length warning
- targeted DirectCall tests passed: `38 tests`
- no APNs was sent for this code checkpoint

## Next Task

Start 2.47C physical close-out: controlled real media credentials request, no-connect.

Goal:
- install a fresh Debug build from the current branch
- run PushKit upload smoke and confirm it is green
- run exactly one authenticated real non-dev invite/APNs attempt
- tap Answer once if CallKit UI appears
- verify the dedicated VoIP receipt proof records redacted credentials success or a redacted blocker
- do not connect media, join LiveKit, request microphone/camera, emit Matrix events, or start full call flow

Expected proof:
```text
pushkit_payload_kind=real_invite_controlled
callkit_first_action_kind=answer
callkit_answer_action_delivered=true
pending_metadata_reference_present=true
pending_metadata_fetch_required=true
pending_metadata_fetch_requested=true
pending_metadata_fetch_authorized=true
pending_metadata_fetch_result=success_redacted
pending_metadata_payload_redacted=true
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
media_credentials_local_persistence_requested=false
media_credentials_cleanup_requested=true
media_credentials_cleanup_result=cleared
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

Safety:
- do not use `dev/invite`
- do not send production APNs
- do not repeat APNs
- do not connect media
- do not join LiveKit
- do not request microphone/camera
- do not emit Matrix events
- do not start full call flow
- do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- do not touch project/signing/entitlement/`Info.plist`/`app.yml` files
