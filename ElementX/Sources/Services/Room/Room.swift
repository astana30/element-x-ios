//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRustSDK

extension RoomProtocol {
    func joinCallIntent(for startMode: ElementCallStartMode) async -> Intent {
        let isDirectRoom = await isDirect()
        
        if isDirectRoom {
            if await hasActiveRoomCall() {
                switch startMode {
                case .audio:
                    return .joinExistingDmVoice
                case .video:
                    return .joinExistingDm
                }
            }

            // Direct calls should behave like regular 1:1 calls instead of persistent
            // conference rooms, so only idle direct rooms start a fresh DM call.
            switch startMode {
            case .audio:
                return .startCallDmVoice
            case .video:
                return .startCallDm
            }
        }
        
        return await hasActiveRoomCall() ? .joinExisting : .startCall
    }
    
    var joinCallIntent: Intent {
        get async {
            await joinCallIntent(for: .audio)
        }
    }
}
