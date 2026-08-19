//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CallKit
import Combine

enum ElementCallServiceAction {
    case receivedIncomingCallRequest
    case startCall(roomID: String, startMode: ElementCallStartMode)
    case endCall(roomID: String)
    case requestCallTermination(roomID: String)
    case setAudioEnabled(_ enabled: Bool, roomID: String)
}

enum EmbeddedElementCallHandoffIntent: Equatable {
    case startNew
    case joinExisting
    case presentExisting
}

enum EmbeddedElementCallLifecycleEvent: Equatable, CaseIterable {
    case presented
    case joining
    case connected
    case remoteEnded
    case localEnded
    case failed
    case dismissed
}

struct EmbeddedElementCallPreparation: Equatable {
    let roomID: String
    let intent: EmbeddedElementCallHandoffIntent
    let startMode: ElementCallStartMode
    let lifecycleEvents: [EmbeddedElementCallLifecycleEvent]

    var cameraRequested: Bool {
        false
    }

    var videoEnabled: Bool {
        false
    }

    static func audio(roomID: String, intent: EmbeddedElementCallHandoffIntent) -> Self {
        .init(roomID: roomID,
              intent: intent,
              startMode: .audio,
              lifecycleEvents: EmbeddedElementCallLifecycleEvent.allCases)
    }
}

enum EmbeddedElementCallHandoffResult: Equatable {
    case readyToPresent(EmbeddedElementCallPreparation)
    case alreadyPresented(EmbeddedElementCallPreparation)
    case noExistingCall(EmbeddedElementCallPreparation)
    case unsupportedIncomingJoin(EmbeddedElementCallPreparation)
}

enum EmbeddedElementCallTerminationResult: Equatable {
    case accepted
    case alreadyTerminated
    case roomUnavailable
    case noActiveCall
    case unsupported
    case failed
}

struct SalemXEmbeddedCallAnswerBridgeConfiguration: Equatable {
    var embeddedMatrixRTCAnswerBridgeEnabled = false
    var answerTimeout: Duration = .seconds(8)
    var endTimeout: Duration = .seconds(8)
}

protocol SalemXCallKitAnswerActionCompleting: AnyObject {
    var callUUID: UUID { get }

    func fulfill()
    func fail()
}

extension CXAnswerCallAction: SalemXCallKitAnswerActionCompleting { }

protocol SalemXCallKitEndActionCompleting: AnyObject {
    var callUUID: UUID { get }

    func fulfill()
    func fail()
}

extension CXEndCallAction: SalemXCallKitEndActionCompleting { }

@MainActor
protocol EmbeddedElementCallHandoff {
    func prepareAudioCall(roomID: String, intent: EmbeddedElementCallHandoffIntent) async -> EmbeddedElementCallHandoffResult
}

@MainActor
protocol EmbeddedElementCallTerminating {
    func terminateEmbeddedElementCall(roomID: String) async -> EmbeddedElementCallTerminationResult
}

@MainActor
protocol EmbeddedElementCallRoomCallPresenting: AnyObject {
    func presentEmbeddedElementCall(roomID: String, startMode: ElementCallStartMode) async
}

@MainActor
protocol EmbeddedElementCallRoomCallStateProviding {
    var presentedEmbeddedElementCallRoomID: String? { get }
}

@MainActor
struct EmbeddedElementCallServiceRoomCallStateProvider: EmbeddedElementCallRoomCallStateProviding {
    private let elementCallService: any ElementCallServiceProtocol

    init(elementCallService: any ElementCallServiceProtocol) {
        self.elementCallService = elementCallService
    }

    var presentedEmbeddedElementCallRoomID: String? {
        elementCallService.ongoingCallRoomIDPublisher.value
    }
}

@MainActor
final class EmbeddedElementCallProductionHandoff: EmbeddedElementCallHandoff {
    private let presenter: any EmbeddedElementCallRoomCallPresenting
    private let stateProvider: any EmbeddedElementCallRoomCallStateProviding
    private let verifiedExistingCallProvider: (String) -> Bool

    init(presenter: any EmbeddedElementCallRoomCallPresenting,
         stateProvider: any EmbeddedElementCallRoomCallStateProviding,
         verifiedExistingCallProvider: @escaping (String) -> Bool = { _ in false }) {
        self.presenter = presenter
        self.stateProvider = stateProvider
        self.verifiedExistingCallProvider = verifiedExistingCallProvider
    }

    func prepareAudioCall(roomID: String, intent: EmbeddedElementCallHandoffIntent) async -> EmbeddedElementCallHandoffResult {
        let preparation = EmbeddedElementCallPreparation.audio(roomID: roomID, intent: intent)

        switch intent {
        case .startNew:
            await presenter.presentEmbeddedElementCall(roomID: roomID, startMode: preparation.startMode)
            return .readyToPresent(preparation)
        case .joinExisting:
            return .unsupportedIncomingJoin(preparation)
        case .presentExisting:
            guard stateProvider.presentedEmbeddedElementCallRoomID == roomID || verifiedExistingCallProvider(roomID) else {
                return .noExistingCall(preparation)
            }

            await presenter.presentEmbeddedElementCall(roomID: roomID, startMode: preparation.startMode)
            return .alreadyPresented(preparation)
        }
    }
}

enum SalemXStockElementCallLifecycleError: Error, Equatable {
    case unavailable
    case invalidHandle
    case cancelled
    case ambiguousMembership
}

struct SalemXStockElementCallObservationHandle: Hashable, CustomStringConvertible {
    let observationID: UUID
    let appSessionGeneration: String
    let attemptGeneration: UInt64

    var description: String {
        "SalemXStockElementCallObservationHandle(<redacted>)"
    }
}

struct SalemXStockElementCallContext: Equatable, CustomStringConvertible {
    let callID: String
    let roomID: String
    let callHandle: String

    var description: String {
        "SalemXStockElementCallContext(<redacted>)"
    }
}

protocol SalemXStockElementCallLifecycleProviding {
    @MainActor func beginOutgoingObservation(roomID: String,
                                             appSessionGeneration: String,
                                             attemptGeneration: UInt64) async
        -> Result<SalemXStockElementCallObservationHandle, SalemXStockElementCallLifecycleError>
    @MainActor func awaitMembershipConfirmation(_ handle: SalemXStockElementCallObservationHandle) async
        -> Result<SalemXStockElementCallContext, SalemXStockElementCallLifecycleError>
    @MainActor func confirmOutgoingCallMembershipAfterCallScreenPresentation(_ handle: SalemXStockElementCallObservationHandle)
    @MainActor func awaitMembershipRemoval(_ handle: SalemXStockElementCallObservationHandle) async
        -> Result<Void, SalemXStockElementCallLifecycleError>
    @MainActor func cancelObservation(_ handle: SalemXStockElementCallObservationHandle)
}

extension SalemXStockElementCallLifecycleProviding {
    @MainActor func confirmOutgoingCallMembershipAfterCallScreenPresentation(_ handle: SalemXStockElementCallObservationHandle) { }
}

struct SalemXProductionDispatchCapabilityConfiguration: CustomStringConvertible {
    let client: any SalemXProductionDispatchClientProtocol
    let appSessionGeneration: String
    let capabilityExpiresInSeconds: Int

    init(client: any SalemXProductionDispatchClientProtocol,
         appSessionGeneration: String,
         capabilityExpiresInSeconds: Int = 3600) {
        self.client = client
        self.appSessionGeneration = appSessionGeneration
        self.capabilityExpiresInSeconds = capabilityExpiresInSeconds
    }

    var description: String {
        "SalemXProductionDispatchCapabilityConfiguration(<redacted>)"
    }
}

// sourcery: AutoMockable
protocol ElementCallServiceProtocol {
    var actions: AnyPublisher<ElementCallServiceAction, Never> { get }
    
    var ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never> { get }
    
    func setClientProxy(_ clientProxy: ClientProxyProtocol)

    @MainActor func configureProductionDispatchCapability(_ configuration: SalemXProductionDispatchCapabilityConfiguration?)

    @MainActor func observeForegroundRoom(roomProxy: JoinedRoomProxyProtocol, roomDisplayName: String?)

    @MainActor func stopObservingForegroundRoom(roomID: String)
    
    func setupCallSession(roomID: String, roomDisplayName: String, startMode: ElementCallStartMode) async
    
    func declineIncomingCall() async
    
    func requestCallTermination(roomID: String) async

    func isPreAnswerOutgoingCall(roomID: String) -> Bool
    
    func tearDownCallSession()
    
    func setAudioEnabled(_ enabled: Bool, roomID: String)

    func ownsNativeMatrixRTCAudio(roomID: String) -> Bool

    func nativeMatrixRTCAudioState(roomID: String) -> MatrixRTCNativeAudioState
}

extension ElementCallServiceProtocol {
    @MainActor func configureProductionDispatchCapability(_ configuration: SalemXProductionDispatchCapabilityConfiguration?) { }

    @MainActor func observeForegroundRoom(roomProxy _: JoinedRoomProxyProtocol, roomDisplayName _: String?) { }

    @MainActor func stopObservingForegroundRoom(roomID _: String) { }

    func setupCallSession(roomID: String, roomDisplayName: String) async {
        await setupCallSession(roomID: roomID, roomDisplayName: roomDisplayName, startMode: .audio)
    }

    func isPreAnswerOutgoingCall(roomID: String) -> Bool {
        false
    }

    func ownsNativeMatrixRTCAudio(roomID: String) -> Bool {
        false
    }

    func nativeMatrixRTCAudioState(roomID: String) -> MatrixRTCNativeAudioState {
        .inactive
    }
}
