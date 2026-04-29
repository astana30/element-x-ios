//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
final class NoOpDirectCallMediaEngine: DirectCallMediaEngineProtocol {
    private let mediaStateSubject = CurrentValueSubject<DirectCallMediaState, Never>(.idle)
    private let tokenProvider: DirectCallMediaTokenProviderProtocol
    private let audioRouteController: DirectCallAudioRouteControllerProtocol
    private let encryptionService: DirectCallEncryptionServiceProtocol
    private var clearedCallIDs = Set<String>()
    private var disconnectedCallIDs = Set<String>()

    var mediaStatePublisher: CurrentValuePublisher<DirectCallMediaState, Never> {
        mediaStateSubject.asCurrentValuePublisher()
    }

    init(tokenProvider: DirectCallMediaTokenProviderProtocol? = nil,
         audioRouteController: DirectCallAudioRouteControllerProtocol? = nil,
         encryptionService: DirectCallEncryptionServiceProtocol? = nil) {
        self.tokenProvider = tokenProvider ?? NoOpDirectCallMediaTokenProvider()
        self.audioRouteController = audioRouteController ?? NoOpDirectCallAudioRouteController()
        self.encryptionService = encryptionService ?? NoOpDirectCallEncryptionService()
    }

    func prepareAudioSession(for session: DirectCallSession) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        guard session.isValidForDirectAudioPreparation else {
            return fail(callID: session.callID, error: session.intent == .audio ? .invalidSession : .unsupportedIntent)
        }

        switch audioRouteController.configureDefaultAudioRoute(for: session) {
        case .success:
            let state = DirectCallMediaState(callID: session.callID,
                                             phase: .preparingAudio,
                                             isMicrophoneEnabled: false,
                                             isSpeakerEnabled: false,
                                             isE2EEReady: session.encryptionState == .ready)
            mediaStateSubject.send(state)
            return .success(state)
        case .failure:
            return fail(callID: session.callID, error: .audioRouteFailed)
        }
    }

    func connectAudio(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        if let error = session.directAudioConnectionError(keyHandle: keyHandle) {
            return fail(callID: session.callID, error: error)
        }

        guard case .success = audioRouteController.configureDefaultAudioRoute(for: session) else {
            return fail(callID: session.callID, error: .audioRouteFailed)
        }

        let connectingState = DirectCallMediaState(callID: session.callID,
                                                   phase: .connectingAudio,
                                                   isMicrophoneEnabled: false,
                                                   isSpeakerEnabled: mediaStateSubject.value.isSpeakerEnabled,
                                                   isE2EEReady: true)
        mediaStateSubject.send(connectingState)

        switch await tokenProvider.connectionInfo(for: session) {
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
    }

    func setMicrophoneEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        var state = mediaStateSubject.value
        guard state.callID == callID else {
            return fail(callID: callID, error: .invalidSession)
        }

        guard state.canPublishMicrophone else {
            return fail(callID: callID, error: .e2eeNotReady)
        }

        state.isMicrophoneEnabled = isEnabled
        mediaStateSubject.send(state)
        return .success(state)
    }

    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        let state = mediaStateSubject.value
        guard isEnabled else {
            return .success(state)
        }

        guard state.callID == callID else {
            return fail(callID: callID, error: .invalidSession)
        }

        guard state.canPlayRemoteAudio else {
            return fail(callID: callID, error: .e2eeNotReady)
        }

        return .success(state)
    }

    func setSpeakerEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        var state = mediaStateSubject.value
        guard state.callID == callID else {
            return fail(callID: callID, error: .invalidSession)
        }

        switch audioRouteController.setSpeakerEnabled(isEnabled) {
        case .success:
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
        guard state.callID == callID else {
            clearPerCallKeyIfNeeded(callID: callID)
            disconnectedCallIDs.insert(callID)
            return
        }

        state.phase = .disconnecting
        state.isMicrophoneEnabled = false
        mediaStateSubject.send(state)

        audioRouteController.deactivateAudioSession()
        clearPerCallKeyIfNeeded(callID: callID)
        disconnectedCallIDs.insert(callID)

        state.phase = .disconnected
        state.isE2EEReady = false
        mediaStateSubject.send(state)
    }

    func cleanup(callID: String) async {
        await disconnect(callID: callID)
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
