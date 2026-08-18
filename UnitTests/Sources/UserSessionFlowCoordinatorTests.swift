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
import UIKit

@MainActor
struct UserSessionFlowCoordinatorTests {
    private var userSessionFlowCoordinator: UserSessionFlowCoordinator!
    private var rootCoordinator: NavigationRootCoordinator!
    private var userIndicatorController: UserIndicatorControllerMock!
    private var flowParameters: CommonFlowParameters!
    private var clientProxy: ClientProxyMock!
    private let stateMachineFactory = PublishedStateMachineFactory()
    
    private let networkReachabilitySubject: CurrentValueSubject<NetworkMonitorReachability, Never> = .init(.reachable)
    private let homeserverReachabilitySubject: CurrentValueSubject<NetworkMonitorReachability, Never> = .init(.reachable)
    private let flowElementCallServiceActions = PassthroughSubject<ElementCallServiceAction, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    private var tabCoordinator: NavigationTabCoordinator<UserSessionFlowCoordinator.HomeTab>? {
        rootCoordinator?.rootCoordinator as? NavigationTabCoordinator
    }
    
    private var chatsSplitCoordinator: NavigationSplitCoordinator? {
        tabCoordinator?.tabCoordinators.first as? NavigationSplitCoordinator
    }
    
    private var detailCoordinator: CoordinatorProtocol? {
        chatsSplitCoordinator?.detailCoordinator
    }
    
    private var detailNavigationStack: NavigationStackCoordinator? {
        detailCoordinator as? NavigationStackCoordinator
    }
    
    private var settingsNavigationStack: NavigationStackCoordinator? {
        tabCoordinator?.tabCoordinators.last as? NavigationStackCoordinator
    }
    
    init() async throws {
        rootCoordinator = NavigationRootCoordinator()
        
        clientProxy = ClientProxyMock(.init(userID: "hi@bob",
                                            deviceID: "TEST_DEVICE",
                                            roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(.mockRooms)))))
        clientProxy.homeserverReachabilityPublisher = homeserverReachabilitySubject.asCurrentValuePublisher()
        
        let networkMonitor = NetworkMonitorMock.default
        networkMonitor.reachabilityPublisher = networkReachabilitySubject.asCurrentValuePublisher()
        let appMediator = AppMediatorMock.default
        appMediator.networkMonitor = networkMonitor
        let windowManager = WindowManagerMock()
        windowManager.mainWindow = UIWindow()
        appMediator.windowManager = windowManager
        
        userIndicatorController = UserIndicatorControllerMock()

        let elementCallService = ElementCallServiceMock(.init())
        elementCallService.underlyingActions = flowElementCallServiceActions.eraseToAnyPublisher()
        
        flowParameters = CommonFlowParameters(userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                              bugReportService: BugReportServiceMock(.init()),
                                              elementCallService: elementCallService,
                                              directCallEngine: DirectCallEngine(ownUserID: "hi@bob") { _ in nil },
                                              timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                              emojiProvider: EmojiProvider(appSettings: ServiceLocator.shared.settings),
                                              linkMetadataProvider: LinkMetadataProvider(),
                                              appMediator: appMediator,
                                              appSettings: ServiceLocator.shared.settings,
                                              appHooks: AppHooks(),
                                              analytics: ServiceLocator.shared.analytics,
                                              userIndicatorController: userIndicatorController,
                                              notificationManager: NotificationManagerMock(),
                                              stateMachineFactory: stateMachineFactory)
        
        userSessionFlowCoordinator = UserSessionFlowCoordinator(isNewLogin: false,
                                                                navigationRootCoordinator: rootCoordinator,
                                                                appLockService: AppLockServiceMock(),
                                                                flowParameters: flowParameters)
        
        userSessionFlowCoordinator.start()
    }
    
    // MARK: Navigation
    
    @Test
    func initialState() {
        #expect(chatsSplitCoordinator != nil)
        #expect(detailCoordinator == nil)
    }

    @Test
    func nativeDirectCallVerificationDiagnosticCommandIsUnavailableWhenDiagnosticGateDisabled() async {
        let coordinator = makeUserSessionFlowCoordinator {
            false
        }

        let result = await coordinator.nativeDirectCallVerificationDiagnosticCommand(.status)

        #expect(result.outcome == .failed)
        #expect(result.reason == .unavailable)
        #expect(result.snapshot.verificationFlowState == .unavailable)
    }
    
    @Test
    mutating func settingsPresentation() async throws {
        try await process(route: .settings)
        #expect(tabCoordinator?.selectedTab == .settings)
        #expect(settingsNavigationStack?.rootCoordinator is SettingsScreenCoordinator)
    }
    
    @Test
    mutating func roomPresentation() async throws {
        try await process(route: .room(roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
    }
    
    @Test
    mutating func roomPresentationClearsSettings() async throws {
        try await process(route: .settings)
        #expect(tabCoordinator?.selectedTab == .settings)
        #expect(settingsNavigationStack?.rootCoordinator is SettingsScreenCoordinator)
        #expect(detailCoordinator == nil)
        
        try await process(route: .room(roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        #expect(tabCoordinator?.selectedTab == .chats)
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
    }

    @Test
    func embeddedElementCallPresentationAwaitsCallScreenOverlay() async {
        await userSessionFlowCoordinator.presentEmbeddedElementCall(roomID: "1", startMode: .audio)

        #expect(tabCoordinator?.overlayCoordinator is CallScreenCoordinator)
    }

    @Test
    func applicationActivationRoutesOnceToExistingActiveCall() async throws {
        await userSessionFlowCoordinator.presentEmbeddedElementCall(roomID: "1", startMode: .audio)
        let existingCallScreen = try #require(tabCoordinator?.overlayCoordinator as? CallScreenCoordinator)
        let elementCallService = try #require(flowParameters.elementCallService as? ElementCallServiceMock)
        elementCallService.underlyingOngoingCallRoomIDPublisher = .init(.init("1"))
        let roomLookupCount = clientProxy.roomForIdentifierCallsCount

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        for _ in 0..<50 where clientProxy.roomForIdentifierCallsCount != roomLookupCount + 1 {
            await Task.yield()
        }
        #expect(clientProxy.roomForIdentifierCallsCount == roomLookupCount + 1)
        #expect(tabCoordinator?.overlayCoordinator === existingCallScreen)
    }

    @Test
    func elementCallServiceEndCallDismissalIsOwnedByCallScreen() async throws {
        let elementCallService = try #require(flowParameters.elementCallService as? ElementCallServiceMock)
        let callScreenElementCallServiceActions = PassthroughSubject<ElementCallServiceAction, Never>()
        elementCallService.underlyingActions = callScreenElementCallServiceActions.eraseToAnyPublisher()
        await userSessionFlowCoordinator.presentEmbeddedElementCall(roomID: "1", startMode: .audio)

        let tabCoordinator = try #require(tabCoordinator)
        let callScreenCoordinator = try #require(tabCoordinator.overlayCoordinator as? CallScreenCoordinator)
        let unexpectedDismissal = deferFailure(tabCoordinator.observe(\.overlayCoordinator), timeout: .milliseconds(100)) { $0 == nil }
        flowElementCallServiceActions.send(.endCall(roomID: "1"))
        try await unexpectedDismissal.fulfill()
        #expect(tabCoordinator.overlayCoordinator === callScreenCoordinator)

        let expectedDismissal = deferFulfillment(tabCoordinator.observe(\.overlayCoordinator)) { $0 == nil }
        callScreenElementCallServiceActions.send(.endCall(roomID: "1"))
        try await expectedDismissal.fulfill()
        #expect(tabCoordinator.overlayCoordinator == nil)
    }
    
    @Test
    mutating func childRoomPresentation() async throws {
        try await process(route: .room(roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        let detailNavigationStack = try #require(detailNavigationStack, "There must be a navigation stack.")
        #expect(detailNavigationStack.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        
        let deferred = deferFulfillment(detailNavigationStack.observe(\.stackCoordinators.count)) { $0 == 1 }
        try await process(route: .childRoom(roomID: "2", via: []))
        try await deferred.fulfill()
        #expect(detailNavigationStack.rootCoordinator is RoomScreenCoordinator)
        #expect(detailCoordinator != nil)
        #expect(detailNavigationStack.stackCoordinators.count == 1)
        #expect(detailNavigationStack.stackCoordinators.first is RoomScreenCoordinator)
    }
    
    @Test
    mutating func shareMediaRouteWithoutRoom() async throws {
        try await process(route: .settings)
        #expect(tabCoordinator?.selectedTab == .settings)
        #expect(settingsNavigationStack?.rootCoordinator is SettingsScreenCoordinator)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil)
        
        let sharePayload: ShareExtensionPayload = .mediaFiles(roomID: nil, mediaFiles: [.init(url: .picturesDirectory, suggestedName: nil)])
        try await process(route: .share(sharePayload),
                          expectedChatsState: .shareExtensionRoomList(sharePayload: sharePayload))
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect((chatsSplitCoordinator?.sheetCoordinator as? NavigationStackCoordinator)?.rootCoordinator is RoomSelectionScreenCoordinator)
    }
    
    @Test
    mutating func shareMediaRouteWithRoom() async throws {
        try await process(route: .event(eventID: "1", roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil)
        
        let sharePayload: ShareExtensionPayload = .mediaFiles(roomID: "2", mediaFiles: [.init(url: .picturesDirectory, suggestedName: nil)])
        try await process(route: .share(sharePayload),
                          expectedChatsState: .roomList(detailState: .room(roomID: "2")))
        
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect((chatsSplitCoordinator?.sheetCoordinator as? NavigationStackCoordinator)?.rootCoordinator is MediaUploadPreviewScreenCoordinator)
    }
    
    @Test
    mutating func shareTextRouteWithoutRoom() async throws {
        try await process(route: .settings)
        #expect(tabCoordinator?.selectedTab == .settings)
        #expect(settingsNavigationStack?.rootCoordinator is SettingsScreenCoordinator)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil)
        
        let sharePayload: ShareExtensionPayload = .text(roomID: nil, text: "Important Text")
        try await process(route: .share(sharePayload),
                          expectedChatsState: .shareExtensionRoomList(sharePayload: sharePayload))
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect((chatsSplitCoordinator?.sheetCoordinator as? NavigationStackCoordinator)?.rootCoordinator is RoomSelectionScreenCoordinator)
    }
    
    @Test
    mutating func shareTextRouteWithRoom() async throws {
        try await process(route: .event(eventID: "1", roomID: "1", via: []), expectedChatsState: .roomList(detailState: .room(roomID: "1")))
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil)
        
        let sharePayload: ShareExtensionPayload = .text(roomID: "2", text: "Important text")
        try await process(route: .share(sharePayload),
                          expectedChatsState: .roomList(detailState: .room(roomID: "2")))
        
        #expect(detailNavigationStack?.rootCoordinator is RoomScreenCoordinator)
        #expect(tabCoordinator?.sheetCoordinator == nil)
        #expect(chatsSplitCoordinator?.sheetCoordinator == nil, "The media upload sheet shouldn't be shown when sharing text.")
    }
    
    // MARK: Indicators
    
    @Test
    func reachabilityIndicators() async throws {
        // Given a flow in its initial state.
        try await Task.sleep(for: .milliseconds(100))
        
        // Then no reachability indicators should be shown.
        #expect(!userIndicatorController.submitIndicatorDelayCalled)
        #expect(retractReachabilityIndicatorCallsCount == 1) // The initial state removes the indicator.
        
        // When the homeserver becomes unreachable.
        homeserverReachabilitySubject.send(.unreachable)
        try await Task.sleep(for: .milliseconds(100))
        
        // Then a server unreachable indicator should be shown.
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 1)
        #expect(userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.title == L10n.commonServerUnreachable)
        #expect(retractReachabilityIndicatorCallsCount == 1)
        
        // When the network also becomes unreachable.
        networkReachabilitySubject.send(.unreachable)
        try await Task.sleep(for: .milliseconds(100))
        
        // Then the server unreachable indicator should be replaced with an offline indicator.
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 2)
        #expect(userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.title == L10n.commonOffline)
        #expect(retractReachabilityIndicatorCallsCount == 1)
        
        // When the homeserver becomes reachable again.
        homeserverReachabilitySubject.send(.reachable)
        try await Task.sleep(for: .milliseconds(100))
        
        // Then there should still be an offline indicator (as we don't yet support air-gapped servers on iOS).
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 3)
        #expect(userIndicatorController.submitIndicatorDelayReceivedArguments?.indicator.title == L10n.commonOffline)
        #expect(retractReachabilityIndicatorCallsCount == 1)
        
        // When the network becomes reachable again.
        networkReachabilitySubject.send(.reachable)
        try await Task.sleep(for: .milliseconds(100))
        
        // Then the indicator should be hidden now as everything is back to normal
        #expect(userIndicatorController.submitIndicatorDelayCallsCount == 3)
        #expect(retractReachabilityIndicatorCallsCount == 2)
    }
    
    // MARK: - Helpers
    
    private mutating func process(route: AppRoute,
                                  expectedUserSessionState: UserSessionFlowCoordinator.State? = nil,
                                  expectedChatsState: ChatsTabFlowCoordinatorStateMachine.State? = nil) async throws {
        let deferredUserSession: DeferredFulfillment<UserSessionFlowCoordinator.State>? = if let expectedUserSessionState {
            deferFulfillment(stateMachineFactory.userSessionFlowStatePublisher.delay(for: .milliseconds(100), scheduler: DispatchQueue.main)) {
                $0 == expectedUserSessionState
            }
        } else {
            nil
        }
        
        let deferredChatsState: DeferredFulfillment<ChatsTabFlowCoordinatorStateMachine.State>? = if let expectedChatsState {
            deferFulfillment(stateMachineFactory.chatsTabFlowStatePublisher.delay(for: .milliseconds(100), scheduler: DispatchQueue.main)) {
                $0 == expectedChatsState
            }
        } else {
            nil
        }
        
        userSessionFlowCoordinator.handleAppRoute(route, animated: true)
        try await deferredUserSession?.fulfill()
        try await deferredChatsState?.fulfill()
    }

    private func makeUserSessionFlowCoordinator(nativeDirectCallDiagnosticRuntimeGate: @escaping () -> Bool) -> UserSessionFlowCoordinator {
        UserSessionFlowCoordinator(isNewLogin: false,
                                   navigationRootCoordinator: NavigationRootCoordinator(),
                                   appLockService: AppLockServiceMock(),
                                   flowParameters: flowParameters,
                                   nativeDirectCallDiagnosticRuntimeGate: nativeDirectCallDiagnosticRuntimeGate)
    }
    
    /// Other services retract indicators, so this filters based on the reachability ID.
    private var retractReachabilityIndicatorCallsCount: Int {
        userIndicatorController
            .retractIndicatorWithIdReceivedInvocations
            .filter { $0 == "io.element.elementx.reachability.notification" }
            .count
    }
}
