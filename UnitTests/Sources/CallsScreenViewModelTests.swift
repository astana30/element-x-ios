//
// Copyright 2026 Element Creations Ltd.
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
struct CallsScreenViewModelTests {
    @Test
    func filtersAndSortsDirectRooms() {
        let rooms = [
            makeRoomSummary(id: "!ongoing:server",
                            name: "Ongoing",
                            isDirect: true,
                            lastMessageDate: Date(timeIntervalSince1970: 1000),
                            hasOngoingCall: true),
            makeRoomSummary(id: "!recent-call:server",
                            name: "Recent Call",
                            isDirect: true,
                            lastCallEvent: .init(state: .missed, intent: .video),
                            lastMessageDate: Date(timeIntervalSince1970: 2000)),
            makeRoomSummary(id: "!plain-dm:server",
                            name: "Plain DM",
                            isDirect: true,
                            lastMessageDate: Date(timeIntervalSince1970: 3000)),
            makeRoomSummary(id: "!space:server",
                            name: "Space",
                            isDirect: true,
                            isSpace: true,
                            lastCallEvent: .init(state: .answered, intent: .audio),
                            lastMessageDate: Date(timeIntervalSince1970: 4000)),
            makeRoomSummary(id: "!invite:server",
                            name: "Invite",
                            isDirect: true,
                            joinRequestType: .invite(inviter: nil),
                            lastCallEvent: .init(state: .declined, intent: .audio),
                            lastMessageDate: Date(timeIntervalSince1970: 5000)),
            makeRoomSummary(id: "!tombstoned:server",
                            name: "Tombstoned",
                            isDirect: true,
                            lastCallEvent: .init(state: .ended, intent: .audio),
                            lastMessageDate: Date(timeIntervalSince1970: 6000),
                            isTombstoned: true),
            makeRoomSummary(id: "!group:server",
                            name: "Group",
                            isDirect: false,
                            lastCallEvent: .init(state: .outgoing, intent: .video),
                            lastMessageDate: Date(timeIntervalSince1970: 7000))
        ]

        let viewModel = makeViewModel(rooms: rooms)

        #expect(viewModel.context.viewState.rooms.map(\.id) == ["!ongoing:server", "!recent-call:server"])

        guard viewModel.context.viewState.rooms.count == 2 else {
            Issue.record("Expected only direct rooms with call activity.")
            return
        }

        #expect(viewModel.context.viewState.rooms[0].status == CallsScreenRoom.Status.ongoing(intent: nil))
        #expect(viewModel.context.viewState.rooms[1].status == CallsScreenRoom.Status.call(.init(state: .missed, intent: .video)))
    }

    @Test
    func ongoingCallPublisherPromotesMatchingRoom() async throws {
        let ongoingCallRoomIDSubject = CurrentValueSubject<String?, Never>(nil)
        let rooms = [
            makeRoomSummary(id: "!alice:server",
                            name: "Alice",
                            isDirect: true,
                            lastCallEvent: .init(state: .answered, intent: .audio),
                            lastMessageDate: Date(timeIntervalSince1970: 2000)),
            makeRoomSummary(id: "!bob:server",
                            name: "Bob",
                            isDirect: true,
                            lastMessageDate: Date(timeIntervalSince1970: 1000))
        ]

        let viewModel = CallsScreenViewModel(userSession: UserSessionMock(.init()),
                                             roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(rooms))),
                                             ongoingCallRoomIDPublisher: ongoingCallRoomIDSubject.asCurrentValuePublisher())

        #expect(viewModel.context.viewState.rooms.map(\.id) == ["!alice:server"])

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.rooms)) {
            $0.map(\.id) == ["!bob:server", "!alice:server"] && $0.first?.status == .ongoing(intent: nil)
        }

        ongoingCallRoomIDSubject.send("!bob:server")

        try await deferred.fulfill()
    }

    private func makeViewModel(rooms: [RoomSummary]) -> CallsScreenViewModel {
        CallsScreenViewModel(userSession: UserSessionMock(.init()),
                             roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(rooms))),
                             ongoingCallRoomIDPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher())
    }

    private func makeRoomSummary(id: String,
                                 name: String,
                                 isDirect: Bool,
                                 isSpace: Bool = false,
                                 joinRequestType: RoomSummary.JoinRequestType? = nil,
                                 lastCallEvent: RoomCallEvent? = nil,
                                 lastMessageDate: Date? = nil,
                                 hasOngoingCall: Bool = false,
                                 isTombstoned: Bool = false) -> RoomSummary {
        RoomSummary(room: RoomSDKMock(),
                    id: id,
                    joinRequestType: joinRequestType,
                    name: name,
                    isDirect: isDirect,
                    isSpace: isSpace,
                    avatarURL: nil,
                    heroes: [],
                    activeMembersCount: 2,
                    lastCallEvent: lastCallEvent,
                    lastMessage: AttributedString("Message for \(name)"),
                    lastMessageDate: lastMessageDate,
                    lastMessageState: nil,
                    unreadMessagesCount: 0,
                    unreadMentionsCount: 0,
                    unreadNotificationsCount: 0,
                    notificationMode: .allMessages,
                    canonicalAlias: nil,
                    alternativeAliases: [],
                    hasOngoingCall: hasOngoingCall,
                    isMarkedUnread: false,
                    isFavourite: false,
                    isTombstoned: isTombstoned)
    }
}
