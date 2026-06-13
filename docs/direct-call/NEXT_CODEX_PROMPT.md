# Next Codex Prompt

Repo:
`/Users/aibattt/Movies/element-x-ios`

Branch:
`salemx-2.43m-pushkit-capability-build-profile-validation`

Next phase: continue from the PushKit capability build/profile validation. The likely next step is controlled physical install validation when a trusted/unlocked iPhone is available, still without enabling PushKit registration or requesting tokens unless explicitly authorized.

## Baseline

Foreground real-invite baseline:

```text
e7b9428db20892a3e3cb27c15933b786883757f4 Consolidate foreground token guard baseline
bf9996ae0665ad3953fac3d7a838bfb619349dd1 Validate foreground real invite token guard smoke
26e520b6f6ec0220ce118051f5acac36ed40bfba Guard debug foreground smoke surface
```

PushKit/background preparation chain:

```text
5fa4d24e288273bcc824496ec4276777d3893280 Document PushKit APNs background call investigation
9e76108e096d90f0586047c4d017cb699fae3a05 Add background invite payload contract
9cd5279ffd1a32898568a25cdded380404d09fcc Add background invite intake seam
fc2881eea7ee2f1398d66ce325c7caee956d3db7 Add background CallKit reporting seam
0ac6a1c86d6315205b3bcf49a42877feb0f5180d Add background CallKit adapter boundary
e8ae7be8d13c93d57ec414dd472e19fd93dfb5f0 Add controlled real CallKit adapter
3266e567f7ff2ff4a6839e5d79794e077658cd9a Add PushKit lifecycle abstraction seam
ac0fa9ef32333fce7bfc3685a5088ef64a33323a Document PushKit readiness plan
0862f4ad00538658e73fe87f5515d49079fe542e Add gated PushKit registrar scaffold
6d78104ab4a13a2df58a5c6171b84383a3bd754b Document PushKit capability readiness verification
f8ad35ee1130b2a9eae6a7db8dfa9f8bb7242e66 Document PushKit entitlement change proposal
adbabef9c1866a82c5e5e3b4ca787a510b3a98b4 Apply minimal PushKit capability files
```

## 2.43M Result

2.43M validates build/profile/codesign capability state only:

- The checked-in 2.43L project built successfully for the generic physical iOS Debug destination.
- Build overrides used the correct physical Debug team: `DEVELOPMENT_TEAM=M639Y9MFR2`.
- Effective Team ID / App Identifier prefix class is `M639Y9MFR2`.
- Effective bundle ID class is `kz.salemx.msg`.
- Effective app entitlements include development `aps-environment`.
- Effective `UIBackgroundModes` includes `voip`.
- No speculative unrestricted VoIP entitlement was present.
- The old Team ID `83LGSC2QPV` was not present in the built app bundle.
- Physical install was blocked because CoreDevice listed the available physical phones as unavailable.
- `app.yml` remains a regeneration risk and must not be used to regenerate the project until source-config signing remediation is separately approved.

No physical PushKit registration smoke was run. Real native direct-call PushKit registration remains disabled by default. No PushKit/APNs token was requested, logged, persisted, or uploaded. No APNs registration was added. No real PushKit/background callback was wired. No media credentials, media connection, Matrix event emission, Element Call route replacement, or production background behavior was introduced.

## Suggested Next Task

Start `2.43N - controlled physical install validation`.

Goal: with at least one physical iPhone available, trusted, unlocked, and visible to Xcode/CoreDevice, install the 2.43M-built Debug app or rebuild/install with the same approved signing overrides, then inspect only safe/redacted installation and capability facts.

Do not enable PushKit registration. Do not request PushKit/APNs tokens. Do not launch a token-registration smoke unless the user explicitly authorizes it in the task. Do not regenerate the project from `app.yml`.

Required checks:

- Preflight clean git status except `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.
- Confirm `SalemX.xcodeproj/project.pbxproj` is clean before any build.
- Build/install with `DEVELOPMENT_TEAM=M639Y9MFR2` and `CODE_SIGN_STYLE=Automatic`.
- Confirm effective app entitlements still include development `aps-environment`.
- Confirm built/installed `UIBackgroundModes` still includes `voip`.
- Confirm old Team ID `83LGSC2QPV` is not used.
- Confirm real PushKit registration remains disabled by default.
- Confirm no PushKit/APNs token is requested/logged/persisted.
- Confirm no media credentials, media connection, Matrix event emission, or Element Call route replacement.
- Confirm route-level server safety:
  - `dev/invite=404`
  - unauthenticated non-dev invite `401`
  - unauthenticated stream `401`

Only claim direct `salemx-call-service active` if `systemctl` or an equivalent direct service check is actually verified. If SSH is blocked or times out, report it separately from route-level safety.

## Do-Not-Touch Constraints

- Do not edit `app.yml`, `.entitlements`, `Info.plist`, signing settings, media logic, or Element Call route replacement logic.
- Do not enable PushKit registration.
- Do not wire PushKit registration to app startup.
- Do not request PushKit/APNs tokens.
- Do not use `dev/invite`, `dev/inject-active`, port `8090`, or `SALEMX_FOREGROUND_SIGNALING_DEV_INVITE_ENABLED=1`.
- Do not log raw tokens, raw identifiers, request payloads, private logs, or secret-bearing URLs.
- Do not stage or commit `docs/direct-call/REPEAT_CALL_FASTPATH_DIAGNOSTICS.md`.
