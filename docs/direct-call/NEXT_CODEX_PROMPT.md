# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Next phase: 2.41B — foreground audio and call lifecycle hardening.

Goal:
Stabilize the foreground native audio call path before PushKit/APNs/background incoming work.

Carry-forward issues from 2.41A-S:
- Repeating audio tick/click artifact during connected media.
- Peer-side end cleanup delay of approximately 10 seconds.
- Full two-physical-device smoke remains pending.

Scope:
- Investigate audio session configuration, audio route, speaker/earpiece/Bluetooth behavior, mute/unmute, repeated calls, end propagation, teardown timing, and 5-10 minute foreground call stability.
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
