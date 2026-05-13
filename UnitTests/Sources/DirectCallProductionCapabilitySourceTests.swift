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
                                                                    dependencyProvider: dependencyProvider)

        let diagnostic = await service.directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: homeserverBaseURL,
                                                                                      roomEligibility: makeRoomEligibility())

        #expect(diagnostic.disabledReason == .appRolloutDisabled)
        #expect(diagnostic.isCapabilityPresent == false)
        #expect(diagnostic.areDependenciesReady == false)
        #expect(capabilityProvider.callCount == 0)
        #expect(dependencyProvider.callCount == 0)
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
                                                                                                                                  hasPeerUserID: true)) -> DirectCallProductionActivationContext {
        .init(appRolloutEnabled: appRolloutEnabled,
              homeserverBaseURL: homeserverBaseURL,
              serverCapability: serverCapability,
              configuredTokenEndpointURL: configuredTokenEndpointURL,
              dependencies: dependencies ?? makeActivationReadyDependencies(),
              roomEligibility: roomEligibility)
    }

    private func makeServerCapability(tokenEndpointPath: String? = DirectCallProductionConfiguration.tokenEndpointPath) -> DirectCallProductionServerCapability {
        DirectCallProductionServerCapability(isEnabled: true,
                                             tokenEndpointPath: tokenEndpointPath,
                                             intents: [DirectCallIntent.audio.rawValue])
    }

    private func makeRoomEligibility() -> DirectCallProductionRoomEligibility {
        DirectCallProductionRoomEligibility(isDirect: true,
                                            isEncrypted: true,
                                            joinedMemberCount: 2,
                                            hasPeerUserID: true)
    }

    private func makeActivationReadyDependencies() -> NativeDirectCallProductionDependencies {
        NativeDirectCallProductionDependencies(encryptionService: ProductionDirectCallEncryptionService(),
                                               mediaEngineFactory: NoOpDirectCallMediaEngineFactory())
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
