# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-2.41g-a-s-repeat-call-audio-smoke

Next phase: 2.41G-A-S - repeat-call audio stutter physical smoke.

Goal:
Run the foreground two-physical-iPhone repeat-call audio smoke after the 2.41G-A embedded web content cleanup.

Context:
- Foreground audio uses the existing Embedded Element Call route.
- 2.41G-A added an idempotent embedded web content reset when the call screen stops or begins local termination.
- The reset stops active audio/video element tracks, detaches stream-backed media, clears media sources, and stops the page load.
- Existing widget hangup, Matrix termination request, and Element Call service teardown paths remain unchanged.
- Physical smoke is required to confirm whether repeat-call stutter/hesitation is fixed or only narrowed.
- Element Call remote video renderer stabilization remains a separate follow-up.

Scope:
- Foreground only.
- Two physical iPhones preferred.
- Call #1 audio, answer, talk 30 seconds, end, wait 2 seconds.
- Call #2 audio, answer, measure audio connection delay, check stutter/hesitation.
- Repeat 3 times.
- Check crash behavior.
- Confirm Element Call route is unaffected.
- Keep logs/docs redacted.

Constraints:
- Do not implement PushKit runtime.
- Do not register APNs or VoIP values.
- Do not add background incoming handling.
- Do not change signing, bundle identifiers, entitlements, Info.plist, app.yml, or project settings.
- Do not replace Element Call routing.
- Do not change production rollout gates.
- Do not implement private native direct-call video in this phase.
- Do not bypass server-issued credential authority.
- Do not add raw account, room, device, event, auth credential, push/media, Apple signing, media-session, track, participant, private runtime log, or credential-shaped fixture values.
- Do not paste full runtime logs into docs.

Expected output:
- Repeat-call smoke result.
- Whether stutter/hesitation reproduced.
- Audio connection delay per call row.
- End/hangup cleanup timing.
- Crash yes/no.
- Element Call route regression yes/no.
- Recommendation: proceed to `2.41G-B - Element Call remote video renderer stabilization`, continue audio hardening, or add narrower diagnostics.
