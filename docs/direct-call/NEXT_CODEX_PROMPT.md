# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderTransportFailureRepair` is complete.

This was a code/test diagnostics repair. No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, video, microphone/camera permission, Matrix event emit, or full call flow was performed.

The previous physical proof remains classified as sender transport-failed / remote participant not observed triage, not remote-audio success:

```text
/tmp/salemx-voip-push-receipt-proof-2.48z-physical2-retry4-sender-join-failure-bucket-polled.txt
proof_generation=generation_18
sender_side_livekit_join_result=failed_redacted
sender_join_failure_diagnostics_classification=transport_failed_redacted
receiver_remote_participant_observer_result=not_observed_redacted
```

New sender transport failure diagnostics are available for the next physical proof:

```text
sender_transport_failure_diagnostics_present=true
sender_transport_failure_diagnostics_debug_only=true
sender_transport_failure_diagnostics_audio_only=true
sender_transport_failure_diagnostics_video_allowed=false
sender_transport_failure_diagnostics_matrix_events_allowed=false
sender_transport_failure_diagnostics_raw_identifiers_logged=false
sender_transport_failure_diagnostics_transport_attempted=<redacted_bool>
sender_transport_failure_diagnostics_transport_started=<redacted_bool>
sender_transport_failure_diagnostics_transport_completed=<redacted_bool>
sender_transport_failure_diagnostics_transport_result=<redacted_bucket>
sender_transport_failure_diagnostics_error_bucket=<redacted_bucket>
sender_transport_failure_diagnostics_classification=<redacted_bucket>
sender_transport_failure_diagnostics_livekit_url_present=<redacted_bool>
sender_transport_failure_diagnostics_token_present=<redacted_bool>
sender_transport_failure_diagnostics_room_binding_present=<redacted_bool>
sender_transport_failure_diagnostics_same_livekit_room=<redacted_bool>
sender_transport_failure_diagnostics_same_token_authority=<redacted_bool>
sender_transport_failure_diagnostics_receiver_sender_room_match=<redacted_bool>
sender_transport_failure_diagnostics_receiver_sender_token_authority_match=<redacted_bool>
```

Transport failure buckets:

```text
transport_not_attempted_redacted
transport_timeout_redacted
transport_tls_or_certificate_failed_redacted
transport_websocket_failed_redacted
transport_auth_rejected_redacted
transport_room_not_found_or_mismatch_redacted
transport_network_unreachable_redacted
transport_livekit_server_rejected_redacted
transport_unknown_failed_redacted
```

Existing pre-transport sender join buckets still classify before transport:

```text
credentials_missing_redacted
token_missing_redacted
url_missing_redacted
room_binding_missing_redacted
same_livekit_room_mismatch_redacted
```

Transport failure remains separate from sender join success but receiver remote missing:

```text
sender_transport_failure_diagnostics_transport_result=failed_redacted
sender_transport_failure_diagnostics_classification=<redacted_transport_bucket>
receiver_remote_participant_observer_error_bucket=sender_join_success_but_remote_missing_redacted
```

## Next Phase

`2.48Z-Physical2-Retry5 — one-shot two-physical-device sender transport bucket proof`

## Diagnostic Goals

Run one explicit two-physical-device Retry5 only after fresh preflight and explicit operator confirmation. The goal is to classify the sender-side transport failure into one of the new redacted buckets and verify the sender/receiver LiveKit room and token-authority comparison fields:

```text
sender_transport_failure_diagnostics_same_livekit_room=<redacted_bool>
sender_transport_failure_diagnostics_same_token_authority=<redacted_bool>
sender_transport_failure_diagnostics_receiver_sender_room_match=<redacted_bool>
sender_transport_failure_diagnostics_receiver_sender_token_authority_match=<redacted_bool>
```

## Hard Limits

Do not:

* send APNs before fresh preflight and explicit operator confirmation
* send production APNs
* send repeated APNs
* run `dev/invite`
* run repeated connect
* run repeated LiveKit join
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

* sender transport bucket proof conclusion
* whether sender transport failure was classified into a precise redacted bucket
* whether same LiveKit room/token authority matched without raw IDs/tokens
* whether receiver remote participant/audio/liveness was observed
* whether one-shot protections remained preserved
* whether default no-connect/no-join safety remained preserved after the proof
* changed files
* checks run
* final `git status --short --branch`
