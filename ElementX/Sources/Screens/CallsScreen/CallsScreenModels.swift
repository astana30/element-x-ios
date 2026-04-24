//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum CallsScreenViewModelAction {
    case openRoom(roomID: String)
    case startCall(roomID: String, startMode: ElementCallStartMode)
}

struct CallsScreenViewState: BindableState {
    var isLoading = true
    var rooms: [CallsScreenRoom] = []
}

enum CallsScreenViewAction {
    case openRoom(roomID: String)
    case startCall(roomID: String, startMode: ElementCallStartMode)
}

struct CallsScreenRoom: Identifiable, Equatable {
    enum Status: Equatable {
        case ongoing(intent: RoomCallEvent.Intent?)
        case call(RoomCallEvent)
    }

    let id: String
    let title: String
    let avatar: RoomAvatar
    let timestamp: String?
    let status: Status
}
