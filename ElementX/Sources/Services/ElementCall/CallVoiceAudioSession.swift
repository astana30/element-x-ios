//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation

enum CallVoiceAudioSession {
    private static var lastLoggedSignature: String?

    static func reset() {
        lastLoggedSignature = nil
    }

    /// Restores PlayAndRecord + voiceChat without activating the session.
    /// CallKit or WebRTC owns `setActive`. WebRTC often reapplies `.defaultToSpeaker`
    /// after getUserMedia; this clears that option and then overrides the port.
    static func prepareEarpieceCategoryIfNeeded() {
        applyOutputPort(speakerEnabled: false)
    }

    static func applyOutputPort(speakerEnabled: Bool) {
        let session = AVAudioSession.sharedInstance()
        let previousOutput = session.currentRoute.outputs.first?.portType
        if isExternalOutput(previousOutput) {
            logIfChanged(session: session, speakerEnabled: false, output: previousOutput)
            return
        }

        let needsVoiceChatCategory = session.category != .playAndRecord
            || session.mode != .voiceChat
            || session.categoryOptions.contains(.defaultToSpeaker)
        let needsPort = speakerEnabled ? previousOutput != .builtInSpeaker : previousOutput != .builtInReceiver

        if !needsVoiceChatCategory, !needsPort {
            logIfChanged(session: session, speakerEnabled: speakerEnabled, output: previousOutput)
            return
        }

        do {
            if needsVoiceChatCategory {
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
            }
            try session.overrideOutputAudioPort(speakerEnabled ? .speaker : .none)
        } catch {
            MXLog.error("Failed updating call audio output port with error: \(error)")
            return
        }

        logIfChanged(session: session, speakerEnabled: speakerEnabled, output: session.currentRoute.outputs.first?.portType)
    }

    static func restoreEarpieceIfNeeded() {
        applyOutputPort(speakerEnabled: false)
    }

    private static func logIfChanged(session: AVAudioSession, speakerEnabled: Bool, output: AVAudioSession.Port?) {
        let outputName = output?.rawValue ?? "none"
        let signature = "\(speakerEnabled)|\(outputName)|\(session.category.rawValue)|\(session.mode.rawValue)|\(session.categoryOptions.rawValue)"
        guard lastLoggedSignature != signature else {
            return
        }

        lastLoggedSignature = signature
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-ROUTE] speaker_enabled=\(speakerEnabled) category=\(session.category.rawValue) mode=\(session.mode.rawValue) options=\(session.categoryOptions.rawValue) output=\(outputName)")
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
