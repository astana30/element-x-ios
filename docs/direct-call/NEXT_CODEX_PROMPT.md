# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Next recommended phase: 2.40M — PushKit registration dry-run design.

Scope: design a disabled, redacted PushKit registration dry-run boundary after the 2.40L foreground incoming acceptance gate. The next phase should not receive pushes, should not report real incoming calls, and should not connect media.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not connect media from background.
- Do not request real server-issued media credentials from push receipt.
- Do not modify Element Call routing.
- Keep token endpoint/server-issued media credential as final authority.
- Keep all proof logs redacted.
