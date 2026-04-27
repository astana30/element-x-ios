//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import LiveKit

@MainActor
final class LiveKitDirectCallClient: DirectCallLiveKitClientProtocol {
    private var room: Room?
    private var isConnected = false
    private var microphoneEnabled = false

    func connect(connectionInfo: DirectCallMediaConnectionInfo, e2eeContext: any DirectCallMediaE2EEContextProtocol) async -> Result<Void, DirectCallMediaError> {
        guard room == nil else {
            return .failure(.mediaSetupUnavailable)
        }

        room = Room(connectOptions: ConnectOptions(enableMicrophone: false),
                    roomOptions: RoomOptions())
        isConnected = false
        microphoneEnabled = false

        // Real connect remains disabled until the SDK E2EE key-provider boundary exists.
        return .failure(.mediaSetupUnavailable)
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
        room = nil
    }
}
