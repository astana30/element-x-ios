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

private final class WeakSessionVerificationControllerProxy: SessionVerificationControllerDelegate, @unchecked Sendable {
    private weak var proxy: SessionVerificationControllerProxy?
    
    init(proxy: SessionVerificationControllerProxy) {
        self.proxy = proxy
    }
    
    // MARK: - SessionVerificationControllerDelegate
    
    func didReceiveVerificationRequest(details: MatrixRustSDK.SessionVerificationRequestDetails) {
        proxy?.didReceiveVerificationRequest(details: details)
    }
    
    func didReceiveVerificationData(data: MatrixRustSDK.SessionVerificationData) {
        switch data {
        // We can handle only emojis for now
        case .emojis(let emojis, _):
            proxy?.didReceiveData(emojis)
        default:
            break
        }
    }
    
    func didAcceptVerificationRequest() {
        proxy?.didAcceptVerificationRequest()
    }
    
    func didStartSasVerification() {
        proxy?.didStartSasVerification()
    }
    
    func didFail() {
        proxy?.didFail()
    }
    
    func didCancel() {
        proxy?.didCancel()
    }
    
    func didFinish() {
        proxy?.didFinish()
    }
}

class SessionVerificationControllerProxy: SessionVerificationControllerProxyProtocol, SessionVerificationControllerDiagnosticProviding {
    private let sessionVerificationController: SessionVerificationController
    private var currentDiagnosticSnapshot = SessionVerificationControllerDiagnosticSnapshot()

    var diagnosticSnapshot: SessionVerificationControllerDiagnosticSnapshot {
        currentDiagnosticSnapshot
    }
    
    init(sessionVerificationController: SessionVerificationController) {
        self.sessionVerificationController = sessionVerificationController
        sessionVerificationController.setDelegate(delegate: WeakSessionVerificationControllerProxy(proxy: self))
    }
    
    deinit {
        sessionVerificationController.setDelegate(delegate: nil)
    }
    
    let actions = PassthroughSubject<SessionVerificationControllerProxyAction, Never>()
    
    func acknowledgeVerificationRequest(details: SessionVerificationRequestDetails) async -> Result<Void, SessionVerificationControllerProxyError> {
        MXLog.info("Acknowledging verification request")
        
        do {
            try await sessionVerificationController.acknowledgeVerificationRequest(senderId: details.senderProfile.userID, flowId: details.flowID)
            updateDiagnosticSnapshot(flowState: .requestAcknowledged, verificationRequestPending: true)
            return .success(())
        } catch {
            MXLog.error("Failed requesting session verification with error: \(error)")
            updateDiagnosticSnapshot(flowState: .failed,
                                     verificationRequestPending: false,
                                     errorReason: .acknowledgeFailed)
            return .failure(.failedAcknowledgingVerificationRequest)
        }
    }
    
    func acceptVerificationRequest() async -> Result<Void, SessionVerificationControllerProxyError> {
        MXLog.info("Accepting verification request")
        
        do {
            try await sessionVerificationController.acceptVerificationRequest()
            updateDiagnosticSnapshot(flowState: .requestAccepted, verificationRequestPending: true)
            return .success(())
        } catch {
            MXLog.error("Failed requesting session verification with error: \(error)")
            updateDiagnosticSnapshot(flowState: .failed,
                                     verificationRequestPending: false,
                                     errorReason: .acceptFailed)
            return .failure(.failedAcceptingVerificationRequest)
        }
    }
        
    func requestDeviceVerification() async -> Result<Void, SessionVerificationControllerProxyError> {
        MXLog.info("Requesting device verification")
        
        do {
            try await sessionVerificationController.requestDeviceVerification()
            updateDiagnosticSnapshot(flowState: .verificationRequested, verificationRequestPending: true)
            return .success(())
        } catch {
            MXLog.error("Failed requesting device verification with error: \(error)")
            updateDiagnosticSnapshot(flowState: .failed,
                                     verificationRequestPending: false,
                                     errorReason: .requestFailed)
            return .failure(.failedRequestingVerification)
        }
    }
    
    func requestUserVerification(_ userID: String) async -> Result<Void, SessionVerificationControllerProxyError> {
        MXLog.info("Requesting user verification")
        
        do {
            try await sessionVerificationController.requestUserVerification(userId: userID)
            updateDiagnosticSnapshot(flowState: .verificationRequested, verificationRequestPending: true)
            return .success(())
        } catch {
            MXLog.error("Failed requesting verification for user \(userID) with error: \(error)")
            updateDiagnosticSnapshot(flowState: .failed,
                                     verificationRequestPending: false,
                                     errorReason: .requestFailed)
            return .failure(.failedRequestingVerification)
        }
    }
    
    func startSasVerification() async -> Result<Void, SessionVerificationControllerProxyError> {
        MXLog.info("Starting SAS verification")
        
        do {
            try await sessionVerificationController.startSasVerification()
            updateDiagnosticSnapshot(flowState: .sasStarted, verificationRequestPending: true)
            return .success(())
        } catch {
            MXLog.error("Failed starting SAS verification with error: \(error)")
            updateDiagnosticSnapshot(flowState: .failed,
                                     verificationRequestPending: false,
                                     errorReason: .startSASFailed)
            return .failure(.failedStartingSasVerification)
        }
    }
    
    func approveVerification() async -> Result<Void, SessionVerificationControllerProxyError> {
        MXLog.info("Approving verification")
        
        do {
            try await sessionVerificationController.approveVerification()
            return .success(())
        } catch {
            MXLog.error("Failed approving verification with error: \(error)")
            updateDiagnosticSnapshot(flowState: .failed,
                                     verificationRequestPending: false,
                                     errorReason: .approveFailed)
            return .failure(.failedApprovingVerification)
        }
    }
    
    func declineVerification() async -> Result<Void, SessionVerificationControllerProxyError> {
        MXLog.info("Declining verification")
        
        do {
            try await sessionVerificationController.declineVerification()
            updateDiagnosticSnapshot(flowState: .cancelled, verificationRequestPending: false)
            return .success(())
        } catch {
            MXLog.error("Failed declining verification with error: \(error)")
            updateDiagnosticSnapshot(flowState: .failed,
                                     verificationRequestPending: false,
                                     errorReason: .declineFailed)
            return .failure(.failedDecliningVerification)
        }
    }
    
    func cancelVerification() async -> Result<Void, SessionVerificationControllerProxyError> {
        MXLog.info("Cancelling verification")
        
        do {
            try await sessionVerificationController.cancelVerification()
            updateDiagnosticSnapshot(flowState: .cancelled, verificationRequestPending: false)
            return .success(())
        } catch {
            MXLog.error("Failed cancelling verification with error: \(error)")
            updateDiagnosticSnapshot(flowState: .failed,
                                     verificationRequestPending: false,
                                     errorReason: .cancelFailed)
            return .failure(.failedCancellingVerification)
        }
    }
    
    // MARK: - Private

    private func updateDiagnosticSnapshot(flowState: SessionVerificationControllerDiagnosticFlowState,
                                          verificationRequestPending: Bool,
                                          errorReason: SessionVerificationControllerDiagnosticErrorReason = .none) {
        currentDiagnosticSnapshot = .init(verificationRequestPending: verificationRequestPending,
                                          verificationFlowState: flowState,
                                          lastVerificationErrorReason: errorReason)
    }
    
    fileprivate func didReceiveVerificationRequest(details: MatrixRustSDK.SessionVerificationRequestDetails) {
        MXLog.info("Received verification request")
        updateDiagnosticSnapshot(flowState: .requestReceived, verificationRequestPending: true)
        
        let details = SessionVerificationRequestDetails(senderProfile: UserProfileProxy(sdkUserProfile: details.senderProfile),
                                                        flowID: details.flowId,
                                                        deviceID: details.deviceId,
                                                        deviceDisplayName: details.deviceDisplayName,
                                                        firstSeenDate: Date(timeIntervalSince1970: TimeInterval(details.firstSeenTimestamp / 1000)))
        
        actions.send(.receivedVerificationRequest(details: details))
    }
    
    fileprivate func didAcceptVerificationRequest() {
        MXLog.info("Accepted verification request")
        updateDiagnosticSnapshot(flowState: .requestAccepted, verificationRequestPending: true)
        
        actions.send(.acceptedVerificationRequest)
    }
    
    fileprivate func didStartSasVerification() {
        MXLog.info("Started SAS verification")
        updateDiagnosticSnapshot(flowState: .sasStarted, verificationRequestPending: true)
        
        actions.send(.startedSasVerification)
    }
    
    fileprivate func didReceiveData(_ data: [MatrixRustSDK.SessionVerificationEmoji]) {
        MXLog.info("Received verification data")
        updateDiagnosticSnapshot(flowState: .emojiReceived, verificationRequestPending: true)
        
        actions.send(.receivedVerificationData(data.map { emoji in
            SessionVerificationEmoji(symbol: emoji.symbol(), description: emoji.description())
        }))
    }
    
    fileprivate func didFail() {
        updateDiagnosticSnapshot(flowState: .failed,
                                 verificationRequestPending: false,
                                 errorReason: .callbackFailed)
        actions.send(.failed)
    }
    
    fileprivate func didFinish() {
        updateDiagnosticSnapshot(flowState: .finished, verificationRequestPending: false)
        actions.send(.finished)
    }
    
    fileprivate func didCancel() {
        updateDiagnosticSnapshot(flowState: .cancelled, verificationRequestPending: false)
        actions.send(.cancelled)
    }
}
