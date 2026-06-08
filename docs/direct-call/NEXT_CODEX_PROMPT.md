# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.40I — push and call reporting payload contract.

Task:
Define a design/test contract for future native audio push and call-reporting payloads.
Do not implement real CallKit runtime code.
Do not implement real PushKit runtime code.
Do not implement real APNs runtime code.
Do not register push credentials.
Do not report real system incoming calls.
Do not add background incoming behavior.
Do not add missed-call UX.
Do not connect media.
Do not modify LiveKit, MatrixRTC, Element Call route, native audio engine media setup, or feature gating.
Do not change bundle IDs, App Group IDs, signing, provisioning, project generation, or production distribution settings.
Do not add video.
Do not globally activate production direct calls.

Context:
- 2.40F physical-device signing proof passed and is recorded in `docs/direct-call/APPLE_SIGNING_PROOF_2026-06-08.md`.
- 2.40G added `docs/direct-call/CALLKIT_PUSHKIT_APNS_DESIGN.md`.
- 2.40H added disabled native incoming lifecycle contracts and mocks.
- Current proven native audio remains foreground/open encrypted direct 1:1 only.
- CallKit, PushKit, APNs runtime, background incoming, missed-call UX, video, broad rollout, production/public rollout, and Element Call replacement remain blocked.

Goal:
Define the smallest redacted payload and reporting contract for future incoming native audio work without enabling runtime behavior.

Inspect:
- `docs/direct-call/CALLKIT_PUSHKIT_APNS_DESIGN.md`
- `docs/direct-call/NATIVE_INCOMING_CONTRACTS.md`
- `docs/direct-call/STATUS.md`
- `docs/direct-call/WORKLOG.md`
- `ElementX/Sources/Services/Calls/DirectCallModels.swift`
- existing direct-call tests

Implementation goals:
1. Define opaque payload models for future incoming native audio push classification.
2. Define call reporting request/response models for the disabled adapter boundary.
3. Define redacted diagnostics for payload classification.
4. Keep payloads free of raw room, user, peer, or device identifiers, media credentials, event bodies, media-session names, and credentialed URLs.
5. Keep default behavior fail-closed/no-op.
6. Add unit tests for malformed, stale, duplicate, missing handle, unsupported version, and redaction.

Hard constraints:
- No real CallKit runtime implementation.
- No real PushKit/APNs runtime implementation.
- No push credential registration.
- No real system incoming UI.
- No background incoming behavior.
- No missed-call UX.
- No media connection.
- No Element Call route change.
- No native audio gate change.
- No bundle ID/App Group/signing/project setting changes.
- No server rollout or production/public rollout.

Validation:
- SwiftFormat changed Swift files.
- SwiftLint changed Swift files.
- Targeted native-call tests.
- Release build if Swift files changed.
- `git diff --check`.
- Direct-call forbidden scan.
- Docs secret scan if docs changed.

Suggested commit:
Add native incoming payload contracts
