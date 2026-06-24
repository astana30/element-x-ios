# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

`2.48Z-SenderTransportUnknownFailureSurfaceRepair` is complete.

This was a local/code diagnostics repair only. No APNs, production APNs, repeated APNs, `dev/invite`, physical media connect, physical LiveKit join, video, microphone/camera permission, Matrix event emit, full call flow, or physical hook reset/re-arm was performed.

Retry5 previously proved receiver PushKit, CallKit Answer, pending metadata, media credentials, one receiver controlled audio connect, and receiver LiveKit join succeeded, but the sender-side transport failure ended as:

```text
sender_side_livekit_join_result=failed_redacted
sender_side_livekit_join_error_bucket=transport_failed_redacted
sender_transport_failure_diagnostics_transport_attempted=true
sender_transport_failure_diagnostics_transport_started=true
sender_transport_failure_diagnostics_transport_completed=true
sender_transport_failure_diagnostics_transport_result=failed_redacted
sender_transport_failure_diagnostics_error_bucket=transport_unknown_failed_redacted
sender_transport_failure_diagnostics_classification=transport_unknown_failed_redacted
sender_transport_failure_diagnostics_same_livekit_room=true
sender_transport_failure_diagnostics_same_token_authority=true
sender_transport_failure_diagnostics_receiver_sender_room_match=true
sender_transport_failure_diagnostics_receiver_sender_token_authority_match=true
```

The repair adds a DEBUG/test-controlled redacted sender transport error surface:

```text
sender_transport_error_surface_present=true
sender_transport_error_surface_debug_only=true
sender_transport_error_surface_raw_error_logged=false
sender_transport_error_surface_raw_url_logged=false
sender_transport_error_surface_raw_token_logged=false
sender_transport_error_surface_source=<redacted_source>
sender_transport_error_surface_sdk_error_bucket=<redacted_bucket>
sender_transport_error_surface_disconnect_reason_bucket=<redacted_bucket>
sender_transport_error_surface_websocket_bucket=<redacted_bucket>
sender_transport_error_surface_auth_bucket=<redacted_bucket>
sender_transport_error_surface_timeout_observed=<redacted_bool>
sender_transport_error_surface_connected_state_observed=<redacted_bool>
sender_transport_error_surface_disconnected_before_connected=<redacted_bool>
sender_transport_error_surface_final_classification=<redacted_transport_bucket>
```

Supported classifications:

```text
transport_connect_throw_redacted
transport_room_connect_callback_failed_redacted
transport_websocket_close_redacted
transport_websocket_upgrade_failed_redacted
transport_auth_rejected_redacted
transport_token_expired_or_invalid_redacted
transport_tls_or_certificate_failed_redacted
transport_network_unreachable_redacted
transport_timeout_waiting_for_connected_state_redacted
transport_disconnected_before_connected_redacted
transport_livekit_sdk_unknown_error_redacted
transport_unknown_failed_redacted
```

Important behavior:

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

## Next Phase

`2.48Z-Physical2-Retry6 — one-shot two-physical-device sender transport error-source proof`

Do not set the phase to actual remote-audio success unless the physical proof observes sender join plus receiver remote participant/audio/liveness.

## Hard Limits

Do not:

* send APNs before fresh preflight and explicit one-shot confirmation
* send production APNs
* send repeated APNs
* run `dev/invite`
* run repeated connect
* join LiveKit repeatedly
* request camera permission
* enable video
* emit Matrix events
* start full call flow
* log raw token/JWT/auth header/APNs payload/invite body/LiveKit URL/room ID/call ID/peer user ID/user ID/device ID
* touch signing/project files
* stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

## Retry6 Expectations

Before APNs, verify both physical devices and same encrypted room with redacted values only.

After exactly one sandbox APNs and one operator Answer, the future proof should include the repaired sender transport error surface fields. If sender transport fails again, classify into the most specific redacted bucket available and preserve:

```text
sender_transport_failure_diagnostics_same_livekit_room=true
sender_transport_failure_diagnostics_same_token_authority=true
sender_transport_failure_diagnostics_receiver_sender_room_match=true
sender_transport_failure_diagnostics_receiver_sender_token_authority_match=true
sender_transport_error_surface_raw_error_logged=false
sender_transport_error_surface_raw_url_logged=false
sender_transport_error_surface_raw_token_logged=false
```

If sender join succeeds but receiver does not observe the remote participant/audio/liveness, classify separately:

```text
sender_side_livekit_join_result=success_redacted
sender_transport_failure_diagnostics_transport_result=success_redacted
receiver_remote_participant_observer_error_bucket=sender_join_success_but_remote_missing_redacted
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

* Retry6 readiness / physical proof classification
* whether sender transport classified into a specific redacted error source
* whether raw error/URL/token stayed unlogged
* whether same LiveKit room/token-authority comparison remained preserved without raw IDs/tokens
* whether sender join success-but-remote-missing remained separate if applicable
* whether default no-connect/no-join safety stayed preserved before the one-shot
* checks run
* final `git status --short --branch`
