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
import Testing

@MainActor
struct ChatsTabFlowCoordinatorTests {
    var clientProxy: ClientProxyMock!
    var timelineControllerFactory: TimelineControllerFactoryMock!
    var chatsTabFlowCoordinator: ChatsTabFlowCoordinator!
    var splitCoordinator: NavigationSplitCoordinator!
    var notificationManager: NotificationManagerMock!
    var flowParameters: CommonFlowParameters!
    let stateMachineFactory = PublishedStateMachineFactory()
    
    var cancellables = Set<AnyCancellable>()
    
    var detailCoordinator: CoordinatorProtocol? {
        splitCoordinator.detailCoordinator
    }
    
    var detailNavigationStack: NavigationStackCoordinator? {
        detailCoordinator as? NavigationStackCoordinator
    }
    
    init() async throws {
        clientProxy = ClientProxyMock(.init(userID: "hi@bob", roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(.mockRooms)))))
        timelineControllerFactory = TimelineControllerFactoryMock(.init())
        
        splitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: false))
        
        notificationManager = NotificationManagerMock()
        
        flowParameters = CommonFlowParameters(userSession: UserSessionMock(.init(clientProxy: clientProxy)),
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
                                              userIndicatorController: UserIndicatorControllerMock(),
                                              notificationManager: notificationManager,
                                              stateMachineFactory: stateMachineFactory)
        chatsTabFlowCoordinator = makeChatsTabFlowCoordinator()
        
        let deferred = deferFulfillment(stateMachineFactory.chatsTabFlowStatePublisher) { $0 == .roomList(detailState: nil) }
        chatsTabFlowCoordinator.start()
        try await deferred.fulfill()
    }
    
    @Test
    mutating func roomPresentation() async throws {
        try await process(route: .room(roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .roomList, expectedState: .roomList(detailState: nil))
        #expect(detailNavigationStack?.rootCoordinator == nil)
        #expect(detailCoordinator == nil)
        
        try await process(route: .room(roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .room(roomID: "2", via: []), expectedState: .roomList(detailState: .room(roomID: "2")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .roomList, expectedState: .roomList(detailState: nil))
        #expect(detailNavigationStack?.rootCoordinator == nil)
        #expect(detailCoordinator == nil)
        
        #expect(notificationManager.removeDeliveredMessageNotificationsForReceivedInvocations == ["1", "1", "2"])
    }
    
    @Test
    mutating func roomAliasPresentation() async throws {
        clientProxy.resolveRoomAliasReturnValue = .success(.init(roomId: "1", servers: []))
        
        try await process(route: .roomAlias("#alias:matrix.org"), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .roomList, expectedState: .roomList(detailState: nil))
        #expect(detailNavigationStack?.rootCoordinator == nil)
        #expect(detailCoordinator == nil)
        
        try await process(route: .room(roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        clientProxy.resolveRoomAliasReturnValue = .success(.init(roomId: "2", servers: []))
        
        try await process(route: .room(roomID: "2", via: []), expectedState: .roomList(detailState: .room(roomID: "2")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .roomList, expectedState: .roomList(detailState: nil))
        #expect(detailNavigationStack?.rootCoordinator == nil)
        #expect(detailCoordinator == nil)
        
        #expect(notificationManager.removeDeliveredMessageNotificationsForReceivedInvocations == ["1", "1", "2"])
    }
    
    @Test
    mutating func roomDetailsPresentation() async throws {
        try await process(route: .roomDetails(roomID: "1"), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomDetailsScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .roomList, expectedState: .roomList(detailState: nil))
        #expect(detailNavigationStack?.rootCoordinator == nil)
        #expect(detailCoordinator == nil)
    }
    
    @Test
    mutating func stackUnwinding() async throws {
        try await process(route: .roomDetails(roomID: "1"), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomDetailsScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .room(roomID: "2", via: []), expectedState: .roomList(detailState: .room(roomID: "2")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
    }
    
    @Test
    mutating func noOp() async throws {
        try await process(route: .roomDetails(roomID: "1"), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomDetailsScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        let unexpectedFulfillment = deferFailure(stateMachineFactory.chatsTabFlowStatePublisher, timeout: .seconds(1)) { _ in true }
        chatsTabFlowCoordinator.handleAppRoute(.roomDetails(roomID: "1"), animated: true)
        try await unexpectedFulfillment.fulfill()
        
        #expect(detailNavigationStack?.rootCoordinator is RoomDetailsScreenCoordinator)
        #expect(detailCoordinator != nil)
    }
    
    @Test
    mutating func switchToDifferentDetails() async throws {
        try await process(route: .roomDetails(roomID: "1"), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomDetailsScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .roomDetails(roomID: "2"), expectedState: .roomList(detailState: .room(roomID: "2")))
        #expect(detailNavigationStack?.rootCoordinator is RoomDetailsScreenCoordinator)
        #expect(detailCoordinator != nil)
    }
    
    @Test
    mutating func pushDetails() async throws {
        try await process(route: .room(roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        let unexpectedFulfillment = deferFailure(stateMachineFactory.chatsTabFlowStatePublisher, timeout: .seconds(1)) { _ in true }
        chatsTabFlowCoordinator.handleAppRoute(.roomDetails(roomID: "1"), animated: true)
        try await unexpectedFulfillment.fulfill()
        
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailNavigationStack?.stackCoordinators.count == 1)
        #expect(detailNavigationStack?.stackCoordinators.first is RoomDetailsScreenCoordinator)
        #expect(detailCoordinator != nil)
    }
    
    @Test
    mutating func replaceDetailsWithTimeline() async throws {
        try await process(route: .roomDetails(roomID: "1"), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomDetailsScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .room(roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
    }
    
    @Test
    mutating func userProfileClearsStack() async throws {
        try await process(route: .roomDetails(roomID: "1"), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomDetailsScreenCoordinator)
        #expect(detailCoordinator != nil)
        #expect(splitCoordinator.sheetCoordinator == nil)
        
        try await process(route: .userProfile(userID: "alice"), expectedState: .userProfileScreen)
        #expect(detailNavigationStack?.rootCoordinator == nil)
        let sheetStackCoordinator = try #require(splitCoordinator.sheetCoordinator as? NavigationStackCoordinator, "There should be a navigation stack presented as a sheet.")
        #expect(sheetStackCoordinator.rootCoordinator is UserProfileScreenCoordinator)
    }
    
    @Test
    mutating func roomClearsStack() async throws {
        try await process(route: .room(roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailNavigationStack?.stackCoordinators.count == 0)
        #expect(detailCoordinator != nil)
        
        chatsTabFlowCoordinator.handleAppRoute(.childRoom(roomID: "2", via: []), animated: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailNavigationStack?.stackCoordinators.count == 1)
        #expect(detailNavigationStack?.stackCoordinators.first is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        try await process(route: .room(roomID: "3", via: []), expectedState: .roomList(detailState: .room(roomID: "3")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailNavigationStack?.stackCoordinators.count == 0)
        #expect(detailCoordinator != nil)
    }
    
    @Test
    mutating func eventRoutes() async throws {
        // A regular event route should set its room as the root of the stack and focus on the event.
        try await process(route: .event(eventID: "1", roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailNavigationStack?.stackCoordinators.count == 0)
        #expect(detailCoordinator != nil)
        #expect(timelineControllerFactory.buildTimelineControllerRoomProxyInitialFocussedEventIDTimelineItemFactoryMediaProviderCallsCount == 1)
        #expect(timelineControllerFactory.buildTimelineControllerRoomProxyInitialFocussedEventIDTimelineItemFactoryMediaProviderReceivedArguments?.initialFocussedEventID == "1")
        
        // A child event route should push a new room screen onto the stack and focus on the event.
        chatsTabFlowCoordinator.handleAppRoute(.childEvent(eventID: "2", roomID: "2", via: []), animated: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailNavigationStack?.stackCoordinators.count == 1)
        #expect(detailNavigationStack?.stackCoordinators.first is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        #expect(timelineControllerFactory.buildTimelineControllerRoomProxyInitialFocussedEventIDTimelineItemFactoryMediaProviderCallsCount == 2)
        #expect(timelineControllerFactory.buildTimelineControllerRoomProxyInitialFocussedEventIDTimelineItemFactoryMediaProviderReceivedArguments?.initialFocussedEventID == "2")
        
        // A subsequent regular event route should clear the stack and set the new room as the root of the stack.
        try await process(route: .event(eventID: "3", roomID: "3", via: []), expectedState: .roomList(detailState: .room(roomID: "3")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailNavigationStack?.stackCoordinators.count == 0)
        #expect(detailCoordinator != nil)
        #expect(timelineControllerFactory.buildTimelineControllerRoomProxyInitialFocussedEventIDTimelineItemFactoryMediaProviderCallsCount == 3)
        #expect(timelineControllerFactory.buildTimelineControllerRoomProxyInitialFocussedEventIDTimelineItemFactoryMediaProviderReceivedArguments?.initialFocussedEventID == "3")
        
        // A regular event route for the same room should set a new instance of the room as the root of the stack.
        try await process(route: .event(eventID: "4", roomID: "3", via: []), expectedState: .roomList(detailState: .room(roomID: "3")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailNavigationStack?.stackCoordinators.count == 0)
        #expect(detailCoordinator != nil)
        #expect(timelineControllerFactory.buildTimelineControllerRoomProxyInitialFocussedEventIDTimelineItemFactoryMediaProviderCallsCount == 4)
        #expect(timelineControllerFactory.buildTimelineControllerRoomProxyInitialFocussedEventIDTimelineItemFactoryMediaProviderReceivedArguments?.initialFocussedEventID == "4",
                "A new timeline should be created for the same room ID, so that the screen isn't stale while loading.")
    }
    
    @Test
    mutating func shareMediaRouteWithRoom() async throws {
        try await process(route: .event(eventID: "1", roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        
        let sharePayload: ShareExtensionPayload = .mediaFiles(roomID: "2", mediaFiles: [.init(url: .picturesDirectory, suggestedName: nil)])
        try await process(route: .share(sharePayload),
                          expectedState: .roomList(detailState: .room(roomID: "2")))
        
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect((splitCoordinator.sheetCoordinator as? NavigationStackCoordinator)?.rootCoordinator is MediaUploadPreviewScreenCoordinator)
    }
    
    @Test
    mutating func shareTextRouteWithRoom() async throws {
        try await process(route: .event(eventID: "1", roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        
        let sharePayload: ShareExtensionPayload = .text(roomID: "2", text: "Important text")
        try await process(route: .share(sharePayload),
                          expectedState: .roomList(detailState: .room(roomID: "2")))
        
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(splitCoordinator.sheetCoordinator == nil, "The media upload sheet shouldn't be shown when sharing text.")
    }
    
    @Test
    mutating func nativeDirectCallDiagnosticCommandFailsClosedWhenRuntimeGateIsDisabled() async throws {
        chatsTabFlowCoordinator = makeChatsTabFlowCoordinator(nativeDirectCallDiagnosticRuntimeGate: Self.disabledDiagnosticRuntimeGate)
        chatsTabFlowCoordinator.start()

        try await process(route: .room(roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))

        let result = await chatsTabFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.prepare)
        #expect(result == .failed(.unavailable))
    }

    @Test
    mutating func nativeDirectCallDiagnosticCommandFailsClosedWithoutActiveRoom() async {
        chatsTabFlowCoordinator = makeChatsTabFlowCoordinator(nativeDirectCallDiagnosticRuntimeGate: Self.enabledDiagnosticRuntimeGate)
        chatsTabFlowCoordinator.start()

        let result = await chatsTabFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.prepare)
        #expect(result == .failed(.unavailable))
    }

    @Test
    mutating func nativeDirectCallDiagnosticCommandForwardsToActiveRoomWhenEnabled() async throws {
        let owner = ChatsTabNativeDirectCallRoomFlowOwnerSpy()
        let session = directCallSession()
        owner.outgoingResult = .success(session)
        chatsTabFlowCoordinator = makeChatsTabFlowCoordinator(nativeDirectCallDiagnosticRuntimeGate: Self.enabledDiagnosticRuntimeGate,
                                                              nativeDirectCallDiagnosticCommandConfiguration: .init(isEnabled: true)) { _ in owner }
        chatsTabFlowCoordinator.start()

        try await process(route: .room(roomID: "1", via: []), expectedState: .roomList(detailState: .room(roomID: "1")))

        #expect(await chatsTabFlowCoordinator.handleNativeDirectCallDiagnosticCommand(.startOutgoingAudioCall) == .outgoingStarted(.init(session)))
        #expect(owner.outgoingCount == 1)
        #expect(owner.startCount == 0)
    }

    // MARK: - Private
    
    private static func disabledDiagnosticRuntimeGate() -> Bool {
        false
    }

    private static func enabledDiagnosticRuntimeGate() -> Bool {
        true
    }

    private func makeChatsTabFlowCoordinator(nativeDirectCallDiagnosticRuntimeGate: @escaping () -> Bool = { ProcessInfo.isRunningUITests },
                                             nativeDirectCallDiagnosticCommandConfiguration: NativeDirectCallRoomDeveloperCommandConfiguration = .init(),
                                             nativeDirectCallRoomFlowOwnerFactory: @escaping @MainActor (JoinedRoomProxyProtocol) -> NativeDirectCallRoomFlowOwning = { roomProxy in
                                                 NativeDirectCallRoomFlowOwner(roomProxy: roomProxy)
                                             }) -> ChatsTabFlowCoordinator {
        ChatsTabFlowCoordinator(isNewLogin: false,
                                navigationSplitCoordinator: splitCoordinator,
                                flowParameters: flowParameters,
                                nativeDirectCallDiagnosticRuntimeGate: nativeDirectCallDiagnosticRuntimeGate,
                                nativeDirectCallDiagnosticCommandConfiguration: nativeDirectCallDiagnosticCommandConfiguration,
                                nativeDirectCallRoomFlowOwnerFactory: nativeDirectCallRoomFlowOwnerFactory)
    }

    private mutating func process(route: AppRoute, expectedState: ChatsTabFlowCoordinatorStateMachine.State) async throws {
        // Sometimes the state machine's state changes before the coordinators have updated the stack.
        let delayedPublisher = stateMachineFactory.chatsTabFlowStatePublisher.delay(for: .milliseconds(100), scheduler: DispatchQueue.main)
        
        let deferred = deferFulfillment(delayedPublisher) { $0 == expectedState }
        chatsTabFlowCoordinator.handleAppRoute(route, animated: true)
        try await deferred.fulfill()
    }
}

@MainActor
private final class ChatsTabNativeDirectCallRoomFlowOwnerSpy: NativeDirectCallRoomFlowOwning {
    private(set) var outgoingCount = 0
    private(set) var startCount = 0

    var isListenerStarted = false
    var activeSession: DirectCallSession?
    var outgoingResult: Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> = .failure(.disabled)

    func prepare() -> Result<NativeDirectCallComposition, NativeDirectCallRoomFlowOwnerError> {
        .failure(.disabled)
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
        .failure(.disabled)
    }

    func hangup() async -> Result<DirectCallSession, NativeDirectCallRoomFlowOwnerError> {
        .failure(.disabled)
    }

    func stop() { }

    func beginReset() { }

    func reset() async { }
}

private func directCallSession() -> DirectCallSession {
    .init(callID: "call",
          roomID: "1",
          peerUserID: "@peer:example.com",
          direction: .outgoing,
          intent: .audio,
          encryptionMode: .e2eeRequired,
          startedAt: .now,
          updatedAt: .now,
          state: .activeAudio,
          encryptionState: .ready)
}
