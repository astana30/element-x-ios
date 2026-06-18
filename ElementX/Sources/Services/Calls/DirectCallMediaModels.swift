//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum DirectCallMediaPhase: Equatable {
    case idle
    case preparingAudio
    case connectingAudio
    case activeAudio
    case disconnecting
    case disconnected
    case failed(DirectCallMediaError)
}

enum DirectCallMediaError: Error, Equatable {
    case invalidSession
    case unsupportedIntent
    case e2eeNotReady
    case keyMismatch
    case e2eeContextUnavailable
    case tokenUnavailable
    case tokenEndpointUnavailable
    case accessTokenUnavailable
    case tokenHTTPUnavailable
    case tokenBackendRejected
    case tokenResponseInvalid
    case audioRouteFailed
    case mediaSetupUnavailable
    case liveKitURLInvalid
    case liveKitURLUnreachable
    case liveKitTokenRejected
    case liveKitRoomJoinFailed
    case liveKitE2EEConfigFailed
    case liveKitNetworkFailed
    case liveKitSDKError
    case liveKitUnknown
}

enum DirectCallAudioRoute: Equatable {
    case earpiece
    case speaker
    case bluetooth
    case systemDefault
}

struct DirectCallMediaConnectionInfo: Equatable, CustomStringConvertible {
    let serverURL: URL
    let roomName: String
    let token: String
    var expiresAtPresent = false

    init(serverURL: URL, roomName: String, token: String, expiresAtPresent: Bool = false) {
        self.serverURL = serverURL
        self.roomName = roomName
        self.token = token
        self.expiresAtPresent = expiresAtPresent
    }

    var description: String {
        "DirectCallMediaConnectionInfo(serverURL: <redacted>, roomName: \(roomName), token: <redacted>)"
    }
}

struct DirectCallMediaState: Equatable {
    var callID: String?
    var phase: DirectCallMediaPhase
    var isMicrophoneEnabled: Bool
    var isSpeakerEnabled: Bool
    var isE2EEReady: Bool

    static let idle = DirectCallMediaState(callID: nil,
                                           phase: .idle,
                                           isMicrophoneEnabled: false,
                                           isSpeakerEnabled: false,
                                           isE2EEReady: false)

    var canPublishMicrophone: Bool {
        phase == .activeAudio && isE2EEReady
    }

    var canPlayRemoteAudio: Bool {
        phase == .activeAudio && isE2EEReady
    }
}

extension DirectCallSession {
    var isValidForDirectAudioPreparation: Bool {
        !callID.isEmpty &&
            !roomID.isEmpty &&
            !peerUserID.isEmpty &&
            intent == .audio &&
            encryptionMode == .e2eeRequired &&
            !state.isTerminal
    }

    func directAudioConnectionError(keyHandle: DirectCallMediaKeyHandle) -> DirectCallMediaError? {
        guard isValidForDirectAudioPreparation else {
            return intent == .audio ? .invalidSession : .unsupportedIntent
        }

        guard encryptionState == .ready else {
            return .e2eeNotReady
        }

        guard keyHandle.callID == callID, !keyHandle.keyID.isEmpty else {
            return .keyMismatch
        }

        return nil
    }
}
