# Supervised Foreground SSE Smoke

## 2.42O - Consolidated Foreground Token-Guard Baseline

Status: completed as a docs-only baseline consolidation after the 2.42M pass and 2.42N release-surface guard.

The current validated foreground real-invite baseline is `26e520b6f6ec0220ce118051f5acac36ed40bfba`. It includes:

- 2.42L stale-token/`401` sender diagnostic hardening.
- 2.42M1 DEBUG-only sender bridge.
- 2.42M2 DEBUG-only receiver SSE bridge/proof path.
- 2.42M3 DEBUG-only in-app foreground smoke controls.
- 2.42M4 DEBUG-only `Internal diagnostics` entry.
- 2.42M physical two-device foreground real-invite smoke pass at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`.
- 2.42N DEBUG smoke tooling release-surface guard at `26e520b6f6ec0220ce118051f5acac36ed40bfba`.

Future work should start from this baseline or a documented descendant. Do not mix PushKit/APNs/background incoming-call investigation, video work, or production call behavior changes into foreground real-invite smoke tooling changes.

The dev route remains disabled by default, and the real non-dev route remains auth-gated. Receiver identifiers were used locally only during smoke and were not recorded. `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md` remains intentionally untracked and must not be staged or committed.

No media credentials, media connection, PushKit/APNs/background behavior, Matrix event emission from invite receipt, or Element Call route replacement was added. Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; do not use the old `83LGSC2QPV` team or persist signing changes.

Route-level safety checks should confirm `dev/invite=404`, unauthenticated non-dev invite `401`, and unauthenticated stream `401`. Claim direct `salemx-call-service active` only when a direct service check such as `systemctl` actually succeeds; SSH host-key/auth blocks should be reported honestly.

## 2.42N - DEBUG Smoke Tooling Release-Surface Guard

Status: completed after the 2.42M physical regression smoke pass at `bf9996ae0665ad3953fac3d7a838bfb619349dd1`.

The M1-M4 sender bridge, receiver bridge, in-app foreground smoke controls, and Settings `Internal diagnostics` entry are local supervised smoke tooling only. They must remain DEBUG-only and must not become production call behavior.

2.42N adds focused source-surface coverage that guards the DEBUG compile gates around the smoke bridge classes, receiver proof controls, active-session registration hook, Settings Developer Options action, and flow-coordinator route.

The smoke proof and diagnostics surface must remain limited to redacted booleans/status classes. It must not display, log, store, document, or commit access tokens, authorization headers, raw user IDs, raw device IDs, room IDs, recipients, call handles, request payloads, private logs, or secret-bearing URLs.

The dev route remains disabled by default. The real non-dev route remains auth-gated. Physical Debug builds should use `DEVELOPMENT_TEAM=M639Y9MFR2`; do not use the old `83LGSC2QPV` team or persist signing changes.

## 2.42I - Supervised Foreground SSE Smoke Preparation

Status: completed. Stream-open and local-only invite self-injection passed on a supervised physical iPhone smoke.

## Scope

This phase prepares the supervised foreground SSE smoke for the DEBUG/dev foreground signaling path. It does not add runtime product wiring.

The smoke proves that a foreground/open iPhone app can receive an opaque server-originated foreground call invite through the call-service SSE stream and request the existing foreground incoming/CallKit path without waiting for Matrix room-list or timeline materialization.

## Server Setup

Use local or staging supervision only.

Enable the disabled-by-default dev invite route for the supervised window:

```text
SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1
```

The stream endpoint is:

```text
GET /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream
```

The supervised dev invite endpoint is:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite
```

The preferred supervised self-injection endpoint for this smoke is:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/inject-active
```

The self-injection endpoint is registered only under the same explicit flag, accepts only local requests on the call-service host, requires exactly one active foreground SSE subscriber, and returns only a redacted active-subscriber count plus delivered/dropped booleans.

## Server Disable And Rollback

After the supervised smoke, disable the dev invite route by unsetting the flag and restarting/redeploying the call-service:

```text
SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED unset
```

With the flag unset, the dev route must not be registered. Keep the stream endpoint available only through the authenticated foreground channel.

## iOS DEBUG Configuration

The iOS app must use a Debug build and explicit supervised construction:

- `DebugForegroundCallSignalingSSERuntimeOwner`
- `isEnabled=true`
- authenticated session available
- injected `ForegroundCallSignalingSSETransport`
- injected `URLSessionForegroundCallSignalingSSEStream`
- injected `URLRequest`
- injected `ForegroundCallInviteHandler`

The app must not hardcode production URLs, auth header values, or credential storage. Request construction remains outside the runtime owner.

The DEBUG owner must stay disabled by default and must be started only for the supervised foreground run.

## DEBUG LLDB Smoke Hook

For supervised physical-device smoke, the Debug app exposes an Objective-C runtime bridge:

```text
SalemXForegroundSSESmokeDebug
```

Configure it only during the supervised window with placeholder values resolved locally. Do not paste resolved values into docs or reports.

Preferred active-session path:

```lldb
expr -l objc++ -O -- [(Class)NSClassFromString(@"SalemXForegroundSSESmokeDebug") stop]
expr -l objc++ -O -- [(Class)NSClassFromString(@"SalemXForegroundSSESmokeDebug") clear]
expr -l objc++ -O -- [(Class)NSClassFromString(@"SalemXForegroundSSESmokeDebug") startWithCurrentSessionURLString:@"<REDACTED_SSE_STREAM_URL>"]
continue
```

This path uses the Debug app's currently active `UserSession` to construct the stream request inside the app process. The credential value is not returned to LLDB, logged, written to disk, or documented. If no active session or current app credential is available, the bridge emits disabled redacted diagnostics and does not start the stream.

Before any server invite testing, confirm the helper was actually invoked by the Debug app process:

- `[SSE-SMOKE-DIAG] helper_invoked=true`
- `[SSE-SMOKE-DIAG] active_session_available=true`
- `[SSE-SMOKE-DIAG] access_token_available=true`
- `[SSE-SMOKE-DIAG] device_id_available=true`
- `[SSE-SMOKE-DIAG] homeserver_url_available=true`
- `[SSE-SMOKE-DIAG] foreground_sse_start_requested=true`
- `[SSE-SMOKE-DIAG] foreground_sse_start_blocked_reason=none`

If `helper_invoked=true` does not appear, the LLDB expression, attached process, installed build, or foreground app state is wrong. Do not debug server fanout, invite delivery, or parser stages until this line appears.

Manual injected-header fallback:

```lldb
expr -l objc++ -O -- [(Class)NSClassFromString(@"SalemXForegroundSSESmokeDebug") configureWithStreamURLString:@"<REDACTED_SSE_STREAM_URL>" authorizationHeaderValue:@"<REDACTED_AUTH_HEADER_VALUE>"]
expr -l objc++ -O -- [(Class)NSClassFromString(@"SalemXForegroundSSESmokeDebug") start]
continue
```

Stop and clear the supervised runtime after the smoke:

```lldb
expr -l objc++ -O -- [(Class)NSClassFromString(@"SalemXForegroundSSESmokeDebug") stop]
expr -l objc++ -O -- [(Class)NSClassFromString(@"SalemXForegroundSSESmokeDebug") clear]
continue
```

The bridge constructs the existing DEBUG SSE runtime owner with an injected request, the URLSession SSE transport, the existing invite handler, and the isolated synthetic CallKit reporting proof adapter. It does not hardcode an endpoint or credential value, and it remains disabled unless configured through LLDB. The active-session helper removes the need to copy the current app credential into LLDB.

The bridge emits grep-able one-line diagnostics with this prefix:

```text
[SSE-SMOKE-DIAG]
```

Expected fields:

- `[SSE-SMOKE-DIAG] helper_invoked=true`
- `[SSE-SMOKE-DIAG] active_session_available=true/false`
- `[SSE-SMOKE-DIAG] access_token_available=true/false`
- `[SSE-SMOKE-DIAG] device_id_available=true/false`
- `[SSE-SMOKE-DIAG] homeserver_url_available=true/false`
- `[SSE-SMOKE-DIAG] foreground_sse_start_requested=true/false`
- `[SSE-SMOKE-DIAG] foreground_sse_start_blocked_reason=none/invalid_stream_url/missing_active_session/missing_access_token_provider/missing_access_token/blank_access_token`
- `[SSE-SMOKE-DIAG] sse_configured=true`
- `[SSE-SMOKE-DIAG] sse_started=true`
- `[SSE-SMOKE-DIAG] sse_connected=true`
- `[SSE-SMOKE-DIAG] invite_received=true`
- `[SSE-SMOKE-DIAG] invite_valid=true`
- `[SSE-SMOKE-DIAG] incoming_requested=true`
- `[SSE-SMOKE-DIAG] fallback_deduped=true/false`
- `[SSE-SMOKE-DIAG] transport_stopped=true`
- `[SSE-SMOKE-DIAG] stream_failure=none/http_unauthorized/http_forbidden/http_client_error/http_server_error/http_unexpected/non_http_response/unsupported_content_type/network`
- `[SSE-SMOKE-DIAG] raw_event_received=true`
- `[SSE-SMOKE-DIAG] sse_event_type=foreground.call.invite`
- `[SSE-SMOKE-DIAG] invite_parse_attempted=true`
- `[SSE-SMOKE-DIAG] invite_parse_succeeded=true`
- `[SSE-SMOKE-DIAG] pipeline_delivered=true`

The diagnostic lines contain booleans and safe enum values only. They must not include raw URLs, account values, room values, device values, event values, credential values, request bodies, media-session names, or private runtime logs.

## Placeholder Dev Invite Commands

This is a placeholder shape only. Replace placeholders locally during supervision and do not paste resolved commands or raw output into docs.

Preferred local-only self-injection command on the call-service host:

```bash
curl -X POST "http://127.0.0.1:8091/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/inject-active" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "foreground.call.invite",
    "version": 1,
    "call_handle": "safe-foreground-smoke-<timestamp>",
    "call_kind": "audio",
    "created_at_ms": 0,
    "expires_at_ms": 0,
    "display_label": "Pilot Participant"
  }'
```

Expected redacted response on pass:

```json
{
  "version": 1,
  "active_subscriber_count": 1,
  "delivered": true,
  "dropped": false
}
```

The older authenticated dev invite command remains useful for targeted server tests, but it is no longer required for the supervised iPhone smoke when the active-session SSE helper is used:

```bash
curl -X POST "https://<CALL_SERVICE_HOST>/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite" \
  -H "Authorization: <AUTH_SCHEME> <REDACTED_AUTH_VALUE>" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "foreground.call.invite",
    "version": 1,
    "call_handle": "opaque-test-call-handle",
    "call_kind": "audio",
    "created_at_ms": 0,
    "expires_at_ms": 0,
    "display_label": "Test Call"
  }'
```

The dev invite must be submitted from the same active callee session while the foreground SSE stream is connected.

The local-only self-injection route avoids copying the active app credential out of the app. It must be used only while exactly one supervised foreground SSE subscriber is connected.

## 2.42I Smoke Troubleshooting Update

The supervised smoke requires the same active app Matrix session for the stream and invite delivery checks:

- the iOS DEBUG SSE stream request;
- the supervised dev invite POST.

An OAuth/MAS value, stale Matrix bearer, refreshed-out bearer, or bearer copied from a different device/session can make the stream or dev invite authenticate as a different principal/device, or fail with an inactive-token response. If any real credential value is exposed during manual supervision, treat it as compromised and rotate or revoke it outside the repo and docs.

Prefer `startWithCurrentSessionURLString:` for the physical iPhone smoke because the Debug app reads its active session credential internally and does not expose it through LLDB. If the dev invite still requires an external authenticated POST, use only a locally verified current credential outside chat/docs, or stop and add a supervised server-side self-injection route tied to the active SSE subscriber.

`[SSE-SMOKE-DIAG] sse_connected=true` now means the app received the server `foreground.ready` SSE event or a valid invite event. A started URLSession task alone is not enough to mark the smoke connected.

If the iOS diagnostics show `sse_started=true`, `sse_connected=false`, and `transport_stopped=true`, diagnose the stream path before retrying dev invite delivery. Use `stream_failure` to distinguish stale/unauthorized credentials, non-SSE responses, network failure, and early stream end. The expected redacted server stream lifecycle is:

- `stream_auth_ok`
- `stream_registered`
- `ready_sent`
- `stream_closed`

The stream response should use `Content-Type: text/event-stream`, `Cache-Control: no-cache`, and `X-Accel-Buffering: no`. The iOS URLSession SSE reader preserves raw line breaks so the blank-line SSE delimiter can flush `foreground.ready`.

The supervised dev invite response may include redacted troubleshooting fields:

- `active_subscriber_count`
- `target_subscriber_count`
- `auth_user_hash`
- `auth_device_hash`
- `target_user_hash`
- `target_device_hash`

These fields are hashes and counters only. They exist to distinguish no active subscriber, target mismatch, and successful target delivery without exposing raw account or device values.

The active-session helper first proved stream-open on physical iPhone. The observed redacted iOS state was:

- `stream_failure=none`
- `sse_configured=true`
- `sse_started=true`
- `sse_connected=true`
- `invite_received=false`
- `invite_valid=false`
- `incoming_requested=false`

The next blocked stage was invite parsing: the server reported `active_subscriber_count=1`, `delivered=true`, `dropped=false`, and `invite_yielded=true`, while iOS observed `sse_event_type=foreground.call.invite` and `invite_parse_attempted=true` but did not complete invite parsing. The likely cause was small device/server clock skew in the invite timestamp. The validator now allows a small future-skew window while still rejecting larger future timestamps.

## 2.42I-S Physical Smoke Result

Status: passed.

2.42I passed and was committed as:

```text
a4d427f5b07e662695ce108530bbafc9bfdd9399 Validate supervised foreground SSE smoke
```

Redacted server evidence:

- `stream_auth_ok=true`
- `stream_registered=true`
- `ready_sent=true`
- `active_subscriber_count=1`
- `delivered=true`
- `dropped=false`
- `invite_enqueued=true`
- `invite_yielded=true`
- `sse_event_type=foreground.call.invite`

Redacted iOS evidence:

- `[SSE-SMOKE-DIAG] helper_invoked=true`
- `[SSE-SMOKE-DIAG] active_session_available=true`
- `[SSE-SMOKE-DIAG] access_token_available=true`
- `[SSE-SMOKE-DIAG] device_id_available=true`
- `[SSE-SMOKE-DIAG] homeserver_url_available=true`
- `[SSE-SMOKE-DIAG] foreground_sse_start_requested=true`
- `[SSE-SMOKE-DIAG] foreground_sse_start_blocked_reason=none`
- `[SSE-SMOKE-DIAG] sse_configured=true`
- `[SSE-SMOKE-DIAG] sse_started=true`
- `[SSE-SMOKE-DIAG] sse_connected=true`
- `[SSE-SMOKE-DIAG] stream_failure=none`
- `[SSE-SMOKE-DIAG] raw_event_received=true`
- `[SSE-SMOKE-DIAG] sse_event_type=foreground.call.invite`
- `[SSE-SMOKE-DIAG] invite_parse_attempted=true`
- `[SSE-SMOKE-DIAG] invite_parse_succeeded=true`
- `[SSE-SMOKE-DIAG] pipeline_delivered=true`
- `[SSE-SMOKE-DIAG] invite_received=true`
- `[SSE-SMOKE-DIAG] invite_valid=true`
- `[SSE-SMOKE-DIAG] incoming_requested=true`
- `[SSE-SMOKE-DIAG] fallback_deduped=false`

The app later reported `transport_stopped=true` and `stream_failure=network` only after the supervised server restart used to disable the dev route. That late stop does not invalidate the invite-delivery pass.

After the smoke, `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=0` was restored, the call-service was restarted, and the public dev invite route returned `404`.

Raw runtime logs are intentionally omitted because they may contain private Matrix/runtime identifiers. The smoke did not request media credentials, connect media, emit Matrix events, add PushKit/APNs/background behavior, replace Element Call routing, or persist signing/project changes.

## 2.42J Guardrails

Status: added.

Server guardrails:

- Dev routes remain absent unless `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1`.
- Disabled `dev/invite` and `dev/inject-active` routes return not found.
- Enabled `dev/invite` still requires an authenticated session.
- Local-only `dev/inject-active` still requires localhost and exactly one active foreground SSE subscriber.
- Stream requests without auth return `401`, not a proxy or server routing failure.
- Server diagnostics for `invite_enqueued`, `invite_yielded`, `foreground.keepalive`, active-subscriber counts, and route results remain redacted.

iOS guardrails:

- `SalemXForegroundSSESmokeDebug` remains DEBUG-only.
- The active-session helper does not print, return, store, or document active credential values.
- Helper diagnostics remain booleans and safe enums only.
- Invite receipt still does not request media credentials, connect media, emit Matrix events, use PushKit/APNs/background behavior, or replace Element Call routing.

Timestamp guardrails:

- Current invites are accepted.
- Small server/device future skew is accepted.
- Excessive future timestamps are rejected.
- Expired invites are rejected.

Physical Debug build note:

- Use local command-line signing overrides only for supervised physical Debug builds.
- Current Team ID: `M639Y9MFR2`.
- Do not use old Team ID `83LGSC2QPV` for current physical Debug builds.
- Do not persist signing changes to `SalemX.xcodeproj/project.pbxproj`, `project.yml`, `app.yml`, `Info.plist`, or entitlements.

This proves `foreground.ready` parsing and active app session request construction.

## 2.42K Real Invite Result

Status: passed.

2.42K passed and was committed as:

```text
00b7db4db914eed61bb45cc51fff7082d15da323 Validate supervised foreground real invite
```

The pass used the authenticated non-dev foreground invite route:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite
```

The dev route stayed disabled throughout the real-invite smoke. The run did not use `dev/invite`, `dev/inject-active`, or `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1`.

Redacted pass evidence:

- sender `sender_invite_post_status=http_success`
- sender `sender_invite_delivery_report_received=true`
- server `active_subscriber_count=1`
- server `delivered=true`
- server `dropped=false`
- server `invite_enqueued=true`
- server `invite_yielded=true`
- server `sse_event_type=foreground.call.invite`
- receiver `sse_connected=true`
- receiver `stream_failure=none`
- receiver `raw_event_received=true`
- receiver `sse_event_type=foreground.call.invite`
- receiver `invite_parse_succeeded=true`
- receiver `pipeline_delivered=true`
- receiver `invite_received=true`
- receiver `invite_valid=true`
- receiver `incoming_requested=true`

Invite receipt did not request media credentials, connect media, emit Matrix events, add PushKit/APNs/background behavior, or replace Element Call routing.

## 2.42L Sender Token Guard

The first sender helper POST may hit a stale active-session token and return `http_unauthorized`. The 2.42L DEBUG-only guard handles this without exposing credentials:

- marks `sender_token_refresh_needed=true`
- asks the active session token provider for a value again
- retries the real non-dev invite route at most once
- reports only `sender_invite_retry_requested` and `sender_invite_retry_status`

No token, recipient, recipient device, call handle, request payload, private URL, or raw runtime log should be printed, returned, stored, or documented. If retry still does not reach `http_success`, keep the dev route disabled and rerun with the sender app foreground/authenticated after the SDK refresh settles.

## 2.42M1 DEBUG Real Invite Bridge

2.42M is a physical regression smoke after the 2.42L token guard. It is not marked passed yet.

The initial 2.42M attempt was blocked by LLDB invocation friction around the existing sender helper, not by server route state or a failed real-invite delivery. 2.42M1 adds a DEBUG-only local bridge:

```text
SalemXForegroundSSESmokeDebugBridge
```

Use the bridge only from the local supervised debugging session after the receiver foreground SSE stream is connected. Receiver identifiers are local-only sensitive inputs: do not paste them into chat, docs, terminal logs, tracked files, or final reports.

Command shape with placeholders only:

```lldb
expr -l objc++ -- [NSClassFromString(@"SalemXForegroundSSESmokeDebugBridge") sendRealInviteWithURLString:@"<REDACTED_REAL_INVITE_URL>" recipient:@"<LOCAL_RECIPIENT>" recipientDevice:@"<LOCAL_DEVICE>"]
continue
```

The bridge delegates to the existing DEBUG sender helper. It does not run automatically, store identifiers, expose tokens, weaken auth, use `dev/invite`, use `dev/inject-active`, request media credentials, connect media, emit Matrix events, add PushKit/APNs/background behavior, or replace Element Call routing.

## 2.42M2 DEBUG Receiver SSE Bridge

2.42M remains a pending physical regression smoke after the 2.42L token guard and the 2.42M1 sender bridge commit `751316429c5476217f7b881d9a2f542a4e7e3b3b`.

The latest 2.42M blocker was `receiver_sse_proof_blocked_by_coredevice_lldb_handshake`: receiver LLDB/CoreDevice handshakes were unstable, and no existing app-visible receiver SSE proof path was available. 2.42M2 adds a DEBUG-only receiver bridge:

```text
SalemXForegroundSSEReceiverSmokeDebugBridge
```

The bridge configures/starts/stops the existing active-session foreground SSE helper and returns a redacted state summary for supervised proof. It does not run automatically, store identifiers, expose tokens, weaken auth, use `dev/invite`, use `dev/inject-active`, request media credentials, connect media, emit Matrix events, add PushKit/APNs/background behavior, or replace Element Call routing.

Receiver identifiers remain local-only sensitive inputs and must not be pasted into chat, docs, terminal logs, tracked files, commits, or final reports. The next 2.42M physical regression smoke must still use the authenticated real non-dev invite route with the dev route disabled. Correct physical Debug builds use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.

The receiver summary is limited to:

- `sse_connected`
- `stream_failure`
- `raw_event_received`
- `sse_event_type`
- `invite_parse_attempted`
- `invite_parse_succeeded`
- `pipeline_delivered`
- `invite_received`
- `invite_valid`
- `incoming_requested`

## 2.42M3 DEBUG In-App Receiver Smoke Controls

2.42M remains pending and is not marked passed. The latest blocker was `receiver_sse_proof_unavailable`: receiver LLDB/CoreDevice expression evaluation was not reliable enough to activate the receiver stream and collect proof.

2.42M3 adds DEBUG-only in-app foreground smoke controls under Developer Options. Use these controls on the receiver to start the current-session foreground SSE stream and refresh the redacted receiver proof summary without receiver LLDB expression evaluation.

The controls use the real non-dev stream route and the existing active-session helper. They do not run automatically, persist identifiers, expose tokens, weaken auth, use `dev/invite`, use `dev/inject-active`, request media credentials, connect media, emit Matrix events, add PushKit/APNs/background behavior, or replace Element Call routing.

Receiver identifiers remain local-only sensitive inputs and must not be pasted into chat, docs, terminal logs, tracked files, commits, or final reports. The sender still uses local-only receiver identifiers when invoking the real non-dev invite path.

The next 2.42M physical regression smoke must:

- keep the receiver app foreground and authenticated
- start receiver SSE from the DEBUG-only in-app foreground smoke controls
- prove `sse_connected=true` and `stream_failure=none` from the in-app redacted proof summary
- invoke the sender bridge only after receiver proof is available
- use the authenticated real non-dev invite route only
- keep the dev route disabled

## 2.42M4 DEBUG Developer Options Entry

2.42M remains pending and is not marked passed. The latest blocker was `debug_smoke_controls_not_reachable_from_settings`: the 2.42M3 controls were present on Developer Options, but that screen was not reachable from the visible Settings UI.

2.42M4 exposes a DEBUG-only `Internal diagnostics` row in Settings that opens the existing Developer Options screen. Use this receiver path for the next physical smoke:

```text
Settings -> Internal diagnostics -> General -> Foreground SSE smoke
```

The row and smoke controls are DEBUG-only. They reuse the existing Developer Options and foreground SSE smoke proof path, and do not add production UI, persist identifiers, expose tokens, weaken auth, use `dev/invite`, use `dev/inject-active`, request media credentials, connect media, emit Matrix events, add PushKit/APNs/background behavior, or replace Element Call routing.

Receiver identifiers remain local-only sensitive inputs and must not be pasted into chat, docs, terminal logs, tracked files, commits, or final reports. Correct physical Debug builds use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.

## 2.42M Physical Regression Smoke Pass

2.42M passed the two-device physical foreground real-invite regression smoke after token guard hardening.

Relevant commits:

```text
9544d85090bb152f5c28d5acd11f37815556e078 Harden foreground real invite token handling
751316429c5476217f7b881d9a2f542a4e7e3b3b Add debug real invite smoke bridge
6c1c47b5386ed5051cea8ee0277719b4d2bd4cce Add debug receiver SSE smoke bridge
a579509c6ea7c294fa428370efa10bf875b053bb Add debug in-app foreground smoke controls
26a07771c22c8c3d615b9c34552f3b811510b724 Expose debug developer options entry
```

Receiver pre-invite proof was collected through DEBUG in-app controls:

```text
Settings -> Internal diagnostics -> General -> Foreground SSE smoke
sse_connected=true
stream_failure=none
```

The sender bridge was invoked locally only. Receiver identifiers were entered locally and were not printed, stored, pasted into chat, documented, committed, or otherwise recorded.

The pass used the authenticated real non-dev foreground invite route only. The dev route stayed disabled, unauthenticated non-dev invite remained `401`, and unauthenticated stream remained `401`.

Redacted pass evidence:

- Sender: `sender_helper_invoked=true`, `sender_active_session_available=true`, `sender_access_token_available=true`, `sender_invite_post_requested=true`, `sender_invite_post_status=http_success`, `sender_invite_delivery_report_received=true`, `sender_invite_blocked_reason=none`.
- Server: `stream_registered active_subscriber_count=1`, `ready_sent active_subscriber_count=1`, `subscriber_available=True`, `invite_enqueued=True`, `delivered=True`, `dropped=False`, `invite_yielded sse_event_type=foreground.call.invite active_subscriber_count=1`.
- Receiver: `raw_event_received=true`, `sse_event_type=foreground.call.invite`, `invite_parse_attempted=true`, `invite_parse_succeeded=true`, `pipeline_delivered=true`, `invite_received=true`, `invite_valid=true`, `incoming_requested=true`.

The smoke did not use `dev/invite`, `dev/inject-active`, `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1`, media credentials, media connection, PushKit/APNs/background paths, or Matrix event emission from invite receipt.

Correct physical Debug builds use `DEVELOPMENT_TEAM=M639Y9MFR2`; the old `83LGSC2QPV` team must not be used.

## Redacted Diagnostics To Collect

Record only safe booleans and timing buckets:

- `sse_configured`
- `sse_started`
- `sse_connected`
- `invite_received`
- `invite_valid`
- `incoming_requested`
- `fallback_deduped`
- `transport_stopped`
- `stream_failure`
- `sender_token_refresh_needed`
- `sender_token_refresh_attempted`
- `sender_token_refresh_succeeded`
- `sender_invite_retry_requested`
- `sender_invite_retry_status`
- SSE connect elapsed bucket
- invite-to-incoming elapsed bucket

Full runtime logs must not be pasted into docs because they can contain private Matrix/runtime values.

## Expected Smoke Flow

1. Start the call-service in local or staging supervision.
2. Enable the dev invite route for the supervised window.
3. Launch the iPhone Debug app in foreground with an authenticated session.
4. Explicitly start the DEBUG foreground SSE runtime owner through the active-session LLDB smoke bridge.
5. Confirm `helper_invoked=true`.
6. Confirm `foreground_sse_start_requested=true`.
7. Confirm `sse_configured=true`.
8. Confirm `sse_started=true`.
9. Confirm `sse_connected=true`.
10. Submit one opaque dev invite through the local-only self-injection route while exactly one foreground SSE subscriber is active.
11. Confirm `invite_received=true`.
12. Confirm `invite_valid=true`.
13. Confirm `incoming_requested=true`.
14. Confirm CallKit appears within 0-2 seconds of invite delivery.
15. Confirm invite receipt does not request media credentials before Answer.
16. Confirm invite receipt does not connect media before Answer.
17. Stop the DEBUG owner and confirm `transport_stopped=true`.
16. Disable the dev invite route.

## Pass Criteria

- iPhone app is foreground/open.
- Authenticated session is available.
- SSE runtime owner is explicitly configured and started.
- Server dev invite route is enabled only during supervision.
- SSE stream receives the invite.
- `invite_valid=true`.
- `incoming_requested=true`.
- CallKit appears within 0-2 seconds.
- No media credential request occurs before Answer.
- No media connection occurs before Answer.
- No Matrix event is emitted from invite receipt.
- No crash occurs.
- Raw runtime logs are omitted from docs.

## Fail Criteria

- SSE stream cannot connect.
- Invite is not received.
- Invite is received but fails validation unexpectedly.
- Incoming/CallKit path is not requested.
- CallKit appears only after Matrix room-list/timeline fallback.
- Fallback duplicate is not de-duped.
- Media credential request or media connection happens before Answer.
- Raw runtime identifiers are required to understand the result.
- Dev invite route remains enabled after the supervised window.

## Out Of Scope

This phase does not add:

- PushKit runtime;
- APNs or VoIP value registration;
- background incoming behavior;
- production SSE enablement;
- hardcoded production URLs;
- hardcoded credential values;
- media credential request from invite receipt;
- media connection from invite receipt;
- Matrix event emission from invite receipt;
- Element Call route replacement;
- signing, entitlement, bundle, `Info.plist`, `app.yml`, or project setting changes.

## Next Phase

Recommended next phase: production configuration and rollout design for the authenticated foreground SSE path.

That phase should define a non-DEBUG configuration boundary for foreground-only SSE startup, keep the dev routes disabled by default, preserve server-issued media credential authority, and keep media credential request/media connection blocked until Answer.
