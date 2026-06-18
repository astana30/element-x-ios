# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47B4 defines the authenticated pending metadata source needed before requesting real media credentials from the PushKit-controlled Answer path.

Implemented:
- real non-dev invite can create pending call metadata server-side from authenticated input
- server stores real call/room/peer metadata behind an opaque reference
- VoIP APNs payload carries only the opaque metadata reference and redaction proof
- authenticated pending-metadata fetch returns metadata only to the intended receiver/device before expiry
- iOS VoIP receipt proof records only metadata-reference/fetch booleans

Validation:
- server compileall passed
- full call-service tests passed: `154 passed`
- changed-file SwiftFormat passed
- changed-file SwiftLint passed with only the existing file-length warning
- targeted DirectCall tests passed: `38 tests`
- no APNs was sent for this code checkpoint

## Next Task

Start 2.47B5: wire the iOS PushKit-controlled Answer path to fetch authenticated pending metadata using the APNs opaque reference.

Goal:
- after `callkit_answer_action_received=true`, fetch pending metadata with existing app authentication
- record only redacted booleans/classes in `Documents/salemx-voip-push-receipt-proof.txt`
- build/observe the foreground pending metadata handoff from the fetched metadata
- reach `media_credentials_request_metadata_available=true`
- do not request real media credentials yet unless explicitly authorized

Expected proof:
```text
pending_metadata_reference_present=true
pending_metadata_fetch_required=true
pending_metadata_fetch_requested=true
pending_metadata_fetch_result=success_redacted
foreground_pending_call_metadata_handoff_observed=true
foreground_pending_call_metadata_source=authenticated_pending_metadata
foreground_pending_call_metadata_has_call_identifier=true
foreground_pending_call_metadata_has_room_binding=true
foreground_pending_call_metadata_has_peer=true
foreground_pending_call_metadata_direction=incoming
foreground_pending_call_metadata_intent=audio
media_credentials_request_metadata_available=true
media_credentials_requested=false
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
