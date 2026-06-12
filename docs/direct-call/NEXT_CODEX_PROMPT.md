# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42j-foreground-sse-repeat-call-validation

Next phase: 2.42J - foreground SSE repeat-call validation and integration hardening.

Goal:
Validate that the foreground SSE invite path can reduce repeated foreground incoming-call delay without regressing the existing Element Call route, foreground audio behavior, or server-issued media credential authority.

Context:
- 2.42D added the authenticated call-service foreground SSE stream endpoint.
- 2.42E added the disabled/configured iOS SSE transport client boundary.
- 2.42F added disabled-by-default supervised dev invite routes.
- 2.42H added `DebugForegroundCallSignalingSSERuntimeOwner`.
- 2.42I added the `SalemXForegroundSSESmokeDebug` active-session LLDB helper, local-only `dev/inject-active` route, stream failure diagnostics, parser diagnostics, and server stream/fanout diagnostics.
- 2.42I-S physical smoke passed:
  - iOS reached `helper_invoked=true`, `foreground_sse_start_requested=true`, `sse_connected=true`, and `stream_failure=none`.
  - Server reached `stream_auth_ok`, `stream_registered`, `ready_sent`, and `active_subscriber_count=1`.
  - Local-only self-injection returned `active_subscriber_count=1`, `delivered=true`, and `dropped=false`.
  - Server emitted `invite_enqueued=true`, `invite_yielded=true`, and `sse_event_type=foreground.call.invite`.
  - iOS emitted `raw_event_received=true`, `sse_event_type=foreground.call.invite`, `invite_parse_attempted=true`, `invite_parse_succeeded=true`, `pipeline_delivered=true`, `invite_received=true`, `invite_valid=true`, and `incoming_requested=true`.
  - The dev route was disabled after the smoke and the public dev route returned `404`.
- The invite validator now allows a small future-skew window for server/device clock drift while still rejecting larger future timestamps.
- Invite receipt still does not request media credentials, connect media, emit Matrix events, add PushKit/APNs behavior, add background incoming behavior, or replace Element Call routing.

Scope:
- Foreground only.
- Debug/dev supervised validation first.
- Keep SSE disabled by default unless explicitly configured.
- Preserve Element Call route behavior.
- Preserve server-issued media credential authority.
- Preserve current fallback and duplicate guards.
- Keep logs/docs redacted.
- Do not hardcode production URLs or credential values.

Primary questions:
1. Can an SSE-delivered invite trigger foreground incoming UI within the target window during repeated foreground calls?
2. Does the Matrix room-list/timeline fallback de-duplicate after an SSE-delivered invite?
3. Does repeated SSE delivery avoid the previous 10-30 second repeated incoming delay?
4. Does answer still require the existing credential authority path before media connects?
5. Does repeated End leave the SSE runtime, Element Call route, and fallback state clean?
6. What production configuration boundary is required before any non-debug rollout?

Expected validation:
- Physical iPhone foreground/open.
- Start Debug SSE helper through the active-session path.
- Confirm `sse_connected=true` and `stream_failure=none`.
- Trigger repeated supervised invites through the local-only route while one subscriber is active.
- Confirm each invite reports:
  - server `active_subscriber_count=1`
  - server `delivered=true`
  - server `dropped=false`
  - server `invite_yielded=true`
  - iOS `invite_received=true`
  - iOS `invite_valid=true`
  - iOS `incoming_requested=true`
- Measure invite-to-incoming request timing bucket.
- Confirm fallback de-duplication if the Matrix fallback later observes the same call.
- Confirm no media credential request or media connect happens before Answer.
- Disable the dev route after each supervised run.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, project.yml, or project settings.
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
