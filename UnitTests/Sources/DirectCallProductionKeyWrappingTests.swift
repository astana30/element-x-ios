//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

@MainActor
// swiftlint:disable:next type_body_length
final class DirectCallProductionKeyWrappingTests {
    private let callID = "call-a"
    private let roomID = "!room:example.com"
    private let peerUserID = "@peer:example.com"
    private let ownUserID = "@me:example.com"

    @Test
    func failClosedMediaKeyWrapperCannotWrapOrUnwrap() async {
        let wrapper = FailClosedDirectCallMediaKeyWrapper()
        let wrapRequest = DirectCallMediaKeyWrapRequest(callID: callID,
                                                        roomID: roomID,
                                                        senderUserID: ownUserID,
                                                        recipientUserID: peerUserID,
                                                        senderDeviceID: "DEVICE",
                                                        intent: .audio,
                                                        expiresAt: .now,
                                                        keyID: "key-a")
        let envelope = DirectCallWrappedMediaKeyEnvelope(algorithm: "test",
                                                         callID: callID,
                                                         roomID: roomID,
                                                         senderUserID: ownUserID,
                                                         recipientUserID: peerUserID,
                                                         senderDeviceID: "DEVICE",
                                                         intent: .audio,
                                                         expiresAt: .now,
                                                         keyID: "key-a",
                                                         opaqueEnvelope: "opaque-envelope")
        let unwrapRequest = DirectCallMediaKeyUnwrapRequest(expectedCallID: callID,
                                                            expectedRoomID: roomID,
                                                            expectedSenderUserID: peerUserID,
                                                            recipientUserID: ownUserID,
                                                            recipientDeviceID: "DEVICE",
                                                            intent: .audio,
                                                            receivedAt: .now)

        #expect(await wrapper.wrapMediaKey("sensitive-media-material", request: wrapRequest) == .failure(.e2eeUnavailable))
        #expect(await wrapper.unwrapMediaKeyEnvelope(envelope, request: unwrapRequest) == .failure(.e2eeUnavailable))
        #expect(String(describing: wrapper).contains("sensitive-media-material") == false)
        #expect(String(describing: wrapRequest).contains(roomID) == false)
        #expect(String(describing: envelope).contains("opaque-envelope") == false)
    }

    @Test
    func productionEncryptionWithFailClosedWrapperDoesNotPopulateKeyStore() async {
        let keyStore = DirectCallLiveKitMediaKeyStore { "key-a" }
        let service = ProductionDirectCallEncryptionService(keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE",
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)

        #expect(result == .failure(.e2eeUnavailable))
        #expect(keyStore.makeKeyProvider(for: .init(callID: callID, keyID: "key-a")) == nil)
    }

    @Test
    func productionEncryptionWithFakeWrapperStoresGeneratedKeyInSharedStore() async throws {
        let keyStore = DirectCallLiveKitMediaKeyStore { "unused-key" }
        let wrapper = MediaKeyWrapperSpy()
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE",
                                                            now: { Date(timeIntervalSince1970: 0) },
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)
        let generated = try result.get()

        #expect(generated.keyHandle == .init(callID: callID, keyID: "key-a"))
        #expect(generated.payload.encryptedPayload == "opaque-key-a")
        #expect(wrapper.wrappedMediaKeys == ["sensitive-media-material"])
        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
        #expect(String(describing: generated.payload).contains("opaque-key-a") == false)
        #expect(String(describing: wrapper.wrappedRequests[0]).contains(roomID) == false)
    }

    @Test
    func productionEncryptionWithFakeWrapperConsumesKeyIntoSharedStore() async throws {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy(unwrappedMediaKey: "sensitive-peer-media-material")
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE") {
            Date(timeIntervalSince1970: 0)
        }
        let payload = DirectCallEncryptedKeyExchangePayload(callID: callID,
                                                            roomID: roomID,
                                                            senderUserID: peerUserID,
                                                            keyID: "key-a",
                                                            encryptedPayload: "opaque-key-a")

        let result = await service.consumeRemoteEncryptedKey(payload,
                                                             expectedCallID: callID,
                                                             expectedRoomID: roomID,
                                                             expectedSenderUserID: peerUserID)
        let keyHandle = try result.get()

        #expect(keyHandle == .init(callID: callID, keyID: "key-a"))
        #expect(wrapper.unwrappedEnvelopes.map(\.opaqueEnvelope) == ["opaque-key-a"])
        #expect(keyStore.makeKeyProvider(for: keyHandle) != nil)
        #expect(String(describing: DirectCallUnwrappedMediaKey(mediaKey: "sensitive-peer-media-material", keyID: "key-a")).contains("sensitive-peer-media-material") == false)
    }

    @Test
    func productionEncryptionRejectsMismatchedWrappedMetadata() async {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy(envelopeOverride: .init(algorithm: "test",
                                                                 callID: "other-call",
                                                                 roomID: roomID,
                                                                 senderUserID: ownUserID,
                                                                 recipientUserID: peerUserID,
                                                                 intent: .audio,
                                                                 expiresAt: .now,
                                                                 keyID: "key-a",
                                                                 opaqueEnvelope: "opaque-key-a"))
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)

        #expect(result == .failure(.keyMismatch))
        #expect(keyStore.makeKeyProvider(for: .init(callID: callID, keyID: "key-a")) == nil)
    }

    @Test
    func productionEncryptionCleanupClearsSharedKeyStoreIdempotently() async throws {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy()
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })
        let generated = try await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)

        service.clearPerCallKey(callID: callID)
        service.clearPerCallKey(callID: callID)

        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) == nil)
    }

    @Test
    func productionDependenciesFactoryCanShareMediaKeyStoreWithEncryptionService() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.com/direct-calls"))
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy()
        let configuration = NativeDirectCallProductionConfiguration(isEnabled: true,
                                                                    liveKitConfiguration: .init(tokenEndpointURL: endpointURL))
        let factory = NativeDirectCallProductionDependenciesFactory(configuration: configuration,
                                                                    liveKitClient: ProductionKeyWrappingLiveKitClientSpy(),
                                                                    keyWrapper: wrapper,
                                                                    mediaKeyStore: keyStore,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")
        let dependencies = factory.makeDependencies()
        let service = try #require(dependencies.encryptionService)

        let generated = try await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
        #expect(dependencies.hasMediaEngineFactory)
        #expect(dependencies.keyWrapperSource == .explicitWrapper)
        #expect(dependencies.isReadyForProductionStart)
    }

    @Test
    func productionDependenciesFactoryCanConstructMatrixSDKKeyWrapperFromNarrowEnvelopeWrapper() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.com/direct-calls"))
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let sdk = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy()
        let configuration = NativeDirectCallProductionConfiguration(isEnabled: true,
                                                                    liveKitConfiguration: .init(tokenEndpointURL: endpointURL))
        let factory = NativeDirectCallProductionDependenciesFactory(configuration: configuration,
                                                                    liveKitClient: ProductionKeyWrappingLiveKitClientSpy(),
                                                                    matrixSDKKeyEnvelopeWrapper: sdk,
                                                                    mediaKeyStore: keyStore,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")
        let dependencies = factory.makeDependencies()
        let service = try #require(dependencies.encryptionService)

        let generated = try await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        let sdkInfo = try #require(sdk.wrapInfos.first)
        #expect(sdkInfo.roomId == roomID)
        #expect(sdkInfo.callId == callID)
        #expect(sdkInfo.recipientUserId == peerUserID)
        #expect(sdkInfo.trustRequirement == .onlyTrustedDevices)
        #expect(generated.payload.encryptedPayload == "sdk-opaque-envelope")
        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
        #expect(dependencies.hasMediaEngineFactory)
        #expect(dependencies.keyWrapperSource == .explicitSDKWrapper)
        #expect(dependencies.isReadyForProductionStart)
    }

    @Test
    func productionDependenciesFactoryPrefersExplicitKeyWrapperOverMatrixSDKEnvelopeWrapper() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.com/direct-calls"))
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let explicitWrapper = MediaKeyWrapperSpy()
        let sdk = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(wrapError: DirectCallMediaKeyEnvelopeError.TrustViolation)
        let configuration = NativeDirectCallProductionConfiguration(isEnabled: true,
                                                                    liveKitConfiguration: .init(tokenEndpointURL: endpointURL))
        let factory = NativeDirectCallProductionDependenciesFactory(configuration: configuration,
                                                                    liveKitClient: ProductionKeyWrappingLiveKitClientSpy(),
                                                                    keyWrapper: explicitWrapper,
                                                                    matrixSDKKeyEnvelopeWrapper: sdk,
                                                                    mediaKeyStore: keyStore,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")
        let dependencies = factory.makeDependencies()
        let service = try #require(dependencies.encryptionService)

        let generated = try await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        #expect(explicitWrapper.wrappedRequests.count == 1)
        #expect(sdk.wrapInfos.isEmpty)
        #expect(generated.payload.encryptedPayload == "opaque-\(generated.keyHandle.keyID)")
        #expect(explicitWrapper.wrappedRequests.first?.keyID == generated.keyHandle.keyID)
        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
    }

    @Test
    func productionDependenciesFactoryDoesNotAskRuntimeProviderWhenDisabled() {
        let provider = DirectCallMediaKeyEnvelopeWrappingProviderSpy(wrapper: MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy())
        let factory = NativeDirectCallProductionDependenciesFactory(matrixSDKKeyEnvelopeWrapperProvider: provider,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")

        let dependencies = factory.makeDependencies()

        #expect(dependencies.hasEncryptionService == false)
        #expect(dependencies.hasMediaEngineFactory == false)
        #expect(provider.makeWrapperCallCount == 0)
    }

    @Test
    func productionDependenciesFactoryCanConstructMatrixSDKKeyWrapperFromRuntimeProvider() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.com/direct-calls"))
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let sdk = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy()
        let provider = DirectCallMediaKeyEnvelopeWrappingProviderSpy(wrapper: sdk)
        let configuration = NativeDirectCallProductionConfiguration(isEnabled: true,
                                                                    liveKitConfiguration: .init(tokenEndpointURL: endpointURL))
        let factory = NativeDirectCallProductionDependenciesFactory(configuration: configuration,
                                                                    liveKitClient: ProductionKeyWrappingLiveKitClientSpy(),
                                                                    matrixSDKKeyEnvelopeWrapperProvider: provider,
                                                                    mediaKeyStore: keyStore,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")
        let dependencies = factory.makeDependencies()
        let service = try #require(dependencies.encryptionService)

        let generated = try await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        let sdkInfo = try #require(sdk.wrapInfos.first)
        #expect(provider.makeWrapperCallCount == 1)
        #expect(sdkInfo.roomId == roomID)
        #expect(sdkInfo.callId == callID)
        #expect(sdkInfo.recipientUserId == peerUserID)
        #expect(sdkInfo.trustRequirement == .onlyTrustedDevices)
        #expect(generated.payload.encryptedPayload == "sdk-opaque-envelope")
        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
        #expect(dependencies.hasMediaEngineFactory)
        #expect(dependencies.keyWrapperSource == .providerWrapper)
        #expect(dependencies.isReadyForProductionStart)
    }

    @Test
    func productionDependenciesFactoryReportsMissingRuntimeProviderWrapperAsNotReady() throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.com/direct-calls"))
        let provider = DirectCallMediaKeyEnvelopeWrappingProviderSpy(wrapper: nil)
        let configuration = NativeDirectCallProductionConfiguration(isEnabled: true,
                                                                    liveKitConfiguration: .init(tokenEndpointURL: endpointURL))
        let factory = NativeDirectCallProductionDependenciesFactory(configuration: configuration,
                                                                    liveKitClient: ProductionKeyWrappingLiveKitClientSpy(),
                                                                    matrixSDKKeyEnvelopeWrapperProvider: provider,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")

        let dependencies = factory.makeDependencies()

        #expect(dependencies.hasEncryptionService)
        #expect(dependencies.hasMediaEngineFactory)
        #expect(dependencies.keyWrapperSource == .missingProvider)
        #expect(dependencies.isReadyForProductionStart == false)
        #expect(provider.makeWrapperCallCount == 1)
        #expect(String(describing: dependencies).contains("missingProvider"))
        #expect(String(describing: dependencies).contains("call-service.example.com") == false)
    }

    @Test
    func productionDependencyAssemblyIsDisabledByDefault() {
        let assembly = NativeDirectCallProductionDependencyAssembly()

        let dependencies = assembly.makeDependencies()

        #expect(dependencies.hasEncryptionService == false)
        #expect(dependencies.hasMediaEngineFactory == false)
        #expect(String(describing: assembly).contains("http://") == false)
        #expect(String(describing: dependencies).contains("Diagnostic") == false)
    }

    @Test
    func productionDependencyAssemblyRequiresRuntimeProviders() throws {
        let baseURL = try #require(URL(string: "https://call-service.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true, tokenEndpointBaseURL: baseURL)
        let httpTransport = DirectCallHTTPTransportSpy()
        let accessTokenProvider = MatrixAccessTokenProviderStub(accessToken: "matrix-credential")
        let liveKitClient = ProductionKeyWrappingLiveKitClientSpy()
        let keyEnvelopeWrapperProvider = DirectCallMediaKeyEnvelopeWrappingProviderSpy(wrapper: MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy())

        let missingHTTPTransport = NativeDirectCallProductionDependencyAssembly(configuration: configuration,
                                                                                accessTokenProvider: accessTokenProvider,
                                                                                liveKitClient: liveKitClient,
                                                                                keyEnvelopeWrapperProvider: keyEnvelopeWrapperProvider,
                                                                                ownUserID: ownUserID).makeDependencies()
        let missingAccessTokenProvider = NativeDirectCallProductionDependencyAssembly(configuration: configuration,
                                                                                      httpTransport: httpTransport,
                                                                                      liveKitClient: liveKitClient,
                                                                                      keyEnvelopeWrapperProvider: keyEnvelopeWrapperProvider,
                                                                                      ownUserID: ownUserID).makeDependencies()
        let missingLiveKitClient = NativeDirectCallProductionDependencyAssembly(configuration: configuration,
                                                                                httpTransport: httpTransport,
                                                                                accessTokenProvider: accessTokenProvider,
                                                                                keyEnvelopeWrapperProvider: keyEnvelopeWrapperProvider,
                                                                                ownUserID: ownUserID).makeDependencies()
        let missingKeyEnvelopeProvider = NativeDirectCallProductionDependencyAssembly(configuration: configuration,
                                                                                      httpTransport: httpTransport,
                                                                                      accessTokenProvider: accessTokenProvider,
                                                                                      liveKitClient: liveKitClient,
                                                                                      ownUserID: ownUserID).makeDependencies()
        let missingOwnUserID = NativeDirectCallProductionDependencyAssembly(configuration: configuration,
                                                                            httpTransport: httpTransport,
                                                                            accessTokenProvider: accessTokenProvider,
                                                                            liveKitClient: liveKitClient,
                                                                            keyEnvelopeWrapperProvider: keyEnvelopeWrapperProvider).makeDependencies()

        for dependencies in [missingHTTPTransport, missingAccessTokenProvider, missingLiveKitClient, missingKeyEnvelopeProvider, missingOwnUserID] {
            #expect(dependencies.hasEncryptionService == false)
            #expect(dependencies.hasMediaEngineFactory == false)
            #expect(dependencies.isReadyForProductionStart == false)
        }
    }

    @Test
    func productionDependencyAssemblyReportsUnavailableWrapperFromRuntimeProviderAsNotReady() throws {
        let baseURL = try #require(URL(string: "https://call-service.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true, tokenEndpointBaseURL: baseURL)
        let provider = DirectCallMediaKeyEnvelopeWrappingProviderSpy(wrapper: nil)
        let assembly = NativeDirectCallProductionDependencyAssembly(configuration: configuration,
                                                                    httpTransport: DirectCallHTTPTransportSpy(),
                                                                    accessTokenProvider: MatrixAccessTokenProviderStub(accessToken: "matrix-credential"),
                                                                    liveKitClient: ProductionKeyWrappingLiveKitClientSpy(),
                                                                    keyEnvelopeWrapperProvider: provider,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")

        let dependencies = assembly.makeDependencies()

        #expect(dependencies.hasEncryptionService)
        #expect(dependencies.hasMediaEngineFactory)
        #expect(dependencies.keyWrapperSource == .missingProvider)
        #expect(dependencies.isReadyForProductionStart == false)
        #expect(provider.makeWrapperCallCount == 1)
        #expect(String(describing: dependencies).contains("missingProvider"))
        #expect(String(describing: assembly).contains(baseURL.absoluteString) == false)
    }

    @Test
    func productionDependencyAssemblyBuildsConfiguredDependenciesFromRuntimeProviders() async throws {
        let baseURL = try #require(URL(string: "https://call-service.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true, tokenEndpointBaseURL: baseURL)
        let responseData = Data("""
        {
          "version": 1,
          "livekit": {
            "server_url": "wss://livekit.example.test",
            "room_name": "assembled-room",
            "participant_token": "participant-credential",
            "expires_at": "2026-05-11T12:00:00Z"
          },
          "allocation": {
            "id": "allocation-a",
            "call_id": "call-a",
            "intent": "audio"
          }
        }
        """.utf8)
        let httpTransport = DirectCallHTTPTransportSpy(result: .success(.init(statusCode: 200, data: responseData)))
        let accessTokenProvider = MatrixAccessTokenProviderStub(accessToken: "matrix-credential")
        let liveKitClient = ProductionKeyWrappingLiveKitClientSpy()
        let sdk = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy()
        let keyEnvelopeWrapperProvider = DirectCallMediaKeyEnvelopeWrappingProviderSpy(wrapper: sdk)
        let assembly = NativeDirectCallProductionDependencyAssembly(configuration: configuration,
                                                                    httpTransport: httpTransport,
                                                                    accessTokenProvider: accessTokenProvider,
                                                                    liveKitClient: liveKitClient,
                                                                    keyEnvelopeWrapperProvider: keyEnvelopeWrapperProvider,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")
        let dependencies = assembly.makeDependencies()
        let encryptionService = try #require(dependencies.encryptionService)
        let mediaEngineFactory = try #require(dependencies.mediaEngineFactory)
        let generated = try await encryptionService.generatePerCallKey(callID: callID,
                                                                       roomID: roomID,
                                                                       peerUserID: peerUserID).get()
        let mediaEngine = try mediaEngineFactory.makeMediaEngine().get()
        let session = makeMediaReadySession()

        let connectResult = await mediaEngine.connectAudio(for: session, keyHandle: generated.keyHandle)

        guard case .success = connectResult else {
            Issue.record("Expected fully injected production assembly to connect through fake runtime dependencies.")
            return
        }
        #expect(dependencies.hasEncryptionService)
        #expect(dependencies.hasMediaEngineFactory)
        #expect(dependencies.keyWrapperSource == .providerWrapper)
        #expect(dependencies.isReadyForProductionStart)
        #expect(keyEnvelopeWrapperProvider.makeWrapperCallCount == 1)
        #expect(sdk.wrapInfos.count == 1)
        #expect(httpTransport.requests.count == 1)
        #expect(httpTransport.requests.first?.headers["Authorization"] == "Bearer matrix-credential")
        #expect(liveKitClient.connectionInfos.map(\.roomName) == ["assembled-room"])
        #expect(String(describing: assembly).contains(baseURL.absoluteString) == false)
        #expect(String(describing: mediaEngineFactory).contains("participant-credential") == false)
    }

    @Test
    func productionActivationGateIsDisabledByDefault() {
        let decision = DirectCallProductionActivationGate().evaluate(.init())

        #expect(decision == .disabled(.appRolloutDisabled))
        #expect(decision.isEnabled == false)
        #expect(String(describing: decision).contains("https://") == false)
        #expect(String(describing: DirectCallProductionServerCapability()).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
    }

    @Test
    func productionServerCapabilityDecodesContractJSONAndRedactsEndpoint() throws {
        let data = Data("""
        {
          "enabled": true,
          "version": 1,
          "token_endpoint": "/_matrix/client/unstable/kz.salemx.direct_call/livekit/token",
          "intents": ["audio"],
          "media_transport": "livekit",
          "e2ee_required": true,
          "key_envelope": "matrix_sdk_direct_call_media_key_envelope_v1"
        }
        """.utf8)

        let capability = try JSONDecoder().decode(DirectCallProductionServerCapability.self, from: data)

        #expect(capability.isEnabled)
        #expect(capability.supportsIntent(.audio))
        #expect(capability.mediaTransport == DirectCallProductionServerCapability.liveKitMediaTransport)
        #expect(capability.keyEnvelope == DirectCallProductionServerCapability.matrixSDKKeyEnvelope)
        #expect(String(describing: capability).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
    }

    @Test
    func productionCapabilityProviderFailsClosedByDefault() async {
        let provider = FailClosedDirectCallProductionCapabilityProvider()

        let result = await provider.directCallProductionServerCapability()

        #expect(result == .unavailable(.providerUnavailable))
        #expect(result.isAvailable == false)
        #expect(String(describing: provider).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
        #expect(String(describing: result).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
    }

    @Test
    func productionCapabilityDiscoveryDecodesEnvelopeAndEnablesActivationModel() throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let result = DirectCallProductionCapabilityPayloadDecoder().decodeCapability(from: makeCapabilitiesPayload())
        let capability = try #require(result.capability)

        let decision = DirectCallProductionActivationGate().evaluate(makeActivationContext(homeserverBaseURL: homeserverBaseURL,
                                                                                           serverCapability: capability))

        #expect(result.failureReason == nil)
        #expect(result.isAvailable)
        #expect(decision.isEnabled)
        #expect(decision.tokenEndpointURL?.host == "matrix.example.com")
        #expect(decision.tokenEndpointURL?.path == DirectCallProductionConfiguration.tokenEndpointPath)
        #expect(String(describing: result).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
        #expect(String(describing: decision).contains("matrix.example.com") == false)
    }

    @Test
    func productionCapabilityDiscoveryMissingCapabilityFailsClosed() throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let data = Data("""
        {
          "capabilities": {
            "m.room_versions": {
              "default": "1"
            }
          }
        }
        """.utf8)

        let result = DirectCallProductionCapabilityPayloadDecoder().decodeCapability(from: data)
        let decision = DirectCallProductionActivationGate().evaluate(makeActivationContext(homeserverBaseURL: homeserverBaseURL,
                                                                                           serverCapability: result.capability))

        #expect(result == .unavailable(.missingCapability))
        #expect(decision == .disabled(.serverCapabilityUnavailable))
    }

    @Test
    func productionCapabilityDiscoveryMalformedCapabilityFailsClosed() {
        let data = Data("""
        {
          "capabilities": {
            "\(DirectCallProductionServerCapability.capabilityName)": {
              "enabled": true,
              "version": "1"
            }
          }
        }
        """.utf8)

        let result = DirectCallProductionCapabilityPayloadDecoder().decodeCapability(from: data)

        #expect(result == .unavailable(.malformedCapability))
    }

    @Test
    func productionCapabilityDiscoveryFeedsUnsupportedCapabilitiesToActivationGate() throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let decoder = DirectCallProductionCapabilityPayloadDecoder()
        let cases: [(Data, DirectCallProductionActivationDisabledReason)] = [
            (makeCapabilitiesPayload(tokenEndpointPath: "https://calls.example.net/token"), .tokenEndpointUnavailable),
            (makeCapabilitiesPayload(mediaTransport: "unknown"), .unsupportedMediaTransport),
            (makeCapabilitiesPayload(isE2EERequired: false), .e2eeNotRequiredByCapability),
            (makeCapabilitiesPayload(keyEnvelope: "unknown"), .unsupportedKeyEnvelope)
        ]

        for (data, reason) in cases {
            let result = decoder.decodeCapability(from: data)
            let decision = DirectCallProductionActivationGate().evaluate(makeActivationContext(homeserverBaseURL: homeserverBaseURL,
                                                                                               serverCapability: result.capability))

            #expect(result.isAvailable)
            #expect(decision == .disabled(reason))
        }
    }

    @Test
    func productionCapabilityDiscoveryAcceptsDirectCapabilityPayloadForTestsOnly() throws {
        let capability = DirectCallProductionCapabilityPayloadDecoder().decodeCapability(from: makeCapabilityPayload())
        let discovered = try #require(capability.capability)

        #expect(discovered.isEnabled)
        #expect(discovered.supportsIntent(.audio))
    }

    @Test
    func productionActivationDecisionServiceDisabledConfigFailsClosedWithoutQueryingProviders() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let decision = await service.directCallProductionActivationDecision(homeserverBaseURL: homeserverBaseURL,
                                                                            roomEligibility: makeRoomEligibility())

        #expect(decision == .disabled(.appRolloutDisabled))
        #expect(capabilityProvider.callCount == 0)
        #expect(dependencyProvider.callCount == 0)
        #expect(String(describing: service).contains("matrix.example.com") == false)
        #expect(String(describing: service).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
    }

    @Test
    func productionActivationDecisionServiceMissingCapabilityFailsClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .unavailable(.missingCapability))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let decision = await service.directCallProductionActivationDecision(homeserverBaseURL: homeserverBaseURL,
                                                                            roomEligibility: makeRoomEligibility())

        #expect(decision == .disabled(.serverCapabilityUnavailable))
        #expect(capabilityProvider.callCount == 1)
        #expect(dependencyProvider.callCount == 0)
    }

    @Test
    func productionActivationDecisionServiceMalformedCapabilityFailsClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .unavailable(.malformedCapability))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let decision = await service.directCallProductionActivationDecision(homeserverBaseURL: homeserverBaseURL,
                                                                            roomEligibility: makeRoomEligibility())

        #expect(decision == .disabled(.serverCapabilityUnavailable))
        #expect(capabilityProvider.callCount == 1)
        #expect(dependencyProvider.callCount == 0)
    }

    @Test
    func productionActivationDecisionServiceUnsupportedCapabilityFailsClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .available(makeServerCapability(mediaTransport: "unknown")))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let decision = await service.directCallProductionActivationDecision(homeserverBaseURL: homeserverBaseURL,
                                                                            roomEligibility: makeRoomEligibility())

        #expect(decision == .disabled(.unsupportedMediaTransport))
        #expect(capabilityProvider.callCount == 1)
        #expect(dependencyProvider.callCount == 1)
    }

    @Test
    func productionActivationDecisionServiceExternalEndpointFailsClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .available(makeServerCapability(tokenEndpointPath: "https://calls.example.net/token")))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let decision = await service.directCallProductionActivationDecision(homeserverBaseURL: homeserverBaseURL,
                                                                            roomEligibility: makeRoomEligibility())

        #expect(decision == .disabled(.tokenEndpointUnavailable))
    }

    @Test
    func productionActivationDecisionServiceDependenciesUnavailableFailsClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: .disabled)
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let decision = await service.directCallProductionActivationDecision(homeserverBaseURL: homeserverBaseURL,
                                                                            roomEligibility: makeRoomEligibility())

        #expect(decision == .disabled(.dependenciesUnavailable))
    }

    @Test
    func productionActivationDecisionServiceRoomIneligibleFailsClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let decision = await service.directCallProductionActivationDecision(homeserverBaseURL: homeserverBaseURL,
                                                                            roomEligibility: makeRoomEligibility(isEncrypted: false))

        #expect(decision == .disabled(.roomNotEncrypted))
    }

    @Test
    func productionActivationDecisionServiceEnablesOnlyWhenAllInputsAreValid() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let decision = await service.directCallProductionActivationDecision(homeserverBaseURL: homeserverBaseURL,
                                                                            roomEligibility: makeRoomEligibility())

        #expect(decision.isEnabled)
        #expect(decision.disabledReason == nil)
        #expect(decision.tokenEndpointURL?.host == "matrix.example.com")
        #expect(decision.tokenEndpointURL?.path == DirectCallProductionConfiguration.tokenEndpointPath)
        #expect(String(describing: decision).contains("matrix.example.com") == false)
    }

    @Test
    func productionActivationDryRunDisabledByDefaultIsRedactedAndHasNoProviderSideEffects() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.isEnabled == false)
        #expect(diagnostic.disabledReason == .appRolloutDisabled)
        #expect(diagnostic.isCapabilityPresent == false)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted == false)
        #expect(capabilityProvider.callCount == 0)
        #expect(dependencyProvider.callCount == 0)
        #expect(String(describing: diagnostic).contains("matrix.example.com") == false)
        #expect(String(describing: diagnostic).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
    }

    @Test
    func productionActivationDryRunMissingCapabilityReturnsRedactedReason() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .unavailable(.missingCapability))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.isEnabled == false)
        #expect(diagnostic.disabledReason == .serverCapabilityUnavailable)
        #expect(diagnostic.isCapabilityPresent == false)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted == false)
        #expect(capabilityProvider.callCount == 1)
        #expect(dependencyProvider.callCount == 0)
    }

    @Test
    func productionActivationDryRunBadRoomEligibilityReturnsRedactedReason() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility(isEncrypted: false))

        #expect(diagnostic.isEnabled == false)
        #expect(diagnostic.disabledReason == .roomNotEncrypted)
        #expect(diagnostic.isCapabilityPresent)
        #expect(diagnostic.areDependenciesReady)
        #expect(diagnostic.isRoomEligible == false)
        #expect(diagnostic.isEndpointAccepted)
    }

    @Test
    func productionActivationDryRunAllValidReturnsEnabledModelWithoutStartingRuntimeWork() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuration = DirectCallProductionConfiguration(isEnabled: true)
        let capabilityProvider = DirectCallProductionCapabilityProviderSpy(result: .available(makeServerCapability()))
        let encryptionService = ProductionActivationEncryptionServiceSpy()
        let mediaEngineFactory = ProductionActivationMediaEngineFactorySpy()
        let dependencyProvider = NativeDirectCallProductionDependencyProviderSpy(dependencies: NativeDirectCallProductionDependencies(encryptionService: encryptionService,
                                                                                                                                      mediaEngineFactory: mediaEngineFactory,
                                                                                                                                      keyWrapperSource: .explicitWrapper))
        let service = DirectCallProductionActivationDecisionService(configuration: configuration,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.isEnabled)
        #expect(diagnostic.disabledReason == nil)
        #expect(diagnostic.isCapabilityPresent)
        #expect(diagnostic.areDependenciesReady)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted)
        #expect(capabilityProvider.callCount == 1)
        #expect(dependencyProvider.callCount == 1)
        #expect(encryptionService.generateKeyCallCount == 0)
        #expect(encryptionService.consumeKeyCallCount == 0)
        #expect(encryptionService.clearKeyCallCount == 0)
        #expect(mediaEngineFactory.makeMediaEngineCallCount == 0)
    }

    @Test
    func productionActivationGateFailsClosedForMissingPrerequisites() throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let externalEndpointURL = try #require(URL(string: "https://calls.example.net/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"))
        let gate = DirectCallProductionActivationGate()
        let failClosedDependencies = NativeDirectCallProductionDependencies(encryptionService: ProductionDirectCallEncryptionService(),
                                                                            mediaEngineFactory: NoOpDirectCallMediaEngineFactory(),
                                                                            keyWrapperSource: .failClosedWrapper)
        let failureCases: [(DirectCallProductionActivationContext, DirectCallProductionActivationDisabledReason)] = [
            (makeActivationContext(appRolloutEnabled: false, homeserverBaseURL: homeserverBaseURL), .appRolloutDisabled),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, serverCapability: nil), .serverCapabilityUnavailable),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, serverCapability: makeServerCapability(isEnabled: false)), .serverCapabilityDisabled),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, serverCapability: makeServerCapability(version: 2)), .unsupportedCapabilityVersion),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, serverCapability: makeServerCapability(intents: ["video"])), .unsupportedIntent),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, serverCapability: makeServerCapability(mediaTransport: "unknown")), .unsupportedMediaTransport),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, serverCapability: makeServerCapability(isE2EERequired: false)), .e2eeNotRequiredByCapability),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, serverCapability: makeServerCapability(keyEnvelope: "unknown")), .unsupportedKeyEnvelope),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, serverCapability: makeServerCapability(tokenEndpointPath: "https://calls.example.net/token")), .tokenEndpointUnavailable),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, configuredTokenEndpointURL: externalEndpointURL), .tokenEndpointNotSameOrigin),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, dependencies: .disabled), .dependenciesUnavailable),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, dependencies: failClosedDependencies), .dependenciesUnavailable),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, roomEligibility: makeRoomEligibility(isEncrypted: false)), .roomNotEncrypted),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, roomEligibility: makeRoomEligibility(isDirect: false)), .roomNotDirect),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, roomEligibility: makeRoomEligibility(joinedMemberCount: 3)), .roomNotOneToOne),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, roomEligibility: makeRoomEligibility(hasPeerUserID: false)), .peerUnavailable),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, peerTrustReadiness: .peerTrustUnavailable), .peerTrustUnavailable),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, peerTrustReadiness: .unverifiedDevice), .unverifiedDevice),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, peerTrustReadiness: .noEligibleDevice), .noEligibleDevice),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, peerTrustReadiness: .crossSigningUnavailable), .crossSigningUnavailable),
            (makeActivationContext(homeserverBaseURL: homeserverBaseURL, peerTrustReadiness: .unknown), .peerTrustUnknown)
        ]

        for (context, reason) in failureCases {
            let decision = gate.evaluate(context)

            #expect(decision == .disabled(reason))
        }
    }

    @Test
    func productionActivationGateEnablesOnlyWhenAllModeledConditionsPass() throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let decision = DirectCallProductionActivationGate().evaluate(makeActivationContext(homeserverBaseURL: homeserverBaseURL))

        #expect(decision.isEnabled)
        #expect(decision.disabledReason == nil)
        #expect(decision.tokenEndpointURL?.scheme == "https")
        #expect(decision.tokenEndpointURL?.host == "matrix.example.com")
        #expect(decision.tokenEndpointURL?.path == DirectCallProductionConfiguration.tokenEndpointPath)
        #expect(String(describing: decision).contains("matrix.example.com") == false)
    }

    @Test
    func productionActivationGateAllowsSameOriginConfiguredEndpoint() throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let configuredEndpointURL = try #require(URL(string: "https://matrix.example.com/_salemx/direct-call/v1/livekit/token"))
        let decision = DirectCallProductionActivationGate().evaluate(makeActivationContext(homeserverBaseURL: homeserverBaseURL,
                                                                                           configuredTokenEndpointURL: configuredEndpointURL))

        #expect(decision.isEnabled)
        #expect(decision.tokenEndpointURL?.path == "/_salemx/direct-call/v1/livekit/token")
    }

    @Test
    func productionDependenciesFactoryPrefersExplicitKeyWrapperOverRuntimeProvider() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.com/direct-calls"))
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let explicitWrapper = MediaKeyWrapperSpy()
        let provider = DirectCallMediaKeyEnvelopeWrappingProviderSpy(wrapper: MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(wrapError: DirectCallMediaKeyEnvelopeError.TrustViolation))
        let configuration = NativeDirectCallProductionConfiguration(isEnabled: true,
                                                                    liveKitConfiguration: .init(tokenEndpointURL: endpointURL))
        let factory = NativeDirectCallProductionDependenciesFactory(configuration: configuration,
                                                                    liveKitClient: ProductionKeyWrappingLiveKitClientSpy(),
                                                                    keyWrapper: explicitWrapper,
                                                                    matrixSDKKeyEnvelopeWrapperProvider: provider,
                                                                    mediaKeyStore: keyStore,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")
        let dependencies = factory.makeDependencies()
        let service = try #require(dependencies.encryptionService)

        let generated = try await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        #expect(explicitWrapper.wrappedRequests.count == 1)
        #expect(provider.makeWrapperCallCount == 0)
        #expect(generated.payload.encryptedPayload == "opaque-\(generated.keyHandle.keyID)")
        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
    }

    @Test
    func matrixSDKWrapperFailsClosedWithoutSDKDependency() async {
        let wrapper = MatrixSDKDirectCallMediaKeyWrapper()
        let wrapRequest = makeWrapRequest()
        let envelope = makeWrappedEnvelope()
        let unwrapRequest = makeUnwrapRequest()

        #expect(await wrapper.wrapMediaKey("sensitive-media-material", request: wrapRequest) == .failure(.sdkWrapperUnavailable))
        #expect(await wrapper.unwrapMediaKeyEnvelope(envelope, request: unwrapRequest) == .failure(.sdkWrapperUnavailable))
        #expect(String(describing: wrapper).contains("sensitive-media-material") == false)
        #expect(String(reflecting: wrapper).contains("sensitive-media-material") == false)
    }

    @Test
    func matrixSDKWrapperMapsWrapRequestAndEnvelopeWithoutLeakingKeyMaterial() async throws {
        let sdk = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(wrapEnvelope: makeSDKEnvelope())
        let wrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: sdk, trustRequirement: .allDevices)
        let request = makeWrapRequest(expiresAt: Date(timeIntervalSince1970: 2))

        let result = await wrapper.wrapMediaKey("sensitive-media-material", request: request)
        let envelope = try result.get()

        let sdkInfo = try #require(sdk.wrapInfos.first)
        #expect(sdkInfo.roomId == roomID)
        #expect(sdkInfo.callId == callID)
        #expect(sdkInfo.recipientUserId == peerUserID)
        #expect(sdkInfo.intent == DirectCallIntent.audio.rawValue)
        #expect(sdkInfo.keyId == "key-a")
        #expect(sdkInfo.expiresAtMs == 2000)
        #expect(sdkInfo.mediaKey == "sensitive-media-material")
        #expect(sdkInfo.trustRequirement == .allDevices)
        #expect(envelope.callID == callID)
        #expect(envelope.roomID == roomID)
        #expect(envelope.senderUserID == ownUserID)
        #expect(envelope.recipientUserID == peerUserID)
        #expect(envelope.opaqueEnvelope == "sdk-opaque-envelope")
        #expect(String(describing: envelope).contains("sdk-opaque-envelope") == false)
    }

    @Test
    func matrixSDKWrapperMapsUnwrapRequestAndResultWithoutLeakingKeyMaterial() async throws {
        let sdk = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(unwrapResult: .init(keyId: "key-a",
                                                                                    mediaKey: "sensitive-peer-media-material",
                                                                                    senderUserId: peerUserID,
                                                                                    senderDeviceId: "PEER_DEVICE"))
        let wrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: sdk)
        let envelope = makeWrappedEnvelope(senderUserID: peerUserID,
                                           recipientUserID: ownUserID,
                                           opaqueEnvelope: "sdk-opaque-envelope")
        let request = makeUnwrapRequest(receivedAt: Date(timeIntervalSince1970: 3))

        let result = await wrapper.unwrapMediaKeyEnvelope(envelope, request: request)
        let unwrapped = try result.get()

        let sdkInfo = try #require(sdk.unwrapInfos.first)
        let sdkEnvelope = try #require(sdk.unwrapEnvelopes.first)
        #expect(sdkInfo.roomId == roomID)
        #expect(sdkInfo.callId == callID)
        #expect(sdkInfo.expectedSenderUserId == peerUserID)
        #expect(sdkInfo.expectedRecipientUserId == ownUserID)
        #expect(sdkInfo.intent == DirectCallIntent.audio.rawValue)
        #expect(sdkInfo.keyId == "key-a")
        #expect(sdkInfo.receivedAtMs == 3000)
        #expect(sdkEnvelope.opaqueCiphertext == "sdk-opaque-envelope")
        #expect(unwrapped.keyID == "key-a")
        #expect(unwrapped.mediaKey == "sensitive-peer-media-material")
        #expect(String(describing: unwrapped).contains("sensitive-peer-media-material") == false)
    }

    @Test
    func matrixSDKWrapperMapsSDKFailuresToFailClosedReasons() async {
        let trustFailureSDK = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(wrapError: DirectCallMediaKeyEnvelopeError.TrustViolation)
        let noEligibleDeviceSDK = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(wrapError: DirectCallMediaKeyEnvelopeError.NoEligibleDevices)
        let genericFailureSDK = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(wrapError: MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpyError.genericFailure)
        let metadataFailureSDK = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(unwrapError: DirectCallMediaKeyEnvelopeError.MalformedEnvelope)
        let wrappingWrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: trustFailureSDK)
        let noEligibleDeviceWrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: noEligibleDeviceSDK)
        let genericFailureWrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: genericFailureSDK)
        let unwrappingWrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: metadataFailureSDK)

        #expect(await wrappingWrapper.wrapMediaKey("sensitive-media-material",
                                                   request: makeWrapRequest()) == .failure(.sdkTrustViolation))
        #expect(await noEligibleDeviceWrapper.wrapMediaKey("sensitive-media-material",
                                                           request: makeWrapRequest()) == .failure(.sdkNoEligibleDevice))
        #expect(await genericFailureWrapper.wrapMediaKey("sensitive-media-material",
                                                         request: makeWrapRequest()) == .failure(.sdkEnvelopeFailed))
        #expect(await unwrappingWrapper.unwrapMediaKeyEnvelope(makeWrappedEnvelope(),
                                                               request: makeUnwrapRequest()) == .failure(.invalidMetadata))
    }

    private func makeWrapRequest(expiresAt: Date = Date(timeIntervalSince1970: 1)) -> DirectCallMediaKeyWrapRequest {
        .init(callID: callID,
              roomID: roomID,
              senderUserID: ownUserID,
              recipientUserID: peerUserID,
              senderDeviceID: "DEVICE",
              intent: .audio,
              expiresAt: expiresAt,
              keyID: "key-a")
    }

    private func makeUnwrapRequest(receivedAt: Date = Date(timeIntervalSince1970: 1)) -> DirectCallMediaKeyUnwrapRequest {
        .init(expectedCallID: callID,
              expectedRoomID: roomID,
              expectedSenderUserID: peerUserID,
              recipientUserID: ownUserID,
              recipientDeviceID: "DEVICE",
              intent: .audio,
              receivedAt: receivedAt)
    }

    private func makeWrappedEnvelope(senderUserID: String? = nil,
                                     recipientUserID: String? = nil,
                                     opaqueEnvelope: String = "opaque-key-a") -> DirectCallWrappedMediaKeyEnvelope {
        .init(algorithm: "salemx.native_direct_call.media_key.v1",
              callID: callID,
              roomID: roomID,
              senderUserID: senderUserID ?? ownUserID,
              recipientUserID: recipientUserID ?? peerUserID,
              senderDeviceID: "DEVICE",
              intent: .audio,
              expiresAt: Date(timeIntervalSince1970: 1),
              keyID: "key-a",
              opaqueEnvelope: opaqueEnvelope)
    }

    private func makeSDKEnvelope() -> MatrixRustSDK.DirectCallMediaKeyEnvelope {
        .init(version: 1,
              algorithm: "salemx.native_direct_call.media_key.v1",
              roomId: roomID,
              callId: callID,
              senderUserId: ownUserID,
              recipientUserId: peerUserID,
              intent: DirectCallIntent.audio.rawValue,
              keyId: "key-a",
              expiresAtMs: 1000,
              opaqueCiphertext: "sdk-opaque-envelope")
    }

    private func makeMediaReadySession() -> DirectCallSession {
        DirectCallSession(callID: callID,
                          roomID: roomID,
                          peerUserID: peerUserID,
                          direction: .outgoing,
                          intent: .audio,
                          encryptionMode: .e2eeRequired,
                          startedAt: .now,
                          updatedAt: .now,
                          state: .connecting,
                          encryptionState: .ready)
    }

    private func makeActivationContext(appRolloutEnabled: Bool = true,
                                       homeserverBaseURL: URL,
                                       serverCapability: DirectCallProductionServerCapability? = DirectCallProductionServerCapability(isEnabled: true,
                                                                                                                                      intents: [DirectCallIntent.audio.rawValue]),
                                       configuredTokenEndpointURL: URL? = nil,
                                       dependencies: NativeDirectCallProductionDependencies? = nil,
                                       roomEligibility: DirectCallProductionRoomEligibility = DirectCallProductionRoomEligibility(isDirect: true,
                                                                                                                                  isEncrypted: true,
                                                                                                                                  joinedMemberCount: 2,
                                                                                                                                  hasPeerUserID: true),
                                       peerTrustReadiness: DirectCallPeerTrustReadiness = .peerTrustReady) -> DirectCallProductionActivationContext {
        DirectCallProductionActivationContext(appRolloutEnabled: appRolloutEnabled,
                                              homeserverBaseURL: homeserverBaseURL,
                                              serverCapability: serverCapability,
                                              configuredTokenEndpointURL: configuredTokenEndpointURL,
                                              dependencies: dependencies ?? makeActivationReadyDependencies(),
                                              roomEligibility: roomEligibility,
                                              peerTrustReadiness: peerTrustReadiness)
    }

    private func makeServerCapability(isEnabled: Bool = true,
                                      version: Int = DirectCallProductionServerCapability.supportedVersion,
                                      tokenEndpointPath: String? = DirectCallProductionConfiguration.tokenEndpointPath,
                                      intents: Set<String> = [DirectCallIntent.audio.rawValue],
                                      mediaTransport: String = DirectCallProductionServerCapability.liveKitMediaTransport,
                                      isE2EERequired: Bool = true,
                                      keyEnvelope: String = DirectCallProductionServerCapability.matrixSDKKeyEnvelope) -> DirectCallProductionServerCapability {
        DirectCallProductionServerCapability(isEnabled: isEnabled,
                                             version: version,
                                             tokenEndpointPath: tokenEndpointPath,
                                             intents: intents,
                                             mediaTransport: mediaTransport,
                                             isE2EERequired: isE2EERequired,
                                             keyEnvelope: keyEnvelope)
    }

    private func makeRoomEligibility(isDirect: Bool = true,
                                     isEncrypted: Bool = true,
                                     joinedMemberCount: Int? = 2,
                                     hasPeerUserID: Bool = true) -> DirectCallProductionRoomEligibility {
        DirectCallProductionRoomEligibility(isDirect: isDirect,
                                            isEncrypted: isEncrypted,
                                            joinedMemberCount: joinedMemberCount,
                                            hasPeerUserID: hasPeerUserID)
    }

    private func makeActivationReadyDependencies() -> NativeDirectCallProductionDependencies {
        NativeDirectCallProductionDependencies(encryptionService: ProductionDirectCallEncryptionService(),
                                               mediaEngineFactory: NoOpDirectCallMediaEngineFactory(),
                                               keyWrapperSource: .explicitWrapper)
    }

    private func makeCapabilitiesPayload(tokenEndpointPath: String = DirectCallProductionConfiguration.tokenEndpointPath,
                                         mediaTransport: String = DirectCallProductionServerCapability.liveKitMediaTransport,
                                         isE2EERequired: Bool = true,
                                         keyEnvelope: String = DirectCallProductionServerCapability.matrixSDKKeyEnvelope) -> Data {
        Data("""
        {
          "capabilities": {
            "\(DirectCallProductionServerCapability.capabilityName)": \(makeCapabilityJSONString(tokenEndpointPath: tokenEndpointPath,
                                                                                                 mediaTransport: mediaTransport,
                                                                                                 isE2EERequired: isE2EERequired,
                                                                                                 keyEnvelope: keyEnvelope)),
            "m.room_versions": {
              "default": "1"
            }
          }
        }
        """.utf8)
    }

    private func makeCapabilityPayload() -> Data {
        Data(makeCapabilityJSONString().utf8)
    }

    private func makeCapabilityJSONString(tokenEndpointPath: String = DirectCallProductionConfiguration.tokenEndpointPath,
                                          mediaTransport: String = DirectCallProductionServerCapability.liveKitMediaTransport,
                                          isE2EERequired: Bool = true,
                                          keyEnvelope: String = DirectCallProductionServerCapability.matrixSDKKeyEnvelope) -> String {
        """
        {
          "enabled": true,
          "version": 1,
          "token_endpoint": "\(tokenEndpointPath)",
          "intents": ["audio"],
          "media_transport": "\(mediaTransport)",
          "e2ee_required": \(isE2EERequired),
          "key_envelope": "\(keyEnvelope)"
        }
        """
    }
}

@MainActor
final class DirectCallPeerTrustReadinessTests {
    private let peerUserID = "@peer:example.com"
    private let ownUserID = "@me:example.com"

    @Test
    func failClosedPeerTrustReadinessProviderFailsClosedByDefault() async {
        let provider = FailClosedDirectCallPeerTrustReadinessProvider()

        let readiness = await provider.directCallPeerTrustReadiness()

        #expect(readiness == .peerTrustUnavailable)
        #expect(String(describing: provider).contains(peerUserID) == false)
        #expect(String(describing: readiness).contains(peerUserID) == false)
    }

    @Test
    func userIdentityPeerTrustReadinessProviderMapsIdentityStateWithoutDeviceDetails() async {
        let clientProxy = ClientProxyMock(.init(userID: ownUserID))
        clientProxy.userIdentityForFallBackToServerClosure = { _, _ in
            .success(UserIdentityProxyMock(configuration: .init(verificationState: .verified)))
        }
        let provider = UserIdentityDirectCallPeerTrustReadinessProvider(clientProxy: clientProxy,
                                                                        peerUserID: peerUserID)

        let readiness = await provider.directCallPeerTrustReadiness()

        #expect(readiness == .peerTrustReady)
        #expect(clientProxy.userIdentityForFallBackToServerReceivedArguments?.userID == peerUserID)
        #expect(clientProxy.userIdentityForFallBackToServerReceivedArguments?.fallBackToServer == true)
        #expect(String(describing: provider).contains(peerUserID) == false)
    }

    @Test
    func userIdentityPeerTrustReadinessProviderFailsClosedForUnverifiedOrMissingIdentity() async {
        let clientProxy = ClientProxyMock(.init(userID: ownUserID))
        let provider = UserIdentityDirectCallPeerTrustReadinessProvider(clientProxy: clientProxy,
                                                                        peerUserID: peerUserID)

        clientProxy.userIdentityForFallBackToServerClosure = { _, _ in
            .success(UserIdentityProxyMock(configuration: .init(verificationState: .notVerified)))
        }
        #expect(await provider.directCallPeerTrustReadiness() == .unverifiedDevice)

        clientProxy.userIdentityForFallBackToServerClosure = { _, _ in
            .success(nil)
        }
        #expect(await provider.directCallPeerTrustReadiness() == .crossSigningUnavailable)

        let missingPeerProvider = UserIdentityDirectCallPeerTrustReadinessProvider(clientProxy: clientProxy,
                                                                                   peerUserID: nil)
        #expect(await missingPeerProvider.directCallPeerTrustReadiness() == .peerTrustUnavailable)
    }
}

@MainActor
final class DirectCallProductionKeyWrappingFailureReasonTests {
    private let callID = "call-a"
    private let roomID = "!room:example.com"
    private let peerUserID = "@peer:example.com"
    private let ownUserID = "@me:example.com"

    @Test
    func productionEncryptionReportsMissingPeerBeforeKeyWrapping() async {
        let keyStore = DirectCallLiveKitMediaKeyStore { "key-a" }
        let wrapper = MediaKeyWrapperSpy()
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE",
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: "")

        #expect(result == .failure(.missingPeer))
        #expect(wrapper.wrappedRequests.isEmpty)
        #expect(keyStore.makeKeyProvider(for: .init(callID: callID, keyID: "key-a")) == nil)
    }

    @Test
    func productionEncryptionReportsMissingMetadataBeforeKeyWrapping() async {
        let keyStore = DirectCallLiveKitMediaKeyStore { "key-a" }
        let wrapper = MediaKeyWrapperSpy()
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE",
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = await service.generatePerCallKey(callID: "", roomID: roomID, peerUserID: peerUserID)

        #expect(result == .failure(.missingMetadata))
        #expect(wrapper.wrappedRequests.isEmpty)
        #expect(keyStore.makeKeyProvider(for: .init(callID: callID, keyID: "key-a")) == nil)
    }

    @Test
    func productionEncryptionPreservesRedactedSDKKeyWrappingFailures() async {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy(wrapFailure: .sdkTrustViolation)
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)

        #expect(result == .failure(.sdkTrustViolation))
        #expect(wrapper.wrappedRequests.count == 1)
        #expect(keyStore.makeKeyProvider(for: .init(callID: callID, keyID: "key-a")) == nil)
        #expect(String(describing: wrapper.wrappedRequests[0]).contains(roomID) == false)
    }
}

private final class MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol {
    private let wrapEnvelope: MatrixRustSDK.DirectCallMediaKeyEnvelope?
    private let unwrapResult: MatrixRustSDK.DirectCallMediaKeyUnwrapResult
    private let wrapError: Error?
    private let unwrapError: Error?

    private(set) var wrapInfos = [MatrixRustSDK.DirectCallMediaKeyWrapInfo]()
    private(set) var unwrapInfos = [MatrixRustSDK.DirectCallMediaKeyUnwrapInfo]()
    private(set) var unwrapEnvelopes = [MatrixRustSDK.DirectCallMediaKeyEnvelope]()

    init(wrapEnvelope: MatrixRustSDK.DirectCallMediaKeyEnvelope? = nil,
         unwrapResult: MatrixRustSDK.DirectCallMediaKeyUnwrapResult? = nil,
         wrapError: Error? = nil,
         unwrapError: Error? = nil) {
        self.wrapEnvelope = wrapEnvelope
        self.unwrapResult = unwrapResult ?? .init(keyId: "key-a",
                                                  mediaKey: "sensitive-media-material",
                                                  senderUserId: "@peer:example.com",
                                                  senderDeviceId: "PEER_DEVICE")
        self.wrapError = wrapError
        self.unwrapError = unwrapError
    }

    func wrapDirectCallMediaKey(info: MatrixRustSDK.DirectCallMediaKeyWrapInfo) async throws -> MatrixRustSDK.DirectCallMediaKeyEnvelope {
        wrapInfos.append(info)

        if let wrapError {
            throw wrapError
        }

        return wrapEnvelope ?? .init(version: 1,
                                     algorithm: "salemx.native_direct_call.media_key.v1",
                                     roomId: info.roomId,
                                     callId: info.callId,
                                     senderUserId: "@me:example.com",
                                     recipientUserId: info.recipientUserId,
                                     intent: info.intent,
                                     keyId: info.keyId,
                                     expiresAtMs: info.expiresAtMs,
                                     opaqueCiphertext: "sdk-opaque-envelope")
    }

    func unwrapDirectCallMediaKeyEnvelope(info: MatrixRustSDK.DirectCallMediaKeyUnwrapInfo,
                                          envelope: MatrixRustSDK.DirectCallMediaKeyEnvelope) async throws -> MatrixRustSDK.DirectCallMediaKeyUnwrapResult {
        unwrapInfos.append(info)
        unwrapEnvelopes.append(envelope)

        if let unwrapError {
            throw unwrapError
        }

        return unwrapResult
    }
}

private enum MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpyError: Error {
    case genericFailure
}

@MainActor
private final class DirectCallProductionCapabilityProviderSpy: DirectCallProductionCapabilityProviding {
    private let result: DirectCallProductionCapabilityDiscoveryResult
    private(set) var callCount = 0

    init(result: DirectCallProductionCapabilityDiscoveryResult) {
        self.result = result
    }

    func directCallProductionServerCapability() async -> DirectCallProductionCapabilityDiscoveryResult {
        callCount += 1
        return result
    }
}

@MainActor
private final class NativeDirectCallProductionDependencyProviderSpy: NativeDirectCallProductionDependencyProviding {
    private let dependencies: NativeDirectCallProductionDependencies
    private(set) var callCount = 0

    init(dependencies: NativeDirectCallProductionDependencies) {
        self.dependencies = dependencies
    }

    func nativeDirectCallProductionDependencies() -> NativeDirectCallProductionDependencies {
        callCount += 1
        return dependencies
    }
}

@MainActor
private final class ProductionActivationEncryptionServiceSpy: DirectCallEncryptionServiceProtocol {
    private(set) var generateKeyCallCount = 0
    private(set) var consumeKeyCallCount = 0
    private(set) var clearKeyCallCount = 0

    func generatePerCallKey(callID: String,
                            roomID: String,
                            peerUserID: String) async -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        generateKeyCallCount += 1
        return .failure(.keyExchangeFailed)
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload,
                                   expectedCallID: String,
                                   expectedRoomID: String,
                                   expectedSenderUserID: String) async -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        consumeKeyCallCount += 1
        return .failure(.keyExchangeFailed)
    }

    func clearPerCallKey(callID: String) {
        clearKeyCallCount += 1
    }
}

@MainActor
private final class ProductionActivationMediaEngineFactorySpy: DirectCallMediaEngineFactoryProtocol {
    private(set) var makeMediaEngineCallCount = 0

    func makeMediaEngine() -> Result<any DirectCallMediaEngineProtocol, DirectCallMediaError> {
        makeMediaEngineCallCount += 1
        return .failure(.mediaSetupUnavailable)
    }
}

@MainActor
private final class DirectCallMediaKeyEnvelopeWrappingProviderSpy: DirectCallMediaKeyEnvelopeWrappingProviding {
    private let wrapper: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol?
    private(set) var makeWrapperCallCount = 0

    init(wrapper: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol?) {
        self.wrapper = wrapper
    }

    func makeDirectCallMediaKeyEnvelopeWrapper() -> MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol? {
        makeWrapperCallCount += 1
        return wrapper
    }
}

@MainActor
private final class DirectCallHTTPTransportSpy: DirectCallHTTPTransportProtocol {
    private(set) var requests = [DirectCallHTTPTransportRequest]()
    var result: Result<DirectCallHTTPTransportResponse, DirectCallMediaError>

    init(result: Result<DirectCallHTTPTransportResponse, DirectCallMediaError> = .failure(.tokenUnavailable)) {
        self.result = result
    }

    func send(_ request: DirectCallHTTPTransportRequest) async -> Result<DirectCallHTTPTransportResponse, DirectCallMediaError> {
        requests.append(request)
        return result
    }
}

@MainActor
private struct MatrixAccessTokenProviderStub: DirectCallMatrixAccessTokenProviding {
    let accessToken: String?

    func matrixAccessToken() async -> String? {
        accessToken
    }
}

@MainActor
private final class MediaKeyWrapperSpy: DirectCallMediaKeyWrappingProtocol {
    private let envelopeOverride: DirectCallWrappedMediaKeyEnvelope?
    private let wrapFailure: DirectCallMediaKeyWrappingFailureReason?
    private let unwrapFailure: DirectCallMediaKeyWrappingFailureReason?
    private let unwrappedMediaKey: String

    private(set) var wrappedMediaKeys = [String]()
    private(set) var wrappedRequests = [DirectCallMediaKeyWrapRequest]()
    private(set) var unwrappedEnvelopes = [DirectCallWrappedMediaKeyEnvelope]()
    private(set) var unwrappedRequests = [DirectCallMediaKeyUnwrapRequest]()

    init(envelopeOverride: DirectCallWrappedMediaKeyEnvelope? = nil,
         wrapFailure: DirectCallMediaKeyWrappingFailureReason? = nil,
         unwrapFailure: DirectCallMediaKeyWrappingFailureReason? = nil,
         unwrappedMediaKey: String = "sensitive-media-material") {
        self.envelopeOverride = envelopeOverride
        self.wrapFailure = wrapFailure
        self.unwrapFailure = unwrapFailure
        self.unwrappedMediaKey = unwrappedMediaKey
    }

    func wrapMediaKey(_ mediaKey: String,
                      request: DirectCallMediaKeyWrapRequest) async -> Result<DirectCallWrappedMediaKeyEnvelope, DirectCallMediaKeyWrappingFailureReason> {
        wrappedMediaKeys.append(mediaKey)
        wrappedRequests.append(request)

        if let wrapFailure {
            return .failure(wrapFailure)
        }

        if let envelopeOverride {
            return .success(envelopeOverride)
        }

        return .success(.init(algorithm: "test",
                              callID: request.callID,
                              roomID: request.roomID,
                              senderUserID: request.senderUserID,
                              recipientUserID: request.recipientUserID,
                              senderDeviceID: request.senderDeviceID,
                              intent: request.intent,
                              expiresAt: request.expiresAt,
                              keyID: request.keyID,
                              opaqueEnvelope: "opaque-\(request.keyID)"))
    }

    func unwrapMediaKeyEnvelope(_ envelope: DirectCallWrappedMediaKeyEnvelope,
                                request: DirectCallMediaKeyUnwrapRequest) async -> Result<DirectCallUnwrappedMediaKey, DirectCallMediaKeyWrappingFailureReason> {
        unwrappedEnvelopes.append(envelope)
        unwrappedRequests.append(request)

        if let unwrapFailure {
            return .failure(unwrapFailure)
        }

        return .success(.init(mediaKey: unwrappedMediaKey, keyID: envelope.keyID))
    }
}

@MainActor
private final class ProductionKeyWrappingLiveKitClientSpy: DirectCallLiveKitClientProtocol {
    private(set) var connectionInfos = [DirectCallMediaConnectionInfo]()

    func connect(connectionInfo: DirectCallMediaConnectionInfo, e2eeContext: any DirectCallMediaE2EEContextProtocol) async -> Result<Void, DirectCallMediaError> {
        connectionInfos.append(connectionInfo)
        return .success(())
    }

    func setMicrophoneEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        .success(())
    }

    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        .success(())
    }

    func disconnect() async { }

    func cleanup() async { }
}
