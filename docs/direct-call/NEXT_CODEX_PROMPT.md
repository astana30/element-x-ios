# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Phase:
2.40F — physical-device signing remediation execution.

Task:
Run or record the Apple Developer signing/provisioning remediation proof for future native audio CallKit/PushKit/APNs work.
Do not implement CallKit.
Do not implement PushKit/APNs.
Do not change app/backend code unless explicitly requested.
Do not change bundle IDs.
Do not change Element Call route.
Do not add video.
Do not globally activate production direct calls.

Context:
- 2.40B documented the native audio incoming-call lifecycle architecture contract.
- 2.40D signing audit found blockers:
  - generic `iphoneos` build completed;
  - local signing identity inspection reported no valid local identities;
  - signature verification reported an untrusted signing chain;
  - embedded main app, NSE, and ShareExtension profiles existed but expire on 2026-06-01;
  - `aps-environment` was missing;
  - physical iPhone was visible but offline;
  - simulator proof is insufficient.
- 2.40E documented the remediation checklist.
- Current proven native audio mode remains foreground/open encrypted direct 1:1 only.
- CallKit, PushKit/APNs, missed-call UX, background incoming, video, Element Call replacement, broad rollout, production/public rollout, participant/device expansion, and global activation remain blocked.

Goal:
Prove or record whether the signing/provisioning remediation checklist is complete enough to unblock future native audio CallKit/PushKit/APNs implementation planning.

Required remediation state:
- paid Apple Developer Program team available;
- valid Apple Development certificate installed locally;
- signing chain trusted locally;
- physical iPhone registered and online;
- App IDs configured:
  - main app: `kz.salemx.msg`;
  - NSE: `kz.salemx.msg.nse`;
  - ShareExtension: `kz.salemx.msg.shareextension`;
  - App Group: `group.kz.salemx.msg`;
- Push Notifications enabled for the main app;
- App Groups and Keychain Sharing enabled for app and extensions;
- durable development provisioning profiles generated for app, NSE, and ShareExtension.

Checks:
1. Inspect local signing identities without printing certificate private data.
2. Build for `iphoneos`.
3. Inspect embedded provisioning profiles with redacted output.
4. Inspect signed app entitlements with redacted output.
5. Confirm main app signed entitlements include `aps-environment`.
6. Confirm app, NSE, and ShareExtension include App Group and Keychain Sharing entitlements.
7. Confirm signed app Info.plist includes `UIBackgroundModes` with `voip`.
8. Install app with NSE and ShareExtension on the registered physical iPhone.
9. Confirm install succeeds.
10. Do not print push tokens, raw device identifiers, certificates, private keys, provisioning private data, or Apple account private data.

Expected report:
A. Files/settings inspected.
B. Signing identity status.
C. Profile status for app/NSE/ShareExtension.
D. Signed entitlement status.
E. Physical-device install result.
F. Remaining blockers.
G. Whether CallKit/PushKit/APNs implementation planning can proceed.
H. Recommended next phase.

Hard constraints:
- Do not implement CallKit, PushKit, APNs, native background incoming, or missed-call UX.
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
- No raw IDs, tokens, JWTs, secrets, certificates, private keys, profile secrets, LiveKit room names, Matrix event bodies, or credentialed URLs in reports.

Suggested next phase if complete:
2.40G — disabled native incoming-call service and CallKit adapter protocols

Suggested next phase if still blocked:
2.40G — signing remediation follow-up
