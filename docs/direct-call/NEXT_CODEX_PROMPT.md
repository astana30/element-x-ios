# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Next recommended phase: 2.40K — incoming call state machine integration design/proof.

Scope: design and prove how CallKit answer/end/mute callbacks will connect to the existing native direct audio state machine without enabling real PushKit/APNs background incoming calls yet.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs/VoIP tokens.
- Do not connect media from background.
- Do not modify Element Call routing.
- Keep token endpoint/server-issued media credential as final authority.
- Keep all proof logs redacted.
