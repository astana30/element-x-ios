//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
protocol DirectCallEngineProtocol {
    var activeSessionPublisher: CurrentValuePublisher<DirectCallSession?, Never> { get }
    var actionsPublisher: AnyPublisher<DirectCallEngineAction, Never> { get }

    func startOutgoingAudioCall(peer: String, roomID: String) async -> Result<DirectCallSession, DirectCallEngineError>
    func startOutgoingVideoCall(peer: String, roomID: String) async -> Result<DirectCallSession, DirectCallEngineError>
    func receiveIncomingCall(event: DirectCallSignalEvent) async -> Result<DirectCallSession?, DirectCallEngineError>
    func acceptCall(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>
    func rejectCall(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>
    func cancelOutgoingBeforeAnswer(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>
    func hangupActiveCall(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>
    func markEncryptionEstablished(callID: String, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallSession, DirectCallEngineError>
    func markEncryptionFailed(callID: String, reason: DirectCallEncryptionFailureReason) async -> Result<DirectCallSession, DirectCallEngineError>
    func timeoutIncoming(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>
    func cleanupCall(callID: String) async
}
