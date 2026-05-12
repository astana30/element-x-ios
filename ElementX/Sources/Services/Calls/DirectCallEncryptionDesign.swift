//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CryptoKit
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
/// Implementations must never expose unencrypted media key material to logs.
struct DirectCallMediaKeyHandle: Equatable {
    let callID: String
    let keyID: String
}

struct DirectCallMediaKeyWrapRequest: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let callID: String
    let roomID: String
    let senderUserID: String
    let recipientUserID: String
    let senderDeviceID: String?
    let intent: DirectCallIntent
    let expiresAt: Date
    let keyID: String

    var description: String {
        let fields = [
            "callID: \(callID)",
            "roomID: <redacted>",
            "senderUserID: <redacted>",
            "recipientUserID: <redacted>",
            "senderDeviceID: <redacted>",
            "intent: \(intent.rawValue)",
            "expiresAt: \(expiresAt)",
            "keyID: \(keyID)"
        ]
        return "DirectCallMediaKeyWrapRequest(\(fields.joined(separator: ", ")))"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallMediaKeyUnwrapRequest: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let expectedCallID: String
    let expectedRoomID: String
    let expectedSenderUserID: String
    let recipientUserID: String
    let recipientDeviceID: String?
    let intent: DirectCallIntent
    let receivedAt: Date

    var description: String {
        let fields = [
            "expectedCallID: \(expectedCallID)",
            "expectedRoomID: <redacted>",
            "expectedSenderUserID: <redacted>",
            "recipientUserID: <redacted>",
            "recipientDeviceID: <redacted>",
            "intent: \(intent.rawValue)",
            "receivedAt: \(receivedAt)"
        ]
        return "DirectCallMediaKeyUnwrapRequest(\(fields.joined(separator: ", ")))"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallWrappedMediaKeyEnvelope: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let version: Int
    let algorithm: String
    let callID: String
    let roomID: String
    let senderUserID: String
    let recipientUserID: String
    let senderDeviceID: String?
    let intent: DirectCallIntent
    let expiresAt: Date
    let keyID: String
    let opaqueEnvelope: String

    init(version: Int = 1,
         algorithm: String,
         callID: String,
         roomID: String,
         senderUserID: String,
         recipientUserID: String,
         senderDeviceID: String? = nil,
         intent: DirectCallIntent,
         expiresAt: Date,
         keyID: String,
         opaqueEnvelope: String) {
        self.version = version
        self.algorithm = algorithm
        self.callID = callID
        self.roomID = roomID
        self.senderUserID = senderUserID
        self.recipientUserID = recipientUserID
        self.senderDeviceID = senderDeviceID
        self.intent = intent
        self.expiresAt = expiresAt
        self.keyID = keyID
        self.opaqueEnvelope = opaqueEnvelope
    }

    var description: String {
        let fields = [
            "version: \(version)",
            "algorithm: \(algorithm)",
            "callID: \(callID)",
            "roomID: <redacted>",
            "senderUserID: <redacted>",
            "recipientUserID: <redacted>",
            "senderDeviceID: <redacted>",
            "intent: \(intent.rawValue)",
            "expiresAt: \(expiresAt)",
            "keyID: \(keyID)",
            "opaqueEnvelope: <redacted>"
        ]
        return "DirectCallWrappedMediaKeyEnvelope(\(fields.joined(separator: ", ")))"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallUnwrappedMediaKey: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let mediaKey: String
    let keyID: String

    var description: String {
        "DirectCallUnwrappedMediaKey(mediaKey: <redacted>, keyID: \(keyID))"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallMediaKeyWrappingFailureReason: Error, Equatable {
    case e2eeUnavailable
    case cannotWrap
    case cannotUnwrap
    case invalidMetadata
}

@MainActor
protocol DirectCallMediaKeyWrappingProtocol {
    /// Future Matrix SDK-backed implementations are expected to become async when
    /// the SDK seam performs device and trust lookup. The app-side skeleton stays
    /// synchronous until `DirectCallEncryptionServiceProtocol` is widened.
    func wrapMediaKey(_ mediaKey: String,
                      request: DirectCallMediaKeyWrapRequest) -> Result<DirectCallWrappedMediaKeyEnvelope, DirectCallMediaKeyWrappingFailureReason>

    func unwrapMediaKeyEnvelope(_ envelope: DirectCallWrappedMediaKeyEnvelope,
                                request: DirectCallMediaKeyUnwrapRequest) -> Result<DirectCallUnwrappedMediaKey, DirectCallMediaKeyWrappingFailureReason>
}

final class FailClosedDirectCallMediaKeyWrapper: DirectCallMediaKeyWrappingProtocol, CustomStringConvertible, CustomDebugStringConvertible {
    func wrapMediaKey(_ mediaKey: String,
                      request: DirectCallMediaKeyWrapRequest) -> Result<DirectCallWrappedMediaKeyEnvelope, DirectCallMediaKeyWrappingFailureReason> {
        .failure(.e2eeUnavailable)
    }

    func unwrapMediaKeyEnvelope(_ envelope: DirectCallWrappedMediaKeyEnvelope,
                                request: DirectCallMediaKeyUnwrapRequest) -> Result<DirectCallUnwrappedMediaKey, DirectCallMediaKeyWrappingFailureReason> {
        .failure(.e2eeUnavailable)
    }

    nonisolated var description: String {
        "FailClosedDirectCallMediaKeyWrapper(status: failClosed)"
    }

    nonisolated var debugDescription: String {
        description
    }
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
    private static let keyAlgorithm = "salemx.native_direct_call.media_key.v1"

    private let keyWrapper: DirectCallMediaKeyWrappingProtocol
    private let keyStore: DirectCallLiveKitMediaKeyStore?
    private let ownUserID: String?
    private let senderDeviceID: String?
    private let now: () -> Date
    private let keyIDProvider: () -> String
    private let mediaKeyProvider: () -> String

    init(keyWrapper: DirectCallMediaKeyWrappingProtocol? = nil,
         keyStore: DirectCallLiveKitMediaKeyStore? = nil,
         ownUserID: String? = nil,
         senderDeviceID: String? = nil,
         now: @escaping () -> Date = Date.init,
         keyIDProvider: @escaping () -> String = { UUID().uuidString },
         mediaKeyProvider: (() -> String)? = nil) {
        self.keyWrapper = keyWrapper ?? FailClosedDirectCallMediaKeyWrapper()
        self.keyStore = keyStore
        self.ownUserID = ownUserID
        self.senderDeviceID = senderDeviceID
        self.now = now
        self.keyIDProvider = keyIDProvider
        self.mediaKeyProvider = mediaKeyProvider ?? Self.makeMediaKey
    }

    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        guard let keyStore,
              let ownUserID,
              !callID.isEmpty,
              !roomID.isEmpty,
              !peerUserID.isEmpty,
              !ownUserID.isEmpty,
              peerUserID != ownUserID else {
            return .failure(.e2eeUnavailable)
        }

        let keyID = keyIDProvider()
        let mediaKey = mediaKeyProvider()
        guard !keyID.isEmpty, !mediaKey.isEmpty else {
            return .failure(.cannotWrap)
        }

        let wrapRequest = DirectCallMediaKeyWrapRequest(callID: callID,
                                                        roomID: roomID,
                                                        senderUserID: ownUserID,
                                                        recipientUserID: peerUserID,
                                                        senderDeviceID: senderDeviceID,
                                                        intent: .audio,
                                                        expiresAt: now().addingTimeInterval(60),
                                                        keyID: keyID)
        switch keyWrapper.wrapMediaKey(mediaKey, request: wrapRequest) {
        case .success(let envelope):
            guard envelope.callID == callID,
                  envelope.roomID == roomID,
                  envelope.senderUserID == ownUserID,
                  envelope.recipientUserID == peerUserID,
                  envelope.keyID == keyID,
                  envelope.intent == .audio,
                  !envelope.opaqueEnvelope.isEmpty else {
                return .failure(.keyMismatch)
            }

            let keyHandle = DirectCallMediaKeyHandle(callID: callID, keyID: keyID)
            switch keyStore.storeSharedKey(mediaKey, keyHandle: keyHandle) {
            case .success(let storedHandle):
                let payload = DirectCallEncryptedKeyExchangePayload(callID: callID,
                                                                    roomID: roomID,
                                                                    senderUserID: ownUserID,
                                                                    keyID: storedHandle.keyID,
                                                                    encryptedPayload: envelope.opaqueEnvelope)
                return .success(.init(payload: payload, keyHandle: storedHandle))
            case .failure:
                return .failure(.e2eeUnavailable)
            }
        case .failure(let reason):
            return .failure(Self.encryptionFailureReason(for: reason, wrapping: true))
        }
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload,
                                   expectedCallID: String,
                                   expectedRoomID: String,
                                   expectedSenderUserID: String) -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        guard let keyStore,
              let ownUserID,
              payload.callID == expectedCallID,
              payload.roomID == expectedRoomID,
              payload.senderUserID == expectedSenderUserID,
              !payload.keyID.isEmpty,
              !payload.encryptedPayload.isEmpty,
              !ownUserID.isEmpty else {
            return .failure(.e2eeUnavailable)
        }

        let envelope = DirectCallWrappedMediaKeyEnvelope(algorithm: Self.keyAlgorithm,
                                                         callID: payload.callID,
                                                         roomID: payload.roomID,
                                                         senderUserID: payload.senderUserID,
                                                         recipientUserID: ownUserID,
                                                         senderDeviceID: nil,
                                                         intent: .audio,
                                                         expiresAt: now().addingTimeInterval(60),
                                                         keyID: payload.keyID,
                                                         opaqueEnvelope: payload.encryptedPayload)
        let unwrapRequest = DirectCallMediaKeyUnwrapRequest(expectedCallID: expectedCallID,
                                                            expectedRoomID: expectedRoomID,
                                                            expectedSenderUserID: expectedSenderUserID,
                                                            recipientUserID: ownUserID,
                                                            recipientDeviceID: senderDeviceID,
                                                            intent: .audio,
                                                            receivedAt: now())
        switch keyWrapper.unwrapMediaKeyEnvelope(envelope, request: unwrapRequest) {
        case .success(let unwrappedKey):
            guard unwrappedKey.keyID == payload.keyID,
                  !unwrappedKey.mediaKey.isEmpty else {
                return .failure(.keyMismatch)
            }

            let keyHandle = DirectCallMediaKeyHandle(callID: payload.callID, keyID: payload.keyID)
            switch keyStore.storeSharedKey(unwrappedKey.mediaKey, keyHandle: keyHandle) {
            case .success(let storedHandle):
                return .success(storedHandle)
            case .failure:
                return .failure(.e2eeUnavailable)
            }
        case .failure(let reason):
            return .failure(Self.encryptionFailureReason(for: reason, wrapping: false))
        }
    }

    func clearPerCallKey(callID: String) {
        keyStore?.clear(callID: callID)
    }

    nonisolated var description: String {
        "ProductionDirectCallEncryptionService(status: failClosed)"
    }

    nonisolated var debugDescription: String {
        description
    }

    private static func encryptionFailureReason(for reason: DirectCallMediaKeyWrappingFailureReason,
                                                wrapping: Bool) -> DirectCallEncryptionFailureReason {
        switch reason {
        case .e2eeUnavailable:
            .e2eeUnavailable
        case .cannotWrap:
            wrapping ? .cannotWrap : .cannotUnwrap
        case .cannotUnwrap:
            .cannotUnwrap
        case .invalidMetadata:
            .keyMismatch
        }
    }

    private static func makeMediaKey() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { keyBytes in
            Data(keyBytes).base64EncodedString()
        }
    }
}
