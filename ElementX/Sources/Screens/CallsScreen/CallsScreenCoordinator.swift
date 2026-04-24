//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct CallsScreenCoordinatorParameters {
    let userSession: UserSessionProtocol
    let roomSummaryProvider: StaticRoomSummaryProviderProtocol
    let ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never>
}

enum CallsScreenCoordinatorAction {
    case openRoom(roomID: String)
    case startCall(roomID: String, startMode: ElementCallStartMode)
}

@MainActor
final class CallsScreenCoordinator: CoordinatorProtocol {
    private let viewModel: CallsScreenViewModelProtocol

    private var cancellables = Set<AnyCancellable>()

    private let actionsSubject: PassthroughSubject<CallsScreenCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<CallsScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: CallsScreenCoordinatorParameters) {
        viewModel = CallsScreenViewModel(userSession: parameters.userSession,
                                         roomSummaryProvider: parameters.roomSummaryProvider,
                                         ongoingCallRoomIDPublisher: parameters.ongoingCallRoomIDPublisher)

        viewModel.actions
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
    }

    func toPresentable() -> AnyView {
        AnyView(CallsScreen(context: viewModel.context))
    }
}
