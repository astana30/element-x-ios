//
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Clocks
import Combine
@testable import ElementX
import MatrixRustSDK
import MatrixRustSDKMocks
import PushKit
import Testing

@MainActor
final class ElementCallServiceTests {
    private let appSettings = AppSettings()
    private var callProvider: CXProviderMock!
    private var currentDate: Date!
    private var testClock: TestClock<Duration>!
    private var pushRegistry: PKPushRegistry!
    private var service: ElementCallService!
    private let clientProxy = ClientProxyMock(.init(userID: "@test:user.net"))
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
        
        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .unanswered {
                    confirmation()
                } else {
                    Issue.record("Call should have ended as unanswered")
                }
            }
            
            // advance past the timeout
            await testClock.advance(by: .seconds(30))
        }
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
        await confirmation { confirmation in
            callProvider.reportCallWithEndedAtReasonClosure = { _, _, reason in
                if reason == .unanswered {
                    confirmation()
                } else {
                    Issue.record("Call should have ended as unanswered")
                }
            }
            
            #expect(!callProvider.reportNewIncomingCallWithUpdateCompletionCalled)
            
            let pushPayload = PKPushPayloadMock().updatingExpiration(currentDate, lifetime: 300)
            
            service.pushRegistry(pushRegistry,
                                 didReceiveIncomingPushWith: pushPayload,
                                 for: .voIP) { }
            
            // Advance past the max timeout but below the 300
            await testClock.advance(by: .seconds(100))
        }
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
    func ongoingDirectCallEndsWhenRemoteLeavesCallMemberState() async {
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
            roomInfoSubject.send(makeRoomInfo(id: roomID,
                                              isDirect: true,
                                              hasRoomCall: true,
                                              participants: [ownUserID]))
        }
        
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
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

    private func makeCallTimelineItem(eventID: String,
                                      sender: String,
                                      isOwn: Bool,
                                      eventType: MessageLikeEventType) -> TimelineItemProxy {
        let content = TimelineItemContent.msgLike(content: .init(kind: .other(eventType: eventType),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        let item = EventTimelineItem(configuration: .init(eventID: eventID,
                                                          sender: sender,
                                                          isOwn: isOwn,
                                                          content: content))
        let proxy = EventTimelineItemProxy(item: item, uniqueID: .init(UUID().uuidString))
        return .event(proxy)
    }
    
    private func configureLiveTimeline(for room: JoinedRoomProxyMock) {
        guard let timelineProxy = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock else {
            return
        }
        
        let timelineUpdates = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>(([], .initial))
        timelineItemProvider.itemProxies = []
        timelineItemProvider.updatePublisher = timelineUpdates.eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live
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
