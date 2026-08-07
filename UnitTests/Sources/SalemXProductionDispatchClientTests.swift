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
struct SalemXProductionDispatchClientTests {
    @Test
    func capabilityUsesExactContractAndBearerAuthentication() async throws {
        let transport = DispatchTransportSpy(response: .success(.init(statusCode: 200, data: Data(#"{"pushkit_token_registration_result":"registered","pushkit_token_redacted":true}"#.utf8))))
        let client = makeClient(transport: transport)
        let request = SalemXProductionDispatchCapabilityRegistrationRequest(token: secretToken,
                                                                            environment: .production,
                                                                            appSessionGeneration: generation)

        let result = await client.registerCapability(request)
        let sent = try #require(transport.requests.first)
        let body = try json(sent.body)

        #expect(try result.get().registrationResult == "registered")
        #expect(sent.url.path == SalemXProductionDispatchClient.capabilityPath)
        #expect(sent.method == "POST")
        #expect(sent.headers["Authorization"] == "Bearer \(accessToken)")
        #expect(Set(body.keys) == ["version", "token", "environment", "protocol_version", "intents", "receiver_handoff", "app_session_generation", "capability_expires_in_seconds"])
        #expect(body["token"] as? String == secretToken)
        #expect(String(describing: request).contains(secretToken) == false)
        #expect(String(describing: sent).contains(accessToken) == false)
    }

    @Test
    func prepareUsesExactPathKeysAndParsesPreparedResponse() async throws {
        let response = #"{"dispatch_protocol_version":1,"dispatch_id":"11111111-1111-4111-8111-111111111111","sender_reference":"sender-ref","receiver_reference":"receiver-ref","state":"prepared"}"#
        let transport = DispatchTransportSpy(response: .success(.init(statusCode: 200, data: Data(response.utf8))))
        let client = makeClient(transport: transport)

        let result = await client.prepare(prepareRequest())
        let sent = try #require(transport.requests.first)
        let body = try json(sent.body)

        #expect(try result.get().state == .prepared)
        #expect(sent.url.path == SalemXProductionDispatchClient.preparePath)
        #expect(Set(body.keys) == ["dispatch_protocol_version", "type", "version", "recipient", "call_handle", "call_kind", "created_at_ms", "expires_at_ms", "display_label", "delivery_mode", "app_session_generation", "pending_metadata"])
        let metadata = try #require(body["pending_metadata"] as? [String: Any])
        #expect(Set(metadata.keys) == ["version", "call_id", "room_id", "intent"])
    }

    @Test(arguments: [
        (SalemXProductionDispatchClient.claimPath, "claimed", "claimed"),
        (SalemXProductionDispatchClient.cancelPreparedPath, "cancelled", "cancelled")
    ])
    func referenceOperationsUseExactPathAndKeys(path: String, state: String, flag: String) async throws {
        let response = "{\"dispatch_protocol_version\":1,\"state\":\"\(state)\",\"\(flag)\":true}"
        let transport = DispatchTransportSpy(response: .success(.init(statusCode: 200, data: Data(response.utf8))))
        let client = makeClient(transport: transport)
        let request = referenceRequest()

        if state == "claimed" {
            _ = try await client.claim(request).get()
        } else {
            _ = try await client.cancelPrepared(request).get()
        }
        let sent = try #require(transport.requests.first)
        let body = try json(sent.body)

        #expect(sent.url.path == path)
        #expect(sent.method == "POST")
        #expect(Set(body.keys) == ["dispatch_protocol_version", "dispatch_id", "sender_reference", "app_session_generation"])
    }

    @Test
    func sendPreparedUsesExactContractAndParsesAcceptedResponse() async throws {
        let response = #"{"dispatch_protocol_version":1,"state":"sent","APNs_sent":true,"APNs_send_count":1,"raw_identifiers_logged":false}"#
        let transport = DispatchTransportSpy(response: .success(.init(statusCode: 200, data: Data(response.utf8))))
        let client = makeClient(transport: transport)

        let result = await client.sendPrepared(sendRequest())
        let sent = try #require(transport.requests.first)
        let body = try json(sent.body)

        #expect(try result.get().state == .sent)
        #expect(sent.url.path == SalemXProductionDispatchClient.sendPreparedPath)
        #expect(Set(body.keys) == ["dispatch_protocol_version", "dispatch_id", "sender_reference", "receiver_reference", "app_session_generation"])
    }

    @Test
    func unsupportedProtocolMalformedReferenceAndInvalidStateFailClosed() async {
        let unsupportedResponse = """
        {"dispatch_protocol_version":2,"dispatch_id":"11111111-1111-4111-8111-111111111111",
        "sender_reference":"sender-ref","receiver_reference":"receiver-ref","state":"prepared"}
        """
        let unsupported = DispatchTransportSpy(response: .success(.init(statusCode: 200,
                                                                        data: Data(unsupportedResponse.utf8))))
        #expect(await makeClient(transport: unsupported).prepare(prepareRequest()) == .failure(.unsupportedProtocol))

        let malformed = SalemXProductionDispatchReferenceRequest(dispatchID: dispatchID,
                                                                 senderReference: "",
                                                                 appSessionGeneration: generation)
        let unused = DispatchTransportSpy(response: .failure(.tokenUnavailable))
        #expect(await makeClient(transport: unused).claim(malformed) == .failure(.malformedReference))
        #expect(unused.requests.isEmpty)

        let invalidState = DispatchTransportSpy(response: .success(.init(statusCode: 200, data: Data(#"{"dispatch_protocol_version":1,"state":"cancelled","claimed":true}"#.utf8))))
        #expect(await makeClient(transport: invalidState).claim(referenceRequest()) == .failure(.invalidState))
    }

    @Test
    func responseDispatchMismatchIsRejected() async {
        let response = #"{"dispatch_protocol_version":1,"dispatch_id":"22222222-2222-4222-8222-222222222222","state":"claimed","claimed":true}"#
        let transport = DispatchTransportSpy(response: .success(.init(statusCode: 200, data: Data(response.utf8))))

        #expect(await makeClient(transport: transport).claim(referenceRequest()) == .failure(.dispatchMismatch))
    }

    @Test
    func transportAndHTTPFailuresAreRedactedAndNeverRetried() async {
        let transport = DispatchTransportSpy(response: .failure(.tokenUnavailable))
        let client = makeClient(transport: transport)
        #expect(await client.prepare(prepareRequest()) == .failure(.transportUnavailable))
        #expect(transport.requests.count == 1)

        transport.response = .success(.init(statusCode: 401, data: Data(#"{"errcode":"M_UNKNOWN_TOKEN","error":"private"}"#.utf8)))
        #expect(await client.claim(referenceRequest()) == .failure(.http(.authentication, .unknown)))
        #expect(transport.requests.count == 2)
        #expect(String(describing: SalemXProductionDispatchClientError.http(.authentication, .unknown)).contains("private") == false)
    }

    @Test
    func ambiguousSendRemainsAmbiguousAndIsNotRetried() async {
        let transport = DispatchTransportSpy(response: .failure(.tokenUnavailable))
        let result = await makeClient(transport: transport).sendPrepared(sendRequest())

        #expect(result == .failure(.ambiguousSend))
        #expect(transport.requests.count == 1)
    }

    @Test
    func cancellationPropagatesToTransport() async {
        let transport = DispatchTransportSpy(response: .failure(.tokenUnavailable), waitsForCancellation: true)
        let client = makeClient(transport: transport)
        let task = Task { await client.prepare(prepareRequest()) }
        await Task.yield()
        task.cancel()

        #expect(await task.value == .failure(.cancelled))
        #expect(transport.cancellationObserved)
        #expect(transport.requests.count == 1)
    }

    @Test
    func productionOriginRequiresHTTPSButExplicitTestOriginMayUseHTTP() async throws {
        let transport = DispatchTransportSpy(response: .failure(.tokenUnavailable))
        let insecureURL = try #require(URL(string: "http://localhost:8080"))
        let productionClient = SalemXProductionDispatchClient(homeserverOrigin: insecureURL,
                                                              httpTransport: transport,
                                                              accessTokenProvider: DispatchAccessTokenProvider(accessToken: accessToken))
        #expect(await productionClient.prepare(prepareRequest()) == .failure(.invalidConfiguration))
        #expect(transport.requests.isEmpty)

        let testClient = SalemXProductionDispatchClient(homeserverOrigin: insecureURL,
                                                        httpTransport: transport,
                                                        accessTokenProvider: DispatchAccessTokenProvider(accessToken: accessToken),
                                                        allowsInsecureTestOrigin: true)
        #expect(await testClient.prepare(prepareRequest()) == .failure(.transportUnavailable))
        #expect(transport.requests.count == 1)
    }

    @Test
    func receiverConsumeModelsMatchServerContract() throws {
        let request = SalemXProductionDispatchReceiverConsumeRequest(dispatchID: dispatchID,
                                                                     receiverReference: "receiver-ref",
                                                                     appSessionGeneration: generation)
        let requestBody = try json(JSONEncoder().encode(request))
        #expect(Set(requestBody.keys) == ["dispatch_protocol_version", "dispatch_id", "receiver_reference", "app_session_generation"])

        let response = #"{"dispatch_protocol_version":1,"state":"consumed","version":1,"call_id":"call","room_id":"room","peer_user_id":"peer","direction":"incoming","intent":"audio","expires_at_ms":123}"#
        let decoded = try JSONDecoder().decode(SalemXProductionDispatchReceiverConsumeResponse.self, from: Data(response.utf8))
        #expect(decoded.state == .consumed)
        #expect(String(describing: decoded).contains("room") == false)
    }

    private func makeClient(transport: DispatchTransportSpy) -> SalemXProductionDispatchClient {
        guard let homeserverOrigin = URL(string: "https://matrix.example.test") else {
            fatalError("Invalid static test URL")
        }
        return SalemXProductionDispatchClient(homeserverOrigin: homeserverOrigin,
                                              httpTransport: transport,
                                              accessTokenProvider: DispatchAccessTokenProvider(accessToken: accessToken))
    }

    private func prepareRequest() -> SalemXProductionDispatchPrepareRequest {
        .init(recipient: "@receiver:example.test",
              recipientDevice: nil,
              callHandle: "call-handle",
              createdAtMS: 1000,
              expiresAtMS: 61000,
              displayLabel: "Audio call",
              appSessionGeneration: generation,
              pendingMetadata: .init(callID: "call-id", roomID: "!room:example.test"))
    }

    private func referenceRequest() -> SalemXProductionDispatchReferenceRequest {
        .init(dispatchID: dispatchID, senderReference: "sender-ref", appSessionGeneration: generation)
    }

    private func sendRequest() -> SalemXProductionDispatchSendPreparedRequest {
        .init(dispatchID: dispatchID,
              senderReference: "sender-ref",
              receiverReference: "receiver-ref",
              appSessionGeneration: generation)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let dispatchID = UUID(uuid: (0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x41, 0x11, 0x81, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11))
    private let accessToken = "matrix-access-token-secret"
    private let secretToken = String(repeating: "a", count: 64)
    private let generation = "opaque-session-generation"
}

@MainActor
private final class DispatchTransportSpy: DirectCallHTTPTransportProtocol {
    var response: Result<DirectCallHTTPTransportResponse, DirectCallMediaError>
    private(set) var requests = [DirectCallHTTPTransportRequest]()
    private(set) var cancellationObserved = false
    private let waitsForCancellation: Bool

    init(response: Result<DirectCallHTTPTransportResponse, DirectCallMediaError>, waitsForCancellation: Bool = false) {
        self.response = response
        self.waitsForCancellation = waitsForCancellation
    }

    func send(_ request: DirectCallHTTPTransportRequest) async -> Result<DirectCallHTTPTransportResponse, DirectCallMediaError> {
        requests.append(request)
        if waitsForCancellation {
            while !Task.isCancelled {
                await Task.yield()
            }
            cancellationObserved = true
        }
        return response
    }
}

@MainActor
private struct DispatchAccessTokenProvider: DirectCallMatrixAccessTokenProviding {
    let accessToken: String?

    func matrixAccessToken() async -> String? {
        accessToken
    }
}
