# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.42m3-in-app-foreground-smoke-controls`

Next phase: run 2.42M physical regression smoke after the DEBUG sender bridge, receiver bridge, and in-app receiver smoke controls.

## Context

- 2.42I passed and was committed as `a4d427f5b07e662695ce108530bbafc9bfdd9399` (`Validate supervised foreground SSE smoke`).
- 2.42J guardrails were committed as `c2fbc505dad52be2413d16fa23c55f9f7594632f` (`Harden supervised foreground SSE guardrails`).
- 2.42K passed and was committed as `00b7db4db914eed61bb45cc51fff7082d15da323` (`Validate supervised foreground real invite`).
- 2.42L was committed as `9544d85090bb152f5c28d5acd11f37815556e078` (`Harden foreground real invite token handling`).
- 2.42L added a DEBUG-only stale-token guard for the sender helper. If the first real-invite POST returns `http_unauthorized`, it asks the active session token provider again and retries at most once. Diagnostics remain redacted.
- 2.42M was blocked by LLDB invocation friction, not by server route state or a failed real-invite delivery.
- 2.42M1 adds `SalemXForegroundSSESmokeDebugBridge`, a DEBUG-only local bridge that forwards to the existing sender helper with an easier Objective-C selector.
- 2.42M1 bridge commit is `751316429c5476217f7b881d9a2f542a4e7e3b3b`.
- 2.42M later hit `receiver_sse_proof_blocked_by_coredevice_lldb_handshake`, so receiver LLDB/CoreDevice attach is not a reliable proof source.
- 2.42M2 adds `SalemXForegroundSSEReceiverSmokeDebugBridge`, a DEBUG-only receiver bridge/proof path that configures/starts/stops the existing active-session SSE helper and returns only redacted state summary fields.
- 2.42M then hit `receiver_sse_proof_unavailable`: the receiver bridge existed, but receiver LLDB/CoreDevice expression evaluation was not reliable enough to activate the stream and collect proof.
- 2.42M3 adds DEBUG-only in-app foreground smoke controls under Developer Options so the receiver can start foreground SSE and refresh redacted proof without receiver LLDB.
- The 2.42M physical regression smoke is not marked passed yet.

## Required Smoke

Run the two-device physical foreground real-invite regression smoke using the authenticated non-dev route only:

```text
/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite
```

Do not use:

- `dev/invite`
- `dev/inject-active`
- `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1`

Receiver:

- Keep the receiver app foreground and authenticated.
- Open foreground SSE first from the DEBUG-only in-app foreground smoke controls in Developer Options.
- Confirm `sse_connected=true` and `stream_failure=none` from the in-app redacted receiver proof summary.
- Do not record receiver identifiers, raw URLs with secrets, tokens, request payloads, or private logs.

Sender:

- Keep the sender app foreground and authenticated.
- Use `SalemXForegroundSSESmokeDebugBridge` from local LLDB with receiver identifiers entered locally only.
- Receiver identifiers must not be pasted into chat, terminal output, docs, tracked files, commits, or final reports.

Command shape with placeholders only:

```lldb
expr -l objc++ -- [NSClassFromString(@"SalemXForegroundSSESmokeDebugBridge") sendRealInviteWithURLString:@"<REDACTED_REAL_INVITE_URL>" recipient:@"<LOCAL_RECIPIENT>" recipientDevice:@"<LOCAL_DEVICE>"]
continue
```

## Pass Evidence

Collect only redacted diagnostics:

- sender `sender_helper_invoked=true`
- sender `sender_active_session_available=true`
- sender `sender_access_token_available=true`
- sender `sender_invite_post_requested=true`
- sender `sender_invite_post_status=http_success`, or `http_unauthorized` followed by `sender_invite_retry_status=http_success`
- sender `sender_invite_delivery_report_received=true`
- sender `sender_invite_blocked_reason=none`
- server `delivered=True`
- server `dropped=False`
- server `invite_enqueued=True`
- server `invite_yielded=True`
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

## Safety

- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, `Info.plist`, `app.yml`, `project.yml`, or project settings.
- Do not replace Element Call routing.
- Do not hardcode production server URLs or credential values.
- Do not request media credentials from invite receipt.
- Do not connect media from invite receipt.
- Do not emit Matrix call events from invite receipt.
- Do not add raw account, room, device, event, credential, media-session, private runtime log, request payload, call handle, recipient, or credential-shaped fixture values.
- Do not stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.

Physical Debug builds should use local command-line signing overrides only:

- `DEVELOPMENT_TEAM=M639Y9MFR2`
- `CODE_SIGN_STYLE=Automatic`
- `-allowProvisioningUpdates`
- `-allowProvisioningDeviceRegistration`

Do not use old Team ID `83LGSC2QPV`.
Do not persist signing changes.

## Server Safety

Before and after the smoke, confirm:

```text
salemx-call-service active
dev/invite=404
unauthenticated non-dev invite=401
unauthenticated stream=401
```

## 2.42M2 DEBUG Receiver SSE Bridge

The receiver bridge is DEBUG-only and local to supervised smoke. It does not run automatically, store identifiers, expose tokens, weaken auth, use `dev/invite`, use `dev/inject-active`, request media credentials, connect media, emit Matrix events, add PushKit/APNs/background behavior, or replace Element Call routing.

Its redacted state summary may include only:

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

Full runtime logs must not be pasted into docs because they can contain private Matrix/runtime values. The 2.42M physical regression smoke is still pending until a two-device real non-dev route pass is collected.
