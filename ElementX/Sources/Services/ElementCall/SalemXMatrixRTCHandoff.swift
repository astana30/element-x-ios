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
    case roomAmbiguous
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
        case .roomAmbiguous:
            "roomAmbiguous"
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

enum VerifiedIncomingCallBootstrapActiveCallState: Equatable {
    case active
    case unavailable
    case none
}

struct VerifiedIncomingCallBootstrap: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let callID: UUID
    let claimedMetadata: SalemXMatrixRTCClaimedMetadata
    let localDeviceID: String
    let activeCallState: VerifiedIncomingCallBootstrapActiveCallState

    var description: String {
        "VerifiedIncomingCallBootstrap(callID: <redacted>, claimedMetadata: \(claimedMetadata), localDeviceID: <redacted>, activeCallState: \(activeCallState))"
    }

    var debugDescription: String {
        description
    }
}

protocol SalemXIncomingCallBootstrapResolving: AnyObject {
    func verifiedBootstrap(for callID: UUID) -> VerifiedIncomingCallBootstrap?
    func removeVerifiedBootstrap(for callID: UUID)
}

final class SalemXIncomingCallBootstrapStore: SalemXIncomingCallBootstrapResolving {
    private var bootstrapsByCallID = [UUID: VerifiedIncomingCallBootstrap]()

    func store(_ bootstrap: VerifiedIncomingCallBootstrap) {
        bootstrapsByCallID[bootstrap.callID] = bootstrap
    }

    func verifiedBootstrap(for callID: UUID) -> VerifiedIncomingCallBootstrap? {
        bootstrapsByCallID[callID]
    }

    func removeVerifiedBootstrap(for callID: UUID) {
        bootstrapsByCallID.removeValue(forKey: callID)
    }
}

enum SalemXEmbeddedCallAnswerResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case presentationAccepted
    case alreadyPresented
    case noAuthenticatedSession
    case sessionIdentityMismatch
    case sessionDeviceMismatch
    case dmRoomNotFound
    case dmRoomAmbiguous
    case dmRoomInvalid
    case noActiveMatrixRTCCall
    case activeCallStateUnavailable
    case unsupportedIncomingJoin
    case bootstrapUnavailable
    case bootstrapMismatch
    case timedOut
    case cancelled
    case failed

    var isCallKitSuccess: Bool {
        switch self {
        case .presentationAccepted, .alreadyPresented:
            true
        case .noAuthenticatedSession,
             .sessionIdentityMismatch,
             .sessionDeviceMismatch,
             .dmRoomNotFound,
             .dmRoomAmbiguous,
             .dmRoomInvalid,
             .noActiveMatrixRTCCall,
             .activeCallStateUnavailable,
             .unsupportedIncomingJoin,
             .bootstrapUnavailable,
             .bootstrapMismatch,
             .timedOut,
             .cancelled,
             .failed:
            false
        }
    }

    var description: String {
        switch self {
        case .presentationAccepted:
            "presentationAccepted"
        case .alreadyPresented:
            "alreadyPresented"
        case .noAuthenticatedSession:
            "noAuthenticatedSession"
        case .sessionIdentityMismatch:
            "sessionIdentityMismatch"
        case .sessionDeviceMismatch:
            "sessionDeviceMismatch"
        case .dmRoomNotFound:
            "dmRoomNotFound"
        case .dmRoomAmbiguous:
            "dmRoomAmbiguous"
        case .dmRoomInvalid:
            "dmRoomInvalid"
        case .noActiveMatrixRTCCall:
            "noActiveMatrixRTCCall"
        case .activeCallStateUnavailable:
            "activeCallStateUnavailable"
        case .unsupportedIncomingJoin:
            "unsupportedIncomingJoin"
        case .bootstrapUnavailable:
            "bootstrapUnavailable"
        case .bootstrapMismatch:
            "bootstrapMismatch"
        case .timedOut:
            "timedOut"
        case .cancelled:
            "cancelled"
        case .failed:
            "failed"
        }
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol SalemXEmbeddedCallAnswerBridging {
    func answer(callID: UUID, bootstrap: VerifiedIncomingCallBootstrap) async -> SalemXEmbeddedCallAnswerResult
}

@MainActor
final class SalemXEmbeddedCallAnswerBridge: SalemXEmbeddedCallAnswerBridging {
    private let clientProxy: ClientProxyProtocol
    private let matrixRTCHandoff: SalemXMatrixRTCHandoff

    init(clientProxy: ClientProxyProtocol, matrixRTCHandoff: SalemXMatrixRTCHandoff) {
        self.clientProxy = clientProxy
        self.matrixRTCHandoff = matrixRTCHandoff
    }

    func answer(callID: UUID, bootstrap: VerifiedIncomingCallBootstrap) async -> SalemXEmbeddedCallAnswerResult {
        guard bootstrap.callID == callID else {
            return .bootstrapMismatch
        }

        guard let localUserID = Self.normalized(clientProxy.userID) else {
            return .noAuthenticatedSession
        }

        guard localUserID == Self.normalized(bootstrap.claimedMetadata.localUserID) else {
            return .sessionIdentityMismatch
        }

        guard let sessionDeviceID = Self.normalized(clientProxy.deviceID),
              sessionDeviceID == Self.normalized(bootstrap.localDeviceID) else {
            return .sessionDeviceMismatch
        }

        switch bootstrap.activeCallState {
        case .active:
            break
        case .unavailable:
            return .activeCallStateUnavailable
        case .none:
            return .noActiveMatrixRTCCall
        }

        let result = await matrixRTCHandoff.prepareAudioCall(claimedMetadata: bootstrap.claimedMetadata,
                                                             intent: .presentExisting)
        return Self.answerResult(from: result)
    }

    private static func answerResult(from handoffResult: SalemXMatrixRTCHandoffResult) -> SalemXEmbeddedCallAnswerResult {
        switch handoffResult {
        case .handedOff(.readyToPresent):
            return .presentationAccepted
        case .handedOff(.alreadyPresented):
            return .alreadyPresented
        case .handedOff(.noExistingCall):
            return .noActiveMatrixRTCCall
        case .handedOff(.unsupportedIncomingJoin):
            return .unsupportedIncomingJoin
        case .blocked(let reason):
            return answerResult(from: reason)
        }
    }

    private static func answerResult(from blockedReason: SalemXMatrixRTCHandoffBlockedReason) -> SalemXEmbeddedCallAnswerResult {
        switch blockedReason {
        case .malformedClaimedMetadata:
            return .bootstrapMismatch
        case .unauthenticatedSession:
            return .noAuthenticatedSession
        case .authenticatedUserMismatch:
            return .sessionIdentityMismatch
        case .roomNotJoined:
            return .dmRoomNotFound
        case .roomAmbiguous:
            return .dmRoomAmbiguous
        case .roomIDMismatch, .roomNotDirectOneToOne, .localUserNotMember, .peerUserNotMember:
            return .dmRoomInvalid
        }
    }

    private nonisolated static func normalized(_ value: String?) -> String? {
        let normalizedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue?.isEmpty == false ? normalizedValue : nil
    }
}

enum SalemXEmbeddedCallEndSource: Equatable, CustomStringConvertible {
    case callKitLocalEnd
    case embeddedLocalEnd
    case embeddedRemoteEnd
    case presentationFailure
    case answerTimeout
    case systemReset

    var description: String {
        switch self {
        case .callKitLocalEnd:
            "callKitLocalEnd"
        case .embeddedLocalEnd:
            "embeddedLocalEnd"
        case .embeddedRemoteEnd:
            "embeddedRemoteEnd"
        case .presentationFailure:
            "presentationFailure"
        case .answerTimeout:
            "answerTimeout"
        case .systemReset:
            "systemReset"
        }
    }
}

enum SalemXEmbeddedCallEndResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case terminationAccepted
    case alreadyTerminated
    case noVerifiedBootstrap
    case bootstrapMismatch
    case noAuthenticatedSession
    case sessionIdentityMismatch
    case sessionDeviceMismatch
    case dmRoomUnavailable
    case noActiveMatrixRTCCall
    case terminationUnsupported
    case timedOut
    case cancelled
    case failed

    var isCallKitSuccess: Bool {
        switch self {
        case .terminationAccepted, .alreadyTerminated:
            true
        case .noVerifiedBootstrap,
             .bootstrapMismatch,
             .noAuthenticatedSession,
             .sessionIdentityMismatch,
             .sessionDeviceMismatch,
             .dmRoomUnavailable,
             .noActiveMatrixRTCCall,
             .terminationUnsupported,
             .timedOut,
             .cancelled,
             .failed:
            false
        }
    }

    var description: String {
        switch self {
        case .terminationAccepted:
            "terminationAccepted"
        case .alreadyTerminated:
            "alreadyTerminated"
        case .noVerifiedBootstrap:
            "noVerifiedBootstrap"
        case .bootstrapMismatch:
            "bootstrapMismatch"
        case .noAuthenticatedSession:
            "noAuthenticatedSession"
        case .sessionIdentityMismatch:
            "sessionIdentityMismatch"
        case .sessionDeviceMismatch:
            "sessionDeviceMismatch"
        case .dmRoomUnavailable:
            "dmRoomUnavailable"
        case .noActiveMatrixRTCCall:
            "noActiveMatrixRTCCall"
        case .terminationUnsupported:
            "terminationUnsupported"
        case .timedOut:
            "timedOut"
        case .cancelled:
            "cancelled"
        case .failed:
            "failed"
        }
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol SalemXEmbeddedCallEndBridging {
    func end(callID: UUID,
             bootstrap: VerifiedIncomingCallBootstrap,
             source: SalemXEmbeddedCallEndSource) async -> SalemXEmbeddedCallEndResult
}

@MainActor
final class SalemXEmbeddedCallEndBridge: SalemXEmbeddedCallEndBridging {
    private let clientProxy: ClientProxyProtocol
    private let embeddedElementCallTerminator: any EmbeddedElementCallTerminating

    init(clientProxy: ClientProxyProtocol,
         embeddedElementCallTerminator: any EmbeddedElementCallTerminating) {
        self.clientProxy = clientProxy
        self.embeddedElementCallTerminator = embeddedElementCallTerminator
    }

    func end(callID: UUID,
             bootstrap: VerifiedIncomingCallBootstrap,
             source _: SalemXEmbeddedCallEndSource) async -> SalemXEmbeddedCallEndResult {
        guard bootstrap.callID == callID else {
            return .bootstrapMismatch
        }

        guard let localUserID = Self.normalized(clientProxy.userID) else {
            return .noAuthenticatedSession
        }

        guard localUserID == Self.normalized(bootstrap.claimedMetadata.localUserID) else {
            return .sessionIdentityMismatch
        }

        guard let sessionDeviceID = Self.normalized(clientProxy.deviceID),
              sessionDeviceID == Self.normalized(bootstrap.localDeviceID) else {
            return .sessionDeviceMismatch
        }

        switch bootstrap.activeCallState {
        case .active:
            break
        case .unavailable, .none:
            return .noActiveMatrixRTCCall
        }

        let result = await embeddedElementCallTerminator.terminateEmbeddedElementCall(roomID: bootstrap.claimedMetadata.roomID)
        return Self.endResult(from: result)
    }

    private static func endResult(from terminationResult: EmbeddedElementCallTerminationResult) -> SalemXEmbeddedCallEndResult {
        switch terminationResult {
        case .accepted:
            .terminationAccepted
        case .alreadyTerminated:
            .alreadyTerminated
        case .roomUnavailable:
            .dmRoomUnavailable
        case .noActiveCall:
            .noActiveMatrixRTCCall
        case .unsupported:
            .terminationUnsupported
        case .failed:
            .failed
        }
    }

    private nonisolated static func normalized(_ value: String?) -> String? {
        let normalizedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedValue?.isEmpty == false ? normalizedValue : nil
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

    private nonisolated static func normalized(_ value: String) -> String? {
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
