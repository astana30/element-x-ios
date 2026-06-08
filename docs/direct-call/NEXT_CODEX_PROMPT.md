# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.40H — native incoming lifecycle contracts and mocks.

Task:
Create disabled native audio incoming-call lifecycle contracts and test doubles for future CallKit / PushKit / APNs work.
Do not implement CallKit runtime code.
Do not implement PushKit runtime code.
Do not implement APNs runtime code.
Do not register for push tokens.
Do not report real system incoming calls.
Do not change Element Call route.
Do not modify LiveKit, MatrixRTC, native audio engine media setup, or feature gating.
Do not change bundle IDs, App Group IDs, signing, provisioning, or production distribution settings.
Do not add video.
Do not globally activate production direct calls.

Context:
- 2.40F physical-device signing proof passed and is recorded in `docs/direct-call/APPLE_SIGNING_PROOF_2026-06-08.md`.
- 2.40G added `docs/direct-call/CALLKIT_PUSHKIT_APNS_DESIGN.md`.
- Current proven native audio remains foreground/open encrypted direct 1:1 only.
- The signed development app has APNs entitlement and the app/extension App Group is `group.kz.salemx.msg.dev`.
- CallKit, PushKit, APNs runtime, background incoming, missed-call UX, video, broad rollout, production/public rollout, and Element Call replacement remain blocked.

Goal:
Prepare the smallest disabled architecture surface for future incoming-call work without enabling runtime behavior.

Inspect:
- `docs/direct-call/CALLKIT_PUSHKIT_APNS_DESIGN.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- `DirectCallEngine.swift`
- `DirectCallMediaEngineProtocol.swift`
- `RoomFlowCoordinator.swift`
- `RoomScreenModels.swift`
- `AppCoordinator.swift`
- existing notification and call-related protocols if present
- relevant unit test targets

Implementation goals:
1. Add disabled protocol/model contracts only if they can stay inert by default:
   - native incoming call identity model using safe opaque labels only;
   - CallKit adapter protocol/test double;
   - PushKit registry protocol/test double;
   - incoming native call state store protocol/test double;
   - call timeout/stale-call model;
   - redacted diagnostics model.
2. Default runtime behavior must remain no-op/fail-closed.
3. No production app path should instantiate real CallKit, PushKit, or APNs objects.
4. No rendering/status refresh should send Matrix events, request media credentials, connect media, connect LiveKit, or report system calls.
5. Element Call route and toolbar must remain unchanged.
6. Token endpoint remains final authority.
7. Do not use `directOneToOneCallsEnabled` as the native audio gate.

Required tests:
- default disabled incoming-call service is fail-closed;
- malformed/stale/duplicate incoming handles fail closed;
- invalid room/trust/eligibility/dependency/session states fail closed;
- token endpoint rejection maps to safe terminal diagnostics;
- CallKit adapter test double receives only safe local identity data;
- PushKit registry test double never exposes token values in descriptions/logs;
- redaction tests cover raw identifiers, push tokens, media credentials, event bodies, and media-session names;
- Element Call route remains untouched.

Hard constraints:
- No real CallKit runtime implementation.
- No real PushKit/APNs runtime implementation.
- No push token registration.
- No real system incoming UI.
- No background incoming behavior.
- No missed-call UX.
- No video.
- No broad internal rollout.
- No production/public rollout.
- No bundle ID/App Group/signing changes.
- No raw identifiers, push tokens, media credentials, Matrix event bodies, Apple private data, or media-session names in logs/docs.

Validation:
- SwiftFormat changed Swift files.
- SwiftLint changed Swift files.
- Targeted native-call tests.
- Release build if Swift files changed.
- `git diff --check`.
- Direct-call forbidden scan.
- Docs secret scan if docs changed.

Suggested commit:
Add disabled native incoming call contracts
