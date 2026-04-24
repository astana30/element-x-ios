//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

enum CallsTabFlowCoordinatorAction {
    case openRoom(roomID: String)
    case startCall(roomID: String, startMode: ElementCallStartMode)
}

final class CallsTabFlowCoordinator: FlowCoordinatorProtocol {
    private let navigationStackCoordinator: NavigationStackCoordinator
    private let flowParameters: CommonFlowParameters
    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<CallsTabFlowCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CallsTabFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters) {
        self.navigationStackCoordinator = navigationStackCoordinator
        self.flowParameters = flowParameters
    }

    func start(animated: Bool) {
        let coordinator = CallsScreenCoordinator(parameters: .init(userSession: flowParameters.userSession,
                                                                   roomSummaryProvider: flowParameters.userSession.clientProxy.staticRoomSummaryProvider,
                                                                   ongoingCallRoomIDPublisher: flowParameters.ongoingCallRoomIDPublisher))

        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }

                switch action {
                case .openRoom(let roomID):
                    actionsSubject.send(.openRoom(roomID: roomID))
                case .startCall(let roomID, let startMode):
                    actionsSubject.send(.startCall(roomID: roomID, startMode: startMode))
                }
            }
            .store(in: &cancellables)

        navigationStackCoordinator.setRootCoordinator(coordinator, animated: animated)
    }

    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) { }

    func clearRoute(animated: Bool) { }
}
