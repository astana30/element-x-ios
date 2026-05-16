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

    #if DEBUG
    static func diagnosticReceiveEventKind(_ envelope: DirectCallMatrixSignalEnvelope,
                                           decoder: JSONDecoder = JSONDecoder()) -> DirectCallDiagnosticReceiveEventKind {
        guard let data = envelope.rawContent.data(using: .utf8),
              let content = try? decoder.decode(DirectCallMatrixSignalContent.self, from: data),
              let type = DirectCallSignalType(rawValue: content.type) else {
            return .malformed
        }

        return .init(type)
    }

    static func diagnosticRejectionReason(_ envelope: DirectCallMatrixSignalEnvelope,
                                          decoder: JSONDecoder = JSONDecoder()) -> DirectCallDiagnosticEnvelopeRejectedReason? {
        guard !envelope.eventID.isEmpty else {
            return .missingEventID
        }

        guard !envelope.roomID.isEmpty, !envelope.ownUserID.isEmpty else {
            return .metadataUnavailable
        }

        guard !envelope.senderUserID.isEmpty else {
            return .missingSender
        }

        guard envelope.senderUserID != envelope.ownUserID else {
            return .ownEvent
        }

        if envelope.isDirectOneToOneRoom == false || envelope.isEncryptedRoom == false {
            return .metadataUnavailable
        }

        guard let data = envelope.rawContent.data(using: .utf8),
              let content = try? decoder.decode(DirectCallMatrixSignalContent.self, from: data) else {
            return .decodeFailed
        }

        guard let type = DirectCallSignalType(rawValue: content.type) else {
            return .unsupportedEvent
        }

        let intent = DirectCallIntent.parse(content.intent)
        guard content.intent == nil || intent != nil else {
            return .decodeFailed
        }

        if let recipient = content.recipient, recipient != envelope.ownUserID {
            return .peerMismatch
        }

        return isValidIncomingContent(content, type: type, intent: intent, envelope: envelope) ? nil : .decodeFailed
    }
    #endif

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
                && (keyExchange.recipientUserID == nil || keyExchange.recipientUserID == content.recipient)
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
                keyExchange.senderUserID == envelope.senderUserID &&
                (keyExchange.recipientUserID == nil || keyExchange.recipientUserID == envelope.ownUserID)
        case .answer, .reject, .cancel, .hangup, .timeout:
            return content.keyExchange == nil
        }
    }
}

enum DirectCallMatrixSignalTransportError: Error, Equatable {
    case invalidSignal
    case sendFailed
}

#if DEBUG
extension DirectCallDiagnosticSignalSendFailureReason {
    init(_ error: DirectCallMatrixSignalTransportError) {
        switch error {
        case .invalidSignal:
            self = .invalidSignal
        case .sendFailed:
            self = .sendFailed
        }
    }
}
#endif

@MainActor
protocol DirectCallMatrixRawSignalSending {
    func sendDirectCallSignal(roomID: String, eventType: String, content: String) async -> Result<Void, DirectCallMatrixSignalTransportError>
}

@MainActor
protocol DirectCallMatrixRawRoomSending {
    func sendRaw(eventType: String, content: String) async throws
}

@MainActor
protocol DirectCallMatrixSignalListeningHandle {
    func cancel()
}

@MainActor
protocol DirectCallMatrixTimelineSignalListening {
    func start(onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) async -> DirectCallMatrixSignalListeningHandle
}

#if DEBUG
@MainActor
protocol DirectCallMatrixTimelineSignalDiagnosticsProviding {
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot { get }
}
#endif

struct DirectCallMatrixTimelineSignalMetadata: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let eventID: String
    let roomID: String
    let senderUserID: String
    let ownUserID: String
    let isDirectOneToOneRoom: Bool?
    let isEncryptedRoom: Bool?
    let timestamp: Date

    var description: String {
        "DirectCallMatrixTimelineSignalMetadata(" + [
            "eventID: \(eventID)",
            "roomID: \(roomID)",
            "senderUserID: \(senderUserID)",
            "ownUserID: \(ownUserID)",
            "isDirectOneToOneRoom: \(String(describing: isDirectOneToOneRoom))",
            "isEncryptedRoom: \(String(describing: isEncryptedRoom))",
            "timestamp: \(timestamp)"
        ].joined(separator: ", ") + ")"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol DirectCallMatrixTimelineItemEnvelopeExtracting {
    func envelope(from metadata: DirectCallMatrixTimelineSignalMetadata, eventItem: EventTimelineItem) -> DirectCallMatrixSignalEnvelope?
}

#if DEBUG
struct DirectCallMatrixTimelineItemEnvelopeDiagnosticResult: Equatable {
    let envelope: DirectCallMatrixSignalEnvelope?
    let eventKind: DirectCallDiagnosticReceiveEventKind
    let rejectionReason: DirectCallDiagnosticEnvelopeRejectedReason
}

@MainActor
protocol DirectCallMatrixTimelineItemEnvelopeDiagnosing {
    func diagnosticEnvelope(from metadata: DirectCallMatrixTimelineSignalMetadata,
                            eventItem: EventTimelineItem) -> DirectCallMatrixTimelineItemEnvelopeDiagnosticResult
}
#endif

/// Keep the production receive path fail-closed when the SDK cannot provide a safe custom event content body.
@MainActor
struct DirectCallMatrixFailClosedTimelineItemEnvelopeExtractor: DirectCallMatrixTimelineItemEnvelopeExtracting {
    func envelope(from metadata: DirectCallMatrixTimelineSignalMetadata, eventItem: EventTimelineItem) -> DirectCallMatrixSignalEnvelope? {
        nil
    }
}

@MainActor
struct DirectCallMatrixSDKTimelineItemEnvelopeExtractor: DirectCallMatrixTimelineItemEnvelopeExtracting {
    func envelope(from metadata: DirectCallMatrixTimelineSignalMetadata, eventItem: EventTimelineItem) -> DirectCallMatrixSignalEnvelope? {
        makeEnvelope(from: metadata, eventItem: eventItem)
    }

    private func makeEnvelope(from metadata: DirectCallMatrixTimelineSignalMetadata, eventItem: EventTimelineItem) -> DirectCallMatrixSignalEnvelope? {
        guard let customContent = eventItem.lazyProvider.messageLikeCustomContent(),
              customContent.eventType == DirectCallMatrixSignalCodec.eventType,
              !customContent.contentJson.isEmpty else {
            return nil
        }

        return .init(eventID: metadata.eventID,
                     roomID: metadata.roomID,
                     senderUserID: metadata.senderUserID,
                     ownUserID: metadata.ownUserID,
                     isDirectOneToOneRoom: metadata.isDirectOneToOneRoom,
                     isEncryptedRoom: metadata.isEncryptedRoom,
                     timestamp: metadata.timestamp,
                     rawContent: customContent.contentJson)
    }
}

#if DEBUG
extension DirectCallMatrixSDKTimelineItemEnvelopeExtractor: DirectCallMatrixTimelineItemEnvelopeDiagnosing {
    func diagnosticEnvelope(from metadata: DirectCallMatrixTimelineSignalMetadata,
                            eventItem: EventTimelineItem) -> DirectCallMatrixTimelineItemEnvelopeDiagnosticResult {
        guard let customContent = eventItem.lazyProvider.messageLikeCustomContent() else {
            return .init(envelope: nil, eventKind: .unknown, rejectionReason: .contentUnavailable)
        }

        guard customContent.eventType == DirectCallMatrixSignalCodec.eventType else {
            return .init(envelope: nil, eventKind: .nonDirectCallEvent, rejectionReason: .wrongEventType)
        }

        guard !customContent.contentJson.isEmpty else {
            return .init(envelope: nil, eventKind: .malformed, rejectionReason: .contentUnavailable)
        }

        let envelope = DirectCallMatrixSignalEnvelope(eventID: metadata.eventID,
                                                      roomID: metadata.roomID,
                                                      senderUserID: metadata.senderUserID,
                                                      ownUserID: metadata.ownUserID,
                                                      isDirectOneToOneRoom: metadata.isDirectOneToOneRoom,
                                                      isEncryptedRoom: metadata.isEncryptedRoom,
                                                      timestamp: metadata.timestamp,
                                                      rawContent: customContent.contentJson)
        return .init(envelope: envelope,
                     eventKind: DirectCallMatrixSignalCodec.diagnosticReceiveEventKind(envelope),
                     rejectionReason: .none)
    }
}
#endif

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
final class DirectCallMatrixSDKTimelineSignalListener: DirectCallMatrixTimelineSignalListening {
    private let timeline: TimelineProtocol
    private let roomID: String
    private let ownUserID: String
    private let isDirectOneToOneRoom: () -> Bool?
    private let isEncryptedRoom: () -> Bool?
    private let envelopeExtractor: DirectCallMatrixTimelineItemEnvelopeExtracting
    private var historicalDirectCallEventIDs = Set<String>()
    private var deliveredDirectCallEventIDs = Set<String>()

    #if DEBUG
    private var diagnosticState = DirectCallDiagnosticSnapshot()

    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        diagnosticState
    }
    #endif

    init(timeline: TimelineProtocol,
         roomID: String,
         ownUserID: String,
         isDirectOneToOneRoom: @escaping () -> Bool?,
         isEncryptedRoom: @escaping () -> Bool?,
         envelopeExtractor: DirectCallMatrixTimelineItemEnvelopeExtracting? = nil) {
        self.timeline = timeline
        self.roomID = roomID
        self.ownUserID = ownUserID
        self.isDirectOneToOneRoom = isDirectOneToOneRoom
        self.isEncryptedRoom = isEncryptedRoom
        self.envelopeExtractor = envelopeExtractor ?? DirectCallMatrixSDKTimelineItemEnvelopeExtractor()
    }

    func start(onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) async -> DirectCallMatrixSignalListeningHandle {
        historicalDirectCallEventIDs.removeAll()
        deliveredDirectCallEventIDs.removeAll()

        #if DEBUG
        diagnosticState.receiveRoomFingerprint = DirectCallDiagnosticRedactor.roomFingerprint(roomID)
        diagnosticState.baselineEstablished = false
        #endif

        let handle = await timeline.addListener(listener: SDKListener { [weak self] diffs in
            Task { @MainActor [weak self] in
                self?.process(diffs, onEnvelope: onEnvelope)
            }
        })
        return DirectCallMatrixSDKSignalListeningHandle(handle: handle)
    }

    private func process(_ diffs: [TimelineDiff], onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) {
        #if DEBUG
        recordTimelineUpdate(diffs)
        #endif

        for observation in Self.timelineItemObservations(from: diffs) {
            process(observation, onEnvelope: onEnvelope)
        }
    }

    private func process(_ observation: TimelineItemObservation, onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) {
        #if DEBUG
        if processDiagnosticObservation(observation, onEnvelope: onEnvelope) {
            return
        }
        #endif

        processFallbackObservation(observation, onEnvelope: onEnvelope)
    }

    #if DEBUG
    private func recordTimelineUpdate(_ diffs: [TimelineDiff]) {
        diagnosticState.timelineUpdateCount += 1
        diagnosticState.timelineDiffReceivedCount += diffs.count
        diagnosticState.lastTimelineDiffKind = Self.diagnosticTimelineDiffKind(from: diffs)
        diagnosticState.lastTimelineDiffItemCount = Self.timelineItems(from: diffs).count
        diagnosticState.baselineEstablished = true
    }

    private func processDiagnosticObservation(_ observation: TimelineItemObservation,
                                              onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) -> Bool {
        let item = observation.item
        guard let eventItem = item.asEvent() else {
            recordReceive(kind: .nonEventTimelineItem, rejectionReason: .unsupportedEvent)
            return true
        }

        diagnosticState.timelineEventReceivedCount += 1
        let isDirectCallSignalContent = Self.isDirectCallSignalContent(eventItem.content)
        if isDirectCallSignalContent {
            diagnosticState.directCallEventTypeSeenCount += 1
        }

        if ignoreHistoricalBacklogIfNeeded(eventItem,
                                           isDirectCallSignalContent: isDirectCallSignalContent,
                                           isHistoricalBacklog: observation.isHistoricalBacklog) {
            return true
        }

        if let rejectionReason = Self.diagnosticMetadataRejectionReason(from: eventItem,
                                                                        roomID: roomID,
                                                                        ownUserID: ownUserID,
                                                                        isDirectCallSignalContent: isDirectCallSignalContent) {
            recordReceive(kind: Self.diagnosticEventKind(from: eventItem.content), rejectionReason: rejectionReason)
            return true
        }

        guard let metadata = Self.metadata(from: eventItem,
                                           roomID: roomID,
                                           ownUserID: ownUserID,
                                           isDirectOneToOneRoom: isDirectOneToOneRoom(),
                                           isEncryptedRoom: isEncryptedRoom()) else {
            recordReceive(kind: Self.diagnosticEventKind(from: eventItem.content), rejectionReason: .metadataUnavailable)
            return true
        }

        guard let diagnosticExtractor = envelopeExtractor as? DirectCallMatrixTimelineItemEnvelopeDiagnosing else {
            return false
        }

        let result = diagnosticExtractor.diagnosticEnvelope(from: metadata, eventItem: eventItem)
        guard let envelope = result.envelope else {
            recordReceive(kind: result.eventKind, rejectionReason: result.rejectionReason)
            return true
        }

        recordDeliveredEnvelope(eventItem: eventItem, eventKind: result.eventKind)
        onEnvelope(envelope)
        return true
    }
    #endif

    private func processFallbackObservation(_ observation: TimelineItemObservation,
                                            onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) {
        guard let eventItem = observation.item.asEvent() else {
            #if DEBUG
            recordReceive(kind: .unknown, rejectionReason: .contentUnavailable)
            #endif
            return
        }

        let fallbackIsDirectCallSignalContent = Self.isDirectCallSignalContent(eventItem.content)
        if ignoreHistoricalBacklogIfNeeded(eventItem,
                                           isDirectCallSignalContent: fallbackIsDirectCallSignalContent,
                                           isHistoricalBacklog: observation.isHistoricalBacklog) {
            return
        }

        guard
            let metadata = Self.metadata(from: eventItem,
                                         roomID: roomID,
                                         ownUserID: ownUserID,
                                         isDirectOneToOneRoom: isDirectOneToOneRoom(),
                                         isEncryptedRoom: isEncryptedRoom()),
            let envelope = envelopeExtractor.envelope(from: metadata, eventItem: eventItem) else {
            #if DEBUG
            recordReceive(kind: .unknown, rejectionReason: .contentUnavailable)
            #endif
            return
        }

        #if DEBUG
        recordDeliveredEnvelope(eventItem: eventItem,
                                eventKind: DirectCallMatrixSignalCodec.diagnosticReceiveEventKind(envelope))
        #else
        if let eventID = Self.stableEventID(from: eventItem) {
            deliveredDirectCallEventIDs.insert(eventID)
        }
        #endif
        onEnvelope(envelope)
    }

    #if DEBUG
    private func recordDeliveredEnvelope(eventItem: EventTimelineItem,
                                         eventKind: DirectCallDiagnosticReceiveEventKind) {
        diagnosticState.envelopeExtractedCount += 1
        diagnosticState.liveEventDeliveredCount += 1
        recordReceive(kind: eventKind, rejectionReason: .none)
        if let eventID = Self.stableEventID(from: eventItem) {
            deliveredDirectCallEventIDs.insert(eventID)
        }
    }
    #endif

    static func metadata(from eventItem: EventTimelineItem,
                         roomID: String,
                         ownUserID: String,
                         isDirectOneToOneRoom: Bool?,
                         isEncryptedRoom: Bool?) -> DirectCallMatrixTimelineSignalMetadata? {
        guard !roomID.isEmpty,
              !ownUserID.isEmpty,
              eventItem.isOwn == false,
              isDirectCallSignalContent(eventItem.content),
              let eventID = stableEventID(from: eventItem) else {
            return nil
        }

        return .init(eventID: eventID,
                     roomID: roomID,
                     senderUserID: eventItem.sender,
                     ownUserID: ownUserID,
                     isDirectOneToOneRoom: isDirectOneToOneRoom,
                     isEncryptedRoom: isEncryptedRoom,
                     timestamp: Date(timeIntervalSince1970: TimeInterval(eventItem.timestamp / 1000)))
    }

    static func timelineItems(from diffs: [TimelineDiff]) -> [TimelineItem] {
        timelineItemObservations(from: diffs).map(\.item)
    }

    private static func timelineItemObservations(from diffs: [TimelineDiff]) -> [TimelineItemObservation] {
        var items = [TimelineItemObservation]()
        for diff in diffs {
            switch diff {
            case .append(let values):
                items.append(contentsOf: values.map { TimelineItemObservation(item: $0, isHistoricalBacklog: false) })
            case .reset(let values):
                items.append(contentsOf: values.map { TimelineItemObservation(item: $0, isHistoricalBacklog: true) })
            case .pushBack(let value):
                items.append(TimelineItemObservation(item: value, isHistoricalBacklog: false))
            case .pushFront(let value), .insert(_, let value), .set(_, let value):
                items.append(TimelineItemObservation(item: value, isHistoricalBacklog: true))
            case .clear, .popFront, .popBack, .remove, .truncate:
                break
            }
        }
        return items
    }

    private struct TimelineItemObservation {
        let item: TimelineItem
        let isHistoricalBacklog: Bool
    }

    private func ignoreHistoricalBacklogIfNeeded(_ eventItem: EventTimelineItem,
                                                 isDirectCallSignalContent: Bool,
                                                 isHistoricalBacklog: Bool) -> Bool {
        guard isDirectCallSignalContent else {
            return false
        }

        let eventID = Self.stableEventID(from: eventItem)
        if let eventID, deliveredDirectCallEventIDs.contains(eventID) {
            #if DEBUG
            recordReceive(kind: Self.diagnosticEventKind(from: eventItem.content), rejectionReason: .duplicateEventID)
            #endif
            return true
        }

        if isHistoricalBacklog {
            if let eventID {
                historicalDirectCallEventIDs.insert(eventID)
            }
            #if DEBUG
            diagnosticState.historicalEventIgnoredCount += 1
            recordReceive(kind: Self.diagnosticEventKind(from: eventItem.content), rejectionReason: .historicalBacklog)
            #endif
            return true
        }

        if let eventID, historicalDirectCallEventIDs.contains(eventID) {
            #if DEBUG
            diagnosticState.historicalEventIgnoredCount += 1
            recordReceive(kind: Self.diagnosticEventKind(from: eventItem.content), rejectionReason: .historicalBacklog)
            #endif
            return true
        }

        return false
    }

    #if DEBUG
    private static func diagnosticTimelineDiffKind(from diffs: [TimelineDiff]) -> DirectCallDiagnosticTimelineDiffKind {
        guard let firstDiff = diffs.first else {
            return .none
        }

        guard diffs.count == 1 else {
            return .mixed
        }

        switch firstDiff {
        case .append:
            return .append
        case .clear:
            return .clear
        case .insert:
            return .insert
        case .set:
            return .set
        case .remove:
            return .remove
        case .pushBack:
            return .pushBack
        case .pushFront:
            return .pushFront
        case .popBack:
            return .popBack
        case .popFront:
            return .popFront
        case .truncate:
            return .truncate
        case .reset:
            return .reset
        }
    }
    #endif

    fileprivate static func stableEventID(from eventItem: EventTimelineItem) -> String? {
        guard case .eventID(let eventID) = TimelineItemIdentifier.EventOrTransactionID(rustValue: eventItem.eventOrTransactionId) else {
            return nil
        }

        return eventID.isEmpty ? nil : eventID
    }

    fileprivate static func isDirectCallSignalContent(_ content: TimelineItemContent) -> Bool {
        switch content {
        case .msgLike(let content):
            guard case .other(let eventType) = content.kind else {
                return false
            }

            return isDirectCallSignalEventType(eventType)
        case .failedToParseMessageLike(let eventType, _):
            return eventType == DirectCallMatrixSignalCodec.eventType
        case .callInvite, .rtcNotification, .roomMembership, .profileChange, .state, .failedToParseState, .liveLocation:
            return false
        }
    }

    fileprivate static func isDirectCallSignalEventType(_ eventType: MessageLikeEventType) -> Bool {
        guard case .other(let eventType) = eventType else {
            return false
        }

        return eventType == DirectCallMatrixSignalCodec.eventType
    }

    #if DEBUG
    private func recordReceive(kind: DirectCallDiagnosticReceiveEventKind,
                               rejectionReason: DirectCallDiagnosticEnvelopeRejectedReason) {
        diagnosticState.lastReceiveEventKind = kind
        diagnosticState.lastEnvelopeRejectedReason = rejectionReason
    }

    fileprivate static func diagnosticMetadataRejectionReason(from eventItem: EventTimelineItem,
                                                              roomID: String,
                                                              ownUserID: String,
                                                              isDirectCallSignalContent: Bool) -> DirectCallDiagnosticEnvelopeRejectedReason? {
        guard !roomID.isEmpty, !ownUserID.isEmpty else {
            return .metadataUnavailable
        }

        guard isDirectCallSignalContent else {
            return diagnosticEventKind(from: eventItem.content) == .nonMessageLike ? .unsupportedEvent : .wrongEventType
        }

        guard eventItem.isOwn == false else {
            return .ownEvent
        }

        guard stableEventID(from: eventItem) != nil else {
            return .missingEventID
        }

        guard !eventItem.sender.isEmpty else {
            return .missingSender
        }

        return nil
    }

    fileprivate static func diagnosticEventKind(from content: TimelineItemContent?) -> DirectCallDiagnosticReceiveEventKind {
        guard let content else {
            return .unknown
        }

        switch content {
        case .msgLike(let content):
            guard case .other(let eventType) = content.kind else {
                return .nonDirectCallEvent
            }

            return isDirectCallSignalEventType(eventType) ? .unknown : .nonDirectCallEvent
        case .failedToParseMessageLike(let eventType, _):
            return eventType == DirectCallMatrixSignalCodec.eventType ? .malformed : .nonDirectCallEvent
        case .callInvite, .rtcNotification, .roomMembership, .profileChange, .state, .failedToParseState, .liveLocation:
            return .nonMessageLike
        }
    }
    #endif
}

#if DEBUG
extension DirectCallMatrixSDKTimelineSignalListener: DirectCallMatrixTimelineSignalDiagnosticsProviding { }
#endif

@MainActor
final class DirectCallMatrixLazySDKTimelineSignalListener: DirectCallMatrixTimelineSignalListening {
    private let timelineFactory: () async throws -> TimelineProtocol
    private let roomID: String
    private let ownUserID: String
    private let isDirectOneToOneRoom: () -> Bool?
    private let isEncryptedRoom: () -> Bool?
    private let envelopeExtractor: DirectCallMatrixTimelineItemEnvelopeExtracting?

    private var listener: DirectCallMatrixSDKTimelineSignalListener?
    private var handle: DirectCallMatrixSignalListeningHandle?

    #if DEBUG
    private var diagnosticState = DirectCallDiagnosticSnapshot()

    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        var snapshot = diagnosticState
        if let listener {
            snapshot.mergeReceiveDiagnostics(from: listener.diagnosticSnapshot)
        }
        return snapshot
    }
    #endif

    init(timelineFactory: @escaping () async throws -> TimelineProtocol,
         roomID: String,
         ownUserID: String,
         isDirectOneToOneRoom: @escaping () -> Bool?,
         isEncryptedRoom: @escaping () -> Bool?,
         envelopeExtractor: DirectCallMatrixTimelineItemEnvelopeExtracting? = nil) {
        self.timelineFactory = timelineFactory
        self.roomID = roomID
        self.ownUserID = ownUserID
        self.isDirectOneToOneRoom = isDirectOneToOneRoom
        self.isEncryptedRoom = isEncryptedRoom
        self.envelopeExtractor = envelopeExtractor
    }

    func start(onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) async -> DirectCallMatrixSignalListeningHandle {
        #if DEBUG
        diagnosticState.receiveRoomFingerprint = DirectCallDiagnosticRedactor.roomFingerprint(roomID)
        #endif

        do {
            let timeline = try await timelineFactory()
            let listener = DirectCallMatrixSDKTimelineSignalListener(timeline: timeline,
                                                                     roomID: roomID,
                                                                     ownUserID: ownUserID,
                                                                     isDirectOneToOneRoom: isDirectOneToOneRoom,
                                                                     isEncryptedRoom: isEncryptedRoom,
                                                                     envelopeExtractor: envelopeExtractor)
            let handle = await listener.start(onEnvelope: onEnvelope)
            self.listener = listener
            self.handle = handle

            return DirectCallMatrixCancellableSignalListeningHandle { [weak self] in
                self?.handle?.cancel()
                self?.handle = nil
                self?.listener = nil
            }
        } catch {
            return DirectCallMatrixCancellableSignalListeningHandle { }
        }
    }
}

#if DEBUG
extension DirectCallMatrixLazySDKTimelineSignalListener: DirectCallMatrixTimelineSignalDiagnosticsProviding { }
#endif

@MainActor
final class DirectCallMatrixTimelineItemProviderSignalListener: DirectCallMatrixTimelineSignalListening {
    private let timelineItemProvider: TimelineItemProviderProtocol
    private let roomID: String
    private let ownUserID: String
    private let isDirectOneToOneRoom: () -> Bool?
    private let isEncryptedRoom: () -> Bool?
    private let envelopeExtractor: DirectCallMatrixTimelineItemEnvelopeExtracting

    private var cancellable: AnyCancellable?
    private var processedNonDirectEventIDs = Set<String>()
    private var historicalDirectCallEventIDs = Set<String>()
    private var deliveredDirectCallEventIDs = Set<String>()
    private var baselineEstablished = false

    #if DEBUG
    private var diagnosticState = DirectCallDiagnosticSnapshot()

    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        diagnosticState
    }
    #endif

    init(timelineItemProvider: TimelineItemProviderProtocol,
         roomID: String,
         ownUserID: String,
         isDirectOneToOneRoom: @escaping () -> Bool?,
         isEncryptedRoom: @escaping () -> Bool?,
         envelopeExtractor: DirectCallMatrixTimelineItemEnvelopeExtracting? = nil) {
        self.timelineItemProvider = timelineItemProvider
        self.roomID = roomID
        self.ownUserID = ownUserID
        self.isDirectOneToOneRoom = isDirectOneToOneRoom
        self.isEncryptedRoom = isEncryptedRoom
        self.envelopeExtractor = envelopeExtractor ?? DirectCallMatrixSDKTimelineItemEnvelopeExtractor()
    }

    func start(onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) async -> DirectCallMatrixSignalListeningHandle {
        #if DEBUG
        diagnosticState.receiveRoomFingerprint = DirectCallDiagnosticRedactor.roomFingerprint(roomID)
        #endif

        cancellable?.cancel()
        processedNonDirectEventIDs.removeAll()
        historicalDirectCallEventIDs.removeAll()
        deliveredDirectCallEventIDs.removeAll()
        baselineEstablished = false
        #if DEBUG
        diagnosticState.baselineEstablished = false
        #endif

        cancellable = timelineItemProvider.updatePublisher
            .sink { [weak self] itemProxies, _ in
                Task { @MainActor [weak self] in
                    self?.process(itemProxies, onEnvelope: onEnvelope)
                }
            }

        return DirectCallMatrixCancellableSignalListeningHandle { [weak self] in
            self?.cancellable?.cancel()
            self?.cancellable = nil
        }
    }

    private func process(_ itemProxies: [TimelineItemProxy],
                         onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) {
        let isBaselineUpdate = baselineEstablished == false
        baselineEstablished = true

        #if DEBUG
        diagnosticState.timelineUpdateCount += 1
        diagnosticState.timelineDiffReceivedCount += 1
        diagnosticState.lastTimelineDiffKind = .providerUpdate
        diagnosticState.lastTimelineDiffItemCount = itemProxies.count
        diagnosticState.baselineEstablished = true
        #endif

        for itemProxy in itemProxies {
            guard case .event(let eventProxy) = itemProxy else {
                #if DEBUG
                recordReceive(kind: .nonEventTimelineItem, rejectionReason: .unsupportedEvent)
                #endif
                continue
            }

            let eventItem = eventProxy.item
            let eventID = DirectCallMatrixSDKTimelineSignalListener.stableEventID(from: eventItem)
            let isDirectCallSignalContent = DirectCallMatrixSDKTimelineSignalListener.isDirectCallSignalContent(eventItem.content)

            if let eventID, !isDirectCallSignalContent, !processedNonDirectEventIDs.insert(eventID).inserted {
                continue
            }

            if process(eventItem,
                       isDirectCallSignalContent: isDirectCallSignalContent,
                       isHistoricalBacklog: isBaselineUpdate,
                       onEnvelope: onEnvelope),
                let eventID {
                deliveredDirectCallEventIDs.insert(eventID)
            }
        }
    }

    private func process(_ eventItem: EventTimelineItem,
                         isDirectCallSignalContent: Bool,
                         isHistoricalBacklog: Bool,
                         onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) -> Bool {
        #if DEBUG
        diagnosticState.timelineEventReceivedCount += 1
        if isDirectCallSignalContent {
            diagnosticState.directCallEventTypeSeenCount += 1
        }

        if ignoreHistoricalBacklogIfNeeded(eventItem,
                                           isDirectCallSignalContent: isDirectCallSignalContent,
                                           isHistoricalBacklog: isHistoricalBacklog) {
            return false
        }

        if let rejectionReason = DirectCallMatrixSDKTimelineSignalListener.diagnosticMetadataRejectionReason(from: eventItem,
                                                                                                             roomID: roomID,
                                                                                                             ownUserID: ownUserID,
                                                                                                             isDirectCallSignalContent: isDirectCallSignalContent) {
            recordReceive(kind: DirectCallMatrixSDKTimelineSignalListener.diagnosticEventKind(from: eventItem.content),
                          rejectionReason: rejectionReason)
            return false
        }

        guard let metadata = DirectCallMatrixSDKTimelineSignalListener.metadata(from: eventItem,
                                                                                roomID: roomID,
                                                                                ownUserID: ownUserID,
                                                                                isDirectOneToOneRoom: isDirectOneToOneRoom(),
                                                                                isEncryptedRoom: isEncryptedRoom()) else {
            recordReceive(kind: DirectCallMatrixSDKTimelineSignalListener.diagnosticEventKind(from: eventItem.content),
                          rejectionReason: .metadataUnavailable)
            return false
        }

        if let diagnosticExtractor = envelopeExtractor as? DirectCallMatrixTimelineItemEnvelopeDiagnosing {
            let result = diagnosticExtractor.diagnosticEnvelope(from: metadata, eventItem: eventItem)
            guard let envelope = result.envelope else {
                recordReceive(kind: result.eventKind, rejectionReason: result.rejectionReason)
                return false
            }

            diagnosticState.envelopeExtractedCount += 1
            diagnosticState.liveEventDeliveredCount += 1
            recordReceive(kind: result.eventKind, rejectionReason: .none)
            onEnvelope(envelope)
            return true
        }
        #endif

        guard let metadata = DirectCallMatrixSDKTimelineSignalListener.metadata(from: eventItem,
                                                                                roomID: roomID,
                                                                                ownUserID: ownUserID,
                                                                                isDirectOneToOneRoom: isDirectOneToOneRoom(),
                                                                                isEncryptedRoom: isEncryptedRoom()),
            let envelope = envelopeExtractor.envelope(from: metadata, eventItem: eventItem) else {
            #if DEBUG
            recordReceive(kind: .unknown, rejectionReason: .contentUnavailable)
            #endif
            return false
        }

        #if DEBUG
        diagnosticState.envelopeExtractedCount += 1
        diagnosticState.liveEventDeliveredCount += 1
        recordReceive(kind: DirectCallMatrixSignalCodec.diagnosticReceiveEventKind(envelope), rejectionReason: .none)
        #endif
        onEnvelope(envelope)
        return true
    }

    private func ignoreHistoricalBacklogIfNeeded(_ eventItem: EventTimelineItem,
                                                 isDirectCallSignalContent: Bool,
                                                 isHistoricalBacklog: Bool) -> Bool {
        guard isDirectCallSignalContent else {
            return false
        }

        let eventID = DirectCallMatrixSDKTimelineSignalListener.stableEventID(from: eventItem)
        if let eventID, deliveredDirectCallEventIDs.contains(eventID) {
            #if DEBUG
            recordReceive(kind: DirectCallMatrixSDKTimelineSignalListener.diagnosticEventKind(from: eventItem.content),
                          rejectionReason: .duplicateEventID)
            #endif
            return true
        }

        if isHistoricalBacklog {
            if let eventID {
                historicalDirectCallEventIDs.insert(eventID)
            }
            #if DEBUG
            diagnosticState.historicalEventIgnoredCount += 1
            recordReceive(kind: DirectCallMatrixSDKTimelineSignalListener.diagnosticEventKind(from: eventItem.content),
                          rejectionReason: .historicalBacklog)
            #endif
            return true
        }

        if let eventID, historicalDirectCallEventIDs.contains(eventID) {
            #if DEBUG
            diagnosticState.historicalEventIgnoredCount += 1
            recordReceive(kind: DirectCallMatrixSDKTimelineSignalListener.diagnosticEventKind(from: eventItem.content),
                          rejectionReason: .historicalBacklog)
            #endif
            return true
        }

        return false
    }

    #if DEBUG
    private func recordReceive(kind: DirectCallDiagnosticReceiveEventKind,
                               rejectionReason: DirectCallDiagnosticEnvelopeRejectedReason) {
        diagnosticState.lastReceiveEventKind = kind
        diagnosticState.lastEnvelopeRejectedReason = rejectionReason
    }
    #endif
}

#if DEBUG
extension DirectCallMatrixTimelineItemProviderSignalListener: DirectCallMatrixTimelineSignalDiagnosticsProviding { }
#endif

@MainActor
private final class DirectCallMatrixSDKSignalListeningHandle: DirectCallMatrixSignalListeningHandle {
    private let handle: TaskHandle

    init(handle: TaskHandle) {
        self.handle = handle
    }

    func cancel() {
        handle.cancel()
    }
}

@MainActor
private final class DirectCallMatrixCancellableSignalListeningHandle: DirectCallMatrixSignalListeningHandle {
    private let onCancel: @MainActor () -> Void

    init(onCancel: @escaping @MainActor () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
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

    @discardableResult
    func receive(_ envelope: DirectCallMatrixSignalEnvelope) -> DirectCallSignalEvent? {
        guard let event = DirectCallMatrixSignalCodec.decode(envelope) else {
            return nil
        }

        onSignal(event)
        return event
    }
}

@MainActor
final class MatrixDirectCallSignalTransport: DirectCallSignalTransportProtocol {
    private let ownUserID: String
    private let sender: DirectCallMatrixSignalTransport
    private let listener: DirectCallMatrixTimelineSignalListening
    private let sendResultSubject = PassthroughSubject<Result<Void, DirectCallMatrixSignalTransportError>, Never>()

    private var subject: PassthroughSubject<DirectCallSignalEvent, Never>?
    private var listenerHandle: DirectCallMatrixSignalListeningHandle?
    private var isListening = false
    private lazy var receiver = DirectCallMatrixSignalReceiver { [weak self] event in
        self?.subject?.send(event)
    }

    #if DEBUG
    private var diagnosticState = DirectCallDiagnosticSnapshot()

    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        var snapshot = diagnosticState
        if let listenerDiagnostics = listener as? DirectCallMatrixTimelineSignalDiagnosticsProviding {
            snapshot.mergeReceiveDiagnostics(from: listenerDiagnostics.diagnosticSnapshot)
        }
        return snapshot
    }
    #endif

    var sendResultsPublisher: AnyPublisher<Result<Void, DirectCallMatrixSignalTransportError>, Never> {
        sendResultSubject.eraseToAnyPublisher()
    }

    init(ownUserID: String,
         sender: DirectCallMatrixSignalTransport,
         listener: DirectCallMatrixTimelineSignalListening) {
        self.ownUserID = ownUserID
        self.sender = sender
        self.listener = listener
    }

    deinit {
        guard let listenerHandle else {
            return
        }

        Task { @MainActor in
            listenerHandle.cancel()
        }
    }

    func attach() async {
        guard !isListening else {
            return
        }

        isListening = true
        #if DEBUG
        diagnosticState.listenerAttached = true
        diagnosticState.listenerStartCount += 1
        #endif
        listenerHandle = await listener.start { [weak self] envelope in
            guard let self, isListening else {
                return
            }

            #if DEBUG
            diagnosticState.envelopeExtractedCount += 1
            diagnosticState.receiveRoomFingerprint = DirectCallDiagnosticRedactor.roomFingerprint(envelope.roomID)
            #endif
            let event = receiver.receive(envelope)
            #if DEBUG
            if let event {
                diagnosticState.lastReceiveEventKind = .init(event.type)
                diagnosticState.lastEnvelopeRejectedReason = .none
                diagnosticState.lastReceiveFailureReason = nil
            } else {
                diagnosticState.lastReceiveEventKind = DirectCallMatrixSignalCodec.diagnosticReceiveEventKind(envelope)
                diagnosticState.lastEnvelopeRejectedReason = DirectCallMatrixSignalCodec.diagnosticRejectionReason(envelope) ?? .decodeFailed
                diagnosticState.lastReceiveFailureReason = .decodeFailed
            }
            #endif
        }
        #if DEBUG
        diagnosticState.listenerHandleRetained = listenerHandle != nil
        #endif
    }

    func stop() {
        isListening = false
        #if DEBUG
        diagnosticState.listenerAttached = false
        diagnosticState.listenerHandleRetained = false
        #endif
        listenerHandle?.cancel()
        listenerHandle = nil
    }

    func send(_ signal: DirectCallOutgoingSignal, from senderID: String) {
        #if DEBUG
        diagnosticState.sendRoomFingerprint = DirectCallDiagnosticRedactor.roomFingerprint(signal.roomID)
        #endif

        guard senderID == ownUserID else {
            sendResultSubject.send(.failure(.invalidSignal))
            return
        }

        Task { @MainActor [sender, sendResultSubject] in
            let result = await sender.send(signal)
            sendResultSubject.send(result)
        }
    }

    func signalsPublisher(for recipientUserID: String) -> AnyPublisher<DirectCallSignalEvent, Never> {
        guard recipientUserID == ownUserID else {
            return Empty<DirectCallSignalEvent, Never>(completeImmediately: false).eraseToAnyPublisher()
        }

        if let subject {
            return subject.eraseToAnyPublisher()
        }

        let subject = PassthroughSubject<DirectCallSignalEvent, Never>()
        self.subject = subject
        return subject.eraseToAnyPublisher()
    }

    func detachSignalsPublisher(for recipientUserID: String) {
        guard recipientUserID == ownUserID else {
            return
        }

        subject = nil
    }
}

#if DEBUG
@MainActor
protocol DirectCallSignalTransportSendResultsProviding {
    var sendResultsPublisher: AnyPublisher<Result<Void, DirectCallMatrixSignalTransportError>, Never> { get }
}

@MainActor
protocol DirectCallSignalTransportDiagnosticSnapshotProviding {
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot { get }
}

extension MatrixDirectCallSignalTransport: DirectCallSignalTransportSendResultsProviding { }
extension MatrixDirectCallSignalTransport: DirectCallSignalTransportDiagnosticSnapshotProviding { }

extension DirectCallDiagnosticEnvelopeRejectedReason {
    init(_ error: DirectCallEngineError) {
        switch error {
        case .invalidPeer, .invalidSender:
            self = .peerMismatch
        case .invalidRoomID, .roomMismatch:
            self = .metadataUnavailable
        case .invalidCallID, .callIDMismatch, .invalidIntent:
            self = .decodeFailed
        case .staleOrUnknownEvent:
            self = .duplicateEventID
        case .sessionAlreadyActive, .invalidTransition:
            self = .unsupportedEvent
        case .invalidEncryptionTransition, .encryptionFailed, .mediaConnectionFailed:
            self = .unknown
        }
    }
}

extension DirectCallDiagnosticReceiveFailureReason {
    init(_ error: DirectCallEngineError) {
        switch error {
        case .invalidPeer, .invalidSender:
            self = .incomingWrongSender
        case .invalidRoomID, .roomMismatch:
            self = .incomingRoomMismatch
        case .invalidCallID, .callIDMismatch:
            self = .incomingCallMismatch
        case .invalidIntent:
            self = .incomingIntentMismatch
        case .staleOrUnknownEvent:
            self = .incomingDuplicate
        case .sessionAlreadyActive, .invalidTransition, .invalidEncryptionTransition:
            self = .incomingStateInvalid
        case .mediaConnectionFailed(let mediaError):
            self = .init(mediaError)
        case .encryptionFailed(let reason):
            self = .init(reason)
        }
    }

    init(_ error: DirectCallEngineError, signalType: DirectCallSignalType) {
        guard signalType == .answer else {
            self.init(error)
            return
        }

        switch error {
        case .invalidPeer, .invalidSender:
            self = .answerWrongSender
        case .invalidRoomID, .roomMismatch, .invalidCallID, .callIDMismatch, .staleOrUnknownEvent:
            self = .answerWrongCall
        case .invalidIntent, .sessionAlreadyActive, .invalidTransition, .invalidEncryptionTransition:
            self = .answerStateInvalid
        case .mediaConnectionFailed(let mediaError):
            self = .init(mediaError)
        case .encryptionFailed(let reason):
            self = .init(reason)
        }
    }

    init(_ reason: DirectCallEncryptionFailureReason) {
        switch reason {
        case .sdkTrustViolation:
            self = .incomingKeyTrustViolation
        case .sdkNoEligibleDevice:
            self = .incomingNoEligibleDevice
        case .wrongRecipient:
            self = .incomingWrongRecipient
        case .expiredKeyExchange:
            self = .incomingExpired
        case .unsupportedEnvelope, .keyMismatch, .missingMetadata:
            self = .incomingUnsupportedEnvelope
        case .missingPeer:
            self = .incomingWrongSender
        case .missingKeyExchange, .keyExchangeFailed, .e2eeNotProven, .e2eeUnavailable, .cannotWrap, .cannotUnwrap, .sdkWrapperUnavailable, .sdkEnvelopeFailed, .unsupportedRuntime:
            self = .incomingKeyUnwrapFailed
        }
    }

    init(_ mediaError: DirectCallMediaError) {
        switch mediaError {
        case .tokenUnavailable:
            self = .mediaTokenUnavailable
        case .tokenEndpointUnavailable:
            self = .tokenEndpointUnavailable
        case .accessTokenUnavailable:
            self = .accessTokenUnavailable
        case .tokenHTTPUnavailable:
            self = .tokenHTTPUnavailable
        case .tokenBackendRejected:
            self = .tokenBackendRejected
        case .tokenResponseInvalid:
            self = .tokenResponseInvalid
        case .e2eeContextUnavailable:
            self = .mediaE2EEContextUnavailable
        case .mediaSetupUnavailable:
            self = .mediaSetupUnavailable
        case .liveKitURLInvalid:
            self = .liveKitURLInvalid
        case .liveKitURLUnreachable:
            self = .liveKitURLUnreachable
        case .liveKitTokenRejected:
            self = .liveKitTokenRejected
        case .liveKitRoomJoinFailed:
            self = .liveKitRoomJoinFailed
        case .liveKitE2EEConfigFailed:
            self = .liveKitE2EEConfigFailed
        case .liveKitNetworkFailed:
            self = .liveKitNetworkFailed
        case .liveKitSDKError:
            self = .liveKitSDKError
        case .liveKitUnknown:
            self = .liveKitUnknown
        case .unsupportedIntent:
            self = .mediaUnsupportedIntent
        case .audioRouteFailed:
            self = .mediaConnectFailed
        case .invalidSession, .e2eeNotReady, .keyMismatch:
            self = .answerStateInvalid
        }
    }
}
#endif

private struct DirectCallMatrixSDKRawRoom: DirectCallMatrixRawRoomSending {
    let room: RoomProtocol

    func sendRaw(eventType: String, content: String) async throws {
        try await room.sendRaw(eventType: eventType, content: content)
    }
}

private struct DirectCallMatrixKeyExchangeContent: Codable, Equatable {
    let version: Int?
    let algorithm: String?
    let callID: String
    let roomID: String
    let senderUserID: String
    let recipientUserID: String?
    let intent: String?
    let expiresAtMilliseconds: UInt64?
    let keyID: String
    let encryptedPayload: String

    init(_ payload: DirectCallEncryptedKeyExchangePayload) {
        version = payload.version
        algorithm = payload.algorithm
        callID = payload.callID
        roomID = payload.roomID
        senderUserID = payload.senderUserID
        recipientUserID = payload.recipientUserID
        intent = payload.intent?.rawValue
        expiresAtMilliseconds = payload.expiresAt.map(Self.millisecondsSince1970)
        keyID = payload.keyID
        encryptedPayload = payload.encryptedPayload
    }

    var payload: DirectCallEncryptedKeyExchangePayload {
        .init(callID: callID,
              roomID: roomID,
              senderUserID: senderUserID,
              keyID: keyID,
              encryptedPayload: encryptedPayload,
              version: version,
              algorithm: algorithm,
              recipientUserID: recipientUserID,
              intent: DirectCallIntent.parse(intent),
              expiresAt: expiresAtMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) })
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case algorithm
        case callID = "call_id"
        case roomID = "room_id"
        case senderUserID = "sender_user_id"
        case recipientUserID = "recipient_user_id"
        case intent
        case expiresAtMilliseconds = "expires_at_ms"
        case keyID = "key_id"
        case encryptedPayload = "encrypted_payload"
    }

    private static func millisecondsSince1970(from date: Date) -> UInt64 {
        let milliseconds = date.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds > 0 else {
            return 0
        }

        guard milliseconds < Double(UInt64.max) else {
            return UInt64.max
        }

        return UInt64(milliseconds.rounded(.down))
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

    #if DEBUG
    private var diagnosticState = DirectCallDiagnosticSnapshot()
    private var previousSessionState: DirectCallState?
    private var receivedSignalEventIDs = Set<String>()

    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        var snapshot = diagnosticState
        if let transportDiagnostics = signalTransport as? DirectCallSignalTransportDiagnosticSnapshotProviding {
            snapshot.mergeReceiveDiagnostics(from: transportDiagnostics.diagnosticSnapshot)
        }
        if let engineDiagnostics = engine as? DirectCallMediaDiagnosticSnapshotProviding {
            snapshot.mergeReceiveDiagnostics(from: engineDiagnostics.diagnosticSnapshot)
        }
        return snapshot
    }
    #endif

    init(ownUserID: String,
         engine: DirectCallEngineProtocol,
         signalTransport: DirectCallSignalTransportProtocol) {
        self.ownUserID = ownUserID
        self.engine = engine
        self.signalTransport = signalTransport

        subscribeToOutgoingSignals()
        subscribeToIncomingSignals()
        #if DEBUG
        subscribeToSignalSendResults()
        #endif
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
                #if DEBUG
                recordDiagnosticAction(action)
                #endif
                guard case .emitSignal(let signal) = action else {
                    return
                }

                #if DEBUG
                diagnosticState.lastSignalSendAttempted = true
                diagnosticState.lastSignalSendSucceeded = nil
                diagnosticState.lastSignalSendFailureReason = nil
                #endif
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
                    #if DEBUG
                    let isDuplicateEvent = receivedSignalEventIDs.insert(signalEvent.eventID).inserted == false
                    diagnosticState.envelopeDeliveredToEngineCount += 1
                    diagnosticState.lastReceiveEventKind = .init(signalEvent.type)
                    diagnosticState.lastEnvelopeRejectedReason = isDuplicateEvent ? .duplicateEventID : .none
                    diagnosticState.lastReceiveFailureReason = nil
                    #endif
                    let result = await engine.receiveIncomingCall(event: signalEvent)
                    #if DEBUG
                    if case .failure(let error) = result {
                        diagnosticState.lastEnvelopeRejectedReason = .init(error)
                        diagnosticState.lastReceiveFailureReason = .init(error, signalType: signalEvent.type)
                    }
                    #endif
                }
            }
            .store(in: &cancellables)
    }

    #if DEBUG
    private func subscribeToSignalSendResults() {
        guard let sendResultsProvider = signalTransport as? DirectCallSignalTransportSendResultsProviding else {
            return
        }

        sendResultsProvider.sendResultsPublisher
            .sink { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    diagnosticState.lastSignalSendSucceeded = true
                    diagnosticState.lastSignalSendFailureReason = nil
                case .failure(let error):
                    diagnosticState.lastSignalSendSucceeded = false
                    diagnosticState.lastSignalSendFailureReason = .init(error)
                }
            }
            .store(in: &cancellables)
    }

    private func recordDiagnosticAction(_ action: DirectCallEngineAction) {
        switch action {
        case .stateChanged(let session):
            diagnosticState.activeSessionPhase = .init(session.state)
            if let terminalReason = Self.terminalReason(previousState: previousSessionState, currentState: session.state) {
                diagnosticState.lastTerminalReason = terminalReason
            }
            previousSessionState = session.state
        case .emitSignal(let signal):
            diagnosticState.lastSignalEventEmitted = .init(signal.type)
            diagnosticState.sendRoomFingerprint = DirectCallDiagnosticRedactor.roomFingerprint(signal.roomID)
        case .sessionCleared:
            diagnosticState.activeSessionPhase = .none
            previousSessionState = nil
        }
    }

    private static func terminalReason(previousState: DirectCallState?,
                                       currentState: DirectCallState) -> DirectCallDiagnosticTerminalReason? {
        switch currentState {
        case .failed:
            switch previousState {
            case .outgoingRinging:
                .outgoingTimeout
            case .connecting:
                .connectingFailed
            default:
                .failed
            }
        case .missed:
            .incomingTimeout
        case .cancelled:
            .cancelled
        case .ended:
            .hangup
        case .idle, .outgoingRinging, .incomingRinging, .connecting, .activeAudio, .activeVideo, .ending:
            nil
        }
    }
    #endif
}

struct NativeDirectCallCompositionConfiguration {
    var isEnabled: Bool
    var engineConfiguration: DirectCallEngineConfiguration

    init(isEnabled: Bool = false,
         engineConfiguration: DirectCallEngineConfiguration = .init()) {
        self.isEnabled = isEnabled
        self.engineConfiguration = engineConfiguration
    }
}

struct NativeDirectCallRoomMetadata: Equatable {
    let roomID: String
    let peerUserID: String?
    let isDirectOneToOneRoom: Bool
    let isEncryptedRoom: Bool
}

enum NativeDirectCallCompositionError: Error, Equatable {
    case disabled
    case invalidOwnUserID
    case invalidRoomID
    case missingSignalTransport
    case nonDirectRoom
    case nonEncryptedRoom
    case missingPeer
}

@MainActor
protocol NativeDirectCallSignalListenerControlProtocol {
    func start() async
    func stop()
}

extension MatrixDirectCallSignalTransport: NativeDirectCallSignalListenerControlProtocol {
    func start() async {
        await attach()
    }
}

@MainActor
final class NativeDirectCallComposition {
    let engine: DirectCallEngineProtocol
    let roomID: String
    let peerUserID: String

    private let signalBridge: DirectCallEngineSignalBridge
    private let listenerControl: NativeDirectCallSignalListenerControlProtocol?

    private(set) var isStarted = false

    #if DEBUG
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        signalBridge.diagnosticSnapshot
    }
    #endif

    init(roomID: String,
         peerUserID: String,
         engine: DirectCallEngineProtocol,
         signalBridge: DirectCallEngineSignalBridge,
         listenerControl: NativeDirectCallSignalListenerControlProtocol? = nil) {
        self.roomID = roomID
        self.peerUserID = peerUserID
        self.engine = engine
        self.signalBridge = signalBridge
        self.listenerControl = listenerControl
    }

    deinit {
        guard isStarted else {
            return
        }

        let listenerControl = listenerControl
        Task { @MainActor in
            listenerControl?.stop()
        }
    }

    func start() async {
        guard !isStarted else {
            return
        }

        isStarted = true
        await listenerControl?.start()
    }

    func stop() {
        guard isStarted else {
            return
        }

        isStarted = false
        listenerControl?.stop()
    }
}

@MainActor
final class NativeDirectCallCompositionFactory {
    private let ownUserID: String
    private let configuration: NativeDirectCallCompositionConfiguration
    private let signalTransport: DirectCallSignalTransportProtocol?
    private let mediaEngineFactory: DirectCallMediaEngineFactoryProtocol?
    private let encryptionService: DirectCallEncryptionServiceProtocol?
    private let listenerControl: NativeDirectCallSignalListenerControlProtocol?
    private let now: () -> Date

    init(ownUserID: String,
         configuration: NativeDirectCallCompositionConfiguration = .init(),
         signalTransport: DirectCallSignalTransportProtocol? = nil,
         mediaEngineFactory: DirectCallMediaEngineFactoryProtocol? = nil,
         encryptionService: DirectCallEncryptionServiceProtocol? = nil,
         listenerControl: NativeDirectCallSignalListenerControlProtocol? = nil,
         now: @escaping () -> Date = Date.init) {
        self.ownUserID = ownUserID
        self.configuration = configuration
        self.signalTransport = signalTransport
        self.mediaEngineFactory = mediaEngineFactory
        self.encryptionService = encryptionService
        self.listenerControl = listenerControl
        self.now = now
    }

    func makeComposition(for roomMetadata: NativeDirectCallRoomMetadata) -> Result<NativeDirectCallComposition, NativeDirectCallCompositionError> {
        guard configuration.isEnabled else {
            return .failure(.disabled)
        }

        guard !ownUserID.isEmpty else {
            return .failure(.invalidOwnUserID)
        }

        guard !roomMetadata.roomID.isEmpty else {
            return .failure(.invalidRoomID)
        }

        guard roomMetadata.isDirectOneToOneRoom else {
            return .failure(.nonDirectRoom)
        }

        guard roomMetadata.isEncryptedRoom else {
            return .failure(.nonEncryptedRoom)
        }

        guard let peerUserID = roomMetadata.peerUserID,
              !peerUserID.isEmpty,
              peerUserID != ownUserID else {
            return .failure(.missingPeer)
        }

        guard let signalTransport else {
            return .failure(.missingSignalTransport)
        }

        let engine = DirectCallEngine(ownUserID: ownUserID,
                                      configuration: configuration.engineConfiguration,
                                      now: now,
                                      encryptionService: encryptionService,
                                      mediaEngineFactory: mediaEngineFactory) { [roomID = roomMetadata.roomID] resolvedRoomID in
            resolvedRoomID == roomID ? peerUserID : nil
        }
        let signalBridge = DirectCallEngineSignalBridge(ownUserID: ownUserID,
                                                        engine: engine,
                                                        signalTransport: signalTransport)

        return .success(NativeDirectCallComposition(roomID: roomMetadata.roomID,
                                                    peerUserID: peerUserID,
                                                    engine: engine,
                                                    signalBridge: signalBridge,
                                                    listenerControl: listenerControl))
    }
}
