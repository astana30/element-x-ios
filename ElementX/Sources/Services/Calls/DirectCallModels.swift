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
        case .answered, .ended, .muted:
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
