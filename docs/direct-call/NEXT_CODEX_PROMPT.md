# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-RealSenderRuntimeJoinRepair` is complete as a code/test phase.

The previous sender-side LiveKit DEBUG URL was only proof-recorder driven and must not be used as runtime evidence. It now no longer accepts query-provided join result, transport result, error bucket, or timeline outcome as proof of SDK behavior.

New runtime path:

```text
DEBUG-only
default-disabled
one-shot
separate sender proof file:
Documents/salemx-sender-runtime-livekit-join-proof.txt
```

The new sender runtime bridge:

```text
uses the sender app's restored Matrix session
uses the opaque pending_metadata_reference
fetches sender pending metadata from authenticated /sender projection
requests real sender media credentials
builds a redacted E2EE context
invokes shared DirectCallLiveKitConnectExecutor
records runtime-derived success/failure only
```

Safety preserved during this repair:

```text
APNs_sent=false
dev_invite_used=false
production_APNs_sent=false
physical_media_connect_performed=false
physical_livekit_join_performed=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
raw URL/token/room/call/user/device IDs logged=false
```

## Next Phase

`2.48Z-Physical2-Retry13 — one-shot real sender runtime join proof`

Goal:
Run one physical two-device proof where the receiver path completes real invite/APNs/PushKit/CallKit Answer and the sender app uses the new runtime bridge to perform the actual sender-side LiveKit join through `DirectCallLiveKitConnectExecutor`.

Required preflight:

```text
receiver_iphone_matrix_session_whoami_result=success_redacted
receiver_iphone_pending_metadata_auth_ready=true
second_physical_device_matrix_session_whoami_result=success_redacted
second_physical_device_pending_metadata_auth_ready=true
room_validation_preflight=pass
sender_connect_executor_unification_present=true
sender_runtime_join_bridge_present=true
sender_runtime_join_bridge_default_disabled=true
sender_runtime_join_bridge_one_shot=true
sender_runtime_join_query_outcome_ignored=true
safe_to_send_apns=true
```

Receiver proof must still show:

```text
physical_voip_push_received=true
callkit_first_action_kind=answer
pending_metadata_fetch_result=success_redacted
media_credentials_result=success_redacted
controlled_connect_first_attempt_result=success_redacted
livekit_join_result=success_redacted
```

Sender proof must come from:

```text
Documents/salemx-sender-runtime-livekit-join-proof.txt
```

Expected sender proof fields:

```text
proof_source=sender_runtime_livekit_join
sender_runtime_join_bridge_triggered=true
sender_runtime_join_bridge_consumed=true
sender_runtime_join_bridge_repeated=false
sender_runtime_join_uses_restored_matrix_session=true
sender_runtime_join_pending_metadata_reference_present=true
sender_runtime_join_pending_metadata_reference_redacted=true
sender_runtime_join_pending_metadata_fetch_requested=true
sender_runtime_join_pending_metadata_fetch_authorized=true
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_metadata_direction=outgoing
sender_runtime_join_metadata_intent=audio
sender_runtime_join_credentials_requested=true
sender_runtime_join_credentials_authorized=true
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_token_received=true
sender_runtime_join_token_redacted=true
sender_runtime_join_url_received=true
sender_runtime_join_url_redacted=true
sender_runtime_join_executor_shared=true
sender_runtime_join_executor_invoked=true
sender_runtime_join_runtime_derived=true
sender_runtime_join_query_outcome_ignored=true
sender_runtime_join_audio_only=true
sender_runtime_join_video_allowed=false
sender_runtime_join_matrix_events_allowed=false
```

Success still requires receiver-side remote participant/audio/liveness observation:

```text
receiver_remote_participant_observer_result=success_redacted
livekit_remote_participant_seen=true
livekit_remote_audio_track_subscribed=true
livekit_audio_liveness_result=success_redacted
```

If runtime join fails, classify using only runtime-derived sender proof fields and do not retry automatically.

## Hard Limits

Do not:

* send APNs until explicit one-shot confirmation
* run production APNs
* run repeated APNs
* run `dev/invite`
* repeat receiver connect
* repeat sender LiveKit join
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw SDK error/localized SDK error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`
