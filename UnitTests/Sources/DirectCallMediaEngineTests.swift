//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
@testable import LiveKit
import Testing

@MainActor
final class DirectCallMediaEngineTests {
    private let callID = "call-a"
    private let roomID = "!room:example.com"
    private let peerUserID = "@alice:example.com"

    @Test
    func connectFailsClosedBeforeE2EEReadyAndDoesNotRequestToken() async {
        let tokenProvider = MediaTokenProviderSpy()
        let engine = makeEngine(tokenProvider: tokenProvider)
        let session = makeSession(encryptionState: .pending)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))

        #expect(result == .failure(.e2eeNotReady))
        #expect(tokenProvider.requestedSessions.isEmpty)
        #expect(engine.mediaStatePublisher.value.canPublishMicrophone == false)
        #expect(engine.mediaStatePublisher.value.canPlayRemoteAudio == false)
    }

    @Test
    func connectRequestsTokenOnlyAfterE2EEReady() async {
        let tokenProvider = MediaTokenProviderSpy()
        let routeController = AudioRouteControllerSpy()
        let engine = makeEngine(tokenProvider: tokenProvider, audioRouteController: routeController)
        let session = makeSession(encryptionState: .ready)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))

        #expect(tokenProvider.requestedSessions == [session])
        #expect(routeController.configuredDefaultRoutes == [callID])
        guard case .success(let state) = result else {
            Issue.record("Expected encrypted audio connect to succeed in the NoOp media engine.")
            return
        }
        #expect(state.phase == .activeAudio)
        #expect(state.canPublishMicrophone == true)
        #expect(state.canPlayRemoteAudio == true)
        #expect(state.isMicrophoneEnabled == false)
    }

    @Test
    func microphoneCannotBeEnabledBeforeEncryptedAudioIsActive() async {
        let tokenProvider = MediaTokenProviderSpy()
        let engine = makeEngine(tokenProvider: tokenProvider)
        let session = makeSession(encryptionState: .ready)

        _ = await engine.prepareAudioSession(for: session)
        let blockedResult = await engine.setMicrophoneEnabled(true, callID: callID)
        #expect(blockedResult == .failure(.e2eeNotReady))

        _ = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))
        let enabledResult = await engine.setMicrophoneEnabled(true, callID: callID)

        guard case .success(let state) = enabledResult else {
            Issue.record("Expected microphone enable to be allowed after E2EE-ready audio connect.")
            return
        }
        #expect(state.isMicrophoneEnabled == true)
    }

    @Test
    func videoSessionIsRejectedInAudioPhaseBeforeTokenRequest() async {
        let tokenProvider = MediaTokenProviderSpy()
        let engine = makeEngine(tokenProvider: tokenProvider)
        let session = makeSession(intent: .video, encryptionState: .ready)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))

        #expect(result == .failure(.unsupportedIntent))
        #expect(tokenProvider.requestedSessions.isEmpty)
        #expect(engine.mediaStatePublisher.value.canPublishMicrophone == false)
    }

    @Test
    func cleanupDisconnectsAndClearsPerCallKeyIdempotently() async {
        let routeController = AudioRouteControllerSpy()
        let encryptionService = MediaEncryptionServiceSpy()
        let engine = makeEngine(audioRouteController: routeController, encryptionService: encryptionService)
        let session = makeSession(encryptionState: .ready)

        _ = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))
        await engine.cleanup(callID: callID)
        await engine.cleanup(callID: callID)

        #expect(routeController.deactivateAudioSessionCount == 1)
        #expect(encryptionService.clearedCallIDs == [callID])
        #expect(engine.mediaStatePublisher.value == .idle)
    }

    @Test
    func liveKitSkeletonFailsClosedWithoutPublishingMedia() async {
        let engine = LiveKitDirectCallMediaEngine()
        let session = makeSession(encryptionState: .ready)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))

        #expect(result == .failure(.e2eeContextUnavailable))
        #expect(engine.mediaStatePublisher.value.canPublishMicrophone == false)
        #expect(engine.mediaStatePublisher.value.canPlayRemoteAudio == false)
    }

    @Test
    func liveKitClientCanBeInitializedAndFailsClosedWithoutE2EEBoundary() async {
        let client = LiveKitDirectCallClient()

        let result = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: MediaE2EEContextSpy())

        guard case .failure(.e2eeContextUnavailable) = result else {
            Issue.record("Expected SDK-backed client to fail closed without SDK E2EE context.")
            return
        }
        await client.cleanup()
    }

    @Test
    func liveKitClientFailsClosedIfE2EEContextCannotBuildSDKOptions() async {
        var roomFactoryCallCount = 0
        let client = LiveKitDirectCallClient { connectOptions, roomOptions in
            roomFactoryCallCount += 1
            return Room(connectOptions: connectOptions, roomOptions: roomOptions)
        }
        let context = LiveKitMediaE2EEContextSpy(result: .failure(.e2eeContextUnavailable))

        let result = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: context)

        guard case .failure(.e2eeContextUnavailable) = result else {
            Issue.record("Expected SDK E2EE option preparation failure.")
            return
        }
        #expect(context.makeRoomOptionsCount == 1)
        #expect(roomFactoryCallCount == 0)
    }

    @Test
    func liveKitClientConnectsWithE2EEConfiguredRoomAndSafeConnectOptions() async {
        var createdConnectOptions: ConnectOptions?
        var createdRoomOptions: RoomOptions?
        var connectedRoomOptions: RoomOptions?
        var connectedConnectOptions: ConnectOptions?
        var connectCallCount = 0
        let client = LiveKitDirectCallClient { connectOptions, roomOptions in
            createdConnectOptions = connectOptions
            createdRoomOptions = roomOptions
            return Room(connectOptions: connectOptions, roomOptions: roomOptions)
        } roomConnector: { _, _, connectOptions, roomOptions in
            connectCallCount += 1
            connectedConnectOptions = connectOptions
            connectedRoomOptions = roomOptions
        }
        let context = LiveKitMediaE2EEContextSpy()

        let result = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: context)

        guard case .success = result else {
            Issue.record("Expected SDK client to connect after E2EE setup.")
            return
        }
        #expect(context.makeRoomOptionsCount == 1)
        #expect(connectCallCount == 1)
        #expect(createdConnectOptions?.autoSubscribe == false)
        #expect(createdConnectOptions?.enableMicrophone == false)
        #expect(connectedConnectOptions?.autoSubscribe == false)
        #expect(connectedConnectOptions?.enableMicrophone == false)
        #expect(createdRoomOptions?.encryptionOptions != nil)
        #expect(createdRoomOptions?.e2eeOptions == nil)
        #expect(connectedRoomOptions?.encryptionOptions != nil)
        await client.cleanup()
    }

    @Test
    func liveKitClientConnectFailureCleansPartialRoomAndContext() async {
        let context = LiveKitMediaE2EEContextSpy()
        var connectCallCount = 0
        let client = LiveKitDirectCallClient { connectOptions, roomOptions in
            Room(connectOptions: connectOptions, roomOptions: roomOptions)
        } roomConnector: { _, _, _, _ in
            connectCallCount += 1
            throw LiveKitClientTestError()
        }

        let result = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: context)

        guard case .failure(.mediaSetupUnavailable) = result else {
            Issue.record("Expected SDK connect failure to map to a safe media setup error.")
            return
        }
        #expect(connectCallCount == 1)
        #expect(context.cleanupCount == 1)

        let retryResult = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: context)
        guard case .failure(.mediaSetupUnavailable) = retryResult else {
            Issue.record("Expected retry to reach the connector after partial cleanup.")
            return
        }
        #expect(connectCallCount == 2)
        #expect(context.cleanupCount == 2)
    }

    @Test
    func liveKitClientCleanupReleasesPreparedE2EEContextIdempotently() async {
        let client = LiveKitDirectCallClient { connectOptions, roomOptions in
            Room(connectOptions: connectOptions, roomOptions: roomOptions)
        } roomConnector: { _, _, _, _ in }
        let context = LiveKitMediaE2EEContextSpy()

        _ = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: context)
        await client.cleanup()
        await client.cleanup()

        #expect(context.cleanupCount == 1)
    }

    @Test
    func liveKitClientCleanupIsIdempotentBeforeConnect() async {
        let client = LiveKitDirectCallClient()

        await client.cleanup()
        await client.cleanup()

        let result = await client.setMicrophoneEnabled(false)
        guard case .success = result else {
            Issue.record("Expected pre-connect microphone disable to be safe.")
            return
        }
    }

    @Test
    func liveKitClientDisconnectIsIdempotentBeforeConnect() async {
        let client = LiveKitDirectCallClient()

        await client.disconnect()
        await client.disconnect()

        let result = await client.setMicrophoneEnabled(false)
        guard case .success = result else {
            Issue.record("Expected pre-connect microphone disable to be safe.")
            return
        }
    }

    @Test
    func liveKitClientMicrophoneDisableBeforeConnectIsSafe() async {
        let client = LiveKitDirectCallClient()

        let result = await client.setMicrophoneEnabled(false)

        guard case .success = result else {
            Issue.record("Expected pre-connect microphone disable to be safe.")
            return
        }
    }

    @Test
    func liveKitClientMicrophoneEnableBeforeConnectFailsClosed() async {
        let client = LiveKitDirectCallClient()

        let result = await client.setMicrophoneEnabled(true)

        guard case .failure(.mediaSetupUnavailable) = result else {
            Issue.record("Expected pre-connect microphone enable to fail closed.")
            return
        }
    }

    @Test
    func liveKitClientRemoteAudioDisableBeforeConnectIsSafe() async {
        let client = LiveKitDirectCallClient()

        let result = await client.setRemoteAudioPlaybackEnabled(false)

        guard case .success = result else {
            Issue.record("Expected pre-connect remote audio disable to be safe.")
            return
        }
    }

    @Test
    func liveKitClientRemoteAudioEnableBeforeConnectFailsClosed() async {
        let client = LiveKitDirectCallClient()

        let result = await client.setRemoteAudioPlaybackEnabled(true)

        guard case .failure(.mediaSetupUnavailable) = result else {
            Issue.record("Expected pre-connect remote audio enable to fail closed.")
            return
        }
    }

    @Test
    func liveKitClientConnectDoesNotSubscribeRemoteAudio() async {
        var remoteAudioValues = [Bool]()
        let client = LiveKitDirectCallClient { connectOptions, roomOptions in
            Room(connectOptions: connectOptions, roomOptions: roomOptions)
        } roomConnector: { _, _, _, _ in
        } remoteAudioSubscriptionUpdater: { _, isEnabled in
            remoteAudioValues.append(isEnabled)
        }

        let result = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: LiveKitMediaE2EEContextSpy())

        guard case .success = result else {
            Issue.record("Expected SDK client connect seam to succeed.")
            return
        }
        #expect(remoteAudioValues.isEmpty)
        await client.cleanup()
    }

    @Test
    func liveKitClientRemoteAudioEnableFailureRollsBackSubscription() async {
        var remoteAudioValues = [Bool]()
        let client = LiveKitDirectCallClient { connectOptions, roomOptions in
            Room(connectOptions: connectOptions, roomOptions: roomOptions)
        } roomConnector: { _, _, _, _ in
        } remoteAudioSubscriptionUpdater: { _, isEnabled in
            remoteAudioValues.append(isEnabled)
            if isEnabled {
                throw DirectCallMediaError.mediaSetupUnavailable
            }
        }

        let connectResult = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: LiveKitMediaE2EEContextSpy())
        guard case .success = connectResult else {
            Issue.record("Expected SDK client connect seam to succeed.")
            return
        }

        let result = await client.setRemoteAudioPlaybackEnabled(true)

        guard case .failure(.mediaSetupUnavailable) = result else {
            Issue.record("Expected remote audio enable failure to fail closed.")
            return
        }
        #expect(remoteAudioValues == [true, false])
        await client.cleanup()
    }

    @Test
    func liveKitClientCleanupUnsubscribesRemoteAudioIdempotently() async {
        var remoteAudioValues = [Bool]()
        let client = LiveKitDirectCallClient { connectOptions, roomOptions in
            Room(connectOptions: connectOptions, roomOptions: roomOptions)
        } roomConnector: { _, _, _, _ in
        } remoteAudioSubscriptionUpdater: { _, isEnabled in
            remoteAudioValues.append(isEnabled)
        }

        let result = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: LiveKitMediaE2EEContextSpy())
        guard case .success = result else {
            Issue.record("Expected SDK client connect seam to succeed.")
            return
        }

        _ = await client.setRemoteAudioPlaybackEnabled(true)
        await client.cleanup()
        await client.cleanup()

        #expect(remoteAudioValues == [true, false])
    }

    @Test
    func liveKitClientDisconnectAndCleanupAreIdempotentAfterConnect() async {
        let context = LiveKitMediaE2EEContextSpy()
        let client = LiveKitDirectCallClient { connectOptions, roomOptions in
            Room(connectOptions: connectOptions, roomOptions: roomOptions)
        } roomConnector: { _, _, _, _ in }

        let result = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: context)
        guard case .success = result else {
            Issue.record("Expected SDK client connect seam to succeed.")
            return
        }

        await client.disconnect()
        await client.disconnect()
        await client.cleanup()
        await client.cleanup()

        #expect(context.cleanupCount == 1)
    }

    @Test
    func liveKitDoesNotRequestTokenOrConnectBeforeE2EEReady() async {
        let tokenProvider = MediaTokenProviderSpy()
        let e2eeContextProvider = MediaE2EEContextProviderSpy()
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(tokenProvider: tokenProvider,
                                       e2eeContextProvider: e2eeContextProvider,
                                       liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .pending)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))

        #expect(result == .failure(.e2eeNotReady))
        #expect(e2eeContextProvider.requestedSessions.isEmpty)
        #expect(tokenProvider.requestedSessions.isEmpty)
        #expect(liveKitClient.connectionInfos.isEmpty)
        #expect(engine.mediaStatePublisher.value.canPlayRemoteAudio == false)
    }

    @Test
    func liveKitDoesNotRequestTokenOrConnectOnKeyMismatch() async {
        let tokenProvider = MediaTokenProviderSpy()
        let e2eeContextProvider = MediaE2EEContextProviderSpy()
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(tokenProvider: tokenProvider,
                                       e2eeContextProvider: e2eeContextProvider,
                                       liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: "other-call", keyID: "key-a"))

        #expect(result == .failure(.keyMismatch))
        #expect(e2eeContextProvider.requestedSessions.isEmpty)
        #expect(tokenProvider.requestedSessions.isEmpty)
        #expect(liveKitClient.connectionInfos.isEmpty)
    }

    @Test
    func liveKitDoesNotRequestTokenOrConnectWhenE2EEContextProviderFails() async {
        let tokenProvider = MediaTokenProviderSpy()
        let e2eeContextProvider = MediaE2EEContextProviderSpy(result: .failure(.e2eeContextUnavailable))
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(tokenProvider: tokenProvider,
                                       e2eeContextProvider: e2eeContextProvider,
                                       liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))

        #expect(result == .failure(.e2eeContextUnavailable))
        #expect(e2eeContextProvider.requestedSessions == [session])
        #expect(e2eeContextProvider.requestedKeyHandles == [.init(callID: callID, keyID: "key-a")])
        #expect(tokenProvider.requestedSessions.isEmpty)
        #expect(liveKitClient.connectionInfos.isEmpty)
    }

    @Test
    func liveKitRequestsTokenAndConnectsOnlyAfterE2EEValidationPasses() async {
        let callOrderRecorder = CallOrderRecorder()
        let tokenProvider = MediaTokenProviderSpy()
        tokenProvider.callOrderRecorder = callOrderRecorder
        let e2eeContextProvider = MediaE2EEContextProviderSpy()
        e2eeContextProvider.callOrderRecorder = callOrderRecorder
        let liveKitClient = LiveKitClientSpy()
        liveKitClient.callOrderRecorder = callOrderRecorder
        let routeController = AudioRouteControllerSpy()
        let engine = makeLiveKitEngine(tokenProvider: tokenProvider,
                                       audioRouteController: routeController,
                                       e2eeContextProvider: e2eeContextProvider,
                                       liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))

        #expect(e2eeContextProvider.requestedSessions == [session])
        #expect(e2eeContextProvider.requestedKeyHandles == [.init(callID: callID, keyID: "key-a")])
        #expect(tokenProvider.requestedSessions == [session])
        #expect(routeController.configuredDefaultRoutes == [callID])
        #expect(liveKitClient.connectionInfos.map(\.roomName) == ["direct-call"])
        #expect(liveKitClient.e2eeContextCount == 1)
        #expect(callOrderRecorder.events == ["e2eeContext", "token", "clientConnect"])
        guard case .success(let state) = result else {
            Issue.record("Expected fake LiveKit audio connect to succeed after E2EE validation.")
            return
        }
        #expect(state.phase == .activeAudio)
        #expect(state.canPublishMicrophone == true)
        #expect(state.canPlayRemoteAudio == true)
        #expect(state.isMicrophoneEnabled == false)
    }

    @Test
    func liveKitMicrophoneEnableIsBlockedBeforeEncryptedAudioIsActive() async {
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        _ = await engine.prepareAudioSession(for: session)
        let result = await engine.setMicrophoneEnabled(true, callID: callID)

        #expect(result == .failure(.e2eeNotReady))
        #expect(liveKitClient.microphoneValues.isEmpty)
    }

    @Test
    func liveKitMicrophoneEnableCallsClientOnlyAfterEncryptedAudioIsActive() async {
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        _ = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))
        let result = await engine.setMicrophoneEnabled(true, callID: callID)

        guard case .success(let state) = result else {
            Issue.record("Expected microphone enable to succeed after fake LiveKit connect.")
            return
        }
        #expect(state.isMicrophoneEnabled == true)
        #expect(liveKitClient.microphoneValues == [true])
    }

    @Test
    func liveKitRemoteAudioEnableIsBlockedBeforeEncryptedAudioIsActive() async {
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        _ = await engine.prepareAudioSession(for: session)
        let result = await engine.setRemoteAudioPlaybackEnabled(true, callID: callID)

        #expect(result == .failure(.e2eeNotReady))
        #expect(liveKitClient.remoteAudioPlaybackValues.isEmpty)
    }

    @Test
    func liveKitRemoteAudioEnableCallsClientOnlyAfterEncryptedAudioIsActive() async {
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        _ = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))
        let result = await engine.setRemoteAudioPlaybackEnabled(true, callID: callID)

        guard case .success(let state) = result else {
            Issue.record("Expected remote audio enable to succeed after fake LiveKit connect.")
            return
        }
        #expect(state.canPlayRemoteAudio == true)
        #expect(liveKitClient.remoteAudioPlaybackValues == [true])
        #expect(liveKitClient.microphoneValues.isEmpty)
    }

    @Test
    func liveKitRemoteAudioDisableIsSafeBeforeConnect() async {
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(liveKitClient: liveKitClient)

        let result = await engine.setRemoteAudioPlaybackEnabled(false, callID: callID)

        guard case .success(let state) = result else {
            Issue.record("Expected remote audio disable to be safe before connect.")
            return
        }
        #expect(state == .idle)
        #expect(liveKitClient.remoteAudioPlaybackValues == [false])
        #expect(liveKitClient.microphoneValues.isEmpty)
    }

    @Test
    func liveKitRejectsVideoBeforeTokenRequest() async {
        let tokenProvider = MediaTokenProviderSpy()
        let e2eeContextProvider = MediaE2EEContextProviderSpy()
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(tokenProvider: tokenProvider,
                                       e2eeContextProvider: e2eeContextProvider,
                                       liveKitClient: liveKitClient)
        let session = makeSession(intent: .video, encryptionState: .ready)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))

        #expect(result == .failure(.unsupportedIntent))
        #expect(e2eeContextProvider.requestedSessions.isEmpty)
        #expect(tokenProvider.requestedSessions.isEmpty)
        #expect(liveKitClient.connectionInfos.isEmpty)
    }

    @Test
    func liveKitConnectFailureMapsToSafeMediaError() async {
        let liveKitClient = LiveKitClientSpy(connectResult: .failure(.mediaSetupUnavailable))
        let engine = makeLiveKitEngine(liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))

        #expect(result == .failure(.mediaSetupUnavailable))
        #expect(liveKitClient.connectionInfos.count == 1)
        #expect(liveKitClient.remoteAudioPlaybackValues.isEmpty)
        #expect(engine.mediaStatePublisher.value.canPublishMicrophone == false)
        #expect(engine.mediaStatePublisher.value.canPlayRemoteAudio == false)
    }

    @Test
    func liveKitCleanupDisablesRemoteAudioPlayback() async {
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        _ = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))
        _ = await engine.setRemoteAudioPlaybackEnabled(true, callID: callID)
        await engine.cleanup(callID: callID)
        await engine.cleanup(callID: callID)

        #expect(liveKitClient.remoteAudioPlaybackValues == [true, false])
        #expect(liveKitClient.microphoneValues == [false])
        #expect(engine.mediaStatePublisher.value == .idle)
    }

    @Test
    func liveKitDisconnectAndCleanupAreIdempotent() async {
        let routeController = AudioRouteControllerSpy()
        let encryptionService = MediaEncryptionServiceSpy()
        let e2eeContext = MediaE2EEContextSpy()
        let e2eeContextProvider = MediaE2EEContextProviderSpy(result: .success(e2eeContext))
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(audioRouteController: routeController,
                                       encryptionService: encryptionService,
                                       e2eeContextProvider: e2eeContextProvider,
                                       liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)

        _ = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))
        await engine.cleanup(callID: callID)
        await engine.cleanup(callID: callID)

        #expect(liveKitClient.microphoneValues == [false])
        #expect(liveKitClient.disconnectCount == 1)
        #expect(liveKitClient.cleanupCount == 1)
        #expect(routeController.deactivateAudioSessionCount == 1)
        #expect(encryptionService.clearedCallIDs == [callID])
        #expect(e2eeContextProvider.clearedCallIDs == [callID])
        #expect(e2eeContext.cleanupCount == 1)
        #expect(engine.mediaStatePublisher.value == .idle)
    }

    @Test
    func directCallMediaConnectionInfoDoesNotCarryRawKeyMaterial() {
        let labels = Mirror(reflecting: makeConnectionInfo()).children.compactMap(\.label)

        #expect(labels == ["serverURL", "roomName", "token"])
        #expect(labels.contains("key") == false)
        #expect(labels.contains("rawKey") == false)
    }

    @Test
    func liveKitRoomConnectIntegrationHarnessSkipsByDefault() {
        let environment = DirectCallLiveKitIntegrationEnvironment(environment: [:])

        #expect(environment == nil)
    }

    @Test
    func liveKitRoomConnectIntegrationHarnessRejectsProductionLikeURL() {
        func singleEndpointEnvironment(url: String) -> DirectCallLiveKitIntegrationEnvironment? {
            DirectCallLiveKitIntegrationEnvironment(environment: [
                "SALEMX_DIRECTCALL_LIVEKIT_INTEGRATION": "1",
                "SALEMX_DIRECTCALL_LIVEKIT_URL": url,
                "SALEMX_DIRECTCALL_LIVEKIT_TOKEN": "test-token",
                "SALEMX_DIRECTCALL_LIVEKIT_ROOM": "test-room",
                "SALEMX_DIRECTCALL_LIVEKIT_IDENTITY": "test-primary",
                "SALEMX_DIRECTCALL_LIVEKIT_E2EE_TEST_KEY": "test-key"
            ])
        }

        func twoEndpointEnvironment(url: String) -> DirectCallLiveKitTwoEndpointIntegrationEnvironment? {
            DirectCallLiveKitTwoEndpointIntegrationEnvironment(environment: [
                "SALEMX_DIRECTCALL_LIVEKIT_TWO_ENDPOINT_INTEGRATION": "1",
                "SALEMX_DIRECTCALL_LIVEKIT_URL": url,
                "SALEMX_DIRECTCALL_LIVEKIT_TOKEN": "test-token",
                "SALEMX_DIRECTCALL_LIVEKIT_ROOM": "test-room",
                "SALEMX_DIRECTCALL_LIVEKIT_IDENTITY": "test-primary",
                "SALEMX_DIRECTCALL_LIVEKIT_PEER_TOKEN": "test-peer-token",
                "SALEMX_DIRECTCALL_LIVEKIT_PEER_IDENTITY": "test-peer",
                "SALEMX_DIRECTCALL_LIVEKIT_E2EE_TEST_KEY": "test-key"
            ])
        }

        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("matrix.mertis.kz") == true)
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("calls.customer01.kz") == true)
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("prod-livekit.example.com") == true)
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("127.0.0.1") == false)
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("localhost") == false)
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("::1") == false)
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("test-livekit.example.com") == false)
        #expect(URL(string: "ws://127.0.0.1:7880").flatMap { DirectCallLiveKitIntegrationEnvironment.normalizedHost(from: $0) } == "127.0.0.1")
        #expect(URL(string: "ws://localhost:7880").flatMap { DirectCallLiveKitIntegrationEnvironment.normalizedHost(from: $0) } == "localhost")
        #expect(URL(string: "ws:/127.0.0.1:7880").flatMap { DirectCallLiveKitIntegrationEnvironment.normalizedHost(from: $0) } == "127.0.0.1")
        #expect(URL(string: "wss:/localhost:7880").flatMap { DirectCallLiveKitIntegrationEnvironment.normalizedHost(from: $0) } == "localhost")
        #expect(URL(string: "http:/127.0.0.1:7880").flatMap { DirectCallLiveKitIntegrationEnvironment.normalizedHost(from: $0) } == "127.0.0.1")
        #expect(URL(string: "https:/localhost:7880").flatMap { DirectCallLiveKitIntegrationEnvironment.normalizedHost(from: $0) } == "localhost")
        #expect(URL(string: "not-a-url").flatMap { DirectCallLiveKitIntegrationEnvironment.normalizedHost(from: $0) } == nil)
        #expect(singleEndpointEnvironment(url: "ws://127.0.0.1:7880")?.usesProductionLikeURL == false)
        #expect(twoEndpointEnvironment(url: "ws://127.0.0.1:7880")?.usesProductionLikeURL == false)
        #expect(singleEndpointEnvironment(url: "ws:/127.0.0.1:7880")?.usesProductionLikeURL == false)
        #expect(singleEndpointEnvironment(url: "ws:/127.0.0.1:7880")?.canonicalLiveKitURLString == "ws://127.0.0.1:7880")
        #expect(twoEndpointEnvironment(url: "ws:/127.0.0.1:7880")?.usesProductionLikeURL == false)
        #expect(twoEndpointEnvironment(url: "ws:/127.0.0.1:7880")?.canonicalLiveKitURLString == "ws://127.0.0.1:7880")
        #expect(singleEndpointEnvironment(url: "wss://matrix.mertis.kz")?.usesProductionLikeURL == true)
        #expect(twoEndpointEnvironment(url: "wss://calls.customer01.kz")?.usesProductionLikeURL == true)
        #expect(twoEndpointEnvironment(url: "wss://prod-livekit.example.com")?.usesProductionLikeURL == true)
        #expect(twoEndpointEnvironment(url: "ws:/matrix.mertis.kz:7880")?.usesProductionLikeURL == true)
        #expect(twoEndpointEnvironment(url: "ws:/matrix.mertis.kz:7880")?.canonicalLiveKitURLString == nil)
    }

    @Test
    func liveKitTwoEndpointRemoteAudioIntegrationHarnessSkipsByDefault() {
        let environment = DirectCallLiveKitTwoEndpointIntegrationEnvironment(environment: [:])

        #expect(environment == nil)
    }

    @Test
    func liveKitTwoEndpointEnvironmentUsesProvidedDictionary() throws {
        let environment = try #require(DirectCallLiveKitTwoEndpointIntegrationEnvironment(environment: [
            "SALEMX_DIRECTCALL_LIVEKIT_TWO_ENDPOINT_INTEGRATION": "1",
            "SALEMX_DIRECTCALL_LIVEKIT_URL": "ws:/127.0.0.1:7880",
            "SALEMX_DIRECTCALL_LIVEKIT_TOKEN": "custom-primary-token",
            "SALEMX_DIRECTCALL_LIVEKIT_ROOM": "custom-runtime-room",
            "SALEMX_DIRECTCALL_LIVEKIT_IDENTITY": "custom-primary",
            "SALEMX_DIRECTCALL_LIVEKIT_PEER_TOKEN": "custom-peer-token",
            "SALEMX_DIRECTCALL_LIVEKIT_PEER_IDENTITY": "custom-peer",
            "SALEMX_DIRECTCALL_LIVEKIT_E2EE_TEST_KEY": "custom-test-key"
        ]))

        #expect(environment.token == "custom-primary-token")
        #expect(environment.peerToken == "custom-peer-token")
        #expect(environment.roomName == "custom-runtime-room")
        #expect(environment.identity == "custom-primary")
        #expect(environment.peerIdentity == "custom-peer")
        #expect(environment.e2eeTestKey == "custom-test-key")
    }

    @Test(.enabled(if: DirectCallLiveKitIntegrationEnvironment.isRunnableInCurrentProcess))
    func liveKitRoomConnectIntegrationCompletesWhenExplicitlyEnabled() async {
        guard let environment = DirectCallLiveKitIntegrationEnvironment.current else {
            Issue.record("Integration environment is not enabled.")
            return
        }

        guard environment.usesProductionLikeURL == false else {
            Issue.record("Integration environment uses a production-like LiveKit URL. \(environment.urlGuardDiagnostic)")
            return
        }

        guard let serverURL = environment.canonicalLiveKitURL else {
            Issue.record("Integration environment URL cannot be canonicalized safely. \(environment.urlGuardDiagnostic)")
            return
        }

        let client = LiveKitDirectCallClient()
        let context = DirectCallLiveKitIntegrationE2EEContext(testKey: environment.e2eeTestKey)
        let connectionInfo = DirectCallMediaConnectionInfo(serverURL: serverURL,
                                                           roomName: environment.roomName,
                                                           token: environment.token)

        let connectResult = await client.connect(connectionInfo: connectionInfo, e2eeContext: context)
        let disableMicResult = await client.setMicrophoneEnabled(false)
        await client.cleanup()

        guard case .success = connectResult else {
            Issue.record("Expected LiveKit Room.connect integration to succeed.")
            return
        }

        guard case .success = disableMicResult else {
            Issue.record("Expected microphone disable to remain safe after integration connect.")
            return
        }

        #expect(environment.identity.isEmpty == false)
        #expect(context.cleanupCount == 1)
    }

    @Test
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func liveKitTwoEndpointRemoteAudioGateIntegrationCompletesWhenExplicitlyEnabled() async {
        let runtimeEnvironment = ProcessInfo.processInfo.environment
        guard let environment = DirectCallLiveKitTwoEndpointIntegrationEnvironment(environment: runtimeEnvironment) else {
            return
        }

        guard environment.usesProductionLikeURL == false else {
            Issue.record("Two-endpoint integration environment uses a production-like LiveKit URL. \(environment.urlGuardDiagnostic)")
            return
        }

        guard let serverURL = environment.canonicalLiveKitURL else {
            Issue.record("Two-endpoint integration environment URL cannot be canonicalized safely. \(environment.urlGuardDiagnostic)")
            return
        }

        guard let tokenDiagnostics = environment.liveKitTokenDiagnostics else {
            Issue.record("Two-endpoint integration environment contains undecodable LiveKit JWT payloads. \(environment.tokenGuardDiagnostic)")
            return
        }

        guard tokenDiagnostics.primaryRoomMatchesEnvironment,
              tokenDiagnostics.peerRoomMatchesEnvironment else {
            Issue.record("Two-endpoint integration token room does not match env room. \(tokenDiagnostics.description)")
            return
        }

        guard tokenDiagnostics.primaryTokenExpired == false,
              tokenDiagnostics.peerTokenExpired == false else {
            Issue.record("Two-endpoint integration token is expired before LiveKit connect. \(tokenDiagnostics.description)")
            return
        }
        logLiveKitIntegration("token diagnostics \(tokenDiagnostics.description)")

        guard let restoreManualRendering = enableLiveKitManualRenderingForIntegration() else { return }
        defer { restoreManualRendering() }

        let primaryClient = LiveKitDirectCallClient()
        let peerClient = LiveKitDirectCallClient()
        let primaryContext = DirectCallLiveKitIntegrationE2EEContext(testKey: environment.e2eeTestKey)
        let peerContext = DirectCallLiveKitIntegrationE2EEContext(testKey: environment.e2eeTestKey)
        let primaryConnectionInfo = DirectCallMediaConnectionInfo(serverURL: serverURL,
                                                                  roomName: environment.roomName,
                                                                  token: environment.token)
        let peerConnectionInfo = DirectCallMediaConnectionInfo(serverURL: serverURL,
                                                               roomName: environment.roomName,
                                                               token: environment.peerToken)

        var integrationStep = "primary connect start"
        let primaryConnectResult = await runLiveKitIntegrationMediaResultStep {
            await primaryClient.connect(connectionInfo: primaryConnectionInfo, e2eeContext: primaryContext)
        }
        guard let primaryConnectResult else {
            Issue.record("Primary LiveKit connect timed out during two-endpoint integration.")
            await cleanupIntegrationClientsWithTimeout(after: integrationStep,
                                                       primaryClient: primaryClient,
                                                       peerClient: peerClient)
            return
        }
        guard case .success = primaryConnectResult,
              let primaryRoom = liveKitRoom(from: primaryClient) else {
            Issue.record("Expected primary LiveKit connect to succeed before peer connect.")
            await cleanupIntegrationClientsWithTimeout(after: integrationStep,
                                                       primaryClient: primaryClient,
                                                       peerClient: peerClient)
            return
        }
        let primarySubscriptionEventWatcher = DirectCallLiveKitSubscriptionEventWatcher()
        primaryRoom.add(delegate: primarySubscriptionEventWatcher)
        integrationStep = "primary connect success"

        integrationStep = "peer connect start"
        let peerConnectResult = await runLiveKitIntegrationMediaResultStep {
            await peerClient.connect(connectionInfo: peerConnectionInfo, e2eeContext: peerContext)
        }
        guard let peerConnectResult else {
            Issue.record("Peer LiveKit connect timed out during two-endpoint integration.")
            await cleanupIntegrationClientsWithTimeout(after: integrationStep,
                                                       primaryClient: primaryClient,
                                                       peerClient: peerClient)
            return
        }
        guard case .success = peerConnectResult,
              let peerRoom = liveKitRoom(from: peerClient) else {
            Issue.record("Expected peer LiveKit connect to succeed after primary connect.")
            await cleanupIntegrationClientsWithTimeout(after: integrationStep,
                                                       primaryClient: primaryClient,
                                                       peerClient: peerClient)
            return
        }
        integrationStep = "peer connect success"

        var peerAudioPublication: LocalTrackPublication?
        func cleanupIntegrationClientsAfterCurrentStep() async {
            await cleanupIntegrationClientsWithTimeout(after: integrationStep,
                                                       primaryClient: primaryClient,
                                                       peerClient: peerClient,
                                                       primaryRoom: primaryRoom,
                                                       primarySubscriptionEventWatcher: primarySubscriptionEventWatcher,
                                                       peerRoom: peerRoom,
                                                       peerAudioPublication: peerAudioPublication)
        }

        integrationStep = "peer publish start"
        let peerAudioTrack = DirectCallLiveKitTestAudioTrack(name: "salemx-test-remote-audio")
        guard let publishedPeerAudio = await publishPeerTestAudioTrack(peerAudioTrack, in: peerRoom) else {
            Issue.record("Expected test-only peer audio publication to succeed before cleanup.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        peerAudioPublication = publishedPeerAudio
        integrationStep = "peer publish success"

        integrationStep = "wait primary remote audio publication start"
        let primarySawRemoteAudio = await waitForLiveKitIntegrationCondition {
            firstRemoteAudioPublication(in: primaryRoom) != nil
        }
        guard primarySawRemoteAudio,
              let primaryRemoteAudioPublication = firstRemoteAudioPublication(in: primaryRoom) else {
            integrationStep = "wait primary remote audio publication timeout"
            Issue.record("Expected primary endpoint to see peer audio publication before cleanup.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        integrationStep = "primary remote audio publication observed"

        #expect(primaryRemoteAudioPublication.isSubscribed == false)
        #expect(hasRemoteVideoPublications(in: primaryRoom) == false)
        #expect(peerRoom.localParticipant.localVideoTracks.isEmpty)
        logLiveKitIntegration("remote audio publications before enable \(remoteAudioPublicationDiagnostics(in: primaryRoom))")
        logLiveKitIntegration("subscription events before enable \(primarySubscriptionEventWatcher.diagnostic)")

        integrationStep = "remote audio enable start"
        logLiveKitIntegration("remote audio enable start")
        let remoteAudioEnableResult = await runLiveKitIntegrationMediaResultStep {
            await primaryClient.setRemoteAudioPlaybackEnabled(true)
        }
        guard let remoteAudioEnableResult else {
            logLiveKitIntegration("remote audio enable timed out \(remoteAudioPublicationDiagnostics(in: primaryRoom))")
            Issue.record("Remote audio enable timed out during two-endpoint integration.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        guard case .success = remoteAudioEnableResult else {
            integrationStep = "remote audio enable failure"
            logLiveKitIntegration("remote audio enable returned failure \(remoteAudioPublicationDiagnostics(in: primaryRoom))")
            Issue.record("Expected remote audio enable to succeed after publication is visible.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        integrationStep = "remote audio enable success"
        logLiveKitIntegration("remote audio enable returned success \(remoteAudioPublicationDiagnostics(in: primaryRoom))")
        logLiveKitIntegration("subscription events after enable \(primarySubscriptionEventWatcher.diagnostic)")

        let primarySubscribedRemoteAudio = await waitForLiveKitIntegrationConditionWithDiagnostics(label: "wait subscribed") {
            [
                remoteAudioPublicationDiagnostics(in: primaryRoom),
                "subscriptionEvents=\(primarySubscriptionEventWatcher.diagnostic)"
            ].joined(separator: " ")
        } condition: {
            primaryRemoteAudioPublication.isSubscribed
        }
        guard primarySubscribedRemoteAudio else {
            integrationStep = "subscribed observed timeout"
            logLiveKitIntegration("subscribed observed timeout final \(remoteAudioPublicationDiagnostics(in: primaryRoom))")
            logLiveKitIntegration("subscription events on subscribed timeout \(primarySubscriptionEventWatcher.diagnostic)")
            Issue.record("Expected primary endpoint to subscribe to remote audio after gate enable.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        integrationStep = "subscribed observed"

        integrationStep = "disable start"
        let remoteAudioDisableResult = await runLiveKitIntegrationMediaResultStep {
            await primaryClient.setRemoteAudioPlaybackEnabled(false)
        }
        guard let remoteAudioDisableResult else {
            Issue.record("Remote audio disable timed out during two-endpoint integration.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        guard case .success = remoteAudioDisableResult else {
            integrationStep = "disable failure"
            Issue.record("Expected remote audio disable to succeed after subscription.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        integrationStep = "disable success"

        let primaryUnsubscribedRemoteAudio = await waitForLiveKitIntegrationCondition {
            primaryRemoteAudioPublication.isSubscribed == false
        }
        guard primaryUnsubscribedRemoteAudio else {
            integrationStep = "unsubscribed observed timeout"
            Issue.record("Expected primary endpoint to unsubscribe from remote audio after gate disable.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        integrationStep = "unsubscribed observed"

        integrationStep = "remote audio reenable start"
        let remoteAudioReenableResult = await runLiveKitIntegrationMediaResultStep {
            await primaryClient.setRemoteAudioPlaybackEnabled(true)
        }
        guard let remoteAudioReenableResult else {
            Issue.record("Remote audio re-enable timed out before cleanup verification.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        guard case .success = remoteAudioReenableResult else {
            Issue.record("Expected remote audio re-enable to succeed before cleanup verification.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        integrationStep = "remote audio reenable success"

        let primaryResubscribedRemoteAudio = await waitForLiveKitIntegrationCondition {
            primaryRemoteAudioPublication.isSubscribed
        }
        guard primaryResubscribedRemoteAudio else {
            integrationStep = "resubscribed observed timeout"
            Issue.record("Expected primary endpoint to re-subscribe before cleanup verification.")
            await cleanupIntegrationClientsAfterCurrentStep()
            return
        }
        integrationStep = "resubscribed observed"

        integrationStep = "cleanup start"
        let cleanupFinished = await cleanupIntegrationClientsWithTimeout(after: integrationStep,
                                                                         primaryClient: primaryClient,
                                                                         peerClient: peerClient,
                                                                         primaryRoom: primaryRoom,
                                                                         primarySubscriptionEventWatcher: primarySubscriptionEventWatcher,
                                                                         peerRoom: peerRoom,
                                                                         peerAudioPublication: peerAudioPublication)
        guard cleanupFinished else {
            return
        }
        integrationStep = "cleanup done"

        let primaryCleanupUnsubscribedRemoteAudio = await waitForLiveKitIntegrationCondition {
            primaryRemoteAudioPublication.isSubscribed == false
        }
        guard primaryCleanupUnsubscribedRemoteAudio else {
            Issue.record("Expected cleanup to leave primary endpoint remote audio unsubscribed.")
            return
        }

        #expect(primarySubscribedRemoteAudio == true)
        #expect(primaryUnsubscribedRemoteAudio == true)
        #expect(primaryResubscribedRemoteAudio == true)
        #expect(primaryCleanupUnsubscribedRemoteAudio == true)

        #expect(environment.identity.isEmpty == false)
        #expect(environment.peerIdentity.isEmpty == false)
        #expect(environment.identity != environment.peerIdentity)
        #expect(peerAudioPublication != nil)
        #expect(primaryContext.cleanupCount == 1)
        #expect(peerContext.cleanupCount == 1)
    }

    private func waitForLiveKitIntegrationCondition(timeoutNanoseconds: UInt64 = 5_000_000_000,
                                                    pollNanoseconds: UInt64 = 100_000_000,
                                                    _ condition: () async -> Bool) async -> Bool {
        let maxAttempts = Int(timeoutNanoseconds / pollNanoseconds)
        for _ in 0..<maxAttempts {
            if await condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }

        return await condition()
    }

    private func runLiveKitIntegrationMediaResultStep(timeoutNanoseconds: UInt64 = 5_000_000_000,
                                                      _ operation: @escaping () async -> Result<Void, DirectCallMediaError>) async -> Result<Void, DirectCallMediaError>? {
        let stepState = LiveKitIntegrationMediaResultState()
        let stepTask = Task {
            let result = await operation()
            await stepState.finish(with: result)
        }

        let stepFinished = await waitForLiveKitIntegrationCondition(timeoutNanoseconds: timeoutNanoseconds) {
            await stepState.hasFinished
        }

        guard stepFinished else {
            stepTask.cancel()
            return nil
        }

        return await stepState.result
    }

    @discardableResult
    private func cleanupIntegrationClientsWithTimeout(after step: String,
                                                      primaryClient: LiveKitDirectCallClient,
                                                      peerClient: LiveKitDirectCallClient,
                                                      primaryRoom: Room? = nil,
                                                      primarySubscriptionEventWatcher: DirectCallLiveKitSubscriptionEventWatcher? = nil,
                                                      peerRoom: Room? = nil,
                                                      peerAudioPublication: LocalTrackPublication? = nil,
                                                      timeoutNanoseconds: UInt64 = 5_000_000_000) async -> Bool {
        let cleanupState = LiveKitIntegrationCompletionState()
        let cleanupTask = Task {
            await primaryClient.cleanup()
            if let primaryRoom, let primarySubscriptionEventWatcher {
                primaryRoom.remove(delegate: primarySubscriptionEventWatcher)
            }

            if let peerRoom, let peerAudioPublication {
                try? await peerRoom.localParticipant.unpublish(publication: peerAudioPublication)
            }

            await peerClient.cleanup()
            await cleanupState.finish()
        }

        let cleanupFinished = await waitForLiveKitIntegrationCondition(timeoutNanoseconds: timeoutNanoseconds) {
            await cleanupState.hasFinished
        }

        guard cleanupFinished else {
            cleanupTask.cancel()
            Issue.record("Integration cleanup timed out after \(step).")
            return false
        }

        return true
    }

    private func publishPeerTestAudioTrack(_ track: LocalAudioTrack, in room: Room) async -> LocalTrackPublication? {
        let publishState = LiveKitIntegrationPublishState()
        let publishTask = Task {
            do {
                let publication = try await room.localParticipant.publish(audioTrack: track)
                await publishState.succeed(with: publication)
            } catch {
                await publishState.fail()
            }
        }

        let publishFinished = await waitForLiveKitIntegrationCondition(timeoutNanoseconds: 5_000_000_000) {
            await publishState.hasFinished
        }

        guard publishFinished else {
            publishTask.cancel()
            return nil
        }

        return await publishState.publication
    }

    private func makeEngine(tokenProvider: DirectCallMediaTokenProviderProtocol? = nil,
                            audioRouteController: DirectCallAudioRouteControllerProtocol? = nil,
                            encryptionService: DirectCallEncryptionServiceProtocol? = nil) -> NoOpDirectCallMediaEngine {
        NoOpDirectCallMediaEngine(tokenProvider: tokenProvider,
                                  audioRouteController: audioRouteController,
                                  encryptionService: encryptionService)
    }

    private func makeLiveKitEngine(tokenProvider: DirectCallMediaTokenProviderProtocol? = nil,
                                   audioRouteController: DirectCallAudioRouteControllerProtocol? = nil,
                                   encryptionService: DirectCallEncryptionServiceProtocol? = nil,
                                   e2eeContextProvider: DirectCallMediaE2EEContextProviderProtocol? = nil,
                                   liveKitClient: DirectCallLiveKitClientProtocol? = nil) -> LiveKitDirectCallMediaEngine {
        LiveKitDirectCallMediaEngine(tokenProvider: tokenProvider ?? MediaTokenProviderSpy(),
                                     audioRouteController: audioRouteController,
                                     encryptionService: encryptionService,
                                     e2eeContextProvider: e2eeContextProvider ?? MediaE2EEContextProviderSpy(),
                                     liveKitClient: liveKitClient ?? LiveKitClientSpy())
    }

    private func makeSession(intent: DirectCallIntent = .audio,
                             encryptionState: DirectCallEncryptionState,
                             state: DirectCallState = .connecting) -> DirectCallSession {
        DirectCallSession(callID: callID,
                          roomID: roomID,
                          peerUserID: peerUserID,
                          direction: .outgoing,
                          intent: intent,
                          encryptionMode: .e2eeRequired,
                          startedAt: .now,
                          updatedAt: .now,
                          state: state,
                          encryptionState: encryptionState)
    }

    private func makeConnectionInfo() -> DirectCallMediaConnectionInfo {
        DirectCallMediaConnectionInfo(serverURL: URL(fileURLWithPath: "/tmp/livekit.example.com"),
                                      roomName: "direct-call",
                                      token: "test-token")
    }
}

@MainActor
private func liveKitRoom(from client: LiveKitDirectCallClient) -> Room? {
    guard let roomValue = Mirror(reflecting: client).children.first(where: { $0.label == "room" })?.value else {
        return nil
    }

    if let room = roomValue as? Room {
        return room
    }

    let optionalMirror = Mirror(reflecting: roomValue)
    guard optionalMirror.displayStyle == .optional else {
        return nil
    }

    return optionalMirror.children.first?.value as? Room
}

@MainActor
private func enableLiveKitManualRenderingForIntegration() -> (() -> Void)? {
    let manualRenderingWasEnabled = AudioManager.shared.isManualRenderingMode
    do {
        try AudioManager.shared.setManualRenderingMode(true)
        logLiveKitIntegration("manual rendering enabled wasEnabled=\(manualRenderingWasEnabled)")
    } catch {
        Issue.record("Expected LiveKit manual rendering mode to be available for simulator two-endpoint remote audio proof.")
        return nil
    }

    return {
        if manualRenderingWasEnabled == false {
            try? AudioManager.shared.setManualRenderingMode(false)
        }
    }
}

@MainActor
private func firstRemoteAudioPublication(in room: Room) -> RemoteTrackPublication? {
    room.remoteParticipants.values
        .flatMap(\.audioTracks)
        .compactMap { $0 as? RemoteTrackPublication }
        .first
}

@MainActor
private func hasRemoteVideoPublications(in room: Room) -> Bool {
    room.remoteParticipants.values.contains { participant in
        participant.videoTracks.isEmpty == false
    }
}

@MainActor
private func waitForLiveKitIntegrationConditionWithDiagnostics(label: String,
                                                               timeoutNanoseconds: UInt64 = 5_000_000_000,
                                                               pollNanoseconds: UInt64 = 100_000_000,
                                                               diagnostics: () async -> String,
                                                               condition: () async -> Bool) async -> Bool {
    let maxAttempts = Int(timeoutNanoseconds / pollNanoseconds)
    for attempt in 0..<maxAttempts {
        let isSatisfied = await condition()
        let diagnostic = await diagnostics()
        logLiveKitIntegration("\(label) attempt=\(attempt) satisfied=\(isSatisfied) \(diagnostic)")
        if isSatisfied {
            return true
        }

        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }

    let isSatisfied = await condition()
    let diagnostic = await diagnostics()
    logLiveKitIntegration("\(label) final satisfied=\(isSatisfied) \(diagnostic)")
    return isSatisfied
}

@MainActor
private func remoteAudioPublicationDiagnostics(in room: Room) -> String {
    let publications = room.remoteParticipants.values.flatMap { participant in
        participant.audioTracks.compactMap { publication -> String? in
            guard let remotePublication = publication as? RemoteTrackPublication else {
                return nil
            }

            return remoteAudioPublicationDiagnosticFields(participant: participant,
                                                          remotePublication: remotePublication)
                .joined(separator: ",")
        }
    }

    guard publications.isEmpty == false else {
        return "remoteAudioPublications=[]"
    }

    return "remoteAudioPublications=[\(publications.joined(separator: "; "))]"
}

private final class DirectCallLiveKitSubscriptionEventWatcher: NSObject, RoomDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var events = [String]()

    var diagnostic: String {
        lock.lock()
        defer { lock.unlock() }

        guard events.isEmpty == false else {
            return "[]"
        }

        return "[\(events.joined(separator: "; "))]"
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        record("didSubscribeTrack \(diagnosticDescription(participant: participant, publication: publication))")
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        record("didUnsubscribeTrack \(diagnosticDescription(participant: participant, publication: publication))")
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              didFailToSubscribeTrackWithSid trackSid: Track.Sid,
              error: LiveKitError) {
        record([
            "didFailToSubscribeTrack",
            "participantIdentity=\(participant.identity?.stringValue ?? "<nil>")",
            "trackSID=\(trackSid.stringValue)",
            "errorType=\(error.type)"
        ].joined(separator: " "))
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              trackPublication: RemoteTrackPublication,
              didUpdateStreamState streamState: StreamState) {
        record("didUpdateStreamState streamState=\(streamState) \(diagnosticDescription(participant: participant, publication: trackPublication))")
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              trackPublication: RemoteTrackPublication,
              didUpdateIsSubscriptionAllowed isSubscriptionAllowed: Bool) {
        record([
            "didUpdateIsSubscriptionAllowed",
            "isSubscriptionAllowed=\(isSubscriptionAllowed)",
            diagnosticDescription(participant: participant, publication: trackPublication)
        ].joined(separator: " "))
    }

    private func diagnosticDescription(participant: RemoteParticipant, publication: RemoteTrackPublication) -> String {
        remoteAudioPublicationDiagnosticFields(participant: participant, remotePublication: publication)
            .joined(separator: ",")
    }

    private func record(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()

        logLiveKitIntegration("subscription event \(event)")
    }
}

private func remoteAudioPublicationDiagnosticFields(participant: RemoteParticipant, remotePublication: RemoteTrackPublication) -> [String] {
    [
        "participantIdentity=\(participant.identity?.stringValue ?? "<nil>")",
        "publicationSID=\(remotePublication.sid.stringValue)",
        "kind=\(remotePublication.kind)",
        "source=\(remotePublication.source)",
        "isSubscribed=\(remotePublication.isSubscribed)",
        "isDesired=\(remotePublication.isDesired)",
        "isSubscribePreferred=\(subscribePreferredDiagnostic(for: remotePublication))",
        "isSubscriptionAllowed=\(remotePublication.isSubscriptionAllowed)",
        "subscriptionState=\(remotePublication.subscriptionState)"
    ]
}

private func subscribePreferredDiagnostic(for remotePublication: RemoteTrackPublication) -> String {
    guard let isSubscribePreferred = remotePublication._state.read({ $0.isSubscribePreferred }) else {
        return "<nil>"
    }

    return "\(isSubscribePreferred)"
}

private func logLiveKitIntegration(_ message: String) {
    NSLog("%@", "[DirectCallLiveKitIntegration] \(message)")
}

@MainActor
private final class MediaTokenProviderSpy: DirectCallMediaTokenProviderProtocol {
    private(set) var requestedSessions = [DirectCallSession]()
    var callOrderRecorder: CallOrderRecorder?
    var result: Result<DirectCallMediaConnectionInfo, DirectCallMediaError>

    init(result: Result<DirectCallMediaConnectionInfo, DirectCallMediaError> = .success(.init(serverURL: URL(fileURLWithPath: "/tmp/livekit.example.com"),
                                                                                              roomName: "direct-call",
                                                                                              token: "test-token"))) {
        self.result = result
    }

    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        callOrderRecorder?.events.append("token")
        requestedSessions.append(session)
        return result
    }
}

@MainActor
private final class AudioRouteControllerSpy: DirectCallAudioRouteControllerProtocol {
    private(set) var configuredDefaultRoutes = [String]()
    private(set) var speakerValues = [Bool]()
    private(set) var deactivateAudioSessionCount = 0

    func configureDefaultAudioRoute(for session: DirectCallSession) -> Result<DirectCallAudioRoute, DirectCallMediaError> {
        configuredDefaultRoutes.append(session.callID)
        return .success(.earpiece)
    }

    func setSpeakerEnabled(_ isEnabled: Bool) -> Result<DirectCallAudioRoute, DirectCallMediaError> {
        speakerValues.append(isEnabled)
        return .success(isEnabled ? .speaker : .earpiece)
    }

    func deactivateAudioSession() {
        deactivateAudioSessionCount += 1
    }
}

@MainActor
private final class MediaEncryptionServiceSpy: DirectCallEncryptionServiceProtocol {
    private(set) var clearedCallIDs = [String]()

    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) -> Result<DirectCallEncryptedKeyExchangePayload, DirectCallEncryptionFailureReason> {
        .failure(.keyExchangeFailed)
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload, expectedCallID: String, expectedRoomID: String, expectedSenderUserID: String) -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        .failure(.keyExchangeFailed)
    }

    func clearPerCallKey(callID: String) {
        guard !clearedCallIDs.contains(callID) else {
            return
        }

        clearedCallIDs.append(callID)
    }
}

@MainActor
private final class CallOrderRecorder {
    var events = [String]()
}

@MainActor
private final class MediaE2EEContextSpy: DirectCallMediaE2EEContextProtocol {
    private(set) var cleanupCount = 0

    func cleanup() {
        cleanupCount += 1
    }
}

@MainActor
private final class LiveKitMediaE2EEContextSpy: DirectCallLiveKitE2EEContextProtocol {
    private(set) var cleanupCount = 0
    private(set) var makeRoomOptionsCount = 0

    var result: Result<RoomOptions, DirectCallMediaError>

    init(result: Result<RoomOptions, DirectCallMediaError>? = nil) {
        self.result = result ?? .success(RoomOptions(encryptionOptions: EncryptionOptions(keyProvider: BaseKeyProvider())))
    }

    func makeLiveKitRoomOptions() -> Result<RoomOptions, DirectCallMediaError> {
        makeRoomOptionsCount += 1
        return result
    }

    func cleanup() {
        cleanupCount += 1
    }
}

@MainActor
private final class MediaE2EEContextProviderSpy: DirectCallMediaE2EEContextProviderProtocol {
    private(set) var requestedSessions = [DirectCallSession]()
    private(set) var requestedKeyHandles = [DirectCallMediaKeyHandle]()
    private(set) var clearedCallIDs = [String]()

    var callOrderRecorder: CallOrderRecorder?
    var result: Result<any DirectCallMediaE2EEContextProtocol, DirectCallMediaError>

    private var contextsByCallID = [String: any DirectCallMediaE2EEContextProtocol]()

    init(result: Result<any DirectCallMediaE2EEContextProtocol, DirectCallMediaError>? = nil) {
        self.result = result ?? .success(MediaE2EEContextSpy())
    }

    func context(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) -> Result<any DirectCallMediaE2EEContextProtocol, DirectCallMediaError> {
        callOrderRecorder?.events.append("e2eeContext")
        requestedSessions.append(session)
        requestedKeyHandles.append(keyHandle)

        switch result {
        case .success(let context):
            contextsByCallID[session.callID] = context
            return .success(context)
        case .failure(let error):
            return .failure(error)
        }
    }

    func clearContext(callID: String) {
        guard !clearedCallIDs.contains(callID) else {
            return
        }

        clearedCallIDs.append(callID)
        contextsByCallID.removeValue(forKey: callID)?.cleanup()
    }
}

private struct LiveKitClientTestError: Error { }

private struct DirectCallLiveKitIntegrationEnvironment: Equatable {
    static var current: DirectCallLiveKitIntegrationEnvironment? {
        DirectCallLiveKitIntegrationEnvironment(environment: ProcessInfo.processInfo.environment)
    }

    static var isRunnableInCurrentProcess: Bool {
        current?.isRunnable == true
    }

    let serverURL: URL
    let token: String
    let roomName: String
    let identity: String
    let e2eeTestKey: String

    var isRunnable: Bool {
        usesProductionLikeURL == false
    }

    var usesProductionLikeURL: Bool {
        guard let host = Self.normalizedHost(from: serverURL) else {
            return true
        }

        return Self.usesProductionLikeHost(host)
    }

    var canonicalLiveKitURLString: String? {
        Self.canonicalLiveKitURLString(from: serverURL)
    }

    var canonicalLiveKitURL: URL? {
        canonicalLiveKitURLString.flatMap(URL.init(string:))
    }

    var urlGuardDiagnostic: String {
        Self.urlGuardDiagnostic(for: serverURL, productionLike: usesProductionLikeURL)
    }

    static func normalizedHost(from serverURL: URL) -> String? {
        let absoluteString = serverURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = serverURL.host ?? URLComponents(string: absoluteString)?.host ?? parsedHost(from: absoluteString)
        return normalizedHostValue(host)
    }

    static func urlGuardDiagnostic(for serverURL: URL, productionLike: Bool) -> String {
        let absoluteString = serverURL.absoluteString
        let componentsHost = URLComponents(string: absoluteString)?.host ?? "<nil>"
        let normalizedHost = normalizedHost(from: serverURL) ?? "<nil>"
        return "url=\(absoluteString), host=\(serverURL.host ?? "<nil>"), componentsHost=\(componentsHost), normalizedHost=\(normalizedHost), productionLike=\(productionLike)"
    }

    static func usesProductionLikeHost(_ host: String) -> Bool {
        guard let host = normalizedHostValue(host) else {
            return true
        }

        let localHosts = ["localhost", "127.0.0.1", "::1"]
        if localHosts.contains(host) {
            return false
        }

        let knownProductionHosts = ["mertis.kz", "customer01.kz"]
        if knownProductionHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return true
        }

        if host.contains("production") || host.contains("prod") {
            let explicitTestMarkers = ["test", "staging", "stage", "dev", "localhost", "127.0.0.1"]
            return explicitTestMarkers.allSatisfy { host.contains($0) == false }
        }

        return false
    }

    static func canonicalLiveKitURLString(from serverURL: URL) -> String? {
        let absoluteString = serverURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = normalizedHost(from: serverURL),
              usesProductionLikeHost(host) == false else {
            return nil
        }

        if absoluteString.contains("://") {
            return absoluteString
        }

        guard isLocalTestHost(host),
              let canonicalURLString = canonicalSingleSlashLocalURLString(from: absoluteString) else {
            return nil
        }

        return canonicalURLString
    }

    private static func parsedHost(from absoluteString: String) -> String? {
        let authorityStart: String.Index
        if let schemeRange = absoluteString.range(of: "://") {
            authorityStart = schemeRange.upperBound
        } else if let schemeSeparatorIndex = absoluteString.firstIndex(of: ":") {
            let scheme = absoluteString[..<schemeSeparatorIndex].lowercased()
            let supportedSchemes = ["ws", "wss", "http", "https"]
            let singleSlashIndex = absoluteString.index(after: schemeSeparatorIndex)
            guard supportedSchemes.contains(String(scheme)),
                  singleSlashIndex < absoluteString.endIndex,
                  absoluteString[singleSlashIndex] == "/" else {
                return nil
            }

            authorityStart = absoluteString.index(after: singleSlashIndex)
        } else {
            return nil
        }

        let remainder = absoluteString[authorityStart...]
        let authorityEnd = remainder.firstIndex { "/?#".contains($0) } ?? remainder.endIndex
        var authority = String(remainder[..<authorityEnd])
        if let userInfoEnd = authority.lastIndex(of: "@") {
            authority = String(authority[authority.index(after: userInfoEnd)...])
        }

        return authority.isEmpty ? nil : authority
    }

    private static func canonicalSingleSlashLocalURLString(from absoluteString: String) -> String? {
        guard let schemeSeparatorIndex = absoluteString.firstIndex(of: ":") else {
            return nil
        }

        let scheme = absoluteString[..<schemeSeparatorIndex].lowercased()
        let supportedSchemes = ["ws", "wss", "http", "https"]
        let singleSlashIndex = absoluteString.index(after: schemeSeparatorIndex)
        guard supportedSchemes.contains(String(scheme)),
              singleSlashIndex < absoluteString.endIndex,
              absoluteString[singleSlashIndex] == "/",
              absoluteString.index(after: singleSlashIndex) < absoluteString.endIndex else {
            return nil
        }

        let authorityStart = absoluteString.index(after: singleSlashIndex)
        let remainder = absoluteString[authorityStart...]
        let authorityEnd = remainder.firstIndex { "/?#".contains($0) } ?? remainder.endIndex
        let authority = String(remainder[..<authorityEnd])
        let tail = String(remainder[authorityEnd...])
        guard let host = normalizedHostValue(authority),
              isLocalTestHost(host) else {
            return nil
        }

        return "\(scheme)://\(authority)\(tail)"
    }

    private static func isLocalTestHost(_ host: String) -> Bool {
        guard let host = normalizedHostValue(host) else {
            return false
        }

        let localHosts = ["localhost", "127.0.0.1", "::1"]
        return localHosts.contains(host)
    }

    private static func normalizedHostValue(_ value: String?) -> String? {
        guard var host = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              host.isEmpty == false else {
            return nil
        }

        if host.hasPrefix("["),
           let closingBracketIndex = host.firstIndex(of: "]") {
            let innerHostStart = host.index(after: host.startIndex)
            let innerHost = String(host[innerHostStart..<closingBracketIndex])
            return innerHost.isEmpty ? nil : innerHost
        }

        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let colonCount = host.filter { $0 == ":" }.count
        if colonCount == 1,
           let portSeparatorIndex = host.lastIndex(of: ":") {
            let portStartIndex = host.index(after: portSeparatorIndex)
            let port = host[portStartIndex...]
            let hostWithoutPort = host[..<portSeparatorIndex]
            if hostWithoutPort.isEmpty == false, port.allSatisfy(\.isNumber) {
                host = String(hostWithoutPort)
            }
        }

        return host.isEmpty ? nil : host
    }

    init?(environment: [String: String]) {
        guard environment["SALEMX_DIRECTCALL_LIVEKIT_INTEGRATION"] == "1",
              let urlValue = environment["SALEMX_DIRECTCALL_LIVEKIT_URL"]?.nonEmpty,
              let url = URL(string: urlValue),
              let token = environment["SALEMX_DIRECTCALL_LIVEKIT_TOKEN"]?.nonEmpty,
              let roomName = environment["SALEMX_DIRECTCALL_LIVEKIT_ROOM"]?.nonEmpty,
              let identity = environment["SALEMX_DIRECTCALL_LIVEKIT_IDENTITY"]?.nonEmpty,
              let e2eeTestKey = environment["SALEMX_DIRECTCALL_LIVEKIT_E2EE_TEST_KEY"]?.nonEmpty else {
            return nil
        }

        serverURL = url
        self.token = token
        self.roomName = roomName
        self.identity = identity
        self.e2eeTestKey = e2eeTestKey
    }
}

private struct DirectCallLiveKitTwoEndpointIntegrationEnvironment: Equatable {
    static var current: DirectCallLiveKitTwoEndpointIntegrationEnvironment? {
        DirectCallLiveKitTwoEndpointIntegrationEnvironment(environment: ProcessInfo.processInfo.environment)
    }

    static var isRunnableInCurrentProcess: Bool {
        current?.isRunnable == true
    }

    let serverURL: URL
    let token: String
    let roomName: String
    let identity: String
    let peerToken: String
    let peerIdentity: String
    let e2eeTestKey: String

    var isRunnable: Bool {
        usesProductionLikeURL == false
    }

    var usesProductionLikeURL: Bool {
        guard let host = DirectCallLiveKitIntegrationEnvironment.normalizedHost(from: serverURL) else {
            return true
        }

        return DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost(host)
    }

    var canonicalLiveKitURLString: String? {
        DirectCallLiveKitIntegrationEnvironment.canonicalLiveKitURLString(from: serverURL)
    }

    var canonicalLiveKitURL: URL? {
        canonicalLiveKitURLString.flatMap(URL.init(string:))
    }

    var urlGuardDiagnostic: String {
        DirectCallLiveKitIntegrationEnvironment.urlGuardDiagnostic(for: serverURL, productionLike: usesProductionLikeURL)
    }

    var liveKitTokenDiagnostics: DirectCallLiveKitTwoEndpointTokenDiagnostics? {
        guard let primaryToken = DirectCallLiveKitDecodedToken(token: token),
              let peerToken = DirectCallLiveKitDecodedToken(token: peerToken) else {
            return nil
        }

        return DirectCallLiveKitTwoEndpointTokenDiagnostics(environment: self,
                                                            primaryToken: primaryToken,
                                                            peerToken: peerToken)
    }

    var tokenGuardDiagnostic: String {
        guard let liveKitTokenDiagnostics else {
            return [
                "runtimeEnvRoom=\(roomName)",
                "primaryTokenRoom=<undecodable>",
                "peerTokenRoom=<undecodable>",
                "primaryTokenIdentity=<undecodable>",
                "peerTokenIdentity=<undecodable>",
                "primaryTokenExpiresInSeconds=<undecodable>",
                "peerTokenExpiresInSeconds=<undecodable>",
                "primaryTokenRoomMatchesRuntimeEnvRoom=false",
                "peerTokenRoomMatchesRuntimeEnvRoom=false"
            ].joined(separator: ", ")
        }

        return liveKitTokenDiagnostics.description
    }

    init?(environment: [String: String]) {
        guard environment["SALEMX_DIRECTCALL_LIVEKIT_TWO_ENDPOINT_INTEGRATION"] == "1",
              let urlValue = environment["SALEMX_DIRECTCALL_LIVEKIT_URL"]?.nonEmpty,
              let url = URL(string: urlValue),
              let token = environment["SALEMX_DIRECTCALL_LIVEKIT_TOKEN"]?.nonEmpty,
              let roomName = environment["SALEMX_DIRECTCALL_LIVEKIT_ROOM"]?.nonEmpty,
              let identity = environment["SALEMX_DIRECTCALL_LIVEKIT_IDENTITY"]?.nonEmpty,
              let peerToken = environment["SALEMX_DIRECTCALL_LIVEKIT_PEER_TOKEN"]?.nonEmpty,
              let peerIdentity = environment["SALEMX_DIRECTCALL_LIVEKIT_PEER_IDENTITY"]?.nonEmpty,
              let e2eeTestKey = environment["SALEMX_DIRECTCALL_LIVEKIT_E2EE_TEST_KEY"]?.nonEmpty,
              identity != peerIdentity else {
            return nil
        }

        serverURL = url
        self.token = token
        self.roomName = roomName
        self.identity = identity
        self.peerToken = peerToken
        self.peerIdentity = peerIdentity
        self.e2eeTestKey = e2eeTestKey
    }
}

private struct DirectCallLiveKitTwoEndpointTokenDiagnostics: Equatable, CustomStringConvertible {
    let runtimeEnvironmentRoom: String
    let primaryTokenRoom: String?
    let peerTokenRoom: String?
    let primaryTokenIdentity: String?
    let peerTokenIdentity: String?
    let primaryTokenExpiresInSeconds: Int?
    let peerTokenExpiresInSeconds: Int?
    let primaryTokenRoomJoin: Bool?
    let peerTokenRoomJoin: Bool?
    let primaryTokenCanPublish: Bool?
    let peerTokenCanPublish: Bool?
    let primaryTokenRoomPublish: Bool?
    let peerTokenRoomPublish: Bool?
    let primaryTokenCanSubscribe: Bool?
    let peerTokenCanSubscribe: Bool?
    let primaryTokenRoomSubscribe: Bool?
    let peerTokenRoomSubscribe: Bool?

    var primaryRoomMatchesEnvironment: Bool {
        primaryTokenRoom == runtimeEnvironmentRoom
    }

    var peerRoomMatchesEnvironment: Bool {
        peerTokenRoom == runtimeEnvironmentRoom
    }

    var primaryTokenExpired: Bool {
        guard let primaryTokenExpiresInSeconds else {
            return true
        }

        return primaryTokenExpiresInSeconds <= 0
    }

    var peerTokenExpired: Bool {
        guard let peerTokenExpiresInSeconds else {
            return true
        }

        return peerTokenExpiresInSeconds <= 0
    }

    var description: String {
        [
            "runtimeEnvRoom=\(runtimeEnvironmentRoom)",
            "primaryTokenRoom=\(primaryTokenRoom ?? "<missing>")",
            "peerTokenRoom=\(peerTokenRoom ?? "<missing>")",
            "primaryTokenIdentity=\(primaryTokenIdentity ?? "<missing>")",
            "peerTokenIdentity=\(peerTokenIdentity ?? "<missing>")",
            "primaryTokenExpiresInSeconds=\(primaryTokenExpiresInSeconds.map(String.init) ?? "<missing>")",
            "peerTokenExpiresInSeconds=\(peerTokenExpiresInSeconds.map(String.init) ?? "<missing>")",
            "primaryTokenRoomJoin=\(optionalBoolDescription(primaryTokenRoomJoin))",
            "peerTokenRoomJoin=\(optionalBoolDescription(peerTokenRoomJoin))",
            "primaryTokenCanPublish=\(optionalBoolDescription(primaryTokenCanPublish))",
            "peerTokenCanPublish=\(optionalBoolDescription(peerTokenCanPublish))",
            "primaryTokenRoomPublish=\(optionalBoolDescription(primaryTokenRoomPublish))",
            "peerTokenRoomPublish=\(optionalBoolDescription(peerTokenRoomPublish))",
            "primaryTokenCanSubscribe=\(optionalBoolDescription(primaryTokenCanSubscribe))",
            "peerTokenCanSubscribe=\(optionalBoolDescription(peerTokenCanSubscribe))",
            "primaryTokenRoomSubscribe=\(optionalBoolDescription(primaryTokenRoomSubscribe))",
            "peerTokenRoomSubscribe=\(optionalBoolDescription(peerTokenRoomSubscribe))",
            "primaryTokenRoomMatchesRuntimeEnvRoom=\(primaryRoomMatchesEnvironment)",
            "peerTokenRoomMatchesRuntimeEnvRoom=\(peerRoomMatchesEnvironment)"
        ].joined(separator: ", ")
    }

    init(environment: DirectCallLiveKitTwoEndpointIntegrationEnvironment,
         primaryToken: DirectCallLiveKitDecodedToken,
         peerToken: DirectCallLiveKitDecodedToken,
         now: Date = Date()) {
        runtimeEnvironmentRoom = environment.roomName
        primaryTokenRoom = primaryToken.room
        peerTokenRoom = peerToken.room
        primaryTokenIdentity = primaryToken.identity
        peerTokenIdentity = peerToken.identity
        primaryTokenExpiresInSeconds = primaryToken.expiresInSeconds(now: now)
        peerTokenExpiresInSeconds = peerToken.expiresInSeconds(now: now)
        primaryTokenRoomJoin = primaryToken.roomJoin
        peerTokenRoomJoin = peerToken.roomJoin
        primaryTokenCanPublish = primaryToken.canPublish
        peerTokenCanPublish = peerToken.canPublish
        primaryTokenRoomPublish = primaryToken.roomPublish
        peerTokenRoomPublish = peerToken.roomPublish
        primaryTokenCanSubscribe = primaryToken.canSubscribe
        peerTokenCanSubscribe = peerToken.canSubscribe
        primaryTokenRoomSubscribe = primaryToken.roomSubscribe
        peerTokenRoomSubscribe = peerToken.roomSubscribe
    }
}

private func optionalBoolDescription(_ value: Bool?) -> String {
    value.map(String.init) ?? "<missing>"
}

private struct DirectCallLiveKitDecodedToken: Equatable {
    let room: String?
    let identity: String?
    let expirationDate: Date?
    let roomJoin: Bool?
    let canPublish: Bool?
    let roomPublish: Bool?
    let canSubscribe: Bool?
    let roomSubscribe: Bool?

    init?(token: String) {
        let tokenSegments = token.split(separator: ".")
        guard tokenSegments.count >= 2,
              let payloadData = Self.base64URLDecodedData(String(tokenSegments[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        let videoPayload = payload["video"] as? [String: Any]

        room = Self.stringValue(for: "room", in: payload)
            ?? videoPayload.flatMap { Self.stringValue(for: "room", in: $0) }
        identity = Self.stringValue(for: "sub", in: payload)
            ?? Self.stringValue(for: "identity", in: payload)
        roomJoin = Self.boolValue(forAnyOf: ["roomJoin", "room_join"], in: payload, nestedPayload: videoPayload)
        canPublish = Self.boolValue(forAnyOf: ["canPublish", "can_publish"], in: payload, nestedPayload: videoPayload)
        roomPublish = Self.boolValue(forAnyOf: ["roomPublish", "room_publish"], in: payload, nestedPayload: videoPayload)
        canSubscribe = Self.boolValue(forAnyOf: ["canSubscribe", "can_subscribe"], in: payload, nestedPayload: videoPayload)
        roomSubscribe = Self.boolValue(forAnyOf: ["roomSubscribe", "room_subscribe"], in: payload, nestedPayload: videoPayload)

        if let expirationTimestamp = Self.doubleValue(for: "exp", in: payload) {
            expirationDate = Date(timeIntervalSince1970: expirationTimestamp)
        } else {
            expirationDate = nil
        }
    }

    func expiresInSeconds(now: Date) -> Int? {
        expirationDate.map { Int($0.timeIntervalSince(now).rounded(.down)) }
    }

    private static func base64URLDecodedData(_ value: String) -> Data? {
        var base64Value = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingLength = (4 - base64Value.count % 4) % 4
        base64Value += String(repeating: "=", count: paddingLength)
        return Data(base64Encoded: base64Value)
    }

    private static func stringValue(for key: String, in payload: [String: Any]) -> String? {
        guard let value = payload[key] else {
            return nil
        }

        if let stringValue = value as? String {
            return stringValue
        }

        return nil
    }

    private static func boolValue(forAnyOf keys: [String], in payload: [String: Any], nestedPayload: [String: Any]?) -> Bool? {
        for key in keys {
            if let boolValue = boolValue(for: key, in: payload) {
                return boolValue
            }
        }

        guard let nestedPayload else {
            return nil
        }

        for key in keys {
            if let boolValue = boolValue(for: key, in: nestedPayload) {
                return boolValue
            }
        }

        return nil
    }

    private static func boolValue(for key: String, in payload: [String: Any]) -> Bool? {
        guard let value = payload[key] else {
            return nil
        }

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let intValue = value as? Int {
            return intValue != 0
        }

        if let stringValue = value as? String {
            switch stringValue.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }

        return nil
    }

    private static func doubleValue(for key: String, in payload: [String: Any]) -> Double? {
        guard let value = payload[key] else {
            return nil
        }

        if let doubleValue = value as? Double {
            return doubleValue
        }

        if let intValue = value as? Int {
            return Double(intValue)
        }

        if let stringValue = value as? String {
            return Double(stringValue)
        }

        return nil
    }
}

@MainActor
private final class DirectCallLiveKitIntegrationE2EEContext: DirectCallLiveKitE2EEContextProtocol {
    private var keyProvider: BaseKeyProvider?
    private(set) var cleanupCount = 0

    init(testKey: String) {
        keyProvider = BaseKeyProvider(isSharedKey: true, sharedKey: testKey)
    }

    func makeLiveKitRoomOptions() -> Result<RoomOptions, DirectCallMediaError> {
        guard let keyProvider else {
            return .failure(.e2eeContextUnavailable)
        }

        return .success(RoomOptions(encryptionOptions: EncryptionOptions(keyProvider: keyProvider)))
    }

    func cleanup() {
        cleanupCount += 1
        keyProvider = nil
    }
}

private final class DirectCallLiveKitTestAudioTrack: LocalAudioTrack, @unchecked Sendable {
    override func startCapture() async throws { }
    override func stopCapture() async throws { }
    override func startWaitingForFrames() async throws { }

    convenience init(name: String) {
        let source = RTC.createAudioSource(nil)
        let rtcTrack = RTC.createAudioTrack(source: source)
        rtcTrack.isEnabled = true
        self.init(name: name,
                  source: .microphone,
                  track: rtcTrack,
                  reportStatistics: false,
                  captureOptions: AudioCaptureOptions())
    }
}

private actor LiveKitIntegrationPublishState {
    private(set) var publication: LocalTrackPublication?
    private var didFail = false

    var hasFinished: Bool {
        publication != nil || didFail
    }

    func succeed(with publication: LocalTrackPublication) {
        self.publication = publication
    }

    func fail() {
        didFail = true
    }
}

private actor LiveKitIntegrationMediaResultState {
    private(set) var result: Result<Void, DirectCallMediaError>?

    var hasFinished: Bool {
        result != nil
    }

    func finish(with result: Result<Void, DirectCallMediaError>) {
        self.result = result
    }
}

private actor LiveKitIntegrationCompletionState {
    private var didFinish = false

    var hasFinished: Bool {
        didFinish
    }

    func finish() {
        didFinish = true
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

@MainActor
private final class LiveKitClientSpy: DirectCallLiveKitClientProtocol {
    private(set) var connectionInfos = [DirectCallMediaConnectionInfo]()
    private(set) var e2eeContextCount = 0
    private(set) var microphoneValues = [Bool]()
    private(set) var remoteAudioPlaybackValues = [Bool]()
    private(set) var disconnectCount = 0
    private(set) var cleanupCount = 0

    var callOrderRecorder: CallOrderRecorder?
    var connectResult: Result<Void, DirectCallMediaError>
    var microphoneResult: Result<Void, DirectCallMediaError>
    var remoteAudioResult: Result<Void, DirectCallMediaError>

    init(connectResult: Result<Void, DirectCallMediaError> = .success(()),
         microphoneResult: Result<Void, DirectCallMediaError> = .success(()),
         remoteAudioResult: Result<Void, DirectCallMediaError> = .success(())) {
        self.connectResult = connectResult
        self.microphoneResult = microphoneResult
        self.remoteAudioResult = remoteAudioResult
    }

    func connect(connectionInfo: DirectCallMediaConnectionInfo, e2eeContext: any DirectCallMediaE2EEContextProtocol) async -> Result<Void, DirectCallMediaError> {
        callOrderRecorder?.events.append("clientConnect")
        connectionInfos.append(connectionInfo)
        e2eeContextCount += 1
        return connectResult
    }

    func setMicrophoneEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        microphoneValues.append(isEnabled)
        return microphoneResult
    }

    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        remoteAudioPlaybackValues.append(isEnabled)
        return remoteAudioResult
    }

    func disconnect() async {
        disconnectCount += 1
    }

    func cleanup() async {
        cleanupCount += 1
    }
}
