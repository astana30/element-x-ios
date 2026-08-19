//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
protocol DirectCallMediaEngineProtocol {
    var mediaStatePublisher: CurrentValuePublisher<DirectCallMediaState, Never> { get }

    func prepareAudioSession(for session: DirectCallSession) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func connectAudio(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func setMicrophoneEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func setSpeakerEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError>
    func disconnect(callID: String) async
    func cleanup(callID: String) async
}

#if DEBUG
@MainActor
protocol DirectCallMediaDiagnosticSnapshotProviding {
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot { get }
}
#endif

@MainActor
protocol DirectCallMediaTokenProviderProtocol {
    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError>
}

@MainActor
protocol DirectCallMediaCredentialsBoundaryRequesting {
    func requestMediaCredentials(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError>
}

enum DirectCallLiveKitTokenDirection: String, Codable, Equatable {
    case incoming
    case outgoing

    init(_ direction: DirectCallDirection) {
        switch direction {
        case .incoming:
            self = .incoming
        case .outgoing:
            self = .outgoing
        }
    }
}

struct DirectCallLiveKitTokenRequest: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let callID: String
    let roomID: String
    let peerUserID: String
    let intent: DirectCallIntent
    let direction: DirectCallLiveKitTokenDirection
    let deviceID: String?
    let clientTransactionID: String?

    init(callID: String,
         roomID: String,
         peerUserID: String,
         intent: DirectCallIntent = .audio,
         direction: DirectCallLiveKitTokenDirection = .outgoing,
         deviceID: String? = nil,
         clientTransactionID: String? = nil) {
        self.callID = callID
        self.roomID = roomID
        self.peerUserID = peerUserID
        self.intent = intent
        self.direction = direction
        self.deviceID = deviceID
        self.clientTransactionID = clientTransactionID
    }

    var description: String {
        "DirectCallLiveKitTokenRequest(callID: <redacted>, roomID: <redacted>, peerUserID: <redacted>, intent: \(intent.rawValue), direction: \(direction.rawValue), deviceID: <redacted>, clientTransactionID: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallLiveKitTokenResponse: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let serverURLString: String
    let roomName: String
    let token: String
    var expiresAtPresent = false

    init(serverURLString: String, roomName: String, token: String, expiresAtPresent: Bool = false) {
        self.serverURLString = serverURLString
        self.roomName = roomName
        self.token = token
        self.expiresAtPresent = expiresAtPresent
    }

    var description: String {
        "DirectCallLiveKitTokenResponse(serverURLString: <redacted>, roomName: <redacted>, token: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol DirectCallLiveKitTokenClientProtocol {
    func connection(for request: DirectCallLiveKitTokenRequest) async -> Result<DirectCallLiveKitTokenResponse, DirectCallMediaError>
}

struct DirectCallProductionLiveKitTokenRequestDTO: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let version: Int
    let callID: String
    let roomID: String
    let peerUserID: String
    let intent: String
    let direction: DirectCallLiveKitTokenDirection
    let deviceID: String?
    let clientTransactionID: String?

    init(version: Int = 1, request: DirectCallLiveKitTokenRequest) {
        self.version = version
        callID = request.callID
        roomID = request.roomID
        peerUserID = request.peerUserID
        intent = request.intent.rawValue
        direction = request.direction
        deviceID = request.deviceID
        clientTransactionID = request.clientTransactionID
    }

    var description: String {
        "DirectCallProductionLiveKitTokenRequestDTO(version: \(version), callID: <redacted>, roomID: <redacted>, peerUserID: <redacted>, intent: \(intent), direction: \(direction.rawValue), deviceID: <redacted>, clientTransactionID: <redacted>)"
    }

    var debugDescription: String {
        description
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case callID = "call_id"
        case roomID = "room_id"
        case peerUserID = "peer_user_id"
        case intent
        case direction
        case deviceID = "device_id"
        case clientTransactionID = "client_transaction_id"
    }
}

struct DirectCallProductionLiveKitTokenResponseDTO: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    struct LiveKit: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
        let serverURL: String
        let roomName: String
        let participantToken: String
        let expiresAt: String?

        var description: String {
            "LiveKit(serverURL: <redacted>, roomName: <redacted>, participantToken: <redacted>, expiresAt: \(expiresAt ?? "<nil>"))"
        }

        var debugDescription: String {
            description
        }

        private enum CodingKeys: String, CodingKey {
            case serverURL = "server_url"
            case roomName = "room_name"
            case participantToken = "participant_token"
            case expiresAt = "expires_at"
        }
    }

    struct Allocation: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
        let id: String
        let callID: String
        let intent: String

        var description: String {
            "Allocation(id: <redacted>, callID: <redacted>, intent: \(intent))"
        }

        var debugDescription: String {
            description
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case callID = "call_id"
            case intent
        }
    }

    let version: Int
    let liveKit: LiveKit
    let allocation: Allocation
    let diagnostics: DirectCallProductionLiveKitTokenDiagnosticsDTO?

    var description: String {
        "DirectCallProductionLiveKitTokenResponseDTO(version: \(version), liveKit: \(liveKit), allocation: \(allocation))"
    }

    var debugDescription: String {
        description
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case liveKit = "livekit"
        case allocation
        case diagnostics
    }
}

struct DirectCallProductionLiveKitTokenDiagnosticsDTO: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let tokenRequestSeen: Bool
    let tokenStatus: Int?
    let tokenErrcode: String?
    let tokenReason: DirectCallDiagnosticTokenReason
    let eligibilityAllowed: Bool
    let rateLimited: Bool
    let allocationAttempted: Bool
    let liveKitRoomPrecreateAttempted: Bool
    let tokenIssued: Bool

    init(tokenRequestSeen: Bool = false,
         tokenStatus: Int? = nil,
         tokenErrcode: String? = nil,
         tokenReason: DirectCallDiagnosticTokenReason = .unknown,
         eligibilityAllowed: Bool = false,
         rateLimited: Bool = false,
         allocationAttempted: Bool = false,
         liveKitRoomPrecreateAttempted: Bool = false,
         tokenIssued: Bool = false) {
        self.tokenRequestSeen = tokenRequestSeen
        self.tokenStatus = tokenStatus
        self.tokenErrcode = tokenErrcode
        self.tokenReason = tokenReason
        self.eligibilityAllowed = eligibilityAllowed
        self.rateLimited = rateLimited
        self.allocationAttempted = allocationAttempted
        self.liveKitRoomPrecreateAttempted = liveKitRoomPrecreateAttempted
        self.tokenIssued = tokenIssued
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokenRequestSeen = try container.decodeIfPresent(Bool.self, forKey: .tokenRequestSeen) ?? false
        tokenStatus = try container.decodeIfPresent(Int.self, forKey: .tokenStatus)
        tokenErrcode = try container.decodeIfPresent(String.self, forKey: .tokenErrcode)
        tokenReason = try container.decodeIfPresent(DirectCallDiagnosticTokenReason.self, forKey: .tokenReason) ?? .unknown
        eligibilityAllowed = try container.decodeIfPresent(Bool.self, forKey: .eligibilityAllowed) ?? false
        rateLimited = try container.decodeIfPresent(Bool.self, forKey: .rateLimited) ?? false
        allocationAttempted = try container.decodeIfPresent(Bool.self, forKey: .allocationAttempted) ?? false
        liveKitRoomPrecreateAttempted = try container.decodeIfPresent(Bool.self, forKey: .liveKitRoomPrecreateAttempted) ?? false
        tokenIssued = try container.decodeIfPresent(Bool.self, forKey: .tokenIssued) ?? false
    }

    #if DEBUG
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        var snapshot = DirectCallDiagnosticSnapshot()
        snapshot.tokenRequestSeen = tokenRequestSeen
        snapshot.tokenStatus = tokenStatus
        snapshot.tokenErrcode = tokenErrcode
        snapshot.tokenReason = tokenReason
        snapshot.tokenEligibilityAllowed = eligibilityAllowed
        snapshot.tokenRateLimited = rateLimited
        snapshot.tokenAllocationAttempted = allocationAttempted
        snapshot.tokenLiveKitRoomPrecreateAttempted = liveKitRoomPrecreateAttempted
        snapshot.tokenIssued = tokenIssued
        return snapshot
    }
    #endif

    var description: String {
        "DirectCallProductionLiveKitTokenDiagnosticsDTO(" + [
            "tokenRequestSeen: \(tokenRequestSeen)",
            "tokenStatus: \(tokenStatus.map(String.init) ?? "none")",
            "tokenErrcode: \(tokenErrcode ?? "none")",
            "tokenReason: \(tokenReason)",
            "eligibilityAllowed: \(eligibilityAllowed)",
            "rateLimited: \(rateLimited)",
            "allocationAttempted: \(allocationAttempted)",
            "liveKitRoomPrecreateAttempted: \(liveKitRoomPrecreateAttempted)",
            "tokenIssued: \(tokenIssued)"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }

    private enum CodingKeys: String, CodingKey {
        case tokenRequestSeen = "token_request_seen"
        case tokenStatus = "token_status"
        case tokenErrcode = "token_errcode"
        case tokenReason = "token_reason"
        case eligibilityAllowed = "eligibility_allowed"
        case rateLimited = "rate_limited"
        case allocationAttempted = "allocation_attempted"
        case liveKitRoomPrecreateAttempted = "livekit_room_precreate_attempted"
        case tokenIssued = "token_issued"
    }
}

struct DirectCallProductionLiveKitTokenErrorDTO: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let errcode: String
    let error: String
    let retryAfterMS: Int?
    let diagnostics: DirectCallProductionLiveKitTokenDiagnosticsDTO?

    var description: String {
        "DirectCallProductionLiveKitTokenErrorDTO(errcode: \(errcode), error: <redacted>, retryAfterMS: \(String(describing: retryAfterMS)), diagnostics: \(diagnostics.map { String(describing: $0) } ?? "none"))"
    }

    var debugDescription: String {
        description
    }

    private enum CodingKeys: String, CodingKey {
        case errcode
        case error
        case retryAfterMS = "retry_after_ms"
        case diagnostics
    }
}

struct DirectCallHTTPTransportRequest: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data
    let timeoutInterval: TimeInterval?

    static func getJSON(from url: URL, bearerAccessToken: String) -> Self {
        .init(url: url,
              method: "GET",
              headers: [
                  "Accept": "application/json",
                  "Authorization": "Bearer \(bearerAccessToken)"
              ],
              body: Data(),
              timeoutInterval: nil)
    }

    static func postJSON(to url: URL,
                         bearerAccessToken: String,
                         body: Data,
                         timeoutInterval: TimeInterval? = nil) -> Self {
        .init(url: url,
              method: "POST",
              headers: [
                  "Accept": "application/json",
                  "Authorization": "Bearer \(bearerAccessToken)",
                  "Content-Type": "application/json"
              ],
              body: body,
              timeoutInterval: timeoutInterval)
    }

    var description: String {
        "DirectCallHTTPTransportRequest(url: <redacted>, method: \(method), headers: <redacted>, bodyByteCount: \(body.count))"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallHTTPTransportResponse: Equatable {
    let statusCode: Int
    let data: Data
}

@MainActor
protocol DirectCallHTTPTransportProtocol {
    func send(_ request: DirectCallHTTPTransportRequest) async -> Result<DirectCallHTTPTransportResponse, DirectCallMediaError>
}

@MainActor
final class URLSessionDirectCallHTTPTransport: DirectCallHTTPTransportProtocol, CustomStringConvertible, CustomDebugStringConvertible {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func send(_ request: DirectCallHTTPTransportRequest) async -> Result<DirectCallHTTPTransportResponse, DirectCallMediaError> {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        if let timeoutInterval = request.timeoutInterval {
            urlRequest.timeoutInterval = timeoutInterval
        }

        for (header, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }

        do {
            let (data, response) = try await urlSession.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.tokenUnavailable)
            }

            return .success(.init(statusCode: httpResponse.statusCode, data: data))
        } catch {
            return .failure(.tokenUnavailable)
        }
    }

    nonisolated var description: String {
        "URLSessionDirectCallHTTPTransport(urlSession: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

@MainActor
protocol DirectCallMatrixAccessTokenProviding {
    func matrixAccessToken() async -> String?
    func refreshedMatrixAccessToken() async -> String?
}

extension DirectCallMatrixAccessTokenProviding {
    func refreshedMatrixAccessToken() async -> String? {
        await matrixAccessToken()
    }
}

struct DirectCallProductionConfiguration: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    static let tokenEndpointPath = "/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"
    static let eligibilityEndpointPath = "/_matrix/client/unstable/kz.salemx.direct_call/eligibility"

    let isEnabled: Bool
    let tokenEndpointBaseURL: URL?

    init(isEnabled: Bool = false, tokenEndpointBaseURL: URL? = nil) {
        self.isEnabled = isEnabled
        self.tokenEndpointBaseURL = tokenEndpointBaseURL
    }

    var tokenEndpointURL: URL? {
        guard isEnabled,
              let tokenEndpointBaseURL else {
            return nil
        }

        return Self.makeTokenEndpointURL(from: tokenEndpointBaseURL)
    }

    var liveKitConfiguration: DirectCallProductionLiveKitConfiguration {
        .init(tokenEndpointURL: tokenEndpointURL)
    }

    var eligibilityEndpointURL: URL? {
        guard isEnabled,
              let tokenEndpointBaseURL else {
            return nil
        }

        return Self.makeEndpointURL(from: tokenEndpointBaseURL, endpointPath: Self.eligibilityEndpointPath)
    }

    var isConfigured: Bool {
        tokenEndpointURL != nil
    }

    var description: String {
        "DirectCallProductionConfiguration(isEnabled: \(isEnabled), tokenEndpointBaseURL: <redacted>, tokenEndpointPath: \(Self.tokenEndpointPath), eligibilityEndpointPath: \(Self.eligibilityEndpointPath), isConfigured: \(isConfigured))"
    }

    var debugDescription: String {
        description
    }

    private static func makeTokenEndpointURL(from baseURL: URL) -> URL? {
        makeEndpointURL(from: baseURL, endpointPath: tokenEndpointPath)
    }

    private static func makeEndpointURL(from baseURL: URL, endpointPath: String) -> URL? {
        guard let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host?.isEmpty == false,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, endpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
            .filter { !$0.isEmpty }
            .joined(separator: "/"))
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

@MainActor
protocol DirectCallProductionRolloutProviding {
    func directCallProductionConfiguration() -> DirectCallProductionConfiguration
}

@MainActor
final class FailClosedDirectCallProductionRolloutProvider: DirectCallProductionRolloutProviding, CustomStringConvertible, CustomDebugStringConvertible {
    func directCallProductionConfiguration() -> DirectCallProductionConfiguration {
        .init()
    }

    nonisolated var description: String {
        "FailClosedDirectCallProductionRolloutProvider(isEnabled: false)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

@MainActor
final class StaticDirectCallProductionRolloutProvider: DirectCallProductionRolloutProviding, CustomStringConvertible, CustomDebugStringConvertible {
    private let configuration: DirectCallProductionConfiguration

    init(configuration: DirectCallProductionConfiguration) {
        self.configuration = configuration
    }

    func directCallProductionConfiguration() -> DirectCallProductionConfiguration {
        configuration
    }

    nonisolated var description: String {
        "StaticDirectCallProductionRolloutProvider(redacted: true)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

struct DirectCallProductionServerCapability: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    static let capabilityName = "kz.salemx.direct_call.native"
    static let supportedVersion = 1
    static let liveKitMediaTransport = "livekit"
    static let matrixSDKKeyEnvelope = "matrix_sdk_direct_call_media_key_envelope_v1"

    let isEnabled: Bool
    let version: Int
    let tokenEndpointPath: String?
    let intents: Set<String>
    let mediaTransport: String
    let isE2EERequired: Bool
    let keyEnvelope: String

    init(isEnabled: Bool = false,
         version: Int = Self.supportedVersion,
         tokenEndpointPath: String? = DirectCallProductionConfiguration.tokenEndpointPath,
         intents: Set<String> = [],
         mediaTransport: String = Self.liveKitMediaTransport,
         isE2EERequired: Bool = true,
         keyEnvelope: String = Self.matrixSDKKeyEnvelope) {
        self.isEnabled = isEnabled
        self.version = version
        self.tokenEndpointPath = tokenEndpointPath
        self.intents = intents
        self.mediaTransport = mediaTransport
        self.isE2EERequired = isE2EERequired
        self.keyEnvelope = keyEnvelope
    }

    func supportsIntent(_ intent: DirectCallIntent) -> Bool {
        intents.contains(intent.rawValue)
    }

    func tokenEndpointURL(homeserverBaseURL: URL?) -> URL? {
        guard let homeserverBaseURL,
              let endpointPath = normalizedTokenEndpointPath else {
            return nil
        }

        return Self.sameOriginURL(baseURL: homeserverBaseURL, path: endpointPath)
    }

    var description: String {
        "DirectCallProductionServerCapability(" + [
            "isEnabled: \(isEnabled)",
            "version: \(version)",
            "tokenEndpointPath: <redacted>",
            "intents: \(intents.sorted())",
            "mediaTransport: \(mediaTransport)",
            "isE2EERequired: \(isE2EERequired)",
            "keyEnvelope: \(keyEnvelope)"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled = "enabled"
        case version
        case tokenEndpointPath = "token_endpoint"
        case intents
        case mediaTransport = "media_transport"
        case isE2EERequired = "e2ee_required"
        case keyEnvelope = "key_envelope"
    }

    private var normalizedTokenEndpointPath: String? {
        let endpointPath = tokenEndpointPath ?? DirectCallProductionConfiguration.tokenEndpointPath
        guard endpointPath.hasPrefix("/"),
              !endpointPath.hasPrefix("//"),
              let components = URLComponents(string: endpointPath),
              components.scheme == nil,
              components.host == nil,
              components.query == nil,
              components.fragment == nil,
              !components.path.isEmpty else {
            return nil
        }

        return components.path
    }

    private static func sameOriginURL(baseURL: URL, path: String) -> URL? {
        guard let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host?.isEmpty == false,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

enum DirectCallProductionCapabilityDiscoveryFailureReason: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case providerUnavailable
    case missingCapability
    case malformedCapability

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallProductionCapabilityDiscoveryResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let capability: DirectCallProductionServerCapability?
    let failureReason: DirectCallProductionCapabilityDiscoveryFailureReason?

    static func available(_ capability: DirectCallProductionServerCapability) -> Self {
        .init(capability: capability, failureReason: nil)
    }

    static func unavailable(_ reason: DirectCallProductionCapabilityDiscoveryFailureReason) -> Self {
        .init(capability: nil, failureReason: reason)
    }

    var isAvailable: Bool {
        capability != nil
    }

    var description: String {
        "DirectCallProductionCapabilityDiscoveryResult(isAvailable: \(isAvailable), failureReason: \(failureReason?.description ?? "none"), capability: \(capability.map { String(describing: $0) } ?? "none"))"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol DirectCallProductionCapabilityProviding {
    func directCallProductionServerCapability() async -> DirectCallProductionCapabilityDiscoveryResult
}

@MainActor
final class FailClosedDirectCallProductionCapabilityProvider: DirectCallProductionCapabilityProviding, CustomStringConvertible, CustomDebugStringConvertible {
    func directCallProductionServerCapability() async -> DirectCallProductionCapabilityDiscoveryResult {
        .unavailable(.providerUnavailable)
    }

    nonisolated var description: String {
        "FailClosedDirectCallProductionCapabilityProvider(isAvailable: false)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

@MainActor
final class HTTPDirectCallProductionCapabilityProvider: DirectCallProductionCapabilityProviding, CustomStringConvertible, CustomDebugStringConvertible {
    static let capabilitiesPath = "/_matrix/client/v3/capabilities"

    private let homeserverBaseURL: URL?
    private let httpTransport: DirectCallHTTPTransportProtocol?
    private let accessTokenProvider: DirectCallMatrixAccessTokenProviding?
    private let payloadDecoder: DirectCallProductionCapabilityPayloadDecoder

    init(homeserverBaseURL: URL? = nil,
         httpTransport: DirectCallHTTPTransportProtocol? = nil,
         accessTokenProvider: DirectCallMatrixAccessTokenProviding? = nil,
         payloadDecoder: DirectCallProductionCapabilityPayloadDecoder = .init()) {
        self.homeserverBaseURL = homeserverBaseURL
        self.httpTransport = httpTransport
        self.accessTokenProvider = accessTokenProvider
        self.payloadDecoder = payloadDecoder
    }

    func directCallProductionServerCapability() async -> DirectCallProductionCapabilityDiscoveryResult {
        guard let capabilitiesURL = Self.capabilitiesURL(from: homeserverBaseURL),
              let httpTransport,
              let accessTokenProvider,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              !accessToken.isEmpty else {
            return .unavailable(.providerUnavailable)
        }

        let request = DirectCallHTTPTransportRequest.getJSON(from: capabilitiesURL,
                                                             bearerAccessToken: accessToken)
        switch await httpTransport.send(request) {
        case .success(let response):
            guard (200..<300).contains(response.statusCode) else {
                return .unavailable(.providerUnavailable)
            }

            return payloadDecoder.decodeCapability(from: response.data)
        case .failure:
            return .unavailable(.providerUnavailable)
        }
    }

    nonisolated var description: String {
        "HTTPDirectCallProductionCapabilityProvider(redacted: true)"
    }

    nonisolated var debugDescription: String {
        description
    }

    private static func capabilitiesURL(from baseURL: URL?) -> URL? {
        guard let baseURL,
              let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host?.isEmpty == false,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.path = capabilitiesPath
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

struct DirectCallProductionCapabilityPayloadDecoder: CustomStringConvertible, CustomDebugStringConvertible {
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    func decodeCapability(from data: Data) -> DirectCallProductionCapabilityDiscoveryResult {
        if let response = try? decoder.decode(DirectCallProductionCapabilitiesResponse.self, from: data),
           response.hasCapabilitiesContainer {
            guard let capability = response.nativeDirectCallCapability else {
                return .unavailable(.missingCapability)
            }

            return .available(capability)
        }

        if let capability = try? decoder.decode(DirectCallProductionServerCapability.self, from: data) {
            return .available(capability)
        }

        return .unavailable(.malformedCapability)
    }

    var description: String {
        "DirectCallProductionCapabilityPayloadDecoder()"
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallInternalPilotUnavailableReason: String, Codable, CaseIterable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case accountNotEligible
    case peerNotEligible
    case roomNotEligible
    case trustNotReady
    case serviceUnavailable
    case capabilityMissing
    case unsupportedClient
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallInternalPilotEligibility: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case eligible
    case unavailable(reason: NativeDirectCallInternalPilotUnavailableReason)
    case disabled
    case unsupported
    case failClosed

    var isEligible: Bool {
        self == .eligible
    }

    var isCapabilityPresentForActivationDryRun: Bool {
        switch self {
        case .eligible,
             .unavailable(reason: .accountNotEligible),
             .unavailable(reason: .peerNotEligible),
             .unavailable(reason: .roomNotEligible),
             .unavailable(reason: .trustNotReady),
             .unavailable(reason: .serviceUnavailable),
             .unavailable(reason: .unsupportedClient),
             .unavailable(reason: .unknown),
             .unsupported:
            return true
        case .unavailable(reason: .capabilityMissing),
             .disabled,
             .failClosed:
            return false
        }
    }

    var description: String {
        switch self {
        case .eligible:
            "eligible"
        case .unavailable(let reason):
            "unavailable(\(reason))"
        case .disabled:
            "disabled"
        case .unsupported:
            "unsupported"
        case .failClosed:
            "failClosed"
        }
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallInternalPilotRolloutConfiguration: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    var description: String {
        "NativeDirectCallInternalPilotRolloutConfiguration(isEnabled: \(isEnabled))"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol NativeDirectCallInternalPilotRolloutProviding {
    func nativeDirectCallInternalPilotRolloutConfiguration() -> NativeDirectCallInternalPilotRolloutConfiguration
}

@MainActor
final class FailClosedNativeDirectCallInternalPilotRolloutProvider: NativeDirectCallInternalPilotRolloutProviding, CustomStringConvertible, CustomDebugStringConvertible {
    func nativeDirectCallInternalPilotRolloutConfiguration() -> NativeDirectCallInternalPilotRolloutConfiguration {
        .init()
    }

    nonisolated var description: String {
        "FailClosedNativeDirectCallInternalPilotRolloutProvider(isEnabled: false)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

@MainActor
struct StaticNativeDirectCallInternalPilotRolloutProvider: NativeDirectCallInternalPilotRolloutProviding, CustomStringConvertible, CustomDebugStringConvertible {
    let configuration: NativeDirectCallInternalPilotRolloutConfiguration

    init(configuration: NativeDirectCallInternalPilotRolloutConfiguration = .init()) {
        self.configuration = configuration
    }

    func nativeDirectCallInternalPilotRolloutConfiguration() -> NativeDirectCallInternalPilotRolloutConfiguration {
        configuration
    }

    nonisolated var description: String {
        "StaticNativeDirectCallInternalPilotRolloutProvider(isEnabled: \(configuration.isEnabled))"
    }

    nonisolated var debugDescription: String {
        description
    }
}

#if DEBUG
@MainActor
struct EnvironmentNativeDirectCallInternalPilotRolloutProvider: NativeDirectCallInternalPilotRolloutProviding, CustomStringConvertible, CustomDebugStringConvertible {
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func nativeDirectCallInternalPilotRolloutConfiguration() -> NativeDirectCallInternalPilotRolloutConfiguration {
        .init(isEnabled: ProcessInfo.isNativeDirectCallInternalPilotRolloutEnabled(environment: environment))
    }

    nonisolated var description: String {
        "EnvironmentNativeDirectCallInternalPilotRolloutProvider(redacted: true)"
    }

    nonisolated var debugDescription: String {
        description
    }
}
#endif

enum NativeDirectCallInternalPilotActivationUnavailableReason: String, CaseIterable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case rolloutDisabled
    case capabilityMissing
    case accountNotEligible
    case peerNotEligible
    case roomNotEligible
    case trustNotReady
    case serviceUnavailable
    case unsupportedClient
    case dependenciesUnavailable
    case unknown

    init(eligibilityReason: NativeDirectCallInternalPilotUnavailableReason) {
        switch eligibilityReason {
        case .accountNotEligible:
            self = .accountNotEligible
        case .peerNotEligible:
            self = .peerNotEligible
        case .roomNotEligible:
            self = .roomNotEligible
        case .trustNotReady:
            self = .trustNotReady
        case .serviceUnavailable:
            self = .serviceUnavailable
        case .capabilityMissing:
            self = .capabilityMissing
        case .unsupportedClient:
            self = .unsupportedClient
        case .unknown:
            self = .unknown
        }
    }

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallInternalPilotActivation: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case disabled
    case unavailable(reason: NativeDirectCallInternalPilotActivationUnavailableReason)
    case eligibleForStatusOnly
    case activationAllowed

    var allowsActivation: Bool {
        self == .activationAllowed
    }

    var description: String {
        switch self {
        case .disabled:
            "disabled"
        case .unavailable(let reason):
            "unavailable(\(reason))"
        case .eligibleForStatusOnly:
            "eligibleForStatusOnly"
        case .activationAllowed:
            "activationAllowed"
        }
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallInternalPilotActivationContext: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let isProductUIEnabled: Bool
    let isInternalPilotRolloutEnabled: Bool
    let isCapabilityPresent: Bool
    let eligibility: NativeDirectCallInternalPilotEligibility
    let roomEligibility: DirectCallProductionRoomEligibility
    let peerTrustReadiness: DirectCallPeerTrustReadiness
    let areDependenciesReady: Bool
    let hasActiveSession: Bool

    init(isProductUIEnabled: Bool = false,
         isInternalPilotRolloutEnabled: Bool = false,
         isCapabilityPresent: Bool = false,
         eligibility: NativeDirectCallInternalPilotEligibility = .disabled,
         roomEligibility: DirectCallProductionRoomEligibility = .init(),
         peerTrustReadiness: DirectCallPeerTrustReadiness = .peerTrustUnavailable,
         areDependenciesReady: Bool = false,
         hasActiveSession: Bool = false) {
        self.isProductUIEnabled = isProductUIEnabled
        self.isInternalPilotRolloutEnabled = isInternalPilotRolloutEnabled
        self.isCapabilityPresent = isCapabilityPresent
        self.eligibility = eligibility
        self.roomEligibility = roomEligibility
        self.peerTrustReadiness = peerTrustReadiness
        self.areDependenciesReady = areDependenciesReady
        self.hasActiveSession = hasActiveSession
    }

    var description: String {
        "NativeDirectCallInternalPilotActivationContext(" + [
            "isProductUIEnabled: \(isProductUIEnabled)",
            "isInternalPilotRolloutEnabled: \(isInternalPilotRolloutEnabled)",
            "isCapabilityPresent: \(isCapabilityPresent)",
            "eligibility: \(eligibility)",
            "roomEligibility: \(roomEligibility)",
            "peerTrustReadiness: \(peerTrustReadiness)",
            "areDependenciesReady: \(areDependenciesReady)",
            "hasActiveSession: \(hasActiveSession)"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol NativeDirectCallInternalPilotActivationProviding {
    func nativeDirectCallInternalPilotActivation(for context: NativeDirectCallInternalPilotActivationContext) async -> NativeDirectCallInternalPilotActivation
}

private enum NativeDirectCallInternalPilotActivationEvaluator {
    static func evaluate(_ context: NativeDirectCallInternalPilotActivationContext,
                         allowsActivationWhenEligible: Bool) -> NativeDirectCallInternalPilotActivation {
        guard context.isInternalPilotRolloutEnabled else {
            return .disabled
        }

        guard context.isProductUIEnabled else {
            return .unavailable(reason: .rolloutDisabled)
        }

        guard context.isCapabilityPresent else {
            return .unavailable(reason: .capabilityMissing)
        }

        if let reason = roomUnavailableReason(context.roomEligibility) {
            return .unavailable(reason: reason)
        }

        if context.peerTrustReadiness != .peerTrustReady {
            return .unavailable(reason: .trustNotReady)
        }

        guard context.areDependenciesReady, !context.hasActiveSession else {
            return .unavailable(reason: .dependenciesUnavailable)
        }

        switch context.eligibility {
        case .eligible:
            return allowsActivationWhenEligible ? .activationAllowed : .eligibleForStatusOnly
        case .unavailable(let reason):
            return .unavailable(reason: .init(eligibilityReason: reason))
        case .unsupported:
            return .unavailable(reason: .unsupportedClient)
        case .disabled, .failClosed:
            return .disabled
        }
    }

    private static func roomUnavailableReason(_ roomEligibility: DirectCallProductionRoomEligibility) -> NativeDirectCallInternalPilotActivationUnavailableReason? {
        guard roomEligibility.isEncrypted,
              roomEligibility.isDirect,
              roomEligibility.hasExactlyTwoJoinedMembers,
              roomEligibility.hasPeerUserID else {
            return .roomNotEligible
        }

        return nil
    }
}

@MainActor
final class FailClosedNativeDirectCallInternalPilotActivationProvider: NativeDirectCallInternalPilotActivationProviding, CustomStringConvertible, CustomDebugStringConvertible {
    func nativeDirectCallInternalPilotActivation(for context: NativeDirectCallInternalPilotActivationContext) async -> NativeDirectCallInternalPilotActivation {
        .disabled
    }

    nonisolated var description: String {
        "FailClosedNativeDirectCallInternalPilotActivationProvider(allowsActivation: false)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

@MainActor
struct StatusOnlyNativeDirectCallInternalPilotActivationProvider: NativeDirectCallInternalPilotActivationProviding, CustomStringConvertible, CustomDebugStringConvertible {
    func nativeDirectCallInternalPilotActivation(for context: NativeDirectCallInternalPilotActivationContext) async -> NativeDirectCallInternalPilotActivation {
        NativeDirectCallInternalPilotActivationEvaluator.evaluate(context, allowsActivationWhenEligible: false)
    }

    nonisolated var description: String {
        "StatusOnlyNativeDirectCallInternalPilotActivationProvider(allowsActivation: false)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

@MainActor
struct ServerBackedNativeDirectCallInternalPilotActivationProvider: NativeDirectCallInternalPilotActivationProviding, CustomStringConvertible, CustomDebugStringConvertible {
    func nativeDirectCallInternalPilotActivation(for context: NativeDirectCallInternalPilotActivationContext) async -> NativeDirectCallInternalPilotActivation {
        NativeDirectCallInternalPilotActivationEvaluator.evaluate(context, allowsActivationWhenEligible: true)
    }

    nonisolated var description: String {
        "ServerBackedNativeDirectCallInternalPilotActivationProvider(allowsActivationWhenEligible: true)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

struct NativeDirectCallInternalPilotEligibilityPayload: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let state: State
    let reason: NativeDirectCallInternalPilotUnavailableReason?
    let accountEligible: Bool?
    let peerEligible: Bool?
    let roomEligible: Bool?
    let trustReady: Bool?
    let serviceAvailable: Bool?
    let capabilityPresent: Bool?
    let clientSupported: Bool?

    init(state: State,
         reason: NativeDirectCallInternalPilotUnavailableReason? = nil,
         accountEligible: Bool? = nil,
         peerEligible: Bool? = nil,
         roomEligible: Bool? = nil,
         trustReady: Bool? = nil,
         serviceAvailable: Bool? = nil,
         capabilityPresent: Bool? = nil,
         clientSupported: Bool? = nil) {
        self.state = state
        self.reason = reason
        self.accountEligible = accountEligible
        self.peerEligible = peerEligible
        self.roomEligible = roomEligible
        self.trustReady = trustReady
        self.serviceAvailable = serviceAvailable
        self.capabilityPresent = capabilityPresent
        self.clientSupported = clientSupported
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(State.self, forKey: .state)
        reason = try container.decodeIfPresent(NativeDirectCallInternalPilotUnavailableReason.self, forKey: .reason)
        accountEligible = try container.decodeIfPresent(Bool.self, forKey: .accountEligible)
        peerEligible = try container.decodeIfPresent(Bool.self, forKey: .peerEligible)
        roomEligible = try container.decodeIfPresent(Bool.self, forKey: .roomEligible)
        trustReady = try container.decodeIfPresent(Bool.self, forKey: .trustReady)
        serviceAvailable = try container.decodeIfPresent(Bool.self, forKey: .serviceAvailable)
        capabilityPresent = try container.decodeIfPresent(Bool.self, forKey: .capabilityPresent) ?? container.decodeIfPresent(Bool.self, forKey: .capabilityPresentCamel)
        clientSupported = try container.decodeIfPresent(Bool.self, forKey: .clientSupported)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(accountEligible, forKey: .accountEligible)
        try container.encodeIfPresent(peerEligible, forKey: .peerEligible)
        try container.encodeIfPresent(roomEligible, forKey: .roomEligible)
        try container.encodeIfPresent(trustReady, forKey: .trustReady)
        try container.encodeIfPresent(serviceAvailable, forKey: .serviceAvailable)
        try container.encodeIfPresent(capabilityPresent, forKey: .capabilityPresent)
        try container.encodeIfPresent(clientSupported, forKey: .clientSupported)
    }

    var eligibility: NativeDirectCallInternalPilotEligibility {
        switch state {
        case .eligible:
            .eligible
        case .unavailable:
            .unavailable(reason: reason ?? .unknown)
        case .disabled:
            .disabled
        case .unsupported:
            .unsupported
        case .failClosed:
            .failClosed
        }
    }

    var description: String {
        "NativeDirectCallInternalPilotEligibilityPayload(" + [
            "state: \(state)",
            "reason: \(reason?.description ?? "none")",
            "accountEligible: \(redactedBoolean(accountEligible))",
            "peerEligible: \(redactedBoolean(peerEligible))",
            "roomEligible: \(redactedBoolean(roomEligible))",
            "trustReady: \(redactedBoolean(trustReady))",
            "serviceAvailable: \(redactedBoolean(serviceAvailable))",
            "capabilityPresent: \(redactedBoolean(capabilityPresent))",
            "clientSupported: \(redactedBoolean(clientSupported))"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }

    private func redactedBoolean(_ value: Bool?) -> String {
        value.map { String($0) } ?? "unknown"
    }

    enum State: String, Codable, CaseIterable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
        case eligible
        case unavailable
        case disabled
        case unsupported
        case failClosed

        var description: String {
            rawValue
        }

        var debugDescription: String {
            description
        }
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case reason
        case accountEligible = "account_eligible"
        case peerEligible = "peer_eligible"
        case roomEligible = "room_eligible"
        case trustReady = "trust_ready"
        case serviceAvailable = "service_available"
        case capabilityPresent = "capability_present"
        case capabilityPresentCamel = "capabilityPresent"
        case clientSupported = "client_supported"
    }
}

struct NativeDirectCallInternalPilotEligibilityRequest: Encodable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let version: Int
    let roomID: String
    let peerUserID: String
    let deviceID: String?
    let intent: DirectCallIntent

    init(version: Int = 1,
         roomID: String,
         peerUserID: String,
         deviceID: String? = nil,
         intent: DirectCallIntent = .audio) {
        self.version = version
        self.roomID = roomID
        self.peerUserID = peerUserID
        self.deviceID = deviceID
        self.intent = intent
    }

    var description: String {
        "NativeDirectCallInternalPilotEligibilityRequest(version: \(version), roomID: <redacted>, peerUserID: <redacted>, deviceID: <redacted>, intent: \(intent.rawValue))"
    }

    var debugDescription: String {
        description
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(roomID, forKey: .roomID)
        try container.encode(peerUserID, forKey: .peerUserID)
        try container.encodeIfPresent(deviceID, forKey: .deviceID)
        try container.encode(intent.rawValue, forKey: .intent)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case roomID = "room_id"
        case peerUserID = "peer_user_id"
        case deviceID = "device_id"
        case intent
    }
}

struct NativeDirectCallEligibilityStatusCacheKey: Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    private let roomID: String
    private let peerUserID: String
    private let deviceID: String?
    private let intent: String

    init(request: NativeDirectCallInternalPilotEligibilityRequest) {
        roomID = request.roomID
        peerUserID = request.peerUserID
        deviceID = request.deviceID
        intent = request.intent.rawValue
    }

    var description: String {
        "NativeDirectCallEligibilityStatusCacheKey(roomID: <redacted>, peerUserID: <redacted>, deviceID: <redacted>, intent: \(intent))"
    }

    var debugDescription: String {
        description
    }
}

final class NativeDirectCallEligibilityStatusCache {
    private struct Entry {
        let eligibility: NativeDirectCallInternalPilotEligibility
        let expiresAt: Date
    }

    private let positiveTTL: TimeInterval
    private let negativeTTL: TimeInterval
    private let now: () -> Date
    private var entries = [NativeDirectCallEligibilityStatusCacheKey: Entry]()

    init(positiveTTL: TimeInterval = 60,
         negativeTTL: TimeInterval = 20,
         now: @escaping () -> Date = Date.init) {
        self.positiveTTL = positiveTTL
        self.negativeTTL = negativeTTL
        self.now = now
    }

    func eligibility(for request: NativeDirectCallInternalPilotEligibilityRequest) -> NativeDirectCallInternalPilotEligibility? {
        let key = NativeDirectCallEligibilityStatusCacheKey(request: request)
        guard let entry = entries[key] else {
            return nil
        }

        guard entry.expiresAt > now() else {
            entries[key] = nil
            return nil
        }

        return entry.eligibility
    }

    func store(_ eligibility: NativeDirectCallInternalPilotEligibility,
               for request: NativeDirectCallInternalPilotEligibilityRequest) {
        let ttl = eligibility.isEligible ? positiveTTL : negativeTTL
        let key = NativeDirectCallEligibilityStatusCacheKey(request: request)
        entries[key] = Entry(eligibility: eligibility, expiresAt: now().addingTimeInterval(ttl))
    }

    func invalidate(for request: NativeDirectCallInternalPilotEligibilityRequest) {
        entries[NativeDirectCallEligibilityStatusCacheKey(request: request)] = nil
    }

    func removeAll() {
        entries.removeAll()
    }
}

struct NativeDirectCallInternalPilotEligibilityPayloadDecoder: CustomStringConvertible, CustomDebugStringConvertible {
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    func decodeEligibility(from data: Data) -> NativeDirectCallInternalPilotEligibility {
        guard let payload = try? decoder.decode(NativeDirectCallInternalPilotEligibilityPayload.self, from: data) else {
            return .failClosed
        }

        return payload.eligibility
    }

    var description: String {
        "NativeDirectCallInternalPilotEligibilityPayloadDecoder(redacted: true)"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol NativeDirectCallInternalPilotEligibilityProviding {
    func nativeDirectCallInternalPilotEligibility(for request: NativeDirectCallInternalPilotEligibilityRequest) async -> NativeDirectCallInternalPilotEligibility
}

@MainActor
final class FailClosedNativeDirectCallInternalPilotEligibilityProvider: NativeDirectCallInternalPilotEligibilityProviding, CustomStringConvertible, CustomDebugStringConvertible {
    func nativeDirectCallInternalPilotEligibility(for request: NativeDirectCallInternalPilotEligibilityRequest) async -> NativeDirectCallInternalPilotEligibility {
        .disabled
    }

    nonisolated var description: String {
        "FailClosedNativeDirectCallInternalPilotEligibilityProvider(isEligible: false)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

@MainActor
final class HTTPNativeDirectCallInternalPilotEligibilityProvider: NativeDirectCallInternalPilotEligibilityProviding, CustomStringConvertible, CustomDebugStringConvertible {
    private let endpointURL: URL?
    private let httpTransport: DirectCallHTTPTransportProtocol?
    private let accessTokenProvider: DirectCallMatrixAccessTokenProviding?
    private let jsonEncoder: JSONEncoder
    private let payloadDecoder: NativeDirectCallInternalPilotEligibilityPayloadDecoder

    init(endpointURL: URL? = nil,
         httpTransport: DirectCallHTTPTransportProtocol? = nil,
         accessTokenProvider: DirectCallMatrixAccessTokenProviding? = nil,
         jsonEncoder: JSONEncoder = JSONEncoder(),
         payloadDecoder: NativeDirectCallInternalPilotEligibilityPayloadDecoder = .init()) {
        self.endpointURL = endpointURL
        self.httpTransport = httpTransport
        self.accessTokenProvider = accessTokenProvider
        self.jsonEncoder = jsonEncoder
        self.payloadDecoder = payloadDecoder
    }

    convenience init(endpointBaseURL: URL?,
                     httpTransport: DirectCallHTTPTransportProtocol? = nil,
                     accessTokenProvider: DirectCallMatrixAccessTokenProviding? = nil,
                     jsonEncoder: JSONEncoder = JSONEncoder(),
                     payloadDecoder: NativeDirectCallInternalPilotEligibilityPayloadDecoder = .init()) {
        self.init(endpointURL: DirectCallProductionConfiguration(isEnabled: true, tokenEndpointBaseURL: endpointBaseURL).eligibilityEndpointURL,
                  httpTransport: httpTransport,
                  accessTokenProvider: accessTokenProvider,
                  jsonEncoder: jsonEncoder,
                  payloadDecoder: payloadDecoder)
    }

    func nativeDirectCallInternalPilotEligibility(for request: NativeDirectCallInternalPilotEligibilityRequest) async -> NativeDirectCallInternalPilotEligibility {
        guard request.intent == .audio else {
            return .unsupported
        }

        guard let endpointURL,
              let httpTransport,
              let accessTokenProvider,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              !accessToken.isEmpty else {
            return .failClosed
        }

        let requestData: Data
        do {
            requestData = try jsonEncoder.encode(request)
        } catch {
            return .failClosed
        }

        let transportRequest = DirectCallHTTPTransportRequest.postJSON(to: endpointURL,
                                                                       bearerAccessToken: accessToken,
                                                                       body: requestData)
        switch await httpTransport.send(transportRequest) {
        case .success(let response):
            return decode(response)
        case .failure:
            return .unavailable(reason: .serviceUnavailable)
        }
    }

    nonisolated var description: String {
        "HTTPNativeDirectCallInternalPilotEligibilityProvider(endpointURL: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }

    private func decode(_ response: DirectCallHTTPTransportResponse) -> NativeDirectCallInternalPilotEligibility {
        guard (200..<300).contains(response.statusCode) else {
            return failureEligibility(for: response.statusCode)
        }

        return payloadDecoder.decodeEligibility(from: response.data)
    }

    private func failureEligibility(for statusCode: Int) -> NativeDirectCallInternalPilotEligibility {
        switch statusCode {
        case 404:
            .unavailable(reason: .capabilityMissing)
        case 401, 403, 500...599:
            .unavailable(reason: .serviceUnavailable)
        default:
            .failClosed
        }
    }
}

private struct DirectCallProductionCapabilitiesResponse: Decodable {
    let nativeDirectCallCapability: DirectCallProductionServerCapability?
    let hasCapabilitiesContainer: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCapabilitiesContainer = container.contains(.capabilities)

        guard hasCapabilitiesContainer else {
            nativeDirectCallCapability = nil
            return
        }

        let capabilities = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .capabilities)
        guard let nativeCapabilityKey = DynamicCodingKey(stringValue: DirectCallProductionServerCapability.capabilityName),
              capabilities.contains(nativeCapabilityKey) else {
            nativeDirectCallCapability = nil
            return
        }

        nativeDirectCallCapability = try capabilities.decode(DirectCallProductionServerCapability.self, forKey: nativeCapabilityKey)
    }

    private enum CodingKeys: String, CodingKey {
        case capabilities
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

struct DirectCallProductionRoomEligibility: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let isDirect: Bool
    let isEncrypted: Bool
    let joinedMemberCount: Int?
    let hasPeerUserID: Bool

    init(isDirect: Bool = false,
         isEncrypted: Bool = false,
         joinedMemberCount: Int? = nil,
         hasPeerUserID: Bool = false) {
        self.isDirect = isDirect
        self.isEncrypted = isEncrypted
        self.joinedMemberCount = joinedMemberCount
        self.hasPeerUserID = hasPeerUserID
    }

    init(roomProxy: JoinedRoomProxyProtocol) {
        let roomInfo = roomProxy.infoPublisher.value
        let members = roomProxy.membersPublisher.value
        self.init(isDirect: roomInfo.isDirect,
                  isEncrypted: roomInfo.isEncrypted,
                  joinedMemberCount: roomInfo.joinedMembersCount,
                  hasPeerUserID: members.contains { !$0.userID.isEmpty && $0.userID != roomProxy.ownUserID })
    }

    var hasExactlyTwoJoinedMembers: Bool {
        joinedMemberCount == 2
    }

    var description: String {
        "DirectCallProductionRoomEligibility(isDirect: \(isDirect), isEncrypted: \(isEncrypted), hasJoinedMemberCount: \(joinedMemberCount != nil), hasExactlyTwoJoinedMembers: \(hasExactlyTwoJoinedMembers), hasPeerUserID: \(hasPeerUserID))"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallPeerTrustReadiness: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case peerTrustReady
    case peerTrustUnavailable
    case unverifiedDevice
    case noEligibleDevice
    case crossSigningUnavailable
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol DirectCallPeerTrustReadinessProviding {
    func directCallPeerTrustReadiness() async -> DirectCallPeerTrustReadiness
}

@MainActor
struct FailClosedDirectCallPeerTrustReadinessProvider: DirectCallPeerTrustReadinessProviding, CustomStringConvertible, CustomDebugStringConvertible {
    func directCallPeerTrustReadiness() async -> DirectCallPeerTrustReadiness {
        .peerTrustUnavailable
    }

    nonisolated var description: String {
        "FailClosedDirectCallPeerTrustReadinessProvider(status: failClosed)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

@MainActor
struct StaticDirectCallPeerTrustReadinessProvider: DirectCallPeerTrustReadinessProviding {
    let readiness: DirectCallPeerTrustReadiness

    func directCallPeerTrustReadiness() async -> DirectCallPeerTrustReadiness {
        readiness
    }
}

@MainActor
struct UserIdentityDirectCallPeerTrustReadinessProvider: DirectCallPeerTrustReadinessProviding, CustomStringConvertible, CustomDebugStringConvertible {
    private let clientProxy: ClientProxyProtocol?
    private let peerUserID: String?

    init(clientProxy: ClientProxyProtocol?, peerUserID: String?) {
        self.clientProxy = clientProxy
        self.peerUserID = peerUserID
    }

    func directCallPeerTrustReadiness() async -> DirectCallPeerTrustReadiness {
        guard let clientProxy,
              let peerUserID,
              !peerUserID.isEmpty,
              peerUserID != clientProxy.userID else {
            return .peerTrustUnavailable
        }

        switch await clientProxy.userIdentity(for: peerUserID, fallBackToServer: true) {
        case .success(let identity):
            guard let identity else {
                return .crossSigningUnavailable
            }

            switch identity.verificationState {
            case .verified:
                return .peerTrustReady
            case .notVerified, .verificationViolation:
                return .unverifiedDevice
            }
        case .failure:
            return .peerTrustUnavailable
        }
    }

    nonisolated var description: String {
        "UserIdentityDirectCallPeerTrustReadinessProvider(peer: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

struct DirectCallPeerTrustDiagnostic: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let ownUserIdentityAvailable: Bool
    let ownSessionVerified: Bool
    let crossSigningReady: Bool
    let peerIdentityAvailable: Bool
    let peerIdentityVerified: Bool
    let peerTrustReadiness: DirectCallPeerTrustReadiness
    let verificationRequestPending: Bool
    let verificationFlowState: SessionVerificationControllerDiagnosticFlowState
    let lastVerificationErrorReason: SessionVerificationControllerDiagnosticErrorReason

    init(ownUserIdentityAvailable: Bool = false,
         ownSessionVerified: Bool = false,
         crossSigningReady: Bool = false,
         peerIdentityAvailable: Bool = false,
         peerIdentityVerified: Bool = false,
         peerTrustReadiness: DirectCallPeerTrustReadiness = .peerTrustUnavailable,
         verificationSnapshot: SessionVerificationControllerDiagnosticSnapshot = .unavailable) {
        self.ownUserIdentityAvailable = ownUserIdentityAvailable
        self.ownSessionVerified = ownSessionVerified
        self.crossSigningReady = crossSigningReady
        self.peerIdentityAvailable = peerIdentityAvailable
        self.peerIdentityVerified = peerIdentityVerified
        self.peerTrustReadiness = peerTrustReadiness
        verificationRequestPending = verificationSnapshot.verificationRequestPending
        verificationFlowState = verificationSnapshot.verificationFlowState
        lastVerificationErrorReason = verificationSnapshot.lastVerificationErrorReason
    }

    var peerTrustReady: Bool {
        peerTrustReadiness == .peerTrustReady
    }

    static let unavailable = Self()

    var description: String {
        "DirectCallPeerTrustDiagnostic(" + [
            "ownUserIdentityAvailable: \(ownUserIdentityAvailable)",
            "ownSessionVerified: \(ownSessionVerified)",
            "crossSigningReady: \(crossSigningReady)",
            "peerIdentityAvailable: \(peerIdentityAvailable)",
            "peerIdentityVerified: \(peerIdentityVerified)",
            "peerTrustReady: \(peerTrustReady)",
            "peerTrustReadiness: \(peerTrustReadiness)",
            "verificationRequestPending: \(verificationRequestPending)",
            "verificationFlowState: \(verificationFlowState)",
            "lastVerificationErrorReason: \(lastVerificationErrorReason)"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol DirectCallPeerTrustDiagnosing {
    func directCallPeerTrustDiagnostic() async -> DirectCallPeerTrustDiagnostic
}

@MainActor
struct FailClosedDirectCallPeerTrustDiagnosticsProvider: DirectCallPeerTrustDiagnosing, CustomStringConvertible, CustomDebugStringConvertible {
    func directCallPeerTrustDiagnostic() async -> DirectCallPeerTrustDiagnostic {
        .unavailable
    }

    nonisolated var description: String {
        "FailClosedDirectCallPeerTrustDiagnosticsProvider(status: failClosed)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

@MainActor
struct UserIdentityDirectCallPeerTrustDiagnosticsProvider: DirectCallPeerTrustDiagnosing, CustomStringConvertible, CustomDebugStringConvertible {
    private let clientProxy: ClientProxyProtocol?
    private let peerUserID: String?

    init(clientProxy: ClientProxyProtocol?, peerUserID: String?) {
        self.clientProxy = clientProxy
        self.peerUserID = peerUserID
    }

    func directCallPeerTrustDiagnostic() async -> DirectCallPeerTrustDiagnostic {
        let verificationSnapshot = (clientProxy?.sessionVerificationController as? SessionVerificationControllerDiagnosticProviding)?.diagnosticSnapshot ?? .unavailable

        guard let clientProxy else {
            return .init(verificationSnapshot: verificationSnapshot)
        }

        let ownSessionVerified = clientProxy.verificationStatePublisher.value == .verified
        let ownUserIdentityAvailable = await userIdentityAvailable(userID: clientProxy.userID, clientProxy: clientProxy)
        let crossSigningReady = ownUserIdentityAvailable && ownSessionVerified

        guard let peerUserID,
              !peerUserID.isEmpty,
              peerUserID != clientProxy.userID else {
            return .init(ownUserIdentityAvailable: ownUserIdentityAvailable,
                         ownSessionVerified: ownSessionVerified,
                         crossSigningReady: crossSigningReady,
                         verificationSnapshot: verificationSnapshot)
        }

        switch await clientProxy.userIdentity(for: peerUserID, fallBackToServer: true) {
        case .success(let identity):
            guard let identity else {
                return .init(ownUserIdentityAvailable: ownUserIdentityAvailable,
                             ownSessionVerified: ownSessionVerified,
                             crossSigningReady: crossSigningReady,
                             peerTrustReadiness: .crossSigningUnavailable,
                             verificationSnapshot: verificationSnapshot)
            }

            let peerIdentityVerified = identity.verificationState == .verified
            let readiness: DirectCallPeerTrustReadiness = switch identity.verificationState {
            case .verified:
                .peerTrustReady
            case .notVerified, .verificationViolation:
                .unverifiedDevice
            }

            return .init(ownUserIdentityAvailable: ownUserIdentityAvailable,
                         ownSessionVerified: ownSessionVerified,
                         crossSigningReady: crossSigningReady,
                         peerIdentityAvailable: true,
                         peerIdentityVerified: peerIdentityVerified,
                         peerTrustReadiness: readiness,
                         verificationSnapshot: verificationSnapshot)
        case .failure:
            return .init(ownUserIdentityAvailable: ownUserIdentityAvailable,
                         ownSessionVerified: ownSessionVerified,
                         crossSigningReady: crossSigningReady,
                         verificationSnapshot: verificationSnapshot)
        }
    }

    nonisolated var description: String {
        "UserIdentityDirectCallPeerTrustDiagnosticsProvider(peer: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }

    private func userIdentityAvailable(userID: String, clientProxy: ClientProxyProtocol) async -> Bool {
        guard !userID.isEmpty else {
            return false
        }

        return switch await clientProxy.userIdentity(for: userID, fallBackToServer: true) {
        case .success(let identity):
            identity != nil
        case .failure:
            false
        }
    }
}

enum DirectCallProductionActivationDisabledReason: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case appRolloutDisabled
    case roomUnavailable
    case serverCapabilityUnavailable
    case serverCapabilityDisabled
    case unsupportedCapabilityVersion
    case unsupportedIntent
    case unsupportedMediaTransport
    case e2eeNotRequiredByCapability
    case unsupportedKeyEnvelope
    case tokenEndpointUnavailable
    case tokenEndpointNotSameOrigin
    case dependenciesUnavailable
    case roomNotEncrypted
    case roomNotDirect
    case roomNotOneToOne
    case peerUnavailable
    case peerTrustUnavailable
    case unverifiedDevice
    case noEligibleDevice
    case crossSigningUnavailable
    case peerTrustUnknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallProductionActivationContext {
    let appRolloutEnabled: Bool
    let homeserverBaseURL: URL?
    let serverCapability: DirectCallProductionServerCapability?
    let configuredTokenEndpointURL: URL?
    let dependencies: NativeDirectCallProductionDependencies
    let roomEligibility: DirectCallProductionRoomEligibility
    let peerTrustReadiness: DirectCallPeerTrustReadiness

    init(appRolloutEnabled: Bool = false,
         homeserverBaseURL: URL? = nil,
         serverCapability: DirectCallProductionServerCapability? = nil,
         configuredTokenEndpointURL: URL? = nil,
         dependencies: NativeDirectCallProductionDependencies = .disabled,
         roomEligibility: DirectCallProductionRoomEligibility = .init(),
         peerTrustReadiness: DirectCallPeerTrustReadiness = .peerTrustUnavailable) {
        self.appRolloutEnabled = appRolloutEnabled
        self.homeserverBaseURL = homeserverBaseURL
        self.serverCapability = serverCapability
        self.configuredTokenEndpointURL = configuredTokenEndpointURL
        self.dependencies = dependencies
        self.roomEligibility = roomEligibility
        self.peerTrustReadiness = peerTrustReadiness
    }
}

struct DirectCallProductionActivationDecision: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let isEnabled: Bool
    let disabledReason: DirectCallProductionActivationDisabledReason?
    let tokenEndpointURL: URL?

    static func enabled(tokenEndpointURL: URL) -> Self {
        .init(isEnabled: true, disabledReason: nil, tokenEndpointURL: tokenEndpointURL)
    }

    static func disabled(_ reason: DirectCallProductionActivationDisabledReason) -> Self {
        .init(isEnabled: false, disabledReason: reason, tokenEndpointURL: nil)
    }

    var description: String {
        "DirectCallProductionActivationDecision(isEnabled: \(isEnabled), disabledReason: \(disabledReason?.description ?? "none"), tokenEndpointURL: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallProductionActivationDryRunDiagnostic: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let isEnabled: Bool
    let disabledReason: DirectCallProductionActivationDisabledReason?
    let isCapabilityPresent: Bool
    let areDependenciesReady: Bool
    let isRoomEligible: Bool
    let isEndpointAccepted: Bool
    let isPeerTrustReady: Bool
    let peerTrustReadiness: DirectCallPeerTrustReadiness
    let keyWrapperSource: NativeDirectCallProductionKeyWrapperSource?

    init(isEnabled: Bool,
         disabledReason: DirectCallProductionActivationDisabledReason?,
         isCapabilityPresent: Bool,
         areDependenciesReady: Bool,
         isRoomEligible: Bool,
         isEndpointAccepted: Bool,
         peerTrustReadiness: DirectCallPeerTrustReadiness = .peerTrustUnavailable,
         keyWrapperSource: NativeDirectCallProductionKeyWrapperSource? = nil) {
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.isCapabilityPresent = isCapabilityPresent
        self.areDependenciesReady = areDependenciesReady
        self.isRoomEligible = isRoomEligible
        self.isEndpointAccepted = isEndpointAccepted
        isPeerTrustReady = peerTrustReadiness == .peerTrustReady
        self.peerTrustReadiness = peerTrustReadiness
        self.keyWrapperSource = keyWrapperSource
    }

    static func disabled(_ reason: DirectCallProductionActivationDisabledReason) -> Self {
        .init(isEnabled: false,
              disabledReason: reason,
              isCapabilityPresent: false,
              areDependenciesReady: false,
              isRoomEligible: false,
              isEndpointAccepted: false,
              peerTrustReadiness: .peerTrustUnavailable,
              keyWrapperSource: nil)
    }

    var description: String {
        let fields = [
            "isEnabled: \(isEnabled)",
            "disabledReason: \(disabledReason?.description ?? "none")",
            "isCapabilityPresent: \(isCapabilityPresent)",
            "areDependenciesReady: \(areDependenciesReady)",
            "isRoomEligible: \(isRoomEligible)",
            "isEndpointAccepted: \(isEndpointAccepted)",
            "isPeerTrustReady: \(isPeerTrustReady)",
            "peerTrustReadiness: \(peerTrustReadiness)",
            "keyWrapperSource: \(keyWrapperSource?.description ?? "none")"
        ]
        return "DirectCallProductionActivationDryRunDiagnostic(\(fields.joined(separator: ", ")))"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallProductionActivationGate {
    let intent: DirectCallIntent

    init(intent: DirectCallIntent = .audio) {
        self.intent = intent
    }

    func evaluate(_ context: DirectCallProductionActivationContext) -> DirectCallProductionActivationDecision {
        guard context.appRolloutEnabled else {
            return .disabled(.appRolloutDisabled)
        }

        if let disabledReason = serverCapabilityDisabledReason(context.serverCapability) {
            return .disabled(disabledReason)
        }

        if let configuredTokenEndpointURL = context.configuredTokenEndpointURL,
           !isSameOrigin(configuredTokenEndpointURL, as: context.homeserverBaseURL) {
            return .disabled(.tokenEndpointNotSameOrigin)
        }

        guard let serverCapability = context.serverCapability,
              let tokenEndpointURL = tokenEndpointURL(for: context, serverCapability: serverCapability) else {
            return .disabled(.tokenEndpointUnavailable)
        }

        guard context.dependencies.isReadyForProductionStart else {
            return .disabled(.dependenciesUnavailable)
        }

        if let disabledReason = roomEligibilityDisabledReason(context.roomEligibility) {
            return .disabled(disabledReason)
        }

        if let disabledReason = peerTrustDisabledReason(context.peerTrustReadiness) {
            return .disabled(disabledReason)
        }

        return .enabled(tokenEndpointURL: tokenEndpointURL)
    }

    func dryRunDiagnostic(_ context: DirectCallProductionActivationContext) -> DirectCallProductionActivationDryRunDiagnostic {
        let decision = evaluate(context)
        return DirectCallProductionActivationDryRunDiagnostic(isEnabled: decision.isEnabled,
                                                              disabledReason: decision.disabledReason,
                                                              isCapabilityPresent: context.serverCapability != nil,
                                                              areDependenciesReady: context.dependencies.isReadyForProductionStart,
                                                              isRoomEligible: roomEligibilityDisabledReason(context.roomEligibility) == nil,
                                                              isEndpointAccepted: isTokenEndpointAccepted(for: context),
                                                              peerTrustReadiness: context.peerTrustReadiness,
                                                              keyWrapperSource: context.dependencies.keyWrapperSource)
    }

    private func serverCapabilityDisabledReason(_ serverCapability: DirectCallProductionServerCapability?) -> DirectCallProductionActivationDisabledReason? {
        guard let serverCapability else {
            return .serverCapabilityUnavailable
        }

        guard serverCapability.isEnabled else {
            return .serverCapabilityDisabled
        }

        guard serverCapability.version == DirectCallProductionServerCapability.supportedVersion else {
            return .unsupportedCapabilityVersion
        }

        guard serverCapability.supportsIntent(intent) else {
            return .unsupportedIntent
        }

        guard serverCapability.mediaTransport == DirectCallProductionServerCapability.liveKitMediaTransport else {
            return .unsupportedMediaTransport
        }

        guard serverCapability.isE2EERequired else {
            return .e2eeNotRequiredByCapability
        }

        guard serverCapability.keyEnvelope == DirectCallProductionServerCapability.matrixSDKKeyEnvelope else {
            return .unsupportedKeyEnvelope
        }

        return nil
    }

    private func tokenEndpointURL(for context: DirectCallProductionActivationContext,
                                  serverCapability: DirectCallProductionServerCapability) -> URL? {
        if let configuredTokenEndpointURL = context.configuredTokenEndpointURL {
            return isSameOrigin(configuredTokenEndpointURL, as: context.homeserverBaseURL) ? configuredTokenEndpointURL : nil
        }

        return serverCapability.tokenEndpointURL(homeserverBaseURL: context.homeserverBaseURL)
    }

    private func isTokenEndpointAccepted(for context: DirectCallProductionActivationContext) -> Bool {
        guard context.appRolloutEnabled,
              serverCapabilityDisabledReason(context.serverCapability) == nil,
              let serverCapability = context.serverCapability else {
            return false
        }

        if let configuredTokenEndpointURL = context.configuredTokenEndpointURL,
           !isSameOrigin(configuredTokenEndpointURL, as: context.homeserverBaseURL) {
            return false
        }

        return tokenEndpointURL(for: context, serverCapability: serverCapability) != nil
    }

    private func roomEligibilityDisabledReason(_ roomEligibility: DirectCallProductionRoomEligibility) -> DirectCallProductionActivationDisabledReason? {
        guard roomEligibility.isEncrypted else {
            return .roomNotEncrypted
        }

        guard roomEligibility.isDirect else {
            return .roomNotDirect
        }

        guard roomEligibility.hasExactlyTwoJoinedMembers else {
            return .roomNotOneToOne
        }

        guard roomEligibility.hasPeerUserID else {
            return .peerUnavailable
        }

        return nil
    }

    private func isSameOrigin(_ lhs: URL, as rhs: URL?) -> Bool {
        guard let rhs,
              let lhsScheme = lhs.scheme?.lowercased(),
              let rhsScheme = rhs.scheme?.lowercased(),
              let lhsHost = lhs.host?.lowercased(),
              let rhsHost = rhs.host?.lowercased() else {
            return false
        }

        return lhsScheme == rhsScheme && lhsHost == rhsHost && normalizedPort(lhs) == normalizedPort(rhs)
    }

    private func normalizedPort(_ url: URL) -> Int? {
        if let port = url.port {
            return port
        }

        switch url.scheme?.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
        }
    }

    private func peerTrustDisabledReason(_ readiness: DirectCallPeerTrustReadiness) -> DirectCallProductionActivationDisabledReason? {
        switch readiness {
        case .peerTrustReady:
            return nil
        case .peerTrustUnavailable:
            return .peerTrustUnavailable
        case .unverifiedDevice:
            return .unverifiedDevice
        case .noEligibleDevice:
            return .noEligibleDevice
        case .crossSigningUnavailable:
            return .crossSigningUnavailable
        case .unknown:
            return .peerTrustUnknown
        }
    }
}

@MainActor
protocol DirectCallProductionActivationDeciding {
    func directCallProductionActivationDecision(homeserverBaseURL: URL?,
                                                roomEligibility: DirectCallProductionRoomEligibility) async -> DirectCallProductionActivationDecision
}

@MainActor
protocol DirectCallProductionActivationDryRunDiagnosing {
    func directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: URL?,
                                                        roomEligibility: DirectCallProductionRoomEligibility) async -> DirectCallProductionActivationDryRunDiagnostic
}

@MainActor
final class DirectCallProductionActivationDecisionService: DirectCallProductionActivationDeciding, DirectCallProductionActivationDryRunDiagnosing, CustomStringConvertible, CustomDebugStringConvertible {
    private let rolloutProvider: DirectCallProductionRolloutProviding
    private let capabilityProvider: DirectCallProductionCapabilityProviding
    private let dependencyProvider: NativeDirectCallProductionDependencyProviding
    private let peerTrustReadinessProvider: DirectCallPeerTrustReadinessProviding
    private let activationGate: DirectCallProductionActivationGate

    init(rolloutProvider: DirectCallProductionRolloutProviding,
         capabilityProvider: DirectCallProductionCapabilityProviding? = nil,
         dependencyProvider: NativeDirectCallProductionDependencyProviding? = nil,
         peerTrustReadinessProvider: DirectCallPeerTrustReadinessProviding? = nil,
         activationGate: DirectCallProductionActivationGate = .init()) {
        self.rolloutProvider = rolloutProvider
        self.capabilityProvider = capabilityProvider ?? FailClosedDirectCallProductionCapabilityProvider()
        self.dependencyProvider = dependencyProvider ?? NativeDirectCallProductionDependencyAssembly(configuration: rolloutProvider.directCallProductionConfiguration())
        self.peerTrustReadinessProvider = peerTrustReadinessProvider ?? FailClosedDirectCallPeerTrustReadinessProvider()
        self.activationGate = activationGate
    }

    convenience init(configuration: DirectCallProductionConfiguration = .init(),
                     capabilityProvider: DirectCallProductionCapabilityProviding? = nil,
                     dependencyProvider: NativeDirectCallProductionDependencyProviding? = nil,
                     peerTrustReadinessProvider: DirectCallPeerTrustReadinessProviding? = nil,
                     activationGate: DirectCallProductionActivationGate = .init()) {
        self.init(rolloutProvider: StaticDirectCallProductionRolloutProvider(configuration: configuration),
                  capabilityProvider: capabilityProvider,
                  dependencyProvider: dependencyProvider ?? NativeDirectCallProductionDependencyAssembly(configuration: configuration),
                  peerTrustReadinessProvider: peerTrustReadinessProvider,
                  activationGate: activationGate)
    }

    func directCallProductionActivationDecision(homeserverBaseURL: URL?,
                                                roomEligibility: DirectCallProductionRoomEligibility) async -> DirectCallProductionActivationDecision {
        let context = await activationContext(homeserverBaseURL: homeserverBaseURL,
                                              roomEligibility: roomEligibility)
        return activationGate.evaluate(context)
    }

    func directCallProductionActivationDryRunDiagnostic(homeserverBaseURL: URL?,
                                                        roomEligibility: DirectCallProductionRoomEligibility) async -> DirectCallProductionActivationDryRunDiagnostic {
        let context = await activationContext(homeserverBaseURL: homeserverBaseURL,
                                              roomEligibility: roomEligibility)
        return activationGate.dryRunDiagnostic(context)
    }

    private func activationContext(homeserverBaseURL: URL?,
                                   roomEligibility: DirectCallProductionRoomEligibility) async -> DirectCallProductionActivationContext {
        let configuration = rolloutProvider.directCallProductionConfiguration()
        guard configuration.isEnabled else {
            return .init(appRolloutEnabled: false,
                         homeserverBaseURL: homeserverBaseURL,
                         configuredTokenEndpointURL: configuration.tokenEndpointURL,
                         roomEligibility: roomEligibility)
        }

        let capabilityResult = await capabilityProvider.directCallProductionServerCapability()
        guard let serverCapability = capabilityResult.capability else {
            return .init(appRolloutEnabled: true,
                         homeserverBaseURL: homeserverBaseURL,
                         serverCapability: nil,
                         configuredTokenEndpointURL: configuration.tokenEndpointURL,
                         roomEligibility: roomEligibility)
        }

        let dependencies = dependencyProvider.nativeDirectCallProductionDependencies()
        let peerTrustReadiness: DirectCallPeerTrustReadiness
        if dependencies.isReadyForProductionStart, isRoomEligibleForPeerTrustCheck(roomEligibility) {
            peerTrustReadiness = await peerTrustReadinessProvider.directCallPeerTrustReadiness()
        } else {
            peerTrustReadiness = .peerTrustUnavailable
        }

        return .init(appRolloutEnabled: true,
                     homeserverBaseURL: homeserverBaseURL,
                     serverCapability: serverCapability,
                     configuredTokenEndpointURL: configuration.tokenEndpointURL,
                     dependencies: dependencies,
                     roomEligibility: roomEligibility,
                     peerTrustReadiness: peerTrustReadiness)
    }

    private func isRoomEligibleForPeerTrustCheck(_ roomEligibility: DirectCallProductionRoomEligibility) -> Bool {
        roomEligibility.isEncrypted &&
            roomEligibility.isDirect &&
            roomEligibility.hasExactlyTwoJoinedMembers &&
            roomEligibility.hasPeerUserID
    }

    nonisolated var description: String {
        "DirectCallProductionActivationDecisionService(redacted: true)"
    }

    nonisolated var debugDescription: String {
        description
    }
}

struct DirectCallProductionLiveKitConfiguration: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let tokenEndpointURL: URL?

    init(tokenEndpointURL: URL? = nil) {
        self.tokenEndpointURL = tokenEndpointURL
    }

    var isConfigured: Bool {
        tokenEndpointURL != nil
    }

    var description: String {
        "DirectCallProductionLiveKitConfiguration(tokenEndpointURL: <redacted>, isConfigured: \(isConfigured))"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol DirectCallAudioRouteControllerProtocol {
    func configureDefaultAudioRoute(for session: DirectCallSession) -> Result<DirectCallAudioRoute, DirectCallMediaError>
    func setSpeakerEnabled(_ isEnabled: Bool) -> Result<DirectCallAudioRoute, DirectCallMediaError>
    func deactivateAudioSession()
}

@MainActor
final class NoOpDirectCallMediaTokenProvider: DirectCallMediaTokenProviderProtocol {
    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        .failure(.tokenUnavailable)
    }
}

@MainActor
final class UnavailableDirectCallLiveKitTokenClient: DirectCallLiveKitTokenClientProtocol {
    func connection(for request: DirectCallLiveKitTokenRequest) async -> Result<DirectCallLiveKitTokenResponse, DirectCallMediaError> {
        .failure(.tokenUnavailable)
    }
}

@MainActor
final class ProductionDirectCallLiveKitTokenClient: DirectCallLiveKitTokenClientProtocol, CustomStringConvertible, CustomDebugStringConvertible {
    private let configuration: DirectCallProductionLiveKitConfiguration
    private let httpTransport: DirectCallHTTPTransportProtocol?
    private let accessTokenProvider: DirectCallMatrixAccessTokenProviding?
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    #if DEBUG
    private var diagnosticState = DirectCallDiagnosticSnapshot()

    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        diagnosticState
    }
    #endif

    init(configuration: DirectCallProductionLiveKitConfiguration = .init(),
         httpTransport: DirectCallHTTPTransportProtocol? = nil,
         accessTokenProvider: DirectCallMatrixAccessTokenProviding? = nil,
         jsonEncoder: JSONEncoder = JSONEncoder(),
         jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.configuration = configuration
        self.httpTransport = httpTransport
        self.accessTokenProvider = accessTokenProvider
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
    }

    func connection(for request: DirectCallLiveKitTokenRequest) async -> Result<DirectCallLiveKitTokenResponse, DirectCallMediaError> {
        #if DEBUG
        diagnosticState = DirectCallDiagnosticSnapshot()
        #endif

        guard request.intent == .audio else {
            recordTokenFailure(reason: .unsupportedIntent)
            return .failure(.unsupportedIntent)
        }

        guard let endpointURL = configuration.tokenEndpointURL else {
            recordTokenFailure(reason: .tokenEndpointUnavailable)
            return .failure(.tokenEndpointUnavailable)
        }

        guard let httpTransport else {
            recordTokenFailure(reason: .tokenHTTPUnavailable)
            return .failure(.tokenHTTPUnavailable)
        }

        guard let accessTokenProvider,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              !accessToken.isEmpty else {
            recordTokenFailure(reason: .accessTokenUnavailable)
            return .failure(.accessTokenUnavailable)
        }

        let requestData: Data
        do {
            requestData = try jsonEncoder.encode(DirectCallProductionLiveKitTokenRequestDTO(request: request))
        } catch {
            recordTokenFailure(reason: .tokenResponseInvalid)
            return .failure(.tokenResponseInvalid)
        }

        let transportRequest = DirectCallHTTPTransportRequest.postJSON(to: endpointURL,
                                                                       bearerAccessToken: accessToken,
                                                                       body: requestData)
        switch await httpTransport.send(transportRequest) {
        case .success(let response):
            return decodeConnectionResponse(response, for: request)
        case .failure:
            recordTokenFailure(reason: .tokenHTTPUnavailable)
            return .failure(.tokenHTTPUnavailable)
        }
    }

    nonisolated var description: String {
        "ProductionDirectCallLiveKitTokenClient(tokenEndpointURL: <redacted>)"
    }

    nonisolated var debugDescription: String {
        description
    }

    private func decodeConnectionResponse(_ response: DirectCallHTTPTransportResponse,
                                          for request: DirectCallLiveKitTokenRequest) -> Result<DirectCallLiveKitTokenResponse, DirectCallMediaError> {
        guard (200..<300).contains(response.statusCode) else {
            return .failure(decodeError(response.data, statusCode: response.statusCode))
        }

        do {
            let dto = try jsonDecoder.decode(DirectCallProductionLiveKitTokenResponseDTO.self, from: response.data)
            recordTokenDiagnostics(dto.diagnostics ?? .init(tokenRequestSeen: true,
                                                            tokenStatus: response.statusCode,
                                                            tokenReason: .issued,
                                                            eligibilityAllowed: true,
                                                            allocationAttempted: true,
                                                            liveKitRoomPrecreateAttempted: true,
                                                            tokenIssued: true))
            return tokenResponse(from: dto, for: request)
        } catch {
            recordTokenDiagnostics(.init(tokenRequestSeen: true,
                                         tokenStatus: response.statusCode,
                                         tokenReason: .tokenResponseInvalid))
            return .failure(.tokenResponseInvalid)
        }
    }

    private func decodeError(_ data: Data, statusCode: Int) -> DirectCallMediaError {
        guard let errorDTO = try? jsonDecoder.decode(DirectCallProductionLiveKitTokenErrorDTO.self, from: data) else {
            recordTokenDiagnostics(.init(tokenRequestSeen: true,
                                         tokenStatus: statusCode,
                                         tokenReason: .unknown))
            return .tokenBackendRejected
        }

        recordTokenDiagnostics(errorDTO.diagnostics ?? .init(tokenRequestSeen: true,
                                                             tokenStatus: statusCode,
                                                             tokenErrcode: errorDTO.errcode,
                                                             tokenReason: tokenReason(for: errorDTO.errcode, statusCode: statusCode),
                                                             rateLimited: errorDTO.errcode == "M_DIRECT_CALL_RATE_LIMITED"))

        switch errorDTO.errcode {
        case "M_DIRECT_CALL_UNSUPPORTED_INTENT":
            return .unsupportedIntent
        default:
            return .tokenBackendRejected
        }
    }

    private func tokenResponse(from dto: DirectCallProductionLiveKitTokenResponseDTO,
                               for request: DirectCallLiveKitTokenRequest) -> Result<DirectCallLiveKitTokenResponse, DirectCallMediaError> {
        guard dto.version == 1,
              dto.allocation.callID == request.callID,
              DirectCallIntent.parse(dto.allocation.intent) == request.intent,
              !dto.liveKit.serverURL.isEmpty,
              !dto.liveKit.roomName.isEmpty,
              !dto.liveKit.participantToken.isEmpty else {
            return .failure(.tokenResponseInvalid)
        }

        return .success(.init(serverURLString: dto.liveKit.serverURL,
                              roomName: dto.liveKit.roomName,
                              token: dto.liveKit.participantToken,
                              expiresAtPresent: dto.liveKit.expiresAt?.isEmpty == false))
    }

    private func tokenReason(for errcode: String, statusCode: Int) -> DirectCallDiagnosticTokenReason {
        switch errcode {
        case "M_DIRECT_CALL_UNSUPPORTED_INTENT":
            .unsupportedIntent
        case "M_DIRECT_CALL_NOT_ELIGIBLE":
            .eligibilityRejected
        case "M_DIRECT_CALL_RATE_LIMITED":
            .rateLimited
        case "M_DIRECT_CALL_RATE_LIMIT_STORE_UNAVAILABLE":
            .rateLimitStoreUnavailable
        case "M_DIRECT_CALL_ALLOCATION_FAILED":
            .allocationFailed
        case "M_DIRECT_CALL_LIVEKIT_ROOM_UNAVAILABLE":
            .liveKitRoomPrecreateFailed
        case "M_NOT_JOINED", "M_DIRECT_CALL_PEER_MISMATCH", "M_ROOM_NOT_ENCRYPTED", "M_DIRECT_CALL_NOT_1_TO_1":
            .roomValidationFailed
        case "M_UNKNOWN_TOKEN", "M_FORBIDDEN":
            .authRejected
        default:
            statusCode == 400 ? .badRequest : .unknown
        }
    }

    private func recordTokenFailure(reason: DirectCallDiagnosticTokenReason) {
        recordTokenDiagnostics(.init(tokenRequestSeen: false,
                                     tokenReason: reason))
    }

    private func recordTokenDiagnostics(_ diagnostics: DirectCallProductionLiveKitTokenDiagnosticsDTO) {
        #if DEBUG
        diagnosticState.mergeReceiveDiagnostics(from: diagnostics.diagnosticSnapshot)
        #endif
    }
}

#if DEBUG
extension ProductionDirectCallLiveKitTokenClient: DirectCallMediaDiagnosticSnapshotProviding { }
#endif

@MainActor
final class DirectCallLiveKitTokenProvider: DirectCallMediaTokenProviderProtocol {
    private let tokenClient: DirectCallLiveKitTokenClientProtocol

    #if DEBUG
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        (tokenClient as? DirectCallMediaDiagnosticSnapshotProviding)?.diagnosticSnapshot ?? .empty
    }
    #endif

    init(tokenClient: DirectCallLiveKitTokenClientProtocol? = nil) {
        self.tokenClient = tokenClient ?? UnavailableDirectCallLiveKitTokenClient()
    }

    func connectionInfo(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        guard session.intent == .audio else {
            return .failure(.unsupportedIntent)
        }

        guard session.isValidForDirectAudioPreparation else {
            return .failure(.invalidSession)
        }

        guard session.encryptionState == .ready else {
            return .failure(.e2eeNotReady)
        }

        let request = DirectCallLiveKitTokenRequest(callID: session.callID,
                                                    roomID: session.roomID,
                                                    peerUserID: session.peerUserID,
                                                    intent: session.intent,
                                                    direction: .init(session.direction))
        switch await tokenClient.connection(for: request) {
        case .success(let response):
            return Self.connectionInfo(from: response)
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func connectionInfo(from response: DirectCallLiveKitTokenResponse) -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        guard response.token.isEmpty == false,
              response.roomName.isEmpty == false,
              let serverURL = URL(string: response.serverURLString),
              let scheme = serverURL.scheme?.lowercased(),
              ["http", "https", "ws", "wss"].contains(scheme),
              serverURL.host?.isEmpty == false else {
            return .failure(.tokenResponseInvalid)
        }

        return .success(.init(serverURL: serverURL,
                              roomName: response.roomName,
                              token: response.token,
                              expiresAtPresent: response.expiresAtPresent))
    }
}

#if DEBUG
extension DirectCallLiveKitTokenProvider: DirectCallMediaDiagnosticSnapshotProviding { }
#endif

@MainActor
final class NoOpDirectCallAudioRouteController: DirectCallAudioRouteControllerProtocol {
    private(set) var currentRoute: DirectCallAudioRoute = .systemDefault

    func configureDefaultAudioRoute(for session: DirectCallSession) -> Result<DirectCallAudioRoute, DirectCallMediaError> {
        guard session.intent == .audio else {
            return .failure(.unsupportedIntent)
        }

        currentRoute = .earpiece
        return .success(currentRoute)
    }

    func setSpeakerEnabled(_ isEnabled: Bool) -> Result<DirectCallAudioRoute, DirectCallMediaError> {
        currentRoute = isEnabled ? .speaker : .earpiece
        return .success(currentRoute)
    }

    func deactivateAudioSession() {
        currentRoute = .systemDefault
    }
}
