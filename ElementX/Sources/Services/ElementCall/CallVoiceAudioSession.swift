//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation

enum CallVoiceAudioSession {
    /// Configures a 1:1 voice call to use the receiver by default, like a phone call.
    /// Speaker is only used when the in-call speaker button is on. Bluetooth and
    /// wired headsets stay on the system route.
    @discardableResult
    static func configure(speakerEnabled: Bool, log: Bool = true) -> Bool {
        let session = AVAudioSession.sharedInstance()
        let previousOutput = session.currentRoute.outputs.first?.portType
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
            if !isExternalOutput(previousOutput) {
                try session.overrideOutputAudioPort(speakerEnabled ? .speaker : .none)
            }
            try session.setActive(true)
            let output = session.currentRoute.outputs.first?.portType.rawValue ?? "none"
            if log || previousOutput == .builtInSpeaker {
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-ROUTE] speaker_enabled=\(speakerEnabled) mode=voiceChat output=\(output)")
            }
            return true
        } catch {
            MXLog.error("Failed configuring call audio session with error: \(error)")
            return false
        }
    }

    static func restoreEarpieceIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        let output = session.currentRoute.outputs.first?.portType
        if isExternalOutput(output) {
            if session.category != .playAndRecord || session.mode != .voiceChat {
                configure(speakerEnabled: false, log: false)
            }
            return
        }

        let shouldReconfigure = session.category != .playAndRecord
            || session.mode != .voiceChat
            || output == .builtInSpeaker
        if shouldReconfigure {
            configure(speakerEnabled: false, log: output == .builtInSpeaker)
        }
    }

    private static func isExternalOutput(_ port: AVAudioSession.Port?) -> Bool {
        switch port {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .headsetMic, .carAudio:
            return true
        default:
            return false
        }
    }
}
