//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import KZFileWatchers
import SwiftUI

extension Notification.Name: @retroactive Codable { }

enum UITestsSignal: Codable, Equatable {
    /// An internal signal used to indicate that one side of the connection is ready.
    case ready
    /// The operation has completed successfully.
    case success
    
    case timeline(Timeline)
    enum Timeline: Codable, Equatable {
        /// Ask the app to back paginate.
        case paginate
        /// Ask the app to simulate an incoming message.
        case incomingMessage
        /// Ask the app to simulate focussing on an event ID.
        case focusOnEvent(String)
    }
    
    /// Posts a notification.
    case notification(name: Notification.Name)
    
    case accessibilityAudit(AccessibilityAudit)
    enum AccessibilityAudit: Codable, Equatable {
        /// Ask the app for the next preview.
        case nextPreview
        /// Tell the test runner about a loaded preview.
        case nextPreviewReady(name: String)
        /// Tell the test runner that there are no more previews.
        case noMorePreviews
    }

    #if DEBUG
    /// Sends a redacted native direct-call diagnostic command to the active room flow.
    case nativeDirectCallDiagnostic(NativeDirectCallDiagnosticCommandRequest)
    /// Reports a redacted native direct-call diagnostic command result.
    case nativeDirectCallDiagnosticResult(NativeDirectCallDiagnosticResult)
    /// Requests redacted native direct-call diagnostic state from the active room flow.
    case nativeDirectCallDiagnosticStatus(NativeDirectCallDiagnosticStatusRequest)
    /// Reports redacted native direct-call diagnostic state.
    case nativeDirectCallDiagnosticStatusResult(NativeDirectCallDiagnosticStatusResult)
    /// Requests a redacted production native direct-call activation dry-run for the active room.
    case nativeDirectCallProductionActivationDryRun(NativeDirectCallProductionActivationDryRunRequest)
    /// Reports a redacted production native direct-call activation dry-run for the active room.
    case nativeDirectCallProductionActivationDryRunResult(NativeDirectCallProductionActivationDryRunResult)
    /// Requests a redacted production native direct-call trigger dry-run for the active room.
    case nativeDirectCallProductionTriggerDryRun(NativeDirectCallProductionTriggerDryRunRequest)
    /// Reports a redacted production native direct-call trigger dry-run for the active room.
    case nativeDirectCallProductionTriggerDryRunResult(NativeDirectCallProductionTriggerDryRunResult)

    struct NativeDirectCallDiagnosticCommandRequest: Codable, Equatable {
        let command: NativeDirectCallDiagnosticCommand
        let correlationID: String?

        init(command: NativeDirectCallDiagnosticCommand, correlationID: String? = nil) {
            self.command = command
            self.correlationID = UITestsSignalling.sanitizedIdentifier(correlationID)
        }
    }

    enum NativeDirectCallDiagnosticCommand: String, Codable, Equatable {
        case prepare
        case startListener
        case startOutgoingAudioCall
        case acceptIncomingCall
        case hangup
        case stop
        case reset
    }

    struct NativeDirectCallDiagnosticResult: Codable, Equatable {
        let correlationID: String?
        let outcome: NativeDirectCallDiagnosticOutcome
        let reason: NativeDirectCallDiagnosticFailureReason?

        init(correlationID: String? = nil,
             outcome: NativeDirectCallDiagnosticOutcome,
             reason: NativeDirectCallDiagnosticFailureReason? = nil) {
            self.correlationID = UITestsSignalling.sanitizedIdentifier(correlationID)
            self.outcome = outcome
            self.reason = reason
        }

        static func success(_ success: NativeDirectCallDiagnosticSuccess, correlationID: String? = nil) -> Self {
            .init(correlationID: correlationID, outcome: .success(success))
        }

        static func failure(_ failure: NativeDirectCallDiagnosticFailure,
                            correlationID: String? = nil,
                            reason: NativeDirectCallDiagnosticFailureReason? = nil) -> Self {
            .init(correlationID: correlationID, outcome: .failure(failure), reason: reason)
        }
    }

    enum NativeDirectCallDiagnosticOutcome: Codable, Equatable {
        case success(NativeDirectCallDiagnosticSuccess)
        case failure(NativeDirectCallDiagnosticFailure)
    }

    enum NativeDirectCallDiagnosticSuccess: String, Codable, Equatable {
        case prepared
        case listenerStarted
        case outgoingStarted
        case incomingAccepted
        case hungUp
        case stopped
        case reset
    }

    enum NativeDirectCallDiagnosticFailure: String, Codable, Equatable {
        case disabled
        case unavailable
        case ownerDisabled
        case missingRoomControllerProvider
        case resetting
        case triggerDisabled
        case compositionUnavailable
        case noIncomingCall
        case noActiveCall
        case engineFailure
        case unknown
    }

    enum NativeDirectCallDiagnosticFailureReason: String, Codable, Equatable {
        case noActiveRoom
        case controllerUnavailable
        case diagnosticsDisabled
        case engineStateInvalid
        case missingPeer
        case signalSendFailed
        case e2eeUnavailable
        case mediaSetupUnavailable
        case mediaCredentialUnavailable
        case inviteSendFailed
        case resetting
        case unknown
    }

    struct NativeDirectCallDiagnosticStatusRequest: Codable, Equatable {
        let correlationID: String?

        init(correlationID: String? = nil) {
            self.correlationID = UITestsSignalling.sanitizedIdentifier(correlationID)
        }
    }

    struct NativeDirectCallDiagnosticStatusResult: Codable, Equatable {
        let correlationID: String?
        let status: NativeDirectCallDiagnosticStatus

        init(correlationID: String? = nil, status: NativeDirectCallDiagnosticStatus) {
            self.correlationID = UITestsSignalling.sanitizedIdentifier(correlationID)
            self.status = status
        }
    }

    struct NativeDirectCallProductionActivationDryRunRequest: Codable, Equatable {
        let correlationID: String?

        init(correlationID: String? = nil) {
            self.correlationID = UITestsSignalling.sanitizedIdentifier(correlationID)
        }
    }

    struct NativeDirectCallProductionActivationDryRunResult: Codable, Equatable {
        let correlationID: String?
        let diagnostic: NativeDirectCallProductionActivationDryRunDiagnostic

        init(correlationID: String? = nil, diagnostic: NativeDirectCallProductionActivationDryRunDiagnostic) {
            self.correlationID = UITestsSignalling.sanitizedIdentifier(correlationID)
            self.diagnostic = diagnostic
        }
    }

    struct NativeDirectCallProductionTriggerDryRunRequest: Codable, Equatable {
        let correlationID: String?

        init(correlationID: String? = nil) {
            self.correlationID = UITestsSignalling.sanitizedIdentifier(correlationID)
        }
    }

    struct NativeDirectCallProductionTriggerDryRunResult: Codable, Equatable {
        let correlationID: String?
        let diagnostic: NativeDirectCallProductionTriggerDryRunDiagnosticPayload

        init(correlationID: String? = nil, diagnostic: NativeDirectCallProductionTriggerDryRunDiagnosticPayload) {
            self.correlationID = UITestsSignalling.sanitizedIdentifier(correlationID)
            self.diagnostic = diagnostic
        }
    }

    struct NativeDirectCallProductionActivationDryRunDiagnostic: Codable, Equatable {
        let enabled: Bool
        let reason: String?
        let capabilityPresent: Bool
        let dependenciesReady: Bool
        let roomEligible: Bool
        let endpointAccepted: Bool

        init(enabled: Bool,
             reason: String?,
             capabilityPresent: Bool,
             dependenciesReady: Bool,
             roomEligible: Bool,
             endpointAccepted: Bool) {
            self.enabled = enabled
            self.reason = reason.flatMap { UITestsSignalling.sanitizedIdentifier($0) }
            self.capabilityPresent = capabilityPresent
            self.dependenciesReady = dependenciesReady
            self.roomEligible = roomEligible
            self.endpointAccepted = endpointAccepted
        }
    }

    struct NativeDirectCallProductionTriggerDryRunDiagnosticPayload: Codable, Equatable {
        let wouldStart: Bool
        let enabled: Bool
        let reason: String?
        let capabilityPresent: Bool
        let dependenciesReady: Bool
        let roomEligible: Bool
        let endpointAccepted: Bool

        init(wouldStart: Bool,
             enabled: Bool,
             reason: String?,
             capabilityPresent: Bool,
             dependenciesReady: Bool,
             roomEligible: Bool,
             endpointAccepted: Bool) {
            self.wouldStart = wouldStart
            self.enabled = enabled
            self.reason = reason
            self.capabilityPresent = capabilityPresent
            self.dependenciesReady = dependenciesReady
            self.roomEligible = roomEligible
            self.endpointAccepted = endpointAccepted
        }
    }

    struct NativeDirectCallDiagnosticStatus: Codable, Equatable {
        let state: NativeDirectCallDiagnosticStatusState
        let listenerStarted: Bool
        let hasActiveSession: Bool
        let activeSessionPhase: DirectCallDiagnosticSessionPhase
        let lastSignalEventEmitted: DirectCallDiagnosticSignalEvent?
        let lastSignalSendAttempted: Bool
        let lastSignalSendSucceeded: Bool?
        let lastSignalSendFailureReason: DirectCallDiagnosticSignalSendFailureReason?
        let lastTerminalReason: DirectCallDiagnosticTerminalReason?
        let listenerAttached: Bool
        let listenerHandleRetained: Bool
        let listenerStartCount: Int
        let timelineUpdateCount: Int
        let timelineDiffReceivedCount: Int
        let lastTimelineDiffKind: DirectCallDiagnosticTimelineDiffKind
        let lastTimelineDiffItemCount: Int
        let timelineEventReceivedCount: Int
        let directCallEventTypeSeenCount: Int
        let envelopeExtractedCount: Int
        let envelopeDeliveredToEngineCount: Int
        let lastReceiveEventKind: DirectCallDiagnosticReceiveEventKind
        let lastEnvelopeRejectedReason: DirectCallDiagnosticEnvelopeRejectedReason
        let lastReceiveFailureReason: DirectCallDiagnosticReceiveFailureReason?
        let sendRoomFingerprint: String?
        let receiveRoomFingerprint: String?
        let mediaFactoryInjected: Bool
        let mediaCredentialProviderAvailable: Bool
        let mediaE2EEProviderAvailable: Bool
        let mediaKeyHandleAvailable: Bool
        let mediaKeyBridgeHit: Bool
        let mediaConnectAttempted: Bool
        let liveKitClientConnectAttempted: Bool
        let mediaFailureReason: DirectCallDiagnosticMediaFailureReason

        init(state: NativeDirectCallDiagnosticStatusState,
             listenerStarted: Bool,
             hasActiveSession: Bool,
             activeSessionPhase: DirectCallDiagnosticSessionPhase = .none,
             lastSignalEventEmitted: DirectCallDiagnosticSignalEvent? = nil,
             lastSignalSendAttempted: Bool = false,
             lastSignalSendSucceeded: Bool? = nil,
             lastSignalSendFailureReason: DirectCallDiagnosticSignalSendFailureReason? = nil,
             lastTerminalReason: DirectCallDiagnosticTerminalReason? = nil,
             listenerAttached: Bool = false,
             listenerHandleRetained: Bool = false,
             listenerStartCount: Int = 0,
             timelineUpdateCount: Int = 0,
             timelineDiffReceivedCount: Int = 0,
             lastTimelineDiffKind: DirectCallDiagnosticTimelineDiffKind = .none,
             lastTimelineDiffItemCount: Int = 0,
             timelineEventReceivedCount: Int = 0,
             directCallEventTypeSeenCount: Int = 0,
             envelopeExtractedCount: Int = 0,
             envelopeDeliveredToEngineCount: Int = 0,
             lastReceiveEventKind: DirectCallDiagnosticReceiveEventKind = .none,
             lastEnvelopeRejectedReason: DirectCallDiagnosticEnvelopeRejectedReason = .none,
             lastReceiveFailureReason: DirectCallDiagnosticReceiveFailureReason? = nil,
             sendRoomFingerprint: String? = nil,
             receiveRoomFingerprint: String? = nil,
             mediaFactoryInjected: Bool = false,
             mediaCredentialProviderAvailable: Bool = false,
             mediaE2EEProviderAvailable: Bool = false,
             mediaKeyHandleAvailable: Bool = false,
             mediaKeyBridgeHit: Bool = false,
             mediaConnectAttempted: Bool = false,
             liveKitClientConnectAttempted: Bool = false,
             mediaFailureReason: DirectCallDiagnosticMediaFailureReason = .none) {
            self.state = state
            self.listenerStarted = listenerStarted
            self.hasActiveSession = hasActiveSession
            self.activeSessionPhase = activeSessionPhase
            self.lastSignalEventEmitted = lastSignalEventEmitted
            self.lastSignalSendAttempted = lastSignalSendAttempted
            self.lastSignalSendSucceeded = lastSignalSendSucceeded
            self.lastSignalSendFailureReason = lastSignalSendFailureReason
            self.lastTerminalReason = lastTerminalReason
            self.listenerAttached = listenerAttached
            self.listenerHandleRetained = listenerHandleRetained
            self.listenerStartCount = listenerStartCount
            self.timelineUpdateCount = timelineUpdateCount
            self.timelineDiffReceivedCount = timelineDiffReceivedCount
            self.lastTimelineDiffKind = lastTimelineDiffKind
            self.lastTimelineDiffItemCount = lastTimelineDiffItemCount
            self.timelineEventReceivedCount = timelineEventReceivedCount
            self.directCallEventTypeSeenCount = directCallEventTypeSeenCount
            self.envelopeExtractedCount = envelopeExtractedCount
            self.envelopeDeliveredToEngineCount = envelopeDeliveredToEngineCount
            self.lastReceiveEventKind = lastReceiveEventKind
            self.lastEnvelopeRejectedReason = lastEnvelopeRejectedReason
            self.lastReceiveFailureReason = lastReceiveFailureReason
            self.sendRoomFingerprint = sendRoomFingerprint.flatMap { UITestsSignalling.sanitizedIdentifier($0) }
            self.receiveRoomFingerprint = receiveRoomFingerprint.flatMap { UITestsSignalling.sanitizedIdentifier($0) }
            self.mediaFactoryInjected = mediaFactoryInjected
            self.mediaCredentialProviderAvailable = mediaCredentialProviderAvailable
            self.mediaE2EEProviderAvailable = mediaE2EEProviderAvailable
            self.mediaKeyHandleAvailable = mediaKeyHandleAvailable
            self.mediaKeyBridgeHit = mediaKeyBridgeHit
            self.mediaConnectAttempted = mediaConnectAttempted
            self.liveKitClientConnectAttempted = liveKitClientConnectAttempted
            self.mediaFailureReason = mediaFailureReason
        }
    }

    enum NativeDirectCallDiagnosticStatusState: String, Codable, Equatable {
        case unavailable
        case disabled
        case idle
        case ringing
        case connecting
        case active
        case terminal
        case resetting
        case failed
    }
    #endif
}

#if DEBUG
extension UITestsSignal.NativeDirectCallDiagnosticCommandRequest {
    static let prepare = Self(command: .prepare)
    static let startListener = Self(command: .startListener)
    static let startOutgoingAudioCall = Self(command: .startOutgoingAudioCall)
    static let acceptIncomingCall = Self(command: .acceptIncomingCall)
    static let hangup = Self(command: .hangup)
    static let stop = Self(command: .stop)
    static let reset = Self(command: .reset)

    var roomFlowCommand: NativeDirectCallRoomDiagnosticCommand {
        switch command {
        case .prepare:
            .prepare
        case .startListener:
            .startListener
        case .startOutgoingAudioCall:
            .startOutgoingAudioCall
        case .acceptIncomingCall:
            .acceptIncomingCall
        case .hangup:
            .hangup
        case .stop:
            .stop
        case .reset:
            .reset
        }
    }
}

extension UITestsSignal.NativeDirectCallDiagnosticResult {
    init(correlationID: String? = nil, _ result: NativeDirectCallRoomDiagnosticCommandResult) {
        switch result {
        case .prepared:
            self = .success(.prepared, correlationID: correlationID)
        case .listenerStarted:
            self = .success(.listenerStarted, correlationID: correlationID)
        case .outgoingStarted:
            self = .success(.outgoingStarted, correlationID: correlationID)
        case .incomingAccepted:
            self = .success(.incomingAccepted, correlationID: correlationID)
        case .hungUp:
            self = .success(.hungUp, correlationID: correlationID)
        case .stopped:
            self = .success(.stopped, correlationID: correlationID)
        case .reset:
            self = .success(.reset, correlationID: correlationID)
        case .failed(let error):
            self = .failure(.init(error), correlationID: correlationID, reason: .init(error))
        }
    }
}

extension UITestsSignal.NativeDirectCallDiagnosticStatusResult {
    init(correlationID: String? = nil, _ status: NativeDirectCallRoomDiagnosticStatus) {
        self.init(correlationID: correlationID,
                  status: .init(status))
    }
}

extension UITestsSignal.NativeDirectCallProductionActivationDryRunResult {
    init(correlationID: String? = nil, _ diagnostic: DirectCallProductionActivationDryRunDiagnostic) {
        self.init(correlationID: correlationID,
                  diagnostic: .init(diagnostic))
    }
}

extension UITestsSignal.NativeDirectCallProductionTriggerDryRunResult {
    init(correlationID: String? = nil, _ diagnostic: NativeDirectCallProductionTriggerDryRunDiagnostic) {
        self.init(correlationID: correlationID,
                  diagnostic: .init(diagnostic))
    }
}

extension UITestsSignal.NativeDirectCallProductionActivationDryRunDiagnostic {
    init(_ diagnostic: DirectCallProductionActivationDryRunDiagnostic) {
        self.init(enabled: diagnostic.isEnabled,
                  reason: diagnostic.disabledReason?.description,
                  capabilityPresent: diagnostic.isCapabilityPresent,
                  dependenciesReady: diagnostic.areDependenciesReady,
                  roomEligible: diagnostic.isRoomEligible,
                  endpointAccepted: diagnostic.isEndpointAccepted)
    }
}

extension UITestsSignal.NativeDirectCallProductionTriggerDryRunDiagnosticPayload {
    init(_ diagnostic: NativeDirectCallProductionTriggerDryRunDiagnostic) {
        self.init(wouldStart: diagnostic.wouldStart,
                  enabled: diagnostic.isEnabled,
                  reason: diagnostic.blockedReason?.description,
                  capabilityPresent: diagnostic.isCapabilityPresent,
                  dependenciesReady: diagnostic.areDependenciesReady,
                  roomEligible: diagnostic.isRoomEligible,
                  endpointAccepted: diagnostic.isEndpointAccepted)
    }
}

extension UITestsSignal.NativeDirectCallDiagnosticStatus {
    init(_ status: NativeDirectCallRoomDiagnosticStatus) {
        self.init(state: .init(status.state),
                  listenerStarted: status.listenerStarted,
                  hasActiveSession: status.hasActiveSession,
                  activeSessionPhase: status.activeSessionPhase,
                  lastSignalEventEmitted: status.lastSignalEventEmitted,
                  lastSignalSendAttempted: status.lastSignalSendAttempted,
                  lastSignalSendSucceeded: status.lastSignalSendSucceeded,
                  lastSignalSendFailureReason: status.lastSignalSendFailureReason,
                  lastTerminalReason: status.lastTerminalReason,
                  listenerAttached: status.listenerAttached,
                  listenerHandleRetained: status.listenerHandleRetained,
                  listenerStartCount: status.listenerStartCount,
                  timelineUpdateCount: status.timelineUpdateCount,
                  timelineDiffReceivedCount: status.timelineDiffReceivedCount,
                  lastTimelineDiffKind: status.lastTimelineDiffKind,
                  lastTimelineDiffItemCount: status.lastTimelineDiffItemCount,
                  timelineEventReceivedCount: status.timelineEventReceivedCount,
                  directCallEventTypeSeenCount: status.directCallEventTypeSeenCount,
                  envelopeExtractedCount: status.envelopeExtractedCount,
                  envelopeDeliveredToEngineCount: status.envelopeDeliveredToEngineCount,
                  lastReceiveEventKind: status.lastReceiveEventKind,
                  lastEnvelopeRejectedReason: status.lastEnvelopeRejectedReason,
                  lastReceiveFailureReason: status.lastReceiveFailureReason,
                  sendRoomFingerprint: status.sendRoomFingerprint,
                  receiveRoomFingerprint: status.receiveRoomFingerprint,
                  mediaFactoryInjected: status.mediaFactoryInjected,
                  mediaCredentialProviderAvailable: status.mediaCredentialProviderAvailable,
                  mediaE2EEProviderAvailable: status.mediaE2EEProviderAvailable,
                  mediaKeyHandleAvailable: status.mediaKeyHandleAvailable,
                  mediaKeyBridgeHit: status.mediaKeyBridgeHit,
                  mediaConnectAttempted: status.mediaConnectAttempted,
                  liveKitClientConnectAttempted: status.liveKitClientConnectAttempted,
                  mediaFailureReason: status.mediaFailureReason)
    }
}

extension UITestsSignal.NativeDirectCallDiagnosticStatusState {
    init(_ state: NativeDirectCallRoomDiagnosticStatusState) {
        switch state {
        case .unavailable:
            self = .unavailable
        case .disabled:
            self = .disabled
        case .idle:
            self = .idle
        case .ringing:
            self = .ringing
        case .connecting:
            self = .connecting
        case .active:
            self = .active
        case .terminal:
            self = .terminal
        case .resetting:
            self = .resetting
        case .failed:
            self = .failed
        }
    }
}

extension UITestsSignal.NativeDirectCallDiagnosticFailure {
    init(_ error: NativeDirectCallRoomDeveloperCommandError) {
        switch error {
        case .disabled:
            self = .disabled
        case .unavailable:
            self = .unavailable
        case .owner(let ownerError):
            self = .init(ownerError)
        }
    }

    init(_ error: NativeDirectCallRoomFlowOwnerError) {
        switch error {
        case .disabled:
            self = .ownerDisabled
        case .missingRoomControllerProvider:
            self = .missingRoomControllerProvider
        case .resetting:
            self = .resetting
        case .trigger(let triggerError):
            self = .init(triggerError)
        }
    }

    init(_ error: NativeDirectCallDeveloperRoomTriggerError) {
        switch error {
        case .disabled:
            self = .triggerDisabled
        case .control(let controlError):
            self = .init(controlError)
        }
    }

    init(_ error: NativeDirectCallRoomControlError) {
        switch error {
        case .composition:
            self = .compositionUnavailable
        case .noIncomingCall:
            self = .noIncomingCall
        case .noActiveCall:
            self = .noActiveCall
        case .engine:
            self = .engineFailure
        }
    }
}

extension UITestsSignal.NativeDirectCallDiagnosticFailureReason {
    init(_ error: NativeDirectCallRoomDeveloperCommandError) {
        switch error {
        case .disabled:
            self = .diagnosticsDisabled
        case .unavailable:
            self = .noActiveRoom
        case .owner(let ownerError):
            self = .init(ownerError)
        }
    }

    init(_ error: NativeDirectCallRoomFlowOwnerError) {
        switch error {
        case .disabled:
            self = .diagnosticsDisabled
        case .missingRoomControllerProvider:
            self = .controllerUnavailable
        case .resetting:
            self = .resetting
        case .trigger(let triggerError):
            self = .init(triggerError)
        }
    }

    init(_ error: NativeDirectCallDeveloperRoomTriggerError) {
        switch error {
        case .disabled:
            self = .diagnosticsDisabled
        case .control(let controlError):
            self = .init(controlError)
        }
    }

    init(_ error: NativeDirectCallRoomControlError) {
        switch error {
        case .composition(let compositionError):
            self = .init(compositionError)
        case .noIncomingCall, .noActiveCall:
            self = .engineStateInvalid
        case .engine(let engineError):
            self = .init(engineError)
        }
    }

    init(_ error: JoinedRoomNativeDirectCallCompositionError) {
        switch error {
        case .composition(.disabled):
            self = .diagnosticsDisabled
        case .composition(.invalidOwnUserID), .composition(.invalidRoomID), .unknownRoomMetadata:
            self = .noActiveRoom
        case .composition(.nonDirectRoom), .composition(.nonEncryptedRoom):
            self = .controllerUnavailable
        case .composition(.missingPeer):
            self = .missingPeer
        case .composition(.missingSignalTransport), .missingSignalSender, .missingTimelineListener:
            self = .signalSendFailed
        }
    }

    init(_ error: NativeDirectCallCompositionError) {
        switch error {
        case .disabled:
            self = .diagnosticsDisabled
        case .invalidOwnUserID, .invalidRoomID:
            self = .noActiveRoom
        case .missingSignalTransport:
            self = .signalSendFailed
        case .nonDirectRoom, .nonEncryptedRoom:
            self = .controllerUnavailable
        case .missingPeer:
            self = .missingPeer
        }
    }

    init(_ error: DirectCallEngineError) {
        switch error {
        case .invalidRoomID:
            self = .noActiveRoom
        case .invalidPeer, .invalidSender:
            self = .missingPeer
        case .invalidEncryptionTransition:
            self = .e2eeUnavailable
        case .mediaConnectionFailed:
            self = .mediaSetupUnavailable
        case .staleOrUnknownEvent,
             .roomMismatch,
             .callIDMismatch,
             .sessionAlreadyActive,
             .invalidTransition,
             .invalidCallID,
             .invalidIntent:
            self = .engineStateInvalid
        }
    }
}
#endif

enum UITestsSignalError: String, LocalizedError {
    /// The app client failed to start as the tests client isn't ready.
    case testsClientNotReady
    /// Failed to send a signal as a connection hasn't been established.
    case notConnected
    
    var errorDescription: String? {
        "UITestsSignalError.\(rawValue)"
    }
}

enum UITestsSignalling {
    static let channelEnvironmentKey = "UI_TESTS_SIGNALLING_CHANNEL"

    static func sanitizedIdentifier(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        var result = ""
        var previousCharacterWasSeparator = false
        for character in value {
            guard result.count < 48 else {
                break
            }

            if character.isLetter || character.isNumber || character == "_" || character == "-" {
                result.append(character)
                previousCharacterWasSeparator = false
            } else if !previousCharacterWasSeparator {
                result.append("-")
                previousCharacterWasSeparator = true
            }
        }

        let sanitized = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return sanitized.isEmpty ? nil : sanitized
    }

    /// A two-way file-based signalling client that can be used to signal between the app and the UI tests runner.
    /// The connection should be created as follows:
    /// - Create a `Client` in `tests` mode in your UI tests before launching the app. It will start listening for signals.
    /// - Within the app, create a `Client` in `app` mode. This will check that the tests are ready and echo back that the app is too.
    /// - Call `waitForApp()` in the tests when you need to send the signal. This will suspend execution until the app has signalled it is ready.
    /// - The two `Client` objects can now be used for two-way signalling.
    class Client {
        /// The file watcher responsible for receiving signals.
        private let fileWatcher: FileWatcher.Local
        private let fileURL: URL
        
        /// The file name used for the connection.
        ///
        /// The device name is included to allow UI tests to run on multiple devices simultaneously.
        /// When using parallel execution, each execution will spawn a simulator clone with its own unique name.
        static func fileURL(deviceName: String = UIDevice.current.name,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
            let directory = URL(filePath: "/Users/Shared")
            let sanitizedDeviceName = deviceName.replacing(" ", with: "-")
            var fileName = "UITestsSignalling-\(sanitizedDeviceName)"
            if let channel = UITestsSignalling.sanitizedIdentifier(environment[UITestsSignalling.channelEnvironmentKey]) {
                fileName += "-\(channel)"
            }
            return directory.appending(component: fileName)
        }
        
        /// A mode that defines the behaviour of the client.
        enum Mode: Codable { case app, tests }
        /// The mode that the client is using.
        let mode: Mode
        
        /// A publisher the will be sent every time a new signal is received.
        let signals = PassthroughSubject<UITestsSignal, Never>()
        
        /// Whether or not the client has established a connection.
        private(set) var isConnected = false
        
        /// Creates a new signalling `Client`.
        init(mode: Mode,
             deviceName: String = UIDevice.current.name,
             environment: [String: String] = ProcessInfo.processInfo.environment) throws {
            fileURL = Self.fileURL(deviceName: deviceName, environment: environment)
            fileWatcher = .init(path: fileURL.path())
            self.mode = mode
            
            switch mode {
            case .tests:
                // The tests client is started first and writes to the file saying it is ready.
                try rawMessage(.ready).write(to: fileURL, atomically: false, encoding: .utf8)
            case .app:
                // The app client is started second and checks that there is a ready signal from the tests.
                guard try String(contentsOf: fileURL, encoding: .utf8) == Message(mode: .tests, signal: .ready).rawValue else { throw UITestsSignalError.testsClientNotReady }
                isConnected = true
                // The app client then echoes back to the tests that it is now ready.
                try send(.ready)
            }
            
            try fileWatcher.start { [weak self] result in
                self?.handleFileRefresh(result)
            }
        }
        
        /// Suspends execution until the app's Client has signalled that it's ready.
        func waitForApp() async {
            guard mode == .tests else { fatalError("The app can't wait for itself.") }
            
            guard !isConnected else { return }
            await _ = signals.values.first { $0 == .ready }
            NSLog("UITestsSignalling: Connected to app.")
        }

        /// Stops listening for signals.
        func stop() throws {
            try fileWatcher.stop()
        }

        /// Sends a signal.
        func send(_ signal: UITestsSignal) throws {
            guard isConnected else { throw UITestsSignalError.notConnected }
            
            let rawMessage = rawMessage(signal)
            try rawMessage.write(to: fileURL, atomically: false, encoding: .utf8)
            NSLog("UITestsSignalling: Sent \(rawMessage)")
        }
        
        /// The signal formatted as a complete message string, including the identifier for this sender.
        private func rawMessage(_ signal: UITestsSignal) -> String {
            Message(mode: mode, signal: signal).rawValue
        }
        
        /// The complete data that is serialised to disk for signalling.
        /// This consists of the signal along with an identifier for the sender.
        private struct Message: Codable {
            let mode: Mode
            let signal: UITestsSignal
            
            init(mode: Mode, signal: UITestsSignal) {
                self.mode = mode
                self.signal = signal
            }
            
            var rawValue: String {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                
                guard let data = try? encoder.encode(self),
                      let rawMessage = String(data: data, encoding: .utf8) else {
                    return "unknown"
                }
                return rawMessage
            }
            
            init?(rawValue: String) {
                guard let data = rawValue.data(using: .utf8),
                      let value = try? JSONDecoder().decode(Self.self, from: data) else {
                    return nil
                }
                self = value
            }
        }
        
        /// Handles a file refresh to receive a new signal.
        fileprivate func handleFileRefresh(_ result: FileWatcher.RefreshResult) {
            switch result {
            case .noChanges:
                guard let data = try? Data(contentsOf: fileURL) else { return }
                processFileData(data)
            case .updated(let data):
                processFileData(data)
            }
        }
        
        /// Processes string data from the file and publishes its signal.
        private func processFileData(_ data: Data) {
            guard let rawMessage = String(data: data, encoding: .utf8),
                  let message = Message(rawValue: rawMessage),
                  message.mode != mode // Filter out messages sent by this client.
            else { return }
            
            if message.signal == .ready {
                isConnected = true
            }
            
            signals.send(message.signal)
            
            NSLog("UITestsSignalling: Received \(rawMessage)")
        }
    }
}
