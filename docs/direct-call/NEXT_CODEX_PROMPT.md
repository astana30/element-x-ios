# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Next recommended phase: 2.41B — foreground native incoming physical-device smoke.

Scope: run or record a supervised physical-device foreground/open-chat smoke for the 2.41A foreground native incoming E2E coordinator path. The proof should use the existing foreground native call path only and must not add background incoming behavior.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not modify Element Call routing.
- Keep token endpoint/server-issued media credential as final authority.
- Keep all proof logs redacted.
