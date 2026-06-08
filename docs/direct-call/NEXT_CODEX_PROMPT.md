# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.40J — device-only synthetic CallKit proof.

Task:
Design and prepare the smallest physical-device synthetic CallKit proof for native direct audio after the payload contract.
Do not implement real PushKit runtime code.
Do not implement real APNs runtime code.
Do not register push credentials.
Do not deliver real pushes.
Do not connect media.
Do not modify LiveKit, MatrixRTC, Element Call route, native audio engine media setup, or feature gating.
Do not change bundle IDs, App Group IDs, signing, provisioning, project generation, or production distribution settings.
Do not add background incoming behavior.
Do not add missed-call UX.
Do not add video.
Do not globally activate production direct calls.

Context:
- 2.40F physical-device signing proof passed and is recorded in `docs/direct-call/APPLE_SIGNING_PROOF_2026-06-08.md`.
- 2.40G added `docs/direct-call/CALLKIT_PUSHKIT_APNS_DESIGN.md`.
- 2.40H added disabled native incoming lifecycle contracts and mocks.
- 2.40I added `docs/direct-call/PUSH_CALLKIT_PAYLOAD_CONTRACT.md`.
- Current proven native audio remains foreground/open encrypted direct 1:1 only.
- PushKit/APNs runtime, background incoming, missed-call UX, video, broad rollout, production/public rollout, and Element Call replacement remain blocked.

Goal:
Define a physical-device-only synthetic CallKit proof that uses validated local fake inputs and disabled adapters, without PushKit/APNs delivery and without media connection.

Inspect:
- `docs/direct-call/CALLKIT_PUSHKIT_APNS_DESIGN.md`
- `docs/direct-call/NATIVE_INCOMING_CONTRACTS.md`
- `docs/direct-call/PUSH_CALLKIT_PAYLOAD_CONTRACT.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- existing direct-call contract models and tests
- existing Element Call CallKit surfaces only for separation review

Implementation goals:
1. Decide whether this phase is design-only or a disabled test harness.
2. If code is added, keep it behind disabled protocol/test boundaries only.
3. Use synthetic validated local call identity only.
4. Do not request media credentials.
5. Do not connect media.
6. Do not alter Element Call route or native audio feature gates.
7. Keep reports redacted.

Hard constraints:
- No real PushKit/APNs implementation.
- No push credential registration.
- No real push delivery.
- No background incoming behavior.
- No missed-call UX.
- No media connection.
- No Element Call route change.
- No native audio gate change.
- No bundle ID/App Group/signing/project setting changes.
- No server rollout or production/public rollout.

Validation:
- SwiftFormat changed Swift files if code changes.
- SwiftLint changed Swift files if code changes.
- Targeted tests if code changes.
- Physical-device proof only if explicitly approved and available.
- `git diff --check`.
- Direct-call forbidden scan.
- Docs private-data scan if docs changed.

Suggested commit:
Prepare synthetic CallKit proof plan
