# Native Direct-Call Decisions

## Architecture Decisions

- Backend issues LiveKit participant tokens for native direct calls.
- The app must never store or use a LiveKit API secret.
- The backend must not know media E2EE unencrypted key material.
- Matrix signalling carries only opaque encrypted key exchange payloads, not LiveKit credentials.
- Diagnostic env and runner paths are not production paths.
- Visible UI waits until production token and production E2EE paths are ready.
- The existing Element Call route remains separate and unchanged.
- The SDK custom timeline filter is used only for the native direct-call receive path, not the visible RoomScreen timeline.

## Security Decisions

- No unencrypted media key material is written to Matrix events.
- No LiveKit participant token or server allocation is written to Matrix signalling.
- Redacted diagnostics may expose state enums and booleans, but not credentials, raw content, or key material.
- Production dependencies remain fail-closed until explicit production configuration and implementations exist.
