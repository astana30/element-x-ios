//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import SwiftUI

struct MatrixRTCWidgetEncryptionKey {
    let identity: String
    let keyBase64: String
    let index: Int32
}

@MainActor
final class MatrixRTCNativeWidgetBridge {
    private let widgetDriver: ElementCallWidgetDriverProtocol
    private var cancellables = Set<AnyCancellable>()
    private var continuations = [String: CheckedContinuation<[String: Any]?, Never>]()
    private var encryptionKeyHandler: ((MatrixRTCWidgetEncryptionKey) -> Void)?

    init(widgetDriver: ElementCallWidgetDriverProtocol) {
        self.widgetDriver = widgetDriver
        widgetDriver.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleIncomingMessage(message)
            }
            .store(in: &cancellables)
    }

    func start(baseURL: URL, clientID: String) async -> Bool {
        switch await widgetDriver.start(baseURL: baseURL,
                                        clientID: clientID,
                                        colorScheme: .dark,
                                        rageshakeURL: nil,
                                        analyticsConfiguration: nil) {
        case .success:
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=widget_start ok=true")
            return true
        case .failure:
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=widget_start ok=false")
            return false
        }
    }

    func requestOpenIDToken() async -> MatrixRTCOpenIDToken? {
        guard let response = await send(action: "get_openid", data: [:]) else {
            return nil
        }

        if let state = response["state"] as? String, state != "allowed" {
            return nil
        }

        return MatrixRTCOpenIDToken.parse(response)
    }

    func sendMembership(_ membership: MatrixRTCNativeMembership, content: [String: Any]) async -> Bool {
        let data: [String: Any] = [
            "type": "org.matrix.msc3401.call.member",
            "state_key": membership.stateKey,
            "content": content
        ]
        return await send(action: "send_event", data: data) != nil
    }

    func sendEncryptionKey(_ keyBase64: String,
                           index: Int32,
                           membership: MatrixRTCNativeMembership,
                           roomID: String,
                           peerUserID: String,
                           peerDeviceID: String) async -> Bool {
        let content: [String: Any] = [
            "keys": [
                "index": index,
                "key": keyBase64
            ],
            "room_id": roomID,
            "member": [
                "claimed_device_id": membership.deviceID,
                "id": membership.membershipID
            ],
            "session": [
                "call_id": "",
                "application": "m.call",
                "scope": "m.room"
            ]
        ]
        let data: [String: Any] = [
            "type": "io.element.call.encryption_keys",
            "encrypted": true,
            "messages": [
                peerUserID: [
                    peerDeviceID: content
                ]
            ]
        ]
        return await send(action: "send_to_device", data: data) != nil
    }

    func listenForEncryptionKeys(_ handler: @escaping (MatrixRTCWidgetEncryptionKey) -> Void) {
        encryptionKeyHandler = handler
    }

    func stop() {
        encryptionKeyHandler = nil
        continuations.values.forEach { $0.resume(returning: nil) }
        continuations.removeAll()
        cancellables.removeAll()
    }

    private func send(action: String, data: [String: Any]) async -> [String: Any]? {
        let requestID = UUID().uuidString
        let payload: [String: Any] = [
            "api": "fromWidget",
            "action": action,
            "widgetId": widgetDriver.widgetID,
            "requestId": requestID,
            "data": data
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            continuations[requestID] = continuation
            Task {
                _ = await widgetDriver.handleMessage(json)
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                finish(requestID: requestID, response: nil)
            }
        }
    }

    private func handleIncomingMessage(_ message: String) {
        guard let data = message.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let requestID = object["requestId"] as? String,
           object["response"] != nil {
            let response = object["response"] as? [String: Any]
            finish(requestID: requestID, response: response)
        }

        if let key = Self.parseEncryptionKey(object) {
            encryptionKeyHandler?(key)
        }
    }

    private func finish(requestID: String, response: [String: Any]?) {
        guard let continuation = continuations.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(returning: response)
    }

    private static func parseEncryptionKey(_ object: [String: Any]) -> MatrixRTCWidgetEncryptionKey? {
        let action = object["action"] as? String
        guard action == "send_to_device" || action == "to_device" else {
            return nil
        }

        let data = object["data"] as? [String: Any] ?? object
        let eventType = data["type"] as? String
        guard eventType == "io.element.call.encryption_keys" else {
            return nil
        }

        let content = data["content"] as? [String: Any] ?? data
        let sender = data["sender"] as? String
        let claimedDeviceID = (content["member"] as? [String: Any])?["claimed_device_id"] as? String
            ?? content["device_id"] as? String
        guard let sender, let claimedDeviceID else {
            return nil
        }

        if let keys = content["keys"] as? [String: Any],
           let key = keys["key"] as? String {
            let index = (keys["index"] as? NSNumber)?.int32Value ?? 0
            return .init(identity: "\(sender):\(claimedDeviceID)", keyBase64: key, index: index)
        }

        if let keys = content["keys"] as? [[String: Any]],
           let first = keys.first,
           let key = first["key"] as? String {
            let index = (first["index"] as? NSNumber)?.int32Value ?? 0
            return .init(identity: "\(sender):\(claimedDeviceID)", keyBase64: key, index: index)
        }

        return nil
    }
}
