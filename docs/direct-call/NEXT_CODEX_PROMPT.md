# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry1-RemoteMissingTriage` is complete.

The one-shot physical proof sent exactly one sandbox APNs after explicit confirmation, then stopped sending. The receiver operator pressed green Answer once.

APNs/send result:

```text
invite_send_attempted=true
invite_http_code=200
real_non_dev_invite_used=true
dev_invite_used=false
background_apns_push_result=sandbox_success
APNs_sent=true
```

Receiver PushKit, CallKit Answer, pending metadata, media credentials, one controlled receiver connect, and receiver LiveKit join succeeded:

```text
proof_generation=generation_16
physical_voip_push_received=true
pushkit_callback_invoked=true
callkit_report_result=reported
callkit_first_action_kind=answer
callkit_answer_action_received=true
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
media_credentials_requested=true
media_credentials_result=success_redacted
physical6_runtime_enablement_url_hook_consumed=true
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=success_redacted
media_connect_requested=true
media_connect_attempted=true
livekit_join_requested=true
livekit_connect_audio_invoked=true
livekit_join_result=success_redacted
```

Physical remote-peer context survived PushKit and Answer:

```text
remote_peer_context_handoff_present=true
remote_peer_context_handoff_armed_before_apns=true
remote_peer_context_handoff_received_by_runtime=true
remote_peer_context_handoff_survived_pushkit=true
remote_peer_context_handoff_survived_answer=true
remote_peer_kind=physical_ios_redacted
remote_peer_physical_device=true
production_like_two_physical_device_proof=true
```

But the final proof did not preserve the sender readiness hook that had been armed before APNs:

```text
sender_livekit_readiness_hook_armed=false
sender_livekit_readiness_hook_matrix_session_ready=false
sender_livekit_readiness_hook_expected_user_matched=false
sender_livekit_readiness_hook_same_room_ready=false
sender_livekit_readiness_hook_blocked_reason=default_disabled_no_connect
second_physical_sender_livekit_readiness_matrix_session_ready=false
second_physical_sender_livekit_readiness_same_room_ready=false
```

Remote participant/audio/liveness was safely not observed:

```text
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_error_bucket=sender_not_joined_or_remote_missing_redacted
receiver_remote_participant_observer_remote_seen=false
receiver_remote_participant_observer_audio_track_seen=false
receiver_remote_participant_observer_liveness_seen=false
livekit_remote_participant_seen=false
livekit_remote_audio_track_subscribed=false
livekit_audio_liveness_result=not_observed_redacted
livekit_audio_liveness_error_bucket=remote_participant_missing_redacted
```

Safety stayed closed:

```text
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
blocked_reason=none
```

Classification:

```text
2.48Z-Physical2-Retry1 = receiver controlled audio join succeeded once, but sender readiness/join was not preserved into final proof and remote participant/audio/liveness was not observed.
No retry performed.
No repeated APNs.
No repeated connect.
```

## Next Phase

`2.48Z-SenderReadinessPersistenceRepair — preserve sender readiness and add sender join result proof before any APNs retry`

This is a code/test diagnostics repair only.

Do not send APNs. Do not run production APNs. Do not run repeated APNs. Do not use `dev/invite`. Do not start physical media connect. Do not join LiveKit on a real device. Do not request microphone/camera permission. Do not enable video. Do not emit Matrix events. Do not start full call flow.

## Goal

Fix the proof/runtime boundary shown by Physical2-Retry1:

```text
pre_apns_sender_livekit_readiness_hook_armed=true
pre_apns_sender_livekit_readiness_hook_matrix_session_ready=true
pre_apns_sender_livekit_readiness_hook_same_room_ready=true

final_sender_livekit_readiness_hook_armed=false
final_sender_livekit_readiness_hook_matrix_session_ready=false
final_sender_livekit_readiness_hook_same_room_ready=false
```

The repair should make sender readiness persistence explicit across PushKit and Answer, without starting a real sender join during the repair phase.

Also add or complete sender-side join result proof fields so the next physical proof can distinguish:

```text
sender_side_livekit_join_present=true
sender_side_livekit_join_debug_only=true
sender_side_livekit_join_default_disabled=true
sender_side_livekit_join_armed=<redacted_bool>
sender_side_livekit_join_requested=<redacted_bool>
sender_side_livekit_join_attempted=<redacted_bool>
sender_side_livekit_join_result=<success_redacted_or_not_requested_or_failed_redacted_or_blocked_redacted>
sender_side_livekit_join_error_bucket=<none_or_redacted_bucket>
sender_side_livekit_join_audio_only=true
sender_side_livekit_join_video_allowed=false
sender_side_livekit_join_matrix_events_allowed=false
sender_side_livekit_join_raw_credentials_logged=false
```

Preserve default runtime no-connect/no-join. The sender join path must remain default-disabled unless a future one-shot physical proof explicitly arms it.

## Required Checks

Run:

```bash
swiftformat ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
swiftlint lint ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift UnitTests/Sources/DirectCallEngineTests.swift
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run a privacy scan over changed files/diff. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.
