# Supervised Foreground SSE Smoke

## 2.42I - Supervised Foreground SSE Smoke Preparation

Status: prepared; physical-device smoke pending.

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

## Placeholder Dev Invite Command

This is a placeholder shape only. Replace placeholders locally during supervision and do not paste the resolved command or raw output into docs.

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
- SSE connect elapsed bucket
- invite-to-incoming elapsed bucket

Full runtime logs must not be pasted into docs because they can contain private Matrix/runtime values.

## Expected Smoke Flow

1. Start the call-service in local or staging supervision.
2. Enable the dev invite route for the supervised window.
3. Launch the iPhone Debug app in foreground with an authenticated session.
4. Explicitly configure and start the DEBUG foreground SSE runtime owner.
5. Confirm `sse_configured=true`.
6. Confirm `sse_started=true`.
7. Confirm `sse_connected=true`.
8. Submit one opaque dev invite through the supervised route.
9. Confirm `invite_received=true`.
10. Confirm `invite_valid=true`.
11. Confirm `incoming_requested=true`.
12. Confirm CallKit appears within 0-2 seconds of invite delivery.
13. Confirm invite receipt does not request media credentials before Answer.
14. Confirm invite receipt does not connect media before Answer.
15. Stop the DEBUG owner and confirm `transport_stopped=true`.
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

Recommended next phase: `2.42I-S - supervised foreground SSE physical smoke`.

That phase should run the prepared smoke, record only redacted diagnostics and timing buckets, then immediately disable the dev invite route.
