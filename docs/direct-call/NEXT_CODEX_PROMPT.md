# Next Codex Prompt

Repo:
/Users/aibattt/Movies/element-x-ios

Branch:
salemx-native-direct-calls

Current phase:
After 2.13E — internal production start command skeleton.

Current app code checkpoint:
2.13E `Add internal production direct-call start command skeleton`

Current SDK checkpoint:
f7c2cfe5c `Add direct-call media key envelope crypto tests`

Current wrapper checkpoint:
1e58d0a `Add direct-call media key envelope bindings`

Published artifact:
https://github.com/astana30/matrix-rust-sdk/releases/download/salemx-direct-call-key-envelope-f7c2cfe5c/MatrixSDKFFI-f7c2cfe5c.xcframework.zip

Artifact checksum:
654f7433a6f5a5782abd8aa4d4c2a429a41d679e0612bf38bc05541e7126420e

Phase:
2.13F — internal production start command runtime proof.

Task:
Run the DEBUG/integration-only internal production native direct-call start command in controlled runtime scenarios.
Do not add visible UI.
Do not modify Element Call route.
Do not wire CallKit/push.
Do not activate production direct calls globally.
Do not print or store secrets.

Goal:
Prove the new `production-start-outgoing` runner command is reachable, redacted, fail-closed by default, and gated by `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`, without accidentally touching visible UI or public production behavior.

Context:
- Two-client Matrix signalling proof passed.
- Diagnostic LiveKit active proof passed.
- Backend token service skeleton exists and local fake mode can serve token and capability smoke responses.
- Production token DTO/client/transport/config seams exist and remain inactive by default.
- SDK and Swift wrapper expose async direct-call media key envelope APIs.
- Production key wrapper/provider seams exist but are not publicly activated.
- Production dependency assembly exists and remains disabled by default.
- Room-scoped `production-activation-dry-run` exists through the DEBUG/integration diagnostic command path.
- Room-scoped `production-trigger-dry-run` exists through the DEBUG/integration diagnostic command path.
- Runtime fake-enabled `production-trigger-dry-run` proof passed for A and B in an active encrypted 1:1 room.
- 2.13E added `nativeDirectCallProductionStartOutgoingAudioCall` and runner command `production-start-outgoing A|B`.
- The start command requires the existing integration diagnostic command gates plus `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1`.
- The start command rechecks production trigger dry-run readiness immediately before any start attempt.
- The start command uses a separate production owner factory seam and does not route through the diagnostic developer command router.
- Default production owner construction remains nil/fail-closed, so runtime should block unless a future explicit production owner is assembled.
- Production remains disabled by default.
- `directOneToOneCallsEnabled` remains unused for native production activation.

Suggested runtime checks:
1. Validate the two-client runner.
2. Launch A/B with normal DEBUG/integration diagnostic gates but without `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED`.
3. Open the same encrypted 1:1 room if needed.
4. Run:
   `DRY_RUN=0 Tools/Scripts/run_native_direct_call_diagnostic_two_client.sh production-start-outgoing A`
   `DRY_RUN=0 Tools/Scripts/run_native_direct_call_diagnostic_two_client.sh production-start-outgoing B`
5. Expected without the dedicated start gate:
   - `outcome=blocked`
   - `reason=productionStartDisabled`
   - redacted activation fields only
6. Relaunch A/B with `NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED=1` and, if appropriate, the fake-enabled dry-run gate:
   `NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED=1`
7. Run `production-trigger-dry-run A|B` first to confirm `wouldStart=true` if using fake-enabled activation inputs.
8. Run `production-start-outgoing A|B` again.
9. Expected with start gate and fake-enabled activation but no real production owner assembly:
   - `outcome=blocked`
   - likely `reason=productionOwnerUnavailable`
   - redacted activation fields only
10. Confirm no visible UI, Element Call route, CallKit, push, listener start, Matrix send, or media connect side effects are observed.

Hard constraints:
- No visible UI.
- No `RoomScreenViewModel.displayCall` changes.
- No `RoomScreenCoordinator.presentCallScreen` changes.
- No Element Call route changes.
- No `directOneToOneCallsEnabled` activation or reuse.
- No CallKit/push.
- No global production runtime activation.
- No broad Matrix SDK raw APIs.
- No raw Matrix event JSON, `debugInfo`, `originalJSON`, or `originalJson`.
- No logging unwrapped media-key material, credentials, bearer values, JWTs, encrypted-payload values, or Matrix event content.
- Do not print passwords, Matrix access tokens, LiveKit tokens, participant tokens, backend secrets, diagnostic secrets, raw keys, or copied secret-bearing logs.
- Do not run shutdown/reboot/sleep/logout/killall/osascript power-management commands.

Validation:
- `bash -n Tools/Scripts/run_native_direct_call_diagnostic_two_client.sh`
- Runtime command outputs are redacted.
- No app code changes unless a runner-only bug is found.
- If docs are updated, run `git diff --check` and the docs secret scan.

Expected output:
1. A/B command output without the dedicated start gate.
2. A/B command output with the dedicated start gate and fake-enabled activation, if run.
3. Whether output is redacted.
4. Whether any side effects occurred.
5. Whether code changes were needed.
6. Docs update if useful.
