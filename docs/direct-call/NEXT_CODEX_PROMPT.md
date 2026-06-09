# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.40K — PushKit registration dry run planning.

Task:
Plan the smallest physical-device PushKit registration dry run for future native direct audio.
Do not implement APNs runtime delivery.
Do not send or receive real pushes.
Do not implement server push.
Do not connect media.
Do not request server-issued media credentials.
Do not modify LiveKit, MatrixRTC, Element Call route, native audio engine media setup, or feature gating.
Do not change bundle IDs, App Group IDs, signing, provisioning, project generation, or production distribution settings.
Do not add background incoming behavior.
Do not add missed-call UX.
Do not add video.
Do not globally activate production direct calls.

Context:
- 2.40F physical-device signing proof passed.
- 2.40G added the CallKit / PushKit / APNs design plan.
- 2.40H added disabled native incoming lifecycle contracts and mocks.
- 2.40I added the push and CallKit payload contract.
- 2.40J-A added the disabled synthetic CallKit proof contracts.
- 2.40J-B added the isolated physical-device synthetic CallKit UI proof adapter and DEBUG-only local harness boundary.
- Current proven native audio remains foreground/open encrypted direct 1:1 only.
- Push delivery, background incoming, missed-call UX, video, broad rollout, production/public rollout, and Element Call replacement remain blocked.
- The synthetic CallKit UI proof does not implement real incoming calls, PushKit/APNs delivery, server fanout, media credential requests, media connection, or production UI.

Goal:
Prepare a registration-only PushKit dry run that can prove physical-device registration lifecycle and redacted diagnostics without delivering pushes or contacting media/session services.

Inspect:
- `docs/direct-call/CALLKIT_PUSHKIT_APNS_DESIGN.md`
- `docs/direct-call/NATIVE_INCOMING_CONTRACTS.md`
- `docs/direct-call/PUSH_CALLKIT_PAYLOAD_CONTRACT.md`
- `docs/direct-call/SYNTHETIC_CALLKIT_PROOF.md`
- `docs/direct-call/SYNTHETIC_CALLKIT_UI_PROOF.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- existing Element Call PushKit surfaces only for separation review
- existing direct-call contract models and tests

Implementation goals:
1. Decide whether 2.40K is docs-only planning or a disabled registration harness.
2. Keep registration disabled by default and physical-device only.
3. Keep all registration values redacted.
4. Do not deliver pushes.
5. Do not request media credentials.
6. Do not connect media.
7. Do not alter Element Call route or native audio feature gates.

Hard constraints:
- No APNs delivery implementation.
- No real push fanout.
- No background incoming behavior.
- No missed-call UX.
- No media connection.
- No media credential request.
- No Element Call route change.
- No native audio gate change.
- No bundle ID/App Group/signing/project setting changes.
- No server rollout or production/public rollout.

Validation:
- SwiftFormat changed Swift files if code changes.
- SwiftLint changed Swift files if code changes.
- Targeted tests if code changes.
- Physical-device registration proof only if explicitly approved and available.
- `git diff --check`.
- Direct-call forbidden scan.
- Docs private-data scan if docs changed.

Suggested commit:
Plan PushKit registration dry run
