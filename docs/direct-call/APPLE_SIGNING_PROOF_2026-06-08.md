# SalemX 2.40F Apple signing proof

Status: physical-device signing proof passed with new paid Apple Developer Team.

Branch:
- salemx-2.40f-signing-remediation

Local signing config:
- Main app bundle ID: kz.salemx.msg
- NSE bundle ID: kz.salemx.msg.nse
- ShareExtension bundle ID: kz.salemx.msg.shareextension
- App Group: group.kz.salemx.msg.dev

Main app signed entitlements:
- aps-environment: development
- application-groups: group.kz.salemx.msg.dev
- keychain-access-groups: present, redacted team-prefixed value

Extensions signed entitlements:
- NSE: application-groups present, keychain-access-groups present
- ShareExtension: application-groups present, keychain-access-groups present

Notes:
- Old installed app signed by previous Team had to be removed from the physical iPhone before install.
- No CallKit, PushKit, APNs runtime implementation, call routing stack, native audio gating, or server-side authority changes were made.
- This proof does not authorize production/public rollout.
