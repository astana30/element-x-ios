# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.47a-controlled-media-credentials-boundary`

Expected intentionally untracked file:
`docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`

Do not stage or commit that diagnostics file.

## Latest Completed State

2.48A planned the controlled media-connect preflight boundary. This was docs-only; no runtime behavior changed.

Closed prerequisites:
- 2.47C physical controlled media credentials request succeeded with no media connect.
- 2.47D physical credentials cleanup / expiry proof succeeded.
- 2.47E server-side allocation/token expiry verification succeeded without LiveKit join.

Relevant existing seams:
- Credentials-only request: `DirectCallEngine.requestMediaCredentials(callID:)`.
- Future connect transition: `DirectCallEngine.connectMediaIfReady(for:keyHandle:)`.
- Media abstraction: `DirectCallMediaEngineProtocol`.
- Real LiveKit implementation: `LiveKitDirectCallMediaEngine`.
- LiveKit client seam: `DirectCallLiveKitClientProtocol`.
- E2EE context seam: `DirectCallMediaE2EEContextProviderProtocol`.
- Audio route seam: `DirectCallAudioRouteControllerProtocol`.
- Token provider seam: `DirectCallLiveKitTokenProvider`.

## Phase

`2.48B — controlled media connect preflight, no LiveKit join`

## Goal

Implement the smallest DEBUG-only preflight boundary after controlled credentials receipt and before any real media connection. The proof may validate that inputs required for a later connect are present and redacted, but it must not connect to LiveKit or request microphone/camera permissions.

## Guardrails

- The boundary must be disabled by default and DEBUG-only.
- It must require the already-proven pending metadata and media credential success state.
- It must not call `DirectCallEngine.connectMediaIfReady`.
- It must not call `LiveKitDirectCallMediaEngine.connectAudio`.
- It must not call `DirectCallLiveKitClientProtocol.connect`.
- It must not request microphone/camera permission.
- It must not emit Matrix events.
- It must not transition the session to active media.
- It must not persist raw token, URL, room name, call ID, room ID, peer/user/device ID, auth header, payload, or key material.

## Proposed Proof Fields

Required true/enum proof:

```text
media_connect_preflight_boundary_reached=true
media_connect_preflight_requested=true
media_connect_preflight_authorized=true
media_connect_preflight_result=ready_redacted|blocked_redacted
media_connect_preflight_source=authenticated_pending_metadata_fetch
media_connect_preflight_credentials_available=true
media_connect_preflight_credentials_redacted=true
media_connect_preflight_e2ee_context_required=true
media_connect_preflight_e2ee_context_available=true|false
media_connect_preflight_key_handle_required=true
media_connect_preflight_key_handle_available=true|false
media_connect_preflight_audio_route_checked=true
media_connect_preflight_audio_route_result=ready_redacted|blocked_redacted|not_requested
media_connect_preflight_cleanup_requested=true
media_connect_preflight_cleanup_result=cleared
```

Fields that must stay false:

```text
media_connect_requested=false
media_connect_attempted=false
livekit_join_requested=false
livekit_client_connect_attempted=false
microphone_permission_requested=false
camera_permission_requested=false
matrix_event_emit_requested=false
real_call_flow_started=false
```

Expected success blocker:

```text
blocked_reason=none
```

Allowed blocked result:

```text
media_connect_preflight_result=blocked_redacted
blocked_reason=media_connect_preflight_not_ready
```

## Required Tests Before Any Future Physical Connect

- Preflight runs only under the explicit DEBUG controlled boundary.
- Preflight requires authenticated pending metadata and credentials success proof.
- Preflight records credential presence/redaction without storing raw token or URL.
- Preflight can prove E2EE context/key-handle/audio-route readiness with redacted booleans/enums.
- Preflight cleanup clears any transient token/URL/key-handle references.
- Preflight does not call `connectAudio`.
- Preflight does not call `DirectCallLiveKitClientProtocol.connect`.
- Preflight does not request microphone/camera permissions.
- Preflight does not emit Matrix events.
- Preflight does not start full direct-call flow.
- Failure paths remain fail-closed and redacted.

## Rollback / Kill Switch Requirements

- One DEBUG flag or operator action must disable the preflight boundary.
- Existing product/private dogfood gates must remain insufficient to run this preflight unless the new explicit controlled boundary is also enabled.
- If preflight fails, clear transient credentials/key references and keep media/join/mic/camera/Matrix/full-flow proof fields false.
- If any forbidden operation is observed, stop immediately and do not proceed to physical media-connect planning.

## Hard Constraints

- Do not send APNs unless explicitly requested.
- Do not use `dev/invite`.
- Do not send production APNs.
- Do not connect media.
- Do not join LiveKit.
- Do not request microphone/camera permissions.
- Do not emit Matrix events.
- Do not start full call flow.
- Do not expose raw PushKit/APNs tokens, keys, JWTs, authorization headers, Matrix access tokens, APNs payloads, invite bodies, private logs, user IDs, device IDs, room IDs, call IDs, call handles, LiveKit URLs/tokens, room names, key material, or secret-bearing URLs.
- Do not touch project/signing/entitlement/`Info.plist`/`app.yml` files.
