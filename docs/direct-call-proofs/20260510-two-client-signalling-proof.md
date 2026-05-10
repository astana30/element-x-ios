# SalemX Native Direct Call — Two-Client Signalling Proof

## Result

Two-client native direct-call signalling proof passed.

## Proven

- A prepare succeeded.
- B prepare succeeded.
- A startListener succeeded.
- B startListener succeeded.
- A startOutgoingAudioCall succeeded.
- A sent invite.
- B received invite and entered incomingRinging.
- B acceptIncomingCall reached engine.
- B sent answer.
- A received answer.

## Expected limitation

Media failed closed with:

- mediaSetupUnavailable
- connectingFailed

This is expected because real LiveKit runtime DI is not wired yet.

## Untouched

- No visible UI activation.
- No Element Call route changes.
- No CallKit/push changes.
- No production feature flag activation.
