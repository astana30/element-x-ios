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
final class DirectCallLiveKitMediaKeyStore {
    private struct StoredKey {
        let keyID: String
        let sharedKey: String
    }

    private let keyIDProvider: () -> String
    private var keysByCallID = [String: StoredKey]()

    init(keyIDProvider: @escaping () -> String = { UUID().uuidString }) {
        self.keyIDProvider = keyIDProvider
    }

    func storeSharedKey(_ sharedKey: String, callID: String) -> Result<DirectCallMediaKeyHandle, DirectCallMediaError> {
        guard callID.isEmpty == false,
              sharedKey.isEmpty == false else {
            return .failure(.e2eeContextUnavailable)
        }

        let keyID = keyIDProvider()
        guard keyID.isEmpty == false else {
            return .failure(.e2eeContextUnavailable)
        }

        keysByCallID[callID] = StoredKey(keyID: keyID, sharedKey: sharedKey)
        return .success(.init(callID: callID, keyID: keyID))
    }

    func storeSharedKey(_ sharedKey: String, keyHandle: DirectCallMediaKeyHandle) -> Result<DirectCallMediaKeyHandle, DirectCallMediaError> {
        guard keyHandle.callID.isEmpty == false,
              keyHandle.keyID.isEmpty == false,
              sharedKey.isEmpty == false else {
            return .failure(.e2eeContextUnavailable)
        }

        keysByCallID[keyHandle.callID] = StoredKey(keyID: keyHandle.keyID, sharedKey: sharedKey)
        return .success(keyHandle)
    }

    func makeKeyProvider(for keyHandle: DirectCallMediaKeyHandle) -> BaseKeyProvider? {
        guard let storedKey = keysByCallID[keyHandle.callID],
              storedKey.keyID == keyHandle.keyID else {
            return nil
        }

        return BaseKeyProvider(isSharedKey: true, sharedKey: storedKey.sharedKey)
    }

    func clear(callID: String) {
        guard callID.isEmpty == false else {
            return
        }

        keysByCallID.removeValue(forKey: callID)
    }
}

@MainActor
final class DirectCallLiveKitE2EEContextProvider: DirectCallMediaE2EEContextProviderProtocol {
    private let keyStore: DirectCallLiveKitMediaKeyStore
    private var contextsByCallID = [String: DirectCallLiveKitE2EEContext]()

    init() {
        keyStore = DirectCallLiveKitMediaKeyStore()
    }

    init(keyStore: DirectCallLiveKitMediaKeyStore) {
        self.keyStore = keyStore
    }

    func context(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) -> Result<any DirectCallMediaE2EEContextProtocol, DirectCallMediaError> {
        if let error = session.directAudioConnectionError(keyHandle: keyHandle) {
            return .failure(error)
        }

        guard let keyProvider = keyStore.makeKeyProvider(for: keyHandle) else {
            return .failure(.e2eeContextUnavailable)
        }

        let context = DirectCallLiveKitE2EEContext(keyProvider: keyProvider)
        contextsByCallID[session.callID] = context
        return .success(context)
    }

    func clearContext(callID: String) {
        contextsByCallID.removeValue(forKey: callID)?.cleanup()
        keyStore.clear(callID: callID)
    }
}

@MainActor
final class DirectCallLiveKitE2EEContext: DirectCallLiveKitE2EEContextProtocol {
    private var keyProvider: BaseKeyProvider?

    init(keyProvider: BaseKeyProvider) {
        self.keyProvider = keyProvider
    }

    func makeLiveKitRoomOptions() -> Result<RoomOptions, DirectCallMediaError> {
        guard let keyProvider else {
            return .failure(.e2eeContextUnavailable)
        }

        return .success(RoomOptions(encryptionOptions: EncryptionOptions(keyProvider: keyProvider)))
    }

    func cleanup() {
        keyProvider = nil
    }
}

@MainActor
final class LiveKitDirectCallClient: DirectCallLiveKitClientProtocol, @unchecked Sendable {
    typealias RoomFactory = (ConnectOptions, RoomOptions) -> Room
    typealias RoomConnector = (Room, DirectCallMediaConnectionInfo, ConnectOptions, RoomOptions) async throws -> Void
    typealias RemoteAudioSubscriptionUpdater = (Room, Bool) async throws -> Void

    private let roomFactory: RoomFactory
    private let roomConnector: RoomConnector
    private let remoteAudioSubscriptionUpdater: RemoteAudioSubscriptionUpdater
    private var room: Room?
    private var e2eeContext: (any DirectCallMediaE2EEContextProtocol)?
    private var isConnected = false
    private var microphoneEnabled = false
    private var remoteAudioPlaybackEnabled = false

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
        remoteAudioSubscriptionUpdater = Self.updateRemoteAudioSubscriptions
    }

    init(roomFactory: @escaping RoomFactory) {
        self.roomFactory = roomFactory
        roomConnector = { room, connectionInfo, connectOptions, roomOptions in
            try await room.connect(url: connectionInfo.serverURL.absoluteString,
                                   token: connectionInfo.token,
                                   connectOptions: connectOptions,
                                   roomOptions: roomOptions)
        }
        remoteAudioSubscriptionUpdater = Self.updateRemoteAudioSubscriptions
    }

    init(roomFactory: @escaping RoomFactory,
         roomConnector: @escaping RoomConnector,
         remoteAudioSubscriptionUpdater: @escaping RemoteAudioSubscriptionUpdater = LiveKitDirectCallClient.updateRemoteAudioSubscriptions) {
        self.roomFactory = roomFactory
        self.roomConnector = roomConnector
        self.remoteAudioSubscriptionUpdater = remoteAudioSubscriptionUpdater
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
        preparedRoom.add(delegate: self)
        room = preparedRoom
        self.e2eeContext = e2eeContext
        isConnected = false
        microphoneEnabled = false
        remoteAudioPlaybackEnabled = false

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

    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        guard isEnabled else {
            remoteAudioPlaybackEnabled = false
            guard let room else {
                return .success(())
            }

            do {
                try await remoteAudioSubscriptionUpdater(room, false)
                return .success(())
            } catch {
                return .failure(.mediaSetupUnavailable)
            }
        }

        guard isConnected, let room else {
            return .failure(.mediaSetupUnavailable)
        }

        do {
            try await remoteAudioSubscriptionUpdater(room, true)
            remoteAudioPlaybackEnabled = true
            return .success(())
        } catch {
            remoteAudioPlaybackEnabled = false
            try? await remoteAudioSubscriptionUpdater(room, false)
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
            remoteAudioPlaybackEnabled = false
            return
        }

        _ = await setRemoteAudioPlaybackEnabled(false)

        if microphoneEnabled {
            _ = await setMicrophoneEnabled(false)
        }

        await room?.disconnect()
        isConnected = false
        microphoneEnabled = false
    }

    func cleanup() async {
        let currentRoom = room
        await disconnect()
        currentRoom?.remove(delegate: self)
        e2eeContext?.cleanup()
        e2eeContext = nil
        room = nil
    }

    private static func updateRemoteAudioSubscriptions(room: Room, isEnabled: Bool) async throws {
        for participant in room.remoteParticipants.values {
            for publication in participant.audioTracks {
                guard let remotePublication = publication as? RemoteTrackPublication else {
                    continue
                }

                try await remotePublication.set(subscribed: isEnabled)
            }
        }
    }

    private func subscribeToRemoteAudioIfNeeded(room: Room, publication: RemoteTrackPublication) async {
        guard self.room === room,
              isConnected,
              remoteAudioPlaybackEnabled,
              publication.kind == .audio else {
            return
        }

        do {
            try await publication.set(subscribed: true)
        } catch {
            remoteAudioPlaybackEnabled = false
            try? await remoteAudioSubscriptionUpdater(room, false)
        }
    }
}

extension LiveKitDirectCallClient: RoomDelegate {
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didPublishTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in
            await self?.subscribeToRemoteAudioIfNeeded(room: room, publication: publication)
        }
    }
}
