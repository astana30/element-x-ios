//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum SalemXMatrixRTCHandoffDirection: Equatable, CustomStringConvertible {
    case incoming
    case outgoing

    var description: String {
        switch self {
        case .incoming:
            "incoming"
        case .outgoing:
            "outgoing"
        }
    }
}

struct SalemXMatrixRTCClaimedMetadata: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let roomID: String
    let localUserID: String
    let peerUserID: String
    let peerDeviceID: String
    let direction: SalemXMatrixRTCHandoffDirection

    var description: String {
        "SalemXMatrixRTCClaimedMetadata(roomID: <redacted>, localUserID: <redacted>, peerUserID: <redacted>, peerDeviceID: <redacted>, direction: \(direction))"
    }

    var debugDescription: String {
        description
    }
}

enum SalemXMatrixRTCHandoffBlockedReason: Equatable, CustomStringConvertible {
    case malformedClaimedMetadata
    case unauthenticatedSession
    case authenticatedUserMismatch
    case roomNotJoined
    case roomIDMismatch
    case roomNotDirectOneToOne
    case localUserNotMember
    case peerUserNotMember

    var description: String {
        switch self {
        case .malformedClaimedMetadata:
            "malformedClaimedMetadata"
        case .unauthenticatedSession:
            "unauthenticatedSession"
        case .authenticatedUserMismatch:
            "authenticatedUserMismatch"
        case .roomNotJoined:
            "roomNotJoined"
        case .roomIDMismatch:
            "roomIDMismatch"
        case .roomNotDirectOneToOne:
            "roomNotDirectOneToOne"
        case .localUserNotMember:
            "localUserNotMember"
        case .peerUserNotMember:
            "peerUserNotMember"
        }
    }
}

enum SalemXMatrixRTCHandoffResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case handedOff(EmbeddedElementCallHandoffResult)
    case blocked(SalemXMatrixRTCHandoffBlockedReason)

    var description: String {
        switch self {
        case .handedOff(let result):
            "SalemXMatrixRTCHandoffResult(handedOff: \(result.salemXRedactedDescription))"
        case .blocked(let reason):
            "SalemXMatrixRTCHandoffResult(blocked: \(reason))"
        }
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol SalemXMatrixRTCHandoff {
    func prepareAudioCall(claimedMetadata: SalemXMatrixRTCClaimedMetadata,
                          intent: EmbeddedElementCallHandoffIntent) async -> SalemXMatrixRTCHandoffResult
}

@MainActor
final class SalemXAuthenticatedMatrixRTCHandoff: SalemXMatrixRTCHandoff {
    private let clientProxy: ClientProxyProtocol
    private let elementCallHandoff: EmbeddedElementCallHandoff

    init(clientProxy: ClientProxyProtocol,
         elementCallHandoff: EmbeddedElementCallHandoff) {
        self.clientProxy = clientProxy
        self.elementCallHandoff = elementCallHandoff
    }

    func prepareAudioCall(claimedMetadata: SalemXMatrixRTCClaimedMetadata,
                          intent: EmbeddedElementCallHandoffIntent) async -> SalemXMatrixRTCHandoffResult {
        guard let metadata = NormalizedClaimedMetadata(claimedMetadata) else {
            return .blocked(.malformedClaimedMetadata)
        }

        guard let authenticatedUserID = Self.normalized(clientProxy.userID) else {
            return .blocked(.unauthenticatedSession)
        }

        guard authenticatedUserID == metadata.localUserID else {
            return .blocked(.authenticatedUserMismatch)
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(metadata.roomID) else {
            return .blocked(.roomNotJoined)
        }

        guard roomProxy.id == metadata.roomID else {
            return .blocked(.roomIDMismatch)
        }

        guard roomProxy.isDirectOneToOneRoom else {
            return .blocked(.roomNotDirectOneToOne)
        }

        guard await hasMember(metadata.localUserID, in: roomProxy) else {
            return .blocked(.localUserNotMember)
        }

        guard await hasMember(metadata.peerUserID, in: roomProxy) else {
            return .blocked(.peerUserNotMember)
        }

        let handoffResult = await elementCallHandoff.prepareAudioCall(roomID: metadata.roomID, intent: intent)
        return .handedOff(handoffResult)
    }

    private func hasMember(_ userID: String, in roomProxy: JoinedRoomProxyProtocol) async -> Bool {
        guard case .success = await roomProxy.getMember(userID: userID) else {
            return false
        }

        return true
    }

    private struct NormalizedClaimedMetadata {
        let roomID: String
        let localUserID: String
        let peerUserID: String

        init?(_ metadata: SalemXMatrixRTCClaimedMetadata) {
            guard let roomID = SalemXAuthenticatedMatrixRTCHandoff.normalized(metadata.roomID),
                  let localUserID = SalemXAuthenticatedMatrixRTCHandoff.normalized(metadata.localUserID),
                  let peerUserID = SalemXAuthenticatedMatrixRTCHandoff.normalized(metadata.peerUserID),
                  SalemXAuthenticatedMatrixRTCHandoff.normalized(metadata.peerDeviceID) != nil,
                  localUserID != peerUserID else {
                return nil
            }

            self.roomID = roomID
            self.localUserID = localUserID
            self.peerUserID = peerUserID
        }
    }

    private static func normalized(_ value: String) -> String? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }
}

private extension EmbeddedElementCallHandoffResult {
    var salemXRedactedDescription: String {
        switch self {
        case .readyToPresent:
            "readyToPresent"
        case .alreadyPresented:
            "alreadyPresented"
        case .noExistingCall:
            "noExistingCall"
        case .unsupportedIncomingJoin:
            "unsupportedIncomingJoin"
        }
    }
}
