# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.42o-consolidate-foreground-token-guard-baseline`

Next phase: continue from the consolidated foreground real-invite token-guard baseline.

## Baseline

Current validated foreground real-invite baseline:

```text
26e520b6f6ec0220ce118051f5acac36ed40bfba Guard debug foreground smoke surface
```

Completed foreground chain:

```text
9544d85090bb152f5c28d5acd11f37815556e078 Harden foreground real invite token handling
751316429c5476217f7b881d9a2f542a4e7e3b3b Add debug real invite smoke bridge
6c1c47b5386ed5051cea8ee0277719b4d2bd4cce Add debug receiver SSE smoke bridge
a579509c6ea7c294fa428370efa10bf875b053bb Add debug in-app foreground smoke controls
26a07771c22c8c3d615b9c34552f3b811510b724 Expose debug developer options entry
bf9996ae0665ad3953fac3d7a838bfb619349dd1 Validate foreground real invite token guard smoke
26e520b6f6ec0220ce118051f5acac36ed40bfba Guard debug foreground smoke surface
```

## Proven Result

2.42M physical two-device foreground real-invite regression smoke passed at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`.

Receiver pre-invite proof was collected through DEBUG in-app controls:

```text
Settings -> Internal diagnostics -> General -> Foreground SSE smoke
sse_connected=true
stream_failure=none
```

The sender bridge was invoked locally only. Receiver identifiers were typed only into local Xcode/LLDB and were not recorded, printed, stored, pasted into chat, documented, or committed.

Redacted pass evidence:

```text
sender_helper_invoked=true
sender_active_session_available=true
sender_access_token_available=true
sender_invite_post_requested=true
sender_invite_post_status=http_success
sender_invite_delivery_report_received=true
sender_invite_blocked_reason=none

stream_registered active_subscriber_count=1
ready_sent active_subscriber_count=1
subscriber_available=True
invite_enqueued=True
delivered=True
dropped=False
invite_yielded sse_event_type=foreground.call.invite active_subscriber_count=1

sse_connected=true
stream_failure=none
raw_event_received=true
sse_event_type=foreground.call.invite
invite_parse_attempted=true
invite_parse_succeeded=true
pipeline_delivered=true
invite_received=true
invite_valid=true
incoming_requested=true
```

2.42N targeted iOS tests passed on `iPhone 17 Pro` simulator: 81 tests passed.

## Guardrails

- Do not start PushKit/APNs/background incoming-call work until this consolidated baseline is clean.
- The likely next phase is a separately scoped PushKit/APNs/background incoming-call investigation, not mixed with foreground real-invite smoke tooling.
- Do not implement PushKit runtime inside foreground smoke tooling.
- Do not register APNs or VoIP values inside foreground smoke tooling.
- Do not add background incoming handling inside foreground smoke tooling.
- Do not change signing, bundle identifiers, entitlements, `Info.plist`, `app.yml`, `project.yml`, or project settings.
- Do not replace Element Call routing.
- Do not request media credentials from invite receipt.
- Do not connect media from invite receipt.
- Do not emit Matrix call events from invite receipt.
- Do not add raw account, room, device, event, credential, media-session, private runtime log, request payload, call handle, recipient, or credential-shaped fixture values.
- Do not stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`; it remains intentionally untracked.

The dev route remains disabled by default. The real non-dev route remains auth-gated.

Server route safety should confirm:

```text
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
```

Claim `salemx-call-service active` only when direct service status is actually verified. If direct `systemctl` SSH is blocked by host-key/auth, report that separately from route-level safety checks.

Physical Debug builds should use local command-line signing overrides only:

```text
DEVELOPMENT_TEAM=M639Y9MFR2
CODE_SIGN_STYLE=Automatic
-allowProvisioningUpdates
-allowProvisioningDeviceRegistration
```

Do not use old Team ID `83LGSC2QPV`. Do not persist signing changes.
