//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation

enum CallVoiceAudioSession {
    private static var hasPreparedCategory = false
    private static var lastLoggedSpeakerEnabled: Bool?
    private static var lastLoggedOutput: String?

    static func reset() {
        hasPreparedCategory = false
        lastLoggedSpeakerEnabled = nil
        lastLoggedOutput = nil
    }

    /// Sets PlayAndRecord + voiceChat once. Never activates the session: CallKit or
    /// WebRTC owns activation. Repeated `setActive` interrupts WKWebView audio.
    static func prepareEarpieceCategoryIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        guard !hasPreparedCategory || session.category != .playAndRecord || session.mode != .voiceChat else {
            applyOutputPort(speakerEnabled: false)
            return
        }

        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
            hasPreparedCategory = true
            applyOutputPort(speakerEnabled: false)
        } catch {
            MXLog.error("Failed preparing call audio session with error: \(error)")
        }
    }

    static func applyOutputPort(speakerEnabled: Bool) {
        let session = AVAudioSession.sharedInstance()
        let previousOutput = session.currentRoute.outputs.first?.portType
        if isExternalOutput(previousOutput) {
            logIfChanged(speakerEnabled: false, output: previousOutput)
            return
        }

        let alreadyCorrect = speakerEnabled ? previousOutput == .builtInSpeaker : previousOutput == .builtInReceiver
        if alreadyCorrect {
            logIfChanged(speakerEnabled: speakerEnabled, output: previousOutput)
            return
        }

        do {
            try session.overrideOutputAudioPort(speakerEnabled ? .speaker : .none)
        } catch {
            MXLog.error("Failed updating call audio output port with error: \(error)")
            return
        }

        logIfChanged(speakerEnabled: speakerEnabled, output: session.currentRoute.outputs.first?.portType)
    }

    static func restoreEarpieceIfNeeded() {
        applyOutputPort(speakerEnabled: false)
    }

    private static func logIfChanged(speakerEnabled: Bool, output: AVAudioSession.Port?) {
        let outputName = output?.rawValue ?? "none"
        guard lastLoggedSpeakerEnabled != speakerEnabled || lastLoggedOutput != outputName else {
            return
        }

        lastLoggedSpeakerEnabled = speakerEnabled
        lastLoggedOutput = outputName
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-ROUTE] speaker_enabled=\(speakerEnabled) mode=voiceChat output=\(outputName)")
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
