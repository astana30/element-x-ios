//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

#if DEBUG
import CryptoKit
import Foundation

/// Diagnostic-only key exchange for integration tests. This is not production E2EE.
@MainActor
final class NativeDirectCallDiagnosticEncryptionService: DirectCallEncryptionServiceProtocol {
    static let encryptionGateEnvironmentKey = "NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION"
    static let secretEnvironmentKey = "NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION_SECRET"

    private static let payloadVersion = "v1"
    private static let purpose = "salemx-native-direct-call-diagnostic"

    private let ownUserID: String
    private let secret: String
    private var keyMaterialByCallID = [String: Data]()

    init?(ownUserID: String, secret: String) {
        guard !ownUserID.isEmpty, !secret.isEmpty else {
            return nil
        }

        self.ownUserID = ownUserID
        self.secret = secret
    }

    static func makeIfEnabled(ownUserID: String,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> NativeDirectCallDiagnosticEncryptionService? {
        guard ProcessInfo.isNativeDirectCallDiagnosticIntegrationEncryptionEnabled(environment: environment),
              let secret = environment[secretEnvironmentKey] else {
            return nil
        }

        return NativeDirectCallDiagnosticEncryptionService(ownUserID: ownUserID, secret: secret)
    }

    func generatePerCallKey(callID: String,
                            roomID: String,
                            peerUserID: String) async -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        guard !callID.isEmpty,
              !roomID.isEmpty,
              !peerUserID.isEmpty,
              peerUserID != ownUserID else {
            return .failure(.keyExchangeFailed)
        }

        let keyMaterial = Self.randomData(count: 32)
        let keyID = keyID(callID: callID,
                          roomID: roomID,
                          senderUserID: ownUserID,
                          keyMaterial: keyMaterial)

        guard let encryptedPayload = seal(keyMaterial: keyMaterial,
                                          callID: callID,
                                          roomID: roomID,
                                          senderUserID: ownUserID,
                                          keyID: keyID) else {
            return .failure(.keyExchangeFailed)
        }

        keyMaterialByCallID[callID] = keyMaterial
        let payload = DirectCallEncryptedKeyExchangePayload(callID: callID,
                                                            roomID: roomID,
                                                            senderUserID: ownUserID,
                                                            keyID: keyID,
                                                            encryptedPayload: encryptedPayload)
        return .success(.init(payload: payload,
                              keyHandle: .init(callID: callID, keyID: keyID)))
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload,
                                   expectedCallID: String,
                                   expectedRoomID: String,
                                   expectedSenderUserID: String) async -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        guard payload.callID == expectedCallID,
              payload.roomID == expectedRoomID,
              payload.senderUserID == expectedSenderUserID,
              !payload.keyID.isEmpty else {
            return .failure(.keyMismatch)
        }

        guard let keyMaterial = open(encryptedPayload: payload.encryptedPayload,
                                     callID: payload.callID,
                                     roomID: payload.roomID,
                                     senderUserID: payload.senderUserID,
                                     keyID: payload.keyID) else {
            return .failure(.keyMismatch)
        }

        guard payload.keyID == keyID(callID: payload.callID,
                                     roomID: payload.roomID,
                                     senderUserID: payload.senderUserID,
                                     keyMaterial: keyMaterial) else {
            return .failure(.keyMismatch)
        }

        keyMaterialByCallID[payload.callID] = keyMaterial
        return .success(.init(callID: payload.callID, keyID: payload.keyID))
    }

    func clearPerCallKey(callID: String) {
        guard !callID.isEmpty else {
            return
        }

        keyMaterialByCallID.removeValue(forKey: callID)
    }

    func storeLiveKitSharedKey(for keyHandle: DirectCallMediaKeyHandle,
                               in keyStore: DirectCallLiveKitMediaKeyStore) -> Result<DirectCallMediaKeyHandle, DirectCallMediaError> {
        guard !keyHandle.callID.isEmpty,
              !keyHandle.keyID.isEmpty,
              let keyMaterial = keyMaterialByCallID[keyHandle.callID] else {
            return .failure(.e2eeContextUnavailable)
        }

        return keyStore.storeSharedKey(keyMaterial.base64URLEncodedString(), keyHandle: keyHandle)
    }

    private func seal(keyMaterial: Data,
                      callID: String,
                      roomID: String,
                      senderUserID: String,
                      keyID: String) -> String? {
        do {
            let box = try AES.GCM.seal(keyMaterial,
                                       using: encryptionKey,
                                       authenticating: authenticatedData(callID: callID,
                                                                         roomID: roomID,
                                                                         senderUserID: senderUserID,
                                                                         keyID: keyID))
            return [
                Self.payloadVersion,
                box.nonce.data.base64URLEncodedString(),
                box.ciphertext.base64URLEncodedString(),
                box.tag.base64URLEncodedString()
            ].joined(separator: ".")
        } catch {
            return nil
        }
    }

    private func open(encryptedPayload: String,
                      callID: String,
                      roomID: String,
                      senderUserID: String,
                      keyID: String) -> Data? {
        let parts = encryptedPayload.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4,
              parts[0] == Self.payloadVersion,
              let nonceData = Data(base64URLEncoded: parts[1]),
              let ciphertext = Data(base64URLEncoded: parts[2]),
              let tag = Data(base64URLEncoded: parts[3]) else {
            return nil
        }

        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.SealedBox(nonce: nonce,
                                            ciphertext: ciphertext,
                                            tag: tag)
            return try AES.GCM.open(box,
                                    using: encryptionKey,
                                    authenticating: authenticatedData(callID: callID,
                                                                      roomID: roomID,
                                                                      senderUserID: senderUserID,
                                                                      keyID: keyID))
        } catch {
            return nil
        }
    }

    private var encryptionKey: SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data("\(Self.purpose).aes.\(secret)".utf8)))
    }

    private var identityKey: SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data("\(Self.purpose).id.\(secret)".utf8)))
    }

    private func keyID(callID: String,
                       roomID: String,
                       senderUserID: String,
                       keyMaterial: Data) -> String {
        var data = Data()
        data.append(keyMaterial)
        data.append(authenticatedData(callID: callID,
                                      roomID: roomID,
                                      senderUserID: senderUserID,
                                      keyID: ""))
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: data, using: identityKey)
        return "diag-\(Data(authenticationCode).prefix(18).base64URLEncodedString())"
    }

    private func authenticatedData(callID: String,
                                   roomID: String,
                                   senderUserID: String,
                                   keyID: String) -> Data {
        Data("\(Self.purpose)|\(callID)|\(roomID)|\(senderUserID)|\(keyID)".utf8)
    }

    private static func randomData(count: Int) -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { keyBytes in
            Data(keyBytes.prefix(count))
        }
    }
}

private extension AES.GCM.Nonce {
    var data: Data {
        withUnsafeBytes { Data($0) }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }
}
#endif
