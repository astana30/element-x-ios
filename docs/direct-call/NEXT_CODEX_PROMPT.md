# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.47E server-side allocation/token expiry verification is closed as a no-join server proof.

Proven:
- real invite/APNs/PushKit/CallKit Answer remains previously proven;
- authenticated pending metadata fetch remains previously proven;
- controlled media credentials request and cleanup remain previously proven;
- participant token expiry is bounded;
- allocation TTL is bounded and intentionally longer than token expiry;
- repeated credentials requests reuse only the active allocation and issue fresh bounded tokens;
- expired allocation state cannot be reused;
- server verification does not join LiveKit or require a LiveKit media session;
- successful token issuance logs use redacted allocation/call hashes only.

Safety remained:
- no APNs in 2.47E;
- no production APNs;
- no repeated APNs;
- no media connect;
- no LiveKit join;
- no microphone/camera permission request;
- no Matrix event emission;
- no full direct-call flow;
- no raw token/JWT/auth header/payload/ID/LiveKit URL exposure;
- no project/signing/entitlements/`Info.plist`/`app.yml` changes.

## Next Task

Start `2.47F — controlled media connect preflight, no join`.

Goal:
Design and prove the smallest controlled media-connect preflight boundary without joining LiveKit or requesting microphone/camera permissions.

Do not:
- send APNs unless explicitly requested;
- use `dev/invite`;
- send production APNs;
- connect media;
- join LiveKit;
- request microphone/camera permissions;
- emit Matrix events;
- start full call flow;
- expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, or secret-bearing URLs;
- touch project/signing/entitlement/`Info.plist`/`app.yml` files.
