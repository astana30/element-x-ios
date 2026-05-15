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
