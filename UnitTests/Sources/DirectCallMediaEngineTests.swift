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

        #expect(result == .failure(.mediaSetupUnavailable))
        #expect(engine.mediaStatePublisher.value.canPublishMicrophone == false)
        #expect(engine.mediaStatePublisher.value.canPlayRemoteAudio == false)
    }

    private func makeEngine(tokenProvider: DirectCallMediaTokenProviderProtocol? = nil,
                            audioRouteController: DirectCallAudioRouteControllerProtocol? = nil,
                            encryptionService: DirectCallEncryptionServiceProtocol? = nil) -> NoOpDirectCallMediaEngine {
        NoOpDirectCallMediaEngine(tokenProvider: tokenProvider,
                                  audioRouteController: audioRouteController,
                                  encryptionService: encryptionService)
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
