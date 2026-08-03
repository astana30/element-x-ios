//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// swiftlint:disable file_length

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
    case wrongRecipient
    case expiredKeyExchange
    case unsupportedEnvelope
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
    case mediaConnectionFailed(DirectCallMediaError)
}

struct NativeIncomingCallHandle: Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    let value: String

    init?(_ value: String) {
        guard Self.isValid(value) else {
            return nil
        }
        self.value = value
    }

    private static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else {
            return false
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return value.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    var description: String {
        "NativeIncomingCallHandle(value: <redacted>, isPresent: true)"
    }

    var debugDescription: String {
        description
    }
}

struct NativeIncomingCallIdentity: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let handle: NativeIncomingCallHandle
    let receivedAt: Date

    var description: String {
        "NativeIncomingCallIdentity(handle: <redacted>, receivedAt: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

enum NativeIncomingCallLifecycleState: String, Codable, Equatable, CaseIterable, CustomStringConvertible, CustomDebugStringConvertible {
    case idle
    case received
    case validating
    case reportable
    case reported
    case answered
    case answerRequested
    case foregroundCredentialAuthorized
    case connecting
    case active
    case ended
    case failed
    case stale
    case rejected
    case missed
    case blocked

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum NativeIncomingCallFailClosedReason: String, Codable, Equatable, CaseIterable, CustomStringConvertible, CustomDebugStringConvertible {
    case malformed
    case stale
    case duplicate
    case unverifiable
    case notEncryptedDirectOneToOne
    case trustNotReady
    case eligibilityDenied
    case dependencyUnavailable
    case existingActiveNativeSession
    case loggedOutOrSessionUnavailable
    case callReportingUnavailable
    case foregroundCredentialAuthorityUnavailable
    case foregroundCredentialDenied
    case foregroundCredentialMalformed
    case foregroundCredentialExpired
    case foregroundCredentialUnverifiable
    case serverIssuedMediaCredentialRejected
    case mediaSetupUnavailable
    case routeConflict
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct NativeIncomingCallValidationContext: Equatable {
    var isEncryptedDirectOneToOneRoom = true
    var isPeerTrustReady = true
    var isEligible = true
    var areDependenciesAvailable = true
    var hasExistingActiveNativeSession = false
    var isLoggedIn = true
    var isRouteAvailable = true

    static let valid = Self()

    var failClosedReason: NativeIncomingCallFailClosedReason? {
        if !isEncryptedDirectOneToOneRoom {
            return .notEncryptedDirectOneToOne
        }
        if !isPeerTrustReady {
            return .trustNotReady
        }
        if !isEligible {
            return .eligibilityDenied
        }
        if !areDependenciesAvailable {
            return .dependencyUnavailable
        }
        if hasExistingActiveNativeSession {
            return .existingActiveNativeSession
        }
        if !isLoggedIn {
            return .loggedOutOrSessionUnavailable
        }
        if !isRouteAvailable {
            return .routeConflict
        }
        return nil
    }
}

struct NativeIncomingCallRedactedDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    var lifecycleState: NativeIncomingCallLifecycleState
    var failClosedReason: NativeIncomingCallFailClosedReason?
    var reportAttempted: Bool
    var reportSucceeded: Bool?
    var mediaCredentialRequested: Bool
    var mediaConnectAttempted: Bool

    static func failClosed(_ reason: NativeIncomingCallFailClosedReason) -> Self {
        .init(lifecycleState: .blocked,
              failClosedReason: reason,
              reportAttempted: false,
              reportSucceeded: nil,
              mediaCredentialRequested: false,
              mediaConnectAttempted: false)
    }

    var description: String {
        "NativeIncomingCallRedactedDiagnostics(" + [
            "lifecycleState: \(lifecycleState)",
            "failClosedReason: \(failClosedReason?.description ?? "none")",
            "reportAttempted: \(reportAttempted)",
            "reportSucceeded: \(reportSucceeded.map(String.init) ?? "none")",
            "mediaCredentialRequested: \(mediaCredentialRequested)",
            "mediaConnectAttempted: \(mediaConnectAttempted)"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

enum NativeIncomingCallLifecycleOutcome: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case failClosed(NativeIncomingCallFailClosedReason)
    case reportable(NativeIncomingCallIdentity)
    case reported(NativeIncomingCallIdentity)

    var description: String {
        switch self {
        case .failClosed(let reason):
            "failClosed(\(reason))"
        case .reportable:
            "reportable(identity: <redacted>)"
        case .reported:
            "reported(identity: <redacted>)"
        }
    }

    var debugDescription: String {
        description
    }
}

enum NativeIncomingForegroundAcceptanceDecision: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case authorized
    case denied
    case malformed
    case expired
    case unverifiable

    var failClosedReason: NativeIncomingCallFailClosedReason? {
        switch self {
        case .authorized:
            nil
        case .denied:
            .foregroundCredentialDenied
        case .malformed:
            .foregroundCredentialMalformed
        case .expired:
            .foregroundCredentialExpired
        case .unverifiable:
            .foregroundCredentialUnverifiable
        }
    }

    var description: String {
        switch self {
        case .authorized:
            "authorized"
        case .denied:
            "denied"
        case .malformed:
            "malformed"
        case .expired:
            "expired"
        case .unverifiable:
            "unverifiable"
        }
    }

    var debugDescription: String {
        description
    }
}

enum NativeIncomingForegroundAcceptanceOutcome: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case failClosed(NativeIncomingCallFailClosedReason)
    case credentialAuthorized(NativeIncomingCallIdentity)

    var description: String {
        switch self {
        case .failClosed(let reason):
            "failClosed(\(reason))"
        case .credentialAuthorized:
            "credentialAuthorized(identity: <redacted>)"
        }
    }

    var debugDescription: String {
        description
    }
}

enum NativeForegroundIncomingCallE2EOutcome: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case callKitReported(NativeIncomingCallIdentity)
    case mediaConnected(NativeIncomingCallIdentity)
    case ended
    case muted(Bool)
    case failClosed(NativeIncomingCallFailClosedReason)

    var description: String {
        switch self {
        case .callKitReported:
            "callKitReported(identity: <redacted>)"
        case .mediaConnected:
            "mediaConnected(identity: <redacted>)"
        case .ended:
            "ended"
        case .muted(let isMuted):
            "muted(\(isMuted))"
        case .failClosed(let reason):
            "failClosed(\(reason))"
        }
    }

    var debugDescription: String {
        description
    }
}

enum NativeForegroundIncomingMediaConnectionOutcome: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case connected
    case failClosed(NativeIncomingCallFailClosedReason)

    var description: String {
        switch self {
        case .connected:
            "connected"
        case .failClosed(let reason):
            "failClosed(\(reason))"
        }
    }

    var debugDescription: String {
        description
    }
}

struct NativeIncomingPushRegistrationCredential: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    enum Kind: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
        case standard
        case voIP

        var description: String {
            rawValue
        }

        var debugDescription: String {
            description
        }
    }

    let kind: Kind
    private let value: Data

    init(kind: Kind, value: Data) {
        self.kind = kind
        self.value = value
    }

    var isPresent: Bool {
        !value.isEmpty
    }

    var description: String {
        "NativeIncomingPushRegistrationCredential(kind: \(kind), value: <redacted>, isPresent: \(isPresent))"
    }

    var debugDescription: String {
        description
    }
}

protocol NativeIncomingCallStateStoring: AnyObject {
    func state(for handle: NativeIncomingCallHandle) -> NativeIncomingCallLifecycleState?
    func hasSeen(_ handle: NativeIncomingCallHandle) -> Bool
    func setState(_ state: NativeIncomingCallLifecycleState, for handle: NativeIncomingCallHandle)
    func clear(_ handle: NativeIncomingCallHandle)
}

protocol NativeIncomingCallReportingAdapting: AnyObject {
    func reportIncomingCall(identity: NativeIncomingCallIdentity) -> Bool
    func endReportedCall(identity: NativeIncomingCallIdentity, reason: NativeIncomingCallFailClosedReason)
}

protocol NativeIncomingPushRegistryManaging: AnyObject {
    func registerForIncomingCallPushes() -> Bool
    func updateIncomingCallPushCredential(_ credential: NativeIncomingPushRegistrationCredential)
    func unregisterIncomingCallPushes()
}

struct DirectCallBackgroundInvitePayload: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let handle: NativeIncomingCallHandle
    let kind: ForegroundCallInviteKind
    let createdAt: Date
    let expiresAt: Date
    let displayMetadata: NativeIncomingCallKitDisplayMetadata

    var description: String {
        "DirectCallBackgroundInvitePayload(handle: <redacted>, kind: \(kind), createdAt: <redacted>, expiresAt: <redacted>, displayMetadata: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundInvitePayloadError: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case missingRequiredField = "missing_required_field"
    case invalidType = "invalid_type"
    case invalidTimestamp = "invalid_timestamp"
    case expired
    case futureTimestampExcessive = "future_timestamp_excessive"
    case unsupportedVersion = "unsupported_version"
    case malformedPayload = "malformed_payload"
    case redacted

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundInvitePayloadValidationResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case valid(DirectCallBackgroundInvitePayload)
    case invalid(DirectCallBackgroundInvitePayloadError)

    var description: String {
        switch self {
        case .valid:
            "valid(payload: <redacted>)"
        case .invalid(let error):
            error.description
        }
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundInvitePayloadParser: CustomStringConvertible, CustomDebugStringConvertible {
    private enum Constants {
        static let expectedType = "salemx.direct_call.background.invite"
        static let supportedVersion = 1
    }

    var futureSkewAllowance: TimeInterval = 5

    func parse(_ payload: [String: Any], now: Date = .now) -> DirectCallBackgroundInvitePayloadValidationResult {
        guard !payload.isEmpty else {
            return .invalid(.malformedPayload)
        }
        guard let type = requiredString("type", in: payload),
              let callHandle = requiredString("call_handle", in: payload),
              let callKind = requiredString("call_kind", in: payload),
              let displayLabel = requiredString("display_label", in: payload),
              let version = requiredInteger("version", in: payload),
              let createdAtMs = requiredInteger("created_at_ms", in: payload),
              let expiresAtMs = requiredInteger("expires_at_ms", in: payload) else {
            return missingOrInvalidRequiredField(in: payload)
        }
        guard type == Constants.expectedType else {
            return .invalid(.invalidType)
        }
        guard version == Constants.supportedVersion else {
            return .invalid(.unsupportedVersion)
        }
        guard createdAtMs >= 0,
              expiresAtMs >= 0,
              expiresAtMs > createdAtMs else {
            return .invalid(.invalidTimestamp)
        }

        let createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1000)
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAtMs) / 1000)

        guard createdAt <= now.addingTimeInterval(futureSkewAllowance) else {
            return .invalid(.futureTimestampExcessive)
        }
        guard expiresAt > now else {
            return .invalid(.expired)
        }
        guard let handle = NativeIncomingCallHandle(callHandle),
              let displayMetadata = NativeIncomingCallKitDisplayMetadata(displayLabel) else {
            return .invalid(.malformedPayload)
        }

        let kind = ForegroundCallInviteKind(rawValue: callKind) ?? .unsupported
        guard kind != .unsupported else {
            return .invalid(.invalidType)
        }

        return .valid(.init(handle: handle,
                            kind: kind,
                            createdAt: createdAt,
                            expiresAt: expiresAt,
                            displayMetadata: displayMetadata))
    }

    private func requiredString(_ key: String, in payload: [String: Any]) -> String? {
        guard let value = payload[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private func requiredInteger(_ key: String, in payload: [String: Any]) -> Int? {
        if let value = payload[key] as? Int {
            return value
        }
        if let value = payload[key] as? Int64,
           value <= Int64(Int.max),
           value >= Int64(Int.min) {
            return Int(value)
        }
        if let value = payload[key] as? Double,
           value.rounded(.towardZero) == value,
           value <= Double(Int.max),
           value >= Double(Int.min) {
            return Int(value)
        }
        return nil
    }

    private func missingOrInvalidRequiredField(in payload: [String: Any]) -> DirectCallBackgroundInvitePayloadValidationResult {
        let requiredFields = [
            "type",
            "version",
            "call_handle",
            "call_kind",
            "created_at_ms",
            "expires_at_ms",
            "display_label"
        ]

        guard requiredFields.allSatisfy({ payload.keys.contains($0) }) else {
            return .invalid(.missingRequiredField)
        }
        return .invalid(.invalidType)
    }

    var description: String {
        "DirectCallBackgroundInvitePayloadParser(pushRegistryRuntime: false, apnsRegistrationRuntime: false, mediaConnectRuntime: false, matrixEventRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundInvitePreparedIncoming: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let identity: NativeIncomingCallIdentity
    let kind: ForegroundCallInviteKind
    let expiresAt: Date
    let displayMetadata: NativeIncomingCallKitDisplayMetadata

    var description: String {
        "DirectCallBackgroundInvitePreparedIncoming(identity: <redacted>, kind: \(kind), expiresAt: <redacted>, displayMetadata: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundInviteIntakeDecision: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case ignoreInvalidPayload = "ignore_invalid_payload"
    case ignoreExpiredPayload = "ignore_expired_payload"
    case ignoreFutureTimestampExcessive = "ignore_future_timestamp_excessive"
    case prepareForegroundEquivalentIncoming = "prepare_foreground_equivalent_incoming"
    case requiresAuthenticatedSession = "requires_authenticated_session"
    case requiresCallKitReportLater = "requires_callkit_report_later"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundInviteIntakeFailure: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case invalidPayload = "invalid_payload"
    case expiredPayload = "expired"
    case futureTimestampExcessive = "future_timestamp_excessive"
    case authenticatedSessionUnavailable = "authenticated_session_unavailable"
    case redacted

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundInviteIntakeDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let intakeInvoked: Bool
    let payloadParseStatus: String
    let intakeDecision: DirectCallBackgroundInviteIntakeDecision
    let callKitReportRequested: Bool
    let mediaCredentialsRequested: Bool
    let mediaConnectRequested: Bool
    let matrixEventEmitRequested: Bool
    let blockedReason: DirectCallBackgroundInviteIntakeFailure?

    var description: String {
        "DirectCallBackgroundInviteIntakeDiagnostics(" + [
            "intake_invoked=\(intakeInvoked)",
            "payload_parse_status=\(payloadParseStatus)",
            "intake_decision=\(intakeDecision)",
            "callkit_report_requested=\(callKitReportRequested)",
            "media_credentials_requested=\(mediaCredentialsRequested)",
            "media_connect_requested=\(mediaConnectRequested)",
            "matrix_event_emit_requested=\(matrixEventEmitRequested)",
            "blocked_reason=\(blockedReason?.description ?? "none")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundInviteIntakeResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let decision: DirectCallBackgroundInviteIntakeDecision
    let preparedIncoming: DirectCallBackgroundInvitePreparedIncoming?
    let diagnostics: DirectCallBackgroundInviteIntakeDiagnostics

    var description: String {
        "DirectCallBackgroundInviteIntakeResult(decision: \(decision), preparedIncoming: <redacted>, diagnostics: \(diagnostics))"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundInviteIntake: CustomStringConvertible, CustomDebugStringConvertible {
    func evaluate(_ validationResult: DirectCallBackgroundInvitePayloadValidationResult,
                  authenticatedSessionAvailable: Bool = false,
                  callKitReportAdapterAvailable: Bool = false) -> DirectCallBackgroundInviteIntakeResult {
        switch validationResult {
        case .invalid(let error):
            let decision = decision(for: error)
            return .init(decision: decision,
                         preparedIncoming: nil,
                         diagnostics: diagnostics(parseStatus: error.description,
                                                  decision: decision,
                                                  blockedReason: failure(for: error)))
        case .valid(let payload):
            guard authenticatedSessionAvailable else {
                return .init(decision: .requiresAuthenticatedSession,
                             preparedIncoming: nil,
                             diagnostics: diagnostics(parseStatus: "valid",
                                                      decision: .requiresAuthenticatedSession,
                                                      blockedReason: .authenticatedSessionUnavailable))
            }

            let preparedIncoming = DirectCallBackgroundInvitePreparedIncoming(identity: .init(handle: payload.handle,
                                                                                              receivedAt: payload.createdAt),
                                                                              kind: payload.kind,
                                                                              expiresAt: payload.expiresAt,
                                                                              displayMetadata: payload.displayMetadata)
            let decision: DirectCallBackgroundInviteIntakeDecision = callKitReportAdapterAvailable ? .requiresCallKitReportLater : .prepareForegroundEquivalentIncoming
            return .init(decision: decision,
                         preparedIncoming: preparedIncoming,
                         diagnostics: diagnostics(parseStatus: "valid",
                                                  decision: decision,
                                                  blockedReason: nil))
        }
    }

    private func decision(for error: DirectCallBackgroundInvitePayloadError) -> DirectCallBackgroundInviteIntakeDecision {
        switch error {
        case .expired:
            .ignoreExpiredPayload
        case .futureTimestampExcessive:
            .ignoreFutureTimestampExcessive
        case .missingRequiredField, .invalidType, .invalidTimestamp, .unsupportedVersion, .malformedPayload, .redacted:
            .ignoreInvalidPayload
        }
    }

    private func failure(for error: DirectCallBackgroundInvitePayloadError) -> DirectCallBackgroundInviteIntakeFailure {
        switch error {
        case .expired:
            .expiredPayload
        case .futureTimestampExcessive:
            .futureTimestampExcessive
        case .missingRequiredField, .invalidType, .invalidTimestamp, .unsupportedVersion, .malformedPayload, .redacted:
            .invalidPayload
        }
    }

    private func diagnostics(parseStatus: String,
                             decision: DirectCallBackgroundInviteIntakeDecision,
                             blockedReason: DirectCallBackgroundInviteIntakeFailure?) -> DirectCallBackgroundInviteIntakeDiagnostics {
        .init(intakeInvoked: true,
              payloadParseStatus: parseStatus,
              intakeDecision: decision,
              callKitReportRequested: false,
              mediaCredentialsRequested: false,
              mediaConnectRequested: false,
              matrixEventEmitRequested: false,
              blockedReason: blockedReason)
    }

    var description: String {
        "DirectCallBackgroundInviteIntake(pushRegistryRuntime: false, apnsRegistrationRuntime: false, callKitReportRuntime: false, mediaConnectRuntime: false, matrixEventRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundCallKitReportRequest: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let callUUID: UUID
    let identity: NativeIncomingCallIdentity
    let kind: ForegroundCallInviteKind
    let expiresAt: Date
    let displayMetadata: NativeIncomingCallKitDisplayMetadata

    var description: String {
        "DirectCallBackgroundCallKitReportRequest(callUUID: <redacted>, identity: <redacted>, kind: \(kind), expiresAt: <redacted>, displayMetadata: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundCallKitReportDecision: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case notReportableInvalidPayload = "not_reportable_invalid_payload"
    case notReportableExpiredPayload = "not_reportable_expired_payload"
    case notReportableFutureTimestampExcessive = "not_reportable_future_timestamp_excessive"
    case notReportableRequiresAuthenticatedSession = "not_reportable_requires_authenticated_session"
    case reportableIncomingCallRequest = "reportable_incoming_call_request"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundCallKitReportFailure: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case invalidPayload = "invalid_payload"
    case expiredPayload = "expired"
    case futureTimestampExcessive = "future_timestamp_excessive"
    case authenticatedSessionUnavailable = "authenticated_session_unavailable"
    case missingPreparedIncoming = "missing_prepared_incoming"
    case redacted

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundCallKitReportDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let callKitPlannerInvoked: Bool
    let intakeDecision: DirectCallBackgroundInviteIntakeDecision
    let callKitReportDecision: DirectCallBackgroundCallKitReportDecision
    let callKitReportRequested: Bool
    let mediaCredentialsRequested: Bool
    let mediaConnectRequested: Bool
    let matrixEventEmitRequested: Bool
    let blockedReason: DirectCallBackgroundCallKitReportFailure?

    var description: String {
        "DirectCallBackgroundCallKitReportDiagnostics(" + [
            "callkit_planner_invoked=\(callKitPlannerInvoked)",
            "intake_decision=\(intakeDecision)",
            "callkit_report_decision=\(callKitReportDecision)",
            "callkit_report_requested=\(callKitReportRequested)",
            "media_credentials_requested=\(mediaCredentialsRequested)",
            "media_connect_requested=\(mediaConnectRequested)",
            "matrix_event_emit_requested=\(matrixEventEmitRequested)",
            "blocked_reason=\(blockedReason?.description ?? "none")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundCallKitReportPlanningResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let decision: DirectCallBackgroundCallKitReportDecision
    let request: DirectCallBackgroundCallKitReportRequest?
    let diagnostics: DirectCallBackgroundCallKitReportDiagnostics

    var description: String {
        "DirectCallBackgroundCallKitReportPlanningResult(decision: \(decision), request: <redacted>, diagnostics: \(diagnostics))"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundCallKitReportPlanner: CustomStringConvertible, CustomDebugStringConvertible {
    var makeCallUUID: () -> UUID = UUID.init

    func plan(from intakeResult: DirectCallBackgroundInviteIntakeResult) -> DirectCallBackgroundCallKitReportPlanningResult {
        switch intakeResult.decision {
        case .prepareForegroundEquivalentIncoming, .requiresCallKitReportLater:
            guard let preparedIncoming = intakeResult.preparedIncoming else {
                return nonReportableResult(intakeDecision: intakeResult.decision,
                                           decision: .notReportableInvalidPayload,
                                           blockedReason: .missingPreparedIncoming)
            }

            let request = DirectCallBackgroundCallKitReportRequest(callUUID: makeCallUUID(),
                                                                   identity: preparedIncoming.identity,
                                                                   kind: preparedIncoming.kind,
                                                                   expiresAt: preparedIncoming.expiresAt,
                                                                   displayMetadata: preparedIncoming.displayMetadata)
            return .init(decision: .reportableIncomingCallRequest,
                         request: request,
                         diagnostics: diagnostics(intakeDecision: intakeResult.decision,
                                                  reportDecision: .reportableIncomingCallRequest,
                                                  reportRequested: true,
                                                  blockedReason: nil))
        case .ignoreInvalidPayload:
            return nonReportableResult(intakeDecision: .ignoreInvalidPayload,
                                       decision: .notReportableInvalidPayload,
                                       blockedReason: .invalidPayload)
        case .ignoreExpiredPayload:
            return nonReportableResult(intakeDecision: .ignoreExpiredPayload,
                                       decision: .notReportableExpiredPayload,
                                       blockedReason: .expiredPayload)
        case .ignoreFutureTimestampExcessive:
            return nonReportableResult(intakeDecision: .ignoreFutureTimestampExcessive,
                                       decision: .notReportableFutureTimestampExcessive,
                                       blockedReason: .futureTimestampExcessive)
        case .requiresAuthenticatedSession:
            return nonReportableResult(intakeDecision: .requiresAuthenticatedSession,
                                       decision: .notReportableRequiresAuthenticatedSession,
                                       blockedReason: .authenticatedSessionUnavailable)
        }
    }

    private func nonReportableResult(intakeDecision: DirectCallBackgroundInviteIntakeDecision,
                                     decision: DirectCallBackgroundCallKitReportDecision,
                                     blockedReason: DirectCallBackgroundCallKitReportFailure) -> DirectCallBackgroundCallKitReportPlanningResult {
        .init(decision: decision,
              request: nil,
              diagnostics: diagnostics(intakeDecision: intakeDecision,
                                       reportDecision: decision,
                                       reportRequested: false,
                                       blockedReason: blockedReason))
    }

    private func diagnostics(intakeDecision: DirectCallBackgroundInviteIntakeDecision,
                             reportDecision: DirectCallBackgroundCallKitReportDecision,
                             reportRequested: Bool,
                             blockedReason: DirectCallBackgroundCallKitReportFailure?) -> DirectCallBackgroundCallKitReportDiagnostics {
        .init(callKitPlannerInvoked: true,
              intakeDecision: intakeDecision,
              callKitReportDecision: reportDecision,
              callKitReportRequested: reportRequested,
              mediaCredentialsRequested: false,
              mediaConnectRequested: false,
              matrixEventEmitRequested: false,
              blockedReason: blockedReason)
    }

    var description: String {
        "DirectCallBackgroundCallKitReportPlanner(callKitRuntime: false, pushRegistryRuntime: false, apnsRegistrationRuntime: false, mediaConnectRuntime: false, matrixEventRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundCallKitReportingResultStatus: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case notReportedNotReportable = "not_reported_not_reportable"
    case notReportedMissingAuthenticatedContext = "not_reported_missing_authenticated_context"
    case reportAttemptRecorded = "report_attempt_recorded"
    case reportFailedRedacted = "report_failed_redacted"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundCallKitReportingFailure: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case notReportable = "not_reportable"
    case authenticatedSessionUnavailable = "authenticated_session_unavailable"
    case missingReportRequest = "missing_report_request"
    case reportFailedRedacted = "report_failed_redacted"
    case redacted

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundCallKitReportingDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let callKitAdapterInvoked: Bool
    let callKitReportAttempted: Bool
    let callKitReportResult: DirectCallBackgroundCallKitReportingResultStatus
    let mediaCredentialsRequested: Bool
    let mediaConnectRequested: Bool
    let matrixEventEmitRequested: Bool
    let pushKitRegistrationRequested: Bool
    let apnsRegistrationRequested: Bool
    let blockedReason: DirectCallBackgroundCallKitReportingFailure?

    var description: String {
        "DirectCallBackgroundCallKitReportingDiagnostics(" + [
            "callkit_adapter_invoked=\(callKitAdapterInvoked)",
            "callkit_report_attempted=\(callKitReportAttempted)",
            "callkit_report_result=\(callKitReportResult)",
            "media_credentials_requested=\(mediaCredentialsRequested)",
            "media_connect_requested=\(mediaConnectRequested)",
            "matrix_event_emit_requested=\(matrixEventEmitRequested)",
            "pushkit_registration_requested=\(pushKitRegistrationRequested)",
            "apns_registration_requested=\(apnsRegistrationRequested)",
            "blocked_reason=\(blockedReason?.description ?? "none")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundCallKitReportingResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let status: DirectCallBackgroundCallKitReportingResultStatus
    let diagnostics: DirectCallBackgroundCallKitReportingDiagnostics

    var description: String {
        "DirectCallBackgroundCallKitReportingResult(status: \(status), diagnostics: \(diagnostics))"
    }

    var debugDescription: String {
        description
    }
}

protocol DirectCallBackgroundCallKitReporting {
    func report(_ planningResult: DirectCallBackgroundCallKitReportPlanningResult) -> DirectCallBackgroundCallKitReportingResult
}

struct DirectCallBackgroundCallKitReportingAdapter: DirectCallBackgroundCallKitReporting, CustomStringConvertible, CustomDebugStringConvertible {
    var recordReportAttempt: (DirectCallBackgroundCallKitReportRequest) -> Bool = { _ in false }

    func report(_ planningResult: DirectCallBackgroundCallKitReportPlanningResult) -> DirectCallBackgroundCallKitReportingResult {
        guard planningResult.decision == .reportableIncomingCallRequest else {
            return result(status: planningResult.decision == .notReportableRequiresAuthenticatedSession ? .notReportedMissingAuthenticatedContext : .notReportedNotReportable,
                          attempted: false,
                          blockedReason: reportingFailure(for: planningResult))
        }
        guard let request = planningResult.request else {
            return result(status: .reportFailedRedacted,
                          attempted: false,
                          blockedReason: .missingReportRequest)
        }

        let didRecordAttempt = recordReportAttempt(request)
        return result(status: didRecordAttempt ? .reportAttemptRecorded : .reportFailedRedacted,
                      attempted: true,
                      blockedReason: didRecordAttempt ? nil : .reportFailedRedacted)
    }

    private func reportingFailure(for planningResult: DirectCallBackgroundCallKitReportPlanningResult) -> DirectCallBackgroundCallKitReportingFailure {
        switch planningResult.decision {
        case .notReportableRequiresAuthenticatedSession:
            .authenticatedSessionUnavailable
        case .notReportableInvalidPayload,
             .notReportableExpiredPayload,
             .notReportableFutureTimestampExcessive:
            .notReportable
        case .reportableIncomingCallRequest:
            planningResult.request == nil ? .missingReportRequest : .redacted
        }
    }

    private func result(status: DirectCallBackgroundCallKitReportingResultStatus,
                        attempted: Bool,
                        blockedReason: DirectCallBackgroundCallKitReportingFailure?) -> DirectCallBackgroundCallKitReportingResult {
        .init(status: status,
              diagnostics: .init(callKitAdapterInvoked: true,
                                 callKitReportAttempted: attempted,
                                 callKitReportResult: status,
                                 mediaCredentialsRequested: false,
                                 mediaConnectRequested: false,
                                 matrixEventEmitRequested: false,
                                 pushKitRegistrationRequested: false,
                                 apnsRegistrationRequested: false,
                                 blockedReason: blockedReason))
    }

    var description: String {
        "DirectCallBackgroundCallKitReportingAdapter(realCallKitRuntime: false, pushKitRuntime: false, apnsRegistrationRuntime: false, mediaRuntime: false, matrixEventRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundCallKitProviderReportRequest: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let callUUID: UUID
    let kind: ForegroundCallInviteKind
    let expiresAt: Date
    let displayMetadata: NativeIncomingCallKitDisplayMetadata

    var description: String {
        "DirectCallBackgroundCallKitProviderReportRequest(callUUID: <redacted>, kind: \(kind), expiresAt: <redacted>, displayMetadata: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundRealCallKitReportStatus: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case notReportedNotReportable = "not_reported_not_reportable"
    case notReportedMissingAuthenticatedContext = "not_reported_missing_authenticated_context"
    case reportAttemptRecorded = "report_attempt_recorded"
    case reportFailedRedacted = "report_failed_redacted"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallBackgroundRealCallKitReportFailure: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case notReportable = "not_reportable"
    case authenticatedSessionUnavailable = "authenticated_session_unavailable"
    case missingReportRequest = "missing_report_request"
    case providerFailedRedacted = "provider_failed_redacted"
    case redacted

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundRealCallKitReportDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let realCallKitAdapterInvoked: Bool
    let callKitProviderReportAttempted: Bool
    let callKitProviderReportResult: DirectCallBackgroundRealCallKitReportStatus
    let providerFailureClass: DirectCallBackgroundRealCallKitReportFailure?
    let mediaCredentialsRequested: Bool
    let mediaConnectRequested: Bool
    let matrixEventEmitRequested: Bool
    let pushKitRegistrationRequested: Bool
    let apnsRegistrationRequested: Bool
    let blockedReason: DirectCallBackgroundRealCallKitReportFailure?

    var description: String {
        "DirectCallBackgroundRealCallKitReportDiagnostics(" + [
            "real_callkit_adapter_invoked=\(realCallKitAdapterInvoked)",
            "callkit_provider_report_attempted=\(callKitProviderReportAttempted)",
            "callkit_provider_report_result=\(callKitProviderReportResult)",
            "provider_failure_class=\(providerFailureClass?.description ?? "none")",
            "media_credentials_requested=\(mediaCredentialsRequested)",
            "media_connect_requested=\(mediaConnectRequested)",
            "matrix_event_emit_requested=\(matrixEventEmitRequested)",
            "pushkit_registration_requested=\(pushKitRegistrationRequested)",
            "apns_registration_requested=\(apnsRegistrationRequested)",
            "blocked_reason=\(blockedReason?.description ?? "none")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallBackgroundCallKitReportResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let status: DirectCallBackgroundRealCallKitReportStatus
    let diagnostics: DirectCallBackgroundRealCallKitReportDiagnostics

    var description: String {
        "DirectCallBackgroundCallKitReportResult(status: \(status), diagnostics: \(diagnostics))"
    }

    var debugDescription: String {
        description
    }
}

protocol DirectCallBackgroundCallKitProviderProtocol: AnyObject {
    func reportIncomingCall(_ request: DirectCallBackgroundCallKitProviderReportRequest) -> Bool
}

struct DirectCallBackgroundRealCallKitReportingAdapter: CustomStringConvertible, CustomDebugStringConvertible {
    let provider: DirectCallBackgroundCallKitProviderProtocol

    func report(_ planningResult: DirectCallBackgroundCallKitReportPlanningResult) -> DirectCallBackgroundCallKitReportResult {
        guard planningResult.decision == .reportableIncomingCallRequest else {
            return result(status: planningResult.decision == .notReportableRequiresAuthenticatedSession ? .notReportedMissingAuthenticatedContext : .notReportedNotReportable,
                          attempted: false,
                          providerFailureClass: nil,
                          blockedReason: reportingFailure(for: planningResult))
        }
        guard let request = planningResult.request else {
            return result(status: .reportFailedRedacted,
                          attempted: false,
                          providerFailureClass: .missingReportRequest,
                          blockedReason: .missingReportRequest)
        }

        let providerRequest = DirectCallBackgroundCallKitProviderReportRequest(callUUID: request.callUUID,
                                                                               kind: request.kind,
                                                                               expiresAt: request.expiresAt,
                                                                               displayMetadata: request.displayMetadata)
        let didReport = provider.reportIncomingCall(providerRequest)
        return result(status: didReport ? .reportAttemptRecorded : .reportFailedRedacted,
                      attempted: true,
                      providerFailureClass: didReport ? nil : .providerFailedRedacted,
                      blockedReason: didReport ? nil : .providerFailedRedacted)
    }

    private func reportingFailure(for planningResult: DirectCallBackgroundCallKitReportPlanningResult) -> DirectCallBackgroundRealCallKitReportFailure {
        switch planningResult.decision {
        case .notReportableRequiresAuthenticatedSession:
            .authenticatedSessionUnavailable
        case .notReportableInvalidPayload,
             .notReportableExpiredPayload,
             .notReportableFutureTimestampExcessive:
            .notReportable
        case .reportableIncomingCallRequest:
            planningResult.request == nil ? .missingReportRequest : .redacted
        }
    }

    private func result(status: DirectCallBackgroundRealCallKitReportStatus,
                        attempted: Bool,
                        providerFailureClass: DirectCallBackgroundRealCallKitReportFailure?,
                        blockedReason: DirectCallBackgroundRealCallKitReportFailure?) -> DirectCallBackgroundCallKitReportResult {
        .init(status: status,
              diagnostics: .init(realCallKitAdapterInvoked: true,
                                 callKitProviderReportAttempted: attempted,
                                 callKitProviderReportResult: status,
                                 providerFailureClass: providerFailureClass,
                                 mediaCredentialsRequested: false,
                                 mediaConnectRequested: false,
                                 matrixEventEmitRequested: false,
                                 pushKitRegistrationRequested: false,
                                 apnsRegistrationRequested: false,
                                 blockedReason: blockedReason))
    }

    var description: String {
        "DirectCallBackgroundRealCallKitReportingAdapter(realCallKitRuntime: true, pushKitRuntime: false, apnsRegistrationRuntime: false, mediaRuntime: false, matrixEventRuntime: false, pushKitCallbackRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallPushKitLifecycleEvent: CustomStringConvertible, CustomDebugStringConvertible {
    case registrationRequested
    case tokenUpdated(Data)
    case tokenInvalidated
    case payloadReceived([String: Any])
    case registrationUnavailable

    var description: String {
        switch self {
        case .registrationRequested:
            "registration_requested"
        case .tokenUpdated:
            "token_updated(value: <redacted>)"
        case .tokenInvalidated:
            "token_invalidated"
        case .payloadReceived:
            "payload_received(payload: <redacted>)"
        case .registrationUnavailable:
            "registration_unavailable"
        }
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallPushKitLifecycleDecision: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case registrationDeferred = "registration_deferred"
    case registrationUnavailable = "registration_unavailable"
    case tokenUpdateReceived = "token_update_received"
    case tokenInvalidated = "token_invalidated"
    case ignoreInvalidPayload = "ignore_invalid_payload"
    case ignoreExpiredPayload = "ignore_expired_payload"
    case ignoreFutureTimestampExcessive = "ignore_future_timestamp_excessive"
    case requiresAuthenticatedSession = "requires_authenticated_session"
    case callKitReportAttemptRecorded = "callkit_report_attempt_recorded"
    case callKitReportFailedRedacted = "callkit_report_failed_redacted"
    case callKitReporterUnavailable = "callkit_reporter_unavailable"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallPushKitLifecycleFailure: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case registrationUnavailable = "registration_unavailable"
    case tokenNotPersisted = "token_not_persisted"
    case invalidPayload = "invalid_payload"
    case expiredPayload = "expired"
    case futureTimestampExcessive = "future_timestamp_excessive"
    case authenticatedSessionUnavailable = "authenticated_session_unavailable"
    case callKitReporterUnavailable = "callkit_reporter_unavailable"
    case callKitReportFailedRedacted = "callkit_report_failed_redacted"
    case redacted

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallPushKitLifecycleDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let pushKitLifecycleInvoked: Bool
    let pushKitRegistrationRequested: Bool
    let apnsRegistrationRequested: Bool
    let tokenUpdateReceived: Bool
    let tokenInvalidated: Bool
    let payloadReceived: Bool
    let payloadParseStatus: String
    let intakeDecision: DirectCallBackgroundInviteIntakeDecision?
    let callKitReportDecision: DirectCallBackgroundCallKitReportDecision?
    let callKitReportAttempted: Bool
    let mediaCredentialsRequested: Bool
    let mediaConnectRequested: Bool
    let matrixEventEmitRequested: Bool
    let blockedReason: DirectCallPushKitLifecycleFailure?

    var description: String {
        "DirectCallPushKitLifecycleDiagnostics(" + [
            "pushkit_lifecycle_invoked=\(pushKitLifecycleInvoked)",
            "pushkit_registration_requested=\(pushKitRegistrationRequested)",
            "apns_registration_requested=\(apnsRegistrationRequested)",
            "token_update_received=\(tokenUpdateReceived)",
            "token_invalidated=\(tokenInvalidated)",
            "payload_received=\(payloadReceived)",
            "payload_parse_status=\(payloadParseStatus)",
            "intake_decision=\(intakeDecision?.description ?? "none")",
            "callkit_report_decision=\(callKitReportDecision?.description ?? "none")",
            "callkit_report_attempted=\(callKitReportAttempted)",
            "media_credentials_requested=\(mediaCredentialsRequested)",
            "media_connect_requested=\(mediaConnectRequested)",
            "matrix_event_emit_requested=\(matrixEventEmitRequested)",
            "blocked_reason=\(blockedReason?.description ?? "none")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallPushKitLifecycleResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let decision: DirectCallPushKitLifecycleDecision
    let diagnostics: DirectCallPushKitLifecycleDiagnostics

    var description: String {
        "DirectCallPushKitLifecycleResult(decision: \(decision), diagnostics: \(diagnostics))"
    }

    var debugDescription: String {
        description
    }
}

protocol DirectCallPushKitLifecycleManaging {
    func handle(_ event: DirectCallPushKitLifecycleEvent,
                now: Date,
                authenticatedSessionAvailable: Bool) -> DirectCallPushKitLifecycleResult
}

struct DirectCallFakePushKitLifecycleManager: DirectCallPushKitLifecycleManaging, CustomStringConvertible, CustomDebugStringConvertible {
    var parser = DirectCallBackgroundInvitePayloadParser()
    var intake = DirectCallBackgroundInviteIntake()
    var planner = DirectCallBackgroundCallKitReportPlanner()
    var reportCallKit: ((DirectCallBackgroundCallKitReportPlanningResult) -> DirectCallBackgroundCallKitReportResult)?

    func handle(_ event: DirectCallPushKitLifecycleEvent,
                now: Date = .now,
                authenticatedSessionAvailable: Bool = false) -> DirectCallPushKitLifecycleResult {
        switch event {
        case .registrationRequested:
            return result(decision: .registrationDeferred,
                          blockedReason: .registrationUnavailable)
        case .registrationUnavailable:
            return result(decision: .registrationUnavailable,
                          blockedReason: .registrationUnavailable)
        case .tokenUpdated:
            return result(decision: .tokenUpdateReceived,
                          tokenUpdateReceived: true,
                          blockedReason: .tokenNotPersisted)
        case .tokenInvalidated:
            return result(decision: .tokenInvalidated,
                          tokenInvalidated: true)
        case .payloadReceived(let payload):
            return handlePayload(payload,
                                 now: now,
                                 authenticatedSessionAvailable: authenticatedSessionAvailable)
        }
    }

    private func handlePayload(_ payload: [String: Any],
                               now: Date,
                               authenticatedSessionAvailable: Bool) -> DirectCallPushKitLifecycleResult {
        let parsed = parser.parse(payload, now: now)
        let intakeResult = intake.evaluate(parsed,
                                           authenticatedSessionAvailable: authenticatedSessionAvailable,
                                           callKitReportAdapterAvailable: true)
        let planningResult = planner.plan(from: intakeResult)

        guard planningResult.decision == .reportableIncomingCallRequest else {
            return result(decision: lifecycleDecision(for: planningResult),
                          payloadReceived: true,
                          payloadParseStatus: parsed.description,
                          intakeDecision: intakeResult.decision,
                          callKitReportDecision: planningResult.decision,
                          blockedReason: lifecycleFailure(for: planningResult))
        }
        guard let reportCallKit else {
            return result(decision: .callKitReporterUnavailable,
                          payloadReceived: true,
                          payloadParseStatus: parsed.description,
                          intakeDecision: intakeResult.decision,
                          callKitReportDecision: planningResult.decision,
                          blockedReason: .callKitReporterUnavailable)
        }

        let reportResult = reportCallKit(planningResult)
        return result(decision: reportResult.status == .reportAttemptRecorded ? .callKitReportAttemptRecorded : .callKitReportFailedRedacted,
                      payloadReceived: true,
                      payloadParseStatus: parsed.description,
                      intakeDecision: intakeResult.decision,
                      callKitReportDecision: planningResult.decision,
                      callKitReportAttempted: reportResult.diagnostics.callKitProviderReportAttempted,
                      blockedReason: reportResult.status == .reportAttemptRecorded ? nil : .callKitReportFailedRedacted)
    }

    private func lifecycleDecision(for planningResult: DirectCallBackgroundCallKitReportPlanningResult) -> DirectCallPushKitLifecycleDecision {
        switch planningResult.decision {
        case .notReportableExpiredPayload:
            .ignoreExpiredPayload
        case .notReportableFutureTimestampExcessive:
            .ignoreFutureTimestampExcessive
        case .notReportableRequiresAuthenticatedSession:
            .requiresAuthenticatedSession
        case .notReportableInvalidPayload:
            .ignoreInvalidPayload
        case .reportableIncomingCallRequest:
            .callKitReporterUnavailable
        }
    }

    private func lifecycleFailure(for planningResult: DirectCallBackgroundCallKitReportPlanningResult) -> DirectCallPushKitLifecycleFailure {
        switch planningResult.decision {
        case .notReportableExpiredPayload:
            .expiredPayload
        case .notReportableFutureTimestampExcessive:
            .futureTimestampExcessive
        case .notReportableRequiresAuthenticatedSession:
            .authenticatedSessionUnavailable
        case .notReportableInvalidPayload:
            .invalidPayload
        case .reportableIncomingCallRequest:
            .callKitReporterUnavailable
        }
    }

    private func result(decision: DirectCallPushKitLifecycleDecision,
                        tokenUpdateReceived: Bool = false,
                        tokenInvalidated: Bool = false,
                        payloadReceived: Bool = false,
                        payloadParseStatus: String = "none",
                        intakeDecision: DirectCallBackgroundInviteIntakeDecision? = nil,
                        callKitReportDecision: DirectCallBackgroundCallKitReportDecision? = nil,
                        callKitReportAttempted: Bool = false,
                        blockedReason: DirectCallPushKitLifecycleFailure? = nil) -> DirectCallPushKitLifecycleResult {
        .init(decision: decision,
              diagnostics: .init(pushKitLifecycleInvoked: true,
                                 pushKitRegistrationRequested: false,
                                 apnsRegistrationRequested: false,
                                 tokenUpdateReceived: tokenUpdateReceived,
                                 tokenInvalidated: tokenInvalidated,
                                 payloadReceived: payloadReceived,
                                 payloadParseStatus: payloadParseStatus,
                                 intakeDecision: intakeDecision,
                                 callKitReportDecision: callKitReportDecision,
                                 callKitReportAttempted: callKitReportAttempted,
                                 mediaCredentialsRequested: false,
                                 mediaConnectRequested: false,
                                 matrixEventEmitRequested: false,
                                 blockedReason: blockedReason))
    }

    var description: String {
        "DirectCallFakePushKitLifecycleManager(pushKitRuntime: false, apnsRegistrationRuntime: false, realCallKitRuntime: false, mediaRuntime: false, matrixEventRuntime: false, tokenPersistenceRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallPushKitRegistrarFeatureGate: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let isEnabled: Bool

    static let disabled = Self(isEnabled: false)

    var description: String {
        "DirectCallPushKitRegistrarFeatureGate(enabled: \(isEnabled))"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallPushKitRegistrarStatus: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case disabled
    case registryCreated = "registry_created"
    case registryUnavailable = "registry_unavailable"
    case tokenUpdateReceived = "token_update_received"
    case tokenInvalidated = "token_invalidated"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallPushKitRegistrarFailure: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case featureGateDisabled = "feature_gate_disabled"
    case registryUnavailable = "registry_unavailable"
    case tokenNotPersisted = "token_not_persisted"
    case tokenNotUploaded = "token_not_uploaded"
    case redacted

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallPushKitRegistrarDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let pushKitRegistrarInvoked: Bool
    let pushKitFeatureGateEnabled: Bool
    let pushKitRegistryCreateRequested: Bool
    let pushKitTokenUpdateReceived: Bool
    let pushKitTokenInvalidated: Bool
    let pushKitTokenPersistenceRequested: Bool
    let pushKitTokenUploadRequested: Bool
    let pushKitRegistrationResult: DirectCallPushKitRegistrarStatus
    let blockedReason: DirectCallPushKitRegistrarFailure?

    var description: String {
        "DirectCallPushKitRegistrarDiagnostics(" + [
            "pushkit_registrar_invoked=\(pushKitRegistrarInvoked)",
            "pushkit_feature_gate_enabled=\(pushKitFeatureGateEnabled)",
            "pushkit_registry_create_requested=\(pushKitRegistryCreateRequested)",
            "pushkit_token_update_received=\(pushKitTokenUpdateReceived)",
            "pushkit_token_invalidated=\(pushKitTokenInvalidated)",
            "pushkit_token_persistence_requested=\(pushKitTokenPersistenceRequested)",
            "pushkit_token_upload_requested=\(pushKitTokenUploadRequested)",
            "pushkit_registration_result=\(pushKitRegistrationResult)",
            "blocked_reason=\(blockedReason?.description ?? "none")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallPushKitRegistrarResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let status: DirectCallPushKitRegistrarStatus
    let diagnostics: DirectCallPushKitRegistrarDiagnostics

    var description: String {
        "DirectCallPushKitRegistrarResult(status: \(status), diagnostics: \(diagnostics))"
    }

    var debugDescription: String {
        description
    }
}

protocol DirectCallPushKitRegistrarRegistryDelegate: AnyObject {
    func pushKitRegistrarDidUpdateToken(_ token: Data)
    func pushKitRegistrarDidInvalidateToken()
}

protocol DirectCallPushKitRegistryControlling: AnyObject {
    func requestVoIPPushRegistration()
}

protocol DirectCallPushKitRegistryMaking {
    func makeRegistry(delegate: DirectCallPushKitRegistrarRegistryDelegate) -> DirectCallPushKitRegistryControlling?
}

struct DirectCallPushKitRegistrarConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    var featureGate: DirectCallPushKitRegistrarFeatureGate = .disabled
    var registryFactory: DirectCallPushKitRegistryMaking?
    var resultHandler: ((DirectCallPushKitRegistrarResult) -> Void)?

    var description: String {
        "DirectCallPushKitRegistrarConfiguration(featureGate: \(featureGate), registryFactoryConfigured: \(registryFactory != nil), resultHandlerConfigured: \(resultHandler != nil), defaultEnabled: false)"
    }

    var debugDescription: String {
        description
    }
}

final class DirectCallPushKitRegistrar: DirectCallPushKitRegistrarRegistryDelegate, CustomStringConvertible, CustomDebugStringConvertible {
    private let configuration: DirectCallPushKitRegistrarConfiguration
    private var registry: DirectCallPushKitRegistryControlling?

    init(configuration: DirectCallPushKitRegistrarConfiguration = .init()) {
        self.configuration = configuration
    }

    func startRegistration() -> DirectCallPushKitRegistrarResult {
        guard configuration.featureGate.isEnabled else {
            return result(status: .disabled,
                          registryCreateRequested: false,
                          blockedReason: .featureGateDisabled)
        }
        guard let registryFactory = configuration.registryFactory,
              let registry = registryFactory.makeRegistry(delegate: self) else {
            return result(status: .registryUnavailable,
                          registryCreateRequested: true,
                          blockedReason: .registryUnavailable)
        }

        self.registry = registry
        registry.requestVoIPPushRegistration()
        return result(status: .registryCreated,
                      registryCreateRequested: true,
                      blockedReason: nil)
    }

    func pushKitRegistrarDidUpdateToken(_ token: Data) {
        _ = handleTokenUpdate(token)
    }

    func pushKitRegistrarDidInvalidateToken() {
        _ = handleTokenInvalidation()
    }

    func handleTokenUpdate(_ token: Data) -> DirectCallPushKitRegistrarResult {
        let result = result(status: .tokenUpdateReceived,
                            registryCreateRequested: false,
                            tokenUpdateReceived: true,
                            blockedReason: .tokenNotPersisted)
        configuration.resultHandler?(result)
        return result
    }

    func handleTokenInvalidation() -> DirectCallPushKitRegistrarResult {
        let result = result(status: .tokenInvalidated,
                            registryCreateRequested: false,
                            tokenInvalidated: true,
                            blockedReason: nil)
        configuration.resultHandler?(result)
        return result
    }

    private func result(status: DirectCallPushKitRegistrarStatus,
                        registryCreateRequested: Bool,
                        tokenUpdateReceived: Bool = false,
                        tokenInvalidated: Bool = false,
                        blockedReason: DirectCallPushKitRegistrarFailure?) -> DirectCallPushKitRegistrarResult {
        .init(status: status,
              diagnostics: .init(pushKitRegistrarInvoked: true,
                                 pushKitFeatureGateEnabled: configuration.featureGate.isEnabled,
                                 pushKitRegistryCreateRequested: registryCreateRequested,
                                 pushKitTokenUpdateReceived: tokenUpdateReceived,
                                 pushKitTokenInvalidated: tokenInvalidated,
                                 pushKitTokenPersistenceRequested: false,
                                 pushKitTokenUploadRequested: false,
                                 pushKitRegistrationResult: status,
                                 blockedReason: blockedReason))
    }

    var description: String {
        "DirectCallPushKitRegistrar(" + [
            "featureGateEnabled: \(configuration.featureGate.isEnabled)",
            "registryCreated: \(registry != nil)",
            "startupWiring: false",
            "apnsRegistrationRuntime: false",
            "mediaRuntime: false",
            "matrixEventRuntime: false",
            "tokenPersistenceRuntime: false",
            "tokenUploadRuntime: false"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallPushKitTokenRegistrationRequest: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let tokenPresent: Bool
    let environmentClass: String

    var description: String {
        "DirectCallPushKitTokenRegistrationRequest(token: <redacted>, tokenPresent: \(tokenPresent), environmentClass: \(environmentClass), payload: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallPushKitTokenRegistrationTransportResult: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case success
    case failure = "failure_redacted"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

protocol DirectCallPushKitTokenRegistrationTransporting {
    func register(_ request: DirectCallPushKitTokenRegistrationRequest) -> DirectCallPushKitTokenRegistrationTransportResult
}

enum DirectCallPushKitTokenRegistrationUploadResult: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case notRequested = "not_requested"
    case fakeUploadSucceeded = "fake_upload_succeeded"
    case failedRedacted = "failed_redacted"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallPushKitTokenRegistrationFailure: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case missingToken = "missing_token"
    case transportUnavailable = "transport_unavailable"
    case transportFailedRedacted = "transport_failed_redacted"
    case redacted

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallPushKitTokenRegistrationDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let pushKitTokenRegistrationInvoked: Bool
    let pushKitTokenPresent: Bool
    let pushKitTokenUploadRequested: Bool
    let pushKitTokenPersistenceRequested: Bool
    let pushKitTokenUploadResult: DirectCallPushKitTokenRegistrationUploadResult
    let pushKitTokenRegistrationFailure: DirectCallPushKitTokenRegistrationFailure?
    let apnsRegistrationRequested: Bool
    let mediaCredentialsRequested: Bool
    let mediaConnectRequested: Bool
    let matrixEventEmitRequested: Bool
    let blockedReason: DirectCallPushKitTokenRegistrationFailure?

    var description: String {
        "DirectCallPushKitTokenRegistrationDiagnostics(" + [
            "pushkit_token_registration_invoked=\(pushKitTokenRegistrationInvoked)",
            "pushkit_token_present=\(pushKitTokenPresent)",
            "pushkit_token_upload_requested=\(pushKitTokenUploadRequested)",
            "pushkit_token_persistence_requested=\(pushKitTokenPersistenceRequested)",
            "pushkit_token_upload_result=\(pushKitTokenUploadResult)",
            "pushkit_token_registration_failure=\(pushKitTokenRegistrationFailure?.description ?? "none")",
            "apns_registration_requested=\(apnsRegistrationRequested)",
            "media_credentials_requested=\(mediaCredentialsRequested)",
            "media_connect_requested=\(mediaConnectRequested)",
            "matrix_event_emit_requested=\(matrixEventEmitRequested)",
            "blocked_reason=\(blockedReason?.description ?? "none")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallPushKitTokenRegistrationResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let uploadResult: DirectCallPushKitTokenRegistrationUploadResult
    let diagnostics: DirectCallPushKitTokenRegistrationDiagnostics

    var description: String {
        "DirectCallPushKitTokenRegistrationResult(uploadResult: \(uploadResult), diagnostics: \(diagnostics))"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallPushKitTokenRegistrationClient: CustomStringConvertible, CustomDebugStringConvertible {
    var transport: DirectCallPushKitTokenRegistrationTransporting?
    var environmentClass = "development"

    func register(token: Data?) -> DirectCallPushKitTokenRegistrationResult {
        guard let token, !token.isEmpty else {
            return result(tokenPresent: false,
                          uploadRequested: false,
                          uploadResult: .notRequested,
                          failure: .missingToken)
        }
        guard let transport else {
            return result(tokenPresent: true,
                          uploadRequested: false,
                          uploadResult: .notRequested,
                          failure: .transportUnavailable)
        }

        let request = DirectCallPushKitTokenRegistrationRequest(tokenPresent: true,
                                                                environmentClass: environmentClass)
        switch transport.register(request) {
        case .success:
            return result(tokenPresent: true,
                          uploadRequested: true,
                          uploadResult: .fakeUploadSucceeded,
                          failure: nil)
        case .failure:
            return result(tokenPresent: true,
                          uploadRequested: true,
                          uploadResult: .failedRedacted,
                          failure: .transportFailedRedacted)
        }
    }

    private func result(tokenPresent: Bool,
                        uploadRequested: Bool,
                        uploadResult: DirectCallPushKitTokenRegistrationUploadResult,
                        failure: DirectCallPushKitTokenRegistrationFailure?) -> DirectCallPushKitTokenRegistrationResult {
        .init(uploadResult: uploadResult,
              diagnostics: .init(pushKitTokenRegistrationInvoked: true,
                                 pushKitTokenPresent: tokenPresent,
                                 pushKitTokenUploadRequested: uploadRequested,
                                 pushKitTokenPersistenceRequested: false,
                                 pushKitTokenUploadResult: uploadResult,
                                 pushKitTokenRegistrationFailure: failure,
                                 apnsRegistrationRequested: false,
                                 mediaCredentialsRequested: false,
                                 mediaConnectRequested: false,
                                 matrixEventEmitRequested: false,
                                 blockedReason: failure))
    }

    var description: String {
        "DirectCallPushKitTokenRegistrationClient(realNetworkRuntime: false, tokenPersistenceRuntime: false, apnsRegistrationRuntime: false, mediaRuntime: false, matrixEventRuntime: false, startupWiring: false, pushKitCallbackWiring: false)"
    }

    var debugDescription: String {
        description
    }
}

protocol NativeIncomingCallTimeoutScheduling: AnyObject {
    func scheduleTimeout(for identity: NativeIncomingCallIdentity, after timeout: Duration)
    func cancelTimeout(for identity: NativeIncomingCallIdentity)
}

protocol NativeIncomingCallDiagnosticsRecording: AnyObject {
    func record(_ diagnostics: NativeIncomingCallRedactedDiagnostics)
}

protocol NativeIncomingForegroundAcceptanceAuthorizing: AnyObject {
    func foregroundAcceptanceDecision(for identity: NativeIncomingCallIdentity) -> NativeIncomingForegroundAcceptanceDecision
}

protocol NativeForegroundIncomingMediaConnecting: AnyObject {
    func connectForegroundIncomingMedia(identity: NativeIncomingCallIdentity) async -> NativeForegroundIncomingMediaConnectionOutcome
    func endForegroundIncomingMedia(identity: NativeIncomingCallIdentity) async
}

final class DisabledNativeIncomingCallLifecycleService: CustomStringConvertible, CustomDebugStringConvertible {
    private let isEnabled: Bool
    private let stateStore: NativeIncomingCallStateStoring
    private let reportingAdapter: NativeIncomingCallReportingAdapting
    private let timeoutScheduler: NativeIncomingCallTimeoutScheduling
    private let diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording
    private let staleInterval: TimeInterval
    private let reportTimeout: Duration

    init(isEnabled: Bool = false,
         stateStore: NativeIncomingCallStateStoring,
         reportingAdapter: NativeIncomingCallReportingAdapting,
         timeoutScheduler: NativeIncomingCallTimeoutScheduling,
         diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording,
         staleInterval: TimeInterval = 45,
         reportTimeout: Duration = .seconds(45)) {
        self.isEnabled = isEnabled
        self.stateStore = stateStore
        self.reportingAdapter = reportingAdapter
        self.timeoutScheduler = timeoutScheduler
        self.diagnosticsRecorder = diagnosticsRecorder
        self.staleInterval = staleInterval
        self.reportTimeout = reportTimeout
    }

    func receiveIncomingCall(handle rawHandle: String,
                             receivedAt: Date,
                             now: Date = .now,
                             context: NativeIncomingCallValidationContext = .valid) -> NativeIncomingCallLifecycleOutcome {
        guard isEnabled else {
            return failClosed(.dependencyUnavailable)
        }
        guard let handle = NativeIncomingCallHandle(rawHandle) else {
            return failClosed(.malformed)
        }
        guard now.timeIntervalSince(receivedAt) <= staleInterval else {
            return failClosed(.stale)
        }
        guard !stateStore.hasSeen(handle) else {
            return failClosed(.duplicate)
        }
        if let failClosedReason = context.failClosedReason {
            return failClosed(failClosedReason)
        }

        let identity = NativeIncomingCallIdentity(handle: handle, receivedAt: receivedAt)
        stateStore.setState(.received, for: handle)
        stateStore.setState(.validating, for: handle)
        stateStore.setState(.reportable, for: handle)

        let reportSucceeded = reportingAdapter.reportIncomingCall(identity: identity)
        diagnosticsRecorder.record(.init(lifecycleState: reportSucceeded ? .reported : .blocked,
                                         failClosedReason: reportSucceeded ? nil : .callReportingUnavailable,
                                         reportAttempted: true,
                                         reportSucceeded: reportSucceeded,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))

        guard reportSucceeded else {
            stateStore.setState(.blocked, for: handle)
            return .failClosed(.callReportingUnavailable)
        }

        stateStore.setState(.reported, for: handle)
        timeoutScheduler.scheduleTimeout(for: identity, after: reportTimeout)
        return .reported(identity)
    }

    func failAfterMediaCredentialRejection(identity: NativeIncomingCallIdentity) -> NativeIncomingCallLifecycleOutcome {
        stateStore.setState(.failed, for: identity.handle)
        timeoutScheduler.cancelTimeout(for: identity)
        reportingAdapter.endReportedCall(identity: identity, reason: .serverIssuedMediaCredentialRejected)
        diagnosticsRecorder.record(.init(lifecycleState: .failed,
                                         failClosedReason: .serverIssuedMediaCredentialRejected,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: true,
                                         mediaConnectAttempted: false))
        return .failClosed(.serverIssuedMediaCredentialRejected)
    }

    private func failClosed(_ reason: NativeIncomingCallFailClosedReason) -> NativeIncomingCallLifecycleOutcome {
        diagnosticsRecorder.record(.failClosed(reason))
        return .failClosed(reason)
    }

    var description: String {
        "DisabledNativeIncomingCallLifecycleService(isEnabled: \(isEnabled), realRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

struct NativeIncomingCallKitDisplayMetadata: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let label: String

    init?(_ label: String) {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty,
              trimmedLabel.count <= 80,
              !trimmedLabel.contains("@"),
              !trimmedLabel.contains("!"),
              !trimmedLabel.contains("$"),
              !trimmedLabel.contains(":"),
              !trimmedLabel.contains("/"),
              !trimmedLabel.contains("\\") else {
            return nil
        }
        self.label = trimmedLabel
    }

    var description: String {
        "NativeIncomingCallKitDisplayMetadata(label: <redacted>, isPresent: \(!label.isEmpty))"
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallInviteKind: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case audio
    case video
    case unsupported

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallInviteSignalState: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case incoming
    case terminal

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct ForegroundCallInviteSignal: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let handle: NativeIncomingCallHandle
    let kind: ForegroundCallInviteKind
    let state: ForegroundCallInviteSignalState
    let createdAt: Date
    let expiresAt: Date
    let displayMetadata: NativeIncomingCallKitDisplayMetadata

    var description: String {
        "ForegroundCallInviteSignal(handle: <redacted>, kind: \(kind), state: \(state), createdAt: <redacted>, expiresAt: <redacted>, displayMetadata: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallInviteValidationResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case valid(ForegroundCallInviteSignal)
    case failClosed(NativeIncomingCallFailClosedReason)

    var description: String {
        switch self {
        case .valid:
            "valid(signal: <redacted>)"
        case .failClosed(let reason):
            "failClosed(\(reason))"
        }
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallInviteHandlingOutcome: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case reported(NativeIncomingCallIdentity)
    case suppressed(NativeIncomingCallFailClosedReason)

    var description: String {
        switch self {
        case .reported:
            "reported(identity: <redacted>)"
        case .suppressed(let reason):
            "suppressed(\(reason))"
        }
    }

    var debugDescription: String {
        description
    }
}

protocol ForegroundCallSignalingClientProtocol: AnyObject {
    func startForegroundCallSignaling(onSignal: @escaping (ForegroundCallInviteSignal) -> Void)
    func stopForegroundCallSignaling()
}

final class DisabledForegroundCallSignalingClient: ForegroundCallSignalingClientProtocol, CustomStringConvertible, CustomDebugStringConvertible {
    private(set) var isStarted = false

    func startForegroundCallSignaling(onSignal: @escaping (ForegroundCallInviteSignal) -> Void) {
        isStarted = true
    }

    func stopForegroundCallSignaling() {
        isStarted = false
    }

    var description: String {
        "DisabledForegroundCallSignalingClient(isStarted: \(isStarted), realTransport: false, backgroundRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallSignalingTransportEventKind: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case ready
    case stopped
    case invite

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallSignalingTransportResult: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case started
    case connected
    case stopped
    case delivered
    case ignored

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallSignalingTransportEvent: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case ready
    case stopped
    case invite(ForegroundCallInviteSignal)

    var kind: ForegroundCallSignalingTransportEventKind {
        switch self {
        case .ready:
            .ready
        case .stopped:
            .stopped
        case .invite:
            .invite
        }
    }

    var description: String {
        switch self {
        case .ready:
            "ready"
        case .stopped:
            "stopped"
        case .invite:
            "invite(signal: <redacted>)"
        }
    }

    var debugDescription: String {
        description
    }
}

struct ForegroundCallSignalingTransportDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    var isStarted: Bool
    var deliveredInviteCount: Int
    var latestEventKind: ForegroundCallSignalingTransportEventKind?
    var latestResult: ForegroundCallSignalingTransportResult
    var realTransport: Bool
    var latestFailureReason: ForegroundCallSignalingSSEStreamFailureReason?

    static let disabled = Self(isStarted: false,
                               deliveredInviteCount: 0,
                               latestEventKind: nil,
                               latestResult: .ignored,
                               realTransport: false,
                               latestFailureReason: nil)

    var description: String {
        "ForegroundCallSignalingTransportDiagnostics(" + [
            "isStarted: \(isStarted)",
            "deliveredInviteCount: \(deliveredInviteCount)",
            "latestEventKind: \(latestEventKind?.description ?? "none")",
            "latestResult: \(latestResult)",
            "realTransport: \(realTransport)",
            "latestFailureReason: \(latestFailureReason?.description ?? "none")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

protocol ForegroundCallSignalingTransport: AnyObject {
    var diagnostics: ForegroundCallSignalingTransportDiagnostics { get }
    func start(onEvent: @escaping (ForegroundCallSignalingTransportEvent) -> Void)
    func stop()
}

final class DisabledForegroundCallSignalingTransport: ForegroundCallSignalingTransport, CustomStringConvertible, CustomDebugStringConvertible {
    private(set) var diagnostics = ForegroundCallSignalingTransportDiagnostics.disabled

    func start(onEvent: @escaping (ForegroundCallSignalingTransportEvent) -> Void) {
        diagnostics = .init(isStarted: false,
                            deliveredInviteCount: 0,
                            latestEventKind: nil,
                            latestResult: .ignored,
                            realTransport: false,
                            latestFailureReason: nil)
    }

    func stop() {
        diagnostics = .init(isStarted: false,
                            deliveredInviteCount: diagnostics.deliveredInviteCount,
                            latestEventKind: diagnostics.latestEventKind,
                            latestResult: .stopped,
                            realTransport: false,
                            latestFailureReason: diagnostics.latestFailureReason)
    }

    var description: String {
        "DisabledForegroundCallSignalingTransport(\(diagnostics))"
    }

    var debugDescription: String {
        description
    }
}

final class InMemoryForegroundCallSignalingTransport: ForegroundCallSignalingTransport, CustomStringConvertible, CustomDebugStringConvertible {
    private(set) var diagnostics = ForegroundCallSignalingTransportDiagnostics.disabled
    private var onEvent: ((ForegroundCallSignalingTransportEvent) -> Void)?

    func start(onEvent: @escaping (ForegroundCallSignalingTransportEvent) -> Void) {
        self.onEvent = onEvent
        diagnostics = .init(isStarted: true,
                            deliveredInviteCount: diagnostics.deliveredInviteCount,
                            latestEventKind: diagnostics.latestEventKind,
                            latestResult: .started,
                            realTransport: false,
                            latestFailureReason: nil)
    }

    func stop() {
        onEvent = nil
        diagnostics = .init(isStarted: false,
                            deliveredInviteCount: diagnostics.deliveredInviteCount,
                            latestEventKind: diagnostics.latestEventKind,
                            latestResult: .stopped,
                            realTransport: false,
                            latestFailureReason: diagnostics.latestFailureReason)
    }

    @discardableResult
    func emit(_ event: ForegroundCallSignalingTransportEvent) -> Bool {
        guard let onEvent else {
            diagnostics = .init(isStarted: false,
                                deliveredInviteCount: diagnostics.deliveredInviteCount,
                                latestEventKind: event.kind,
                                latestResult: .ignored,
                                realTransport: false,
                                latestFailureReason: diagnostics.latestFailureReason)
            return false
        }

        onEvent(event)
        diagnostics = .init(isStarted: true,
                            deliveredInviteCount: diagnostics.deliveredInviteCount + 1,
                            latestEventKind: event.kind,
                            latestResult: .delivered,
                            realTransport: false,
                            latestFailureReason: nil)
        return true
    }

    @discardableResult
    func emitInvite(_ signal: ForegroundCallInviteSignal) -> Bool {
        emit(.invite(signal))
    }

    var description: String {
        "InMemoryForegroundCallSignalingTransport(\(diagnostics))"
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallSignalingSSEHTTPStatusClass: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case unauthorized
    case forbidden
    case clientError
    case serverError
    case unexpected

    init(statusCode: Int) {
        switch statusCode {
        case 401:
            self = .unauthorized
        case 403:
            self = .forbidden
        case 400..<500:
            self = .clientError
        case 500..<600:
            self = .serverError
        default:
            self = .unexpected
        }
    }

    var description: String {
        switch self {
        case .unauthorized:
            "unauthorized"
        case .forbidden:
            "forbidden"
        case .clientError:
            "client_error"
        case .serverError:
            "server_error"
        case .unexpected:
            "unexpected"
        }
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallSignalingSSEStreamFailureReason: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case httpStatus(ForegroundCallSignalingSSEHTTPStatusClass)
    case nonHTTPResponse
    case unsupportedContentType
    case network

    var description: String {
        switch self {
        case .httpStatus(let statusClass):
            "http_\(statusClass)"
        case .nonHTTPResponse:
            "non_http_response"
        case .unsupportedContentType:
            "unsupported_content_type"
        case .network:
            "network"
        }
    }

    var debugDescription: String {
        description
    }
}

enum ForegroundCallSignalingSSEStreamCompletion: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case ended
    case failed(ForegroundCallSignalingSSEStreamFailureReason)

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }

    private var rawValue: String {
        switch self {
        case .ended:
            "ended"
        case .failed(let reason):
            "failed(\(reason))"
        }
    }

    var failureReason: ForegroundCallSignalingSSEStreamFailureReason? {
        switch self {
        case .ended:
            nil
        case .failed(let reason):
            reason
        }
    }
}

protocol ForegroundCallSignalingSSEStreaming: AnyObject {
    func start(onChunk: @escaping (Data) -> Void,
               onCompletion: @escaping (ForegroundCallSignalingSSEStreamCompletion) -> Void)
    func stop()
}

final class DisabledForegroundCallSignalingSSEStream: ForegroundCallSignalingSSEStreaming, CustomStringConvertible, CustomDebugStringConvertible {
    private(set) var isStarted = false

    func start(onChunk: @escaping (Data) -> Void,
               onCompletion: @escaping (ForegroundCallSignalingSSEStreamCompletion) -> Void) {
        isStarted = false
    }

    func stop() {
        isStarted = false
    }

    var description: String {
        "DisabledForegroundCallSignalingSSEStream(isStarted: \(isStarted), realTransport: false)"
    }

    var debugDescription: String {
        description
    }
}

final class URLSessionForegroundCallSignalingSSEStream: ForegroundCallSignalingSSEStreaming, CustomStringConvertible, CustomDebugStringConvertible {
    private let request: URLRequest
    private let session: URLSession
    private var task: Task<Void, Never>?

    init(request: URLRequest, session: URLSession = .shared) {
        self.request = request
        self.session = session
    }

    func start(onChunk: @escaping (Data) -> Void,
               onCompletion: @escaping (ForegroundCallSignalingSSEStreamCompletion) -> Void) {
        stop()
        task = Task {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let response = response as? HTTPURLResponse else {
                    onCompletion(.failed(.nonHTTPResponse))
                    return
                }

                guard (200..<300).contains(response.statusCode) else {
                    onCompletion(.failed(.httpStatus(.init(statusCode: response.statusCode))))
                    return
                }

                guard response.safeSSEContentTypeIsSupported else {
                    onCompletion(.failed(.unsupportedContentType))
                    return
                }

                var currentLine = Data()
                for try await byte in bytes {
                    guard !Task.isCancelled else {
                        return
                    }
                    currentLine.append(byte)
                    if byte == UInt8(ascii: "\n") {
                        onChunk(currentLine)
                        currentLine.removeAll(keepingCapacity: true)
                    }
                }

                if !currentLine.isEmpty {
                    onChunk(currentLine)
                }

                onCompletion(.ended)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                onCompletion(.failed(.network))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    var description: String {
        "URLSessionForegroundCallSignalingSSEStream(realTransport: true, request: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

private extension HTTPURLResponse {
    var safeSSEContentTypeIsSupported: Bool {
        value(forHTTPHeaderField: "Content-Type")?
            .lowercased()
            .hasPrefix("text/event-stream") == true
    }
}

struct ForegroundCallSignalingSSEParser: CustomStringConvertible, CustomDebugStringConvertible {
    private var bufferedLine = ""
    private var currentEventType: String?
    private var currentDataLines = [String]()
    private let validator: ForegroundCallInviteValidator
    private let now: () -> Date

    init(validator: ForegroundCallInviteValidator = .init(), now: @escaping () -> Date = Date.init) {
        self.validator = validator
        self.now = now
    }

    mutating func consume(_ data: Data) -> [ForegroundCallSignalingTransportEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        bufferedLine += text
        var events = [ForegroundCallSignalingTransportEvent]()
        while let newlineIndex = bufferedLine.firstIndex(of: "\n") {
            let line = String(bufferedLine[..<newlineIndex]).trimmingCharacters(in: .newlines)
            bufferedLine.removeSubrange(...newlineIndex)

            if let event = consumeLine(line) {
                events.append(event)
            }
        }
        return events
    }

    mutating func finish() -> [ForegroundCallSignalingTransportEvent] {
        guard !bufferedLine.isEmpty else {
            return flushCurrentEvent()
        }

        let line = bufferedLine
        bufferedLine = ""
        if let event = consumeLine(line) {
            return [event]
        }
        return flushCurrentEvent()
    }

    private mutating func consumeLine(_ line: String) -> ForegroundCallSignalingTransportEvent? {
        let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedLine.isEmpty {
            return flushCurrentEvent().first
        }
        if normalizedLine.hasPrefix(":") {
            return nil
        }
        if normalizedLine.hasPrefix("event:") {
            currentEventType = normalizedLine.dropPrefix("event:").trimmedSSEField
            return nil
        }
        if normalizedLine.hasPrefix("data:") {
            currentDataLines.append(normalizedLine.dropPrefix("data:").trimmedSSEField)
            return nil
        }
        return nil
    }

    private mutating func flushCurrentEvent() -> [ForegroundCallSignalingTransportEvent] {
        defer {
            currentEventType = nil
            currentDataLines = []
        }

        if currentEventType == "foreground.ready" {
            return [.ready]
        }

        guard currentEventType == "foreground.call.invite",
              !currentDataLines.isEmpty,
              let payload = currentDataLines.joined(separator: "\n").data(using: .utf8),
              let dto = try? JSONDecoder().decode(ForegroundCallInviteSSEPayload.self, from: payload) else {
            return []
        }

        return dto.transportEvent(validator: validator, now: now()).map { [$0] } ?? []
    }

    var description: String {
        "ForegroundCallSignalingSSEParser(buffered: \(bufferedLine.isEmpty ? "false" : "true"), realTransport: false)"
    }

    var debugDescription: String {
        description
    }
}

final class ForegroundCallSignalingSSETransport: ForegroundCallSignalingTransport, CustomStringConvertible, CustomDebugStringConvertible {
    private let isEnabled: Bool
    private let stream: ForegroundCallSignalingSSEStreaming
    private var parser: ForegroundCallSignalingSSEParser
    private var onEvent: ((ForegroundCallSignalingTransportEvent) -> Void)?
    private(set) var diagnostics = ForegroundCallSignalingTransportDiagnostics.disabled
    #if DEBUG
    private var debugPendingInviteParse = false
    #endif
    #if DEBUG
    private let debugObserver: (DebugForegroundCallSignalingSSESmokeTraceEvent) -> Void
    #endif

    #if DEBUG
    init(isEnabled: Bool = false,
         stream: ForegroundCallSignalingSSEStreaming = DisabledForegroundCallSignalingSSEStream(),
         validator: ForegroundCallInviteValidator = .init(),
         debugObserver: @escaping (DebugForegroundCallSignalingSSESmokeTraceEvent) -> Void = { _ in },
         now: @escaping () -> Date = Date.init) {
        self.isEnabled = isEnabled
        self.stream = stream
        parser = ForegroundCallSignalingSSEParser(validator: validator, now: now)
        self.debugObserver = debugObserver
    }
    #else
    init(isEnabled: Bool = false,
         stream: ForegroundCallSignalingSSEStreaming = DisabledForegroundCallSignalingSSEStream(),
         validator: ForegroundCallInviteValidator = .init(),
         now: @escaping () -> Date = Date.init) {
        self.isEnabled = isEnabled
        self.stream = stream
        parser = ForegroundCallSignalingSSEParser(validator: validator, now: now)
    }
    #endif

    func start(onEvent: @escaping (ForegroundCallSignalingTransportEvent) -> Void) {
        guard isEnabled else {
            diagnostics = .init(isStarted: false,
                                deliveredInviteCount: diagnostics.deliveredInviteCount,
                                latestEventKind: nil,
                                latestResult: .ignored,
                                realTransport: false,
                                latestFailureReason: nil)
            return
        }

        self.onEvent = onEvent
        diagnostics = .init(isStarted: true,
                            deliveredInviteCount: diagnostics.deliveredInviteCount,
                            latestEventKind: diagnostics.latestEventKind,
                            latestResult: .started,
                            realTransport: true,
                            latestFailureReason: nil)
        stream.start { [weak self] chunk in
            self?.handle(chunk)
        } onCompletion: { [weak self] completion in
            self?.handle(completion)
        }
    }

    func stop() {
        stream.stop()
        onEvent = nil
        parser = ForegroundCallSignalingSSEParser()
        #if DEBUG
        debugPendingInviteParse = false
        #endif
        diagnostics = .init(isStarted: false,
                            deliveredInviteCount: diagnostics.deliveredInviteCount,
                            latestEventKind: diagnostics.latestEventKind,
                            latestResult: .stopped,
                            realTransport: isEnabled,
                            latestFailureReason: diagnostics.latestFailureReason)
    }

    private func handle(_ chunk: Data) {
        #if DEBUG
        let isEventDelimiter = String(data: chunk, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == true
        if !chunk.isEmpty {
            debugObserver(.rawEventReceived)
            if let eventType = ForegroundCallSignalingSSESafeEventType(chunk: chunk) {
                debugObserver(.sseEventType(eventType))
                if eventType == .invite {
                    debugObserver(.inviteParseAttempted)
                    debugPendingInviteParse = true
                }
            }
        }
        #endif
        let events = parser.consume(chunk)
        guard !events.isEmpty else {
            #if DEBUG
            if isEventDelimiter, debugPendingInviteParse {
                debugObserver(.inviteParseSucceeded(false))
                debugPendingInviteParse = false
            }
            #endif
            diagnostics = .init(isStarted: diagnostics.isStarted,
                                deliveredInviteCount: diagnostics.deliveredInviteCount,
                                latestEventKind: diagnostics.latestEventKind,
                                latestResult: .ignored,
                                realTransport: isEnabled,
                                latestFailureReason: diagnostics.latestFailureReason)
            return
        }

        for event in events {
            onEvent?(event)
            #if DEBUG
            if event.kind == .invite {
                debugObserver(.inviteParseSucceeded(true))
                debugObserver(.pipelineDelivered(true))
                debugPendingInviteParse = false
            }
            #endif
            let deliveredInviteCount = event.kind == .invite ? diagnostics.deliveredInviteCount + 1 : diagnostics.deliveredInviteCount
            let latestResult: ForegroundCallSignalingTransportResult = event.kind == .ready ? .connected : .delivered
            diagnostics = .init(isStarted: diagnostics.isStarted,
                                deliveredInviteCount: deliveredInviteCount,
                                latestEventKind: event.kind,
                                latestResult: latestResult,
                                realTransport: isEnabled,
                                latestFailureReason: nil)
        }
    }

    private func handle(_ completion: ForegroundCallSignalingSSEStreamCompletion) {
        let latestResult: ForegroundCallSignalingTransportResult = completion == .ended ? .stopped : .ignored
        diagnostics = .init(isStarted: false,
                            deliveredInviteCount: diagnostics.deliveredInviteCount,
                            latestEventKind: diagnostics.latestEventKind,
                            latestResult: latestResult,
                            realTransport: isEnabled,
                            latestFailureReason: completion.failureReason)
        onEvent?(.stopped)
    }

    var description: String {
        "ForegroundCallSignalingSSETransport(\(diagnostics), configured: \(isEnabled), mediaConnectRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

private struct ForegroundCallInviteSSEPayload: Decodable {
    let type: String
    let version: Int
    let callHandle: String
    let callKind: String
    let createdAtMs: Int
    let expiresAtMs: Int
    let displayLabel: String

    enum CodingKeys: String, CodingKey {
        case type
        case version
        case callHandle = "call_handle"
        case callKind = "call_kind"
        case createdAtMs = "created_at_ms"
        case expiresAtMs = "expires_at_ms"
        case displayLabel = "display_label"
    }

    func transportEvent(validator: ForegroundCallInviteValidator, now: Date) -> ForegroundCallSignalingTransportEvent? {
        guard type == "foreground.call.invite",
              version == 1 else {
            return nil
        }

        let kind = ForegroundCallInviteKind(rawValue: callKind) ?? .unsupported
        let createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1000)
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAtMs) / 1000)
        let displayMetadata = NativeIncomingCallKitDisplayMetadata(displayLabel)

        switch validator.validate(rawHandle: callHandle,
                                  kind: kind,
                                  state: .incoming,
                                  createdAt: createdAt,
                                  expiresAt: expiresAt,
                                  displayMetadata: displayMetadata,
                                  now: now) {
        case .valid(let signal):
            return .invite(signal)
        case .failClosed:
            return nil
        }
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }
        return String(dropFirst(prefix.count))
    }

    var trimmedSSEField: String {
        if hasPrefix(" ") {
            return String(dropFirst())
        }
        return self
    }
}

final class ForegroundCallSignalingTransportPipeline: CustomStringConvertible, CustomDebugStringConvertible {
    private let transport: ForegroundCallSignalingTransport
    private let inviteHandler: ForegroundCallInviteHandler
    private let validationContext: () -> NativeIncomingCallValidationContext
    private(set) var latestOutcome: ForegroundCallInviteHandlingOutcome?

    init(transport: ForegroundCallSignalingTransport,
         inviteHandler: ForegroundCallInviteHandler,
         validationContext: @escaping () -> NativeIncomingCallValidationContext = { .valid }) {
        self.transport = transport
        self.inviteHandler = inviteHandler
        self.validationContext = validationContext
    }

    func start() {
        transport.start { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        transport.stop()
    }

    private func handle(_ event: ForegroundCallSignalingTransportEvent) {
        switch event {
        case .ready, .stopped:
            break
        case .invite(let signal):
            latestOutcome = inviteHandler.handle(signal, context: validationContext())
        }
    }

    var description: String {
        "ForegroundCallSignalingTransportPipeline(latestOutcome: \(latestOutcome?.description ?? "none"), realTransport: false, mediaConnectRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

#if DEBUG
enum ForegroundCallSignalingSSESafeEventType: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case ready = "foreground.ready"
    case invite = "foreground.call.invite"
    case other

    init?(chunk: Data) {
        guard let text = String(data: chunk, encoding: .utf8),
              let eventLine = text.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("event:") }) else {
            return nil
        }

        let eventType = eventLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .dropPrefix("event:")
            .trimmedSSEField
        switch eventType {
        case Self.ready.rawValue:
            self = .ready
        case Self.invite.rawValue:
            self = .invite
        default:
            self = .other
        }
    }

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DebugForegroundCallSignalingSSESmokeTraceEvent: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case rawEventReceived
    case sseEventType(ForegroundCallSignalingSSESafeEventType)
    case inviteParseAttempted
    case inviteParseSucceeded(Bool)
    case pipelineDelivered(Bool)

    var description: String {
        switch self {
        case .rawEventReceived:
            "raw_event_received=true"
        case .sseEventType(let eventType):
            "sse_event_type=\(eventType)"
        case .inviteParseAttempted:
            "invite_parse_attempted=true"
        case .inviteParseSucceeded(let succeeded):
            "invite_parse_succeeded=\(succeeded)"
        case .pipelineDelivered(let delivered):
            "pipeline_delivered=\(delivered)"
        }
    }

    var debugDescription: String {
        description
    }
}

enum DebugForegroundCallSignalingSSESmokeHelperBlockedReason: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case invalidStreamURL = "invalid_stream_url"
    case missingActiveSession = "missing_active_session"
    case missingAccessTokenProvider = "missing_access_token_provider"
    case missingAccessToken = "missing_access_token"
    case blankAccessToken = "blank_access_token"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DebugForegroundCallSignalingSSESmokeHelperDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    var helperInvoked: Bool
    var activeSessionAvailable: Bool
    var accessTokenAvailable: Bool
    var deviceIDAvailable: Bool
    var homeserverURLAvailable: Bool
    var foregroundSSEStartRequested: Bool
    var foregroundSSEStartBlockedReason: DebugForegroundCallSignalingSSESmokeHelperBlockedReason

    var description: String {
        "DebugForegroundCallSignalingSSESmokeHelperDiagnostics(" + [
            "helper_invoked=\(helperInvoked)",
            "active_session_available=\(activeSessionAvailable)",
            "access_token_available=\(accessTokenAvailable)",
            "device_id_available=\(deviceIDAvailable)",
            "homeserver_url_available=\(homeserverURLAvailable)",
            "foreground_sse_start_requested=\(foregroundSSEStartRequested)",
            "foreground_sse_start_blocked_reason=\(foregroundSSEStartBlockedReason)"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

enum DebugForegroundCallSignalingRealInviteSenderBlockedReason: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case invalidInviteURL = "invalid_invite_url"
    case missingActiveSession = "missing_active_session"
    case missingAccessTokenProvider = "missing_access_token_provider"
    case missingAccessToken = "missing_access_token"
    case blankAccessToken = "blank_access_token"
    case missingRecipient = "missing_recipient"

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum DebugForegroundCallSignalingRealInviteSenderPostStatus: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case notRequested = "not_requested"
    case requested
    case httpSuccess = "http_success"
    case httpUnauthorized = "http_unauthorized"
    case httpFailed = "http_failed"
    case httpForbidden = "http_forbidden"
    case httpClientError = "http_client_error"
    case httpServerError = "http_server_error"
    case httpUnexpected = "http_unexpected"
    case nonHTTPResponse = "non_http_response"
    case network

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DebugForegroundCallSignalingRealInviteSenderDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    var senderHelperInvoked: Bool
    var senderActiveSessionAvailable: Bool
    var senderAccessTokenAvailable: Bool
    var senderInvitePostRequested: Bool
    var senderInvitePostStatus: DebugForegroundCallSignalingRealInviteSenderPostStatus
    var senderInviteDeliveryReportReceived: Bool
    var senderTokenRefreshNeeded = false
    var senderTokenRefreshAttempted = false
    var senderTokenRefreshSucceeded = false
    var senderInviteRetryRequested = false
    var senderInviteRetryStatus: DebugForegroundCallSignalingRealInviteSenderPostStatus = .notRequested
    var senderInviteBlockedReason: DebugForegroundCallSignalingRealInviteSenderBlockedReason

    var description: String {
        "DebugForegroundCallSignalingRealInviteSenderDiagnostics(" + [
            "sender_helper_invoked=\(senderHelperInvoked)",
            "sender_active_session_available=\(senderActiveSessionAvailable)",
            "sender_access_token_available=\(senderAccessTokenAvailable)",
            "sender_invite_post_requested=\(senderInvitePostRequested)",
            "sender_invite_post_status=\(senderInvitePostStatus)",
            "sender_invite_delivery_report_received=\(senderInviteDeliveryReportReceived)",
            "sender_token_refresh_needed=\(senderTokenRefreshNeeded)",
            "sender_token_refresh_attempted=\(senderTokenRefreshAttempted)",
            "sender_token_refresh_succeeded=\(senderTokenRefreshSucceeded)",
            "sender_invite_retry_requested=\(senderInviteRetryRequested)",
            "sender_invite_retry_status=\(senderInviteRetryStatus)",
            "sender_invite_blocked_reason=\(senderInviteBlockedReason)"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DebugForegroundCallSignalingSSERuntimeDiagnostics: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    var sseConfigured: Bool
    var sseStarted: Bool
    var sseConnected: Bool
    var inviteReceived: Bool
    var inviteValid: Bool
    var incomingRequested: Bool
    var fallbackDeduped: Bool
    var transportStopped: Bool
    var streamFailure: ForegroundCallSignalingSSEStreamFailureReason?

    static let disabled = Self(sseConfigured: false,
                               sseStarted: false,
                               sseConnected: false,
                               inviteReceived: false,
                               inviteValid: false,
                               incomingRequested: false,
                               fallbackDeduped: false,
                               transportStopped: false,
                               streamFailure: nil)

    var description: String {
        "DebugForegroundCallSignalingSSERuntimeDiagnostics(" + [
            "sse_configured=\(sseConfigured)",
            "sse_started=\(sseStarted)",
            "sse_connected=\(sseConnected)",
            "invite_received=\(inviteReceived)",
            "invite_valid=\(inviteValid)",
            "incoming_requested=\(incomingRequested)",
            "fallback_deduped=\(fallbackDeduped)",
            "transport_stopped=\(transportStopped)",
            "stream_failure=\(streamFailure?.description ?? "none")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

struct DebugForegroundCallSignalingSSESmokeDiagnosticsLogger {
    static let prefix = "[SSE-SMOKE-DIAG]"

    func redactedLines(for diagnostics: DebugForegroundCallSignalingSSERuntimeDiagnostics) -> [String] {
        [
            "\(Self.prefix) sse_configured=\(diagnostics.sseConfigured)",
            "\(Self.prefix) sse_started=\(diagnostics.sseStarted)",
            "\(Self.prefix) sse_connected=\(diagnostics.sseConnected)",
            "\(Self.prefix) invite_received=\(diagnostics.inviteReceived)",
            "\(Self.prefix) invite_valid=\(diagnostics.inviteValid)",
            "\(Self.prefix) incoming_requested=\(diagnostics.incomingRequested)",
            "\(Self.prefix) fallback_deduped=\(diagnostics.fallbackDeduped)",
            "\(Self.prefix) transport_stopped=\(diagnostics.transportStopped)",
            "\(Self.prefix) stream_failure=\(diagnostics.streamFailure?.description ?? "none")"
        ]
    }

    func redactedLines(for diagnostics: DebugForegroundCallSignalingSSESmokeHelperDiagnostics) -> [String] {
        [
            "\(Self.prefix) helper_invoked=\(diagnostics.helperInvoked)",
            "\(Self.prefix) active_session_available=\(diagnostics.activeSessionAvailable)",
            "\(Self.prefix) access_token_available=\(diagnostics.accessTokenAvailable)",
            "\(Self.prefix) device_id_available=\(diagnostics.deviceIDAvailable)",
            "\(Self.prefix) homeserver_url_available=\(diagnostics.homeserverURLAvailable)",
            "\(Self.prefix) foreground_sse_start_requested=\(diagnostics.foregroundSSEStartRequested)",
            "\(Self.prefix) foreground_sse_start_blocked_reason=\(diagnostics.foregroundSSEStartBlockedReason)"
        ]
    }

    func redactedLines(for diagnostics: DebugForegroundCallSignalingRealInviteSenderDiagnostics) -> [String] {
        [
            "\(Self.prefix) sender_helper_invoked=\(diagnostics.senderHelperInvoked)",
            "\(Self.prefix) sender_active_session_available=\(diagnostics.senderActiveSessionAvailable)",
            "\(Self.prefix) sender_access_token_available=\(diagnostics.senderAccessTokenAvailable)",
            "\(Self.prefix) sender_invite_post_requested=\(diagnostics.senderInvitePostRequested)",
            "\(Self.prefix) sender_invite_post_status=\(diagnostics.senderInvitePostStatus)",
            "\(Self.prefix) sender_invite_delivery_report_received=\(diagnostics.senderInviteDeliveryReportReceived)",
            "\(Self.prefix) sender_token_refresh_needed=\(diagnostics.senderTokenRefreshNeeded)",
            "\(Self.prefix) sender_token_refresh_attempted=\(diagnostics.senderTokenRefreshAttempted)",
            "\(Self.prefix) sender_token_refresh_succeeded=\(diagnostics.senderTokenRefreshSucceeded)",
            "\(Self.prefix) sender_invite_retry_requested=\(diagnostics.senderInviteRetryRequested)",
            "\(Self.prefix) sender_invite_retry_status=\(diagnostics.senderInviteRetryStatus)",
            "\(Self.prefix) sender_invite_blocked_reason=\(diagnostics.senderInviteBlockedReason)"
        ]
    }

    func log(_ diagnostics: DebugForegroundCallSignalingSSERuntimeDiagnostics) {
        redactedLines(for: diagnostics).forEach { MXLog.info($0) }
    }

    func log(_ diagnostics: DebugForegroundCallSignalingSSESmokeHelperDiagnostics) {
        redactedLines(for: diagnostics).forEach { MXLog.info($0) }
    }

    func log(_ diagnostics: DebugForegroundCallSignalingRealInviteSenderDiagnostics) {
        redactedLines(for: diagnostics).forEach { MXLog.info($0) }
    }

    func redactedLine(for event: DebugForegroundCallSignalingSSESmokeTraceEvent) -> String {
        "\(Self.prefix) \(event)"
    }

    func log(_ event: DebugForegroundCallSignalingSSESmokeTraceEvent) {
        MXLog.info(redactedLine(for: event))
    }
}

final class DebugForegroundCallSignalingSSERuntimeOwner: CustomStringConvertible, CustomDebugStringConvertible {
    private let isEnabled: Bool
    private let transport: ForegroundCallSignalingTransport?
    private let inviteHandler: ForegroundCallInviteHandler?
    private let validationContext: () -> NativeIncomingCallValidationContext
    private let diagnosticsObserver: (DebugForegroundCallSignalingSSERuntimeDiagnostics) -> Void
    private var handledHandles = Set<NativeIncomingCallHandle>()
    private(set) var diagnostics: DebugForegroundCallSignalingSSERuntimeDiagnostics {
        didSet {
            diagnosticsObserver(diagnostics)
        }
    }

    private(set) var latestOutcome: ForegroundCallInviteHandlingOutcome?

    init(isEnabled: Bool = false,
         transport: ForegroundCallSignalingTransport? = nil,
         inviteHandler: ForegroundCallInviteHandler? = nil,
         validationContext: @escaping () -> NativeIncomingCallValidationContext = { .valid },
         diagnosticsObserver: @escaping (DebugForegroundCallSignalingSSERuntimeDiagnostics) -> Void = { _ in }) {
        self.isEnabled = isEnabled
        self.transport = transport
        self.inviteHandler = inviteHandler
        self.validationContext = validationContext
        self.diagnosticsObserver = diagnosticsObserver
        diagnostics = .disabled
    }

    func appDidEnterForeground(authenticatedSessionAvailable: Bool) {
        start(authenticatedSessionAvailable: authenticatedSessionAvailable)
    }

    func appDidEnterBackground() {
        stop()
    }

    func start(authenticatedSessionAvailable: Bool) {
        guard isEnabled,
              authenticatedSessionAvailable,
              let transport,
              let inviteHandler else {
            diagnostics = .init(sseConfigured: false,
                                sseStarted: false,
                                sseConnected: false,
                                inviteReceived: diagnostics.inviteReceived,
                                inviteValid: diagnostics.inviteValid,
                                incomingRequested: diagnostics.incomingRequested,
                                fallbackDeduped: diagnostics.fallbackDeduped,
                                transportStopped: diagnostics.transportStopped,
                                streamFailure: diagnostics.streamFailure)
            return
        }

        transport.start { [weak self, inviteHandler] event in
            self?.handle(event, inviteHandler: inviteHandler)
        }
        diagnostics = .init(sseConfigured: true,
                            sseStarted: transport.diagnostics.isStarted,
                            sseConnected: false,
                            inviteReceived: diagnostics.inviteReceived,
                            inviteValid: diagnostics.inviteValid,
                            incomingRequested: diagnostics.incomingRequested,
                            fallbackDeduped: diagnostics.fallbackDeduped,
                            transportStopped: false,
                            streamFailure: nil)
    }

    func stop() {
        transport?.stop()
        diagnostics = .init(sseConfigured: diagnostics.sseConfigured,
                            sseStarted: false,
                            sseConnected: false,
                            inviteReceived: diagnostics.inviteReceived,
                            inviteValid: diagnostics.inviteValid,
                            incomingRequested: diagnostics.incomingRequested,
                            fallbackDeduped: diagnostics.fallbackDeduped,
                            transportStopped: true,
                            streamFailure: diagnostics.streamFailure)
    }

    func handleFallbackInvite(_ signal: ForegroundCallInviteSignal,
                              context: NativeIncomingCallValidationContext = .valid) -> ForegroundCallInviteHandlingOutcome? {
        guard let inviteHandler else {
            return nil
        }

        if handledHandles.contains(signal.handle) {
            latestOutcome = .suppressed(.duplicate)
            diagnostics = .init(sseConfigured: diagnostics.sseConfigured,
                                sseStarted: diagnostics.sseStarted,
                                sseConnected: diagnostics.sseConnected,
                                inviteReceived: diagnostics.inviteReceived,
                                inviteValid: diagnostics.inviteValid,
                                incomingRequested: diagnostics.incomingRequested,
                                fallbackDeduped: true,
                                transportStopped: diagnostics.transportStopped,
                                streamFailure: diagnostics.streamFailure)
            return latestOutcome
        }

        latestOutcome = inviteHandler.handle(signal, context: context)
        if case .reported = latestOutcome {
            handledHandles.insert(signal.handle)
        }
        return latestOutcome
    }

    private func handle(_ event: ForegroundCallSignalingTransportEvent,
                        inviteHandler: ForegroundCallInviteHandler) {
        switch event {
        case .ready:
            diagnostics = .init(sseConfigured: diagnostics.sseConfigured,
                                sseStarted: diagnostics.sseStarted,
                                sseConnected: true,
                                inviteReceived: diagnostics.inviteReceived,
                                inviteValid: diagnostics.inviteValid,
                                incomingRequested: diagnostics.incomingRequested,
                                fallbackDeduped: diagnostics.fallbackDeduped,
                                transportStopped: diagnostics.transportStopped,
                                streamFailure: diagnostics.streamFailure)
        case .stopped:
            diagnostics = .init(sseConfigured: diagnostics.sseConfigured,
                                sseStarted: false,
                                sseConnected: false,
                                inviteReceived: diagnostics.inviteReceived,
                                inviteValid: diagnostics.inviteValid,
                                incomingRequested: diagnostics.incomingRequested,
                                fallbackDeduped: diagnostics.fallbackDeduped,
                                transportStopped: true,
                                streamFailure: transport?.diagnostics.latestFailureReason)
        case .invite(let signal):
            let outcome = inviteHandler.handle(signal, context: validationContext())
            latestOutcome = outcome
            let wasReported: Bool
            switch outcome {
            case .reported:
                handledHandles.insert(signal.handle)
                wasReported = true
            case .suppressed:
                wasReported = false
            }
            diagnostics = .init(sseConfigured: diagnostics.sseConfigured,
                                sseStarted: diagnostics.sseStarted,
                                sseConnected: true,
                                inviteReceived: true,
                                inviteValid: wasReported,
                                incomingRequested: wasReported,
                                fallbackDeduped: diagnostics.fallbackDeduped,
                                transportStopped: diagnostics.transportStopped,
                                streamFailure: diagnostics.streamFailure)
        }
    }

    var description: String {
        "DebugForegroundCallSignalingSSERuntimeOwner(\(diagnostics), debugOnly: true, hardcodedEndpoint: false, mediaConnectRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}
#endif

struct ForegroundCallInviteValidator {
    var supportedKind: ForegroundCallInviteKind = .audio
    var futureSkewAllowance: TimeInterval = 5

    func validate(rawHandle: String,
                  kind: ForegroundCallInviteKind,
                  state: ForegroundCallInviteSignalState,
                  createdAt: Date,
                  expiresAt: Date,
                  displayMetadata: NativeIncomingCallKitDisplayMetadata?,
                  now: Date) -> ForegroundCallInviteValidationResult {
        guard let handle = NativeIncomingCallHandle(rawHandle),
              let displayMetadata else {
            return .failClosed(.malformed)
        }

        let signal = ForegroundCallInviteSignal(handle: handle,
                                                kind: kind,
                                                state: state,
                                                createdAt: createdAt,
                                                expiresAt: expiresAt,
                                                displayMetadata: displayMetadata)
        return validate(signal, now: now)
    }

    func validate(_ signal: ForegroundCallInviteSignal, now: Date) -> ForegroundCallInviteValidationResult {
        guard signal.kind == supportedKind else {
            return .failClosed(.unverifiable)
        }
        guard signal.state == .incoming else {
            return .failClosed(.stale)
        }
        guard signal.createdAt <= now.addingTimeInterval(futureSkewAllowance),
              signal.expiresAt > now else {
            return .failClosed(.stale)
        }

        return .valid(signal)
    }
}

final class ForegroundCallInviteHandler: CustomStringConvertible, CustomDebugStringConvertible {
    private let isEnabled: Bool
    private let validator: ForegroundCallInviteValidator
    private let stateStore: NativeIncomingCallStateStoring
    private let reportingAdapter: NativeIncomingCallReportingAdapting
    private let diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording
    private let now: () -> Date
    private var handledHandles = Set<NativeIncomingCallHandle>()

    init(isEnabled: Bool = false,
         validator: ForegroundCallInviteValidator = .init(),
         stateStore: NativeIncomingCallStateStoring,
         reportingAdapter: NativeIncomingCallReportingAdapting,
         diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording,
         now: @escaping () -> Date = Date.init) {
        self.isEnabled = isEnabled
        self.validator = validator
        self.stateStore = stateStore
        self.reportingAdapter = reportingAdapter
        self.diagnosticsRecorder = diagnosticsRecorder
        self.now = now
    }

    func handle(rawHandle: String,
                kind: ForegroundCallInviteKind,
                state: ForegroundCallInviteSignalState,
                createdAt: Date,
                expiresAt: Date,
                displayMetadata: NativeIncomingCallKitDisplayMetadata?,
                context: NativeIncomingCallValidationContext = .valid) -> ForegroundCallInviteHandlingOutcome {
        switch validator.validate(rawHandle: rawHandle,
                                  kind: kind,
                                  state: state,
                                  createdAt: createdAt,
                                  expiresAt: expiresAt,
                                  displayMetadata: displayMetadata,
                                  now: now()) {
        case .valid(let signal):
            return handle(signal, context: context)
        case .failClosed(let reason):
            return failClosed(reason)
        }
    }

    func handle(_ signal: ForegroundCallInviteSignal,
                context: NativeIncomingCallValidationContext = .valid) -> ForegroundCallInviteHandlingOutcome {
        guard isEnabled else {
            return failClosed(.dependencyUnavailable)
        }
        switch validator.validate(signal, now: now()) {
        case .valid:
            break
        case .failClosed(let reason):
            return failClosed(reason)
        }
        guard !stateStore.hasSeen(signal.handle),
              !handledHandles.contains(signal.handle) else {
            return failClosed(.duplicate)
        }
        if let failClosedReason = context.failClosedReason {
            return failClosed(failClosedReason)
        }

        let identity = NativeIncomingCallIdentity(handle: signal.handle, receivedAt: signal.createdAt)
        stateStore.setState(.received, for: signal.handle)
        stateStore.setState(.validating, for: signal.handle)
        stateStore.setState(.reportable, for: signal.handle)
        handledHandles.insert(signal.handle)

        let reportSucceeded = reportingAdapter.reportIncomingCall(identity: identity)
        diagnosticsRecorder.record(.init(lifecycleState: reportSucceeded ? .reported : .blocked,
                                         failClosedReason: reportSucceeded ? nil : .callReportingUnavailable,
                                         reportAttempted: true,
                                         reportSucceeded: reportSucceeded,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))

        guard reportSucceeded else {
            stateStore.setState(.blocked, for: signal.handle)
            return .suppressed(.callReportingUnavailable)
        }

        stateStore.setState(.reported, for: signal.handle)
        return .reported(identity)
    }

    private func failClosed(_ reason: NativeIncomingCallFailClosedReason) -> ForegroundCallInviteHandlingOutcome {
        diagnosticsRecorder.record(.failClosed(reason))
        return .suppressed(reason)
    }

    var description: String {
        "ForegroundCallInviteHandler(isEnabled: \(isEnabled), handledCount: \(handledHandles.count), realTransport: false, mediaConnectRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

enum NativeIncomingSyntheticCallKitProofResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case reported
    case answered
    case ended
    case muted(Bool)
    case failed(NativeIncomingCallFailClosedReason)

    var description: String {
        switch self {
        case .reported:
            "reported"
        case .answered:
            "answered"
        case .ended:
            "ended"
        case .muted(let isMuted):
            "muted(\(isMuted))"
        case .failed(let reason):
            "failed(\(reason))"
        }
    }

    var debugDescription: String {
        description
    }
}

protocol NativeIncomingSyntheticCallKitActionHandling: AnyObject {
    func answerSyntheticCall(identity: NativeIncomingCallIdentity)
    func endSyntheticCall(identity: NativeIncomingCallIdentity)
    func setSyntheticCallMuted(_ isMuted: Bool, identity: NativeIncomingCallIdentity)
}

protocol NativeIncomingCallStateMachineActionRouting: AnyObject {
    func requestAnswer(identity: NativeIncomingCallIdentity)
    func endIncomingCall(identity: NativeIncomingCallIdentity)
    func setIncomingCallMuted(_ isMuted: Bool, identity: NativeIncomingCallIdentity)
}

final class DisabledNativeIncomingForegroundAcceptanceGate: CustomStringConvertible, CustomDebugStringConvertible {
    private let isEnabled: Bool
    private let stateStore: NativeIncomingCallStateStoring
    private let diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording
    private let authorizer: NativeIncomingForegroundAcceptanceAuthorizing?

    init(isEnabled: Bool = false,
         stateStore: NativeIncomingCallStateStoring,
         diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording,
         authorizer: NativeIncomingForegroundAcceptanceAuthorizing?) {
        self.isEnabled = isEnabled
        self.stateStore = stateStore
        self.diagnosticsRecorder = diagnosticsRecorder
        self.authorizer = authorizer
    }

    func requestForegroundAcceptance(identity: NativeIncomingCallIdentity) -> NativeIncomingForegroundAcceptanceOutcome {
        guard isEnabled else {
            return failClosed(.dependencyUnavailable, identity: identity, mediaCredentialRequested: false)
        }
        guard stateStore.state(for: identity.handle) == .answerRequested else {
            return failClosed(.unverifiable, identity: identity, mediaCredentialRequested: false)
        }
        guard let authorizer else {
            return failClosed(.foregroundCredentialAuthorityUnavailable, identity: identity, mediaCredentialRequested: false)
        }

        let decision = authorizer.foregroundAcceptanceDecision(for: identity)
        if let failClosedReason = decision.failClosedReason {
            return failClosed(failClosedReason, identity: identity, mediaCredentialRequested: true)
        }

        stateStore.setState(.foregroundCredentialAuthorized, for: identity.handle)
        diagnosticsRecorder.record(.init(lifecycleState: .foregroundCredentialAuthorized,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: true,
                                         mediaConnectAttempted: false))
        return .credentialAuthorized(identity)
    }

    func isMediaAllowedAfterForegroundAcceptance(identity: NativeIncomingCallIdentity) -> Bool {
        stateStore.state(for: identity.handle) == .foregroundCredentialAuthorized
    }

    func endForegroundAcceptance(identity: NativeIncomingCallIdentity) {
        stateStore.clear(identity.handle)
        diagnosticsRecorder.record(.init(lifecycleState: .ended,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
    }

    private func failClosed(_ reason: NativeIncomingCallFailClosedReason,
                            identity: NativeIncomingCallIdentity,
                            mediaCredentialRequested: Bool) -> NativeIncomingForegroundAcceptanceOutcome {
        stateStore.setState(.failed, for: identity.handle)
        diagnosticsRecorder.record(.init(lifecycleState: .failed,
                                         failClosedReason: reason,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: mediaCredentialRequested,
                                         mediaConnectAttempted: false))
        return .failClosed(reason)
    }

    var description: String {
        "DisabledNativeIncomingForegroundAcceptanceGate(isEnabled: \(isEnabled), realRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

final class ForegroundNativeIncomingCallE2ECoordinator: CustomStringConvertible, CustomDebugStringConvertible {
    private let isEnabled: Bool
    private let stateStore: NativeIncomingCallStateStoring
    private let callKitAdapter: NativeIncomingSyntheticCallKitUIProofAdapter
    private let acceptanceGate: DisabledNativeIncomingForegroundAcceptanceGate
    private let mediaConnector: NativeForegroundIncomingMediaConnecting
    private let diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording
    private let now: () -> Date
    private let staleInterval: TimeInterval
    private var identitiesByHandle = [NativeIncomingCallHandle: NativeIncomingCallIdentity]()
    private var mediaConnectedHandles = Set<NativeIncomingCallHandle>()
    private var mediaConnectAttemptedHandles = Set<NativeIncomingCallHandle>()
    private var endedHandles = Set<NativeIncomingCallHandle>()

    init(isEnabled: Bool = false,
         stateStore: NativeIncomingCallStateStoring,
         callKitAdapter: NativeIncomingSyntheticCallKitUIProofAdapter,
         acceptanceGate: DisabledNativeIncomingForegroundAcceptanceGate,
         mediaConnector: NativeForegroundIncomingMediaConnecting,
         diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording,
         now: @escaping () -> Date = Date.init,
         staleInterval: TimeInterval = 45) {
        self.isEnabled = isEnabled
        self.stateStore = stateStore
        self.callKitAdapter = callKitAdapter
        self.acceptanceGate = acceptanceGate
        self.mediaConnector = mediaConnector
        self.diagnosticsRecorder = diagnosticsRecorder
        self.now = now
        self.staleInterval = staleInterval
    }

    func receiveForegroundIncomingCall(session: DirectCallSession,
                                       displayMetadata: NativeIncomingCallKitDisplayMetadata?,
                                       context: NativeIncomingCallValidationContext = .valid) -> NativeForegroundIncomingCallE2EOutcome {
        guard isEnabled else {
            return failClosed(.dependencyUnavailable, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }
        guard session.direction == .incoming,
              session.state == .incomingRinging,
              session.intent == .audio else {
            return failClosed(.unverifiable, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }
        guard let displayMetadata else {
            return failClosed(.malformed, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }
        guard now().timeIntervalSince(session.startedAt) <= staleInterval else {
            return failClosed(.stale, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }
        guard let handle = NativeIncomingCallHandle("foreground-\(session.callID)") else {
            return failClosed(.malformed, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }
        guard !stateStore.hasSeen(handle), identitiesByHandle[handle] == nil else {
            return failClosed(.duplicate, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }
        if let failClosedReason = context.failClosedReason {
            return failClosed(failClosedReason, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }

        let identity = NativeIncomingCallIdentity(handle: handle, receivedAt: session.startedAt)
        stateStore.setState(.received, for: handle)
        stateStore.setState(.validating, for: handle)
        stateStore.setState(.reportable, for: handle)

        switch callKitAdapter.reportSyntheticIncomingCall(identity: identity, displayMetadata: displayMetadata) {
        case .reported:
            identitiesByHandle[handle] = identity
            stateStore.setState(.reported, for: handle)
            return .callKitReported(identity)
        case .failed(let reason):
            stateStore.setState(.blocked, for: handle)
            return failClosed(reason, identity: identity, mediaCredentialRequested: false, mediaConnectAttempted: false)
        case .providerDidReset, .audioSessionActivated, .audioSessionDeactivated, .answerActionDelivered, .answered, .endActionDelivered, .endActionFulfilled, .localEndRequestedBeforeAnswer, .ended, .muted:
            return failClosed(.unverifiable, identity: identity, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }
    }

    func connectAnsweredForegroundIncomingCall(handle rawHandle: String) async -> NativeForegroundIncomingCallE2EOutcome {
        guard let identity = activeIdentity(for: rawHandle) else {
            return failClosed(.unverifiable, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }

        if mediaConnectedHandles.contains(identity.handle) {
            diagnosticsRecorder.record(.init(lifecycleState: .active,
                                             failClosedReason: nil,
                                             reportAttempted: false,
                                             reportSucceeded: nil,
                                             mediaCredentialRequested: true,
                                             mediaConnectAttempted: false))
            return .mediaConnected(identity)
        }
        guard !mediaConnectAttemptedHandles.contains(identity.handle) else {
            return failClosed(.existingActiveNativeSession,
                              identity: identity,
                              mediaCredentialRequested: true,
                              mediaConnectAttempted: false)
        }

        switch acceptanceGate.requestForegroundAcceptance(identity: identity) {
        case .failClosed(let reason):
            _ = callKitAdapter.endSyntheticCall(handle: identity.handle.value)
            stateStore.setState(.failed, for: identity.handle)
            diagnosticsRecorder.record(.init(lifecycleState: .failed,
                                             failClosedReason: reason,
                                             reportAttempted: false,
                                             reportSucceeded: nil,
                                             mediaCredentialRequested: reason != .foregroundCredentialAuthorityUnavailable,
                                             mediaConnectAttempted: false))
            return .failClosed(reason)
        case .credentialAuthorized:
            break
        }

        mediaConnectAttemptedHandles.insert(identity.handle)
        switch await mediaConnector.connectForegroundIncomingMedia(identity: identity) {
        case .connected:
            mediaConnectedHandles.insert(identity.handle)
            stateStore.setState(.active, for: identity.handle)
            diagnosticsRecorder.record(.init(lifecycleState: .active,
                                             failClosedReason: nil,
                                             reportAttempted: false,
                                             reportSucceeded: nil,
                                             mediaCredentialRequested: true,
                                             mediaConnectAttempted: true))
            return .mediaConnected(identity)
        case .failClosed(let reason):
            _ = callKitAdapter.endSyntheticCall(handle: identity.handle.value)
            stateStore.setState(.failed, for: identity.handle)
            diagnosticsRecorder.record(.init(lifecycleState: .failed,
                                             failClosedReason: reason,
                                             reportAttempted: false,
                                             reportSucceeded: nil,
                                             mediaCredentialRequested: true,
                                             mediaConnectAttempted: true))
            return .failClosed(reason)
        }
    }

    func endForegroundIncomingCall(handle rawHandle: String) async -> NativeForegroundIncomingCallE2EOutcome {
        if let handle = NativeIncomingCallHandle(rawHandle),
           endedHandles.contains(handle) {
            return .ended
        }
        guard let identity = activeIdentity(for: rawHandle) else {
            return failClosed(.unverifiable, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }

        _ = callKitAdapter.endSyntheticCall(handle: identity.handle.value)
        acceptanceGate.endForegroundAcceptance(identity: identity)
        identitiesByHandle[identity.handle] = nil
        stateStore.clear(identity.handle)
        endedHandles.insert(identity.handle)

        if mediaConnectedHandles.remove(identity.handle) != nil {
            await mediaConnector.endForegroundIncomingMedia(identity: identity)
        }
        mediaConnectAttemptedHandles.remove(identity.handle)
        return .ended
    }

    func setForegroundIncomingCallMuted(_ isMuted: Bool, handle rawHandle: String) -> NativeForegroundIncomingCallE2EOutcome {
        guard let identity = activeIdentity(for: rawHandle) else {
            return failClosed(.unverifiable, identity: nil, mediaCredentialRequested: false, mediaConnectAttempted: false)
        }

        _ = callKitAdapter.setSyntheticCallMuted(isMuted, handle: identity.handle.value)
        return .muted(isMuted)
    }

    private func activeIdentity(for rawHandle: String) -> NativeIncomingCallIdentity? {
        guard isEnabled,
              let handle = NativeIncomingCallHandle(rawHandle) else {
            return nil
        }

        return identitiesByHandle[handle]
    }

    private func failClosed(_ reason: NativeIncomingCallFailClosedReason,
                            identity: NativeIncomingCallIdentity?,
                            mediaCredentialRequested: Bool,
                            mediaConnectAttempted: Bool) -> NativeForegroundIncomingCallE2EOutcome {
        if let identity {
            stateStore.setState(.failed, for: identity.handle)
        }
        diagnosticsRecorder.record(.init(lifecycleState: .failed,
                                         failClosedReason: reason,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: mediaCredentialRequested,
                                         mediaConnectAttempted: mediaConnectAttempted))
        return .failClosed(reason)
    }

    var description: String {
        "ForegroundNativeIncomingCallE2ECoordinator(isEnabled: \(isEnabled), activeIdentityCount: \(identitiesByHandle.count), " +
            "mediaConnectedCount: \(mediaConnectedHandles.count), mediaConnectAttemptedCount: \(mediaConnectAttemptedHandles.count), " +
            "endedCount: \(endedHandles.count), pushRuntime: false, backgroundRuntime: false, realRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

final class DisabledNativeIncomingCallStateMachineActionRouter: NativeIncomingCallStateMachineActionRouting, CustomStringConvertible, CustomDebugStringConvertible {
    private let stateStore: NativeIncomingCallStateStoring
    private let diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording
    private(set) var answerRequestCount = 0
    private(set) var endCount = 0
    private(set) var muteCount = 0
    private(set) var latestMuteValue: Bool?

    init(stateStore: NativeIncomingCallStateStoring,
         diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording) {
        self.stateStore = stateStore
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    func requestAnswer(identity: NativeIncomingCallIdentity) {
        answerRequestCount += 1
        stateStore.setState(.answerRequested, for: identity.handle)
        diagnosticsRecorder.record(.init(lifecycleState: .answerRequested,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
    }

    func endIncomingCall(identity: NativeIncomingCallIdentity) {
        endCount += 1
        stateStore.setState(.ended, for: identity.handle)
        diagnosticsRecorder.record(.init(lifecycleState: .ended,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
    }

    func setIncomingCallMuted(_ isMuted: Bool, identity: NativeIncomingCallIdentity) {
        muteCount += 1
        latestMuteValue = isMuted
        diagnosticsRecorder.record(.init(lifecycleState: stateStore.state(for: identity.handle) ?? .reported,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
    }

    var description: String {
        "DisabledNativeIncomingCallStateMachineActionRouter(answerRequestCount: \(answerRequestCount), endCount: \(endCount), muteCount: \(muteCount), latestMuteValue: \(latestMuteValue.map(String.init) ?? "none"), realRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

final class NativeIncomingCallStateMachineSyntheticActionHandler: NativeIncomingSyntheticCallKitActionHandling, CustomStringConvertible, CustomDebugStringConvertible {
    private let actionRouter: NativeIncomingCallStateMachineActionRouting

    init(actionRouter: NativeIncomingCallStateMachineActionRouting) {
        self.actionRouter = actionRouter
    }

    func answerSyntheticCall(identity: NativeIncomingCallIdentity) {
        actionRouter.requestAnswer(identity: identity)
    }

    func endSyntheticCall(identity: NativeIncomingCallIdentity) {
        actionRouter.endIncomingCall(identity: identity)
    }

    func setSyntheticCallMuted(_ isMuted: Bool, identity: NativeIncomingCallIdentity) {
        actionRouter.setIncomingCallMuted(isMuted, identity: identity)
    }

    var description: String {
        "NativeIncomingCallStateMachineSyntheticActionHandler(realRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

final class DisabledNativeIncomingSyntheticCallKitProofCoordinator: CustomStringConvertible, CustomDebugStringConvertible {
    private let isEnabled: Bool
    private let stateStore: NativeIncomingCallStateStoring
    private let reportingAdapter: NativeIncomingCallReportingAdapting
    private let actionHandler: NativeIncomingSyntheticCallKitActionHandling
    private let diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording
    private var activeIdentities = [NativeIncomingCallHandle: NativeIncomingCallIdentity]()

    init(isEnabled: Bool = false,
         stateStore: NativeIncomingCallStateStoring,
         reportingAdapter: NativeIncomingCallReportingAdapting,
         actionHandler: NativeIncomingSyntheticCallKitActionHandling,
         diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording) {
        self.isEnabled = isEnabled
        self.stateStore = stateStore
        self.reportingAdapter = reportingAdapter
        self.actionHandler = actionHandler
        self.diagnosticsRecorder = diagnosticsRecorder
    }

    func reportSyntheticIncomingCall(identity: NativeIncomingCallIdentity,
                                     displayMetadata: NativeIncomingCallKitDisplayMetadata?) -> NativeIncomingSyntheticCallKitProofResult {
        guard isEnabled else {
            return failClosed(.dependencyUnavailable)
        }
        guard displayMetadata != nil else {
            return failClosed(.malformed)
        }
        guard stateStore.hasSeen(identity.handle) else {
            return failClosed(.unverifiable)
        }
        guard activeIdentities[identity.handle] == nil else {
            return failClosed(.duplicate)
        }

        let reportSucceeded = reportingAdapter.reportIncomingCall(identity: identity)
        diagnosticsRecorder.record(.init(lifecycleState: reportSucceeded ? .reported : .blocked,
                                         failClosedReason: reportSucceeded ? nil : .callReportingUnavailable,
                                         reportAttempted: true,
                                         reportSucceeded: reportSucceeded,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        guard reportSucceeded else {
            return .failed(.callReportingUnavailable)
        }

        activeIdentities[identity.handle] = identity
        stateStore.setState(.reported, for: identity.handle)
        return .reported
    }

    func answerSyntheticCall(handle rawHandle: String) -> NativeIncomingSyntheticCallKitProofResult {
        guard let identity = activeIdentity(for: rawHandle) else {
            return failClosed(.unverifiable)
        }

        stateStore.setState(.answered, for: identity.handle)
        actionHandler.answerSyntheticCall(identity: identity)
        diagnosticsRecorder.record(.init(lifecycleState: .answered,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        return .answered
    }

    func endSyntheticCall(handle rawHandle: String) -> NativeIncomingSyntheticCallKitProofResult {
        guard let identity = activeIdentity(for: rawHandle) else {
            return failClosed(.unverifiable)
        }

        activeIdentities[identity.handle] = nil
        stateStore.setState(.ended, for: identity.handle)
        reportingAdapter.endReportedCall(identity: identity, reason: .unknown)
        actionHandler.endSyntheticCall(identity: identity)
        diagnosticsRecorder.record(.init(lifecycleState: .ended,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        stateStore.clear(identity.handle)
        return .ended
    }

    func setSyntheticCallMuted(_ isMuted: Bool, handle rawHandle: String) -> NativeIncomingSyntheticCallKitProofResult {
        guard let identity = activeIdentity(for: rawHandle) else {
            return failClosed(.unverifiable)
        }

        actionHandler.setSyntheticCallMuted(isMuted, identity: identity)
        diagnosticsRecorder.record(.init(lifecycleState: stateStore.state(for: identity.handle) ?? .reported,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        return .muted(isMuted)
    }

    private func activeIdentity(for rawHandle: String) -> NativeIncomingCallIdentity? {
        guard isEnabled,
              let handle = NativeIncomingCallHandle(rawHandle) else {
            return nil
        }
        return activeIdentities[handle]
    }

    private func failClosed(_ reason: NativeIncomingCallFailClosedReason) -> NativeIncomingSyntheticCallKitProofResult {
        diagnosticsRecorder.record(.failClosed(reason))
        return .failed(reason)
    }

    var description: String {
        "DisabledNativeIncomingSyntheticCallKitProofCoordinator(isEnabled: \(isEnabled), realCallKitRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallDiagnosticTokenReason: String, Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case issued
    case unsupportedIntent
    case badRequest
    case authRejected
    case roomValidationFailed
    case eligibilityRejected
    case rateLimited
    case rateLimitStoreUnavailable
    case allocationFailed
    case liveKitRoomPrecreateFailed
    case tokenSigningFailed
    case tokenEndpointUnavailable
    case accessTokenUnavailable
    case tokenHTTPUnavailable
    case tokenResponseInvalid
    case serviceUnavailable
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

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
    case answerAccepted
    case answerWrongCall
    case answerWrongSender
    case answerStateInvalid
    case incomingKeyUnwrapFailed
    case incomingKeyTrustViolation
    case incomingNoEligibleDevice
    case incomingWrongRecipient
    case incomingWrongSender
    case incomingRoomMismatch
    case incomingCallMismatch
    case incomingIntentMismatch
    case incomingExpired
    case incomingDuplicate
    case incomingStateInvalid
    case incomingUnsupportedEnvelope
    case mediaTokenUnavailable
    case tokenEndpointUnavailable
    case accessTokenUnavailable
    case tokenHTTPUnavailable
    case tokenBackendRejected
    case tokenResponseInvalid
    case mediaFactoryUnavailable
    case mediaE2EEContextUnavailable
    case mediaConnectFailed
    case mediaSetupUnavailable
    case mediaUnsupportedIntent
    case liveKitURLInvalid
    case liveKitURLUnreachable
    case liveKitTokenRejected
    case liveKitRoomJoinFailed
    case liveKitE2EEConfigFailed
    case liveKitNetworkFailed
    case liveKitSDKError
    case liveKitUnknown
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
    case mediaFactoryUnavailable
    case mediaTokenUnavailable
    case tokenEndpointUnavailable
    case accessTokenUnavailable
    case tokenHTTPUnavailable
    case tokenBackendRejected
    case tokenResponseInvalid
    case mediaE2EEContextUnavailable
    case mediaConnectFailed
    case mediaSetupUnavailable
    case mediaUnsupportedIntent
    case liveKitURLInvalid
    case liveKitURLUnreachable
    case liveKitTokenRejected
    case liveKitRoomJoinFailed
    case liveKitE2EEConfigFailed
    case liveKitNetworkFailed
    case liveKitSDKError
    case liveKitUnknown
    case unknown

    init(_ error: DirectCallMediaError) {
        switch error {
        case .invalidSession, .e2eeNotReady, .keyMismatch:
            self = .invalidSessionState
        case .unsupportedIntent:
            self = .mediaUnsupportedIntent
        case .e2eeContextUnavailable:
            self = .mediaE2EEContextUnavailable
        case .tokenUnavailable:
            self = .mediaTokenUnavailable
        case .tokenEndpointUnavailable:
            self = .tokenEndpointUnavailable
        case .accessTokenUnavailable:
            self = .accessTokenUnavailable
        case .tokenHTTPUnavailable:
            self = .tokenHTTPUnavailable
        case .tokenBackendRejected:
            self = .tokenBackendRejected
        case .tokenResponseInvalid:
            self = .tokenResponseInvalid
        case .audioRouteFailed:
            self = .mediaConnectFailed
        case .mediaSetupUnavailable:
            self = .mediaSetupUnavailable
        case .liveKitURLInvalid:
            self = .liveKitURLInvalid
        case .liveKitURLUnreachable:
            self = .liveKitURLUnreachable
        case .liveKitTokenRejected:
            self = .liveKitTokenRejected
        case .liveKitRoomJoinFailed:
            self = .liveKitRoomJoinFailed
        case .liveKitE2EEConfigFailed:
            self = .liveKitE2EEConfigFailed
        case .liveKitNetworkFailed:
            self = .liveKitNetworkFailed
        case .liveKitSDKError:
            self = .liveKitSDKError
        case .liveKitUnknown:
            self = .liveKitUnknown
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
    var mediaDisconnectAttempted = false
    var mediaCleanupAttempted = false
    var liveKitClientConnectAttempted = false
    var liveKitFailureReason: DirectCallDiagnosticMediaFailureReason = .none
    var tokenRequestSeen = false
    var tokenStatus: Int?
    var tokenErrcode: String?
    var tokenReason: DirectCallDiagnosticTokenReason = .none
    var tokenEligibilityAllowed = false
    var tokenRateLimited = false
    var tokenAllocationAttempted = false
    var tokenLiveKitRoomPrecreateAttempted = false
    var tokenIssued = false
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
        mediaDisconnectAttempted = mediaDisconnectAttempted || other.mediaDisconnectAttempted
        mediaCleanupAttempted = mediaCleanupAttempted || other.mediaCleanupAttempted
        liveKitClientConnectAttempted = liveKitClientConnectAttempted || other.liveKitClientConnectAttempted
        mergeLiveKitDiagnostics(from: other)
        mergeTokenDiagnostics(from: other)
    }

    private mutating func mergeLiveKitDiagnostics(from other: Self) {
        if other.liveKitFailureReason != .none {
            liveKitFailureReason = other.liveKitFailureReason
        }
        if other.mediaFailureReason != .none {
            mediaFailureReason = other.mediaFailureReason
        }
    }

    private mutating func mergeTokenDiagnostics(from other: Self) {
        tokenRequestSeen = tokenRequestSeen || other.tokenRequestSeen
        if let tokenStatus = other.tokenStatus {
            self.tokenStatus = tokenStatus
        }
        if let tokenErrcode = other.tokenErrcode {
            self.tokenErrcode = tokenErrcode
        }
        if other.tokenReason != .none {
            tokenReason = other.tokenReason
        }
        tokenEligibilityAllowed = tokenEligibilityAllowed || other.tokenEligibilityAllowed
        tokenRateLimited = tokenRateLimited || other.tokenRateLimited
        tokenAllocationAttempted = tokenAllocationAttempted || other.tokenAllocationAttempted
        tokenLiveKitRoomPrecreateAttempted = tokenLiveKitRoomPrecreateAttempted || other.tokenLiveKitRoomPrecreateAttempted
        tokenIssued = tokenIssued || other.tokenIssued
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
            "mediaDisconnectAttempted: \(mediaDisconnectAttempted), " +
            "mediaCleanupAttempted: \(mediaCleanupAttempted), " +
            "liveKitClientConnectAttempted: \(liveKitClientConnectAttempted), " +
            "liveKitFailureReason: \(liveKitFailureReason), " +
            "tokenRequestSeen: \(tokenRequestSeen), " +
            "tokenStatus: \(tokenStatus.map(String.init) ?? "none"), " +
            "tokenErrcode: \(tokenErrcode ?? "none"), " +
            "tokenReason: \(tokenReason), " +
            "tokenEligibilityAllowed: \(tokenEligibilityAllowed), " +
            "tokenRateLimited: \(tokenRateLimited), " +
            "tokenAllocationAttempted: \(tokenAllocationAttempted), " +
            "tokenLiveKitRoomPrecreateAttempted: \(tokenLiveKitRoomPrecreateAttempted), " +
            "tokenIssued: \(tokenIssued), " +
            "mediaFailureReason: \(mediaFailureReason))"
    }

    var debugDescription: String {
        description
    }
}
#endif
