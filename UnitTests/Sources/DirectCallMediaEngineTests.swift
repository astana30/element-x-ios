//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
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

        #expect(result == .failure(.tokenUnavailable))
        #expect(engine.mediaStatePublisher.value.canPublishMicrophone == false)
        #expect(engine.mediaStatePublisher.value.canPlayRemoteAudio == false)
    }
    
    @Test
    func liveKitDoesNotRequestTokenOrConnectBeforeE2EEReady() async {
        let tokenProvider = MediaTokenProviderSpy()
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(tokenProvider: tokenProvider, liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .pending)
        
        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))
        
        #expect(result == .failure(.e2eeNotReady))
        #expect(tokenProvider.requestedSessions.isEmpty)
        #expect(liveKitClient.connectionInfos.isEmpty)
        #expect(engine.mediaStatePublisher.value.canPlayRemoteAudio == false)
    }
    
    @Test
    func liveKitDoesNotRequestTokenOrConnectOnKeyMismatch() async {
        let tokenProvider = MediaTokenProviderSpy()
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(tokenProvider: tokenProvider, liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)
        
        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: "other-call", keyID: "key-a"))
        
        #expect(result == .failure(.keyMismatch))
        #expect(tokenProvider.requestedSessions.isEmpty)
        #expect(liveKitClient.connectionInfos.isEmpty)
    }
    
    @Test
    func liveKitRequestsTokenAndConnectsOnlyAfterE2EEValidationPasses() async {
        let tokenProvider = MediaTokenProviderSpy()
        let liveKitClient = LiveKitClientSpy()
        let routeController = AudioRouteControllerSpy()
        let engine = makeLiveKitEngine(tokenProvider: tokenProvider,
                                       audioRouteController: routeController,
                                       liveKitClient: liveKitClient)
        let session = makeSession(encryptionState: .ready)
        
        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))
        
        #expect(tokenProvider.requestedSessions == [session])
        #expect(routeController.configuredDefaultRoutes == [callID])
        #expect(liveKitClient.connectionInfos.map(\.roomName) == ["direct-call"])
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
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(tokenProvider: tokenProvider, liveKitClient: liveKitClient)
        let session = makeSession(intent: .video, encryptionState: .ready)
        
        let result = await engine.connectAudio(for: session, keyHandle: .init(callID: callID, keyID: "key-a"))
        
        #expect(result == .failure(.unsupportedIntent))
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
        let liveKitClient = LiveKitClientSpy()
        let engine = makeLiveKitEngine(audioRouteController: routeController,
                                       encryptionService: encryptionService,
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
        #expect(engine.mediaStatePublisher.value == .idle)
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
                                   liveKitClient: DirectCallLiveKitClientProtocol? = nil) -> LiveKitDirectCallMediaEngine {
        LiveKitDirectCallMediaEngine(tokenProvider: tokenProvider ?? MediaTokenProviderSpy(),
                                     audioRouteController: audioRouteController,
                                     encryptionService: encryptionService,
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
}

@MainActor
private final class MediaTokenProviderSpy: DirectCallMediaTokenProviderProtocol {
    private(set) var requestedSessions = [DirectCallSession]()
    var result: Result<DirectCallMediaConnectionInfo, DirectCallMediaError>

    init(result: Result<DirectCallMediaConnectionInfo, DirectCallMediaError> = .success(.init(serverURL: URL(fileURLWithPath: "/tmp/livekit.example.com"),
                                                                                              roomName: "direct-call",
                                                                                              token: "test-token"))) {
        self.result = result
    }

    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
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
private final class LiveKitClientSpy: DirectCallLiveKitClientProtocol {
    private(set) var connectionInfos = [DirectCallMediaConnectionInfo]()
    private(set) var microphoneValues = [Bool]()
    private(set) var disconnectCount = 0
    private(set) var cleanupCount = 0
    
    var connectResult: Result<Void, DirectCallMediaError>
    var microphoneResult: Result<Void, DirectCallMediaError>
    
    init(connectResult: Result<Void, DirectCallMediaError> = .success(()),
         microphoneResult: Result<Void, DirectCallMediaError> = .success(())) {
        self.connectResult = connectResult
        self.microphoneResult = microphoneResult
    }
    
    func connect(connectionInfo: DirectCallMediaConnectionInfo) async -> Result<Void, DirectCallMediaError> {
        connectionInfos.append(connectionInfo)
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
