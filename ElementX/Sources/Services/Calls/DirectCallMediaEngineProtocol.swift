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

#if DEBUG
@MainActor
protocol DirectCallMediaDiagnosticSnapshotProviding {
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot { get }
}
#endif

@MainActor
protocol DirectCallMediaTokenProviderProtocol {
    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError>
}

struct DirectCallLiveKitTokenRequest: Equatable {
    let callID: String
    let roomID: String
    let peerUserID: String
}

struct DirectCallLiveKitTokenResponse: Equatable, CustomStringConvertible {
    let serverURLString: String
    let roomName: String
    let token: String

    var description: String {
        "DirectCallLiveKitTokenResponse(serverURLString: <redacted>, roomName: \(roomName), token: <redacted>)"
    }
}

@MainActor
protocol DirectCallLiveKitTokenClientProtocol {
    func connection(for request: DirectCallLiveKitTokenRequest) async -> Result<DirectCallLiveKitTokenResponse, DirectCallMediaError>
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
final class UnavailableDirectCallLiveKitTokenClient: DirectCallLiveKitTokenClientProtocol {
    func connection(for request: DirectCallLiveKitTokenRequest) async -> Result<DirectCallLiveKitTokenResponse, DirectCallMediaError> {
        .failure(.tokenUnavailable)
    }
}

@MainActor
final class DirectCallLiveKitTokenProvider: DirectCallMediaTokenProviderProtocol {
    private let tokenClient: DirectCallLiveKitTokenClientProtocol

    init(tokenClient: DirectCallLiveKitTokenClientProtocol? = nil) {
        self.tokenClient = tokenClient ?? UnavailableDirectCallLiveKitTokenClient()
    }

    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        guard session.intent == .audio else {
            return .failure(.unsupportedIntent)
        }

        guard session.isValidForDirectAudioPreparation else {
            return .failure(.invalidSession)
        }

        guard session.encryptionState == .ready else {
            return .failure(.e2eeNotReady)
        }

        let request = DirectCallLiveKitTokenRequest(callID: session.callID,
                                                    roomID: session.roomID,
                                                    peerUserID: session.peerUserID)
        switch await tokenClient.connection(for: request) {
        case .success(let response):
            return Self.connectionInfo(from: response)
        case .failure:
            return .failure(.tokenUnavailable)
        }
    }

    private static func connectionInfo(from response: DirectCallLiveKitTokenResponse) -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        guard response.token.isEmpty == false,
              response.roomName.isEmpty == false,
              let serverURL = URL(string: response.serverURLString),
              let scheme = serverURL.scheme?.lowercased(),
              ["http", "https", "ws", "wss"].contains(scheme),
              serverURL.host?.isEmpty == false else {
            return .failure(.tokenUnavailable)
        }

        return .success(.init(serverURL: serverURL,
                              roomName: response.roomName,
                              token: response.token))
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
