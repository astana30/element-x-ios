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
    func audioIntentDoesNotExposeMediaCredentials() {
        let preparation = EmbeddedElementCallPreparation.audio(roomID: "!room:example.org", intent: .startNew)
        let exposedLabels = Mirror(reflecting: preparation).children.compactMap(\.label).joined(separator: ",")

        #expect(preparation.startMode == .audio)
        #expect(preparation.cameraRequested == false)
        #expect(preparation.videoEnabled == false)
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

        let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
        try? await Task.sleep(for: .milliseconds(120))

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")
        service.tearDownCallSession()
        await service.requestCallTermination(roomID: roomID)

        #expect(room.declineCallNotificationIDCalled)
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

        var declineListener: CallDeclineListener?
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, listener in
            declineListener = listener
            return .success(TaskHandle(noHandle: .init()))
        }

        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .remoteEnded {
                    confirmation()
                }
            }

            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
            try? await Task.sleep(for: .milliseconds(120))

            declineListener?.call(declinerUserId: remoteUserID)
        }
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
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
            try? await Task.sleep(for: .milliseconds(120))

            roomInfoSubject.send(makeRoomInfo(id: roomID,
                                              isDirect: true,
                                              hasRoomCall: true,
                                              participants: []))
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
        timelineItemProvider.itemProxies = []
        timelineItemProvider.updatePublisher = timelineUpdates.eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live

        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .remoteEnded {
                    confirmation()
                }
            }

            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
            try? await Task.sleep(for: .milliseconds(120))

            let hangupItem = makeCallTimelineItem(eventID: "$hangup",
                                                  sender: remoteUserID,
                                                  isOwn: false,
                                                  eventType: .callHangup)
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
        room.infoPublisher = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                            isDirect: true,
                                                                                            hasRoomCall: true,
                                                                                            participants: [])).asCurrentValuePublisher()

        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .remoteEnded {
                    confirmation()
                }
            }

            let payload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) { }
            try? await Task.sleep(for: .milliseconds(120))

            roomSummaries.send([
                makeRoomSummary(id: roomID,
                                isDirect: true,
                                hasOngoingCall: false,
                                participants: [],
                                lastCallEvent: .init(state: .ended, intent: .audio))
            ])
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
    func ongoingDirectCallRoomInfoFirstThenTimelineRemovalEndsExactlyOnce() async {
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
        try? await Task.sleep(for: .milliseconds(50))
        #expect(endCallCount == 0)
        #expect(service.ongoingCallRoomIDPublisher.value == roomID)

        let remoteRemoval = [
            makeMatrixRTCMembershipTimelineItem(eventID: "$room-info-first-local-current",
                                                roomID: roomID,
                                                userID: ownUserID,
                                                deviceID: "LOCAL_DEVICE",
                                                membershipID: "LOCAL_PARTY",
                                                isActive: true),
            makeMatrixRTCMembershipTimelineItem(eventID: "$room-info-first-remote-empty",
                                                roomID: roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]
        #expect(subscription.receiveSDKTimelineUpdate(remoteRemoval))
        for _ in 0..<30 where endCallCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(endCallCount == 1)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
        #expect(subscription.receiveSDKTimelineUpdate(remoteRemoval))
        #expect(subscription.receiveSDKUpdate(makeRoomInfo(id: roomID,
                                                           isDirect: true,
                                                           hasRoomCall: false,
                                                           participants: [])))
        try? await Task.sleep(for: .milliseconds(50))
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
        let (room, subscription) = makeOngoingCallRoom(id: roomID,
                                                       ownUserID: ownUserID,
                                                       initialHasRoomCall: true,
                                                       initialParticipants: [ownUserID, ownUserID],
                                                       initialTimelineItems: [firstLocalMembership, secondLocalMembership])
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
                                                           participants: [ownUserID, ownUserID])))
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
    func differentClientSessionReplacesObservationAndRejectsPreviousProxyCallbacks() async {
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

        var observedRTCNotificationID: String?
        var declineListener: CallDeclineListener?
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { rtcNotificationEventID, listener in
            observedRTCNotificationID = rtcNotificationEventID
            declineListener = listener
            return .success(TaskHandle(noHandle: .init()))
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

            try? await Task.sleep(for: .milliseconds(120))
            declineListener?.call(declinerUserId: remoteUserID)
        }

        #expect(observedRTCNotificationID == "$000")
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
            return .success(TaskHandle(noHandle: .init()))
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
            .success(TaskHandle(noHandle: .init()))
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
            .success(TaskHandle(noHandle: .init()))
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
            .success(TaskHandle(noHandle: .init()))
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
    func incomingPushCallIntentParsingIsCaseInsensitive() async {
        await assertIncomingPush(callIntentKey: "CALL_INTENT",
                                 callIntent: "STARTCALLDMVOICE",
                                 expectsVideo: false)
        await assertIncomingPush(callIntentKey: "INTENT",
                                 callIntent: "VIDEO",
                                 expectsVideo: true)
    }

    @Test
    func incomingPushWithUnknownCallIntentUsesVideoFallback() async {
        await assertIncomingPush(callIntentKey: "callIntent",
                                 callIntent: "unknown",
                                 expectsVideo: true)
    }

    @Test
    func incomingPushWithoutCallIntentUsesVideoFallback() async {
        await assertIncomingPush(expectsVideo: true)
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
        timelineItemProvider.itemProxies = []
        timelineItemProvider.updatePublisher = timelineUpdates.eraseToAnyPublisher()
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

            try? await Task.sleep(for: .milliseconds(120))

            let hangupItem = makeCallTimelineItem(eventID: "$hangup",
                                                  sender: remoteUserID,
                                                  isOwn: false,
                                                  eventType: .callHangup)
            timelineUpdates.send(([hangupItem], .initial))
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
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }
        room.infoPublisher = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                            isDirect: true,
                                                                                            hasRoomCall: true,
                                                                                            participants: [ownUserID, remoteUserID])).asCurrentValuePublisher()

        await service.setupCallSession(roomID: roomID, roomDisplayName: "Room")

        await confirmation { confirmation in
            service.actions
                .sink { action in
                    if case .endCall(let observedRoomID) = action, observedRoomID == roomID {
                        confirmation()
                    }
                }
                .store(in: &cancellables)

            try? await Task.sleep(for: .milliseconds(120))

            roomSummaries.send([
                makeRoomSummary(id: roomID,
                                isDirect: true,
                                hasOngoingCall: true,
                                participants: [ownUserID, remoteUserID],
                                lastCallEvent: .init(state: .ended, intent: .audio))
            ])
        }

        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func whenVoIPPushTokenUpdatesAndClientProxyExists_voIPPusherIsRegistered() async throws {
        await service.declineIncomingCall()
        service.setClientProxy(clientProxy)

        let pushCredentials = PKPushCredentialsMock(token: Data("1234".utf8))

        await confirmation { confirmation in
            clientProxy.setPusherWithClosure = { _ in
                confirmation()
            }

            service.pushRegistry(pushRegistry, didUpdate: pushCredentials, for: .voIP)
            try? await Task.sleep(for: .milliseconds(100))
        }

        let configuration = try #require(clientProxy.setPusherWithReceivedConfiguration)
        #expect(configuration.identifiers.pushkey == Data("1234".utf8).base64EncodedString())
        #expect(configuration.identifiers.appId == appSettings.voIPPusherAppID)
        #expect(configuration.profileTag == appSettings.voIPPusherProfileTag)
    }

    @Test
    func whenClientProxyArrivesAfterVoIPPushToken_voIPPusherIsRegistered() async throws {
        await service.declineIncomingCall()
        let pushCredentials = PKPushCredentialsMock(token: Data("abcd".utf8))
        service.pushRegistry(pushRegistry, didUpdate: pushCredentials, for: .voIP)

        await confirmation { confirmation in
            clientProxy.setPusherWithClosure = { _ in
                confirmation()
            }

            service.setClientProxy(clientProxy)
            try? await Task.sleep(for: .milliseconds(100))
        }

        let configuration = try #require(clientProxy.setPusherWithReceivedConfiguration)
        #expect(configuration.identifiers.pushkey == Data("abcd".utf8).base64EncodedString())
        #expect(configuration.identifiers.appId == appSettings.voIPPusherAppID)
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
        let room = JoinedRoomProxyMock(.init(id: id,
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

    private func makeCallTimelineItem(eventID: String,
                                      sender: String,
                                      isOwn: Bool,
                                      eventType: MessageLikeEventType) -> TimelineItemProxy {
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        lazyProvider.debugInfoReturnValue = .init(model: "call event",
                                                  originalJson: nil,
                                                  latestEditJson: nil)
        let content = TimelineItemContent.msgLike(content: .init(kind: .other(eventType: eventType),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        let item = EventTimelineItem(configuration: .init(eventID: eventID,
                                                          sender: sender,
                                                          isOwn: isOwn,
                                                          content: content,
                                                          lazyProvider: lazyProvider))
        let proxy = EventTimelineItemProxy(item: item, uniqueID: .init(UUID().uuidString))
        return .event(proxy)
    }

    private func configureLiveTimeline(for room: JoinedRoomProxyMock) {
        guard let timelineProxy = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock else {
            return
        }

        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerReturnValue = .failure(.missingTransactionID)
        let timelineUpdates = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>(([], .initial))
        timelineItemProvider.itemProxies = []
        timelineItemProvider.updatePublisher = timelineUpdates.eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live
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
    func secureAnswerBridgeSuppressesForegroundIncomingFallback() async {
        service = ElementCallService(appSettings: appSettings,
                                     callProvider: callProvider,
                                     timeProvider: TimeProvider(clock: testClock) { self.currentDate },
                                     salemXAnswerBridgeConfiguration: .init(embeddedMatrixRTCAnswerBridgeEnabled: true))
        let roomID = "redacted-room"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: ["redacted-remote"])
        service.setClientProxy(clientProxy)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        handleForegroundCall(roomID: roomID, deduplicationID: "redacted-current-call")

        #expect(await waitForIncomingCallReports(count: 1) == false)
    }

    @Test
    func terminatedCallSuppressionDoesNotBlockFreshIncomingFallback() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        let roomSummaryProvider = RoomSummaryProviderMock()
        let roomSummaries = CurrentValueSubject<[RoomSummary], Never>([])
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 1)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = roomSummaries.asCurrentValuePublisher()
        clientProxy.roomSummaryProvider = roomSummaryProvider
        configureJoinedRoomMock(roomID: roomID, activeParticipants: [remoteUserID])
        service.setClientProxy(clientProxy)

        await service.requestCallTermination(roomID: roomID)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        roomSummaries.send([
            makeRoomSummary(id: roomID,
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: [remoteUserID],
                            lastCallEvent: .init(state: .incoming, intent: .audio))
        ])
        #expect(await waitForIncomingCallReports(count: 1))
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update.hasVideo == false)
    }

    @Test
    func terminatedCallSuppressionStillBlocksStaleIncomingFallback() async {
        let roomID = "redacted-room"
        let roomSummaryProvider = RoomSummaryProviderMock()
        let roomSummaries = CurrentValueSubject<[RoomSummary], Never>([])
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 1)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = roomSummaries.asCurrentValuePublisher()
        clientProxy.roomSummaryProvider = roomSummaryProvider
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
    func activeCallGuardStillBlocksConcurrentIncomingFallback() async {
        let roomID = "redacted-room"
        let nextRoomID = "redacted-next-room"
        let remoteUserID = "redacted-remote"
        let roomSummaryProvider = RoomSummaryProviderMock()
        let roomSummaries = CurrentValueSubject<[RoomSummary], Never>([])
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 1)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = roomSummaries.asCurrentValuePublisher()
        clientProxy.roomSummaryProvider = roomSummaryProvider
        configureJoinedRoomMock(roomID: roomID, activeParticipants: [remoteUserID])
        service.setClientProxy(clientProxy)

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        roomSummaries.send([
            makeRoomSummary(id: roomID,
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: [remoteUserID],
                            lastCallEvent: .init(state: .incoming, intent: .audio))
        ])
        #expect(await waitForIncomingCallReports(count: 1))

        roomSummaries.send([
            makeRoomSummary(id: nextRoomID,
                            isDirect: true,
                            hasOngoingCall: true,
                            participants: [remoteUserID],
                            lastCallEvent: .init(state: .incoming, intent: .audio))
        ])

        #expect(await waitForIncomingCallReports(count: 2) == false)
    }

    @Test
    func foregroundCurrentRoomCallEventReportsIncomingPromptly() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: [remoteUserID])
        service.setClientProxy(clientProxy)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        handleForegroundCall(roomID: roomID, deduplicationID: "redacted-current-call-a")

        #expect(await waitForIncomingCallReports(count: 1))
        #expect(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.update.hasVideo == false)
    }

    @Test
    func foregroundCurrentRoomRepeatIncomingAfterEndReportsAgain() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: [remoteUserID])
        service.setClientProxy(clientProxy)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        handleForegroundCall(roomID: roomID, deduplicationID: "redacted-current-call-a")
        #expect(await waitForIncomingCallReports(count: 1))

        await service.declineIncomingCall()

        handleForegroundCall(roomID: roomID, deduplicationID: "redacted-current-call-b")

        #expect(await waitForIncomingCallReports(count: 2))
    }

    @Test
    func foregroundCurrentRoomTerminalEventRemainsSuppressed() async {
        let roomID = "redacted-room"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: [])
        service.setClientProxy(clientProxy)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        handleForegroundCall(roomID: roomID,
                             state: .ended,
                             deduplicationID: "redacted-terminal-call")

        #expect(await waitForIncomingCallReports(count: 1) == false)
    }

    @Test
    func foregroundCurrentRoomActiveCallGuardBlocksConcurrentIncoming() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: [remoteUserID])
        service.setClientProxy(clientProxy)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        handleForegroundCall(roomID: roomID, deduplicationID: "redacted-current-call-a")
        #expect(await waitForIncomingCallReports(count: 1))

        handleForegroundCall(roomID: roomID, deduplicationID: "redacted-current-call-b")

        #expect(await waitForIncomingCallReports(count: 2) == false)
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

        handleForegroundCall(roomID: roomID, deduplicationID: "redacted-current-call-a")

        #expect(await waitForIncomingCallReports(count: 1))
    }

    @Test
    func foregroundCurrentRoomDuplicateCallEventDoesNotReportTwice() async {
        let roomID = "redacted-room"
        let remoteUserID = "redacted-remote"
        configureRoomSummaryProvider()
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: [remoteUserID])
        service.setClientProxy(clientProxy)
        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        callProvider.reportNewIncomingCallWithUpdateCompletionClosure = { _, _, completion in
            completion(nil)
        }

        handleForegroundCall(roomID: roomID, deduplicationID: "redacted-current-call-a")
        #expect(await waitForIncomingCallReports(count: 1))

        await service.declineIncomingCall()

        handleForegroundCall(roomID: roomID, deduplicationID: "redacted-current-call-a")

        #expect(await waitForIncomingCallReports(count: 2) == false)
    }

    @Test
    func foregroundCurrentRoomObservationDoesNotSubscribeTimelineAgain() {
        let roomID = "redacted-room"
        let room = configureJoinedRoomMock(roomID: roomID, activeParticipants: [])
        guard let timeline = room.timeline as? TimelineProxyMock else {
            Issue.record("Expected timeline mock")
            return
        }

        service.observeForegroundRoom(roomProxy: room, roomDisplayName: "Room")

        #expect(timeline.subscribeForUpdatesCallsCount == 0)
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

    private func handleForegroundCall(roomID: String,
                                      state: RoomCallEvent.State = .incoming,
                                      deduplicationID: String) {
        service.handleForegroundCurrentRoomCallEvent(.init(roomID: roomID,
                                                           roomDisplayName: "Room",
                                                           isDirect: true,
                                                           isOwnEvent: false,
                                                           callEvent: .init(state: state, intent: .audio),
                                                           deduplicationID: deduplicationID))
    }

    private func configureRoomSummaryProvider() {
        let roomSummaryProvider = RoomSummaryProviderMock()
        roomSummaryProvider.statePublisher = CurrentValueSubject<RoomSummaryProviderState, Never>(.loaded(totalNumberOfRooms: 1)).asCurrentValuePublisher()
        roomSummaryProvider.roomListPublisher = CurrentValueSubject<[RoomSummary], Never>([]).asCurrentValuePublisher()
        clientProxy.roomSummaryProvider = roomSummaryProvider
    }

    @discardableResult
    private func configureJoinedRoomMock(roomID: String, activeParticipants: [String]) -> JoinedRoomProxyMock {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             name: "Room",
                                             isDirect: true,
                                             hasOngoingCall: true,
                                             ownUserID: clientProxy.userID))
        room.infoPublisher = CurrentValueSubject<RoomInfoProxyProtocol, Never>(makeRoomInfo(id: roomID,
                                                                                            activeParticipants: activeParticipants)).asCurrentValuePublisher()
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .success(TaskHandle(noHandle: .init()))
        }

        if let timelineProxy = room.timeline as? TimelineProxyMock,
           let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock {
            timelineItemProvider.itemProxies = []
            timelineItemProvider.updatePublisher = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>(([], .initial)).eraseToAnyPublisher()
            timelineItemProvider.paginationState = .initial
            timelineItemProvider.kind = .live
        }

        clientProxy.roomForIdentifierClosure = { _ in
            .joined(room)
        }

        return room
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
}

@MainActor
func makeMatrixRTCMembershipTimelineItem(eventID: String,
                                         roomID: String,
                                         userID: String = "@test:user.net",
                                         deviceID: String = "LOCAL_DEVICE",
                                         membershipID: String = "LOCAL_PARTY",
                                         isActive: Bool = true,
                                         createdAt: Date = Date(),
                                         expiresInMilliseconds: UInt64 = 3_600_000) -> TimelineItemProxy {
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
    let item = EventTimelineItem(configuration: .init(eventID: eventID,
                                                      sender: userID,
                                                      isOwn: deviceID == "LOCAL_DEVICE",
                                                      content: .failedToParseState(eventType: "org.matrix.msc3401.call.member",
                                                                                   stateKey: stateKey,
                                                                                   error: "Unsupported state event"),
                                                      lazyProvider: lazyProvider))
    return .event(.init(item: item, uniqueID: .init(UUID().uuidString)))
}

@MainActor
private final class RoomInfoSubscriptionHarness {
    private let subject: CurrentValueSubject<RoomInfoProxyProtocol, Never>
    private var timelineSubject: CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>?
    private weak var timelineItemProvider: TimelineItemProviderMock?
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
            if timelineSubscriptionStartCount == 1 {
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
              let timelineItemProvider else {
            return false
        }

        timelineItemProvider.itemProxies = items
        timelineSubject.send((items, .initial))
        return true
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

private struct DeclineOwnCallMockError: Error, CustomStringConvertible {
    var description: String {
        "DeclineOwnCall"
    }
}
