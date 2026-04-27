//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
protocol DirectCallLiveKitClientProtocol {
    func connect(connectionInfo: DirectCallMediaConnectionInfo) async -> Result<Void, DirectCallMediaError>
    func setMicrophoneEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError>
    func disconnect() async
    func cleanup() async
}

@MainActor
final class UnavailableDirectCallLiveKitClient: DirectCallLiveKitClientProtocol {
    func connect(connectionInfo: DirectCallMediaConnectionInfo) async -> Result<Void, DirectCallMediaError> {
        .failure(.mediaSetupUnavailable)
    }
    
    func setMicrophoneEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        .failure(.mediaSetupUnavailable)
    }
    
    func disconnect() async { }
    
    func cleanup() async { }
}

@MainActor
final class LiveKitDirectCallMediaEngine: DirectCallMediaEngineProtocol {
    private let mediaStateSubject = CurrentValueSubject<DirectCallMediaState, Never>(.idle)
    private let tokenProvider: DirectCallMediaTokenProviderProtocol
    private let audioRouteController: DirectCallAudioRouteControllerProtocol
    private let encryptionService: DirectCallEncryptionServiceProtocol
    private let liveKitClient: DirectCallLiveKitClientProtocol
    private var clearedCallIDs = Set<String>()
    private var disconnectedCallIDs = Set<String>()
    private var cleanedCallIDs = Set<String>()

    var mediaStatePublisher: CurrentValuePublisher<DirectCallMediaState, Never> {
        mediaStateSubject.asCurrentValuePublisher()
    }

    init(tokenProvider: DirectCallMediaTokenProviderProtocol? = nil,
         audioRouteController: DirectCallAudioRouteControllerProtocol? = nil,
         encryptionService: DirectCallEncryptionServiceProtocol? = nil,
         liveKitClient: DirectCallLiveKitClientProtocol? = nil) {
        self.tokenProvider = tokenProvider ?? NoOpDirectCallMediaTokenProvider()
        self.audioRouteController = audioRouteController ?? NoOpDirectCallAudioRouteController()
        self.encryptionService = encryptionService ?? NoOpDirectCallEncryptionService()
        self.liveKitClient = liveKitClient ?? UnavailableDirectCallLiveKitClient()
    }

    func prepareAudioSession(for session: DirectCallSession) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        guard session.isValidForDirectAudioPreparation else {
            return fail(callID: session.callID, error: session.intent == .audio ? .invalidSession : .unsupportedIntent)
        }

        guard case .success = audioRouteController.configureDefaultAudioRoute(for: session) else {
            return fail(callID: session.callID, error: .audioRouteFailed)
        }

        let state = DirectCallMediaState(callID: session.callID,
                                         phase: .preparingAudio,
                                         isMicrophoneEnabled: false,
                                         isSpeakerEnabled: false,
                                         isE2EEReady: session.encryptionState == .ready)
        mediaStateSubject.send(state)
        return .success(state)
    }

    func connectAudio(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        let preparingState = DirectCallMediaState(callID: session.callID,
                                                  phase: .preparingAudio,
                                                  isMicrophoneEnabled: false,
                                                  isSpeakerEnabled: mediaStateSubject.value.isSpeakerEnabled,
                                                  isE2EEReady: false)
        mediaStateSubject.send(preparingState)

        if let error = session.directAudioConnectionError(keyHandle: keyHandle) {
            return fail(callID: session.callID, error: error)
        }

        switch await tokenProvider.connectionInfo(for: session) {
        case .success(let connectionInfo):
            guard case .success = audioRouteController.configureDefaultAudioRoute(for: session) else {
                return fail(callID: session.callID, error: .audioRouteFailed)
            }

            let connectingState = DirectCallMediaState(callID: session.callID,
                                                       phase: .connectingAudio,
                                                       isMicrophoneEnabled: false,
                                                       isSpeakerEnabled: mediaStateSubject.value.isSpeakerEnabled,
                                                       isE2EEReady: true)
            mediaStateSubject.send(connectingState)

            switch await liveKitClient.connect(connectionInfo: connectionInfo) {
            case .success:
                let activeState = DirectCallMediaState(callID: session.callID,
                                                       phase: .activeAudio,
                                                       isMicrophoneEnabled: false,
                                                       isSpeakerEnabled: connectingState.isSpeakerEnabled,
                                                       isE2EEReady: true)
                disconnectedCallIDs.remove(session.callID)
                mediaStateSubject.send(activeState)
                return .success(activeState)
            case .failure(let error):
                return fail(callID: session.callID, error: error)
            }
        case .failure(let error):
            return fail(callID: session.callID, error: error)
        }
    }

    func setMicrophoneEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        var state = mediaStateSubject.value
        guard state.callID == callID else {
            return fail(callID: callID, error: .invalidSession)
        }

        if isEnabled {
            guard state.canPublishMicrophone else {
                return fail(callID: callID, error: .e2eeNotReady)
            }
        }

        switch await liveKitClient.setMicrophoneEnabled(isEnabled) {
        case .success:
            state.isMicrophoneEnabled = isEnabled
            mediaStateSubject.send(state)
            return .success(state)
        case .failure(let error):
            return fail(callID: callID, error: error)
        }
    }

    func setSpeakerEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        switch audioRouteController.setSpeakerEnabled(isEnabled) {
        case .success:
            var state = mediaStateSubject.value
            state.isSpeakerEnabled = isEnabled
            mediaStateSubject.send(state)
            return .success(state)
        case .failure:
            return fail(callID: callID, error: .audioRouteFailed)
        }
    }

    func disconnect(callID: String) async {
        guard !callID.isEmpty, !disconnectedCallIDs.contains(callID) else {
            return
        }

        var state = mediaStateSubject.value
        if state.callID == callID {
            state.phase = .disconnecting
            state.isMicrophoneEnabled = false
            mediaStateSubject.send(state)
        }

        _ = await liveKitClient.setMicrophoneEnabled(false)
        await liveKitClient.disconnect()
        audioRouteController.deactivateAudioSession()
        clearPerCallKeyIfNeeded(callID: callID)
        disconnectedCallIDs.insert(callID)

        if state.callID == callID {
            state.phase = .disconnected
            state.isSpeakerEnabled = false
            state.isE2EEReady = false
            mediaStateSubject.send(state)
        }
    }

    func cleanup(callID: String) async {
        await disconnect(callID: callID)
        if !callID.isEmpty, !cleanedCallIDs.contains(callID) {
            await liveKitClient.cleanup()
            cleanedCallIDs.insert(callID)
        }
        if mediaStateSubject.value.callID == callID {
            mediaStateSubject.send(.idle)
        }
    }

    private func fail(callID: String, error: DirectCallMediaError) -> Result<DirectCallMediaState, DirectCallMediaError> {
        let state = DirectCallMediaState(callID: callID.isEmpty ? nil : callID,
                                         phase: .failed(error),
                                         isMicrophoneEnabled: false,
                                         isSpeakerEnabled: mediaStateSubject.value.isSpeakerEnabled,
                                         isE2EEReady: false)
        mediaStateSubject.send(state)
        return .failure(error)
    }

    private func clearPerCallKeyIfNeeded(callID: String) {
        guard !callID.isEmpty, !clearedCallIDs.contains(callID) else {
            return
        }

        encryptionService.clearPerCallKey(callID: callID)
        clearedCallIDs.insert(callID)
    }
}
