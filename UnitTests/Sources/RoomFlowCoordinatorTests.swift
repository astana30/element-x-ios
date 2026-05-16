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
import MatrixRustSDK
import MatrixRustSDKMocks
import Testing

@MainActor
// swiftlint:disable:next type_body_length
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

        // swiftlint:disable:next trailing_closure
        setupRoomFlowCoordinator(nativeDirectCallRoomFlowOwnerFactory: { roomProxy in
            #expect(roomProxy.id == "1")
            owner.makeCount += 1
            return owner
        })

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
    func nativeDirectCallProductionActivationDryRunFailsClosedWithoutActiveRoom() async {
        setupRoomFlowCoordinator { _ in
            Issue.record("Native direct-call room-flow owner should not be created without an active room.")
            return NativeDirectCallRoomFlowOwnerSpy()
        } nativeDirectCallProductionActivationDryRunProviderFactory: { _ in
            Issue.record("Production activation dry-run provider should not be created without an active room.")
            return FailClosedNativeDirectCallProductionActivationDryRunProvider()
        }

        let diagnostic = await roomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()

        #expect(diagnostic == .disabled(.roomUnavailable))
    }

    @Test
    func nativeDirectCallProductionActivationDryRunDelegatesForActiveRoomWithoutStartingCalls() async throws {
        let owner = NativeDirectCallRoomFlowOwnerSpy()
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: .init(isEnabled: true,
                                                                                           disabledReason: nil,
                                                                                           isCapabilityPresent: true,
                                                                                           areDependenciesReady: true,
                                                                                           isRoomEligible: true,
                                                                                           isEndpointAccepted: true))
        setupRoomFlowCoordinator { roomProxy in
            #expect(roomProxy.id == "1")
            owner.makeCount += 1
            return owner
        } nativeDirectCallProductionActivationDryRunProviderFactory: { roomProxy in
            #expect(roomProxy.id == "1")
            provider.makeCount += 1
            return provider
        }

        try await process(route: .room(roomID: "1", via: []))
        let diagnostic = await roomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()

        #expect(diagnostic.isEnabled)
        #expect(provider.makeCount == 1)
        #expect(provider.callCount == 1)
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
    func nativeDirectCallProductionActivationDryRunCanUseDecisionServiceForRoom() async throws {
        let decisionService = DirectCallProductionActivationDecisionService(configuration: DirectCallProductionConfiguration(isEnabled: true),
                                                                            capabilityProvider: StaticDirectCallProductionCapabilityProvider(capability: nil),
                                                                            dependencyProvider: NativeDirectCallProductionDependencyProviderSpy(dependencies: .disabled))
        let roomEligibility = DirectCallProductionRoomEligibility(isDirect: true,
                                                                  isEncrypted: true,
                                                                  joinedMemberCount: 2,
                                                                  hasPeerUserID: true)
        let provider = NativeDirectCallProductionActivationDryRunProvider(activationDryRunDiagnostics: decisionService,
                                                                          homeserverBaseURL: URL(string: "https://matrix.example.test"),
                                                                          roomEligibility: roomEligibility)
        let providerFactory: @MainActor (JoinedRoomProxyProtocol) -> NativeDirectCallProductionActivationDryRunProviding = { _ in provider }
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: providerFactory)

        try await process(route: .room(roomID: "1", via: []))
        let diagnostic = await roomFlowCoordinator.nativeDirectCallProductionActivationDryRunDiagnostic()

        #expect(diagnostic.isEnabled == false)
        #expect(diagnostic.disabledReason == .serverCapabilityUnavailable)
        #expect(diagnostic.isCapabilityPresent == false)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted == false)
    }

    @Test
    func nativeDirectCallProductionActivationDryRunRuntimeFakeIsDisabledByDefault() async {
        let roomProxy = makeEligibleNativeDirectCallRoomProxy()
        let provider = AppCoordinator.makeNativeDirectCallProductionActivationDryRunProvider(roomProxy: roomProxy,
                                                                                             homeserver: "https://matrix.example.test",
                                                                                             environment: [:])

        let diagnostic = await provider.nativeDirectCallProductionActivationDryRunDiagnostic()

        #expect(diagnostic.isEnabled == false)
        #expect(diagnostic.disabledReason == .appRolloutDisabled)
        #expect(diagnostic.isCapabilityPresent == false)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted == false)
    }

    @Test
    func nativeDirectCallProductionActivationDryRunRuntimeFakeCanEnableEligibleRoomWithoutStartingCalls() async {
        let roomProxy = makeEligibleNativeDirectCallRoomProxy()
        let clientProxy = makeVerifiedPeerClientProxy()
        let provider = AppCoordinator.makeNativeDirectCallProductionActivationDryRunProvider(roomProxy: roomProxy,
                                                                                             homeserver: "https://matrix.example.test",
                                                                                             clientProxy: clientProxy,
                                                                                             environment: makeProductionDryRunFakeEnabledEnvironment())

        let diagnostic = await provider.nativeDirectCallProductionActivationDryRunDiagnostic()

        #expect(diagnostic.isEnabled)
        #expect(diagnostic.disabledReason == nil)
        #expect(diagnostic.isCapabilityPresent)
        #expect(diagnostic.areDependenciesReady)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted)
        #expect(diagnostic.isPeerTrustReady)
        #expect(String(describing: diagnostic).contains("matrix.example.test") == false)
        #expect(String(describing: diagnostic).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
    }

    @Test
    func nativeDirectCallProductionActivationDryRunRuntimeFakeFailsClosedWithoutPeerTrust() async {
        let roomProxy = makeEligibleNativeDirectCallRoomProxy()
        let provider = AppCoordinator.makeNativeDirectCallProductionActivationDryRunProvider(roomProxy: roomProxy,
                                                                                             homeserver: "https://matrix.example.test",
                                                                                             environment: makeProductionDryRunFakeEnabledEnvironment())

        let diagnostic = await provider.nativeDirectCallProductionActivationDryRunDiagnostic()

        #expect(diagnostic.isEnabled == false)
        #expect(diagnostic.disabledReason == .peerTrustUnavailable)
        #expect(diagnostic.isCapabilityPresent)
        #expect(diagnostic.areDependenciesReady)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted)
        #expect(diagnostic.isPeerTrustReady == false)
        #expect(diagnostic.peerTrustReadiness == .peerTrustUnavailable)
    }

    @Test
    func nativeDirectCallProductionTriggerDryRunFailsClosedWithoutActiveRoom() async {
        setupRoomFlowCoordinator { _ in
            Issue.record("Native direct-call room-flow owner should not be created without an active room.")
            return NativeDirectCallRoomFlowOwnerSpy()
        } nativeDirectCallProductionActivationDryRunProviderFactory: { _ in
            Issue.record("Production trigger dry-run provider should not be created without an active room.")
            return FailClosedNativeDirectCallProductionActivationDryRunProvider()
        }

        let diagnostic = await roomFlowCoordinator.nativeDirectCallProductionTriggerDryRunDiagnostic()

        #expect(diagnostic.wouldStart == false)
        #expect(diagnostic.isEnabled == false)
        #expect(diagnostic.blockedReason == .roomUnavailable)
        #expect(diagnostic.isCapabilityPresent == false)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(diagnostic.isRoomEligible == false)
        #expect(diagnostic.isEndpointAccepted == false)
    }

    @Test
    func nativeDirectCallProductionTriggerDryRunBlocksWhenActivationDisabledWithoutStartingCalls() async throws {
        let owner = NativeDirectCallRoomFlowOwnerSpy()
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: .disabled(.appRolloutDisabled))
        setupRoomFlowCoordinator { roomProxy in
            #expect(roomProxy.id == "1")
            owner.makeCount += 1
            return owner
        } nativeDirectCallProductionActivationDryRunProviderFactory: { roomProxy in
            #expect(roomProxy.id == "1")
            provider.makeCount += 1
            return provider
        }

        try await process(route: .room(roomID: "1", via: []))
        let diagnostic = await roomFlowCoordinator.nativeDirectCallProductionTriggerDryRunDiagnostic()

        #expect(diagnostic.wouldStart == false)
        #expect(diagnostic.isEnabled == false)
        #expect(diagnostic.blockedReason == .appRolloutDisabled)
        #expect(provider.makeCount == 1)
        #expect(provider.callCount == 1)
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
    func nativeDirectCallProductionTriggerDryRunWouldStartWhenActivationEnabledWithoutStartingCalls() async throws {
        let owner = NativeDirectCallRoomFlowOwnerSpy()
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: .init(isEnabled: true,
                                                                                           disabledReason: nil,
                                                                                           isCapabilityPresent: true,
                                                                                           areDependenciesReady: true,
                                                                                           isRoomEligible: true,
                                                                                           isEndpointAccepted: true))
        setupRoomFlowCoordinator { roomProxy in
            #expect(roomProxy.id == "1")
            owner.makeCount += 1
            return owner
        } nativeDirectCallProductionActivationDryRunProviderFactory: { roomProxy in
            #expect(roomProxy.id == "1")
            provider.makeCount += 1
            return provider
        }

        try await process(route: .room(roomID: "1", via: []))
        let diagnostic = await roomFlowCoordinator.nativeDirectCallProductionTriggerDryRunDiagnostic()

        #expect(diagnostic.wouldStart)
        #expect(diagnostic.isEnabled)
        #expect(diagnostic.blockedReason == nil)
        #expect(diagnostic.isCapabilityPresent)
        #expect(diagnostic.areDependenciesReady)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted)
        #expect(String(describing: diagnostic).contains("matrix.example.test") == false)
        #expect(String(describing: diagnostic).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
        #expect(provider.makeCount == 1)
        #expect(provider.callCount == 1)
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
    func nativeDirectCallProductionStartBlocksWithoutDedicatedGate() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.outgoingResult = .success(directCallSession(direction: .outgoing, state: .outgoingRinging))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: false)

        #expect(result.didStart == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .productionStartDisabled)
        #expect(result.triggerDiagnostic.isEnabled)
        #expect(provider.callCount == 1)
        #expect(productionOwner.outgoingCount == 0)
    }

    @Test
    func nativeDirectCallProductionStartBlocksWhenActivationDisabled() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: .disabled(.appRolloutDisabled))
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .appRolloutDisabled)
        #expect(result.triggerDiagnostic.isEnabled == false)
        #expect(provider.callCount == 1)
        #expect(productionOwner.outgoingCount == 0)
    }

    @Test
    func nativeDirectCallProductionStartBlocksBeforeOwnerWhenPeerTrustIsNotReady() async throws {
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: .init(isEnabled: false,
                                                                                           disabledReason: .unverifiedDevice,
                                                                                           isCapabilityPresent: true,
                                                                                           areDependenciesReady: true,
                                                                                           isRoomEligible: true,
                                                                                           isEndpointAccepted: true,
                                                                                           peerTrustReadiness: .unverifiedDevice,
                                                                                           keyWrapperSource: .providerWrapper))
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in
                                     Issue.record("Production owner should not be created when peer trust is not ready.")
                                     return .owner(NativeDirectCallRoomFlowOwnerSpy())
                                 })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .unverifiedDevice)
        #expect(result.triggerDiagnostic.isPeerTrustReady == false)
        #expect(result.triggerDiagnostic.peerTrustReadiness == .unverifiedDevice)
        #expect(provider.callCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartBlocksWhenProductionOwnerUnavailable() async throws {
        let diagnosticOwner = NativeDirectCallRoomFlowOwnerSpy()
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator { _ in
            diagnosticOwner
        } nativeDirectCallProductionActivationDryRunProviderFactory: { _ in
            provider
        }

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .productionOwnerUnavailable)
        #expect(diagnosticOwner.outgoingCount == 0)
        #expect(provider.callCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartBlocksWhenProductionDependenciesUnavailable() async throws {
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .blocked(.dependenciesUnavailable) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .dependenciesUnavailable)
        #expect(provider.callCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartBlocksWhenActiveSessionExists() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.activeSession = directCallSession(direction: .outgoing, state: .outgoingRinging)
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .activeSessionExists)
        #expect(productionOwner.outgoingCount == 0)
        #expect(provider.callCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartUsesProductionOwnerWhenGatesPass() async throws {
        let diagnosticOwner = NativeDirectCallRoomFlowOwnerSpy()
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.outgoingResult = .success(directCallSession(direction: .outgoing, state: .outgoingRinging))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator { _ in
            diagnosticOwner
        } nativeDirectCallProductionActivationDryRunProviderFactory: { _ in
            provider
        } nativeDirectCallProductionRoomFlowOwnerFactory: { _ in
            .owner(productionOwner)
        }

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart)
        #expect(result.outcome == .started)
        #expect(result.reason == nil)
        #expect(result.sessionSummary?.hasCallID == true)
        #expect(result.sessionSummary?.direction == "outgoing")
        #expect(result.sessionSummary?.intent == "audio")
        #expect(productionOwner.outgoingCount == 1)
        #expect(productionOwner.startCount == 0)
        #expect(diagnosticOwner.outgoingCount == 0)
        #expect(provider.callCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartListenerCreatesOwnerAndStartsOnlyListener() async throws {
        let diagnosticOwner = NativeDirectCallRoomFlowOwnerSpy()
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.startResult = .success(nativeDirectCallComposition())
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallDiagnosticCommandConfiguration: .init(isEnabled: true)) { _ in
            diagnosticOwner
        } nativeDirectCallProductionActivationDryRunProviderFactory: { _ in
            provider
        } nativeDirectCallProductionRoomFlowOwnerFactory: { _ in
            .owner(productionOwner)
        }

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartListener()
        let status = roomFlowCoordinator.nativeDirectCallProductionStatus()
        let diagnosticStatus = roomFlowCoordinator.nativeDirectCallDiagnosticStatus()

        #expect(result.didStartListener)
        #expect(result.outcome == .started)
        #expect(result.reason == nil)
        #expect(result.status.productionOwnerAvailable)
        #expect(result.status.productionListenerStarted)
        #expect(result.status.productionHasActiveSession == false)
        #expect(status.productionOwnerAvailable)
        #expect(status.productionListenerStarted)
        #expect(status.productionHasActiveSession == false)
        #expect(status.productionLastSignalSendAttempted == false)
        #expect(diagnosticStatus.state == .idle)
        #expect(diagnosticStatus.lastSignalSendAttempted == false)
        #expect(diagnosticOwner.startCount == 0)
        #expect(diagnosticOwner.outgoingCount == 0)
        #expect(productionOwner.startCount == 1)
        #expect(productionOwner.outgoingCount == 0)
        #expect(provider.callCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartListenerBlocksWhenActivationDisabled() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: .disabled(.appRolloutDisabled))
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartListener()

        #expect(result.didStartListener == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .appRolloutDisabled)
        #expect(result.status.productionOwnerAvailable == false)
        #expect(productionOwner.startCount == 0)
        #expect(productionOwner.outgoingCount == 0)
        #expect(provider.callCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartListenerReportsListenerFailure() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.startResult = .failure(.trigger(.control(.noActiveCall)))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartListener()

        #expect(result.didStartListener == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .listenerStartFailed)
        #expect(result.status.productionOwnerAvailable)
        #expect(result.status.productionListenerStarted == false)
        #expect(productionOwner.startCount == 1)
        #expect(productionOwner.outgoingCount == 0)
    }

    @Test
    func nativeDirectCallProductionStartListenerKeepsIncomingSessionVisible() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.activeSession = directCallSession(direction: .incoming, state: .incomingRinging)
        productionOwner.diagnosticSnapshot = .init(activeSessionPhase: .incomingRinging)
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartListener()

        #expect(result.didStartListener)
        #expect(result.status.productionHasActiveSession)
        #expect(result.status.productionSessionState == "incomingRinging")
        #expect(result.status.productionEncryptionState == "ready")
        #expect(productionOwner.startCount == 0)
        #expect(productionOwner.outgoingCount == 0)
    }

    @Test
    func nativeDirectCallProductionAcceptBlocksWhenOwnerUnavailable() async throws {
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator { roomProxy in
            NativeDirectCallRoomFlowOwner(roomProxy: roomProxy)
        } nativeDirectCallProductionActivationDryRunProviderFactory: { _ in
            provider
        }

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionAcceptIncomingCall()

        #expect(result.didAccept == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .productionOwnerUnavailable)
        #expect(result.status.productionOwnerAvailable == false)
    }

    @Test
    func nativeDirectCallProductionAcceptBlocksWithoutIncomingSession() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        _ = await roomFlowCoordinator.nativeDirectCallProductionStartListener()
        let result = await roomFlowCoordinator.nativeDirectCallProductionAcceptIncomingCall()

        #expect(result.didAccept == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .noIncomingCall)
        #expect(result.status.productionOwnerAvailable)
        #expect(productionOwner.acceptCount == 0)
    }

    @Test
    func nativeDirectCallProductionAcceptUsesProductionOwnerForIncomingSession() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        let acceptedSession = directCallSession(direction: .incoming, state: .connecting)
        productionOwner.isListenerStarted = true
        productionOwner.activeSession = directCallSession(direction: .incoming, state: .incomingRinging)
        productionOwner.acceptResult = .success(acceptedSession)
        productionOwner.updatesActiveSessionOnAcceptSuccess = true
        productionOwner.diagnosticSnapshot = .init(lastSignalEventEmitted: .answer,
                                                   lastSignalSendAttempted: true,
                                                   lastSignalSendSucceeded: true)
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        _ = await roomFlowCoordinator.nativeDirectCallProductionStartListener()
        let result = await roomFlowCoordinator.nativeDirectCallProductionAcceptIncomingCall()

        #expect(result.didAccept)
        #expect(result.outcome == .started)
        #expect(result.reason == nil)
        #expect(result.sessionSummary?.state == String(describing: DirectCallState.connecting))
        #expect(result.status.productionSessionState == String(describing: DirectCallState.connecting))
        #expect(result.status.productionLastSignalEventEmitted == .answer)
        #expect(result.status.productionLastSignalSendAttempted)
        #expect(result.status.productionLastSignalSendSucceeded == true)
        #expect(productionOwner.acceptCount == 1)
        #expect(productionOwner.outgoingCount == 0)
    }

    @Test
    func nativeDirectCallProductionAcceptReportsMediaTokenUnavailable() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.activeSession = directCallSession(direction: .incoming, state: .incomingRinging)
        productionOwner.acceptResult = .failure(.trigger(.control(.engine(.mediaConnectionFailed(.tokenUnavailable)))))
        productionOwner.diagnosticSnapshot = .init(lastSignalEventEmitted: .answer,
                                                   lastSignalSendAttempted: true,
                                                   lastSignalSendSucceeded: true,
                                                   mediaFactoryInjected: true,
                                                   mediaCredentialProviderAvailable: true,
                                                   mediaE2EEProviderAvailable: true,
                                                   mediaKeyHandleAvailable: true,
                                                   mediaConnectAttempted: true,
                                                   mediaFailureReason: .mediaTokenUnavailable)
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        _ = await roomFlowCoordinator.nativeDirectCallProductionStartListener()
        let result = await roomFlowCoordinator.nativeDirectCallProductionAcceptIncomingCall()

        #expect(result.didAccept == false)
        #expect(result.outcome == .engineFailure)
        #expect(result.reason == .mediaTokenUnavailable)
        #expect(result.status.productionLastSignalEventEmitted == .answer)
        #expect(result.status.productionLastSignalSendAttempted)
        #expect(result.status.productionLastSignalSendSucceeded == true)
        #expect(result.status.productionMediaConnectAttempted)
        #expect(result.status.productionMediaFailureReason == .mediaTokenUnavailable)
        #expect(String(describing: result).contains("participant_token") == false)
        #expect(String(describing: result).contains("encrypted_payload") == false)
        #expect(productionOwner.acceptCount == 1)
    }

    @Test
    func nativeDirectCallProductionStatusDoesNotCreateOwner() async throws {
        // swiftlint:disable trailing_closure
        setupRoomFlowCoordinator(nativeDirectCallProductionRoomFlowOwnerFactory: { _ in
            Issue.record("Production status must not create the production owner.")
            return .owner(NativeDirectCallRoomFlowOwnerSpy())
        })
        // swiftlint:enable trailing_closure

        try await process(route: .room(roomID: "1", via: []))
        let status = roomFlowCoordinator.nativeDirectCallProductionStatus()

        #expect(status.productionOwnerAvailable == false)
        #expect(status.productionListenerStarted == false)
        #expect(status.productionHasActiveSession == false)
        #expect(status.productionSessionState == "unavailable")
        #expect(status.productionLastSignalSendAttempted == false)
    }

    @Test
    func nativeDirectCallProductionStatusReportsRetainedOwnerAfterStart() async throws {
        let diagnosticOwner = NativeDirectCallRoomFlowOwnerSpy()
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.updatesActiveSessionOnOutgoingSuccess = true
        productionOwner.outgoingResult = .success(directCallSession(direction: .outgoing, state: .outgoingRinging))
        productionOwner.diagnosticSnapshot = .init(activeSessionPhase: .outgoingRinging,
                                                   lastSignalEventEmitted: .invite,
                                                   lastSignalSendAttempted: true,
                                                   lastSignalSendSucceeded: true,
                                                   listenerAttached: true,
                                                   listenerHandleRetained: true,
                                                   listenerStartCount: 1,
                                                   timelineUpdateCount: 1,
                                                   timelineDiffReceivedCount: 1,
                                                   lastTimelineDiffKind: .append,
                                                   lastTimelineDiffItemCount: 1,
                                                   timelineEventReceivedCount: 1,
                                                   directCallEventTypeSeenCount: 1,
                                                   envelopeExtractedCount: 1,
                                                   envelopeDeliveredToEngineCount: 1,
                                                   historicalEventIgnoredCount: 2,
                                                   liveEventDeliveredCount: 1,
                                                   baselineEstablished: true,
                                                   lastReceiveEventKind: .directCallInvite,
                                                   lastEnvelopeRejectedReason: .none,
                                                   lastReceiveFailureReason: nil,
                                                   sendRoomFingerprint: "send-room-redacted",
                                                   receiveRoomFingerprint: "receive-room-redacted",
                                                   mediaFactoryInjected: true,
                                                   mediaCredentialProviderAvailable: true,
                                                   mediaE2EEProviderAvailable: true,
                                                   mediaKeyHandleAvailable: true,
                                                   mediaKeyBridgeHit: true,
                                                   mediaConnectAttempted: true,
                                                   liveKitClientConnectAttempted: true,
                                                   mediaFailureReason: .mediaSetupUnavailable)
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallDiagnosticCommandConfiguration: .init(isEnabled: true)) { _ in
            diagnosticOwner
        } nativeDirectCallProductionActivationDryRunProviderFactory: { _ in
            provider
        } nativeDirectCallProductionRoomFlowOwnerFactory: { _ in
            .owner(productionOwner)
        }

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)
        let productionStatus = roomFlowCoordinator.nativeDirectCallProductionStatus()
        let diagnosticStatus = roomFlowCoordinator.nativeDirectCallDiagnosticStatus()

        #expect(result.didStart)
        #expect(productionStatus.productionOwnerAvailable)
        #expect(productionStatus.productionListenerStarted)
        #expect(productionStatus.productionHasActiveSession)
        #expect(productionStatus.productionSessionState == "outgoingRinging")
        #expect(productionStatus.productionEncryptionState == "ready")
        #expect(productionStatus.productionLastSignalEventEmitted == .invite)
        #expect(productionStatus.productionLastSignalSendAttempted)
        #expect(productionStatus.productionLastSignalSendSucceeded == true)
        #expect(productionStatus.productionLastSignalSendFailureReason == nil)
        #expect(productionStatus.productionListenerAttached)
        #expect(productionStatus.productionListenerHandleRetained)
        #expect(productionStatus.productionListenerStartCount == 1)
        #expect(productionStatus.productionTimelineUpdateCount == 1)
        #expect(productionStatus.productionTimelineDiffReceivedCount == 1)
        #expect(productionStatus.productionLastTimelineDiffKind == .append)
        #expect(productionStatus.productionLastTimelineDiffItemCount == 1)
        #expect(productionStatus.productionTimelineEventReceivedCount == 1)
        #expect(productionStatus.productionDirectCallEventTypeSeenCount == 1)
        #expect(productionStatus.productionEnvelopeExtractedCount == 1)
        #expect(productionStatus.productionEnvelopeDeliveredToEngineCount == 1)
        #expect(productionStatus.productionHistoricalEventIgnoredCount == 2)
        #expect(productionStatus.productionLiveEventDeliveredCount == 1)
        #expect(productionStatus.productionBaselineEstablished)
        #expect(productionStatus.productionLastReceiveEventKind == .directCallInvite)
        #expect(productionStatus.productionLastEnvelopeRejectedReason == .none)
        #expect(productionStatus.productionLastReceiveFailureReason == nil)
        #expect(productionStatus.productionSendRoomFingerprint == "send-room-redacted")
        #expect(productionStatus.productionReceiveRoomFingerprint == "receive-room-redacted")
        #expect(productionStatus.productionMediaFactoryInjected)
        #expect(productionStatus.productionMediaCredentialProviderAvailable)
        #expect(productionStatus.productionMediaE2EEProviderAvailable)
        #expect(productionStatus.productionMediaKeyHandleAvailable)
        #expect(productionStatus.productionMediaKeyBridgeHit)
        #expect(productionStatus.productionMediaConnectAttempted)
        #expect(productionStatus.productionLiveKitClientConnectAttempted)
        #expect(productionStatus.productionMediaFailureReason == .mediaSetupUnavailable)
        #expect(diagnosticStatus.state == .idle)
        #expect(diagnosticStatus.hasActiveSession == false)
        #expect(diagnosticStatus.lastSignalSendAttempted == false)
        #expect(diagnosticOwner.outgoingCount == 0)
        #expect(productionOwner.outgoingCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartStartsListenerBeforeOutgoing() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .productionOwnerDisabled)
        #expect(productionOwner.startCount == 1)
        #expect(productionOwner.outgoingCount == 0)
    }

    @Test
    func nativeDirectCallProductionStartReportsListenerStartFailure() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.startResult = .failure(.trigger(.control(.noActiveCall)))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .blocked)
        #expect(result.reason == .listenerStartFailed)
        #expect(productionOwner.startCount == 1)
        #expect(productionOwner.outgoingCount == 0)
    }

    @Test
    func nativeDirectCallProductionStartReportsKeyWrapUnavailable() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.outgoingResult = .failure(.trigger(.control(.engine(.encryptionFailed(.e2eeUnavailable)))))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .engineFailure)
        #expect(result.reason == .keyWrapUnavailable)
        #expect(String(describing: result).contains("encrypted_payload") == false)
        #expect(String(describing: result).contains("token") == false)
        #expect(productionOwner.startCount == 0)
        #expect(productionOwner.outgoingCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartReportsKeyWrapFailure() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.outgoingResult = .failure(.trigger(.control(.engine(.encryptionFailed(.cannotWrap)))))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .engineFailure)
        #expect(result.reason == .keyWrapFailed)
    }

    @Test
    func nativeDirectCallProductionStartReportsOutgoingWrapInvalidMetadata() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.outgoingResult = .failure(.trigger(.control(.engine(.encryptionFailed(.keyMismatch)))))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .engineFailure)
        #expect(result.reason == .outgoingWrapInvalidMetadata)
        #expect(String(describing: result).contains("encrypted_payload") == false)
    }

    @Test
    func nativeDirectCallProductionStartReportsOutgoingWrapUnsupportedAlgorithm() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.outgoingResult = .failure(.trigger(.control(.engine(.encryptionFailed(.unsupportedEnvelope)))))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .engineFailure)
        #expect(result.reason == .outgoingWrapUnsupportedAlgorithm)
        #expect(String(describing: result).contains("encrypted_payload") == false)
    }

    @Test
    func nativeDirectCallProductionStartReportsSDKTrustViolation() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.outgoingResult = .failure(.trigger(.control(.engine(.encryptionFailed(.sdkTrustViolation)))))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .engineFailure)
        #expect(result.reason == .sdkTrustViolation)
        #expect(String(describing: result).contains("encrypted_payload") == false)
        #expect(String(describing: result).contains("token") == false)
        #expect(productionOwner.outgoingCount == 1)
    }

    @Test
    func nativeDirectCallProductionStartReportsSDKNoEligibleDevice() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.outgoingResult = .failure(.trigger(.control(.engine(.encryptionFailed(.sdkNoEligibleDevice)))))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .engineFailure)
        #expect(result.reason == .sdkNoEligibleDevice)
    }

    @Test
    func nativeDirectCallProductionStartReportsEngineStateInvalid() async throws {
        let productionOwner = NativeDirectCallRoomFlowOwnerSpy()
        productionOwner.isListenerStarted = true
        productionOwner.outgoingResult = .failure(.trigger(.control(.engine(.invalidTransition))))
        let provider = NativeDirectCallProductionActivationDryRunProviderSpy(result: enabledProductionActivationDiagnostic())
        setupRoomFlowCoordinator(nativeDirectCallProductionActivationDryRunProviderFactory: { _ in provider },
                                 nativeDirectCallProductionRoomFlowOwnerFactory: { _ in .owner(productionOwner) })

        try await process(route: .room(roomID: "1", via: []))
        let result = await roomFlowCoordinator.nativeDirectCallProductionStartOutgoingAudioCall(isProductionStartEnabled: true)

        #expect(result.didStart == false)
        #expect(result.outcome == .engineFailure)
        #expect(result.reason == .engineStateInvalid)
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
        // swiftlint:disable:next trailing_closure
        setupRoomFlowCoordinator(nativeDirectCallRoomFlowOwnerFactory: { roomProxy in
            #expect(roomProxy.id == "1")
            owner.makeCount += 1
            return owner
        })

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
    func nativeDirectCallTrustDiagnosticFailsClosedWithoutActiveRoom() async {
        setupRoomFlowCoordinator()

        let diagnostic = await roomFlowCoordinator.nativeDirectCallPeerTrustDiagnostic()

        #expect(diagnostic.peerTrustReadiness == .peerTrustUnavailable)
        #expect(diagnostic.verificationFlowState == .unavailable)
    }

    @Test
    func nativeDirectCallTrustDiagnosticUsesActiveRoomPeerWithoutStartingCalls() async throws {
        setupRoomFlowCoordinator()
        let roomProxy = makeEligibleNativeDirectCallRoomProxy()
        clientProxy.roomForIdentifierClosure = { _ in
            .joined(roomProxy)
        }
        clientProxy.verificationStatePublisher = .init(.verified)
        clientProxy.userIdentityForFallBackToServerClosure = { userID, _ in
            guard userID == self.clientProxy.userID || userID == RoomMemberProxyMock.mockBob.userID else {
                return .success(nil)
            }

            return .success(UserIdentityProxyMock(configuration: .init(verificationState: .verified)))
        }

        try await process(route: .room(roomID: "1", via: []))
        let diagnostic = await roomFlowCoordinator.nativeDirectCallPeerTrustDiagnostic()

        #expect(diagnostic.ownUserIdentityAvailable)
        #expect(diagnostic.ownSessionVerified)
        #expect(diagnostic.crossSigningReady)
        #expect(diagnostic.peerIdentityAvailable)
        #expect(diagnostic.peerIdentityVerified)
        #expect(diagnostic.peerTrustReady)
        #expect(diagnostic.peerTrustReadiness == .peerTrustReady)
        #expect(diagnostic.verificationFlowState == .unavailable)
    }

    @Test
    func nativeDirectCallDiagnosticCommandEntryDelegatesExplicitCommandsOnly() async throws {
        let owner = NativeDirectCallRoomFlowOwnerSpy()
        let session = directCallSession()
        owner.diagnosticSnapshot = .init(activeSessionPhase: .outgoingRinging,
                                         lastSignalEventEmitted: .invite,
                                         lastSignalSendAttempted: true,
                                         lastSignalSendSucceeded: true,
                                         listenerAttached: true,
                                         listenerHandleRetained: true,
                                         listenerStartCount: 1,
                                         timelineUpdateCount: 1,
                                         timelineDiffReceivedCount: 1,
                                         lastTimelineDiffKind: .append,
                                         lastTimelineDiffItemCount: 1,
                                         timelineEventReceivedCount: 1,
                                         directCallEventTypeSeenCount: 1,
                                         envelopeExtractedCount: 1,
                                         envelopeDeliveredToEngineCount: 1,
                                         lastReceiveEventKind: .directCallInvite,
                                         sendRoomFingerprint: "send-room-redacted",
                                         receiveRoomFingerprint: "receive-room-redacted")
        owner.outgoingResult = .success(session)
        owner.acceptResult = .success(session)
        owner.hangupResult = .success(session)
        // swiftlint:disable trailing_closure
        setupRoomFlowCoordinator(nativeDirectCallDiagnosticCommandConfiguration: .init(isEnabled: true),
                                 nativeDirectCallRoomFlowOwnerFactory: { roomProxy in
                                     #expect(roomProxy.id == "1")
                                     owner.makeCount += 1
                                     return owner
                                 })
        // swiftlint:enable trailing_closure

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
        #expect(status.listenerAttached)
        #expect(status.listenerHandleRetained)
        #expect(status.listenerStartCount == 1)
        #expect(status.timelineUpdateCount == 1)
        #expect(status.timelineDiffReceivedCount == 1)
        #expect(status.lastTimelineDiffKind == .append)
        #expect(status.lastTimelineDiffItemCount == 1)
        #expect(status.envelopeDeliveredToEngineCount == 1)
        #expect(status.lastReceiveEventKind == .directCallInvite)
        #expect(status.sendRoomFingerprint == "send-room-redacted")
        #expect(status.receiveRoomFingerprint == "receive-room-redacted")

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
        // swiftlint:disable trailing_closure
        setupRoomFlowCoordinator(nativeDirectCallDiagnosticCommandConfiguration: .init(isEnabled: true),
                                 nativeDirectCallRoomFlowOwnerFactory: { _ in
                                     owner
                                 })
        // swiftlint:enable trailing_closure

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
                                                                                              lastSignalSendSucceeded: true,
                                                                                              listenerAttached: true,
                                                                                              listenerHandleRetained: true,
                                                                                              listenerStartCount: 1,
                                                                                              timelineUpdateCount: 1,
                                                                                              timelineDiffReceivedCount: 1,
                                                                                              lastTimelineDiffKind: .append,
                                                                                              lastTimelineDiffItemCount: 1,
                                                                                              timelineEventReceivedCount: 1,
                                                                                              directCallEventTypeSeenCount: 1,
                                                                                              envelopeExtractedCount: 1,
                                                                                              envelopeDeliveredToEngineCount: 1,
                                                                                              lastReceiveEventKind: .directCallInvite,
                                                                                              sendRoomFingerprint: "send-room-redacted",
                                                                                              receiveRoomFingerprint: "receive-room-redacted",
                                                                                              mediaFactoryInjected: true,
                                                                                              mediaCredentialProviderAvailable: true,
                                                                                              mediaE2EEProviderAvailable: true,
                                                                                              mediaKeyHandleAvailable: true,
                                                                                              mediaKeyBridgeHit: true,
                                                                                              mediaConnectAttempted: true,
                                                                                              liveKitClientConnectAttempted: true,
                                                                                              mediaFailureReason: .liveKitConnectFailed))
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
        let statusDiagnosticFragments = ["hasActiveSession", "lastSignalEventEmitted", "lastSignalSendAttempted", "lastSignalSendSucceeded",
                                         "activeSessionPhase", "listenerAttached", "listenerHandleRetained", "timelineUpdateCount",
                                         "timelineDiffReceivedCount", "lastTimelineDiffKind", "lastTimelineDiffItemCount",
                                         "envelopeDeliveredToEngineCount", "lastReceiveEventKind", "sendRoomFingerprint", "receiveRoomFingerprint"]
        for statusDiagnosticFragment in statusDiagnosticFragments {
            #expect(encodedStatusResult.contains(statusDiagnosticFragment))
        }
        let mediaDiagnosticFragments = ["mediaFactoryInjected", "mediaCredentialProviderAvailable", "mediaE2EEProviderAvailable", "mediaKeyHandleAvailable",
                                        "mediaKeyBridgeHit", "mediaConnectAttempted", "liveKitClientConnectAttempted", "liveKitConnectFailed"]
        for mediaDiagnosticFragment in mediaDiagnosticFragments {
            #expect(encodedStatusResult.contains(mediaDiagnosticFragment))
        }
        #expect(encodedStatusResult.contains("send-room-redacted"))
        #expect(encodedStatusResult.contains("receive-room-redacted"))
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
        let combinedSignals = encodedCommand
            + encodedResult
            + encodedFailureResult
            + encodedStatus
            + encodedStatusResult
        for fragment in forbiddenFragments {
            #expect(combinedSignals.localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test
    func nativeDirectCallTrustDiagnosticsSignalEncodesRedactedResult() throws {
        let request = UITestsSignal.NativeDirectCallTrustDiagnosticsRequest(correlationID: "call-A-1")
        let result = UITestsSignal.NativeDirectCallTrustDiagnosticsResult(correlationID: "call-A-1",
                                                                          diagnostic: .init(ownUserIdentityAvailable: true,
                                                                                            ownSessionVerified: false,
                                                                                            crossSigningReady: false,
                                                                                            peerIdentityAvailable: true,
                                                                                            peerIdentityVerified: false,
                                                                                            peerTrustReady: false,
                                                                                            peerTrustReadiness: "unverifiedDevice",
                                                                                            verificationRequestPending: true,
                                                                                            verificationFlowState: "requestAccepted",
                                                                                            lastVerificationErrorReason: "none"))
        let requestSignal = UITestsSignal.nativeDirectCallTrustDiagnostics(request)
        let resultSignal = UITestsSignal.nativeDirectCallTrustDiagnosticsResult(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encodedRequest = try #require(String(data: encoder.encode(requestSignal), encoding: .utf8))
        let encodedResult = try #require(String(data: encoder.encode(resultSignal), encoding: .utf8))

        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedRequest.utf8)) == requestSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedResult.utf8)) == resultSignal)
        #expect(encodedRequest.contains("nativeDirectCallTrustDiagnostics"))
        #expect(encodedResult.contains("nativeDirectCallTrustDiagnosticsResult"))
        #expect(encodedResult.contains("ownUserIdentityAvailable"))
        #expect(encodedResult.contains("ownSessionVerified"))
        #expect(encodedResult.contains("crossSigningReady"))
        #expect(encodedResult.contains("peerIdentityAvailable"))
        #expect(encodedResult.contains("peerIdentityVerified"))
        #expect(encodedResult.contains("peerTrustReadiness"))
        #expect(encodedResult.contains("verificationRequestPending"))
        #expect(encodedResult.contains("verificationFlowState"))
        #expect(encodedResult.contains("lastVerificationErrorReason"))
        #expect(result.correlationID == request.correlationID)

        let forbiddenFragments = [
            "@alice",
            "@bob",
            "DEVICE-",
            "debug" + "Info",
            "original" + "JSON",
            "original" + "Json",
            "raw " + "JSON",
            "encrypted_" + "payload",
            "to" + "ken",
            "j" + "wt",
            "raw " + "key"
        ]
        let combinedSignals = encodedRequest + encodedResult
        for fragment in forbiddenFragments {
            #expect(combinedSignals.localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test
    func nativeDirectCallVerificationFlowCommandSignalEncodesRedactedResult() throws {
        let request = UITestsSignal.NativeDirectCallVerificationFlowCommandRequest(correlationID: "call-A-1",
                                                                                   command: .startSAS)
        let result = UITestsSignal.NativeDirectCallVerificationFlowCommandResult(correlationID: "call-A-1",
                                                                                 diagnostic: .init(outcome: "succeeded",
                                                                                                   reason: "none",
                                                                                                   requestPending: true,
                                                                                                   flowState: "sasStarted",
                                                                                                   sasStarted: true,
                                                                                                   emojiReceived: false,
                                                                                                   finished: false,
                                                                                                   cancelled: false,
                                                                                                   failed: false,
                                                                                                   lastErrorReason: "none"))
        let requestSignal = UITestsSignal.nativeDirectCallVerificationFlowCommand(request)
        let resultSignal = UITestsSignal.nativeDirectCallVerificationFlowCommandResult(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encodedRequest = try #require(String(data: encoder.encode(requestSignal), encoding: .utf8))
        let encodedResult = try #require(String(data: encoder.encode(resultSignal), encoding: .utf8))

        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedRequest.utf8)) == requestSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedResult.utf8)) == resultSignal)
        #expect(request.diagnosticCommand == .startSAS)
        #expect(encodedRequest.contains("nativeDirectCallVerificationFlowCommand"))
        #expect(encodedResult.contains("nativeDirectCallVerificationFlowCommandResult"))
        #expect(encodedResult.contains("requestPending"))
        #expect(encodedResult.contains("flowState"))
        #expect(encodedResult.contains("sasStarted"))
        #expect(encodedResult.contains("emojiReceived"))
        #expect(encodedResult.contains("lastErrorReason"))

        let forbiddenFragments = [
            "@alice",
            "@bob",
            "DEVICE-",
            "debug" + "Info",
            "original" + "JSON",
            "original" + "Json",
            "raw " + "JSON",
            "encrypted_" + "payload",
            "to" + "ken",
            "j" + "wt",
            "raw " + "key"
        ]
        let combinedSignals = encodedRequest + encodedResult
        for fragment in forbiddenFragments {
            #expect(combinedSignals.localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test
    func nativeDirectCallProductionActivationDryRunSignalEncodesRedactedResult() throws {
        let request = UITestsSignal.NativeDirectCallProductionActivationDryRunRequest(correlationID: "call-A-1")
        let result = UITestsSignal.NativeDirectCallProductionActivationDryRunResult(correlationID: "call-A-1",
                                                                                    diagnostic: .init(enabled: false,
                                                                                                      reason: "appRolloutDisabled",
                                                                                                      capabilityPresent: false,
                                                                                                      dependenciesReady: false,
                                                                                                      roomEligible: true,
                                                                                                      endpointAccepted: false))
        let requestSignal = UITestsSignal.nativeDirectCallProductionActivationDryRun(request)
        let resultSignal = UITestsSignal.nativeDirectCallProductionActivationDryRunResult(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encodedRequest = try #require(String(data: encoder.encode(requestSignal), encoding: .utf8))
        let encodedResult = try #require(String(data: encoder.encode(resultSignal), encoding: .utf8))

        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedRequest.utf8)) == requestSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedResult.utf8)) == resultSignal)
        #expect(encodedRequest.contains("nativeDirectCallProductionActivationDryRun"))
        #expect(encodedResult.contains("nativeDirectCallProductionActivationDryRunResult"))
        #expect(encodedResult.contains("enabled"))
        #expect(encodedResult.contains("appRolloutDisabled"))
        #expect(encodedResult.contains("capabilityPresent"))
        #expect(encodedResult.contains("dependenciesReady"))
        #expect(encodedResult.contains("roomEligible"))
        #expect(encodedResult.contains("endpointAccepted"))
        #expect(encodedResult.contains("peerTrustReady"))
        #expect(encodedResult.contains("peerTrustReadiness"))
        #expect(result.correlationID == request.correlationID)

        let forbiddenFragments = [
            "debug" + "Info",
            "original" + "JSON",
            "original" + "Json",
            "raw " + "JSON",
            "encrypted_" + "payload",
            "j" + "wt",
            "raw " + "key",
            "!room",
            "@alice",
            "peer-user",
            "participant_" + "token",
            "access_" + "token",
            "matrix.example.com",
            DirectCallProductionConfiguration.tokenEndpointPath
        ]
        for fragment in forbiddenFragments {
            #expect((encodedRequest + encodedResult).localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test
    func nativeDirectCallProductionTriggerDryRunSignalEncodesRedactedResult() throws {
        let request = UITestsSignal.NativeDirectCallProductionTriggerDryRunRequest(correlationID: "call-A-1")
        let result = UITestsSignal.NativeDirectCallProductionTriggerDryRunResult(correlationID: "call-A-1",
                                                                                 diagnostic: .init(wouldStart: false,
                                                                                                   enabled: false,
                                                                                                   reason: "appRolloutDisabled",
                                                                                                   capabilityPresent: false,
                                                                                                   dependenciesReady: false,
                                                                                                   roomEligible: true,
                                                                                                   endpointAccepted: false))
        let requestSignal = UITestsSignal.nativeDirectCallProductionTriggerDryRun(request)
        let resultSignal = UITestsSignal.nativeDirectCallProductionTriggerDryRunResult(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encodedRequest = try #require(String(data: encoder.encode(requestSignal), encoding: .utf8))
        let encodedResult = try #require(String(data: encoder.encode(resultSignal), encoding: .utf8))

        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedRequest.utf8)) == requestSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedResult.utf8)) == resultSignal)
        #expect(encodedRequest.contains("nativeDirectCallProductionTriggerDryRun"))
        #expect(encodedResult.contains("nativeDirectCallProductionTriggerDryRunResult"))
        #expect(encodedResult.contains("wouldStart"))
        #expect(encodedResult.contains("enabled"))
        #expect(encodedResult.contains("appRolloutDisabled"))
        #expect(encodedResult.contains("capabilityPresent"))
        #expect(encodedResult.contains("dependenciesReady"))
        #expect(encodedResult.contains("roomEligible"))
        #expect(encodedResult.contains("endpointAccepted"))
        #expect(encodedResult.contains("peerTrustReady"))
        #expect(encodedResult.contains("peerTrustReadiness"))
        #expect(result.correlationID == request.correlationID)

        let forbiddenFragments = [
            "debug" + "Info",
            "original" + "JSON",
            "original" + "Json",
            "raw " + "JSON",
            "encrypted_" + "payload",
            "j" + "wt",
            "raw " + "key",
            "!room",
            "@alice",
            "peer-user",
            "participant_" + "token",
            "access_" + "token",
            "matrix.example.com",
            DirectCallProductionConfiguration.tokenEndpointPath
        ]
        for fragment in forbiddenFragments {
            #expect((encodedRequest + encodedResult).localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test
    func nativeDirectCallProductionStartSignalEncodesRedactedResult() throws {
        let request = UITestsSignal.NativeDirectCallProductionStartOutgoingAudioCallRequest(correlationID: "call-A-1")
        let result = UITestsSignal.NativeDirectCallProductionStartOutgoingAudioCallResult(correlationID: "call-A-1",
                                                                                          outcome: .blocked,
                                                                                          reason: "productionOwnerUnavailable",
                                                                                          triggerDiagnostic: .init(wouldStart: true,
                                                                                                                   enabled: true,
                                                                                                                   reason: nil,
                                                                                                                   capabilityPresent: true,
                                                                                                                   dependenciesReady: true,
                                                                                                                   roomEligible: true,
                                                                                                                   endpointAccepted: true,
                                                                                                                   peerTrustReady: true,
                                                                                                                   peerTrustReadiness: DirectCallPeerTrustReadiness.peerTrustReady.rawValue))
        let requestSignal = UITestsSignal.nativeDirectCallProductionStartOutgoingAudioCall(request)
        let resultSignal = UITestsSignal.nativeDirectCallProductionStartOutgoingAudioCallResult(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encodedRequest = try #require(String(data: encoder.encode(requestSignal), encoding: .utf8))
        let encodedResult = try #require(String(data: encoder.encode(resultSignal), encoding: .utf8))

        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedRequest.utf8)) == requestSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedResult.utf8)) == resultSignal)
        #expect(encodedRequest.contains("nativeDirectCallProductionStartOutgoingAudioCall"))
        #expect(encodedResult.contains("nativeDirectCallProductionStartOutgoingAudioCallResult"))
        #expect(encodedResult.contains("blocked"))
        #expect(encodedResult.contains("productionOwnerUnavailable"))
        #expect(encodedResult.contains("capabilityPresent"))
        #expect(encodedResult.contains("dependenciesReady"))
        #expect(encodedResult.contains("roomEligible"))
        #expect(encodedResult.contains("endpointAccepted"))
        #expect(encodedResult.contains("peerTrustReady"))
        #expect(encodedResult.contains("peerTrustReadiness"))
        #expect(result.correlationID == request.correlationID)

        let forbiddenFragments = [
            "debug" + "Info",
            "original" + "JSON",
            "original" + "Json",
            "raw " + "JSON",
            "encrypted_" + "payload",
            "j" + "wt",
            "raw " + "key",
            "!room",
            "@alice",
            "peer-user",
            "participant_" + "token",
            "access_" + "token",
            "matrix.example.com",
            DirectCallProductionConfiguration.tokenEndpointPath
        ]
        for fragment in forbiddenFragments {
            #expect((encodedRequest + encodedResult).localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test
    func nativeDirectCallProductionStartListenerSignalEncodesRedactedResult() throws {
        let request = UITestsSignal.NativeDirectCallProductionStartListenerRequest(correlationID: "call-A-1")
        let status = UITestsSignal.NativeDirectCallProductionStatusPayload(productionOwnerAvailable: true,
                                                                           productionListenerStarted: true,
                                                                           productionHasActiveSession: false,
                                                                           productionSessionState: "idle",
                                                                           productionEncryptionState: "unknown",
                                                                           productionLastSignalEventEmitted: nil,
                                                                           productionLastSignalSendAttempted: false,
                                                                           productionLastSignalSendSucceeded: nil,
                                                                           productionLastSignalSendFailureReason: nil)
        let result = UITestsSignal.NativeDirectCallProductionStartListenerResult(correlationID: "call-A-1",
                                                                                 outcome: .started,
                                                                                 reason: nil,
                                                                                 triggerDiagnostic: .init(wouldStart: true,
                                                                                                          enabled: true,
                                                                                                          reason: nil,
                                                                                                          capabilityPresent: true,
                                                                                                          dependenciesReady: true,
                                                                                                          roomEligible: true,
                                                                                                          endpointAccepted: true,
                                                                                                          peerTrustReady: true,
                                                                                                          peerTrustReadiness: DirectCallPeerTrustReadiness.peerTrustReady.rawValue),
                                                                                 status: status)
        let requestSignal = UITestsSignal.nativeDirectCallProductionStartListener(request)
        let resultSignal = UITestsSignal.nativeDirectCallProductionStartListenerResult(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encodedRequest = try #require(String(data: encoder.encode(requestSignal), encoding: .utf8))
        let encodedResult = try #require(String(data: encoder.encode(resultSignal), encoding: .utf8))

        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedRequest.utf8)) == requestSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedResult.utf8)) == resultSignal)
        #expect(encodedRequest.contains("nativeDirectCallProductionStartListener"))
        #expect(encodedResult.contains("nativeDirectCallProductionStartListenerResult"))
        #expect(encodedResult.contains("started"))
        #expect(encodedResult.contains("productionListenerStarted"))
        #expect(encodedResult.contains("productionLastSignalSendAttempted"))
        #expect(encodedResult.contains("productionTimelineUpdateCount"))
        #expect(encodedResult.contains("productionBaselineEstablished"))
        #expect(encodedResult.contains("peerTrustReady"))
        #expect(encodedResult.contains("peerTrustReadiness"))
        #expect(result.correlationID == request.correlationID)

        let forbiddenFragments = [
            "debug" + "Info",
            "original" + "JSON",
            "original" + "Json",
            "raw " + "JSON",
            "encrypted_" + "payload",
            "j" + "wt",
            "raw " + "key",
            "!room",
            "@alice",
            "peer-user",
            "participant_" + "token",
            "access_" + "token",
            "matrix.example.com",
            DirectCallProductionConfiguration.tokenEndpointPath
        ]
        for fragment in forbiddenFragments {
            #expect((encodedRequest + encodedResult).localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test
    func nativeDirectCallProductionAcceptSignalEncodesRedactedResult() throws {
        let request = UITestsSignal.NativeDirectCallProductionAcceptIncomingCallRequest(correlationID: "call-A-1")
        let status = UITestsSignal.NativeDirectCallProductionStatusPayload(productionOwnerAvailable: true,
                                                                           productionListenerStarted: true,
                                                                           productionHasActiveSession: true,
                                                                           productionSessionState: "connecting",
                                                                           productionEncryptionState: "ready",
                                                                           productionLastSignalEventEmitted: .answer,
                                                                           productionLastSignalSendAttempted: true,
                                                                           productionLastSignalSendSucceeded: true,
                                                                           productionLastSignalSendFailureReason: nil)
        let result = UITestsSignal.NativeDirectCallProductionAcceptIncomingCallResult(correlationID: "call-A-1",
                                                                                      outcome: .started,
                                                                                      reason: nil,
                                                                                      triggerDiagnostic: .init(wouldStart: true,
                                                                                                               enabled: true,
                                                                                                               reason: nil,
                                                                                                               capabilityPresent: true,
                                                                                                               dependenciesReady: true,
                                                                                                               roomEligible: true,
                                                                                                               endpointAccepted: true,
                                                                                                               peerTrustReady: true,
                                                                                                               peerTrustReadiness: DirectCallPeerTrustReadiness.peerTrustReady.rawValue),
                                                                                      sessionSummary: .init(hasCallID: true,
                                                                                                            direction: "incoming",
                                                                                                            intent: "audio",
                                                                                                            state: "connecting",
                                                                                                            encryptionState: "ready"),
                                                                                      status: status)
        let requestSignal = UITestsSignal.nativeDirectCallProductionAcceptIncomingCall(request)
        let resultSignal = UITestsSignal.nativeDirectCallProductionAcceptIncomingCallResult(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encodedRequest = try #require(String(data: encoder.encode(requestSignal), encoding: .utf8))
        let encodedResult = try #require(String(data: encoder.encode(resultSignal), encoding: .utf8))

        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedRequest.utf8)) == requestSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedResult.utf8)) == resultSignal)
        #expect(encodedRequest.contains("nativeDirectCallProductionAcceptIncomingCall"))
        #expect(encodedResult.contains("nativeDirectCallProductionAcceptIncomingCallResult"))
        #expect(encodedResult.contains("started"))
        #expect(encodedResult.contains("answer"))
        #expect(encodedResult.contains("productionLastSignalSendAttempted"))
        #expect(encodedResult.contains("peerTrustReady"))
        #expect(encodedResult.contains("peerTrustReadiness"))
        #expect(result.correlationID == request.correlationID)

        let forbiddenFragments = [
            "debug" + "Info",
            "original" + "JSON",
            "original" + "Json",
            "raw " + "JSON",
            "encrypted_" + "payload",
            "j" + "wt",
            "raw " + "key",
            "!room",
            "@alice",
            "peer-user",
            "participant_" + "token",
            "access_" + "token",
            "matrix.example.com",
            DirectCallProductionConfiguration.tokenEndpointPath
        ]
        for fragment in forbiddenFragments {
            #expect((encodedRequest + encodedResult).localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test
    func nativeDirectCallProductionStatusSignalEncodesRedactedResult() throws {
        let request = UITestsSignal.NativeDirectCallProductionStatusRequest(correlationID: "call-A-1")
        let status = UITestsSignal.NativeDirectCallProductionStatusPayload(productionOwnerAvailable: true,
                                                                           productionListenerStarted: true,
                                                                           productionHasActiveSession: true,
                                                                           productionSessionState: "outgoingRinging",
                                                                           productionEncryptionState: "ready",
                                                                           productionLastSignalEventEmitted: .invite,
                                                                           productionLastSignalSendAttempted: true,
                                                                           productionLastSignalSendSucceeded: true,
                                                                           productionLastSignalSendFailureReason: nil,
                                                                           productionListenerAttached: true,
                                                                           productionListenerHandleRetained: true,
                                                                           productionListenerStartCount: 1,
                                                                           productionTimelineUpdateCount: 2,
                                                                           productionTimelineDiffReceivedCount: 3,
                                                                           productionLastTimelineDiffKind: .append,
                                                                           productionLastTimelineDiffItemCount: 1,
                                                                           productionTimelineEventReceivedCount: 4,
                                                                           productionDirectCallEventTypeSeenCount: 5,
                                                                           productionEnvelopeExtractedCount: 6,
                                                                           productionEnvelopeDeliveredToEngineCount: 7,
                                                                           productionHistoricalEventIgnoredCount: 8,
                                                                           productionLiveEventDeliveredCount: 9,
                                                                           productionBaselineEstablished: true,
                                                                           productionLastReceiveEventKind: .directCallInvite,
                                                                           productionLastEnvelopeRejectedReason: .none,
                                                                           productionLastReceiveFailureReason: .engineRejected,
                                                                           productionSendRoomFingerprint: "send-room-redacted",
                                                                           productionReceiveRoomFingerprint: "receive-room-redacted",
                                                                           productionMediaFactoryInjected: true,
                                                                           productionMediaCredentialProviderAvailable: true,
                                                                           productionMediaE2EEProviderAvailable: true,
                                                                           productionMediaKeyHandleAvailable: true,
                                                                           productionMediaKeyBridgeHit: true,
                                                                           productionMediaConnectAttempted: true,
                                                                           productionLiveKitClientConnectAttempted: true,
                                                                           productionMediaFailureReason: .mediaSetupUnavailable)
        let result = UITestsSignal.NativeDirectCallProductionStatusResult(correlationID: "call-A-1",
                                                                          status: status)
        let requestSignal = UITestsSignal.nativeDirectCallProductionStatus(request)
        let resultSignal = UITestsSignal.nativeDirectCallProductionStatusResult(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let encodedRequest = try #require(String(data: encoder.encode(requestSignal), encoding: .utf8))
        let encodedResult = try #require(String(data: encoder.encode(resultSignal), encoding: .utf8))

        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedRequest.utf8)) == requestSignal)
        #expect(try JSONDecoder().decode(UITestsSignal.self, from: Data(encodedResult.utf8)) == resultSignal)
        #expect(encodedRequest.contains("nativeDirectCallProductionStatus"))
        #expect(encodedResult.contains("nativeDirectCallProductionStatusResult"))
        #expect(encodedResult.contains("productionOwnerAvailable"))
        #expect(encodedResult.contains("productionListenerStarted"))
        #expect(encodedResult.contains("productionHasActiveSession"))
        #expect(encodedResult.contains("productionLastSignalSendAttempted"))
        #expect(encodedResult.contains("productionListenerAttached"))
        #expect(encodedResult.contains("productionListenerHandleRetained"))
        #expect(encodedResult.contains("productionTimelineUpdateCount"))
        #expect(encodedResult.contains("productionTimelineDiffReceivedCount"))
        #expect(encodedResult.contains("productionDirectCallEventTypeSeenCount"))
        #expect(encodedResult.contains("productionEnvelopeExtractedCount"))
        #expect(encodedResult.contains("productionEnvelopeDeliveredToEngineCount"))
        #expect(encodedResult.contains("productionHistoricalEventIgnoredCount"))
        #expect(encodedResult.contains("productionLiveEventDeliveredCount"))
        #expect(encodedResult.contains("productionBaselineEstablished"))
        #expect(encodedResult.contains("productionLastReceiveEventKind"))
        #expect(encodedResult.contains("productionLastEnvelopeRejectedReason"))
        #expect(encodedResult.contains("productionLastReceiveFailureReason"))
        #expect(encodedResult.contains("productionSendRoomFingerprint"))
        #expect(encodedResult.contains("productionReceiveRoomFingerprint"))
        #expect(encodedResult.contains("productionMediaFactoryInjected"))
        #expect(encodedResult.contains("productionMediaCredentialProviderAvailable"))
        #expect(encodedResult.contains("productionMediaE2EEProviderAvailable"))
        #expect(encodedResult.contains("productionMediaKeyHandleAvailable"))
        #expect(encodedResult.contains("productionMediaKeyBridgeHit"))
        #expect(encodedResult.contains("productionMediaConnectAttempted"))
        #expect(encodedResult.contains("productionLiveKitClientConnectAttempted"))
        #expect(encodedResult.contains("productionMediaFailureReason"))
        #expect(encodedResult.contains("mediaSetupUnavailable"))
        #expect(encodedResult.contains("send-room-redacted"))
        #expect(encodedResult.contains("receive-room-redacted"))
        #expect(result.correlationID == request.correlationID)

        let forbiddenFragments = [
            "debug" + "Info",
            "original" + "JSON",
            "original" + "Json",
            "raw " + "JSON",
            "encrypted_" + "payload",
            "j" + "wt",
            "raw " + "key",
            "!room",
            "@alice",
            "peer-user",
            "participant_" + "token",
            "access_" + "token",
            "matrix.example.com",
            DirectCallProductionConfiguration.tokenEndpointPath
        ]
        for fragment in forbiddenFragments {
            #expect((encodedRequest + encodedResult).localizedCaseInsensitiveContains(fragment) == false)
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
            #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationLiveKitEnabled(environment: environment) == false)
            #expect(ProcessInfo.isNativeDirectCallProductionDryRunFakeEnabled(environment: environment) == false)
            #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: environment) == false)
        }

        let harnessOnlyEnvironment = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1"
        ]
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationHarnessEnabled(environment: harnessOnlyEnvironment) == true)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: harnessOnlyEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: harnessOnlyEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationLiveKitEnabled(environment: harnessOnlyEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionDryRunFakeEnabled(environment: harnessOnlyEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: harnessOnlyEnvironment) == false)

        let commandsEnabledEnvironment = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1"
        ]
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationHarnessEnabled(environment: commandsEnabledEnvironment) == true)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationCommandsEnabled(environment: commandsEnabledEnvironment) == true)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: commandsEnabledEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationLiveKitEnabled(environment: commandsEnabledEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionDryRunFakeEnabled(environment: commandsEnabledEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: commandsEnabledEnvironment) == false)

        var fakeDryRunEnvironment = commandsEnabledEnvironment
        fakeDryRunEnvironment["NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED"] = "1"
        #expect(ProcessInfo.isNativeDirectCallProductionDryRunFakeEnabled(environment: fakeDryRunEnvironment) == true)
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: fakeDryRunEnvironment) == false)

        var productionStartEnvironment = commandsEnabledEnvironment
        productionStartEnvironment["NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED"] = "1"
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: productionStartEnvironment) == true)
        #expect(ProcessInfo.nativeDirectCallProductionTokenBaseURL(environment: productionStartEnvironment) == nil)
        productionStartEnvironment["NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL"] = "http://127.0.0.1:8088"
        #expect(ProcessInfo.nativeDirectCallProductionTokenBaseURL(environment: productionStartEnvironment)?.absoluteString == "http://127.0.0.1:8088")

        var encryptionEnvironment = commandsEnabledEnvironment
        encryptionEnvironment[NativeDirectCallDiagnosticEncryptionService.encryptionGateEnvironmentKey] = "1"
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: encryptionEnvironment) == false)
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticEncryptionService(ownUserID: "hi@bob",
                                                                               environment: encryptionEnvironment) == nil)

        encryptionEnvironment[NativeDirectCallDiagnosticEncryptionService.secretEnvironmentKey] = ""
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: encryptionEnvironment) == false)

        encryptionEnvironment[NativeDirectCallDiagnosticEncryptionService.secretEnvironmentKey] = "diagnostic-shared-secret"
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: encryptionEnvironment) == true)
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationLiveKitEnabled(environment: encryptionEnvironment) == false)
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticEncryptionService(ownUserID: "hi@bob",
                                                                               environment: encryptionEnvironment) != nil)

        var liveKitEnvironment = encryptionEnvironment
        liveKitEnvironment[NativeDirectCallDiagnosticLiveKitMedia.liveKitGateEnvironmentKey] = "1"
        #expect(ProcessInfo.isNativeDirectCallDiagnosticIntegrationLiveKitEnabled(environment: liveKitEnvironment) == true)
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticMediaEngineFactory(encryptionService: nil,
                                                                                environment: liveKitEnvironment) == nil)

        let encryptionService = AppCoordinator.makeNativeDirectCallDiagnosticEncryptionService(ownUserID: "hi@bob",
                                                                                               environment: liveKitEnvironment)
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticMediaEngineFactory(encryptionService: encryptionService,
                                                                                environment: liveKitEnvironment) == nil)

        liveKitEnvironment[NativeDirectCallDiagnosticLiveKitMedia.urlEnvironmentKey] = "wss://test-livekit.example.com"
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticMediaEngineFactory(encryptionService: encryptionService,
                                                                                environment: liveKitEnvironment) == nil)

        liveKitEnvironment[NativeDirectCallDiagnosticLiveKitMedia.tokenAEnvironmentKey] = "opaque-a"
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticMediaEngineFactory(encryptionService: encryptionService,
                                                                                environment: liveKitEnvironment) != nil)

        liveKitEnvironment[NativeDirectCallDiagnosticLiveKitMedia.signallingChannelEnvironmentKey] = "B"
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticMediaEngineFactory(encryptionService: encryptionService,
                                                                                environment: liveKitEnvironment) == nil)

        liveKitEnvironment[NativeDirectCallDiagnosticLiveKitMedia.tokenBEnvironmentKey] = "opaque-b"
        #expect(AppCoordinator.makeNativeDirectCallDiagnosticMediaEngineFactory(encryptionService: encryptionService,
                                                                                environment: liveKitEnvironment) != nil)
    }

    @Test
    func nativeDirectCallProductionTokenBaseURLUsesHomeserverUnlessDebugIntegrationOverrideIsSet() {
        let disabledOverrideEnvironment = [
            "NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL": "http://127.0.0.1:8088"
        ]
        var enabledOverrideEnvironment = makeProductionDryRunFakeEnabledEnvironment()
        enabledOverrideEnvironment["NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL"] = "http://127.0.0.1:8088"

        #expect(AppCoordinator.nativeDirectCallProductionTokenEndpointBaseURL(homeserver: "https://matrix.example.test",
                                                                              environment: disabledOverrideEnvironment)?.absoluteString == "https://matrix.example.test")
        #expect(AppCoordinator.nativeDirectCallProductionTokenEndpointBaseURL(homeserver: "https://matrix.example.test",
                                                                              environment: enabledOverrideEnvironment)?.absoluteString == "http://127.0.0.1:8088")
    }

    @Test
    func nativeDirectCallProductionRoomFlowOwnerRejectsInvalidDebugTokenBaseURL() {
        let roomProxy = makeEligibleNativeDirectCallRoomProxy()
        let clientProxy = makeVerifiedPeerClientProxy()
        clientProxy.homeserver = "https://matrix.example.test"
        var environment = makeProductionDryRunFakeEnabledEnvironment()
        environment["NATIVE_DIRECT_CALL_PRODUCTION_TOKEN_BASE_URL"] = "file:///tmp/salemx-call-service"

        let result = AppCoordinator.makeNativeDirectCallProductionRoomFlowOwner(roomProxy: roomProxy,
                                                                                clientProxy: clientProxy,
                                                                                environment: environment)

        guard case .blocked(.tokenEndpointUnavailable) = result else {
            Issue.record("Expected invalid DEBUG token endpoint override to fail closed.")
            return
        }
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
                                                                                                     lastSignalSendSucceeded: true,
                                                                                                     listenerAttached: true,
                                                                                                     listenerStartCount: 1,
                                                                                                     lastReceiveEventKind: .directCallInvite))).status.activeSessionPhase == .outgoingRinging)
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

    private func makeEligibleNativeDirectCallRoomProxy() -> JoinedRoomProxyMock {
        JoinedRoomProxyMock(.init(id: "!room:example.test",
                                  isDirect: true,
                                  isEncrypted: true,
                                  members: [.mockMe, .mockBob]))
    }

    private func makeProductionDryRunFakeEnabledEnvironment() -> [String: String] {
        [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1",
            "NATIVE_DIRECT_CALL_PRODUCTION_DRY_RUN_FAKE_ENABLED": "1"
        ]
    }

    private func enabledProductionActivationDiagnostic() -> DirectCallProductionActivationDryRunDiagnostic {
        .init(isEnabled: true,
              disabledReason: nil,
              isCapabilityPresent: true,
              areDependenciesReady: true,
              isRoomEligible: true,
              isEndpointAccepted: true,
              peerTrustReadiness: .peerTrustReady,
              keyWrapperSource: .providerWrapper)
    }

    private func makeVerifiedPeerClientProxy() -> ClientProxyMock {
        let clientProxy = ProductionDryRunClientProxyMock(.init(userID: RoomMemberProxyMock.mockMe.userID))
        clientProxy.userIdentityForFallBackToServerClosure = { userID, _ in
            guard userID == RoomMemberProxyMock.mockBob.userID else {
                return .success(nil)
            }

            return .success(UserIdentityProxyMock(configuration: .init(verificationState: .verified)))
        }
        return clientProxy
    }
    
    private func setupRoomFlowCoordinator(asChildFlow: Bool = false,
                                          roomType: RoomType? = nil,
                                          nativeDirectCallDiagnosticCommandConfiguration: NativeDirectCallRoomDeveloperCommandConfiguration = .init(),
                                          nativeDirectCallRoomFlowOwnerFactory: @escaping @MainActor (JoinedRoomProxyProtocol) -> NativeDirectCallRoomFlowOwning = { roomProxy in
                                              NativeDirectCallRoomFlowOwner(roomProxy: roomProxy)
                                          },
                                          nativeDirectCallProductionActivationDryRunProviderFactory: @escaping @MainActor (JoinedRoomProxyProtocol) -> NativeDirectCallProductionActivationDryRunProviding = { _ in
                                              FailClosedNativeDirectCallProductionActivationDryRunProvider()
                                          },
                                          nativeDirectCallProductionRoomFlowOwnerFactory: @escaping @MainActor (JoinedRoomProxyProtocol) -> NativeDirectCallProductionRoomFlowOwnerFactoryResult = { _ in
                                              .blocked(.productionOwnerUnavailable)
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
                                                  nativeDirectCallRoomFlowOwnerFactory: nativeDirectCallRoomFlowOwnerFactory,
                                                  nativeDirectCallProductionActivationDryRunProviderFactory: nativeDirectCallProductionActivationDryRunProviderFactory,
                                                  nativeDirectCallProductionRoomFlowOwnerFactory: nativeDirectCallProductionRoomFlowOwnerFactory)
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

    private func directCallSession(direction: DirectCallDirection = .incoming,
                                   state: DirectCallState = .activeAudio) -> DirectCallSession {
        DirectCallSession(callID: "call-1",
                          roomID: "room-1",
                          peerUserID: "@alice:example.com",
                          direction: direction,
                          intent: .audio,
                          encryptionMode: .e2eeRequired,
                          startedAt: .now,
                          updatedAt: .now,
                          state: state,
                          encryptionState: .ready)
    }

    private func nativeDirectCallComposition() -> NativeDirectCallComposition {
        let engine = DirectCallEngine(ownUserID: "hi@bob") { _ in
            "@alice:example.com"
        }
        let signalBridge = DirectCallEngineSignalBridge(ownUserID: "hi@bob",
                                                        engine: engine,
                                                        signalTransport: InMemoryDirectCallSignalTransport())
        return NativeDirectCallComposition(roomID: "room-1",
                                           peerUserID: "@alice:example.com",
                                           engine: engine,
                                           signalBridge: signalBridge)
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
private final class NativeDirectCallProductionActivationDryRunProviderSpy: NativeDirectCallProductionActivationDryRunProviding {
    var makeCount = 0
    private(set) var callCount = 0
    private let result: DirectCallProductionActivationDryRunDiagnostic

    init(result: DirectCallProductionActivationDryRunDiagnostic) {
        self.result = result
    }

    func nativeDirectCallProductionActivationDryRunDiagnostic() async -> DirectCallProductionActivationDryRunDiagnostic {
        callCount += 1
        return result
    }
}

@MainActor
private final class StaticDirectCallProductionCapabilityProvider: DirectCallProductionCapabilityProviding {
    private let result: DirectCallProductionCapabilityDiscoveryResult

    init(capability: DirectCallProductionServerCapability?) {
        result = capability.map { .available($0) } ?? .unavailable(.missingCapability)
    }

    func directCallProductionServerCapability() async -> DirectCallProductionCapabilityDiscoveryResult {
        result
    }
}

@MainActor
private final class NativeDirectCallProductionDependencyProviderSpy: NativeDirectCallProductionDependencyProviding {
    private let dependencies: NativeDirectCallProductionDependencies

    init(dependencies: NativeDirectCallProductionDependencies) {
        self.dependencies = dependencies
    }

    func nativeDirectCallProductionDependencies() -> NativeDirectCallProductionDependencies {
        dependencies
    }
}

private final class ProductionDryRunClientProxyMock: ClientProxyMock, DirectCallMatrixAccessTokenProviding, DirectCallMediaKeyEnvelopeWrappingProviding, @unchecked Sendable {
    func matrixAccessToken() async -> String? {
        "redacted-test-access"
    }

    func makeDirectCallMediaKeyEnvelopeWrapper() -> MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol? {
        ProductionDryRunMatrixSDKKeyEnvelopeWrapperSpy()
    }
}

private final class ProductionDryRunMatrixSDKKeyEnvelopeWrapperSpy: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol {
    func wrapDirectCallMediaKey(info: MatrixRustSDK.DirectCallMediaKeyWrapInfo) async throws -> MatrixRustSDK.DirectCallMediaKeyEnvelope {
        .init(version: 1,
              algorithm: "m.olm.v1.curve25519-aes-sha2",
              roomId: info.roomId,
              callId: info.callId,
              senderUserId: "@redacted:example.com",
              recipientUserId: info.recipientUserId,
              intent: info.intent,
              keyId: info.keyId,
              expiresAtMs: info.expiresAtMs,
              opaqueCiphertext: "redacted-opaque-envelope")
    }

    func unwrapDirectCallMediaKeyEnvelope(info _: MatrixRustSDK.DirectCallMediaKeyUnwrapInfo,
                                          envelope: MatrixRustSDK.DirectCallMediaKeyEnvelope) async throws -> MatrixRustSDK.DirectCallMediaKeyUnwrapResult {
        .init(keyId: envelope.keyId,
              mediaKey: "redacted-test-media-key",
              senderUserId: envelope.senderUserId,
              senderDeviceId: nil)
    }
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
    var startResult: Result<NativeDirectCallComposition, NativeDirectCallRoomFlowOwnerError> = .failure(.disabled)
    var outgoingResult: Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> = .failure(.disabled)
    var acceptResult: Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> = .failure(.disabled)
    var hangupResult: Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> = .failure(.disabled)
    var updatesActiveSessionOnOutgoingSuccess = false
    var updatesActiveSessionOnAcceptSuccess = false

    func prepare() -> Result<NativeDirectCallComposition, NativeDirectCallRoomFlowOwnerError> {
        prepareCount += 1
        return .failure(.disabled)
    }

    func startListener() async -> Result<NativeDirectCallComposition, NativeDirectCallRoomFlowOwnerError> {
        startCount += 1
        if case .success = startResult {
            isListenerStarted = true
        }
        return startResult
    }

    func startOutgoingAudioCall() async -> Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> {
        outgoingCount += 1
        if updatesActiveSessionOnOutgoingSuccess, case .success(let session) = outgoingResult {
            activeSession = session
        }
        return outgoingResult
    }

    func acceptIncomingCall() async -> Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> {
        acceptCount += 1
        if updatesActiveSessionOnAcceptSuccess, case .success(let session) = acceptResult {
            activeSession = session
        }
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
