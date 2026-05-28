# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.40C — native audio signing and entitlement readiness audit.

Task:
Inspection/audit only. Do not modify app/backend code. Do not wire CallKit. Do not wire PushKit/APNs. Do not change Element Call route. Do not add video. Do not globally activate production direct calls.

Context:
- 2.39V implemented foreground/open-chat limitation UX polish for the private native audio card.
- 2.39W proved the UX polish at runtime: visible foreground/open-chat limitation copy, no backend/token/LiveKit/raw-ID wording in visible copy, Element Call fallback visible/unchanged, no rendering side effects, and a short internal-pilot A -> B smoke returned idle/no active session with media failure none.
- 2.40A reviewed the path from foreground/open-chat-only native audio toward proper incoming-call UX.
- 2.40B documented the native audio incoming-call lifecycle architecture contract:
  - native incoming lifecycle is separate from Element Call;
  - CallKit reporting happens only after safe local validation;
  - PushKit/APNs payloads must be minimal and opaque;
  - token endpoint remains final authority;
  - backend must not centralize Matrix trust decisions;
  - APNs/PushKit work requires signing, entitlements, provisioning, physical-device, and push gateway proof first.
- Additional non-engineering pilot windows, participant/device expansion, broad internal rollout, production/public rollout, unsupervised dogfood, CallKit/PushKit/APNs implementation, missed-call UX, video, session restoration, Element Call replacement, and global activation remain blocked.

Goal:
Audit whether the app and team are ready to begin future native audio CallKit/PushKit/APNs implementation work. This phase should prove or list blockers for signing, entitlements, Apple Developer account capabilities, physical device coverage, APNs environment, VoIP background mode, and push gateway prerequisites.

Inspect:
- docs/direct-call/PRIVATE_NATIVE_AUDIO_DOGFOOD.md
- docs/direct-call/STATUS.md
- docs/direct-call/WORKLOG.md
- server/salemx-call-service/docs/STAGING_SMOKE_2026-05-21.md
- project.yml
- ElementX/SupportingFiles/target.yml
- ElementX/SupportingFiles/ElementX.entitlements
- NSE/SupportingFiles/NSE.entitlements
- ElementX/Sources/Application/Settings/AppSettings.swift
- ElementX/Sources/Services/ElementCall/ElementCallService.swift
- ElementX/Sources/Services/Notification/Manager/NotificationManager.swift
- NSE/Sources/NotificationHandler.swift
- Any provisioning/signing docs or local build settings that are safe to inspect without printing secrets.

Questions:
1. Is Push Notifications capability present for the app target and relevant profiles?
2. Is `aps-environment` present or supplied by provisioning for the app target?
3. Is VoIP background mode present and correctly scoped?
4. Is a physical device available for future APNs/PushKit proof?
5. Does the Apple Developer account/App ID support the required capabilities?
6. Is native audio pusher registration able to stay separate from Element Call pusher registration?
7. What APNs/push gateway or Sygnal prerequisites are required for staging?
8. What must be proven before any CallKit adapter or PushKit registration code is written?
9. What remains blocked even if signing looks ready?

Hard constraints:
- Do not implement CallKit, PushKit, APNs, or native incoming-call code.
- Do not approve additional non-engineering pilot windows.
- Do not approve participant/device expansion.
- Do not approve broad internal rollout.
- Do not approve production/public rollout.
- Do not approve unsupervised dogfood.
- Do not replace Element Call toolbar or route.
- Do not add video.
- Do not globally activate production direct calls.
- Do not weaken trusted-device/E2EE behavior.
- Do not use `directOneToOneCallsEnabled` as the native audio gate.
- Token endpoint remains final authority.
- No raw IDs, tokens, JWTs, secrets, LiveKit room names, Matrix event bodies, or credentialed URLs in reports.

Expected output:
A. Files inspected.
B. Signing and entitlement readiness.
C. Physical-device readiness.
D. APNs/PushKit/pusher prerequisites.
E. Apple account/provisioning blockers.
F. Element Call separation risks.
G. Redaction/privacy risks.
H. Required proof before implementation.
I. Remaining blocked items.
J. Recommended next phase.
