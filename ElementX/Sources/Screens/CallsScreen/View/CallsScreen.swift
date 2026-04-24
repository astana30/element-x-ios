//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct CallsScreen: View {
    @Bindable var context: CallsScreenViewModelType.Context

    var body: some View {
        Group {
            if context.viewState.isLoading, context.viewState.rooms.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if context.viewState.rooms.isEmpty {
                emptyState
            } else {
                Form {
                    Section {
                        ForEach(context.viewState.rooms) { room in
                            CallsScreenRow(room: room, context: context)
                        }
                    }
                }
                .compoundList()
                .scrollContentBackground(.hidden)
            }
        }
        .salemScreenBackground()
        .navigationTitle(UntranslatedL10n.screenHomeTabCalls)
        .navigationBarTitleDisplayMode(.large)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            BigIcon(icon: \.voiceCallSolid)

            Text(UntranslatedL10n.screenCallsEmptyTitle)
                .font(.compound.headingMDBold)
                .foregroundColor(.compound.textPrimary)

            Text(UntranslatedL10n.screenCallsEmptySubtitle)
                .font(.compound.bodyMD)
                .foregroundColor(.compound.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

import MatrixRustSDKMocks

struct CallsScreen_Previews: PreviewProvider, TestablePreview {
    static let loadedViewModel = CallsScreenViewModel(userSession: UserSessionMock(.init()),
                                                      roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(mockRooms))),
                                                      ongoingCallRoomIDPublisher: .init(.init("!room-a:server")))
    static let emptyViewModel = CallsScreenViewModel(userSession: UserSessionMock(.init()),
                                                     roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded([]))),
                                                     ongoingCallRoomIDPublisher: .init(.init(nil)))

    static var previews: some View {
        Group {
            ElementNavigationStack {
                CallsScreen(context: loadedViewModel.context)
            }
            .previewDisplayName("Loaded")

            ElementNavigationStack {
                CallsScreen(context: emptyViewModel.context)
            }
            .previewDisplayName("Empty")
        }
    }

    private static let mockRooms: [RoomSummary] = [
        .init(room: RoomSDKMock(),
              id: "!room-a:server",
              joinRequestType: nil,
              name: "Alice",
              isDirect: true,
              isSpace: false,
              avatarURL: .mockMXCAvatar,
              heroes: [],
              activeMembersCount: 2,
              lastCallEvent: .init(state: .missed, intent: .video),
              lastMessage: AttributedString("Пропущенный видеозвонок"),
              lastMessageDate: .mock,
              lastMessageState: nil,
              unreadMessagesCount: 0,
              unreadMentionsCount: 0,
              unreadNotificationsCount: 0,
              notificationMode: .allMessages,
              canonicalAlias: nil,
              alternativeAliases: [],
              hasOngoingCall: false,
              isMarkedUnread: false,
              isFavourite: false,
              isTombstoned: false),
        .init(room: RoomSDKMock(),
              id: "!room-b:server",
              joinRequestType: nil,
              name: "Bob",
              isDirect: true,
              isSpace: false,
              avatarURL: nil,
              heroes: [],
              activeMembersCount: 2,
              lastCallEvent: .init(state: .answered, intent: .audio),
              lastMessage: AttributedString("Звонок принят"),
              lastMessageDate: Date.mock.addingTimeInterval(-3600),
              lastMessageState: nil,
              unreadMessagesCount: 0,
              unreadMentionsCount: 0,
              unreadNotificationsCount: 0,
              notificationMode: .allMessages,
              canonicalAlias: nil,
              alternativeAliases: [],
              hasOngoingCall: false,
              isMarkedUnread: false,
              isFavourite: false,
              isTombstoned: false)
    ]
}
