//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SwiftUI

struct HomeScreenRoomCell: View {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.redactionReasons) private var redactionReasons
    
    let room: HomeScreenRoom
    let isSelected: Bool
    let mediaProvider: MediaProviderProtocol!
    let action: (HomeScreenViewAction) -> Void
    
    private let verticalInsets = 12.0
    private let horizontalInsets = 16.0
    
    var body: some View {
        Button {
            if let roomID = room.roomID {
                action(.selectRoom(roomIdentifier: roomID))
            }
        } label: {
            HStack(spacing: 16.0) {
                avatar
                
                content
                    .padding(.vertical, verticalInsets)
            }
            .padding(.horizontal, horizontalInsets)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(HomeScreenRoomCellButtonStyle(isSelected: isSelected))
        .accessibilityIdentifier(A11yIdentifiers.homeScreen.roomName(room.name))
        .accessibilityHidden(redactionReasons.contains(.placeholder) ? true : false)
    }
    
    @ViewBuilder @MainActor
    private var avatar: some View {
        if dynamicTypeSize < .accessibility3 {
            RoomAvatarImage(avatar: room.avatar,
                            avatarSize: .room(on: .chats),
                            mediaProvider: mediaProvider)
                .dynamicTypeSize(dynamicTypeSize < .accessibility1 ? dynamicTypeSize : .accessibility1)
                .accessibilityHidden(true)
        }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            footer
        }
        // Hide the normal content for Skeletons and overlay centre aligned placeholders.
        .opacity(redactionReasons.contains(.placeholder) ? 0 : 1)
        .overlay {
            if redactionReasons.contains(.placeholder) {
                VStack(alignment: .leading, spacing: 2) {
                    header
                    lastMessage
                }
            }
        }
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(room.name)
                .font(.compound.bodyLGSemibold)
                .foregroundColor(.compound.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if let timestamp = room.timestamp {
                Text(timestamp)
                    .font(room.isHighlighted ? .compound.bodySMSemibold : .compound.bodySM)
                    .foregroundColor(room.isHighlighted ? .compound.textActionAccent : .compound.textSecondary)
            }
        }
    }
    
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Hidden text with 2 lines to maintain consistent height, scaling with dynamic text.
                Text(" \n ")
                    .lastMessageFormatting(hasFailed: false)
                    .hidden()
                    .environment(\.redactionReasons, []) // Always maintain consistent height
                
                HStack(alignment: .top, spacing: 4.0) {
                    lastMessageLeadingIcon
                    
                    lastMessage
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if room.badges.isCallShown {
                    CompoundIcon(\.voiceCallSolid,
                                 size: .xSmall,
                                 relativeTo: .compound.bodySM)
                        .accessibilityLabel(L10n.a11yNotificationsOngoingCall)
                }
                
                if room.badges.isMuteShown {
                    CompoundIcon(\.notificationsOffSolid, size: .custom(15), relativeTo: .compound.bodyMD)
                        .accessibilityLabel(L10n.a11yNotificationsMuted)
                }
                
                if room.badges.isMentionShown {
                    mentionIcon
                }
                
                if room.badges.isDotShown {
                    Circle()
                        .frame(width: 12, height: 12)
                        .accessibilityLabel(L10n.a11yNotificationsNewMessages)
                }
            }
            .foregroundColor(room.isHighlighted ? .compound.iconAccentTertiary : .compound.iconQuaternary)
        }
    }
            
    private var mentionIcon: some View {
        CompoundIcon(\.mention, size: .custom(15), relativeTo: .compound.bodyMD)
            .accessibilityLabel(L10n.a11yNotificationsNewMentions)
    }

    @ViewBuilder @MainActor
    private var lastMessageLeadingIcon: some View {
        switch room.lastMessageState {
        case .sending:
            CompoundIcon(\.time, size: .small, relativeTo: .compound.bodyMD)
                .foregroundStyle(.compound.iconTertiary)
                .offset(y: -1)
                .accessibilityLabel(L10n.commonSending)
        case .failed:
            CompoundIcon(\.errorSolid, size: .small, relativeTo: .compound.bodyMD)
                .foregroundStyle(.compound.iconCriticalPrimary)
                .offset(y: -1)
                .accessibilityHidden(true) // The last message contains the error.
        case .none:
            if let lastCallEvent = room.lastCallEvent {
                HStack(spacing: 2) {
                    CompoundIcon(lastCallEvent.compoundIcon, size: .xSmall, relativeTo: .compound.bodyMD)
                        .foregroundStyle(lastCallEvent.compoundTintColor)
                        .offset(y: 1)

                    if let kindCompoundIcon = lastCallEvent.kindCompoundIcon {
                        CompoundIcon(kindCompoundIcon, size: .custom(11), relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.textSecondary)
                            .offset(y: 1)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
    
    @ViewBuilder
    private var lastMessage: some View {
        if let displayedLastMessage = room.displayedLastMessage {
            Text(displayedLastMessage)
                .lastMessageFormatting(hasFailed: room.lastMessageState == .failed)
        }
    }
}

struct HomeScreenRoomCellButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        let isActive = isSelected || configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        configuration.label
            .padding(.vertical, 3)
            .padding(.horizontal, 12)
            .background {
                shape
                    .fill(Color.clear)
                    .overlay {
                        shape
                            .fill(LinearGradient(colors: [
                                SalemBrandPalette.skyLight.opacity(isActive ? 0.22 : 0.04),
                                SalemBrandPalette.sky.opacity(isActive ? 0.14 : 0.01),
                                Color.clear
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        shape
                            .stroke(SalemBrandPalette.sky.opacity(isActive ? 0.46 : 0.10), lineWidth: isActive ? 1.2 : 1)
                    }
                    .overlay(alignment: .bottom) {
                        Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [
                                SalemBrandPalette.skyLight.opacity(isActive ? 0.80 : 0),
                                SalemBrandPalette.sky.opacity(isActive ? 0.45 : 0),
                                Color.clear
                            ], startPoint: .top, endPoint: .bottom))
                            .frame(height: isActive ? 5 : 0)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 5)
                            .blur(radius: isActive ? 0.8 : 0)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(isSelected ? .none : .easeOut(duration: 0.1).disabledDuringTests(), value: isSelected)
            .animation(.easeOut(duration: 0.12).disabledDuringTests(), value: configuration.isPressed)
    }
}

private extension View {
    func lastMessageFormatting(hasFailed: Bool) -> some View {
        font(.compound.bodyMD)
            .foregroundColor(hasFailed ? .compound.textCriticalPrimary : .compound.textSecondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}

// MARK: - Previews

import MatrixRustSDKMocks

struct HomeScreenRoomCell_Previews: PreviewProvider, TestablePreview {
    static let summaryProviderGeneric = RoomSummaryProviderMock(.init(state: .loaded(.mockRooms)))
    static let genericRooms = summaryProviderGeneric.roomListPublisher.value.compactMap(mockRoom)
    
    static let summaryProviderForNotificationsState = RoomSummaryProviderMock(.init(state: .loaded(.mockRoomsWithNotificationsState)))
    static let notificationsStateRooms = summaryProviderForNotificationsState.roomListPublisher.value.compactMap(mockRoom)
    
    static let lastMessageStateRooms = [makeRoom(lastMessageState: .sending), makeRoom(lastMessageState: .failed)]
    
    static var previews: some View {
        VStack(spacing: 0) {
            ForEach(genericRooms) { room in
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: MediaProviderMock(configuration: .init())) { _ in }
            }
            
            HomeScreenRoomCell(room: .placeholder(), isSelected: false, mediaProvider: MediaProviderMock(configuration: .init())) { _ in }
                .redacted(reason: .placeholder)
        }
        .previewDisplayName("Generic")
        
        VStack(spacing: 0) {
            ForEach(notificationsStateRooms) { room in
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: MediaProviderMock(configuration: .init())) { _ in }
            }
        }
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Notifications State")
        
        VStack(spacing: 0) {
            ForEach(lastMessageStateRooms) { room in
                HomeScreenRoomCell(room: room, isSelected: false, mediaProvider: MediaProviderMock(configuration: .init())) { _ in }
            }
        }
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Last Message State")
    }
    
    static func mockRoom(summary: RoomSummary) -> HomeScreenRoom? {
        HomeScreenRoom(summary: summary, hideUnreadMessagesBadge: false)
    }
    
    static func makeViewModel(roomSummaryProvider: RoomSummaryProviderProtocol) -> HomeScreenViewModel {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "John Doe", roomSummaryProvider: roomSummaryProvider))))

        return HomeScreenViewModel(userSession: userSession,
                                   selectedRoomPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher(),
                                   appSettings: ServiceLocator.shared.settings,
                                   analyticsService: ServiceLocator.shared.analytics,
                                   notificationManager: NotificationManagerMock(),
                                   userIndicatorController: ServiceLocator.shared.userIndicatorController)
    }
    
    static func makeRoom(lastMessageState: RoomSummary.LastMessageState) -> HomeScreenRoom {
        let summary = RoomSummary(room: RoomSDKMock(),
                                  id: UUID().uuidString,
                                  joinRequestType: nil,
                                  name: "Foundation and Empire",
                                  isDirect: false,
                                  isSpace: false,
                                  avatarURL: .mockMXCAvatar,
                                  heroes: [],
                                  activeMembersCount: 0,
                                  lastCallEvent: nil,
                                  lastMessage: AttributedString("How do you see the Emperor then? You think he keeps office hours?"),
                                  lastMessageDate: .mock,
                                  lastMessageState: lastMessageState,
                                  unreadMessagesCount: 2,
                                  unreadMentionsCount: 0,
                                  unreadNotificationsCount: 2,
                                  notificationMode: .mute,
                                  canonicalAlias: "#foundation-and-empire:matrix.org",
                                  alternativeAliases: [],
                                  hasOngoingCall: false,
                                  isMarkedUnread: false,
                                  isFavourite: false,
                                  isTombstoned: false)
        
        return .init(summary: summary, hideUnreadMessagesBadge: false)
    }
}
