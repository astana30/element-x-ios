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

struct DirectCallDiagnosticSnapshot: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    var activeSessionPhase: DirectCallDiagnosticSessionPhase = .none
    var lastSignalEventEmitted: DirectCallDiagnosticSignalEvent?
    var lastSignalSendAttempted = false
    var lastSignalSendSucceeded: Bool?
    var lastSignalSendFailureReason: DirectCallDiagnosticSignalSendFailureReason?
    var lastTerminalReason: DirectCallDiagnosticTerminalReason?

    static let empty = Self()

    var description: String {
        "DirectCallDiagnosticSnapshot(activeSessionPhase: \(activeSessionPhase), " +
            "lastSignalEventEmitted: \(String(describing: lastSignalEventEmitted)), " +
            "lastSignalSendAttempted: \(lastSignalSendAttempted), " +
            "lastSignalSendSucceeded: \(String(describing: lastSignalSendSucceeded)), " +
            "lastSignalSendFailureReason: \(String(describing: lastSignalSendFailureReason)), " +
            "lastTerminalReason: \(String(describing: lastTerminalReason)))"
    }

    var debugDescription: String {
        description
    }
}
#endif
