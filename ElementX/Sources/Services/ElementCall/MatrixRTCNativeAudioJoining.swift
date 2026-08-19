//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum MatrixRTCNativeAudioState: Equatable {
    case inactive
    case connecting
    case connected
}

protocol MatrixRTCNativeAudioJoining: AnyObject {
    var activeRoomID: String? { get }
    var state: MatrixRTCNativeAudioState { get }

    func joinIncomingAudio(roomID: String, clientProxy: ClientProxyProtocol) async
    func setMicrophoneEnabled(_ enabled: Bool)
    func leave()
}
