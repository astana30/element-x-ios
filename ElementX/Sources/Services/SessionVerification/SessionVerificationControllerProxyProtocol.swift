//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import MatrixRustSDK

enum SessionVerificationControllerProxyError: Error {
    case failedAcknowledgingVerificationRequest
    case failedAcceptingVerificationRequest
    case failedRequestingVerification
    case failedStartingSasVerification
    case failedApprovingVerification
    case failedDecliningVerification
    case failedCancellingVerification
}

enum SessionVerificationControllerProxyAction: Equatable {
    case receivedVerificationRequest(details: SessionVerificationRequestDetails)
    case acceptedVerificationRequest
    case startedSasVerification
    case receivedVerificationData([SessionVerificationEmoji])
    case finished
    case cancelled
    case failed
}

enum SessionVerificationControllerDiagnosticFlowState: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case unavailable
    case idle
    case requestReceived
    case requestAcknowledged
    case requestAccepted
    case verificationRequested
    case sasStarted
    case emojiReceived
    case finished
    case cancelled
    case failed

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum SessionVerificationControllerDiagnosticErrorReason: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case acknowledgeFailed
    case acceptFailed
    case requestFailed
    case startSASFailed
    case approveFailed
    case declineFailed
    case cancelFailed
    case callbackFailed
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct SessionVerificationControllerDiagnosticSnapshot: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let verificationRequestPending: Bool
    let verificationFlowState: SessionVerificationControllerDiagnosticFlowState
    let lastVerificationErrorReason: SessionVerificationControllerDiagnosticErrorReason

    init(verificationRequestPending: Bool = false,
         verificationFlowState: SessionVerificationControllerDiagnosticFlowState = .idle,
         lastVerificationErrorReason: SessionVerificationControllerDiagnosticErrorReason = .none) {
        self.verificationRequestPending = verificationRequestPending
        self.verificationFlowState = verificationFlowState
        self.lastVerificationErrorReason = lastVerificationErrorReason
    }

    static let unavailable = Self(verificationFlowState: .unavailable)

    var description: String {
        "SessionVerificationControllerDiagnosticSnapshot(verificationRequestPending: \(verificationRequestPending), verificationFlowState: \(verificationFlowState), lastVerificationErrorReason: \(lastVerificationErrorReason))"
    }

    var debugDescription: String {
        description
    }
}

protocol SessionVerificationControllerDiagnosticProviding {
    var diagnosticSnapshot: SessionVerificationControllerDiagnosticSnapshot { get }
}

enum SessionVerificationControllerDiagnosticCommand: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case status
    case accept
    case startSAS
    case cancel

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum SessionVerificationControllerDiagnosticCommandOutcome: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case status
    case succeeded
    case blocked
    case failed

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum SessionVerificationControllerDiagnosticCommandReason: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case unavailable
    case requestNotPending
    case invalidFlowState
    case acceptFailed
    case startSASFailed
    case cancelFailed
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct SessionVerificationControllerDiagnosticCommandResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let outcome: SessionVerificationControllerDiagnosticCommandOutcome
    let reason: SessionVerificationControllerDiagnosticCommandReason
    let snapshot: SessionVerificationControllerDiagnosticSnapshot

    init(outcome: SessionVerificationControllerDiagnosticCommandOutcome,
         reason: SessionVerificationControllerDiagnosticCommandReason = .none,
         snapshot: SessionVerificationControllerDiagnosticSnapshot) {
        self.outcome = outcome
        self.reason = reason
        self.snapshot = snapshot
    }

    static let unavailable = Self(outcome: .failed,
                                  reason: .unavailable,
                                  snapshot: .unavailable)

    var requestPending: Bool {
        snapshot.verificationRequestPending
    }

    var sasStarted: Bool {
        switch snapshot.verificationFlowState {
        case .sasStarted, .emojiReceived:
            true
        default:
            false
        }
    }

    var emojiReceived: Bool {
        snapshot.verificationFlowState == .emojiReceived
    }

    var finished: Bool {
        snapshot.verificationFlowState == .finished
    }

    var cancelled: Bool {
        snapshot.verificationFlowState == .cancelled
    }

    var failed: Bool {
        snapshot.verificationFlowState == .failed
    }

    var description: String {
        "SessionVerificationControllerDiagnosticCommandResult(" + [
            "outcome: \(outcome)",
            "reason: \(reason)",
            "requestPending: \(requestPending)",
            "flowState: \(snapshot.verificationFlowState)",
            "sasStarted: \(sasStarted)",
            "emojiReceived: \(emojiReceived)",
            "finished: \(finished)",
            "cancelled: \(cancelled)",
            "failed: \(failed)",
            "lastErrorReason: \(snapshot.lastVerificationErrorReason)"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
struct SessionVerificationControllerDiagnosticCommandDriver {
    private let controller: SessionVerificationControllerProxyProtocol?

    init(controller: SessionVerificationControllerProxyProtocol?) {
        self.controller = controller
    }

    func execute(_ command: SessionVerificationControllerDiagnosticCommand) async -> SessionVerificationControllerDiagnosticCommandResult {
        guard let controller else {
            return .unavailable
        }

        switch command {
        case .status:
            return .init(outcome: .status, snapshot: snapshot(from: controller))
        case .accept:
            return await accept(controller)
        case .startSAS:
            return await startSAS(controller)
        case .cancel:
            return await cancel(controller)
        }
    }

    private func accept(_ controller: SessionVerificationControllerProxyProtocol) async -> SessionVerificationControllerDiagnosticCommandResult {
        let currentSnapshot = snapshot(from: controller)
        guard currentSnapshot.verificationRequestPending else {
            return .init(outcome: .blocked,
                         reason: .requestNotPending,
                         snapshot: currentSnapshot)
        }

        guard currentSnapshot.verificationFlowState == .requestReceived ||
            currentSnapshot.verificationFlowState == .requestAcknowledged ||
            currentSnapshot.verificationFlowState == .verificationRequested else {
            return .init(outcome: .blocked,
                         reason: .invalidFlowState,
                         snapshot: currentSnapshot)
        }

        switch await controller.acceptVerificationRequest() {
        case .success:
            return .init(outcome: .succeeded, snapshot: snapshot(from: controller))
        case .failure:
            return .init(outcome: .failed,
                         reason: .acceptFailed,
                         snapshot: snapshot(from: controller))
        }
    }

    private func startSAS(_ controller: SessionVerificationControllerProxyProtocol) async -> SessionVerificationControllerDiagnosticCommandResult {
        let currentSnapshot = snapshot(from: controller)
        guard currentSnapshot.verificationRequestPending else {
            return .init(outcome: .blocked,
                         reason: .requestNotPending,
                         snapshot: currentSnapshot)
        }

        guard currentSnapshot.verificationFlowState == .requestAccepted else {
            return .init(outcome: .blocked,
                         reason: .invalidFlowState,
                         snapshot: currentSnapshot)
        }

        switch await controller.startSasVerification() {
        case .success:
            return .init(outcome: .succeeded, snapshot: snapshot(from: controller))
        case .failure:
            return .init(outcome: .failed,
                         reason: .startSASFailed,
                         snapshot: snapshot(from: controller))
        }
    }

    private func cancel(_ controller: SessionVerificationControllerProxyProtocol) async -> SessionVerificationControllerDiagnosticCommandResult {
        let currentSnapshot = snapshot(from: controller)
        guard currentSnapshot.verificationRequestPending else {
            return .init(outcome: .blocked,
                         reason: .requestNotPending,
                         snapshot: currentSnapshot)
        }

        switch await controller.cancelVerification() {
        case .success:
            return .init(outcome: .succeeded, snapshot: snapshot(from: controller))
        case .failure:
            return .init(outcome: .failed,
                         reason: .cancelFailed,
                         snapshot: snapshot(from: controller))
        }
    }

    private func snapshot(from controller: SessionVerificationControllerProxyProtocol) -> SessionVerificationControllerDiagnosticSnapshot {
        (controller as? SessionVerificationControllerDiagnosticProviding)?.diagnosticSnapshot ?? .unavailable
    }
}

struct SessionVerificationRequestDetails: Equatable {
    let senderProfile: UserProfileProxy
    let flowID: String
    let deviceID: String
    let deviceDisplayName: String?
    let firstSeenDate: Date
}

struct SessionVerificationEmoji: Hashable {
    let symbol: String
    let description: String
    
    var localizedDescription: String {
        SASL10n.localizedDescription(for: description.lowercased())
    }
}

// sourcery: AutoMockable
protocol SessionVerificationControllerProxyProtocol {
    var actions: PassthroughSubject<SessionVerificationControllerProxyAction, Never> { get }
    
    func acknowledgeVerificationRequest(details: SessionVerificationRequestDetails) async -> Result<Void, SessionVerificationControllerProxyError>
    
    func acceptVerificationRequest() async -> Result<Void, SessionVerificationControllerProxyError>
        
    func requestDeviceVerification() async -> Result<Void, SessionVerificationControllerProxyError>
    
    func requestUserVerification(_ userID: String) async -> Result<Void, SessionVerificationControllerProxyError>
    
    func startSasVerification() async -> Result<Void, SessionVerificationControllerProxyError>
    
    func approveVerification() async -> Result<Void, SessionVerificationControllerProxyError>
    
    func declineVerification() async -> Result<Void, SessionVerificationControllerProxyError>
    
    func cancelVerification() async -> Result<Void, SessionVerificationControllerProxyError>
}
