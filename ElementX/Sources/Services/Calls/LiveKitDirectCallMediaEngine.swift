//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
final class LiveKitDirectCallMediaEngine: DirectCallMediaEngineProtocol {
    private let mediaStateSubject = CurrentValueSubject<DirectCallMediaState, Never>(.idle)
    private let audioRouteController: DirectCallAudioRouteControllerProtocol
    private let encryptionService: DirectCallEncryptionServiceProtocol
    private var clearedCallIDs = Set<String>()

    var mediaStatePublisher: CurrentValuePublisher<DirectCallMediaState, Never> {
        mediaStateSubject.asCurrentValuePublisher()
    }

    init(audioRouteController: DirectCallAudioRouteControllerProtocol? = nil,
         encryptionService: DirectCallEncryptionServiceProtocol? = nil) {
        self.audioRouteController = audioRouteController ?? NoOpDirectCallAudioRouteController()
        self.encryptionService = encryptionService ?? NoOpDirectCallEncryptionService()
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
        if let error = session.directAudioConnectionError(keyHandle: keyHandle) {
            return fail(callID: session.callID, error: error)
        }

        return fail(callID: session.callID, error: .mediaSetupUnavailable)
    }

    func setMicrophoneEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        fail(callID: callID, error: .mediaSetupUnavailable)
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
        guard !callID.isEmpty else {
            return
        }

        audioRouteController.deactivateAudioSession()
        clearPerCallKeyIfNeeded(callID: callID)

        if mediaStateSubject.value.callID == callID {
            mediaStateSubject.send(DirectCallMediaState(callID: callID,
                                                        phase: .disconnected,
                                                        isMicrophoneEnabled: false,
                                                        isSpeakerEnabled: false,
                                                        isE2EEReady: false))
        }
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
