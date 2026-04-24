//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

struct CallInviteRoomTimelineView: View {
    let timelineItem: CallInviteRoomTimelineItem
    
    var body: some View {
        RoomCallTimelineRow(sender: timelineItem.sender,
                            timestamp: timelineItem.timestamp,
                            callEvent: timelineItem.details)
    }
}

struct CallInviteRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    
    static var previews: some View {
        body.environmentObject(viewModel.context)
    }
    
    static var body: some View {
        CallInviteRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                       timestamp: .mock,
                                                       isEditable: false,
                                                       canBeRepliedTo: false,
                                                       sender: .init(id: "Bob"),
                                                       details: .init(state: .legacyInvite, intent: .audio)))
    }
}
