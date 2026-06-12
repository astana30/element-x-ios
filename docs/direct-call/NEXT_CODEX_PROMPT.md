# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.42m-foreground-real-invite-token-guard-smoke`

Next phase: continue after the 2.42M physical foreground real-invite regression smoke pass.

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
- 2.42M then hit `debug_smoke_controls_not_reachable_from_settings`: the 2.42M3 controls were present on Developer Options, but that screen was not reachable from the visible Settings UI.
- 2.42M4 exposes a DEBUG-only `Internal diagnostics` row in Settings that opens the existing Developer Options screen.
- 2.42M physical regression smoke passed on two physical iPhones after token guard hardening and M1-M4 DEBUG smoke tooling.
- Receiver pre-invite proof was collected through DEBUG in-app controls at `Settings -> Internal diagnostics -> General -> Foreground SSE smoke`.
- The sender bridge was invoked locally only; receiver identifiers were typed locally and were not recorded, printed, stored, pasted into chat, documented, or committed.
- The real authenticated non-dev invite route was used. The dev route remained disabled, unauthenticated non-dev invite remained `401`, and unauthenticated stream remained `401`.
- No media credentials, media connection, PushKit/APNs/background path, Matrix event emission from invite receipt, or Element Call route replacement was used.

## 2.42M Redacted Pass Evidence

Sender:

```text
sender_helper_invoked=true
sender_active_session_available=true
sender_access_token_available=true
sender_invite_post_requested=true
sender_invite_post_status=http_success
sender_invite_delivery_report_received=true
sender_invite_blocked_reason=none
```

Server:

```text
stream_registered active_subscriber_count=1
ready_sent active_subscriber_count=1
subscriber_available=True
invite_enqueued=True
delivered=True
dropped=False
invite_yielded sse_event_type=foreground.call.invite active_subscriber_count=1
```

Receiver:

```text
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
