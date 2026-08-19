//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation

enum CallVoiceAudioSession {
    private static var lastLoggedSignature: String?
    private static var didPrepareVoiceChatCategory = false
    private static var isLockedAfterCapture = false

    static func reset() {
        lastLoggedSignature = nil
        didPrepareVoiceChatCategory = false
        isLockedAfterCapture = false
    }

    /// One-shot PlayAndRecord + voiceChat without speaker-default or session activation.
    /// Call this before WKWebView getUserMedia. After capture, `lockAfterCapture()`
    /// may reassert category once; later automatic routing must not fight WebRTC.
    static func prepareEarpieceCategoryIfNeeded() {
        applyVoiceChatCategory(allowRepeat: false)
    }

    /// Reassert voiceChat once after microphone capture, then ignore automatic routing.
    /// User speaker-button updates still go through `applyOutputPort`.
    static func lockAfterCapture() {
        applyVoiceChatCategory(allowRepeat: true)
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
            try applyVoiceChatCategoryIfNeeded(on: session)
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

    private static func applyVoiceChatCategory(allowRepeat: Bool) {
        if isLockedAfterCapture {
            logCurrentRoute(speakerEnabled: false)
            return
        }

        if didPrepareVoiceChatCategory, !allowRepeat {
            logCurrentRoute(speakerEnabled: false)
            return
        }

        let session = AVAudioSession.sharedInstance()
        let previousOutput = session.currentRoute.outputs.first?.portType
        if isExternalOutput(previousOutput) {
            didPrepareVoiceChatCategory = true
            logIfChanged(session: session, speakerEnabled: false, output: previousOutput)
            return
        }

        do {
            try applyVoiceChatCategoryIfNeeded(on: session)
            didPrepareVoiceChatCategory = true
        } catch {
            MXLog.error("Failed updating call audio category with error: \(error)")
            return
        }

        logIfChanged(session: session, speakerEnabled: false, output: session.currentRoute.outputs.first?.portType)
    }

    private static func applyVoiceChatCategoryIfNeeded(on session: AVAudioSession) throws {
        let needsVoiceChatCategory = session.category != .playAndRecord
            || session.mode != .voiceChat
            || session.categoryOptions.contains(.defaultToSpeaker)
        guard needsVoiceChatCategory else {
            return
        }

        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
    }

    private static func logIfChanged(session: AVAudioSession, speakerEnabled: Bool, output: AVAudioSession.Port?) {
        let outputName = output?.rawValue ?? "none"
        let signature = "\(isLockedAfterCapture)|\(speakerEnabled)|\(outputName)|\(session.category.rawValue)|\(session.mode.rawValue)|\(session.categoryOptions.rawValue)"
        guard lastLoggedSignature != signature else {
            return
        }

        lastLoggedSignature = signature
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-ROUTE] voicechat_once=true locked=\(isLockedAfterCapture) speaker_enabled=\(speakerEnabled) category=\(session.category.rawValue) mode=\(session.mode.rawValue) options=\(session.categoryOptions.rawValue) output=\(outputName)")
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
