//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

struct NativeDirectCallRoomDeveloperCommandConfiguration: Equatable {
    let isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

#if DEBUG
enum NativeDirectCallRoomDiagnosticCommand: Equatable {
    case prepare
    case startListener
    case startOutgoingAudioCall
    case acceptIncomingCall
    case hangup
    case stop
    case reset
}

struct NativeDirectCallRoomDiagnosticSession: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let callID: String
    let roomID: String
    let peerUserID: String
    let direction: DirectCallDirection
    let intent: DirectCallIntent
    let state: DirectCallState
    let encryptionState: DirectCallEncryptionState

    init(_ session: DirectCallSession) {
        callID = session.callID
        roomID = session.roomID
        peerUserID = session.peerUserID
        direction = session.direction
        intent = session.intent
        state = session.state
        encryptionState = session.encryptionState
    }

    var description: String {
        "NativeDirectCallRoomDiagnosticSession(hasCallID: \(!callID.isEmpty), hasRoomID: \(!roomID.isEmpty), hasPeerUserID: \(!peerUserID.isEmpty), direction: \(direction), intent: \(intent), state: \(state), encryptionState: \(encryptionState))"
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallRoomDiagnosticCommandResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case prepared
    case listenerStarted
    case outgoingStarted(NativeDirectCallRoomDiagnosticSession)
    case incomingAccepted(NativeDirectCallRoomDiagnosticSession)
    case hungUp(NativeDirectCallRoomDiagnosticSession)
    case stopped
    case reset
    case failed(NativeDirectCallRoomDeveloperCommandError)

    var description: String {
        switch self {
        case .prepared:
            "prepared"
        case .listenerStarted:
            "listenerStarted"
        case .outgoingStarted(let session):
            "outgoingStarted(\(session))"
        case .incomingAccepted(let session):
            "incomingAccepted(\(session))"
        case .hungUp(let session):
            "hungUp(\(session))"
        case .stopped:
            "stopped"
        case .reset:
            "reset"
        case .failed(let error):
            "failed(\(error))"
        }
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallRoomDiagnosticStatusState: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case unavailable
    case disabled
    case idle
    case ringing
    case connecting
    case active
    case terminal
    case resetting
    case failed

    init(_ callState: DirectCallState) {
        switch callState {
        case .idle:
            self = .idle
        case .outgoingRinging, .incomingRinging:
            self = .ringing
        case .connecting, .ending:
            self = .connecting
        case .activeAudio, .activeVideo:
            self = .active
        case .ended, .missed, .cancelled:
            self = .terminal
        case .failed:
            self = .failed
        }
    }

    var description: String {
        switch self {
        case .unavailable:
            "unavailable"
        case .disabled:
            "disabled"
        case .idle:
            "idle"
        case .ringing:
            "ringing"
        case .connecting:
            "connecting"
        case .active:
            "active"
        case .terminal:
            "terminal"
        case .resetting:
            "resetting"
        case .failed:
            "failed"
        }
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallRoomDiagnosticStatus: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let state: NativeDirectCallRoomDiagnosticStatusState
    let listenerStarted: Bool
    let hasActiveSession: Bool
    let activeSessionPhase: DirectCallDiagnosticSessionPhase
    let lastSignalEventEmitted: DirectCallDiagnosticSignalEvent?
    let lastSignalSendAttempted: Bool
    let lastSignalSendSucceeded: Bool?
    let lastSignalSendFailureReason: DirectCallDiagnosticSignalSendFailureReason?
    let lastTerminalReason: DirectCallDiagnosticTerminalReason?

    init(state: NativeDirectCallRoomDiagnosticStatusState,
         listenerStarted: Bool,
         hasActiveSession: Bool,
         diagnosticSnapshot: DirectCallDiagnosticSnapshot = .empty) {
        self.state = state
        self.listenerStarted = listenerStarted
        self.hasActiveSession = hasActiveSession
        activeSessionPhase = diagnosticSnapshot.activeSessionPhase
        lastSignalEventEmitted = diagnosticSnapshot.lastSignalEventEmitted
        lastSignalSendAttempted = diagnosticSnapshot.lastSignalSendAttempted
        lastSignalSendSucceeded = diagnosticSnapshot.lastSignalSendSucceeded
        lastSignalSendFailureReason = diagnosticSnapshot.lastSignalSendFailureReason
        lastTerminalReason = diagnosticSnapshot.lastTerminalReason
    }

    static let unavailable = Self(state: .unavailable, listenerStarted: false, hasActiveSession: false)
    static let disabled = Self(state: .disabled, listenerStarted: false, hasActiveSession: false)

    var description: String {
        "NativeDirectCallRoomDiagnosticStatus(" + [
            "state: \(state)",
            "listenerStarted: \(listenerStarted)",
            "hasActiveSession: \(hasActiveSession)",
            "activeSessionPhase: \(activeSessionPhase)",
            "lastSignalEventEmitted: \(String(describing: lastSignalEventEmitted))",
            "lastSignalSendAttempted: \(lastSignalSendAttempted)",
            "lastSignalSendSucceeded: \(String(describing: lastSignalSendSucceeded))",
            "lastSignalSendFailureReason: \(String(describing: lastSignalSendFailureReason))",
            "lastTerminalReason: \(String(describing: lastTerminalReason))"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}
#endif

enum NativeDirectCallRoomDeveloperCommandError: Error, Equatable {
    case disabled
    case unavailable
    case owner(NativeDirectCallRoomFlowOwnerError)
}

@MainActor
protocol NativeDirectCallRoomDeveloperCommanding: AnyObject {
    var isListenerStarted: Bool { get }
    var activeSession: DirectCallSession? { get }
    #if DEBUG
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        get
    }
    #endif

    func prepare() -> Result<NativeDirectCallComposition, NativeDirectCallRoomDeveloperCommandError>
    func startListener() async -> Result<NativeDirectCallComposition, NativeDirectCallRoomDeveloperCommandError>
    func startOutgoingAudioCall() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError>
    func acceptIncomingCall() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError>
    func hangup() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError>
    func stop() -> Result<Void, NativeDirectCallRoomDeveloperCommandError>
    func reset() async -> Result<Void, NativeDirectCallRoomDeveloperCommandError>
    #if DEBUG
    func status() -> NativeDirectCallRoomDiagnosticStatus
    #endif
}

@MainActor
final class NativeDirectCallRoomDeveloperCommandRouter: NativeDirectCallRoomDeveloperCommanding {
    private let configuration: NativeDirectCallRoomDeveloperCommandConfiguration
    private let ownerProvider: () -> NativeDirectCallRoomFlowOwning?

    var isListenerStarted: Bool {
        guard configuration.isEnabled, let owner = ownerProvider() else {
            return false
        }

        return owner.isListenerStarted
    }

    var activeSession: DirectCallSession? {
        guard configuration.isEnabled, let owner = ownerProvider() else {
            return nil
        }

        return owner.activeSession
    }

    #if DEBUG
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        guard configuration.isEnabled, let owner = ownerProvider() else {
            return .empty
        }

        return owner.diagnosticSnapshot
    }
    #endif

    init(configuration: NativeDirectCallRoomDeveloperCommandConfiguration = .init(),
         ownerProvider: @escaping () -> NativeDirectCallRoomFlowOwning?) {
        self.configuration = configuration
        self.ownerProvider = ownerProvider
    }

    func prepare() -> Result<NativeDirectCallComposition, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return owner.prepare()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func startListener() async -> Result<NativeDirectCallComposition, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return await owner.startListener()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func startOutgoingAudioCall() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return await owner.startOutgoingAudioCall()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func acceptIncomingCall() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return await owner.acceptIncomingCall()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func hangup() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return await owner.hangup()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func stop() -> Result<Void, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            owner.stop()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func reset() async -> Result<Void, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            await owner.reset()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    #if DEBUG
    func status() -> NativeDirectCallRoomDiagnosticStatus {
        guard configuration.isEnabled else {
            return .disabled
        }

        guard let owner = ownerProvider() else {
            return .unavailable
        }

        let activeSession = owner.activeSession
        let diagnosticSnapshot = owner.diagnosticSnapshot
        if owner.isResetting {
            return .init(state: .resetting,
                         listenerStarted: owner.isListenerStarted,
                         hasActiveSession: activeSession != nil,
                         diagnosticSnapshot: diagnosticSnapshot)
        }

        guard let activeSession else {
            return .init(state: .idle,
                         listenerStarted: owner.isListenerStarted,
                         hasActiveSession: false,
                         diagnosticSnapshot: diagnosticSnapshot)
        }

        return .init(state: .init(activeSession.state),
                     listenerStarted: owner.isListenerStarted,
                     hasActiveSession: true,
                     diagnosticSnapshot: diagnosticSnapshot)
    }
    #endif

    private func makeOwner() -> Result<NativeDirectCallRoomFlowOwning, NativeDirectCallRoomDeveloperCommandError> {
        guard configuration.isEnabled else {
            return .failure(.disabled)
        }

        guard let owner = ownerProvider() else {
            return .failure(.unavailable)
        }

        return .success(owner)
    }
}
