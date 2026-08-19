//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import LiveKit

@MainActor
protocol MatrixRTCNativeLiveKitConnecting: AnyObject {
    func connect(serverURL: URL, token: String, localIdentity: String, localKeyBase64: String) async -> Bool
    func setRemoteParticipantKey(_ keyBase64: String, identity: String, index: Int32)
    func setMicrophoneEnabled(_ enabled: Bool) async
    func disconnect() async
}

@MainActor
final class MatrixRTCNativeLiveKitClient: MatrixRTCNativeLiveKitConnecting {
    private var room: Room?
    private var keyProvider: BaseKeyProvider?

    func connect(serverURL: URL, token: String, localIdentity: String, localKeyBase64: String) async -> Bool {
        await disconnect()

        guard Self.isSupportedLiveKitURL(serverURL) else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=livekit ok=false reason=url")
            return false
        }

        let options = KeyProviderOptions(sharedKey: false, ratchetWindowSize: 10, keyRingSize: 256)
        let keyProvider = BaseKeyProvider(options: options)
        keyProvider.setKey(key: localKeyBase64, participantId: localIdentity, index: 0)
        self.keyProvider = keyProvider

        let roomOptions = RoomOptions(encryptionOptions: EncryptionOptions(keyProvider: keyProvider))
        let connectOptions = ConnectOptions(autoSubscribe: true, enableMicrophone: false)
        let room = Room(connectOptions: connectOptions, roomOptions: roomOptions)
        self.room = room

        do {
            try await room.connect(url: serverURL.absoluteString,
                                   token: token,
                                   connectOptions: connectOptions,
                                   roomOptions: roomOptions)
            try await room.localParticipant.setMicrophone(enabled: true)
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=livekit ok=true")
            return true
        } catch {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=livekit ok=false reason=connect")
            await disconnect()
            return false
        }
    }

    func setRemoteParticipantKey(_ keyBase64: String, identity: String, index: Int32) {
        keyProvider?.setKey(key: keyBase64, participantId: identity, index: index)
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=remote_key index=\(index)")
    }

    func setMicrophoneEnabled(_ enabled: Bool) async {
        try? await room?.localParticipant.setMicrophone(enabled: enabled)
    }

    func disconnect() async {
        let currentRoom = room
        room = nil
        keyProvider = nil
        await currentRoom?.disconnect()
    }

    private static func isSupportedLiveKitURL(_ url: URL) -> Bool {
        guard url.host?.isEmpty == false else {
            return false
        }

        switch url.scheme?.lowercased() {
        case "ws", "wss", "http", "https":
            return true
        default:
            return false
        }
    }
}
