//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVKit
import Combine
import Compound
import SwiftState
import SwiftUI

enum UserSessionFlowCoordinatorAction {
    case logout
    case clearCache
    /// Logout and disable App Lock without any confirmation. The user forgot their PIN.
    case forceLogout
}

class UserSessionFlowCoordinator: FlowCoordinatorProtocol {
    enum HomeTab: Hashable {
        case chats, calls, contacts, settings
    }
    
    private let navigationRootCoordinator: NavigationRootCoordinator
    private let navigationTabCoordinator: NavigationTabCoordinator<HomeTab>
    private let appLockService: AppLockServiceProtocol
    private let flowParameters: CommonFlowParameters
    
    private var userSession: UserSessionProtocol {
        flowParameters.userSession
    }
    
    private let onboardingFlowCoordinator: OnboardingFlowCoordinator
    private let onboardingStackCoordinator: NavigationStackCoordinator
    private let chatsTabFlowCoordinator: ChatsTabFlowCoordinator
    private let chatsTabDetails: NavigationTabCoordinator<HomeTab>.TabDetails
    private let callsTabNavigationStackCoordinator: NavigationStackCoordinator
    private let callsTabFlowCoordinator: CallsTabFlowCoordinator
    private let callsTabDetails: NavigationTabCoordinator<HomeTab>.TabDetails
    private let contactsTabNavigationStackCoordinator: NavigationStackCoordinator
    private let contactsTabFlowCoordinator: ContactsTabFlowCoordinator
    private let contactsTabDetails: NavigationTabCoordinator<HomeTab>.TabDetails
    private let settingsTabNavigationStackCoordinator: NavigationStackCoordinator
    private let settingsTabDetails: NavigationTabCoordinator<HomeTab>.TabDetails
    
    // periphery:ignore - retaining purpose
    private var settingsFlowCoordinator: SettingsFlowCoordinator?
    private let nativeDirectCallDiagnosticRuntimeGate: () -> Bool
    
    enum State: StateType {
        /// The state machine hasn't started.
        case initial
        /// The root screen for this flow.
        case tabBar
        /// Showing the settings screen.
        case settingsScreen
    }
    
    enum Event: EventType {
        /// The flow is being started.
        case start
        
        /// Request presentation of the settings screen.
        case showSettingsScreen
        /// The settings screen has been dismissed.
        case dismissedSettingsScreen
    }
    
    private let stateMachine: StateMachine<State, Event>
    private var cancellables: Set<AnyCancellable> = []
    private var activeCallStartMode: ElementCallStartMode?
    
    private let actionsSubject: PassthroughSubject<UserSessionFlowCoordinatorAction, Never> = .init()
    private var hasHandledInitialSecurityGate = false
    var actionsPublisher: AnyPublisher<UserSessionFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(isNewLogin: Bool,
         navigationRootCoordinator: NavigationRootCoordinator,
         appLockService: AppLockServiceProtocol,
         flowParameters: CommonFlowParameters,
         nativeDirectCallDiagnosticRuntimeGate: @escaping () -> Bool = { ProcessInfo.isRunningUITests },
         nativeDirectCallDiagnosticCommandConfiguration: NativeDirectCallRoomDeveloperCommandConfiguration = .init(),
         nativeDirectCallRoomFlowOwnerFactory: @escaping @MainActor (JoinedRoomProxyProtocol) -> NativeDirectCallRoomFlowOwning = { roomProxy in
             NativeDirectCallRoomFlowOwner(roomProxy: roomProxy)
         }) {
        self.navigationRootCoordinator = navigationRootCoordinator
        self.appLockService = appLockService
        self.flowParameters = flowParameters
        self.nativeDirectCallDiagnosticRuntimeGate = nativeDirectCallDiagnosticRuntimeGate
        
        navigationTabCoordinator = NavigationTabCoordinator()
        navigationRootCoordinator.setRootCoordinator(navigationTabCoordinator)
        
        let chatsSplitCoordinator = NavigationSplitCoordinator(placeholderCoordinator: PlaceholderScreenCoordinator(hideBrandChrome: flowParameters.appSettings.hideBrandChrome))
        chatsTabFlowCoordinator = ChatsTabFlowCoordinator(isNewLogin: isNewLogin,
                                                          navigationSplitCoordinator: chatsSplitCoordinator,
                                                          flowParameters: flowParameters,
                                                          nativeDirectCallDiagnosticRuntimeGate: nativeDirectCallDiagnosticRuntimeGate,
                                                          nativeDirectCallDiagnosticCommandConfiguration: nativeDirectCallDiagnosticCommandConfiguration,
                                                          nativeDirectCallRoomFlowOwnerFactory: nativeDirectCallRoomFlowOwnerFactory)
        chatsTabDetails = .init(tag: HomeTab.chats, title: L10n.screenHomeTabChats, icon: \.chat, selectedIcon: \.chatSolid)
        chatsTabDetails.navigationSplitCoordinator = chatsSplitCoordinator

        callsTabNavigationStackCoordinator = NavigationStackCoordinator()
        callsTabFlowCoordinator = CallsTabFlowCoordinator(navigationStackCoordinator: callsTabNavigationStackCoordinator,
                                                          flowParameters: flowParameters)
        callsTabDetails = .init(tag: HomeTab.calls,
                                title: UntranslatedL10n.screenHomeTabCalls,
                                icon: \.voiceCall,
                                selectedIcon: \.voiceCallSolid)

        contactsTabNavigationStackCoordinator = NavigationStackCoordinator()
        contactsTabFlowCoordinator = ContactsTabFlowCoordinator(navigationStackCoordinator: contactsTabNavigationStackCoordinator,
                                                                flowParameters: flowParameters)
        contactsTabDetails = .init(tag: HomeTab.contacts,
                                   title: L10n.screenContactsTitle,
                                   icon: \.userProfile,
                                   selectedIcon: \.userProfileSolid)
        settingsTabNavigationStackCoordinator = NavigationStackCoordinator()
        settingsTabDetails = .init(tag: HomeTab.settings,
                                   title: L10n.commonSettings,
                                   icon: \.settings,
                                   selectedIcon: \.settings)
        settingsFlowCoordinator = SettingsFlowCoordinator(appLockService: appLockService,
                                                          navigationStackCoordinator: settingsTabNavigationStackCoordinator,
                                                          flowParameters: flowParameters)
        
        onboardingStackCoordinator = NavigationStackCoordinator()
        onboardingFlowCoordinator = OnboardingFlowCoordinator(isNewLogin: isNewLogin,
                                                              appLockService: appLockService,
                                                              navigationStackCoordinator: onboardingStackCoordinator,
                                                              flowParameters: flowParameters)
        
        navigationTabCoordinator.setTabs([
            .init(coordinator: chatsSplitCoordinator, details: chatsTabDetails),
            .init(coordinator: callsTabNavigationStackCoordinator, details: callsTabDetails),
            .init(coordinator: contactsTabNavigationStackCoordinator, details: contactsTabDetails),
            .init(coordinator: settingsTabNavigationStackCoordinator, details: settingsTabDetails)
        ])
        
        stateMachine = flowParameters.stateMachineFactory.makeUserSessionFlowStateMachine(state: .initial)
        configureStateMachine()
        
        setupObservers()
    }
    
    func start(animated: Bool) {
        stateMachine.tryEvent(.start)
    }
    
    func stop() {
        chatsTabFlowCoordinator.stop()
    }
    
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        switch appRoute {
        case .accountProvisioningLink:
            break // We always ignore this flow when logged in.
        case .settings, .chatBackupSettings:
            clearPresentedSheets(animated: animated)
            if navigationTabCoordinator.selectedTab != .settings {
                navigationTabCoordinator.selectedTab = .settings
            }
            settingsFlowCoordinator?.handleAppRoute(appRoute, animated: animated)
        case .call(let roomID):
            Task { await presentCallScreen(roomID: roomID) }
        case .genericCallLink(let url):
            presentCallScreen(genericCallLink: url)
        case .roomList, .room, .roomAlias, .childRoom, .childRoomAlias,
             .roomDetails, .roomMemberDetails, .userProfile,
             .event, .eventOnRoomAlias, .childEvent, .childEventOnRoomAlias,
             .share, .transferOwnership, .thread:
            clearPresentedSheets(animated: animated) // Make sure the presented route is visible.
            chatsTabFlowCoordinator.handleAppRoute(appRoute, animated: animated)
            if navigationTabCoordinator.selectedTab != .chats {
                navigationTabCoordinator.selectedTab = .chats
            }
        }
    }
    
    func clearRoute(animated: Bool) {
        clearPresentedSheets(animated: animated)
        chatsTabFlowCoordinator.clearRoute(animated: animated)
    }

    func startCall(roomID: String, startMode: ElementCallStartMode) {
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][USER-SESSION-START-CALL] room_id=\(roomID) start_mode=\(startMode)")
        Task { await presentCallScreen(roomID: roomID, startMode: startMode) }
    }
    
    /// Clearing routes is more complicated than it first seems. When passing routes
    /// to the chats flow we can't clear all routes as e.g. childRoom/childEvent etc
    /// expect to push into the existing stack. But we do need to hide any sheets that
    /// might cover up the presented route. BUT! We probably shouldn't dismiss onboarding
    /// or verification flows until they're complete… This needs more thought before we
    /// codify it all into the state machine.
    private func clearPresentedSheets(animated: Bool) {
        switch stateMachine.state {
        case .initial, .tabBar:
            break
        case .settingsScreen:
            navigationTabCoordinator.setSheetCoordinator(nil, animated: animated)
        }
    }
    
    func isDisplayingRoomScreen(withRoomID roomID: String) -> Bool {
        guard navigationTabCoordinator.selectedTab == .chats else { return false }
        return chatsTabFlowCoordinator.isDisplayingRoomScreen(withRoomID: roomID)
    }
    
    #if DEBUG
    func handleNativeDirectCallDiagnosticCommand(_ command: NativeDirectCallRoomDiagnosticCommand) async -> NativeDirectCallRoomDiagnosticCommandResult {
        guard nativeDirectCallDiagnosticRuntimeGate(),
              navigationTabCoordinator.selectedTab == .chats else {
            return .failed(.unavailable)
        }

        return await chatsTabFlowCoordinator.handleNativeDirectCallDiagnosticCommand(command)
    }

    func nativeDirectCallDiagnosticStatus() -> NativeDirectCallRoomDiagnosticStatus {
        guard nativeDirectCallDiagnosticRuntimeGate(),
              navigationTabCoordinator.selectedTab == .chats else {
            return .unavailable
        }

        return chatsTabFlowCoordinator.nativeDirectCallDiagnosticStatus()
    }
    #endif

    // MARK: - Private
    
    private func configureStateMachine() {
        stateMachine.addRoutes(event: .start, transitions: [.initial => .tabBar]) { [weak self] _ in
            guard let self else { return }
            
            chatsTabFlowCoordinator.start()
            callsTabFlowCoordinator.start(animated: false)
            contactsTabFlowCoordinator.start(animated: false)
            settingsFlowCoordinator?.handleAppRoute(.settings, animated: false)
            attemptStartingOnboarding()
        }
        
        stateMachine.addRoutes(event: .showSettingsScreen, transitions: [.tabBar => .settingsScreen]) { [weak self] _ in
            self?.startSettingsFlow()
        }
        stateMachine.addRoutes(event: .dismissedSettingsScreen, transitions: [.settingsScreen => .tabBar]) { [weak self] _ in
            self?.settingsFlowCoordinator = nil
        }
        
        stateMachine.addErrorHandler { context in
            fatalError("Unexpected transition: \(context)")
        }
    }
    
    private func setupObservers() {
        chatsTabFlowCoordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .switchToChatsTab:
                    navigationTabCoordinator.selectedTab = .chats
                case .showSettings:
                    handleAppRoute(.settings, animated: true)
                case .showChatBackupSettings:
                    handleAppRoute(.chatBackupSettings, animated: true)
                case .sessionVerification(let flow):
                    presentSessionVerificationScreen(flow: flow)
                case .showCallScreen(let roomProxy, let startMode):
                    presentCallScreen(roomProxy: roomProxy, startMode: startMode)
                case .hideCallScreenOverlay:
                    hideCallScreenOverlay()
                case .logout:
                    Task { await self.runLogoutFlow() }
                }
            }
            .store(in: &cancellables)

        observeContactsTabActions()
        observeCallsTabActions()

        observeSettingsFlowActionsIfNeeded()
        
        userSession.sessionSecurityStatePublisher
            .map(\.verificationState)
            .filter { $0 != .unknown }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                
                attemptStartingOnboarding()
                setupSessionVerificationRequestsObserver()
            }
            .store(in: &cancellables)
        
        let reachabilityNotificationID = "io.element.elementx.reachability.notification"
        userSession.clientProxy.homeserverReachabilityPublisher.removeDuplicates()
            .combineLatest(flowParameters.appMediator.networkMonitor.reachabilityPublisher.removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] homeserverReachability, networkReachability in
                MXLog.info("Homeserver reachability: \(homeserverReachability)")
                
                guard let self else { return }
                switch (networkReachability, homeserverReachability) {
                case (.reachable, .reachable):
                    flowParameters.userIndicatorController.retractIndicatorWithId(reachabilityNotificationID)
                case (.reachable, .unreachable):
                    flowParameters.userIndicatorController.submitIndicator(.init(id: reachabilityNotificationID,
                                                                                 title: L10n.commonServerUnreachable,
                                                                                 persistent: true))
                case (.unreachable, _):
                    flowParameters.userIndicatorController.submitIndicator(.init(id: reachabilityNotificationID,
                                                                                 title: L10n.commonOffline,
                                                                                 persistent: true))
                }
            }
            .store(in: &cancellables)
        
        onboardingFlowCoordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .requestPresentation(let animated):
                    navigationTabCoordinator.setFullScreenCoverCoordinator(onboardingStackCoordinator, animated: animated)
                case .dismiss:
                    navigationTabCoordinator.setFullScreenCoverCoordinator(nil)
                case .logout:
                    logout()
                }
            }
            .store(in: &cancellables)
        
        flowParameters.elementCallService.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                switch action {
                case .endCall:
                    self?.dismissCallScreenIfNeeded()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func observeSettingsFlowActionsIfNeeded() {
        guard let settingsFlowCoordinator else {
            return
        }

        settingsFlowCoordinator.actions
            .sink { [weak self] action in
                guard let self else { return }

                switch action {
                case .dismiss:
                    navigationTabCoordinator.selectedTab = .chats
                case .clearCache:
                    actionsSubject.send(.clearCache)
                case .runLogoutFlow:
                    Task { await self.runLogoutFlow() }
                case .forceLogout:
                    actionsSubject.send(.forceLogout)
                }
            }
            .store(in: &cancellables)
    }

    private func observeContactsTabActions() {
        contactsTabFlowCoordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }

                switch action {
                case .openRoom(let roomID):
                    navigationTabCoordinator.selectedTab = .chats
                    chatsTabFlowCoordinator.openRoom(roomID: roomID, animated: true)
                }
            }
            .store(in: &cancellables)
    }

    private func observeCallsTabActions() {
        callsTabFlowCoordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }

                switch action {
                case .openRoom(let roomID):
                    navigationTabCoordinator.selectedTab = .chats
                    chatsTabFlowCoordinator.openRoom(roomID: roomID, animated: true)
                case .startCall(let roomID, let startMode):
                    Task { await self.presentCallScreen(roomID: roomID, startMode: startMode) }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Onboarding
    
    private func attemptStartingOnboarding() {
        let recoveryState = userSession.clientProxy.secureBackupController.recoveryState.value

        if hasHandledInitialSecurityGate {
            return
        }

        switch recoveryState {
        case .unknown, .settingUp:
            MXLog.info("Security state is still unknown, waiting before deciding post-login flow")
            return

        case .incomplete:
            hasHandledInitialSecurityGate = true
            MXLog.info("Recovery is incomplete, presenting recovery key screen")
            presentInitialRecoveryKeyScreen()

        case .enabled:
            hasHandledInitialSecurityGate = true
            MXLog.info("Recovery is enabled, skipping onboarding and opening chats directly")

        case .disabled:
            hasHandledInitialSecurityGate = true
            MXLog.warning("Recovery is disabled, skipping onboarding and opening chats directly")

        @unknown default:
            hasHandledInitialSecurityGate = true
            MXLog.warning("Unhandled recovery state, skipping onboarding and opening chats directly")
        }
    }

    private func presentInitialRecoveryKeyScreen() {
        let sheetNavigationStackCoordinator = NavigationStackCoordinator()

        let parameters = SecureBackupRecoveryKeyScreenCoordinatorParameters(secureBackupController: userSession.clientProxy.secureBackupController,
                                                                            userIndicatorController: flowParameters.userIndicatorController,
                                                                            isModallyPresented: true)

        let coordinator = SecureBackupRecoveryKeyScreenCoordinator(parameters: parameters)

        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }

                switch action {
                case .complete:
                    navigationTabCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)

        sheetNavigationStackCoordinator.setRootCoordinator(coordinator)
        navigationTabCoordinator.setSheetCoordinator(sheetNavigationStackCoordinator, animated: true)
    }

    // MARK: - Settings
    
    private func startSettingsFlow() {
        let navigationStackCoordinator = NavigationStackCoordinator()
        let coordinator = SettingsFlowCoordinator(appLockService: appLockService,
                                                  navigationStackCoordinator: navigationStackCoordinator,
                                                  flowParameters: flowParameters)
        
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .dismiss:
                navigationTabCoordinator.setSheetCoordinator(nil)
            case .clearCache:
                actionsSubject.send(.clearCache)
            case .runLogoutFlow:
                Task {
                    self.navigationTabCoordinator.setSheetCoordinator(nil)
                    
                    // The sheet needs to be dismissed before the alert can be shown
                    try await Task.sleep(for: .milliseconds(100))
                    await self.runLogoutFlow()
                }
            case .forceLogout:
                actionsSubject.send(.forceLogout)
            }
        }
        .store(in: &cancellables)
        
        settingsFlowCoordinator = coordinator
        coordinator.handleAppRoute(.settings, animated: false)
        
        navigationTabCoordinator.setSheetCoordinator(navigationStackCoordinator) { [weak self] in
            self?.stateMachine.tryEvent(.dismissedSettingsScreen)
        }
    }
    
    // MARK: - Session Verification
    
    private func setupSessionVerificationRequestsObserver() {
        userSession.clientProxy.sessionVerificationController?.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard let self, case .receivedVerificationRequest(let details) = action else {
                    return
                }
                
                MXLog.info("Received session verification request")
                
                if details.senderProfile.userID == userSession.clientProxy.userID {
                    presentSessionVerificationScreen(flow: .deviceResponder(requestDetails: details))
                } else {
                    presentSessionVerificationScreen(flow: .userResponder(requestDetails: details))
                }
            }
            .store(in: &cancellables)
    }
    
    private func presentSessionVerificationScreen(flow: SessionVerificationScreenFlow) {
        guard let sessionVerificationController = userSession.clientProxy.sessionVerificationController else {
            fatalError("The sessionVerificationController should aways be valid at this point")
        }
        
        let navigationStackCoordinator = NavigationStackCoordinator()
        
        let parameters = SessionVerificationScreenCoordinatorParameters(sessionVerificationControllerProxy: sessionVerificationController,
                                                                        flow: flow,
                                                                        appSettings: flowParameters.appSettings,
                                                                        mediaProvider: userSession.mediaProvider)
        
        let coordinator = SessionVerificationScreenCoordinator(parameters: parameters)
        
        coordinator.actions
            .sink { [weak self] action in
                switch action {
                case .done:
                    self?.navigationTabCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.setRootCoordinator(coordinator)
        
        navigationTabCoordinator.setSheetCoordinator(navigationStackCoordinator)
    }
    
    // MARK: - Calls
    
    private func presentCallScreen(genericCallLink url: URL) {
        presentCallScreen(configuration: .init(genericCallLink: url))
    }
    
    private func presentCallScreen(roomID: String, startMode: ElementCallStartMode = .video) async {
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][USER-SESSION-PRESENT-BY-ID] room_id=\(roomID) start_mode=\(startMode)")
        guard case let .joined(roomProxy) = await userSession.clientProxy.roomForIdentifier(roomID) else {
            return
        }
        
        presentCallScreen(roomProxy: roomProxy, startMode: startMode)
    }
    
    private func presentCallScreen(roomProxy: JoinedRoomProxyProtocol, startMode: ElementCallStartMode = .video) {
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][USER-SESSION-PRESENT-ROOM] room_id=\(roomProxy.id) start_mode=\(startMode)")
        let colorScheme: ColorScheme = flowParameters.windowManager.mainWindow.traitCollection.userInterfaceStyle == .light ? .light : .dark
        presentCallScreen(configuration: .init(roomProxy: roomProxy,
                                               clientProxy: userSession.clientProxy,
                                               clientID: InfoPlistReader.main.bundleIdentifier,
                                               elementCallBaseURL: flowParameters.appSettings.elementCallBaseURL,
                                               elementCallBaseURLOverride: flowParameters.appSettings.elementCallBaseURLOverride,
                                               colorScheme: colorScheme,
                                               startMode: startMode))
    }
    
    private var callScreenPictureInPictureController: AVPictureInPictureController?
    private func presentCallScreen(configuration: ElementCallConfiguration) {
        guard flowParameters.ongoingCallRoomIDPublisher.value != configuration.callRoomID else {
            MXLog.info("Returning to existing call.")
            callScreenPictureInPictureController?.stopPictureInPicture()
            navigationTabCoordinator.setOverlayPresentationMode(.fullScreen)
            return
        }

        activeCallStartMode = configuration.startMode
        
        let callScreenCoordinator = CallScreenCoordinator(parameters: .init(elementCallService: flowParameters.elementCallService,
                                                                            configuration: configuration,
                                                                            allowPictureInPicture: configuration.startMode == .video,
                                                                            mediaProvider: userSession.mediaProvider,
                                                                            appSettings: flowParameters.appSettings,
                                                                            appHooks: flowParameters.appHooks,
                                                                            analytics: flowParameters.analytics))
        
        callScreenCoordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .pictureInPictureIsAvailable(let controller):
                    callScreenPictureInPictureController = controller
                case .pictureInPictureStarted:
                    navigationTabCoordinator.setOverlayPresentationMode(.minimized)
                case .pictureInPictureStopped:
                    navigationTabCoordinator.setOverlayPresentationMode(.fullScreen)
                case .dismiss:
                    activeCallStartMode = nil
                    callScreenPictureInPictureController = nil
                    navigationTabCoordinator.setOverlayCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        
        navigationTabCoordinator.setOverlayCoordinator(callScreenCoordinator, animated: true)
        
        flowParameters.analytics.track(screen: .RoomCall)
    }
    
    private func hideCallScreenOverlay() {
        guard activeCallStartMode == .video else {
            MXLog.info("Minimizing audio call without Picture in Picture.")
            navigationTabCoordinator.setOverlayPresentationMode(.minimized)
            return
        }

        guard let callScreenPictureInPictureController else {
            MXLog.warning("Picture in picture isn't available, keeping the call screen visible.")
            navigationTabCoordinator.setOverlayPresentationMode(.fullScreen)
            return
        }
        
        callScreenPictureInPictureController.startPictureInPicture()
        navigationTabCoordinator.setOverlayPresentationMode(.minimized)
    }
    
    private func dismissCallScreenIfNeeded() {
        guard navigationTabCoordinator.overlayCoordinator is CallScreenCoordinator else {
            return
        }

        navigationTabCoordinator.setOverlayCoordinator(nil)
    }

    // MARK: - Logout
    
    private func runLogoutFlow() async {
        let secureBackupController = userSession.clientProxy.secureBackupController
        
        guard case let .success(isLastDevice) = await userSession.clientProxy.isOnlyDeviceLeft() else {
            navigationRootCoordinator.alertInfo = .init(id: .init())
            return
        }
        
        guard isLastDevice else {
            logout()
            return
        }
        
        guard secureBackupController.recoveryState.value == .enabled else {
            navigationRootCoordinator.alertInfo = .init(id: .init(),
                                                        title: L10n.screenSignoutRecoveryDisabledTitle,
                                                        message: L10n.screenSignoutRecoveryDisabledSubtitle,
                                                        primaryButton: .init(title: L10n.screenSignoutConfirmationDialogSubmit, role: .destructive) { [weak self] in
                                                            self?.actionsSubject.send(.logout)
                                                        }, secondaryButton: .init(title: L10n.commonSettings, role: .cancel) { [weak self] in
                                                            self?.handleAppRoute(.chatBackupSettings, animated: true)
                                                        })
            return
        }
        
        guard secureBackupController.keyBackupState.value == .enabled else {
            navigationRootCoordinator.alertInfo = .init(id: .init(),
                                                        title: L10n.screenSignoutKeyBackupDisabledTitle,
                                                        message: L10n.screenSignoutKeyBackupDisabledSubtitle,
                                                        primaryButton: .init(title: L10n.screenSignoutConfirmationDialogSubmit, role: .destructive) { [weak self] in
                                                            self?.actionsSubject.send(.logout)
                                                        }, secondaryButton: .init(title: L10n.commonSettings, role: .cancel) { [weak self] in
                                                            self?.handleAppRoute(.chatBackupSettings, animated: true)
                                                        })
            return
        }
        
        presentSecureBackupLogoutConfirmationScreen()
    }
    
    private func logout() {
        navigationRootCoordinator.alertInfo = .init(id: .init(),
                                                    title: L10n.screenSignoutConfirmationDialogTitle,
                                                    message: L10n.screenSignoutConfirmationDialogContent,
                                                    primaryButton: .init(title: L10n.screenSignoutConfirmationDialogSubmit, role: .destructive) { [weak self] in
                                                        self?.actionsSubject.send(.logout)
                                                    })
    }
    
    private func presentSecureBackupLogoutConfirmationScreen() {
        let coordinator = SecureBackupLogoutConfirmationScreenCoordinator(parameters: .init(secureBackupController: userSession.clientProxy.secureBackupController,
                                                                                            homeserverReachabilityPublisher: userSession.clientProxy.homeserverReachabilityPublisher))
        
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .cancel:
                    navigationTabCoordinator.setSheetCoordinator(nil)
                case .settings:
                    navigationTabCoordinator.setSheetCoordinator(nil)
                    handleAppRoute(.chatBackupSettings, animated: true)
                case .logout:
                    actionsSubject.send(.logout)
                }
            }
            .store(in: &cancellables)
        
        navigationTabCoordinator.setSheetCoordinator(coordinator, animated: true)
    }
}
