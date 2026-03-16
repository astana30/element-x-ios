//
// Copyright 2026
//

import Combine
import SwiftUI

enum ContactsTabFlowCoordinatorAction {
    case openRoom(roomID: String)
}

final class ContactsTabFlowCoordinator: FlowCoordinatorProtocol {
    private let navigationStackCoordinator: NavigationStackCoordinator
    private let flowParameters: CommonFlowParameters
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<ContactsTabFlowCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ContactsTabFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters) {
        self.navigationStackCoordinator = navigationStackCoordinator
        self.flowParameters = flowParameters
    }

    func start(animated: Bool) {
        let userDiscoveryService = UserDiscoveryService(clientProxy: flowParameters.userSession.clientProxy)

        let parameters = StartChatScreenCoordinatorParameters(userSession: flowParameters.userSession,
                                                              userDiscoveryService: userDiscoveryService,
                                                              userIndicatorController: flowParameters.userIndicatorController,
                                                              appSettings: flowParameters.appSettings,
                                                              analytics: flowParameters.analytics,
                                                              mode: .contactsTab)

        let coordinator = StartChatScreenCoordinator(parameters: parameters)
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }

                switch action {
                case .openRoom(let roomID):
                    actionsSubject.send(.openRoom(roomID: roomID))
                case .close, .createRoom, .openRoomDirectorySearch:
                    break
                }
            }
            .store(in: &cancellables)

        navigationStackCoordinator.setRootCoordinator(coordinator, animated: animated)
    }

    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) { }

    func clearRoute(animated: Bool) { }
}
