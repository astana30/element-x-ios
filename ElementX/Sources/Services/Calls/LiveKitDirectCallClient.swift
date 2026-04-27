//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import LiveKit

@MainActor
protocol DirectCallLiveKitE2EEContextProtocol: DirectCallMediaE2EEContextProtocol {
    func makeLiveKitRoomOptions() -> Result<RoomOptions, DirectCallMediaError>
}

@MainActor
final class LiveKitDirectCallClient: DirectCallLiveKitClientProtocol {
    typealias RoomFactory = (ConnectOptions, RoomOptions) -> Room
    typealias RoomConnector = (Room, DirectCallMediaConnectionInfo, ConnectOptions, RoomOptions) async throws -> Void
    
    private let roomFactory: RoomFactory
    private let roomConnector: RoomConnector
    private var room: Room?
    private var e2eeContext: (any DirectCallMediaE2EEContextProtocol)?
    private var isConnected = false
    private var microphoneEnabled = false

    init() {
        roomFactory = { connectOptions, roomOptions in
            Room(connectOptions: connectOptions, roomOptions: roomOptions)
        }
        roomConnector = { room, connectionInfo, connectOptions, roomOptions in
            try await room.connect(url: connectionInfo.serverURL.absoluteString,
                                   token: connectionInfo.token,
                                   connectOptions: connectOptions,
                                   roomOptions: roomOptions)
        }
    }

    init(roomFactory: @escaping RoomFactory) {
        self.roomFactory = roomFactory
        roomConnector = { room, connectionInfo, connectOptions, roomOptions in
            try await room.connect(url: connectionInfo.serverURL.absoluteString,
                                   token: connectionInfo.token,
                                   connectOptions: connectOptions,
                                   roomOptions: roomOptions)
        }
    }

    init(roomFactory: @escaping RoomFactory, roomConnector: @escaping RoomConnector) {
        self.roomFactory = roomFactory
        self.roomConnector = roomConnector
    }

    func connect(connectionInfo: DirectCallMediaConnectionInfo, e2eeContext: any DirectCallMediaE2EEContextProtocol) async -> Result<Void, DirectCallMediaError> {
        guard room == nil else {
            return .failure(.mediaSetupUnavailable)
        }

        guard let liveKitE2EEContext = e2eeContext as? any DirectCallLiveKitE2EEContextProtocol else {
            return .failure(.e2eeContextUnavailable)
        }

        let roomOptions: RoomOptions
        switch liveKitE2EEContext.makeLiveKitRoomOptions() {
        case .success(let options):
            guard options.e2eeOptions != nil || options.encryptionOptions != nil else {
                return .failure(.e2eeContextUnavailable)
            }
            roomOptions = options
        case .failure(let error):
            return .failure(error)
        }

        let connectOptions = ConnectOptions(autoSubscribe: false, enableMicrophone: false)
        let preparedRoom = roomFactory(connectOptions, roomOptions)
        room = preparedRoom
        self.e2eeContext = e2eeContext
        isConnected = false
        microphoneEnabled = false

        do {
            try await roomConnector(preparedRoom, connectionInfo, connectOptions, roomOptions)
            isConnected = true
            microphoneEnabled = false
            return .success(())
        } catch {
            await cleanup()
            return .failure(.mediaSetupUnavailable)
        }
    }

    func setMicrophoneEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        guard isEnabled else {
            guard isConnected else {
                microphoneEnabled = false
                return .success(())
            }

            do {
                try await room?.localParticipant.setMicrophone(enabled: false)
                microphoneEnabled = false
                return .success(())
            } catch {
                return .failure(.mediaSetupUnavailable)
            }
        }

        guard isConnected else {
            return .failure(.mediaSetupUnavailable)
        }

        do {
            try await room?.localParticipant.setMicrophone(enabled: true)
            microphoneEnabled = true
            return .success(())
        } catch {
            return .failure(.mediaSetupUnavailable)
        }
    }

    func disconnect() async {
        guard room != nil else {
            isConnected = false
            microphoneEnabled = false
            return
        }

        if microphoneEnabled {
            _ = await setMicrophoneEnabled(false)
        }

        await room?.disconnect()
        isConnected = false
        microphoneEnabled = false
    }

    func cleanup() async {
        await disconnect()
        e2eeContext?.cleanup()
        e2eeContext = nil
        room = nil
    }
}
