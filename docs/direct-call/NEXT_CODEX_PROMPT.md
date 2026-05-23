# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.31B — side-effect-safe eligibility status cache skeleton.

Current checkpoints:
- App room-card UX/status hardening: 2.29D `Harden native audio card failure copy` (`71056f143`).
- App split-brain fix: 2.27D `Fail closed caller when callee media setup fails after answer` (`38fa26586`).
- App activation gate cleanup: 2.26D `Clarify native call private dogfood activation gate` (`76f2064ca`).
- App listener preparation: 2.26E `Enable private dogfood card listener preparation` (`07256bf0a`).
- Product-card-only staging smoke documentation: 2.26E `Record product-card-only staging smoke` (`01e8dc1cb`).
- Call-service LiveKit room pre-create: 2.25E implemented server-side RoomService `CreateRoom` before participant token issuance (`33e95e7b1`).
- Controlled dogfood operations checklist: 2.28A recorded in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- Controlled dogfood pilot session 1: 2.28B recorded in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- Controlled dogfood pilot session 2: 2.28C recorded in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- Broader internal dogfood hardening plan: 2.29B recorded in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- Redacted pilot monitoring contract: 2.29E recorded in `docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md`.
- Internal pilot eligibility contract skeleton: 2.30B added typed fail-closed app models, a redacted payload shape, safe card-copy mapping for account/peer ineligibility, and docs.
- Eligibility runtime/no-activation proof: 2.30C confirmed product UI/start gates without private dogfood still fail closed, and controlled engineering dogfood still reaches active audio under explicit private dogfood gates.
- Backend eligibility endpoint skeleton: 2.30E added the disabled-by-default call-service `/eligibility` endpoint, static allowlist policy skeleton, redacted readiness booleans, and token endpoint enforcement before rate limit/allocation/LiveKit room pre-create/token issuance.
- Eligibility endpoint local route smoke: 2.30F proved default fail-closed `/eligibility`, token endpoint enforcement before allocation/pre-create/token issuance, explicit allowlisted positive route behavior, negative route cases, and redacted output.
- iOS eligibility provider skeleton: 2.30H added a redacted request DTO, optional `capability_present` / `capabilityPresent` response decoding, and an HTTP provider skeleton for the backend `/eligibility` endpoint without wiring non-engineering activation.
- iOS eligibility provider no-activation proof: 2.30I proved product UI/start gates without the private dogfood gate remain blocked with `appRolloutDisabled`, the iOS provider skeleton remains unwired for non-engineering activation, and controlled engineering dogfood still reaches active audio under the explicit private dogfood gate.
- Eligibility status cache skeleton: 2.31B added a disabled-by-default DEBUG/integration status gate, room-flow scoped in-memory cache, safe card-status merge, manual refresh bypass, and tests proving backend eligibility status does not activate native audio.
- SDK: f7c2cfe5c `Add direct-call media key envelope crypto tests`.
- Wrapper: 1e58d0a `Add direct-call media key envelope bindings`.

Current proven/prepared state:
- Product-card-only staging happy path passed under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`.
- Without `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`, activation remains blocked with `appRolloutDisabled`, with no Matrix send, token/media path, or LiveKit client connect.
- The legacy `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` name was explicitly unset and is not used for staging pilot proof.
- Manual private-card Start, Accept, and Hang up passed on staging in 2.26E: A/B reached `productionSessionState=activeAudio`, then hangup returned A/B to `productionSessionState=idle` with `productionMediaFailureReason=none`.
- Receiver listener preparation is limited to private-card status after activation is already enabled; it does not start outgoing calls, request tokens, send Matrix events, or connect media.
- 2.27D fixed the split-brain state where callee could emit answer, fail media/token setup, and leave caller active.
- 2.27E runtime proof passed:
  - preflight readiness/trust passed;
  - two normal repeated A -> B calls reached `activeAudio`, then hangup returned A/B to `idle`;
  - forced callee post-answer token/backend failure made B fail closed with `tokenHTTPUnavailable`;
  - A received the terminal path and did not remain `activeAudio`;
  - recovery after restoring B to the normal staging URL reached A/B `activeAudio`, then hangup returned A/B to `idle`;
  - Element Call route remained untouched and no code changed during the runtime proof.
- 2.27F controlled dogfood matrix rerun passed:
  - preflight readiness/trust passed;
  - happy path, reverse direction, repeated calls, decline, cancel, timeout, backend-off, backend recovery, relaunch active, relaunch ringing, and listener/open-room unavailable cases passed;
  - backend-off immediate accept failed closed with `connectingFailed`, `tokenHTTPUnavailable`, and no LiveKit client connect;
  - LiveKit-off was not run because the staging LiveKit instance is shared;
  - runner commands were used for matrix control/status, so this is not a claim that every matrix case was manually product-card-only;
  - final A/B status was idle/no active session with media failure `none`;
  - Element Call route remained untouched and no code changed during the runtime proof.
- 2.28A operations checklist is recorded:
  - named operator and participant sign-off;
  - staging call-service ownership and local start/stop procedure;
  - Redis/call-service readiness checks;
  - A/B gate, trust, private-card, and stale-session checks;
  - redacted monitoring fields and forbidden outputs;
  - failure triage matrix;
  - stop criteria and rollback;
  - post-session report template;
  - security cleanup for temporary SSH keys, disposable reports, password rotation, and ignored env files.
- 2.28B controlled dogfood pilot session 1 passed:
  - preflight readiness/trust passed;
  - required private dogfood gates were used, and the legacy fake/dry-run gate was unset;
  - manual private-card happy path A -> B, reverse B -> A, and repeated call reached `activeAudio`, then returned A/B to `idle` with media failure `none`;
  - manual private-card decline, cancel, timeout, and relaunch fail-closed cases returned A/B to safe idle/no-active-session state;
  - backend-off recovery was not repeated in this manual pilot because the local staging call-service stayed up for the session;
  - LiveKit-off was not run because the staging LiveKit instance is shared;
  - runner use was limited to launch, readiness/trust/status polling, and relaunch;
  - no rollback was needed, no stop criteria triggered, no runtime bug was observed, no redaction issue was found, and Element Call remained untouched.
- 2.28C controlled dogfood pilot session 2 passed:
  - preflight readiness/trust passed;
  - required private dogfood gates were used, and the legacy fake/dry-run gate was unset;
  - manual private-card happy path A -> B and reverse B -> A reached `activeAudio`, then returned A/B to `idle` with media failure `none`;
  - two back-to-back repeated A -> B calls reached active audio and returned idle with no stale session and no split-brain;
  - decline and cancel returned A/B idle with terminal `cancelled`;
  - relaunch from an active session restored no active session and no media path;
  - timeout was not repeated because it is already covered by session 1 and the 2.27F matrix;
  - backend-off recovery was not repeated because the local staging call-service stayed up for the session;
  - LiveKit-off was not run because the staging LiveKit instance is shared;
  - runner use was limited to launch, readiness/trust/status polling, and relaunch;
  - no rollback was needed, no stop criteria triggered, no runtime bug was observed, no redaction issue was found, and Element Call remained untouched.
- 2.29A/2.29B decision:
  - two successful controlled engineering sessions are not enough for broader internal dogfood or non-engineering users;
  - controlled engineering dogfood may continue and slightly expand only to more named engineering operators/devices on the same staging path;
  - the future non-engineering internal pilot remains blocked until activation/rollout, UX/failure copy, incoming behavior, monitoring/telemetry, backend/staging operations, support/rollback, security review, and soak testing are hardened;
  - public rollout, production activation, Element Call replacement, CallKit, push/background incoming, missed calls, video, and session restoration remain out of scope.
- 2.29D/2.29E hardening:
  - private native card failure copy now maps backend, LiveKit/audio, trust, invalid-room, listener/open-room, timeout, cancel, decline, ended, and unknown failures to user-safe text;
  - DEBUG-only card redacted status exposes state/reason enums, listener/restoration enums, loading/action booleans, and no raw identifiers or credential-bearing values;
  - rendering/status display remains side-effect-free: no Matrix send, no token request, no media connect, and no LiveKit connect;
  - the dogfood runbook now defines the exact redacted monitoring contract for app/card status, runner output, backend readiness, backend errors, and LiveKit/media state;
  - LiveKit room names are treated as forbidden pilot report output because they may be correlatable.
- 2.30B eligibility contract skeleton:
  - `NativeDirectCallInternalPilotEligibility` supports `eligible`, `unavailable(reason)`, `disabled`, `unsupported`, and `failClosed`;
  - unavailable reasons are limited to `accountNotEligible`, `peerNotEligible`, `roomNotEligible`, `trustNotReady`, `serviceUnavailable`, `capabilityMissing`, `unsupportedClient`, and `unknown`;
  - payload shape is redacted and enum/boolean-only;
  - default provider returns disabled/fail-closed;
  - account and peer not-eligible states map to safe private-card unavailable copy;
  - non-engineering pilot remains blocked until server-side allowlist/capability backing and runtime proof exist.
- 2.30C runtime/no-activation proof:
  - backend readiness passed with `ready=true`, `reason=ok`, and Redis/storage booleans true;
  - with product UI/start gates but without the private dogfood gate, an attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`;
  - the no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session;
  - with the private dogfood gate restored, A/B trust and activation were ready;
  - runner-assisted A -> B reached A/B `activeAudio`, then hangup returned A/B to `idle` with media failure `none`;
  - the legacy fake/dry-run gate remained unset and Element Call remained untouched.
- 2.30E backend eligibility endpoint skeleton:
  - `POST /_matrix/client/unstable/kz.salemx.direct_call/eligibility` validates Matrix bearer auth, optional device binding, and encrypted direct 1:1 room structure before evaluating eligibility;
  - the default backend eligibility policy is fail-closed;
  - static allowlist mode requires both caller and peer accounts when explicitly enabled by local deployment config;
  - responses are limited to `state`, `reason`, and redacted booleans such as account, peer, room, trust, service, capability, and client support;
  - readiness exposes `nativeAudioEligibilityConfigured` and `nativeAudioEligibilityAllowlistConfigured` only;
  - token issuance reuses the same policy before rate limiting, allocation, LiveKit room pre-create, or participant token issuance;
  - this does not wire iOS non-engineering activation.
- 2.30F local route smoke:
  - readiness returned `ready=true`, `reason=ok`, and included `nativeAudioEligibilityConfigured` plus `nativeAudioEligibilityAllowlistConfigured`;
  - default `/eligibility` returned `state=unavailable`, `reason=capabilityMissing`, and `capability_present=false`;
  - default token endpoint enforcement returned `403` with `M_DIRECT_CALL_NOT_ELIGIBLE`, no allocation, no LiveKit room pre-create, and no participant token issuance;
  - explicit allowlisted local fixture returned `/eligibility` `state=eligible`, `reason=null`, and allowed the token path to proceed with token output redacted;
  - negative cases passed for caller not allowlisted, peer not allowlisted, invalid room, malformed request, and unsupported intent;
  - smoke output remained redacted, with no raw tokens, JWTs, secrets, room IDs, user IDs, peer IDs, device IDs, Redis credential URLs, or LiveKit room names printed.
- 2.30H iOS eligibility provider skeleton:
  - added `NativeDirectCallInternalPilotEligibilityRequest` for the backend `/eligibility` endpoint;
  - request descriptions and debug output redact room, peer, and device identifiers;
  - response decoding supports optional `capability_present` / `capabilityPresent`;
  - `HTTPNativeDirectCallInternalPilotEligibilityProvider` uses the existing Matrix bearer access-token provider and redacted direct-call HTTP transport;
  - missing config/auth/transport, network failures, 5xx, malformed JSON, unknown enums, and unsupported intents fail closed or map to safe unavailable states;
  - the default provider remains disabled/fail-closed;
  - this is not wired into non-engineering activation.
- 2.30I iOS eligibility provider no-activation proof:
  - staging readiness returned `ready=true`, `reason=ok`, and Redis/storage readiness booleans true;
  - with product UI/start gates but without the private dogfood gate, an attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`;
  - the no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session;
  - source inspection confirmed the provider skeleton remains unwired for non-engineering activation; app-side provider usage is limited to provider/types and tests;
  - `directOneToOneCallsEnabled` remains separate from native audio activation and does not enable the native eligibility path;
  - with the explicit private dogfood gate restored, A/B trust and activation were ready;
  - runner-assisted A -> B reached A/B `activeAudio`, then hangup returned A/B to `idle` with media failure `none`;
  - the legacy fake/dry-run gate remained unset and Element Call remained untouched.
- 2.31B eligibility status cache skeleton:
  - `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1` is a DEBUG/integration-only status/preflight gate and is off by default;
  - the gate does not enable private dogfood activation, production start, or non-engineering rollout;
  - eligibility status refresh is allowed to call only backend `/eligibility`;
  - room-card status merge is fail-closed: backend eligible never changes the card to `canStart`, backend ineligible maps only to safe unavailable copy, and local room/trust failures remain authoritative;
  - private dogfood activation remains unchanged and is not blocked by eligibility status;
  - card appear/status refresh can reuse cache, while manual Refresh/Retry bypasses it;
  - status refresh/rendering still must not send Matrix events, request tokens, allocate/pre-create rooms, connect media, connect LiveKit, or start outgoing calls.
- Element Call route remains unchanged and must stay available as fallback.
- No CallKit, push/background incoming, missed calls, video, session restoration, broad internal rollout, public rollout, production activation, or global activation exists.

Pilot decision:
- Controlled engineering dogfood may continue on the narrow staging path under the 2.28A operations checklist.
- A small expansion to more named engineering operators/devices is allowed under the same constraints.
- Broader internal dogfood and non-engineering users remain blocked until the 2.29B hardening checklist is complete.
- This is not broad internal dogfood, product beta, public rollout, production activation, or Element Call replacement.

Required pilot scope:
- Named engineering operators only.
- DEBUG/integration builds only.
- Staging call-service and staging LiveKit only.
- Foreground/open encrypted direct 1:1 rooms only.
- Verified/trusted peers only.
- Private native audio card only.
- Runner-assisted checks are allowed when explicitly reported.
- Audio only.
- Existing Element Call route remains visible and available as fallback.

Required gates:
- `IS_RUNNING_INTEGRATION_TESTS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging call-service>`
- Do not set `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED` for staging pilot proof.

Required backend preflight:
- readiness `ready=true`
- readiness `reason=ok`
- Redis allocation store connected
- Redis rate-limit store connected
- storage key configured
- LiveKit room provisioning configured
- Synapse validation smoke passing or explicitly accepted as a blocking prerequisite before the session starts

Required client preflight:
- A/B trust ready
- encrypted 1:1 DM open on both clients
- listener/card available
- no stale active session
- Element Call fallback visible

Phase:
2.31C — eligibility status cache no-activation runtime proof.

Task:
Runtime proof that the side-effect-safe eligibility status cache remains fail-closed by default and does not broaden native audio activation. Do not modify code unless a real runtime bug is found and explicitly approved.

Goal:
Verify that default/product-UI-only launches remain blocked, the status gate does not activate native audio, eligibility status refresh has no Matrix/token/media/LiveKit side effects, and controlled engineering dogfood still reaches active audio under the explicit private dogfood gate.

Inspect:
Use the existing redacted runner/status tooling and the 2.28A operations checklist. Do not print raw tokens, JWTs, secrets, room IDs, user IDs, peer IDs, device IDs, media keys, event bodies, Redis URLs, or LiveKit room names.

Required output:
A. Default fail-closed result.
B. Product UI/start gates without private dogfood result.
C. Eligibility status gate no-activation result.
D. Side-effect check.
E. Engineering dogfood happy path result.
F. Final A/B status.
G. Any regression.
H. Whether code changed.
I. Recommended next phase.

Allowed report fields:
- readiness booleans;
- trust booleans;
- redacted card state/reason enums;
- listener availability booleans/enums;
- activation reason enum;
- `productionSessionState`;
- `productionMediaFailureReason`;
- terminal reason enum;
- media/LiveKit connect attempted booleans;
- cleanup/disconnect booleans;
- pass/fail/not-run;
- timestamp/session number if non-identifying.

Forbidden output:
- raw tokens;
- JWTs;
- keys;
- Matrix access tokens;
- Synapse admin tokens;
- LiveKit API secrets;
- participant tokens;
- passwords;
- raw room IDs;
- raw user IDs;
- raw peer IDs;
- raw device IDs;
- LiveKit room names;
- Redis URLs with credentials;
- Matrix event bodies;
- full request or response bodies.

Stop immediately if:
- any raw secret, token, JWT, key, room ID, user ID, peer ID, device ID, LiveKit room name, endpoint credential, or Matrix event body appears in output;
- a call starts without required gates;
- Element Call route behavior changes;
- an untrusted peer or device can connect;
- a stale active session survives relaunch or cleanup;
- backend issues a token for invalid room, peer, trust, or membership;
- media failure is not fail-closed or leaves stale state;
- caller remains `activeAudio` after callee has failed closed.

Validation if docs change:
- `git diff --check`.
- Docs-only diff.
- Docs secret scan.
- Direct-call forbidden scan.

Suggested commit if docs change:
Record eligibility status cache no-activation proof
