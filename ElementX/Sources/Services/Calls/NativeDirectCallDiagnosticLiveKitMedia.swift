//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

#if DEBUG
import Foundation

enum NativeDirectCallDiagnosticLiveKitMedia {
    static let liveKitGateEnvironmentKey = "NATIVE_DIRECT_CALL_DIAGNOSTIC_LIVEKIT"
    static let urlEnvironmentKey = "NATIVE_DIRECT_CALL_LIVEKIT_URL"
    static let tokenAEnvironmentKey = "NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_A"
    static let tokenBEnvironmentKey = "NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_B"
    static let roomEnvironmentKey = "NATIVE_DIRECT_CALL_LIVEKIT_ROOM"
    static let signallingChannelEnvironmentKey = "UI_TESTS_SIGNALLING_CHANNEL"

    @MainActor
    static func makeMediaEngineFactoryIfEnabled(encryptionService: NativeDirectCallDiagnosticEncryptionService?,
                                                environment: [String: String] = ProcessInfo.processInfo.environment,
                                                liveKitClient: DirectCallLiveKitClientProtocol? = nil) -> DirectCallMediaEngineFactoryProtocol? {
        guard ProcessInfo.isNativeDirectCallDiagnosticIntegrationLiveKitEnabled(environment: environment),
              let encryptionService,
              let tokenProvider = NativeDirectCallDiagnosticLiveKitTokenProvider(environment: environment) else {
            return nil
        }

        let e2eeContextProvider = NativeDirectCallDiagnosticLiveKitE2EEContextProvider(encryptionService: encryptionService)
        return DirectCallLiveKitMediaEngineFactory(tokenProvider: tokenProvider,
                                                   encryptionService: encryptionService,
                                                   e2eeContextProvider: e2eeContextProvider,
                                                   liveKitClient: liveKitClient ?? LiveKitDirectCallClient())
    }
}

@MainActor
final class NativeDirectCallDiagnosticLiveKitTokenProvider: DirectCallMediaTokenProviderProtocol, CustomStringConvertible, CustomDebugStringConvertible {
    private let serverURL: URL
    private let token: String
    private let roomName: String?

    init?(environment: [String: String]) {
        guard let serverURL = Self.serverURL(from: environment[NativeDirectCallDiagnosticLiveKitMedia.urlEnvironmentKey]),
              let token = Self.selectedToken(from: environment),
              !token.isEmpty else {
            return nil
        }

        self.serverURL = serverURL
        self.token = token
        roomName = Self.nonEmptyString(environment[NativeDirectCallDiagnosticLiveKitMedia.roomEnvironmentKey])
    }

    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        guard session.intent == .audio,
              session.isValidForDirectAudioPreparation,
              session.encryptionState == .ready else {
            return .failure(.tokenUnavailable)
        }

        return .success(.init(serverURL: serverURL,
                              roomName: roomName ?? session.callID,
                              token: token))
    }

    nonisolated var description: String {
        "NativeDirectCallDiagnosticLiveKitTokenProvider(serverURL: <redacted>, roomName: \(roomName ?? "<call-id>"), token: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }

    private static func selectedToken(from environment: [String: String]) -> String? {
        switch environment[NativeDirectCallDiagnosticLiveKitMedia.signallingChannelEnvironmentKey] {
        case "B":
            nonEmptyString(environment[NativeDirectCallDiagnosticLiveKitMedia.tokenBEnvironmentKey])
        default:
            nonEmptyString(environment[NativeDirectCallDiagnosticLiveKitMedia.tokenAEnvironmentKey])
        }
    }

    private static func serverURL(from value: String?) -> URL? {
        guard let value = nonEmptyString(value),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "ws", "wss"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }

        return url
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        return value
    }
}

@MainActor
final class NativeDirectCallDiagnosticLiveKitE2EEContextProvider: DirectCallMediaE2EEContextProviderProtocol {
    private let encryptionService: NativeDirectCallDiagnosticEncryptionService
    private let keyStore: DirectCallLiveKitMediaKeyStore
    private let contextProvider: DirectCallLiveKitE2EEContextProvider

    private var diagnosticState = DirectCallDiagnosticSnapshot()

    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        diagnosticState
    }

    init(encryptionService: NativeDirectCallDiagnosticEncryptionService) {
        self.encryptionService = encryptionService
        keyStore = DirectCallLiveKitMediaKeyStore()
        contextProvider = DirectCallLiveKitE2EEContextProvider(keyStore: keyStore)
    }

    init(encryptionService: NativeDirectCallDiagnosticEncryptionService,
         keyStore: DirectCallLiveKitMediaKeyStore) {
        self.encryptionService = encryptionService
        self.keyStore = keyStore
        contextProvider = DirectCallLiveKitE2EEContextProvider(keyStore: keyStore)
    }

    func context(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) -> Result<any DirectCallMediaE2EEContextProtocol, DirectCallMediaError> {
        diagnosticState.mediaE2EEProviderAvailable = true
        diagnosticState.mediaKeyHandleAvailable = !keyHandle.keyID.isEmpty && keyHandle.callID == session.callID

        switch encryptionService.storeLiveKitSharedKey(for: keyHandle, in: keyStore) {
        case .success:
            diagnosticState.mediaKeyBridgeHit = true
            let result = contextProvider.context(for: session, keyHandle: keyHandle)
            if case .failure = result {
                diagnosticState.mediaFailureReason = .e2eeContextUnavailable
            }
            return result
        case .failure:
            diagnosticState.mediaKeyBridgeHit = false
            diagnosticState.mediaFailureReason = .keyBridgeMiss
            return .failure(.e2eeContextUnavailable)
        }
    }

    func clearContext(callID: String) {
        contextProvider.clearContext(callID: callID)
    }
}

extension NativeDirectCallDiagnosticLiveKitE2EEContextProvider: DirectCallMediaDiagnosticSnapshotProviding { }
#endif
