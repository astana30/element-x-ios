//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import MatrixRustSDK

struct DirectCallMatrixSignalContent: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    static let currentVersion = 1

    let version: Int
    let callID: String
    let type: String
    let intent: String?
    let recipient: String?
    let keyExchange: DirectCallEncryptedKeyExchangePayload?

    init(version: Int = Self.currentVersion,
         callID: String,
         type: String,
         intent: String?,
         recipient: String?,
         keyExchange: DirectCallEncryptedKeyExchangePayload?) {
        self.version = version
        self.callID = callID
        self.type = type
        self.intent = intent
        self.recipient = recipient
        self.keyExchange = keyExchange
    }

    init(signal: DirectCallOutgoingSignal) {
        self.init(callID: signal.callID,
                  type: signal.type.rawValue,
                  intent: signal.intent?.rawValue,
                  recipient: signal.peerUserID,
                  keyExchange: signal.type == .invite ? signal.keyExchange : nil)
    }

    var description: String {
        "DirectCallMatrixSignalContent(" + [
            "version: \(version)",
            "callID: \(callID)",
            "type: \(type)",
            "intent: \(String(describing: intent))",
            "recipient: \(String(describing: recipient))",
            "keyExchange: \(keyExchange == nil ? "nil" : "<redacted>")"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case callID = "call_id"
        case type
        case intent
        case recipient
        case keyExchange = "key_exchange"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        callID = try container.decode(String.self, forKey: .callID)
        type = try container.decode(String.self, forKey: .type)
        intent = try container.decodeIfPresent(String.self, forKey: .intent)
        recipient = try container.decodeIfPresent(String.self, forKey: .recipient)
        keyExchange = try container.decodeIfPresent(DirectCallMatrixKeyExchangeContent.self, forKey: .keyExchange)?.payload
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(callID, forKey: .callID)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(intent, forKey: .intent)
        try container.encodeIfPresent(recipient, forKey: .recipient)
        try container.encodeIfPresent(keyExchange.map(DirectCallMatrixKeyExchangeContent.init), forKey: .keyExchange)
    }
}

struct DirectCallMatrixSignalEnvelope: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let eventID: String
    let roomID: String
    let senderUserID: String
    let ownUserID: String
    let isDirectOneToOneRoom: Bool?
    let isEncryptedRoom: Bool?
    let timestamp: Date
    let rawContent: String

    init(eventID: String,
         roomID: String,
         senderUserID: String,
         ownUserID: String,
         isDirectOneToOneRoom: Bool? = nil,
         isEncryptedRoom: Bool? = nil,
         timestamp: Date,
         rawContent: String) {
        self.eventID = eventID
        self.roomID = roomID
        self.senderUserID = senderUserID
        self.ownUserID = ownUserID
        self.isDirectOneToOneRoom = isDirectOneToOneRoom
        self.isEncryptedRoom = isEncryptedRoom
        self.timestamp = timestamp
        self.rawContent = rawContent
    }

    var description: String {
        "DirectCallMatrixSignalEnvelope(" + [
            "eventID: \(eventID)",
            "roomID: \(roomID)",
            "senderUserID: \(senderUserID)",
            "ownUserID: \(ownUserID)",
            "isDirectOneToOneRoom: \(String(describing: isDirectOneToOneRoom))",
            "isEncryptedRoom: \(String(describing: isEncryptedRoom))",
            "timestamp: \(timestamp)",
            "rawContent: <redacted>"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

enum DirectCallMatrixSignalCodec {
    static let eventType = "kz.salemx.direct_call.signal"

    static func encode(_ signal: DirectCallOutgoingSignal,
                       encoder: JSONEncoder = JSONEncoder()) -> String? {
        let content = DirectCallMatrixSignalContent(signal: signal)
        guard isValidOutgoingContent(content, roomID: signal.roomID),
              let data = try? encoder.encode(content) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func decode(_ envelope: DirectCallMatrixSignalEnvelope,
                       decoder: JSONDecoder = JSONDecoder()) -> DirectCallSignalEvent? {
        guard isValidEnvelope(envelope),
              let data = envelope.rawContent.data(using: .utf8),
              let content = try? decoder.decode(DirectCallMatrixSignalContent.self, from: data),
              let type = DirectCallSignalType(rawValue: content.type) else {
            return nil
        }

        let intent = DirectCallIntent.parse(content.intent)
        guard content.intent == nil || intent != nil,
              isValidIncomingContent(content, type: type, intent: intent, envelope: envelope) else {
            return nil
        }

        return DirectCallSignalEvent(eventID: envelope.eventID,
                                     roomID: envelope.roomID,
                                     senderID: envelope.senderUserID,
                                     callID: content.callID,
                                     type: type,
                                     intent: intent,
                                     timestamp: envelope.timestamp,
                                     keyExchange: content.keyExchange)
    }

    private static func isValidEnvelope(_ envelope: DirectCallMatrixSignalEnvelope) -> Bool {
        guard !envelope.eventID.isEmpty,
              !envelope.roomID.isEmpty,
              !envelope.senderUserID.isEmpty,
              !envelope.ownUserID.isEmpty,
              envelope.senderUserID != envelope.ownUserID else {
            return false
        }

        if envelope.isDirectOneToOneRoom == false {
            return false
        }

        if envelope.isEncryptedRoom == false {
            return false
        }

        return true
    }

    private static func isValidOutgoingContent(_ content: DirectCallMatrixSignalContent, roomID: String) -> Bool {
        guard content.version == DirectCallMatrixSignalContent.currentVersion,
              !roomID.isEmpty,
              !content.callID.isEmpty,
              !content.type.isEmpty,
              content.recipient?.isEmpty == false,
              let type = DirectCallSignalType(rawValue: content.type) else {
            return false
        }

        switch type {
        case .invite:
            guard content.intent == DirectCallIntent.audio.rawValue,
                  let keyExchange = content.keyExchange else {
                return false
            }
            return keyExchange.callID == content.callID && keyExchange.roomID == roomID
        case .answer, .reject, .cancel, .hangup, .timeout:
            return true
        }
    }

    private static func isValidIncomingContent(_ content: DirectCallMatrixSignalContent,
                                               type: DirectCallSignalType,
                                               intent: DirectCallIntent?,
                                               envelope: DirectCallMatrixSignalEnvelope) -> Bool {
        guard content.version == DirectCallMatrixSignalContent.currentVersion,
              !content.callID.isEmpty else {
            return false
        }

        if let recipient = content.recipient, recipient != envelope.ownUserID {
            return false
        }

        switch type {
        case .invite:
            guard intent == .audio,
                  let keyExchange = content.keyExchange else {
                return false
            }

            return keyExchange.callID == content.callID &&
                keyExchange.roomID == envelope.roomID &&
                keyExchange.senderUserID == envelope.senderUserID
        case .answer, .reject, .cancel, .hangup, .timeout:
            return content.keyExchange == nil
        }
    }
}

enum DirectCallMatrixSignalTransportError: Error, Equatable {
    case invalidSignal
    case sendFailed
}

@MainActor
protocol DirectCallMatrixRawSignalSending {
    func sendDirectCallSignal(roomID: String, eventType: String, content: String) async -> Result<Void, DirectCallMatrixSignalTransportError>
}

@MainActor
protocol DirectCallMatrixRawRoomSending {
    func sendRaw(eventType: String, content: String) async throws
}

@MainActor
final class DirectCallMatrixRoomRawSignalSender: DirectCallMatrixRawSignalSending {
    private let roomID: String
    private let room: DirectCallMatrixRawRoomSending

    init(roomID: String, room: DirectCallMatrixRawRoomSending) {
        self.roomID = roomID
        self.room = room
    }

    convenience init(roomID: String, room: RoomProtocol) {
        self.init(roomID: roomID, room: DirectCallMatrixSDKRawRoom(room: room))
    }

    func sendDirectCallSignal(roomID: String, eventType: String, content: String) async -> Result<Void, DirectCallMatrixSignalTransportError> {
        guard !self.roomID.isEmpty,
              roomID == self.roomID,
              eventType == DirectCallMatrixSignalCodec.eventType,
              !content.isEmpty else {
            return .failure(.invalidSignal)
        }

        do {
            try await room.sendRaw(eventType: DirectCallMatrixSignalCodec.eventType, content: content)
            return .success(())
        } catch {
            return .failure(.sendFailed)
        }
    }
}

@MainActor
final class DirectCallMatrixSignalTransport {
    private let rawSender: DirectCallMatrixRawSignalSending

    init(rawSender: DirectCallMatrixRawSignalSending) {
        self.rawSender = rawSender
    }

    func send(_ signal: DirectCallOutgoingSignal) async -> Result<Void, DirectCallMatrixSignalTransportError> {
        guard let content = DirectCallMatrixSignalCodec.encode(signal) else {
            return .failure(.invalidSignal)
        }

        return await rawSender.sendDirectCallSignal(roomID: signal.roomID,
                                                    eventType: DirectCallMatrixSignalCodec.eventType,
                                                    content: content)
    }
}

@MainActor
final class DirectCallMatrixSignalReceiver {
    private let onSignal: (DirectCallSignalEvent) -> Void

    init(onSignal: @escaping (DirectCallSignalEvent) -> Void) {
        self.onSignal = onSignal
    }

    func receive(_ envelope: DirectCallMatrixSignalEnvelope) {
        guard let event = DirectCallMatrixSignalCodec.decode(envelope) else {
            return
        }

        onSignal(event)
    }
}

private struct DirectCallMatrixSDKRawRoom: DirectCallMatrixRawRoomSending {
    let room: RoomProtocol

    func sendRaw(eventType: String, content: String) async throws {
        try await room.sendRaw(eventType: eventType, content: content)
    }
}

private struct DirectCallMatrixKeyExchangeContent: Codable, Equatable {
    let callID: String
    let roomID: String
    let senderUserID: String
    let keyID: String
    let encryptedPayload: String

    init(_ payload: DirectCallEncryptedKeyExchangePayload) {
        callID = payload.callID
        roomID = payload.roomID
        senderUserID = payload.senderUserID
        keyID = payload.keyID
        encryptedPayload = payload.encryptedPayload
    }

    var payload: DirectCallEncryptedKeyExchangePayload {
        .init(callID: callID,
              roomID: roomID,
              senderUserID: senderUserID,
              keyID: keyID,
              encryptedPayload: encryptedPayload)
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case roomID = "room_id"
        case senderUserID = "sender_user_id"
        case keyID = "key_id"
        case encryptedPayload = "encrypted_payload"
    }
}

@MainActor
protocol DirectCallSignalTransportProtocol {
    func send(_ signal: DirectCallOutgoingSignal, from senderID: String)
    func signalsPublisher(for recipientUserID: String) -> AnyPublisher<DirectCallSignalEvent, Never>
    func detachSignalsPublisher(for recipientUserID: String)
}

/// DEV/TEST ONLY.
/// This transport is in-memory and must never be used as production signalling transport.
@MainActor
final class InMemoryDirectCallSignalTransport: DirectCallSignalTransportProtocol {
    static let shared = InMemoryDirectCallSignalTransport()

    private let now: () -> Date
    private let eventIDProvider: () -> String

    private var subjectsByRecipient = [String: PassthroughSubject<DirectCallSignalEvent, Never>]()

    init(now: @escaping () -> Date = Date.init,
         eventIDProvider: @escaping () -> String = { UUID().uuidString }) {
        self.now = now
        self.eventIDProvider = eventIDProvider
    }

    func send(_ signal: DirectCallOutgoingSignal, from senderID: String) {
        guard !signal.callID.isEmpty,
              !signal.roomID.isEmpty,
              !senderID.isEmpty,
              !signal.peerUserID.isEmpty,
              let recipientSubject = subjectsByRecipient[signal.peerUserID] else {
            return
        }

        let event = DirectCallSignalEvent(eventID: eventIDProvider(),
                                          roomID: signal.roomID,
                                          senderID: senderID,
                                          callID: signal.callID,
                                          type: signal.type,
                                          intent: signal.intent,
                                          timestamp: now(),
                                          keyExchange: signal.keyExchange)
        recipientSubject.send(event)
    }

    func signalsPublisher(for recipientUserID: String) -> AnyPublisher<DirectCallSignalEvent, Never> {
        guard !recipientUserID.isEmpty else {
            return Empty<DirectCallSignalEvent, Never>(completeImmediately: false).eraseToAnyPublisher()
        }
        return subject(for: recipientUserID).eraseToAnyPublisher()
    }

    func detachSignalsPublisher(for recipientUserID: String) {
        guard !recipientUserID.isEmpty else {
            return
        }
        subjectsByRecipient.removeValue(forKey: recipientUserID)
    }

    func reset() {
        subjectsByRecipient.removeAll()
    }

    private func subject(for recipientUserID: String) -> PassthroughSubject<DirectCallSignalEvent, Never> {
        if let existing = subjectsByRecipient[recipientUserID] {
            return existing
        }

        let subject = PassthroughSubject<DirectCallSignalEvent, Never>()
        subjectsByRecipient[recipientUserID] = subject
        return subject
    }
}

@MainActor
final class DirectCallEngineSignalBridge {
    private let ownUserID: String
    private let engine: DirectCallEngineProtocol
    private let signalTransport: DirectCallSignalTransportProtocol

    private var cancellables = Set<AnyCancellable>()

    init(ownUserID: String,
         engine: DirectCallEngineProtocol,
         signalTransport: DirectCallSignalTransportProtocol) {
        self.ownUserID = ownUserID
        self.engine = engine
        self.signalTransport = signalTransport

        subscribeToOutgoingSignals()
        subscribeToIncomingSignals()
    }

    deinit {
        let recipientUserID = ownUserID
        let signalTransport = signalTransport
        Task { @MainActor in
            signalTransport.detachSignalsPublisher(for: recipientUserID)
        }
    }

    private func subscribeToOutgoingSignals() {
        engine.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                guard case .emitSignal(let signal) = action else {
                    return
                }

                signalTransport.send(signal, from: ownUserID)
            }
            .store(in: &cancellables)
    }

    private func subscribeToIncomingSignals() {
        signalTransport.signalsPublisher(for: ownUserID)
            .sink { [weak self] signalEvent in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await engine.receiveIncomingCall(event: signalEvent)
                }
            }
            .store(in: &cancellables)
    }
}
