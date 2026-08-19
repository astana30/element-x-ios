//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation

enum CallVoiceAudioSession {
    private static var lastLoggedSignature: String?
    private static var isLockedAfterCapture = false

    static func reset() {
        lastLoggedSignature = nil
        isLockedAfterCapture = false
    }

    /// Logs the current route without mutating AVAudioSession.
    /// WKWebView WebRTC owns category, mode, and activation after CallKit has
    /// activated the session. CallKit answer still needs PlayAndRecord/VoiceChat
    /// configured before `CXAnswerCallAction.fulfill()`.
    static func prepareEarpieceCategoryIfNeeded() {
        logCurrentRoute(speakerEnabled: false)
    }

    /// Sets PlayAndRecord/VoiceChat so CallKit can activate audio on a locked phone.
    /// Does not call `setActive` — CallKit owns activation after the answer action is fulfilled.
    static func configurePlayAndRecordVoiceChatForCallKitAnswer(session: AudioSessionProtocol) {
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-ANSWER-CATEGORY] category=PlayAndRecord mode=VoiceChat")
        } catch {
            MXLog.error("Failed configuring CallKit answer audio category with error: \(error)")
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-ANSWER-CATEGORY] failed=true")
        }
        logCurrentRoute(speakerEnabled: false)
    }

    /// Marks capture complete so automatic routing stays UI-only.
    /// WKWebView WebRTC keeps owning category, mode, and activation.
    static func lockAfterCapture() {
        isLockedAfterCapture = true
        logCurrentRoute(speakerEnabled: false)
    }

    static func applyOutputPort(speakerEnabled: Bool) {
        let session = AVAudioSession.sharedInstance()
        let previousOutput = session.currentRoute.outputs.first?.portType
        if isExternalOutput(previousOutput) {
            logIfChanged(session: session, speakerEnabled: false, output: previousOutput)
            return
        }

        do {
            try session.overrideOutputAudioPort(speakerEnabled ? .speaker : .none)
        } catch {
            MXLog.error("Failed updating call audio output port with error: \(error)")
            return
        }

        logIfChanged(session: session, speakerEnabled: speakerEnabled, output: session.currentRoute.outputs.first?.portType)
    }

    static func logCurrentRoute(speakerEnabled: Bool) {
        let session = AVAudioSession.sharedInstance()
        logIfChanged(session: session, speakerEnabled: speakerEnabled, output: session.currentRoute.outputs.first?.portType)
    }

    private static func logIfChanged(session: AVAudioSession, speakerEnabled: Bool, output: AVAudioSession.Port?) {
        let outputName = output?.rawValue ?? "none"
        let signature = "\(isLockedAfterCapture)|\(speakerEnabled)|\(outputName)|\(session.category.rawValue)|\(session.mode.rawValue)|\(session.categoryOptions.rawValue)"
        guard lastLoggedSignature != signature else {
            return
        }

        lastLoggedSignature = signature
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-ROUTE] native_category=false locked=\(isLockedAfterCapture) speaker_enabled=\(speakerEnabled) category=\(session.category.rawValue) mode=\(session.mode.rawValue) options=\(session.categoryOptions.rawValue) output=\(outputName)")
    }

    static func isExternalRoute(_ port: AVAudioSession.Port?) -> Bool {
        isExternalOutput(port)
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
