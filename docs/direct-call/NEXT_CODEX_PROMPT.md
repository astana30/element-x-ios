# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-PreAPNsSenderReadinessBlocked` is complete.

Both physical iPhones were installed and launched from the repaired Debug build at:

```text
1af50e240a3bc5e99d1160fe8db2781c46940f94
Add remote participant presence repair diagnostics
```

Receiver app session validated:

```text
receiver_iphone_matrix_session_whoami_result=success_redacted
receiver_iphone_matrix_session_user_hash=497015f5745c933a
receiver_iphone_pending_metadata_auth_ready=true
APNs_sent=false
blocked_reason=none
```

Second physical sender app session validated:

```text
second_physical_device_matrix_session_whoami_result=success_redacted
second_physical_device_matrix_session_user_hash=7d434d7f252427fb
second_physical_device_matrix_session_user_hash_matches_expected=true
second_physical_device_pending_metadata_auth_ready=true
APNs_sent=false
blocked_reason=none
```

Receiver hooks armed without side effects:

```text
physical6_runtime_enablement_url_hook_armed=true
physical6_runtime_enablement_url_hook_audio_only=true
physical6_runtime_enablement_url_hook_video_allowed=false
physical6_runtime_enablement_url_hook_matrix_events_allowed=false
physical6_runtime_enablement_url_hook_consumed=false
physical6_runtime_enablement_url_hook_blocked_reason=armed_waiting_for_one_incoming_answer

remote_peer_context_handoff_armed_before_apns=true
remote_peer_context_handoff_received_by_runtime=false
remote_peer_kind=physical_ios_redacted
remote_peer_physical_device=true
simulator_assisted_remote_audio_proof=false
production_like_two_physical_device_proof=true
second_device_remote_audio_readiness=ready_redacted
```

The pre-APNs sender readiness gate was not satisfied:

```text
remote_participant_presence_repair_present=true
second_physical_sender_livekit_readiness_present=true
second_physical_sender_livekit_readiness_matrix_session_ready=false
second_physical_sender_livekit_readiness_same_room_ready=false
second_physical_sender_livekit_join_path_present=true
second_physical_sender_livekit_join_path_audio_only=true
second_physical_sender_livekit_join_path_video_allowed=false
second_physical_sender_livekit_join_path_matrix_events_allowed=false
```

Classification:

```text
2.48Z-Physical2 = pre-APNs sender LiveKit readiness safely blocked
sender readiness result=not_ready_redacted
APNs_sent=false
invite_send_attempted=false
receiver_media_connect_attempted=false
receiver_livekit_join_requested=false
sender_livekit_join_attempted=false
receiver_remote_participant_observer_result=not_started_redacted
remote_audio_liveness_result=not_requested
no retry performed
```

No APNs, production APNs, repeated APNs, `dev/invite`, media connect, LiveKit join, microphone/camera permission, video, Matrix event emit, or full call flow was performed.

## Next Phase

`2.48Z-SenderLiveKitReadinessHookRepair — make second physical sender readiness/join path activatable before any APNs retry`

This is a code/test diagnostics repair only.

Do not send APNs. Do not run production APNs. Do not use `dev/invite`. Do not run physical media connect. Do not join LiveKit on a real device. Do not request microphone/camera permission. Do not enable video. Do not emit Matrix events. Do not start full call flow.

## Goal

Repair the DEBUG-only second physical sender readiness/join boundary so a future `2.48Z-Physical2-Retry` can determine, before APNs, whether the sender app session and room readiness are available and whether the sender join path is explicitly armed.

The repair should preserve default no-connect and no-join behavior. It should not start a real sender LiveKit join during the repair phase.

## Required Behavior

Add or adjust the redacted proof surface so the future physical proof can distinguish:

```text
second_physical_sender_livekit_readiness_present=true
second_physical_sender_livekit_readiness_debug_only=true
second_physical_sender_livekit_readiness_default_disabled=true
second_physical_sender_livekit_readiness_matrix_session_ready=<true_or_false>
second_physical_sender_livekit_readiness_same_room_ready=<true_or_false>
second_physical_sender_livekit_readiness_credentials_ready=false
second_physical_sender_livekit_join_path_present=true
second_physical_sender_livekit_join_path_default_disabled=true
second_physical_sender_livekit_join_path_audio_only=true
second_physical_sender_livekit_join_path_video_allowed=false
second_physical_sender_livekit_join_path_matrix_events_allowed=false
second_physical_sender_livekit_join_path_raw_credentials_logged=false
second_physical_sender_livekit_join_path_armed=<true_or_false>
second_physical_sender_livekit_join_path_consumed=false
second_physical_sender_livekit_join_path_blocked_reason=<redacted_bucket>
```

The future physical helper must be able to stop before APNs when sender readiness is false, without relying on stale post-PushKit receiver state.

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
