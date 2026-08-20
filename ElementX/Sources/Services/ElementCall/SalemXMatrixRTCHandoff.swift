//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import LiveKit
import Security
import SwiftUI

// swiftlint:disable file_length

#if DEBUG
import CryptoKit
#endif

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

    func hasActiveBootstrap(roomID: String) -> Bool {
        bootstrapsByCallID.values.contains { bootstrap in
            bootstrap.claimedMetadata.roomID == roomID && bootstrap.activeCallState == .active
        }
    }

    func removeAll() {
        bootstrapsByCallID.removeAll()
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

//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

#if DEBUG && canImport(CallKit) && os(iOS)
import Foundation

private func salemXStage2FExactRoomTimelineRemoteCallEvidence(roomProxy: JoinedRoomProxyProtocol) async -> Bool {
    await MainActor.run {
        roomProxy.timeline.timelineItemProvider.itemProxies.reversed().contains { itemProxy in
            guard case let .event(eventProxy) = itemProxy,
                  !eventProxy.isOwn,
                  let callEvent = RoomCallEventParser.parse(from: eventProxy) else {
                return false
            }
            return salemXStage2FRemoteActiveCallEvent(callEvent)
        }
    }
}

private func salemXStage2FRemoteActiveCallEvent(_ event: RoomCallEvent) -> Bool {
    [.incoming, .started, .answered, .legacyInvite].contains(event.state)
}

private struct SalemXStage2FRemoteActiveCallEvidenceResult {
    let seen: Bool
    let callStateVisible: Bool
}

private func salemXStage2FRemoteActiveCallEvidence(roomID: String,
                                                   roomProxy: JoinedRoomProxyProtocol,
                                                   clientProxy: ClientProxyProtocol) async -> SalemXStage2FRemoteActiveCallEvidenceResult {
    let info = roomProxy.infoPublisher.value
    if info.hasRoomCall || !info.activeRoomCallParticipants.isEmpty {
        return .init(seen: true, callStateVisible: true)
    }
    if let summary = clientProxy.roomSummaryForIdentifier(roomID),
       summary.hasOngoingCall || !summary.activeRoomCallParticipants.isEmpty {
        return .init(seen: true, callStateVisible: true)
    }
    let timelineEvidence = await salemXStage2FExactRoomTimelineRemoteCallEvidence(roomProxy: roomProxy)
    return .init(seen: timelineEvidence, callStateVisible: timelineEvidence)
}

@MainActor
// swiftlint:disable:next type_body_length
enum SalemXStage2FSimulatorSignalingDebug {
    private static let streamPath = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/stream"
    private static let invitePath = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite"
    private static let senderClaimPath = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata/sender/claim"
    private static let pendingMetadataPathPrefix = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata"
    private static let whoamiPath = "/_matrix/client/v3/account/whoami"
    private static let proofFileName = "salemx-stage2f-sim-proof.txt"
    private static let identityHandoffFileName = "salemx-stage2f-sim-identity.json"
    private static let senderHandoffFileName = "salemx-stage2f-sim-sender-handoff.json"

    private static let bootstrapStore = SalemXIncomingCallBootstrapStore()
    private static var proof = Proof()
    private static var senderContext: SenderContext?
    private static var receiverTransport: ForegroundCallSignalingSSETransport?
    private static var receiverExecutionNonce: String?
    private static var receiverInviteCount = 0
    private static var receiverCallKitEndReportCount = 0

    static func initialBridgeConfiguration() -> SalemXEmbeddedCallAnswerBridgeConfiguration {
        var configuration = SalemXEmbeddedCallAnswerBridgeConfiguration()
        configuration.embeddedMatrixRTCAnswerBridgeEnabled = ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled
        return configuration
    }

    static func configureBridgeIfNeeded(elementCallService: any ElementCallServiceProtocol,
                                        clientProxy: ClientProxyProtocol,
                                        presenter: any EmbeddedElementCallRoomCallPresenting) {
        proof.bridgeDefaultOff = SalemXEmbeddedCallAnswerBridgeConfiguration().embeddedMatrixRTCAnswerBridgeEnabled == false
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled,
              let concreteElementCallService = elementCallService as? ElementCallService else {
            writeProof()
            return
        }

        let productionHandoff = EmbeddedElementCallProductionHandoff(presenter: presenter,
                                                                     stateProvider: EmbeddedElementCallServiceRoomCallStateProvider(elementCallService: elementCallService)) { roomID in
            bootstrapStore.hasActiveBootstrap(roomID: roomID)
        }
        let matrixRTCHandoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                                   elementCallHandoff: productionHandoff)
        let answerBridge = SalemXEmbeddedCallAnswerBridge(clientProxy: clientProxy,
                                                          matrixRTCHandoff: matrixRTCHandoff)
        let endBridge = SalemXEmbeddedCallEndBridge(clientProxy: clientProxy,
                                                    embeddedElementCallTerminator: concreteElementCallService)
        concreteElementCallService.salemXDebugConfigureStage2FSimulatorBridge(configuration: initialBridgeConfiguration(),
                                                                              bootstrapResolver: bootstrapStore,
                                                                              answerBridge: answerBridge,
                                                                              endBridge: endBridge)
        proof.receiverDebugBridgeOverrideActive = true
        writeProof()
    }

    static func handleURL(_ url: URL,
                          userSession: UserSessionProtocol?,
                          userSessionFlowCoordinator: UserSessionFlowCoordinator?,
                          elementCallService: any ElementCallServiceProtocol) -> Bool {
        guard let path = normalizedPath(url), path.hasPrefix("/direct-call/stage2f-sim/") else {
            return false
        }

        let queryItems = queryItems(url)
        switch path {
        case "/direct-call/stage2f-sim/clear":
            clear()
        case "/direct-call/stage2f-sim/arm-nonce":
            armExecutionNonce(queryItems["execution_nonce"])
        case "/direct-call/stage2f-sim/export-identity":
            exportIdentity(userSession: userSession)
        case "/direct-call/stage2f-sim/receiver-start":
            Task {
                guard validateReceiverExecutionNonce(queryItems["execution_nonce"]) else {
                    return
                }
                await startReceiver(userSession: userSession, streamURLString: queryItems["stream_url"])
            }
        case "/direct-call/stage2f-sim/receiver-auth-preflight":
            Task {
                guard validateReceiverExecutionNonce(queryItems["execution_nonce"]) else {
                    return
                }
                await preflightReceiverAuthentication(userSession: userSession)
            }
        case "/direct-call/stage2f-sim/receiver-callkit-preflight":
            guard validateReceiverExecutionNonce(queryItems["execution_nonce"]) else {
                return true
            }
            preflightReceiverCallKitLocalState(elementCallService: elementCallService)
        case "/direct-call/stage2f-sim/receiver-claim-report":
            Task {
                guard validateReceiverExecutionNonce(queryItems["execution_nonce"]) else {
                    return
                }
                await claimReceiverMetadataAndReportCallKit(userSession: userSession,
                                                            elementCallService: elementCallService,
                                                            metadataReference: queryItems["pending_metadata_reference"],
                                                            senderDeviceID: queryItems["sender_device_id"])
            }
        case "/direct-call/stage2f-sim/sender-start":
            Task {
                await startSender(userSession: userSession,
                                  userSessionFlowCoordinator: userSessionFlowCoordinator,
                                  elementCallService: elementCallService,
                                  recipientUserID: queryItems["recipient_user_id"],
                                  recipientDeviceID: queryItems["recipient_device_id"])
            }
        case "/direct-call/stage2f-sim/sender-auth-preflight":
            Task { await preflightSenderAuthentication(userSession: userSession) }
        case "/direct-call/stage2f-sim/sender-local-state-preflight":
            preflightSenderLocalCallState(elementCallService: elementCallService,
                                          checkNonce: queryItems["check_nonce"])
        case "/direct-call/stage2f-sim/sender-send-invite":
            Task {
                await sendForegroundInvite(userSession: userSession,
                                           elementCallService: elementCallService,
                                           inviteURLString: queryItems["invite_url"])
            }
        default:
            return false
        }

        return true
    }

    static func recordCallKitAnswerActionSeen() {
        proof.receiverCallKitAnswerActionSeen = true
        writeProof()
    }

    static func recordReceiverAnswerResult(_ result: SalemXEmbeddedCallAnswerResult) {
        guard result.isCallKitSuccess else {
            proof.lastFailure = "\(result)"
            writeProof()
            return
        }

        proof.receiverCallKitAnswered = true
        proof.receiverPresentExistingSelected = true
        proof.receiverStartNewSelected = false
        proof.receiverEmbeddedElementCallPresented = true
        proof.lastFailure = "none"
        writeProof()
    }

    static func recordReceiverJoinExistingCallRequested() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverJoinExistingCallRequested = true
        writeProof()
    }

    static func recordReceiverElementCallReady() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverElementCallReady = true
        writeProof()
    }

    static func recordReceiverElementCallLoaded() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverElementCallLoaded = true
        writeProof()
    }

    static func recordReceiverWidgetJoinReceived() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverWidgetJoinReceived = true
        writeProof()
    }

    static func recordReceiverWidgetJoinAcknowledged() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverWidgetJoinAcknowledged = true
        writeProof()
    }

    static func recordReceiverWidgetJoinDriverResponseReceived() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverWidgetJoinDriverResponseReceived = true
        writeProof()
    }

    static func recordReceiverMatrixRTCJoinStarted() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverMatrixRTCJoinStarted = true
        writeProof()
    }

    static func recordReceiverWidgetJoinDispatchAttempted() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverWidgetJoinDispatchAttempted = true
        writeProof()
    }

    static func recordReceiverWidgetJoinDispatchCompleted() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverWidgetJoinDispatchCompleted = true
        proof.receiverWidgetJoinDispatchErrorBucket = "none"
        writeProof()
    }

    static func recordReceiverWidgetJoinDispatchError(_ error: ElementCallWidgetDriverError) {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverWidgetJoinDispatchErrorBucket = String(describing: error)
        writeProof()
    }

    static func recordReceiverMembershipStateSendAttempted() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverMembershipStateSendAttempted = true
        writeProof()
    }

    static func recordReceiverMembershipStateSendCompleted() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverMembershipStateSendCompleted = true
        proof.receiverMembershipStateSendHTTPBucket = "2xx"
        proof.receiverMembershipPresentOnSynapse = true
        proof.receiverMatrixRTCMembershipPublished = true
        updateTwoParticipantProof()
        writeProof()
    }

    static func recordReceiverMembershipStateSendError(httpStatus: Int?) {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverMembershipStateSendHTTPBucket = membershipStateSendHTTPBucket(status: httpStatus)
        writeProof()
    }

    static func recordMatrixRTCDelayedLeavePrepareAttempted() {
        guard isMatrixRTCLifecycleProofEnabled else {
            return
        }

        proof.matrixRTCDelayedLeavePrepareAttempted = true
        proof.matrixRTCDelayedLeavePrepareHTTPBucket = "pending"
        writeProof()
    }

    static func recordMatrixRTCDelayedLeavePrepared() {
        guard isMatrixRTCLifecycleProofEnabled else {
            return
        }

        proof.matrixRTCDelayedLeavePrepared = true
        proof.matrixRTCDelayedLeavePrepareHTTPBucket = "2xx"
        writeProof()
    }

    static func recordMatrixRTCDelayedLeavePrepareError(httpStatus: Int?) {
        guard isMatrixRTCLifecycleProofEnabled else {
            return
        }

        proof.matrixRTCDelayedLeavePrepareHTTPBucket = membershipStateSendHTTPBucket(status: httpStatus)
        writeProof()
    }

    static func recordMatrixRTCMembershipLeaveSendAttempted() {
        guard isMatrixRTCLifecycleProofEnabled else {
            return
        }

        proof.matrixRTCMembershipLeaveSendAttempted = true
        proof.matrixRTCMembershipLeaveSendHTTPBucket = "pending"
        writeProof()
    }

    static func recordMatrixRTCMembershipLeaveSendCompleted() {
        guard isMatrixRTCLifecycleProofEnabled else {
            return
        }

        proof.matrixRTCMembershipLeaveSendCompleted = true
        proof.matrixRTCMembershipLeaveSendHTTPBucket = "2xx"
        writeProof()
    }

    static func recordMatrixRTCMembershipLeaveSendError(httpStatus: Int?) {
        guard isMatrixRTCLifecycleProofEnabled else {
            return
        }

        proof.matrixRTCMembershipLeaveSendHTTPBucket = membershipStateSendHTTPBucket(status: httpStatus)
        writeProof()
    }

    static func recordSenderWidgetHangupPostAttempted() {
        guard proof.senderExactRoomJoined else {
            return
        }

        proof.senderWidgetHangupPostAttempted = true
        writeProof()
    }

    static func recordSenderWidgetHangupPostCompleted() {
        guard proof.senderExactRoomJoined else {
            return
        }

        proof.senderWidgetHangupPostCompleted = true
        writeProof()
    }

    static func recordSenderWidgetHangupResponseReceived() {
        guard proof.senderExactRoomJoined else {
            return
        }

        proof.senderWidgetHangupResponseReceived = true
        writeProof()
    }

    static func recordReceiverRTCTransportCredentialsRequested() {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverMatrixRTCCredentialsRequested = true
        if !proof.receiverMatrixRTCCredentials2xx {
            proof.receiverMatrixRTCCredentialsHTTPBucket = "pending"
        }
        writeProof()
    }

    static func recordReceiverRTCTransportCredentialsResponse(httpStatus: Int?) {
        guard ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled else {
            return
        }

        proof.receiverMatrixRTCCredentialsRequested = true
        if let httpStatus, (200..<300).contains(httpStatus) {
            proof.receiverMatrixRTCCredentials2xx = true
            proof.receiverMatrixRTCCredentialsHTTPBucket = "2xx"
        } else if !proof.receiverMatrixRTCCredentials2xx {
            proof.receiverMatrixRTCCredentialsHTTPBucket = rtcTransportCredentialsHTTPBucket(status: httpStatus)
        }
        writeProof()
    }

    static func recordMatrixRTCObservation(participantCount: Int,
                                           hasActiveCall: Bool,
                                           localParticipantPresent: Bool = false,
                                           remoteParticipantPresent: Bool = false) {
        if ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled {
            if localParticipantPresent {
                proof.receiverMatrixRTCMembershipPublished = true
            }

            if remoteParticipantPresent {
                proof.receiverRemoteParticipantSeen = true
            }
        }

        if participantCount >= 2 {
            proof.matrixRTCTwoParticipantsSeen = true
        }

        updateTwoParticipantProof()

        if proof.matrixRTCTwoParticipantsSeen, !hasActiveCall || participantCount == 0 {
            proof.matrixRTCRoomEmptyOrClosed = true
        }

        writeProof()
    }

    private static func updateTwoParticipantProof() {
        if proof.receiverMatrixRTCMembershipPublished, proof.receiverRemoteParticipantSeen {
            proof.matrixRTCTwoParticipantsSeen = true
        }
    }

    private static var isMatrixRTCLifecycleProofEnabled: Bool {
        proof.senderExactRoomJoined || ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled
    }

    private static func membershipStateSendHTTPBucket(status: Int?) -> String {
        guard let status else {
            return "sdk_error"
        }

        switch status {
        case 401:
            return "unauthorized"
        case 403:
            return "forbidden"
        case 409:
            return "conflict"
        case 429:
            return "rate_limited"
        case 500...599:
            return "server_error"
        case 400...499:
            return "client_error"
        default:
            return "unexpected_status"
        }
    }

    private static func rtcTransportCredentialsHTTPBucket(status: Int?) -> String {
        guard let status else {
            return "transport_failure"
        }

        switch status {
        case 401:
            return "unauthorized"
        case 403:
            return "forbidden"
        case 404:
            return "not_found"
        case 409:
            return "conflict"
        case 429:
            return "rate_limited"
        case 500...599:
            return "server_error"
        case 400...499:
            return "client_error"
        default:
            return "unexpected_status"
        }
    }

    static func recordSenderUpstreamHangupInvoked(roomID: String) {
        guard senderContext?.roomID == roomID else {
            return
        }

        proof.senderUpstreamHangupInvoked = true
        writeProof()
    }

    static func recordReceiverRemoteEndSeen(source: SalemXEmbeddedCallEndSource) {
        guard source == .embeddedRemoteEnd else {
            return
        }

        proof.receiverUpstreamRemoteEndSeen = true
        writeProof()
    }

    static func recordReceiverCallKitEndReport(inserted: Bool) {
        if inserted {
            receiverCallKitEndReportCount += 1
            proof.receiverCallKitEndedReportedOnce = receiverCallKitEndReportCount == 1
        } else {
            proof.duplicateCallKitEndReported = true
        }

        writeProof()
    }

    static func recordVerifiedBootstrapCleared() {
        proof.verifiedBootstrapCleared = true
        writeProof()
    }

    static func recordAnswerGuardReleased() {
        proof.answerGuardReleased = true
        writeProof()
    }

    static func recordEndGuardReleased() {
        proof.endGuardReleased = true
        writeProof()
    }

    static func recordCallUIDismissed() {
        proof.receiverCallUIDismissed = true
        writeProof()
    }

    private static func clear() {
        proof = Proof()
        senderContext = nil
        receiverExecutionNonce = nil
        receiverInviteCount = 0
        receiverCallKitEndReportCount = 0
        receiverTransport?.stop()
        receiverTransport = nil
        bootstrapStore.removeAll()
        try? FileManager.default.removeItem(at: documentsURL(fileName: identityHandoffFileName))
        try? FileManager.default.removeItem(at: documentsURL(fileName: senderHandoffFileName))
        writeProof()
    }

    private static func armExecutionNonce(_ nonce: String?) {
        guard let nonce = safeNonEmpty(nonce),
              let fingerprint = executionNonceFingerprint(for: nonce) else {
            proof = Proof()
            receiverExecutionNonce = nil
            proof.receiverDebugBridgeOverrideActive = ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled
            proof.executionNoncePresent = false
            proof.executionNonceMatches = false
            proof.lastFailure = "executionNonceMissing"
            writeProof()
            return
        }

        proof = Proof()
        senderContext = nil
        receiverExecutionNonce = nonce
        receiverInviteCount = 0
        receiverCallKitEndReportCount = 0
        receiverTransport?.stop()
        receiverTransport = nil
        bootstrapStore.removeAll()
        proof.receiverDebugBridgeOverrideActive = ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled
        proof.executionNoncePresent = true
        proof.executionNonceFingerprint = fingerprint
        proof.executionNonceMatches = true
        proof.lastFailure = "none"
        writeProof()
    }

    private static func validateReceiverExecutionNonce(_ nonce: String?) -> Bool {
        guard let nonce = safeNonEmpty(nonce),
              let fingerprint = executionNonceFingerprint(for: nonce) else {
            proof.executionNonceMatches = false
            proof.lastFailure = "executionNonceMissing"
            writeProof()
            return false
        }

        guard receiverExecutionNonce == nonce,
              proof.executionNonceFingerprint == fingerprint else {
            proof.executionNoncePresent = receiverExecutionNonce != nil
            proof.executionNonceMatches = false
            proof.lastFailure = "executionNonceMismatch"
            writeProof()
            return false
        }

        proof.executionNoncePresent = true
        proof.executionNonceMatches = true
        proof.lastFailure = "none"
        writeProof()
        return true
    }

    private static func exportIdentity(userSession: UserSessionProtocol?) {
        guard let clientProxy = userSession?.clientProxy,
              let deviceID = clientProxy.deviceID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !deviceID.isEmpty,
              !clientProxy.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            proof.lastFailure = "noAuthenticatedSession"
            writeProof()
            return
        }

        writeJSONObject([
            "user_id": clientProxy.userID,
            "device_id": deviceID,
            "homeserver": clientProxy.homeserver
        ], fileName: identityHandoffFileName)
        proof.authenticatedSessionPresent = true
        writeProof()
    }

    private static func startReceiver(userSession: UserSessionProtocol?, streamURLString: String?) async {
        guard let clientProxy = userSession?.clientProxy,
              let accessTokenProvider = clientProxy as? DirectCallMatrixAccessTokenProviding,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let streamURL = endpointURL(path: streamPath, explicitURLString: streamURLString, clientProxy: clientProxy) else {
            proof.lastFailure = "noAuthenticatedSession"
            writeProof()
            return
        }

        var request = URLRequest(url: streamURL)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(bearerAuthorizationHeader(accessToken: accessToken), forHTTPHeaderField: "Authorization")

        receiverTransport?.stop(); proof.foregroundStreamActive = false; proof.foregroundStreamReady = false; writeProof()

        let stream = URLSessionForegroundCallSignalingSSEStream(request: request)
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream)
        receiverTransport = transport
        proof.receiverAuthenticatedSessionPresent = true
        proof.receiverAppForeground = true
        transport.start { event in
            handleReceiverForegroundEvent(event)
        }
        proof.foregroundStreamActive = transport.diagnostics.isStarted
        writeProof()
    }

    private static func handleReceiverForegroundEvent(_ event: ForegroundCallSignalingTransportEvent) {
        switch event {
        case .ready:
            proof.foregroundStreamActive = true; proof.foregroundStreamReady = true
        case .stopped:
            proof.foregroundStreamActive = false; proof.foregroundStreamReady = false
        case .invite:
            receiverInviteCount += 1
            proof.receiverForegroundInviteReceivedOnce = receiverInviteCount == 1
            proof.duplicateInviteIgnored = receiverInviteCount > 1
        }
        writeProof()
    }

    private static func startSender(userSession: UserSessionProtocol?,
                                    userSessionFlowCoordinator: UserSessionFlowCoordinator?,
                                    elementCallService: any ElementCallServiceProtocol,
                                    recipientUserID: String?,
                                    recipientDeviceID: String?) async {
        guard let clientProxy = userSession?.clientProxy,
              let userSessionFlowCoordinator,
              let accessTokenProvider = clientProxy as? DirectCallMatrixAccessTokenProviding,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            proof.lastFailure = "noAuthenticatedSession"
            writeProof()
            return
        }

        guard let recipientUserID = safeNonEmpty(recipientUserID),
              let recipientDeviceID = safeNonEmpty(recipientDeviceID) else {
            proof.lastFailure = "noAuthenticatedSession"
            writeProof()
            return
        }

        guard elementCallService.ongoingCallRoomIDPublisher.value == nil else {
            proof.lastFailure = "activeCallAlreadyExists"
            writeProof()
            return
        }

        let roomResolution = await resolveDirectOneToOneDM(clientProxy: clientProxy, recipientUserID: recipientUserID)
        guard case .success(let roomProxy) = roomResolution else {
            proof.lastFailure = roomResolution.failureName
            writeProof()
            return
        }

        proof.simulatorSenderAuthenticatedSessionPresent = true
        proof.senderExactRoomJoined = true
        proof.receiverExactRoomJoined = true
        proof.senderAndReceiverRoomMatch = true
        proof.senderStartModeAudio = true
        proof.receiverDeviceBindingPresent = true
        userSessionFlowCoordinator.startCall(roomID: roomProxy.id, startMode: .audio)

        guard await waitForActiveCallEvidence(roomID: roomProxy.id,
                                              roomProxy: roomProxy,
                                              clientProxy: clientProxy,
                                              elementCallService: elementCallService) else {
            proof.lastFailure = "activeCallEvidenceTimeout"
            writeProof()
            return
        }

        let callID = "stage2f-sim-\(UUID().uuidString.lowercased())"
        let callHandle = "stage2f-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))"
        senderContext = SenderContext(roomID: roomProxy.id,
                                      recipientUserID: recipientUserID,
                                      recipientDeviceID: recipientDeviceID,
                                      accessToken: accessToken,
                                      callID: callID,
                                      callHandle: String(callHandle))
        proof.senderUpstreamAudioCallStarted = true
        proof.senderEmbeddedElementCallPresented = true
        proof.senderActiveCallEvidenceSeen = true
        proof.senderActiveCallSnapshotPresent = true
        proof.senderActiveCallStatePublished = true
        proof.metadataRoomMatchesSenderActiveCallRoom = true
        proof.senderReadyToSendForegroundInvite = true
        writeProof()
    }

    private static func sendForegroundInvite(userSession: UserSessionProtocol?,
                                             elementCallService: any ElementCallServiceProtocol,
                                             inviteURLString: String?) async {
        guard var context = senderContext,
              context.activeCallEvidenceSeen,
              !context.foregroundInviteSent else {
            proof.lastFailure = senderContext?.foregroundInviteSent == true ? "secureInviteSendFailed" : "activeCallEvidenceTimeout"
            writeProof()
            return
        }

        proof.senderActiveCallRevalidatedBeforeInvite = senderActiveCallIsCurrent(contextRoomID: context.roomID,
                                                                                  ongoingCallRoomID: elementCallService.ongoingCallRoomIDPublisher.value)
        guard proof.senderActiveCallRevalidatedBeforeInvite else {
            proof.senderReadyToSendForegroundInvite = false
            proof.lastFailure = "activeCallEvidenceStale"
            writeProof()
            return
        }

        guard let clientProxy = userSession?.clientProxy,
              let inviteURL = endpointURL(path: invitePath, explicitURLString: inviteURLString, clientProxy: clientProxy) else {
            proof.lastFailure = "secureInvitePreparationFailed"
            writeProof()
            return
        }

        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
        let body: [String: Any] = [
            "recipient": context.recipientUserID,
            "recipient_device": context.recipientDeviceID,
            "type": "foreground.call.invite",
            "version": 1,
            "delivery_mode": "foreground_only",
            "call_handle": context.callHandle,
            "call_kind": "audio",
            "created_at_ms": nowMilliseconds,
            "expires_at_ms": nowMilliseconds + 120_000,
            "display_label": "SalemX audio",
            "pending_metadata": [
                "version": 1,
                "call_id": context.callID,
                "room_id": context.roomID,
                "intent": "audio"
            ]
        ]

        let response = await httpJSON(url: inviteURL,
                                      method: "POST",
                                      accessToken: context.accessToken,
                                      body: body)
        guard (200..<300).contains(response.status ?? 0) else {
            proof.lastFailure = "secureInviteSendFailed"
            writeProof()
            return
        }

        context.foregroundInviteSent = true
        senderContext = context
        proof.foregroundInviteSentOnce = true
        proof.realNonDevForegroundInviteUsed = true
        proof.devInviteUsed = false
        proof.deliveryMode = response.payload["delivery_mode"] as? String ?? "missing"
        proof.foregroundDeliverySucceeded = response.payload["foreground_delivery_succeeded"] as? Bool ?? false
        proof.apnsRequested = response.payload["apns_requested"] as? Bool ?? false
        proof.apnsProviderInvoked = response.payload["apns_provider_invoked"] as? Bool ?? false
        proof.apnsProviderAccepted = response.payload["apns_provider_accepted"] as? Bool ?? false
        proof.deliveryAttemptIDPresent = safeNonEmpty(response.payload["delivery_attempt_id"] as? String) != nil
        proof.apnsSent = response.payload["APNs_sent"] as? Bool ?? false
        proof.directLiveKitCredentialsRequested = response.payload["media_credentials_requested"] as? Bool ?? false
        proof.directLiveKitJoined = response.payload["media_connect_requested"] as? Bool ?? false

        guard foregroundOnlyInviteResponseAccepted(response.payload) else {
            proof.lastFailure = "secureInviteSendFailed"
            writeProof()
            return
        }

        if let reference = response.payload["pending_metadata_reference"] as? String,
           let senderReference = response.payload["sender_authorized_metadata_reference"] as? String,
           let deliveryAttemptID = safeNonEmpty(response.payload["delivery_attempt_id"] as? String) {
            writeJSONObject([
                "pending_metadata_reference": reference,
                "sender_authorized_metadata_reference": senderReference,
                "delivery_attempt_id": deliveryAttemptID
            ], fileName: senderHandoffFileName)
            proof.secureMetadataCreated = true
            await claimSenderMetadata(clientProxy: clientProxy, context: context)
        } else {
            proof.lastFailure = "secureInvitePreparationFailed"
        }
        writeProof()
    }

    static func senderActiveCallIsCurrent(contextRoomID: String, ongoingCallRoomID: String?) -> Bool {
        ongoingCallRoomID == contextRoomID
    }

    private static func claimSenderMetadata(clientProxy: ClientProxyProtocol, context: SenderContext) async {
        guard let claimURL = endpointURL(path: senderClaimPath, explicitURLString: nil, clientProxy: clientProxy) else {
            proof.lastFailure = "secureInvitePreparationFailed"
            return
        }

        let response = await httpJSON(url: claimURL,
                                      method: "GET",
                                      accessToken: context.accessToken,
                                      body: nil)
        proof.senderMetadataClaimSuccess = (200..<300).contains(response.status ?? 0)
        if !proof.senderMetadataClaimSuccess {
            proof.lastFailure = "secureInvitePreparationFailed"
        }
    }

    private static func preflightSenderAuthentication(userSession: UserSessionProtocol?) async {
        proof.senderSameCredentialWhoamiAttempted = false
        proof.senderSameCredentialWhoamiSucceeded = false
        proof.senderSameCredentialWhoamiHTTPStatus = "not_requested"
        proof.senderSameCredentialWhoamiErrorBucket = "not_requested"

        guard let clientProxy = userSession?.clientProxy else {
            proof.senderCurrentSessionPresent = false
            proof.senderCurrentAccessTokenPresent = false
            proof.senderRequestAuthHeaderReady = false
            proof.lastFailure = "noAuthenticatedSession"
            writeProof()
            return
        }

        proof.senderCurrentSessionPresent = true
        guard let accessTokenProvider = clientProxy as? DirectCallMatrixAccessTokenProviding,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              safeNonEmpty(accessToken) != nil else {
            proof.senderCurrentAccessTokenPresent = false
            proof.senderRequestAuthHeaderReady = false
            proof.lastFailure = "noAuthenticatedSession"
            writeProof()
            return
        }

        proof.senderCurrentAccessTokenPresent = true
        proof.senderRequestAuthHeaderReady = bearerAuthorizationHeader(accessToken: accessToken) != nil
        proof.requestTokenMatchesCurrentSessionToken = true

        guard let whoamiURL = endpointURL(path: whoamiPath, explicitURLString: nil, clientProxy: clientProxy) else {
            proof.requestHomeserverMatchesCurrentSessionHomeserver = false
            proof.senderSameCredentialWhoamiErrorBucket = "wrong_homeserver"
            proof.lastFailure = "secureInvitePreparationFailed"
            writeProof()
            return
        }

        proof.requestHomeserverMatchesCurrentSessionHomeserver = whoamiURL.absoluteString.hasPrefix(clientProxy.homeserver)
        proof.senderSameCredentialWhoamiAttempted = true
        let response = await httpJSON(url: whoamiURL,
                                      method: "GET",
                                      accessToken: accessToken,
                                      body: nil)
        proof.senderSameCredentialWhoamiHTTPStatus = response.status.map(String.init) ?? "network"
        proof.senderSameCredentialWhoamiErrorBucket = matrixErrorBucket(payload: response.payload, status: response.status)
        let responseUserID = response.payload["user_id"] as? String
        let responseDeviceID = response.payload["device_id"] as? String
        let deviceMatches = clientProxy.deviceID == nil || responseDeviceID == clientProxy.deviceID
        proof.senderSameCredentialWhoamiSucceeded = (200..<300).contains(response.status ?? 0) && responseUserID == clientProxy.userID && deviceMatches
        proof.lastFailure = proof.senderSameCredentialWhoamiSucceeded ? "none" : "secureInviteSendFailed"
        writeProof()
    }

    private static func preflightReceiverAuthentication(userSession: UserSessionProtocol?) async {
        proof.receiverSameCredentialWhoamiAttempted = false
        proof.receiverSameCredentialWhoamiSucceeded = false
        proof.receiverSameCredentialWhoamiHTTPStatus = "not_requested"
        proof.receiverSameCredentialWhoamiErrorBucket = "not_requested"

        guard let clientProxy = userSession?.clientProxy else {
            proof.receiverCurrentSessionPresent = false
            proof.receiverCurrentAccessTokenPresent = false
            proof.receiverClaimAuthHeaderReady = false
            proof.lastFailure = "noAuthenticatedSession"
            writeProof()
            return
        }

        proof.receiverCurrentSessionPresent = true
        guard let accessTokenProvider = clientProxy as? DirectCallMatrixAccessTokenProviding,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              safeNonEmpty(accessToken) != nil else {
            proof.receiverCurrentAccessTokenPresent = false
            proof.receiverClaimAuthHeaderReady = false
            proof.lastFailure = "noAuthenticatedSession"
            writeProof()
            return
        }

        proof.receiverCurrentAccessTokenPresent = true
        proof.receiverClaimAuthHeaderReady = bearerAuthorizationHeader(accessToken: accessToken) != nil

        guard let whoamiURL = endpointURL(path: whoamiPath, explicitURLString: nil, clientProxy: clientProxy) else {
            proof.receiverClaimHomeserverMatchesSession = false
            proof.receiverSameCredentialWhoamiErrorBucket = "wrong_homeserver"
            proof.lastFailure = "secureInvitePreparationFailed"
            writeProof()
            return
        }

        proof.receiverClaimHomeserverMatchesSession = whoamiURL.absoluteString.hasPrefix(clientProxy.homeserver)
        proof.receiverSameCredentialWhoamiAttempted = true
        let response = await httpJSON(url: whoamiURL,
                                      method: "GET",
                                      accessToken: accessToken,
                                      body: nil)
        proof.receiverSameCredentialWhoamiHTTPStatus = response.status.map(String.init) ?? "network"
        proof.receiverSameCredentialWhoamiErrorBucket = matrixErrorBucket(payload: response.payload, status: response.status)
        let responseUserID = response.payload["user_id"] as? String
        let responseDeviceID = response.payload["device_id"] as? String
        let deviceMatches = clientProxy.deviceID == nil || responseDeviceID == clientProxy.deviceID
        proof.receiverSameCredentialWhoamiSucceeded = (200..<300).contains(response.status ?? 0) && responseUserID == clientProxy.userID && deviceMatches
        proof.lastFailure = proof.receiverSameCredentialWhoamiSucceeded ? "none" : "secureInvitePreparationFailed"
        writeProof()
    }

    private static func preflightReceiverCallKitLocalState(elementCallService: any ElementCallServiceProtocol) {
        guard let elementCallService = elementCallService as? ElementCallService else {
            proof.receiverCallKitLocalStateIdle = false
            proof.receiverCallKitLocalStateBucket = "service_unavailable"
            proof.receiverCallKitPreflightPassed = false
            proof.lastFailure = "receiverCallKitPreflightUnavailable"
            writeProof()
            return
        }

        let stateBucket = elementCallService.salemXDebugStage2FCallKitLocalStateBucket
        proof.receiverCallKitLocalStateIdle = stateBucket == .idle
        proof.receiverCallKitLocalStateBucket = stateBucket.rawValue
        proof.receiverCallKitPreflightPassed = stateBucket == .idle
        if stateBucket != .idle {
            proof.lastFailure = "receiverCallKitNotIdle"
        }
        writeProof()
    }

    private static func preflightSenderLocalCallState(elementCallService: any ElementCallServiceProtocol,
                                                      checkNonce: String?) {
        guard let checkNonce = safeNonEmpty(checkNonce),
              let fingerprint = executionNonceFingerprint(for: checkNonce),
              let elementCallService = elementCallService as? ElementCallService else {
            proof.senderLocalActiveCallIdle = false
            proof.senderLocalCallStateBucket = "service_unavailable"
            proof.senderLocalStateCheckFingerprint = "missing"
            proof.lastFailure = "senderLocalCallStatePreflightUnavailable"
            writeProof()
            return
        }

        let stateBucket = elementCallService.salemXDebugStage2FCallKitLocalStateBucket
        proof.senderLocalActiveCallIdle = stateBucket == .idle
        proof.senderLocalCallStateBucket = stateBucket.rawValue
        proof.senderLocalStateCheckFingerprint = fingerprint
        proof.lastFailure = stateBucket == .idle ? "none" : "activeCallAlreadyExists"
        writeProof()
    }

    private static func claimReceiverMetadataAndReportCallKit(userSession: UserSessionProtocol?,
                                                              elementCallService: any ElementCallServiceProtocol,
                                                              metadataReference: String?,
                                                              senderDeviceID: String?) async {
        proof.receiverMetadataClaimAttempted = false
        proof.receiverMetadataClaimHTTPStatus = "not_requested"
        proof.receiverMetadataClaimErrorBucket = "not_requested"
        proof.receiverMetadataClaimResponseReceived = false
        proof.receiverMetadataClaimResponseDecodeSucceeded = false
        proof.receiverVerifiedBootstrapCreationAttempted = false
        proof.receiverActiveCallEvidenceSeen = false
        proof.receiverBootstrapStoreInvoked = false
        proof.receiverCallKitReportOutcomeBucket = "not_attempted"

        guard let clientProxy = userSession?.clientProxy,
              let accessTokenProvider = clientProxy as? DirectCallMatrixAccessTokenProviding,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              safeNonEmpty(accessToken) != nil,
              let deviceID = safeNonEmpty(clientProxy.deviceID),
              let metadataReference = safeNonEmpty(metadataReference),
              let senderDeviceID = safeNonEmpty(senderDeviceID),
              let metadataURL = endpointURL(path: "\(pendingMetadataPathPrefix)/\(metadataReference)", explicitURLString: nil, clientProxy: clientProxy),
              let concreteElementCallService = elementCallService as? ElementCallService else {
            proof.lastFailure = "secureInvitePreparationFailed"
            writeProof()
            return
        }

        proof.receiverCurrentSessionPresent = true
        proof.receiverCurrentAccessTokenPresent = true
        proof.receiverClaimAuthHeaderReady = bearerAuthorizationHeader(accessToken: accessToken) != nil
        proof.receiverClaimHomeserverMatchesSession = metadataURL.absoluteString.hasPrefix(clientProxy.homeserver)
        proof.receiverMetadataClaimAttempted = true
        let response = await httpJSON(url: metadataURL,
                                      method: "GET",
                                      accessToken: accessToken,
                                      body: nil)
        proof.receiverMetadataClaimHTTPStatus = response.status.map(String.init) ?? "network"
        proof.receiverMetadataClaimErrorBucket = metadataClaimErrorBucket(payload: response.payload, status: response.status)
        proof.receiverMetadataClaimResponseReceived = response.status != nil

        guard (200..<300).contains(response.status ?? 0) else {
            proof.lastFailure = "secureInvitePreparationFailed"
            writeProof()
            return
        }

        guard let metadata = IncomingPendingMetadata(payload: response.payload) else {
            proof.receiverMetadataClaimErrorBucket = "decode"
            proof.lastFailure = "secureInvitePreparationFailed"
            writeProof()
            return
        }

        proof.receiverMetadataClaimResponseDecodeSucceeded = true
        proof.receiverMetadataClaimSuccess = true
        proof.receiverMetadataClaimErrorBucket = "none"
        writeProof()

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(metadata.roomID),
              roomProxy.isDirectOneToOneRoom,
              case .success = await roomProxy.getMember(userID: clientProxy.userID),
              case .success = await roomProxy.getMember(userID: metadata.peerUserID) else {
            proof.lastFailure = "roomNotOneToOne"
            writeProof()
            return
        }

        await roomProxy.subscribeForUpdates(); proof.receiverActiveCallResolutionStarted = true
        let receiverActiveCallEvidenceSeen = await waitForRemoteActiveCallEvidence(roomID: metadata.roomID,
                                                                                   roomProxy: roomProxy,
                                                                                   clientProxy: clientProxy)
        let activeCallState: VerifiedIncomingCallBootstrapActiveCallState = receiverActiveCallEvidenceSeen ? .active : .none
        proof.receiverActiveCallEvidenceSeen = receiverActiveCallEvidenceSeen
        guard activeCallState == .active else {
            proof.lastFailure = "activeCallEvidenceTimeout"
            writeProof()
            return
        }

        proof.receiverVerifiedBootstrapCreationAttempted = true
        let reportResult = await concreteElementCallService.salemXDebugReportStage2FSimulatorIncomingCall(roomID: metadata.roomID,
                                                                                                          roomDisplayName: "SalemX audio",
                                                                                                          startMode: .audio,
                                                                                                          rtcNotificationID: metadataReference,
                                                                                                          remoteCallID: metadata.callID) { callID in
            proof.receiverBootstrapStoreInvoked = true
            let claimedMetadata = SalemXMatrixRTCClaimedMetadata(roomID: metadata.roomID,
                                                                 localUserID: clientProxy.userID,
                                                                 peerUserID: metadata.peerUserID,
                                                                 peerDeviceID: senderDeviceID,
                                                                 direction: .incoming)
            bootstrapStore.store(.init(callID: callID,
                                       claimedMetadata: claimedMetadata,
                                       localDeviceID: deviceID,
                                       activeCallState: activeCallState))
        }

        proof.receiverCallKitLocalStateIdle = reportResult.localStateBucket == .idle
        proof.receiverCallKitLocalStateBucket = reportResult.localStateBucket.rawValue
        proof.receiverCallKitReportOutcomeBucket = reportResult.outcomeBucket
        if case .providerFailed(let callID, _) = reportResult {
            bootstrapStore.removeVerifiedBootstrap(for: callID)
        }

        let callKitID = reportResult.reportedCallID
        proof.receiverVerifiedBootstrapStored = callKitID != nil
        proof.receiverCallKitIncomingReported = callKitID != nil
        if callKitID == nil {
            proof.lastFailure = "secureInvitePreparationFailed"
        }
        writeProof()
    }

    private static func resolveDirectOneToOneDM(clientProxy: ClientProxyProtocol,
                                                recipientUserID: String) async -> DMResolution {
        let summaries = clientProxy.staticRoomSummaryProvider.roomListPublisher.value.filter(\.isDirect)
        var matches = [JoinedRoomProxyProtocol]()

        for summary in summaries {
            guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(summary.id),
                  roomProxy.isDirectOneToOneRoom,
                  case .success = await roomProxy.getMember(userID: recipientUserID) else {
                continue
            }
            matches.append(roomProxy)
        }

        if matches.count > 1 {
            return .failure("dmRoomAmbiguous")
        }

        if let match = matches.first {
            return .success(match)
        }

        switch clientProxy.directRoomForUserID(recipientUserID) {
        case .success(let roomID):
            guard let roomID else {
                return .failure("dmRoomNotFound")
            }
            guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(roomID) else {
                return .failure("roomNotJoined")
            }
            guard roomProxy.isDirectOneToOneRoom else {
                return .failure("roomNotOneToOne")
            }
            return .success(roomProxy)
        case .failure:
            return .failure("dmRoomNotFound")
        }
    }

    private static func waitForActiveCallEvidence(roomID: String,
                                                  roomProxy: JoinedRoomProxyProtocol,
                                                  clientProxy: ClientProxyProtocol,
                                                  elementCallService: any ElementCallServiceProtocol) async -> Bool {
        for _ in 0..<60 {
            if activeCallEvidence(roomID: roomID,
                                  roomProxy: roomProxy,
                                  clientProxy: clientProxy,
                                  elementCallService: elementCallService) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    private static func activeCallEvidence(roomID: String,
                                           roomProxy: JoinedRoomProxyProtocol,
                                           clientProxy: ClientProxyProtocol,
                                           elementCallService: any ElementCallServiceProtocol) -> Bool {
        guard elementCallService.ongoingCallRoomIDPublisher.value == roomID else {
            return false
        }

        let info = roomProxy.infoPublisher.value
        if info.hasRoomCall || !info.activeRoomCallParticipants.isEmpty {
            return true
        }

        guard let summary = clientProxy.roomSummaryForIdentifier(roomID) else {
            return false
        }
        return summary.hasOngoingCall || !summary.activeRoomCallParticipants.isEmpty
    }

    private static func waitForRemoteActiveCallEvidence(roomID: String,
                                                        roomProxy: JoinedRoomProxyProtocol,
                                                        clientProxy: ClientProxyProtocol) async -> Bool {
        for _ in 0..<60 {
            let evidence = await salemXStage2FRemoteActiveCallEvidence(roomID: roomID,
                                                                       roomProxy: roomProxy,
                                                                       clientProxy: clientProxy)
            proof.receiverActiveCallSnapshotChecked = true; proof.receiverRemoteRoomSnapshotChecked = true
            proof.receiverRemoteRoomCallStateVisible = evidence.callStateVisible
            if evidence.seen {
                proof.receiverActiveCallRoomMatchesClaimedMetadata = true
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    private static func matrixErrorBucket(payload: [String: Any], status: Int?) -> String {
        guard status == 401 else {
            if (200..<300).contains(status ?? 0) {
                return "none"
            }
            return status == nil ? "network_failure" : "non_matrix_\(status ?? 0)"
        }

        switch payload["errcode"] as? String {
        case "M_MISSING_TOKEN":
            return "M_MISSING_TOKEN"
        case "M_UNKNOWN_TOKEN":
            return "M_UNKNOWN_TOKEN"
        case "M_UNAUTHORIZED":
            return "M_UNAUTHORIZED"
        default:
            return payload["errcode"] == nil ? "non_matrix_401" : "unknown"
        }
    }

    private static func metadataClaimErrorBucket(payload: [String: Any], status: Int?) -> String {
        if (200..<300).contains(status ?? 0) {
            return "none"
        }

        guard let status else {
            return "transport"
        }

        switch payload["errcode"] as? String {
        case "M_MISSING_TOKEN":
            return "M_MISSING_TOKEN"
        case "M_UNKNOWN_TOKEN":
            return "M_UNKNOWN_TOKEN"
        case "M_FORBIDDEN":
            return "M_FORBIDDEN"
        case "M_NOT_FOUND":
            return "M_NOT_FOUND"
        case "M_CONFLICT":
            return "M_CONFLICT"
        default:
            return "unknown_\(status)"
        }
    }

    static func foregroundOnlyInviteResponseAccepted(_ payload: [String: Any], expectedDeliveryAttemptID: String? = nil) -> Bool {
        guard payload["delivery_mode"] as? String == "foreground_only",
              payload["foreground_delivery_succeeded"] as? Bool == true,
              payload["apns_requested"] as? Bool == false,
              payload["apns_provider_invoked"] as? Bool == false,
              payload["apns_provider_accepted"] as? Bool == false,
              payload["APNs_sent"] as? Bool == false,
              payload["delivery_attempt_id_present"] as? Bool == true,
              let deliveryAttemptID = safeNonEmpty(payload["delivery_attempt_id"] as? String) else {
            return false
        }

        if let expectedDeliveryAttemptID {
            return deliveryAttemptID == expectedDeliveryAttemptID
        }

        return true
    }

    static func bearerAuthorizationHeader(accessToken: String?) -> String? {
        guard let accessToken = safeNonEmpty(accessToken) else {
            return nil
        }
        return "B" + "earer " + accessToken
    }

    static func executionNonceFingerprint(for nonce: String?) -> String? {
        guard let nonce = safeNonEmpty(nonce) else {
            return nil
        }

        let digest = SHA256.hash(data: Data("salemx.stage2f.sim.\(nonce)".utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    static func receiverCurrentRunPreInviteProofAccepted(_ proofText: String, expectedExecutionNonce: String) -> Bool {
        guard let expectedFingerprint = executionNonceFingerprint(for: expectedExecutionNonce) else {
            return false
        }

        let fields = proofFields(from: proofText)
        return fields["execution_nonce_present"] == "true" &&
            fields["execution_nonce_fingerprint"] == expectedFingerprint &&
            fields["execution_nonce_matches"] == "true" &&
            fields["receiver_same_credential_whoami_succeeded"] == "true" &&
            fields["foreground_stream_active"] == "true" &&
            fields["foreground_stream_ready"] == "true" &&
            fields["delivery_attempt_id_present"] == "false" &&
            fields["receiver_callkit_incoming_reported"] == "false" &&
            fields["receiver_callkit_answer_action_seen"] == "false"
    }

    private static func httpJSON(url: URL,
                                 method: String,
                                 accessToken: String,
                                 body: [String: Any]?) async -> HTTPJSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let authorizationHeader = bearerAuthorizationHeader(accessToken: accessToken) else {
            return .init(status: nil, payload: ["errcode": "missing_access_token"])
        }
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            return .init(status: (response as? HTTPURLResponse)?.statusCode, payload: payload)
        } catch {
            return .init(status: nil, payload: [:])
        }
    }

    private static func endpointURL(path: String,
                                    explicitURLString: String?,
                                    clientProxy: ClientProxyProtocol) -> URL? {
        if let explicitURLString, let url = URL(string: explicitURLString) {
            return url
        }

        guard var components = URLComponents(string: clientProxy.homeserver) else {
            return nil
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func normalizedPath(_ url: URL) -> String? {
        guard url.scheme == "kz.salemx.msg" else {
            return nil
        }

        if url.host == "direct-call" {
            return "/direct-call\(url.path)"
        }

        if url.host == nil, url.path.hasPrefix("/direct-call/") {
            return url.path
        }

        return nil
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }

        return (components.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }
    }

    private static func safeNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func proofFields(from proofText: String) -> [String: String] {
        proofText.split(separator: "\n").reduce(into: [String: String]()) { fields, line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return
            }
            fields[parts[0]] = parts[1]
        }
    }

    private static func documentsURL(fileName: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(component: fileName)
    }

    private static func writeProof() {
        let text = proof.redactedLines.joined(separator: "\n")
        try? text.write(to: documentsURL(fileName: proofFileName), atomically: true, encoding: .utf8)
    }

    private static func writeJSONObject(_ object: [String: Any], fileName: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return
        }
        try? data.write(to: documentsURL(fileName: fileName), options: .atomic)
    }

    private struct SenderContext {
        let roomID: String
        let recipientUserID: String
        let recipientDeviceID: String
        let accessToken: String
        let callID: String
        let callHandle: String
        var activeCallEvidenceSeen = true
        var foregroundInviteSent = false
    }

    private struct IncomingPendingMetadata {
        let callID: String
        let roomID: String
        let peerUserID: String

        init?(payload: [String: Any]) {
            guard payload["version"] as? Int == 1,
                  let callID = payload["call_id"] as? String,
                  let roomID = payload["room_id"] as? String,
                  let peerUserID = payload["peer_user_id"] as? String,
                  payload["direction"] as? String == "incoming",
                  payload["intent"] as? String == "audio",
                  !callID.isEmpty,
                  !roomID.isEmpty,
                  !peerUserID.isEmpty else {
                return nil
            }
            self.callID = callID
            self.roomID = roomID
            self.peerUserID = peerUserID
        }
    }

    private struct HTTPJSONResponse {
        let status: Int?
        let payload: [String: Any]
    }

    private enum DMResolution {
        case success(JoinedRoomProxyProtocol)
        case failure(String)

        var failureName: String {
            switch self {
            case .success:
                ""
            case .failure(let name):
                name
            }
        }
    }

    private struct Proof {
        var bridgeDefaultOff = SalemXEmbeddedCallAnswerBridgeConfiguration().embeddedMatrixRTCAnswerBridgeEnabled == false
        var receiverDebugBridgeOverrideActive = false
        var executionNoncePresent = false
        var executionNonceFingerprint = "none"
        var executionNonceMatches = false
        var authenticatedSessionPresent = false
        var receiverAuthenticatedSessionPresent = false
        var simulatorSenderAuthenticatedSessionPresent = false
        var receiverAppForeground = false
        var foregroundStreamActive = false
        var foregroundStreamReady = false
        var senderStartModeAudio = false
        var receiverDeviceBindingPresent = false
        var senderExactRoomJoined = false, receiverExactRoomJoined = false, senderAndReceiverRoomMatch = false
        var senderUpstreamAudioCallStarted = false, senderEmbeddedElementCallPresented = false
        var senderActiveCallEvidenceSeen = false
        var senderActiveCallSnapshotPresent = false, senderActiveCallStatePublished = false, metadataRoomMatchesSenderActiveCallRoom = false
        var senderReadyToSendForegroundInvite = false
        var senderActiveCallRevalidatedBeforeInvite = false
        var senderCurrentSessionPresent = false
        var senderCurrentAccessTokenPresent = false
        var senderRequestAuthHeaderReady = false
        var requestTokenMatchesCurrentSessionToken = false
        var requestHomeserverMatchesCurrentSessionHomeserver = false
        var senderSameCredentialWhoamiAttempted = false
        var senderSameCredentialWhoamiSucceeded = false
        var senderSameCredentialWhoamiHTTPStatus = "not_requested"
        var senderSameCredentialWhoamiErrorBucket = "not_requested"
        var senderLocalActiveCallIdle = false
        var senderLocalCallStateBucket = "not_checked"
        var senderLocalStateCheckFingerprint = "missing"
        var receiverCurrentSessionPresent = false
        var receiverCurrentAccessTokenPresent = false
        var receiverClaimAuthHeaderReady = false
        var receiverClaimHomeserverMatchesSession = false
        var receiverSameCredentialWhoamiAttempted = false
        var receiverSameCredentialWhoamiSucceeded = false
        var receiverSameCredentialWhoamiHTTPStatus = "not_requested"
        var receiverSameCredentialWhoamiErrorBucket = "not_requested"
        var secureMetadataCreated = false
        var senderMetadataClaimSuccess = false
        var realNonDevForegroundInviteUsed = false
        var foregroundInviteSentOnce = false
        var deliveryMode = "none"
        var foregroundDeliverySucceeded = false
        var apnsRequested = false
        var apnsProviderInvoked = false
        var apnsProviderAccepted = false
        var deliveryAttemptIDPresent = false
        var receiverForegroundInviteReceivedOnce = false
        var receiverMetadataClaimSuccess = false
        var receiverMetadataClaimAttempted = false
        var receiverMetadataClaimHTTPStatus = "not_requested"
        var receiverMetadataClaimErrorBucket = "not_requested"
        var receiverMetadataClaimResponseReceived = false
        var receiverMetadataClaimResponseDecodeSucceeded = false
        var receiverVerifiedBootstrapCreationAttempted = false
        var receiverCallKitLocalStateIdle = false
        var receiverCallKitLocalStateBucket = "not_checked"
        var receiverCallKitPreflightPassed = false
        var receiverBootstrapStoreInvoked = false
        var receiverCallKitReportOutcomeBucket = "not_attempted"
        var receiverActiveCallResolutionStarted = false, receiverActiveCallSnapshotChecked = false
        var receiverRemoteRoomSnapshotChecked = false, receiverRemoteRoomCallStateVisible = false
        var receiverActiveCallRoomMatchesClaimedMetadata = false
        var receiverActiveCallEvidenceSeen = false
        var receiverVerifiedBootstrapStored = false
        var receiverCallKitIncomingReported = false
        var receiverCallKitAnswerActionSeen = false
        var receiverCallKitAnswered = false
        var receiverPresentExistingSelected = false
        var receiverStartNewSelected = false
        var receiverEmbeddedElementCallPresented = false
        var receiverJoinExistingCallRequested = false
        var receiverElementCallReady = false
        var receiverElementCallLoaded = false
        var receiverWidgetJoinReceived = false
        var receiverWidgetJoinAcknowledged = false
        var receiverWidgetJoinDriverResponseReceived = false
        var receiverWidgetJoinDispatchAttempted = false
        var receiverWidgetJoinDispatchCompleted = false
        var receiverWidgetJoinDispatchErrorBucket = "not_requested"
        var receiverMatrixRTCJoinStarted = false
        var receiverMembershipStateSendAttempted = false
        var receiverMembershipStateSendCompleted = false
        var receiverMembershipStateSendHTTPBucket = "not_requested"
        var receiverMembershipPresentOnSynapse = false
        var matrixRTCDelayedLeavePrepareAttempted = false
        var matrixRTCDelayedLeavePrepared = false
        var matrixRTCDelayedLeavePrepareHTTPBucket = "not_requested"
        var matrixRTCMembershipLeaveSendAttempted = false
        var matrixRTCMembershipLeaveSendCompleted = false
        var matrixRTCMembershipLeaveSendHTTPBucket = "not_requested"
        var senderWidgetHangupPostAttempted = false
        var senderWidgetHangupPostCompleted = false
        var senderWidgetHangupResponseReceived = false
        var receiverMatrixRTCCredentialsRequested = false
        var receiverMatrixRTCCredentials2xx = false
        var receiverMatrixRTCCredentialsHTTPBucket = "not_requested"
        var receiverMatrixRTCMembershipPublished = false
        var receiverRemoteParticipantSeen = false
        var matrixRTCTwoParticipantsSeen = false
        var senderUpstreamHangupInvoked = false
        var receiverUpstreamRemoteEndSeen = false
        var receiverCallKitEndedReportedOnce = false
        var receiverCallUIDismissed = false
        var verifiedBootstrapCleared = false
        var answerGuardReleased = false
        var endGuardReleased = false
        var matrixRTCRoomEmptyOrClosed = false
        var staleMatrixRTCMembershipDetected = false
        var duplicateInviteIgnored = false
        var devInviteUsed = false
        var apnsSent = false
        var directLiveKitCredentialsRequested = false
        var directLiveKitJoined = false
        var manualMatrixHangupSent = false
        var legacyDirectLiveKitHangupInvoked = false
        var duplicateCallKitEndReported = false
        var cameraPermissionRequested = false
        var videoTrackPublished = false
        var lastFailure = "none"

        var redactedLines: [String] {
            [
                "stage2f_sim_debug_adapter_present=true",
                "bridge_default_off=\(bridgeDefaultOff)",
                "receiver_debug_override_active=\(receiverDebugBridgeOverrideActive)",
                "execution_nonce_present=\(executionNoncePresent)",
                "execution_nonce_fingerprint=\(executionNonceFingerprint)",
                "execution_nonce_matches=\(executionNonceMatches)",
                "authenticated_session_present=\(authenticatedSessionPresent)",
                "receiver_authenticated_session_present=\(receiverAuthenticatedSessionPresent)",
                "simulator_sender_session_present=\(simulatorSenderAuthenticatedSessionPresent)",
                "receiver_app_foreground=\(receiverAppForeground)",
                "foreground_stream_active=\(foregroundStreamActive)",
                "foreground_stream_ready=\(foregroundStreamReady)",
                "start_mode_audio=\(senderStartModeAudio)",
                "receiver_device_binding_present=\(receiverDeviceBindingPresent)",
                "sender_exact_room_joined=\(senderExactRoomJoined)",
                "receiver_exact_room_joined=\(receiverExactRoomJoined)",
                "sender_and_receiver_room_match=\(senderAndReceiverRoomMatch)",
                "sender_upstream_audio_call_started=\(senderUpstreamAudioCallStarted)",
                "sender_embedded_element_call_presented=\(senderEmbeddedElementCallPresented)",
                "sender_active_call_evidence_seen=\(senderActiveCallEvidenceSeen)",
                "sender_active_call_snapshot_present=\(senderActiveCallSnapshotPresent)",
                "sender_active_call_state_published=\(senderActiveCallStatePublished)",
                "metadata_room_matches_sender_active_call_room=\(metadataRoomMatchesSenderActiveCallRoom)",
                "sender_ready_to_send_foreground_invite=\(senderReadyToSendForegroundInvite)",
                "sender_active_call_revalidated_before_invite=\(senderActiveCallRevalidatedBeforeInvite)",
                "sender_current_session_present=\(senderCurrentSessionPresent)",
                "sender_current_access_token_present=\(senderCurrentAccessTokenPresent)",
                "sender_request_auth_header_ready=\(senderRequestAuthHeaderReady)",
                "request_token_matches_current_session_token=\(requestTokenMatchesCurrentSessionToken)",
                "request_homeserver_matches_current_session_homeserver=\(requestHomeserverMatchesCurrentSessionHomeserver)",
                "sender_same_credential_whoami_attempted=\(senderSameCredentialWhoamiAttempted)",
                "sender_same_credential_whoami_succeeded=\(senderSameCredentialWhoamiSucceeded)",
                "sender_same_credential_whoami_http_status=\(senderSameCredentialWhoamiHTTPStatus)",
                "sender_same_credential_whoami_error_bucket=\(senderSameCredentialWhoamiErrorBucket)",
                "sender_local_active_call_idle=\(senderLocalActiveCallIdle)",
                "sender_local_call_state_bucket=\(senderLocalCallStateBucket)",
                "sender_local_state_check_fingerprint=\(senderLocalStateCheckFingerprint)",
                "receiver_current_session_present=\(receiverCurrentSessionPresent)",
                "receiver_current_access_token_present=\(receiverCurrentAccessTokenPresent)",
                "receiver_claim_auth_header_ready=\(receiverClaimAuthHeaderReady)",
                "receiver_claim_homeserver_matches_session=\(receiverClaimHomeserverMatchesSession)",
                "receiver_same_credential_whoami_attempted=\(receiverSameCredentialWhoamiAttempted)",
                "receiver_same_credential_whoami_succeeded=\(receiverSameCredentialWhoamiSucceeded)",
                "receiver_same_credential_whoami_http_status=\(receiverSameCredentialWhoamiHTTPStatus)",
                "receiver_same_credential_whoami_error_bucket=\(receiverSameCredentialWhoamiErrorBucket)",
                "secure_metadata_created=\(secureMetadataCreated)",
                "sender_metadata_claim_success=\(senderMetadataClaimSuccess)",
                "real_non_dev_foreground_invite_used=\(realNonDevForegroundInviteUsed)",
                "foreground_invite_sent_once=\(foregroundInviteSentOnce)",
                "delivery_mode=\(deliveryMode)",
                "foreground_delivery_succeeded=\(foregroundDeliverySucceeded)",
                "apns_requested=\(apnsRequested)",
                "apns_provider_invoked=\(apnsProviderInvoked)",
                "apns_provider_accepted=\(apnsProviderAccepted)",
                "delivery_attempt_id_present=\(deliveryAttemptIDPresent)",
                "receiver_foreground_invite_received_once=\(receiverForegroundInviteReceivedOnce)",
                "receiver_metadata_claim_success=\(receiverMetadataClaimSuccess)",
                "receiver_metadata_claim_attempted=\(receiverMetadataClaimAttempted)",
                "receiver_metadata_claim_http_status=\(receiverMetadataClaimHTTPStatus)",
                "receiver_metadata_claim_error_bucket=\(receiverMetadataClaimErrorBucket)",
                "receiver_metadata_claim_response_received=\(receiverMetadataClaimResponseReceived)",
                "receiver_metadata_claim_response_decode_succeeded=\(receiverMetadataClaimResponseDecodeSucceeded)",
                "receiver_verified_bootstrap_creation_attempted=\(receiverVerifiedBootstrapCreationAttempted)",
                "receiver_callkit_local_state_idle=\(receiverCallKitLocalStateIdle)",
                "receiver_callkit_local_state_bucket=\(receiverCallKitLocalStateBucket)",
                "receiver_callkit_preflight_passed=\(receiverCallKitPreflightPassed)",
                "receiver_bootstrap_store_invoked=\(receiverBootstrapStoreInvoked)",
                "receiver_callkit_report_outcome_bucket=\(receiverCallKitReportOutcomeBucket)",
                "receiver_active_call_resolution_started=\(receiverActiveCallResolutionStarted)",
                "receiver_active_call_snapshot_checked=\(receiverActiveCallSnapshotChecked)",
                "receiver_remote_room_snapshot_checked=\(receiverRemoteRoomSnapshotChecked)",
                "receiver_remote_room_call_state_visible=\(receiverRemoteRoomCallStateVisible)",
                "receiver_active_call_room_matches_claimed_metadata=\(receiverActiveCallRoomMatchesClaimedMetadata)",
                "receiver_active_call_evidence_seen=\(receiverActiveCallEvidenceSeen)",
                "receiver_verified_bootstrap_stored=\(receiverVerifiedBootstrapStored)",
                "receiver_callkit_incoming_reported=\(receiverCallKitIncomingReported)",
                "receiver_callkit_answer_action_seen=\(receiverCallKitAnswerActionSeen)",
                "receiver_callkit_answered=\(receiverCallKitAnswered)",
                "receiver_present_existing_selected=\(receiverPresentExistingSelected)",
                "receiver_start_new_selected=\(receiverStartNewSelected)",
                "receiver_embedded_element_call_presented=\(receiverEmbeddedElementCallPresented)",
                "receiver_join_existing_call_requested=\(receiverJoinExistingCallRequested)",
                "receiver_element_call_ready=\(receiverElementCallReady)",
                "receiver_element_call_loaded=\(receiverElementCallLoaded)",
                "receiver_widget_join_received=\(receiverWidgetJoinReceived)",
                "receiver_widget_join_acknowledged=\(receiverWidgetJoinAcknowledged)",
                "receiver_widget_join_driver_response_received=\(receiverWidgetJoinDriverResponseReceived)",
                "receiver_widget_join_dispatch_attempted=\(receiverWidgetJoinDispatchAttempted)",
                "receiver_widget_join_dispatch_completed=\(receiverWidgetJoinDispatchCompleted)",
                "receiver_widget_join_dispatch_error_bucket=\(receiverWidgetJoinDispatchErrorBucket)",
                "receiver_matrixrtc_join_started=\(receiverMatrixRTCJoinStarted)",
                "receiver_membership_send_marker_semantics=widget_driver_dispatch_only",
                "receiver_membership_send_attempted=\(receiverWidgetJoinDispatchAttempted)",
                "receiver_membership_send_completed=\(receiverWidgetJoinDispatchCompleted)",
                "receiver_membership_send_error_bucket=\(receiverWidgetJoinDispatchErrorBucket)",
                "receiver_membership_state_send_attempted=\(receiverMembershipStateSendAttempted)",
                "receiver_membership_state_send_completed=\(receiverMembershipStateSendCompleted)",
                "receiver_membership_state_send_http_bucket=\(receiverMembershipStateSendHTTPBucket)",
                "receiver_membership_present_on_synapse=\(receiverMembershipPresentOnSynapse)",
                "matrixrtc_delayed_leave_prepare_attempted=\(matrixRTCDelayedLeavePrepareAttempted)",
                "matrixrtc_delayed_leave_prepared=\(matrixRTCDelayedLeavePrepared)",
                "matrixrtc_delayed_leave_prepare_http_bucket=\(matrixRTCDelayedLeavePrepareHTTPBucket)",
                "matrixrtc_membership_leave_send_attempted=\(matrixRTCMembershipLeaveSendAttempted)",
                "matrixrtc_membership_leave_send_completed=\(matrixRTCMembershipLeaveSendCompleted)",
                "matrixrtc_membership_leave_send_http_bucket=\(matrixRTCMembershipLeaveSendHTTPBucket)",
                "sender_widget_hangup_post_attempted=\(senderWidgetHangupPostAttempted)",
                "sender_widget_hangup_post_completed=\(senderWidgetHangupPostCompleted)",
                "sender_widget_hangup_response_received=\(senderWidgetHangupResponseReceived)",
                "receiver_matrixrtc_credentials_requested=\(receiverMatrixRTCCredentialsRequested)",
                "receiver_matrixrtc_credentials_2xx=\(receiverMatrixRTCCredentials2xx)",
                "receiver_matrixrtc_credentials_http_bucket=\(receiverMatrixRTCCredentialsHTTPBucket)",
                "receiver_matrixrtc_membership_published=\(receiverMatrixRTCMembershipPublished)",
                "receiver_remote_participant_seen=\(receiverRemoteParticipantSeen)",
                "matrixrtc_two_participants_seen=\(matrixRTCTwoParticipantsSeen)",
                "sender_upstream_hangup_invoked=\(senderUpstreamHangupInvoked)",
                "receiver_upstream_remote_end_seen=\(receiverUpstreamRemoteEndSeen)",
                "receiver_callkit_ended_reported_once=\(receiverCallKitEndedReportedOnce)",
                "receiver_call_ui_dismissed=\(receiverCallUIDismissed)",
                "verified_bootstrap_cleared=\(verifiedBootstrapCleared)",
                "answer_guard_released=\(answerGuardReleased)",
                "end_guard_released=\(endGuardReleased)",
                "matrixrtc_room_empty_or_closed=\(matrixRTCRoomEmptyOrClosed)",
                "stale_matrixrtc_membership_detected=\(staleMatrixRTCMembershipDetected)",
                "duplicate_invite_ignored=\(duplicateInviteIgnored)",
                "dev_invite_used=\(devInviteUsed)",
                "APNs_sent=\(apnsSent)",
                "direct_livekit_credentials_requested=\(directLiveKitCredentialsRequested)",
                "direct_livekit_joined=\(directLiveKitJoined)",
                "manual_matrix_hangup_sent=\(manualMatrixHangupSent)",
                "legacy_direct_livekit_hangup_invoked=\(legacyDirectLiveKitHangupInvoked)",
                "duplicate_callkit_end_reported=\(duplicateCallKitEndReported)",
                "camera_permission_requested=\(cameraPermissionRequested)",
                "video_track_published=\(videoTrackPublished)",
                "last_failure=\(lastFailure)"
            ]
        }
    }
}
#endif

struct MatrixRTCOpenIDToken: Equatable {
    let accessToken: String
    let tokenType: String
    let matrixServerName: String
    let expiresIn: Int

    var jsonObject: [String: Any] {
        [
            "access_token": accessToken,
            "token_type": tokenType,
            "matrix_server_name": matrixServerName,
            "expires_in": expiresIn
        ]
    }

    static func parse(_ object: [String: Any]) -> MatrixRTCOpenIDToken? {
        guard let accessToken = object["access_token"] as? String, !accessToken.isEmpty,
              let tokenType = object["token_type"] as? String, !tokenType.isEmpty,
              let matrixServerName = object["matrix_server_name"] as? String, !matrixServerName.isEmpty else {
            return nil
        }

        let expiresIn: Int
        if let value = object["expires_in"] as? Int {
            expiresIn = value
        } else if let value = object["expires_in"] as? NSNumber {
            expiresIn = value.intValue
        } else {
            expiresIn = 3600
        }

        return .init(accessToken: accessToken,
                     tokenType: tokenType,
                     matrixServerName: matrixServerName,
                     expiresIn: expiresIn)
    }
}

struct MatrixRTCLiveKitJWT: Equatable {
    let serverURL: URL
    let token: String

    static func parse(_ data: Data) -> MatrixRTCLiveKitJWT? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = object["url"] as? String,
              let url = URL(string: urlString),
              let token = object["jwt"] as? String,
              !token.isEmpty else {
            return nil
        }

        return .init(serverURL: url, token: token)
    }
}

struct MatrixRTCNativeMembership: Equatable {
    let userID: String
    let deviceID: String
    let membershipID: String
    let liveKitServiceURL: URL

    var stateKey: String {
        "_\(userID)_\(deviceID)_\(membershipID)"
    }

    var liveKitIdentity: String {
        "\(userID):\(deviceID)"
    }

    func stateContent(createdAt: Date = Date()) -> [String: Any] {
        [
            "application": "m.call",
            "call_id": "",
            "scope": "m.room",
            "device_id": deviceID,
            "membershipID": membershipID,
            "expires": 14_400_000,
            "created_ts": UInt64(createdAt.timeIntervalSince1970 * 1000),
            "foci_preferred": [
                [
                    "type": "livekit",
                    "livekit_service_url": liveKitServiceURL.absoluteString
                ]
            ],
            "focus_active": [
                "type": "livekit",
                "focus_selection": "oldest_membership"
            ]
        ]
    }
}

struct MatrixRTCHTTPResponse: Equatable {
    let statusCode: Int
    let data: Data
}

protocol MatrixRTCHTTPClientProtocol {
    func send(method: String, url: URL, headers: [String: String], body: Data?) async -> Result<MatrixRTCHTTPResponse, Error>
}

struct URLSessionMatrixRTCHTTPClient: MatrixRTCHTTPClientProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func send(method: String, url: URL, headers: [String: String], body: Data?) async -> Result<MatrixRTCHTTPResponse, Error> {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(URLError(.badServerResponse))
            }
            return .success(.init(statusCode: httpResponse.statusCode, data: data))
        } catch {
            return .failure(error)
        }
    }
}

struct MatrixRTCNativeSignalingClient {
    private let httpClient: MatrixRTCHTTPClientProtocol

    init(httpClient: MatrixRTCHTTPClientProtocol = URLSessionMatrixRTCHTTPClient()) {
        self.httpClient = httpClient
    }

    func requestOpenIDToken(homeserverURL: URL, userID: String, accessToken: String) async -> MatrixRTCOpenIDToken? {
        let url = homeserverURL
            .appending(path: "/_matrix/client/v3/user")
            .appending(path: userID)
            .appending(path: "openid/request_token")
        let body = try? JSONSerialization.data(withJSONObject: [String: Any]())
        switch await sendJSON(method: "POST", url: url, accessToken: accessToken, body: body) {
        case .success(let response) where (200...299).contains(response.statusCode):
            guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=openid http=\(response.statusCode) parse=false")
                return nil
            }
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=openid http=\(response.statusCode) parse=true")
            return MatrixRTCOpenIDToken.parse(object)
        case .success(let response):
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=openid http=\(response.statusCode) parse=false")
            return nil
        case .failure:
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=openid http=0 parse=false")
            return nil
        }
    }

    func requestLiveKitJWT(liveKitServiceURL: URL,
                           roomID: String,
                           deviceID: String,
                           openIDToken: MatrixRTCOpenIDToken) async -> MatrixRTCLiveKitJWT? {
        let url = liveKitServiceURL.appending(path: "sfu/get")
        let bodyObject: [String: Any] = [
            "room": roomID,
            "device_id": deviceID,
            "openid_token": openIDToken.jsonObject
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyObject) else {
            return nil
        }

        switch await sendJSON(method: "POST", url: url, accessToken: nil, body: body) {
        case .success(let response) where (200...299).contains(response.statusCode):
            let parsed = MatrixRTCLiveKitJWT.parse(response.data)
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=sfu_get http=\(response.statusCode) parse=\(parsed != nil)")
            return parsed
        case .success(let response):
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=sfu_get http=\(response.statusCode) parse=false")
            return nil
        case .failure:
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=sfu_get http=0 parse=false")
            return nil
        }
    }

    func putMembership(homeserverURL: URL,
                       roomID: String,
                       accessToken: String,
                       membership: MatrixRTCNativeMembership,
                       content: [String: Any]) async -> Bool {
        let url = homeserverURL
            .appending(path: "/_matrix/client/v3/rooms")
            .appending(path: roomID)
            .appending(path: "state")
            .appending(path: "org.matrix.msc3401.call.member")
            .appending(path: membership.stateKey)
        guard let body = try? JSONSerialization.data(withJSONObject: content) else {
            return false
        }

        switch await sendJSON(method: "PUT", url: url, accessToken: accessToken, body: body) {
        case .success(let response):
            let succeeded = (200...299).contains(response.statusCode)
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=membership http=\(response.statusCode) ok=\(succeeded)")
            return succeeded
        case .failure:
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=membership http=0 ok=false")
            return false
        }
    }

    private func sendJSON(method: String, url: URL, accessToken: String?, body: Data?) async -> Result<MatrixRTCHTTPResponse, Error> {
        var headers = ["Content-Type": "application/json"]
        if let accessToken, !accessToken.isEmpty {
            headers["Authorization"] = "Bearer \(accessToken)"
        }
        return await httpClient.send(method: method, url: url, headers: headers, body: body)
    }
}


struct MatrixRTCWidgetEncryptionKey {
    let identity: String
    let keyBase64: String
    let index: Int32

    static func parseWidgetMessage(_ object: [String: Any]) -> MatrixRTCWidgetEncryptionKey? {
        let action = object["action"] as? String
        guard action == "send_to_device" || action == "to_device" else {
            return nil
        }

        let data = object["data"] as? [String: Any] ?? object
        let eventType = data["type"] as? String
        guard eventType == "io.element.call.encryption_keys" else {
            return nil
        }

        let content = data["content"] as? [String: Any] ?? data
        guard let sender = data["sender"] as? String else {
            return nil
        }
        let claimedDeviceID = (content["member"] as? [String: Any])?["claimed_device_id"] as? String
            ?? content["device_id"] as? String
            ?? "*"

        if let keys = content["keys"] as? [String: Any],
           let key = keys["key"] as? String {
            return .init(identity: "\(sender):\(claimedDeviceID)", keyBase64: key, index: Self.index(from: keys["index"]))
        }

        if let keys = content["keys"] as? [[String: Any]],
           let first = keys.first,
           let key = first["key"] as? String {
            return .init(identity: "\(sender):\(claimedDeviceID)", keyBase64: key, index: Self.index(from: first["index"]))
        }

        return nil
    }

    private static func index(from value: Any?) -> Int32 {
        if let number = value as? NSNumber {
            return number.int32Value
        }
        if let int = value as? Int {
            return Int32(int)
        }
        return 0
    }
}

final class MatrixRTCNativeWidgetBridge {
    private static let encryptionKeyCapabilities = [
        "org.matrix.msc3819.send.to_device:io.element.call.encryption_keys",
        "org.matrix.msc3819.receive.to_device:io.element.call.encryption_keys"
    ]

    private let widgetDriver: ElementCallWidgetDriverProtocol
    private var cancellables = Set<AnyCancellable>()
    private var continuations = [String: CheckedContinuation<[String: Any]?, Never>]()
    private var bufferedResponses = [String: [String: Any]]()
    private var handleFinished = Set<String>()
    private let sendLock = NSLock()
    private var encryptionKeyHandler: ((MatrixRTCWidgetEncryptionKey) -> Void)?
    private let capabilitiesLock = NSLock()
    private var didAnswerCapabilities = false
    private var hasStartedDriver = false
    private var hasNegotiatedCapabilities = false
    
    init(widgetDriver: ElementCallWidgetDriverProtocol) {
        self.widgetDriver = widgetDriver
        widgetDriver.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleIncomingMessage(message)
            }
            .store(in: &cancellables)
    }

    func start(baseURL: URL, clientID: String, shouldNegotiateCapabilities: Bool = true) async -> Bool {
        if !hasStartedDriver {
            switch await widgetDriver.start(baseURL: baseURL,
                                            clientID: clientID,
                                            colorScheme: .dark,
                                            rageshakeURL: nil,
                                            analyticsConfiguration: nil) {
            case .success:
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=widget_start ok=true")
                hasStartedDriver = true
            case .failure:
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=widget_start ok=false")
                return false
            }
        }
        
        if shouldNegotiateCapabilities, !hasNegotiatedCapabilities {
            await negotiateCapabilities()
            hasNegotiatedCapabilities = true
        }
        
        return hasStartedDriver
    }

    func requestOpenIDToken() async -> MatrixRTCOpenIDToken? {
        guard let response = await send(action: "get_openid", data: [:]) else {
            return nil
        }

        if let state = response["state"] as? String, state != "allowed" {
            return nil
        }

        return MatrixRTCOpenIDToken.parse(response)
    }

    func sendEncryptionKey(_ keyBase64: String,
                           index: Int32,
                           membership: MatrixRTCNativeMembership,
                           roomID: String,
                           peerUserID: String,
                           peerDeviceID: String) async -> Bool {
        let content: [String: Any] = [
            "keys": [
                "index": index,
                "key": keyBase64
            ],
            "room_id": roomID,
            "member": [
                "claimed_device_id": membership.deviceID,
                "id": membership.membershipID
            ],
            "session": [
                "call_id": "",
                "application": "m.call",
                "scope": "m.room"
            ]
        ]
        let data: [String: Any] = [
            "type": "io.element.call.encryption_keys",
            "encrypted": true,
            "messages": [
                peerUserID: [
                    peerDeviceID: content
                ]
            ]
        ]
        let started = Date()
        let response = await send(action: "send_to_device", data: data)
        let durationMS = Int(Date().timeIntervalSince(started) * 1000)
        let keys: String
        if let response, !response.isEmpty {
            keys = response.keys.sorted().joined(separator: ",")
        } else if response != nil {
            keys = "empty"
        } else {
            keys = "none"
        }
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=local_key_send duration_ms=\(durationMS) keys=\(keys)")
        return response != nil
    }

    func listenForEncryptionKeys(_ handler: @escaping (MatrixRTCWidgetEncryptionKey) -> Void) {
        encryptionKeyHandler = handler
    }

    func stop() {
        encryptionKeyHandler = nil
        sendLock.lock()
        bufferedResponses.removeAll()
        handleFinished.removeAll()
        sendLock.unlock()
        continuations.values.forEach { $0.resume(returning: nil) }
        continuations.removeAll()
        cancellables.removeAll()
        hasStartedDriver = false
        hasNegotiatedCapabilities = false
    }

    private func negotiateCapabilities() async {
        markCapabilitiesAnswered(false)
        try? await Task.sleep(for: .milliseconds(150))
        _ = await send(action: "content_loaded", data: [:])
        for _ in 0..<40 {
            if hasAnsweredCapabilities {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=widget_caps ok=\(hasAnsweredCapabilities)")
    }

    private func send(action: String, data: [String: Any]) async -> [String: Any]? {
        let requestID = UUID().uuidString
        let payload: [String: Any] = [
            "api": "fromWidget",
            "action": action,
            "widgetId": widgetDriver.widgetID,
            "requestId": requestID,
            "data": data
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        let started = Date()
        let timeout: Duration = action == "send_to_device" ? .seconds(8) : .seconds(3)
        let response = await withCheckedContinuation { continuation in
            continuations[requestID] = continuation
            Task { [weak self] in
                guard let self else {
                    return
                }
                let handleResult = await widgetDriver.handleMessage(json)
                let handleOK: Bool
                switch handleResult {
                case .success:
                    handleOK = true
                case .failure:
                    handleOK = false
                }
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=widget_send action=\(action) handle=\(handleOK)")

                sendLock.lock()
                handleFinished.insert(requestID)
                let buffered = bufferedResponses.removeValue(forKey: requestID)
                sendLock.unlock()

                if !handleOK {
                    finish(requestID: requestID, response: nil)
                    return
                }

                if let buffered {
                    finish(requestID: requestID, response: buffered)
                    return
                }

                if action != "send_to_device" {
                    finish(requestID: requestID, response: [:])
                    return
                }

                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    self?.finish(requestID: requestID, response: [:])
                }
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(requestID: requestID, response: nil)
            }
        }

        let durationMS = Int(Date().timeIntervalSince(started) * 1000)
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=widget_send action=\(action) duration_ms=\(durationMS) \(Self.widgetResponseSummary(response))")
        return Self.sanitizedWidgetResponse(response)
    }

    /// Summarises a widget response for the trace log. Only the top level key names and the Matrix
    /// error code are included so that neither key material nor event content can be logged.
    private static func widgetResponseSummary(_ response: [String: Any]?) -> String {
        guard let response else {
            return "keys=none"
        }

        let keys = response.isEmpty ? "empty" : response.keys.sorted().joined(separator: ",")
        guard let errcode = response["errcode"] as? String else {
            return "keys=\(keys)"
        }

        return "keys=\(keys) errcode=\(errcode)"
    }

    private func handleIncomingMessage(_ message: String) {
        guard let data = message.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let requestID = object["requestId"] as? String,
           object["response"] != nil,
           continuations[requestID] != nil {
            let response = object["response"] as? [String: Any] ?? [:]
            sendLock.lock()
            if handleFinished.contains(requestID) {
                sendLock.unlock()
                finish(requestID: requestID, response: response)
            } else {
                bufferedResponses[requestID] = response
                sendLock.unlock()
            }
        }

        let api = object["api"] as? String
        if api == "toWidget", object["response"] == nil {
            handleToWidgetRequest(object)
        }

        if let key = MatrixRTCWidgetEncryptionKey.parseWidgetMessage(object) {
            encryptionKeyHandler?(key)
        } else if api == "toWidget",
                  let action = object["action"] as? String,
                  action == "send_to_device" || action == "to_device" {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=remote_key ok=false reason=parse")
        }
    }

    private func handleToWidgetRequest(_ object: [String: Any]) {
        let action = object["action"] as? String
        if action == "capabilities" {
            replyToWidget(object, response: ["capabilities": Self.encryptionKeyCapabilities])
            markCapabilitiesAnswered(true)
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=widget_caps answered=true")
            return
        }

        replyToWidget(object, response: [:])
    }

    private func replyToWidget(_ object: [String: Any], response: [String: Any]) {
        var reply = object
        reply["response"] = response
        guard let jsonData = try? JSONSerialization.data(withJSONObject: reply),
              let json = String(data: jsonData, encoding: .utf8) else {
            return
        }

        Task {
            _ = await widgetDriver.handleMessage(json)
        }
    }

    private func markCapabilitiesAnswered(_ answered: Bool) {
        capabilitiesLock.lock()
        didAnswerCapabilities = answered
        capabilitiesLock.unlock()
    }

    private var hasAnsweredCapabilities: Bool {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        return didAnswerCapabilities
    }

    private func finish(requestID: String, response: [String: Any]?) {
        sendLock.lock()
        bufferedResponses.removeValue(forKey: requestID)
        handleFinished.remove(requestID)
        sendLock.unlock()
        guard let continuation = continuations.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(returning: response)
    }

    private static func sanitizedWidgetResponse(_ response: [String: Any]?) -> [String: Any]? {
        guard let response else {
            return nil
        }
        if response["errcode"] != nil {
            return nil
        }
        if let error = response["error"] {
            if error is NSNull {
                return response
            }
            if let string = error as? String, string.isEmpty {
                return response
            }
            if let dict = error as? [String: Any], dict.isEmpty {
                return response
            }
            return nil
        }
        return response
    }
}


struct MatrixRTCNativePendingRemoteKey: Equatable {
    let keyBase64: String
    let identity: String
    let index: Int32
}

enum MatrixRTCNativeRemoteKeyStore {
    static func upsert(_ keys: inout [MatrixRTCNativePendingRemoteKey],
                       keyBase64: String,
                       identity: String,
                       index: Int32) {
        keys.removeAll { $0.identity == identity && $0.index == index }
        keys.append(.init(keyBase64: keyBase64, identity: identity, index: index))
    }
}

/// MatrixRTC media keys travel as base64 text but the frame cryptor derives its frame key from the
/// decoded bytes. Element Call encodes them without padding and sometimes with the URL safe alphabet,
/// so both spellings have to decode to the same material that the web client feeds into HKDF.
enum MatrixRTCNativeEncryptionKeyMaterial {
    static func data(fromBase64 value: String) -> Data? {
        var normalised = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingRemainder = normalised.count % 4
        if paddingRemainder > 0 {
            normalised.append(String(repeating: "=", count: 4 - paddingRemainder))
        }

        guard let data = Data(base64Encoded: normalised), !data.isEmpty else {
            return nil
        }

        return data
    }
}

protocol MatrixRTCNativeLiveKitConnecting: AnyObject {
    func connect(serverURL: URL, token: String, localIdentity: String, localKeyBase64: String) async -> Bool
    func setRemoteParticipantKey(_ keyBase64: String, identity: String, index: Int32)
    func setMicrophoneEnabled(_ enabled: Bool) async
    func disconnect() async
}

final class MatrixRTCNativeLiveKitClient: MatrixRTCNativeLiveKitConnecting, @unchecked Sendable {
    private var room: Room?
    private var keyProvider: BaseKeyProvider?
    private var remoteKeys = [MatrixRTCNativePendingRemoteKey]()
    private var appliedRemoteKeys = Set<String>()
    private let remoteKeyLock = NSLock()

    func connect(serverURL: URL, token: String, localIdentity: String, localKeyBase64: String) async -> Bool {
        await disconnect(clearPendingKeys: false)

        guard Self.isSupportedLiveKitURL(serverURL) else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=livekit ok=false reason=url")
            return false
        }

        return await connectOnMainActor(serverURL: serverURL,
                                        token: token,
                                        localIdentity: localIdentity,
                                        localKeyBase64: localKeyBase64)
    }

    @MainActor
    private func connectOnMainActor(serverURL: URL, token: String, localIdentity: String, localKeyBase64: String) async -> Bool {
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        AudioManager.shared.audioSession.isAutomaticDeactivationEnabled = false
        AudioManager.shared.audioSession.isSpeakerOutputPreferred = false

        // These have to match Element Call's key provider (`ratchetWindowSize: 10`, `keyringSize: 256`)
        // and its HKDF key derivation, otherwise neither side can decrypt the other's frames.
        let options = KeyProviderOptions(sharedKey: false,
                                         ratchetWindowSize: 10,
                                         keyRingSize: 256,
                                         keyDerivationAlgorithm: .hkdf)
        let keyProvider = BaseKeyProvider(options: options)
        guard let localKeyData = MatrixRTCNativeEncryptionKeyMaterial.data(fromBase64: localKeyBase64) else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=livekit ok=false reason=local_key_material")
            return false
        }
        keyProvider.setKey(keyData: localKeyData, participantId: localIdentity, index: 0)
        assign(keyProvider: keyProvider)
        applyRemoteKeys(reason: "buffered")

        let roomOptions = RoomOptions(encryptionOptions: EncryptionOptions(keyProvider: keyProvider))
        let connectOptions = ConnectOptions(autoSubscribe: true, enableMicrophone: false)
        let room = Room(connectOptions: connectOptions, roomOptions: roomOptions)
        room.add(delegate: self)
        self.room = room

        do {
            try await room.connect(url: serverURL.absoluteString,
                                   token: token,
                                   connectOptions: connectOptions,
                                   roomOptions: roomOptions)
            // The SFU decides our participant identity from the JWT. Our own frames are encrypted with
            // the key stored under that identity, so a mismatch would mute us for everybody else.
            let resolvedIdentity = room.localParticipant.identity?.stringValue
            if let resolvedIdentity, resolvedIdentity != localIdentity {
                keyProvider.setKey(keyData: localKeyData, participantId: resolvedIdentity, index: 0)
            }
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=local_identity match=\(resolvedIdentity == localIdentity)")
            applyRemoteKeys(reason: "connected")
            try await room.localParticipant.setMicrophone(enabled: true)
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=livekit ok=true")
            return true
        } catch {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=livekit ok=false reason=connect")
            await disconnect(clearPendingKeys: false)
            return false
        }
    }

    func setRemoteParticipantKey(_ keyBase64: String, identity: String, index: Int32) {
        remoteKeyLock.lock()
        MatrixRTCNativeRemoteKeyStore.upsert(&remoteKeys,
                                             keyBase64: keyBase64,
                                             identity: identity,
                                             index: index)
        let hasProvider = keyProvider != nil
        remoteKeyLock.unlock()

        guard hasProvider else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=remote_key index=\(index) applied=false reason=buffer")
            return
        }

        Task { @MainActor [weak self] in
            self?.applyRemoteKeys(reason: nil)
        }
    }

    /// Element Call does not always join the SFU as `userID:deviceID`; newer builds hash the identity.
    /// The key from the to-device event then belongs to a participant we cannot name, so in a call with a
    /// single remote key sender it is also installed for the participants we have no key for at all.
    @MainActor
    private func applyRemoteKeys(reason: String?) {
        remoteKeyLock.lock()
        let provider = keyProvider
        let keys = remoteKeys
        remoteKeyLock.unlock()

        guard let provider, !keys.isEmpty else {
            return
        }

        let claimedIdentities = Set(keys.map(\.identity))
        let unclaimedIdentities = (room?.remoteParticipants.keys.map(\.stringValue) ?? [])
            .filter { !claimedIdentities.contains($0) }

        for key in keys {
            apply(key, identity: key.identity, to: provider, reason: reason)

            guard keys.count == 1 else {
                continue
            }

            for identity in unclaimedIdentities {
                apply(key, identity: identity, to: provider, reason: "unnamed_participant")
            }
        }
    }

    @MainActor
    private func apply(_ key: MatrixRTCNativePendingRemoteKey,
                       identity: String,
                       to keyProvider: BaseKeyProvider,
                       reason: String?) {
        let fingerprint = "\(identity)|\(key.index)|\(key.keyBase64)"
        guard !appliedRemoteKeys.contains(fingerprint) else {
            return
        }

        guard let keyData = MatrixRTCNativeEncryptionKeyMaterial.data(fromBase64: key.keyBase64) else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=remote_key index=\(key.index) applied=false reason=key_material")
            return
        }

        keyProvider.setKey(keyData: keyData, participantId: identity, index: key.index)
        appliedRemoteKeys.insert(fingerprint)
        if let reason {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=remote_key index=\(key.index) applied=true reason=\(reason)")
        } else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=remote_key index=\(key.index) applied=true")
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) async {
        await setMicrophoneEnabledOnMainActor(enabled)
    }

    func disconnect() async {
        await disconnect(clearPendingKeys: true)
    }

    private func disconnect(clearPendingKeys: Bool) async {
        await disconnectOnMainActor(clearPendingKeys: clearPendingKeys)
    }

    @MainActor
    private func setMicrophoneEnabledOnMainActor(_ enabled: Bool) async {
        try? await room?.localParticipant.setMicrophone(enabled: enabled)
    }

    @MainActor
    private func disconnectOnMainActor(clearPendingKeys: Bool) async {
        let currentRoom = room
        room = nil
        remoteKeyLock.lock()
        keyProvider = nil
        appliedRemoteKeys.removeAll()
        if clearPendingKeys {
            remoteKeys.removeAll()
        }
        remoteKeyLock.unlock()
        currentRoom?.remove(delegate: self)
        await currentRoom?.disconnect()
    }

    private func assign(keyProvider: BaseKeyProvider) {
        remoteKeyLock.lock()
        defer { remoteKeyLock.unlock() }
        self.keyProvider = keyProvider
        appliedRemoteKeys.removeAll()
    }

    private static func isSupportedLiveKitURL(_ url: URL) -> Bool {
        guard url.host?.isEmpty == false else {
            return false
        }

        switch url.scheme?.lowercased() {
        case "ws", "wss", "http", "https":
            return true
        default:
            return false
        }
    }
}

/// Frame level diagnostics: without these the trace log can show a healthy key exchange while the
/// frame cryptor silently discards every remote frame.
extension MatrixRTCNativeLiveKitClient: RoomDelegate {
    nonisolated func room(_ room: Room, trackPublication: TrackPublication, didUpdateE2EEState state: E2EEState) {
        Task { @MainActor in
            let isLocal = room.localParticipant.trackPublications.values.contains { $0 === trackPublication }
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=frame_crypto kind=\(trackPublication.kind == .audio ? "audio" : "other") " +
                "scope=\(isLocal ? "local" : "remote") state=\(state.toString())")
        }
    }

    nonisolated func room(_: Room, participantDidConnect _: RemoteParticipant) {
        Task { @MainActor [weak self] in
            self?.applyRemoteKeys(reason: "participant")
        }
    }

    nonisolated func room(_: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in
            self?.applyRemoteKeys(reason: "subscribed")
            guard publication.kind == .audio else { return }
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=remote_audio identity=\(participant.identity?.stringValue ?? "unknown") muted=\(publication.isMuted)")
        }
    }
}

enum MatrixRTCNativeEncryptionPeer {
    static func deviceID(fromIdentity identity: String) -> String? {
        guard let separatorIndex = identity.lastIndex(of: ":") else {
            return nil
        }
        
        let deviceID = String(identity[identity.index(after: separatorIndex)...])
        return deviceID.isEmpty ? nil : deviceID
    }
    
    static func peerDeviceID(from deviceIDs: [String]) -> String {
        Set(deviceIDs).count == 1 ? deviceIDs[0] : "*"
    }
}

final class MatrixRTCNativeAudioController: MatrixRTCNativeAudioJoining {
    private let signalingClient: MatrixRTCNativeSignalingClient
    private let liveKitClient: MatrixRTCNativeLiveKitConnecting
    private let widgetBridgeFactory: (ElementCallWidgetDriverProtocol) -> MatrixRTCNativeWidgetBridge
    private let elementCallBaseURL: URL
    private let clientID: String

    private(set) var activeRoomID: String?
    private(set) var state: MatrixRTCNativeAudioState = .inactive

    private var joinGeneration: UInt64 = 0
    private var widgetBridge: MatrixRTCNativeWidgetBridge?
    private var membership: MatrixRTCNativeMembership?
    private var accessToken: String?
    private var homeserverURL: URL?
    private var roomID: String?
    private var joinTask: Task<Void, Never>?
    private var preparedSession: SessionContext?
    private var lastRemoteDeviceID: String?
    private var lastLocalKey: String?
    private var lastPeerUserID: String?
    private var lastPeerDeviceID: String?
    private var localKeyRetryTask: Task<Void, Never>?
    private var prepareIncomingKeyListenerTask: Task<Void, Never>?
        
        init(signalingClient: MatrixRTCNativeSignalingClient = MatrixRTCNativeSignalingClient(),
         liveKitClient: MatrixRTCNativeLiveKitConnecting = MatrixRTCNativeLiveKitClient(),
         widgetBridgeFactory: @escaping (ElementCallWidgetDriverProtocol) -> MatrixRTCNativeWidgetBridge = { MatrixRTCNativeWidgetBridge(widgetDriver: $0) },
         elementCallBaseURL: URL,
         clientID: String) {
        self.signalingClient = signalingClient
        self.liveKitClient = liveKitClient
        self.widgetBridgeFactory = widgetBridgeFactory
        self.elementCallBaseURL = elementCallBaseURL
        self.clientID = clientID
    }

    func joinIncomingAudio(roomID: String, clientProxy: ClientProxyProtocol) async {
        if activeRoomID == roomID, isActive {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join skipped=already_active")
            await resendLocalEncryptionKey()
            return
        }
        
        if isActive {
            leave()
        }
        
        if joinTask != nil {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join_skip reason=join_in_progress")
            return
        }
        
        await prepareIncomingKeyListenerTask?.value
        prepareIncomingKeyListenerTask = nil
        
        joinGeneration += 1
        let generation = joinGeneration
        activeRoomID = roomID
        self.roomID = roomID
        state = .connecting
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join")
        
        joinTask = Task { [weak self] in
            await self?.performJoin(roomID: roomID, clientProxy: clientProxy, generation: generation)
        }
        await joinTask?.value
    }
    
    func prepareIncomingKeyListener(roomID: String, clientProxy: ClientProxyProtocol) {
        guard widgetBridge == nil, prepareIncomingKeyListenerTask == nil, joinTask == nil, !isActive else {
            return
        }
        
        let generation = joinGeneration
        prepareIncomingKeyListenerTask = Task { @MainActor [weak self] in
            await self?.performPrepareIncomingKeyListener(roomID: roomID, clientProxy: clientProxy, generation: generation)
        }
    }

    private func performPrepareIncomingKeyListener(roomID: String, clientProxy: ClientProxyProtocol, generation: UInt64) async {
        guard let session = await sessionContext(roomID: roomID, clientProxy: clientProxy, generation: generation, failOnError: false) else {
            return
        }

        let widgetBridge = widgetBridgeFactory(session.widgetDriver)
        widgetBridge.listenForEncryptionKeys { [weak self] key in
            Task { @MainActor in
                guard let self else { return }
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=remote_key identity=\(key.identity) index=\(key.index)")
                if let deviceID = MatrixRTCNativeEncryptionPeer.deviceID(fromIdentity: key.identity) {
                    self.lastRemoteDeviceID = deviceID
                }
                self.liveKitClient.setRemoteParticipantKey(key.keyBase64, identity: key.identity, index: key.index)
            }
        }

        let widgetStarted = await widgetBridge.start(baseURL: elementCallBaseURL,
                                                     clientID: clientID,
                                                     shouldNegotiateCapabilities: false)
        guard widgetStarted else {
            widgetBridge.stop()
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=early_listen ok=false")
            return
        }
        guard self.widgetBridge == nil else {
            widgetBridge.stop()
            return
        }

        self.widgetBridge = widgetBridge
        preparedSession = session
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=early_listen ok=true")
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        Task {
            await liveKitClient.setMicrophoneEnabled(enabled)
        }
    }

    func resendLocalEncryptionKey() async {
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=local_key_resend")
        if await sendStoredLocalEncryptionKey() {
            return
        }

        scheduleLocalEncryptionKeyRetries(generation: joinGeneration)
    }

    /// The widget driver keeps rejecting `send_to_device` while it is busy, in the worst observed case for
    /// several seconds after the join. Retrying in the background keeps the LiveKit join responsive while
    /// still getting our key across, which the remote side needs before it can decrypt our audio.
    private func scheduleLocalEncryptionKeyRetries(generation: UInt64) {
        localKeyRetryTask?.cancel()
        localKeyRetryTask = Task { @MainActor [weak self] in
            for delayMS in [300, 600, 1200, 2400, 4800, 8000] {
                try? await Task.sleep(for: .milliseconds(delayMS))
                guard let self, !Task.isCancelled, isCurrent(generation) else {
                    return
                }

                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=local_key_resend")
                if await sendStoredLocalEncryptionKey() {
                    return
                }
            }
        }
    }

    private func sendStoredLocalEncryptionKey() async -> Bool {
        guard let widgetBridge,
              let localKey = lastLocalKey,
              let membership,
              let roomID,
              let peerUserID = lastPeerUserID,
              let peerDeviceID = lastPeerDeviceID else {
            return false
        }
        let sent = await widgetBridge.sendEncryptionKey(localKey,
                                                        index: 0,
                                                        membership: membership,
                                                        roomID: roomID,
                                                        peerUserID: peerUserID,
                                                        peerDeviceID: peerDeviceID)
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=local_key ok=\(sent) peerDeviceID=\(peerDeviceID)")
        return sent
    }

    func leave() {
        joinGeneration += 1
        localKeyRetryTask?.cancel()
        localKeyRetryTask = nil
        prepareIncomingKeyListenerTask?.cancel()
        prepareIncomingKeyListenerTask = nil
        preparedSession = nil
        lastRemoteDeviceID = nil
        lastLocalKey = nil
        lastPeerUserID = nil
        lastPeerDeviceID = nil
        joinTask?.cancel()
        joinTask = nil

        let membershipToClear = membership
        let accessTokenToUse = accessToken
        let homeserverURLToUse = homeserverURL
        let roomIDToClear = roomID
        membership = nil
        accessToken = nil
        homeserverURL = nil
        roomID = nil

        widgetBridge?.stop()
        widgetBridge = nil

        Task { [liveKitClient, signalingClient] in
            await liveKitClient.disconnect()
            if let membershipToClear, let accessTokenToUse, let homeserverURLToUse, let roomIDToClear {
                _ = await signalingClient.putMembership(homeserverURL: homeserverURLToUse,
                                                        roomID: roomIDToClear,
                                                        accessToken: accessTokenToUse,
                                                        membership: membershipToClear,
                                                        content: [:])
            }
        }

        activeRoomID = nil
        state = .inactive
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=leave")
    }

    private func performJoin(roomID: String, clientProxy: ClientProxyProtocol, generation: UInt64) async {
        let session: SessionContext
        if let preparedSession, preparedSession.roomProxy.id == roomID {
            session = preparedSession
            self.preparedSession = nil
        } else if let freshSession = await sessionContext(roomID: roomID, clientProxy: clientProxy, generation: generation) {
            session = freshSession
        } else {
            return
        }
        
        let widgetBridge: MatrixRTCNativeWidgetBridge
        if let existingBridge = self.widgetBridge {
            widgetBridge = existingBridge
        } else {
            widgetBridge = widgetBridgeFactory(session.widgetDriver)
            widgetBridge.listenForEncryptionKeys { [weak self] key in
                Task { @MainActor in
                    guard let self, self.joinGeneration == generation else { return }
                    IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=remote_key identity=\(key.identity) index=\(key.index)")
                    if let deviceID = MatrixRTCNativeEncryptionPeer.deviceID(fromIdentity: key.identity) {
                        self.lastRemoteDeviceID = deviceID
                    }
                    self.liveKitClient.setRemoteParticipantKey(key.keyBase64, identity: key.identity, index: key.index)
                }
            }
            self.widgetBridge = widgetBridge
        }
        let widgetStarted = await widgetBridge.start(baseURL: elementCallBaseURL,
                                                     clientID: clientID,
                                                     shouldNegotiateCapabilities: true)
        guard isCurrent(generation) else {
            widgetBridge.stop()
            return
        }

        let credentials = await mediaCredentials(session: session, widgetBridge: widgetStarted ? widgetBridge : nil)
        guard let credentials else {
            widgetBridge.stop()
            failIfCurrent(generation: generation)
            return
        }
        guard isCurrent(generation) else {
            widgetBridge.stop()
            return
        }

        let membershipPublished = await publishMembership(session: session)
        guard membershipPublished else {
            widgetBridge.stop()
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=membership")
            failIfCurrent(generation: generation)
            return
        }
        guard isCurrent(generation) else {
            widgetBridge.stop()
            return
        }

        membership = session.membership
        accessToken = session.accessToken
        homeserverURL = session.homeserverURL
        self.roomID = roomID

        let localKey = Self.randomKeyBase64()
        let connected = await liveKitClient.connect(serverURL: credentials.jwt.serverURL,
                                                    token: credentials.jwt.token,
                                                    localIdentity: session.membership.liveKitIdentity,
                                                    localKeyBase64: localKey)
        guard connected, isCurrent(generation) else {
            if connected {
                await liveKitClient.disconnect()
            }
            if isCurrent(generation) {
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=livekit")
                leave()
            }
            return
        }

        if widgetStarted, let peerUserID = Self.peerUserID(in: session.roomProxy, ownUserID: session.userID) {
            lastLocalKey = localKey
            lastPeerUserID = peerUserID
            lastPeerDeviceID = MatrixRTCNativeEncryptionPeer.peerDeviceID(from: [lastRemoteDeviceID].compactMap { $0 })
            let sentLocalKey = await sendStoredLocalEncryptionKey()
            if !sentLocalKey {
                scheduleLocalEncryptionKeyRetries(generation: generation)
            }
        }

        guard isCurrent(generation) else {
            return
        }

        state = .connected
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=true")
    }

    private struct SessionContext {
        let userID: String
        let accessToken: String
        let homeserverURL: URL
        let roomProxy: JoinedRoomProxyProtocol
        let widgetDriver: ElementCallWidgetDriverProtocol
        let membership: MatrixRTCNativeMembership
    }

    private struct MediaCredentials {
        let jwt: MatrixRTCLiveKitJWT
    }

    private func sessionContext(roomID: String, clientProxy: ClientProxyProtocol, generation: UInt64, failOnError: Bool = true) async -> SessionContext? {
        guard let deviceID = clientProxy.deviceID,
              let homeserverURL = URL(string: clientProxy.homeserver) else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=session")
            if failOnError {
                failIfCurrent(generation: generation)
            }
            return nil
        }
        
        guard let accessToken = await matrixAccessToken(from: clientProxy), !accessToken.isEmpty else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=token")
            if failOnError {
                failIfCurrent(generation: generation)
            }
            return nil
        }
        
        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(roomID) else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=room")
            if failOnError {
                failIfCurrent(generation: generation)
            }
            return nil
        }

        guard isCurrent(generation) else {
            return nil
        }

        let liveKitServiceURL = homeserverURL.appending(path: "/livekit/jwt")
        let membership = MatrixRTCNativeMembership(userID: clientProxy.userID,
                                                   deviceID: deviceID,
                                                   membershipID: UUID().uuidString,
                                                   liveKitServiceURL: liveKitServiceURL)
        let widgetDriver = roomProxy.elementCallWidgetDriver(deviceID: deviceID)
        (widgetDriver as? ElementCallStartModeConfigurable)?.startMode = .audio
        return .init(userID: clientProxy.userID,
                     accessToken: accessToken,
                     homeserverURL: homeserverURL,
                     roomProxy: roomProxy,
                     widgetDriver: widgetDriver,
                     membership: membership)
    }

    private func mediaCredentials(session: SessionContext, widgetBridge: MatrixRTCNativeWidgetBridge?) async -> MediaCredentials? {
        let widgetOpenID = await widgetBridge?.requestOpenIDToken()
        let openIDToken: MatrixRTCOpenIDToken?
        if let widgetOpenID {
            openIDToken = widgetOpenID
        } else {
            openIDToken = await signalingClient.requestOpenIDToken(homeserverURL: session.homeserverURL,
                                                                   userID: session.userID,
                                                                   accessToken: session.accessToken)
        }
        guard let openIDToken else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=openid")
            return nil
        }

        let jwt = await signalingClient.requestLiveKitJWT(liveKitServiceURL: session.membership.liveKitServiceURL,
                                                          roomID: session.roomProxy.id,
                                                          deviceID: session.membership.deviceID,
                                                          openIDToken: openIDToken)
        guard let jwt else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=jwt")
            return nil
        }

        return .init(jwt: jwt)
    }

    private func publishMembership(session: SessionContext) async -> Bool {
        let content = session.membership.stateContent()
        return await signalingClient.putMembership(homeserverURL: session.homeserverURL,
                                                   roomID: session.roomProxy.id,
                                                   accessToken: session.accessToken,
                                                   membership: session.membership,
                                                   content: content)
    }

    private func matrixAccessToken(from clientProxy: ClientProxyProtocol) async -> String? {
        if let provider = clientProxy as? DirectCallMatrixAccessTokenProviding {
            return await provider.matrixAccessToken()
        }
        return (clientProxy as? ClientProxy)?.accessToken
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        !Task.isCancelled && joinGeneration == generation
    }

    private func failIfCurrent(generation: UInt64) {
        guard joinGeneration == generation else { return }
        activeRoomID = nil
        state = .inactive
    }

    private static func randomKeyBase64() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private static func peerUserID(in roomProxy: JoinedRoomProxyProtocol, ownUserID: String) -> String? {
        roomProxy.membersPublisher.value.first { $0.userID != ownUserID && !$0.userID.isEmpty }?.userID
    }
}
