# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47B2 code is implemented as a DEBUG-only controlled media credentials request using the real foreground `DirectCallSession` metadata handoff.

Implemented:
- request credentials through the existing `DirectCallLiveKitTokenProvider` boundary after `foreground_call_state=real_invite_pending_media`
- record only redacted success/block proof fields
- redact token request/response descriptions, including call ID, room ID, peer/user metadata, token, URL, and allocation identifiers
- keep `media_connect_requested=false`, `media_connect_attempted=false`, `livekit_join_requested=false`, `matrix_event_emit_requested=false`, and `real_call_flow_started=false`

Validation so far:
- changed-file SwiftFormat passed
- changed-file SwiftLint passed with only existing file-length warnings
- targeted DirectCall test build compiled, then simulator launch failed with the known `FBSOpenApplicationServiceErrorDomain / SBMainWorkspace` environment issue
- no APNs was sent for the code checkpoint

## Next Task

Run 2.47B2 physical validation.

Goal:
- install a fresh Debug build
- run PushKit upload smoke
- run exactly one real non-dev invite/APNs attempt
- tap Answer if CallKit UI appears
- read `Documents/salemx-voip-push-receipt-proof.txt`

Expected success proof:
```text
media_credentials_boundary_reached=true
media_credentials_requested=true
media_credentials_request_authorized=true
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_token_redacted=true
media_credentials_url_received=true
media_credentials_url_redacted=true
media_credentials_payload_redacted=true
media_credentials_local_persistence_requested=false
media_credentials_cleanup_requested=true
media_credentials_cleanup_result=cleared
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

If blocked:
```text
media_credentials_boundary_reached=true
media_credentials_requested=true
media_credentials_result=blocked_redacted
blocked_reason=<redacted_reason>
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
