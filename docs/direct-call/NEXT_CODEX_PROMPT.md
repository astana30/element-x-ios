# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.37C — engineering-only internal pilot activation soak session 1.

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
- Call-service Redis readiness hardening: 2.31D/2.31E-fix made Redis-backed staging readiness perform bounded live Redis pings for allocation and rate-limit stores at startup and on each readiness request, with safe reasons `allocationStoreUnavailable` and `rateLimitStoreUnavailable`.
- Eligibility endpoint local route smoke: 2.30F proved default fail-closed `/eligibility`, token endpoint enforcement before allocation/pre-create/token issuance, explicit allowlisted positive route behavior, negative route cases, and redacted output.
- iOS eligibility provider skeleton: 2.30H added a redacted request DTO, optional `capability_present` / `capabilityPresent` response decoding, and an HTTP provider skeleton for the backend `/eligibility` endpoint without wiring non-engineering activation.
- iOS eligibility provider no-activation proof: 2.30I proved product UI/start gates without the private dogfood gate remain blocked with `appRolloutDisabled`, the iOS provider skeleton remains unwired for non-engineering activation, and controlled engineering dogfood still reaches active audio under the explicit private dogfood gate.
- Eligibility status cache skeleton: 2.31B added a disabled-by-default DEBUG/integration status gate, room-flow scoped in-memory cache, safe card-status merge, manual refresh bypass, and tests proving backend eligibility status does not activate native audio.
- Eligibility status integration polish: 2.32B redacts LiveKit room names from token response descriptions, forwards the eligibility status gate through the two-client runner, and proved status-only/no-activation behavior plus the private dogfood happy path.
- Eligibility status controlled soak: 2.32C kept the eligibility status gate enabled during runner-assisted happy path, reverse, repeated, decline, cancel, timeout, and relaunch-ringing cases.
- Narrow engineering expansion runbook: 2.33B defines the engineering-only expansion cap, ownership window, participant/device matrix, pair matrix, required gates, preflight, stop criteria, rollback, and redacted report template.
- Timeout cleanup fix: 2.33D `Clear active session after direct call timeout` (`1d9218057`) makes timeout terminal paths disconnect and cleanup immediately.
- Engineering expansion session 1 rerun: 2.33E passed the first expanded engineering-only pilot window after the timeout cleanup fix.
- Engineering expansion soak plan: 2.34A defines a 3-session engineering-only soak before any broader readiness review.
- Engineering expansion soak session 1: 2.34B passed as the first clean soak session.
- Engineering expansion soak session 2: 2.34C passed as the second clean soak session.
- Engineering expansion soak session 3: 2.34D passed as the third clean soak session; the planned 3-session engineering-only soak is complete.
- Engineering expansion operations handoff: 2.35B documents named operator ownership, backend readiness watching, redacted report intake, stop/rollback ownership, monitoring baseline, periodic cadence, and decision rules for continuing engineering sessions without per-session Codex supervision.
- Operator-owned engineering expansion session 1: 2.35C passed under the 2.35B handoff with redacted Operator A/B and Device A1/B1 labels, readiness/trust/activation preflight, happy path, reverse, repeated calls x2, decline, cancel, timeout, relaunch-ringing, listener/open-room unavailable, and post-listener recovery.
- Internal pilot activation provider skeleton: 2.36C added a disabled-by-default native-audio-specific activation model/provider boundary. The default provider fails closed, the status-only provider never returns `activationAllowed`, backend eligible alone remains insufficient, product UI alone remains insufficient, and non-engineering internal dogfood remains disabled.
- Internal pilot activation no-activation proof: 2.36D proved product UI, eligibility status, and production start gates without private dogfood stay blocked with `appRolloutDisabled`, no Matrix/token/media/LiveKit side effects, and no active session; private engineering dogfood still reaches active audio and returns idle.
- Server-backed internal pilot activation provider: 2.36F added a default-off internal pilot rollout source and a concrete provider that can return `activationAllowed` only when all rollout, backend eligibility, local room, trust, dependency, and idle-session gates pass in unit tests; non-engineering runtime activation remains disabled.
- Server-backed internal pilot activation provider no-activation proof: 2.36G proved product UI, eligibility status, and production start gates without private dogfood still block with `appRolloutDisabled`, no Matrix/token/media/LiveKit side effects, no active session, and private engineering dogfood still reaches active audio and returns idle.
- Internal pilot activation dry-run status wiring: 2.36I adds a DEBUG/integration-only `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ACTIVATION_DRY_RUN_ENABLED=1` status gate that can report redacted internal pilot activation decisions from the server-backed provider without enabling Start or Accept.
- Internal pilot activation dry-run no-activation proof: 2.36J proved product UI, eligibility status, dry-run, and production start gates still do not activate native audio without private dogfood, while private engineering dogfood still reaches active audio and returns idle. Runner-visible output remained redacted, but that proof did not yet expose the new dry-run enum fields directly.
- Internal pilot activation dry-run runner observability: 2.36K exposes the dry-run enum/boolean fields in redacted `production-status` output and forwards the dry-run gate through the runner. 2.36L proved the fields are visible at runtime, enum/boolean-only, and observability-only.
- Engineering-only internal pilot activation proof wiring: 2.36N wires the server-backed activation provider into Start/Accept availability for explicit DEBUG/integration engineering proof gates only. Internal pilot rollout can enable Start/Accept only when backend eligibility, encrypted direct 1:1 room state, trust, dependencies, and no stale session all pass. Private dogfood remains separate, non-engineering internal dogfood remains blocked, and token endpoint enforcement remains final.
- Engineering-only internal pilot activation runtime proof: 2.36O passed for the allowlisted A/B path after `5fc30fe6a` wired the HTTP eligibility provider through `AppCoordinator`, `UserSessionFlowCoordinator`, `ChatsTabFlowCoordinator`, and `RoomFlowCoordinator`. With private dogfood unset, internal rollout enabled, and backend allowlisted A/B, runner status reported internal-pilot `activationAllowed`; A Start -> B Accept reached `activeAudio`; hangup returned A/B to idle with no active session and media failure `none`.
- Internal pilot trigger dry-run observability alignment: 2.36P `f930f8f7a` aligned `production-trigger-dry-run` with the same redacted activation decision path used by `production-start-outgoing`. Runner output now includes `activationSource`, `internalPilotActivationDecision`, and `internalPilotActivationReason`, and forwards `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED`. Dry-run remains side-effect-free, private dogfood compatibility was rechecked, and Element Call remains untouched.
- Engineering-only internal pilot activation soak plan: 2.37B defines a 3-session soak for the server-backed internal pilot activation path using engineering accounts only. The main soak keeps `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED` unset, uses the internal rollout gate, requires token endpoint final authority, and keeps non-engineering internal dogfood blocked.
- Engineering-only internal pilot activation soak session 1: 2.37C passed with the private dogfood gate unset and the internal rollout path active. Preflight passed, trigger dry-run reported `activationSource=internalPilot`, `internalPilotActivationDecision=activationAllowed`, `internalPilotActivationReason=none`, and A -> B, B -> A, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, post-listener recovery, token final-authority, and Element Call fallback rows passed. Token final-authority used a temporary ineligible local fixture and blocked with safe reason `accountNotEligible` before media/LiveKit. Final A/B state was idle/no active session with media failure `none`, no rollback, no stop criteria, no runtime bug, and no redaction issue. Soak progress: 1 of 3 clean.
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
- 2.31C eligibility status cache no-activation proof:
  - readiness passed with `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility plus allowlist configured;
  - with product UI and eligibility status gates enabled, but without the private dogfood gate, an attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`;
  - with product UI, production start, and eligibility status gates enabled, but without the private dogfood gate, `production-start-outgoing` stayed blocked with `appRolloutDisabled`;
  - the no-private-dogfood runs had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session;
  - a temporary happy-path blocker was diagnosed as Redis rate-limit store unavailability (`M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE` / `503`) and recovered by restoring Redis connectivity;
  - with the explicit private dogfood gate restored, A/B trust and activation were ready;
  - runner-assisted A -> B reached A/B `activeAudio`, media/LiveKit connect were attempted on both sides, media failure stayed `none`, and hangup returned A/B to `idle`;
  - the legacy fake/dry-run gate remained unset and Element Call remained untouched.
- 2.31D live Redis readiness hardening:
  - Redis-backed staging readiness now requires bounded live Redis pings for both allocation and rate-limit stores;
  - allocation Redis failure reports `allocationStoreUnavailable` with `allocationStoreConnected=false`;
  - rate-limit Redis failure reports `rateLimitStoreUnavailable` with `rateLimitConnected=false`;
  - readiness output remains redacted and does not include Redis URLs, credentials, keys, values, raw Matrix identifiers, tokens, JWTs, or secrets;
  - token endpoint behavior remains fail-closed and unchanged on Redis failures.
- 2.31F Redis readiness recovery smoke:
  - readiness after Redis restore returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured;
  - A/B trust remained ready;
  - runner-assisted A -> B reached B `incomingRinging`, B accepted, and A/B reached `activeAudio`;
  - media/LiveKit connect were attempted on both sides, media failure stayed `none`, and hangup returned A/B to `idle`;
  - Element Call route remained untouched and no code changed during the proof.
- 2.32B eligibility status integration polish and runtime proof:
  - production LiveKit token response descriptions now redact LiveKit room names, server URLs, and participant tokens;
  - the runner forwards `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1` into simulator launches and reports that gate without printing env values;
  - readiness returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured;
  - with product UI, production start, and eligibility status gates enabled, but without the private dogfood gate, an attached encrypted direct 1:1 room stayed blocked with `appRolloutDisabled`;
  - the no-private-dogfood run had no Matrix send, no token request, no media connect, no LiveKit client connect, and no active session;
  - with the explicit private dogfood gate restored, A/B activation and trust were ready;
  - runner-assisted A -> B reached A/B `activeAudio`, media/LiveKit connect were attempted on both sides, media failure stayed `none`, and hangup returned A/B to `idle`;
  - `wait-status incomingRinging` timed out before accept, but explicit accept and final status proved incoming, active audio, hangup, and cleanup;
  - negative backend eligibility reason mappings remain covered by unit tests and the 2.30F route smoke; the live staging allowlist was not reconfigured for negative cases;
  - the legacy fake/dry-run gate remained unset and Element Call remained untouched.
- 2.32C eligibility status controlled engineering soak:
  - readiness before and after the soak returned `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured;
  - A/B activation and trust were ready under the explicit private dogfood gates with `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1`;
  - runner-assisted happy path A -> B and reverse B -> A reached A/B `activeAudio`, then hangup returned both sides to idle/no active session with media failure `none`;
  - two repeated A -> B calls reached `activeAudio`, returned idle, and showed no stale session or split-brain;
  - decline and cancel passed through the shared production hangup command: incoming ringing emitted `reject`, outgoing ringing emitted `cancel`, both sides returned idle, and terminal reason was `cancelled`;
  - timeout passed with terminal reasons `outgoingTimeout` and `incomingTimeout`;
  - relaunch during ringing restored no active session; post-relaunch status was `unavailable` until the encrypted 1:1 room is re-opened, matching the current foreground/open-room limitation;
  - runner output did not include LiveKit room names;
  - Element Call route remained untouched and no code changed during the soak.
- 2.33B narrow engineering expansion runbook:
  - a narrow engineering-only expansion is allowed, still staging-only and conditional;
  - maximum safe next step is up to 4 named engineering operators and up to 8 named devices;
  - the first expanded window allows one active 1:1 native audio call at a time;
  - participant/device and pair matrices use labels only, with no raw user IDs, room IDs, peer IDs, device IDs, tokens, JWTs, secrets, Redis credential URLs, Matrix event bodies, or LiveKit room names;
  - every new pair must run happy path, reverse, repeated x2, decline, cancel, timeout if practical, relaunch fail-closed, listener/open-room unavailable, Element Call fallback, and backend-off/recovery only when safe;
  - LiveKit-off remains not-run unless the shared staging LiveKit owner explicitly approves a disruption window;
  - non-engineering users, broad internal rollout, production/public rollout, Element Call replacement, CallKit, push/background incoming, missed calls, video, session restoration, and global activation remain blocked.
- 2.33D timeout cleanup proof:
  - the first 2.33C expansion attempt paused because timeout terminal reasons were set while `productionHasActiveSession` stayed true until explicit cleanup;
  - root cause was timeout terminal paths leaving the active session owned until delayed cleanup;
  - `1d9218057` disconnects and cleans up immediately on timeout terminal paths;
  - runtime proof passed with A terminal `outgoingTimeout`, B terminal `incomingTimeout`, A/B `productionSessionState=idle`, A/B `productionHasActiveSession=false`, cleanup/disconnect attempted, and media failure `none`;
  - next call after timeout reached A/B `activeAudio`, then hangup returned A/B idle with no active session and media failure `none`;
  - DirectCallEngineTests 36/36, focused native subset 171 tests, Release build, SwiftFormat/SwiftLint, `git diff --check`, and direct-call forbidden scan passed.
- 2.33E engineering expansion pilot session 1 rerun:
  - session used redacted A/B engineering labels only, staging call-service, staging LiveKit, required DEBUG/integration gates, eligibility status gate, private dogfood gate, production start gate, and the staging token base URL;
  - the legacy fake/dry-run gate stayed unset;
  - preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured;
  - A/B trust was ready and baseline status was idle/no active session;
  - runner-assisted happy path A -> B, reverse B -> A, and repeated A -> B calls x2 reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`;
  - decline and cancel returned A/B to idle/no active session;
  - timeout passed with A terminal `outgoingTimeout`, B terminal `incomingTimeout`, A/B idle/no active session, cleanup/disconnect attempted, and media failure `none`;
  - relaunch during ringing returned A/B idle/no active session;
  - listener-unavailable/open-room edge passed by stopping B before A started: A timed out fail-closed with `outgoingTimeout`, no active session, and media failure `none`; B relaunched idle/no active session;
  - backend-off recovery was not run because the local staging call-service stayed up for the pilot;
  - LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval;
  - final A/B status was idle/no active session with media failure `none`, no rollback was needed, no stop criteria triggered, no redaction issue was observed, and Element Call route remained untouched.
- 2.34A engineering expansion soak plan:
  - 3 short engineering-only soak sessions are required before any broader readiness review;
  - scope remains up to 4 named engineering operators, up to 8 named devices, staging-only, private native audio card only, foreground/open encrypted direct 1:1 rooms only, verified/trusted peers only, one active 1:1 call at a time, Element Call fallback visible, and redacted reporting only;
  - every soak session must run A -> B happy path, B -> A reverse, repeated calls x2, decline, cancel, timeout, relaunch fail-closed, listener/open-room unavailable, and Element Call fallback smoke;
  - backend-off/recovery is optional only when safe for the local staging setup;
  - LiveKit-off is not run unless explicitly approved by the shared staging LiveKit owner;
  - decision rule: 3 clean sessions lead to a readiness review for the next phase; any critical bug or stop criterion pauses the soak for diagnosis.
- 2.34B engineering expansion soak session 1:
  - session used redacted A/B engineering labels only, staging call-service, staging LiveKit, required DEBUG/integration gates, eligibility status gate, private dogfood gate, production start gate, and staging token base URL;
  - the legacy fake/dry-run gate stayed unset;
  - preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session;
  - runner-assisted A -> B happy path, B -> A reverse path, and repeated A -> B calls x2 reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`;
  - decline, cancel, timeout, relaunch-ringing, listener-unavailable/open-room edge, and post-listener recovery passed;
  - timeout reported A `outgoingTimeout` and B `incomingTimeout`; both sides returned idle/no active session with media failure `none`;
  - backend-off recovery was not run because the local staging call-service stayed up for the session;
  - LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval;
  - final A/B status was idle/no active session with media failure `none`, cleanup/disconnect attempted on both sides, no rollback, no stop criteria, no redaction issue, and Element Call route untouched;
  - soak progress is 1 of 3 clean sessions.
- 2.34C engineering expansion soak session 2:
  - session used redacted A/B engineering labels only, staging call-service, staging LiveKit, required DEBUG/integration gates, eligibility status gate, private dogfood gate, production start gate, and staging token base URL;
  - the legacy fake/dry-run gate stayed unset;
  - preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session;
  - runner-assisted A -> B happy path, B -> A reverse path, and repeated A -> B calls x2 reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`;
  - decline, cancel, timeout, relaunch-ringing, listener-unavailable/open-room edge, and post-listener recovery passed;
  - timeout reported A `outgoingTimeout` and B `incomingTimeout`; both sides returned idle/no active session with media failure `none`;
  - backend-off recovery was not run because the local staging call-service stayed up for the session;
  - LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval;
  - final A/B status was idle/no active session with media failure `none`, cleanup/disconnect attempted on both sides, no rollback, no stop criteria, no redaction issue, and Element Call route untouched;
  - soak progress is 2 of 3 clean sessions.
- 2.34D engineering expansion soak session 3:
  - session used redacted A/B engineering labels only, staging call-service, staging LiveKit, required DEBUG/integration gates, eligibility status gate, private dogfood gate, production start gate, and staging token base URL;
  - the legacy fake/dry-run gate stayed unset;
  - preflight passed with readiness `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session;
  - runner-assisted A -> B happy path, B -> A reverse path, and repeated A -> B calls x2 reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`;
  - decline, cancel, timeout, relaunch-ringing, listener-unavailable/open-room edge, and post-listener recovery passed;
  - timeout reported A `outgoingTimeout` and B `incomingTimeout`; both sides returned idle/no active session with media failure `none`;
  - backend-off recovery was not run because the local staging call-service stayed up for the session;
  - LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval;
  - final A/B status was idle/no active session with media failure `none`, cleanup/disconnect attempted on both sides, no rollback, no stop criteria, no redaction issue, and Element Call route untouched;
  - soak progress is 3 of 3 clean sessions; the planned engineering-only soak is complete.
- 2.35B engineering expansion operations handoff:
  - narrow engineering expansion may continue without per-session Codex supervision only when a named session owner follows the handoff;
  - required roles are session owner, backend readiness watcher, client operators, redaction reviewer, stop authority, and rollback owner;
  - allowed scope remains capped at up to 4 named engineering operators, up to 8 named devices, predeclared pairs only, staging-only, one active 1:1 call at a time, private native audio card only, foreground/open encrypted direct 1:1 rooms only, verified/trusted peers only, Element Call fallback visible/unchanged, and redacted reporting only;
  - monitoring output remains limited to readiness booleans, trust booleans, `productionSessionState`, `productionMediaFailureReason`, terminal reason enum, cleanup/disconnect booleans, pass/fail/not-run, and redacted backend reason enums;
  - clean sessions follow a docs-only redacted report path with `git diff --check`, docs secret scan, direct-call forbidden scan, and redaction review before commit;
  - Codex/engineering review remains required for runtime bugs, stop criteria, scope expansion, non-engineering access, config changes, rollout changes, or activation changes.
- 2.35C operator-owned engineering expansion session 1:
  - session used redacted Operator A/B and Device A1/B1 labels only;
  - preflight passed with readiness `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, native audio eligibility/allowlist configured, A/B trust ready, activation enabled, and baseline A/B idle/no active session;
  - runner/status-assisted A -> B happy path, B -> A reverse path, and repeated A -> B calls x2 reached A/B `activeAudio`, then hangup returned A/B idle/no active session with media failure `none`;
  - decline, cancel, timeout, relaunch-ringing, listener-unavailable/open-room edge, and post-listener recovery passed;
  - timeout reported A `outgoingTimeout` and B `incomingTimeout`;
  - backend-off recovery was not run because the local staging call-service stayed up for the session;
  - LiveKit-off was not run because shared staging LiveKit must not be stopped without owner approval;
  - final A/B status was idle/no active session with media failure `none`, cleanup/disconnect attempted on both sides, no rollback, no stop criteria, no redaction issue, and Element Call route untouched.
- 2.36C internal pilot activation provider skeleton:
  - activation states are `disabled`, `unavailable`, `eligibleForStatusOnly`, and `activationAllowed`;
  - safe unavailable reasons are `rolloutDisabled`, `capabilityMissing`, `accountNotEligible`, `peerNotEligible`, `roomNotEligible`, `trustNotReady`, `serviceUnavailable`, `unsupportedClient`, `dependenciesUnavailable`, and `unknown`;
  - default activation provider returns disabled/fail-closed;
  - status-only provider can combine future rollout/capability/eligibility/room/trust/dependency inputs but never returns `activationAllowed`;
  - backend eligible alone, product UI alone, eligibility status alone, and `directOneToOneCallsEnabled` do not activate native audio;
  - engineering private dogfood remains on `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1` under DEBUG/integration gates;
  - non-engineering internal dogfood remains blocked.
- 2.36D internal pilot activation skeleton runtime proof:
  - readiness passed with `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured;
  - product UI and eligibility status enabled without private dogfood stayed blocked;
  - product UI, eligibility status, and production start enabled without private dogfood still blocked Start with `appRolloutDisabled`;
  - no Matrix send, token request, media connect, LiveKit client connect, or active session occurred in the no-private-dogfood runs;
  - `directOneToOneCallsEnabled` was not toggled at runtime because there is no safe runner hook without changing Element Call settings; the 2.36C tests cover that separation;
  - restoring private dogfood allowed A -> B `activeAudio`, then hangup returned A/B to idle with cleanup/disconnect attempted and media failure `none`;
  - no code changed, no redaction issue was observed, and Element Call stayed untouched.
- 2.36G internal pilot activation provider runtime proof:
  - readiness passed with `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, and storage key configured;
  - product UI and eligibility status enabled without private dogfood stayed blocked with `appRolloutDisabled` once the encrypted direct 1:1 room was open;
  - product UI, eligibility status, and production start enabled without private dogfood still blocked Start with `appRolloutDisabled`;
  - no Matrix send, token request, media connect, LiveKit client connect, or active session occurred in the no-private-dogfood runs;
  - the internal pilot rollout source stayed default-off at runtime and backend eligibility/status did not enable Start or Accept;
  - restoring private dogfood allowed A -> B `activeAudio`, then hangup returned A/B to idle with cleanup/disconnect attempted and media failure `none`;
  - no code changed, no redaction issue was observed, and Element Call stayed untouched.
- 2.36I internal pilot activation dry-run status wiring:
  - room-card provider boundary can compute a redacted dry-run status behind `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ACTIVATION_DRY_RUN_ENABLED=1`;
  - dry-run output is limited to safe enum/boolean fields: enabled, decision, reason, product UI, internal rollout, capability, room, trust, dependency, and active-session booleans;
  - dry-run can report `activationAllowed` in unit tests when all gates pass, but that result is status-only and does not enable Start or Accept;
  - private engineering dogfood remains separate under `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED=1`;
  - product UI, eligibility status, backend eligible, production start, and `directOneToOneCallsEnabled` remain insufficient by themselves.
- 2.36J internal pilot activation dry-run runtime proof:
  - readiness passed with `200`, `ready=true`, `reason=ok`, Redis allocation/rate-limit connected, storage key configured, LiveKit room provisioning configured, and native audio eligibility/allowlist configured;
  - product UI, eligibility status, and dry-run gates without private dogfood stayed blocked with no Matrix send, no token request, no media connect, no LiveKit client connect, no active session, and media failure `none`;
  - adding production start without private dogfood stayed blocked and still did not request token/media/LiveKit;
  - restoring private dogfood allowed A -> B `activeAudio`, then hangup returned A/B idle with no active session, cleanup/disconnect attempted, and media failure `none`;
  - runner output stayed redacted, but that proof did not yet expose the new internal-pilot dry-run enum fields directly.
- 2.36K internal pilot activation dry-run runner observability:
  - `production-status` now carries the dry-run enum/boolean fields in redacted output;
  - the runner prints `internalPilotActivationDryRunEnabled`, `internalPilotActivationDecision`, `internalPilotActivationReason`, `internalPilotRolloutEnabled`, `internalPilotEligibilityReady`, `internalPilotRoomReady`, `internalPilotTrustReady`, and `internalPilotDependenciesReady`;
  - this remains observability only and does not enable Start or Accept.
- 2.36N engineering-only internal pilot activation proof wiring:
  - Start/Accept can be made available from the server-backed activation provider only under explicit DEBUG/integration engineering proof gates;
  - internal pilot rollout can enable Start/Accept only when backend eligibility, encrypted direct 1:1 room state, trust, dependencies, and no stale session all pass;
  - private dogfood remains separate;
  - non-engineering internal dogfood remains blocked;
  - token endpoint enforcement remains final.
- 2.36O engineering-only internal pilot activation runtime proof:
  - commit `5fc30fe6a` wires the HTTP eligibility provider into the actual room-flow dependency chain;
  - default and Release behavior remain fail-closed;
  - HTTP provider selection requires explicit DEBUG/integration proof gates;
  - private engineering dogfood remains separate and unchanged;
  - with private dogfood unset, internal rollout enabled, and backend allowlisted A/B, runner status reported internal-pilot `activationAllowed`;
  - A Start -> B Accept reached `activeAudio`;
  - hangup returned A/B to idle with no active session and media failure `none`;
  - no raw identifiers, tokens, JWTs, secrets, LiveKit room names, Matrix event bodies, Redis credentials, or full request/response bodies were printed;
  - validation passed: SwiftFormat, SwiftLint, targeted tests 176/176, Release build with existing warnings only, `git diff --check`, and changed-line forbidden scan;
  - the remaining observability caveat was handled in 2.36P.
- 2.36P internal pilot trigger dry-run observability alignment:
  - commit `f930f8f7a` aligns `production-trigger-dry-run` with the same redacted activation decision path used by `production-start-outgoing`;
  - runner output now includes `activationSource`, `internalPilotActivationDecision`, and `internalPilotActivationReason`;
  - runner forwards `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED` for explicit DEBUG/integration proof runs;
  - trigger dry-run remains side-effect-free: no Matrix send, token request, allocation, LiveKit room pre-create, media connect, LiveKit client connect, outgoing call, or active session;
  - private dogfood compatibility was verified after the alignment: Start -> Accept reached `activeAudio`, Hangup returned A/B to `idle`, no active session remained, and media failure stayed `none`;
  - validation passed: SwiftFormat, SwiftLint, targeted native-call tests 179/179, Release build with existing warnings only, runner `bash -n`, `git diff --check`, and changed-line forbidden scan.
- Element Call route remains unchanged and must stay available as fallback.
- No CallKit, push/background incoming, missed calls, video, session restoration, broad internal rollout, public rollout, production activation, or global activation exists.

Pilot decision:
- Controlled engineering dogfood may continue on the narrow staging path under the 2.28A operations checklist.
- A small expansion to more named engineering operators/devices is allowed under the 2.33B runbook constraints.
- The first expanded window is capped at up to 4 named engineering operators, up to 8 named devices, predeclared pairs only, and one active 1:1 native audio call at a time.
- Broader internal dogfood and non-engineering users remain blocked until the 2.29B hardening checklist is complete.
- This is not broad internal dogfood, product beta, public rollout, production activation, or Element Call replacement.

Required pilot scope:
- Named engineering operators only.
- Up to 4 engineering operators and up to 8 named devices for the first expansion.
- Predeclared accounts/devices and pair labels only.
- DEBUG/integration builds only.
- Staging call-service and staging LiveKit only.
- Foreground/open encrypted direct 1:1 rooms only.
- Verified/trusted peers only.
- Private native audio card only.
- One active 1:1 native audio call at a time during the first expanded window.
- Runner-assisted checks are allowed when explicitly reported.
- Audio only.
- Existing Element Call route remains visible and available as fallback.

Required gates:
- `IS_RUNNING_INTEGRATION_TESTS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1`
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
2.37D — engineering-only internal pilot activation soak session 2.

Task:
Run or record the second engineering-only soak session for the server-backed internal pilot activation path.
Do not modify code unless a real runtime bug is found and explicitly approved.
Do not change Element Call route.
Do not wire CallKit/push/video.
Do not globally activate production direct calls.

Context:
2.37B added a 3-session soak plan for the server-backed internal pilot activation path.
2.37C passed as the first clean soak session.
This soak uses engineering accounts only and explicitly tests the internal rollout path without the private dogfood gate.
Non-engineering internal dogfood remains blocked.
Production/public rollout remains blocked.

Required scope:
- named engineering operators/devices only;
- backend allowlisted A/B or named engineering pairs only;
- staging call-service and staging LiveKit only;
- private native audio card only;
- foreground/open encrypted direct 1:1 rooms only;
- verified/trusted peers only;
- one active 1:1 call at a time;
- Element Call fallback visible and unchanged;
- redacted reporting only.

Required gates:
- `IS_RUNNING_INTEGRATION_TESTS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS=1`
- `NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED=1`
- `NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED=1`
- `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ACTIVATION_DRY_RUN_ENABLED=1`
- `NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`
- `NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL=<staging call-service>`

Must remain unset for the main soak:
- `NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED`
- `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED`

Backend preflight:
- `SALEMX_NATIVE_AUDIO_ELIGIBILITY_ENABLED=1`
- allowlist contains only named engineering accounts for this session;
- readiness `ready=true`;
- readiness `reason=ok`;
- Redis allocation/rate-limit connected;
- LiveKit room provisioning configured;
- native audio eligibility and allowlist configured.

Client preflight:
- A/B launched;
- A/B trust ready;
- encrypted direct 1:1 DM open on both clients;
- private native audio card visible;
- no stale active session;
- Element Call fallback visible.

Soak matrix:
1. A -> B happy path.
2. B -> A reverse path.
3. Repeated calls x2.
4. Decline incoming.
5. Cancel outgoing.
6. Timeout.
7. Relaunch fail-closed during ringing or active.
8. Listener/open-room unavailable behavior.
9. Post-listener recovery.
10. Token final-authority check if safe: remove/disable allowlist or use ineligible fixture; must block before media/LiveKit.
11. Element Call fallback visible check.

Optional:
- backend-off/recovery only if safe;
- LiveKit-off not run unless explicitly approved by LiveKit owner.

Report only redacted:
A. Session date/time.
B. Operator/device labels only.
C. Preflight result.
D. Matrix result table.
E. Final A/B state.
F. `activationSource`, `internalPilotActivationDecision`, `internalPilotActivationReason`.
G. Media failure enum.
H. Terminal reason enum.
I. Cleanup/disconnect booleans.
J. Stop criteria hit yes/no.
K. Rollback used yes/no.
L. Redaction issue yes/no.
M. Decision continue/pause.

Forbidden:
- Matrix access tokens;
- Synapse admin token;
- LiveKit API secret;
- participant JWT/token;
- raw room IDs;
- raw user/peer/device IDs;
- LiveKit room names;
- media keys;
- Matrix event bodies;
- Redis credentials;
- full request/response bodies;
- backend URLs with credentials.

Stop immediately if:
- raw secret/token/JWT/key/ID appears;
- call starts without required gates;
- private dogfood gate is accidentally used in the main internal-pilot soak;
- Element Call route changes;
- untrusted peer/device can connect;
- stale active/ringing survives cleanup/relaunch;
- backend issues token for invalid room/peer/trust;
- media failure does not fail closed;
- split-brain reappears;
- token final-authority check fails.

If passed with no code changes, create docs-only report commit.

Suggested commit:
Record internal pilot activation soak session 2
