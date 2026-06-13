# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.43k-pushkit-entitlement-change-proposal`

Next phase: continue from the PushKit entitlement/provisioning change proposal. Do not edit entitlement, project, signing, `Info.plist`, or `app.yml` files unless the user explicitly authorizes those files/settings in the next task.

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

2.43E adds only an inert background CallKit adapter boundary and fake/test reporting seam:

- It consumes the 2.43D report planning result and returns redacted statuses such as `not_reported_not_reportable`, `not_reported_missing_authenticated_context`, `report_attempt_recorded`, and `report_failed_redacted`.
- A fake/test recorder can record one redacted report attempt for a reportable request.
- Non-reportable and missing-session decisions record no report attempt.
- No real `CXProvider.reportNewIncomingCall` is called by this boundary.
- No PushKit/background callback is wired to this boundary.
- No PushKit registration was added.
- No APNs registration was added.
- No VoIP/background entitlement, provisioning, project, `Info.plist`, or `app.yml` file was changed.
- Foreground real invite behavior remains unchanged.
- No media credentials or media connection were introduced.
- No Matrix events are emitted.
- Adapter diagnostics remain redacted booleans/status classes only.

2.43F adds only a controlled real CallKit adapter behind the existing boundary:

- It consumes the 2.43D report planning result and translates reportable requests into a CallKit-provider report request through an injected provider protocol.
- Tests use a fake provider to prove exactly one report attempt for valid reportable requests, no provider call for non-reportable decisions, and redacted provider failures.
- The iOS provider implementation can build a `CXCallUpdate` from safe internal request data, but it is not wired to PushKit/APNs/background callbacks, app launch, or production background behavior.
- No PushKit registration was added.
- No APNs registration was added.
- No VoIP/background entitlement, provisioning, project, `Info.plist`, or `app.yml` file was changed.
- Foreground real invite behavior remains unchanged.
- No media credentials or media connection were introduced.
- No Matrix events are emitted.
- Real adapter diagnostics remain redacted booleans/status classes only.

2.43G adds only a PushKit lifecycle abstraction/fake seam:

- It defines redacted fake lifecycle events for registration requests, token updates, token invalidation, payload receipt, and registration-unavailable states.
- Fake payload receipt composes the 2.43B parser, 2.43C intake, 2.43D planner, and an injected fake/test 2.43F CallKit adapter path.
- Token update and invalidation events produce redacted decisions only.
- Raw PushKit/APNs tokens are not logged, persisted, sent to a server, or exposed in diagnostics.
- No real `PKPushRegistry` was created.
- No PushKit registration was added.
- No APNs registration was added.
- No PushKit/APNs token was requested.
- No real PushKit/background callback was wired.
- No VoIP/background entitlement, provisioning, project, `Info.plist`, or `app.yml` file was changed.
- Foreground real invite behavior remains unchanged.
- No media credentials or media connection were introduced.
- No Matrix events are emitted.
- Lifecycle diagnostics remain redacted booleans/status classes only.

2.43H adds only a docs-first PushKit entitlement/provisioning/server readiness plan:

- The plan lives in `docs/direct-call/PUSHKIT_READINESS_PLAN.md`.
- It records the safe baseline after the validated foreground real-invite path and 2.43B-G seams.
- It documents Apple APNs and VoIP/background capability assumptions, profile/certificate risks, and physical Debug team requirement `M639Y9MFR2`.
- The old `83LGSC2QPV` team must not be used.
- It separates future app-side work into registrar design, token redaction/lifecycle tests, controlled physical registration smoke, server token registration contract, and later VoIP push delivery smoke.
- It documents server requirements for token registration, invalidation, provider credentials, redacted logs, payload mapping, auth gates, and rollback.
- It documents security/privacy constraints: no raw PushKit/APNs tokens, raw identifiers, request payloads, private logs, secret-bearing URLs, media credentials, media connection, or Matrix event emission from push receipt.
- It documents validation gates and rollback requirements before any real PushKit task.
- No PushKit registration was added.
- No APNs registration was added.
- No PushKit/APNs token was requested.
- No real PushKit/background callback was wired.
- No VoIP/background entitlement, provisioning, project, `Info.plist`, or `app.yml` file was changed.
- Foreground real invite behavior remains unchanged.

2.43I adds only a gated PushKit registrar scaffold:

- The registrar feature gate defaults disabled.
- Default configuration does not create a PushKit registry.
- Default configuration does not request a PushKit token.
- Default configuration does not persist or upload a token.
- An isolated real PushKit registry factory exists behind the protocol boundary, but it is not wired to app startup or production background callbacks.
- Enabled tests use fake registry/fake delegate only.
- Token update and invalidation diagnostics are redacted and do not include raw PushKit/APNs token values.
- No APNs registration was added.
- No VoIP/background entitlement, provisioning, project, `Info.plist`, or `app.yml` file was changed.
- Foreground real invite behavior remains unchanged.
- No media credentials or media connection were introduced.
- No Matrix events are emitted.

2.43J adds only a docs-first PushKit capability readiness verification:

- The readiness matrix lives in `docs/direct-call/PUSHKIT_READINESS_PLAN.md`.
- Foreground real invite remains verified at the 2.42M/2.42O baseline.
- The 2.43B-F background parser/intake/planner/adapter chain remains scaffolded.
- The 2.43I registrar remains a disabled-by-default scaffold.
- Real PushKit runtime registration remains blocked.
- Tracked `ElementX/SupportingFiles/ElementX.entitlements` contains development `aps-environment`.
- Tracked `ElementX/SupportingFiles/Info.plist` contains `UIBackgroundModes` including `voip`.
- Apple Developer capability and installed provisioning profile readiness were not verified by this docs-only task.
- Tracked `app.yml` still references old `DEVELOPMENT_TEAM: 83LGSC2QPV`; physical Debug work must use `M639Y9MFR2`.
- Any signing remediation requires a separate explicit task.
- Server token registration endpoint work remains not implemented.
- Server VoIP push provider credential readiness remains not verified.
- Route-level safety remains the fallback server verification.
- Direct `systemctl` service status must not be claimed unless actually verified.
- No physical smoke was rerun.
- No PushKit registration was enabled.
- No PushKit/APNs token was requested, logged, or persisted.
- No APNs registration was added.
- No entitlement, provisioning, project, signing, `Info.plist`, or `app.yml` file was changed.
- No real PushKit/background callback was wired to app startup.
- No media credentials or media connection were introduced.
- No Matrix events are emitted.

2.43K adds only a docs-first PushKit entitlement/provisioning change proposal:

- The proposal lives in `docs/direct-call/PUSHKIT_ENTITLEMENT_CHANGE_PROPOSAL.md`.
- It documents current tracked entitlement files for the main app, NSE, and Share Extension.
- Main app entitlements include development `aps-environment`.
- NSE and Share Extension entitlements include app group and keychain access groups but no APNs entitlement.
- No tracked entitlement file includes `com.apple.developer.pushkit.unrestricted-voip` or another PushKit/VoIP-specific entitlement key.
- Main app `Info.plist` and target config already include `UIBackgroundModes` with `voip`.
- Target/project config references all three entitlement files.
- Tracked `app.yml` and generated project state still reference old team `83LGSC2QPV`.
- Future physical PushKit work must use `M639Y9MFR2`.
- The proposal does not apply changes.
- No `.entitlements`, `Info.plist`, `SalemX.xcodeproj/project.pbxproj`, `app.yml`, signing/provisioning setting, bundle ID, PushKit registration, APNs registration, token request, physical smoke, media credential, media connection, Matrix event emission, Element Call route replacement, or production background behavior was changed.

## Guardrails

- Do not implement PushKit/APNs/background incoming-call behavior without a separately scoped task.
- Any future signing, entitlement, provisioning, project, `Info.plist`, or `app.yml` change requires explicit approval in that task.
- Future controlled local physical PushKit registrar smoke is blocked until explicit entitlement/profile readiness approval and signing/team readiness are present.
- Do not edit `.entitlements`, `Info.plist`, `SalemX.xcodeproj/project.pbxproj`, `app.yml`, or signing/provisioning settings unless the next user prompt explicitly authorizes those exact files/settings.
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

## Future Explicit Authorization Boundary

A future entitlement/provisioning implementation task may proceed only if the user explicitly authorizes touching one or more of:

```text
.entitlements
Info.plist
SalemX.xcodeproj/project.pbxproj
app.yml
signing/provisioning settings
```

Without that explicit authorization, keep the next task docs/test-only and do not apply project, signing, capability, profile, entitlement, or `Info.plist` changes.
