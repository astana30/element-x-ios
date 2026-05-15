//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
final class DirectCallProductionCapabilitySourceTests {
    @Test
    func productionRolloutProviderFailsClosedByDefault() {
        let provider = FailClosedDirectCallProductionRolloutProvider()

        let configuration = provider.directCallProductionConfiguration()

        #expect(configuration == DirectCallProductionConfiguration())
        #expect(configuration.isEnabled == false)
        #expect(configuration.isConfigured == false)
        #expect(String(describing: provider).contains("directOneToOneCallsEnabled") == false)
        #expect(String(describing: provider).contains("DIAGNOSTIC") == false)
    }

    @Test
    func productionActivationDecisionServiceCanUseFailClosedRolloutProvider() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let rolloutProvider = FailClosedDirectCallProductionRolloutProvider()
        let capabilityProvider = CapabilitySourceProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = CapabilitySourceDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(rolloutProvider: rolloutProvider,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.disabledReason == .appRolloutDisabled)
        #expect(diagnostic.isCapabilityPresent == false)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(capabilityProvider.callCount == 0)
        #expect(dependencyProvider.callCount == 0)
    }

    @Test
    func productionActivationDecisionServiceDefaultProvidersFailClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let service = DirectCallProductionActivationDecisionService()

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.disabledReason == .appRolloutDisabled)
        #expect(diagnostic.isCapabilityPresent == false)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted == false)
        #expect(String(describing: service).contains("matrix.example.com") == false)
        #expect(String(describing: diagnostic).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
    }

    @Test
    func productionActivationDecisionServiceAsksRolloutProviderBeforeOtherProviders() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let rolloutProvider = CapabilitySourceRolloutProviderSpy(configuration: .init())
        let capabilityProvider = CapabilitySourceProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = CapabilitySourceDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(rolloutProvider: rolloutProvider,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.disabledReason == .appRolloutDisabled)
        #expect(rolloutProvider.callCount == 1)
        #expect(capabilityProvider.callCount == 0)
        #expect(dependencyProvider.callCount == 0)
    }

    @Test
    func productionActivationDecisionServiceRolloutEnabledButCapabilityMissingFailsClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let rolloutProvider = CapabilitySourceRolloutProviderSpy(configuration: .init(isEnabled: true))
        let capabilityProvider = CapabilitySourceProviderSpy(result: .unavailable(.missingCapability))
        let dependencyProvider = CapabilitySourceDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(rolloutProvider: rolloutProvider,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.disabledReason == .serverCapabilityUnavailable)
        #expect(diagnostic.isCapabilityPresent == false)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted == false)
        #expect(rolloutProvider.callCount == 1)
        #expect(capabilityProvider.callCount == 1)
        #expect(dependencyProvider.callCount == 0)
    }

    @Test
    func productionActivationDecisionServiceCapabilityValidButDependenciesMissingFailsClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let rolloutProvider = CapabilitySourceRolloutProviderSpy(configuration: .init(isEnabled: true))
        let capabilityProvider = CapabilitySourceProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = CapabilitySourceDependencyProviderSpy(dependencies: .disabled)
        let service = DirectCallProductionActivationDecisionService(rolloutProvider: rolloutProvider,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.disabledReason == .dependenciesUnavailable)
        #expect(diagnostic.isCapabilityPresent)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted)
        #expect(rolloutProvider.callCount == 1)
        #expect(capabilityProvider.callCount == 1)
        #expect(dependencyProvider.callCount == 1)
    }

    @Test
    func productionActivationDecisionServiceDependenciesReadyButRoomIneligibleFailsClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let rolloutProvider = CapabilitySourceRolloutProviderSpy(configuration: .init(isEnabled: true))
        let capabilityProvider = CapabilitySourceProviderSpy(result: .available(makeServerCapability()))
        let dependencyProvider = CapabilitySourceDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(rolloutProvider: rolloutProvider,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility(isEncrypted: false))

        #expect(diagnostic.disabledReason == .roomNotEncrypted)
        #expect(diagnostic.isCapabilityPresent)
        #expect(diagnostic.areDependenciesReady)
        #expect(diagnostic.isRoomEligible == false)
        #expect(diagnostic.isEndpointAccepted)
    }

    @Test
    func productionActivationDecisionServiceAllValidInputsEnableDryRunWithoutRuntimeSideEffects() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let rolloutProvider = CapabilitySourceRolloutProviderSpy(configuration: .init(isEnabled: true))
        let capabilityProvider = CapabilitySourceProviderSpy(result: .available(makeServerCapability()))
        let encryptionService = CapabilitySourceEncryptionServiceSpy()
        let mediaEngineFactory = CapabilitySourceMediaEngineFactorySpy()
        let dependencyProvider = CapabilitySourceDependencyProviderSpy(dependencies: NativeDirectCallProductionDependencies(encryptionService: encryptionService,
                                                                                                                            mediaEngineFactory: mediaEngineFactory,
                                                                                                                            keyWrapperSource: .explicitWrapper))
        let service = DirectCallProductionActivationDecisionService(rolloutProvider: rolloutProvider,
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
        #expect(diagnostic.isPeerTrustReady)
        #expect(rolloutProvider.callCount == 1)
        #expect(capabilityProvider.callCount == 1)
        #expect(dependencyProvider.callCount == 1)
        #expect(encryptionService.generateKeyCallCount == 0)
        #expect(encryptionService.consumeKeyCallCount == 0)
        #expect(encryptionService.clearKeyCallCount == 0)
        #expect(mediaEngineFactory.makeMediaEngineCallCount == 0)
    }

    @Test
    func productionActivationDecisionServiceCapabilityProviderFailureStaysRedacted() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let rolloutProvider = CapabilitySourceRolloutProviderSpy(configuration: .init(isEnabled: true))
        let capabilityProvider = CapabilitySourceProviderSpy(result: .unavailable(.providerUnavailable))
        let dependencyProvider = CapabilitySourceDependencyProviderSpy(dependencies: makeActivationReadyDependencies())
        let service = DirectCallProductionActivationDecisionService(rolloutProvider: rolloutProvider,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.disabledReason == .serverCapabilityUnavailable)
        #expect(String(describing: diagnostic).contains("providerUnavailable") == false)
        #expect(String(describing: diagnostic).contains("matrix.example.com") == false)
        #expect(String(describing: diagnostic).contains(DirectCallProductionConfiguration.tokenEndpointPath) == false)
    }

    @Test
    func productionActivationReadinessPackEnablesOnlyWhenEveryInputIsValid() async {
        let pack = makeActivationReadinessPack()

        let diagnostic = await pack.diagnostic()

        #expect(diagnostic.isEnabled)
        #expect(diagnostic.disabledReason == nil)
        #expect(diagnostic.isCapabilityPresent)
        #expect(diagnostic.areDependenciesReady)
        #expect(diagnostic.isRoomEligible)
        #expect(diagnostic.isEndpointAccepted)
        assertActivationDiagnosticIsRedacted(diagnostic)
        pack.expectProviderCalls(rollout: 1, capability: 1, dependencies: 1)
        pack.expectNoRuntimeSideEffects()
    }

    @Test
    func productionActivationReadinessPackFailsClosedForMissingReadinessInputs() async throws {
        let externalEndpointURL = try #require(URL(string: "https://calls.example.net/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"))
        let cases: [CapabilitySourceActivationReadinessFailureCase] = [
            .init(name: "rollout-disabled",
                  pack: makeActivationReadinessPack(configuration: .init()),
                  expectedReason: .appRolloutDisabled,
                  expectedCapability: false,
                  expectedDependencies: false,
                  expectedRoom: true,
                  expectedEndpoint: false),
            .init(name: "capability-missing",
                  pack: makeActivationReadinessPack(capabilityResult: .unavailable(.missingCapability)),
                  expectedReason: .serverCapabilityUnavailable,
                  expectedCapability: false,
                  expectedDependencies: false,
                  expectedRoom: true,
                  expectedEndpoint: false),
            .init(name: "capability-malformed",
                  pack: makeActivationReadinessPack(capabilityResult: .unavailable(.malformedCapability)),
                  expectedReason: .serverCapabilityUnavailable,
                  expectedCapability: false,
                  expectedDependencies: false,
                  expectedRoom: true,
                  expectedEndpoint: false),
            .init(name: "capability-external-endpoint",
                  pack: makeActivationReadinessPack(capabilityResult: .available(makeServerCapability(tokenEndpointPath: "https://calls.example.net/token"))),
                  expectedReason: .tokenEndpointUnavailable,
                  expectedCapability: true,
                  expectedDependencies: true,
                  expectedRoom: true,
                  expectedEndpoint: false),
            .init(name: "configured-external-endpoint",
                  pack: makeActivationReadinessPack(configuration: .init(isEnabled: true, tokenEndpointBaseURL: externalEndpointURL)),
                  expectedReason: .tokenEndpointNotSameOrigin,
                  expectedCapability: true,
                  expectedDependencies: true,
                  expectedRoom: true,
                  expectedEndpoint: false),
            .init(name: "dependencies-missing",
                  pack: makeActivationReadinessPack(dependencies: .disabled),
                  expectedReason: .dependenciesUnavailable,
                  expectedCapability: true,
                  expectedDependencies: false,
                  expectedRoom: true,
                  expectedEndpoint: true),
            .init(name: "room-not-encrypted",
                  pack: makeActivationReadinessPack(roomEligibility: makeRoomEligibility(isEncrypted: false)),
                  expectedReason: .roomNotEncrypted,
                  expectedCapability: true,
                  expectedDependencies: true,
                  expectedRoom: false,
                  expectedEndpoint: true),
            .init(name: "room-not-one-to-one",
                  pack: makeActivationReadinessPack(roomEligibility: makeRoomEligibility(joinedMemberCount: 3)),
                  expectedReason: .roomNotOneToOne,
                  expectedCapability: true,
                  expectedDependencies: true,
                  expectedRoom: false,
                  expectedEndpoint: true),
            .init(name: "peer-trust-unavailable",
                  pack: makeActivationReadinessPack(peerTrustReadiness: .peerTrustUnavailable),
                  expectedReason: .peerTrustUnavailable,
                  expectedCapability: true,
                  expectedDependencies: true,
                  expectedRoom: true,
                  expectedEndpoint: true),
            .init(name: "peer-unverified",
                  pack: makeActivationReadinessPack(peerTrustReadiness: .unverifiedDevice),
                  expectedReason: .unverifiedDevice,
                  expectedCapability: true,
                  expectedDependencies: true,
                  expectedRoom: true,
                  expectedEndpoint: true)
        ]

        for failureCase in cases {
            let diagnostic = await failureCase.pack.diagnostic()

            #expect(diagnostic.isEnabled == false, "Expected \(failureCase.name) to fail closed.")
            #expect(diagnostic.disabledReason == failureCase.expectedReason, "Unexpected reason for \(failureCase.name).")
            #expect(diagnostic.isCapabilityPresent == failureCase.expectedCapability, "Unexpected capability flag for \(failureCase.name).")
            #expect(diagnostic.areDependenciesReady == failureCase.expectedDependencies, "Unexpected dependency flag for \(failureCase.name).")
            #expect(diagnostic.isRoomEligible == failureCase.expectedRoom, "Unexpected room flag for \(failureCase.name).")
            #expect(diagnostic.isEndpointAccepted == failureCase.expectedEndpoint, "Unexpected endpoint flag for \(failureCase.name).")
            assertActivationDiagnosticIsRedacted(diagnostic)
            failureCase.pack.expectNoRuntimeSideEffects()
        }
    }

    @Test
    func productionHTTPCapabilityProviderFailsClosedWithoutTransport() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let provider = HTTPDirectCallProductionCapabilityProvider(homeserverBaseURL: homeserverBaseURL,
                                                                  accessTokenProvider: CapabilitySourceAccessTokenProviderStub(accessToken: "matrix-access-credential"))

        let result = await provider.directCallProductionServerCapability()

        #expect(result == .unavailable(.providerUnavailable))
        #expect(String(describing: provider).contains("matrix.example.com") == false)
        #expect(String(describing: provider).contains("matrix-access-credential") == false)
    }

    @Test
    func productionHTTPCapabilityProviderFailsClosedWithoutAccessToken() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let transport = CapabilitySourceHTTPTransportSpy(result: .success(.init(statusCode: 200, data: makeCapabilitiesPayload())))
        let provider = HTTPDirectCallProductionCapabilityProvider(homeserverBaseURL: homeserverBaseURL,
                                                                  httpTransport: transport,
                                                                  accessTokenProvider: CapabilitySourceAccessTokenProviderStub(accessToken: nil))

        let result = await provider.directCallProductionServerCapability()

        #expect(result == .unavailable(.providerUnavailable))
        #expect(transport.requests.isEmpty)
    }

    @Test
    func productionHTTPCapabilityProviderFailsClosedWithInvalidHomeserverURL() async throws {
        let invalidBaseURL = try #require(URL(string: "file:///tmp/matrix.example.com"))
        let transport = CapabilitySourceHTTPTransportSpy(result: .success(.init(statusCode: 200, data: makeCapabilitiesPayload())))
        let provider = HTTPDirectCallProductionCapabilityProvider(homeserverBaseURL: invalidBaseURL,
                                                                  httpTransport: transport,
                                                                  accessTokenProvider: CapabilitySourceAccessTokenProviderStub(accessToken: "matrix-access-credential"))

        let result = await provider.directCallProductionServerCapability()

        #expect(result == .unavailable(.providerUnavailable))
        #expect(transport.requests.isEmpty)
    }

    @Test
    func productionHTTPCapabilityProviderFetchesCapabilitiesAndDecodesNativeCapability() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com/ignored?query=1#fragment"))
        let transport = CapabilitySourceHTTPTransportSpy(result: .success(.init(statusCode: 200, data: makeCapabilitiesPayload())))
        let provider = HTTPDirectCallProductionCapabilityProvider(homeserverBaseURL: homeserverBaseURL,
                                                                  httpTransport: transport,
                                                                  accessTokenProvider: CapabilitySourceAccessTokenProviderStub(accessToken: "matrix-access-credential"))

        let result = await provider.directCallProductionServerCapability()
        let capability = try #require(result.capability)
        let request = try #require(transport.requests.first)

        #expect(result.isAvailable)
        #expect(capability.isEnabled)
        #expect(capability.supportsIntent(.audio))
        #expect(transport.requests.count == 1)
        #expect(request.method == "GET")
        #expect(request.url.scheme == "https")
        #expect(request.url.host == "matrix.example.com")
        #expect(request.url.path == HTTPDirectCallProductionCapabilityProvider.capabilitiesPath)
        #expect(request.url.query == nil)
        #expect(request.url.fragment == nil)
        #expect(request.url.absoluteString.contains(".well-known") == false)
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["Authorization"] == "Bearer matrix-access-credential")
        #expect(request.headers["Content-Type"] == nil)
        #expect(request.body.isEmpty)
        #expect(String(describing: request).contains("matrix-access-credential") == false)
        #expect(String(describing: request).contains("matrix.example.com") == false)
        #expect(String(describing: result).contains("matrix-access-credential") == false)
    }

    @Test
    func productionHTTPCapabilityProviderMapsMissingAndMalformedCapabilitiesFailClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let cases: [(Data, DirectCallProductionCapabilityDiscoveryResult)] = [
            (Data("""
            {
              "capabilities": {
                "m.room_versions": { "default": "1" }
              }
            }
            """.utf8), .unavailable(.missingCapability)),
            (Data("""
            {
              "capabilities": {
                "\(DirectCallProductionServerCapability.capabilityName)": {
                  "enabled": true,
                  "version": "1"
                }
              }
            }
            """.utf8), .unavailable(.malformedCapability))
        ]

        for (data, expectedResult) in cases {
            let transport = CapabilitySourceHTTPTransportSpy(result: .success(.init(statusCode: 200, data: data)))
            let provider = HTTPDirectCallProductionCapabilityProvider(homeserverBaseURL: homeserverBaseURL,
                                                                      httpTransport: transport,
                                                                      accessTokenProvider: CapabilitySourceAccessTokenProviderStub(accessToken: "matrix-access-credential"))

            let result = await provider.directCallProductionServerCapability()

            #expect(result == expectedResult)
            #expect(transport.requests.count == 1)
        }
    }

    @Test
    func productionHTTPCapabilityProviderHTTPFailuresFailClosed() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))

        for statusCode in [401, 403, 404, 429, 500] {
            let transport = CapabilitySourceHTTPTransportSpy(result: .success(.init(statusCode: statusCode, data: Data("not logged".utf8))))
            let provider = HTTPDirectCallProductionCapabilityProvider(homeserverBaseURL: homeserverBaseURL,
                                                                      httpTransport: transport,
                                                                      accessTokenProvider: CapabilitySourceAccessTokenProviderStub(accessToken: "matrix-access-credential"))

            let result = await provider.directCallProductionServerCapability()

            #expect(result == .unavailable(.providerUnavailable))
            #expect(transport.requests.count == 1)
            #expect(String(describing: result).contains("not logged") == false)
        }
    }

    @Test
    func productionHTTPCapabilityProviderExternalEndpointIsRejectedByActivationGate() async throws {
        let homeserverBaseURL = try #require(URL(string: "https://matrix.example.com"))
        let transport = CapabilitySourceHTTPTransportSpy(result: .success(.init(statusCode: 200,
                                                                                data: makeCapabilitiesPayload(tokenEndpointPath: "https://calls.example.net/token"))))
        let provider = HTTPDirectCallProductionCapabilityProvider(homeserverBaseURL: homeserverBaseURL,
                                                                  httpTransport: transport,
                                                                  accessTokenProvider: CapabilitySourceAccessTokenProviderStub(accessToken: "matrix-access-credential"))

        let result = await provider.directCallProductionServerCapability()
        let decision = DirectCallProductionActivationGate().evaluate(makeActivationContext(homeserverBaseURL: homeserverBaseURL,
                                                                                           serverCapability: result.capability))

        #expect(result.isAvailable)
        #expect(decision == .disabled(.tokenEndpointUnavailable))
    }

    private func makeActivationContext(appRolloutEnabled: Bool = true,
                                       homeserverBaseURL: URL? = URL(string: "https://matrix.example.com"),
                                       serverCapability: DirectCallProductionServerCapability? = DirectCallProductionServerCapability(isEnabled: true,
                                                                                                                                      intents: [DirectCallIntent.audio.rawValue]),
                                       configuredTokenEndpointURL: URL? = nil,
                                       dependencies: NativeDirectCallProductionDependencies? = nil,
                                       roomEligibility: DirectCallProductionRoomEligibility = DirectCallProductionRoomEligibility(isDirect: true,
                                                                                                                                  isEncrypted: true,
                                                                                                                                  joinedMemberCount: 2,
                                                                                                                                  hasPeerUserID: true),
                                       peerTrustReadiness: DirectCallPeerTrustReadiness = .peerTrustReady) -> DirectCallProductionActivationContext {
        .init(appRolloutEnabled: appRolloutEnabled,
              homeserverBaseURL: homeserverBaseURL,
              serverCapability: serverCapability,
              configuredTokenEndpointURL: configuredTokenEndpointURL,
              dependencies: dependencies ?? makeActivationReadyDependencies(),
              roomEligibility: roomEligibility,
              peerTrustReadiness: peerTrustReadiness)
    }

    private func makeServerCapability(tokenEndpointPath: String? = DirectCallProductionConfiguration.tokenEndpointPath) -> DirectCallProductionServerCapability {
        DirectCallProductionServerCapability(isEnabled: true,
                                             tokenEndpointPath: tokenEndpointPath,
                                             intents: [DirectCallIntent.audio.rawValue])
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

    private func makeActivationReadinessPack(configuration: DirectCallProductionConfiguration = .init(isEnabled: true),
                                             homeserverBaseURL: URL? = URL(string: "https://matrix.example.com"),
                                             capabilityResult: DirectCallProductionCapabilityDiscoveryResult? = nil,
                                             dependencies: NativeDirectCallProductionDependencies? = nil,
                                             roomEligibility: DirectCallProductionRoomEligibility? = nil,
                                             peerTrustReadiness: DirectCallPeerTrustReadiness = .peerTrustReady) -> CapabilitySourceActivationReadinessPack {
        let encryptionService = CapabilitySourceEncryptionServiceSpy()
        let mediaEngineFactory = CapabilitySourceMediaEngineFactorySpy()
        let dependencyProvider = CapabilitySourceDependencyProviderSpy(dependencies: dependencies ?? NativeDirectCallProductionDependencies(encryptionService: encryptionService,
                                                                                                                                            mediaEngineFactory: mediaEngineFactory,
                                                                                                                                            keyWrapperSource: .explicitWrapper))
        let rolloutProvider = CapabilitySourceRolloutProviderSpy(configuration: configuration)
        let capabilityProvider = CapabilitySourceProviderSpy(result: capabilityResult ?? .available(makeServerCapability()))
        let service = DirectCallProductionActivationDecisionService(rolloutProvider: rolloutProvider,
                                                                    capabilityProvider: capabilityProvider,
                                                                    dependencyProvider: dependencyProvider,
                                                                    peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: peerTrustReadiness))

        return CapabilitySourceActivationReadinessPack(service: service,
                                                       homeserverBaseURL: homeserverBaseURL,
                                                       roomEligibility: roomEligibility ?? makeRoomEligibility(),
                                                       rolloutProvider: rolloutProvider,
                                                       capabilityProvider: capabilityProvider,
                                                       dependencyProvider: dependencyProvider,
                                                       encryptionService: encryptionService,
                                                       mediaEngineFactory: mediaEngineFactory)
    }

    private func assertActivationDiagnosticIsRedacted(_ diagnostic: DirectCallProductionActivationDryRunDiagnostic) {
        let description = String(describing: diagnostic)
        let forbiddenFragments = [
            "matrix.example.com",
            "calls.example.net",
            DirectCallProductionConfiguration.tokenEndpointPath,
            "!room",
            "@alice",
            "peer-user",
            "participant_" + "token",
            "access_" + "token",
            "bearer",
            "j" + "wt",
            "raw " + "key",
            "encrypted_" + "payload",
            "debug" + "Info",
            "original" + "JSON",
            "raw " + "JSON"
        ]

        for fragment in forbiddenFragments {
            #expect(description.localizedCaseInsensitiveContains(fragment) == false)
        }
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
private struct CapabilitySourceActivationReadinessPack {
    let service: DirectCallProductionActivationDryRunDiagnosing
    let homeserverBaseURL: URL?
    let roomEligibility: DirectCallProductionRoomEligibility
    let rolloutProvider: CapabilitySourceRolloutProviderSpy
    let capabilityProvider: CapabilitySourceProviderSpy
    let dependencyProvider: CapabilitySourceDependencyProviderSpy
    let encryptionService: CapabilitySourceEncryptionServiceSpy
    let mediaEngineFactory: CapabilitySourceMediaEngineFactorySpy

    func diagnostic() async -> DirectCallProductionActivationDryRunDiagnostic {
        await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                     roomEligibility: roomEligibility)
    }

    func expectProviderCalls(rollout: Int, capability: Int, dependencies: Int) {
        #expect(rolloutProvider.callCount == rollout)
        #expect(capabilityProvider.callCount == capability)
        #expect(dependencyProvider.callCount == dependencies)
    }

    func expectNoRuntimeSideEffects() {
        #expect(encryptionService.generateKeyCallCount == 0)
        #expect(encryptionService.consumeKeyCallCount == 0)
        #expect(encryptionService.clearKeyCallCount == 0)
        #expect(mediaEngineFactory.makeMediaEngineCallCount == 0)
    }
}

@MainActor
private struct CapabilitySourceActivationReadinessFailureCase {
    let name: String
    let pack: CapabilitySourceActivationReadinessPack
    let expectedReason: DirectCallProductionActivationDisabledReason
    let expectedCapability: Bool
    let expectedDependencies: Bool
    let expectedRoom: Bool
    let expectedEndpoint: Bool
}

@MainActor
private final class CapabilitySourceRolloutProviderSpy: DirectCallProductionRolloutProviding {
    private let configuration: DirectCallProductionConfiguration
    private(set) var callCount = 0

    init(configuration: DirectCallProductionConfiguration) {
        self.configuration = configuration
    }

    func directCallProductionConfiguration() -> DirectCallProductionConfiguration {
        callCount += 1
        return configuration
    }
}

@MainActor
private final class CapabilitySourceProviderSpy: DirectCallProductionCapabilityProviding {
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
private final class CapabilitySourceDependencyProviderSpy: NativeDirectCallProductionDependencyProviding {
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
private final class CapabilitySourceHTTPTransportSpy: DirectCallHTTPTransportProtocol {
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
private struct CapabilitySourceAccessTokenProviderStub: DirectCallMatrixAccessTokenProviding {
    let accessToken: String?

    func matrixAccessToken() async -> String? {
        accessToken
    }
}

@MainActor
private final class CapabilitySourceEncryptionServiceSpy: DirectCallEncryptionServiceProtocol {
    private(set) var generateKeyCallCount = 0
    private(set) var consumeKeyCallCount = 0
    private(set) var clearKeyCallCount = 0

    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) async -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        generateKeyCallCount += 1
        return .failure(.keyExchangeFailed)
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload, expectedCallID: String, expectedRoomID: String, expectedSenderUserID: String) async -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        consumeKeyCallCount += 1
        return .failure(.keyExchangeFailed)
    }

    func clearPerCallKey(callID: String) {
        clearKeyCallCount += 1
    }
}

@MainActor
private final class CapabilitySourceMediaEngineFactorySpy: DirectCallMediaEngineFactoryProtocol {
    private(set) var makeMediaEngineCallCount = 0

    func makeMediaEngine() -> Result<any DirectCallMediaEngineProtocol, DirectCallMediaError> {
        makeMediaEngineCallCount += 1
        return .failure(.mediaSetupUnavailable)
    }
}

@MainActor
final class DirectCallBackendSmokeTests {
    @Test
    func smokeEnvironmentIsDisabledByDefaultAndLocalOnly() {
        #expect(DirectCallBackendSmokeEnvironment(environment: [:]) == nil)
        #expect(DirectCallBackendSmokeEnvironment(environment: [
            DirectCallBackendSmokeEnvironment.smokeEnabledKey: "1",
            DirectCallBackendSmokeEnvironment.backendBaseURLKey: "https://call-service.example.com",
            DirectCallBackendSmokeEnvironment.fakeAccessTokenKey: "matrix-access-credential"
        ]) == nil)
        #expect(DirectCallBackendSmokeEnvironment(environment: [
            DirectCallBackendSmokeEnvironment.smokeEnabledKey: "1",
            DirectCallBackendSmokeEnvironment.backendBaseURLKey: "http://127.0.0.1:8088",
            DirectCallBackendSmokeEnvironment.fakeAccessTokenKey: "matrix-access-credential"
        ]) != nil)
    }

    @Test(.enabled(if: DirectCallBackendSmokeEnvironment.isRunnableInCurrentProcess))
    func productionLiveKitTokenProviderMapsLocalBackendSmokeResponseToConnectionInfo() async throws {
        let environment = try #require(DirectCallBackendSmokeEnvironment.current)
        let productionConfiguration = DirectCallProductionConfiguration(isEnabled: true,
                                                                        tokenEndpointBaseURL: environment.backendBaseURL)
        let tokenClient = ProductionDirectCallLiveKitTokenClient(configuration: productionConfiguration.liveKitConfiguration,
                                                                 httpTransport: URLSessionDirectCallHTTPTransport(),
                                                                 accessTokenProvider: DirectCallBackendSmokeAccessTokenProvider(accessToken: environment.fakeAccessToken))
        let provider = DirectCallLiveKitTokenProvider(tokenClient: tokenClient)
        let session = DirectCallSession(callID: "local-smoke-call",
                                        roomID: "!local-smoke:example.test",
                                        peerUserID: "@bob:local.test",
                                        direction: .outgoing,
                                        intent: .audio,
                                        encryptionMode: .e2eeRequired,
                                        startedAt: .now,
                                        updatedAt: .now,
                                        state: .connecting,
                                        encryptionState: .ready)

        let connectionInfo = try await provider.connectionInfo(for: session).get()

        #expect(productionConfiguration.isConfigured)
        #expect(connectionInfo.serverURL.scheme?.isEmpty == false)
        #expect(connectionInfo.roomName.isEmpty == false)
        #expect(connectionInfo.token.isEmpty == false)
        #expect(String(describing: environment).contains(environment.fakeAccessToken) == false)
        #expect(String(describing: tokenClient).contains(environment.backendBaseURL.absoluteString) == false)
        #expect(String(describing: connectionInfo).contains(connectionInfo.token) == false)
    }

    @Test(.enabled(if: DirectCallBackendSmokeEnvironment.isRunnableInCurrentProcess))
    func productionHTTPCapabilityProviderMapsLocalBackendSmokeCapabilityToDryRunDecision() async throws {
        let environment = try #require(DirectCallBackendSmokeEnvironment.current)
        let transport = DirectCallBackendSmokeCountingHTTPTransport(upstream: URLSessionDirectCallHTTPTransport())
        let provider = HTTPDirectCallProductionCapabilityProvider(homeserverBaseURL: environment.backendBaseURL,
                                                                  httpTransport: transport,
                                                                  accessTokenProvider: DirectCallBackendSmokeAccessTokenProvider(accessToken: environment.fakeAccessToken))

        let result = await provider.directCallProductionServerCapability()
        let capability = try #require(result.capability)
        let request = try #require(transport.requests.first)

        #expect(result.isAvailable)
        #expect(capability.isEnabled)
        #expect(capability.tokenEndpointPath == DirectCallProductionConfiguration.tokenEndpointPath)
        #expect(capability.supportsIntent(.audio))
        #expect(transport.requests.count == 1)
        #expect(request.method == "GET")
        #expect(request.url.path == HTTPDirectCallProductionCapabilityProvider.capabilitiesPath)
        #expect(transport.requests.contains { $0.url.path == DirectCallProductionConfiguration.tokenEndpointPath } == false)
        #expect(DirectCallProductionConfiguration().isEnabled == false)
        #expect(String(describing: environment).contains(environment.fakeAccessToken) == false)
        #expect(String(describing: provider).contains(environment.backendBaseURL.absoluteString) == false)
        #expect(String(describing: transport).contains(environment.fakeAccessToken) == false)
        #expect(String(describing: request).contains(environment.fakeAccessToken) == false)

        let disabledDependencyProvider = DirectCallBackendSmokeDependencyProvider(dependencies: makeActivationReadyDependencies())
        let disabledService = DirectCallProductionActivationDecisionService(rolloutProvider: FailClosedDirectCallProductionRolloutProvider(),
                                                                            capabilityProvider: provider,
                                                                            dependencyProvider: disabledDependencyProvider)
        let disabledDiagnostic = await disabledService.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: environment.backendBaseURL,
                                                                                                      roomEligibility: makeRoomEligibility())

        #expect(disabledDiagnostic.disabledReason == .appRolloutDisabled)
        #expect(disabledDiagnostic.isCapabilityPresent == false)
        #expect(disabledDiagnostic.areDependenciesReady == false)
        #expect(disabledDependencyProvider.callCount == 0)
        assertActivationDiagnosticIsRedacted(disabledDiagnostic)

        let encryptionService = CapabilitySourceEncryptionServiceSpy()
        let mediaEngineFactory = CapabilitySourceMediaEngineFactorySpy()
        let enabledDependencyProvider = DirectCallBackendSmokeDependencyProvider(dependencies: NativeDirectCallProductionDependencies(encryptionService: encryptionService,
                                                                                                                                      mediaEngineFactory: mediaEngineFactory,
                                                                                                                                      keyWrapperSource: .explicitWrapper))
        let enabledService = DirectCallProductionActivationDecisionService(rolloutProvider: DirectCallBackendSmokeRolloutProvider(configuration: .init(isEnabled: true)),
                                                                           capabilityProvider: DirectCallBackendSmokeCapabilityProvider(result: result),
                                                                           dependencyProvider: enabledDependencyProvider,
                                                                           peerTrustReadinessProvider: StaticDirectCallPeerTrustReadinessProvider(readiness: .peerTrustReady))
        let enabledDiagnostic = await enabledService.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: environment.backendBaseURL,
                                                                                                    roomEligibility: makeRoomEligibility())

        #expect(enabledDiagnostic.isEnabled)
        #expect(enabledDiagnostic.disabledReason == nil)
        #expect(enabledDiagnostic.isCapabilityPresent)
        #expect(enabledDiagnostic.areDependenciesReady)
        #expect(enabledDiagnostic.isRoomEligible)
        #expect(enabledDiagnostic.isEndpointAccepted)
        #expect(enabledDependencyProvider.callCount == 1)
        #expect(encryptionService.generateKeyCallCount == 0)
        #expect(encryptionService.consumeKeyCallCount == 0)
        #expect(encryptionService.clearKeyCallCount == 0)
        #expect(mediaEngineFactory.makeMediaEngineCallCount == 0)
        #expect(transport.requests.count == 1)
        assertActivationDiagnosticIsRedacted(enabledDiagnostic)
    }

    private func makeActivationReadyDependencies() -> NativeDirectCallProductionDependencies {
        NativeDirectCallProductionDependencies(encryptionService: ProductionDirectCallEncryptionService(),
                                               mediaEngineFactory: NoOpDirectCallMediaEngineFactory(),
                                               keyWrapperSource: .explicitWrapper)
    }

    private func makeRoomEligibility() -> DirectCallProductionRoomEligibility {
        DirectCallProductionRoomEligibility(isDirect: true,
                                            isEncrypted: true,
                                            joinedMemberCount: 2,
                                            hasPeerUserID: true)
    }

    private func assertActivationDiagnosticIsRedacted(_ diagnostic: DirectCallProductionActivationDryRunDiagnostic) {
        let description = String(describing: diagnostic)
        let forbiddenFragments = [
            "local-smoke",
            "127.0.0.1",
            DirectCallProductionConfiguration.tokenEndpointPath,
            "!local",
            "@bob",
            "participant_" + "token",
            "access_" + "token",
            "bearer",
            "j" + "wt",
            "raw " + "key",
            "encrypted_" + "payload",
            "debug" + "Info",
            "original" + "JSON",
            "raw " + "JSON"
        ]

        for fragment in forbiddenFragments {
            #expect(description.localizedCaseInsensitiveContains(fragment) == false)
        }
    }
}

private struct DirectCallBackendSmokeEnvironment: CustomStringConvertible, CustomDebugStringConvertible {
    static let smokeEnabledKey = "SALEMX_DIRECTCALL_BACKEND_SMOKE"
    static let backendBaseURLKey = "SALEMX_DIRECTCALL_BACKEND_BASE_URL"
    static let fakeAccessTokenKey = "SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN"
    static let smokeCreatedAtKey = "SALEMX_DIRECTCALL_BACKEND_SMOKE_CREATED_AT"
    static let smokeFileURL = URL(fileURLWithPath: "/tmp/salemx-direct-call-backend-smoke.env")
    static let smokeFileTTL: TimeInterval = 600

    static var current: DirectCallBackendSmokeEnvironment? {
        DirectCallBackendSmokeEnvironment(environment: ProcessInfo.processInfo.environment)
            ?? DirectCallBackendSmokeEnvironment(smokeFileURL: smokeFileURL)
    }

    static var isRunnableInCurrentProcess: Bool {
        current != nil
    }

    let backendBaseURL: URL
    let fakeAccessToken: String

    init?(environment: [String: String]) {
        guard environment[Self.smokeEnabledKey] == "1",
              let backendBaseURLString = Self.nonEmptyString(environment[Self.backendBaseURLKey]),
              let backendBaseURL = URL(string: backendBaseURLString),
              Self.isLocalBackendURL(backendBaseURL),
              let fakeAccessToken = Self.nonEmptyString(environment[Self.fakeAccessTokenKey]) else {
            return nil
        }

        self.backendBaseURL = backendBaseURL
        self.fakeAccessToken = fakeAccessToken
    }

    init?(smokeFileURL: URL) {
        guard let contents = try? String(contentsOf: smokeFileURL, encoding: .utf8) else {
            return nil
        }

        let environment = Self.environment(from: contents)
        guard let createdAtValue = environment[Self.smokeCreatedAtKey],
              let createdAt = TimeInterval(createdAtValue),
              Date().timeIntervalSince1970 - createdAt <= Self.smokeFileTTL else {
            return nil
        }

        self.init(environment: environment)
    }

    var description: String {
        "DirectCallBackendSmokeEnvironment(backendBaseURL: <redacted>, fakeAccessToken: <redacted>)"
    }

    var debugDescription: String {
        description
    }

    private static func isLocalBackendURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased() else {
            return false
        }

        return ["127.0.0.1", "localhost", "::1"].contains(host)
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else {
            return nil
        }

        return value
    }

    private static func environment(from contents: String) -> [String: String] {
        contents.split(whereSeparator: \.isNewline).reduce(into: [String: String]()) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return
            }

            result[parts[0]] = parts[1]
        }
    }
}

@MainActor
private struct DirectCallBackendSmokeAccessTokenProvider: DirectCallMatrixAccessTokenProviding {
    let accessToken: String?

    func matrixAccessToken() async -> String? {
        accessToken
    }
}

@MainActor
private final class DirectCallBackendSmokeRolloutProvider: DirectCallProductionRolloutProviding {
    private let configuration: DirectCallProductionConfiguration

    init(configuration: DirectCallProductionConfiguration) {
        self.configuration = configuration
    }

    func directCallProductionConfiguration() -> DirectCallProductionConfiguration {
        configuration
    }
}

@MainActor
private final class DirectCallBackendSmokeCapabilityProvider: DirectCallProductionCapabilityProviding {
    private let result: DirectCallProductionCapabilityDiscoveryResult

    init(result: DirectCallProductionCapabilityDiscoveryResult) {
        self.result = result
    }

    func directCallProductionServerCapability() async -> DirectCallProductionCapabilityDiscoveryResult {
        result
    }
}

@MainActor
private final class DirectCallBackendSmokeDependencyProvider: NativeDirectCallProductionDependencyProviding {
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
private final class DirectCallBackendSmokeCountingHTTPTransport: DirectCallHTTPTransportProtocol, CustomStringConvertible, CustomDebugStringConvertible {
    private let upstream: DirectCallHTTPTransportProtocol
    private(set) var requests = [DirectCallHTTPTransportRequest]()

    init(upstream: DirectCallHTTPTransportProtocol) {
        self.upstream = upstream
    }

    func send(_ request: DirectCallHTTPTransportRequest) async -> Result<DirectCallHTTPTransportResponse, DirectCallMediaError> {
        requests.append(request)
        return await upstream.send(request)
    }

    nonisolated var description: String {
        "DirectCallBackendSmokeCountingHTTPTransport(requestCount: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }
}
