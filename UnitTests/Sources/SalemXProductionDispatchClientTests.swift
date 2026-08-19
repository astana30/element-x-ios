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
    func transportFailuresAreNotRetried() async {
        let transport = DispatchTransportSpy(response: .failure(.tokenUnavailable))
        let client = makeClient(transport: transport)
        #expect(await client.prepare(prepareRequest()) == .failure(.transportUnavailable))
        #expect(transport.requests.count == 1)
    }

    @Test
    func authenticationFailureRetriesOnceWithARefreshedAccessToken() async throws {
        let prepared = #"{"dispatch_protocol_version":1,"dispatch_id":"11111111-1111-4111-8111-111111111111","sender_reference":"sender-ref","receiver_reference":"receiver-ref","state":"prepared"}"#
        let transport = DispatchTransportSpy(responses: [
            .success(.init(statusCode: 401, data: Data(#"{"errcode":"M_UNKNOWN_TOKEN","error":"private"}"#.utf8))),
            .success(.init(statusCode: 200, data: Data(prepared.utf8)))
        ])
        let provider = RotatingDispatchAccessTokenProvider(tokens: ["stale-token", "fresh-token"])
        let result = await makeClient(transport: transport, accessTokenProvider: provider).prepare(prepareRequest())

        #expect(try result.get().state == .prepared)
        #expect(transport.requests.count == 2)
        #expect(transport.requests[0].headers["Authorization"] == "Bearer stale-token")
        #expect(transport.requests[1].headers["Authorization"] == "Bearer fresh-token")
        #expect(provider.refreshCalls == 1)
        #expect(String(describing: result).contains("private") == false)
        #expect(String(describing: SalemXProductionDispatchClientError.http(.authentication, .unknown)).contains("private") == false)
    }

    @Test
    func authenticationFailureIsRetriedOnlyOnce() async {
        let transport = DispatchTransportSpy(response: .success(.init(statusCode: 401,
                                                                      data: Data(#"{"errcode":"M_UNKNOWN_TOKEN","error":"private"}"#.utf8))))
        #expect(await makeClient(transport: transport).prepare(prepareRequest()) == .failure(.http(.authentication, .unknown)))
        #expect(transport.requests.count == 2)
    }

    @Test
    func sendPreparedServerDeliveryFailureIsNotRetried() async {
        let transport = DispatchTransportSpy(response: .success(.init(statusCode: 502,
                                                                      data: Data(#"{"errcode":"M_DIRECT_CALL_APNS_DELIVERY_FAILED","error":"APNs delivery failed"}"#.utf8))))
        #expect(await makeClient(transport: transport).sendPrepared(sendRequest()) == .failure(.http(.server, .deliveryFailed)))
        #expect(transport.requests.count == 1)
    }

    @Test
    func invalidCallHandleBadRequestIsBucketedWithoutIdentifiers() async {
        let transport = DispatchTransportSpy(response: .success(.init(statusCode: 400,
                                                                      data: Data(#"{"errcode":"M_UNKNOWN","error":"Invalid foreground call handle."}"#.utf8))))
        #expect(await makeClient(transport: transport).prepare(prepareRequest()) == .failure(.http(.other, .invalidRequest)))
        #expect(SalemXProductionDispatchErrorSanitizer.loggedErrcode(from: Data(#"{"errcode":"M_UNKNOWN","error":"Invalid foreground call handle."}"#.utf8)) == "M_UNKNOWN")
        #expect(SalemXProductionDispatchErrorSanitizer.loggedErrorText(from: Data(#"{"errcode":"M_UNKNOWN","error":"Invalid foreground call handle."}"#.utf8)) == "Invalid foreground call handle")
        #expect(!SalemXProductionDispatchErrorSanitizer.sanitizeErrorText("User @alice:example.org missing").contains("alice"))
        #expect(SalemXProductionDispatchOpaqueToken.isValidCallHandle(SalemXProductionDispatchOpaqueToken.callHandle()))
        #expect(!SalemXProductionDispatchOpaqueToken.isValidCallHandle("_@alice:example.test_DEVICE_m.call"))
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
    func receiverConsumeUsesExactContractAndParsesResponse() async throws {
        let request = SalemXProductionDispatchReceiverConsumeRequest(dispatchID: dispatchID,
                                                                     receiverReference: "receiver-ref",
                                                                     appSessionGeneration: generation)
        let requestBody = try json(JSONEncoder().encode(request))
        #expect(Set(requestBody.keys) == ["dispatch_protocol_version", "dispatch_id", "receiver_reference", "app_session_generation"])

        let response = #"{"dispatch_protocol_version":1,"state":"consumed","version":1,"call_id":"call","room_id":"room","peer_user_id":"peer","direction":"incoming","intent":"audio","expires_at_ms":123}"#
        let transport = DispatchTransportSpy(response: .success(.init(statusCode: 200, data: Data(response.utf8))))
        let decoded = try await makeClient(transport: transport).consume(request).get()
        let sent = try #require(transport.requests.first)

        #expect(decoded.state == .consumed)
        #expect(sent.url.path == SalemXProductionDispatchClient.receiverConsumePath)
        #expect(sent.headers["Authorization"] == "Bearer \(accessToken)")
        #expect(sent.timeoutInterval == 4)
        #expect(String(describing: decoded).contains("room") == false)
    }

    private func makeClient(transport: DispatchTransportSpy,
                            accessTokenProvider: DirectCallMatrixAccessTokenProviding? = nil) -> SalemXProductionDispatchClient {
        guard let homeserverOrigin = URL(string: "https://matrix.example.test") else {
            fatalError("Invalid static test URL")
        }
        return SalemXProductionDispatchClient(homeserverOrigin: homeserverOrigin,
                                              httpTransport: transport,
                                              accessTokenProvider: accessTokenProvider ?? DispatchAccessTokenProvider(accessToken: accessToken))
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
    private var queuedResponses: [Result<DirectCallHTTPTransportResponse, DirectCallMediaError>]
    var response: Result<DirectCallHTTPTransportResponse, DirectCallMediaError> {
        get { queuedResponses.last ?? .failure(.tokenUnavailable) }
        set { queuedResponses = [newValue] }
    }
    private(set) var requests = [DirectCallHTTPTransportRequest]()
    private(set) var cancellationObserved = false
    private let waitsForCancellation: Bool

    init(response: Result<DirectCallHTTPTransportResponse, DirectCallMediaError>, waitsForCancellation: Bool = false) {
        queuedResponses = [response]
        self.waitsForCancellation = waitsForCancellation
    }

    init(responses: [Result<DirectCallHTTPTransportResponse, DirectCallMediaError>], waitsForCancellation: Bool = false) {
        queuedResponses = responses
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
        guard !queuedResponses.isEmpty else {
            return .failure(.tokenUnavailable)
        }
        if queuedResponses.count == 1 {
            return queuedResponses[0]
        }
        return queuedResponses.removeFirst()
    }
}

@MainActor
private struct DispatchAccessTokenProvider: DirectCallMatrixAccessTokenProviding {
    let accessToken: String?

    func matrixAccessToken() async -> String? {
        accessToken
    }
}

@MainActor
private final class RotatingDispatchAccessTokenProvider: DirectCallMatrixAccessTokenProviding {
    private var tokens: [String]
    private(set) var refreshCalls = 0

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func matrixAccessToken() async -> String? {
        tokens.first
    }

    func refreshedMatrixAccessToken() async -> String? {
        refreshCalls += 1
        if tokens.count > 1 {
            tokens.removeFirst()
        }
        return tokens.first
    }
}

@MainActor
struct SalemXProductionDispatchLoopbackTests {
    @Test
    func swiftURLSessionExercisesPythonRoutesAndPostgreSQL() async throws {
        guard let originValue = ProcessInfo.processInfo.environment["SALEMX_STAGE7_LOOPBACK_ORIGIN"] else {
            return
        }
        let origin = try #require(URL(string: originValue))
        let sender = makeClient(origin: origin, accessToken: senderAccessToken)
        let receiver = makeClient(origin: origin, accessToken: receiverAccessToken)

        _ = try await sender.registerCapability(.init(token: String(repeating: "a", count: 64),
                                                      environment: .production,
                                                      appSessionGeneration: senderGeneration)).get()
        _ = try await receiver.registerCapability(.init(token: String(repeating: "b", count: 64),
                                                        environment: .production,
                                                        appSessionGeneration: receiverGeneration)).get()

        let sentDispatch = try await prepareAndClaim(sender: sender,
                                                     roomID: "!stage7-swift-room:example.invalid",
                                                     callID: "stage7-swift-call")
        let sent = try await sender.sendPrepared(.init(dispatchID: sentDispatch.dispatchID,
                                                       senderReference: sentDispatch.senderReference,
                                                       receiverReference: sentDispatch.receiverReference,
                                                       appSessionGeneration: senderGeneration)).get()
        #expect(sent.state == .sent)
        #expect(sent.apnsSendCount == 1)

        let consumed = try await receiver.consume(.init(dispatchID: sentDispatch.dispatchID,
                                                        receiverReference: sentDispatch.receiverReference,
                                                        appSessionGeneration: receiverGeneration)).get()
        #expect(consumed.state == .consumed)
        #expect(consumed.callID == "stage7-swift-call")
        #expect(consumed.roomID == "!stage7-swift-room:example.invalid")
        #expect(consumed.peerUserID == senderUserID)
        #expect(await receiver.consume(.init(dispatchID: sentDispatch.dispatchID,
                                             receiverReference: sentDispatch.receiverReference,
                                             appSessionGeneration: receiverGeneration)) == .failure(.http(.conflict, .conflict)))

        let cancelledDispatch = try await sender.prepare(prepareRequest(roomID: "!stage7-cancel-room:example.invalid",
                                                                        callID: "stage7-cancel-call")).get()
        let cancelled = try await sender.cancelPrepared(.init(dispatchID: cancelledDispatch.dispatchID,
                                                              senderReference: cancelledDispatch.senderReference,
                                                              appSessionGeneration: senderGeneration)).get()
        #expect(cancelled.state == .cancelled)

        let ambiguousDispatch = try await prepareAndClaim(sender: sender,
                                                          roomID: "!stage7-ambiguous-room:example.invalid",
                                                          callID: "stage7-ambiguous-call")
        let ambiguous = await sender.sendPrepared(.init(dispatchID: ambiguousDispatch.dispatchID,
                                                        senderReference: ambiguousDispatch.senderReference,
                                                        receiverReference: ambiguousDispatch.receiverReference,
                                                        appSessionGeneration: senderGeneration))
        #expect(ambiguous == .failure(.http(.server, .deliveryFailed)))

        let unauthorized = makeClient(origin: origin, accessToken: "stage7-invalid-auth-token")
        let unauthorizedResult = await unauthorized.registerCapability(.init(token: String(repeating: "c", count: 64),
                                                                             environment: .production,
                                                                             appSessionGeneration: "stage7-invalid-generation"))
        #expect(unauthorizedResult == .failure(.http(.authentication, .unknown)))

        let metrics = try await metrics(origin: origin)
        #expect(metrics.senderAuthCount > 0)
        #expect(metrics.receiverAuthCount > 0)
        #expect(metrics.rejectedAuthCount == 1)
        #expect(metrics.fakeAPNsAttemptCount == 2)
        #expect(metrics.fakeAPNsAcceptedCount == 1)
        #expect(metrics.fakeAPNsAmbiguousCount == 1)
    }

    private func prepareAndClaim(sender: SalemXProductionDispatchClient,
                                 roomID: String,
                                 callID: String) async throws -> SalemXProductionDispatchPrepareResponse {
        let prepared = try await sender.prepare(prepareRequest(roomID: roomID, callID: callID)).get()
        let claimed = try await sender.claim(.init(dispatchID: prepared.dispatchID,
                                                   senderReference: prepared.senderReference,
                                                   appSessionGeneration: senderGeneration)).get()
        #expect(claimed.state == .claimed)
        return prepared
    }

    private func prepareRequest(roomID: String, callID: String) -> SalemXProductionDispatchPrepareRequest {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return .init(recipient: receiverUserID,
                     recipientDevice: nil,
                     callHandle: "stage7-loopback-handle",
                     createdAtMS: now,
                     expiresAtMS: now + 60000,
                     displayLabel: "Audio call",
                     appSessionGeneration: senderGeneration,
                     pendingMetadata: .init(callID: callID, roomID: roomID))
    }

    private func makeClient(origin: URL, accessToken: String) -> SalemXProductionDispatchClient {
        SalemXProductionDispatchClient(homeserverOrigin: origin,
                                       accessTokenProvider: Stage7AccessTokenProvider(accessToken: accessToken),
                                       allowsInsecureTestOrigin: true)
    }

    private func metrics(origin: URL) async throws -> Stage7LoopbackMetrics {
        let url = try #require(URL(string: metricsPath, relativeTo: origin)?.absoluteURL)
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        return try JSONDecoder().decode(Stage7LoopbackMetrics.self, from: data)
    }

    private let senderAccessToken = "stage7-sender-auth-token"
    private let receiverAccessToken = "stage7-receiver-auth-token"
    private let senderGeneration = "stage7-swift-sender-generation"
    private let receiverGeneration = "stage7-swift-receiver-generation"
    private let senderUserID = "@stage7-swift-sender:example.invalid"
    private let receiverUserID = "@stage7-swift-receiver:example.invalid"
    private let metricsPath = "/_salemx/test-only/stage7/metrics"
}

@MainActor
private struct Stage7AccessTokenProvider: DirectCallMatrixAccessTokenProviding {
    let accessToken: String

    func matrixAccessToken() async -> String? {
        accessToken
    }
}

private struct Stage7LoopbackMetrics: Decodable {
    let senderAuthCount: Int
    let receiverAuthCount: Int
    let rejectedAuthCount: Int
    let fakeAPNsAttemptCount: Int
    let fakeAPNsAcceptedCount: Int
    let fakeAPNsAmbiguousCount: Int

    private enum CodingKeys: String, CodingKey {
        case senderAuthCount = "sender_auth_count"
        case receiverAuthCount = "receiver_auth_count"
        case rejectedAuthCount = "rejected_auth_count"
        case fakeAPNsAttemptCount = "fake_apns_attempt_count"
        case fakeAPNsAcceptedCount = "fake_apns_accepted_count"
        case fakeAPNsAmbiguousCount = "fake_apns_ambiguous_count"
    }
}
