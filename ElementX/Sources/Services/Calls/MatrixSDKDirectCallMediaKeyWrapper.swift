//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

protocol MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol: AnyObject {
    func wrapDirectCallMediaKey(info: MatrixRustSDK.DirectCallMediaKeyWrapInfo) async throws -> MatrixRustSDK.DirectCallMediaKeyEnvelope
    func unwrapDirectCallMediaKeyEnvelope(info: MatrixRustSDK.DirectCallMediaKeyUnwrapInfo,
                                          envelope: MatrixRustSDK.DirectCallMediaKeyEnvelope) async throws -> MatrixRustSDK.DirectCallMediaKeyUnwrapResult
}

@MainActor
protocol DirectCallMediaKeyEnvelopeWrappingProviding: AnyObject {
    func makeDirectCallMediaKeyEnvelopeWrapper() -> MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol?
}

final class MatrixSDKDirectCallMediaKeyEnvelopeWrapperAdapter: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol {
    private let encryption: MatrixRustSDK.EncryptionProtocol

    init(encryption: MatrixRustSDK.EncryptionProtocol) {
        self.encryption = encryption
    }

    func wrapDirectCallMediaKey(info: MatrixRustSDK.DirectCallMediaKeyWrapInfo) async throws -> MatrixRustSDK.DirectCallMediaKeyEnvelope {
        try await encryption.wrapDirectCallMediaKey(info: info)
    }

    func unwrapDirectCallMediaKeyEnvelope(info: MatrixRustSDK.DirectCallMediaKeyUnwrapInfo,
                                          envelope: MatrixRustSDK.DirectCallMediaKeyEnvelope) async throws -> MatrixRustSDK.DirectCallMediaKeyUnwrapResult {
        try await encryption.unwrapDirectCallMediaKeyEnvelope(info: info, envelope: envelope)
    }
}

/// Production-shaped adapter for the Matrix SDK direct-call key envelope seam.
/// It is not injected by default; missing SDK dependencies fail closed.
@MainActor
final class MatrixSDKDirectCallMediaKeyWrapper: DirectCallMediaKeyWrappingProtocol, CustomStringConvertible, CustomDebugStringConvertible {
    private let encryption: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol?
    private let trustRequirement: MatrixRustSDK.DirectCallMediaKeyTrustRequirement

    convenience init(encryption: MatrixRustSDK.EncryptionProtocol?,
                     trustRequirement: MatrixRustSDK.DirectCallMediaKeyTrustRequirement = .onlyTrustedDevices) {
        self.init(envelopeWrapper: encryption.map(MatrixSDKDirectCallMediaKeyEnvelopeWrapperAdapter.init(encryption:)),
                  trustRequirement: trustRequirement)
    }

    init(envelopeWrapper: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol? = nil,
         trustRequirement: MatrixRustSDK.DirectCallMediaKeyTrustRequirement = .onlyTrustedDevices) {
        encryption = envelopeWrapper
        self.trustRequirement = trustRequirement
    }

    func wrapMediaKey(_ mediaKey: String,
                      request: DirectCallMediaKeyWrapRequest) async -> Result<DirectCallWrappedMediaKeyEnvelope, DirectCallMediaKeyWrappingFailureReason> {
        guard let encryption else {
            return .failure(.sdkWrapperUnavailable)
        }

        guard !request.callID.isEmpty,
              !request.roomID.isEmpty,
              !request.keyID.isEmpty else {
            return .failure(.missingMetadata)
        }

        guard !request.senderUserID.isEmpty,
              !request.recipientUserID.isEmpty,
              request.senderUserID != request.recipientUserID else {
            return .failure(.missingPeer)
        }

        guard !mediaKey.isEmpty else {
            return .failure(.cannotWrap)
        }

        do {
            let envelope = try await encryption.wrapDirectCallMediaKey(info: .init(roomId: request.roomID,
                                                                                   callId: request.callID,
                                                                                   recipientUserId: request.recipientUserID,
                                                                                   intent: request.intent.rawValue,
                                                                                   keyId: request.keyID,
                                                                                   expiresAtMs: Self.millisecondsSince1970(from: request.expiresAt),
                                                                                   mediaKey: mediaKey,
                                                                                   trustRequirement: trustRequirement))
            return .success(Self.appEnvelope(from: envelope, senderDeviceID: request.senderDeviceID))
        } catch {
            return .failure(Self.failureReason(for: error, wrapping: true))
        }
    }

    func unwrapMediaKeyEnvelope(_ envelope: DirectCallWrappedMediaKeyEnvelope,
                                request: DirectCallMediaKeyUnwrapRequest) async -> Result<DirectCallUnwrappedMediaKey, DirectCallMediaKeyWrappingFailureReason> {
        guard let encryption else {
            return .failure(.sdkWrapperUnavailable)
        }

        guard !request.expectedCallID.isEmpty,
              !request.expectedRoomID.isEmpty,
              !envelope.keyID.isEmpty else {
            return .failure(.missingMetadata)
        }

        guard !request.expectedSenderUserID.isEmpty,
              !request.recipientUserID.isEmpty,
              request.expectedSenderUserID != request.recipientUserID else {
            return .failure(.missingPeer)
        }

        guard let sdkEnvelope = Self.sdkEnvelope(from: envelope) else {
            return .failure(.invalidMetadata)
        }

        do {
            let result = try await encryption.unwrapDirectCallMediaKeyEnvelope(info: .init(roomId: request.expectedRoomID,
                                                                                           callId: request.expectedCallID,
                                                                                           expectedSenderUserId: request.expectedSenderUserID,
                                                                                           expectedRecipientUserId: request.recipientUserID,
                                                                                           intent: request.intent.rawValue,
                                                                                           keyId: envelope.keyID,
                                                                                           receivedAtMs: Self.millisecondsSince1970(from: request.receivedAt)),
                                                                               envelope: sdkEnvelope)
            guard result.senderUserId == request.expectedSenderUserID else {
                return .failure(.invalidMetadata)
            }

            return .success(.init(mediaKey: result.mediaKey, keyID: result.keyId))
        } catch {
            return .failure(Self.failureReason(for: error, wrapping: false))
        }
    }

    nonisolated var description: String {
        "MatrixSDKDirectCallMediaKeyWrapper(status: explicitDependency, trustRequirement: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }

    private static func appEnvelope(from envelope: MatrixRustSDK.DirectCallMediaKeyEnvelope,
                                    senderDeviceID: String?) -> DirectCallWrappedMediaKeyEnvelope {
        .init(version: Int(envelope.version),
              algorithm: envelope.algorithm,
              callID: envelope.callId,
              roomID: envelope.roomId,
              senderUserID: envelope.senderUserId,
              recipientUserID: envelope.recipientUserId,
              senderDeviceID: senderDeviceID,
              intent: DirectCallIntent.parse(envelope.intent) ?? .audio,
              expiresAt: Date(timeIntervalSince1970: TimeInterval(envelope.expiresAtMs) / 1000),
              keyID: envelope.keyId,
              opaqueEnvelope: envelope.opaqueCiphertext)
    }

    private static func sdkEnvelope(from envelope: DirectCallWrappedMediaKeyEnvelope) -> MatrixRustSDK.DirectCallMediaKeyEnvelope? {
        guard let version = UInt8(exactly: envelope.version) else {
            return nil
        }

        return .init(version: version,
                     algorithm: envelope.algorithm,
                     roomId: envelope.roomID,
                     callId: envelope.callID,
                     senderUserId: envelope.senderUserID,
                     recipientUserId: envelope.recipientUserID,
                     intent: envelope.intent.rawValue,
                     keyId: envelope.keyID,
                     expiresAtMs: millisecondsSince1970(from: envelope.expiresAt),
                     opaqueCiphertext: envelope.opaqueEnvelope)
    }

    private static func millisecondsSince1970(from date: Date) -> UInt64 {
        let milliseconds = date.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds > 0 else {
            return 0
        }

        guard milliseconds < Double(UInt64.max) else {
            return UInt64.max
        }

        return UInt64(milliseconds.rounded(.down))
    }

    private static func failureReason(for error: Error, wrapping: Bool) -> DirectCallMediaKeyWrappingFailureReason {
        guard let envelopeError = error as? MatrixRustSDK.DirectCallMediaKeyEnvelopeError else {
            return .sdkEnvelopeFailed
        }

        switch envelopeError {
        case .MissingSession, .MissingOlmMachine:
            return .sdkWrapperUnavailable
        case .NoEligibleDevices:
            return .sdkNoEligibleDevice
        case .TrustViolation:
            return .sdkTrustViolation
        case .InvalidMetadata:
            return .invalidMetadata
        case .NotIntendedRecipient:
            return .wrongRecipient
        case .Expired:
            return .expired
        case .UnsupportedVersion, .MalformedEnvelope:
            return .unsupportedEnvelope
        case .EncryptionFailed:
            return wrapping ? .sdkEnvelopeFailed : .cannotUnwrap
        case .DecryptionFailed:
            return wrapping ? .cannotWrap : .sdkEnvelopeFailed
        }
    }
}
