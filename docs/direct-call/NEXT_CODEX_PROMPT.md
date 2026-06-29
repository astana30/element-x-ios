# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

Retry29 is final. Do not rerun it and do not send another APNs for Retry29.

Retry29 achieved the two-device path through receiver/sender LiveKit connection, participant presence, sender audio publish, and receiver remote audio publication:

```text
APNs_sent=true
background_apns_push_result=sandbox_success
physical_voip_push_received=true
callkit_answer_action_received=true
receiver_post_answer_pending_metadata_fetch_result=success_redacted
receiver_post_answer_media_credentials_result=success_redacted
receiver_post_answer_controlled_connect_result=success_redacted
receiver_post_answer_livekit_join_result=success_redacted
controlled_connect_first_attempt_result=success_redacted
livekit_join_result=success_redacted
receiver_connected_session_lease_acquired=true
sender_runtime_join_executor_invoked=true
sender_runtime_join_pending_metadata_fetch_result=success_redacted
sender_runtime_join_credentials_result=success_redacted
sender_runtime_join_runtime_result=success_redacted
sender_livekit_room_connected=true
sender_local_audio_publish_requested=true
sender_local_audio_publish_allowed=true
sender_local_audio_publish_result=success_redacted
sender_local_audio_muted_state_bucket=unmuted_redacted
sender_audio_session_activation_observed=true
sender_microphone_permission_requested=true
sender_microphone_permission_result_bucket=success_redacted
receiver_participant_event_callback_seen=true
livekit_remote_participant_seen=true
livekit_remote_participant_count_bucket=1
receiver_remote_audio_observer_bound_to_retained_room=true
receiver_remote_audio_observer_bound_to_connected_room=true
receiver_remote_audio_observer_attached_after_participant_seen=true
receiver_remote_audio_publication_seen=true
receiver_remote_audio_track_unmuted=true
```

Retry29 narrowed the remaining blocker to receiver remote audio subscription/liveness:

```text
receiver_remote_audio_track_subscribed=false
receiver_remote_audio_level_observed=false
receiver_remote_audio_liveness_observed=false
receiver_remote_audio_liveness_wait_started=true
receiver_remote_audio_liveness_wait_completed=false
receiver_remote_audio_liveness_wait_timeout=false
receiver_remote_audio_liveness_final_classification=remote_audio_subscription_missing_redacted
livekit_audio_liveness_observed=false
remote_audio_liveness_result=not_observed_redacted
retry29_success=false
```

Safety remained preserved:

```text
no repeated APNs
no production APNs
no dev/invite
no repeated receiver connect
no repeated sender join
video=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Retry29 also exposed a helper accounting bug:

```text
phase_pushkit_ready=false
first_failed_phase=pushkit_ready
```

Those fields were stale/wrong because pre-APNs PushKit readiness passed. Future helpers must preserve the pre-APNs readiness result and classify the terminal blocker as receiver remote audio subscription/liveness when subscription remains missing.

## Receiver Subscription Repair Completed

The latest code repair is DEBUG-only and no physical proof has been rerun yet.

New proof fields:

```text
receiver_remote_audio_subscription_repair_present=true
receiver_remote_audio_subscription_repair_debug_only=true
receiver_remote_audio_subscription_raw_identifiers_logged=false
receiver_remote_audio_auto_subscribe_enabled=false
receiver_remote_audio_publication_subscribed_state_bucket=<redacted_bucket>
receiver_remote_audio_explicit_subscribe_requested=<runtime>
receiver_remote_audio_explicit_subscribe_result=<redacted_bucket>
receiver_remote_audio_subscription_callback_seen=<runtime>
receiver_remote_audio_subscription_wait_started=<runtime>
receiver_remote_audio_subscription_wait_completed=<runtime>
receiver_remote_audio_subscription_wait_timeout=<runtime>
receiver_remote_audio_subscription_final_classification=<redacted_bucket>
```

Runtime behavior:
- receiver controlled connect explicitly enables remote audio playback/subscription after LiveKit join success
- LiveKit subscription callbacks update receiver proof from runtime state
- participant callback/snapshot success no longer releases the retained receiver room before subscription/liveness success or bounded timeout
- no raw token, URL, room ID, call ID, user ID, device ID, participant identity, track SID, APNs payload, invite body, auth header, pending metadata, or private logs are recorded

## New Phase

Start:

```text
2.49A-Physical2-Retry30 — one-shot receiver remote audio subscription/liveness validation
```

Goal:

Validate the receiver subscription repair after the already-proven Retry29 path:

```text
receiver LiveKit connected
sender LiveKit connected
receiver remote participant seen
sender audio publish success
receiver remote audio publication seen
remote audio track subscribed/unmuted/liveness observed
```

Primary proof targets:

```text
remote_audio_track_liveness_proof_present=true
remote_audio_track_liveness_proof_debug_only=true
remote_audio_track_liveness_raw_identifiers_logged=false
receiver_remote_audio_subscription_repair_present=true
receiver_remote_audio_subscription_repair_debug_only=true
receiver_remote_audio_subscription_raw_identifiers_logged=false
livekit_remote_participant_seen=true
receiver_remote_audio_observer_bound_to_retained_room=true
receiver_remote_audio_observer_bound_to_connected_room=true
receiver_remote_audio_observer_attached_after_participant_seen=true
receiver_remote_audio_publication_seen=true
receiver_remote_audio_explicit_subscribe_requested=true
receiver_remote_audio_explicit_subscribe_result=success_redacted
receiver_remote_audio_subscription_callback_seen=true
receiver_remote_audio_track_subscribed=true
receiver_remote_audio_track_unmuted=true
receiver_remote_audio_subscription_wait_started=true
receiver_remote_audio_subscription_wait_completed=true
receiver_remote_audio_subscription_wait_timeout=false
receiver_remote_audio_subscription_final_classification=remote_audio_subscription_observed_redacted OR remote_audio_explicit_subscription_success_redacted
receiver_remote_audio_level_observed=true
receiver_remote_audio_liveness_observed=true
receiver_remote_audio_liveness_wait_started=true
receiver_remote_audio_liveness_wait_completed=true
receiver_remote_audio_liveness_wait_timeout=false
receiver_remote_audio_liveness_final_classification=remote_audio_liveness_observed_redacted
sender_local_audio_publish_requested=true
sender_local_audio_publish_allowed=true
sender_local_audio_publish_result=success_redacted
sender_local_audio_muted_state_bucket=unmuted_redacted
sender_audio_session_activation_observed=true
sender_microphone_permission_requested=true
sender_microphone_permission_result_bucket=success_redacted
livekit_audio_liveness_observed=true
livekit_audio_liveness_result=success_redacted
remote_audio_liveness_result=success_redacted
video_enabled=false
```

Guardrails:

```text
no video
no camera permission request
no Matrix event emit
no full production flow
no raw token, URL, room ID, call ID, user ID, device ID, APNs payload, invite body, auth header, pending metadata contents, or private log exposure
```

Before any APNs:

```text
build/install current Debug app on receiver and sender
receiver=iPhone PRO unless explicitly changed
sender=Carpediem unless explicitly changed
verify app sessions and encrypted room preflight
verify all 2.49A proof-surface fields are present before APNs
arm the existing receiver controlled audio connect, remote peer context, sender readiness/correlation, operator-ready, and foreground in-app answer hooks as required by the latest helper
fail closed before APNs if any freshness/proof-surface/readiness field is missing
```

Run at most one sandbox APNs after exact manual confirmation. Do not repeat APNs. Do not use production APNs or `dev/invite`.

If participant is seen but audio liveness is missing, classify with one of:

```text
remote_audio_subscription_observed_redacted
remote_audio_explicit_subscription_success_redacted
remote_audio_publication_seen_but_subscription_missing_redacted
remote_audio_auto_subscribe_disabled_redacted
remote_audio_subscription_timeout_redacted
remote_audio_track_subscribed_but_silent_redacted
remote_audio_publication_missing_redacted
remote_audio_subscription_missing_redacted
remote_audio_track_muted_redacted
remote_audio_liveness_timeout_redacted
sender_audio_publish_not_requested_redacted
sender_microphone_permission_blocked_redacted
sender_audio_session_not_active_redacted
remote_audio_observer_not_bound_to_connected_room_redacted
```

## Checks

Run targeted checks only:

```bash
swiftformat <changed Swift files>
swiftlint lint <changed Swift files>
DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/NativeIncomingCallLifecycleContractTests' Tools/Scripts/verify_direct_call_unit.sh
git diff --check
git diff --cached --check
git diff --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|.entitlements|Info.plist' && exit 1 || true
git diff --cached --name-only | grep -E 'SalemX.xcodeproj/project.pbxproj|app.yml|.entitlements|Info.plist' && exit 1 || true
```
