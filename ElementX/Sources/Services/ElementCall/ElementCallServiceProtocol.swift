//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine

enum ElementCallServiceAction {
    case receivedIncomingCallRequest
    case startCall(roomID: String, startMode: ElementCallStartMode)
    case endCall(roomID: String)
    case requestCallTermination(roomID: String)
    case setAudioEnabled(_ enabled: Bool, roomID: String)
}

// sourcery: AutoMockable
protocol ElementCallServiceProtocol {
    var actions: AnyPublisher<ElementCallServiceAction, Never> { get }
    
    var ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never> { get }
    
    func setClientProxy(_ clientProxy: ClientProxyProtocol)

    @MainActor func observeForegroundRoom(roomProxy: JoinedRoomProxyProtocol, roomDisplayName: String?)

    @MainActor func stopObservingForegroundRoom(roomID: String)
    
    func setupCallSession(roomID: String, roomDisplayName: String, startMode: ElementCallStartMode) async
    
    func declineIncomingCall() async
    
    func requestCallTermination(roomID: String) async

    func isPreAnswerOutgoingCall(roomID: String) -> Bool
    
    func tearDownCallSession()
    
    func setAudioEnabled(_ enabled: Bool, roomID: String)
}

extension ElementCallServiceProtocol {
    @MainActor func observeForegroundRoom(roomProxy _: JoinedRoomProxyProtocol, roomDisplayName _: String?) { }

    @MainActor func stopObservingForegroundRoom(roomID _: String) { }

    func setupCallSession(roomID: String, roomDisplayName: String) async {
        await setupCallSession(roomID: roomID, roomDisplayName: roomDisplayName, startMode: .video)
    }

    func isPreAnswerOutgoingCall(roomID: String) -> Bool {
        false
    }
}
