# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47C5 is committed as a DEBUG-only pending metadata fetch diagnostic fix. The previous physical proof reached real invite/APNs/PushKit/CallKit Answer with `pending_metadata_reference_present=true`, but pending metadata fetch returned `pending_metadata_fetch_result=blocked_redacted` and `blocked_reason=pending_metadata_fetch_http_failure_redacted` before foreground pending metadata handoff.

Proven:
- iOS stores the opaque `pending_metadata_reference` from the real-invite VoIP payload.
- After CallKit Answer, iOS requests authenticated pending metadata with existing app auth.
- The deployed pending metadata route is covered: unauthenticated `/foreground-signaling/pending-metadata/{reference}` returns auth-gated `401`, not `404`.
- Server route tests prove valid receiver auth can fetch stored metadata in-process and wrong-user fetch returns `403`.
- iOS proof now records redacted pending metadata fetch diagnostics:
  - `pending_metadata_fetch_http_status_bucket`
  - `pending_metadata_fetch_errcode`
  - `pending_metadata_fetch_failure_reason`
- Media connection, LiveKit join, microphone/camera permission request, Matrix event emission, and full call flow remain blocked.

## Next Task

Start 2.47C5 physical close-out: run one controlled no-connect proof to classify the pending metadata fetch result. Do not repeat APNs if the fetch remains blocked.

Required proof fields:

```text
pushkit_payload_kind=real_invite_controlled
callkit_first_action_kind=answer
callkit_answer_action_delivered=true
pending_metadata_reference_present=true
pending_metadata_fetch_required=true
pending_metadata_fetch_requested=true
pending_metadata_fetch_authorized=true
pending_metadata_fetch_result=success_redacted OR blocked_redacted
pending_metadata_fetch_http_status_bucket=2xx/400/401/403/404/429/5xx/other_redacted/network_failure/unknown
pending_metadata_fetch_errcode=none OR M_UNKNOWN_TOKEN OR M_FORBIDDEN OR M_NOT_FOUND OR M_UNRECOGNIZED
pending_metadata_fetch_failure_reason=none OR auth_rejected OR forbidden OR not_found OR server_error OR network_failure OR payload_invalid OR http_error_redacted
pending_metadata_payload_redacted=true
foreground_pending_call_metadata_handoff_observed=true/false
foreground_pending_call_metadata_source=authenticated_pending_metadata_fetch
foreground_pending_call_metadata_has_call_identifier=true/false
foreground_pending_call_metadata_has_room_binding=true/false
foreground_pending_call_metadata_has_peer=true/false
media_credentials_request_metadata_available=true/false
media_credentials_boundary_reached=true
media_credentials_requested=true/false
media_credentials_token_request_seen=true/false
media_credentials_token_http_status_bucket=2xx/400/401/403/404/429/5xx/other_redacted/unknown/not_requested
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
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
