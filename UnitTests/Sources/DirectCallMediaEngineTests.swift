//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import LiveKit
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
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("matrix.mertis.kz") == true)
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("calls.customer01.kz") == true)
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("prod-livekit.example.com") == true)
        #expect(DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost("test-livekit.example.com") == false)
    }

    @Test
    func liveKitTwoEndpointRemoteAudioIntegrationHarnessSkipsByDefault() {
        let environment = DirectCallLiveKitTwoEndpointIntegrationEnvironment(environment: [:])

        #expect(environment == nil)
    }

    @Test(.enabled(if: DirectCallLiveKitIntegrationEnvironment.isRunnableInCurrentProcess))
    func liveKitRoomConnectIntegrationCompletesWhenExplicitlyEnabled() async {
        guard let environment = DirectCallLiveKitIntegrationEnvironment.current else {
            Issue.record("Integration environment is not enabled.")
            return
        }

        guard environment.usesProductionLikeURL == false else {
            Issue.record("Integration environment uses a production-like LiveKit URL.")
            return
        }

        let client = LiveKitDirectCallClient()
        let context = DirectCallLiveKitIntegrationE2EEContext(testKey: environment.e2eeTestKey)
        let connectionInfo = DirectCallMediaConnectionInfo(serverURL: environment.serverURL,
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

    @Test(.enabled(if: DirectCallLiveKitTwoEndpointIntegrationEnvironment.isRunnableInCurrentProcess))
    func liveKitTwoEndpointRemoteAudioGateIntegrationCompletesWhenExplicitlyEnabled() async {
        guard let environment = DirectCallLiveKitTwoEndpointIntegrationEnvironment.current else {
            Issue.record("Two-endpoint integration environment is not enabled.")
            return
        }

        guard environment.usesProductionLikeURL == false else {
            Issue.record("Two-endpoint integration environment uses a production-like LiveKit URL.")
            return
        }

        let primaryClient = LiveKitDirectCallClient()
        let peerClient = LiveKitDirectCallClient()
        let primaryContext = DirectCallLiveKitIntegrationE2EEContext(testKey: environment.e2eeTestKey)
        let peerContext = DirectCallLiveKitIntegrationE2EEContext(testKey: environment.e2eeTestKey)
        let primaryConnectionInfo = DirectCallMediaConnectionInfo(serverURL: environment.serverURL,
                                                                  roomName: environment.roomName,
                                                                  token: environment.token)
        let peerConnectionInfo = DirectCallMediaConnectionInfo(serverURL: environment.serverURL,
                                                               roomName: environment.roomName,
                                                               token: environment.peerToken)

        let primaryConnectResult = await primaryClient.connect(connectionInfo: primaryConnectionInfo, e2eeContext: primaryContext)
        let peerConnectResult = await peerClient.connect(connectionInfo: peerConnectionInfo, e2eeContext: peerContext)
        guard case .success = primaryConnectResult,
              case .success = peerConnectResult,
              let primaryRoom = liveKitRoom(from: primaryClient),
              let peerRoom = liveKitRoom(from: peerClient) else {
            await primaryClient.cleanup()
            await peerClient.cleanup()
            Issue.record("Expected two LiveKit clients to connect and expose test-only rooms.")
            return
        }

        var peerAudioPublication: LocalTrackPublication?
        func cleanupIntegrationClients() async {
            await primaryClient.cleanup()

            if let peerAudioPublication {
                try? await peerRoom.localParticipant.unpublish(publication: peerAudioPublication)
            }

            await peerClient.cleanup()
        }

        let peerAudioTrack = LocalAudioTrack.createTrack(name: "salemx-test-remote-audio",
                                                         options: .noProcessing)
        do {
            peerAudioPublication = try await peerRoom.localParticipant.publish(audioTrack: peerAudioTrack)
        } catch {
            await cleanupIntegrationClients()
            Issue.record("Expected test-only peer audio publication to succeed.")
            return
        }

        let primarySawRemoteAudio = await waitForLiveKitIntegrationCondition {
            firstRemoteAudioPublication(in: primaryRoom) != nil
        }
        guard primarySawRemoteAudio,
              let primaryRemoteAudioPublication = firstRemoteAudioPublication(in: primaryRoom) else {
            await cleanupIntegrationClients()
            Issue.record("Expected primary endpoint to see peer audio publication.")
            return
        }

        #expect(primaryRemoteAudioPublication.isSubscribed == false)
        #expect(hasRemoteVideoPublications(in: primaryRoom) == false)
        #expect(peerRoom.localParticipant.localVideoTracks.isEmpty)

        let primaryMicDisableResult = await primaryClient.setMicrophoneEnabled(false)
        let peerMicDisableResult = await peerClient.setMicrophoneEnabled(false)
        let remoteAudioEnableResult = await primaryClient.setRemoteAudioPlaybackEnabled(true)
        let primarySubscribedRemoteAudio = await waitForLiveKitIntegrationCondition {
            primaryRemoteAudioPublication.isSubscribed
        }
        let remoteAudioDisableResult = await primaryClient.setRemoteAudioPlaybackEnabled(false)
        let primaryUnsubscribedRemoteAudio = await waitForLiveKitIntegrationCondition {
            primaryRemoteAudioPublication.isSubscribed == false
        }
        let remoteAudioReenableResult = await primaryClient.setRemoteAudioPlaybackEnabled(true)
        let primaryResubscribedRemoteAudio = await waitForLiveKitIntegrationCondition {
            primaryRemoteAudioPublication.isSubscribed
        }
        await cleanupIntegrationClients()
        let primaryCleanupUnsubscribedRemoteAudio = await waitForLiveKitIntegrationCondition {
            primaryRemoteAudioPublication.isSubscribed == false
        }

        guard case .success = primaryMicDisableResult,
              case .success = peerMicDisableResult else {
            Issue.record("Expected microphone disable to remain safe after integration connect.")
            return
        }

        guard case .success = remoteAudioEnableResult,
              case .success = remoteAudioDisableResult,
              case .success = remoteAudioReenableResult else {
            Issue.record("Expected remote audio gate changes to be safe after two endpoint connect.")
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

    private func waitForLiveKitIntegrationCondition(timeoutNanoseconds: UInt64 = 5_000_000_000,
                                                    pollNanoseconds: UInt64 = 100_000_000,
                                                    _ condition: () -> Bool) async -> Bool {
        let maxAttempts = Int(timeoutNanoseconds / pollNanoseconds)
        for _ in 0..<maxAttempts {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }

        return condition()
    }

    private func firstRemoteAudioPublication(in room: Room) -> RemoteTrackPublication? {
        room.remoteParticipants.values
            .flatMap(\.audioTracks)
            .compactMap { $0 as? RemoteTrackPublication }
            .first
    }

    private func hasRemoteVideoPublications(in room: Room) -> Bool {
        room.remoteParticipants.values.contains { participant in
            participant.videoTracks.isEmpty == false
        }
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
        guard let host = serverURL.host?.lowercased() else {
            return true
        }

        return Self.usesProductionLikeHost(host)
    }

    static func usesProductionLikeHost(_ host: String) -> Bool {
        let host = host.lowercased()
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
        guard let host = serverURL.host?.lowercased() else {
            return true
        }

        return DirectCallLiveKitIntegrationEnvironment.usesProductionLikeHost(host)
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
