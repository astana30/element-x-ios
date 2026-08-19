//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

struct MatrixRTCOpenIDToken: Equatable {
    let accessToken: String
    let tokenType: String
    let matrixServerName: String
    let expiresIn: Int

    var jsonObject: [String: Any] {
        [
            "access_token": accessToken,
            "token_type": tokenType,
            "matrix_server_name": matrixServerName,
            "expires_in": expiresIn
        ]
    }

    static func parse(_ object: [String: Any]) -> MatrixRTCOpenIDToken? {
        guard let accessToken = object["access_token"] as? String, !accessToken.isEmpty,
              let tokenType = object["token_type"] as? String, !tokenType.isEmpty,
              let matrixServerName = object["matrix_server_name"] as? String, !matrixServerName.isEmpty else {
            return nil
        }

        let expiresIn: Int
        if let value = object["expires_in"] as? Int {
            expiresIn = value
        } else if let value = object["expires_in"] as? NSNumber {
            expiresIn = value.intValue
        } else {
            expiresIn = 3600
        }

        return .init(accessToken: accessToken,
                     tokenType: tokenType,
                     matrixServerName: matrixServerName,
                     expiresIn: expiresIn)
    }
}

struct MatrixRTCLiveKitJWT: Equatable {
    let serverURL: URL
    let token: String

    static func parse(_ data: Data) -> MatrixRTCLiveKitJWT? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = object["url"] as? String,
              let url = URL(string: urlString),
              let token = object["jwt"] as? String,
              !token.isEmpty else {
            return nil
        }

        return .init(serverURL: url, token: token)
    }
}

struct MatrixRTCNativeMembership: Equatable {
    let userID: String
    let deviceID: String
    let membershipID: String
    let liveKitServiceURL: URL

    var stateKey: String {
        "_\(userID)_\(deviceID)_\(membershipID)"
    }

    var liveKitIdentity: String {
        "\(userID):\(deviceID)"
    }

    func stateContent(createdAt: Date = Date()) -> [String: Any] {
        [
            "application": "m.call",
            "call_id": "",
            "scope": "m.room",
            "device_id": deviceID,
            "membershipID": membershipID,
            "expires": 14_400_000,
            "created_ts": UInt64(createdAt.timeIntervalSince1970 * 1000),
            "foci_preferred": [
                [
                    "type": "livekit",
                    "livekit_service_url": liveKitServiceURL.absoluteString
                ]
            ],
            "focus_active": [
                "type": "livekit",
                "focus_selection": "oldest_membership"
            ]
        ]
    }
}

struct MatrixRTCHTTPResponse: Equatable {
    let statusCode: Int
    let data: Data
}

protocol MatrixRTCHTTPClientProtocol {
    func send(method: String, url: URL, headers: [String: String], body: Data?) async -> Result<MatrixRTCHTTPResponse, Error>
}

struct URLSessionMatrixRTCHTTPClient: MatrixRTCHTTPClientProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func send(method: String, url: URL, headers: [String: String], body: Data?) async -> Result<MatrixRTCHTTPResponse, Error> {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(URLError(.badServerResponse))
            }
            return .success(.init(statusCode: httpResponse.statusCode, data: data))
        } catch {
            return .failure(error)
        }
    }
}

struct MatrixRTCNativeSignalingClient {
    private let httpClient: MatrixRTCHTTPClientProtocol

    init(httpClient: MatrixRTCHTTPClientProtocol = URLSessionMatrixRTCHTTPClient()) {
        self.httpClient = httpClient
    }

    func requestOpenIDToken(homeserverURL: URL, userID: String, accessToken: String) async -> MatrixRTCOpenIDToken? {
        let url = homeserverURL
            .appending(path: "/_matrix/client/v3/user")
            .appending(path: userID)
            .appending(path: "openid/request_token")
        let body = try? JSONSerialization.data(withJSONObject: [String: Any]())
        switch await sendJSON(method: "POST", url: url, accessToken: accessToken, body: body) {
        case .success(let response) where (200...299).contains(response.statusCode):
            guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=openid http=\(response.statusCode) parse=false")
                return nil
            }
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=openid http=\(response.statusCode) parse=true")
            return MatrixRTCOpenIDToken.parse(object)
        case .success(let response):
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=openid http=\(response.statusCode) parse=false")
            return nil
        case .failure:
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=openid http=0 parse=false")
            return nil
        }
    }

    func requestLiveKitJWT(liveKitServiceURL: URL,
                           roomID: String,
                           deviceID: String,
                           openIDToken: MatrixRTCOpenIDToken) async -> MatrixRTCLiveKitJWT? {
        let url = liveKitServiceURL.appending(path: "sfu/get")
        let bodyObject: [String: Any] = [
            "room": roomID,
            "device_id": deviceID,
            "openid_token": openIDToken.jsonObject
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: bodyObject) else {
            return nil
        }

        switch await sendJSON(method: "POST", url: url, accessToken: nil, body: body) {
        case .success(let response) where (200...299).contains(response.statusCode):
            let parsed = MatrixRTCLiveKitJWT.parse(response.data)
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=sfu_get http=\(response.statusCode) parse=\(parsed != nil)")
            return parsed
        case .success(let response):
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=sfu_get http=\(response.statusCode) parse=false")
            return nil
        case .failure:
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=sfu_get http=0 parse=false")
            return nil
        }
    }

    func putMembership(homeserverURL: URL,
                       roomID: String,
                       accessToken: String,
                       membership: MatrixRTCNativeMembership,
                       content: [String: Any]) async -> Bool {
        let url = homeserverURL
            .appending(path: "/_matrix/client/v3/rooms")
            .appending(path: roomID)
            .appending(path: "state")
            .appending(path: "org.matrix.msc3401.call.member")
            .appending(path: membership.stateKey)
        guard let body = try? JSONSerialization.data(withJSONObject: content) else {
            return false
        }

        switch await sendJSON(method: "PUT", url: url, accessToken: accessToken, body: body) {
        case .success(let response):
            let succeeded = (200...299).contains(response.statusCode)
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=membership http=\(response.statusCode) ok=\(succeeded)")
            return succeeded
        case .failure:
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=membership http=0 ok=false")
            return false
        }
    }

    private func sendJSON(method: String, url: URL, accessToken: String?, body: Data?) async -> Result<MatrixRTCHTTPResponse, Error> {
        var headers = ["Content-Type": "application/json"]
        if let accessToken, !accessToken.isEmpty {
            headers["Authorization"] = "Bearer \(accessToken)"
        }
        return await httpClient.send(method: method, url: url, headers: headers, body: body)
    }
}
