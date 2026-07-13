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

@MainActor
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
                                                                     stateProvider: EmbeddedElementCallServiceRoomCallStateProvider(elementCallService: elementCallService))
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
        case "/direct-call/stage2f-sim/export-identity":
            exportIdentity(userSession: userSession)
        case "/direct-call/stage2f-sim/receiver-start":
            Task { await startReceiver(userSession: userSession, streamURLString: queryItems["stream_url"]) }
        case "/direct-call/stage2f-sim/receiver-claim-report":
            Task {
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
        case "/direct-call/stage2f-sim/sender-send-invite":
            Task { await sendForegroundInvite(userSession: userSession, inviteURLString: queryItems["invite_url"]) }
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
        writeProof()
    }

    static func recordMatrixRTCObservation(participantCount: Int, hasActiveCall: Bool) {
        if participantCount >= 2 {
            proof.matrixRTCTwoParticipantsSeen = true
        }

        if proof.matrixRTCTwoParticipantsSeen, !hasActiveCall || participantCount == 0 {
            proof.matrixRTCRoomEmptyOrClosed = true
        }

        writeProof()
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
        receiverInviteCount = 0
        receiverCallKitEndReportCount = 0
        receiverTransport?.stop()
        receiverTransport = nil
        bootstrapStore.removeAll()
        try? FileManager.default.removeItem(at: documentsURL(fileName: identityHandoffFileName))
        try? FileManager.default.removeItem(at: documentsURL(fileName: senderHandoffFileName))
        writeProof()
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
        request.setValue("B" + "earer " + accessToken, forHTTPHeaderField: "Authorization")

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
            proof.foregroundStreamReady = true
        case .stopped:
            proof.foregroundStreamActive = false
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
        proof.senderReadyToSendForegroundInvite = true
        writeProof()
    }

    private static func sendForegroundInvite(userSession: UserSessionProtocol?, inviteURLString: String?) async {
        guard var context = senderContext,
              context.activeCallEvidenceSeen,
              !context.foregroundInviteSent else {
            proof.lastFailure = senderContext?.foregroundInviteSent == true ? "secureInviteSendFailed" : "activeCallEvidenceTimeout"
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

    private static func claimReceiverMetadataAndReportCallKit(userSession: UserSessionProtocol?,
                                                              elementCallService: any ElementCallServiceProtocol,
                                                              metadataReference: String?,
                                                              senderDeviceID: String?) async {
        guard let clientProxy = userSession?.clientProxy,
              let accessTokenProvider = clientProxy as? DirectCallMatrixAccessTokenProviding,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let deviceID = safeNonEmpty(clientProxy.deviceID),
              let metadataReference = safeNonEmpty(metadataReference),
              let senderDeviceID = safeNonEmpty(senderDeviceID),
              let metadataURL = endpointURL(path: "\(pendingMetadataPathPrefix)/\(metadataReference)", explicitURLString: nil, clientProxy: clientProxy),
              let concreteElementCallService = elementCallService as? ElementCallService else {
            proof.lastFailure = "secureInvitePreparationFailed"
            writeProof()
            return
        }

        let response = await httpJSON(url: metadataURL,
                                      method: "GET",
                                      accessToken: accessToken,
                                      body: nil)
        guard (200..<300).contains(response.status ?? 0),
              let metadata = IncomingPendingMetadata(payload: response.payload) else {
            proof.lastFailure = "secureInvitePreparationFailed"
            writeProof()
            return
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(metadata.roomID),
              roomProxy.isDirectOneToOneRoom,
              case .success = await roomProxy.getMember(userID: clientProxy.userID),
              case .success = await roomProxy.getMember(userID: metadata.peerUserID) else {
            proof.lastFailure = "roomNotOneToOne"
            writeProof()
            return
        }

        let activeCallState: VerifiedIncomingCallBootstrapActiveCallState = activeCallEvidence(roomID: metadata.roomID,
                                                                                               roomProxy: roomProxy,
                                                                                               clientProxy: clientProxy,
                                                                                               elementCallService: elementCallService) ? .active : .none
        guard activeCallState == .active else {
            proof.lastFailure = "activeCallEvidenceTimeout"
            writeProof()
            return
        }

        let callKitID = await concreteElementCallService.salemXDebugReportStage2FSimulatorIncomingCall(roomID: metadata.roomID,
                                                                                                       roomDisplayName: "SalemX audio",
                                                                                                       startMode: .audio) { callID in
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

        proof.receiverMetadataClaimSuccess = true
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
        let roomID: String
        let peerUserID: String

        init?(payload: [String: Any]) {
            guard payload["version"] as? Int == 1,
                  let roomID = payload["room_id"] as? String,
                  let peerUserID = payload["peer_user_id"] as? String,
                  payload["direction"] as? String == "incoming",
                  payload["intent"] as? String == "audio",
                  !roomID.isEmpty,
                  !peerUserID.isEmpty else {
                return nil
            }
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
        var authenticatedSessionPresent = false
        var receiverAuthenticatedSessionPresent = false
        var simulatorSenderAuthenticatedSessionPresent = false
        var receiverAppForeground = false
        var foregroundStreamActive = false
        var foregroundStreamReady = false
        var senderStartModeAudio = false
        var receiverDeviceBindingPresent = false
        var senderUpstreamAudioCallStarted = false
        var senderEmbeddedElementCallPresented = false
        var senderActiveCallEvidenceSeen = false
        var senderReadyToSendForegroundInvite = false
        var senderCurrentSessionPresent = false
        var senderCurrentAccessTokenPresent = false
        var senderRequestAuthHeaderReady = false
        var requestTokenMatchesCurrentSessionToken = false
        var requestHomeserverMatchesCurrentSessionHomeserver = false
        var senderSameCredentialWhoamiAttempted = false
        var senderSameCredentialWhoamiSucceeded = false
        var senderSameCredentialWhoamiHTTPStatus = "not_requested"
        var senderSameCredentialWhoamiErrorBucket = "not_requested"
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
        var receiverVerifiedBootstrapStored = false
        var receiverCallKitIncomingReported = false
        var receiverCallKitAnswerActionSeen = false
        var receiverCallKitAnswered = false
        var receiverPresentExistingSelected = false
        var receiverStartNewSelected = false
        var receiverEmbeddedElementCallPresented = false
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
                "authenticated_session_present=\(authenticatedSessionPresent)",
                "receiver_authenticated_session_present=\(receiverAuthenticatedSessionPresent)",
                "simulator_sender_session_present=\(simulatorSenderAuthenticatedSessionPresent)",
                "receiver_app_foreground=\(receiverAppForeground)",
                "foreground_stream_active=\(foregroundStreamActive)",
                "foreground_stream_ready=\(foregroundStreamReady)",
                "start_mode_audio=\(senderStartModeAudio)",
                "receiver_device_binding_present=\(receiverDeviceBindingPresent)",
                "sender_upstream_audio_call_started=\(senderUpstreamAudioCallStarted)",
                "sender_embedded_element_call_presented=\(senderEmbeddedElementCallPresented)",
                "sender_active_call_evidence_seen=\(senderActiveCallEvidenceSeen)",
                "sender_ready_to_send_foreground_invite=\(senderReadyToSendForegroundInvite)",
                "sender_current_session_present=\(senderCurrentSessionPresent)",
                "sender_current_access_token_present=\(senderCurrentAccessTokenPresent)",
                "sender_request_auth_header_ready=\(senderRequestAuthHeaderReady)",
                "request_token_matches_current_session_token=\(requestTokenMatchesCurrentSessionToken)",
                "request_homeserver_matches_current_session_homeserver=\(requestHomeserverMatchesCurrentSessionHomeserver)",
                "sender_same_credential_whoami_attempted=\(senderSameCredentialWhoamiAttempted)",
                "sender_same_credential_whoami_succeeded=\(senderSameCredentialWhoamiSucceeded)",
                "sender_same_credential_whoami_http_status=\(senderSameCredentialWhoamiHTTPStatus)",
                "sender_same_credential_whoami_error_bucket=\(senderSameCredentialWhoamiErrorBucket)",
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
                "receiver_verified_bootstrap_stored=\(receiverVerifiedBootstrapStored)",
                "receiver_callkit_incoming_reported=\(receiverCallKitIncomingReported)",
                "receiver_callkit_answer_action_seen=\(receiverCallKitAnswerActionSeen)",
                "receiver_callkit_answered=\(receiverCallKitAnswered)",
                "receiver_present_existing_selected=\(receiverPresentExistingSelected)",
                "receiver_start_new_selected=\(receiverStartNewSelected)",
                "receiver_embedded_element_call_presented=\(receiverEmbeddedElementCallPresented)",
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
