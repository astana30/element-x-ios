# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Next phase: 2.41B-S — foreground audio and call lifecycle hardening smoke.

Goal:
Run the next redacted physical smoke for the hardened foreground native audio lifecycle before PushKit/APNs/background incoming work.

Carry-forward checks from 2.41B:
- Verify whether the repeating audio tick/click artifact is fixed or still present.
- Verify whether both sides clear promptly after End.
- Full two-physical-device smoke remains pending.

Scope:
- Simulator caller plus physical iPhone callee with callee foreground/open.
- CallKit UI appears.
- Answer.
- Media connects only after foreground authority approval.
- End from each side in separate runs.
- Repeat call 2-3 times.
- Mute/unmute.
- Speaker/earpiece route if available.
- One 30-60 second call.
- Record whether a longer 5-10 minute foreground call is ready.
- Keep PushKit/APNs/background incoming out of scope.
- Keep Element Call route intact.
- Keep server-issued media credential authority as final authority.
- Keep logs/docs redacted.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not modify Element Call routing.
- Keep token endpoint/server-issued media credential as final authority.
- Keep all proof logs redacted.
