# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-Physical2-Retry6-SenderTransportErrorSourceTriage` is complete.

This was a one-shot two-physical-device proof. One sandbox APNs was already sent after explicit confirmation and must not be repeated. Receiver PushKit, CallKit Answer, pending metadata, media credentials, one receiver controlled audio connect, and receiver LiveKit join succeeded. Sender-side join activation triggered and consumed exactly once, then safely classified the sender transport failure through the repaired redacted transport error surface.

Proof path:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry6-sender-transport-error-source-polled.txt
```

Receiver path:

```text
proof_generation=generation_22
physical_voip_push_received=true
pushkit_callback_invoked=true
pushkit_payload_kind=real_invite_controlled
callkit_report_result=reported
callkit_first_action_kind=answer
callkit_answer_action_received=true
callkit_answer_action_fulfilled=true
pending_metadata_fetch_result=success_redacted
pending_metadata_fetch_http_status_bucket=2xx
media_credentials_requested=true
media_credentials_result=success_redacted
controlled_connect_first_attempt_completed=true
controlled_connect_first_attempt_repeated=false
controlled_connect_first_attempt_result=success_redacted
livekit_join_result=success_redacted
```

Sender transport classification:

```text
sender_side_livekit_join_activation_triggered=true
sender_side_livekit_join_activation_consumed=true
sender_side_livekit_join_activation_repeated=false
sender_side_livekit_join_requested=true
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=transport_livekit_sdk_unknown_error_redacted
sender_side_livekit_join_repeated=false
sender_transport_failure_diagnostics_transport_attempted=true
sender_transport_failure_diagnostics_transport_started=true
sender_transport_failure_diagnostics_transport_completed=true
sender_transport_failure_diagnostics_transport_result=failed_redacted
sender_transport_failure_diagnostics_error_bucket=transport_livekit_sdk_unknown_error_redacted
sender_transport_failure_diagnostics_classification=transport_livekit_sdk_unknown_error_redacted
sender_transport_failure_diagnostics_same_livekit_room=true
sender_transport_failure_diagnostics_same_token_authority=true
sender_transport_failure_diagnostics_receiver_sender_room_match=true
sender_transport_failure_diagnostics_receiver_sender_token_authority_match=true
sender_transport_error_surface_source=livekit_sdk_unknown_error_redacted
sender_transport_error_surface_sdk_error_bucket=livekit_sdk_unknown_error_redacted
sender_transport_error_surface_raw_error_logged=false
sender_transport_error_surface_raw_url_logged=false
sender_transport_error_surface_raw_token_logged=false
sender_transport_error_surface_final_classification=transport_livekit_sdk_unknown_error_redacted
```

Remote participant/audio/liveness did not succeed:

```text
receiver_remote_participant_observer_result=not_observed_redacted
receiver_remote_participant_observer_error_bucket=sender_join_failed_redacted
receiver_remote_participant_observer_remote_seen=false
receiver_remote_participant_observer_audio_track_seen=false
receiver_remote_participant_observer_liveness_seen=false
livekit_remote_participant_seen=false
livekit_remote_audio_track_subscribed=false
livekit_audio_liveness_result=not_observed_redacted
```

Safety stayed closed:

```text
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
controlled_connect_first_attempt_repeated=false
sender_side_livekit_join_repeated=false
blocked_reason=none
```

## Next Phase

`2.48Z-SenderLiveKitSDKUnknownTransportDiagnostics — inspect sender LiveKit SDK unknown transport source, no APNs/connect`

Do not set the phase to another physical APNs attempt yet. Do not set it to remote-audio success.

## Hard Limits

Do not:

* send APNs
* send production APNs
* send repeated APNs
* run `dev/invite`
* run repeated connect
* join LiveKit physically
* request microphone permission
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID/raw error
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Suggested Work

Investigate why the sender-side transport surface classified as:

```text
transport_livekit_sdk_unknown_error_redacted
```

Keep the work no-APNs/no-connect unless a later prompt explicitly prepares another one-shot physical attempt. Prefer local/unit proof and redacted diagnostics. Preserve these boundaries:

```text
raw_error_logged=false
raw_url_logged=false
raw_token_logged=false
room_token_authority_comparisons_redacted=true
pre_transport_failures_classify_before_transport=true
sender_transport_unknown_fallback_only=true
sender_join_success_but_remote_missing_separate=true
default_runtime_no_connect=true
```

## Suggested Checks

Before and after edits:

```bash
git status --short --branch
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|\.entitlements|Info.plist' && exit 1 || true
```

Run privacy scans over changed files/diff. Allowed hits are field names, redacted labels, negative statements, synthetic test values, and stable hashes only.

## Expected Output

Return:

* current phase conclusion
* whether no APNs/connect/LiveKit/permissions/full flow were performed
* implementation or diagnostics summary
* checks run
* final `git status --short --branch`
