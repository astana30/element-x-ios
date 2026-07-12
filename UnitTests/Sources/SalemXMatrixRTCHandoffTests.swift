//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CallKit
import Combine
@testable import ElementX
import Foundation
import PushKit
import Testing

@MainActor
final class SalemXEmbeddedCallAnswerBridgeTests {
    @Test
    func validVerifiedBootstrapAcceptsExistingAudioPresentation() async {
        let handoff = MatrixRTCHandoffSpy(result: .handedOff(.readyToPresent(.audio(roomID: roomID, intent: .presentExisting))))
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .presentationAccepted)
        #expect(handoff.calls == [.init(metadata: claimedMetadata(direction: .incoming), intent: .presentExisting)])
        #expect(!handoff.calls.contains { $0.intent == .startNew })
    }

    @Test
    func alreadyPresentedExistingCallIsAccepted() async {
        let handoff = MatrixRTCHandoffSpy(result: .handedOff(.alreadyPresented(.audio(roomID: roomID, intent: .presentExisting))))
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .alreadyPresented)
        #expect(handoff.calls.map(\.intent) == [.presentExisting])
    }

    @Test
    func unsupportedIncomingJoinFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy(result: .handedOff(.unsupportedIncomingJoin(.audio(roomID: roomID, intent: .presentExisting))))
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .unsupportedIncomingJoin)
        #expect(handoff.calls.map(\.intent) == [.presentExisting])
    }

    @Test
    func noActiveMatrixRTCCallFailsClosedBeforeHandoff() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID,
                                         bootstrap: verifiedBootstrap(activeCallState: .none))

        #expect(result == .noActiveMatrixRTCCall)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func activeCallStateUnavailableFailsClosedBeforeHandoff() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID,
                                         bootstrap: verifiedBootstrap(activeCallState: .unavailable))

        #expect(result == .activeCallStateUnavailable)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func missingAuthenticatedSessionFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(userID: "", handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .noAuthenticatedSession)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func sessionUserMismatchFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(userID: "@other:matrix.org", handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .sessionIdentityMismatch)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func sessionDeviceMismatchFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(deviceID: "OTHERDEVICE", handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .sessionDeviceMismatch)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func dmRoomAmbiguityFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy(result: .blocked(.roomAmbiguous))
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .dmRoomAmbiguous)
        #expect(handoff.calls.map(\.intent) == [.presentExisting])
    }

    @Test
    func bootstrapUUIDMismatchFailsClosedBeforeHandoff() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: UUID(), bootstrap: verifiedBootstrap())

        #expect(result == .bootstrapMismatch)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func audioOnlyBoundaryDoesNotExposeMediaOrPermissions() throws {
        let preparation = EmbeddedElementCallPreparation.audio(roomID: roomID, intent: .presentExisting)
        let source = try Self.source(named: "ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift")

        #expect(preparation.startMode == .audio)
        #expect(preparation.cameraRequested == false)
        #expect(preparation.videoEnabled == false)
        #expect(!source.contains("requestMediaCredentials"))
        #expect(!source.contains("LiveKitDirectCall"))
        #expect(!source.contains("ProductionDirectCallLiveKitTokenClient"))
        #expect(!source.contains("AVCaptureDevice.requestAccess"))
        #expect(!source.contains("requestRecordPermission"))
    }

    @Test
    func answerBridgeDoesNotSynthesizeConnectedLifecycleFromCallKit() throws {
        let source = try Self.source(named: "ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift")

        #expect(!source.contains("CXAnswerCallAction"))
        #expect(!source.contains("connected"))
    }

    private let callID = UUID()
    private let roomID = "!room:matrix.org"
    private let localUserID = "@me:matrix.org"
    private let localDeviceID = "MEDEVICE"
    private let peerUserID = "@alice:matrix.org"
    private let peerDeviceID = "ALICEDEVICE"

    private func makeBridge(userID: String? = nil,
                            deviceID: String? = nil,
                            handoff: MatrixRTCHandoffSpy) -> SalemXEmbeddedCallAnswerBridge {
        let clientProxy = ClientProxyMock(.init(userID: userID ?? localUserID,
                                                deviceID: deviceID ?? localDeviceID))
        return SalemXEmbeddedCallAnswerBridge(clientProxy: clientProxy, matrixRTCHandoff: handoff)
    }

    private func verifiedBootstrap(activeCallState: VerifiedIncomingCallBootstrapActiveCallState = .active) -> VerifiedIncomingCallBootstrap {
        .init(callID: callID,
              claimedMetadata: claimedMetadata(direction: .incoming),
              localDeviceID: localDeviceID,
              activeCallState: activeCallState)
    }

    private func claimedMetadata(direction: SalemXMatrixRTCHandoffDirection) -> SalemXMatrixRTCClaimedMetadata {
        .init(roomID: roomID,
              localUserID: localUserID,
              peerUserID: peerUserID,
              peerDeviceID: peerDeviceID,
              direction: direction)
    }

    private static func source(named path: String) throws -> String {
        let repositoryRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRootURL.appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private struct MatrixRTCHandoffCall: Equatable {
        let metadata: SalemXMatrixRTCClaimedMetadata
        let intent: EmbeddedElementCallHandoffIntent
    }

    private final class MatrixRTCHandoffSpy: SalemXMatrixRTCHandoff {
        private let result: SalemXMatrixRTCHandoffResult
        private(set) var calls = [MatrixRTCHandoffCall]()

        init(result: SalemXMatrixRTCHandoffResult = .handedOff(.alreadyPresented(.audio(roomID: "!room:matrix.org", intent: .presentExisting)))) {
            self.result = result
        }

        func prepareAudioCall(claimedMetadata: SalemXMatrixRTCClaimedMetadata,
                              intent: EmbeddedElementCallHandoffIntent) async -> SalemXMatrixRTCHandoffResult {
            calls.append(.init(metadata: claimedMetadata, intent: intent))
            return result
        }
    }
}

@MainActor
final class SalemXMatrixRTCHandoffTests {
    @Test
    func claimedJoinedDMRoomHandsOffToAudioElementCall() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockAlice]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .handedOff(.readyToPresent(.audio(roomID: roomID, intent: .startNew))))
        #expect(elementCallHandoff.calls == [.init(roomID: roomID, intent: .startNew)])
        #expect(clientProxy.roomForIdentifierReceivedIdentifier == roomID)
        #expect(room.getMemberUserIDReceivedInvocations == [localUserID, peerUserID])
    }

    @Test
    func incomingJoinPreservesUnsupportedJoinSemantics() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockAlice]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy { roomID, intent in
            .unsupportedIncomingJoin(.audio(roomID: roomID, intent: intent))
        }
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(direction: .incoming),
                                                    intent: .joinExisting)

        #expect(result == .handedOff(.unsupportedIncomingJoin(.audio(roomID: roomID, intent: .joinExisting))))
        #expect(elementCallHandoff.calls == [.init(roomID: roomID, intent: .joinExisting)])
    }

    @Test
    func malformedClaimedMetadataBlocksBeforeRoomLookup() async {
        let clientProxy = makeClientProxy()
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(peerDeviceID: " "),
                                                    intent: .startNew)

        #expect(result == .blocked(.malformedClaimedMetadata))
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func unauthenticatedSessionBlocksBeforeRoomLookup() async {
        let clientProxy = makeClientProxy(userID: "")
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.unauthenticatedSession))
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func authenticatedUserMismatchBlocksBeforeRoomLookup() async {
        let clientProxy = makeClientProxy(userID: "@other:matrix.org")
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.authenticatedUserMismatch))
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func unjoinedRoomBlocksBeforeHandoff() async {
        let clientProxy = makeClientProxy()
        clientProxy.roomForIdentifierClosure = { _ in .left }
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.roomNotJoined))
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func nonDirectRoomBlocksBeforeHandoff() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: false,
                                             members: [.mockMe, .mockAlice]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.roomNotDirectOneToOne))
        #expect(room.getMemberUserIDCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func roomWithMoreThanTwoActiveMembersBlocksBeforeHandoff() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockAlice, .mockBob]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.roomNotDirectOneToOne))
        #expect(room.getMemberUserIDCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func peerOutsideRoomBlocksBeforeHandoff() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockBob]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.peerUserNotMember))
        #expect(room.getMemberUserIDReceivedInvocations == [localUserID, peerUserID])
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func claimedMetadataDescriptionIsRedacted() {
        let metadata = claimedMetadata()
        let description = String(describing: metadata)

        #expect(!description.contains(roomID))
        #expect(!description.contains(localUserID))
        #expect(!description.contains(peerUserID))
        #expect(!description.contains(peerDeviceID))
        #expect(description.contains("direction: outgoing"))
    }

    @Test
    func handoffResultDescriptionIsRedacted() {
        let result = SalemXMatrixRTCHandoffResult.handedOff(.readyToPresent(.audio(roomID: roomID, intent: .startNew)))
        let description = String(describing: result)

        #expect(!description.contains(roomID))
        #expect(description.contains("readyToPresent"))
    }

    private let roomID = "!room:matrix.org"
    private let localUserID = "@me:matrix.org"
    private let peerUserID = "@alice:matrix.org"
    private let peerDeviceID = "ALICEDEVICE"

    private func claimedMetadata(peerDeviceID: String? = nil,
                                 direction: SalemXMatrixRTCHandoffDirection = .outgoing) -> SalemXMatrixRTCClaimedMetadata {
        .init(roomID: roomID,
              localUserID: localUserID,
              peerUserID: peerUserID,
              peerDeviceID: peerDeviceID ?? self.peerDeviceID,
              direction: direction)
    }

    private func makeClientProxy(userID: String? = nil,
                                 roomProxy: JoinedRoomProxyProtocol? = nil) -> ClientProxyMock {
        let clientProxy = ClientProxyMock(.init(userID: userID ?? localUserID))
        clientProxy.roomForIdentifierClosure = { requestedRoomID in
            guard requestedRoomID == self.roomID, let roomProxy else {
                return nil
            }

            return .joined(roomProxy)
        }
        return clientProxy
    }

    private struct ElementCallHandoffCall: Equatable {
        let roomID: String
        let intent: EmbeddedElementCallHandoffIntent
    }

    private final class ElementCallHandoffSpy: EmbeddedElementCallHandoff {
        private let result: (String, EmbeddedElementCallHandoffIntent) -> EmbeddedElementCallHandoffResult
        private(set) var calls = [ElementCallHandoffCall]()

        init(result: @escaping (String, EmbeddedElementCallHandoffIntent) -> EmbeddedElementCallHandoffResult = { roomID, intent in
            .readyToPresent(.audio(roomID: roomID, intent: intent))
        }) {
            self.result = result
        }

        func prepareAudioCall(roomID: String, intent: EmbeddedElementCallHandoffIntent) async -> EmbeddedElementCallHandoffResult {
            calls.append(.init(roomID: roomID, intent: intent))
            return result(roomID, intent)
        }
    }
}

@MainActor
final class SalemXEmbeddedCallAnswerBridgeServiceTests {
    private let appSettings = AppSettings()
    private var callProvider: CXProviderMock!
    private var currentDate: Date!
    private var pushRegistry: PKPushRegistry!
    private var service: ElementCallService!
    private let localUserID = "@test:user.net"
    private var cancellables = Set<AnyCancellable>()

    init() {
        AppSettings.resetAllSettings()
        callProvider = CXProviderMock(.init())
        currentDate = Date()
        pushRegistry = PKPushRegistry(queue: nil)
    }

    deinit {
        callProvider = nil
        currentDate = nil
        pushRegistry = nil
    }

    @Test
    func defaultRouteRemainsUnchangedWhenBridgeIsConfiguredButDisabled() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.fulfillCount == 1 })
        #expect(action.failCount == 0)
        #expect(answerBridge.calls.isEmpty)
        #expect(await waitUntil { observedActions.contains { action in
            guard case .startCall(let roomID, let startMode) = action else {
                return false
            }
            return roomID == Self.roomID && startMode == .video
        } })
    }

    @Test
    func enabledBridgeFulfillsSuccessfulPresentationOnceWithoutStartingLegacyRoute() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.fulfillCount == 1 })
        #expect(action.failCount == 0)
        #expect(answerBridge.calls.map(\.callID) == [callID])
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
        #expect(bootstrapResolver.removedCallIDs == [callID])
        #expect(!observedActions.contains { action in
            if case .startCall = action {
                return true
            }
            return false
        })
    }

    @Test
    func enabledBridgeFailsPresentationErrorOnce() async throws {
        let answerBridge = AnswerBridgeSpy(result: .noActiveMatrixRTCCall)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(action.fulfillCount == 0)
        #expect(answerBridge.calls.count == 1)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .failed)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func duplicateAnswerDoesNotStartSecondTaskOrPresentTwice() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented, delay: .milliseconds(50))
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let firstAction = AnswerActionSpy(callUUID: callID)
        let secondAction = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(firstAction, provider: callProvider)
        service.handleAnswerCallAction(firstAction, provider: callProvider)
        service.handleAnswerCallAction(secondAction, provider: callProvider)

        #expect(await waitUntil { firstAction.fulfillCount == 1 && secondAction.fulfillCount == 1 })
        #expect(firstAction.failCount == 0)
        #expect(secondAction.failCount == 0)
        #expect(answerBridge.calls.count == 1)
    }

    @Test
    func timeoutFailsOnceAndReleasesBootstrap() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented, delay: .milliseconds(100))
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(embeddedMatrixRTCAnswerBridgeEnabled: true,
                                                               answerTimeout: .milliseconds(10)),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(action.fulfillCount == 0)
        #expect(answerBridge.calls.count == 1)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func cancellationReleasesInFlightGuardAndFailsActionOnce() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented, delay: .milliseconds(100))
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)
        await service.declineIncomingCall()

        #expect(await waitUntil { action.failCount == 1 })
        #expect(action.fulfillCount == 0)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func missingSecureBootstrapFailsClosed() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(answerBridge.calls.isEmpty)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .failed)
    }

    @Test
    func bootstrapRoomOrUUIDMismatchFailsClosed() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: UUID())

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(answerBridge.calls.isEmpty)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    private func makeAnswerBridgeService(configuration: SalemXEmbeddedCallAnswerBridgeConfiguration = .init(embeddedMatrixRTCAnswerBridgeEnabled: true,
                                                                                                            answerTimeout: .seconds(1)),
                                         bootstrapResolver: BootstrapResolverSpy,
                                         answerBridge: AnswerBridgeSpy) -> ElementCallService {
        ElementCallService(appSettings: appSettings,
                           callProvider: callProvider,
                           timeProvider: TimeProvider(clock: ContinuousClock()) { self.currentDate },
                           salemXAnswerBridgeConfiguration: configuration,
                           salemXIncomingCallBootstrapResolver: bootstrapResolver,
                           salemXAnswerBridge: answerBridge)
    }

    private func reportIncomingCall() async throws -> UUID {
        let payload = Stage2DPKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        await confirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        return try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid)
    }

    private func verifiedBootstrap(callID: UUID,
                                   roomID: String? = nil) -> VerifiedIncomingCallBootstrap {
        let roomID = roomID ?? Self.roomID
        return .init(callID: callID,
                     claimedMetadata: .init(roomID: roomID,
                                            localUserID: localUserID,
                                            peerUserID: "@alice:example.com",
                                            peerDeviceID: "ALICEDEVICE",
                                            direction: .incoming),
                     localDeviceID: "DEVICEID",
                     activeCallState: .active)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async -> Bool {
        for _ in 0..<30 {
            if condition() {
                return true
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return false
    }

    static let roomID = "!room:example.com"
}

private class Stage2DPKPushPayloadMock: PKPushPayload {
    var dict: [AnyHashable: Any] = [:]

    override init() {
        dict[ElementCallServiceNotificationKey.roomID.rawValue] = SalemXEmbeddedCallAnswerBridgeServiceTests.roomID
        dict[ElementCallServiceNotificationKey.roomDisplayName.rawValue] = "welcome"
        dict[ElementCallServiceNotificationKey.rtcNotifyEventID.rawValue] = "$000"
        dict[ElementCallServiceNotificationKey.expirationDate.rawValue] = Date(timeIntervalSince1970: 10)
    }

    override var dictionaryPayload: [AnyHashable: Any] {
        dict
    }

    func updatingExpiration(_ from: Date, lifetime: TimeInterval) -> Self {
        dict[ElementCallServiceNotificationKey.expirationDate.rawValue] = from.addingTimeInterval(lifetime)
        return self
    }
}

private final class AnswerActionSpy: SalemXCallKitAnswerActionCompleting {
    let callUUID: UUID
    private(set) var fulfillCount = 0
    private(set) var failCount = 0

    init(callUUID: UUID) {
        self.callUUID = callUUID
    }

    func fulfill() {
        fulfillCount += 1
    }

    func fail() {
        failCount += 1
    }
}

private final class BootstrapResolverSpy: SalemXIncomingCallBootstrapResolving {
    var bootstrapByCallID = [UUID: VerifiedIncomingCallBootstrap]()
    private(set) var requestedCallIDs = [UUID]()
    private(set) var removedCallIDs = [UUID]()

    func verifiedBootstrap(for callID: UUID) -> VerifiedIncomingCallBootstrap? {
        requestedCallIDs.append(callID)
        return bootstrapByCallID[callID]
    }

    func removeVerifiedBootstrap(for callID: UUID) {
        removedCallIDs.append(callID)
        bootstrapByCallID.removeValue(forKey: callID)
    }
}

@MainActor
private final class AnswerBridgeSpy: SalemXEmbeddedCallAnswerBridging {
    struct Call: Equatable {
        let callID: UUID
        let bootstrap: VerifiedIncomingCallBootstrap
    }

    private let result: SalemXEmbeddedCallAnswerResult
    private let delay: Duration?
    private(set) var calls = [Call]()

    init(result: SalemXEmbeddedCallAnswerResult, delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }

    func answer(callID: UUID, bootstrap: VerifiedIncomingCallBootstrap) async -> SalemXEmbeddedCallAnswerResult {
        calls.append(.init(callID: callID, bootstrap: bootstrap))
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return result
    }
}
