# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42k-foreground-sse-repeat-call-validation

Next phase: 2.42K - foreground SSE repeat-call validation.

Goal:
Validate that the foreground SSE invite path reduces repeated foreground incoming-call delay while preserving Element Call routing, foreground audio behavior, fallback de-duplication, and server-issued media credential authority.

Context:
- 2.42I passed and was committed as `a4d427f5b07e662695ce108530bbafc9bfdd9399` (`Validate supervised foreground SSE smoke`).
- 2.42I-S physical smoke evidence:
  - server `active_subscriber_count=1`;
  - server `delivered=true`;
  - server `dropped=false`;
  - server `invite_enqueued=true`;
  - server `invite_yielded=true`;
  - server `sse_event_type=foreground.call.invite`;
  - iOS `helper_invoked=true`;
  - iOS `foreground_sse_start_requested=true`;
  - iOS `sse_connected=true`;
  - iOS `stream_failure=none`;
  - iOS `raw_event_received=true`;
  - iOS `invite_parse_succeeded=true`;
  - iOS `pipeline_delivered=true`;
  - iOS `invite_received=true`;
  - iOS `invite_valid=true`;
  - iOS `incoming_requested=true`.
- The remaining 2.42I blocker was invite timestamp validation. iOS reached `invite_parse_attempted=true` but not parse success until a small future-skew allowance was added for minor server/device clock drift. Larger future timestamps still fail closed.
- 2.42J added guardrail cleanup:
  - disabled dev routes return not found;
  - enabled dev invite remains authenticated;
  - local-only self-injection remains localhost-only and exact-one-subscriber gated;
  - `foreground.keepalive`, `invite_enqueued`, and `invite_yielded` diagnostics remain redacted;
  - the DEBUG helper remains DEBUG-only and does not print, return, store, log, or document active credential values;
  - timestamp tests cover current, small future skew, excessive future skew, and expired invites.
- Physical Debug builds should use local command-line signing overrides only:
  - `DEVELOPMENT_TEAM=M639Y9MFR2`;
  - `CODE_SIGN_STYLE=Automatic`;
  - `-allowProvisioningUpdates`;
  - `-allowProvisioningDeviceRegistration`.
- Do not use old Team ID `83LGSC2QPV` for current physical Debug builds.
- Do not persist signing changes.

Scope:
- Foreground only.
- Supervised physical validation first.
- Keep SSE disabled by default unless explicitly configured.
- Preserve Element Call route behavior.
- Preserve server-issued media credential authority.
- Preserve fallback and duplicate guards.
- Keep logs/docs redacted.
- Do not hardcode production URLs or credential values.

Primary questions:
1. Does an SSE-delivered invite request foreground incoming UI within the target window across repeated calls?
2. Does Matrix room-list/timeline fallback de-duplicate after an SSE-delivered invite?
3. Does repeated SSE delivery avoid the previous 10-30 second repeated incoming delay?
4. Does Answer still require the existing credential authority path before media connects?
5. Does repeated End leave SSE runtime, Element Call route, and fallback state clean?
6. What production configuration boundary is required before non-debug rollout?

Expected validation:
- Physical iPhone foreground/open.
- Start Debug SSE helper through the active-session path.
- Confirm `sse_connected=true` and `stream_failure=none`.
- Trigger three supervised local-only invites while exactly one subscriber is active.
- For each invite, confirm:
  - server `active_subscriber_count=1`;
  - server `delivered=true`;
  - server `dropped=false`;
  - server `invite_yielded=true`;
  - iOS `raw_event_received=true`;
  - iOS `invite_parse_succeeded=true`;
  - iOS `pipeline_delivered=true`;
  - iOS `invite_received=true`;
  - iOS `invite_valid=true`;
  - iOS `incoming_requested=true`.
- Measure invite-to-incoming request timing bucket for each invite.
- Confirm fallback de-duplication if Matrix fallback later observes the same call.
- Confirm no media credential request or media connect happens before Answer.
- Disable the dev route after the supervised run and verify public dev route returns not found.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, `Info.plist`, `app.yml`, `project.yml`, or project settings.
- Do not replace Element Call routing.
- Do not hardcode production server URLs or credential values.
- Do not bypass server-issued media credential authority.
- Do not connect media from invite receipt.
- Do not emit Matrix call events from invite receipt.
- Do not add raw account, room, device, event, credential, push/media, Apple signing, media-session, track, participant, private runtime log, or credential-shaped fixture values.

Expected output:
- Redacted repeat-call physical validation report.
- Whether target incoming latency is reached with SSE.
- Whether fallback de-duplication works.
- Whether media credential request and media connection stay blocked before Answer.
- Whether Element Call route behavior remains unchanged.
- Whether the dev invite route was disabled after the smoke.
- Updated docs/status/worklog/next prompt.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
