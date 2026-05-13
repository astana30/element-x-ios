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
        "DirectCallLiveKitTokenRequest(callID: \(callID), roomID: <redacted>, peerUserID: <redacted>, intent: \(intent.rawValue), direction: \(direction.rawValue), deviceID: <redacted>, clientTransactionID: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

struct DirectCallLiveKitTokenResponse: Equatable, CustomStringConvertible {
    let serverURLString: String
    let roomName: String
    let token: String

    var description: String {
        "DirectCallLiveKitTokenResponse(serverURLString: <redacted>, roomName: \(roomName), token: <redacted>)"
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
        "DirectCallProductionLiveKitTokenRequestDTO(version: \(version), callID: \(callID), roomID: <redacted>, peerUserID: <redacted>, intent: \(intent), direction: \(direction.rawValue), deviceID: <redacted>, clientTransactionID: <redacted>)"
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
            "LiveKit(serverURL: <redacted>, roomName: \(roomName), participantToken: <redacted>, expiresAt: \(expiresAt ?? "<nil>"))"
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
            "Allocation(id: <redacted>, callID: \(callID), intent: \(intent))"
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
    }
}

struct DirectCallProductionLiveKitTokenErrorDTO: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let errcode: String
    let error: String
    let retryAfterMS: Int?

    var description: String {
        "DirectCallProductionLiveKitTokenErrorDTO(errcode: \(errcode), error: <redacted>, retryAfterMS: \(String(describing: retryAfterMS)))"
    }

    var debugDescription: String {
        description
    }

    private enum CodingKeys: String, CodingKey {
        case errcode
        case error
        case retryAfterMS = "retry_after_ms"
    }
}

struct DirectCallHTTPTransportRequest: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data

    static func getJSON(from url: URL, bearerAccessToken: String) -> Self {
        .init(url: url,
              method: "GET",
              headers: [
                  "Accept": "application/json",
                  "Authorization": "Bearer \(bearerAccessToken)"
              ],
              body: Data())
    }

    static func postJSON(to url: URL, bearerAccessToken: String, body: Data) -> Self {
        .init(url: url,
              method: "POST",
              headers: [
                  "Accept": "application/json",
                  "Authorization": "Bearer \(bearerAccessToken)",
                  "Content-Type": "application/json"
              ],
              body: body)
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
}

struct DirectCallProductionConfiguration: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    static let tokenEndpointPath = "/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"

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

    var isConfigured: Bool {
        tokenEndpointURL != nil
    }

    var description: String {
        "DirectCallProductionConfiguration(isEnabled: \(isEnabled), tokenEndpointBaseURL: <redacted>, tokenEndpointPath: \(Self.tokenEndpointPath), isConfigured: \(isConfigured))"
    }

    var debugDescription: String {
        description
    }

    private static func makeTokenEndpointURL(from baseURL: URL) -> URL? {
        guard let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host?.isEmpty == false,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, tokenEndpointPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
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

    init(appRolloutEnabled: Bool = false,
         homeserverBaseURL: URL? = nil,
         serverCapability: DirectCallProductionServerCapability? = nil,
         configuredTokenEndpointURL: URL? = nil,
         dependencies: NativeDirectCallProductionDependencies = .disabled,
         roomEligibility: DirectCallProductionRoomEligibility = .init()) {
        self.appRolloutEnabled = appRolloutEnabled
        self.homeserverBaseURL = homeserverBaseURL
        self.serverCapability = serverCapability
        self.configuredTokenEndpointURL = configuredTokenEndpointURL
        self.dependencies = dependencies
        self.roomEligibility = roomEligibility
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

    static func disabled(_ reason: DirectCallProductionActivationDisabledReason) -> Self {
        .init(isEnabled: false,
              disabledReason: reason,
              isCapabilityPresent: false,
              areDependenciesReady: false,
              isRoomEligible: false,
              isEndpointAccepted: false)
    }

    var description: String {
        let fields = [
            "isEnabled: \(isEnabled)",
            "disabledReason: \(disabledReason?.description ?? "none")",
            "isCapabilityPresent: \(isCapabilityPresent)",
            "areDependenciesReady: \(areDependenciesReady)",
            "isRoomEligible: \(isRoomEligible)",
            "isEndpointAccepted: \(isEndpointAccepted)"
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

        guard context.dependencies.hasEncryptionService,
              context.dependencies.hasMediaEngineFactory else {
            return .disabled(.dependenciesUnavailable)
        }

        if let disabledReason = roomEligibilityDisabledReason(context.roomEligibility) {
            return .disabled(disabledReason)
        }

        return .enabled(tokenEndpointURL: tokenEndpointURL)
    }

    func dryRunDiagnostic(_ context: DirectCallProductionActivationContext) -> DirectCallProductionActivationDryRunDiagnostic {
        let decision = evaluate(context)
        return DirectCallProductionActivationDryRunDiagnostic(isEnabled: decision.isEnabled,
                                                              disabledReason: decision.disabledReason,
                                                              isCapabilityPresent: context.serverCapability != nil,
                                                              areDependenciesReady: context.dependencies.hasEncryptionService && context.dependencies.hasMediaEngineFactory,
                                                              isRoomEligible: roomEligibilityDisabledReason(context.roomEligibility) == nil,
                                                              isEndpointAccepted: isTokenEndpointAccepted(for: context))
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
    private let configuration: DirectCallProductionConfiguration
    private let capabilityProvider: DirectCallProductionCapabilityProviding
    private let dependencyProvider: NativeDirectCallProductionDependencyProviding
    private let activationGate: DirectCallProductionActivationGate

    init(configuration: DirectCallProductionConfiguration = .init(),
         capabilityProvider: DirectCallProductionCapabilityProviding? = nil,
         dependencyProvider: NativeDirectCallProductionDependencyProviding? = nil,
         activationGate: DirectCallProductionActivationGate = .init()) {
        self.configuration = configuration
        self.capabilityProvider = capabilityProvider ?? FailClosedDirectCallProductionCapabilityProvider()
        self.dependencyProvider = dependencyProvider ?? NativeDirectCallProductionDependencyAssembly(configuration: configuration)
        self.activationGate = activationGate
    }

    convenience init(rolloutProvider: DirectCallProductionRolloutProviding,
                     capabilityProvider: DirectCallProductionCapabilityProviding? = nil,
                     dependencyProvider: NativeDirectCallProductionDependencyProviding? = nil,
                     activationGate: DirectCallProductionActivationGate = .init()) {
        self.init(configuration: rolloutProvider.directCallProductionConfiguration(),
                  capabilityProvider: capabilityProvider,
                  dependencyProvider: dependencyProvider,
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

        return .init(appRolloutEnabled: true,
                     homeserverBaseURL: homeserverBaseURL,
                     serverCapability: serverCapability,
                     configuredTokenEndpointURL: configuration.tokenEndpointURL,
                     dependencies: dependencyProvider.nativeDirectCallProductionDependencies(),
                     roomEligibility: roomEligibility)
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
        guard request.intent == .audio else {
            return .failure(.unsupportedIntent)
        }

        guard let endpointURL = configuration.tokenEndpointURL else {
            return .failure(.tokenUnavailable)
        }

        guard let httpTransport else {
            return .failure(.tokenUnavailable)
        }

        guard let accessTokenProvider,
              let accessToken = await accessTokenProvider.matrixAccessToken(),
              !accessToken.isEmpty else {
            return .failure(.tokenUnavailable)
        }

        let requestData: Data
        do {
            requestData = try jsonEncoder.encode(DirectCallProductionLiveKitTokenRequestDTO(request: request))
        } catch {
            return .failure(.tokenUnavailable)
        }

        let transportRequest = DirectCallHTTPTransportRequest.postJSON(to: endpointURL,
                                                                       bearerAccessToken: accessToken,
                                                                       body: requestData)
        switch await httpTransport.send(transportRequest) {
        case .success(let response):
            return decodeConnectionResponse(response, for: request)
        case .failure(let error):
            return .failure(error)
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
            return .failure(decodeError(response.data))
        }

        do {
            let dto = try jsonDecoder.decode(DirectCallProductionLiveKitTokenResponseDTO.self, from: response.data)
            return tokenResponse(from: dto, for: request)
        } catch {
            return .failure(.tokenUnavailable)
        }
    }

    private func decodeError(_ data: Data) -> DirectCallMediaError {
        guard let errorDTO = try? jsonDecoder.decode(DirectCallProductionLiveKitTokenErrorDTO.self, from: data) else {
            return .tokenUnavailable
        }

        switch errorDTO.errcode {
        case "M_DIRECT_CALL_UNSUPPORTED_INTENT":
            return .unsupportedIntent
        default:
            return .tokenUnavailable
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
            return .failure(.tokenUnavailable)
        }

        return .success(.init(serverURLString: dto.liveKit.serverURL,
                              roomName: dto.liveKit.roomName,
                              token: dto.liveKit.participantToken))
    }
}

@MainActor
final class DirectCallLiveKitTokenProvider: DirectCallMediaTokenProviderProtocol {
    private let tokenClient: DirectCallLiveKitTokenClientProtocol

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
        case .failure:
            return .failure(.tokenUnavailable)
        }
    }

    private static func connectionInfo(from response: DirectCallLiveKitTokenResponse) -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        guard response.token.isEmpty == false,
              response.roomName.isEmpty == false,
              let serverURL = URL(string: response.serverURLString),
              let scheme = serverURL.scheme?.lowercased(),
              ["http", "https", "ws", "wss"].contains(scheme),
              serverURL.host?.isEmpty == false else {
            return .failure(.tokenUnavailable)
        }

        return .success(.init(serverURL: serverURL,
                              roomName: response.roomName,
                              token: response.token))
    }
}

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
