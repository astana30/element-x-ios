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
        "DirectCallMediaConnectionInfo(serverURL: <redacted>, roomName: <redacted>, token: <redacted>)"
    }
}

extension DirectCallMediaConnectionInfo {
    var diagnosticServerURLHash: String {
        DirectCallDiagnosticRedactor.roomFingerprint(serverURL.absoluteString) ?? "missing_redacted"
    }

    var diagnosticRoomNameHash: String {
        DirectCallDiagnosticRedactor.roomFingerprint(roomName) ?? "missing_redacted"
    }

    var diagnosticTokenRoomGrantHash: String {
        guard let roomGrant = decodedLiveKitTokenPayload?.videoRoomGrant else {
            return "missing_redacted"
        }
        return DirectCallDiagnosticRedactor.roomFingerprint(roomGrant) ?? "missing_redacted"
    }

    var diagnosticTokenIdentityHash: String {
        guard let identity = decodedLiveKitTokenPayload?.identity else {
            return "missing_redacted"
        }
        return DirectCallDiagnosticRedactor.roomFingerprint(identity) ?? "missing_redacted"
    }

    private var decodedLiveKitTokenPayload: LiveKitTokenDiagnosticPayload? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else {
            return nil
        }

        var encodedPayload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encodedPayload.count % 4 != 0 {
            encodedPayload.append("=")
        }

        guard let data = Data(base64Encoded: encodedPayload),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let video = payload["video"] as? [String: Any]
        let roomGrant = video?["room"] as? String
        let identity = (payload["sub"] as? String) ?? (payload["identity"] as? String)
        return LiveKitTokenDiagnosticPayload(videoRoomGrant: roomGrant, identity: identity)
    }

    private struct LiveKitTokenDiagnosticPayload {
        let videoRoomGrant: String?
        let identity: String?
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
