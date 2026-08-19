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

    /// WKWebView WebRTC owns category, mode, and output port. Mutating the
    /// shared audio session after getUserMedia mutes the call. CallKit still owns
    /// session activation for incoming audio; this helper only logs the current route.
    static func prepareEarpieceCategoryIfNeeded() {
        logCurrentRoute(speakerEnabled: false)
    }

    static func applyOutputPort(speakerEnabled: Bool) {
        logCurrentRoute(speakerEnabled: speakerEnabled)
    }

    static func restoreEarpieceIfNeeded() {
        logCurrentRoute(speakerEnabled: false)
    }

    static func logCurrentRoute(speakerEnabled: Bool) {
        let session = AVAudioSession.sharedInstance()
        logIfChanged(session: session, speakerEnabled: speakerEnabled, output: session.currentRoute.outputs.first?.portType)
    }

    private static func logIfChanged(session: AVAudioSession, speakerEnabled: Bool, output: AVAudioSession.Port?) {
        let outputName = output?.rawValue ?? "none"
        let signature = "\(speakerEnabled)|\(outputName)|\(session.category.rawValue)|\(session.mode.rawValue)|\(session.categoryOptions.rawValue)"
        guard lastLoggedSignature != signature else {
            return
        }

        lastLoggedSignature = signature
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-ROUTE] leave_webrtc=true speaker_enabled=\(speakerEnabled) category=\(session.category.rawValue) mode=\(session.mode.rawValue) options=\(session.categoryOptions.rawValue) output=\(outputName)")
    }
}
