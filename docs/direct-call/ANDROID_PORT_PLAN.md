# SalemX Native Direct-Call Android Port Plan

## Goal

Port the SalemX native 1:1 direct-call stack to Android so Android and iOS interoperate using the same Matrix signalling schema, SDK key-envelope format, backend token contract, LiveKit media behavior, timeout semantics, and fail-closed rules.

The Android work should begin with diagnostics and cross-platform proofs, not visible UI.

## Ground Rules

- Keep production direct calls disabled until protocol, backend, key wrapping, and media proofs pass.
- Do not route through Element Call.
- Do not add visible call UI in the first porting phases.
- Do not add CallKit-equivalent platform integration or push handling yet.
- Do not place LiveKit credentials in Matrix signalling.
- Do not place unwrapped media-key material in Matrix signalling.
- Do not log credentials, event bodies, or media-key material.
- Keep diagnostic and production paths separate.

## Recommended Starting Point

Fork or branch from Element X Android and preserve the Matrix Rust SDK architecture. The Android implementation should wrap SDK functionality behind narrow app-owned services, mirroring the iOS approach without exposing broad raw SDK or timeline APIs to product code.

## Phase 1 — Shared Protocol Models

Implement app-owned Kotlin models for the shared v1 protocol:

- Signal event type: `kz.salemx.direct_call.signal`.
- Signal kinds: `invite`, `answer`, `hangup`, `cancel`, `reject`, `timeout`.
- Intent: initial supported value `audio`.
- Required metadata: version, call ID, room binding, sender, recipient, created time, expiry, key ID.
- Key exchange: SDK-produced opaque envelope only.
- Terminal reason enum matching iOS semantics.

Tests:

- Encode/decode valid invite.
- Encode/decode answer and terminal events.
- Unsupported version fails closed.
- Unsupported intent fails closed.
- Missing key envelope on invite fails closed.
- Terminal event with key envelope fails closed.
- Descriptions/loggable strings redact envelope and credentials.

## Phase 2 — Matrix Custom Event Send/Receive

Implement sending and receiving of the message-like custom Matrix event.

Requirements:

- Send `kz.salemx.direct_call.signal` into the encrypted Matrix DM room.
- Use SDK-backed event content APIs, not raw event JSON.
- Implement a direct-call receive source that includes this custom message-like event type.
- Do not make the event visible in the normal room timeline UI.
- Ignore initial timeline reset/backlog.
- Establish a listener baseline and deliver only live events observed after that baseline.
- Ignore own events, duplicate event IDs, wrong recipients, unsupported types, and malformed content.

If Android's timeline provider filters out custom message-like events in the same way iOS did, add a narrow SDK/wrapper seam equivalent to iOS's custom timeline filter. Prefer an upstream-friendly API that allows a specific custom message-like event type in addition to the default UI timeline events.

Tests:

- Initial backlog invite is counted diagnostically but not delivered to the engine.
- Live invite after baseline is delivered.
- Duplicate event ID is ignored.
- Own event is ignored.
- Wrong recipient is ignored.
- Custom direct-call event does not appear in visible room UI timeline.

## Phase 3 — Direct-Call Engine State Machine

Implement or port the direct-call engine with matching states and terminal behavior.

Required states:

- `idle`
- `outgoingRinging`
- `incomingRinging`
- `connecting`
- `active`
- `failed` or terminal

Timeouts should match iOS defaults unless both platforms intentionally revise the protocol:

- Ringing timeout: 45 seconds.
- Connecting timeout: 20 seconds.
- Cleanup delay: 2 seconds.

Tests:

- Outgoing invite moves to outgoing ringing.
- Live incoming invite moves to incoming ringing.
- Accept emits answer.
- Terminal events clear the session.
- Timeout emits/handles compatible terminal reason.
- Metadata mismatch fails closed.

## Phase 4 — SDK Media Key Envelope Wrapper

Implement the Android equivalent of the Matrix SDK direct-call media key envelope seam.

Requirements:

- Wrap per-call media key material for eligible peer devices.
- Produce an opaque envelope for Matrix signalling.
- Unwrap only on intended recipient devices.
- Bind and verify call ID, room ID, sender, recipient, intent, key ID, and expiry.
- Fail closed for wrong metadata, unsupported version, unknown device policy, malformed envelope, or unwrap failure.
- Keep media-key material inside the encryption/key-store boundary.

Tests:

- Android wraps and unwraps locally with two test devices.
- Wrong call ID fails.
- Wrong room ID fails.
- Wrong sender or recipient fails.
- Non-recipient device cannot unwrap.
- Envelope output does not contain media-key plaintext.
- Debug strings redact envelope and key material.

## Phase 5 — Backend Token Client

Implement the same production token endpoint contract as iOS:

```text
POST /_matrix/client/unstable/kz.salemx.direct_call/livekit/token
```

Requirements:

- Authenticate with the logged-in Matrix session credential.
- Request a token for call ID, room ID, peer user ID, intent, direction, device ID, and client transaction ID.
- Treat backend failures as fail-closed media setup failures.
- Do not call LiveKit APIs directly with an API secret from the app.
- Do not log request or response bodies.
- Do not include LiveKit credentials in Matrix signalling.

Tests:

- Successful backend-shaped response maps to media connection info.
- 401/403/404/429/500 fail closed.
- Malformed response fails closed.
- Unsupported intent fails closed.
- Descriptions redact credentials and endpoint values according to platform policy.

## Phase 6 — LiveKit Android E2EE Bridge

Implement the Android LiveKit media bridge after signalling and key-envelope proofs are stable.

Requirements:

- Allocate/reuse the same LiveKit room for `room_id + call_id + intent` through the backend.
- Use token scoped to one LiveKit room.
- Build the LiveKit E2EE context from the unwrapped Matrix key-envelope result.
- Do not publish microphone before explicit user action.
- First diagnostic media proof may connect with microphone publishing disabled.
- Do not expect visible audio UI in the first proof.

Tests:

- Missing token provider fails closed.
- Missing E2EE key handle fails closed.
- Missing LiveKit client fails closed.
- Fake LiveKit client connect is attempted only after answer and key unwrap.
- No microphone publish before explicit user action.

## Phase 7 — Diagnostic Harness Before UI

Start with a debug/internal diagnostic harness equivalent to iOS.

Recommended commands:

- status
- prepare
- start listener
- start outgoing audio call
- accept incoming call
- hangup
- production activation dry-run

Diagnostics must be redacted and should expose only booleans/enums/counters such as:

- listener attached
- live update count
- direct-call event seen count
- envelope extracted count
- envelope delivered count
- active session phase
- last terminal reason
- media setup reason

Diagnostics must not include credentials, event bodies, peer-specific secrets, LiveKit URLs, or media-key material.

## Phase 8 — Cross-Platform Proof Matrix

Complete these proofs before visible UI work:

1. Android sends invite, iOS receives incoming ringing.
2. iOS sends invite, Android receives incoming ringing.
3. Android accepts iOS invite and iOS receives answer.
4. iOS accepts Android invite and Android receives answer.
5. Android and iOS both reach LiveKit active state in diagnostic mode.
6. Historical backlog invite is ignored on both platforms.
7. Wrong recipient and duplicate events are ignored on both platforms.
8. Terminal event semantics match on both platforms.

## Phase 9 — Production Activation Readiness

Only after diagnostics pass, add a disabled-by-default production readiness layer matching iOS:

- App-owned rollout source defaults false.
- Authenticated server capability `kz.salemx.direct_call.native` is required.
- Token endpoint must be same-origin and accepted by the activation gate.
- Runtime dependencies must be ready.
- Room must be encrypted direct 1:1.
- Dry-run diagnostics must be side-effect-free.

Production activation must not start listeners, construct media engines, send Matrix events, or show UI until a later product phase explicitly enables it.

## Phase 10 — UI Later

Visible UI comes after protocol and media proofs.

Before UI activation:

- Product copy and accessibility are defined.
- Call controls are implemented using platform design system patterns.
- Mic permission flow is explicit.
- CallKit-equivalent and push strategy are designed separately.
- Element Call route remains separate unless a later product decision changes it.

## Android Interop Checklist

- Same event type as iOS.
- Same v1 signal schema.
- Same key-envelope algorithm identifier.
- Same backend token endpoint.
- Same timeout and terminal reason semantics.
- Same historical backlog ignore rule.
- Same fail-closed policy.
- Same no-credential/no-key-material Matrix signalling policy.
- Same diagnostic redaction policy.

## Open Questions

- Final production peer-device trust policy for unknown or unverified devices.
- Whether answer-side key material is needed in a future protocol version.
- Whether Android requires an SDK custom timeline filter or can use a narrower room-event receive source.
- Exact Android LiveKit E2EE API shape and key-provider lifecycle.
- Production UI timing, CallKit-equivalent behavior, and push integration.
