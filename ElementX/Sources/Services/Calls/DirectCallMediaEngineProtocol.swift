//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
protocol DirectCallMediaEngineProtocol {
    var mediaStatePublisher: CurrentValuePublisher<DirectCallMediaState, Never> { get }

    func prepareAudioSession(for session: DirectCallSession) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func connectAudio(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func setMicrophoneEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func setSpeakerEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func disconnect(callID: String) async
    func cleanup(callID: String) async
}

@MainActor
protocol DirectCallMediaTokenProviderProtocol {
    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError>
}

@MainActor
protocol DirectCallAudioRouteControllerProtocol {
    func configureDefaultAudioRoute(for session: DirectCallSession) -> Result<DirectCallAudioRoute, DirectCallMediaError>
    func setSpeakerEnabled(_ isEnabled: Bool) -> Result<DirectCallAudioRoute, DirectCallMediaError>
    func deactivateAudioSession()
}

@MainActor
final class NoOpDirectCallMediaTokenProvider: DirectCallMediaTokenProviderProtocol {
    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        .failure(.tokenUnavailable)
    }
}

@MainActor
final class NoOpDirectCallAudioRouteController: DirectCallAudioRouteControllerProtocol {
    private(set) var currentRoute: DirectCallAudioRoute = .systemDefault

    func configureDefaultAudioRoute(for session: DirectCallSession) -> Result<DirectCallAudioRoute, DirectCallMediaError> {
        guard session.intent == .audio else {
            return .failure(.unsupportedIntent)
        }

        currentRoute = .earpiece
        return .success(currentRoute)
    }

    func setSpeakerEnabled(_ isEnabled: Bool) -> Result<DirectCallAudioRoute, DirectCallMediaError> {
        currentRoute = isEnabled ? .speaker : .earpiece
        return .success(currentRoute)
    }

    func deactivateAudioSession() {
        currentRoute = .systemDefault
    }
}
