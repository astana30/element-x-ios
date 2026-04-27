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
    func liveKitClientPreparesE2EEConfiguredRoomWithoutConnecting() async {
        var createdConnectOptions: ConnectOptions?
        var createdRoomOptions: RoomOptions?
        let client = LiveKitDirectCallClient { connectOptions, roomOptions in
            createdConnectOptions = connectOptions
            createdRoomOptions = roomOptions
            return Room(connectOptions: connectOptions, roomOptions: roomOptions)
        }
        let context = LiveKitMediaE2EEContextSpy()

        let result = await client.connect(connectionInfo: makeConnectionInfo(), e2eeContext: context)

        guard case .failure(.mediaSetupUnavailable) = result else {
            Issue.record("Expected compile-only SDK client to fail closed after E2EE setup.")
            return
        }
        #expect(context.makeRoomOptionsCount == 1)
        #expect(createdConnectOptions?.enableMicrophone == false)
        #expect(createdRoomOptions?.encryptionOptions != nil)
        #expect(createdRoomOptions?.e2eeOptions == nil)
        await client.cleanup()
    }

    @Test
    func liveKitClientCleanupReleasesPreparedE2EEContextIdempotently() async {
        let client = LiveKitDirectCallClient()
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
        #expect(engine.mediaStatePublisher.value.canPublishMicrophone == false)
        #expect(engine.mediaStatePublisher.value.canPlayRemoteAudio == false)
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

@MainActor
private final class LiveKitClientSpy: DirectCallLiveKitClientProtocol {
    private(set) var connectionInfos = [DirectCallMediaConnectionInfo]()
    private(set) var e2eeContextCount = 0
    private(set) var microphoneValues = [Bool]()
    private(set) var disconnectCount = 0
    private(set) var cleanupCount = 0
    
    var callOrderRecorder: CallOrderRecorder?
    var connectResult: Result<Void, DirectCallMediaError>
    var microphoneResult: Result<Void, DirectCallMediaError>
    
    init(connectResult: Result<Void, DirectCallMediaError> = .success(()),
         microphoneResult: Result<Void, DirectCallMediaError> = .success(())) {
        self.connectResult = connectResult
        self.microphoneResult = microphoneResult
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
    
    func disconnect() async {
        disconnectCount += 1
    }
    
    func cleanup() async {
        cleanupCount += 1
    }
}
