# iOS embedded Element Call migration audit

Stage: 2A

Baseline:

- Branch: `salemx-2.47a-controlled-media-credentials-boundary`
- HEAD: `a441cf250f3f11635225d8bd21f3074743fb2d82`
- Server prerequisite: Stage 1D-R6 accepted MatrixRTC server functional reference calls.
- Scope: read-only source audit plus documentation. No runtime code, dependency, project, server, APNs or media action was changed.

## Executive conclusion

The local fork already has a pinned, bundled embedded Element Call path for normal MatrixRTC room calls. The production-room path is not a remote SPA: `AppSettings.elementCallBaseURL` is `EmbeddedElementCall.appURL!`, `CallScreen` loads local file URLs with read access to the embedded bundle, and `ElementCallWidgetDriver` builds a Matrix Rust SDK widget URL for a joined room.

The smallest migration boundary is to keep SalemX secure incoming metadata, PushKit and CallKit as bootstrap and OS presentation layers, then adapt the accepted CallKit answer path to hand a validated DM room into the existing `UserSessionFlowCoordinator.startCall(roomID:startMode:)` / `CallScreen` room-call path with `startMode: .audio`.

The custom SalemX direct LiveKit production media path must not be the target architecture. It currently owns a parallel direct-call state machine, custom Matrix signal events, LiveKit token acquisition, direct LiveKit connection, custom remote-audio subscription and a media-key envelope path. Those components should be bypassed during the MatrixRTC migration and retired from production routing only after repeated-call acceptance passes.

Stage 2B is ready for a compile-time adapter seam because the embedded Element Call path, authenticated Matrix session handoff, DM room resolution path and primary migration seam are all present. Audio-only start mode exists, but camera-denial hardening remains a Stage 2 implementation requirement because the current WebKit permission gate is origin-based rather than audio-only specific.

## Dependency topology

| Area | Evidence | Result |
| --- | --- | --- |
| Matrix Rust SDK | `project.yml`, `SalemX.xcodeproj/project.pbxproj` | `https://github.com/astana30/matrix-rust-components-swift`, revision `1e58d0a4317e3ff74c2d565cf532bc8d035bcc8f` |
| Embedded Element Call | `project.yml`, `SalemX.xcodeproj/project.pbxproj` | `https://github.com/element-hq/element-call-swift`, exact version `0.17.0` |
| LiveKit SDK | `project.yml`, `SalemX.xcodeproj/project.pbxproj` | `https://github.com/livekit/client-sdk-swift.git`, exact version `2.13.0` |
| App target delivery | `ElementX/SupportingFiles/target.yml` | App depends on `EmbeddedElementCall`, `MatrixRustSDK` and `LiveKit` |
| Embedded EC patching | `ElementX/SupportingFiles/target.yml` | Pre-build script patches the checked-out `element-call-swift` sources with `Tools/branding/patch_embedded_element_call_rtc.py` |
| Tooling lockfile | `Package.swift`, `Package.resolved` | Top-level package is tooling-only; app package pins live in XcodeGen/project metadata |

`element_call_delivery_model=embedded_package` for internal room calls. Generic Element Call links are a separate external URL surface and are not the SalemX v1 production direct-call target.

## Upstream call flow

| Hop | Symbol | File | Role | Production reachable | Ownership |
| --- | --- | --- | --- | --- | --- |
| Room call button | `RoomScreen` sends `.displayCall(startMode:)` | `ElementX/Sources/Screens/RoomScreen/View/RoomScreen.swift` | Starts a normal room call from room UI | true | upstream |
| Room VM/coordinator action | `RoomScreenViewAction.displayCall`, `RoomScreenCoordinatorAction.presentCallScreen` | `ElementX/Sources/Screens/RoomScreen/RoomScreenModels.swift`, `RoomScreenCoordinator.swift` | Carries requested call start mode | true | upstream |
| Room flow | `RoomFlowCoordinatorAction.presentCallScreen` | `ElementX/Sources/FlowCoordinators/RoomFlowCoordinator.swift` | Sends selected room and start mode upward | true | upstream |
| User session flow | `UserSessionFlowCoordinator.startCall(roomID:startMode:)` | `ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift` | Resolves `JoinedRoomProxy` from authenticated `ClientProxy` and presents call screen | true | upstream |
| Call configuration | `ElementCallConfiguration.Kind.roomCall` | `ElementX/Sources/Services/ElementCall/ElementCallConfiguration.swift` | Holds room proxy, client proxy, client ID, embedded base URL and start mode | true | upstream |
| Widget driver | `ElementCallWidgetDriver.start` | `ElementX/Sources/Services/ElementCall/ElementCallWidgetDriver.swift` | Uses Matrix Rust SDK room APIs and widget driver to generate the EC URL | true | upstream |
| RTC authorization bridge | `CallScreenViewModel.makeRTCTransportScript` | `ElementX/Sources/Screens/CallScreen/CallScreenViewModel.swift` | Injects Matrix bearer authorization only for MatrixRTC transport and `/livekit/jwt` paths | true | mixed |
| Embedded web view | `CallScreen.CallView.Coordinator.load` | `ElementX/Sources/Screens/CallScreen/View/CallScreen.swift` | Loads bundled Element Call file URL with bundle read access | true | upstream |
| Session setup | `ElementCallService.setupCallSession` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | Tracks active CallKit/Element Call room session after widget start | true | upstream |
| Hangup | `CallScreenViewModel.hangup` and `.requestCallTermination` | `CallScreenViewModel.swift`, `ElementCallService.swift` | Sends widget hangup and tears down service state | true | upstream |

Normal Element X room calls are room-based MatrixRTC calls presented through embedded Element Call. They are not direct native LiveKit connections. One-to-one calls are represented as direct-room MatrixRTC calls and receive native audio/video chrome in `CallScreen`, but media still runs through embedded Element Call.

## SalemX direct-call flow

Current SalemX direct-call components and target classification:

| Component | Evidence | Current role | Classification |
| --- | --- | --- | --- |
| PushKit ingress | `ElementCallService.pushRegistry(_:didReceiveIncomingPushWith:)`, DEBUG bridge hook | Receives VoIP pushes and reports CallKit | KEEP |
| CallKit provider/delegate | `ElementCallService` | OS incoming UI, answer, end, mute bridge | KEEP/ADAPT |
| Secure metadata claim/proof helpers | `NativeIncomingSyntheticCallKitUIProofAdapter.swift` | Metadata prepare/claim/send proof and redacted diagnostics | KEEP for server contract, ADAPT for production handoff, TEST_ONLY for synthetic helpers |
| Foreground-signaling service client | `DeveloperOptionsScreenHook.swift`, `NativeIncomingSyntheticCallKitUIProofAdapter.swift` | SSE/invite proof surface | KEEP for bootstrap contract, TEST_ONLY where DEBUG proof-only |
| Direct-call room card | `RoomScreen.swift`, `RoomScreenViewModel.swift` | DEBUG native direct call control surface | BYPASS |
| Direct-call engine | `DirectCallEngine.swift`, `DirectCallModels.swift` | Parallel invite/answer/connect/active/end state authority | RETIRE from production |
| Custom Matrix signal transport | `DirectCallSignalTransport.swift`, `JoinedRoomProxy.makeNativeDirectCallTimelineSignalListener` | Sends/listens to `kz.salemx.direct_call.signal` events | RETIRE from production |
| LiveKit media factory | `DirectCallMediaEngineFactory.swift` | Builds direct LiveKit media dependencies | RETIRE from production |
| Direct LiveKit media engine | `LiveKitDirectCallMediaEngine.swift` | Requests credentials and connects audio | RETIRE from production |
| Direct LiveKit client | `LiveKitDirectCallClient.swift` | Joins LiveKit, publishes microphone, subscribes remote audio | RETIRE from production |
| Credentials client | `DirectCallMediaEngineProtocol.swift`, `DirectCallProductionConfiguration` | Calls custom `/kz.salemx.direct_call/livekit/token` endpoint | RETIRE from production |
| Media key wrapper | `MatrixSDKDirectCallMediaKeyWrapper.swift`, `DirectCallProductionKeyWrappingTests.swift` | Custom LiveKit E2EE key-envelope path | RETIRE from production |
| Native direct flow owner | `RoomFlowCoordinator.NativeDirectCallRoomFlowOwner` | Wraps direct-call trigger for production-like harness | BYPASS, then remove after acceptance |
| Audio route bridge | `CallScreenViewModel` | Earpiece/speaker handling for embedded direct room calls | KEEP/ADAPT |
| Matrix call-event observer/filter | `RoomCallEventParser`, `ElementCallService` foreground room observation | Room call display and incoming fallback | KEEP, with replay tests |
| Synthetic proof/debug helpers | `NativeIncomingSyntheticCallKitUIProofAdapter`, `NativeDirectCallRoomDeveloperCommandRouter`, `NativeDirectCallDiagnosticLiveKitMedia` | Development and proof controls | TEST_ONLY |

## Call-state authority matrix

| State | Current authorities | Conflict risk | Target single authority | Required change |
| --- | --- | --- | --- | --- |
| Incoming | PushKit/CallKit, ElementCallService, direct engine/proof helpers | high | Salem metadata bootstrap plus MatrixRTC room call | Route SalemX incoming metadata into room-call handoff, not direct engine |
| Ringing | CallKit, ElementCallService `CallSession`, direct engine | high | CallKit presentation plus MatrixRTC call availability | Keep CallKit as UI only; do not emit custom direct signals |
| Answered | `CXAnswerCallAction`, direct engine `acceptCall`, widget join | high | Embedded Element Call joins MatrixRTC after CallKit answer | Replace direct accept/media credential path with `startCall(roomID:.audio)` |
| Connecting | Direct engine and LiveKit media engine; embedded EC widget | high | Embedded Element Call / MatrixRTC | Bypass direct `connectMediaIfReady` |
| Connected | Direct LiveKit client and EC media state | high | Embedded Element Call media state | Observe EC widget/media state only |
| Ended | CallKit end, widget hangup, direct hangup, Matrix events | high | MatrixRTC leave/hangup with CallKit teardown bridge | Make CallKit end call widget hangup and never custom direct hangup |
| Remote participant left | Direct LiveKit remote participant snapshot, MatrixRTC membership | high | MatrixRTC / embedded Element Call | Use EC/MatrixRTC state; remove direct snapshot as production gate |
| Retry | Direct room card, repeated-call timers | medium | MatrixRTC room call re-entry | Stage 2H repeated-call acceptance before removal |
| Cleanup | Direct engine cleanup, EC teardown, CallKit teardown | high | MatrixRTC room cleanup with CallKit bridge cleanup | Tests for stale membership and repeated-call trail |

CallKit remains an OS presentation and action bridge. It must not become an independent call-state protocol.

## Embedded Element Call capability matrix

| Capability | Supported now | Evidence | Gap |
| --- | --- | --- | --- |
| One-to-one room call | true | `JoinedRoomProxy.isDirectOneToOneRoom`, `ElementCallWidgetDriver.adjustedCallURL` direct-room parameters | SalemX metadata must resolve the target DM room |
| Audio-only start | true | `ElementCallStartMode.audio`, room audio button, `joinCallIntent(for:)`, `allowPictureInPicture: startMode == .video` | Stage 2 must ensure SalemX path always chooses `.audio` |
| Audio-only answer | partial | `ElementCallService` parses incoming start mode and CallKit answer emits `.startCall(roomID:startMode:)` | SalemX secure metadata path is not yet adapted to that answer bridge |
| Camera disabled | partial | Audio start mode disables video UI/PiP, but WebKit permission grant is origin-based | Add v1 audio-only camera denial or equivalent proof before physical acceptance |
| Existing authenticated Matrix session | true | `UserSessionFlowCoordinator` uses `userSession.clientProxy`; RTC script uses client homeserver/access token | Keep token redaction and avoid new credential surfaces |
| Existing room/session identifier | true | `presentCallScreen(roomID:)` resolves `roomForIdentifier(roomID)` | Adapter must pass a verified DM room ID |
| Programmatic presentation | true | `UserSessionFlowCoordinator.startCall(roomID:startMode:)` | None for Stage 2B |
| Programmatic hangup | partial | `ElementCallService.requestCallTermination` and `CallScreenViewModel` widget hangup | Need SalemX CallKit end tests after adapter |
| CallKit answer bridging | partial | `CXAnswerCallAction` sends `.startCall(roomID:startMode:)` for normal MatrixRTC push | Need SalemX secure metadata answer bridge |
| CallKit end bridging | partial | `CXEndCallAction` sends `.requestCallTermination(roomID:)` | Need no-double-end and remote-end synchronization tests |
| Foreground/background transition handling | partial | `ElementCallService`, CallScreen PiP/fullscreen logic | Physical background acceptance remains Stage 2G/2H |
| Media E2EE | true for MatrixRTC path | `ElementCallWidgetDriver` uses per-participant keys for encrypted rooms | Verify in controlled reference call on device later |
| Remote participant state observation | partial | widget `.mediaState`, room info active participants, ElementCallService trackers | Need SalemX-specific assertions after handoff |

## Remote SPA assessment

| Source | Classification | Production target impact |
| --- | --- | --- |
| `AppSettings.elementCallBaseURL = EmbeddedElementCall.appURL!` | bundled_local | Required target for SalemX v1 |
| `CallScreen.loadFileURL(... EmbeddedElementCall.bundle.bundleURL)` | bundled_local | Required target for SalemX v1 |
| `elementCallBaseURLOverride` developer setting | dynamic_remote | Must not be used by SalemX v1 production direct-call migration |
| `AppRoutes.ElementCallURLParser` for `call.element.io` | trusted_fixed_remote | Generic external call links, not SalemX v1 direct-call target |
| `CallScreen` previews using `https://call.element.io` | test_only | No production effect |

`dynamic_remote_spa_in_production_path=false` for the selected SalemX migration boundary, provided the adapter always uses the internal room-call configuration and does not enable the developer override for the production direct-call path.

## Selected migration seam

Primary seam:

| Field | Value |
| --- | --- |
| Entry symbol | `UserSessionFlowCoordinator.startCall(roomID:startMode:)` called after SalemX metadata claim and CallKit answer acceptance |
| Entry file | `ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift` |
| Inputs available | Authenticated `ClientProxy`, room ID, room proxy resolution, Element Call base URL, `.audio` start mode |
| Missing inputs | A narrow adapter from SalemX claimed metadata to verified DM room ID and start mode |
| Custom components bypassed | `DirectCallEngine.acceptCall`, `requestMediaCredentials`, `LiveKitDirectCallMediaEngine`, `LiveKitDirectCallClient`, custom direct signal transport |
| Upstream components invoked | `ElementCallConfiguration`, `ElementCallWidgetDriver`, `CallScreenViewModel`, `EmbeddedElementCall`, `ElementCallService` session/hangup bridge |
| Risk | Medium: CallKit answer and end are partially implemented for normal MatrixRTC but need SalemX-specific tests and camera hardening |

Fallback seam:

| Field | Value |
| --- | --- |
| Entry symbol | Existing `ElementCallServiceAction.startCall(roomID:startMode:)` emission |
| Entry file | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` |
| Use only if | Stage 2B needs to keep the adapter inside ElementCallService instead of the user-session flow |
| Risk | Higher: ElementCallService already owns a local call session tracker, so adding SalemX metadata logic here can deepen the authority conflict |

Rejected seams:

- Any seam that constructs LiveKit JWTs on iOS.
- Any seam that directly joins LiveKit from SalemX code.
- Any seam that keeps `DirectCallEngine` as production state authority.
- Any seam that loads an unpinned remote Element Call SPA.
- Any seam that emits synthetic Matrix call events from SalemX code.

## Lifecycle risks

| Historical failure mode | Classification | Reason |
| --- | --- | --- |
| PC manager is closed | removed_by_migration | Custom direct WebRTC/LiveKit media is bypassed; embedded EC owns media internals |
| Dispatcher missing | removed_by_migration | Direct LiveKit media dispatcher path is bypassed |
| Room binding missing | requires_adapter_fix | Adapter must resolve and validate a joined DM room before handoff |
| Remote audio subscription missing | removed_by_migration | Direct manual LiveKit subscription is bypassed |
| Repeated-call trail | still_relevant | Stage 1 server passed, but iOS handoff must preserve cleanup |
| Stale MatrixRTC membership | still_relevant | MatrixRTC is the new authority and must be tested after iOS handoff |
| Malformed `m.call.hangup` | requires_adapter_fix | CallKit end must call EC widget hangup, not custom malformed events |
| Historical call event replay | still_relevant | `RoomCallEventParser` and ElementCallService fallback logic remain active |
| Duplicate incoming presentation | requires_adapter_fix | PushKit, CallKit, foreground metadata and MatrixRTC fallback must dedupe |
| CallKit end without MatrixRTC leave | requires_adapter_fix | End bridge must send EC hangup and await/observe cleanup |
| MatrixRTC leave without CallKit teardown | requires_adapter_fix | Remote-end observation must dismiss native UI and CallKit state |

## Staged implementation sequence

| Stage | Objective | Maximum changed files | Allowed files/modules | Tests | Physical action allowed | Stop conditions | Rollback boundary | Commit message |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2B | Add compile-time seam that can invoke embedded EC with `.audio` from a verified room ID behind disabled gate | 8 | `Services/ElementCall`, `FlowCoordinators`, new adapter tests | targeted unit tests for seam inputs and no LiveKit invocation | none | direct LiveKit called, dynamic remote URL used, package/project touched | revert adapter files | `Add embedded Element Call handoff seam` |
| 2C | Bind authenticated session and claimed DM room metadata into the seam | 10 | SalemX metadata/claim adapter, flow coordinator tests | metadata claim adapter tests, room resolution tests | none | room not joined, not DM, no authenticated session | revert metadata adapter | `Bind SalemX metadata to MatrixRTC room handoff` |
| 2D | Bridge CallKit answer to audio-only embedded EC start | 10 | `ElementCallService`, adapter, tests | CallKit answer unit tests, camera-denial assertion if implemented | none | camera request allowed, direct media credentials requested | revert answer bridge | `Bridge SalemX answer to embedded Element Call` |
| 2E | Synchronize hangup, remote end and cleanup | 10 | `ElementCallService`, `CallScreenViewModel`, adapter tests | end action, remote end, duplicate end tests | none | stale CallKit or MatrixRTC state | revert end bridge | `Synchronize MatrixRTC hangup and CallKit teardown` |
| 2F | Foreground controlled reference call on simulator/local device path only | 6 | test harness/docs only | targeted UI or integration smoke | no APNs, no production users | media connects through direct LiveKit or camera/video appears | revert harness changes | `Verify foreground embedded Element Call handoff` |
| 2G | One sandbox APNs physical incoming call | 6 | test harness/docs only | physical acceptance log and narrow assertions | one sandbox APNs maximum | no PushKit, auth fail, no CallKit answer, direct LiveKit used | revert harness changes | `Verify sandbox APNs MatrixRTC incoming call` |
| 2H | Repeated-call and cleanup acceptance | 6 | tests/docs only | two-call cleanup, stale membership, repeated trail | controlled physical/device call sequence | stale membership, repeated-call trail, webhook debt worsens | revert harness/docs | `Accept repeated MatrixRTC direct calls` |
| 2I | Retire custom direct LiveKit production routing | 12 | `Services/Calls`, flow/coordinator routing, tests | direct LiveKit absence tests, old proof still DEBUG-only | none | replacement acceptance incomplete | revert removal | `Retire custom direct LiveKit production routing` |

Constraints for every stage: one narrow commit, no production APNs, no camera, no video, no group calls, no direct LiveKit fallback, stop at first failed gate, and do not remove old code before Stage 2H passes.

## Test inventory

| Test file or suite | What it proves | Production path covered | Reusable |
| --- | --- | --- | --- |
| `UnitTests/Sources/ElementCallServiceTests.swift` | PushKit/CallKit session transitions, answer/end behavior, repeat incoming fast path | partial | true |
| `UnitTests/Sources/CallScreenViewModelTests.swift` | CallScreen setup, view-model state, widget interaction behavior | partial | true |
| `UnitTests/Sources/RoomCallEventTests.swift` | Matrix call and RTC notification timeline parsing | partial | true |
| `UnitTests/Sources/RoomScreenViewModelTests.swift` | Room UI actions and native direct-call card state | partial | true, for UI action regression |
| `UnitTests/Sources/DirectCallEngineTests.swift` | Existing custom direct-call state machine and lifecycle contracts | old path | limited, useful for removal guards |
| `UnitTests/Sources/DirectCallEngineSignalTransportTests.swift` | Custom direct Matrix signal transport/composition integration | old path | limited, useful for retirement assertions |
| `UnitTests/Sources/DirectCallMediaEngineTests.swift` | Direct LiveKit media engine, token, audio and diagnostics behavior | old path | limited, useful for no-production-routing assertions |
| `UnitTests/Sources/DirectCallProductionCapabilitySourceTests.swift` | Custom direct-call server capability and token endpoint behavior | old path | limited |
| `UnitTests/Sources/DirectCallProductionKeyWrappingTests.swift` | Custom direct LiveKit E2EE key wrapping | old path | limited |
| `UnitTests/Sources/NativeIncomingSyntheticCallKitUIProofTests.swift` | Synthetic CallKit proof adapter behavior | test-only | limited |
| `UnitTests/Sources/NativeDirectCallInternalControlPanelTests.swift` | DEBUG direct-call controls | test-only | limited |
| `UITests/Sources/RoomScreenTests.swift` | Room screen snapshots/UI | partial | true for visible migration impacts |

Missing before/within Stage 2B:

- A unit test that verifies the new SalemX handoff invokes `UserSessionFlowCoordinator.startCall(roomID:startMode:.audio)` and never invokes direct LiveKit credentials.
- A unit test that rejects unjoined, non-DM or missing-room inputs before handoff.
- A test or static assertion that the SalemX v1 path cannot use `elementCallBaseURLOverride`.
- A no-camera v1 assertion for audio-only embedded calls.
- A CallKit answer test that proves SalemX metadata answer does not enter `DirectCallEngine.acceptCall`.

## Blockers and unknowns

- Production webhook observability debt remains open, but it blocks production rollout rather than Stage 2 development.
- Camera permission hardening is partial in current source. The migration can start, but Stage 2D or earlier must prove the SalemX v1 path cannot request camera.
- The embedded Element Call package is patched by a pre-build script. This audit does not judge the patch content; Stage 2B should keep its seam independent of further package edits.
- The exact SalemX secure metadata production adapter is mixed with DEBUG proof code today. Stage 2B/2C must isolate the production metadata-to-room handoff without promoting proof-only controls.
- Existing generic Element Call links can load trusted remote URLs. They are not the selected SalemX v1 production path and must remain separate from the direct-call migration.

## Stage 2B entry conditions

```text
upstream_embedded_element_call_path_found=true
authenticated_matrix_session_handoff_found=true
dm_room_resolution_path_found=true
audio_only_configuration_path_found=partial
callkit_answer_bridge_existing=partial
callkit_end_bridge_existing=partial
dynamic_remote_spa_in_production_path=false
primary_migration_seam_selected=true
custom_direct_livekit_retirement_boundary_defined=true
stage_2b_ready=true
```

Stage 2B must not begin media connection or APNs work. It should add only the compile-time seam and tests proving that SalemX direct-call production routing can hand off to the existing embedded Element Call path without constructing LiveKit credentials or joining LiveKit from iOS.
