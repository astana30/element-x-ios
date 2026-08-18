//
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import CallKit
import Clocks
import Combine
@testable import ElementX
import MatrixRustSDK
import MatrixRustSDKMocks
import PushKit
import Testing

// swiftlint:disable file_length

@MainActor
final class EmbeddedElementCallProductionHandoffTests {
    @Test
    func startNewMapsOnlyToAudioPresentation() async {
        let presenter = HandoffPresenterSpy()
        let handoff = EmbeddedElementCallProductionHandoff(presenter: presenter,
                                                           stateProvider: HandoffStateProvider(presentedRoomID: nil))

        let result = await handoff.prepareAudioCall(roomID: "!room:example.org", intent: .startNew)

        #expect(result == .readyToPresent(.audio(roomID: "!room:example.org", intent: .startNew)))
        #expect(presenter.calls == [.init(roomID: "!room:example.org", startMode: .audio)])
    }

    @Test
    func joinExistingDoesNotFallBackToStartNew() async {
        let presenter = HandoffPresenterSpy()
        let handoff = EmbeddedElementCallProductionHandoff(presenter: presenter,
                                                           stateProvider: HandoffStateProvider(presentedRoomID: nil))

        let result = await handoff.prepareAudioCall(roomID: "!room:example.org", intent: .joinExisting)

        #expect(result == .unsupportedIncomingJoin(.audio(roomID: "!room:example.org", intent: .joinExisting)))
        #expect(presenter.calls.isEmpty)
    }

    @Test
    func presentExistingDoesNotCreateNewCallWhenNoExistingCallIsKnown() async {
        let presenter = HandoffPresenterSpy()
        let handoff = EmbeddedElementCallProductionHandoff(presenter: presenter,
                                                           stateProvider: HandoffStateProvider(presentedRoomID: nil))

        let result = await handoff.prepareAudioCall(roomID: "!room:example.org", intent: .presentExisting)

        #expect(result == .noExistingCall(.audio(roomID: "!room:example.org", intent: .presentExisting)))
        #expect(presenter.calls.isEmpty)
    }

    @Test
    func presentExistingCanRepresentAlreadyPresentedRoom() async {
        let presenter = HandoffPresenterSpy()
        let handoff = EmbeddedElementCallProductionHandoff(presenter: presenter,
                                                           stateProvider: HandoffStateProvider(presentedRoomID: "!room:example.org"))

        let result = await handoff.prepareAudioCall(roomID: "!room:example.org", intent: .presentExisting)

        #expect(result == .alreadyPresented(.audio(roomID: "!room:example.org", intent: .presentExisting)))
        #expect(presenter.calls == [.init(roomID: "!room:example.org", startMode: .audio)])
    }

    @Test
    func presentExistingCanUseVerifiedRemoteCallWithoutLocalParticipation() async {
        let presenter = HandoffPresenterSpy()
        let handoff = EmbeddedElementCallProductionHandoff(presenter: presenter,
                                                           stateProvider: HandoffStateProvider(presentedRoomID: nil)) { $0 == "!room:example.org" }

        let result = await handoff.prepareAudioCall(roomID: "!room:example.org", intent: .presentExisting)

        #expect(result == .alreadyPresented(.audio(roomID: "!room:example.org", intent: .presentExisting)))
        #expect(presenter.calls == [.init(roomID: "!room:example.org", startMode: .audio)])
    }

    @Test
    func presentExistingRejectsWrongVerifiedRemoteCallRoom() async {
        let presenter = HandoffPresenterSpy()
        let handoff = EmbeddedElementCallProductionHandoff(presenter: presenter,
                                                           stateProvider: HandoffStateProvider(presentedRoomID: nil)) { $0 == "!other:example.org" }

        let result = await handoff.prepareAudioCall(roomID: "!room:example.org", intent: .presentExisting)

        #expect(result == .noExistingCall(.audio(roomID: "!room:example.org", intent: .presentExisting)))
        #expect(presenter.calls.isEmpty)
    }

    @Test
    func audioOnlyDirectCallDoesNotRequestVideoOrCameraTrack() async {
        let preparation = EmbeddedElementCallPreparation.audio(roomID: "!room:example.org", intent: .startNew)
        let exposedLabels = Mirror(reflecting: preparation).children.compactMap(\.label).joined(separator: ",")
        let room = RoomSDKMock()
        room.hasActiveRoomCallReturnValue = false
        room.isDirectReturnValue = true
        let widgetDriver = ElementCallWidgetDriver(room: room, deviceID: "redacted-device")

        #expect(preparation.startMode == .audio)
        #expect(preparation.cameraRequested == false)
        #expect(preparation.videoEnabled == false)
        #expect(await room.joinCallIntent == .startCallDmVoice)
        #expect(widgetDriver.startMode == .audio)
        #expect(preparation.lifecycleEvents == EmbeddedElementCallLifecycleEvent.allCases)
        #expect(!exposedLabels.localizedCaseInsensitiveContains("livekit"))
        #expect(!exposedLabels.localizedCaseInsensitiveContains("token"))
        #expect(!exposedLabels.localizedCaseInsensitiveContains("jwt"))
        #expect(!exposedLabels.localizedCaseInsensitiveContains("url"))
    }

    @Test
    func stage2BCurrentProductionDirectCallRouteRemainsUnchanged() {
        let configuration = DirectCallProductionConfiguration()

        #expect(configuration.isEnabled == false)
        #expect(configuration.isConfigured == false)
        #expect(configuration.tokenEndpointURL == nil)
    }

    @Test
    func handoffDoesNotSynthesizeLifecycleFromCallKitState() async {
        let presenter = HandoffPresenterSpy()
        let handoff = EmbeddedElementCallProductionHandoff(presenter: presenter,
                                                           stateProvider: HandoffStateProvider(presentedRoomID: nil))

        let result = await handoff.prepareAudioCall(roomID: "!room:example.org", intent: .joinExisting)

        #expect(result == .unsupportedIncomingJoin(.audio(roomID: "!room:example.org", intent: .joinExisting)))
        #expect(presenter.calls.isEmpty)
    }

    private struct PresentationCall: Equatable {
        let roomID: String
        let startMode: ElementCallStartMode
    }

    private final class HandoffPresenterSpy: EmbeddedElementCallRoomCallPresenting {
        private(set) var calls = [PresentationCall]()

        func presentEmbeddedElementCall(roomID: String, startMode: ElementCallStartMode) async {
            calls.append(.init(roomID: roomID, startMode: startMode))
        }
    }

    private struct HandoffStateProvider: EmbeddedElementCallRoomCallStateProviding {
        let presentedRoomID: String?

        var presentedEmbeddedElementCallRoomID: String? {
            presentedRoomID
        }
    }
}

@MainActor
final class SalemXStage2FCallKitDebugBoundaryTests {
    private let appSettings = AppSettings()
    private var callProvider: CXProviderMock!
    private var service: ElementCallService!

    init() {
        AppSettings.resetAllSettings()
        callProvider = CXProviderMock(.init())
        service = ElementCallService(appSettings: appSettings, callProvider: callProvider)
    }

    deinit {
        callProvider = nil
    }

    @Test
    func reportStoresBootstrapAndBlocksASecondIncomingCall() async throws {
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }
        var storedCallIDs = [UUID]()

        let firstResult = await service.salemXDebugReportStage2FSimulatorIncomingCall(roomID: "redacted-room",
                                                                                      roomDisplayName: "Call",
                                                                                      startMode: .audio) { callID in
            storedCallIDs.append(callID)
        }
        let firstCallID = try #require(firstResult.reportedCallID)

        #expect(storedCallIDs == [firstCallID])
        #expect(firstResult.outcomeBucket == "reported")
        #expect(service.salemXDebugStage2FCallKitLocalStateBucket == .incomingCallActive)

        let secondResult = await service.salemXDebugReportStage2FSimulatorIncomingCall(roomID: "redacted-room",
                                                                                       roomDisplayName: "Call",
                                                                                       startMode: .audio) { callID in
            storedCallIDs.append(callID)
        }

        #expect(secondResult == .blockedByExistingIncomingCall)
        #expect(secondResult.outcomeBucket == "blocked_existing_incoming_call")
        #expect(storedCallIDs == [firstCallID])
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
        await service.declineIncomingCall()
    }

    @Test
    func reportClassifiesProviderFailureAfterBootstrapStore() async {
        let error = NSError(domain: CXErrorDomainIncomingCall,
                            code: CXErrorCodeIncomingCallError.Code.filteredByDoNotDisturb.rawValue)
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(error)
        }
        var storedCallIDs = [UUID]()

        let result = await service.salemXDebugReportStage2FSimulatorIncomingCall(roomID: "redacted-room",
                                                                                 roomDisplayName: "Call",
                                                                                 startMode: .audio) { callID in
            storedCallIDs.append(callID)
        }

        guard case .providerFailed(let callID, let errorBucket) = result else {
            Issue.record("Expected a redacted provider failure")
            return
        }

        #expect(storedCallIDs == [callID])
        #expect(errorBucket == .filteredByDoNotDisturb)
        #expect(result.outcomeBucket == "provider_failed_filtered_by_do_not_disturb")
        #expect(service.salemXDebugStage2FCallKitLocalStateBucket == .idle)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
    }

    @Test
    func terminalIdentityIgnoresDuplicateForegroundInvite() async throws {
        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        let firstResult = await service.salemXDebugReportStage2FSimulatorIncomingCall(roomID: "redacted-room",
                                                                                      roomDisplayName: "Call",
                                                                                      startMode: .audio,
                                                                                      rtcNotificationID: "redacted-notification",
                                                                                      remoteCallID: "redacted-session") { _ in }
        _ = try #require(firstResult.reportedCallID)

        await service.declineIncomingCall()

        let duplicateResult = await service.salemXDebugReportStage2FSimulatorIncomingCall(roomID: "redacted-room",
                                                                                          roomDisplayName: "Call",
                                                                                          startMode: .audio,
                                                                                          rtcNotificationID: "redacted-notification",
                                                                                          remoteCallID: "redacted-session") { _ in }

        #expect(duplicateResult == .blockedByConsumedCallIdentity)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
    }
}

@MainActor
// swiftlint:disable:next type_body_length
final class ElementCallServiceTests {
    private let appSettings = AppSettings()
    private var callProvider: CXProviderMock!
    private var currentDate: Date!
    private var testClock: TestClock<Duration>!
    private var pushRegistry: PKPushRegistry!
    private var service: ElementCallService!
    private let clientProxy = ClientProxyMock(.init(userID: "@test:user.net", deviceID: "LOCAL_DEVICE"))
    private var cancellables = Set<AnyCancellable>()

    init() {
        AppSettings.resetAllSettings()
        pushRegistry = PKPushRegistry(queue: nil)
        callProvider = CXProviderMock(.init())
        currentDate = Date()
        testClock = TestClock()
        let dateProvider: () -> Date = {
            self.currentDate
        }
        service = ElementCallService(appSettings: appSettings,
                                     callProvider: callProvider,
                                     timeProvider: TimeProvider(clock: testClock, now: dateProvider))
    }

    deinit {
        callProvider = nil
        currentDate = nil
        testClock = nil
        pushRegistry = nil
    }

    @Test
    func incomingCall() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)

        await confirmation { confirmation in
            let pkPushPayloadMock = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)

            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: pkPushPayloadMock, for: .voIP) {
                confirmation()
            }
        }

        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        await service.declineIncomingCall()
    }

    @Test
    func productionDispatchDisabledPreservesLegacyPushWithoutConsume() async {
        let dispatchClient = SalemXProductionDispatchCapabilityClientSpy()
        service.configureProductionDispatchCapability(.init(client: dispatchClient,
                                                            appSessionGeneration: "opaque-generation"))
        let payload = productionDispatchPayload(includingLegacyCallBootstrap: true)

        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                continuation.resume()
            }
        }

        #expect(dispatchClient.consumeRequests.isEmpty)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
        await service.declineIncomingCall()
    }

    @Test
    func serverGeneratedProductionDispatchPayloadParsesAtPushKitIngress() async throws {
        appSettings.salemxProductionDispatchV1Enabled = true
        let dispatchClient = SalemXProductionDispatchCapabilityClientSpy()
        dispatchClient.consumeResult = .success(productionDispatchConsumeResponse())
        service.configureProductionDispatchCapability(.init(client: dispatchClient,
                                                            appSessionGeneration: "opaque-generation"))
        let json = #"{"aps":{"content-available":1},"salemx_direct_call":{"version":1,"kind":"real_invite_controlled","redacted":true,"receiver_reference":"receiver-reference","dispatch_id":"11111111-1111-4111-8111-111111111111"}}"#
        let serverPayload = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let payload = PKPushPayloadMock(dictionaryPayload: serverPayload)

        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                continuation.resume()
            }
        }

        #expect(dispatchClient.consumeRequests.count == 1)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
        await service.declineIncomingCall()
    }

    @Test
    func productionDispatchValidPushConsumesExactlyOnceBeforeExistingCallKitIngress() async {
        appSettings.salemxProductionDispatchV1Enabled = true
        let dispatchClient = SalemXProductionDispatchCapabilityClientSpy()
        dispatchClient.consumeResult = .success(productionDispatchConsumeResponse())
        service.configureProductionDispatchCapability(.init(client: dispatchClient,
                                                            appSessionGeneration: "opaque-generation"))
        let payload = productionDispatchPayload()

        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                continuation.resume()
            }
        }

        #expect(dispatchClient.consumeRequests.count == 1)
        #expect(dispatchClient.consumeRequests.first?.appSessionGeneration == "opaque-generation")
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)

        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                continuation.resume()
            }
        }
        #expect(dispatchClient.consumeRequests.count == 1)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
        await service.declineIncomingCall()
    }

    @Test
    func productionDispatchInvalidOrFailedPushCompletesWithoutCallKit() async throws {
        appSettings.salemxProductionDispatchV1Enabled = true
        let dispatchClient = SalemXProductionDispatchCapabilityClientSpy()
        dispatchClient.consumeResult = .failure(.http(.authentication, .unknown))
        service.configureProductionDispatchCapability(.init(client: dispatchClient,
                                                            appSessionGeneration: "opaque-generation"))

        let malformedPayload = productionDispatchPayload(dispatchID: "invalid")
        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: malformedPayload, for: .voIP) {
                continuation.resume()
            }
        }
        #expect(dispatchClient.consumeRequests.isEmpty)

        let missingDispatchIDPayload = productionDispatchPayload()
        var envelope = try #require(missingDispatchIDPayload.dict[SalemXProductionDispatchNotificationKey.envelope.rawValue] as? [String: Any])
        envelope.removeValue(forKey: SalemXProductionDispatchNotificationKey.dispatchID.rawValue)
        missingDispatchIDPayload.dict[SalemXProductionDispatchNotificationKey.envelope.rawValue] = envelope
        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: missingDispatchIDPayload, for: .voIP) {
                continuation.resume()
            }
        }
        #expect(dispatchClient.consumeRequests.isEmpty)

        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: productionDispatchPayload(), for: .voIP) {
                continuation.resume()
            }
        }
        #expect(dispatchClient.consumeRequests.count == 1)
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
    }

    @Test
    func productionDispatchDisabledResponseCompletesOnceWithoutCallKit() async {
        appSettings.salemxProductionDispatchV1Enabled = true
        let dispatchClient = SalemXProductionDispatchCapabilityClientSpy()
        dispatchClient.consumeResult = .failure(.http(.notFound, .disabled))
        service.configureProductionDispatchCapability(.init(client: dispatchClient,
                                                            appSessionGeneration: "opaque-generation"))
        var completionCount = 0

        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: productionDispatchPayload(), for: .voIP) {
                completionCount += 1
                continuation.resume()
            }
        }

        #expect(dispatchClient.consumeRequests.count == 1)
        #expect(completionCount == 1)
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
    }

    @Test
    func productionDispatchStaleAndInvalidResponsesFailClosed() async {
        appSettings.salemxProductionDispatchV1Enabled = true
        let dispatchClient = SalemXProductionDispatchCapabilityClientSpy()
        service.configureProductionDispatchCapability(.init(client: dispatchClient,
                                                            appSessionGeneration: "opaque-generation"))

        dispatchClient.consumeResult = .success(productionDispatchConsumeResponse(direction: "outgoing"))
        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: productionDispatchPayload(), for: .voIP) {
                continuation.resume()
            }
        }

        dispatchClient.consumeResult = .success(productionDispatchConsumeResponse(expiresAt: currentDate))
        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry,
                                 didReceiveIncomingPushWith: productionDispatchPayload(dispatchID: "22222222-2222-4222-8222-222222222222"),
                                 for: .voIP) {
                continuation.resume()
            }
        }

        #expect(dispatchClient.consumeRequests.count == 2)
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
    }

    @Test
    func productionDispatchSessionReplacementFailsClosedAndCompletesOnce() async {
        appSettings.salemxProductionDispatchV1Enabled = true
        let dispatchClient = SalemXProductionDispatchCapabilityClientSpy()
        dispatchClient.consumeHandler = { [weak self] _ in
            self?.service.configureProductionDispatchCapability(.init(client: dispatchClient,
                                                                      appSessionGeneration: "replacement-generation"))
            return .success(self?.productionDispatchConsumeResponse() ?? .init(dispatchProtocolVersion: 1,
                                                                               state: .consumed,
                                                                               version: 1,
                                                                               callID: "redacted",
                                                                               roomID: "redacted",
                                                                               peerUserID: "redacted",
                                                                               direction: "incoming",
                                                                               intent: .audio,
                                                                               expiresAtMS: 1))
        }
        service.configureProductionDispatchCapability(.init(client: dispatchClient,
                                                            appSessionGeneration: "opaque-generation"))
        var completionCount = 0

        await withCheckedContinuation { continuation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: productionDispatchPayload(), for: .voIP) {
                completionCount += 1
                continuation.resume()
            }
        }

        #expect(dispatchClient.consumeRequests.count == 1)
        #expect(completionCount == 1)
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
    }

    @Test
    func callIsTimingOut() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)

        await confirmation { confirmation in
            let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 20)

            service.pushRegistry(pushRegistry,
                                 didReceiveIncomingPushWith: pushPayload,
                                 for: .voIP) {
                confirmation()
            }
        }

        // advance past the timeout
        await testClock.advance(by: .seconds(30))
        #expect(await waitForEndedCall(reason: .unanswered))
    }

    @Test
    func expiredRingLifetimeIsIgnored() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)

        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 20)

        currentDate = currentDate.addingTimeInterval(60)

        service.pushRegistry(pushRegistry,
                             didReceiveIncomingPushWith: pushPayload,
                             for: .voIP) { }
        sleep(20)

        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
        await service.declineIncomingCall()
    }

    @Test
    func lifetimeIsCapped() async {
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)

        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 300)

        service.pushRegistry(pushRegistry,
                             didReceiveIncomingPushWith: pushPayload,
                             for: .voIP) { }

        // Advance past the max timeout but below the 300
        await testClock.advance(by: .seconds(100))
        #expect(await waitForEndedCall(reason: .unanswered))
    }

    @Test
    func timedOutIncomingCallDoesNotSendDeclineEcho() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: false))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        configureLiveTimeline(for: room)

        let roomSummaryProvider = RoomSummaryProviderMock()
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 0)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = CurrentValueSubject<[RoomSummary], Never>([]).asCurrentValuePublisher()
        clientProxy.roomSummaryProvider = roomSummaryProvider

        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 20)

        service.pushRegistry(pushRegistry,
                             didReceiveIncomingPushWith: pushPayload,
                             for: .voIP) { }

        await testClock.advance(by: .seconds(30))
        await service.declineIncomingCall()

        #expect(!room.declineCallNotificationIDCalled)
    }

    @Test
    func declineIncomingCallSendsDeclineEventAndStopsRinging() async {
        service.setClientProxy(clientProxy)

        let room = JoinedRoomProxyMock(.init(id: "!room:example.com",
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        configureLiveTimeline(for: room)
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }

        room.declineCallNotificationIDClosure = { notificationID in
            #expect(notificationID == "$000")
            return .success(())
        }

        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .declinedElsewhere {
                    confirmation()
                }
            }

            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
            await service.declineIncomingCall()
        }

        #expect(room.declineCallNotificationIDCalled)
        #expect(callProvider.reportCallWithEndedAtReasonCalled)
    }

    @Test
    func requestCallTerminationAfterTearDownUsesCachedRTCNotificationID() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        configureLiveTimeline(for: room)

        room.declineCallNotificationIDClosure = { notificationID in
            #expect(notificationID == "$000")
            return .success(())
        }

        var endedRoomIDs = [String]()
        service.actions
            .sink { action in
                if case .endCall(let endedRoomID) = action {
                    endedRoomIDs.append(endedRoomID)
                }
            }
            .store(in: &cancellables)

        let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        await deliverIncomingPush(payload)
        #expect(await waitForIncomingLifecycleObservation(on: room))

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        service.tearDownCallSession()
        await service.requestCallTermination(roomID: roomID)

        #expect(endedRoomIDs == [roomID])
        #expect(!room.declineCallNotificationIDCalled)
    }

    @Test
    func duplicateCallKitAndAppUITerminationRequestsEmitUpstreamEndOnce() async {
        let roomID = "redacted-room"
        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall(let endedRoomID) = action, endedRoomID == roomID {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        await service.requestCallTermination(roomID: roomID)
        await service.requestCallTermination(roomID: roomID)

        #expect(endCallCount == 1)
    }

    @Test
    func incomingDirectCallStopsRingingWhenRemoteDeclines() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let remoteUserID = "@alice:example.com"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        configureLiveTimeline(for: room)

        let declineHandle = TaskHandleSDKMock()
        var declineListener: CallDeclineListener?
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, listener in
            declineListener = listener
            return .success(declineHandle)
        }

        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .remoteEnded {
                    confirmation()
                }
            }

            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            await deliverIncomingPush(payload)
            #expect(await waitForIncomingLifecycleObservation(on: room))

            declineListener?.call(declinerUserId: remoteUserID)
        }

        #expect(declineHandle.cancelCalled)
    }

    @Test
    func incomingDirectCallStopsRingingWhenRemoteLeavesCallMemberState() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        configureLiveTimeline(for: room)
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }

        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: [remoteUserID]))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .remoteEnded {
                    confirmation()
                }
            }

            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            await deliverIncomingPush(payload)
            #expect(await waitForIncomingLifecycleObservation(on: room))

            roomInfoSubject.send(makeRoomInfo(id: roomID,
                                              isDirect: true,
                                              hasRoomCall: false,
                                              participants: []))
            #expect(await waitForEndedCall(reason: .remoteEnded))
        }
    }

    @Test
    func incomingDirectCallStopsRingingWhenRemoteSendsHangupEvent() async throws {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        configureLiveTimeline(for: room)
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }

        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: []))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        let timelineProxy = try #require(room.timeline as? TimelineProxyMock)
        let timelineItemProvider = try #require(timelineProxy.timelineItemProvider as? TimelineItemProviderMock)
        let timelineUpdates = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>(([], .initial))
        let timelineSubscriptionProbe = PublisherSubscriptionProbe()
        timelineItemProvider.itemProxies = []
        timelineItemProvider.updatePublisher = timelineUpdates
            .handleEvents { _ in timelineSubscriptionProbe.recordSubscription() }
            .eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live

        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .remoteEnded {
                    confirmation()
                }
            }

            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            await deliverIncomingPush(payload)
            #expect(await waitForIncomingLifecycleObservation(on: room))
            #expect(await waitForPublisherSubscription(timelineSubscriptionProbe))

            let hangupItem = makeCallTimelineItem(eventID: "$hangup",
                                                  sender: remoteUserID,
                                                  isOwn: false,
                                                  eventType: .callHangup,
                                                  timestamp: currentDate)
            timelineUpdates.send(([hangupItem], .initial))
        }
    }

    @Test
    func incomingDirectCallStopsRingingWhenRoomSummaryEndsCall() async {
        let roomID = "!room:example.com"
        let roomSummaryProvider = RoomSummaryProviderMock()
        let roomSummaries = CurrentValueSubject<[RoomSummary], Never>([
            makeRoomSummary(id: roomID,
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: [])
        ])
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 1)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = roomSummaries.asCurrentValuePublisher()
        clientProxy.roomSummaryProvider = roomSummaryProvider
        clientProxy.staticRoomSummaryProvider = roomSummaryProvider
        service.setClientProxy(clientProxy)

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        configureLiveTimeline(for: room)
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }
        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: []))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .remoteEnded {
                    confirmation()
                }
            }

            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            await deliverIncomingPush(payload)
            #expect(await waitForIncomingLifecycleObservation(on: room))

            roomSummaries.send([
                makeRoomSummary(id: roomID,
                                isDirect: true,
                                hasOngoingCall: false,
                                participants: [],
                                lastCallEvent: .init(state: .ended, intent: .audio))
            ])
            #expect(await waitForEndedCall(reason: .remoteEnded) == false)

            roomInfoSubject.send(makeRoomInfo(id: roomID,
                                              isDirect: true,
                                              hasRoomCall: false,
                                              participants: []))
            #expect(await waitForEndedCall(reason: .remoteEnded))
        }
    }

    @Test
    func ongoingDirectCallEndsWhenRemoteLeavesCallMemberState() async throws {
        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let (room, roomInfoSubscription) = makeOngoingCallRoom(id: roomID,
                                                               ownUserID: ownUserID,
                                                               remoteUserID: remoteUserID)
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        let timelineProxy = try #require(room.timeline as? TimelineProxyMock)
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(room.subscribeToRoomInfoUpdatesCallsCount == 1)
        #expect(roomInfoSubscription.subscriptionStartCount == 1)
        #expect(room.infoPublisher.value.activeRoomCallParticipants.count == 2)
        #expect(await roomInfoSubscription.waitForTimelineSubscription())
        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                                   isDirect: true,
                                                                   hasRoomCall: true,
                                                                   participants: [ownUserID, remoteUserID])))

        let deferredEndCall = deferFulfillment(service.actions) { action in
            if case .endCall(let observedRoomID) = action {
                return observedRoomID == roomID
            }
            return false
        }

        #expect(roomInfoSubscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership-current",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: true),
            makeMatrixRTCMembershipTimelineItem(eventID: "$remote-membership-empty",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                                   isDirect: true,
                                                                   hasRoomCall: true,
                                                                   participants: [ownUserID])))
        try await deferredEndCall.fulfill()

        #expect(service.ongoingCallRoomIDPublisher.value == nil)
        #expect(room.subscribeToRoomInfoUpdatesCallsCount == 1)
        #expect(roomInfoSubscription.timelineSubscriptionStartCount == 1)
        #expect(timelineProxy.subscribeForUpdatesCallsCount >= 1)
    }

    @Test
    // swiftlint:disable:next function_body_length
    func ongoingDirectCallReconcilesRawSDKExplicitEmptyWithoutUITimelineRemoval() async throws {
        let roomID = "!raw-state-reconciliation:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let uiTimeline = TimelineSDKMock()
        uiTimeline.addListenerListenerReturnValue = TaskHandleSDKMock()
        uiTimeline.subscribeToBackPaginationStatusListenerReturnValue = TaskHandleSDKMock()
        let rawTimeline = TimelineSDKMock()
        rawTimeline.addListenerListenerReturnValue = TaskHandleSDKMock()
        let room = RoomSDKMock()
        room.idReturnValue = roomID
        room.ownUserIdReturnValue = ownUserID
        room.encryptionStateReturnValue = .encrypted
        room.roomInfoReturnValue = makeMatrixRTCRoomInfo(roomID: roomID,
                                                         participants: [ownUserID, remoteUserID])
        room.subscribeToRoomInfoUpdatesListenerReturnValue = TaskHandleSDKMock()
        let membersIterator = RoomMembersIteratorSDKMock()
        membersIterator.lenReturnValue = 0
        membersIterator.nextChunkChunkSizeReturnValue = []
        room.membersReturnValue = membersIterator
        room.membersNoSyncReturnValue = membersIterator
        room.timelineWithConfigurationConfigurationClosure = { configuration in
            switch configuration.filter {
            case .all:
                rawTimeline
            default:
                uiTimeline
            }
        }

        var rawStateEmptyPresent = false
        let rawStateRecorder = SDKListener<[TimelineDiff]> { diffs in
            rawStateEmptyPresent = diffs.contains { diff in
                guard case .pushBack(let item) = diff,
                      let event = item.asEvent(),
                      let rawJSON = event.lazyProvider.debugInfo().originalJson,
                      let data = rawJSON.data(using: .utf8),
                      let rawEvent = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = rawEvent["content"] as? [String: Any] else {
                    return false
                }
                return content.isEmpty
            }
        }
        let rawStateTimeline = try await room.timelineWithConfiguration(configuration: .init(focus: .live(hideThreadedEvents: false),
                                                                                             filter: .all,
                                                                                             internalIdPrefix: nil,
                                                                                             dateDividerMode: .daily,
                                                                                             trackReadReceipts: .disabled,
                                                                                             reportUtds: false))
        let rawStateRecorderHandle = await rawStateTimeline.addListener(listener: rawStateRecorder)
        defer { rawStateRecorderHandle.cancel() }

        let roomProxy = try await JoinedRoomProxy(roomListService: RoomListServiceSDKMock(),
                                                  room: room,
                                                  appSettings: appSettings,
                                                  analyticsService: AnalyticsService(client: AnalyticsClientMock(),
                                                                                     appSettings: appSettings))
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        let setupTask = Task {
            await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        }
        for _ in 0..<30 where uiTimeline.addListenerListenerReceivedListener == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let uiListener = try #require(uiTimeline.addListenerListenerReceivedListener)
        let localMembership = makeMatrixRTCMembershipSDKTimelineItem(eventID: "$raw-state-local-active",
                                                                     roomID: roomID,
                                                                     userID: ownUserID,
                                                                     deviceID: "LOCAL_DEVICE",
                                                                     membershipID: "LOCAL_PARTY")
        let remoteMembership = makeMatrixRTCMembershipSDKTimelineItem(eventID: "$raw-state-remote-active",
                                                                      roomID: roomID,
                                                                      userID: remoteUserID,
                                                                      deviceID: "REMOTE_DEVICE",
                                                                      membershipID: "REMOTE_PARTY")
        uiListener.onUpdate(diff: [.reset(values: [localMembership, remoteMembership])])
        await setupTask.value
        #expect(room.subscribeToRoomInfoUpdatesListenerCallsCount == 1)

        for _ in 0..<10 where rawTimeline.addListenerListenerCallsCount < 2 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        rawStateRecorder.onUpdate(diff: [.reset(values: [localMembership, remoteMembership])])
        if rawTimeline.addListenerListenerCallsCount > 1 {
            rawTimeline.addListenerListenerReceivedListener?.onUpdate(diff: [.reset(values: [localMembership, remoteMembership])])
        }

        let remoteExplicitEmpty = makeMatrixRTCMembershipSDKTimelineItem(eventID: "$raw-state-remote-empty",
                                                                         roomID: roomID,
                                                                         userID: remoteUserID,
                                                                         deviceID: "REMOTE_DEVICE",
                                                                         membershipID: "REMOTE_PARTY",
                                                                         isActive: false,
                                                                         createdAt: currentDate.addingTimeInterval(1))
        rawStateRecorder.onUpdate(diff: [.pushBack(value: remoteExplicitEmpty)])
        if rawTimeline.addListenerListenerCallsCount > 1 {
            rawTimeline.addListenerListenerReceivedListener?.onUpdate(diff: [.pushBack(value: remoteExplicitEmpty)])
        }
        #expect(rawStateEmptyPresent)

        let roomInfoTerminalReceived = room.subscribeToRoomInfoUpdatesListenerReceivedListener != nil
        room.subscribeToRoomInfoUpdatesListenerReceivedListener?.call(roomInfo: makeMatrixRTCRoomInfo(roomID: roomID,
                                                                                                      participants: [ownUserID]))
        for _ in 0..<20 where endCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(roomInfoTerminalReceived)
        #expect(uiTimeline.addListenerListenerCallsCount == 1)
        #expect(endCallCount == 1,
                "raw_state_empty_present=true ui_timeline_removal_missing=true roominfo_terminal_received=true pre_fix_remote_end_missing=true")
    }

    @Test
    func ongoingDirectCallReconcilesRawSDKRemovalOmissionWithoutExplicitEmpty() async throws {
        let roomID = "!raw-state-removal-reconciliation:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let uiTimeline = TimelineSDKMock()
        uiTimeline.addListenerListenerReturnValue = TaskHandleSDKMock()
        uiTimeline.subscribeToBackPaginationStatusListenerReturnValue = TaskHandleSDKMock()
        let rawTimeline = TimelineSDKMock()
        rawTimeline.addListenerListenerReturnValue = TaskHandleSDKMock()
        let room = RoomSDKMock()
        room.idReturnValue = roomID
        room.ownUserIdReturnValue = ownUserID
        room.encryptionStateReturnValue = .encrypted
        room.roomInfoReturnValue = makeMatrixRTCRoomInfo(roomID: roomID,
                                                         participants: [ownUserID, remoteUserID])
        room.subscribeToRoomInfoUpdatesListenerReturnValue = TaskHandleSDKMock()
        let membersIterator = RoomMembersIteratorSDKMock()
        membersIterator.lenReturnValue = 0
        membersIterator.nextChunkChunkSizeReturnValue = []
        room.membersReturnValue = membersIterator
        room.membersNoSyncReturnValue = membersIterator
        room.timelineWithConfigurationConfigurationClosure = { configuration in
            switch configuration.filter {
            case .all:
                rawTimeline
            default:
                uiTimeline
            }
        }

        let roomProxy = try await JoinedRoomProxy(roomListService: RoomListServiceSDKMock(),
                                                  room: room,
                                                  appSettings: appSettings,
                                                  analyticsService: AnalyticsService(client: AnalyticsClientMock(),
                                                                                     appSettings: appSettings))
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        let setupTask = Task {
            await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        }
        for _ in 0..<30 where uiTimeline.addListenerListenerReceivedListener == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let uiListener = try #require(uiTimeline.addListenerListenerReceivedListener)
        let localMembership = makeMatrixRTCMembershipSDKTimelineItem(eventID: "$raw-removal-local-active",
                                                                     roomID: roomID,
                                                                     userID: ownUserID,
                                                                     deviceID: "LOCAL_DEVICE",
                                                                     membershipID: "LOCAL_PARTY")
        let remoteMembership = makeMatrixRTCMembershipSDKTimelineItem(eventID: "$raw-removal-remote-active",
                                                                      roomID: roomID,
                                                                      userID: remoteUserID,
                                                                      deviceID: "REMOTE_DEVICE",
                                                                      membershipID: "REMOTE_PARTY")
        uiListener.onUpdate(diff: [.reset(values: [localMembership, remoteMembership])])
        await setupTask.value
        #expect(room.subscribeToRoomInfoUpdatesListenerCallsCount == 1)

        for _ in 0..<30 where rawTimeline.addListenerListenerReceivedListener == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let rawListener = try #require(rawTimeline.addListenerListenerReceivedListener)
        rawListener.onUpdate(diff: [.reset(values: [localMembership, remoteMembership])])
        try? await Task.sleep(for: .milliseconds(50))

        rawListener.onUpdate(diff: [.remove(index: 1)])
        let roomInfoTerminalReceived = room.subscribeToRoomInfoUpdatesListenerReceivedListener != nil
        room.subscribeToRoomInfoUpdatesListenerReceivedListener?.call(roomInfo: makeMatrixRTCRoomInfo(roomID: roomID,
                                                                                                      participants: []))
        for _ in 0..<20 where endCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(roomInfoTerminalReceived)
        #expect(uiTimeline.addListenerListenerCallsCount == 1)
        #expect(endCallCount == 1,
                "pre_fix_real_sdk_removal_semantics_remote_end_missing=true")
    }

    @Test(arguments: [
        "org.matrix.msc3401.call.member",
        "m.call.member",
        "org.matrix.msc4143.rtc.member",
        "m.rtc.member"
    ])
    func ongoingDirectCallSupportsRawMembershipEventFamily(eventType: String) async {
        let roomID = "!membership-family:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let localMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$family-local-active",
                                                                  roomID: roomID,
                                                                  userID: ownUserID,
                                                                  deviceID: "LOCAL_DEVICE",
                                                                  membershipID: "LOCAL_PARTY",
                                                                  eventType: eventType)
        let remoteMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$family-remote-active",
                                                                   roomID: roomID,
                                                                   userID: remoteUserID,
                                                                   deviceID: "REMOTE_DEVICE",
                                                                   membershipID: "REMOTE_PARTY",
                                                                   eventType: eventType)
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID, remoteUserID],
                                                       initialTimelineItems: [localMembership, remoteMembership])
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())

        let remoteExplicitEmpty = makeMatrixRTCMembershipTimelineItem(eventID: "$family-remote-empty",
                                                                      roomID: roomID,
                                                                      userID: remoteUserID,
                                                                      deviceID: "REMOTE_DEVICE",
                                                                      membershipID: "REMOTE_PARTY",
                                                                      isActive: false,
                                                                      eventType: eventType)
        #expect(subscription.receiveSDKRawMembershipUpdate([localMembership, remoteExplicitEmpty]))
        #expect(subscription.receiveSDKRawMembershipUpdate([localMembership, remoteExplicitEmpty]))
        #expect(endCallCount == 0)
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID])))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID])))
        for _ in 0..<30 where endCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(endCallCount == 1)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func ongoingDirectCallSameGenerationRoomInfoTerminalIgnoresStaleRawActiveStateAndEndsOnce() async {
        let roomID = "!room-info-first:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       remoteUserID: remoteUserID)
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))

        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: false,
                                                           participants: [])))
        for _ in 0..<30 where endCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(endCallCount == 1,
                "pre_fix_direct_roominfo_state_machine_remote_end_missing=true")
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func ongoingDirectCallRejectsMismatchedAndStaleRawMembershipMutations() async {
        let roomID = "!guarded-membership:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let initialTimestamp = currentDate ?? Date()
        let localMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$guarded-local-active",
                                                                  roomID: roomID,
                                                                  userID: ownUserID,
                                                                  createdAt: initialTimestamp)
        let remoteMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$guarded-remote-active",
                                                                   roomID: roomID,
                                                                   userID: remoteUserID,
                                                                   deviceID: "REMOTE_DEVICE",
                                                                   membershipID: "REMOTE_PARTY",
                                                                   createdAt: initialTimestamp)
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID, remoteUserID],
                                                       initialTimelineItems: [localMembership, remoteMembership])
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))

        let mismatchedMutation = makeMatrixRTCMembershipTimelineItem(eventID: "$guarded-remote-mismatched",
                                                                     roomID: roomID,
                                                                     userID: remoteUserID,
                                                                     deviceID: "REMOTE_DEVICE",
                                                                     membershipID: "REMOTE_PARTY",
                                                                     createdAt: initialTimestamp.addingTimeInterval(3),
                                                                     callID: "OTHER")
        #expect(subscription.receiveSDKRawMembershipUpdate([localMembership, remoteMembership, mismatchedMutation]))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(endCallCount == 0)

        let authoritativeEmpty = makeMatrixRTCMembershipTimelineItem(eventID: "$guarded-remote-empty",
                                                                     roomID: roomID,
                                                                     userID: remoteUserID,
                                                                     deviceID: "REMOTE_DEVICE",
                                                                     membershipID: "REMOTE_PARTY",
                                                                     isActive: false,
                                                                     createdAt: initialTimestamp.addingTimeInterval(2))
        let staleActive = makeMatrixRTCMembershipTimelineItem(eventID: "$guarded-remote-stale",
                                                              roomID: roomID,
                                                              userID: remoteUserID,
                                                              deviceID: "REMOTE_DEVICE",
                                                              membershipID: "REMOTE_PARTY",
                                                              createdAt: initialTimestamp.addingTimeInterval(1))
        #expect(subscription.receiveSDKRawMembershipUpdate([localMembership, authoritativeEmpty, staleActive, mismatchedMutation]))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID])))
        for _ in 0..<30 where endCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(endCallCount == 1)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func ongoingDirectCallReevaluatesRemoteMembershipAtExpiryAfterRoomInfoDropsRemote() async {
        let roomID = "!membership-expiry:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let membershipCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        currentDate = membershipCreatedAt
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID, remoteUserID],
                                                       initialTimelineItems: [
                                                           makeMatrixRTCMembershipTimelineItem(eventID: "$membership-expiry-local",
                                                                                               roomID: roomID,
                                                                                               userID: ownUserID,
                                                                                               deviceID: "LOCAL_DEVICE",
                                                                                               membershipID: "LOCAL_PARTY",
                                                                                               createdAt: membershipCreatedAt),
                                                           makeMatrixRTCMembershipTimelineItem(eventID: "$membership-expiry-remote",
                                                                                               roomID: roomID,
                                                                                               userID: remoteUserID,
                                                                                               deviceID: "REMOTE_DEVICE",
                                                                                               membershipID: "REMOTE_PARTY",
                                                                                               createdAt: membershipCreatedAt,
                                                                                               expiresInMilliseconds: 1000)
                                                       ])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))
        try? await Task.sleep(for: .milliseconds(50))

        currentDate = membershipCreatedAt.addingTimeInterval(0.999)
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(endCallCount == 0)
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)

        currentDate = membershipCreatedAt.addingTimeInterval(1)
        #expect(endCallCount == 0)
        await testClock.advance(by: .milliseconds(1))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID])))
        for _ in 0..<30 where endCallCount == 0 {
            await Task.yield()
        }

        #expect(endCallCount == 1)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
        await testClock.advance(by: .seconds(1))
        #expect(endCallCount == 1)
    }

    @Test
    func ongoingDirectCallMembershipRefreshReschedulesExpiryReevaluation() async {
        let roomID = "!membership-refresh:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let membershipCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        currentDate = membershipCreatedAt
        let localMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$membership-refresh-local",
                                                                  roomID: roomID,
                                                                  userID: ownUserID,
                                                                  deviceID: "LOCAL_DEVICE",
                                                                  membershipID: "LOCAL_PARTY",
                                                                  createdAt: membershipCreatedAt)
        let remoteMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$membership-refresh-remote",
                                                                   roomID: roomID,
                                                                   userID: remoteUserID,
                                                                   deviceID: "REMOTE_DEVICE",
                                                                   membershipID: "REMOTE_PARTY",
                                                                   createdAt: membershipCreatedAt,
                                                                   expiresInMilliseconds: 10000)
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID, remoteUserID],
                                                       initialTimelineItems: [localMembership, remoteMembership])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))
        try? await Task.sleep(for: .milliseconds(50))

        currentDate = membershipCreatedAt.addingTimeInterval(0.999)
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))
        #expect(subscription.receiveSDKTimelineUpdate([
            localMembership,
            makeMatrixRTCMembershipTimelineItem(eventID: "$membership-refresh-remote-new",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                createdAt: currentDate,
                                                expiresInMilliseconds: 1000)
        ]))
        try? await Task.sleep(for: .milliseconds(50))

        currentDate = membershipCreatedAt.addingTimeInterval(1)
        await testClock.advance(by: .milliseconds(1))
        #expect(endCallCount == 0)
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)

        currentDate = membershipCreatedAt.addingTimeInterval(1.5)
        await testClock.advance(by: .milliseconds(500))
        #expect(endCallCount == 0)

        #expect(subscription.receiveSDKTimelineUpdate([
            localMembership,
            makeMatrixRTCMembershipTimelineItem(eventID: "$membership-refresh-remote-later",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                createdAt: currentDate,
                                                expiresInMilliseconds: 10000)
        ]))
        try? await Task.sleep(for: .milliseconds(50))

        currentDate = membershipCreatedAt.addingTimeInterval(1.999)
        await testClock.advance(by: .milliseconds(499))
        #expect(endCallCount == 0)

        currentDate = membershipCreatedAt.addingTimeInterval(2)
        await testClock.advance(by: .milliseconds(1))
        #expect(endCallCount == 0)
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)

        currentDate = membershipCreatedAt.addingTimeInterval(11.499)
        await testClock.advance(by: .milliseconds(9499))
        #expect(endCallCount == 0)

        currentDate = membershipCreatedAt.addingTimeInterval(11.5)
        await testClock.advance(by: .milliseconds(1))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID])))
        for _ in 0..<30 where endCallCount == 0 {
            await Task.yield()
        }

        #expect(endCallCount == 1)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
        await testClock.advance(by: .seconds(10))
        #expect(endCallCount == 1)
    }

    @Test
    func ongoingDirectCallLocalOnlyProjectionKeepsRemoteEndDecisionWhenLocalLaterLeaves() async {
        let roomID = "!local-only-transition:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       remoteUserID: remoteUserID)
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))

        #expect(subscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$local-only-local-current",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: true),
            makeMatrixRTCMembershipTimelineItem(eventID: "$local-only-remote-empty",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID])))
        for _ in 0..<30 where endCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(endCallCount == 1)

        #expect(subscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$local-only-local-empty",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: false),
            makeMatrixRTCMembershipTimelineItem(eventID: "$local-only-remote-empty-duplicate",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: false,
                                                           participants: [])))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(endCallCount == 1)
    }

    @Test
    func ongoingDirectCallCoalescedTwoToZeroEndsExactlyOnce() async {
        let roomID = "!coalesced-zero:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       remoteUserID: remoteUserID)
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))

        let emptyMemberships = [
            makeMatrixRTCMembershipTimelineItem(eventID: "$coalesced-local-empty",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: false),
            makeMatrixRTCMembershipTimelineItem(eventID: "$coalesced-remote-empty",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]
        #expect(subscription.receiveSDKTimelineUpdate(emptyMemberships))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(endCallCount == 0)
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: false,
                                                           participants: [])))
        for _ in 0..<30 where endCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(endCallCount == 1)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
        #expect(subscription.receiveSDKTimelineUpdate(emptyMemberships))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: false,
                                                           participants: [])))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(endCallCount == 1)
    }

    @Test
    func ongoingDirectCallAmbiguousLocalMembershipIdentityFailsClosed() async {
        let roomID = "!ambiguous-local:example.com"
        let ownUserID = "@test:user.net"
        let firstLocalMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$ambiguous-local-first",
                                                                       roomID: roomID,
                                                                       userID: ownUserID,
                                                                       deviceID: "LOCAL_DEVICE",
                                                                       membershipID: "LOCAL_PARTY_ONE",
                                                                       isActive: true)
        let secondLocalMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$ambiguous-local-second",
                                                                        roomID: roomID,
                                                                        userID: ownUserID,
                                                                        deviceID: "LOCAL_DEVICE",
                                                                        membershipID: "LOCAL_PARTY_TWO",
                                                                        isActive: true)
        let remoteMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$ambiguous-local-remote",
                                                                   roomID: roomID,
                                                                   userID: ownUserID,
                                                                   deviceID: "REMOTE_DEVICE",
                                                                   membershipID: "REMOTE_PARTY",
                                                                   isActive: true)
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID, ownUserID, ownUserID],
                                                       initialTimelineItems: [firstLocalMembership, secondLocalMembership, remoteMembership])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, ownUserID, ownUserID])))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: false,
                                                           participants: [])))
        #expect(subscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$ambiguous-local-first-empty",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY_ONE",
                                                isActive: false),
            makeMatrixRTCMembershipTimelineItem(eventID: "$ambiguous-local-second-empty",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY_TWO",
                                                isActive: false),
            makeMatrixRTCMembershipTimelineItem(eventID: "$ambiguous-local-remote-empty",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        try? await Task.sleep(for: .milliseconds(100))

        #expect(endCallCount == 0)
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
    }

    @Test
    func ongoingDirectCallInitialEmptyRoomInfoDoesNotEndBeforeRemoteMembershipIsObserved() async {
        let roomID = "!empty-room:example.com"
        let ownUserID = "@test:user.net"
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: false,
                                                       initialParticipants: [])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        try? await Task.sleep(for: .milliseconds(100))

        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
    }

    @Test
    func ongoingDirectCallLocalMembershipOnlyAndExpiredRemoteDoNotEndBeforeRemoteMembershipIsObserved() async {
        let roomID = "!local-only-room:example.com"
        let ownUserID = "@test:user.net"
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID],
                                                       initialTimelineItems: [
                                                           makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership",
                                                                                               roomID: roomID),
                                                           makeMatrixRTCMembershipTimelineItem(eventID: "$expired-remote-membership",
                                                                                               roomID: roomID,
                                                                                               userID: "@alice:example.com",
                                                                                               deviceID: "REMOTE_DEVICE",
                                                                                               membershipID: "REMOTE_PARTY",
                                                                                               createdAt: currentDate.addingTimeInterval(-2),
                                                                                               expiresInMilliseconds: 1000)
                                                       ])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        try? await Task.sleep(for: .milliseconds(100))

        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
    }

    @Test
    func ongoingDirectCallLocalMembershipRemovalDoesNotEndBeforeRemoteMembershipIsObserved() async {
        let roomID = "!preconvergence-room:example.com"
        let ownUserID = "@test:user.net"
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID],
                                                       initialTimelineItems: [
                                                           makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership",
                                                                                               roomID: roomID)
                                                       ])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership-empty",
                                                roomID: roomID,
                                                isActive: false)
        ]))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: false,
                                                           participants: [])))
        try? await Task.sleep(for: .milliseconds(100))

        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
    }

    @Test
    func ongoingDirectCallRepeatedEmptyUpdatesDoNotEndBeforeRemoteMembershipIsObserved() async {
        let roomID = "!repeated-empty-room:example.com"
        let ownUserID = "@test:user.net"
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID],
                                                       initialTimelineItems: [
                                                           makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership",
                                                                                               roomID: roomID)
                                                       ])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())

        for index in 0..<3 {
            #expect(subscription.receiveSDKTimelineUpdate([
                makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership-empty-\(index)",
                                                    roomID: roomID,
                                                    isActive: false)
            ]))
            #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                               isDirect: true,
                                                               hasRoomCall: false,
                                                               participants: [])))
        }
        try? await Task.sleep(for: .milliseconds(100))

        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
    }

    @Test
    func ongoingDirectCallTreatsSameAccountDifferentDeviceAndPartyAsRemote() async throws {
        let roomID = "!same-account-room:example.com"
        let ownUserID = "@test:user.net"
        let localMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership",
                                                                  roomID: roomID,
                                                                  userID: ownUserID,
                                                                  deviceID: "LOCAL_DEVICE",
                                                                  membershipID: "LOCAL_PARTY",
                                                                  isActive: true)
        let remoteMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$remote-membership",
                                                                   roomID: roomID,
                                                                   userID: ownUserID,
                                                                   deviceID: "REMOTE_DEVICE",
                                                                   membershipID: "REMOTE_PARTY",
                                                                   isActive: true)
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID, ownUserID],
                                                       initialTimelineItems: [localMembership, remoteMembership])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, ownUserID])))

        let deferredEndCall = deferFulfillment(service.actions) { action in
            if case .endCall(let observedRoomID) = action {
                return observedRoomID == roomID
            }
            return false
        }

        #expect(subscription.receiveSDKTimelineUpdate([
            localMembership,
            makeMatrixRTCMembershipTimelineItem(eventID: "$remote-membership-empty",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID])))
        try await deferredEndCall.fulfill()

        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func incomingOngoingCallLatchesRemoteMembershipBeforeLocalPublication() async throws {
        let roomID = "!incoming-convergence-room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let localMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership",
                                                                  roomID: roomID,
                                                                  userID: ownUserID,
                                                                  deviceID: "LOCAL_DEVICE",
                                                                  membershipID: "LOCAL_PARTY",
                                                                  isActive: true)
        let remoteMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$remote-membership",
                                                                   roomID: roomID,
                                                                   userID: remoteUserID,
                                                                   deviceID: "REMOTE_DEVICE",
                                                                   membershipID: "REMOTE_PARTY",
                                                                   isActive: true)
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [remoteUserID],
                                                       initialTimelineItems: [remoteMembership])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [remoteUserID])))
        #expect(subscription.receiveSDKTimelineUpdate([remoteMembership, localMembership]))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))

        let deferredEndCall = deferFulfillment(service.actions) { action in
            if case .endCall(let observedRoomID) = action {
                return observedRoomID == roomID
            }
            return false
        }

        #expect(subscription.receiveSDKTimelineUpdate([
            localMembership,
            makeMatrixRTCMembershipTimelineItem(eventID: "$remote-membership-empty",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID])))
        try await deferredEndCall.fulfill()
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func duplicateRemoteMembershipRemovalEndsOngoingCallOnce() async {
        let roomID = "!duplicate-removal-room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       remoteUserID: remoteUserID)
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        var endedRoomIDs = [String]()
        service.actions
            .sink { action in
                if case .endCall(let roomID) = action {
                    endedRoomIDs.append(roomID)
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: room))
        #expect(await subscription.waitForTimelineSubscription())
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: true,
                                                           participants: [ownUserID, remoteUserID])))

        let remoteRemovedInfo = makeRoomInfo(id: roomID,
                                             isDirect: true,
                                             hasRoomCall: true,
                                             participants: [ownUserID])
        let remoteRemovedMemberships = [
            makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership-current",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: true),
            makeMatrixRTCMembershipTimelineItem(eventID: "$remote-membership-empty",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]
        #expect(subscription.receiveSDKTimelineUpdate(remoteRemovedMemberships))
        #expect(subscription.receiveSDKUpdate(remoteRemovedInfo))
        #expect(subscription.receiveSDKTimelineUpdate(remoteRemovedMemberships))
        #expect(subscription.receiveSDKUpdate(remoteRemovedInfo))
        try? await Task.sleep(for: .milliseconds(100))

        #expect(endedRoomIDs == [roomID])
    }

    @Test
    func ongoingMembershipExpiryTaskRejectsReplacedCallIdentity() async throws {
        let firstRoomID = "!first-expiry-room:example.com"
        let secondRoomID = "!second-expiry-room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let membershipCreatedAt = try #require(currentDate)
        let (firstRoom, firstSubscription) = makeOngoingCallRoom(id: firstRoomID,
                                                                 ownUserID: ownUserID,
                                                                 initialHasRoomCall: true,
                                                                 initialParticipants: [ownUserID, remoteUserID],
                                                                 initialTimelineItems: [
                                                                     makeMatrixRTCMembershipTimelineItem(eventID: "$first-expiry-local",
                                                                                                         roomID: firstRoomID,
                                                                                                         userID: ownUserID,
                                                                                                         createdAt: membershipCreatedAt),
                                                                     makeMatrixRTCMembershipTimelineItem(eventID: "$first-expiry-remote",
                                                                                                         roomID: firstRoomID,
                                                                                                         userID: remoteUserID,
                                                                                                         deviceID: "REMOTE_DEVICE",
                                                                                                         membershipID: "REMOTE_PARTY",
                                                                                                         createdAt: membershipCreatedAt,
                                                                                                         expiresInMilliseconds: 1000)
                                                                 ])
        let (secondRoom, secondSubscription) = makeOngoingCallRoom(id: secondRoomID,
                                                                   ownUserID: ownUserID,
                                                                   remoteUserID: remoteUserID)
        clientProxy.roomForIdentifierClosure = { roomID in
            switch roomID {
            case firstRoomID: .joined(firstRoom)
            case secondRoomID: .joined(secondRoom)
            default: nil
            }
        }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: firstRoomID, roomDisplayName: "First")
        #expect(await waitForRoomInfoSubscription(on: firstRoom))
        #expect(await firstSubscription.waitForTimelineSubscription())
        #expect(firstSubscription.receiveSDKUpdate(makeRoomInfo(id: firstRoomID,
                                                                isDirect: true,
                                                                hasRoomCall: true,
                                                                participants: [ownUserID, remoteUserID])))
        try? await Task.sleep(for: .milliseconds(50))

        currentDate = membershipCreatedAt.addingTimeInterval(0.999)
        #expect(firstSubscription.receiveSDKUpdate(makeRoomInfo(id: firstRoomID,
                                                                isDirect: true,
                                                                hasRoomCall: true,
                                                                participants: [ownUserID, remoteUserID])))
        try? await Task.sleep(for: .milliseconds(50))

        await service.setupCallSession(roomID: secondRoomID, roomDisplayName: "Second")
        #expect(await waitForRoomInfoSubscription(on: secondRoom))
        #expect(await secondSubscription.waitForTimelineSubscription())
        #expect(secondSubscription.receiveSDKUpdate(makeRoomInfo(id: secondRoomID,
                                                                 isDirect: true,
                                                                 hasRoomCall: true,
                                                                 participants: [ownUserID, remoteUserID])))

        currentDate = membershipCreatedAt.addingTimeInterval(1)
        await testClock.advance(by: .milliseconds(1))
        #expect(firstSubscription.receiveSDKUpdate(makeRoomInfo(id: firstRoomID,
                                                                isDirect: true,
                                                                hasRoomCall: true,
                                                                participants: [ownUserID])))
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(endCallCount == 0)
        #expect(service.ongoingCallRoomIDPublisher.value == secondRoomID)
    }

    @Test
    func ongoingRoomInfoSubscriptionRejectsStaleProxyAfterCallIdentityChanges() async {
        let firstRoomID = "!first-room:example.com"
        let secondRoomID = "!second-room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let (firstRoom, firstSubscription) = makeOngoingCallRoom(id: firstRoomID,
                                                                 ownUserID: ownUserID,
                                                                 remoteUserID: remoteUserID)
        let (secondRoom, secondSubscription) = makeOngoingCallRoom(id: secondRoomID,
                                                                   ownUserID: ownUserID,
                                                                   remoteUserID: remoteUserID)
        clientProxy.roomForIdentifierClosure = { roomID in
            switch roomID {
            case firstRoomID:
                .joined(firstRoom)
            case secondRoomID:
                .joined(secondRoom)
            default:
                nil
            }
        }

        var endedRoomIDs = [String]()
        service.actions
            .sink { action in
                if case .endCall(let roomID) = action {
                    endedRoomIDs.append(roomID)
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: firstRoomID, roomDisplayName: "First")
        #expect(await waitForRoomInfoSubscription(on: firstRoom))
        #expect(await firstSubscription.waitForTimelineSubscription())

        await service.setupCallSession(roomID: secondRoomID, roomDisplayName: "Second")
        #expect(await waitForRoomInfoSubscription(on: secondRoom))
        #expect(await secondSubscription.waitForTimelineSubscription())
        #expect(secondSubscription.receiveSDKUpdate(makeRoomInfo(id: secondRoomID,
                                                                 isDirect: true,
                                                                 hasRoomCall: true,
                                                                 participants: [ownUserID, remoteUserID])))

        #expect(firstSubscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$first-local-membership-current",
                                                roomID: firstRoomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: true),
            makeMatrixRTCMembershipTimelineItem(eventID: "$first-remote-membership-empty",
                                                roomID: firstRoomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        #expect(firstSubscription.receiveSDKUpdate(makeRoomInfo(id: firstRoomID,
                                                                isDirect: true,
                                                                hasRoomCall: true,
                                                                participants: [ownUserID])))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(service.ongoingCallRoomIDPublisher.value == secondRoomID)
        #expect(endedRoomIDs.isEmpty)

        #expect(secondSubscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$second-local-membership-current",
                                                roomID: secondRoomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: true),
            makeMatrixRTCMembershipTimelineItem(eventID: "$second-remote-membership-empty",
                                                roomID: secondRoomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        #expect(secondSubscription.receiveSDKUpdate(makeRoomInfo(id: secondRoomID,
                                                                 isDirect: true,
                                                                 hasRoomCall: true,
                                                                 participants: [ownUserID])))
        for _ in 0..<30 where endedRoomIDs.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(endedRoomIDs == [secondRoomID])
        #expect(firstRoom.subscribeToRoomInfoUpdatesCallsCount == 1)
        #expect(secondRoom.subscribeToRoomInfoUpdatesCallsCount == 1)
        #expect(firstSubscription.timelineSubscriptionStartCount == 1)
        #expect(secondSubscription.timelineSubscriptionStartCount == 1)
    }

    @Test
    func differentClientSessionRejectsStaleGenerationAndMismatchedIdentityCallbacks() async {
        let roomID = "!session-replacement-room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let (firstRoom, firstSubscription) = makeOngoingCallRoom(id: roomID,
                                                                 ownUserID: ownUserID,
                                                                 remoteUserID: remoteUserID)
        let (replacementRoom, replacementSubscription) = makeOngoingCallRoom(id: roomID,
                                                                             ownUserID: ownUserID,
                                                                             initialHasRoomCall: true,
                                                                             initialParticipants: [ownUserID],
                                                                             initialTimelineItems: [
                                                                                 makeMatrixRTCMembershipTimelineItem(eventID: "$replacement-local-membership",
                                                                                                                     roomID: roomID,
                                                                                                                     userID: ownUserID,
                                                                                                                     deviceID: "LOCAL_DEVICE",
                                                                                                                     membershipID: "LOCAL_PARTY",
                                                                                                                     isActive: true)
                                                                             ])
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(firstRoom)
        }

        var endCallCount = 0
        service.actions
            .sink { action in
                if case .endCall = action {
                    endCallCount += 1
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        #expect(await waitForRoomInfoSubscription(on: firstRoom))
        #expect(await firstSubscription.waitForTimelineSubscription())
        #expect(firstSubscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                                isDirect: true,
                                                                hasRoomCall: true,
                                                                participants: [ownUserID, remoteUserID])))

        let replacementClientProxy = ClientProxyMock(.init(userID: ownUserID, deviceID: "LOCAL_DEVICE"))
        replacementClientProxy.roomForIdentifierClosure = { _ in
            .joined(replacementRoom)
        }
        service.setClientProxy(replacementClientProxy)
        #expect(await waitForRoomInfoSubscription(on: replacementRoom))
        #expect(await replacementSubscription.waitForTimelineSubscription())

        #expect(firstSubscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$stale-local-current",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: true),
            makeMatrixRTCMembershipTimelineItem(eventID: "$stale-remote-empty",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        #expect(firstSubscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                                isDirect: true,
                                                                hasRoomCall: true,
                                                                participants: [ownUserID])))
        #expect(replacementSubscription.receiveSDKUpdate(makeRoomInfo(id: "!mismatched-room:example.com",
                                                                      isDirect: true,
                                                                      hasRoomCall: true,
                                                                      participants: [ownUserID, remoteUserID])))
        #expect(replacementSubscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$replacement-local-empty",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: false)
        ]))
        #expect(replacementSubscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                                      isDirect: true,
                                                                      hasRoomCall: false,
                                                                      participants: [])))
        try? await Task.sleep(for: .milliseconds(100))

        #expect(endCallCount == 0)
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)
        #expect(firstRoom.subscribeToRoomInfoUpdatesCallsCount == 1)
        #expect(replacementRoom.subscribeToRoomInfoUpdatesCallsCount == 1)
    }

    @Test
    func newOngoingCallStartsWithoutRemoteMembershipObservedByPreviousCall() async {
        let firstRoomID = "!latched-room:example.com"
        let secondRoomID = "!fresh-room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let (firstRoom, firstSubscription) = makeOngoingCallRoom(id: firstRoomID,
                                                                 ownUserID: ownUserID,
                                                                 remoteUserID: remoteUserID)
        let (secondRoom, secondSubscription) = makeOngoingCallRoom(id: secondRoomID,
                                                                   ownUserID: ownUserID,
                                                                   initialHasRoomCall: true,
                                                                   initialParticipants: [ownUserID],
                                                                   initialTimelineItems: [
                                                                       makeMatrixRTCMembershipTimelineItem(eventID: "$second-local-membership",
                                                                                                           roomID: secondRoomID,
                                                                                                           userID: ownUserID,
                                                                                                           deviceID: "LOCAL_DEVICE",
                                                                                                           membershipID: "LOCAL_PARTY",
                                                                                                           isActive: true)
                                                                   ])
        clientProxy.roomForIdentifierClosure = { roomID in
            switch roomID {
            case firstRoomID:
                .joined(firstRoom)
            case secondRoomID:
                .joined(secondRoom)
            default:
                nil
            }
        }

        var endedRoomIDs = [String]()
        service.actions
            .sink { action in
                if case .endCall(let roomID) = action {
                    endedRoomIDs.append(roomID)
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: firstRoomID, roomDisplayName: "First")
        #expect(await waitForRoomInfoSubscription(on: firstRoom))
        #expect(await firstSubscription.waitForTimelineSubscription())
        await service.setupCallSession(roomID: secondRoomID, roomDisplayName: "Second")
        #expect(await waitForRoomInfoSubscription(on: secondRoom))
        #expect(await secondSubscription.waitForTimelineSubscription())

        #expect(firstSubscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$first-local-membership-current",
                                                roomID: firstRoomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: true),
            makeMatrixRTCMembershipTimelineItem(eventID: "$first-remote-membership-empty",
                                                roomID: firstRoomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]))
        #expect(firstSubscription.receiveSDKUpdate(makeRoomInfo(id: firstRoomID,
                                                                isDirect: true,
                                                                hasRoomCall: true,
                                                                participants: [ownUserID])))
        #expect(secondSubscription.receiveSDKTimelineUpdate([
            makeMatrixRTCMembershipTimelineItem(eventID: "$second-local-membership-empty",
                                                roomID: secondRoomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: false)
        ]))
        #expect(secondSubscription.receiveSDKUpdate(makeRoomInfo(id: secondRoomID,
                                                                 isDirect: true,
                                                                 hasRoomCall: false,
                                                                 participants: [])))
        try? await Task.sleep(for: .milliseconds(100))

        #expect(endedRoomIDs.isEmpty)
        #expect(service.ongoingCallRoomIDPublisher.value == secondRoomID)
    }

    @Test
    func staleObservationTaskCannotClearNewCallSubscription() async {
        let firstRoomID = "!delayed-room:example.com"
        let secondRoomID = "!current-room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        let (firstRoom, _) = makeOngoingCallRoom(id: firstRoomID,
                                                 ownUserID: ownUserID,
                                                 remoteUserID: remoteUserID)
        let (secondRoom, secondSubscription) = makeOngoingCallRoom(id: secondRoomID,
                                                                   ownUserID: ownUserID,
                                                                   remoteUserID: remoteUserID)
        let firstLookupStarted = CurrentValueSubject<Bool, Never>(false)
        clientProxy.roomForIdentifierClosure = { roomID in
            switch roomID {
            case firstRoomID:
                firstLookupStarted.send(true)
                try? await Task.sleep(for: .milliseconds(200))
                return .joined(firstRoom)
            case secondRoomID:
                return .joined(secondRoom)
            default:
                return nil
            }
        }

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: firstRoomID, roomDisplayName: "Delayed")
        for _ in 0..<30 where !firstLookupStarted.value {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(firstLookupStarted.value)

        await service.setupCallSession(roomID: secondRoomID, roomDisplayName: "Current")
        #expect(await waitForRoomInfoSubscription(on: secondRoom))
        try? await Task.sleep(for: .milliseconds(250))

        #expect(firstRoom.subscribeToRoomInfoUpdatesCallsCount == 0)
        #expect(secondRoom.subscribeToRoomInfoUpdatesCallsCount == 1)
        #expect(secondSubscription.subscriptionStartCount == 1)
        #expect(service.ongoingCallRoomIDPublisher.value == secondRoomID)
        service.tearDownCallSession()
    }

    @Test
    func completedCallReleasesProxyAndSubsequentCallCreatesNewSubscription() async {
        let firstRoomID = "!released-room:example.com"
        let secondRoomID = "!subsequent-room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"
        var firstRoom: JoinedRoomProxyMock?
        let firstSubscription: RoomInfoSubscriptionHarness
        do {
            let firstCall = makeOngoingCallRoom(id: firstRoomID,
                                                ownUserID: ownUserID,
                                                remoteUserID: remoteUserID)
            firstRoom = firstCall.0
            firstSubscription = firstCall.1
        }
        weak var weakFirstRoom: JoinedRoomProxyMock?
        weakFirstRoom = firstRoom

        let (secondRoom, secondSubscription) = makeOngoingCallRoom(id: secondRoomID,
                                                                   ownUserID: ownUserID,
                                                                   remoteUserID: remoteUserID)
        clientProxy.roomForIdentifierClosure = { roomID in
            switch roomID {
            case firstRoomID:
                if let firstRoom {
                    .joined(firstRoom)
                } else {
                    nil
                }
            case secondRoomID:
                .joined(secondRoom)
            default:
                nil
            }
        }

        service.setClientProxy(clientProxy)
        await service.setupCallSession(roomID: firstRoomID, roomDisplayName: "Released")
        #expect(await waitForRoomInfoSubscription(on: firstRoom))
        #expect(await firstSubscription.waitForTimelineSubscription())

        service.tearDownCallSession()
        firstRoom = nil
        for _ in 0..<30 where weakFirstRoom != nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(weakFirstRoom == nil)

        await service.setupCallSession(roomID: secondRoomID, roomDisplayName: "Subsequent")
        #expect(await waitForRoomInfoSubscription(on: secondRoom))
        #expect(await secondSubscription.waitForTimelineSubscription())
        #expect(secondSubscription.subscriptionStartCount == 1)
        #expect(secondSubscription.timelineSubscriptionStartCount == 1)
        service.tearDownCallSession()
    }

    @Test
    func ongoingDirectCallUsesIncomingRTCNotificationForDeclineListener() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        configureLiveTimeline(for: room)

        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: [ownUserID, remoteUserID]))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        let declineHandle = TaskHandleSDKMock()
        var observedRTCNotificationID: String?
        var declineListener: CallDeclineListener?
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { rtcNotificationEventID, listener in
            observedRTCNotificationID = rtcNotificationEventID
            declineListener = listener
            return .success(declineHandle)
        }

        let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")

        await confirmation { confirmation in
            service.actions
                .sink { action in
                    if case .endCall(let observedRoomID) = action, observedRoomID == roomID {
                        confirmation()
                    }
                }
                .store(in: &cancellables)

            #expect(await waitForIncomingLifecycleObservation(on: room))
            declineListener?.call(declinerUserId: remoteUserID)
        }

        #expect(observedRTCNotificationID == "$000")
        #expect(declineHandle.cancelCalled)
    }

    @Test
    func ongoingDirectCallFallsBackToRemoteRTCNotificationForDeclineListenerWhenOwnIsMissing() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: [ownUserID, remoteUserID]))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        guard let timelineProxy = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock else {
            Issue.record("Failed configuring timeline mocks.")
            return
        }

        timelineItemProvider.itemProxies = [
            makeCallTimelineItem(eventID: "$remoteInvite",
                                 sender: remoteUserID,
                                 isOwn: false,
                                 eventType: .callInvite)
        ]
        timelineItemProvider.updatePublisher = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>((timelineItemProvider.itemProxies, .initial)).eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live

        var observedRTCNotificationID: String?
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { rtcNotificationEventID, _ in
            observedRTCNotificationID = rtcNotificationEventID
            return .success(TaskHandleSDKMock())
        }

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        try? await Task.sleep(for: .milliseconds(120))

        #expect(observedRTCNotificationID == "$remoteInvite")
    }

    @Test
    func ongoingDirectCallObservesDeclinesForOwnAndRemoteRTCNotifications() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        guard let timelineProxy = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock else {
            Issue.record("Failed configuring timeline mocks.")
            return
        }

        timelineItemProvider.itemProxies = [
            makeCallTimelineItem(eventID: "$ownInvite",
                                 sender: ownUserID,
                                 isOwn: true,
                                 eventType: .callInvite),
            makeCallTimelineItem(eventID: "$remoteInvite",
                                 sender: remoteUserID,
                                 isOwn: false,
                                 eventType: .callInvite)
        ]
        timelineItemProvider.updatePublisher = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>((timelineItemProvider.itemProxies, .initial)).eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live

        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: [ownUserID, remoteUserID]))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .success(TaskHandleSDKMock())
        }

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        try? await Task.sleep(for: .milliseconds(200))

        let observedRTCNotificationIDs = Set(room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReceivedInvocations.map(\.rtcNotificationEventID))
        #expect(observedRTCNotificationIDs == Set(["$ownInvite", "$remoteInvite"]))
    }

    @Test
    func ongoingDirectCallRefreshesDeclineListenersWhenRemoteRTCNotificationArrivesLater() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        guard let timelineProxy = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock else {
            Issue.record("Failed configuring timeline mocks.")
            return
        }

        let timelineUpdates = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>(([], .initial))
        let ownInvite = makeCallTimelineItem(eventID: "$ownInvite",
                                             sender: ownUserID,
                                             isOwn: true,
                                             eventType: .callInvite)
        let remoteInvite = makeCallTimelineItem(eventID: "$remoteInvite",
                                                sender: remoteUserID,
                                                isOwn: false,
                                                eventType: .callInvite)

        timelineItemProvider.itemProxies = [ownInvite]
        timelineItemProvider.updatePublisher = timelineUpdates.eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live

        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: [ownUserID, remoteUserID]))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .success(TaskHandleSDKMock())
        }

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        try? await Task.sleep(for: .milliseconds(200))

        timelineItemProvider.itemProxies = [ownInvite, remoteInvite]
        timelineUpdates.send(([ownInvite, remoteInvite], .initial))
        try? await Task.sleep(for: .milliseconds(200))

        let observedRTCNotificationIDs = Set(room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReceivedInvocations.map(\.rtcNotificationEventID))
        #expect(observedRTCNotificationIDs == Set(["$ownInvite", "$remoteInvite"]))
    }

    @Test
    func requestCallTerminationSkipsDeclineForOutgoingCall() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        guard let timelineProxy = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock else {
            Issue.record("Failed configuring timeline mocks.")
            return
        }

        timelineItemProvider.itemProxies = [
            makeCallTimelineItem(eventID: "$ownInvite",
                                 sender: ownUserID,
                                 isOwn: true,
                                 eventType: .callInvite),
            makeCallTimelineItem(eventID: "$remoteInvite",
                                 sender: remoteUserID,
                                 isOwn: false,
                                 eventType: .callInvite)
        ]
        timelineItemProvider.updatePublisher = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>((timelineItemProvider.itemProxies, .initial)).eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live

        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: [ownUserID, remoteUserID]))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .success(TaskHandleSDKMock())
        }
        room.declineCallNotificationIDClosure = { _ in
            .success(())
        }

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        try? await Task.sleep(for: .milliseconds(200))

        await service.requestCallTermination(roomID: roomID)

        #expect(room.declineCallNotificationIDReceivedInvocations.isEmpty)
    }

    @Test
    func requestCallTerminationIgnoresCachedOwnRTCNotificationID() async {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        guard let timelineProxy = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock else {
            Issue.record("Failed configuring timeline mocks.")
            return
        }

        let ownInvite = makeCallTimelineItem(eventID: "$ownInvite",
                                             sender: ownUserID,
                                             isOwn: true,
                                             eventType: .callInvite)
        let timelineUpdates = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>(([ownInvite], .initial))
        timelineItemProvider.itemProxies = [ownInvite]
        timelineItemProvider.updatePublisher = timelineUpdates.eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live

        room.infoPublisher = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                            isDirect: true,
                                                                                            hasRoomCall: true,
                                                                                            participants: [ownUserID])).asCurrentValuePublisher()
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }
        room.declineCallNotificationIDClosure = { _ in
            .failure(.sdkError(DeclineOwnCallMockError()))
        }

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        try? await Task.sleep(for: .milliseconds(150))

        // Drop timeline events so only the cached rtc notification remains.
        timelineItemProvider.itemProxies = []
        timelineUpdates.send(([], .initial))

        await service.requestCallTermination(roomID: roomID)
        try? await Task.sleep(for: .seconds(2))

        #expect(room.declineCallNotificationIDReceivedInvocations.isEmpty)
    }

    @Test
    func incomingPushCallIntentAliasesUseExpectedStartMode() async {
        let intentKeys = [
            ElementCallServiceNotificationKey.callIntent.rawValue,
            "call_intent",
            "intent",
            "call_type",
            "callType"
        ]

        for intentKey in intentKeys {
            await assertIncomingPush(callIntentKey: intentKey,
                                     callIntent: "StartCallDMVoice",
                                     expectsVideo: false)
            await assertIncomingPush(callIntentKey: intentKey,
                                     callIntent: "StartCallDM",
                                     expectsVideo: true)
        }
    }

    @Test
    func incomingAudioPushReportsCallKitWithoutVideo() async {
        await assertIncomingPush(callIntentKey: "call_type",
                                 callIntent: "audio",
                                 expectsVideo: false)
    }

    @Test
    func incomingPushCallIntentParsingIsCaseInsensitive() async {
        await assertIncomingPush(callIntentKey: "CALL_INTENT",
                                 callIntent: "STARTCALLDMVOICE",
                                 expectsVideo: false)
        await assertIncomingPush(callIntentKey: "INTENT",
                                 callIntent: "VIDEO",
                                 expectsVideo: true)
    }

    @Test
    func incomingPushWithMissingOrUnknownTypeFallsBackToAudio() async {
        await assertIncomingPush(callIntentKey: "callIntent",
                                 callIntent: "unknown",
                                 expectsVideo: false)
        await assertIncomingPush(expectsVideo: false)
    }

    @Test
    func ongoingDirectCallEndsWhenRemoteSendsHangupEvent() async throws {
        service.setClientProxy(clientProxy)

        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        configureLiveTimeline(for: room)
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }

        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: [ownUserID, remoteUserID]))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        let timelineProxy = try #require(room.timeline as? TimelineProxyMock)
        let timelineItemProvider = try #require(timelineProxy.timelineItemProvider as? TimelineItemProviderMock)
        let timelineUpdates = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>(([], .initial))
        let timelineSubscriptionProbe = PublisherSubscriptionProbe()
        timelineItemProvider.itemProxies = []
        timelineItemProvider.updatePublisher = timelineUpdates
            .handleEvents { _ in timelineSubscriptionProbe.recordSubscription() }
            .eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")

        await confirmation { confirmation in
            service.actions
                .sink { action in
                    if case .endCall(let observedRoomID) = action, observedRoomID == roomID {
                        confirmation()
                    }
                }
                .store(in: &cancellables)

            #expect(await waitForPublisherSubscription(timelineSubscriptionProbe))

            let hangupItem = makeCallTimelineItem(eventID: "$hangup",
                                                  sender: remoteUserID,
                                                  isOwn: false,
                                                  eventType: .callHangup,
                                                  timestamp: currentDate)
            timelineUpdates.send(([hangupItem], .initial))
            #expect(await waitForOngoingCallToEnd(roomID: roomID))
        }

        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func ongoingDirectCallEndsWhenRoomSummaryShowsTerminalCallEvent() async {
        let roomID = "!room:example.com"
        let ownUserID = "@test:user.net"
        let remoteUserID = "@alice:example.com"

        let roomSummaryProvider = RoomSummaryProviderMock()
        let roomSummaries = CurrentValueSubject<[RoomSummary], Never>([
            makeRoomSummary(id: roomID,
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: [ownUserID, remoteUserID],
                            lastCallEvent: .init(state: .answered, intent: .audio))
        ])
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 1)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = roomSummaries.asCurrentValuePublisher()
        clientProxy.roomSummaryProvider = roomSummaryProvider
        service.setClientProxy(clientProxy)

        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: ownUserID))
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }
        let timelineSubscriptionProbe = configureLiveTimeline(for: room)
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }
        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                             isDirect: true,
                                                                                             hasRoomCall: true,
                                                                                             participants: [ownUserID, remoteUserID]))
        room.infoPublisher = roomInfoSubject.asCurrentValuePublisher()

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")

        await confirmation { confirmation in
            service.actions
                .sink { action in
                    if case .endCall(let observedRoomID) = action, observedRoomID == roomID {
                        confirmation()
                    }
                }
                .store(in: &cancellables)

            #expect(await waitForPublisherSubscription(timelineSubscriptionProbe))

            roomSummaries.send([
                makeRoomSummary(id: roomID,
                                isDirect: true,
                                hasOngoingCall: true,
                                participants: [ownUserID, remoteUserID],
                                lastCallEvent: .init(state: .ended, intent: .audio))
            ])
            await Task.yield()
            #expect(service.ongoingCallRoomIDPublisher.value == roomID)

            roomInfoSubject.send(makeRoomInfo(id: roomID,
                                              isDirect: true,
                                              hasRoomCall: false,
                                              participants: []))
            #expect(await waitForOngoingCallToEnd(roomID: roomID))
        }

        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func whenVoIPPushTokenUpdatesAndClientProxyExists_voIPPusherIsRegistered() async throws {
        await service.declineIncomingCall()
        try? await Task.sleep(for: .milliseconds(200))
        service.setClientProxy(clientProxy)

        let pushCredentials = PKPushCredentialsMock(token: Data("1234".utf8))
        let expectedPushkey = Data("1234".utf8).base64EncodedString()
        var matchingConfiguration: PusherConfiguration?

        await confirmation { confirmation in
            clientProxy.setPusherWithClosure = { configuration in
                guard configuration.identifiers.pushkey == expectedPushkey else { return }
                matchingConfiguration = configuration
                confirmation()
            }

            service.pushRegistry(pushRegistry, didUpdate: pushCredentials, for: .voIP)
            try? await Task.sleep(for: .milliseconds(100))
        }

        let configuration = try #require(matchingConfiguration)
        #expect(configuration.identifiers.pushkey == expectedPushkey)
        #expect(configuration.identifiers.appId == appSettings.voIPPusherAppID)
        #expect(configuration.profileTag == appSettings.voIPPusherProfileTag)
    }

    @Test
    func whenClientProxyArrivesAfterVoIPPushToken_voIPPusherIsRegistered() async throws {
        await service.declineIncomingCall()
        try? await Task.sleep(for: .milliseconds(200))
        let pushCredentials = PKPushCredentialsMock(token: Data("abcd".utf8))
        let expectedPushkey = Data("abcd".utf8).base64EncodedString()
        var matchingConfiguration: PusherConfiguration?
        service.pushRegistry(pushRegistry, didUpdate: pushCredentials, for: .voIP)

        await confirmation { confirmation in
            clientProxy.setPusherWithClosure = { configuration in
                guard configuration.identifiers.pushkey == expectedPushkey else { return }
                matchingConfiguration = configuration
                confirmation()
            }

            service.setClientProxy(clientProxy)
            try? await Task.sleep(for: .milliseconds(100))
        }

        let configuration = try #require(matchingConfiguration)
        #expect(configuration.identifiers.pushkey == expectedPushkey)
        #expect(configuration.identifiers.appId == appSettings.voIPPusherAppID)
    }

    @Test
    func productionDispatchCapabilityReusesRegisteredVoIPToken() async throws {
        await service.declineIncomingCall()
        try? await Task.sleep(for: .milliseconds(200))
        let capabilityClient = SalemXProductionDispatchCapabilityClientSpy()
        service.configureProductionDispatchCapability(.init(client: capabilityClient,
                                                            appSessionGeneration: "opaque-generation"))
        clientProxy.setPusherWithClosure = { _ in }
        service.setClientProxy(clientProxy)

        await confirmation { confirmation in
            capabilityClient.registrationHandler = { request in
                guard request.token == Data("capability-token".utf8).base64EncodedString() else { return }
                confirmation()
            }
            service.pushRegistry(pushRegistry,
                                 didUpdate: PKPushCredentialsMock(token: Data("capability-token".utf8)),
                                 for: .voIP)
            try? await Task.sleep(for: .milliseconds(100))
        }

        let matchingRequests = capabilityClient.registrationRequests.filter {
            $0.token == Data("capability-token".utf8).base64EncodedString()
        }
        let request = try #require(matchingRequests.first)
        #expect(matchingRequests.count == 1)
        #expect(request.version == 1)
        #expect(request.protocolVersion == 1)
        #expect(request.intents == [.audio])
        #expect(request.receiverHandoff == .matrixRTCElementCall)
        #expect(request.appSessionGeneration == "opaque-generation")
        #expect(request.token == Data("capability-token".utf8).base64EncodedString())
        #expect(String(describing: request) == "SalemXProductionDispatchCapabilityRegistrationRequest(<redacted>)")
    }

    @Test
    func productionDispatchObservationRejectsHistoricalAndWrongScopeThenTracksRemoval() async throws {
        await service.declineIncomingCall()
        let roomID = "!outgoing:test"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: roomID,
                                                              name: "Room",
                                                              isDirect: true))
        room.initialRawMembershipState = [makeMatrixRTCMembershipTimelineItem(eventID: "$historical",
                                                                              roomID: roomID,
                                                                              membershipID: "HISTORICAL",
                                                                              createdAt: currentDate.addingTimeInterval(-60))]
        clientProxy.roomForIdentifierClosure = { identifier in
            identifier == roomID ? .joined(room) : nil
        }
        service.setClientProxy(clientProxy)

        let handle = try await service.beginOutgoingObservation(roomID: roomID,
                                                                appSessionGeneration: "opaque-generation",
                                                                attemptGeneration: 7).get()
        #expect(room.rawMembershipObservationStartCount == 1)

        let wrongGenerationHandle = SalemXStockElementCallObservationHandle(observationID: handle.observationID,
                                                                            appSessionGeneration: "stale-generation",
                                                                            attemptGeneration: handle.attemptGeneration)
        #expect(await service.awaitMembershipConfirmation(wrongGenerationHandle) == .failure(.invalidHandle))

        let confirmationTask = Task { @MainActor in
            await self.service.awaitMembershipConfirmation(handle)
        }
        #expect(room.receiveRawMembershipState([makeMatrixRTCMembershipTimelineItem(eventID: "$wrong-room",
                                                                                    roomID: "!wrong:test",
                                                                                    membershipID: "WRONG_ROOM",
                                                                                    createdAt: currentDate.addingTimeInterval(1))]))
        #expect(room.receiveRawMembershipState(room.initialRawMembershipState))
        #expect(room.receiveRawMembershipState([makeMatrixRTCMembershipTimelineItem(eventID: "$fresh",
                                                                                    roomID: roomID,
                                                                                    membershipID: "FRESH",
                                                                                    createdAt: currentDate.addingTimeInterval(1))]))

        let context = try await confirmationTask.value.get()
        #expect(context.callID == "ROOM")
        #expect(context.roomID == roomID)
        #expect(context.callHandle == "_@test:user.net_LOCAL_DEVICE_FRESH")

        let removalTask = Task { @MainActor in
            await self.service.awaitMembershipRemoval(handle)
        }
        #expect(room.receiveRawMembershipState([]))
        switch await removalTask.value {
        case .success:
            break
        case .failure(let error):
            Issue.record("Unexpected removal error: \(error)")
        }
        service.cancelObservation(handle)
    }

    @Test
    func productionDispatchObservationDoesNotWaitForAnInitialTimelineDiff() async throws {
        await service.declineIncomingCall()
        let roomID = "!outgoing-without-initial-diff:test"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: roomID,
                                                              name: "Room",
                                                              isDirect: true))
        room.emitsInitialRawMembershipState = false
        clientProxy.roomForIdentifierClosure = { identifier in
            identifier == roomID ? .joined(room) : nil
        }
        service.setClientProxy(clientProxy)

        let handle = try await service.beginOutgoingObservation(roomID: roomID,
                                                                appSessionGeneration: "opaque-generation",
                                                                attemptGeneration: 9).get()
        #expect(room.rawMembershipObservationStartCount == 1)

        let confirmationTask = Task { @MainActor in
            await self.service.awaitMembershipConfirmation(handle)
        }
        #expect(room.receiveRawMembershipState([makeMatrixRTCMembershipTimelineItem(eventID: "$historical",
                                                                                    roomID: roomID,
                                                                                    membershipID: "HISTORICAL",
                                                                                    createdAt: currentDate.addingTimeInterval(-60))]))
        #expect(room.receiveRawMembershipState([makeMatrixRTCMembershipTimelineItem(eventID: "$fresh",
                                                                                    roomID: roomID,
                                                                                    membershipID: "FRESH",
                                                                                    createdAt: currentDate.addingTimeInterval(1))]))

        let context = try await confirmationTask.value.get()
        #expect(context.callHandle == "_@test:user.net_LOCAL_DEVICE_FRESH")
        service.cancelObservation(handle)
    }

    @Test
    func productionDispatchObservationConfirmsMembershipSlightlyBeforeArmTime() async throws {
        await service.declineIncomingCall()
        let roomID = "!outgoing-clock-skew:test"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: roomID,
                                                              name: "Room",
                                                              isDirect: true))
        room.emitsInitialRawMembershipState = false
        clientProxy.roomForIdentifierClosure = { identifier in
            identifier == roomID ? .joined(room) : nil
        }
        service.setClientProxy(clientProxy)

        let handle = try await service.beginOutgoingObservation(roomID: roomID,
                                                                appSessionGeneration: "opaque-generation",
                                                                attemptGeneration: 10).get()
        let confirmationTask = Task { @MainActor in
            await self.service.awaitMembershipConfirmation(handle)
        }
        #expect(room.receiveRawMembershipState([makeMatrixRTCMembershipTimelineItem(eventID: "$skewed",
                                                                                    roomID: roomID,
                                                                                    membershipID: "SKEWED",
                                                                                    createdAt: currentDate.addingTimeInterval(-2))]))

        let context = try await confirmationTask.value.get()
        #expect(context.callHandle == "_@test:user.net_LOCAL_DEVICE_SKEWED")
        service.cancelObservation(handle)
    }

    @Test
    func productionDispatchObservationCancellationResumesExactlyOnce() async throws {
        await service.declineIncomingCall()
        let roomID = "!cancel:test"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: roomID,
                                                              name: "Room",
                                                              isDirect: true))
        clientProxy.roomForIdentifierClosure = { identifier in
            identifier == roomID ? .joined(room) : nil
        }
        service.setClientProxy(clientProxy)

        let handle = try await service.beginOutgoingObservation(roomID: roomID,
                                                                appSessionGeneration: "opaque-generation",
                                                                attemptGeneration: 8).get()
        let confirmationTask = Task { @MainActor in
            await self.service.awaitMembershipConfirmation(handle)
        }
        await Task.yield()
        service.cancelObservation(handle)
        service.cancelObservation(handle)

        #expect(await confirmationTask.value == .failure(.cancelled))
        #expect(room.receiveRawMembershipState([makeMatrixRTCMembershipTimelineItem(eventID: "$stale",
                                                                                    roomID: roomID,
                                                                                    membershipID: "STALE",
                                                                                    createdAt: currentDate.addingTimeInterval(1))]))
        #expect(await service.awaitMembershipConfirmation(handle) == .failure(.invalidHandle))
    }

    @Test
    func productionDispatchObservationTaskCancellationResumesMembershipWait() async throws {
        await service.declineIncomingCall()
        let roomID = "!cancel-task:test"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: roomID,
                                                              name: "Room",
                                                              isDirect: true))
        clientProxy.roomForIdentifierClosure = { identifier in
            identifier == roomID ? .joined(room) : nil
        }
        service.setClientProxy(clientProxy)

        let handle = try await service.beginOutgoingObservation(roomID: roomID,
                                                                appSessionGeneration: "opaque-generation",
                                                                attemptGeneration: 9).get()
        let confirmationTask = Task { @MainActor in
            await self.service.awaitMembershipConfirmation(handle)
        }
        await Task.yield()
        confirmationTask.cancel()

        #expect(await confirmationTask.value == .failure(.cancelled))
        #expect(await service.awaitMembershipConfirmation(handle) == .failure(.invalidHandle))
    }

    @Test
    func productionDispatchObservationConfirmsLocalParticipationFromRoomInfoWhenTimelineIsSilent() async throws {
        await service.declineIncomingCall()
        let roomID = "!outgoing-room-info:test"
        let ownUserID = "@test:user.net"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: roomID,
                                                              name: "Room",
                                                              isDirect: true,
                                                              hasOngoingCall: false))
        let infoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                         isDirect: true,
                                                                                         hasRoomCall: false,
                                                                                         participants: []))
        room.infoPublisher = infoSubject.asCurrentValuePublisher()
        room.emitsInitialRawMembershipState = false
        clientProxy.roomForIdentifierClosure = { identifier in
            identifier == roomID ? .joined(room) : nil
        }
        service.setClientProxy(clientProxy)

        let handle = try await service.beginOutgoingObservation(roomID: roomID,
                                                                appSessionGeneration: "opaque-generation",
                                                                attemptGeneration: 11).get()
        #expect(room.subscribeToRoomInfoUpdatesCalled)
        let confirmationTask = Task { @MainActor in
            await self.service.awaitMembershipConfirmation(handle)
        }
        infoSubject.send(makeRoomInfo(id: roomID,
                                      isDirect: true,
                                      hasRoomCall: true,
                                      participants: [ownUserID]))

        let context = try await confirmationTask.value.get()
        #expect(context.callID == "ROOM")
        #expect(context.roomID == roomID)
        #expect(context.callHandle == "_@test:user.net_LOCAL_DEVICE_m.call")

        let removalTask = Task { @MainActor in
            await self.service.awaitMembershipRemoval(handle)
        }
        infoSubject.send(makeRoomInfo(id: roomID,
                                      isDirect: true,
                                      hasRoomCall: false,
                                      participants: []))
        switch await removalTask.value {
        case .success:
            break
        case .failure(let error):
            Issue.record("Unexpected removal error: \(error)")
        }
        service.cancelObservation(handle)
    }

    @Test
    func productionDispatchObservationIgnoresHistoricalRoomInfoParticipation() async throws {
        await service.declineIncomingCall()
        let roomID = "!outgoing-room-info-historical:test"
        let ownUserID = "@test:user.net"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: roomID,
                                                              name: "Room",
                                                              isDirect: true,
                                                              hasOngoingCall: true))
        let infoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                         isDirect: true,
                                                                                         hasRoomCall: true,
                                                                                         participants: [ownUserID]))
        room.infoPublisher = infoSubject.asCurrentValuePublisher()
        room.emitsInitialRawMembershipState = false
        clientProxy.roomForIdentifierClosure = { identifier in
            identifier == roomID ? .joined(room) : nil
        }
        service.setClientProxy(clientProxy)

        let handle = try await service.beginOutgoingObservation(roomID: roomID,
                                                                appSessionGeneration: "opaque-generation",
                                                                attemptGeneration: 12).get()
        let confirmationTask = Task { @MainActor in
            await self.service.awaitMembershipConfirmation(handle)
        }
        infoSubject.send(makeRoomInfo(id: roomID,
                                      isDirect: true,
                                      hasRoomCall: true,
                                      participants: [ownUserID]))
        await Task.yield()
        #expect(room.receiveRawMembershipState([makeMatrixRTCMembershipTimelineItem(eventID: "$fresh",
                                                                                    roomID: roomID,
                                                                                    membershipID: "FRESH",
                                                                                    createdAt: currentDate.addingTimeInterval(1))]))

        let context = try await confirmationTask.value.get()
        #expect(context.callHandle == "_@test:user.net_LOCAL_DEVICE_FRESH")
        service.cancelObservation(handle)
    }

    @Test
    func productionDispatchObservationConfirmsMembershipAfterTimeoutWhenTimelineIsSilent() async throws {
        await service.declineIncomingCall()
        let roomID = "!outgoing-timeout:test"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: roomID,
                                                              name: "Room",
                                                              isDirect: true))
        room.emitsInitialRawMembershipState = false
        clientProxy.roomForIdentifierClosure = { identifier in
            identifier == roomID ? .joined(room) : nil
        }
        service.setClientProxy(clientProxy)

        let handle = try await service.beginOutgoingObservation(roomID: roomID,
                                                                appSessionGeneration: "opaque-generation",
                                                                attemptGeneration: 13).get()
        let confirmationTask = Task { @MainActor in
            await self.service.awaitMembershipConfirmation(handle)
        }
        await Task.yield()
        await testClock.advance(by: .seconds(5))

        let context = try await confirmationTask.value.get()
        #expect(context.roomID == roomID)
        #expect(context.callHandle == "_@test:user.net_LOCAL_DEVICE_m.call")
        service.cancelObservation(handle)
    }

    private func makeRoomInfo(id: String,
                              isDirect: Bool,
                              hasRoomCall: Bool,
                              participants: [String]) -> RoomInfoProxyProtocol {
        let info = RoomInfoProxyMock()
        info.id = id
        info.isEncrypted = true
        info.isDirect = isDirect
        info.isSpace = false
        info.isFavourite = false
        info.membership = .joined
        info.activeMembersCount = 2
        info.invitedMembersCount = 0
        info.joinedMembersCount = 2
        info.highlightCount = 0
        info.notificationCount = 0
        info.hasRoomCall = hasRoomCall
        info.activeRoomCallParticipants = participants
        info.isMarkedUnread = false
        info.unreadMessagesCount = 0
        info.unreadNotificationsCount = 0
        info.unreadMentionsCount = 0
        info.pinnedEventIDs = []
        info.historyVisibility = .shared
        return info
    }

    private func makeOngoingCallRoom(id: String,
                                     ownUserID: String,
                                     remoteUserID: String) -> (JoinedRoomProxyMock, RoomInfoSubscriptionHarness) {
        let memberships = [
            makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership",
                                                roomID: id,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: true),
            makeMatrixRTCMembershipTimelineItem(eventID: "$remote-membership",
                                                roomID: id,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: true)
        ]
        return makeOngoingCallRoom(id: id,
                                   ownUserID: ownUserID,
                                   initialHasRoomCall: true,
                                   initialParticipants: [ownUserID, remoteUserID],
                                   initialTimelineItems: memberships)
    }

    private func makeOngoingCallRoom(id: String,
                                     ownUserID: String,
                                     initialHasRoomCall: Bool,
                                     initialParticipants: [String],
                                     initialTimelineItems: [TimelineItemProxy] = []) -> (JoinedRoomProxyMock, RoomInfoSubscriptionHarness) {
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: id,
                                                              name: "Room",
                                                              isDirect: true,
                                                              hasOngoingCall: true,
                                                              ownUserID: ownUserID))
        configureLiveTimeline(for: room)
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }

        let subscription = RoomInfoSubscriptionHarness(initialValue: makeRoomInfo(id: id,
                                                                                  isDirect: true,
                                                                                  hasRoomCall: initialHasRoomCall,
                                                                                  participants: initialParticipants))
        subscription.install(on: room, initialTimelineItems: initialTimelineItems)
        return (room, subscription)
    }

    private func waitForRoomInfoSubscription(on room: JoinedRoomProxyMock?) async -> Bool {
        guard let room else {
            return false
        }

        for _ in 0..<30 {
            if room.subscribeToRoomInfoUpdatesCallsCount == 1 {
                return true
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return false
    }

    private func deliverIncomingPush(_ payload: PKPushPayload) async {
        await confirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
    }

    private func waitForIncomingLifecycleObservation(on room: JoinedRoomProxyMock) async -> Bool {
        for _ in 0..<30 {
            if room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerCalled {
                return true
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return false
    }

    private func waitForPublisherSubscription(_ probe: PublisherSubscriptionProbe) async -> Bool {
        for _ in 0..<30 {
            if probe.hasSubscription {
                return true
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return false
    }

    private func waitForOngoingCallToEnd(roomID: String) async -> Bool {
        for _ in 0..<30 {
            if service.ongoingCallRoomIDPublisher.value != roomID {
                return true
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return false
    }

    private func makeCallTimelineItem(eventID: String,
                                      sender: String,
                                      isOwn: Bool,
                                      eventType: MessageLikeEventType,
                                      timestamp: Date? = nil) -> TimelineItemProxy {
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        lazyProvider.debugInfoReturnValue = .init(model: "call event",
                                                  originalJson: nil,
                                                  latestEditJson: nil)
        let content = TimelineItemContent.msgLike(content: .init(kind: .other(eventType: eventType),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        var item = EventTimelineItem(configuration: .init(eventID: eventID,
                                                          sender: sender,
                                                          isOwn: isOwn,
                                                          content: content,
                                                          lazyProvider: lazyProvider))
        if let timestamp {
            item.timestamp = UInt64(timestamp.timeIntervalSince1970 * 1000)
        }
        let proxy = EventTimelineItemProxy(item: item, uniqueID: .init(UUID().uuidString))
        return .event(proxy)
    }

    @discardableResult
    private func configureLiveTimeline(for room: JoinedRoomProxyMock) -> PublisherSubscriptionProbe {
        let subscriptionProbe = PublisherSubscriptionProbe()
        guard let timelineProxy = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock else {
            return subscriptionProbe
        }

        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .failure(.missingTransactionID)
        let timelineUpdates = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>(([], .initial))
        timelineItemProvider.itemProxies = []
        timelineItemProvider.updatePublisher = timelineUpdates
            .handleEvents { _ in subscriptionProbe.recordSubscription() }
            .eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live
        return subscriptionProbe
    }

    private func waitForEndedCall(reason: CXCallEndedReason) async -> Bool {
        for _ in 0..<10 {
            if callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == reason {
                return true
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return false
    }

    private func makeRoomSummary(id: String,
                                 isDirect: Bool,
                                 hasOngoingCall: Bool,
                                 participants: [String],
                                 lastCallEvent: RoomCallEvent? = nil) -> RoomSummary {
        RoomSummary(room: RoomSDKMock(),
                    id: id,
                    joinRequestType: nil,
                    name: "Room",
                    isDirect: isDirect,
                    isSpace: false,
                    avatarURL: nil,
                    heroes: [],
                    activeMembersCount: 2,
                    lastCallEvent: lastCallEvent,
                    lastMessage: nil,
                    lastMessageDate: .mock,
                    lastMessageState: nil,
                    unreadMessagesCount: 0,
                    unreadMentionsCount: 0,
                    unreadNotificationsCount: 0,
                    notificationMode: nil,
                    canonicalAlias: nil,
                    alternativeAliases: [],
                    hasOngoingCall: hasOngoingCall,
                    isMarkedUnread: false,
                    isFavourite: false,
                    isTombstoned: false,
                    activeRoomCallParticipants: participants)
    }

    private func assertIncomingPush(callIntentKey: String? = nil,
                                    callIntent: String? = nil,
                                    expectsVideo: Bool) async {
        let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        if let callIntentKey, let callIntent {
            pushPayload.settingCallIntent(callIntentKey, callIntent)
        }

        let callProvider = CXProviderMock(.init())
        let dateProvider: () -> Date = { self.currentDate }
        let service = ElementCallService(appSettings: appSettings,
                                         callProvider: callProvider,
                                         timeProvider: TimeProvider(clock: testClock, now: dateProvider))

        await confirmation { confirmation in
            callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, update, completion in
                #expect(update.hasVideo == expectsVideo)
                completion(nil)
                confirmation()
            }

            service.pushRegistry(pushRegistry,
                                 didReceiveIncomingPushWith: pushPayload,
                                 for: .voIP) { }
        }
    }

    private func productionDispatchPayload(dispatchID: String = "11111111-1111-4111-8111-111111111111",
                                           includingLegacyCallBootstrap: Bool = false) -> PKPushPayloadMock {
        let payload = PKPushPayloadMock()
        if includingLegacyCallBootstrap {
            _ = payload.updatingExpiration(currentDate, lifetime: 30)
        } else {
            payload.dict.removeAll()
        }
        payload.dict[SalemXProductionDispatchNotificationKey.envelope.rawValue] = [
            SalemXProductionDispatchNotificationKey.protocolVersion.rawValue: 1,
            SalemXProductionDispatchNotificationKey.dispatchID.rawValue: dispatchID,
            SalemXProductionDispatchNotificationKey.receiverReference.rawValue: "receiver-reference"
        ]
        return payload
    }

    private func productionDispatchConsumeResponse(direction: String = "incoming",
                                                   expiresAt: Date? = nil) -> SalemXProductionDispatchReceiverConsumeResponse {
        .init(dispatchProtocolVersion: 1,
              state: .consumed,
              version: 1,
              callID: "opaque-call",
              roomID: "!room:example.com",
              peerUserID: "@peer:example.com",
              direction: direction,
              intent: .audio,
              expiresAtMS: Int64((expiresAt ?? currentDate.addingTimeInterval(30)).timeIntervalSince1970 * 1000))
    }
}

@MainActor
final class ElementCallServiceRepeatIncomingFastPathTests {
    private let appSettings = AppSettings()
    private var callProvider: CXProviderMock!
    private var currentDate: Date!
    private var testClock: TestClock<Duration>!
    private var service: ElementCallService!
    private let clientProxy = ClientProxyMock(.init(userID: "redacted-own"))

    init() {
        AppSettings.resetAllSettings()
        callProvider = CXProviderMock(.init())
        currentDate = Date()
        testClock = TestClock()
        let dateProvider: () -> Date = {
            self.currentDate
        }
        service = ElementCallService(appSettings: appSettings,
                                     callProvider: callProvider,
                                     timeProvider: TimeProvider(clock: testClock, now: dateProvider))
    }

    deinit {
        callProvider = nil
        currentDate = nil
        testClock = nil
    }

    @Test
    func secureAnswerBridgeSuppressesRoomSummaryIncomingFallback() async {
        service = ElementCallService(appSettings: appSettings,
                                     callProvider: callProvider,
                                     timeProvider: TimeProvider(clock: testClock) { self.currentDate },
                                     salemXAnswerBridgeConfiguration: .init(embeddedMatrixRTCAnswerBridgeEnabled: true))
        let roomSummaryProvider = RoomSummaryProviderMock()
        let roomSummaries = CurrentValueSubject<[RoomSummary], Never>([])
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 1)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = roomSummaries.asCurrentValuePublisher()
        clientProxy.roomSummaryProvider = roomSummaryProvider
        clientProxy.staticRoomSummaryProvider = roomSummaryProvider
        service.setClientProxy(clientProxy)

        roomSummaries.send([
            makeRoomSummary(id: "redacted-room",
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: ["redacted-remote"],
                            lastCallEvent: .init(state: .incoming, intent: .audio))
        ])

        #expect(await waitForIncomingCallReports(count: 1) == false)
    }

    @Test
    func matrixRTCRoomListPresenceReportsIncomingCallKit() async {
        let roomSummaries = configureRoomSummaryProvider()
        service.setClientProxy(clientProxy)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        roomSummaries.send([
            makeRoomSummary(id: "redacted-room",
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: ["redacted-remote"])
        ])

        #expect(await waitForIncomingCallReports(count: 1))
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update.hasVideo == false)
    }

    @Test
    func localMatrixRTCPresenceDoesNotReportIncomingCallKit() async {
        let roomSummaries = configureRoomSummaryProvider()
        service.setClientProxy(clientProxy)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        roomSummaries.send([
            makeRoomSummary(id: "redacted-room",
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: [clientProxy.userID])
        ])

        #expect(await waitForIncomingCallReports(count: 1) == false)
        #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
    }

    @Test
    func terminatedCallSuppressionStillBlocksStaleIncomingFallback() async {
        let roomID = "redacted-room"
        let roomSummaryProvider = RoomSummaryProviderMock()
        let roomSummaries = CurrentValueSubject<[RoomSummary], Never>([])
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 1)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = roomSummaries.asCurrentValuePublisher()
        clientProxy.roomSummaryProvider = roomSummaryProvider
        clientProxy.staticRoomSummaryProvider = roomSummaryProvider
        service.setClientProxy(clientProxy)

        await service.requestCallTermination(roomID: roomID)

        roomSummaries.send([
            makeRoomSummary(id: roomID,
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: [],
                            lastCallEvent: nil)
        ])

        #expect(await waitForIncomingCallReports(count: 1) == false)
    }

    @Test
    func productionLivePublisherEventWithClosedRoomReportsCallKitOnce() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        let listener = configureLiveNotificationListener()
        service.setClientProxy(clientProxy)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        let notification = makeLiveRTCNotification(eventID: "redacted-delivery-a",
                                                   senderID: remoteUserID,
                                                   timestamp: currentDate.addingTimeInterval(1),
                                                   expirationDate: currentDate.addingTimeInterval(60))
        listener.onNotification(notification: notification, roomId: roomID)

        #expect(await waitForIncomingCallReports(count: 1))
        listener.onNotification(notification: notification, roomId: roomID)
        #expect(await waitForIncomingCallReports(count: 2) == false)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update.hasVideo == false)
    }

    @Test
    func newIdentityInSameRoomReportsNewCallKit() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        configureJoinedRoomMock(roomID: roomID, activeParticipants: [remoteUserID])
        service.setClientProxy(clientProxy)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        handleSessionGlobalCall(roomID: roomID,
                                callID: "redacted-session-a",
                                deduplicationID: "redacted-current-call-a")
        #expect(await waitForIncomingCallReports(count: 1))

        await service.declineIncomingCall()

        handleSessionGlobalCall(roomID: roomID,
                                callID: "redacted-session-b",
                                deduplicationID: "redacted-delivery-b")

        #expect(await waitForIncomingCallReports(count: 2))
        handleSessionGlobalCall(roomID: roomID,
                                callID: "redacted-session-b",
                                deduplicationID: "redacted-delivery-b")
        #expect(await waitForIncomingCallReports(count: 3) == false)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 2)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update.hasVideo == false)
    }

    @Test
    func foregroundCurrentRoomTerminalEventRemainsSuppressed() async {
        let roomID = "redacted-room"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: [])
        service.setClientProxy(clientProxy)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        handleSessionGlobalCall(roomID: roomID,
                                state: .ended,
                                deduplicationID: "redacted-terminal-call")

        #expect(await waitForIncomingCallReports(count: 1) == false)
    }

    @Test
    func openingRoomAfterReportedCallDoesNotDuplicateCallKit() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID,
                                           activeParticipants: [remoteUserID],
                                           timelineItems: [makeHistoricalCallTimelineItem(eventID: "redacted-stable-event",
                                                                                          uniqueID: "redacted-room-timeline",
                                                                                          callID: "redacted-session-a")])
        service.setClientProxy(clientProxy)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        handleSessionGlobalCall(roomID: roomID,
                                callID: "redacted-session-a",
                                deduplicationID: "redacted-delivery-a")
        #expect(await waitForIncomingCallReports(count: 1))

        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        #expect(await waitForIncomingCallReports(count: 2) == false)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
    }

    @Test
    func foregroundCurrentRoomCallEventBypassesTimeBasedSuppression() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: [remoteUserID])
        service.setClientProxy(clientProxy)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        await service.requestCallTermination(roomID: roomID)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        handleSessionGlobalCall(roomID: roomID, deduplicationID: "redacted-current-call-a")

        #expect(await waitForIncomingCallReports(count: 1))
    }

    @Test
    func terminalIdentityIgnoresDuplicateMatrixRTCNotification() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: [remoteUserID])
        service.setClientProxy(clientProxy)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        handleSessionGlobalCall(roomID: roomID,
                                callID: "redacted-session-a",
                                deduplicationID: "redacted-current-call-a")
        #expect(await waitForIncomingCallReports(count: 1))

        await service.declineIncomingCall()

        service.stopObservingForegroundRoom(roomID: roomID)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        handleSessionGlobalCall(roomID: roomID,
                                callID: "redacted-session-a",
                                deduplicationID: "redacted-current-call-a")

        #expect(await waitForIncomingCallReports(count: 2) == false)
    }

    @Test
    func roomReopenDoesNotDuplicateProductionLiveNotification() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        let listener = configureLiveNotificationListener()
        let room = configureJoinedRoomMock(roomID: roomID,
                                           activeParticipants: [remoteUserID],
                                           timelineItems: [makeHistoricalCallTimelineItem(eventID: "redacted-stable-event",
                                                                                          uniqueID: "redacted-first-timeline",
                                                                                          callID: "redacted-session-a")])
        service.setClientProxy(clientProxy)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        let notification = makeLiveRTCNotification(eventID: "redacted-delivery-a",
                                                   senderID: remoteUserID,
                                                   timestamp: currentDate.addingTimeInterval(1),
                                                   expirationDate: currentDate.addingTimeInterval(60))
        listener.onNotification(notification: notification, roomId: roomID)
        #expect(await waitForIncomingCallReports(count: 1))

        await service.declineIncomingCall()
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)

        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")
        service.stopObservingForegroundRoom(roomID: roomID)

        let reopenedRoom = configureJoinedRoomMock(roomID: roomID,
                                                   activeParticipants: [remoteUserID],
                                                   timelineItems: [makeHistoricalCallTimelineItem(eventID: "redacted-stable-event",
                                                                                                  uniqueID: "redacted-reopened-timeline",
                                                                                                  callID: "redacted-session-a")])
        service.observeForegroundRoom(roomProxy: reopenedRoom, roomDisplayName: "Room")
        listener.onNotification(notification: notification, roomId: roomID)

        #expect(await waitForIncomingCallReports(count: 2) == false)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)
    }

    @Test
    func staticAndHistoricalEventsDoNotReportCallKit() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        let roomSummaries = configureRoomSummaryProvider()
        roomSummaries.send([
            makeRoomSummary(id: roomID,
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: [remoteUserID],
                            lastCallEvent: .init(state: .incoming,
                                                 intent: .audio,
                                                 callID: "redacted-historical-session"),
                            lastMessageDate: currentDate.addingTimeInterval(-60))
        ])
        let listener = configureLiveNotificationListener()

        service.setClientProxy(clientProxy)
        roomSummaries.send([
            makeRoomSummary(id: roomID,
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: [remoteUserID],
                            lastCallEvent: .init(state: .incoming,
                                                 intent: .audio,
                                                 callID: "redacted-static-replay"),
                            lastMessageDate: currentDate.addingTimeInterval(1))
        ])
        listener.onNotification(notification: makeLiveRTCNotification(eventID: "redacted-historical-event",
                                                                      senderID: remoteUserID,
                                                                      timestamp: currentDate.addingTimeInterval(-1),
                                                                      expirationDate: currentDate.addingTimeInterval(60)),
                                roomId: roomID)

        #expect(await waitForIncomingCallReports(count: 1) == false)
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 0)
    }

    @Test
    func clientSessionReplacementRejectsStaleLiveCallback() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        let staleClient = ClientProxyMock(.init(userID: "redacted-old-user"))
        let currentClient = ClientProxyMock(.init(userID: "redacted-current-user"))
        configureRoomSummaryProvider(for: staleClient)
        configureRoomSummaryProvider(for: currentClient)
        let staleListener = configureLiveNotificationListener(for: staleClient)
        let currentListener = configureLiveNotificationListener(for: currentClient)
        service.setClientProxy(staleClient)
        service.setClientProxy(currentClient)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        staleListener.onNotification(notification: makeLiveRTCNotification(eventID: "redacted-stale-delivery",
                                                                           senderID: remoteUserID,
                                                                           timestamp: currentDate.addingTimeInterval(1),
                                                                           expirationDate: currentDate.addingTimeInterval(60)),
                                     roomId: roomID)
        #expect(await waitForIncomingCallReports(count: 1) == false)

        currentListener.onNotification(notification: makeLiveRTCNotification(eventID: "redacted-current-delivery",
                                                                             senderID: remoteUserID,
                                                                             timestamp: currentDate.addingTimeInterval(1),
                                                                             expirationDate: currentDate.addingTimeInterval(60)),
                                       roomId: roomID)
        #expect(await waitForIncomingCallReports(count: 1))
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount == 1)
    }

    private func waitForIncomingCallReports(count: Int) async -> Bool {
        for _ in 0..<10 {
            if callProvider.reportNewIncomingCallWithUpdateCompletionCallsCount >= count {
                return true
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return false
    }

    private func handleSessionGlobalCall(roomID: String,
                                         state: RoomCallEvent.State = .incoming,
                                         callID: String? = nil,
                                         deduplicationID: String) {
        service.handleSessionGlobalIncomingCallEvent(.init(roomID: roomID,
                                                           roomDisplayName: "Room",
                                                           isDirect: true,
                                                           isOwnEvent: false,
                                                           callEvent: .init(state: state,
                                                                            intent: .audio,
                                                                            callID: callID),
                                                           deduplicationID: deduplicationID))
    }

    @discardableResult
    private func configureRoomSummaryProvider(for client: ClientProxyMock? = nil) -> CurrentValueSubject<[RoomSummary], Never> {
        let client = client ?? clientProxy
        let roomSummaryProvider = RoomSummaryProviderMock()
        let roomSummaries = CurrentValueSubject<[RoomSummary], Never>([])
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 1)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = roomSummaries.asCurrentValuePublisher()
        client.roomSummaryProvider = roomSummaryProvider
        client.staticRoomSummaryProvider = roomSummaryProvider
        return roomSummaries
    }

    private func configureLiveNotificationListener(for client: ClientProxyMock? = nil) -> ClientSyncNotificationListener {
        let client = client ?? clientProxy
        let actionsSubject = PassthroughSubject<ClientProxyAction, Never>()
        client.actionsPublisher = actionsSubject.eraseToAnyPublisher()
        return ClientSyncNotificationListener(actionsSubject: actionsSubject)
    }

    private func makeLiveRTCNotification(eventID: String,
                                         senderID: String,
                                         timestamp: Date,
                                         expirationDate: Date) -> NotificationItem {
        let event = TimelineEventSDKMock()
        event.contentReturnValue = .messageLike(content: .rtcNotification(notificationType: .ring,
                                                                          expirationTs: timestampInMilliseconds(expirationDate),
                                                                          callIntent: .audio))
        event.eventIdReturnValue = eventID
        event.senderIdReturnValue = senderID
        event.timestampReturnValue = timestampInMilliseconds(timestamp)

        return .init(event: .timeline(event: event),
                     rawEvent: "{}",
                     senderInfo: .init(displayName: nil, avatarUrl: nil, isNameAmbiguous: false),
                     roomInfo: .init(displayName: "Room",
                                     avatarUrl: nil,
                                     canonicalAlias: nil,
                                     topic: nil,
                                     joinRule: nil,
                                     joinedMembersCount: 2,
                                     isEncrypted: true,
                                     isDirect: true,
                                     isSpace: false),
                     isNoisy: true,
                     hasMention: false,
                     threadId: nil,
                     actions: nil)
    }

    private func timestampInMilliseconds(_ date: Date) -> UInt64 {
        UInt64(date.timeIntervalSince1970 * 1000)
    }

    @discardableResult
    private func configureJoinedRoomMock(roomID: String,
                                         activeParticipants: [String],
                                         timelineItems: [TimelineItemProxy] = []) -> JoinedRoomProxyMock {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: clientProxy.userID))
        room.infoPublisher = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                            activeParticipants: activeParticipants)).asCurrentValuePublisher()
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .success(TaskHandleSDKMock())
        }
        room.declineCallNotificationIDClosure = { _ in .success(()) }

        if let timelineProxy = room.timeline as? TimelineProxyMock,
           let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock {
            timelineItemProvider.itemProxies = timelineItems
            timelineItemProvider.updatePublisher = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>((timelineItems, .initial)).eraseToAnyPublisher()
            timelineItemProvider.paginationState = .initial
            timelineItemProvider.kind = .live
        }

        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        return room
    }

    private func makeHistoricalCallTimelineItem(eventID: String,
                                                uniqueID: String,
                                                callID: String? = nil) -> TimelineItemProxy {
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        let originalJSON = callID.map { #"{"content":{"call_id":"\#($0)"}}"# }
        lazyProvider.debugInfoReturnValue = .init(model: "call event",
                                                  originalJson: originalJSON,
                                                  latestEditJson: nil)
        let item = EventTimelineItem(configuration: .init(eventID: eventID,
                                                          sender: "redacted-remote",
                                                          isOwn: false,
                                                          content: .callInvite,
                                                          lazyProvider: lazyProvider))
        return .event(.init(item: item, uniqueID: .init(uniqueID)))
    }

    private func makeRoomInfo(id: String, activeParticipants: [String]) -> RoomInfoProxyProtocol {
        let info = RoomInfoProxyMock()
        info.id = id
        info.isEncrypted = true
        info.isDirect = true
        info.isSpace = false
        info.isFavourite = false
        info.membership = .joined
        info.activeMembersCount = 2
        info.invitedMembersCount = 0
        info.joinedMembersCount = 2
        info.highlightCount = 0
        info.notificationCount = 0
        info.hasRoomCall = true
        info.activeRoomCallParticipants = activeParticipants
        info.isMarkedUnread = false
        info.unreadMessagesCount = 0
        info.unreadNotificationsCount = 0
        info.unreadMentionsCount = 0
        info.pinnedEventIDs = []
        info.historyVisibility = .shared
        return info
    }

    private func makeRoomSummary(id: String,
                                 isDirect: Bool,
                                 hasOngoingCall: Bool,
                                 participants: [String],
                                 lastCallEvent: RoomCallEvent? = nil,
                                 lastMessageDate: Date = .mock) -> RoomSummary {
        RoomSummary(room: RoomSDKMock(),
                    id: id,
                    joinRequestType: nil,
                    name: "Room",
                    isDirect: isDirect,
                    isSpace: false,
                    avatarURL: nil,
                    heroes: [],
                    activeMembersCount: 2,
                    lastCallEvent: lastCallEvent,
                    lastMessage: nil,
                    lastMessageDate: lastMessageDate,
                    lastMessageState: nil,
                    unreadMessagesCount: 0,
                    unreadMentionsCount: 0,
                    unreadNotificationsCount: 0,
                    notificationMode: nil,
                    canonicalAlias: nil,
                    alternativeAliases: [],
                    hasOngoingCall: hasOngoingCall,
                    isMarkedUnread: false,
                    isFavourite: false,
                    isTombstoned: false,
                    activeRoomCallParticipants: participants)
    }
}

@MainActor
func makeMatrixRTCMembershipTimelineItem(eventID: String,
                                         roomID: String,
                                         userID: String = "@test:user.net",
                                         deviceID: String = "LOCAL_DEVICE",
                                         membershipID: String = "LOCAL_PARTY",
                                         isActive: Bool = true,
                                         createdAt: Date = Date(),
                                         expiresInMilliseconds: UInt64 = 3_600_000,
                                         eventType: String = "org.matrix.msc3401.call.member",
                                         callID: String? = nil,
                                         scope: String = "m.room") -> TimelineItemProxy {
    let stateKey = "_\(userID)_\(deviceID)_\(membershipID)"
    let createdTimestamp = UInt64(createdAt.timeIntervalSince1970 * 1000)
    let isRTCEvent = eventType == "org.matrix.msc4143.rtc.member" || eventType == "m.rtc.member"
    let content = if isRTCEvent, isActive {
        """
        {
          "slot_id": "m.call#\(callID ?? "ROOM")",
          "application": {
            "type": "m.call"
          },
          "member": {
            "user_id": "\(userID)",
            "device_id": "\(deviceID)",
            "id": "\(membershipID)"
          },
          "rtc_transports": [
            {
              "type": "livekit"
            }
          ],
          "versions": ["v0"],
          "msc4354_sticky_key": "\(stateKey)"
        }
        """
    } else if isRTCEvent {
        """
        {
          "msc4354_sticky_key": "\(stateKey)"
        }
        """
    } else if isActive {
        """
        {
          "application": "m.call",
          "call_id": "\(callID ?? "")",
          "scope": "\(scope)",
          "device_id": "\(deviceID)",
          "membershipID": "\(membershipID)",
          "expires": \(expiresInMilliseconds),
          "created_ts": \(createdTimestamp),
          "foci_preferred": [],
          "focus_active": {
            "type": "livekit",
            "focus_selection": "oldest_membership"
          }
        }
        """
    } else {
        "{}"
    }
    let rawEvent = """
    {
      "event_id": "\(eventID)",
      "room_id": "\(roomID)",
      "sender": "\(userID)",
      "origin_server_ts": \(createdTimestamp),
      "type": "\(eventType)",
      "state_key": "\(stateKey)",
      "content": \(content)
    }
    """
    let lazyProvider = LazyTimelineItemProviderSDKMock()
    lazyProvider.debugInfoReturnValue = .init(model: "MatrixRTC membership event",
                                              originalJson: rawEvent,
                                              latestEditJson: nil)
    let item = EventTimelineItem(configuration: .init(eventID: eventID,
                                                      sender: userID,
                                                      isOwn: deviceID == "LOCAL_DEVICE",
                                                      content: .failedToParseState(eventType: eventType,
                                                                                   stateKey: stateKey,
                                                                                   error: "Unsupported state event"),
                                                      lazyProvider: lazyProvider))
    return .event(.init(item: item, uniqueID: .init(UUID().uuidString)))
}

@MainActor
func makeMatrixRTCMembershipSDKTimelineItem(eventID: String,
                                            roomID: String,
                                            userID: String,
                                            deviceID: String,
                                            membershipID: String,
                                            isActive: Bool = true,
                                            createdAt: Date = Date(),
                                            expiresInMilliseconds: UInt64 = 3_600_000) -> TimelineItem {
    let stateKey = "_\(userID)_\(deviceID)_\(membershipID)"
    let createdTimestamp = UInt64(createdAt.timeIntervalSince1970 * 1000)
    let content = if isActive {
        """
        {
          "application": "m.call",
          "call_id": "",
          "scope": "m.room",
          "device_id": "\(deviceID)",
          "membershipID": "\(membershipID)",
          "expires": \(expiresInMilliseconds),
          "created_ts": \(createdTimestamp),
          "foci_preferred": [],
          "focus_active": {
            "type": "livekit",
            "focus_selection": "oldest_membership"
          }
        }
        """
    } else {
        "{}"
    }
    let rawEvent = """
    {
      "event_id": "\(eventID)",
      "room_id": "\(roomID)",
      "sender": "\(userID)",
      "origin_server_ts": \(createdTimestamp),
      "type": "org.matrix.msc3401.call.member",
      "state_key": "\(stateKey)",
      "content": \(content)
    }
    """
    let lazyProvider = LazyTimelineItemProviderSDKMock()
    lazyProvider.debugInfoReturnValue = .init(model: "MatrixRTC membership event",
                                              originalJson: rawEvent,
                                              latestEditJson: nil)
    let eventItem = EventTimelineItem(configuration: .init(eventID: eventID,
                                                           sender: userID,
                                                           isOwn: deviceID == "LOCAL_DEVICE",
                                                           content: .failedToParseState(eventType: "org.matrix.msc3401.call.member",
                                                                                        stateKey: stateKey,
                                                                                        error: "Unsupported state event"),
                                                           lazyProvider: lazyProvider))
    let item = TimelineItemSDKMock()
    item.asEventReturnValue = eventItem
    item.uniqueIdReturnValue = .init(id: UUID().uuidString)
    return item
}

func makeMatrixRTCRoomInfo(roomID: String, participants: [String]) -> RoomInfo {
    .init(id: roomID,
          encryptionState: .encrypted,
          creators: nil,
          displayName: "Room",
          rawName: nil,
          topic: nil,
          avatarUrl: nil,
          isDirect: true,
          isPublic: false,
          isSpace: false,
          successorRoom: nil,
          isFavourite: false,
          isLowPriority: false,
          canonicalAlias: nil,
          alternativeAliases: [],
          membership: .joined,
          inviter: nil,
          heroes: [],
          activeMembersCount: 2,
          invitedMembersCount: 0,
          joinedMembersCount: 2,
          serviceMembers: [],
          highlightCount: 0,
          notificationCount: 0,
          cachedUserDefinedNotificationMode: nil,
          hasRoomCall: !participants.isEmpty,
          activeRoomCallParticipants: participants,
          isMarkedUnread: false,
          numUnreadMessages: 0,
          numUnreadNotifications: 0,
          numUnreadMentions: 0,
          pinnedEventIds: [],
          joinRule: nil,
          historyVisibility: .shared,
          powerLevels: nil,
          roomVersion: nil,
          privilegedCreatorsRole: false)
}

private final class MatrixRTCCallMembershipStateObservationMock: MatrixRTCCallMembershipStateObservationProtocol {
    private var cancellation: (() -> Void)?

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    deinit {
        cancel()
    }

    func cancel() {
        cancellation?()
        cancellation = nil
    }
}

private final class PublisherSubscriptionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var subscriptionCount = 0

    var hasSubscription: Bool {
        lock.lock()
        defer { lock.unlock() }
        return subscriptionCount > 0
    }

    func recordSubscription() {
        lock.lock()
        subscriptionCount += 1
        lock.unlock()
    }
}

final class MatrixRTCCallMembershipRoomProxyMock: JoinedRoomProxyMock, MatrixRTCCallMembershipStateObserving, @unchecked Sendable {
    var initialRawMembershipState = [TimelineItemProxy]()
    var emitsInitialRawMembershipState = true
    private(set) var rawMembershipObservationStartCount = 0
    private var rawMembershipListener: (([TimelineItemProxy]) -> Void)?
    private var rawMembershipObservationID: UUID?

    func observeMatrixRTCCallMembershipState(_ listener: @escaping ([TimelineItemProxy]) -> Void) async
        -> (any MatrixRTCCallMembershipStateObservationProtocol)? {
        rawMembershipObservationStartCount += 1
        let observationID = UUID()
        rawMembershipObservationID = observationID
        rawMembershipListener = listener
        if emitsInitialRawMembershipState {
            listener(initialRawMembershipState)
        }

        return MatrixRTCCallMembershipStateObservationMock { [weak self] in
            guard self?.rawMembershipObservationID == observationID else { return }
            self?.rawMembershipObservationID = nil
        }
    }

    func receiveRawMembershipState(_ itemProxies: [TimelineItemProxy]) -> Bool {
        guard rawMembershipObservationStartCount > 0, let rawMembershipListener else {
            return false
        }

        rawMembershipListener(itemProxies)
        return true
    }
}

@MainActor
private final class RoomInfoSubscriptionHarness {
    private let subject: CurrentValueSubject<RoomInfoProxyProtocol, Never>
    private var timelineSubject: CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>?
    private weak var timelineItemProvider: TimelineItemProviderMock?
    private weak var rawMembershipRoom: MatrixRTCCallMembershipRoomProxyMock?
    private(set) var subscriptionStartCount = 0
    private(set) var timelineSubscriptionStartCount = 0

    init(initialValue: RoomInfoProxyProtocol) {
        subject = .init(initialValue)
    }

    func install(on room: JoinedRoomProxyMock, initialTimelineItems: [TimelineItemProxy] = []) {
        room.infoPublisher = subject.asCurrentValuePublisher()
        room.subscribeToRoomInfoUpdatesClosure = { [weak self] in
            self?.subscriptionStartCount += 1
        }
        if let rawMembershipRoom = room as? MatrixRTCCallMembershipRoomProxyMock {
            self.rawMembershipRoom = rawMembershipRoom
            rawMembershipRoom.initialRawMembershipState = initialTimelineItems
        }
        guard let timeline = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timeline.timelineItemProvider as? TimelineItemProviderMock else {
            return
        }

        let timelineSubject = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>((initialTimelineItems, .initial))
        self.timelineSubject = timelineSubject
        self.timelineItemProvider = timelineItemProvider
        timelineItemProvider.itemProxies = initialTimelineItems
        timelineItemProvider.updatePublisher = timelineSubject.eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live
        timeline.subscribeForUpdatesClosure = { [weak self] in
            guard let self, timelineSubscriptionStartCount == 0 else { return }
            timelineSubscriptionStartCount += 1
        }
    }

    func waitForTimelineSubscription() async -> Bool {
        for _ in 0..<30 {
            if timelineSubscriptionStartCount == 1,
               rawMembershipRoom?.rawMembershipObservationStartCount == 1 {
                return true
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return false
    }

    @discardableResult
    func receiveSDKUpdate(_ roomInfo: RoomInfoProxyProtocol) -> Bool {
        guard subscriptionStartCount > 0 else {
            return false
        }

        subject.send(roomInfo)
        return true
    }

    @discardableResult
    func receiveSDKTimelineUpdate(_ items: [TimelineItemProxy]) -> Bool {
        guard timelineSubscriptionStartCount > 0,
              let timelineSubject,
              let timelineItemProvider,
              receiveSDKRawMembershipUpdate(items) else {
            return false
        }

        timelineItemProvider.itemProxies = items
        timelineSubject.send((items, .initial))
        return true
    }

    @discardableResult
    func receiveSDKRawMembershipUpdate(_ items: [TimelineItemProxy]) -> Bool {
        rawMembershipRoom?.receiveRawMembershipState(items) ?? false
    }
}

private class PKPushPayloadMock: PKPushPayload {
    var dict: [AnyHashable: Any] = [:]

    override init() {
        dict[ElementCallServiceNotificationKey.roomID.rawValue] = "!room:example.com"
        dict[ElementCallServiceNotificationKey.roomDisplayName.rawValue] = "welcome"
        dict[ElementCallServiceNotificationKey.rtcNotifyEventID.rawValue] = "$000"
        dict[ElementCallServiceNotificationKey.expirationDate.rawValue] = Date(timeIntervalSince1970: 10)
    }

    init(dictionaryPayload: [AnyHashable: Any]) {
        dict = dictionaryPayload
    }

    override var dictionaryPayload: [AnyHashable: Any] {
        dict
    }

    func updatingExpiration(_ from: Date, lifetime: TimeInterval) -> Self {
        dict[ElementCallServiceNotificationKey.expirationDate.rawValue] = from.addingTimeInterval(lifetime)
        return self
    }

    func settingCallIntent(_ key: String, _ callIntent: String) -> Self {
        dict[key] = callIntent
        return self
    }
}

private class PKPushCredentialsMock: PKPushCredentials {
    private let mockToken: Data

    init(token: Data) {
        mockToken = token
        super.init()
    }

    override var token: Data {
        mockToken
    }
}

@MainActor
private final class SalemXProductionDispatchCapabilityClientSpy: SalemXProductionDispatchClientProtocol {
    private(set) var registrationRequests = [SalemXProductionDispatchCapabilityRegistrationRequest]()
    private(set) var consumeRequests = [SalemXProductionDispatchReceiverConsumeRequest]()
    var registrationHandler: ((SalemXProductionDispatchCapabilityRegistrationRequest) -> Void)?
    var consumeResult: Result<SalemXProductionDispatchReceiverConsumeResponse, SalemXProductionDispatchClientError> = .failure(.invalidState)
    var consumeHandler: ((SalemXProductionDispatchReceiverConsumeRequest) async
        -> Result<SalemXProductionDispatchReceiverConsumeResponse, SalemXProductionDispatchClientError>)?

    func registerCapability(_ request: SalemXProductionDispatchCapabilityRegistrationRequest) async
        -> Result<SalemXProductionDispatchCapabilityRegistrationResponse, SalemXProductionDispatchClientError> {
        registrationRequests.append(request)
        registrationHandler?(request)
        return .success(.init(registrationResult: "stored", tokenRedacted: true))
    }

    func prepare(_ request: SalemXProductionDispatchPrepareRequest) async
        -> Result<SalemXProductionDispatchPrepareResponse, SalemXProductionDispatchClientError> {
        fatalError("Unexpected prepare")
    }

    func claim(_ request: SalemXProductionDispatchReferenceRequest) async
        -> Result<SalemXProductionDispatchClaimResponse, SalemXProductionDispatchClientError> {
        fatalError("Unexpected claim")
    }

    func sendPrepared(_ request: SalemXProductionDispatchSendPreparedRequest) async
        -> Result<SalemXProductionDispatchSendPreparedResponse, SalemXProductionDispatchClientError> {
        fatalError("Unexpected send")
    }

    func cancelPrepared(_ request: SalemXProductionDispatchReferenceRequest) async
        -> Result<SalemXProductionDispatchCancelResponse, SalemXProductionDispatchClientError> {
        fatalError("Unexpected cancel")
    }

    func consume(_ request: SalemXProductionDispatchReceiverConsumeRequest) async
        -> Result<SalemXProductionDispatchReceiverConsumeResponse, SalemXProductionDispatchClientError> {
        consumeRequests.append(request)
        if let consumeHandler {
            return await consumeHandler(request)
        }
        return consumeResult
    }
}

private struct DeclineOwnCallMockError: Error, CustomStringConvertible {
    var description: String {
        "DeclineOwnCall"
    }
}
