//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum DirectCallIntent: String, CaseIterable, Equatable {
    case audio
    case video

    static func parse(_ rawValue: String?) -> Self? {
        guard let rawValue else {
            return nil
        }

        switch rawValue.lowercased() {
        case Self.audio.rawValue:
            return .audio
        case Self.video.rawValue:
            return .video
        default:
            return nil
        }
    }
}

enum DirectCallEncryptionMode: Equatable {
    case e2eeRequired
}

enum DirectCallEncryptionFailureReason: Error, Equatable {
    case missingKeyExchange
    case keyMismatch
    case keyExchangeFailed
    case e2eeNotProven
    case e2eeUnavailable
    case cannotWrap
    case cannotUnwrap
    case missingPeer
    case missingMetadata
    case sdkWrapperUnavailable
    case sdkTrustViolation
    case sdkNoEligibleDevice
    case sdkEnvelopeFailed
    case unsupportedRuntime
}

enum DirectCallEncryptionState: Equatable {
    case pending
    case ready
    case failed(DirectCallEncryptionFailureReason)

    var isReadyForMediaPublishing: Bool {
        switch self {
        case .ready:
            true
        case .pending, .failed:
            false
        }
    }
}

enum DirectCallState: Equatable {
    case idle
    case outgoingRinging
    case incomingRinging
    case connecting
    case activeAudio
    case activeVideo
    case ending
    case ended
    case missed
    case cancelled
    case failed

    var isTerminal: Bool {
        switch self {
        case .ended, .missed, .cancelled, .failed:
            true
        case .idle, .outgoingRinging, .incomingRinging, .connecting, .activeAudio, .activeVideo, .ending:
            false
        }
    }
}

enum DirectCallDirection: Equatable {
    case incoming
    case outgoing
}

enum DirectCallSignalType: String, Equatable {
    case invite
    case answer
    case reject
    case cancel
    case hangup
    case timeout

    var isTerminal: Bool {
        switch self {
        case .reject, .cancel, .hangup, .timeout:
            true
        case .invite, .answer:
            false
        }
    }
}

struct DirectCallSignalEvent: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let eventID: String
    let roomID: String
    let senderID: String
    let callID: String
    let type: DirectCallSignalType
    let intent: DirectCallIntent?
    let timestamp: Date
    let keyExchange: DirectCallEncryptedKeyExchangePayload?

    init(eventID: String,
         roomID: String,
         senderID: String,
         callID: String,
         type: DirectCallSignalType,
         intent: DirectCallIntent?,
         timestamp: Date,
         keyExchange: DirectCallEncryptedKeyExchangePayload? = nil) {
        self.eventID = eventID
        self.roomID = roomID
        self.senderID = senderID
        self.callID = callID
        self.type = type
        self.intent = intent
        self.timestamp = timestamp
        self.keyExchange = keyExchange
    }

    var description: String {
        "DirectCallSignalEvent(" + [
            "eventID: \(eventID)",
            "roomID: \(roomID)",
            "senderID: \(senderID)",
            "callID: \(callID)",
            "type: \(type)",
            "intent: \(String(describing: intent))",
            "timestamp: \(timestamp)",
            "keyExchange: \(keyExchange == nil ? "nil" : "<redacted>")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallOutgoingSignal: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let roomID: String
    let peerUserID: String
    let callID: String
    let type: DirectCallSignalType
    let intent: DirectCallIntent?
    let keyExchange: DirectCallEncryptedKeyExchangePayload?

    init(roomID: String,
         peerUserID: String,
         callID: String,
         type: DirectCallSignalType,
         intent: DirectCallIntent?,
         keyExchange: DirectCallEncryptedKeyExchangePayload? = nil) {
        self.roomID = roomID
        self.peerUserID = peerUserID
        self.callID = callID
        self.type = type
        self.intent = intent
        self.keyExchange = keyExchange
    }

    var description: String {
        "DirectCallOutgoingSignal(roomID: \(roomID), peerUserID: \(peerUserID), callID: \(callID), type: \(type), intent: \(String(describing: intent)), keyExchange: \(keyExchange == nil ? "nil" : "<redacted>"))"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallSession: Equatable {
    let callID: String
    let roomID: String
    let peerUserID: String
    let direction: DirectCallDirection
    let intent: DirectCallIntent
    let encryptionMode: DirectCallEncryptionMode
    let startedAt: Date
    var updatedAt: Date
    var state: DirectCallState
    var encryptionState: DirectCallEncryptionState

    var isMediaPublishingAllowed: Bool {
        switch encryptionMode {
        case .e2eeRequired:
            encryptionState.isReadyForMediaPublishing
        }
    }
}

struct DirectCallEngineConfiguration {
    var incomingRingingTimeout: Duration = .seconds(45)
    var outgoingRingingTimeout: Duration = .seconds(45)
    var connectingTimeout: Duration = .seconds(20)
    var cleanupDelay: Duration = .seconds(2)
    var processedTerminalEventLimit = 64
}

enum DirectCallEngineAction: Equatable {
    case stateChanged(DirectCallSession)
    case emitSignal(DirectCallOutgoingSignal)
    case sessionCleared(callID: String, roomID: String)
}

enum DirectCallEngineError: Error, Equatable {
    case invalidRoomID
    case invalidPeer
    case invalidSender
    case invalidCallID
    case invalidIntent
    case staleOrUnknownEvent
    case roomMismatch
    case callIDMismatch
    case sessionAlreadyActive
    case invalidTransition
    case invalidEncryptionTransition
    case encryptionFailed(DirectCallEncryptionFailureReason)
    case mediaConnectionFailed
}

#if DEBUG
enum DirectCallDiagnosticSignalEvent: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case invite
    case answer
    case reject
    case cancel
    case hangup
    case timeout

    init(_ signalType: DirectCallSignalType) {
        switch signalType {
        case .invite:
            self = .invite
        case .answer:
            self = .answer
        case .reject:
            self = .reject
        case .cancel:
            self = .cancel
        case .hangup:
            self = .hangup
        case .timeout:
            self = .timeout
        }
    }

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticSessionPhase: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case idle
    case outgoingRinging
    case incomingRinging
    case connecting
    case active
    case ending
    case terminal
    case failed

    init(_ state: DirectCallState) {
        switch state {
        case .idle:
            self = .idle
        case .outgoingRinging:
            self = .outgoingRinging
        case .incomingRinging:
            self = .incomingRinging
        case .connecting:
            self = .connecting
        case .activeAudio, .activeVideo:
            self = .active
        case .ending:
            self = .ending
        case .ended, .missed, .cancelled:
            self = .terminal
        case .failed:
            self = .failed
        }
    }

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticSignalSendFailureReason: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case invalidSignal
    case sendFailed
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticTerminalReason: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case outgoingTimeout
    case incomingTimeout
    case connectingFailed
    case cancelled
    case hangup
    case failed
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticReceiveEventKind: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case nonEventTimelineItem
    case nonMessageLike
    case nonDirectCallEvent
    case directCallInvite
    case directCallAnswer
    case directCallReject
    case directCallCancel
    case directCallHangup
    case directCallTimeout
    case malformed
    case unknown

    init(_ signalType: DirectCallSignalType) {
        switch signalType {
        case .invite:
            self = .directCallInvite
        case .answer:
            self = .directCallAnswer
        case .reject:
            self = .directCallReject
        case .cancel:
            self = .directCallCancel
        case .hangup:
            self = .directCallHangup
        case .timeout:
            self = .directCallTimeout
        }
    }

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticEnvelopeRejectedReason: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case ownEvent
    case wrongEventType
    case missingEventID
    case missingSender
    case peerMismatch
    case contentUnavailable
    case decodeFailed
    case duplicateEventID
    case historicalBacklog
    case metadataUnavailable
    case unsupportedEvent
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticReceiveFailureReason: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case decodeFailed
    case engineRejected
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticMediaFailureReason: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case factoryUnavailable
    case credentialUnavailable
    case e2eeContextUnavailable
    case keyBridgeMiss
    case liveKitConnectFailed
    case invalidSessionState
    case unknown

    init(_ error: DirectCallMediaError) {
        switch error {
        case .invalidSession, .unsupportedIntent, .e2eeNotReady, .keyMismatch, .audioRouteFailed:
            self = .invalidSessionState
        case .e2eeContextUnavailable:
            self = .e2eeContextUnavailable
        case .tokenUnavailable:
            self = .credentialUnavailable
        case .mediaSetupUnavailable:
            self = .unknown
        }
    }

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticTimelineDiffKind: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case append
    case clear
    case insert
    case set
    case remove
    case pushBack
    case pushFront
    case popBack
    case popFront
    case truncate
    case reset
    case providerUpdate
    case mixed

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticRedactor {
    static func roomFingerprint(_ roomID: String) -> String? {
        guard !roomID.isEmpty else {
            return nil
        }

        // Stable FNV-1a fingerprint, short enough for diagnostics and never reversible in logs.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in roomID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }

        return String(format: "%016llx", hash)
    }
}

struct DirectCallDiagnosticSnapshot: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    var activeSessionPhase: DirectCallDiagnosticSessionPhase = .none
    var lastSignalEventEmitted: DirectCallDiagnosticSignalEvent?
    var lastSignalSendAttempted = false
    var lastSignalSendSucceeded: Bool?
    var lastSignalSendFailureReason: DirectCallDiagnosticSignalSendFailureReason?
    var lastTerminalReason: DirectCallDiagnosticTerminalReason?
    var listenerAttached = false
    var listenerHandleRetained = false
    var listenerStartCount = 0
    var timelineUpdateCount = 0
    var timelineDiffReceivedCount = 0
    var lastTimelineDiffKind: DirectCallDiagnosticTimelineDiffKind = .none
    var lastTimelineDiffItemCount = 0
    var timelineEventReceivedCount = 0
    var directCallEventTypeSeenCount = 0
    var envelopeExtractedCount = 0
    var envelopeDeliveredToEngineCount = 0
    var historicalEventIgnoredCount = 0
    var liveEventDeliveredCount = 0
    var baselineEstablished = false
    var lastReceiveEventKind: DirectCallDiagnosticReceiveEventKind = .none
    var lastEnvelopeRejectedReason: DirectCallDiagnosticEnvelopeRejectedReason = .none
    var lastReceiveFailureReason: DirectCallDiagnosticReceiveFailureReason?
    var sendRoomFingerprint: String?
    var receiveRoomFingerprint: String?
    var mediaFactoryInjected = false
    var mediaCredentialProviderAvailable = false
    var mediaE2EEProviderAvailable = false
    var mediaKeyHandleAvailable = false
    var mediaKeyBridgeHit = false
    var mediaConnectAttempted = false
    var liveKitClientConnectAttempted = false
    var mediaFailureReason: DirectCallDiagnosticMediaFailureReason = .none

    static let empty = Self()

    mutating func mergeReceiveDiagnostics(from other: Self) {
        listenerAttached = listenerAttached || other.listenerAttached
        listenerHandleRetained = listenerHandleRetained || other.listenerHandleRetained
        listenerStartCount = max(listenerStartCount, other.listenerStartCount)
        timelineUpdateCount = max(timelineUpdateCount, other.timelineUpdateCount)
        timelineDiffReceivedCount = max(timelineDiffReceivedCount, other.timelineDiffReceivedCount)
        if other.lastTimelineDiffKind != .none {
            lastTimelineDiffKind = other.lastTimelineDiffKind
            lastTimelineDiffItemCount = other.lastTimelineDiffItemCount
        }
        timelineEventReceivedCount = max(timelineEventReceivedCount, other.timelineEventReceivedCount)
        directCallEventTypeSeenCount = max(directCallEventTypeSeenCount, other.directCallEventTypeSeenCount)
        envelopeExtractedCount = max(envelopeExtractedCount, other.envelopeExtractedCount)
        envelopeDeliveredToEngineCount = max(envelopeDeliveredToEngineCount, other.envelopeDeliveredToEngineCount)
        historicalEventIgnoredCount = max(historicalEventIgnoredCount, other.historicalEventIgnoredCount)
        liveEventDeliveredCount = max(liveEventDeliveredCount, other.liveEventDeliveredCount)
        baselineEstablished = baselineEstablished || other.baselineEstablished
        if other.lastReceiveEventKind != .none {
            lastReceiveEventKind = other.lastReceiveEventKind
        }
        if other.lastEnvelopeRejectedReason != .none {
            lastEnvelopeRejectedReason = other.lastEnvelopeRejectedReason
        }
        if let lastReceiveFailureReason = other.lastReceiveFailureReason {
            self.lastReceiveFailureReason = lastReceiveFailureReason
        }
        if let sendRoomFingerprint = other.sendRoomFingerprint {
            self.sendRoomFingerprint = sendRoomFingerprint
        }
        if let receiveRoomFingerprint = other.receiveRoomFingerprint {
            self.receiveRoomFingerprint = receiveRoomFingerprint
        }
        mediaFactoryInjected = mediaFactoryInjected || other.mediaFactoryInjected
        mediaCredentialProviderAvailable = mediaCredentialProviderAvailable || other.mediaCredentialProviderAvailable
        mediaE2EEProviderAvailable = mediaE2EEProviderAvailable || other.mediaE2EEProviderAvailable
        mediaKeyHandleAvailable = mediaKeyHandleAvailable || other.mediaKeyHandleAvailable
        mediaKeyBridgeHit = mediaKeyBridgeHit || other.mediaKeyBridgeHit
        mediaConnectAttempted = mediaConnectAttempted || other.mediaConnectAttempted
        liveKitClientConnectAttempted = liveKitClientConnectAttempted || other.liveKitClientConnectAttempted
        if other.mediaFailureReason != .none {
            mediaFailureReason = other.mediaFailureReason
        }
    }

    var description: String {
        "DirectCallDiagnosticSnapshot(activeSessionPhase: \(activeSessionPhase), " +
            "lastSignalEventEmitted: \(String(describing: lastSignalEventEmitted)), " +
            "lastSignalSendAttempted: \(lastSignalSendAttempted), " +
            "lastSignalSendSucceeded: \(String(describing: lastSignalSendSucceeded)), " +
            "lastSignalSendFailureReason: \(String(describing: lastSignalSendFailureReason)), " +
            "lastTerminalReason: \(String(describing: lastTerminalReason)), " +
            "listenerAttached: \(listenerAttached), " +
            "listenerHandleRetained: \(listenerHandleRetained), " +
            "listenerStartCount: \(listenerStartCount), " +
            "timelineUpdateCount: \(timelineUpdateCount), " +
            "timelineDiffReceivedCount: \(timelineDiffReceivedCount), " +
            "lastTimelineDiffKind: \(lastTimelineDiffKind), " +
            "lastTimelineDiffItemCount: \(lastTimelineDiffItemCount), " +
            "timelineEventReceivedCount: \(timelineEventReceivedCount), " +
            "directCallEventTypeSeenCount: \(directCallEventTypeSeenCount), " +
            "envelopeExtractedCount: \(envelopeExtractedCount), " +
            "envelopeDeliveredToEngineCount: \(envelopeDeliveredToEngineCount), " +
            "historicalEventIgnoredCount: \(historicalEventIgnoredCount), " +
            "liveEventDeliveredCount: \(liveEventDeliveredCount), " +
            "baselineEstablished: \(baselineEstablished), " +
            "lastReceiveEventKind: \(lastReceiveEventKind), " +
            "lastEnvelopeRejectedReason: \(lastEnvelopeRejectedReason), " +
            "lastReceiveFailureReason: \(String(describing: lastReceiveFailureReason)), " +
            "sendRoomFingerprint: \(String(describing: sendRoomFingerprint)), " +
            "receiveRoomFingerprint: \(String(describing: receiveRoomFingerprint)), " +
            "mediaFactoryInjected: \(mediaFactoryInjected), " +
            "mediaCredentialProviderAvailable: \(mediaCredentialProviderAvailable), " +
            "mediaE2EEProviderAvailable: \(mediaE2EEProviderAvailable), " +
            "mediaKeyHandleAvailable: \(mediaKeyHandleAvailable), " +
            "mediaKeyBridgeHit: \(mediaKeyBridgeHit), " +
            "mediaConnectAttempted: \(mediaConnectAttempted), " +
            "liveKitClientConnectAttempted: \(liveKitClientConnectAttempted), " +
            "mediaFailureReason: \(mediaFailureReason))"
    }

    var debugDescription: String {
        description
    }
}
#endif
