//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

typealias CallsScreenViewModelType = StateStoreViewModelV2<CallsScreenViewState, CallsScreenViewAction>

@MainActor
final class CallsScreenViewModel: CallsScreenViewModelType, CallsScreenViewModelProtocol {
    private let roomSummaryProvider: StaticRoomSummaryProviderProtocol

    private var roomSummaries = [RoomSummary]()
    private var ongoingCallRoomID: String?

    private let actionsSubject: PassthroughSubject<CallsScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<CallsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(userSession: UserSessionProtocol,
         roomSummaryProvider: StaticRoomSummaryProviderProtocol,
         ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never>) {
        self.roomSummaryProvider = roomSummaryProvider
        ongoingCallRoomID = ongoingCallRoomIDPublisher.value

        super.init(initialViewState: .init(),
                   mediaProvider: userSession.mediaProvider)

        roomSummaryProvider.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.state.isLoading = !state.isLoaded
            }
            .store(in: &cancellables)

        roomSummaryProvider.roomListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summaries in
                self?.roomSummaries = summaries
                self?.updateRooms()
            }
            .store(in: &cancellables)

        ongoingCallRoomIDPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomID in
                self?.ongoingCallRoomID = roomID
                self?.updateRooms()
            }
            .store(in: &cancellables)

        state.isLoading = !roomSummaryProvider.statePublisher.value.isLoaded
        roomSummaries = roomSummaryProvider.roomListPublisher.value
        updateRooms()
    }

    override func process(viewAction: CallsScreenViewAction) {
        switch viewAction {
        case .openRoom(let roomID):
            actionsSubject.send(.openRoom(roomID: roomID))
        case .startCall(let roomID, let startMode):
            actionsSubject.send(.startCall(roomID: roomID, startMode: startMode))
        }
    }

    private func updateRooms() {
        state.rooms = sortedCallRooms(from: roomSummaries).map(buildRoom)
    }

    private func sortedCallRooms(from summaries: [RoomSummary]) -> [RoomSummary] {
        summaries
            .filter(\.isDirect)
            .filter { !$0.isSpace }
            .filter { summary in
                if case .some = summary.joinRequestType {
                    return false
                }
                return true
            }
            .filter { !$0.isTombstoned }
            .filter { hasOngoingCall($0) || $0.lastCallEvent != nil }
            .sorted { lhs, rhs in
                let lhsHasOngoingCall = hasOngoingCall(lhs)
                let rhsHasOngoingCall = hasOngoingCall(rhs)
                if lhsHasOngoingCall != rhsHasOngoingCall {
                    return lhsHasOngoingCall
                }

                let lhsHasCallActivity = lhs.lastCallEvent != nil
                let rhsHasCallActivity = rhs.lastCallEvent != nil
                if lhsHasCallActivity != rhsHasCallActivity {
                    return lhsHasCallActivity
                }

                let lhsDate = lhs.lastMessageDate ?? .distantPast
                let rhsDate = rhs.lastMessageDate ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func buildRoom(from summary: RoomSummary) -> CallsScreenRoom {
        let status: CallsScreenRoom.Status
        if hasOngoingCall(summary) {
            status = .ongoing(intent: summary.lastCallEvent?.intent == .unknown ? nil : summary.lastCallEvent?.intent)
        } else if let lastCallEvent = summary.lastCallEvent {
            status = .call(lastCallEvent)
        } else {
            fatalError("Calls screen rooms must have call activity.")
        }

        return .init(id: summary.id,
                     title: summary.name,
                     avatar: summary.avatar,
                     timestamp: summary.lastMessageDate?.formattedMinimal(),
                     status: status)
    }

    private func hasOngoingCall(_ summary: RoomSummary) -> Bool {
        summary.hasOngoingCall || ongoingCallRoomID == summary.id
    }
}
