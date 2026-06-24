# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderJoinFailureDiagnostics` is complete.

This was a code/test/docs diagnostics repair phase only. It did not send APNs, did not run physical connect, and did not join LiveKit on a device.

The sender-side LiveKit join failure proof now emits redacted diagnostics:

```text
sender_join_failure_diagnostics_present=true
sender_join_failure_diagnostics_debug_only=true
sender_join_failure_diagnostics_audio_only=true
sender_join_failure_diagnostics_video_allowed=false
sender_join_failure_diagnostics_matrix_events_allowed=false
sender_join_failure_diagnostics_raw_identifiers_logged=false
sender_join_failure_diagnostics_credentials_present=<redacted_bool>
sender_join_failure_diagnostics_token_present=<redacted_bool>
sender_join_failure_diagnostics_url_present=<redacted_bool>
sender_join_failure_diagnostics_room_binding_present=<redacted_bool>
sender_join_failure_diagnostics_same_livekit_room=<redacted_bool>
sender_join_failure_diagnostics_transport_attempted=<redacted_bool>
sender_join_failure_diagnostics_transport_result=<redacted_bucket>
sender_join_failure_diagnostics_error_bucket=<redacted_bucket>
sender_join_failure_diagnostics_classification=<redacted_bucket>
```

Missing sender prerequisites are classified before transport:

```text
credentials_missing_redacted
token_missing_redacted
url_missing_redacted
room_binding_missing_redacted
same_livekit_room_mismatch_redacted
sender_join_repeated_redacted
```

Transport/join failure buckets are separate:

```text
transport_failed_redacted
join_failed_redacted
unknown_sender_join_failure_redacted
```

Receiver observer classification remains separate for sender join success with receiver remote missing:

```text
sender_join_failed_redacted
sender_join_success_but_remote_missing_redacted
remote_participant_seen_redacted
remote_audio_track_missing_redacted
remote_liveness_not_observed_redacted
```

Safety remains closed by default:

```text
sender_side_livekit_join_requested=false
sender_side_livekit_join_result=not_requested
sender_join_failure_diagnostics_transport_attempted=false
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_connect_audio_invoked=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Conclusion:

```text
2.48Z-SenderJoinFailureDiagnostics = sender-side join failures can now be classified into precise redacted buckets before the next physical retry.
Missing credentials/token/URL/room binding classify before transport.
Same LiveKit room mismatch classifies before transport.
Transport failure is separate from join failure.
Sender join success but receiver remote missing remains separate.
Sender join activation remains one-shot.
Default runtime remains no-connect/no-join.
No APNs.
No production APNs.
No repeated APNs.
No dev/invite.
No physical media connect.
No physical LiveKit join.
No video.
No microphone permission.
No camera permission.
No Matrix event emit.
No full call flow.
```

## Next Phase

`2.48Z-Physical2-Retry4 — one-shot two-physical-device sender join failure-bucket proof`

This is a one-shot physical retry only after fresh operator confirmation and validated two-physical-device readiness. Do not run it automatically from this docs prompt.

## Retry4 Goals

The next proof should capture which sender join failure bucket appears after the one-shot physical path:

```text
sender_join_failure_diagnostics_classification=<redacted_bucket>
sender_join_failure_diagnostics_error_bucket=<redacted_bucket>
sender_join_failure_diagnostics_transport_attempted=<redacted_bool>
sender_join_failure_diagnostics_transport_result=<redacted_bucket>
```

Expected diagnostic outcomes include:

```text
credentials_missing_redacted
token_missing_redacted
url_missing_redacted
room_binding_missing_redacted
same_livekit_room_mismatch_redacted
transport_failed_redacted
join_failed_redacted
unknown_sender_join_failure_redacted
sender_join_success_but_remote_missing_redacted
remote_participant_seen_redacted
```

## Hard Limits

Do not:

* send APNs
* send production APNs
* send repeated APNs
* run `dev/invite`
* run physical media connect
* join LiveKit on device
* request microphone permission
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

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

* sender join failure diagnostic conclusion
* whether default no-connect/no-join remains preserved
* whether one-shot protections remain preserved
* changed files
* checks run
* final `git status --short --branch`
