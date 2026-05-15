//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CryptoKit
import Foundation

/// Ciphertext plus non-secret key envelope metadata.
/// The encrypted payload must travel via Matrix E2EE-protected signalling and must never contain plaintext media-key material.
struct DirectCallEncryptedKeyExchangePayload: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let version: Int?
    let algorithm: String?
    let callID: String
    let roomID: String
    let senderUserID: String
    let recipientUserID: String?
    let intent: DirectCallIntent?
    let expiresAt: Date?
    let keyID: String
    let encryptedPayload: String

    init(callID: String,
         roomID: String,
         senderUserID: String,
         keyID: String,
         encryptedPayload: String,
         version: Int? = nil,
         algorithm: String? = nil,
         recipientUserID: String? = nil,
         intent: DirectCallIntent? = nil,
         expiresAt: Date? = nil) {
        self.version = version
        self.algorithm = algorithm
        self.callID = callID
        self.roomID = roomID
        self.senderUserID = senderUserID
        self.recipientUserID = recipientUserID
        self.intent = intent
        self.expiresAt = expiresAt
        self.keyID = keyID
        self.encryptedPayload = encryptedPayload
    }

    var description: String {
        "DirectCallEncryptedKeyExchangePayload(" + [
            "callID: \(callID)",
            "roomID: \(roomID)",
            "senderUserID: \(senderUserID)",
            "recipientUserID: <redacted>",
            "intent: \(String(describing: intent))",
            "expiresAt: \(String(describing: expiresAt))",
            "keyID: \(keyID)",
            "encryptedPayload: <redacted>"
        ].joined(separator: ", ") + ")"
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
    case missingPeer
    case missingMetadata
    case sdkWrapperUnavailable
    case sdkTrustViolation
    case sdkNoEligibleDevice
    case sdkEnvelopeFailed
    case wrongRecipient
    case expired
    case unsupportedEnvelope
    case unsupportedRuntime
}

@MainActor
protocol DirectCallMediaKeyWrappingProtocol {
    func wrapMediaKey(_ mediaKey: String,
                      request: DirectCallMediaKeyWrapRequest) async -> Result<DirectCallWrappedMediaKeyEnvelope, DirectCallMediaKeyWrappingFailureReason>

    func unwrapMediaKeyEnvelope(_ envelope: DirectCallWrappedMediaKeyEnvelope,
                                request: DirectCallMediaKeyUnwrapRequest) async -> Result<DirectCallUnwrappedMediaKey, DirectCallMediaKeyWrappingFailureReason>
}

final class FailClosedDirectCallMediaKeyWrapper: DirectCallMediaKeyWrappingProtocol, CustomStringConvertible, CustomDebugStringConvertible {
    func wrapMediaKey(_ mediaKey: String,
                      request: DirectCallMediaKeyWrapRequest) async -> Result<DirectCallWrappedMediaKeyEnvelope, DirectCallMediaKeyWrappingFailureReason> {
        .failure(.e2eeUnavailable)
    }

    func unwrapMediaKeyEnvelope(_ envelope: DirectCallWrappedMediaKeyEnvelope,
                                request: DirectCallMediaKeyUnwrapRequest) async -> Result<DirectCallUnwrappedMediaKey, DirectCallMediaKeyWrappingFailureReason> {
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
    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) async -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason>

    /// Consumes remote encrypted key material and verifies compatibility for this call.
    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload, expectedCallID: String, expectedRoomID: String, expectedSenderUserID: String) async -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason>

    /// Removes all key material for the call from memory.
    func clearPerCallKey(callID: String)
}

final class NoOpDirectCallEncryptionService: DirectCallEncryptionServiceProtocol {
    private var clearedCallIDs = Set<String>()

    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) async -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        .failure(.keyExchangeFailed)
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload, expectedCallID: String, expectedRoomID: String, expectedSenderUserID: String) async -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
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

    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) async -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        guard let keyStore,
              let ownUserID,
              !ownUserID.isEmpty else {
            return .failure(.e2eeUnavailable)
        }

        guard !callID.isEmpty,
              !roomID.isEmpty else {
            return .failure(.missingMetadata)
        }

        guard !peerUserID.isEmpty,
              peerUserID != ownUserID else {
            return .failure(.missingPeer)
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
        switch await keyWrapper.wrapMediaKey(mediaKey, request: wrapRequest) {
        case .success(let envelope):
            guard envelope.version == 1,
                  envelope.algorithm == Self.keyAlgorithm,
                  envelope.callID == callID,
                  envelope.roomID == roomID,
                  envelope.senderUserID == ownUserID,
                  envelope.recipientUserID == peerUserID,
                  envelope.keyID == keyID,
                  envelope.intent == .audio,
                  envelope.expiresAt >= now(),
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
                                                                    encryptedPayload: envelope.opaqueEnvelope,
                                                                    version: envelope.version,
                                                                    algorithm: envelope.algorithm,
                                                                    recipientUserID: envelope.recipientUserID,
                                                                    intent: envelope.intent,
                                                                    expiresAt: envelope.expiresAt)
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
                                   expectedSenderUserID: String) async -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
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

        guard let recipientUserID = payload.recipientUserID else {
            return .failure(.missingMetadata)
        }

        guard recipientUserID == ownUserID else {
            return .failure(.wrongRecipient)
        }

        guard let version = payload.version,
              let algorithm = payload.algorithm,
              let intent = payload.intent,
              let expiresAt = payload.expiresAt else {
            return .failure(.missingMetadata)
        }

        guard version == 1,
              algorithm == Self.keyAlgorithm,
              intent == .audio else {
            return .failure(.unsupportedEnvelope)
        }

        guard expiresAt >= now() else {
            return .failure(.expiredKeyExchange)
        }

        let envelope = DirectCallWrappedMediaKeyEnvelope(version: version,
                                                         algorithm: algorithm,
                                                         callID: payload.callID,
                                                         roomID: payload.roomID,
                                                         senderUserID: payload.senderUserID,
                                                         recipientUserID: recipientUserID,
                                                         senderDeviceID: nil,
                                                         intent: intent,
                                                         expiresAt: expiresAt,
                                                         keyID: payload.keyID,
                                                         opaqueEnvelope: payload.encryptedPayload)
        let unwrapRequest = DirectCallMediaKeyUnwrapRequest(expectedCallID: expectedCallID,
                                                            expectedRoomID: expectedRoomID,
                                                            expectedSenderUserID: expectedSenderUserID,
                                                            recipientUserID: ownUserID,
                                                            recipientDeviceID: senderDeviceID,
                                                            intent: .audio,
                                                            receivedAt: now())
        switch await keyWrapper.unwrapMediaKeyEnvelope(envelope, request: unwrapRequest) {
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
        case .missingPeer:
            .missingPeer
        case .missingMetadata:
            .missingMetadata
        case .sdkWrapperUnavailable:
            .sdkWrapperUnavailable
        case .sdkTrustViolation:
            .sdkTrustViolation
        case .sdkNoEligibleDevice:
            .sdkNoEligibleDevice
        case .sdkEnvelopeFailed:
            .sdkEnvelopeFailed
        case .wrongRecipient:
            .wrongRecipient
        case .expired:
            .expiredKeyExchange
        case .unsupportedEnvelope:
            .unsupportedEnvelope
        case .unsupportedRuntime:
            .unsupportedRuntime
        }
    }

    private static func makeMediaKey() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { keyBytes in
            Data(keyBytes).base64EncodedString()
        }
    }
}
