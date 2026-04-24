//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct RoomCallTimelineRow: View {
    @Environment(\.timelineContext) private var context

    let sender: TimelineItemSender
    let timestamp: Date
    let callEvent: RoomCallEvent

    var body: some View {
        HStack(spacing: 12) {
            LoadableAvatarImage(url: sender.avatarURL,
                                name: sender.displayName ?? sender.id,
                                contentID: sender.id,
                                avatarSize: .user(on: .timeline),
                                mediaProvider: context?.mediaProvider)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(sender.disambiguatedDisplayName ?? sender.id)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    callStatusBadge
                    if callEvent.kindLabel != nil, callEvent.kindCompoundIcon != nil {
                        callKindBadge
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timestamp.formattedTime())
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(callEvent.cardBackgroundColor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(callEvent.cardBorderColor, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(callEvent.cardAccentColor)
                .frame(width: 3)
                .padding(.vertical, 9)
                .padding(.leading, 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var callStatusBadge: some View {
        Label {
            Text(callEvent.statusTitle)
        } icon: {
            CompoundIcon(callEvent.compoundIcon, size: .medium, relativeTo: .compound.bodyMD)
        }
        .font(.compound.bodySM)
        .foregroundStyle(callEvent.compoundTintColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(callEvent.cardAccentColor.opacity(0.12))
        }
    }

    @ViewBuilder
    private var callKindBadge: some View {
        if let kindLabel = callEvent.kindLabel,
           let kindCompoundIcon = callEvent.kindCompoundIcon {
            Label {
                Text(kindLabel)
            } icon: {
                CompoundIcon(kindCompoundIcon, size: .xSmall, relativeTo: .compound.bodySM)
            }
            .font(.compound.bodySM)
            .foregroundStyle(.compound.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.compound.bgSubtleSecondary)
            }
        }
    }
}
