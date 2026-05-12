# Native Direct-Call Status

## Current Phase

After 2.10L — local app-to-backend token smoke behind a disabled test harness.

## Latest Commit

`e92c60c6a Add env-gated production token backend smoke test`

## Proven Checkpoints

- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit media proof reached active.
- Production token DTOs, client, and transport seams exist.
- Backend token service skeleton exists.
- Synapse room validation skeleton exists.
- Local backend fake smoke exists.
- App production token client smoke test exists and is disabled by default.

## Current Blocker

- Production backend is still skeleton/fake mode.
- Production E2EE Matrix crypto key wrapping is not implemented.
- No production activation, visible UI, CallKit, or push integration exists yet.

## Next Recommended Phase

Preferred next phase:

`2.10M — production E2EE key wrapping seam inspection`

Alternative documentation phase:

`2.10M — app-to-backend local smoke run instructions / optional CI-safe documentation`

## Do-Not-Touch Constraints

- No visible UI yet.
- No Element Call route reuse.
- No CallKit or push yet.
- No production feature activation.
- No diagnostic secrets or tokens in production.
- No unencrypted key material in Matrix events.
- No raw JSON, `debugInfo`, `originalJSON`, or `originalJson` receive path.
