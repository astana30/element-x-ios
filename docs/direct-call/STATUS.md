# Native Direct-Call Status

## Current Phase

After 2.10N — production E2EE app key-wrapping seam skeleton.

## Latest Commit

2.10N implementation commit: `Add production direct-call key wrapping seams`

## Latest Code Checkpoint

2.10N local checkpoint: production direct-call key wrapping seams added and validated.

## Proven Checkpoints

- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit media proof reached active.
- Production token DTOs, client, and transport seams exist.
- Backend token service skeleton exists.
- Synapse room validation skeleton exists.
- Local backend fake smoke exists.
- App production token client smoke test exists and is disabled by default.
- Production E2EE key wrapping seam inspection is complete:
  - The direct-call room-flow path has room and peer metadata plus a clean dependency injection point.
  - The custom direct-call Matrix event is sent through SDK room sending and is expected to be room-encrypted when the room is encrypted.
  - Room encryption is a necessary transport layer, but not sufficient as the production media-key wrapping design: the app still must not place unwrapped media key material in the event content handed to the SDK.
  - The current app Matrix crypto proxies expose identity/key status, but not a narrow per-call media-key wrapping primitive.
  - The Rust SDK has lower-level custom encrypted to-device capabilities in source, but the current Swift app/wrapper does not expose a direct-call key wrapping API suitable for the room-timeline signal path.
- App-side production key-wrapping seams now exist and remain fail-closed:
  - `DirectCallMediaKeyWrappingProtocol` models wrap/unwrap requests around call, room, sender, recipient, device, intent, expiry, key ID, and an opaque envelope.
  - `FailClosedDirectCallMediaKeyWrapper` is the default wrapper and cannot wrap or unwrap.
  - `ProductionDirectCallEncryptionService` can use an injected wrapper plus a shared `DirectCallLiveKitMediaKeyStore`, but defaults to fail-closed with no production activation.
  - `NativeDirectCallProductionDependenciesFactory` can accept a future production key wrapper and shared media key store, while remaining disabled by default.

## Current Blocker

- Production backend is still skeleton/fake mode.
- Production E2EE Matrix crypto key wrapping is not implemented; the app seam is only a fail-closed skeleton.
- A narrow Matrix SDK/wrapper seam is still missing for wrapping/unwrapping per-call media keys without exposing event JSON or broad raw APIs.
- `DirectCallEncryptionServiceProtocol` is synchronous today; production Matrix crypto wrapping is likely async because it may need SDK crypto/device lookup.
- Production key exchange can be bridged to `DirectCallLiveKitMediaKeyStore` via injection, but only with fake/test wrappers today.
- Production trust policy for peer devices is not finalized; the safest initial policy should fail closed on unknown or unverifiable device trust.
- No production activation, visible UI, CallKit, or push integration exists yet.

## Next Recommended Phase

`2.10O — Matrix SDK narrow direct-call key wrapping seam prototype`

## Do-Not-Touch Constraints

- No visible UI yet.
- No Element Call route reuse.
- No CallKit or push yet.
- No production feature activation.
- No diagnostic secrets or tokens in production.
- No unencrypted key material in Matrix events.
- No raw JSON, `debugInfo`, `originalJSON`, or `originalJson` receive path.
