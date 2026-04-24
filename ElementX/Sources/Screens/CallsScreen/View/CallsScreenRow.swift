//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct CallsScreenRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let room: CallsScreenRoom
    let context: CallsScreenViewModelType.Context

    var body: some View {
        ListRow(kind: .custom {
            HStack(spacing: 16) {
                Button {
                    context.send(viewAction: .openRoom(roomID: room.id))
                } label: {
                    HStack(spacing: 16) {
                        avatar
                        roomContent
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                callActions
            }
            .padding(.horizontal, ListRowPadding.horizontal)
            .padding(.vertical, ListRowPadding.vertical)
            .salemCard(highlighted: isHighlighted)
        })
        .listRowInsets(.init(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder @MainActor
    private var avatar: some View {
        if dynamicTypeSize < .accessibility3 {
            RoomAvatarImage(avatar: room.avatar,
                            avatarSize: .room(on: .chats),
                            mediaProvider: context.mediaProvider)
                .dynamicTypeSize(dynamicTypeSize < .accessibility1 ? dynamicTypeSize : .accessibility1)
                .accessibilityHidden(true)
        }
    }

    private var roomContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(room.title)
                    .font(.compound.bodyLG)
                    .foregroundColor(.compound.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let timestamp = room.timestamp {
                    Text(timestamp)
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textSecondary)
                        .lineLimit(1)
                }
            }

            statusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    @ViewBuilder @MainActor
    private var statusLine: some View {
        switch room.status {
        case .ongoing(let intent):
            HStack(spacing: 8) {
                callBadge(title: UntranslatedL10n.commonOngoingCall,
                          icon: intent == .video ? \.videoCallSolid : \.voiceCallSolid,
                          tint: .compound.iconAccentTertiary,
                          background: .compound.bgSubtleSecondary)

                if let intent {
                    callKindBadge(title: intent == .video ? L10n.commonVideo : L10n.commonAudio,
                                  icon: intent == .video ? \.videoCallSolid : \.voiceCallSolid)
                }
            }
        case .call(let event):
            HStack(spacing: 8) {
                callBadge(title: event.statusTitle,
                          icon: event.compoundIcon,
                          tint: event.compoundTintColor,
                          background: event.cardAccentColor.opacity(0.12))

                if event.kindLabel != nil, event.kindCompoundIcon != nil {
                    callKindBadge(for: event)
                }
            }
        }
    }

    private func callBadge(title: String,
                           icon: KeyPath<CompoundIcons, Image>,
                           tint: Color,
                           background: Color) -> some View {
        Label(title: { Text(title) },
              icon: { CompoundIcon(icon, size: .xSmall, relativeTo: .compound.bodySM) })
            .font(.compound.bodySM)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(background))
    }

    private func callKindBadge(for event: RoomCallEvent) -> some View {
        callKindBadge(title: event.kindLabel ?? "",
                      icon: event.kindCompoundIcon ?? \.voiceCallSolid)
    }

    private func callKindBadge(title: String, icon: KeyPath<CompoundIcons, Image>) -> some View {
        Label(title: { Text(title) },
              icon: { CompoundIcon(icon, size: .xSmall, relativeTo: .compound.bodySM) })
            .font(.compound.bodySM)
            .foregroundStyle(.compound.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(.compound.bgSubtleSecondary))
    }

    private var callActions: some View {
        HStack(spacing: 8) {
            Button {
                context.send(viewAction: .startCall(roomID: room.id, startMode: .audio))
            } label: {
                CompoundIcon(\.voiceCall, size: .small, relativeTo: .compound.bodyLG)
            }
            .buttonStyle(.compound(.super, size: .toolbarIcon))
            .accessibilityLabel(L10n.a11yStartVoiceCall)

            Button {
                context.send(viewAction: .startCall(roomID: room.id, startMode: .video))
            } label: {
                CompoundIcon(\.videoCall, size: .small, relativeTo: .compound.bodyLG)
            }
            .buttonStyle(.compound(.super, size: .toolbarIcon))
            .accessibilityLabel(L10n.a11yStartCall)
        }
    }

    private var isHighlighted: Bool {
        switch room.status {
        case .ongoing:
            true
        case .call(let event):
            event.state == .missed || event.state == .declined
        }
    }
}

// MARK: - Previews

import MatrixRustSDKMocks

struct CallsScreenRow_Previews: PreviewProvider, TestablePreview {
    static let mediaProvider = MediaProviderMock(configuration: .init())
    static let context = CallsScreenViewModel(userSession: UserSessionMock(.init()),
                                              roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded([]))),
                                              ongoingCallRoomIDPublisher: .init(.init(nil))).context

    static var previews: some View {
        Form {
            Section {
                CallsScreenRow(room: .init(id: "!room-a:server",
                                           title: "Alice",
                                           avatar: .room(id: "!room-a:server", name: "Alice", avatarURL: .mockMXCAvatar),
                                           timestamp: Date.mock.formattedMinimal(),
                                           status: .call(.init(state: .missed, intent: .video))),
                               context: context)

                CallsScreenRow(room: .init(id: "!room-b:server",
                                           title: "Bob",
                                           avatar: .room(id: "!room-b:server", name: "Bob", avatarURL: nil),
                                           timestamp: Date.mock.formattedMinimal(),
                                           status: .ongoing(intent: .video)),
                               context: context)
            }
        }
        .compoundList()
    }
}
