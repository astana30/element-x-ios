//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

/// Ciphertext-only key exchange payload.
/// The encrypted payload must travel via Matrix E2EE-protected signalling.
struct DirectCallEncryptedKeyExchangePayload: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let callID: String
    let roomID: String
    let senderUserID: String
    let keyID: String
    let encryptedPayload: String

    var description: String {
        "DirectCallEncryptedKeyExchangePayload(callID: \(callID), roomID: \(roomID), senderUserID: \(senderUserID), keyID: \(keyID), encryptedPayload: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

/// Generated local key handle plus the ciphertext payload that can be sent to the peer.
/// The raw media key must remain hidden inside the encryption implementation.
struct DirectCallGeneratedKeyExchange: Equatable {
    let payload: DirectCallEncryptedKeyExchangePayload
    let keyHandle: DirectCallMediaKeyHandle
}

/// Opaque per-call media key handle.
/// Implementations must never expose raw key material to logs.
struct DirectCallMediaKeyHandle: Equatable {
    let callID: String
    let keyID: String
}

@MainActor
protocol DirectCallEncryptionServiceProtocol {
    /// Generates a new per-call key. Keys must never be reused across calls.
    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason>

    /// Consumes remote encrypted key material and verifies compatibility for this call.
    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload, expectedCallID: String, expectedRoomID: String, expectedSenderUserID: String) -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason>

    /// Removes all key material for the call from memory.
    func clearPerCallKey(callID: String)
}

final class NoOpDirectCallEncryptionService: DirectCallEncryptionServiceProtocol {
    private var clearedCallIDs = Set<String>()

    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        .failure(.keyExchangeFailed)
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload, expectedCallID: String, expectedRoomID: String, expectedSenderUserID: String) -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        .failure(.keyExchangeFailed)
    }

    func clearPerCallKey(callID: String) {
        guard !callID.isEmpty else {
            return
        }

        _ = clearedCallIDs.insert(callID)
    }
}

/// Production-shaped placeholder for the future Matrix-crypto-backed media key exchange.
/// It must stay fail-closed until the production key wrapping design is implemented.
final class ProductionDirectCallEncryptionService: DirectCallEncryptionServiceProtocol, CustomStringConvertible, CustomDebugStringConvertible {
    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        .failure(.e2eeNotProven)
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload,
                                   expectedCallID: String,
                                   expectedRoomID: String,
                                   expectedSenderUserID: String) -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        .failure(.e2eeNotProven)
    }

    func clearPerCallKey(callID: String) { }

    nonisolated var description: String {
        "ProductionDirectCallEncryptionService(status: failClosed)"
    }

    nonisolated var debugDescription: String {
        description
    }
}
