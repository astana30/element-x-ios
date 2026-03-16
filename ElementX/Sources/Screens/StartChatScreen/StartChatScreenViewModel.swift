//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import MatrixRustSDK
import SwiftUI

typealias StartChatScreenViewModelType = StateStoreViewModel<StartChatScreenViewState, StartChatScreenViewAction>

class StartChatScreenViewModel: StartChatScreenViewModelType, StartChatScreenViewModelProtocol {
    private let userSession: UserSessionProtocol
    private let analytics: AnalyticsService
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let userDiscoveryService: UserDiscoveryServiceProtocol
    private let appSettings: AppSettings
    
    private var knownUsers = [UserProfileProxy]()
    
    private let actionsSubject: PassthroughSubject<StartChatScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<StartChatScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(userSession: UserSessionProtocol,
         analytics: AnalyticsService,
         userIndicatorController: UserIndicatorControllerProtocol,
         userDiscoveryService: UserDiscoveryServiceProtocol,
         appSettings: AppSettings,
         mode: StartChatScreenMode = .startChatFlow) {
        self.userSession = userSession
        self.analytics = analytics
        self.userIndicatorController = userIndicatorController
        self.userDiscoveryService = userDiscoveryService
        self.appSettings = appSettings
        
        let initialViewState: StartChatScreenViewState
        
        switch mode {
        case .startChatFlow:
            initialViewState = StartChatScreenViewState(userID: userSession.clientProxy.userID,
                                                        screenTitle: L10n.screenContactsTitle,
                                                        showsCloseButton: true,
                                                        showsCreateRoomSection: true,
                                                        showsRoomDirectorySection: true,
                                                        showsJoinByAddressSection: true,
                                                        showsInviteFriendsSection: true)
        case .contactsTab:
            initialViewState = StartChatScreenViewState(userID: userSession.clientProxy.userID,
                                                        screenTitle: L10n.screenContactsTitle,
                                                        showsCloseButton: false,
                                                        showsCreateRoomSection: false,
                                                        showsRoomDirectorySection: false,
                                                        showsJoinByAddressSection: false,
                                                        showsInviteFriendsSection: true)
        }
        
        super.init(initialViewState: initialViewState, mediaProvider: userSession.mediaProvider)
        
        setupBindings()
        
        Task {
            knownUsers = await userSession.clientProxy.recentConversationCounterparts()
            
            if state.usersSection.type == .suggestions {
                state.usersSection = .init(type: .suggestions, users: knownUsers)
            }
        }
    }
    
    // MARK: - Public
    
    override func process(viewAction: StartChatScreenViewAction) {
        switch viewAction {
        case .close:
            actionsSubject.send(.close)
        case .createRoom:
            actionsSubject.send(.createRoom)
        case .selectUser(let user):
            showLoadingIndicator(delay: .milliseconds(200))
            
            let currentDirectRoom = userSession.clientProxy.directRoomForUserID(user.userID)
            switch currentDirectRoom {
            case .success(.some(let roomId)):
                hideLoadingIndicator()
                actionsSubject.send(.showRoom(roomID: roomId))
            case .success:
                hideLoadingIndicator()
                state.bindings.selectedUserToInvite = user
            case .failure:
                hideLoadingIndicator()
                displayError()
            }
        case .createDM(let user):
            Task { await createDirectRoom(user: user) }
        case .joinRoomByAddress:
            joinRoomByAddress()
        case .openRoomDirectorySearch:
            actionsSubject.send(.openRoomDirectorySearch)
        }
    }
    
    // MARK: - Private
    
    // periphery:ignore - auto cancels when reassigned
    @CancellableTask private var resolveAliasTask: Task<Void, Never>?
    private var internalRoomAddressState: JoinByAddressState = .example
    
    private func setupBindings() {
        appSettings.$publicSearchEnabled
            .weakAssign(to: \.state.isRoomDirectoryEnabled, on: self)
            .store(in: &cancellables)
        
        context.$viewState
            .map(\.bindings.searchQuery)
            .debounceTextQueriesAndRemoveDuplicates()
            .sink { [weak self] _ in
                self?.fetchUsers()
            }
            .store(in: &cancellables)
        
        context.$viewState
            .map(\.bindings.roomAddress)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                state.joinByAddressState = .example
                internalRoomAddressState = .example
            }
            .store(in: &cancellables)
        
        context.$viewState
            .map(\.bindings.roomAddress)
            .debounceTextQueriesAndRemoveDuplicates()
            .sink { [weak self] roomAddress in
                guard let self else {
                    return
                }
                resolveRoomAddress(roomAddress)
            }
            .store(in: &cancellables)
    }
    
    private func resolveRoomAddress(_ roomAddress: String) {
        guard !roomAddress.isEmpty,
              isRoomAliasFormatValid(alias: roomAddress) else {
            internalRoomAddressState = .invalidAddress
            resolveAliasTask = nil
            return
        }
        
        resolveAliasTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer { resolveAliasTask = nil }
            
            guard case let .success(resolved) = await userSession.clientProxy.resolveRoomAlias(roomAddress) else {
                if Task.isCancelled {
                    return
                }
                internalRoomAddressState = .addressNotFound
                return
            }

            guard !Task.isCancelled else {
                return
            }
            
            let result = JoinByAddressState.addressFound(address: roomAddress, roomID: resolved.roomId)
            internalRoomAddressState = result
            state.joinByAddressState = result
        }
    }
    
    // periphery:ignore - auto cancels when reassigned
    @CancellableTask
    private var fetchUsersTask: Task<Void, Never>?
    
    private func fetchUsers() {
        let query = context.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !query.isEmpty else {
            state.usersSection = .init(type: .suggestions, users: knownUsers)
            return
        }
        
        let normalizedQuery = query.lowercased()
        
        let localMatches = knownUsers.filter { user in
            let displayName = user.displayName?.lowercased() ?? ""
            let userID = user.userID.lowercased()
            return displayName.contains(normalizedQuery) || userID.contains(normalizedQuery)
        }
        
        // Показываем локальные результаты сразу.
        state.usersSection = .init(type: .searchResult, users: localMatches)
        
        // Короткие запросы не отправляем на сервер, чтобы не шуметь directory search.
        guard query.count >= 2 else {
            return
        }
        
        fetchUsersTask = Task {
            let result = await userDiscoveryService.searchProfiles(with: query)
            
            guard !Task.isCancelled else { return }
            
            switch result {
            case .success(let remoteUsers):
                let mergedUsers = mergeUsers(local: localMatches, remote: remoteUsers)
                state.usersSection = .init(type: .searchResult, users: mergedUsers)
            case .failure:
                // Если серверный поиск не удался, оставляем локальные результаты.
                state.usersSection = .init(type: .searchResult, users: localMatches)
            }
        }
    }
    
    private func mergeUsers(local: [UserProfileProxy], remote: [UserProfileProxy]) -> [UserProfileProxy] {
        var seen = Set<String>()
        var result: [UserProfileProxy] = []
        
        for user in local + remote {
            if seen.insert(user.userID).inserted {
                result.append(user)
            }
        }
        
        return result
    }
        
    private func createDirectRoom(user: UserProfileProxy) async {
        defer {
            hideLoadingIndicator()
        }
        showLoadingIndicator()
        switch await userSession.clientProxy.createDirectRoom(with: user.userID, expectedRoomName: user.displayName) {
        case .success(let roomId):
            analytics.trackCreatedRoom(isDM: true)
            actionsSubject.send(.showRoom(roomID: roomId))
        case .failure:
            displayError()
        }
    }
    
    private func displayError() {
        state.bindings.alertInfo = AlertInfo(id: .failedCreatingRoom,
                                             title: L10n.commonError,
                                             message: L10n.screenStartChatErrorStartingChat)
    }
    
    private func joinRoomByAddress() {
        if case let .addressFound(lastTestedAddress, roomID) = internalRoomAddressState,
           lastTestedAddress == state.bindings.roomAddress {
            actionsSubject.send(.showRoom(roomID: roomID))
        } else if let resolveAliasTask {
            // If the task is still running we wait for it to complete and we check the state again
            showLoadingIndicator(delay: .milliseconds(250))
            Task {
                await resolveAliasTask.value
                hideLoadingIndicator()
                joinRoomByAddress()
            }
        } else if internalRoomAddressState == .example {
            // If we are in the example state internally, this means that the task has not started yet so we start it, and the check the state again
            resolveRoomAddress(state.bindings.roomAddress)
            joinRoomByAddress()
        } else {
            // In any other case we just use the internal state
            state.joinByAddressState = internalRoomAddressState
        }
    }
        
    // MARK: Loading indicator
    
    private static let loadingIndicatorIdentifier = "\(StartChatScreenViewModel.self)-Loading"
    
    private func showLoadingIndicator(delay: Duration? = nil) {
        userIndicatorController.submitIndicator(UserIndicator(id: Self.loadingIndicatorIdentifier,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: L10n.commonLoading,
                                                              persistent: true),
                                                delay: delay)
    }
    
    private func hideLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(Self.loadingIndicatorIdentifier)
    }
}
