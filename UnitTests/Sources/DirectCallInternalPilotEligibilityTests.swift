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
final class DirectCallInternalPilotEligibilityTests {
    init() async throws {
        AppSettings.resetAllSettings()
    }

    deinit {
        AppSettings.resetAllSettings()
    }

    @Test
    func failClosedInternalPilotEligibilityProviderIsDisabledByDefault() async {
        let provider = FailClosedNativeDirectCallInternalPilotEligibilityProvider()

        let eligibility = await provider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest())

        #expect(eligibility == .disabled)
        #expect(eligibility.isEligible == false)
        assertEligibilityOutputIsRedacted(eligibility)
        #expect(String(describing: provider).contains("directOneToOneCallsEnabled") == false)
    }

    @Test
    func directOneToOneCallsSettingDoesNotEnableInternalPilotEligibility() async {
        let appSettings = AppSettings()
        appSettings.directOneToOneCallsEnabled = true
        let provider = FailClosedNativeDirectCallInternalPilotEligibilityProvider()

        let eligibility = await provider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest())

        #expect(appSettings.directOneToOneCallsEnabled)
        #expect(eligibility == .disabled)
        #expect(eligibility.isEligible == false)
    }

    @Test
    func failClosedInternalPilotActivationProviderIsDisabledByDefault() async {
        let provider = FailClosedNativeDirectCallInternalPilotActivationProvider()

        let activation = await provider.nativeDirectCallInternalPilotActivation(for: makeActivationContext(eligibility: .eligible))

        #expect(activation == .disabled)
        #expect(activation.allowsActivation == false)
        assertActivationOutputIsRedacted(activation)
        #expect(String(describing: provider).contains("directOneToOneCallsEnabled") == false)
    }

    @Test
    func failClosedInternalPilotRolloutProviderIsDisabledByDefault() {
        let provider = FailClosedNativeDirectCallInternalPilotRolloutProvider()

        let configuration = provider.nativeDirectCallInternalPilotRolloutConfiguration()

        #expect(configuration.isEnabled == false)
        #expect(String(describing: provider).contains("directOneToOneCallsEnabled") == false)
        #expect(String(describing: configuration).contains("isEnabled: false"))
    }

    @Test
    func directOneToOneCallsSettingDoesNotEnableInternalPilotActivation() async {
        let appSettings = AppSettings()
        appSettings.directOneToOneCallsEnabled = true
        let provider = FailClosedNativeDirectCallInternalPilotActivationProvider()

        let activation = await provider.nativeDirectCallInternalPilotActivation(for: makeActivationContext(eligibility: .eligible))

        #expect(appSettings.directOneToOneCallsEnabled)
        #expect(activation == .disabled)
        #expect(activation.allowsActivation == false)
    }

    @Test
    func serverBackedInternalPilotActivationProviderIsFailClosedWithoutAllGates() async {
        let provider = ServerBackedNativeDirectCallInternalPilotActivationProvider()
        let contexts: [NativeDirectCallInternalPilotActivationContext] = [
            makeActivationContext(isProductUIEnabled: true,
                                  isInternalPilotRolloutEnabled: false,
                                  eligibility: .eligible),
            makeActivationContext(isProductUIEnabled: false,
                                  isInternalPilotRolloutEnabled: true,
                                  eligibility: .eligible),
            makeActivationContext(isProductUIEnabled: true,
                                  isInternalPilotRolloutEnabled: true,
                                  isCapabilityPresent: false,
                                  eligibility: .eligible),
            makeActivationContext(isProductUIEnabled: true,
                                  isInternalPilotRolloutEnabled: true,
                                  eligibility: .disabled),
            makeActivationContext(isProductUIEnabled: true,
                                  isInternalPilotRolloutEnabled: true,
                                  eligibility: .failClosed)
        ]

        for context in contexts {
            let activation = await provider.nativeDirectCallInternalPilotActivation(for: context)

            #expect(activation.allowsActivation == false)
            assertActivationOutputIsRedacted(activation)
        }
    }

    @Test
    func serverBackedInternalPilotActivationProviderAllowsActivationOnlyWhenAllGatesPass() async {
        let provider = ServerBackedNativeDirectCallInternalPilotActivationProvider()
        let activation = await provider.nativeDirectCallInternalPilotActivation(for: makeActivationContext(eligibility: .eligible))

        #expect(activation == .activationAllowed)
        #expect(activation.allowsActivation)
        assertActivationOutputIsRedacted(activation)
        #expect(String(describing: provider).contains("directOneToOneCallsEnabled") == false)
    }

    @Test
    func serverBackedInternalPilotActivationProviderMapsSafeUnavailableReasons() async {
        let provider = ServerBackedNativeDirectCallInternalPilotActivationProvider()
        let cases: [(NativeDirectCallInternalPilotEligibility, NativeDirectCallInternalPilotActivation)] = [
            (.unavailable(reason: .accountNotEligible), .unavailable(reason: .accountNotEligible)),
            (.unavailable(reason: .peerNotEligible), .unavailable(reason: .peerNotEligible)),
            (.unavailable(reason: .roomNotEligible), .unavailable(reason: .roomNotEligible)),
            (.unavailable(reason: .trustNotReady), .unavailable(reason: .trustNotReady)),
            (.unavailable(reason: .serviceUnavailable), .unavailable(reason: .serviceUnavailable)),
            (.unavailable(reason: .capabilityMissing), .unavailable(reason: .capabilityMissing)),
            (.unavailable(reason: .unsupportedClient), .unavailable(reason: .unsupportedClient)),
            (.unavailable(reason: .unknown), .unavailable(reason: .unknown)),
            (.unsupported, .unavailable(reason: .unsupportedClient)),
            (.disabled, .disabled),
            (.failClosed, .disabled)
        ]

        for (eligibility, expectedActivation) in cases {
            let activation = await provider.nativeDirectCallInternalPilotActivation(for: makeActivationContext(eligibility: eligibility))

            #expect(activation == expectedActivation)
            #expect(activation.allowsActivation == false)
            assertActivationOutputIsRedacted(activation)
        }
    }

    @Test
    func serverBackedInternalPilotActivationProviderLocalStateOverridesBackendEligible() async {
        let provider = ServerBackedNativeDirectCallInternalPilotActivationProvider()
        let localFailureCases: [(NativeDirectCallInternalPilotActivationContext, NativeDirectCallInternalPilotActivation)] = [
            (makeActivationContext(eligibility: .eligible,
                                   roomEligibility: .init(isDirect: true, isEncrypted: false, joinedMemberCount: 2, hasPeerUserID: true)),
             .unavailable(reason: .roomNotEligible)),
            (makeActivationContext(eligibility: .eligible,
                                   peerTrustReadiness: .unverifiedDevice),
             .unavailable(reason: .trustNotReady)),
            (makeActivationContext(eligibility: .eligible,
                                   areDependenciesReady: false),
             .unavailable(reason: .dependenciesUnavailable)),
            (makeActivationContext(eligibility: .eligible,
                                   hasActiveSession: true),
             .unavailable(reason: .dependenciesUnavailable))
        ]

        for (context, expectedActivation) in localFailureCases {
            let activation = await provider.nativeDirectCallInternalPilotActivation(for: context)

            #expect(activation == expectedActivation)
            #expect(activation.allowsActivation == false)
        }
    }

    @Test
    func statusOnlyInternalPilotActivationProviderNeverAllowsActivation() async {
        let provider = StatusOnlyNativeDirectCallInternalPilotActivationProvider()

        let activation = await provider.nativeDirectCallInternalPilotActivation(for: makeActivationContext(eligibility: .eligible))

        #expect(activation == .eligibleForStatusOnly)
        #expect(activation.allowsActivation == false)
        assertActivationOutputIsRedacted(activation)
        #expect(String(describing: provider).contains("allowsActivation: false"))
    }

    @Test
    func backendEligibleAloneDoesNotEnableInternalPilotActivation() async {
        let provider = StatusOnlyNativeDirectCallInternalPilotActivationProvider()
        let context = makeActivationContext(isInternalPilotRolloutEnabled: false,
                                            eligibility: .eligible)

        let activation = await provider.nativeDirectCallInternalPilotActivation(for: context)

        #expect(activation == .disabled)
        #expect(activation.allowsActivation == false)
    }

    @Test
    func productUIOrEligibilityStatusDoesNotEnableInternalPilotActivation() async {
        let provider = StatusOnlyNativeDirectCallInternalPilotActivationProvider()
        let productUIOnlyContext = makeActivationContext(isInternalPilotRolloutEnabled: false,
                                                         eligibility: .eligible)
        let eligibilityStatusOnlyContext = NativeDirectCallInternalPilotActivationContext(isProductUIEnabled: false,
                                                                                          isInternalPilotRolloutEnabled: false,
                                                                                          isCapabilityPresent: true,
                                                                                          eligibility: .eligible,
                                                                                          roomEligibility: eligibleRoom,
                                                                                          peerTrustReadiness: .peerTrustReady,
                                                                                          areDependenciesReady: true)

        #expect(await provider.nativeDirectCallInternalPilotActivation(for: productUIOnlyContext) == .disabled)
        #expect(await provider.nativeDirectCallInternalPilotActivation(for: eligibilityStatusOnlyContext) == .disabled)
    }

    @Test
    func internalPilotActivationMapsEligibilityReasonsToSafeUnavailableReasons() async {
        let provider = StatusOnlyNativeDirectCallInternalPilotActivationProvider()
        let cases: [(NativeDirectCallInternalPilotEligibility, NativeDirectCallInternalPilotActivation)] = [
            (.unavailable(reason: .accountNotEligible), .unavailable(reason: .accountNotEligible)),
            (.unavailable(reason: .peerNotEligible), .unavailable(reason: .peerNotEligible)),
            (.unavailable(reason: .roomNotEligible), .unavailable(reason: .roomNotEligible)),
            (.unavailable(reason: .trustNotReady), .unavailable(reason: .trustNotReady)),
            (.unavailable(reason: .serviceUnavailable), .unavailable(reason: .serviceUnavailable)),
            (.unavailable(reason: .capabilityMissing), .unavailable(reason: .capabilityMissing)),
            (.unavailable(reason: .unsupportedClient), .unavailable(reason: .unsupportedClient)),
            (.unavailable(reason: .unknown), .unavailable(reason: .unknown)),
            (.unsupported, .unavailable(reason: .unsupportedClient)),
            (.disabled, .disabled),
            (.failClosed, .disabled)
        ]

        for (eligibility, expectedActivation) in cases {
            let activation = await provider.nativeDirectCallInternalPilotActivation(for: makeActivationContext(eligibility: eligibility))

            #expect(activation == expectedActivation)
            #expect(activation.allowsActivation == false)
            assertActivationOutputIsRedacted(activation)
        }
    }

    @Test
    func internalPilotActivationFailsClosedForMissingCapabilityOrDependencies() async {
        let provider = StatusOnlyNativeDirectCallInternalPilotActivationProvider()
        let missingCapability = makeActivationContext(isCapabilityPresent: false,
                                                      eligibility: .eligible)
        let missingDependencies = makeActivationContext(eligibility: .eligible,
                                                        areDependenciesReady: false)

        #expect(await provider.nativeDirectCallInternalPilotActivation(for: missingCapability) == .unavailable(reason: .capabilityMissing))
        #expect(await provider.nativeDirectCallInternalPilotActivation(for: missingDependencies) == .unavailable(reason: .dependenciesUnavailable))
    }

    @Test
    func localRoomAndTrustFailuresOverrideBackendEligibleActivation() async {
        let provider = StatusOnlyNativeDirectCallInternalPilotActivationProvider()
        let localFailureCases: [(NativeDirectCallInternalPilotActivationContext, NativeDirectCallInternalPilotActivation)] = [
            (makeActivationContext(eligibility: .eligible,
                                   roomEligibility: .init(isDirect: true, isEncrypted: false, joinedMemberCount: 2, hasPeerUserID: true)),
             .unavailable(reason: .roomNotEligible)),
            (makeActivationContext(eligibility: .eligible,
                                   roomEligibility: .init(isDirect: false, isEncrypted: true, joinedMemberCount: 2, hasPeerUserID: true)),
             .unavailable(reason: .roomNotEligible)),
            (makeActivationContext(eligibility: .eligible,
                                   roomEligibility: .init(isDirect: true, isEncrypted: true, joinedMemberCount: 3, hasPeerUserID: true)),
             .unavailable(reason: .roomNotEligible)),
            (makeActivationContext(eligibility: .eligible,
                                   roomEligibility: .init(isDirect: true, isEncrypted: true, joinedMemberCount: 2, hasPeerUserID: false)),
             .unavailable(reason: .roomNotEligible)),
            (makeActivationContext(eligibility: .eligible,
                                   peerTrustReadiness: .unverifiedDevice),
             .unavailable(reason: .trustNotReady))
        ]

        for (context, expectedActivation) in localFailureCases {
            let activation = await provider.nativeDirectCallInternalPilotActivation(for: context)

            #expect(activation == expectedActivation)
            #expect(activation.allowsActivation == false)
        }
    }

    @Test
    func internalPilotEligibilityRequestEncodesContractJSONAndRedactsIdentifiers() throws {
        let request = makeEligibilityRequest()

        let data = try JSONEncoder().encode(request)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(payload["version"] as? Int == 1)
        #expect(payload["room_id"] as? String == roomID)
        #expect(payload["peer_user_id"] as? String == peerUserID)
        #expect(payload["device_id"] as? String == deviceID)
        #expect(payload["intent"] as? String == "audio")
        #expect(String(describing: request).contains(roomID) == false)
        #expect(String(describing: request).contains(peerUserID) == false)
        #expect(String(describing: request).contains(deviceID) == false)
        #expect(String(reflecting: request).contains(roomID) == false)
        #expect(String(reflecting: request).contains(peerUserID) == false)
    }

    @Test
    func internalPilotEligibilityPayloadDecodesRedactedStates() throws {
        let decoder = NativeDirectCallInternalPilotEligibilityPayloadDecoder()
        let eligiblePayload = try JSONEncoder().encode(NativeDirectCallInternalPilotEligibilityPayload(state: .eligible,
                                                                                                       accountEligible: true,
                                                                                                       peerEligible: true,
                                                                                                       roomEligible: true,
                                                                                                       trustReady: true,
                                                                                                       serviceAvailable: true,
                                                                                                       capabilityPresent: true,
                                                                                                       clientSupported: true))

        let eligibility = decoder.decodeEligibility(from: eligiblePayload)
        let payload = try JSONDecoder().decode(NativeDirectCallInternalPilotEligibilityPayload.self, from: eligiblePayload)

        #expect(eligibility == .eligible)
        #expect(eligibility.isEligible)
        #expect(payload.capabilityPresent == true)
        assertEligibilityOutputIsRedacted(eligibility)
        #expect(String(describing: decoder).contains("redacted: true"))

        let camelCasePayload = Data(#"{"state":"eligible","capabilityPresent":true}"#.utf8)
        let camelCaseDecodedPayload = try JSONDecoder().decode(NativeDirectCallInternalPilotEligibilityPayload.self, from: camelCasePayload)

        #expect(camelCaseDecodedPayload.capabilityPresent == true)
    }

    @Test
    func internalPilotEligibilityPayloadDecodesUnavailableReasons() {
        let decoder = NativeDirectCallInternalPilotEligibilityPayloadDecoder()
        let cases: [(String, NativeDirectCallInternalPilotEligibility)] = [
            (#"{"state":"unavailable","reason":"accountNotEligible","account_eligible":false}"#, .unavailable(reason: .accountNotEligible)),
            (#"{"state":"unavailable","reason":"peerNotEligible","peer_eligible":false}"#, .unavailable(reason: .peerNotEligible)),
            (#"{"state":"unavailable","reason":"roomNotEligible","room_eligible":false}"#, .unavailable(reason: .roomNotEligible)),
            (#"{"state":"unavailable","reason":"trustNotReady","trust_ready":false}"#, .unavailable(reason: .trustNotReady)),
            (#"{"state":"unavailable","reason":"serviceUnavailable","service_available":false}"#, .unavailable(reason: .serviceUnavailable)),
            (#"{"state":"unavailable","reason":"capabilityMissing","capability_present":false}"#, .unavailable(reason: .capabilityMissing)),
            (#"{"state":"unavailable","reason":"unsupportedClient","client_supported":false}"#, .unavailable(reason: .unsupportedClient)),
            (#"{"state":"unavailable","reason":null}"#, .unavailable(reason: .unknown)),
            (#"{"state":"unavailable"}"#, .unavailable(reason: .unknown)),
            (#"{"state":"disabled"}"#, .disabled),
            (#"{"state":"unsupported"}"#, .unsupported),
            (#"{"state":"failClosed"}"#, .failClosed)
        ]

        for (payload, expectedEligibility) in cases {
            let eligibility = decoder.decodeEligibility(from: Data(payload.utf8))

            #expect(eligibility == expectedEligibility)
            #expect(eligibility.isEligible == false)
            assertEligibilityOutputIsRedacted(eligibility)
        }
    }

    @Test
    func missingOrMalformedInternalPilotEligibilityFailsClosed() {
        let decoder = NativeDirectCallInternalPilotEligibilityPayloadDecoder()
        let cases = [
            Data(),
            Data("{}".utf8),
            Data(#"{"state":true}"#.utf8),
            Data(#"{"state":"unavailable","reason":"@alice:example.com"}"#.utf8)
        ]

        for payload in cases {
            let eligibility = decoder.decodeEligibility(from: payload)

            #expect(eligibility == .failClosed)
            #expect(eligibility.isEligible == false)
        }
    }

    @Test
    func httpEligibilityProviderFailsClosedWithoutEndpointTransportOrAccessToken() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.test/_matrix/client/unstable/kz.salemx.direct_call/eligibility"))
        let transport = NativeAudioEligibilityHTTPTransportSpy()
        let accessTokenProvider = NativeAudioEligibilityAccessTokenProviderStub(accessToken: "matrix-access-credential")
        let missingEndpointProvider = HTTPNativeDirectCallInternalPilotEligibilityProvider(httpTransport: transport,
                                                                                           accessTokenProvider: accessTokenProvider)
        let missingTransportProvider = HTTPNativeDirectCallInternalPilotEligibilityProvider(endpointURL: endpointURL,
                                                                                            accessTokenProvider: accessTokenProvider)
        let missingAccessTokenProvider = HTTPNativeDirectCallInternalPilotEligibilityProvider(endpointURL: endpointURL,
                                                                                              httpTransport: transport,
                                                                                              accessTokenProvider: NativeAudioEligibilityAccessTokenProviderStub(accessToken: nil))

        #expect(await missingEndpointProvider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest()) == .failClosed)
        #expect(await missingTransportProvider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest()) == .failClosed)
        #expect(await missingAccessTokenProvider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest()) == .failClosed)
        #expect(transport.requests.isEmpty)
        #expect(String(describing: missingEndpointProvider).contains(endpointURL.absoluteString) == false)
        #expect(String(describing: missingEndpointProvider).contains("matrix-access-credential") == false)
    }

    @Test
    func httpEligibilityProviderBuildsRedactedPOSTRequestAndDecodesEligibleResponse() async throws {
        let endpointBaseURL = try #require(URL(string: "https://call-service.example.test/base?ignored=true#fragment"))
        let responseData = Data("""
        {
          "state": "eligible",
          "reason": null,
          "account_eligible": true,
          "peer_eligible": true,
          "room_eligible": true,
          "trust_ready": true,
          "service_available": true,
          "capability_present": true,
          "client_supported": true
        }
        """.utf8)
        let transport = NativeAudioEligibilityHTTPTransportSpy(result: .success(.init(statusCode: 200, data: responseData)))
        let provider = HTTPNativeDirectCallInternalPilotEligibilityProvider(endpointBaseURL: endpointBaseURL,
                                                                            httpTransport: transport,
                                                                            accessTokenProvider: NativeAudioEligibilityAccessTokenProviderStub(accessToken: "matrix-access-credential"))

        let eligibility = await provider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest())

        #expect(eligibility == .eligible)
        let transportRequest = try #require(transport.requests.first)
        #expect(transport.requests.count == 1)
        #expect(transportRequest.method == "POST")
        #expect(transportRequest.url.scheme == "https")
        #expect(transportRequest.url.host == "call-service.example.test")
        #expect(transportRequest.url.path == "/base\(DirectCallProductionConfiguration.eligibilityEndpointPath)")
        #expect(transportRequest.url.query == nil)
        #expect(transportRequest.url.fragment == nil)
        #expect(transportRequest.headers["Accept"] == "application/json")
        #expect(transportRequest.headers["Content-Type"] == "application/json")
        #expect(transportRequest.headers["Authorization"] == "Bearer matrix-access-credential")
        let body = try #require(JSONSerialization.jsonObject(with: transportRequest.body) as? [String: Any])
        #expect(body["version"] as? Int == 1)
        #expect(body["room_id"] as? String == roomID)
        #expect(body["peer_user_id"] as? String == peerUserID)
        #expect(body["device_id"] as? String == deviceID)
        #expect(body["intent"] as? String == "audio")
        #expect(String(describing: provider).contains(endpointBaseURL.absoluteString) == false)
        #expect(String(describing: transportRequest).contains(endpointBaseURL.absoluteString) == false)
        #expect(String(describing: transportRequest).contains("matrix-access-credential") == false)
        assertEligibilityOutputIsRedacted(eligibility)
    }

    @Test
    func httpEligibilityProviderDecodesUnavailableReasons() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.test/_matrix/client/unstable/kz.salemx.direct_call/eligibility"))
        let cases: [(String, NativeDirectCallInternalPilotEligibility)] = [
            (#"{"state":"unavailable","reason":"accountNotEligible","account_eligible":false}"#, .unavailable(reason: .accountNotEligible)),
            (#"{"state":"unavailable","reason":"peerNotEligible","peer_eligible":false}"#, .unavailable(reason: .peerNotEligible)),
            (#"{"state":"unavailable","reason":"roomNotEligible","room_eligible":false}"#, .unavailable(reason: .roomNotEligible)),
            (#"{"state":"unavailable","reason":"trustNotReady","trust_ready":false}"#, .unavailable(reason: .trustNotReady))
        ]

        for (payload, expectedEligibility) in cases {
            let transport = NativeAudioEligibilityHTTPTransportSpy(result: .success(.init(statusCode: 200, data: Data(payload.utf8))))
            let provider = HTTPNativeDirectCallInternalPilotEligibilityProvider(endpointURL: endpointURL,
                                                                                httpTransport: transport,
                                                                                accessTokenProvider: NativeAudioEligibilityAccessTokenProviderStub(accessToken: "matrix-access-credential"))

            let eligibility = await provider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest())

            #expect(eligibility == expectedEligibility)
            #expect(transport.requests.count == 1)
            assertEligibilityOutputIsRedacted(eligibility)
        }
    }

    @Test
    func httpEligibilityProviderMapsHTTPAndTransportFailuresToSafeResults() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.test/_matrix/client/unstable/kz.salemx.direct_call/eligibility"))
        let cases: [(Int, NativeDirectCallInternalPilotEligibility)] = [
            (401, .unavailable(reason: .serviceUnavailable)),
            (403, .unavailable(reason: .serviceUnavailable)),
            (404, .unavailable(reason: .capabilityMissing)),
            (429, .failClosed),
            (500, .unavailable(reason: .serviceUnavailable))
        ]

        for (statusCode, expectedEligibility) in cases {
            let transport = NativeAudioEligibilityHTTPTransportSpy(result: .success(.init(statusCode: statusCode, data: Data("redacted".utf8))))
            let provider = HTTPNativeDirectCallInternalPilotEligibilityProvider(endpointURL: endpointURL,
                                                                                httpTransport: transport,
                                                                                accessTokenProvider: NativeAudioEligibilityAccessTokenProviderStub(accessToken: "matrix-access-credential"))

            let eligibility = await provider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest())

            #expect(eligibility == expectedEligibility)
            #expect(transport.requests.count == 1)
            assertEligibilityOutputIsRedacted(eligibility)
        }

        let failingTransport = NativeAudioEligibilityHTTPTransportSpy(result: .failure(.tokenUnavailable))
        let provider = HTTPNativeDirectCallInternalPilotEligibilityProvider(endpointURL: endpointURL,
                                                                            httpTransport: failingTransport,
                                                                            accessTokenProvider: NativeAudioEligibilityAccessTokenProviderStub(accessToken: "matrix-access-credential"))

        #expect(await provider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest()) == .unavailable(reason: .serviceUnavailable))
        #expect(failingTransport.requests.count == 1)
    }

    @Test
    func httpEligibilityProviderFailsClosedForMalformedOrUnsupportedPayloads() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.test/_matrix/client/unstable/kz.salemx.direct_call/eligibility"))
        let malformedPayloads = [
            Data("not-json".utf8),
            Data("{}".utf8),
            Data(#"{"state":"maybe"}"#.utf8),
            Data(#"{"state":"unavailable","reason":"@alice:example.test"}"#.utf8)
        ]

        for payload in malformedPayloads {
            let transport = NativeAudioEligibilityHTTPTransportSpy(result: .success(.init(statusCode: 200, data: payload)))
            let provider = HTTPNativeDirectCallInternalPilotEligibilityProvider(endpointURL: endpointURL,
                                                                                httpTransport: transport,
                                                                                accessTokenProvider: NativeAudioEligibilityAccessTokenProviderStub(accessToken: "matrix-access-credential"))

            let eligibility = await provider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest())

            #expect(eligibility == .failClosed)
            #expect(transport.requests.count == 1)
        }
    }

    @Test
    func httpEligibilityProviderRejectsUnsupportedIntentBeforeHTTP() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.test/_matrix/client/unstable/kz.salemx.direct_call/eligibility"))
        let transport = NativeAudioEligibilityHTTPTransportSpy(result: .success(.init(statusCode: 200, data: Data(#"{"state":"eligible"}"#.utf8))))
        let provider = HTTPNativeDirectCallInternalPilotEligibilityProvider(endpointURL: endpointURL,
                                                                            httpTransport: transport,
                                                                            accessTokenProvider: NativeAudioEligibilityAccessTokenProviderStub(accessToken: "matrix-access-credential"))

        let eligibility = await provider.nativeDirectCallInternalPilotEligibility(for: makeEligibilityRequest(intent: .video))

        #expect(eligibility == .unsupported)
        #expect(transport.requests.isEmpty)
    }

    @Test
    func internalPilotUnavailableReasonsMapToUserSafeCardCopy() {
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.accountNotEligible) == .accountNotEligible)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.peerNotEligible) == .peerNotEligible)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.roomNotEligible) == .roomNotOneToOne)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.trustNotReady) == .peerTrustUnavailable)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.serviceUnavailable) == .callServiceUnavailable)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.capabilityMissing) == .serverUnsupported)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.unsupportedClient) == .serverUnsupported)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.unknown) == .unknown)

        let accountState = NativeDirectCallRoomCardState.unavailable(reason: .accountNotEligible)
        let peerState = NativeDirectCallRoomCardState.unavailable(reason: .peerNotEligible)
        #expect(accountState.displayText == UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHere)
        #expect(accountState.detailText == UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHereDetail)
        #expect(peerState.displayText == UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHere)
        #expect(peerState.detailText == UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHereDetail)
    }

    #if DEBUG
    @Test
    func productUIGateAloneDoesNotEnablePrivateDogfoodOrProductionStart() {
        let productOnlyEnvironment = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1",
            "NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED": "1"
        ]

        #expect(ProcessInfo.isNativeDirectCallProductUIEnabled(environment: productOnlyEnvironment))
        #expect(ProcessInfo.isNativeDirectCallPrivateDogfoodEnabled(environment: productOnlyEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: productOnlyEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallEligibilityStatusEnabled(environment: productOnlyEnvironment) == false)
    }

    @Test
    func eligibilityStatusGateRequiresDebugIntegrationHarnessAndDoesNotEnableDogfood() {
        let statusWithoutHarness = [
            "NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED": "1"
        ]
        let statusWithHarness = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1",
            "NATIVE_DIRECT_CALL_ELIGIBILITY_STATUS_ENABLED": "1"
        ]

        #expect(ProcessInfo.isNativeDirectCallEligibilityStatusEnabled(environment: statusWithoutHarness) == false)
        #expect(ProcessInfo.isNativeDirectCallEligibilityStatusEnabled(environment: statusWithHarness))
        #expect(ProcessInfo.isNativeDirectCallPrivateDogfoodEnabled(environment: statusWithHarness) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: statusWithHarness) == false)
    }

    @Test
    func internalPilotRolloutGateRequiresDebugIntegrationHarnessAndDoesNotEnableDogfood() {
        let rolloutWithoutHarness = [
            "NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED": "1"
        ]
        let rolloutWithHarness = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1",
            "NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED": "1"
        ]
        let provider = EnvironmentNativeDirectCallInternalPilotRolloutProvider(environment: rolloutWithHarness)

        #expect(ProcessInfo.isNativeDirectCallInternalPilotRolloutEnabled(environment: rolloutWithoutHarness) == false)
        #expect(ProcessInfo.isNativeDirectCallInternalPilotRolloutEnabled(environment: rolloutWithHarness))
        #expect(ProcessInfo.isNativeDirectCallPrivateDogfoodEnabled(environment: rolloutWithHarness) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: rolloutWithHarness) == false)
        #expect(provider.nativeDirectCallInternalPilotRolloutConfiguration().isEnabled)
        #expect(String(describing: provider).contains("NATIVE_DIRECT_CALL_INTERNAL_PILOT_ROLLOUT_ENABLED") == false)
    }

    @Test
    func privateDogfoodGateRequiresDebugIntegrationHarness() {
        let dogfoodWithoutHarness = [
            "NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED": "1",
            "NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED": "1"
        ]
        let dogfoodWithHarness = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1",
            "NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED": "1",
            "NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED": "1"
        ]

        #expect(ProcessInfo.isNativeDirectCallPrivateDogfoodEnabled(environment: dogfoodWithoutHarness) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: dogfoodWithoutHarness) == false)
        #expect(ProcessInfo.isNativeDirectCallPrivateDogfoodEnabled(environment: dogfoodWithHarness))
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: dogfoodWithHarness))
    }
    #endif

    @Test
    func eligibilityStatusCacheUsesRedactedKeysAndSeparateTTLs() {
        var now = Date(timeIntervalSince1970: 100)
        let cache = NativeDirectCallEligibilityStatusCache(positiveTTL: 60,
                                                           negativeTTL: 20) { now }
        let request = makeEligibilityRequest()
        let key = NativeDirectCallEligibilityStatusCacheKey(request: request)

        cache.store(.eligible, for: request)
        now = Date(timeIntervalSince1970: 150)
        #expect(cache.eligibility(for: request) == .eligible)
        now = Date(timeIntervalSince1970: 161)
        #expect(cache.eligibility(for: request) == nil)

        now = Date(timeIntervalSince1970: 200)
        cache.store(.unavailable(reason: .accountNotEligible), for: request)
        now = Date(timeIntervalSince1970: 219)
        #expect(cache.eligibility(for: request) == .unavailable(reason: .accountNotEligible))
        now = Date(timeIntervalSince1970: 221)
        #expect(cache.eligibility(for: request) == nil)
        #expect(String(describing: key).contains(roomID) == false)
        #expect(String(describing: key).contains(peerUserID) == false)
        #expect(String(describing: key).contains(deviceID) == false)
    }

    @Test
    func eligibilityStatusCacheInvalidatesAndClearsEntries() {
        let cache = NativeDirectCallEligibilityStatusCache()
        let request = makeEligibilityRequest()
        let otherRequest = NativeDirectCallInternalPilotEligibilityRequest(roomID: "!other:example.test",
                                                                           peerUserID: "@other:example.test",
                                                                           deviceID: "OTHER",
                                                                           intent: .audio)

        cache.store(.eligible, for: request)
        cache.store(.unavailable(reason: .peerNotEligible), for: otherRequest)
        cache.invalidate(for: request)
        #expect(cache.eligibility(for: request) == nil)
        #expect(cache.eligibility(for: otherRequest) == .unavailable(reason: .peerNotEligible))

        cache.removeAll()
        #expect(cache.eligibility(for: otherRequest) == nil)
    }

    private let roomID = "!room:example.test"
    private let peerUserID = "@bob:example.test"
    private let deviceID = "DEVICEID"
    private var eligibleRoom: DirectCallProductionRoomEligibility {
        .init(isDirect: true,
              isEncrypted: true,
              joinedMemberCount: 2,
              hasPeerUserID: true)
    }

    private func makeEligibilityRequest(intent: DirectCallIntent = .audio) -> NativeDirectCallInternalPilotEligibilityRequest {
        .init(roomID: roomID,
              peerUserID: peerUserID,
              deviceID: deviceID,
              intent: intent)
    }

    private func makeActivationContext(isProductUIEnabled: Bool = true,
                                       isInternalPilotRolloutEnabled: Bool = true,
                                       isCapabilityPresent: Bool = true,
                                       eligibility: NativeDirectCallInternalPilotEligibility,
                                       roomEligibility: DirectCallProductionRoomEligibility? = nil,
                                       peerTrustReadiness: DirectCallPeerTrustReadiness = .peerTrustReady,
                                       areDependenciesReady: Bool = true,
                                       hasActiveSession: Bool = false) -> NativeDirectCallInternalPilotActivationContext {
        .init(isProductUIEnabled: isProductUIEnabled,
              isInternalPilotRolloutEnabled: isInternalPilotRolloutEnabled,
              isCapabilityPresent: isCapabilityPresent,
              eligibility: eligibility,
              roomEligibility: roomEligibility ?? eligibleRoom,
              peerTrustReadiness: peerTrustReadiness,
              areDependenciesReady: areDependenciesReady,
              hasActiveSession: hasActiveSession)
    }

    private func assertEligibilityOutputIsRedacted(_ eligibility: NativeDirectCallInternalPilotEligibility) {
        let description = String(describing: eligibility)
        let forbiddenFragments = [
            "!room",
            "@alice",
            "device",
            "participant_" + "token",
            "access_" + "token",
            "bearer",
            "j" + "wt",
            "livekit",
            "room_name",
            "raw " + "key",
            "matrix.example.com",
            "redis://"
        ]

        for fragment in forbiddenFragments {
            #expect(description.localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    private func assertActivationOutputIsRedacted(_ activation: NativeDirectCallInternalPilotActivation) {
        let description = String(describing: activation)
        let forbiddenFragments = [
            "!room",
            "@alice",
            "@bob",
            "device",
            "participant_" + "token",
            "access_" + "token",
            "bearer",
            "j" + "wt",
            "livekit",
            "room_name",
            "raw " + "key",
            "matrix.example.com",
            "redis://"
        ]

        for fragment in forbiddenFragments {
            #expect(description.localizedCaseInsensitiveContains(fragment) == false)
        }
    }
}

@MainActor
private final class NativeAudioEligibilityHTTPTransportSpy: DirectCallHTTPTransportProtocol {
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
private struct NativeAudioEligibilityAccessTokenProviderStub: DirectCallMatrixAccessTokenProviding {
    let accessToken: String?

    func matrixAccessToken() async -> String? {
        accessToken
    }
}
