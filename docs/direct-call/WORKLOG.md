# Native Direct-Call Worklog

This file records durable phase-level progress for future Codex and strategy sessions.

## Milestones

- Added Matrix SDK-backed custom content accessor for direct-call message-like events.
- Added and pinned the SDK custom timeline filter so the native direct-call receive path can observe the custom message-like signal event without changing the visible RoomScreen timeline.
- Hardened receive semantics so historical timeline reset/backlog direct-call events are ignored and only live post-baseline events are delivered to the engine.
- Proved two-client Matrix signalling end-to-end: invite, incoming ringing, accept, answer, and hangup/cleanup diagnostics.
- Proved diagnostic LiveKit media path can reach active under DEBUG/integration-only gates.
- Added production-shaped dependency seams for token, encryption, and media dependencies while keeping them fail-closed and inactive by default.
- Drafted the backend LiveKit token API contract for native direct calls.
- Added the SalemX call service backend skeleton for LiveKit token allocation.
- Added Synapse-backed room validation skeleton for requester/peer membership, encrypted room eligibility, and one-to-one validation.
- Added local backend fake smoke mode for the call service.
- Added app-side production token backend smoke coverage through an env-gated, disabled-by-default test harness.
