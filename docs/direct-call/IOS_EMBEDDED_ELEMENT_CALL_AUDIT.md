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
| LiveKit SDK | `project.yml`, `SalemX.xcodeproj/project.pbxproj` | `https://github.com/livekit/client-sdk-swift.git`, exact version `2.16.0` |
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

## Stage 2B handoff seam

Stage 2B introduced a compile-time-only embedded Element Call handoff seam without changing active SalemX direct-call routing.

Typed contract:

```text
protocol=EmbeddedElementCallHandoff
method=prepareAudioCall(roomID:intent:)
intent_cases=startNew,joinExisting,presentExisting
result_cases=readyToPresent,alreadyPresented,noExistingCall,unsupportedIncomingJoin
lifecycle_events=presented,joining,connected,remoteEnded,localEnded,failed,dismissed
```

Production adapter:

```text
adapter=EmbeddedElementCallProductionHandoff
presenter_protocol=EmbeddedElementCallRoomCallPresenting
state_protocol=EmbeddedElementCallRoomCallStateProviding
state_adapter=EmbeddedElementCallServiceRoomCallStateProvider
coordinator_conformance=UserSessionFlowCoordinator: EmbeddedElementCallRoomCallPresenting
```

Operation semantics recorded for Stage 2B:

| Operation | Production symbol | Semantics proven | Stage 2B behavior |
| --- | --- | --- | --- |
| Start new audio room call | `UserSessionFlowCoordinator.startCall(roomID:startMode:)` -> `presentCallScreen(roomID:startMode:)` -> `ElementCallWidgetDriver.start` | true | `startNew` presents the embedded room-call path with `startMode=.audio` |
| Join existing incoming MatrixRTC call | No separate proven programmatic API in this repository stage | unsupported | `joinExisting` returns `unsupportedIncomingJoin`; it never falls back to `startNew` |
| Present existing call UI | `UserSessionFlowCoordinator.startCall` re-enters the existing overlay only when the same room is already the ongoing call | true | `presentExisting` requires the state provider to report the same room, otherwise returns `noExistingCall` |
| End or leave | `CallScreenViewModel` sends widget hangup; `ElementCallService.requestCallTermination` emits end action | not wired in Stage 2B | lifecycle vocabulary only; no mutable SalemX state machine |

The handoff result contains only the Matrix room ID, intent, `ElementCallStartMode.audio`, and the upstream lifecycle vocabulary needed by later stages. It intentionally contains no LiveKit URL, LiveKit JWT, LiveKit room alias, participant identity, media key, Matrix access token, raw widget URL, or remote SPA URL.

Audio-only status:

```text
startMode=.audio
camera_requested=false
video_enabled=false
audio_only_enforcement=partial
```

The stage keeps audio intent explicit, but camera hardening remains partial because the existing `WKWebView` media-permission delegate is origin-gated rather than v1 audio-only hard-denied.

Production routing:

```text
production_direct_livekit_route_changed=false
callkit_answer_wired=false
pushkit_changed=false
direct_livekit_dependency_added=false
```

Validation:

```text
changed_swift_files_swiftformat_lint=pass
changed_swift_files_swiftlint=pass
handoff_protocol_typecheck_harness=pass
handoff_behavior_isolation_harness=pass
coordinator_and_test_syntax_parse=pass
xcodebuild_package_resolution_disabled_attempt=blocked_before_compile_by_local_cache_permissions
simulator_run=false
package_update=false
```

Stage 2C entry conditions after Stage 2B:

```text
typed_handoff_contract_created=true
upstream_adapter_created=true
start_new_semantics_proven=true
join_existing_semantics_proven=unsupported
present_existing_semantics_proven=true
join_never_falls_back_to_start=true
audio_only_intent_explicit=true
camera_permission_requested=false
livekit_credentials_exposed=false
second_call_state_machine_created=false
production_direct_livekit_route_changed=false
callkit_answer_wired=false
stage_2c_ready=true
```

## Stage 2C authenticated metadata binding

Stage 2C introduced `SalemXAuthenticatedMatrixRTCHandoff`, a narrow adapter from already-claimed SalemX MatrixRTC metadata into the Stage 2B embedded Element Call handoff seam.

Stage 2C-R2 also closed the MatrixRustSDK packaging defect that had kept SwiftPM from exposing `matrix_sdk_ffiFFI` through the public XCFramework header root. The published `packagingfix1` asset keeps the binary payloads unchanged, exposes the module map from `Headers/MatrixSDKFFI`, and is pinned through wrapper commit `a4d568701a249bb7d1e8019ed6fef9ebf4a2c461`. The release asset hash is `f9ace1c50d7facf73c80feae349e8317de4d229ee21b53e91e2083e25124669c`; release governance still has an open debt because the release metadata remains `isImmutable=false`.

```text
release_asset_published=true
release_asset_hash_verified=true
release_metadata_immutable=false
release_immutability_debt=open
```

Typed contract:

```text
adapter=SalemXAuthenticatedMatrixRTCHandoff
input=SalemXMatrixRTCClaimedMetadata
metadata_fields=roomID,localUserID,peerUserID,peerDeviceID,direction
validation=authenticated_user_match,joined_room,room_id_match,direct_one_to_one_room,local_member,peer_member
success=delegates_to_EmbeddedElementCallHandoff
blocked_reasons=malformedClaimedMetadata,unauthenticatedSession,authenticatedUserMismatch,roomNotJoined,roomIDMismatch,roomNotDirectOneToOne,localUserNotMember,peerUserNotMember
```

Operation semantics recorded for Stage 2C:

| Operation | Semantics proven | Stage 2C behavior |
| --- | --- | --- |
| Claimed outgoing DM metadata | Authenticated local user and verified joined one-to-one DM room are required before handoff | Delegates to Stage 2B handoff with `.startNew` and `.audio` preparation |
| Claimed incoming DM metadata | Incoming metadata may be validated without changing join semantics | Delegates the caller's `.joinExisting` intent and preserves `unsupportedIncomingJoin` |
| Missing or malformed metadata | No room lookup or handoff occurs | Blocks with `malformedClaimedMetadata` |
| Missing authenticated session | No room lookup or handoff occurs | Blocks with `unauthenticatedSession` |
| Claimed user mismatch | No room lookup or handoff occurs | Blocks with `authenticatedUserMismatch` |
| Unjoined room | No handoff occurs | Blocks with `roomNotJoined` |
| Non-DM or multi-member room | No member probe or handoff occurs | Blocks with `roomNotDirectOneToOne` |
| Peer outside the room | No handoff occurs | Blocks with `peerUserNotMember` |

The adapter intentionally carries no LiveKit URL, LiveKit JWT, LiveKit room alias, media key, Matrix access token, widget URL, remote SPA URL, PushKit payload, APNs payload, CallKit UUID, or direct-call engine session. It does not request media credentials, send APNs, wire CallKit answer, connect media, request camera, enable video, or emit Matrix call media events.

Metadata and adapter result descriptions redact room IDs, user IDs and device IDs.

Validation:

```text
claimed_joined_dm_room_handoff=covered_by_unit_test
incoming_join_unsupported_semantics=covered_by_unit_test
malformed_metadata_blocks_before_room_lookup=covered_by_unit_test
unauthenticated_session_blocks_before_room_lookup=covered_by_unit_test
authenticated_user_mismatch_blocks_before_room_lookup=covered_by_unit_test
unjoined_room_blocks_before_handoff=covered_by_unit_test
non_direct_room_blocks_before_handoff=covered_by_unit_test
multi_member_room_blocks_before_handoff=covered_by_unit_test
peer_outside_room_blocks_before_handoff=covered_by_unit_test
metadata_description_redacted=covered_by_unit_test
handoff_result_description_redacted=covered_by_unit_test
matrixrustsdk_target_compile_passed=true
elementx_unittests_target_compile_passed=true
filtered_salemx_handoff_tests_passed=true
changed_swift_files_swiftformat=pass
changed_swift_files_swiftlint=pass
changed_swift_files_syntax_parse=pass
targeted_unit_test_attempt=passed
```

Stage 2D entry conditions after Stage 2C:

```text
packaging_defect_repaired=true
generated_bindings_unchanged=true
binary_payloads_unchanged=true
release_asset_published=true
release_asset_hash_verified=true
release_metadata_immutable=false
release_immutability_debt=open
wrapper_commit_pushed=true
elementx_pin_updated=true
matrixrustsdk_target_compile_passed=true
elementx_unittests_target_compile_passed=true
filtered_salemx_handoff_tests_passed=true
authenticated_metadata_adapter_created=true
local_authenticated_user_bound=true
joined_dm_room_validation_created=true
local_and_peer_membership_validation_created=true
incoming_join_semantics_unchanged=true
livekit_credentials_requested=false
pushkit_changed=false
callkit_answer_wired=false
media_connection_started=false
camera_permission_requested=false
stage_2d_ready=true
```

## Stage 2D disabled CallKit answer bridge

Stage 2D added a disabled-by-default, audio-only CallKit answer bridge from the production `CXAnswerCallAction` handler into the verified Stage 2C MatrixRTC handoff. The default production route is unchanged while `embeddedMatrixRTCAnswerBridgeEnabled=false`.

Actual production answer path:

| Hop | Symbol | File | production_reachable | salemx_or_upstream | current_side_effect |
| --- | --- | --- | --- | --- | --- |
| PushKit ingress | `ElementCallService.pushRegistry(_:didReceiveIncomingPushWith:for:completion:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | mixed | Parses the VoIP push into private `CallID`, records room and RTC notification IDs, creates incoming `CallSession`, reports a native CallKit incoming call and starts the unanswered timeout. |
| CallKit answer entry | `ElementCallService.provider(_:perform: CXAnswerCallAction)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | mixed | Receives the OS answer action and delegates to `handleAnswerCallAction`. |
| Gate and UUID lookup | `ElementCallService.handleAnswerCallAction(_:provider:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | salemx | Uses `embeddedMatrixRTCAnswerBridgeEnabled`; disabled path calls the legacy answer handler, enabled path requires `incomingCallID.callKitID == action.callUUID`. |
| Legacy route | `ElementCallService.handleLegacyAnswerCallAction(_:provider:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | upstream | Preserves current behavior: apply accept, fulfill immediately, delay, report CallKit ended and send `.startCall(roomID:startMode:)`. |
| Bootstrap lookup | `SalemXIncomingCallBootstrapResolving.verifiedBootstrap(for:)` | `ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift` | true only when Stage 2D gate is enabled | salemx | Reuses an already-claimed `VerifiedIncomingCallBootstrap`; does not claim metadata again and does not read raw PushKit payload fields. |
| Enabled answer bridge | `SalemXEmbeddedCallAnswerBridge.answer(callID:bootstrap:)` | `ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift` | true only when Stage 2D gate is enabled | salemx | Checks bootstrap UUID, authenticated Matrix user, local device and active MatrixRTC evidence, then invokes handoff with `.presentExisting`. |
| MatrixRTC handoff | `SalemXAuthenticatedMatrixRTCHandoff.prepareAudioCall(claimedMetadata:intent:)` | `ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift` | true only when Stage 2D gate is enabled | salemx | Validates joined one-to-one DM room membership and delegates to `EmbeddedElementCallHandoff` without creating rooms or direct LiveKit media. |
| Embedded presentation | `EmbeddedElementCallProductionHandoff.prepareAudioCall(roomID:intent:)` | `ElementX/Sources/Services/ElementCall/ElementCallServiceProtocol.swift` | true only when Stage 2D gate is enabled and state already reports the room | upstream | For `.presentExisting`, requires the same existing room and calls the embedded Element Call presenter with `ElementCallStartMode.audio`; `.startNew` is not selected by incoming answer. |
| Action completion | `ElementCallService.finishEmbeddedMatrixRTCAnswer(callID:incomingCallID:result:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true only when Stage 2D gate is enabled | salemx | `presentationAccepted` or `alreadyPresented` fulfills once and reports native CallKit ended; every typed failure, timeout or cancellation fails once and tears down local state. |

Excluded answer paths:

| Symbol | File | production_reachable | Reason |
| --- | --- | --- | --- |
| `NativeIncomingSyntheticCallKitUIProofAdapter.provider(_:perform: CXAnswerCallAction)` | `ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift` | false | Synthetic CallKit proof helper, DEBUG/test-only; not wired by Stage 2D. |
| `DirectCallEngine.acceptCall` | `ElementX/Sources/Services/Calls/DirectCallEngine.swift` | false for Stage 2D bridge | Custom direct LiveKit answer path remains present but is not invoked by the embedded MatrixRTC answer bridge. |

Answer bridge contract:

```text
protocol=SalemXEmbeddedCallAnswerBridging
input=callID:UUID,bootstrap:VerifiedIncomingCallBootstrap
bootstrap_source=already_claimed_and_validated_metadata_only
required_consistency=callkit_uuid,room_id,authenticated_user,authenticated_device,active_matrixrtc_call
operation=SalemXMatrixRTCHandoff.prepareAudioCall(intent:.presentExisting)
start_mode=audio
typed_results=presentationAccepted,alreadyPresented,noAuthenticatedSession,sessionIdentityMismatch,sessionDeviceMismatch,dmRoomNotFound,dmRoomAmbiguous,dmRoomInvalid,noActiveMatrixRTCCall,activeCallStateUnavailable,unsupportedIncomingJoin,bootstrapUnavailable,bootstrapMismatch,timedOut,cancelled,failed
exposed_credentials=none
```

Routing and completion semantics:

```text
embeddedMatrixRTCAnswerBridgeEnabled=false
default_route_unchanged=true
server_delivered_flag=false
remote_configuration=false
release_environment_activation=false
presentationAccepted_or_alreadyPresented=fulfill_once
typed_failure_timeout_or_cancelled=fail_once
fulfill_on_tap_only=false
wait_for_remote_audio_before_fulfill=false
direct_livekit_fallback_after_bridge_start=false
```

Idempotency and lifecycle:

```text
in_flight_guard=bounded_per_callkit_uuid
duplicate_answer_does_not_present_twice=true
duplicate_answer_does_not_start_second_task=true
action_fulfilled_or_failed_once=true
guard_released_on=success,failure,timeout,cancellation,CallKit_end
observed_lifecycle_only=presented,joining,connected,remoteEnded,localEnded,failed,dismissed
connected_synthesized_from_callkit=false
```

Audio-only and privacy boundary:

```text
start_mode=audio
camera_requested=false
video_enabled=false
microphone_permission_requested_by_bridge=false
livekit_credentials_requested=false
direct_livekit_joined=false
APNs_sent=false
media_connected=false
pushkit_changed=false
```

Focused tests:

```text
default_feature_gate_keeps_current_answer_route=covered_by_unit_test
enabled_bridge_accepts_valid_verified_bootstrap=covered_by_unit_test
incoming_answer_selects_presentExisting=covered_by_unit_test
incoming_answer_never_selects_startNew=covered_by_unit_test
unsupported_incoming_join_fails_closed=covered_by_unit_test
no_active_matrixrtc_call_fails_closed=covered_by_unit_test
missing_authenticated_session_fails_closed=covered_by_unit_test
session_user_mismatch_fails_closed=covered_by_unit_test
session_device_mismatch_fails_closed=covered_by_unit_test
dm_ambiguity_fails_closed=covered_by_unit_test
missing_secure_bootstrap_fails_closed=covered_by_unit_test
bootstrap_uuid_mismatch_fails_closed=covered_by_unit_test
successful_presentation_fulfills_once=covered_by_unit_test
failure_fails_once=covered_by_unit_test
duplicate_answer_does_not_present_twice=covered_by_unit_test
timeout_fails_once_and_releases_guard=covered_by_unit_test
cancellation_releases_guard=covered_by_unit_test
no_direct_livekit_credentials_request=covered_by_unit_test
no_direct_livekit_join=covered_by_unit_test
camera_permission_never_requested=covered_by_unit_test
connected_lifecycle_not_synthesized_from_callkit=covered_by_unit_test
```

Validation:

```text
unit_tests_target_compile_passed=true
filtered_answer_bridge_tests_passed=true
stage2c_regression_tests_passed=true
```

Stage 2E entry conditions after Stage 2D:

```text
production_callkit_answer_path_found=true
secure_bootstrap_lookup_proven=true
typed_answer_bridge_created=true
answer_bridge_default_enabled=false
default_production_route_unchanged=true
incoming_selects_present_existing=true
incoming_never_selects_start_new=true
presentation_runs_on_main_actor=true
callkit_action_fulfilled_once=true
callkit_action_failed_once_on_error=true
duplicate_answer_idempotent=true
timeout_handled=true
cancellation_handled=true
direct_livekit_credentials_requested=false
direct_livekit_joined=false
camera_permission_requested=false
connected_synthesized_from_callkit=false
pushkit_changed=false
server_accessed=false
APNs_sent=false
media_connected=false
unit_tests_target_compile_passed=true
filtered_answer_bridge_tests_passed=true
stage2c_regression_tests_passed=true
stage_2e_ready=true
```

## Stage 2E CallKit End and MatrixRTC termination synchronization

Stage 2E added a typed, disabled-by-default End bridge using the existing `embeddedMatrixRTCAnswerBridgeEnabled=false` gate. The default answer and End production routes remain unchanged while the gate is disabled.

Actual production End and termination path:

| Hop | Symbol | File | production_reachable | upstream_or_salemx | current_side_effect |
| --- | --- | --- | --- | --- | --- |
| CallKit End entry | `ElementCallService.provider(_:perform: CXEndCallAction)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | mixed | Receives the OS End action and delegates to `handleEndCallAction(_:provider:)`. |
| Gate and UUID lookup | `ElementCallService.handleEndCallAction(_:provider:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | salemx | Uses `embeddedMatrixRTCAnswerBridgeEnabled`; disabled path calls the legacy End handler, enabled path resolves the exact incoming or ongoing `CallID` by CallKit UUID. |
| Legacy End route | `ElementCallService.handleLegacyEndCallAction(_:provider:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | mixed | Preserves current behavior: ongoing calls emit `.requestCallTermination(roomID:)`, incoming calls reject/decline, local state is cleared, and the action is fulfilled. |
| Verified bootstrap lookup | `SalemXIncomingCallBootstrapResolving.verifiedBootstrap(for:)` | `ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift` | true only when the gate is enabled | salemx | Reuses the already-claimed `VerifiedIncomingCallBootstrap`; raw PushKit payload fields are not trusted or re-claimed. |
| Typed End bridge | `SalemXEmbeddedCallEndBridge.end(callID:bootstrap:source:)` | `ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift` | true only when the gate is enabled | salemx | Checks CallKit UUID, authenticated user, local device and active MatrixRTC evidence before termination. |
| Embedded termination API | `EmbeddedElementCallTerminating.terminateEmbeddedElementCall(roomID:)` | `ElementX/Sources/Services/ElementCall/ElementCallServiceProtocol.swift` | true only when the gate is enabled | upstream | Abstracts the embedded Element Call termination route without exposing LiveKit, Matrix tokens, PushKit payloads or widget URLs. |
| Production terminator | `ElementCallService.terminateEmbeddedElementCall(roomID:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true only when the gate is enabled | mixed | Delegates to `requestCallTermination(roomID:)` and maps accepted termination back to the typed bridge result. |
| Service termination | `ElementCallService.requestCallTermination(roomID:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | upstream | Duplicate-guards by room, applies local hangup session state, suppresses incoming fallback and emits `.endCall(roomID:)`. |
| Call screen local hangup | `CallScreenViewModel.process(viewAction: .endCall)` and `requestLocalCallTermination(sendHangupMessage:)` | `ElementX/Sources/Screens/CallScreen/CallScreenViewModel.swift` | true | upstream | User hangup sends widget termination when requested; service-driven `.endCall` dismisses through the existing coordinator path without manual Matrix hangup construction. |
| Widget hangup source | `ElementCallWidgetDriver.handleMessageIfNeeded(_:)` | `ElementX/Sources/Services/ElementCall/ElementCallWidgetDriver.swift` | true | upstream | Embedded widget `.hangup` or `.close` messages become upstream call-ended actions. |
| Remote timeline observation | `ElementCallService.observeOngoingCallTimeline(roomProxy:ongoingCallID:)` and `latestRemoteTerminationEvent(in:roomID:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | mixed | Existing Matrix timeline termination evidence ends the ongoing call. |
| Remote room-info observation | `ElementCallService.observeOngoingCallRoomInfo(roomProxy:ongoingCallID:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | mixed | Existing MatrixRTC room-info disappearance or no foreign participants ends the ongoing call. |
| Embedded terminal handling | `ElementCallService.handleEmbeddedMatrixRTCTerminalEventIfNeeded(_:source:deduplicationID:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true only when the gate is enabled | salemx | Reports CallKit ended once, drains in-flight End actions, cancels/supersedes answer actions, emits `.endCall(roomID:)` and clears bootstrap state once. |
| CallKit ended report | `ElementCallService.reportEmbeddedMatrixRTCCallEnded(callID:reason:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true only when the gate is enabled | salemx | Deduplicates native `reportCall(with:endedAt:reason:)` per CallKit UUID. |
| Local teardown | `ElementCallService.tearDownCallSession(sendEndCallAction:)` and `clearIncomingCallState(cancelEmbeddedAnswer:)` | `ElementX/Sources/Services/ElementCall/ElementCallService.swift` | true | mixed | Clears local CallKit/session references and releases embedded answer guards without creating Matrix events. |
| Legacy direct hangup | `DirectCallEngine.hangupActiveCall(callID:)` | `ElementX/Sources/Services/Calls/DirectCallEngine.swift` | true for legacy direct calls; false for Stage 2E embedded route | salemx | Legacy direct path emits a direct-call hangup signal and disconnects media; the embedded bridge does not invoke it. |
| Legacy Matrix signal sender | `DirectCallSignalTransport.send(_:)` | `ElementX/Sources/Services/Calls/DirectCallSignalTransport.swift` | true for legacy direct calls; false for Stage 2E embedded route | salemx | Serializes legacy direct-call Matrix content through `sendDirectCallSignal`; the embedded bridge does not construct `m.call.hangup` or custom hangup content. |

Synthetic and diagnostic End paths excluded from Stage 2E routing:

| Symbol | File | production_reachable | Reason |
| --- | --- | --- | --- |
| `NativeIncomingSyntheticCallKitUIProofAdapter.provider(_:perform: CXEndCallAction)` | `ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift` | false | Synthetic CallKit proof helper; not wired into the production bridge. |
| Physical-device diagnostics helpers | `ElementX/Sources/Services/Calls/SyntheticCallKitProof/` | false | DEBUG/proof utilities; not used for Stage 2E production routing. |

Typed End bridge contract:

```text
protocol=SalemXEmbeddedCallEndBridging
input=callID:UUID,bootstrap:VerifiedIncomingCallBootstrap,source:SalemXEmbeddedCallEndSource
sources=callKitLocalEnd,embeddedLocalEnd,embeddedRemoteEnd,presentationFailure,answerTimeout,systemReset
bootstrap_source=already_claimed_and_validated_metadata_only
required_consistency=callkit_uuid,room_id,authenticated_user,authenticated_device,active_matrixrtc_call
typed_results=terminationAccepted,alreadyTerminated,noVerifiedBootstrap,bootstrapMismatch,noAuthenticatedSession,sessionIdentityMismatch,sessionDeviceMismatch,dmRoomUnavailable,noActiveMatrixRTCCall,terminationUnsupported,timedOut,cancelled,failed
exposed_credentials=none
```

CallKit action completion and reason mapping:

```text
terminationAccepted_or_alreadyTerminated=fulfill_once
typed_failure_timeout_or_cancelled=fail_once
wait_for_remote_audio_teardown=false
remoteEnded=remoteEnded
localEnded=unspecified_due_to_CallKit_API_mapping
failedBeforeConnection=failed
unansweredOrTimeout=unanswered
systemReset=unspecified
internal_errors_exposed_to_CallKit=false
```

Race and cleanup policy:

```text
in_flight_guard=bounded_per_callkit_uuid
local_end_while_answer_in_flight=answer_failed_once_and_end_processed
remote_end_before_answer_presentation=answer_superseded_and_callkit_ended_reported_once
local_remote_race=first_terminal_path_wins_late_completion_ignored
duplicate_CXEndCallAction=termination_invoked_once_actions_completed_once
duplicate_upstream_terminal_event=callkit_ended_reported_once
provider_reset=answer_and_end_guards_released_bootstrap_removed_once
timeout_followed_by_late_completion=late_completion_ignored_safely
bootstrap_cleanup_idempotent=true
```

Audio, privacy and malformed hangup boundaries:

```text
embeddedMatrixRTCAnswerBridgeEnabled=false
legacy_answer_route_unchanged=true
legacy_end_route_unchanged=true
automatic_fallback_to_direct_livekit=false
manual_matrix_hangup_sent=false
legacy_hangup_sender_invoked=false
direct_livekit_credentials_requested=false
direct_livekit_joined=false
camera_permission_requested=false
microphone_permission_requested_by_end_bridge=false
video_enabled=false
media_connection_started=false
pushkit_changed=false
server_accessed=false
APNs_sent=false
```

Focused tests:

```text
default_disabled_local_end_stays_on_legacy_path=covered_by_unit_test
enabled_local_end_invokes_upstream_termination=covered_by_unit_test
local_end_never_invokes_direct_livekit_credentials_or_join=covered_by_absence_of_bridge_dependency_and_unit_test
local_end_never_manually_sends_matrix_hangup=covered_by_absence_of_legacy_signal_dependency_and_unit_test
successful_termination_fulfills_once=covered_by_unit_test
termination_failure_fails_once=covered_by_unit_test
duplicate_end_invokes_termination_once=covered_by_unit_test
remote_end_reports_callkit_ended_once=covered_by_unit_test
duplicate_remote_terminal_event_ignored=covered_by_unit_test
local_remote_race_completes_once=covered_by_unit_test
end_during_answer_supersedes_answer_safely=covered_by_unit_test
answer_timeout_followed_by_end_idempotent=covered_by_unit_test
provider_reset_releases_guards=covered_by_unit_test
bootstrap_uuid_mismatch_fails_closed=covered_by_unit_test
missing_bootstrap_fails_closed=covered_by_unit_test
no_active_matrixrtc_call_fails_closed=covered_by_unit_test
late_upstream_completion_ignored=covered_by_unit_test
bootstrap_cleared_once=covered_by_unit_test
connected_event_not_synthesized=covered_by_unit_test
camera_and_microphone_permissions_not_requested=covered_by_unit_test
stage2d_answer_bridge_regression=covered_by_unit_test
stage2c_handoff_regression=covered_by_unit_test
```

Validation:

```text
unit_tests_target_compile_passed=true
filtered_end_bridge_tests_passed=true
stage2d_regression_tests_passed=true
stage2c_regression_tests_passed=true
focused_xcode_tests=48_passed
```

Stage 2F entry conditions after Stage 2E:

```text
production_callkit_end_path_found=true
typed_end_bridge_created=true
upstream_termination_api_proven=true
upstream_terminal_event_source_proven=true
answer_bridge_default_enabled=false
default_answer_route_unchanged=true
default_end_route_unchanged=true
incoming_never_selects_start_new=true
local_end_invokes_upstream_termination=true
manual_matrix_hangup_sent=false
legacy_direct_livekit_hangup_invoked=false
remote_end_reports_callkit_once=true
duplicate_end_idempotent=true
local_remote_race_safe=true
provider_reset_safe=true
bootstrap_cleanup_idempotent=true
callkit_action_completed_once=true
camera_permission_requested=false
microphone_permission_requested=false
pushkit_changed=false
server_accessed=false
APNs_sent=false
media_connected=false
unit_tests_target_compile_passed=true
filtered_end_bridge_tests_passed=true
stage2d_regression_tests_passed=true
stage2c_regression_tests_passed=true
stage_2f_ready=true
```

## Stage 2F-SIM-R2D Foreground-Only Simulator Signaling Readiness

Stage 2F-SIM is still not passed. The accepted R2D state only adds the server/client contract needed for a later rerun of the simulator sender to physical iPhone receiver signaling proof without APNs.

The failed initial Stage 2F-SIM execution proved the simulator sender could reach the real authenticated foreground-signaling route, but it also proved that the production foreground invite endpoint invoked sandbox APNs after foreground stream delivery. The helper stopped on that APNs guard before the full CallKit Answer, two-participant MatrixRTC, remote-end and cleanup proof was completed. This failure is recorded as a production route contract gap, not as a failure of Stage 2C, Stage 2D or Stage 2E.

R2 adds a DEBUG-only sender adaptation in `SalemXMatrixRTCHandoff.swift`: the Stage 2F-SIM sender request includes `delivery_mode=foreground_only`. The normal release/default sender behavior remains unchanged and omits the new field, preserving the server default `foreground_and_apns` behavior for existing clients.

The DEBUG sender accepts a foreground invite response only when the current request reports:

```text
delivery_mode=foreground_only
foreground_delivery_succeeded=true
apns_requested=false
apns_provider_invoked=false
apns_provider_accepted=false
APNs_sent=false
delivery_attempt_id_present=true
```

The proof is scoped to the response `delivery_attempt_id`, so aggregate or historical APNs markers are no longer accepted. Missing attempt IDs, mismatched attempt IDs, APNs requested, APNs provider invocation and APNs sent all fail the DEBUG helper guard. No invite is repeated automatically.

The receiver bridge behavior from Stage 2D and Stage 2E remains unchanged:

```text
embeddedMatrixRTCAnswerBridgeEnabled=false_by_default
receiver_debug_override_required=true
incoming_answer_selects_presentExisting=true
incoming_answer_selects_startNew=false
manual_matrix_hangup_sent=false
direct_livekit_credentials_requested=false
direct_livekit_joined=false
camera_permission_requested=false
video_track_published=false
```

Focused iOS validation for R2:

```text
ios_focused_tests=62_passed
debug_stage2f_sender_uses_foreground_only=true
release_default_sender_behavior_unchanged=true
helper_rejects_missing_delivery_attempt_id=true
helper_rejects_mismatched_delivery_attempt_id=true
helper_rejects_apns_requested=true
helper_rejects_provider_invoked=true
helper_rejects_apns_sent=true
stage2e_regression_passed=true
stage2d_regression_passed=true
stage2c_regression_passed=true
```

R2D cleanup evidence before documentation and commit:

```text
sender_call_ui_active=false
receiver_device_connected=true
receiver_device_unlocked=true
livekit_established_socket_count=0
call_service_established_socket_count=0
stale_matrixrtc_membership_detected=false
```

The physical receiver UI could not be screen-captured through `devicectl` without an invasive workflow, and unprivileged LiveKit admin room listing was unavailable without reading secrets. The cleanup classification therefore uses the strongest available non-mutating evidence and does not delete rooms, participants or Matrix state.

R2D keeps the acceptance boundary closed:

```text
authenticated_invite_sent_during_r2=false
APNs_sent_during_r2=false
stage_2f_simulator_signaling_passed=false
physical_two_way_audio_proven=false
physical_stage_2f_still_required=true
stage_2g_ready=false
```
