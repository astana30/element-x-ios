# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.43d-background-callkit-reporting-seam`

Next phase: continue from the background CallKit report request planner seam.

## Baseline

Foreground real-invite baseline:

```text
e7b9428db20892a3e3cb27c15933b786883757f4 Consolidate foreground token guard baseline
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
e7b9428db20892a3e3cb27c15933b786883757f4 Consolidate foreground token guard baseline
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

2.43A is a docs-only investigation of PushKit/APNs/background incoming-call requirements. It does not implement production background behavior.

Key findings:

- Existing PushKit registration and VoIP push handling are present in the Element Call service path, not in SalemX native direct-call background behavior.
- Existing normal APNs registration flows through `AppDelegate`, `AppCoordinator`, and `NotificationManager`.
- Tracked app files already contain development APNs and background-mode assumptions, but 2.43A does not change signing, provisioning, project files, `Info.plist`, `app.yml`, or entitlements.
- Native direct-call background PushKit/APNs incoming-call support is not implemented yet.
- Detailed notes are in `docs/direct-call/PUSHKIT_APNS_BACKGROUND_INVESTIGATION.md`.

2.43B adds only an inert background invite payload contract/parser seam:

- No PushKit registration was added.
- No APNs registration was added.
- No entitlement, provisioning, project, `Info.plist`, or `app.yml` file was changed.
- Foreground real invite behavior remains unchanged.
- No media credentials or media connection were introduced.
- No Matrix events are emitted from background payload parsing.
- Parser diagnostics remain redacted status classes only.
- Timestamp validation matches the foreground invite path for current, small future skew, excessive future skew, and expired payloads.

2.43C adds only an inert background invite intake seam:

- It consumes the 2.43B parser result and returns a redacted internal decision/action class.
- Valid parsed payloads can prepare a foreground-equivalent internal incoming representation or require a later CallKit report decision, but no CallKit report is performed.
- Invalid, expired, and excessive-future payloads are ignored with redacted classes.
- Missing authenticated-session state is represented as `requires_authenticated_session`; the seam does not access tokens.
- No PushKit registration was added.
- No APNs registration was added.
- No VoIP/background entitlement, provisioning, project, `Info.plist`, or `app.yml` file was changed.
- Foreground real invite behavior remains unchanged.
- No media credentials or media connection were introduced.
- No Matrix events are emitted from background intake.
- Intake diagnostics remain redacted booleans/status classes only.

2.43D adds only an inert background CallKit report request planner seam:

- It consumes the 2.43C intake result and returns a redacted internal `reportable_incoming_call_request` model or a non-reportable decision.
- Invalid, expired, excessive-future, and missing-session decisions remain non-reportable with redacted blocked reasons.
- The report request model is not handed to a real CallKit provider in 2.43D.
- No PushKit registration was added.
- No APNs registration was added.
- No VoIP/background entitlement, provisioning, project, `Info.plist`, or `app.yml` file was changed.
- Foreground real invite behavior remains unchanged.
- No real CallKit reporting from PushKit or background callbacks was introduced.
- No media credentials or media connection were introduced.
- No Matrix events are emitted from background CallKit planning.
- Planner diagnostics remain redacted booleans/status classes only.

## Guardrails

- Do not implement PushKit/APNs/background incoming-call behavior without a separately scoped task.
- Any future signing, entitlement, provisioning, project, `Info.plist`, or `app.yml` change requires explicit approval in that task.
- Future 2.43E may add a fake/test-only CallKit adapter boundary or a controlled real CallKit adapter, still without PushKit registration unless explicitly allowed.
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
