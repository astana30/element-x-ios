# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47C8 is committed as a targeted server fix for the persistent direct credentials `eligibilityRejected` blocker after 2.47C7.

Root cause:
- Staging set the legacy switch spelling `SALEMXNATIVE_AUDIO_ELIGIBILITY_ENABLED=1`.
- The service only read the canonical `SALEMX_NATIVE_AUDIO_ELIGIBILITY_ENABLED`.
- The allowlist and homeserver values were present, but the service could still construct `DisabledNativeAudioEligibilityPolicy`, producing `eligibilityRejected` before allocation.

Fix:
- The service now accepts the explicit legacy switch spelling as an alias for the canonical switch.
- Eligibility still remains fail-closed by default.
- The switch must be set to `1`, and existing allowlist/homeserver values are still required.
- Incoming receiver token eligibility from 2.47C7 remains intact.

No APNs was sent for this fix. No production APNs, repeated APNs, `dev/invite`, media connect, LiveKit join, microphone/camera permission request, Matrix event emission, full call flow, raw token/JWT/auth header/payload/ID/LiveKit URL exposure, or forbidden project/signing file change was introduced.

## Next Task

Start 2.47C8 direct credentials close-out after deploying the server fix.

Do not run APNs first. Verify the no-APNs direct credentials path before any physical APNs proof.

Expected direct credentials success:

```text
media_credentials_direct_http_code=200
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_url_received=true
media_credentials_expires_at_present=true
blocked_reason=none
```

Only after direct credentials succeeds, run at most one physical APNs proof.

Final physical target:

```text
media_credentials_token_http_status_bucket=2xx
media_credentials_result=success_redacted
media_credentials_token_received=true
media_credentials_url_received=true
media_credentials_expires_at_present=true
blocked_reason=none
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Do not:
- use `dev/invite`
- send production APNs
- repeat APNs
- connect media
- join LiveKit
- request microphone/camera permissions
- emit Matrix events
- start full call flow
- expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs
- touch project/signing/entitlement/`Info.plist`/`app.yml` files
