//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

@MainActor
protocol DirectCallMediaEngineFactoryProtocol {
    func makeMediaEngine() -> Result<any DirectCallMediaEngineProtocol, DirectCallMediaError>
}

@MainActor
final class NoOpDirectCallMediaEngineFactory: DirectCallMediaEngineFactoryProtocol {
    private let tokenProvider: DirectCallMediaTokenProviderProtocol?
    private let audioRouteController: DirectCallAudioRouteControllerProtocol?
    private let encryptionService: DirectCallEncryptionServiceProtocol?

    init(tokenProvider: DirectCallMediaTokenProviderProtocol? = nil,
         audioRouteController: DirectCallAudioRouteControllerProtocol? = nil,
         encryptionService: DirectCallEncryptionServiceProtocol? = nil) {
        self.tokenProvider = tokenProvider
        self.audioRouteController = audioRouteController
        self.encryptionService = encryptionService
    }

    func makeMediaEngine() -> Result<any DirectCallMediaEngineProtocol, DirectCallMediaError> {
        .success(NoOpDirectCallMediaEngine(tokenProvider: tokenProvider,
                                           audioRouteController: audioRouteController,
                                           encryptionService: encryptionService))
    }
}

@MainActor
final class DirectCallLiveKitMediaEngineFactory: DirectCallMediaEngineFactoryProtocol {
    private let tokenProvider: DirectCallMediaTokenProviderProtocol?
    private let audioRouteController: DirectCallAudioRouteControllerProtocol?
    private let encryptionService: DirectCallEncryptionServiceProtocol?
    private let e2eeContextProvider: DirectCallMediaE2EEContextProviderProtocol?
    private let liveKitClient: DirectCallLiveKitClientProtocol?

    init(tokenProvider: DirectCallMediaTokenProviderProtocol? = nil,
         audioRouteController: DirectCallAudioRouteControllerProtocol? = nil,
         encryptionService: DirectCallEncryptionServiceProtocol? = nil,
         e2eeContextProvider: DirectCallMediaE2EEContextProviderProtocol? = nil,
         liveKitClient: DirectCallLiveKitClientProtocol? = nil) {
        self.tokenProvider = tokenProvider
        self.audioRouteController = audioRouteController
        self.encryptionService = encryptionService
        self.e2eeContextProvider = e2eeContextProvider
        self.liveKitClient = liveKitClient
    }

    func makeMediaEngine() -> Result<any DirectCallMediaEngineProtocol, DirectCallMediaError> {
        guard let tokenProvider else {
            return .failure(.tokenUnavailable)
        }

        guard let e2eeContextProvider else {
            return .failure(.e2eeContextUnavailable)
        }

        guard let liveKitClient else {
            return .failure(.mediaSetupUnavailable)
        }

        return .success(LiveKitDirectCallMediaEngine(tokenProvider: tokenProvider,
                                                     audioRouteController: audioRouteController,
                                                     encryptionService: encryptionService,
                                                     e2eeContextProvider: e2eeContextProvider,
                                                     liveKitClient: liveKitClient))
    }
}

struct NativeDirectCallProductionDependencies: CustomStringConvertible, CustomDebugStringConvertible {
    let encryptionService: DirectCallEncryptionServiceProtocol?
    let mediaEngineFactory: DirectCallMediaEngineFactoryProtocol?

    static let disabled = NativeDirectCallProductionDependencies(encryptionService: nil, mediaEngineFactory: nil)

    var hasEncryptionService: Bool {
        encryptionService != nil
    }

    var hasMediaEngineFactory: Bool {
        mediaEngineFactory != nil
    }

    var description: String {
        "NativeDirectCallProductionDependencies(encryptionServiceAvailable: \(hasEncryptionService), mediaEngineFactoryAvailable: \(hasMediaEngineFactory))"
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallProductionConfiguration: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let isEnabled: Bool
    let liveKitConfiguration: DirectCallProductionLiveKitConfiguration

    init(isEnabled: Bool = false, liveKitConfiguration: DirectCallProductionLiveKitConfiguration = .init()) {
        self.isEnabled = isEnabled
        self.liveKitConfiguration = liveKitConfiguration
    }

    init(productionConfiguration: DirectCallProductionConfiguration) {
        isEnabled = productionConfiguration.isEnabled
        liveKitConfiguration = productionConfiguration.liveKitConfiguration
    }

    var description: String {
        "NativeDirectCallProductionConfiguration(isEnabled: \(isEnabled), liveKitConfiguration: \(liveKitConfiguration))"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
struct NativeDirectCallProductionDependenciesFactory {
    private let configuration: NativeDirectCallProductionConfiguration
    private let liveKitClient: DirectCallLiveKitClientProtocol?
    private let keyWrapper: DirectCallMediaKeyWrappingProtocol?
    private let matrixSDKKeyEnvelopeWrapper: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol?
    private let matrixSDKKeyEnvelopeWrapperProvider: DirectCallMediaKeyEnvelopeWrappingProviding?
    private let mediaKeyStore: DirectCallLiveKitMediaKeyStore?
    private let ownUserID: String?
    private let senderDeviceID: String?

    init(configuration: NativeDirectCallProductionConfiguration = .init(),
         liveKitClient: DirectCallLiveKitClientProtocol? = nil,
         keyWrapper: DirectCallMediaKeyWrappingProtocol? = nil,
         matrixSDKKeyEnvelopeWrapper: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol? = nil,
         matrixSDKKeyEnvelopeWrapperProvider: DirectCallMediaKeyEnvelopeWrappingProviding? = nil,
         mediaKeyStore: DirectCallLiveKitMediaKeyStore? = nil,
         ownUserID: String? = nil,
         senderDeviceID: String? = nil) {
        self.configuration = configuration
        self.liveKitClient = liveKitClient
        self.keyWrapper = keyWrapper
        self.matrixSDKKeyEnvelopeWrapper = matrixSDKKeyEnvelopeWrapper
        self.matrixSDKKeyEnvelopeWrapperProvider = matrixSDKKeyEnvelopeWrapperProvider
        self.mediaKeyStore = mediaKeyStore
        self.ownUserID = ownUserID
        self.senderDeviceID = senderDeviceID
    }

    init(productionConfiguration: DirectCallProductionConfiguration,
         liveKitClient: DirectCallLiveKitClientProtocol? = nil,
         keyWrapper: DirectCallMediaKeyWrappingProtocol? = nil,
         matrixSDKKeyEnvelopeWrapper: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol? = nil,
         matrixSDKKeyEnvelopeWrapperProvider: DirectCallMediaKeyEnvelopeWrappingProviding? = nil,
         mediaKeyStore: DirectCallLiveKitMediaKeyStore? = nil,
         ownUserID: String? = nil,
         senderDeviceID: String? = nil) {
        configuration = .init(productionConfiguration: productionConfiguration)
        self.liveKitClient = liveKitClient
        self.keyWrapper = keyWrapper
        self.matrixSDKKeyEnvelopeWrapper = matrixSDKKeyEnvelopeWrapper
        self.matrixSDKKeyEnvelopeWrapperProvider = matrixSDKKeyEnvelopeWrapperProvider
        self.mediaKeyStore = mediaKeyStore
        self.ownUserID = ownUserID
        self.senderDeviceID = senderDeviceID
    }

    func makeDependencies() -> NativeDirectCallProductionDependencies {
        guard configuration.isEnabled,
              configuration.liveKitConfiguration.isConfigured else {
            return .disabled
        }

        let sharedKeyStore = mediaKeyStore ?? DirectCallLiveKitMediaKeyStore()
        let mediaKeyWrapper: DirectCallMediaKeyWrappingProtocol
        if let keyWrapper {
            mediaKeyWrapper = keyWrapper
        } else if let matrixSDKKeyEnvelopeWrapper {
            mediaKeyWrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: matrixSDKKeyEnvelopeWrapper)
        } else if let matrixSDKKeyEnvelopeWrapper = matrixSDKKeyEnvelopeWrapperProvider?.makeDirectCallMediaKeyEnvelopeWrapper() {
            mediaKeyWrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: matrixSDKKeyEnvelopeWrapper)
        } else {
            mediaKeyWrapper = FailClosedDirectCallMediaKeyWrapper()
        }
        let encryptionService = ProductionDirectCallEncryptionService(keyWrapper: mediaKeyWrapper,
                                                                      keyStore: sharedKeyStore,
                                                                      ownUserID: ownUserID,
                                                                      senderDeviceID: senderDeviceID)
        let tokenClient = ProductionDirectCallLiveKitTokenClient(configuration: configuration.liveKitConfiguration)
        let tokenProvider = DirectCallLiveKitTokenProvider(tokenClient: tokenClient)
        let e2eeContextProvider = DirectCallLiveKitE2EEContextProvider(keyStore: sharedKeyStore)
        let mediaEngineFactory = DirectCallLiveKitMediaEngineFactory(tokenProvider: tokenProvider,
                                                                     encryptionService: encryptionService,
                                                                     e2eeContextProvider: e2eeContextProvider,
                                                                     liveKitClient: liveKitClient ?? LiveKitDirectCallClient())

        return NativeDirectCallProductionDependencies(encryptionService: encryptionService,
                                                      mediaEngineFactory: mediaEngineFactory)
    }
}
