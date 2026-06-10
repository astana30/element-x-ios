# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.42g-supervised-foreground-sse-smoke

Next phase: 2.42G - supervised foreground SSE smoke.

Goal:
Run a supervised local or staging smoke proving that the foreground SSE stream can deliver a dev-only opaque invite to an active iOS foreground subscriber without waiting for Matrix room-list/timeline sync.

Context:
- 2.42D added the authenticated foreground SSE stream endpoint.
- 2.42E added the disabled/configured iOS SSE transport client boundary.
- 2.42F added a disabled-by-default supervised dev invite source.
- The dev invite route is `POST /_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/dev/invite`.
- The dev invite route is registered only when `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1` is set.
- The dev route targets only the authenticated foreground subscriber for the same active session/device.
- Invite receipt must remain side-effect-free for media and Matrix events.

Scope:
- Start the call-service with foreground SSE enabled and the dev invite flag enabled only in local or staging supervision.
- Open the iOS foreground SSE transport from an active foreground session.
- Inject one safe opaque dev invite into the active subscriber.
- Verify the iOS foreground incoming/CallKit request path is triggered promptly.
- Verify timeline/room-list fallback does not duplicate the incoming UI.
- Verify invite receipt does not request media credentials, connect media, or emit Matrix call events.
- Keep runtime logs redacted and do not paste raw logs into docs.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, or project settings.
- Do not replace Element Call routing.
- Do not hardcode production server URLs or credential values.
- Do not bypass server-issued media credential authority.
- Do not connect media from invite receipt.
- Do not emit Matrix call events from invite receipt.
- Do not add raw account, room, device, event, auth credential, push/media, Apple signing, media-session, track, participant, private runtime log, or credential-shaped fixture values.

Expected output:
- Redacted supervised smoke report.
- Timing for foreground SSE invite receipt and incoming/CallKit request.
- Whether duplicate fallback UI occurred.
- Whether media credential request and media connection stayed blocked before answer.
- Updated docs/status/worklog/next prompt.
- Confirmation that PushKit/APNs/background/signing/project/Element Call route remain unchanged.
