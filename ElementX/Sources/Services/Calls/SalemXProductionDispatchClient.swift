//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum SalemXProductionDispatchHTTPStatusBucket: String {
    case authentication
    case forbidden
    case notFound
    case conflict
    case expired
    case server
    case other
}

enum SalemXProductionDispatchServerReasonBucket: String {
    case disabled
    case capability
    case expired
    case conflict
    case deliveryFailed
    case unavailable
    case unknown
}

enum SalemXProductionDispatchClientError: Error, Equatable, CustomStringConvertible {
    case invalidConfiguration
    case accessTokenUnavailable
    case encoding
    case cancelled
    case transportUnavailable
    case ambiguousSend
    case http(SalemXProductionDispatchHTTPStatusBucket, SalemXProductionDispatchServerReasonBucket)
    case decoding
    case unsupportedProtocol
    case malformedReference
    case dispatchMismatch
    case invalidState

    var description: String {
        switch self {
        case .invalidConfiguration:
            "SalemXProductionDispatchClientError.invalidConfiguration"
        case .accessTokenUnavailable:
            "SalemXProductionDispatchClientError.accessTokenUnavailable"
        case .encoding:
            "SalemXProductionDispatchClientError.encoding"
        case .cancelled:
            "SalemXProductionDispatchClientError.cancelled"
        case .transportUnavailable:
            "SalemXProductionDispatchClientError.transportUnavailable"
        case .ambiguousSend:
            "SalemXProductionDispatchClientError.ambiguousSend"
        case .http(let status, let reason):
            "SalemXProductionDispatchClientError.http(status: \(status.rawValue), reason: \(reason.rawValue))"
        case .decoding:
            "SalemXProductionDispatchClientError.decoding"
        case .unsupportedProtocol:
            "SalemXProductionDispatchClientError.unsupportedProtocol"
        case .malformedReference:
            "SalemXProductionDispatchClientError.malformedReference"
        case .dispatchMismatch:
            "SalemXProductionDispatchClientError.dispatchMismatch"
        case .invalidState:
            "SalemXProductionDispatchClientError.invalidState"
        }
    }
}

@MainActor
protocol SalemXProductionDispatchClientProtocol {
    func registerCapability(_ request: SalemXProductionDispatchCapabilityRegistrationRequest) async
        -> Result<SalemXProductionDispatchCapabilityRegistrationResponse, SalemXProductionDispatchClientError>
    func prepare(_ request: SalemXProductionDispatchPrepareRequest) async
        -> Result<SalemXProductionDispatchPrepareResponse, SalemXProductionDispatchClientError>
    func claim(_ request: SalemXProductionDispatchReferenceRequest) async
        -> Result<SalemXProductionDispatchClaimResponse, SalemXProductionDispatchClientError>
    func sendPrepared(_ request: SalemXProductionDispatchSendPreparedRequest) async
        -> Result<SalemXProductionDispatchSendPreparedResponse, SalemXProductionDispatchClientError>
    func cancelPrepared(_ request: SalemXProductionDispatchReferenceRequest) async
        -> Result<SalemXProductionDispatchCancelResponse, SalemXProductionDispatchClientError>
}

@MainActor
final class SalemXProductionDispatchClient: SalemXProductionDispatchClientProtocol, CustomStringConvertible {
    static let capabilityPath = "/_matrix/client/unstable/kz.salemx.direct_call/pushkit/token"
    static let preparePath = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite/prepare"
    static let claimPath = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata/sender/claim"
    static let sendPreparedPath = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite/send-prepared"
    static let cancelPreparedPath = "/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/invite/cancel-prepared"

    private let homeserverOrigin: URL
    private let httpTransport: DirectCallHTTPTransportProtocol
    private let accessTokenProvider: DirectCallMatrixAccessTokenProviding
    private let allowsInsecureTestOrigin: Bool
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(homeserverOrigin: URL,
         httpTransport: DirectCallHTTPTransportProtocol? = nil,
         accessTokenProvider: DirectCallMatrixAccessTokenProviding,
         allowsInsecureTestOrigin: Bool = false,
         encoder: JSONEncoder = JSONEncoder(),
         decoder: JSONDecoder = JSONDecoder()) {
        self.homeserverOrigin = homeserverOrigin
        self.httpTransport = httpTransport ?? URLSessionDirectCallHTTPTransport()
        self.accessTokenProvider = accessTokenProvider
        self.allowsInsecureTestOrigin = allowsInsecureTestOrigin
        self.encoder = encoder
        self.decoder = decoder
    }

    var description: String {
        "SalemXProductionDispatchClient(origin: <redacted>)"
    }

    func registerCapability(_ request: SalemXProductionDispatchCapabilityRegistrationRequest) async
        -> Result<SalemXProductionDispatchCapabilityRegistrationResponse, SalemXProductionDispatchClientError> {
        guard !request.token.isEmpty,
              !request.appSessionGeneration.isEmpty,
              (1...86400).contains(request.capabilityExpiresInSeconds) else {
            return .failure(.malformedReference)
        }
        let result: Result<SalemXProductionDispatchCapabilityRegistrationResponse, SalemXProductionDispatchClientError> = await perform(path: Self.capabilityPath,
                                                                                                                                        request: request,
                                                                                                                                        ambiguousOnTransportFailure: false)
        return result.flatMap { response in
            guard response.registrationResult == "registered", response.tokenRedacted else {
                return .failure(.invalidState)
            }
            return .success(response)
        }
    }

    func prepare(_ request: SalemXProductionDispatchPrepareRequest) async
        -> Result<SalemXProductionDispatchPrepareResponse, SalemXProductionDispatchClientError> {
        guard !request.appSessionGeneration.isEmpty else { return .failure(.malformedReference) }
        let result: Result<SalemXProductionDispatchPrepareResponse, SalemXProductionDispatchClientError> = await perform(path: Self.preparePath,
                                                                                                                         request: request,
                                                                                                                         ambiguousOnTransportFailure: false)
        return result.flatMap { response in
            do {
                try response.validate()
                return .success(response)
            } catch {
                return .failure(Self.modelError(error))
            }
        }
    }

    func claim(_ request: SalemXProductionDispatchReferenceRequest) async
        -> Result<SalemXProductionDispatchClaimResponse, SalemXProductionDispatchClientError> {
        await stateOperation(path: Self.claimPath,
                             request: request,
                             expectedState: .claimed,
                             expectedFlag: \SalemXProductionDispatchClaimResponse.claimed)
    }

    func sendPrepared(_ request: SalemXProductionDispatchSendPreparedRequest) async
        -> Result<SalemXProductionDispatchSendPreparedResponse, SalemXProductionDispatchClientError> {
        guard Self.validReferenceRequest(request.dispatchID,
                                         request.senderReference,
                                         request.appSessionGeneration),
            !request.receiverReference.isEmpty else {
            return .failure(.malformedReference)
        }
        let result: Result<SalemXProductionDispatchSendPreparedResponse, SalemXProductionDispatchClientError> = await perform(path: Self.sendPreparedPath,
                                                                                                                              request: request,
                                                                                                                              ambiguousOnTransportFailure: true)
        return result.flatMap { response in
            guard response.dispatchProtocolVersion == SalemXProductionDispatchProtocolVersion.v1.rawValue else {
                return .failure(.unsupportedProtocol)
            }
            guard response.dispatchID == nil || response.dispatchID == request.dispatchID else {
                return .failure(.dispatchMismatch)
            }
            guard response.state == .sent,
                  response.apnsSent,
                  response.apnsSendCount == 1,
                  !response.rawIdentifiersLogged else {
                return .failure(.invalidState)
            }
            return .success(response)
        }
    }

    func cancelPrepared(_ request: SalemXProductionDispatchReferenceRequest) async
        -> Result<SalemXProductionDispatchCancelResponse, SalemXProductionDispatchClientError> {
        await stateOperation(path: Self.cancelPreparedPath,
                             request: request,
                             expectedState: .cancelled,
                             expectedFlag: \SalemXProductionDispatchCancelResponse.cancelled)
    }

    private func stateOperation<Request, Response>(path: String,
                                                   request: Request,
                                                   expectedState: SalemXProductionDispatchState,
                                                   expectedFlag: KeyPath<Response, Bool>) async -> Result<Response, SalemXProductionDispatchClientError>
        where Request: Encodable & Sendable & DispatchReferenceProviding,
        Response: Decodable & Sendable & DispatchStateResponseProviding {
        guard Self.validReferenceRequest(request.dispatchID, request.senderReference, request.appSessionGeneration) else {
            return .failure(.malformedReference)
        }
        let result: Result<Response, SalemXProductionDispatchClientError> = await perform(path: path,
                                                                                          request: request,
                                                                                          ambiguousOnTransportFailure: false)
        return result.flatMap { response in
            guard response.dispatchProtocolVersion == SalemXProductionDispatchProtocolVersion.v1.rawValue else {
                return .failure(.unsupportedProtocol)
            }
            guard response.dispatchID == nil || response.dispatchID == request.dispatchID else {
                return .failure(.dispatchMismatch)
            }
            guard response.state == expectedState, response[keyPath: expectedFlag] else {
                return .failure(.invalidState)
            }
            return .success(response)
        }
    }

    private func perform<Request: Encodable, Response: Decodable>(path: String,
                                                                  request: Request,
                                                                  ambiguousOnTransportFailure: Bool) async -> Result<Response, SalemXProductionDispatchClientError> {
        guard let endpoint = endpointURL(path: path) else { return .failure(.invalidConfiguration) }
        guard let accessToken = await accessTokenProvider.matrixAccessToken(), !accessToken.isEmpty else {
            return .failure(.accessTokenUnavailable)
        }
        let body: Data
        do {
            body = try encoder.encode(request)
        } catch {
            return .failure(.encoding)
        }
        let transportRequest = DirectCallHTTPTransportRequest.postJSON(to: endpoint,
                                                                       bearerAccessToken: accessToken,
                                                                       body: body)
        switch await httpTransport.send(transportRequest) {
        case .failure:
            if Task.isCancelled { return .failure(.cancelled) }
            return .failure(ambiguousOnTransportFailure ? .ambiguousSend : .transportUnavailable)
        case .success(let response):
            if Task.isCancelled { return .failure(.cancelled) }
            guard (200..<300).contains(response.statusCode) else {
                return .failure(httpError(response))
            }
            do {
                return try .success(decoder.decode(Response.self, from: response.data))
            } catch {
                return .failure(.decoding)
            }
        }
    }

    private func endpointURL(path: String) -> URL? {
        guard let scheme = homeserverOrigin.scheme?.lowercased(),
              let host = homeserverOrigin.host?.lowercased(),
              !host.isEmpty,
              scheme == "https" || (allowsInsecureTestOrigin && scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)),
              var components = URLComponents(url: homeserverOrigin, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func httpError(_ response: DirectCallHTTPTransportResponse) -> SalemXProductionDispatchClientError {
        let status: SalemXProductionDispatchHTTPStatusBucket = switch response.statusCode {
        case 401: .authentication
        case 403: .forbidden
        case 404: .notFound
        case 409: .conflict
        case 410: .expired
        case 500...599: .server
        default: .other
        }
        let errcode = (try? decoder.decode(SalemXProductionDispatchServerErrorResponse.self, from: response.data))?.errcode
        return .http(status, Self.reasonBucket(errcode))
    }

    private static func reasonBucket(_ errcode: String?) -> SalemXProductionDispatchServerReasonBucket {
        guard let errcode else { return .unknown }
        if errcode == "M_UNRECOGNIZED" { return .disabled }
        if errcode.contains("CAPABILITY") || errcode.contains("BINDING") { return .capability }
        if errcode.contains("EXPIRED") { return .expired }
        if errcode.contains("CONFLICT") || errcode == "M_FORBIDDEN" { return .conflict }
        if errcode.contains("DELIVERY") { return .deliveryFailed }
        if errcode.contains("UNAVAILABLE") { return .unavailable }
        return .unknown
    }

    private static func validReferenceRequest(_ dispatchID: UUID, _ reference: String, _ generation: String) -> Bool {
        !reference.isEmpty && !generation.isEmpty
    }

    private static func modelError(_ error: Error) -> SalemXProductionDispatchClientError {
        switch error as? SalemXProductionDispatchModelError {
        case .unsupportedProtocol: .unsupportedProtocol
        case .malformedReference: .malformedReference
        case .invalidState: .invalidState
        case nil: .decoding
        }
    }
}

private protocol DispatchReferenceProviding {
    var dispatchID: UUID { get }
    var senderReference: String { get }
    var appSessionGeneration: String { get }
}

private protocol DispatchStateResponseProviding {
    var dispatchProtocolVersion: Int { get }
    var state: SalemXProductionDispatchState { get }
    var dispatchID: UUID? { get }
}

extension SalemXProductionDispatchReferenceRequest: DispatchReferenceProviding { }
extension SalemXProductionDispatchClaimResponse: DispatchStateResponseProviding { }
extension SalemXProductionDispatchCancelResponse: DispatchStateResponseProviding { }
