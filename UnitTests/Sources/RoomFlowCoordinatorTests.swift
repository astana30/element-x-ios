//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import MatrixRustSDKMocks
import Testing

@MainActor
final class RoomFlowCoordinatorTests {
    var clientProxy: ClientProxyMock!
    var timelineControllerFactory: TimelineControllerFactoryMock!
    var roomFlowCoordinator: RoomFlowCoordinator!
    var navigationStackCoordinator: NavigationStackCoordinator!
    var cancellables = Set<AnyCancellable>()
    
    deinit {
        AppSettings.resetAllSettings()
    }
    
    @Test
    func roomPresentation() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .room(roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        
        try await clearRoute(expectedActions: [.finished])
        #expect(navigationStackCoordinator.rootCoordinator == nil)
    }
    
    @Test
    func roomDetailsPresentation() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .roomDetails(roomID: "1"))
        #expect(navigationStackCoordinator.rootCoordinator is RoomDetailsScreenCoordinator)
        
        try await clearRoute(expectedActions: [.finished])
        #expect(navigationStackCoordinator.rootCoordinator == nil)
    }
    
    @Test
    func noOp() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .roomDetails(roomID: "1"))
        #expect(navigationStackCoordinator.rootCoordinator is RoomDetailsScreenCoordinator)
        let detailsCoordinator = navigationStackCoordinator.rootCoordinator
        
        roomFlowCoordinator.handleAppRoute(.roomDetails(roomID: "1"), animated: true)
        await Task.yield()
        
        #expect(navigationStackCoordinator.rootCoordinator is RoomDetailsScreenCoordinator)
        #expect(navigationStackCoordinator.rootCoordinator === detailsCoordinator)
    }
    
    @Test
    func pushDetails() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .room(roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        try await process(route: .roomDetails(roomID: "1"))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomDetailsScreenCoordinator)
    }
    
    @Test
    func childRoomFlow() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .room(roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        try await process(route: .childRoom(roomID: "2", via: []))
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomScreenCoordinator)
        
        try await process(route: .childRoom(roomID: "3", via: []))
        #expect(navigationStackCoordinator.stackCoordinators.count == 2)
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.last is RoomScreenCoordinator)
        
        try await clearRoute(expectedActions: [.finished])
        #expect(navigationStackCoordinator.rootCoordinator == nil)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
    }
    
    /// Tests the child flow teardown in isolation of it's parent.
    @Test
    func childFlowTearDown() async throws {
        setupRoomFlowCoordinator(asChildFlow: true)
        navigationStackCoordinator.setRootCoordinator(BlankFormCoordinator())
        
        try await process(route: .room(roomID: "1", via: []))
        try await process(route: .roomDetails(roomID: "1"))
        #expect(navigationStackCoordinator.rootCoordinator is BlankFormCoordinator, "A child room flow should push onto the stack, leaving the root alone.")
        #expect(navigationStackCoordinator.stackCoordinators.count == 2)
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.last is RoomDetailsScreenCoordinator)
        
        try await clearRoute(expectedActions: [.finished])
        #expect(navigationStackCoordinator.rootCoordinator is BlankFormCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 2, "A child room flow should leave its parent to clean up the stack.")
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomScreenCoordinator, "A child room flow should leave its parent to clean up the stack.")
        #expect(navigationStackCoordinator.stackCoordinators.last is RoomDetailsScreenCoordinator, "A child room flow should leave its parent to clean up the stack.")
    }
    
    @Test
    func childRoomMemberDetails() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .room(roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        try await process(route: .childRoom(roomID: "2", via: []))
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomScreenCoordinator)
        
        try await process(route: .roomMemberDetails(userID: RoomMemberProxyMock.mockMe.userID))
        #expect(navigationStackCoordinator.stackCoordinators.count == 2)
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.last is RoomMemberDetailsScreenCoordinator)
    }
    
    @Test
    func childRoomIgnoresDirectDuplicate() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .room(roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        try await process(route: .childRoom(roomID: "1", via: []))
        #expect(navigationStackCoordinator.stackCoordinators.count == 0,
                "A room flow shouldn't present a direct child for the same room.")
        
        try await process(route: .childRoom(roomID: "2", via: []))
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomScreenCoordinator)
        
        try await process(route: .childRoom(roomID: "1", via: []))
        #expect(navigationStackCoordinator.stackCoordinators.count == 2,
                "Presenting the same room multiple times should be allowed when it's not a direct child of itself.")
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.last is RoomScreenCoordinator)
    }
    
    @Test
    func roomMembershipInvite() async throws {
        setupRoomFlowCoordinator(roomType: .invited(roomID: "InvitedRoomID"))
        
        try await process(route: .room(roomID: "InvitedRoomID", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is JoinRoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        try await clearRoute(expectedActions: [.finished])
        #expect(navigationStackCoordinator.rootCoordinator == nil)
        
        setupRoomFlowCoordinator(roomType: .invited(roomID: "InvitedRoomID"))
        
        try await process(route: .room(roomID: "InvitedRoomID", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is JoinRoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        // "Join" the room
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(JoinedRoomProxyMock(.init()))
        }
        
        try await process(route: .room(roomID: "InvitedRoomID", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
    }
    
    @Test
    func childRoomMembershipInvite() async throws {
        setupRoomFlowCoordinator(asChildFlow: true, roomType: .invited(roomID: "InvitedRoomID"))
        navigationStackCoordinator.setRootCoordinator(BlankFormCoordinator())
        
        try await process(route: .room(roomID: "InvitedRoomID", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is BlankFormCoordinator, "A child room flow should push onto the stack, leaving the root alone.")
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        #expect(navigationStackCoordinator.stackCoordinators.last is JoinRoomScreenCoordinator)
        
        try await clearRoute(expectedActions: [.finished])
        #expect(navigationStackCoordinator.stackCoordinators.last == nil, "A child room flow should remove the join room scren on dismissal")
        
        setupRoomFlowCoordinator(asChildFlow: true, roomType: .invited(roomID: "InvitedRoomID"))
        navigationStackCoordinator.setRootCoordinator(BlankFormCoordinator())
        
        try await process(route: .room(roomID: "InvitedRoomID", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is BlankFormCoordinator, "A child room flow should push onto the stack, leaving the root alone.")
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        #expect(navigationStackCoordinator.stackCoordinators.last is JoinRoomScreenCoordinator)
        
        // "Join" the room
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(JoinedRoomProxyMock(.init()))
        }
        
        try await process(route: .room(roomID: "InvitedRoomID", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is BlankFormCoordinator, "A child room flow should push onto the stack, leaving the root alone.")
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        #expect(navigationStackCoordinator.stackCoordinators.last is RoomScreenCoordinator)
    }
    
    @Test
    func eventRoute() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .event(eventID: "1", roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        try await process(route: .childEvent(eventID: "2", roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        try await process(route: .childEvent(eventID: "3", roomID: "2", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        #expect(navigationStackCoordinator.stackCoordinators.first is RoomScreenCoordinator)
    }
    
    @Test
    func threadedEventRoutes() async throws {
        ServiceLocator.shared.settings.threadsEnabled = true
        setupRoomFlowCoordinator()
        
        // Navigate directly to the threaded event
        var configuration = JoinedRoomProxyMockConfiguration(id: "1")
        var roomProxy = JoinedRoomProxyMock(configuration)
        
        var roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(RoomInfoProxyMock(configuration))
        roomProxy.infoPublisher = roomInfoSubject.asCurrentValuePublisher()
        
        var mockedEvent = TimelineEventSDKMock()
        mockedEvent.threadRootEventIdReturnValue = "1"
        roomProxy.loadOrFetchEventDetailsForReturnValue = .success(mockedEvent)
        
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(roomProxy)
        }
        
        try await process(route: .event(eventID: "2", roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        try #require(navigationStackCoordinator.stackCoordinators.count == 1) // #require these counts so accessing by index is safe.
        #expect(navigationStackCoordinator.stackCoordinators[0] is ThreadTimelineScreenCoordinator)
        
        // From the thread screen, navigate to another threaded event in the same room, and in the same thread.
        let threadCoordinator = navigationStackCoordinator.stackCoordinators[0] as? ThreadTimelineScreenCoordinator
        try await process(route: .childEvent(eventID: "3", roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        try #require(navigationStackCoordinator.stackCoordinators.count == 1)
        #expect(navigationStackCoordinator.stackCoordinators[0] is ThreadTimelineScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators[0] === threadCoordinator)
        // Would be nice to test if the focusEvent function has been called but there is no way to mock that.
        
        // From the thread screen, navigate to another threaded event in the same room, but in a different thread.
        mockedEvent = TimelineEventSDKMock()
        mockedEvent.threadRootEventIdReturnValue = "4"
        roomProxy.loadOrFetchEventDetailsForReturnValue = .success(mockedEvent)
        try await process(route: .childEvent(eventID: "5", roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        try #require(navigationStackCoordinator.stackCoordinators.count == 2)
        #expect(navigationStackCoordinator.stackCoordinators[0] is ThreadTimelineScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators[1] is ThreadTimelineScreenCoordinator)
        
        // From the thread screen, navigate to another threaded event in a different room.
        configuration = JoinedRoomProxyMockConfiguration(id: "2")
        roomProxy = JoinedRoomProxyMock(configuration)
        
        roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(RoomInfoProxyMock(configuration))
        roomProxy.infoPublisher = roomInfoSubject.asCurrentValuePublisher()
        
        mockedEvent = TimelineEventSDKMock()
        mockedEvent.threadRootEventIdReturnValue = "1"
        roomProxy.loadOrFetchEventDetailsForReturnValue = .success(mockedEvent)
        
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(roomProxy)
        }
        
        try await process(route: .childEvent(eventID: "2", roomID: "2", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        try #require(navigationStackCoordinator.stackCoordinators.count == 4)
        #expect(navigationStackCoordinator.stackCoordinators[0] is ThreadTimelineScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators[1] is ThreadTimelineScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators[2] is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators[3] is ThreadTimelineScreenCoordinator)
        
        // From the thread screen, navigate to an event of the same room that is not threaded
        mockedEvent = TimelineEventSDKMock()
        mockedEvent.threadRootEventIdReturnValue = nil
        roomProxy.loadOrFetchEventDetailsForReturnValue = .success(mockedEvent)
        
        try await process(route: .childEvent(eventID: "3", roomID: "2", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        try #require(navigationStackCoordinator.stackCoordinators.count == 5)
        #expect(navigationStackCoordinator.stackCoordinators[0] is ThreadTimelineScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators[1] is ThreadTimelineScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators[2] is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators[3] is ThreadTimelineScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators[4] is RoomScreenCoordinator)
    }
    
    @Test
    func shareMediaRoute() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .room(roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        let sharePayload: ShareExtensionPayload = .mediaFiles(roomID: "1", mediaFiles: [.init(url: .picturesDirectory, suggestedName: nil)])
        try await process(route: .share(sharePayload))
        
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        #expect((navigationStackCoordinator.sheetCoordinator as? NavigationStackCoordinator)?.rootCoordinator is MediaUploadPreviewScreenCoordinator)
        
        try await process(route: .childRoom(roomID: "2", via: []))
        #expect(navigationStackCoordinator.sheetCoordinator == nil)
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        
        try await process(route: .share(sharePayload))
        
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        #expect((navigationStackCoordinator.sheetCoordinator as? NavigationStackCoordinator)?.rootCoordinator is MediaUploadPreviewScreenCoordinator)
    }
    
    @Test
    func shareTextRoute() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .room(roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        let sharePayload: ShareExtensionPayload = .text(roomID: "1", text: "Important text")
        try await process(route: .share(sharePayload))
        
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        
        #expect(navigationStackCoordinator.sheetCoordinator == nil, "The media upload sheet shouldn't be shown when sharing text.")
        
        try await process(route: .childRoom(roomID: "2", via: []))
        #expect(navigationStackCoordinator.sheetCoordinator == nil)
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
        
        try await process(route: .share(sharePayload))
        
        #expect(navigationStackCoordinator.stackCoordinators.count == 0)
        #expect(navigationStackCoordinator.sheetCoordinator == nil, "The media upload sheet shouldn't be shown when sharing text.")
    }
    
    @Test
    func leavingRoom() async throws {
        setupRoomFlowCoordinator()
        
        var configuration = JoinedRoomProxyMockConfiguration()
        let roomProxy = JoinedRoomProxyMock(configuration)
        
        let roomInfoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(RoomInfoProxyMock(configuration))
        roomProxy.infoPublisher = roomInfoSubject.asCurrentValuePublisher()
        
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(roomProxy)
        }
        
        try await process(route: .room(roomID: "1", via: []))
        
        let fulfillment = deferFulfillment(roomFlowCoordinator.actions) { action in
            action == .finished
        }
        
        configuration.membership = .left
        roomInfoSubject.send(RoomInfoProxyMock(configuration))
        
        try await fulfillment.fulfill()
    }

    @Test
    func nativeDirectCallRoomFlowOwnerIsDisabledByDefault() async {
        let owner = NativeDirectCallRoomFlowOwner(roomProxy: JoinedRoomProxyMock(.init()))

        expectFailure(owner.prepare(), .disabled)
        await expectFailure(owner.startListener(), .disabled)
        await expectFailure(owner.startOutgoingAudioCall(), .disabled)
        await expectFailure(owner.acceptIncomingCall(), .disabled)
        await expectFailure(owner.hangup(), .disabled)

        owner.stop()
        await owner.reset()

        #expect(owner.isListenerStarted == false)
        #expect(owner.activeSession == nil)
    }

    @Test
    func nativeDirectCallRoomFlowOwnerFailsClosedWithoutRoomControllerProvider() async {
        let owner = NativeDirectCallRoomFlowOwner(roomProxy: JoinedRoomProxyMock(.init()),
                                                  triggerConfiguration: .init(isEnabled: true))

        expectFailure(owner.prepare(), .missingRoomControllerProvider)
        await expectFailure(owner.startListener(), .missingRoomControllerProvider)
        await expectFailure(owner.startOutgoingAudioCall(), .missingRoomControllerProvider)
        await expectFailure(owner.acceptIncomingCall(), .missingRoomControllerProvider)
        await expectFailure(owner.hangup(), .missingRoomControllerProvider)
    }

    @Test
    func nativeDirectCallRoomFlowOwnerCreatesTriggerOnlyWhenExplicitlyPrepared() async {
        let controller = NativeDirectCallRoomControllingSpy()
        let roomProxy = NativeDirectCallProvidingJoinedRoomProxyMock(controller: controller)
        let owner = NativeDirectCallRoomFlowOwner(roomProxy: roomProxy,
                                                  triggerConfiguration: .init(isEnabled: true))

        #expect(roomProxy.makeNativeDirectCallRoomControllerCount == 0)
        #expect(controller.prepareCount == 0)
        #expect(controller.startCount == 0)
        #expect(owner.isListenerStarted == false)

        expectFailure(owner.prepare(), .trigger(.control(.noActiveCall)))

        #expect(roomProxy.makeNativeDirectCallRoomControllerCount == 1)
        #expect(controller.prepareCount == 1)
        #expect(controller.startCount == 0)

        await expectFailure(owner.startListener(), .trigger(.control(.noActiveCall)))

        #expect(roomProxy.makeNativeDirectCallRoomControllerCount == 1)
        #expect(controller.startCount == 1)
    }

    @Test
    func nativeDirectCallRoomFlowOwnerStopAndResetAreIdempotent() async {
        let controller = NativeDirectCallRoomControllingSpy()
        let roomProxy = NativeDirectCallProvidingJoinedRoomProxyMock(controller: controller)
        let owner = NativeDirectCallRoomFlowOwner(roomProxy: roomProxy,
                                                  triggerConfiguration: .init(isEnabled: true))

        expectFailure(owner.prepare(), .trigger(.control(.noActiveCall)))

        owner.stop()
        owner.stop()
        await owner.reset()
        await owner.reset()

        #expect(controller.stopCount == 1)
        #expect(controller.resetCount == 1)
    }

    @Test
    func nativeDirectCallRoomFlowOwnerDeinitStopsPreparedTrigger() {
        let controller = NativeDirectCallRoomControllingSpy()
        let roomProxy = NativeDirectCallProvidingJoinedRoomProxyMock(controller: controller)
        var owner: NativeDirectCallRoomFlowOwner? = NativeDirectCallRoomFlowOwner(roomProxy: roomProxy,
                                                                                  triggerConfiguration: .init(isEnabled: true))

        do {
            guard let unwrappedOwner = owner else {
                Issue.record("Expected native direct-call room-flow owner to be available.")
                return
            }

            expectFailure(unwrappedOwner.prepare(), .trigger(.control(.noActiveCall)))
            #expect(controller.stopCount == 0)
        }

        owner = nil

        #expect(controller.stopCount == 1)
        #expect(controller.resetCount == 0)
    }

    @Test
    func nativeDirectCallRoomFlowOwnerResetBlocksCommandsAndDeduplicatesResetTask() async {
        let controller = NativeDirectCallRoomControllingSpy()
        controller.activeSession = directCallSession()
        controller.suspendReset = true
        let roomProxy = NativeDirectCallProvidingJoinedRoomProxyMock(controller: controller)
        let owner = NativeDirectCallRoomFlowOwner(roomProxy: roomProxy,
                                                  triggerConfiguration: .init(isEnabled: true))

        expectFailure(owner.prepare(), .trigger(.control(.noActiveCall)))
        #expect(owner.activeSession == controller.activeSession)

        owner.beginReset()
        owner.beginReset()
        await Task.yield()

        #expect(controller.stopCount == 1)
        #expect(controller.resetCount == 1)
        expectFailure(owner.prepare(), .resetting)
        await expectFailure(owner.startListener(), .resetting)
        await expectFailure(owner.startOutgoingAudioCall(), .resetting)
        await expectFailure(owner.acceptIncomingCall(), .resetting)
        await expectFailure(owner.hangup(), .resetting)

        controller.resumeReset()
        await owner.reset()
        await owner.reset()

        #expect(controller.stopCount == 1)
        #expect(controller.resetCount == 1)
        #expect(owner.isListenerStarted == false)
        #expect(owner.activeSession == nil)
    }

    @Test
    func roomFlowDismissStopsAndResetsNativeDirectCallOwner() async throws {
        let owner = NativeDirectCallRoomFlowOwnerSpy()
        owner.suspendReset = true

        setupRoomFlowCoordinator { roomProxy in
            #expect(roomProxy.id == "1")
            owner.makeCount += 1
            return owner
        }

        try await process(route: .room(roomID: "1", via: []))
        #expect(owner.makeCount == 1)
        #expect(owner.stopCount == 0)
        #expect(owner.resetCount == 0)

        try await clearRoute(expectedActions: [.finished])
        #expect(owner.stopCount == 1)
        #expect(owner.resetCount == 1)
        #expect(owner.resetCompletionCount == 0)

        owner.resumeReset()
        await Task.yield()
        #expect(owner.resetCompletionCount == 1)
    }

    @Test
    func nativeDirectCallDeveloperCommandRouterIsDisabledByDefault() async {
        let owner = NativeDirectCallRoomFlowOwnerSpy()
        owner.isListenerStarted = true
        owner.activeSession = directCallSession()
        let commandRouter = NativeDirectCallRoomDeveloperCommandRouter {
            owner
        }

        expectFailure(commandRouter.prepare(), .disabled)
        await expectFailure(commandRouter.startListener(), .disabled)
        await expectFailure(commandRouter.startOutgoingAudioCall(), .disabled)
        await expectFailure(commandRouter.acceptIncomingCall(), .disabled)
        await expectFailure(commandRouter.hangup(), .disabled)
        expectFailure(commandRouter.stop(), .disabled)
        await expectFailure(commandRouter.reset(), .disabled)

        #expect(commandRouter.isListenerStarted == false)
        #expect(commandRouter.activeSession == nil)
        #expect(owner.prepareCount == 0)
        #expect(owner.startCount == 0)
        #expect(owner.outgoingCount == 0)
        #expect(owner.acceptCount == 0)
        #expect(owner.hangupCount == 0)
        #expect(owner.stopCount == 0)
        #expect(owner.resetCount == 0)
    }

    @Test
    func nativeDirectCallDeveloperCommandRouterFailsClosedWithoutOwner() async {
        let commandRouter = NativeDirectCallRoomDeveloperCommandRouter(configuration: .init(isEnabled: true)) {
            nil
        }

        expectFailure(commandRouter.prepare(), .unavailable)
        await expectFailure(commandRouter.startListener(), .unavailable)
        await expectFailure(commandRouter.startOutgoingAudioCall(), .unavailable)
        await expectFailure(commandRouter.acceptIncomingCall(), .unavailable)
        await expectFailure(commandRouter.hangup(), .unavailable)
        expectFailure(commandRouter.stop(), .unavailable)
        await expectFailure(commandRouter.reset(), .unavailable)

        #expect(commandRouter.isListenerStarted == false)
        #expect(commandRouter.activeSession == nil)
    }

    @Test
    func nativeDirectCallDeveloperCommandRouterDelegatesExplicitCommandsOnly() async {
        let owner = NativeDirectCallRoomFlowOwnerSpy()
        let session = directCallSession()
        owner.isListenerStarted = true
        owner.activeSession = session
        let commandRouter = NativeDirectCallRoomDeveloperCommandRouter(configuration: .init(isEnabled: true)) {
            owner
        }

        expectFailure(commandRouter.prepare(), .owner(.disabled))
        #expect(owner.prepareCount == 1)
        #expect(owner.startCount == 0)

        await expectFailure(commandRouter.startListener(), .owner(.disabled))
        await expectFailure(commandRouter.startOutgoingAudioCall(), .owner(.disabled))
        await expectFailure(commandRouter.acceptIncomingCall(), .owner(.disabled))
        await expectFailure(commandRouter.hangup(), .owner(.disabled))

        expectSuccess(commandRouter.stop())
        let resetResult = await commandRouter.reset()
        expectSuccess(resetResult)

        #expect(commandRouter.isListenerStarted == true)
        #expect(commandRouter.activeSession == session)
        #expect(owner.startCount == 1)
        #expect(owner.outgoingCount == 1)
        #expect(owner.acceptCount == 1)
        #expect(owner.hangupCount == 1)
        #expect(owner.stopCount == 1)
        #expect(owner.resetCount == 1)
    }

    @Test
    func nativeDirectCallDeveloperCommandRouterFailsClosedWhileOwnerIsResetting() async {
        let controller = NativeDirectCallRoomControllingSpy()
        controller.suspendReset = true
        let roomProxy = NativeDirectCallProvidingJoinedRoomProxyMock(controller: controller)
        let owner = NativeDirectCallRoomFlowOwner(roomProxy: roomProxy,
                                                  triggerConfiguration: .init(isEnabled: true))
        let commandRouter = NativeDirectCallRoomDeveloperCommandRouter(configuration: .init(isEnabled: true)) {
            owner
        }

        expectFailure(commandRouter.prepare(), .owner(.trigger(.control(.noActiveCall))))
        owner.beginReset()
        await Task.yield()

        await expectFailure(commandRouter.startListener(), .owner(.resetting))
        await expectFailure(commandRouter.startOutgoingAudioCall(), .owner(.resetting))
        await expectFailure(commandRouter.acceptIncomingCall(), .owner(.resetting))
        await expectFailure(commandRouter.hangup(), .owner(.resetting))
        expectFailure(commandRouter.prepare(), .owner(.resetting))

        guard controller.resetCount == 1 else {
            Issue.record("Expected native direct-call room-flow owner reset to start.")
            return
        }

        controller.resumeReset()
        let resetResult = await commandRouter.reset()
        expectSuccess(resetResult)

        #expect(controller.stopCount == 1)
        #expect(controller.resetCount == 1)
    }

    @Test
    func nativeDirectCallDiagnosticCommandEntryIsDisabledByDefault() async throws {
        let owner = NativeDirectCallRoomFlowOwnerSpy()
        owner.isListenerStarted = true
        owner.activeSession = directCallSession()
        setupRoomFlowCoordinator { roomProxy in
            #expect(roomProxy.id == "1")
            owner.makeCount += 1
            return owner
        }

        try await process(route: .room(roomID: "1", via: []))

        for command in NativeDirectCallRoomDiagnosticCommand.allTestCases {
            let result = await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(command)
            #expect(result == .failed(.disabled))
        }
        #expect(roomFlowCoordinator.nativeDirectCallDiagnosticStatus() == .disabled)

        #expect(owner.makeCount == 1)
        #expect(owner.prepareCount == 0)
        #expect(owner.startCount == 0)
        #expect(owner.outgoingCount == 0)
        #expect(owner.acceptCount == 0)
        #expect(owner.hangupCount == 0)
        #expect(owner.stopCount == 0)
        #expect(owner.resetCount == 0)
    }

    @Test
    func nativeDirectCallDiagnosticCommandEntryDelegatesExplicitCommandsOnly() async throws {
        let owner = NativeDirectCallRoomFlowOwnerSpy()
        let session = directCallSession()
        owner.diagnosticSnapshot = .init(activeSessionPhase: .outgoingRinging,
                                         lastSignalEventEmitted: .invite,
                                         lastSignalSendAttempted: true,
                                         lastSignalSendSucceeded: true)
        owner.outgoingResult = .success(session)
        owner.acceptResult = .success(session)
        owner.hangupResult = .success(session)
        setupRoomFlowCoordinator(nativeDirectCallDiagnosticCommandConfiguration: .init(isEnabled: true)) { roomProxy in
            #expect(roomProxy.id == "1")
            owner.makeCount += 1
            return owner
        }

        try await process(route: .room(roomID: "1", via: []))

        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.prepare) == .failed(.owner(.disabled)))
        #expect(owner.prepareCount == 1)
        #expect(owner.startCount == 0)

        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.startOutgoingAudioCall) == .outgoingStarted(.init(session)))
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.acceptIncomingCall) == .incomingAccepted(.init(session)))
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.hangup) == .hungUp(.init(session)))
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.startListener) == .failed(.owner(.disabled)))
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.stop) == .stopped)
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.reset) == .reset)
        let status = roomFlowCoordinator.nativeDirectCallDiagnosticStatus()
        #expect(status.state == .idle)
        #expect(status.activeSessionPhase == .outgoingRinging)
        #expect(status.lastSignalEventEmitted == .invite)
        #expect(status.lastSignalSendAttempted)
        #expect(status.lastSignalSendSucceeded == true)

        #expect(owner.startCount == 1)
        #expect(owner.outgoingCount == 1)
        #expect(owner.acceptCount == 1)
        #expect(owner.hangupCount == 1)
        #expect(owner.stopCount == 1)
        #expect(owner.resetCount == 1)
    }

    @Test
    func nativeDirectCallDiagnosticCommandEntryFailsClosedWhileOwnerIsResetting() async throws {
        let controller = NativeDirectCallRoomControllingSpy()
        controller.suspendReset = true
        let roomProxy = NativeDirectCallProvidingJoinedRoomProxyMock(controller: controller)
        let owner = NativeDirectCallRoomFlowOwner(roomProxy: roomProxy,
                                                  triggerConfiguration: .init(isEnabled: true))
        setupRoomFlowCoordinator(nativeDirectCallDiagnosticCommandConfiguration: .init(isEnabled: true)) { _ in
            owner
        }

        try await process(route: .room(roomID: "1", via: []))

        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.prepare) == .failed(.owner(.trigger(.control(.noActiveCall)))))
        owner.beginReset()
        await Task.yield()

        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.startListener) == .failed(.owner(.resetting)))
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.startOutgoingAudioCall) == .failed(.owner(.resetting)))
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.acceptIncomingCall) == .failed(.owner(.resetting)))
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.hangup) == .failed(.owner(.resetting)))
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.prepare) == .failed(.owner(.resetting)))
        #expect(roomFlowCoordinator.nativeDirectCallDiagnosticStatus().state == .resetting)

        controller.resumeReset()
        #expect(await roomFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.reset) == .reset)
        #expect(controller.stopCount == 1)
        #expect(controller.resetCount == 1)
    }
    
    @Test
    func nativeDirectCallUITestDiagnosticSignalEncodesRedactedCommandAndResult() throws {
        let command = UITestsSignal.NativeDirectCallDiagnosticCommandRequest(command: .startOutgoingAudioCall,
                                                                             correlationID: "call-A-1")
        let result = UITestsSignal.NativeDirectCallDiagnosticResult.success(.outgoingStarted,
                                                                            correlationID: "call-A-1")
        let failureResult = UITestsSignal.NativeDirectCallDiagnosticResult.failure(.engineFailure,
                                                                                   correlationID: "call-A-1",
                                                                                   reason: .e2eeUnavailable)
        let commandSignal = UITestsSignal.nativeDirectCallDiagnostic(command)
        let resultSignal = UITestsSignal.nativeDirectCallDiagnosticResult(result)
        let failureResultSignal = UITestsSignal.nativeDirectCallDiagnosticResult(failureResult)
        let statusRequest = UITestsSignal.NativeDirectCallDiagnosticStatusRequest(correlationID: "call-A-1")
        let statusResult = UITestsSignal.NativeDirectCallDiagnosticStatusResult(correlationID: "call-A-1",
                                                                                status: .init(state: .active,
                                                                                              listenerStarted: true,
                                                                                              hasActiveSession: true,
                                                                                              activeSessionPhase: .outgoingRinging,
                                                                                              lastSignalEventEmitted: .invite,
                                                                                              lastSignalSendAttempted: true,
                                                                                              lastSignalSendSucceeded: true))
        let statusSignal = UITestsSignal.nativeDirectCallDiagnosticStatus(statusRequest)
        let statusResultSignal = UITestsSignal.nativeDirectCallDiagnosticStatusResult(statusResult)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encodedCommand = try #require(String(data: encoder.encode(commandSignal), encoding: .utf8))
        let encodedResult = try #require(String(data: encoder.encode(resultSignal), encoding: .utf8))
        let encodedFailureResult = try #require(String(data: encoder.encode(failureResultSignal), encoding: .utf8))
        let encodedStatus = try #require(String(data: encoder.encode(statusSignal), encoding: .utf8))
        let encodedStatusResult = try #require(String(data: encoder.encode(statusResultSignal), encoding: .utf8))

        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedCommand.utf8)) == commandSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedResult.utf8)) == resultSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedFailureResult.utf8)) == failureResultSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedStatus.utf8)) == statusSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedStatusResult.utf8)) == statusResultSignal)
        #expect(encodedCommand.contains("startOutgoingAudioCall"))
        #expect(encodedResult.contains("outgoingStarted"))
        #expect(encodedFailureResult.contains("e2eeUnavailable"))
        #expect(encodedStatus.contains("nativeDirectCallDiagnosticStatus"))
        #expect(encodedStatusResult.contains("hasActiveSession"))
        #expect(encodedStatusResult.contains("lastSignalEventEmitted"))
        #expect(encodedStatusResult.contains("lastSignalSendAttempted"))
        #expect(encodedStatusResult.contains("lastSignalSendSucceeded"))
        #expect(encodedStatusResult.contains("activeSessionPhase"))
        #expect(result.correlationID == command.correlationID)
        #expect(failureResult.correlationID == command.correlationID)
        #expect(statusResult.correlationID == statusRequest.correlationID)

        let forbiddenFragments = [
            "debug" + "Info",
            "original" + "JSON",
            "original" + "Json",
            "raw " + "JSON",
            "encrypted_" + "payload",
            "to" + "ken",
            "j" + "wt",
            "raw " + "key",
            "livekit.example.com"
        ]
        let combinedSignals = encodedCommand + encodedResult + encodedFailureResult + encodedStatus + encodedStatusResult
        for fragment in forbiddenFragments {
            #expect(combinedSignals.localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test
    func nativeDirectCallUITestDiagnosticCorrelationIdentifiesStaleResults() {
        let request = UITestsSignal.NativeDirectCallDiagnosticCommandRequest(command: .hangup,
                                                                             correlationID: "call-A-1")
        let staleResult = UITestsSignal.NativeDirectCallDiagnosticResult.success(.hungUp,
                                                                                 correlationID: "call-B-1")

        #expect(request.correlationID == "call-A-1")
        #expect(staleResult.correlationID == "call-B-1")
        #expect(staleResult.correlationID != request.correlationID)
    }

    @Test
    func nativeDirectCallIntegrationDiagnosticGateRequiresExplicitIntegrationEnvironment() {
        let disabledEnvironments: [[String: String]] = [
            [:],
            ["IS_RUNNING_INTEGRATION_TESTS": "1"],
            ["NATIVE_DIRECT_CALL_DIAGNOSTICS": "1"],
            [
                "UI_TESTS_SCREEN": "userSessionScreen",
                "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
                "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1"
            ],
            [
                "IS_RUNNING_INTEGRATION_TESTS": "0",
                "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
                "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1"
            ],
            [
                "IS_RUNNING_INTEGRATION_TESTS": "1",
                "NATIVE_DIRECT_CALL_DIAGNOSTICS": "0",
                "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1"
            ]
        ]

        for environment in disabledEnvironments {
            #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationHarnessEnabled(environment: environment) == false)
            #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: environment) == false)
            #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: environment) == false)
        }

        let harnessOnlyEnvironment = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1"
        ]
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationHarnessEnabled(environment: harnessOnlyEnvironment) == true)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: harnessOnlyEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: harnessOnlyEnvironment) == false)

        let commandsEnabledEnvironment = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1"
        ]
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationHarnessEnabled(environment: commandsEnabledEnvironment) == true)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: commandsEnabledEnvironment) == true)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: commandsEnabledEnvironment) == false)

        var encryptionEnvironment = commandsEnabledEnvironment
        encryptionEnvironment[NativeDirectCallDiagnosticEncryptionService.encryptionGateEnvironmentKey] = "1"
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: encryptionEnvironment) == false)
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticEncryptionService(ownUserID: "hi@bob",
                                                                               environment: encryptionEnvironment) == nil)

        encryptionEnvironment[NativeDirectCallDiagnosticEncryptionService.secretEnvironmentKey] = ""
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: encryptionEnvironment) == false)

        encryptionEnvironment[NativeDirectCallDiagnosticEncryptionService.secretEnvironmentKey] = "diagnostic-shared-secret"
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: encryptionEnvironment) == true)
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticEncryptionService(ownUserID: "hi@bob",
                                                                               environment: encryptionEnvironment) != nil)
    }

    @Test
    func uiTestsSignallingFileURLUsesOptionalSanitizedChannel() {
        let defaultURL = UITestsSignalling.Client.fileURL(deviceName: "iPhone 17",
                                                          environment: [:])
        let channelURL = UITestsSignalling.Client.fileURL(deviceName: "iPhone 17",
                                                          environment: [UITestsSignalling.channelEnvironmentKey: "A"])
        let sanitizedChannelURL = UITestsSignalling.Client.fileURL(deviceName: "iPhone 17",
                                                                   environment: [UITestsSignalling.channelEnvironmentKey: "Client A / stale:1"])

        #expect(defaultURL.path() == "/Users/Shared/UITestsSignalling-iPhone-17")
        #expect(channelURL.path() == "/Users/Shared/UITestsSignalling-iPhone-17-A")
        #expect(sanitizedChannelURL.path() == "/Users/Shared/UITestsSignalling-iPhone-17-Client-A-stale-1")
    }

    @Test
    func nativeDirectCallUITestDiagnosticSignalMapsToRedactedResult() {
        #expect(UITestsSignal.NativeDirectCallDiagnosticCommandRequest.prepare.roomFlowCommand == .prepare)
        #expect(UITestsSignal.NativeDirectCallDiagnosticCommandRequest.startListener.roomFlowCommand == .startListener)
        #expect(UITestsSignal.NativeDirectCallDiagnosticCommandRequest.startOutgoingAudioCall.roomFlowCommand == .startOutgoingAudioCall)
        #expect(UITestsSignal.NativeDirectCallDiagnosticCommandRequest.acceptIncomingCall.roomFlowCommand == .acceptIncomingCall)
        #expect(UITestsSignal.NativeDirectCallDiagnosticCommandRequest.hangup.roomFlowCommand == .hangup)
        #expect(UITestsSignal.NativeDirectCallDiagnosticCommandRequest.stop.roomFlowCommand == .stop)
        #expect(UITestsSignal.NativeDirectCallDiagnosticCommandRequest.reset.roomFlowCommand == .reset)
        #expect(UITestsSignal.NativeDirectCallDiagnosticResult(.outgoingStarted(.init(directCallSession()))).outcome == .success(.outgoingStarted))
        #expect(UITestsSignal.NativeDirectCallDiagnosticResult(.failed(.disabled)).outcome == .failure(.disabled))
        #expect(UITestsSignal.NativeDirectCallDiagnosticResult(.failed(.unavailable)).outcome == .failure(.unavailable))
        #expect(UITestsSignal.NativeDirectCallDiagnosticResult(.failed(.owner(.resetting))).outcome == .failure(.resetting))
        #expect(UITestsSignal.NativeDirectCallDiagnosticResult(.failed(.owner(.trigger(.disabled)))).outcome == .failure(.triggerDisabled))
        #expect(UITestsSignal.NativeDirectCallDiagnosticResult(.failed(.owner(.trigger(.control(.noActiveCall))))).outcome == .failure(.noActiveCall))
        let e2eeFailure = UITestsSignal.NativeDirectCallDiagnosticResult(.failed(.owner(.trigger(.control(.engine(.invalidEncryptionTransition))))))
        #expect(e2eeFailure.outcome == .failure(.engineFailure))
        #expect(e2eeFailure.reason == .e2eeUnavailable)
        #expect(UITestsSignal.NativeDirectCallDiagnosticStatusResult(.init(state: .active,
                                                                           listenerStarted: true,
                                                                           hasActiveSession: true,
                                                                           diagnosticSnapshot: .init(activeSessionPhase: .outgoingRinging,
                                                                                                     lastSignalEventEmitted: .invite,
                                                                                                     lastSignalSendAttempted: true,
                                                                                                     lastSignalSendSucceeded: true))).status.activeSessionPhase == .outgoingRinging)
    }

    // MARK: - Spaces
    
    @Test
    func spacePermalink() async throws {
        setupRoomFlowCoordinator()
        
        try await process(route: .room(roomID: "1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        
        try await process(route: .childRoom(roomID: "space1", via: []))
        #expect(navigationStackCoordinator.rootCoordinator is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.stackCoordinators.first is SpaceScreenCoordinator)
    }
    
    // MARK: - Private
    
    private func process(route: AppRoute) async throws {
        roomFlowCoordinator.handleAppRoute(route, animated: true)
        // A single yield isn't enough when creating the new flow coordinator.
        try await Task.sleep(for: .milliseconds(100))
    }
    
    private func clearRoute(expectedActions: [RoomFlowCoordinatorAction]) async throws {
        try await processRouteOrClear(route: nil, expectedActions: expectedActions)
    }
    
    private func process(route: AppRoute, expectedActions: [RoomFlowCoordinatorAction]) async throws {
        try await processRouteOrClear(route: route, expectedActions: expectedActions)
    }
    
    private func processRouteOrClear(route: AppRoute?, expectedActions: [RoomFlowCoordinatorAction]) async throws {
        guard !expectedActions.isEmpty else {
            return
        }
        
        var fulfillments = [DeferredFulfillment<RoomFlowCoordinatorAction>]()
        
        for expectedAction in expectedActions {
            fulfillments.append(deferFulfillment(roomFlowCoordinator.actions) { action in
                action == expectedAction
            })
        }
        
        if let route {
            roomFlowCoordinator.handleAppRoute(route, animated: true)
        } else {
            roomFlowCoordinator.clearRoute(animated: true)
        }
        
        for fulfillment in fulfillments {
            try await fulfillment.fulfill()
        }
    }
    
    private func setupRoomFlowCoordinator(asChildFlow: Bool = false,
                                          roomType: RoomType? = nil,
                                          nativeDirectCallDiagnosticCommandConfiguration: NativeDirectCallRoomDeveloperCommandConfiguration = .init(),
                                          nativeDirectCallRoomFlowOwnerFactory: @escaping @MainActor (JoinedRoomProxyProtocol) -> NativeDirectCallRoomFlowOwning = { roomProxy in
                                              NativeDirectCallRoomFlowOwner(roomProxy: roomProxy)
                                          }) {
        cancellables.removeAll()
        clientProxy = ClientProxyMock(.init(userID: "hi@bob",
                                            roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(.mockRooms))),
                                            spaceServiceConfiguration: .populated))
        timelineControllerFactory = TimelineControllerFactoryMock(.init())
        
        clientProxy.roomPreviewForIdentifierViaClosure = { [roomType] roomID, _ in
            switch roomType {
            case .invited:
                return .success(RoomPreviewProxyMock.invited(roomID: roomID))
            default:
                fatalError("Something isn't set up right")
            }
        }
        
        let navigationSplitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: false))
        navigationStackCoordinator = NavigationStackCoordinator()
        navigationSplitCoordinator.setDetailCoordinator(navigationStackCoordinator)
        
        let roomID = switch roomType {
        case .invited(let roomID):
            roomID
        default:
            "1"
        }
        
        let flowParameters = CommonFlowParameters(userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                                  bugReportService: BugReportServiceMock(.init()),
                                                  elementCallService: ElementCallServiceMock(.init()),
                                                  directCallEngine: DirectCallEngine(ownUserID: "hi@bob") { _ in nil },
                                                  timelineControllerFactory: timelineControllerFactory,
                                                  emojiProvider: EmojiProvider(appSettings: ServiceLocator.shared.settings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  appMediator: AppMediatorMock.default,
                                                  appSettings: ServiceLocator.shared.settings,
                                                  appHooks: AppHooks(),
                                                  analytics: ServiceLocator.shared.analytics,
                                                  userIndicatorController: ServiceLocator.shared.userIndicatorController,
                                                  notificationManager: NotificationManagerMock(),
                                                  stateMachineFactory: StateMachineFactory())
        
        roomFlowCoordinator = RoomFlowCoordinator(roomID: roomID,
                                                  isChildFlow: asChildFlow,
                                                  navigationStackCoordinator: navigationStackCoordinator,
                                                  flowParameters: flowParameters,
                                                  nativeDirectCallRoomFlowOwnerFactory: nativeDirectCallRoomFlowOwnerFactory)
        roomFlowCoordinator.nativeDirectCallDiagnosticCommandConfiguration = nativeDirectCallDiagnosticCommandConfiguration
    }

    private func expectFailure<T>(_ result: Result<T, NativeDirectCallRoomFlowOwnerError>,
                                  _ expectedError: NativeDirectCallRoomFlowOwnerError) {
        guard case .failure(let error) = result else {
            Issue.record("Expected native direct-call room-flow owner failure: \(expectedError).")
            return
        }

        #expect(error == expectedError)
    }

    private func expectFailure<T>(_ result: Result<T, NativeDirectCallRoomDeveloperCommandError>,
                                  _ expectedError: NativeDirectCallRoomDeveloperCommandError) {
        guard case .failure(let error) = result else {
            Issue.record("Expected native direct-call developer command failure: \(expectedError).")
            return
        }

        #expect(error == expectedError)
    }

    private func expectSuccess<T>(_ result: Result<T, NativeDirectCallRoomDeveloperCommandError>) {
        guard case .failure(let error) = result else {
            return
        }

        Issue.record("Expected native direct-call developer command success, got: \(error).")
    }

    private func directCallSession() -> DirectCallSession {
        DirectCallSession(callID: "call-1",
                          roomID: "room-1",
                          peerUserID: "@alice:example.com",
                          direction: .incoming,
                          intent: .audio,
                          encryptionMode: .e2eeRequired,
                          startedAt: .now,
                          updatedAt: .now,
                          state: .activeAudio,
                          encryptionState: .ready)
    }
}

private enum RoomType {
    case invited(roomID: String)
}

private extension NativeDirectCallRoomDiagnosticCommand {
    static let allTestCases: [Self] = [
        .prepare,
        .startListener,
        .startOutgoingAudioCall,
        .acceptIncomingCall,
        .hangup,
        .stop,
        .reset
    ]
}

@MainActor
private final class NativeDirectCallRoomFlowOwnerSpy: NativeDirectCallRoomFlowOwning {
    var makeCount = 0
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var outgoingCount = 0
    private(set) var acceptCount = 0
    private(set) var hangupCount = 0
    private(set) var stopCount = 0
    private(set) var resetCount = 0
    private(set) var resetCompletionCount = 0
    var suspendReset = false
    private var resetTask: Task<Void, Never>?
    private var resetContinuation: CheckedContinuation<Void, Never>?

    var isListenerStarted = false
    var activeSession: DirectCallSession?
    var isResetting = false
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot = .empty
    var outgoingResult: Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> = .failure(.disabled)
    var acceptResult: Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> = .failure(.disabled)
    var hangupResult: Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> = .failure(.disabled)

    func prepare() -> Result<NativeDirectCallComposition, NativeDirectCallRoomFlowOwnerError> {
        prepareCount += 1
        return .failure(.disabled)
    }

    func startListener() async -> Result<NativeDirectCallComposition, NativeDirectCallRoomFlowOwnerError> {
        startCount += 1
        return .failure(.disabled)
    }

    func startOutgoingAudioCall() async -> Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> {
        outgoingCount += 1
        return outgoingResult
    }

    func acceptIncomingCall() async -> Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> {
        acceptCount += 1
        return acceptResult
    }

    func hangup() async -> Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> {
        hangupCount += 1
        return hangupResult
    }

    func stop() {
        stopCount += 1
    }

    func beginReset() {
        isResetting = true
        stop()
        guard resetTask == nil else {
            return
        }

        resetTask = Task { @MainActor in
            await reset()
            resetTask = nil
        }
    }

    func reset() async {
        resetCount += 1
        guard suspendReset else {
            isResetting = false
            return
        }

        await withCheckedContinuation { continuation in
            resetContinuation = continuation
        }
        isResetting = false
        resetCompletionCount += 1
    }

    func resumeReset() {
        resetContinuation?.resume()
        resetContinuation = nil
    }
}

@MainActor
private final class NativeDirectCallProvidingJoinedRoomProxyMock: JoinedRoomProxyMock, NativeDirectCallRoomControllerProviding, @unchecked Sendable {
    private let controller: NativeDirectCallRoomControlling
    private(set) var makeNativeDirectCallRoomControllerCount = 0

    init(controller: NativeDirectCallRoomControlling) {
        self.controller = controller
        super.init()
    }

    func makeNativeDirectCallRoomController(configuration _: NativeDirectCallCompositionConfiguration,
                                            mediaEngineFactory _: DirectCallMediaEngineFactoryProtocol?,
                                            encryptionService _: DirectCallEncryptionServiceProtocol?,
                                            now _: @escaping () -> Date) -> NativeDirectCallRoomControlling {
        makeNativeDirectCallRoomControllerCount += 1
        return controller
    }
}

@MainActor
private final class NativeDirectCallRoomControllingSpy: NativeDirectCallRoomControlling {
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var outgoingCount = 0
    private(set) var acceptCount = 0
    private(set) var hangupCount = 0
    private(set) var stopCount = 0
    private(set) var resetCount = 0
    var suspendReset = false
    private var resetContinuation: CheckedContinuation<Void, Never>?

    var isListenerStarted = false
    var activeSession: DirectCallSession?
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot = .empty

    func prepare() -> Result<NativeDirectCallComposition, NativeDirectCallRoomControlError> {
        prepareCount += 1
        return .failure(.noActiveCall)
    }

    func start() async -> Result<NativeDirectCallComposition, NativeDirectCallRoomControlError> {
        startCount += 1
        return .failure(.noActiveCall)
    }

    func startOutgoingAudioCall() async -> Result<DirectCallSession, NativeDirectCallRoomControlError> {
        outgoingCount += 1
        return .failure(.noActiveCall)
    }

    func acceptIncomingCall() async -> Result<DirectCallSession, NativeDirectCallRoomControlError> {
        acceptCount += 1
        return .failure(.noActiveCall)
    }

    func hangup() async -> Result<DirectCallSession, NativeDirectCallRoomControlError> {
        hangupCount += 1
        return .failure(.noActiveCall)
    }

    func stop() {
        stopCount += 1
    }

    func reset() async {
        resetCount += 1
        guard suspendReset else {
            return
        }

        await withCheckedContinuation { continuation in
            resetContinuation = continuation
        }
    }

    func resumeReset() {
        resetContinuation?.resume()
        resetContinuation = nil
    }
}
