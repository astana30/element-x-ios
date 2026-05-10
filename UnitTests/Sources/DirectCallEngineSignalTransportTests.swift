//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import MatrixRustSDK
import MatrixRustSDKMocks
import Testing

@MainActor
final class DirectCallEngineSignalTransportTests {
    private let userA = "@a:example.com"
    private let userB = "@b:example.com"
    private let roomID = "!dm:example.com"

    @Test
    func callerCancelBeforeAnswerClearsIncomingAndStaleAnswerStaysBlocked() async {
        let harness = makeHarness(cleanupDelay: .seconds(1))

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })

        _ = await harness.engineA.cancelOutgoingBeforeAnswer(callID: outgoingSession.callID)

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .cancelled })
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value == nil })

        let staleAnswerResult = await harness.engineB.acceptCall(callID: outgoingSession.callID)
        #expect(staleAnswerResult == .failure(.invalidTransition))
    }

    @Test
    func calleeRejectEndsCallerWithoutMediaPath() async {
        let harness = makeHarness(cleanupDelay: .seconds(1))

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })
        _ = await harness.engineB.rejectCall(callID: outgoingSession.callID)

        #expect(await waitUntil { harness.engineA.activeSessionPublisher.value?.state == .cancelled })
    }

    @Test
    func acceptThenCallerHangupTransitionsBothSidesToTerminalState() async {
        let harness = makeHarness()

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })

        _ = await harness.engineB.acceptCall(callID: outgoingSession.callID)

        #expect(await waitUntil { harness.engineA.activeSessionPublisher.value?.state == .activeAudio })
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .activeAudio })

        _ = await harness.engineA.hangupActiveCall(callID: outgoingSession.callID)

        #expect(await waitUntil { harness.engineA.activeSessionPublisher.value?.state == .ended })
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .ended })
    }

    @Test
    func duplicateTerminalSignalsAreIgnoredSafelyInHarness() async {
        let harness = makeHarness(cleanupDelay: .seconds(1))
        var receiverStateChanges = 0
        let cancellable = harness.engineB.actionsPublisher.sink { action in
            if case .stateChanged = action {
                receiverStateChanges += 1
            }
        }
        defer { cancellable.cancel() }

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })
        _ = await harness.engineB.acceptCall(callID: outgoingSession.callID)
        #expect(await waitUntil { harness.engineA.activeSessionPublisher.value?.state == .activeAudio })
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .activeAudio })

        _ = await harness.engineA.hangupActiveCall(callID: outgoingSession.callID)
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .ended })
        let transitionsAfterFirstTerminal = receiverStateChanges

        harness.transport.send(.init(roomID: roomID,
                                     peerUserID: userB,
                                     callID: outgoingSession.callID,
                                     type: .hangup,
                                     intent: nil), from: userA)
        harness.transport.send(.init(roomID: roomID,
                                     peerUserID: userB,
                                     callID: outgoingSession.callID,
                                     type: .cancel,
                                     intent: nil), from: userA)

        await Task.yield()
        #expect(harness.engineB.activeSessionPublisher.value?.state == .ended)
        #expect(receiverStateChanges == transitionsAfterFirstTerminal)
    }

    @Test
    func invalidRoomSenderAndCallIDSignalsDoNotMutateReceiverState() async {
        let harness = makeHarness(cleanupDelay: .seconds(1))

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })

        harness.transport.send(.init(roomID: roomID,
                                     peerUserID: userB,
                                     callID: outgoingSession.callID,
                                     type: .hangup,
                                     intent: nil), from: "@mallory:example.com")
        harness.transport.send(.init(roomID: "!wrong:example.com",
                                     peerUserID: userB,
                                     callID: outgoingSession.callID,
                                     type: .cancel,
                                     intent: nil), from: userA)
        harness.transport.send(.init(roomID: roomID,
                                     peerUserID: userB,
                                     callID: "wrong-call-id",
                                     type: .hangup,
                                     intent: nil), from: userA)

        await Task.yield()
        #expect(harness.engineB.activeSessionPublisher.value?.state == .incomingRinging)
    }

    @Test
    func transportRejectsInvalidSignalsBeforeDelivery() async {
        let transport = InMemoryDirectCallSignalTransport()
        var receivedEvents = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()

        transport.signalsPublisher(for: userB)
            .sink { receivedEvents.append($0) }
            .store(in: &cancellables)

        transport.send(.init(roomID: roomID,
                             peerUserID: userB,
                             callID: "",
                             type: .invite,
                             intent: .audio), from: userA)
        transport.send(.init(roomID: "",
                             peerUserID: userB,
                             callID: "call-1",
                             type: .invite,
                             intent: .audio), from: userA)
        transport.send(.init(roomID: roomID,
                             peerUserID: "",
                             callID: "call-2",
                             type: .invite,
                             intent: .audio), from: userA)
        transport.send(.init(roomID: roomID,
                             peerUserID: userB,
                             callID: "call-3",
                             type: .invite,
                             intent: .audio), from: "")

        await Task.yield()
        #expect(receivedEvents.isEmpty)
    }

    @Test
    func transportPreservesInviteKeyExchangePayload() async {
        let transport = InMemoryDirectCallSignalTransport(now: Date.init) { "$event" }
        let payload = keyExchange(callID: "call-1", senderUserID: userA)
        var receivedEvents = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()

        transport.signalsPublisher(for: userB)
            .sink { receivedEvents.append($0) }
            .store(in: &cancellables)

        transport.send(.init(roomID: roomID,
                             peerUserID: userB,
                             callID: "call-1",
                             type: .invite,
                             intent: .audio,
                             keyExchange: payload), from: userA)

        await Task.yield()
        #expect(receivedEvents.first?.keyExchange == payload)
    }

    @Test
    func signalDescriptionsRedactEncryptedPayload() {
        let payload = keyExchange(callID: "call-1",
                                  senderUserID: userA,
                                  encryptedPayload: "ciphertext-must-not-appear")
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: payload)
        let event = DirectCallSignalEvent(eventID: "$event",
                                          roomID: roomID,
                                          senderID: userA,
                                          callID: "call-1",
                                          type: .invite,
                                          intent: .audio,
                                          timestamp: .now,
                                          keyExchange: payload)

        #expect(String(describing: payload).contains("ciphertext-must-not-appear") == false)
        #expect(String(reflecting: payload).contains("ciphertext-must-not-appear") == false)
        #expect(String(describing: signal).contains("ciphertext-must-not-appear") == false)
        #expect(String(reflecting: signal).contains("ciphertext-must-not-appear") == false)
        #expect(String(describing: event).contains("ciphertext-must-not-appear") == false)
        #expect(String(reflecting: event).contains("ciphertext-must-not-appear") == false)
    }

    @Test
    func signalModelsDoNotExposeRawKeyFields() {
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let labels = Set(Mirror(reflecting: signal).children.compactMap(\.label))

        #expect(labels.contains("rawKey") == false)
        #expect(labels.contains("keyData") == false)
        #expect(labels.contains("sharedKey") == false)
    }

    @Test
    func matrixInviteEncodingIncludesKeyExchangeCiphertextField() throws {
        let payload = keyExchange(callID: "call-1",
                                  senderUserID: userA,
                                  encryptedPayload: "ciphertext-for-matrix")
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: payload)

        let json = try #require(DirectCallMatrixSignalCodec.encode(signal))

        #expect(json.contains("\"key_exchange\""))
        #expect(json.contains("\"encrypted_payload\""))
        #expect(json.contains("ciphertext-for-matrix"))
    }

    @Test
    func matrixTerminalEncodingOmitsKeyExchange() throws {
        let payload = keyExchange(callID: "call-1", senderUserID: userA)
        let terminalTypes: [DirectCallSignalType] = [.answer, .reject, .cancel, .hangup, .timeout]

        for type in terminalTypes {
            let signal = DirectCallOutgoingSignal(roomID: roomID,
                                                  peerUserID: userB,
                                                  callID: "call-1",
                                                  type: type,
                                                  intent: nil,
                                                  keyExchange: payload)
            let json = try #require(DirectCallMatrixSignalCodec.encode(signal))
            let content = try JSONDecoder().decode(DirectCallMatrixSignalContent.self, from: #require(json.data(using: .utf8)))

            #expect(json.contains("\"key_exchange\"") == false)
            #expect(content.keyExchange == nil)
        }
    }

    @Test
    func matrixSignalContentDescriptionRedactsEncryptedPayload() {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1",
                                                                             senderUserID: userA,
                                                                             encryptedPayload: "ciphertext-must-not-appear"))

        #expect(String(describing: content).contains("ciphertext-must-not-appear") == false)
        #expect(String(reflecting: content).contains("ciphertext-must-not-appear") == false)
        #expect(String(describing: content).contains("encrypted_payload") == false)
        #expect(String(reflecting: content).contains("encrypted_payload") == false)
    }

    @Test
    func matrixSignalEnvelopeDescriptionRedactsRawContent() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1",
                                                                             senderUserID: userA,
                                                                             encryptedPayload: "ciphertext-must-not-appear"))
        let envelope = try matrixEnvelope(rawContent: json(for: content))

        #expect(String(describing: envelope).contains("ciphertext-must-not-appear") == false)
        #expect(String(reflecting: envelope).contains("ciphertext-must-not-appear") == false)
        #expect(String(describing: envelope).contains("encrypted_payload") == false)
        #expect(String(reflecting: envelope).contains("encrypted_payload") == false)
    }

    @Test
    func matrixValidInviteJSONDecodesToSignalEvent() throws {
        let payload = keyExchange(callID: "call-1", senderUserID: userA)
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: payload)
        let json = try #require(DirectCallMatrixSignalCodec.encode(signal))

        let event = DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json))

        #expect(event?.eventID == "$matrix-event")
        #expect(event?.roomID == roomID)
        #expect(event?.senderID == userA)
        #expect(event?.callID == "call-1")
        #expect(event?.type == .invite)
        #expect(event?.intent == .audio)
        #expect(event?.keyExchange == payload)
    }

    @Test
    func matrixValidAnswerAndHangupJSONDecodeToSignalEvents() throws {
        for type in [DirectCallSignalType.answer, .hangup] {
            let signal = DirectCallOutgoingSignal(roomID: roomID,
                                                  peerUserID: userB,
                                                  callID: "call-1",
                                                  type: type,
                                                  intent: nil)
            let json = try #require(DirectCallMatrixSignalCodec.encode(signal))

            let event = DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json))

            #expect(event?.type == type)
            #expect(event?.intent == nil)
            #expect(event?.keyExchange == nil)
        }
    }

    @Test
    func matrixMalformedJSONFailsClosed() {
        let event = DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: "{not-json"))

        #expect(event == nil)
    }

    @Test
    func matrixUnknownVersionFailsClosed() throws {
        let content = DirectCallMatrixSignalContent(version: 2,
                                                    callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixUnknownTypeFailsClosed() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: "unknown",
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixInviteWithoutKeyExchangeFailsClosed() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: nil)
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixInviteWithNonAudioIntentFailsClosed() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.video.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixKeyExchangeCallIDMismatchFailsClosed() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "other-call", senderUserID: userA))
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixKeyExchangeRoomIDMismatchFailsClosed() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1",
                                                                             roomID: "!other:example.com",
                                                                             senderUserID: userA))
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixKeyExchangeSenderUserIDMismatchFailsClosed() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1",
                                                                             senderUserID: "@mallory:example.com"))
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixRecipientMismatchIsIgnored() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: "@other:example.com",
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixOwnEventsAreIgnored() throws {
        let payload = keyExchange(callID: "call-1", senderUserID: userB)
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: payload)
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(senderUserID: userB, rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixNonDirectRoomMetadataIsIgnoredWhenAvailable() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(isDirectOneToOneRoom: false,
                                                                          rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixNonEncryptedRoomMetadataIsIgnoredWhenAvailable() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let event = try DirectCallMatrixSignalCodec.decode(matrixEnvelope(isEncryptedRoom: false,
                                                                          rawContent: json(for: content)))

        #expect(event == nil)
    }

    @Test
    func matrixSignalReceiverEmitsValidInvite() throws {
        let payload = keyExchange(callID: "call-1", senderUserID: userA)
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: payload)
        let events = try receiveMatrixEnvelopes([matrixEnvelope(rawContent: #require(DirectCallMatrixSignalCodec.encode(signal)))])

        #expect(events.count == 1)
        #expect(events.first?.type == .invite)
        #expect(events.first?.keyExchange == payload)
    }

    @Test
    func matrixSignalReceiverEmitsValidAnswer() throws {
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .answer,
                                              intent: nil)
        let events = try receiveMatrixEnvelopes([matrixEnvelope(rawContent: #require(DirectCallMatrixSignalCodec.encode(signal)))])

        #expect(events.count == 1)
        #expect(events.first?.type == .answer)
        #expect(events.first?.keyExchange == nil)
    }

    @Test
    func matrixSignalReceiverIgnoresMalformedJSON() {
        let events = receiveMatrixEnvelopes([matrixEnvelope(rawContent: "{not-json")])

        #expect(events.isEmpty)
    }

    @Test
    func matrixSignalReceiverIgnoresOwnEvent() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userB))
        let events = try receiveMatrixEnvelopes([matrixEnvelope(senderUserID: userB, rawContent: json(for: content))])

        #expect(events.isEmpty)
    }

    @Test
    func matrixSignalReceiverIgnoresRecipientMismatch() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: "@other:example.com",
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let events = try receiveMatrixEnvelopes([matrixEnvelope(rawContent: json(for: content))])

        #expect(events.isEmpty)
    }

    @Test
    func matrixSignalReceiverIgnoresNonDirectRoomMetadataWhenFalse() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let events = try receiveMatrixEnvelopes([matrixEnvelope(isDirectOneToOneRoom: false, rawContent: json(for: content))])

        #expect(events.isEmpty)
    }

    @Test
    func matrixSignalReceiverIgnoresNonEncryptedRoomMetadataWhenFalse() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let events = try receiveMatrixEnvelopes([matrixEnvelope(isEncryptedRoom: false, rawContent: json(for: content))])

        #expect(events.isEmpty)
    }

    @Test
    func matrixSignalReceiverIgnoresInviteWithoutKeyExchange() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: nil)
        let events = try receiveMatrixEnvelopes([matrixEnvelope(rawContent: json(for: content))])

        #expect(events.isEmpty)
    }

    @Test
    func matrixSignalReceiverIgnoresKeyExchangeMismatch() throws {
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: userB,
                                                    keyExchange: keyExchange(callID: "other-call", senderUserID: userA))
        let events = try receiveMatrixEnvelopes([matrixEnvelope(rawContent: json(for: content))])

        #expect(events.isEmpty)
    }

    @Test
    func matrixSignalReceiverDoesNotExposeRawContentOrEncryptedPayloadInOutputDescriptions() throws {
        let payload = keyExchange(callID: "call-1",
                                  senderUserID: userA,
                                  encryptedPayload: "ciphertext-must-not-appear")
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: payload)

        let events = try receiveMatrixEnvelopes([matrixEnvelope(rawContent: #require(DirectCallMatrixSignalCodec.encode(signal)))])
        let event = try #require(events.first)

        #expect(String(describing: event).contains("ciphertext-must-not-appear") == false)
        #expect(String(reflecting: event).contains("ciphertext-must-not-appear") == false)
        #expect(String(describing: event).contains("rawContent") == false)
        #expect(String(reflecting: event).contains("rawContent") == false)
    }

    @Test
    func matrixSignalReceiverProcessesMultipleEventsInOrder() throws {
        let invitePayload = keyExchange(callID: "call-1", senderUserID: userA)
        let invite = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: invitePayload)
        let answer = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .answer,
                                              intent: nil)
        let hangup = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .hangup,
                                              intent: nil)

        let events = try receiveMatrixEnvelopes([
            matrixEnvelope(eventID: "$event-1", rawContent: #require(DirectCallMatrixSignalCodec.encode(invite))),
            matrixEnvelope(eventID: "$event-2", rawContent: #require(DirectCallMatrixSignalCodec.encode(answer))),
            matrixEnvelope(eventID: "$event-3", rawContent: #require(DirectCallMatrixSignalCodec.encode(hangup)))
        ])

        #expect(events.map(\.eventID) == ["$event-1", "$event-2", "$event-3"])
        #expect(events.map(\.type) == [.invite, .answer, .hangup])
    }

    @Test
    func matrixRawSenderSkeletonSendsExpectedEventTypeAndJSON() async throws {
        let rawSender = MatrixRawSignalSenderSpy()
        let transport = DirectCallMatrixSignalTransport(rawSender: rawSender)
        let payload = keyExchange(callID: "call-1", senderUserID: userA)
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: payload)

        let result = await transport.send(signal)

        guard case .success = result else {
            Issue.record("Expected Matrix raw sender skeleton to send the encoded signal.")
            return
        }
        #expect(rawSender.sentSignals.count == 1)
        #expect(rawSender.sentSignals.first?.roomID == roomID)
        #expect(rawSender.sentSignals.first?.eventType == DirectCallMatrixSignalCodec.eventType)

        let rawContent = try #require(rawSender.sentSignals.first?.content)
        let decodedEvent = DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: rawContent))
        #expect(decodedEvent?.keyExchange == payload)
    }

    @Test
    func matrixRoomRawSignalSenderCallsSendRawWithDedicatedEventTypeAndUnchangedContent() async {
        let rawRoom = MatrixRawRoomSenderSpy()
        let sender = DirectCallMatrixRoomRawSignalSender(roomID: roomID, room: rawRoom)
        let content = #"{"version":1,"call_id":"call-1"}"#

        let result = await sender.sendDirectCallSignal(roomID: roomID,
                                                       eventType: DirectCallMatrixSignalCodec.eventType,
                                                       content: content)

        guard case .success = result else {
            Issue.record("Expected Matrix room raw signal sender to send content.")
            return
        }
        #expect(rawRoom.sentRawEvents == [.init(eventType: DirectCallMatrixSignalCodec.eventType, content: content)])
    }

    @Test
    func matrixRoomRawSignalSenderMapsThrownErrorToSendFailed() async {
        let rawRoom = MatrixRawRoomSenderSpy()
        rawRoom.error = MatrixRawRoomSenderError()
        let sender = DirectCallMatrixRoomRawSignalSender(roomID: roomID, room: rawRoom)

        let result = await sender.sendDirectCallSignal(roomID: roomID,
                                                       eventType: DirectCallMatrixSignalCodec.eventType,
                                                       content: #"{"version":1}"#)

        guard case .failure(.sendFailed) = result else {
            Issue.record("Expected Matrix room raw signal sender to map SDK send errors to sendFailed.")
            return
        }
        #expect(rawRoom.sentRawEvents.isEmpty)
    }

    @Test
    func matrixRoomRawSignalSenderRejectsInvalidArguments() async {
        let rawRoom = MatrixRawRoomSenderSpy()
        let sender = DirectCallMatrixRoomRawSignalSender(roomID: roomID, room: rawRoom)

        let emptyRoomResult = await sender.sendDirectCallSignal(roomID: "",
                                                                eventType: DirectCallMatrixSignalCodec.eventType,
                                                                content: #"{"version":1}"#)
        let mismatchedRoomResult = await sender.sendDirectCallSignal(roomID: "!other:example.com",
                                                                     eventType: DirectCallMatrixSignalCodec.eventType,
                                                                     content: #"{"version":1}"#)
        let emptyEventTypeResult = await sender.sendDirectCallSignal(roomID: roomID,
                                                                     eventType: "",
                                                                     content: #"{"version":1}"#)
        let wrongEventTypeResult = await sender.sendDirectCallSignal(roomID: roomID,
                                                                     eventType: "m.call.hangup",
                                                                     content: #"{"version":1}"#)
        let emptyContentResult = await sender.sendDirectCallSignal(roomID: roomID,
                                                                   eventType: DirectCallMatrixSignalCodec.eventType,
                                                                   content: "")

        for result in [emptyRoomResult, mismatchedRoomResult, emptyEventTypeResult, wrongEventTypeResult, emptyContentResult] {
            guard case .failure(.invalidSignal) = result else {
                Issue.record("Expected Matrix room raw signal sender to reject invalid arguments.")
                return
            }
        }
        #expect(rawRoom.sentRawEvents.isEmpty)
    }

    @Test
    func matrixDirectCallSignalTransportSendsEncodedInviteThroughRawSender() async throws {
        let rawSender = MatrixRawSignalSenderSpy()
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userA,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: rawSender),
                                                        listener: listener)
        let payload = keyExchange(callID: "call-1", senderUserID: userA)
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: payload)

        transport.send(signal, from: userA)

        #expect(await waitUntil { rawSender.sentSignals.count == 1 })
        #expect(transport.diagnosticSnapshot.sendRoomFingerprint == DirectCallDiagnosticRedactor.roomFingerprint(roomID))
        #expect(transport.diagnosticSnapshot.sendRoomFingerprint != roomID)
        let sentSignal = try #require(rawSender.sentSignals.first)
        #expect(sentSignal.roomID == roomID)
        #expect(sentSignal.eventType == DirectCallMatrixSignalCodec.eventType)

        let decodedEvent = DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: sentSignal.content))
        #expect(decodedEvent?.keyExchange == payload)
    }

    @Test
    func matrixDirectCallSignalTransportPublishesSendFailureSafely() async {
        let rawSender = MatrixRawSignalSenderSpy()
        rawSender.result = .failure(.sendFailed)
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userA,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: rawSender),
                                                        listener: listener)
        var results = [Result<Void, DirectCallMatrixSignalTransportError>]()
        var cancellables = Set<AnyCancellable>()
        transport.sendResultsPublisher
            .sink { results.append($0) }
            .store(in: &cancellables)

        transport.send(.init(roomID: roomID,
                             peerUserID: userB,
                             callID: "call-1",
                             type: .answer,
                             intent: nil), from: userA)

        #expect(await waitUntil {
            guard case .failure(.sendFailed) = results.first else {
                return false
            }
            return true
        })
    }

    @Test
    func matrixDirectCallSignalTransportReceivesValidInviteEnvelope() async throws {
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userB,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: MatrixRawSignalSenderSpy()),
                                                        listener: listener)
        let payload = keyExchange(callID: "call-1", senderUserID: userA)
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: payload)
        var events = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()
        transport.signalsPublisher(for: userB)
            .sink { events.append($0) }
            .store(in: &cancellables)
        await transport.attach()

        #expect(transport.diagnosticSnapshot.listenerAttached)
        #expect(transport.diagnosticSnapshot.listenerHandleRetained)
        #expect(transport.diagnosticSnapshot.listenerStartCount == 1)

        try listener.emit(matrixEnvelope(rawContent: #require(DirectCallMatrixSignalCodec.encode(signal))))

        #expect(await waitUntil { events.count == 1 })
        #expect(events.first?.type == .invite)
        #expect(events.first?.keyExchange == payload)
        #expect(transport.diagnosticSnapshot.envelopeExtractedCount == 1)
        #expect(transport.diagnosticSnapshot.lastReceiveEventKind == .directCallInvite)
        #expect(transport.diagnosticSnapshot.lastEnvelopeRejectedReason == .none)
        #expect(transport.diagnosticSnapshot.receiveRoomFingerprint == DirectCallDiagnosticRedactor.roomFingerprint(roomID))
        #expect(transport.diagnosticSnapshot.receiveRoomFingerprint != roomID)
    }

    @Test
    func matrixDirectCallSignalTransportRecordsRedactedDecodeFailureDiagnostics() async {
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userB,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: MatrixRawSignalSenderSpy()),
                                                        listener: listener)
        var events = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()
        transport.signalsPublisher(for: userB)
            .sink { events.append($0) }
            .store(in: &cancellables)
        await transport.attach()

        listener.emit(matrixEnvelope(rawContent: "{not-json"))
        await Task.yield()

        #expect(events.isEmpty)
        #expect(transport.diagnosticSnapshot.envelopeExtractedCount == 1)
        #expect(transport.diagnosticSnapshot.lastReceiveEventKind == .malformed)
        #expect(transport.diagnosticSnapshot.lastEnvelopeRejectedReason == .decodeFailed)
        #expect(transport.diagnosticSnapshot.lastReceiveFailureReason == .decodeFailed)
    }

    @Test
    func matrixDirectCallSignalTransportRecordsRedactedPeerMismatchDiagnostics() async throws {
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userB,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: MatrixRawSignalSenderSpy()),
                                                        listener: listener)
        let content = DirectCallMatrixSignalContent(callID: "call-1",
                                                    type: DirectCallSignalType.invite.rawValue,
                                                    intent: DirectCallIntent.audio.rawValue,
                                                    recipient: "@other:example.com",
                                                    keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        var events = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()
        transport.signalsPublisher(for: userB)
            .sink { events.append($0) }
            .store(in: &cancellables)
        await transport.attach()

        try listener.emit(matrixEnvelope(rawContent: json(for: content)))
        await Task.yield()

        #expect(events.isEmpty)
        #expect(transport.diagnosticSnapshot.lastReceiveEventKind == .directCallInvite)
        #expect(transport.diagnosticSnapshot.lastEnvelopeRejectedReason == .peerMismatch)
    }

    @Test
    func matrixDirectCallSignalTransportReceivesAnswerAndHangupInOrder() async throws {
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userB,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: MatrixRawSignalSenderSpy()),
                                                        listener: listener)
        let answer = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .answer,
                                              intent: nil)
        let hangup = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .hangup,
                                              intent: nil)
        var events = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()
        transport.signalsPublisher(for: userB)
            .sink { events.append($0) }
            .store(in: &cancellables)
        await transport.attach()

        try listener.emit(matrixEnvelope(eventID: "$event-1", rawContent: #require(DirectCallMatrixSignalCodec.encode(answer))))
        try listener.emit(matrixEnvelope(eventID: "$event-2", rawContent: #require(DirectCallMatrixSignalCodec.encode(hangup))))

        #expect(await waitUntil { events.count == 2 })
        #expect(events.map(\.eventID) == ["$event-1", "$event-2"])
        #expect(events.map(\.type) == [.answer, .hangup])
    }

    @Test
    func matrixDirectCallSignalTransportIgnoresInvalidEnvelopes() async throws {
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userB,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: MatrixRawSignalSenderSpy()),
                                                        listener: listener)
        let validContent = DirectCallMatrixSignalContent(callID: "call-1",
                                                         type: DirectCallSignalType.invite.rawValue,
                                                         intent: DirectCallIntent.audio.rawValue,
                                                         recipient: userB,
                                                         keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        var events = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()
        transport.signalsPublisher(for: userB)
            .sink { events.append($0) }
            .store(in: &cancellables)
        await transport.attach()

        listener.emit(matrixEnvelope(rawContent: "{not-json"))
        try listener.emit(matrixEnvelope(senderUserID: userB, rawContent: json(for: validContent)))
        try listener.emit(matrixEnvelope(rawContent: json(for: DirectCallMatrixSignalContent(callID: "call-1",
                                                                                             type: DirectCallSignalType.invite.rawValue,
                                                                                             intent: DirectCallIntent.audio.rawValue,
                                                                                             recipient: "@other:example.com",
                                                                                             keyExchange: keyExchange(callID: "call-1", senderUserID: userA)))))
        try listener.emit(matrixEnvelope(isDirectOneToOneRoom: false, rawContent: json(for: validContent)))
        try listener.emit(matrixEnvelope(isEncryptedRoom: false, rawContent: json(for: validContent)))

        await Task.yield()
        #expect(events.isEmpty)
    }

    @Test
    func matrixDirectCallSignalTransportPreservesStableEventID() async throws {
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userB,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: MatrixRawSignalSenderSpy()),
                                                        listener: listener)
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .hangup,
                                              intent: nil)
        var events = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()
        transport.signalsPublisher(for: userB)
            .sink { events.append($0) }
            .store(in: &cancellables)
        await transport.attach()

        try listener.emit(matrixEnvelope(eventID: "$stable-terminal-event", rawContent: #require(DirectCallMatrixSignalCodec.encode(signal))))

        #expect(await waitUntil { events.first?.eventID == "$stable-terminal-event" })
    }

    @Test
    func matrixDirectCallSignalTransportDetachAndStopPreventFutureDelivery() async throws {
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userB,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: MatrixRawSignalSenderSpy()),
                                                        listener: listener)
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .answer,
                                              intent: nil)
        var events = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()
        transport.signalsPublisher(for: userB)
            .sink { events.append($0) }
            .store(in: &cancellables)
        await transport.attach()

        transport.detachSignalsPublisher(for: userB)
        try listener.emit(matrixEnvelope(eventID: "$after-detach", rawContent: #require(DirectCallMatrixSignalCodec.encode(signal))))
        await Task.yield()
        #expect(events.isEmpty)

        transport.signalsPublisher(for: userB)
            .sink { events.append($0) }
            .store(in: &cancellables)
        transport.stop()
        try listener.emit(matrixEnvelope(eventID: "$after-stop", rawContent: #require(DirectCallMatrixSignalCodec.encode(signal))))
        await Task.yield()

        #expect(events.isEmpty)
        #expect(listener.cancelCount == 1)
    }

    @Test
    func matrixDirectCallSignalTransportDoesNotExposeRawContentOrEncryptedPayloadToConsumers() async throws {
        let listener = MatrixTimelineSignalListenerSpy()
        let transport = MatrixDirectCallSignalTransport(ownUserID: userB,
                                                        sender: DirectCallMatrixSignalTransport(rawSender: MatrixRawSignalSenderSpy()),
                                                        listener: listener)
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: keyExchange(callID: "call-1",
                                                                       senderUserID: userA,
                                                                       encryptedPayload: "ciphertext-must-not-appear"))
        var events = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()
        transport.signalsPublisher(for: userB)
            .sink { events.append($0) }
            .store(in: &cancellables)
        await transport.attach()

        try listener.emit(matrixEnvelope(rawContent: #require(DirectCallMatrixSignalCodec.encode(signal))))

        #expect(await waitUntil { events.count == 1 })
        let event = try #require(events.first)
        #expect(String(describing: event).contains("ciphertext-must-not-appear") == false)
        #expect(String(reflecting: event).contains("ciphertext-must-not-appear") == false)
        #expect(String(describing: event).contains("rawContent") == false)
        #expect(String(reflecting: event).contains("rawContent") == false)
    }

    @Test
    func transportDetachRemovesRecipientDeliveryPath() async {
        let transport = InMemoryDirectCallSignalTransport()
        var receivedEvents = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()

        transport.signalsPublisher(for: userB)
            .sink { receivedEvents.append($0) }
            .store(in: &cancellables)

        transport.send(.init(roomID: roomID,
                             peerUserID: userB,
                             callID: "call-before-detach",
                             type: .invite,
                             intent: .audio), from: userA)
        #expect(receivedEvents.count == 1)

        transport.detachSignalsPublisher(for: userB)

        transport.send(.init(roomID: roomID,
                             peerUserID: userB,
                             callID: "call-after-detach",
                             type: .invite,
                             intent: .audio), from: userA)

        await Task.yield()
        #expect(receivedEvents.count == 1)
    }

    private func makeHarness(cleanupDelay: Duration = .milliseconds(20)) -> Harness {
        let transport = InMemoryDirectCallSignalTransport()

        let engineA = makeEngine(ownUserID: userA, peerUserID: userB, cleanupDelay: cleanupDelay)
        let engineB = makeEngine(ownUserID: userB, peerUserID: userA, cleanupDelay: cleanupDelay)

        let bridgeA = DirectCallEngineSignalBridge(ownUserID: userA,
                                                   engine: engineA,
                                                   signalTransport: transport)
        let bridgeB = DirectCallEngineSignalBridge(ownUserID: userB,
                                                   engine: engineB,
                                                   signalTransport: transport)

        return Harness(transport: transport,
                       engineA: engineA,
                       engineB: engineB,
                       bridgeA: bridgeA,
                       bridgeB: bridgeB)
    }

    private func makeEngine(ownUserID: String,
                            peerUserID: String,
                            cleanupDelay: Duration) -> DirectCallEngine {
        DirectCallEngine(ownUserID: ownUserID,
                         configuration: .init(incomingRingingTimeout: .seconds(120),
                                              outgoingRingingTimeout: .seconds(120),
                                              connectingTimeout: .seconds(120),
                                              cleanupDelay: cleanupDelay,
                                              processedTerminalEventLimit: 64),
                         encryptionService: SignalEncryptionServiceSpy(senderUserID: ownUserID),
                         mediaEngine: SignalMediaEngineSpy()) { [roomID] resolvedRoomID in
            resolvedRoomID == roomID ? peerUserID : nil
        }
    }

    private func keyExchange(callID: String,
                             roomID: String? = nil,
                             senderUserID: String,
                             encryptedPayload: String = "encrypted") -> DirectCallEncryptedKeyExchangePayload {
        .init(callID: callID,
              roomID: roomID ?? self.roomID,
              senderUserID: senderUserID,
              keyID: "key-\(callID)",
              encryptedPayload: encryptedPayload)
    }

    private func matrixEnvelope(eventID: String = "$matrix-event",
                                roomID: String? = nil,
                                senderUserID: String? = nil,
                                ownUserID: String? = nil,
                                isDirectOneToOneRoom: Bool? = true,
                                isEncryptedRoom: Bool? = true,
                                rawContent: String) -> DirectCallMatrixSignalEnvelope {
        .init(eventID: eventID,
              roomID: roomID ?? self.roomID,
              senderUserID: senderUserID ?? userA,
              ownUserID: ownUserID ?? userB,
              isDirectOneToOneRoom: isDirectOneToOneRoom,
              isEncryptedRoom: isEncryptedRoom,
              timestamp: .now,
              rawContent: rawContent)
    }

    private func json(for content: DirectCallMatrixSignalContent) throws -> String {
        try String(data: JSONEncoder().encode(content), encoding: .utf8) ?? ""
    }

    private func receiveMatrixEnvelopes(_ envelopes: [DirectCallMatrixSignalEnvelope]) -> [DirectCallSignalEvent] {
        var events = [DirectCallSignalEvent]()
        let receiver = DirectCallMatrixSignalReceiver { event in
            events.append(event)
        }

        for envelope in envelopes {
            _ = receiver.receive(envelope)
        }
        return events
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           checkInterval: Duration = .milliseconds(20),
                           condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: checkInterval)
        }
        return condition()
    }
}

@MainActor
final class NativeDirectCallCompositionFactoryTests {
    private let userA = "@a:example.com"
    private let userB = "@b:example.com"
    private let roomID = "!dm:example.com"

    @Test
    func factoryIsDisabledByDefault() {
        let factory = NativeDirectCallCompositionFactory(ownUserID: userA,
                                                         signalTransport: InMemoryDirectCallSignalTransport(),
                                                         encryptionService: SignalEncryptionServiceSpy(senderUserID: userA))

        expectFailure(factory.makeComposition(for: encryptedDirectRoomMetadata()), .disabled)
    }

    @Test
    func enabledFactoryBuildsEngineWithExplicitFakesWithoutStartingListener() async {
        let transport = InMemoryDirectCallSignalTransport(eventIDProvider: { "$native-invite" })
        let mediaFactory = SignalMediaEngineFactorySpy(mediaEngine: SignalMediaEngineSpy())
        let listener = NativeDirectCallListenerControlSpy()
        let factory = enabledFactory(signalTransport: transport,
                                     mediaEngineFactory: mediaFactory,
                                     listenerControl: listener)

        guard case .success(let composition) = factory.makeComposition(for: encryptedDirectRoomMetadata()) else {
            Issue.record("Expected enabled native direct-call composition to build with explicit fakes.")
            return
        }

        #expect(composition.isStarted == false)
        #expect(listener.startCount == 0)
        #expect(mediaFactory.makeMediaEngineCount == 1)

        var receivedEvents = [DirectCallSignalEvent]()
        var cancellables = Set<AnyCancellable>()
        transport.signalsPublisher(for: userB)
            .sink { receivedEvents.append($0) }
            .store(in: &cancellables)

        let result = await composition.engine.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success = result else {
            Issue.record("Expected composed engine to start outgoing audio with fake dependencies.")
            return
        }

        #expect(await waitUntil { receivedEvents.count == 1 })
        #expect(receivedEvents.last?.eventID == "$native-invite")
        #expect(receivedEvents.last?.type == .invite)
        #expect(receivedEvents.last?.keyExchange != nil)
    }

    @Test
    func enabledFactoryFailsClosedForUnsafeRoomMetadata() {
        let factory = enabledFactory(signalTransport: InMemoryDirectCallSignalTransport(),
                                     mediaEngineFactory: fakeMediaEngineFactory())

        expectFailure(factory.makeComposition(for: encryptedDirectRoomMetadata(isDirectOneToOneRoom: false)), .nonDirectRoom)
        expectFailure(factory.makeComposition(for: encryptedDirectRoomMetadata(isEncryptedRoom: false)), .nonEncryptedRoom)
        expectFailure(factory.makeComposition(for: encryptedDirectRoomMetadata(peerUserID: nil)), .missingPeer)
        expectFailure(factory.makeComposition(for: encryptedDirectRoomMetadata(peerUserID: userA)), .missingPeer)
        expectFailure(factory.makeComposition(for: encryptedDirectRoomMetadata(roomID: "")), .invalidRoomID)
        expectFailure(enabledFactory(signalTransport: nil,
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(for: encryptedDirectRoomMetadata()), .missingSignalTransport)
    }

    @Test
    func listenerStartsOnlyWhenExplicitlyRequestedAndStopsIdempotently() async {
        let listener = NativeDirectCallListenerControlSpy()
        let factory = enabledFactory(signalTransport: InMemoryDirectCallSignalTransport(),
                                     mediaEngineFactory: fakeMediaEngineFactory(),
                                     listenerControl: listener)

        guard case .success(let composition) = factory.makeComposition(for: encryptedDirectRoomMetadata()) else {
            Issue.record("Expected enabled native direct-call composition to build.")
            return
        }

        #expect(composition.isStarted == false)
        #expect(listener.startCount == 0)
        #expect(listener.stopCount == 0)

        await composition.start()
        await composition.start()

        #expect(composition.isStarted)
        #expect(listener.startCount == 1)
        #expect(listener.stopCount == 0)

        composition.stop()
        composition.stop()

        #expect(composition.isStarted == false)
        #expect(listener.startCount == 1)
        #expect(listener.stopCount == 1)
    }

    @Test
    func missingMediaFactoryUsesNoOpFailClosedPath() async {
        let factory = enabledFactory(signalTransport: InMemoryDirectCallSignalTransport(),
                                     mediaEngineFactory: nil)

        guard case .success(let composition) = factory.makeComposition(for: encryptedDirectRoomMetadata()) else {
            Issue.record("Expected enabled native direct-call composition to build with default NoOp media factory.")
            return
        }

        let outgoingResult = await composition.engine.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let session) = outgoingResult else {
            Issue.record("Expected outgoing call start to succeed before NoOp media connection.")
            return
        }

        let answerEvent = DirectCallSignalEvent(eventID: "$answer",
                                                roomID: roomID,
                                                senderID: userB,
                                                callID: session.callID,
                                                type: .answer,
                                                intent: nil,
                                                timestamp: .now)
        let answerResult = await composition.engine.receiveIncomingCall(event: answerEvent)
        expectFailure(answerResult, .mediaConnectionFailed)
        #expect(composition.engine.activeSessionPublisher.value?.state == .failed)
    }

    private func enabledFactory(signalTransport: DirectCallSignalTransportProtocol?,
                                mediaEngineFactory: DirectCallMediaEngineFactoryProtocol?,
                                listenerControl: NativeDirectCallSignalListenerControlProtocol? = nil) -> NativeDirectCallCompositionFactory {
        .init(ownUserID: userA,
              configuration: .init(isEnabled: true,
                                   engineConfiguration: .init(incomingRingingTimeout: .seconds(120),
                                                              outgoingRingingTimeout: .seconds(120),
                                                              connectingTimeout: .seconds(120),
                                                              cleanupDelay: .seconds(120),
                                                              processedTerminalEventLimit: 64)),
              signalTransport: signalTransport,
              mediaEngineFactory: mediaEngineFactory,
              encryptionService: SignalEncryptionServiceSpy(senderUserID: userA),
              listenerControl: listenerControl)
    }

    private func fakeMediaEngineFactory() -> DirectCallMediaEngineFactoryProtocol {
        SignalMediaEngineFactorySpy(mediaEngine: SignalMediaEngineSpy())
    }

    private func encryptedDirectRoomMetadata(roomID: String? = nil,
                                             peerUserID: String? = "@b:example.com",
                                             isDirectOneToOneRoom: Bool = true,
                                             isEncryptedRoom: Bool = true) -> NativeDirectCallRoomMetadata {
        .init(roomID: roomID ?? self.roomID,
              peerUserID: peerUserID,
              isDirectOneToOneRoom: isDirectOneToOneRoom,
              isEncryptedRoom: isEncryptedRoom)
    }

    private func expectFailure(_ result: Result<NativeDirectCallComposition, NativeDirectCallCompositionError>,
                               _ expectedError: NativeDirectCallCompositionError) {
        guard case .failure(let error) = result else {
            Issue.record("Expected native direct-call composition to fail closed with \(expectedError).")
            return
        }

        #expect(error == expectedError)
    }

    private func expectFailure(_ result: Result<DirectCallSession?, DirectCallEngineError>,
                               _ expectedError: DirectCallEngineError) {
        guard case .failure(let error) = result else {
            Issue.record("Expected composed engine to fail closed with \(expectedError).")
            return
        }

        #expect(error == expectedError)
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           checkInterval: Duration = .milliseconds(20),
                           condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: checkInterval)
        }
        return condition()
    }
}

@MainActor
final class JoinedRoomNativeDirectCallCompositionFactoryTests {
    private let userA = "@a:example.com"
    private let userB = "@b:example.com"
    private let roomID = "!dm:example.com"

    @Test
    func adapterIsDisabledByDefault() {
        let roomBoundary = roomBoundary()
        let factory = JoinedRoomNativeDirectCallCompositionFactory(roomBoundary: roomBoundary,
                                                                   mediaEngineFactory: fakeMediaEngineFactory(),
                                                                   encryptionService: SignalEncryptionServiceSpy(senderUserID: userA))

        expectFailure(factory.makeComposition(), .composition(.disabled))
        #expect(roomBoundary.makeRawSignalSenderCount == 0)
        #expect(roomBoundary.makeTimelineSignalListenerCount == 0)
    }

    @Test
    func controllerIsDisabledByDefaultAndDoesNotCreateComposition() async {
        let roomBoundary = roomBoundary()
        let controller = JoinedRoomNativeDirectCallCompositionController(roomID: roomID,
                                                                         factory: .init(roomBoundary: roomBoundary,
                                                                                        mediaEngineFactory: fakeMediaEngineFactory(),
                                                                                        encryptionService: SignalEncryptionServiceSpy(senderUserID: userA)))

        expectFailure(controller.makeComposition(), .composition(.disabled))
        let startResult = await controller.start()
        expectFailure(startResult, .composition(.disabled))

        #expect(controller.isStarted == false)
        #expect(roomBoundary.makeRawSignalSenderCount == 0)
        #expect(roomBoundary.makeTimelineSignalListenerCount == 0)
    }

    @Test
    func enabledAdapterBuildsCompositionFromRoomBoundaryFakesWithoutStartingListener() async throws {
        let rawSender = MatrixRawSignalSenderSpy()
        let listener = MatrixTimelineSignalListenerSpy()
        let roomBoundary = roomBoundary(rawSender: rawSender,
                                        timelineSignalListener: listener)
        let mediaFactory = fakeMediaEngineFactory()
        let factory = enabledFactory(roomBoundary: roomBoundary,
                                     mediaEngineFactory: mediaFactory)

        guard case .success(let composition) = factory.makeComposition() else {
            Issue.record("Expected enabled joined-room native direct-call composition to build with fake room boundaries.")
            return
        }

        #expect(composition.isStarted == false)
        #expect(listener.startCount == 0)
        #expect(mediaFactory.makeMediaEngineCount == 1)
        #expect(roomBoundary.makeRawSignalSenderCount == 1)
        #expect(roomBoundary.makeTimelineSignalListenerCount == 1)

        let result = await composition.engine.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success = result else {
            Issue.record("Expected composed joined-room engine to start outgoing audio with fake boundaries.")
            return
        }

        #expect(await waitUntil { rawSender.sentSignals.count == 1 })
        let sentSignal = try #require(rawSender.sentSignals.last)
        #expect(sentSignal.eventType == DirectCallMatrixSignalCodec.eventType)

        let content = try JSONDecoder().decode(DirectCallMatrixSignalContent.self,
                                               from: #require(sentSignal.content.data(using: .utf8)))
        #expect(content.type == DirectCallSignalType.invite.rawValue)
        #expect(content.keyExchange != nil)
    }

    @Test
    func controllerCreatesAtMostOneCompositionForRoomWithoutStartingListener() {
        let listener = MatrixTimelineSignalListenerSpy()
        let roomBoundary = roomBoundary(timelineSignalListener: listener)
        let controller = enabledController(roomBoundary: roomBoundary,
                                           mediaEngineFactory: fakeMediaEngineFactory())

        guard case .success(let firstComposition) = controller.makeComposition(),
              case .success(let secondComposition) = controller.makeComposition() else {
            Issue.record("Expected controller to create and reuse a native direct-call composition.")
            return
        }

        #expect(firstComposition === secondComposition)
        #expect(controller.roomID == roomID)
        #expect(controller.isStarted == false)
        #expect(listener.startCount == 0)
        #expect(roomBoundary.makeRawSignalSenderCount == 1)
        #expect(roomBoundary.makeTimelineSignalListenerCount == 1)
    }

    @Test
    func enabledAdapterFailsClosedForUnsafeRoomMetadataBeforeCreatingRoomSignalObjects() {
        let emptyRoomID = roomBoundary(roomID: "")
        expectFailure(enabledFactory(roomBoundary: emptyRoomID,
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(),
                      .composition(.invalidRoomID))
        #expect(emptyRoomID.makeRawSignalSenderCount == 0)
        #expect(emptyRoomID.makeTimelineSignalListenerCount == 0)

        let nonDirect = roomBoundary(isDirectOneToOneRoom: false)
        expectFailure(enabledFactory(roomBoundary: nonDirect,
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(),
                      .composition(.nonDirectRoom))
        #expect(nonDirect.makeRawSignalSenderCount == 0)
        #expect(nonDirect.makeTimelineSignalListenerCount == 0)

        let nonEncrypted = roomBoundary(isEncryptedRoom: false)
        expectFailure(enabledFactory(roomBoundary: nonEncrypted,
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(),
                      .composition(.nonEncryptedRoom))
        #expect(nonEncrypted.makeRawSignalSenderCount == 0)
        #expect(nonEncrypted.makeTimelineSignalListenerCount == 0)

        let missingPeer = roomBoundary(peerUserID: nil)
        expectFailure(enabledFactory(roomBoundary: missingPeer,
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(),
                      .composition(.missingPeer))
        #expect(missingPeer.makeRawSignalSenderCount == 0)
        #expect(missingPeer.makeTimelineSignalListenerCount == 0)

        let selfPeer = roomBoundary(peerUserID: userA)
        expectFailure(enabledFactory(roomBoundary: selfPeer,
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(),
                      .composition(.missingPeer))
        #expect(selfPeer.makeRawSignalSenderCount == 0)
        #expect(selfPeer.makeTimelineSignalListenerCount == 0)
    }

    @Test
    func enabledAdapterFailsClosedForUnknownRoomMetadataBeforeCreatingRoomSignalObjects() {
        let unknownDirectMetadata = roomBoundary(isDirectOneToOneRoom: nil)
        expectFailure(enabledFactory(roomBoundary: unknownDirectMetadata,
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(),
                      .unknownRoomMetadata)
        #expect(unknownDirectMetadata.makeRawSignalSenderCount == 0)
        #expect(unknownDirectMetadata.makeTimelineSignalListenerCount == 0)

        let unknownEncryptedMetadata = roomBoundary(isEncryptedRoom: nil)
        expectFailure(enabledFactory(roomBoundary: unknownEncryptedMetadata,
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(),
                      .unknownRoomMetadata)
        #expect(unknownEncryptedMetadata.makeRawSignalSenderCount == 0)
        #expect(unknownEncryptedMetadata.makeTimelineSignalListenerCount == 0)
    }

    @Test
    func enabledAdapterFailsClosedWhenSenderOrListenerCannotBeCreated() {
        expectFailure(enabledFactory(roomBoundary: roomBoundary(createsRawSender: false),
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(),
                      .missingSignalSender)

        expectFailure(enabledFactory(roomBoundary: roomBoundary(createsTimelineSignalListener: false),
                                     mediaEngineFactory: fakeMediaEngineFactory()).makeComposition(),
                      .missingTimelineListener)
    }

    @Test
    func listenerStartsOnlyWhenCompositionIsExplicitlyStartedAndStopsIdempotently() async {
        let listener = MatrixTimelineSignalListenerSpy()
        let controller = enabledController(roomBoundary: roomBoundary(timelineSignalListener: listener),
                                           mediaEngineFactory: fakeMediaEngineFactory())

        guard case .success = await controller.start() else {
            Issue.record("Expected enabled joined-room composition to build.")
            return
        }

        #expect(controller.isStarted)
        #expect(listener.startCount == 1)
        #expect(listener.cancelCount == 0)

        _ = await controller.start()

        #expect(controller.isStarted)
        #expect(listener.startCount == 1)
        #expect(listener.cancelCount == 0)

        controller.stop()
        controller.stop()

        #expect(controller.isStarted == false)
        #expect(listener.startCount == 1)
        #expect(listener.cancelCount == 1)
    }

    @Test
    func controllerDeinitStopsStartedListener() async {
        let listener = MatrixTimelineSignalListenerSpy()
        var controller: JoinedRoomNativeDirectCallCompositionController? = enabledController(roomBoundary: roomBoundary(timelineSignalListener: listener),
                                                                                             mediaEngineFactory: fakeMediaEngineFactory())

        guard let startResult = await controller?.start(),
              case .success = startResult else {
            Issue.record("Expected enabled joined-room controller to start.")
            return
        }

        #expect(listener.startCount == 1)
        #expect(listener.cancelCount == 0)

        controller = nil

        #expect(listener.startCount == 1)
        #expect(await waitUntil { listener.cancelCount == 1 })
    }

    @Test
    func missingMediaFactoryUsesNoOpFailClosedPath() async {
        let factory = enabledFactory(roomBoundary: roomBoundary(),
                                     mediaEngineFactory: nil)

        guard case .success(let composition) = factory.makeComposition() else {
            Issue.record("Expected enabled joined-room composition to build with default NoOp media factory.")
            return
        }

        let outgoingResult = await composition.engine.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let session) = outgoingResult else {
            Issue.record("Expected outgoing call start to succeed before NoOp media connection.")
            return
        }

        let answerEvent = DirectCallSignalEvent(eventID: "$answer",
                                                roomID: roomID,
                                                senderID: userB,
                                                callID: session.callID,
                                                type: .answer,
                                                intent: nil,
                                                timestamp: .now)
        let answerResult = await composition.engine.receiveIncomingCall(event: answerEvent)
        expectFailure(answerResult, .mediaConnectionFailed)
        #expect(composition.engine.activeSessionPublisher.value?.state == .failed)
    }

    @Test
    func controllerResetStopsExistingCompositionAndAllowsExplicitRecreation() async {
        let listener = MatrixTimelineSignalListenerSpy()
        let roomBoundary = roomBoundary(timelineSignalListener: listener)
        let controller = enabledController(roomBoundary: roomBoundary,
                                           mediaEngineFactory: fakeMediaEngineFactory())

        guard case .success(let firstComposition) = controller.makeComposition() else {
            Issue.record("Expected controller to create a native direct-call composition.")
            return
        }

        guard case .success = await controller.start() else {
            Issue.record("Expected enabled joined-room controller to start.")
            return
        }

        controller.reset()

        guard case .success(let secondComposition) = controller.makeComposition() else {
            Issue.record("Expected controller to recreate a native direct-call composition after reset.")
            return
        }

        #expect(firstComposition !== secondComposition)
        #expect(controller.isStarted == false)
        #expect(listener.startCount == 1)
        #expect(listener.cancelCount == 1)
        #expect(roomBoundary.makeRawSignalSenderCount == 2)
        #expect(roomBoundary.makeTimelineSignalListenerCount == 2)
    }

    @Test
    func joinedRoomPeerResolutionRequiresExactlyOneActiveNonSelfMember() {
        #expect(JoinedRoomProxy.nativeDirectCallPeerUserID(ownUserID: userA,
                                                           members: [member(userB)]) == userB)
        #expect(JoinedRoomProxy.nativeDirectCallPeerUserID(ownUserID: userA,
                                                           members: [member(userA),
                                                                     member(userB)]) == userB)
        #expect(JoinedRoomProxy.nativeDirectCallPeerUserID(ownUserID: userA,
                                                           members: [member(userB, membership: .leave)]) == nil)
        #expect(JoinedRoomProxy.nativeDirectCallPeerUserID(ownUserID: userA,
                                                           members: [member(userB),
                                                                     member("@c:example.com")]) == nil)
    }

    private func enabledFactory(roomBoundary: JoinedRoomNativeDirectCallCompositionBoundarySpy,
                                mediaEngineFactory: DirectCallMediaEngineFactoryProtocol?) -> JoinedRoomNativeDirectCallCompositionFactory {
        .init(roomBoundary: roomBoundary,
              configuration: .init(isEnabled: true,
                                   engineConfiguration: .init(incomingRingingTimeout: .seconds(120),
                                                              outgoingRingingTimeout: .seconds(120),
                                                              connectingTimeout: .seconds(120),
                                                              cleanupDelay: .seconds(120),
                                                              processedTerminalEventLimit: 64)),
              mediaEngineFactory: mediaEngineFactory,
              encryptionService: SignalEncryptionServiceSpy(senderUserID: userA))
    }

    private func enabledController(roomBoundary: JoinedRoomNativeDirectCallCompositionBoundarySpy,
                                   mediaEngineFactory: DirectCallMediaEngineFactoryProtocol?) -> JoinedRoomNativeDirectCallCompositionController {
        .init(roomID: roomBoundary.nativeDirectCallRoomID,
              factory: enabledFactory(roomBoundary: roomBoundary,
                                      mediaEngineFactory: mediaEngineFactory))
    }

    private func roomBoundary(roomID: String? = nil,
                              ownUserID: String? = nil,
                              isDirectOneToOneRoom: Bool? = true,
                              isEncryptedRoom: Bool? = true,
                              peerUserID: String? = "@b:example.com",
                              createsRawSender: Bool = true,
                              createsTimelineSignalListener: Bool = true,
                              rawSender: DirectCallMatrixRawSignalSending? = nil,
                              timelineSignalListener: DirectCallMatrixTimelineSignalListening? = nil) -> JoinedRoomNativeDirectCallCompositionBoundarySpy {
        .init(roomID: roomID ?? self.roomID,
              ownUserID: ownUserID ?? userA,
              isDirectOneToOneRoom: isDirectOneToOneRoom,
              isEncryptedRoom: isEncryptedRoom,
              peerUserID: peerUserID,
              rawSender: createsRawSender ? (rawSender ?? MatrixRawSignalSenderSpy()) : nil,
              timelineSignalListener: createsTimelineSignalListener ? (timelineSignalListener ?? MatrixTimelineSignalListenerSpy()) : nil)
    }

    private func fakeMediaEngineFactory() -> SignalMediaEngineFactorySpy {
        SignalMediaEngineFactorySpy(mediaEngine: SignalMediaEngineSpy())
    }

    private func member(_ userID: String, membership: MembershipState = .join) -> RoomMemberProxyProtocol {
        RoomMemberProxyMock(with: .init(userID: userID,
                                        displayName: nil,
                                        avatarURL: nil,
                                        membership: membership))
    }

    private func expectFailure(_ result: Result<NativeDirectCallComposition, JoinedRoomNativeDirectCallCompositionError>,
                               _ expectedError: JoinedRoomNativeDirectCallCompositionError) {
        guard case .failure(let error) = result else {
            Issue.record("Expected joined-room native direct-call composition to fail closed with \(expectedError).")
            return
        }

        #expect(error == expectedError)
    }

    private func expectFailure(_ result: Result<DirectCallSession?, DirectCallEngineError>,
                               _ expectedError: DirectCallEngineError) {
        guard case .failure(let error) = result else {
            Issue.record("Expected composed engine to fail closed with \(expectedError).")
            return
        }

        #expect(error == expectedError)
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           checkInterval: Duration = .milliseconds(20),
                           condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: checkInterval)
        }
        return condition()
    }
}

@MainActor
final class NativeDirectCallRoomControllerTests {
    private let userA = "@a:example.com"
    private let userB = "@b:example.com"
    private let roomID = "!dm:example.com"

    @Test
    func disabledDefaultRejectsRoomControlCommandsSafely() async {
        let harness = roomControlHarness(isEnabled: false)

        expectFailure(harness.controller.prepare(), .composition(.composition(.disabled)))
        await expectFailure(harness.controller.startOutgoingAudioCall(), .composition(.composition(.disabled)))
        await expectFailure(harness.controller.acceptIncomingCall(), .composition(.composition(.disabled)))
        await expectFailure(harness.controller.hangup(), .composition(.composition(.disabled)))

        await harness.controller.reset()

        #expect(harness.controller.isListenerStarted == false)
        #expect(harness.rawSender.sentSignals.isEmpty)
        #expect(harness.listener.startCount == 0)
        #expect(harness.listener.cancelCount == 0)
        #expect(harness.mediaEngine.connectedSessions.isEmpty)
    }

    @Test
    func disabledDeveloperTriggerRejectsRoomCommandsSafely() async {
        let harness = roomControlHarness()
        let trigger = NativeDirectCallDeveloperRoomTrigger(controller: harness.controller)

        expectFailure(trigger.prepare(), .disabled)
        await expectFailure(trigger.startListener(), .disabled)
        await expectFailure(trigger.startOutgoingAudioCall(), .disabled)
        await expectFailure(trigger.acceptIncomingCall(), .disabled)
        await expectFailure(trigger.hangup(), .disabled)
        expectFailure(trigger.stop(), .disabled)
        await expectFailure(trigger.reset(), .disabled)

        #expect(trigger.isListenerStarted == false)
        #expect(trigger.activeSession == nil)
        #expect(harness.rawSender.sentSignals.isEmpty)
        #expect(harness.listener.startCount == 0)
        #expect(harness.listener.cancelCount == 0)
        #expect(harness.mediaEngine.connectedSessions.isEmpty)
    }

    @Test
    func enabledControllerRejectsAcceptAndHangupWithoutActiveSession() async {
        let harness = roomControlHarness()

        guard case .success = harness.controller.prepare() else {
            Issue.record("Expected enabled native direct-call room controller to prepare.")
            return
        }

        await expectFailure(harness.controller.acceptIncomingCall(), .noIncomingCall)
        await expectFailure(harness.controller.hangup(), .noActiveCall)

        #expect(harness.controller.activeSession == nil)
        #expect(harness.rawSender.sentSignals.isEmpty)
        #expect(harness.mediaEngine.connectedSessions.isEmpty)
    }

    @Test
    func enabledDeveloperTriggerPreparesWithoutAutoStartingListener() {
        let harness = roomControlHarness()
        let trigger = enabledTrigger(controller: harness.controller)

        guard case .success = trigger.prepare() else {
            Issue.record("Expected enabled native direct-call developer trigger to prepare.")
            return
        }

        #expect(trigger.isListenerStarted == false)
        #expect(trigger.activeSession == nil)
        #expect(harness.listener.startCount == 0)
        #expect(harness.listener.cancelCount == 0)
        #expect(harness.rawSender.sentSignals.isEmpty)
    }

    @Test
    func enabledControllerStartsAndStopsListenerOnlyWhenExplicitlyRequested() async {
        let harness = roomControlHarness()

        guard case .success = harness.controller.prepare() else {
            Issue.record("Expected enabled native direct-call room controller to prepare.")
            return
        }

        #expect(harness.controller.isListenerStarted == false)
        #expect(harness.listener.startCount == 0)

        _ = await harness.controller.start()
        _ = await harness.controller.start()

        #expect(harness.controller.isListenerStarted)
        #expect(harness.listener.startCount == 1)
        #expect(harness.listener.cancelCount == 0)

        harness.controller.stop()
        harness.controller.stop()

        #expect(harness.controller.isListenerStarted == false)
        #expect(harness.listener.startCount == 1)
        #expect(harness.listener.cancelCount == 1)
    }

    @Test
    func enabledDeveloperTriggerStartsStopsAndResetsListenerExplicitly() async {
        let harness = roomControlHarness()
        let trigger = enabledTrigger(controller: harness.controller)

        guard case .success = trigger.prepare() else {
            Issue.record("Expected enabled native direct-call developer trigger to prepare.")
            return
        }

        #expect(trigger.isListenerStarted == false)
        #expect(harness.listener.startCount == 0)

        _ = await trigger.startListener()
        _ = await trigger.startListener()

        #expect(trigger.isListenerStarted)
        #expect(harness.listener.startCount == 1)
        #expect(harness.listener.cancelCount == 0)

        guard case .success = trigger.stop() else {
            Issue.record("Expected enabled native direct-call developer trigger to stop.")
            return
        }

        guard case .success = trigger.stop() else {
            Issue.record("Expected repeated native direct-call developer trigger stop to remain safe.")
            return
        }

        #expect(trigger.isListenerStarted == false)
        #expect(harness.listener.startCount == 1)
        #expect(harness.listener.cancelCount == 1)

        guard case .success = await trigger.reset() else {
            Issue.record("Expected enabled native direct-call developer trigger to reset.")
            return
        }

        guard case .success = await trigger.reset() else {
            Issue.record("Expected repeated native direct-call developer trigger reset to remain safe.")
            return
        }

        #expect(trigger.isListenerStarted == false)
        #expect(trigger.activeSession == nil)
        #expect(harness.listener.cancelCount == 1)
    }

    @Test
    func outgoingCallUsesGatedPeerAndSendsInviteThroughRoomTransport() async throws {
        let harness = roomControlHarness()

        let result = await harness.controller.startOutgoingAudioCall()
        guard case .success(let session) = result else {
            Issue.record("Expected native direct-call room controller to start outgoing audio.")
            return
        }

        #expect(session.roomID == roomID)
        #expect(session.peerUserID == userB)
        #expect(harness.listener.startCount == 0)
        #expect(await waitUntil { harness.rawSender.sentSignals.count == 1 })

        let sentSignal = try #require(harness.rawSender.sentSignals.last)
        #expect(sentSignal.roomID == roomID)
        #expect(sentSignal.eventType == DirectCallMatrixSignalCodec.eventType)

        let content = try JSONDecoder().decode(DirectCallMatrixSignalContent.self,
                                               from: #require(sentSignal.content.data(using: .utf8)))
        #expect(content.type == DirectCallSignalType.invite.rawValue)
        #expect(content.intent == DirectCallIntent.audio.rawValue)
        #expect(content.keyExchange?.senderUserID == userA)
        #expect(content.keyExchange?.callID == session.callID)
    }

    @Test
    func developerTriggerOutgoingCallSendsInviteThroughRoomTransport() async throws {
        let harness = roomControlHarness()
        let trigger = enabledTrigger(controller: harness.controller)

        let result = await trigger.startOutgoingAudioCall()
        guard case .success(let session) = result else {
            Issue.record("Expected native direct-call developer trigger to start outgoing audio.")
            return
        }

        #expect(session.roomID == roomID)
        #expect(session.peerUserID == userB)
        #expect(harness.listener.startCount == 0)
        #expect(await waitUntil { harness.rawSender.sentSignals.count == 1 })

        let sentSignal = try #require(harness.rawSender.sentSignals.last)
        #expect(sentSignal.roomID == roomID)
        #expect(sentSignal.eventType == DirectCallMatrixSignalCodec.eventType)

        let content = try JSONDecoder().decode(DirectCallMatrixSignalContent.self,
                                               from: #require(sentSignal.content.data(using: .utf8)))
        #expect(content.type == DirectCallSignalType.invite.rawValue)
        #expect(content.intent == DirectCallIntent.audio.rawValue)
        #expect(content.keyExchange?.senderUserID == userA)
        #expect(content.keyExchange?.callID == session.callID)
    }

    @Test
    func outgoingCallStatusRecordsRedactedInviteSendBreadcrumbs() async {
        let harness = roomControlHarness()

        let result = await harness.controller.startOutgoingAudioCall()
        guard case .success = result else {
            Issue.record("Expected native direct-call room controller to start outgoing audio.")
            return
        }

        #expect(await waitUntil { harness.controller.diagnosticSnapshot.lastSignalSendSucceeded == true })

        let diagnostics = harness.controller.diagnosticSnapshot
        #expect(diagnostics.activeSessionPhase == .outgoingRinging)
        #expect(diagnostics.lastSignalEventEmitted == .invite)
        #expect(diagnostics.lastSignalSendAttempted)
        #expect(diagnostics.lastSignalSendSucceeded == true)
        #expect(diagnostics.lastSignalSendFailureReason == nil)
        #expect(diagnostics.lastTerminalReason == nil)
        #expect(String(describing: diagnostics).contains(roomID) == false)
        #expect(String(describing: diagnostics).contains(userB) == false)
    }

    @Test
    func outgoingCallStatusRecordsRedactedSignalSendFailure() async {
        let harness = roomControlHarness()
        harness.rawSender.result = .failure(.sendFailed)

        let result = await harness.controller.startOutgoingAudioCall()
        guard case .success = result else {
            Issue.record("Expected engine to accept outgoing command before async send result is known.")
            return
        }

        #expect(await waitUntil { harness.controller.diagnosticSnapshot.lastSignalSendSucceeded == false })

        let diagnostics = harness.controller.diagnosticSnapshot
        #expect(diagnostics.activeSessionPhase == .outgoingRinging)
        #expect(diagnostics.lastSignalEventEmitted == .invite)
        #expect(diagnostics.lastSignalSendAttempted)
        #expect(diagnostics.lastSignalSendSucceeded == false)
        #expect(diagnostics.lastSignalSendFailureReason == .sendFailed)
        #expect(diagnostics.lastTerminalReason == nil)
        #expect(String(describing: diagnostics).contains(roomID) == false)
        #expect(String(describing: diagnostics).contains(userB) == false)
    }

    @Test
    func outgoingCallStatusRecordsRedactedTimeoutCleanupReason() async {
        let harness = roomControlHarness(outgoingRingingTimeout: .milliseconds(20),
                                         cleanupDelay: .milliseconds(20))

        let result = await harness.controller.startOutgoingAudioCall()
        guard case .success = result else {
            Issue.record("Expected native direct-call room controller to start outgoing audio.")
            return
        }

        #expect(await waitUntil(timeout: .seconds(1)) {
            harness.controller.diagnosticSnapshot.lastTerminalReason == .outgoingTimeout &&
                harness.controller.diagnosticSnapshot.activeSessionPhase == .none
        })
        #expect(harness.controller.activeSession == nil)

        let diagnostics = harness.controller.diagnosticSnapshot
        #expect(diagnostics.lastSignalEventEmitted == .invite)
        #expect(diagnostics.lastSignalSendAttempted)
        #expect(diagnostics.lastSignalSendSucceeded == true)
        #expect(diagnostics.lastTerminalReason == .outgoingTimeout)
        #expect(String(describing: diagnostics).contains(roomID) == false)
        #expect(String(describing: diagnostics).contains(userB) == false)
    }

    @Test
    func roomControllersDriveIncomingAcceptHangupAndTerminalCleanupWithFakes() async throws {
        let harness = roomPairHarness(cleanupDelay: .seconds(120))

        _ = await harness.controllerA.start()
        _ = await harness.controllerB.start()

        let outgoingResult = await harness.controllerA.startOutgoingAudioCall()
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected caller room controller to start outgoing audio.")
            return
        }

        #expect(await waitUntil { harness.senderA.sentSignals.count == 1 })
        try emitMatrixSignal(#require(harness.senderA.sentSignals.last),
                             eventID: "$room-invite",
                             senderUserID: userA,
                             ownUserID: userB,
                             to: harness.listenerB)

        #expect(await waitUntil { harness.controllerB.activeSession?.state == .incomingRinging })
        #expect(harness.controllerB.activeSession?.callID == outgoingSession.callID)

        guard case .success(let acceptedSession) = await harness.controllerB.acceptIncomingCall() else {
            Issue.record("Expected callee room controller to accept incoming call.")
            return
        }

        #expect(acceptedSession.state == .activeAudio)
        #expect(harness.mediaEngineB.connectedSessions.map(\.callID) == [outgoingSession.callID])
        #expect(await waitUntil { harness.senderB.sentSignals.count == 1 })

        try emitMatrixSignal(#require(harness.senderB.sentSignals.last),
                             eventID: "$room-answer",
                             senderUserID: userB,
                             ownUserID: userA,
                             to: harness.listenerA)

        #expect(await waitUntil { harness.controllerA.activeSession?.state == .activeAudio })
        #expect(harness.mediaEngineA.connectedSessions.map(\.callID) == [outgoingSession.callID])

        guard case .success(let hangupSession) = await harness.controllerB.hangup() else {
            Issue.record("Expected callee room controller to hang up active call.")
            return
        }

        #expect(hangupSession.state == .ended)
        #expect(harness.mediaEngineB.disconnectCallIDs == [outgoingSession.callID])
        #expect(await waitUntil { harness.senderB.sentSignals.count == 2 })

        let terminalEnvelope = try matrixEnvelope(from: #require(harness.senderB.sentSignals.last),
                                                  eventID: "$room-terminal",
                                                  senderUserID: userB,
                                                  ownUserID: userA)
        harness.listenerA.emit(terminalEnvelope)
        #expect(await waitUntil { harness.controllerA.activeSession?.state == .ended })
        #expect(harness.mediaEngineA.disconnectCallIDs == [outgoingSession.callID])

        harness.listenerA.emit(terminalEnvelope)
        await Task.yield()
        #expect(harness.mediaEngineA.disconnectCallIDs == [outgoingSession.callID])

        await harness.controllerB.reset()
        await harness.controllerA.reset()

        #expect(harness.mediaEngineB.cleanupCallIDs == [outgoingSession.callID])
        #expect(harness.mediaEngineA.cleanupCallIDs == [outgoingSession.callID])
        #expect(harness.controllerA.activeSession == nil)
        #expect(harness.controllerB.activeSession == nil)
    }

    @Test
    func developerTriggersDriveIncomingAcceptHangupAndTerminalCleanupWithFakes() async throws {
        let harness = roomPairHarness(cleanupDelay: .seconds(120))
        let triggerA = enabledTrigger(controller: harness.controllerA)
        let triggerB = enabledTrigger(controller: harness.controllerB)

        _ = await triggerA.startListener()
        _ = await triggerB.startListener()

        let outgoingResult = await triggerA.startOutgoingAudioCall()
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected caller developer trigger to start outgoing audio.")
            return
        }

        #expect(await waitUntil { harness.senderA.sentSignals.count == 1 })
        try emitMatrixSignal(#require(harness.senderA.sentSignals.last),
                             eventID: "$trigger-invite",
                             senderUserID: userA,
                             ownUserID: userB,
                             to: harness.listenerB)

        #expect(await waitUntil { triggerB.activeSession?.state == .incomingRinging })
        #expect(triggerB.activeSession?.callID == outgoingSession.callID)

        guard case .success(let acceptedSession) = await triggerB.acceptIncomingCall() else {
            Issue.record("Expected callee developer trigger to accept incoming call.")
            return
        }

        #expect(acceptedSession.state == .activeAudio)
        #expect(harness.mediaEngineB.connectedSessions.map(\.callID) == [outgoingSession.callID])
        #expect(await waitUntil { harness.senderB.sentSignals.count == 1 })

        try emitMatrixSignal(#require(harness.senderB.sentSignals.last),
                             eventID: "$trigger-answer",
                             senderUserID: userB,
                             ownUserID: userA,
                             to: harness.listenerA)

        #expect(await waitUntil { triggerA.activeSession?.state == .activeAudio })
        #expect(harness.mediaEngineA.connectedSessions.map(\.callID) == [outgoingSession.callID])

        guard case .success(let hangupSession) = await triggerB.hangup() else {
            Issue.record("Expected callee developer trigger to hang up active call.")
            return
        }

        #expect(hangupSession.state == .ended)
        #expect(harness.mediaEngineB.disconnectCallIDs == [outgoingSession.callID])
        #expect(await waitUntil { harness.senderB.sentSignals.count == 2 })

        let terminalEnvelope = try matrixEnvelope(from: #require(harness.senderB.sentSignals.last),
                                                  eventID: "$trigger-terminal",
                                                  senderUserID: userB,
                                                  ownUserID: userA)
        harness.listenerA.emit(terminalEnvelope)
        #expect(await waitUntil { triggerA.activeSession?.state == .ended })
        #expect(harness.mediaEngineA.disconnectCallIDs == [outgoingSession.callID])

        harness.listenerA.emit(terminalEnvelope)
        await Task.yield()
        #expect(harness.mediaEngineA.disconnectCallIDs == [outgoingSession.callID])

        _ = await triggerB.reset()
        _ = await triggerA.reset()

        #expect(harness.mediaEngineB.cleanupCallIDs == [outgoingSession.callID])
        #expect(harness.mediaEngineA.cleanupCallIDs == [outgoingSession.callID])
        #expect(triggerA.activeSession == nil)
        #expect(triggerB.activeSession == nil)
    }

    @Test
    func resetStopsListenerAndCancelsUnansweredOutgoingCall() async {
        let harness = roomControlHarness(cleanupDelay: .seconds(120))

        _ = await harness.controller.start()
        let outgoingResult = await harness.controller.startOutgoingAudioCall()
        guard case .success(let session) = outgoingResult else {
            Issue.record("Expected native direct-call room controller to start outgoing audio.")
            return
        }

        #expect(await waitUntil { harness.rawSender.sentSignals.count == 1 })
        await harness.controller.reset()

        #expect(harness.controller.isListenerStarted == false)
        #expect(harness.controller.activeSession == nil)
        #expect(harness.listener.cancelCount == 1)
        #expect(harness.mediaEngine.cleanupCallIDs == [session.callID])
        #expect(await waitUntil { harness.rawSender.sentSignals.count == 2 })
        #expect(harness.rawSender.sentSignals.compactMap { signalType(from: $0.content) } == [.invite, .cancel])
    }

    private func roomPairHarness(cleanupDelay: Duration = .seconds(120)) -> NativeDirectCallRoomPairHarness {
        let caller = roomControlHarness(ownUserID: userA,
                                        peerUserID: userB,
                                        cleanupDelay: cleanupDelay)
        let callee = roomControlHarness(ownUserID: userB,
                                        peerUserID: userA,
                                        cleanupDelay: cleanupDelay)

        return .init(controllerA: caller.controller,
                     controllerB: callee.controller,
                     senderA: caller.rawSender,
                     senderB: callee.rawSender,
                     listenerA: caller.listener,
                     listenerB: callee.listener,
                     mediaEngineA: caller.mediaEngine,
                     mediaEngineB: callee.mediaEngine)
    }

    private func roomControlHarness(ownUserID: String? = nil,
                                    peerUserID: String? = nil,
                                    isEnabled: Bool = true,
                                    outgoingRingingTimeout: Duration = .seconds(120),
                                    cleanupDelay: Duration = .seconds(120)) -> NativeDirectCallRoomControlHarness {
        let ownUserID = ownUserID ?? userA
        let peerUserID = peerUserID ?? userB
        let rawSender = MatrixRawSignalSenderSpy()
        let listener = MatrixTimelineSignalListenerSpy()
        let mediaEngine = SignalMediaEngineSpy()
        let roomBoundary = JoinedRoomNativeDirectCallCompositionBoundarySpy(roomID: roomID,
                                                                            ownUserID: ownUserID,
                                                                            isDirectOneToOneRoom: true,
                                                                            isEncryptedRoom: true,
                                                                            peerUserID: peerUserID,
                                                                            rawSender: rawSender,
                                                                            timelineSignalListener: listener)
        let factory = JoinedRoomNativeDirectCallCompositionFactory(roomBoundary: roomBoundary,
                                                                   configuration: .init(isEnabled: isEnabled,
                                                                                        engineConfiguration: .init(incomingRingingTimeout: .seconds(120),
                                                                                                                   outgoingRingingTimeout: outgoingRingingTimeout,
                                                                                                                   connectingTimeout: .seconds(120),
                                                                                                                   cleanupDelay: cleanupDelay,
                                                                                                                   processedTerminalEventLimit: 64)),
                                                                   mediaEngineFactory: SignalMediaEngineFactorySpy(mediaEngine: mediaEngine),
                                                                   encryptionService: SignalEncryptionServiceSpy(senderUserID: ownUserID))
        let compositionController = JoinedRoomNativeDirectCallCompositionController(roomID: roomID,
                                                                                    factory: factory)

        return .init(controller: NativeDirectCallRoomController(compositionController: compositionController),
                     rawSender: rawSender,
                     listener: listener,
                     mediaEngine: mediaEngine)
    }

    private func enabledTrigger(controller: NativeDirectCallRoomController) -> NativeDirectCallDeveloperRoomTrigger {
        NativeDirectCallDeveloperRoomTrigger(configuration: .init(isEnabled: true),
                                             controller: controller)
    }

    private func emitMatrixSignal(_ signal: SentRawSignal,
                                  eventID: String,
                                  senderUserID: String,
                                  ownUserID: String,
                                  to listener: MatrixTimelineSignalListenerSpy) throws {
        try listener.emit(matrixEnvelope(from: signal,
                                         eventID: eventID,
                                         senderUserID: senderUserID,
                                         ownUserID: ownUserID))
    }

    private func matrixEnvelope(from signal: SentRawSignal,
                                eventID: String,
                                senderUserID: String,
                                ownUserID: String) throws -> DirectCallMatrixSignalEnvelope {
        .init(eventID: eventID,
              roomID: signal.roomID,
              senderUserID: senderUserID,
              ownUserID: ownUserID,
              isDirectOneToOneRoom: true,
              isEncryptedRoom: true,
              timestamp: .now,
              rawContent: signal.content)
    }

    private func expectFailure<T>(_ result: Result<T, NativeDirectCallRoomControlError>,
                                  _ expectedError: NativeDirectCallRoomControlError) {
        guard case .failure(let error) = result else {
            Issue.record("Expected native direct-call room controller to fail closed with \(expectedError).")
            return
        }

        #expect(error == expectedError)
    }

    private func expectFailure<T>(_ result: Result<T, NativeDirectCallDeveloperRoomTriggerError>,
                                  _ expectedError: NativeDirectCallDeveloperRoomTriggerError) {
        guard case .failure(let error) = result else {
            Issue.record("Expected native direct-call developer trigger to fail closed with \(expectedError).")
            return
        }

        #expect(error == expectedError)
    }

    private func signalType(from rawContent: String) -> DirectCallSignalType? {
        guard let data = rawContent.data(using: .utf8),
              let content = try? JSONDecoder().decode(DirectCallMatrixSignalContent.self, from: data) else {
            return nil
        }

        return DirectCallSignalType(rawValue: content.type)
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           checkInterval: Duration = .milliseconds(20),
                           condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: checkInterval)
        }
        return condition()
    }
}

private struct NativeDirectCallRoomControlHarness {
    let controller: NativeDirectCallRoomController
    let rawSender: MatrixRawSignalSenderSpy
    let listener: MatrixTimelineSignalListenerSpy
    let mediaEngine: SignalMediaEngineSpy
}

private struct NativeDirectCallRoomPairHarness {
    let controllerA: NativeDirectCallRoomController
    let controllerB: NativeDirectCallRoomController
    let senderA: MatrixRawSignalSenderSpy
    let senderB: MatrixRawSignalSenderSpy
    let listenerA: MatrixTimelineSignalListenerSpy
    let listenerB: MatrixTimelineSignalListenerSpy
    let mediaEngineA: SignalMediaEngineSpy
    let mediaEngineB: SignalMediaEngineSpy
}

private struct Harness {
    let transport: InMemoryDirectCallSignalTransport
    let engineA: DirectCallEngine
    let engineB: DirectCallEngine
    let bridgeA: DirectCallEngineSignalBridge
    let bridgeB: DirectCallEngineSignalBridge
}

@MainActor
private struct MatrixHarness {
    let senderA: MatrixRawSignalSenderSpy
    let senderB: MatrixRawSignalSenderSpy
    let listenerA: MatrixTimelineSignalListenerSpy
    let listenerB: MatrixTimelineSignalListenerSpy
    let mediaEngineA: SignalMediaEngineSpy
    let mediaEngineB: SignalMediaEngineSpy
    let mediaFactoryA: SignalMediaEngineFactorySpy
    let mediaFactoryB: SignalMediaEngineFactorySpy
    let transportA: MatrixDirectCallSignalTransport
    let transportB: MatrixDirectCallSignalTransport
    let engineA: DirectCallEngine
    let engineB: DirectCallEngine
    let bridgeA: DirectCallEngineSignalBridge
    let bridgeB: DirectCallEngineSignalBridge

    func stop() {
        transportA.stop()
        transportB.stop()
    }
}

@MainActor
final class MatrixDirectCallEngineIntegrationTests {
    private let userA = "@a:example.com"
    private let userB = "@b:example.com"
    private let roomID = "!dm:example.com"

    @Test
    func matrixSignalTransportBridgeDrivesInviteAnswerAndHangupAcrossEngines() async throws {
        let harness = await makeMatrixHarness(cleanupDelay: .seconds(1))
        defer { harness.stop() }

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing Matrix direct call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.senderA.sentSignals.count == 1 })
        let inviteSignal = try #require(harness.senderA.sentSignals.last)
        #expect(inviteSignal.eventType == DirectCallMatrixSignalCodec.eventType)

        let inviteEvent = DirectCallMatrixSignalCodec.decode(matrixEnvelope(rawContent: inviteSignal.content))
        #expect(inviteEvent?.type == .invite)
        #expect(inviteEvent?.keyExchange?.callID == outgoingSession.callID)

        emitMatrixSignal(inviteSignal,
                         eventID: "$matrix-invite",
                         senderUserID: userA,
                         ownUserID: userB,
                         to: harness.listenerB)

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })
        #expect(harness.bridgeB.diagnosticSnapshot.envelopeExtractedCount == 1)
        #expect(harness.bridgeB.diagnosticSnapshot.envelopeDeliveredToEngineCount == 1)
        #expect(harness.bridgeB.diagnosticSnapshot.lastReceiveEventKind == .directCallInvite)
        #expect(harness.bridgeB.diagnosticSnapshot.lastEnvelopeRejectedReason == .none)
        #expect(harness.engineB.activeSessionPublisher.value?.callID == outgoingSession.callID)

        _ = await harness.engineB.acceptCall(callID: outgoingSession.callID)

        #expect(await waitUntil { harness.senderB.sentSignals.count == 1 })
        let answerSignal = try #require(harness.senderB.sentSignals.last)
        let answerEvent = DirectCallMatrixSignalCodec.decode(matrixEnvelope(senderUserID: userB,
                                                                            ownUserID: userA,
                                                                            rawContent: answerSignal.content))
        #expect(answerEvent?.type == .answer)

        emitMatrixSignal(answerSignal,
                         eventID: "$matrix-answer",
                         senderUserID: userB,
                         ownUserID: userA,
                         to: harness.listenerA)

        #expect(await waitUntil { harness.engineA.activeSessionPublisher.value?.state == .activeAudio })
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .activeAudio })
        #expect(harness.mediaEngineA.connectedSessions.map(\.callID) == [outgoingSession.callID])
        #expect(harness.mediaEngineB.connectedSessions.map(\.callID) == [outgoingSession.callID])
        #expect(harness.mediaEngineA.connectedKeyHandles == [.init(callID: outgoingSession.callID,
                                                                   keyID: "key-\(outgoingSession.callID)")])
        #expect(harness.mediaEngineB.connectedKeyHandles == [.init(callID: outgoingSession.callID,
                                                                   keyID: "key-\(outgoingSession.callID)")])
        #expect(harness.mediaFactoryA.makeMediaEngineCount == 1)
        #expect(harness.mediaFactoryB.makeMediaEngineCount == 1)

        var receiverStateChanges = 0
        let receiverStateCancellable = harness.engineB.actionsPublisher.sink { action in
            if case .stateChanged = action {
                receiverStateChanges += 1
            }
        }
        defer { receiverStateCancellable.cancel() }

        _ = await harness.engineA.hangupActiveCall(callID: outgoingSession.callID)

        #expect(await waitUntil { harness.senderA.sentSignals.count == 2 })
        #expect(harness.mediaEngineA.disconnectCallIDs == [outgoingSession.callID])
        await harness.engineA.cleanupCall(callID: outgoingSession.callID)
        #expect(harness.mediaEngineA.cleanupCallIDs == [outgoingSession.callID])
        let hangupSignal = try #require(harness.senderA.sentSignals.last)
        let terminalEnvelope = matrixEnvelope(from: hangupSignal,
                                              eventID: "$matrix-terminal",
                                              senderUserID: userA,
                                              ownUserID: userB)
        harness.listenerB.emit(terminalEnvelope)

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .ended })
        #expect(harness.mediaEngineB.disconnectCallIDs == [outgoingSession.callID])
        let stateChangesAfterFirstTerminal = receiverStateChanges

        harness.listenerB.emit(terminalEnvelope)
        await Task.yield()

        #expect(harness.engineB.activeSessionPublisher.value?.state == .ended)
        #expect(harness.bridgeB.diagnosticSnapshot.lastEnvelopeRejectedReason == .duplicateEventID)
        #expect(receiverStateChanges == stateChangesAfterFirstTerminal)
        #expect(harness.mediaEngineB.disconnectCallIDs == [outgoingSession.callID])
    }

    @Test
    func matrixSignalTransportBridgeIgnoresOwnMalformedAndFilteredEnvelopes() async throws {
        let harness = await makeMatrixHarness(cleanupDelay: .seconds(1))
        defer { harness.stop() }

        let validContent = DirectCallMatrixSignalContent(callID: "call-valid",
                                                         type: DirectCallSignalType.invite.rawValue,
                                                         intent: DirectCallIntent.audio.rawValue,
                                                         recipient: userB,
                                                         keyExchange: keyExchange(callID: "call-valid", senderUserID: userA))

        harness.listenerB.emit(matrixEnvelope(eventID: "$malformed", rawContent: "{not-json"))
        try harness.listenerB.emit(matrixEnvelope(eventID: "$own",
                                                  senderUserID: userB,
                                                  rawContent: json(for: validContent)))
        try harness.listenerB.emit(matrixEnvelope(eventID: "$recipient-mismatch",
                                                  rawContent: json(for: DirectCallMatrixSignalContent(callID: "call-recipient",
                                                                                                      type: DirectCallSignalType.invite.rawValue,
                                                                                                      intent: DirectCallIntent.audio.rawValue,
                                                                                                      recipient: "@other:example.com",
                                                                                                      keyExchange: keyExchange(callID: "call-recipient",
                                                                                                                               senderUserID: userA)))))
        try harness.listenerB.emit(matrixEnvelope(eventID: "$not-direct-room",
                                                  isDirectOneToOneRoom: false,
                                                  rawContent: json(for: validContent)))
        try harness.listenerB.emit(matrixEnvelope(eventID: "$not-encrypted-room",
                                                  isEncryptedRoom: false,
                                                  rawContent: json(for: validContent)))
        harness.listenerB.emit(matrixEnvelope(eventID: "$unknown-type",
                                              rawContent: #"{"version":1,"call_id":"call-unknown","type":"unknown","intent":"audio","recipient":"@b:example.com"}"#))

        await Task.yield()

        #expect(harness.engineB.activeSessionPublisher.value == nil)
        #expect(harness.senderB.sentSignals.isEmpty)
        #expect(harness.mediaEngineB.connectedSessions.isEmpty)
        #expect(harness.mediaFactoryB.makeMediaEngineCount == 1)
    }

    @Test
    func matrixSignalTransportBridgeFailsClosedWhenIncomingInviteHasNoUsableKeyExchange() async throws {
        let harness = await makeMatrixHarness(cleanupDelay: .seconds(1))
        defer { harness.stop() }

        let missingKeyExchange = DirectCallMatrixSignalContent(callID: "call-missing-key",
                                                               type: DirectCallSignalType.invite.rawValue,
                                                               intent: DirectCallIntent.audio.rawValue,
                                                               recipient: userB,
                                                               keyExchange: nil)
        let mismatchedKeyExchange = DirectCallMatrixSignalContent(callID: "call-mismatched-key",
                                                                  type: DirectCallSignalType.invite.rawValue,
                                                                  intent: DirectCallIntent.audio.rawValue,
                                                                  recipient: userB,
                                                                  keyExchange: keyExchange(callID: "other-call", senderUserID: userA))

        try harness.listenerB.emit(matrixEnvelope(eventID: "$missing-key",
                                                  rawContent: json(for: missingKeyExchange)))
        try harness.listenerB.emit(matrixEnvelope(eventID: "$mismatched-key",
                                                  rawContent: json(for: mismatchedKeyExchange)))

        await Task.yield()

        #expect(harness.engineB.activeSessionPublisher.value == nil)
        #expect(harness.mediaEngineB.connectedSessions.isEmpty)
        #expect(harness.senderB.sentSignals.isEmpty)
    }

    @Test
    func matrixSignalTransportBridgeFailsClosedWhenOutgoingMediaConnectionFails() async throws {
        let failingMediaEngine = SignalMediaEngineSpy(connectResult: .failure(.tokenUnavailable))
        let harness = await makeMatrixHarness(cleanupDelay: .seconds(1),
                                              mediaEngineA: failingMediaEngine)
        defer { harness.stop() }

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing Matrix direct call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.senderA.sentSignals.count == 1 })
        try emitMatrixSignal(#require(harness.senderA.sentSignals.last),
                             eventID: "$matrix-invite",
                             senderUserID: userA,
                             ownUserID: userB,
                             to: harness.listenerB)
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })

        _ = await harness.engineB.acceptCall(callID: outgoingSession.callID)
        #expect(await waitUntil { harness.senderB.sentSignals.count == 1 })
        try emitMatrixSignal(#require(harness.senderB.sentSignals.last),
                             eventID: "$matrix-answer",
                             senderUserID: userB,
                             ownUserID: userA,
                             to: harness.listenerA)

        #expect(await waitUntil { harness.engineA.activeSessionPublisher.value?.state == .failed })
        #expect(harness.mediaEngineA.connectedSessions.map(\.callID) == [outgoingSession.callID])
        #expect(harness.mediaEngineA.cleanupCallIDs == [outgoingSession.callID])
        #expect(harness.engineA.activeSessionPublisher.value?.state != .activeAudio)
    }

    @Test
    func matrixSignalTransportBridgeFailsClosedWhenIncomingMediaConnectionFails() async throws {
        let failingMediaEngine = SignalMediaEngineSpy(connectResult: .failure(.mediaSetupUnavailable))
        let harness = await makeMatrixHarness(cleanupDelay: .seconds(1),
                                              mediaEngineB: failingMediaEngine)
        defer { harness.stop() }

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing Matrix direct call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.senderA.sentSignals.count == 1 })
        try emitMatrixSignal(#require(harness.senderA.sentSignals.last),
                             eventID: "$matrix-invite",
                             senderUserID: userA,
                             ownUserID: userB,
                             to: harness.listenerB)
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })

        _ = await harness.engineB.acceptCall(callID: outgoingSession.callID)

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .failed })
        #expect(await waitUntil { harness.senderB.sentSignals.count == 1 })
        #expect(harness.mediaEngineB.connectedSessions.map(\.callID) == [outgoingSession.callID])
        #expect(harness.mediaEngineB.cleanupCallIDs == [outgoingSession.callID])
        #expect(harness.senderB.sentSignals.map(\.eventType) == [DirectCallMatrixSignalCodec.eventType])
    }

    @Test
    func matrixSignalTransportBridgeFailsClosedWhenMediaFactoryIsUnavailable() async throws {
        let unavailableFactory = SignalMediaEngineFactorySpy(result: .failure(.tokenUnavailable))
        let harness = await makeMatrixHarness(cleanupDelay: .seconds(1),
                                              mediaFactoryB: unavailableFactory)
        defer { harness.stop() }

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing Matrix direct call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.senderA.sentSignals.count == 1 })
        try emitMatrixSignal(#require(harness.senderA.sentSignals.last),
                             eventID: "$matrix-invite",
                             senderUserID: userA,
                             ownUserID: userB,
                             to: harness.listenerB)
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })

        _ = await harness.engineB.acceptCall(callID: outgoingSession.callID)

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .failed })
        #expect(unavailableFactory.makeMediaEngineCount == 1)
        #expect(harness.mediaEngineB.connectedSessions.isEmpty)
        #expect(harness.engineB.activeSessionPublisher.value?.state != .activeAudio)
    }

    @Test
    func matrixSignalTransportBridgeFailsClosedWhenE2EEContextFactoryIsUnavailable() async throws {
        let unavailableFactory = SignalMediaEngineFactorySpy(result: .failure(.e2eeContextUnavailable))
        let harness = await makeMatrixHarness(cleanupDelay: .seconds(1),
                                              mediaFactoryB: unavailableFactory)
        defer { harness.stop() }

        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing Matrix direct call start to succeed.")
            return
        }

        #expect(await waitUntil { harness.senderA.sentSignals.count == 1 })
        try emitMatrixSignal(#require(harness.senderA.sentSignals.last),
                             eventID: "$matrix-invite",
                             senderUserID: userA,
                             ownUserID: userB,
                             to: harness.listenerB)
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })

        _ = await harness.engineB.acceptCall(callID: outgoingSession.callID)

        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .failed })
        #expect(unavailableFactory.makeMediaEngineCount == 1)
        #expect(harness.mediaEngineB.connectedSessions.isEmpty)
        #expect(harness.mediaEngineB.connectedKeyHandles.isEmpty)
        #expect(harness.engineB.activeSessionPublisher.value?.state != .activeAudio)
    }

    @Test
    func matrixSignalTransportBridgeCleansMediaIdempotentlyAfterRemoteTerminal() async throws {
        let harness = await makeMatrixHarness(cleanupDelay: .seconds(120))
        defer { harness.stop() }

        let activeSession = try await connectOutgoingCall(harness: harness)
        let terminalSignal = DirectCallOutgoingSignal(roomID: roomID,
                                                      peerUserID: userB,
                                                      callID: activeSession.callID,
                                                      type: .hangup,
                                                      intent: nil)
        let terminalContent = try #require(DirectCallMatrixSignalCodec.encode(terminalSignal))
        let terminalEnvelope = matrixEnvelope(eventID: "$matrix-remote-hangup",
                                              rawContent: terminalContent)

        harness.listenerB.emit(terminalEnvelope)
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .ended })
        harness.listenerB.emit(terminalEnvelope)
        await harness.engineB.cleanupCall(callID: activeSession.callID)
        await harness.engineB.cleanupCall(callID: activeSession.callID)

        #expect(harness.mediaEngineB.disconnectCallIDs == [activeSession.callID])
        #expect(harness.mediaEngineB.cleanupCallIDs == [activeSession.callID])
    }

    @Test
    func matrixSignalTransportBridgeDisconnectsOutgoingCallerAfterRemoteTerminal() async throws {
        let harness = await makeMatrixHarness(cleanupDelay: .seconds(120))
        defer { harness.stop() }

        let activeSession = try await connectOutgoingCall(harness: harness)
        let terminalSignal = DirectCallOutgoingSignal(roomID: roomID,
                                                      peerUserID: userA,
                                                      callID: activeSession.callID,
                                                      type: .hangup,
                                                      intent: nil)
        let terminalContent = try #require(DirectCallMatrixSignalCodec.encode(terminalSignal))
        let terminalEnvelope = matrixEnvelope(eventID: "$matrix-remote-hangup-outgoing",
                                              senderUserID: userB,
                                              ownUserID: userA,
                                              rawContent: terminalContent)

        harness.listenerA.emit(terminalEnvelope)
        #expect(await waitUntil { harness.engineA.activeSessionPublisher.value?.state == .ended })
        harness.listenerA.emit(terminalEnvelope)
        await harness.engineA.cleanupCall(callID: activeSession.callID)
        await harness.engineA.cleanupCall(callID: activeSession.callID)

        #expect(harness.mediaEngineA.disconnectCallIDs == [activeSession.callID])
        #expect(harness.mediaEngineA.cleanupCallIDs == [activeSession.callID])
    }

    private func makeMatrixHarness(cleanupDelay: Duration = .milliseconds(20),
                                   mediaEngineA: SignalMediaEngineSpy? = nil,
                                   mediaEngineB: SignalMediaEngineSpy? = nil,
                                   mediaFactoryA: SignalMediaEngineFactorySpy? = nil,
                                   mediaFactoryB: SignalMediaEngineFactorySpy? = nil) async -> MatrixHarness {
        let senderA = MatrixRawSignalSenderSpy()
        let senderB = MatrixRawSignalSenderSpy()
        let listenerA = MatrixTimelineSignalListenerSpy()
        let listenerB = MatrixTimelineSignalListenerSpy()
        let mediaEngineA = mediaEngineA ?? SignalMediaEngineSpy()
        let mediaEngineB = mediaEngineB ?? SignalMediaEngineSpy()
        let mediaFactoryA = mediaFactoryA ?? SignalMediaEngineFactorySpy(mediaEngine: mediaEngineA)
        let mediaFactoryB = mediaFactoryB ?? SignalMediaEngineFactorySpy(mediaEngine: mediaEngineB)

        let transportA = MatrixDirectCallSignalTransport(ownUserID: userA,
                                                         sender: DirectCallMatrixSignalTransport(rawSender: senderA),
                                                         listener: listenerA)
        let transportB = MatrixDirectCallSignalTransport(ownUserID: userB,
                                                         sender: DirectCallMatrixSignalTransport(rawSender: senderB),
                                                         listener: listenerB)

        let engineA = makeEngine(ownUserID: userA,
                                 peerUserID: userB,
                                 cleanupDelay: cleanupDelay,
                                 mediaEngineFactory: mediaFactoryA)
        let engineB = makeEngine(ownUserID: userB,
                                 peerUserID: userA,
                                 cleanupDelay: cleanupDelay,
                                 mediaEngineFactory: mediaFactoryB)

        let bridgeA = DirectCallEngineSignalBridge(ownUserID: userA,
                                                   engine: engineA,
                                                   signalTransport: transportA)
        let bridgeB = DirectCallEngineSignalBridge(ownUserID: userB,
                                                   engine: engineB,
                                                   signalTransport: transportB)

        await transportA.attach()
        await transportB.attach()

        return MatrixHarness(senderA: senderA,
                             senderB: senderB,
                             listenerA: listenerA,
                             listenerB: listenerB,
                             mediaEngineA: mediaEngineA,
                             mediaEngineB: mediaEngineB,
                             mediaFactoryA: mediaFactoryA,
                             mediaFactoryB: mediaFactoryB,
                             transportA: transportA,
                             transportB: transportB,
                             engineA: engineA,
                             engineB: engineB,
                             bridgeA: bridgeA,
                             bridgeB: bridgeB)
    }

    private func makeEngine(ownUserID: String,
                            peerUserID: String,
                            cleanupDelay: Duration,
                            mediaEngineFactory: DirectCallMediaEngineFactoryProtocol) -> DirectCallEngine {
        DirectCallEngine(ownUserID: ownUserID,
                         configuration: .init(incomingRingingTimeout: .seconds(120),
                                              outgoingRingingTimeout: .seconds(120),
                                              connectingTimeout: .seconds(120),
                                              cleanupDelay: cleanupDelay,
                                              processedTerminalEventLimit: 64),
                         encryptionService: SignalEncryptionServiceSpy(senderUserID: ownUserID),
                         mediaEngineFactory: mediaEngineFactory) { [roomID] resolvedRoomID in
            resolvedRoomID == roomID ? peerUserID : nil
        }
    }

    private func connectOutgoingCall(harness: MatrixHarness) async throws -> DirectCallSession {
        let outgoingResult = await harness.engineA.startOutgoingAudioCall(peer: userB, roomID: roomID)
        guard case .success(let outgoingSession) = outgoingResult else {
            Issue.record("Expected outgoing Matrix direct call start to succeed.")
            throw MatrixIntegrationTestError()
        }

        #expect(await waitUntil { harness.senderA.sentSignals.count == 1 })
        try emitMatrixSignal(#require(harness.senderA.sentSignals.last),
                             eventID: "$matrix-invite",
                             senderUserID: userA,
                             ownUserID: userB,
                             to: harness.listenerB)
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .incomingRinging })

        _ = await harness.engineB.acceptCall(callID: outgoingSession.callID)
        #expect(await waitUntil { harness.senderB.sentSignals.count == 1 })
        try emitMatrixSignal(#require(harness.senderB.sentSignals.last),
                             eventID: "$matrix-answer",
                             senderUserID: userB,
                             ownUserID: userA,
                             to: harness.listenerA)

        #expect(await waitUntil { harness.engineA.activeSessionPublisher.value?.state == .activeAudio })
        #expect(await waitUntil { harness.engineB.activeSessionPublisher.value?.state == .activeAudio })

        guard let activeSession = harness.engineB.activeSessionPublisher.value else {
            throw MatrixIntegrationTestError()
        }
        return activeSession
    }

    private func keyExchange(callID: String,
                             roomID: String? = nil,
                             senderUserID: String,
                             encryptedPayload: String = "encrypted") -> DirectCallEncryptedKeyExchangePayload {
        .init(callID: callID,
              roomID: roomID ?? self.roomID,
              senderUserID: senderUserID,
              keyID: "key-\(callID)",
              encryptedPayload: encryptedPayload)
    }

    private func matrixEnvelope(eventID: String = "$matrix-event",
                                roomID: String? = nil,
                                senderUserID: String? = nil,
                                ownUserID: String? = nil,
                                isDirectOneToOneRoom: Bool? = true,
                                isEncryptedRoom: Bool? = true,
                                rawContent: String) -> DirectCallMatrixSignalEnvelope {
        .init(eventID: eventID,
              roomID: roomID ?? self.roomID,
              senderUserID: senderUserID ?? userA,
              ownUserID: ownUserID ?? userB,
              isDirectOneToOneRoom: isDirectOneToOneRoom,
              isEncryptedRoom: isEncryptedRoom,
              timestamp: .now,
              rawContent: rawContent)
    }

    private func matrixEnvelope(from signal: SentRawSignal,
                                eventID: String,
                                senderUserID: String,
                                ownUserID: String) -> DirectCallMatrixSignalEnvelope {
        matrixEnvelope(eventID: eventID,
                       roomID: signal.roomID,
                       senderUserID: senderUserID,
                       ownUserID: ownUserID,
                       rawContent: signal.content)
    }

    private func emitMatrixSignal(_ signal: SentRawSignal,
                                  eventID: String,
                                  senderUserID: String,
                                  ownUserID: String,
                                  to listener: MatrixTimelineSignalListenerSpy) {
        listener.emit(matrixEnvelope(from: signal,
                                     eventID: eventID,
                                     senderUserID: senderUserID,
                                     ownUserID: ownUserID))
    }

    private func json(for content: DirectCallMatrixSignalContent) throws -> String {
        try String(data: JSONEncoder().encode(content), encoding: .utf8) ?? ""
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           checkInterval: Duration = .milliseconds(20),
                           condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: checkInterval)
        }
        return condition()
    }
}

@MainActor
private final class SignalEncryptionServiceSpy: DirectCallEncryptionServiceProtocol {
    private let senderUserID: String

    init(senderUserID: String) {
        self.senderUserID = senderUserID
    }

    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        let keyID = "key-\(callID)"
        return .success(.init(payload: .init(callID: callID,
                                             roomID: roomID,
                                             senderUserID: senderUserID,
                                             keyID: keyID,
                                             encryptedPayload: "encrypted-\(callID)"),
                              keyHandle: .init(callID: callID, keyID: keyID)))
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload, expectedCallID: String, expectedRoomID: String, expectedSenderUserID: String) -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        guard payload.callID == expectedCallID,
              payload.roomID == expectedRoomID,
              payload.senderUserID == expectedSenderUserID,
              !payload.keyID.isEmpty,
              !payload.encryptedPayload.isEmpty else {
            return .failure(.keyMismatch)
        }

        return .success(.init(callID: payload.callID, keyID: payload.keyID))
    }

    func clearPerCallKey(callID: String) { }
}

@MainActor
private final class SignalMediaEngineSpy: DirectCallMediaEngineProtocol {
    private let mediaStateSubject = CurrentValueSubject<DirectCallMediaState, Never>(.idle)
    private let connectResult: Result<DirectCallMediaState, DirectCallMediaError>

    private(set) var connectedSessions = [DirectCallSession]()
    private(set) var connectedKeyHandles = [DirectCallMediaKeyHandle]()
    private(set) var disconnectCallIDs = [String]()
    private(set) var cleanupCallIDs = [String]()

    var mediaStatePublisher: CurrentValuePublisher<DirectCallMediaState, Never> {
        mediaStateSubject.asCurrentValuePublisher()
    }

    init(connectResult: Result<DirectCallMediaState, DirectCallMediaError> = .success(.init(callID: "call",
                                                                                            phase: .activeAudio,
                                                                                            isMicrophoneEnabled: false,
                                                                                            isSpeakerEnabled: false,
                                                                                            isE2EEReady: true))) {
        self.connectResult = connectResult
    }

    func prepareAudioSession(for session: DirectCallSession) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        .success(.init(callID: session.callID,
                       phase: .preparingAudio,
                       isMicrophoneEnabled: false,
                       isSpeakerEnabled: false,
                       isE2EEReady: session.encryptionState == .ready))
    }

    func connectAudio(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        connectedSessions.append(session)
        connectedKeyHandles.append(keyHandle)
        return connectResult
    }

    func setMicrophoneEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        .success(mediaStateSubject.value)
    }

    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        .success(mediaStateSubject.value)
    }

    func setSpeakerEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        .success(mediaStateSubject.value)
    }

    func disconnect(callID: String) async {
        disconnectCallIDs.append(callID)
    }

    func cleanup(callID: String) async {
        cleanupCallIDs.append(callID)
    }
}

private struct MatrixIntegrationTestError: Error { }

@MainActor
private final class NativeDirectCallListenerControlSpy: NativeDirectCallSignalListenerControlProtocol {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() async {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class SignalMediaEngineFactorySpy: DirectCallMediaEngineFactoryProtocol {
    private let result: Result<any DirectCallMediaEngineProtocol, DirectCallMediaError>
    private(set) var makeMediaEngineCount = 0

    init(mediaEngine: DirectCallMediaEngineProtocol) {
        result = .success(mediaEngine)
    }

    init(result: Result<any DirectCallMediaEngineProtocol, DirectCallMediaError>) {
        self.result = result
    }

    func makeMediaEngine() -> Result<any DirectCallMediaEngineProtocol, DirectCallMediaError> {
        makeMediaEngineCount += 1
        return result
    }
}

@MainActor
private final class MatrixRawSignalSenderSpy: DirectCallMatrixRawSignalSending {
    private(set) var sentSignals = [SentRawSignal]()
    var result: Result<Void, DirectCallMatrixSignalTransportError> = .success(())

    func sendDirectCallSignal(roomID: String, eventType: String, content: String) async -> Result<Void, DirectCallMatrixSignalTransportError> {
        sentSignals.append(.init(roomID: roomID, eventType: eventType, content: content))
        return result
    }
}

@MainActor
private final class MatrixTimelineSignalListenerSpy: DirectCallMatrixTimelineSignalListening {
    private var onEnvelope: (@MainActor (DirectCallMatrixSignalEnvelope) -> Void)?
    private let handle = MatrixSignalListeningHandleSpy()
    private(set) var startCount = 0

    var cancelCount: Int {
        handle.cancelCount
    }

    func start(onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) async -> DirectCallMatrixSignalListeningHandle {
        startCount += 1
        self.onEnvelope = onEnvelope
        return handle
    }

    func emit(_ envelope: DirectCallMatrixSignalEnvelope) {
        onEnvelope?(envelope)
    }
}

@MainActor
private final class MatrixSignalListeningHandleSpy: DirectCallMatrixSignalListeningHandle {
    private(set) var cancelCount = 0

    func cancel() {
        cancelCount += 1
    }
}

private struct SentRawSignal {
    let roomID: String
    let eventType: String
    let content: String
}

@MainActor
private final class JoinedRoomNativeDirectCallCompositionBoundarySpy: JoinedRoomNativeDirectCallCompositionBoundaryProtocol {
    let nativeDirectCallRoomID: String
    let nativeDirectCallOwnUserID: String
    let nativeDirectCallIsDirectOneToOneRoom: Bool?
    let nativeDirectCallIsEncryptedRoom: Bool?
    let nativeDirectCallPeerUserID: String?

    private let rawSender: DirectCallMatrixRawSignalSending?
    private let timelineSignalListener: DirectCallMatrixTimelineSignalListening?

    private(set) var makeRawSignalSenderCount = 0
    private(set) var makeTimelineSignalListenerCount = 0

    init(roomID: String,
         ownUserID: String,
         isDirectOneToOneRoom: Bool?,
         isEncryptedRoom: Bool?,
         peerUserID: String?,
         rawSender: DirectCallMatrixRawSignalSending?,
         timelineSignalListener: DirectCallMatrixTimelineSignalListening?) {
        nativeDirectCallRoomID = roomID
        nativeDirectCallOwnUserID = ownUserID
        nativeDirectCallIsDirectOneToOneRoom = isDirectOneToOneRoom
        nativeDirectCallIsEncryptedRoom = isEncryptedRoom
        nativeDirectCallPeerUserID = peerUserID
        self.rawSender = rawSender
        self.timelineSignalListener = timelineSignalListener
    }

    func makeNativeDirectCallRawSignalSender() -> DirectCallMatrixRawSignalSending? {
        makeRawSignalSenderCount += 1
        return rawSender
    }

    func makeNativeDirectCallTimelineSignalListener() -> DirectCallMatrixTimelineSignalListening? {
        makeTimelineSignalListenerCount += 1
        return timelineSignalListener
    }
}

@MainActor
private final class MatrixRawRoomSenderSpy: DirectCallMatrixRawRoomSending {
    private(set) var sentRawEvents = [SentRawRoomEvent]()
    var error: Error?

    func sendRaw(eventType: String, content: String) async throws {
        if let error {
            throw error
        }

        sentRawEvents.append(.init(eventType: eventType, content: content))
    }
}

private struct SentRawRoomEvent: Equatable {
    let eventType: String
    let content: String
}

private struct MatrixRawRoomSenderError: Error { }

@MainActor
final class DirectCallMatrixSDKSignalAdapterTests {
    private let userA = "@a:example.com"
    private let userB = "@b:example.com"
    private let roomID = "!dm:example.com"

    @Test
    func matrixSDKTimelineSignalListenerStartsAndCancelsSDKListener() async {
        let timeline = TimelineSDKMock()
        let sdkHandle = TaskHandleSDKMock()
        timeline.addListenerListenerReturnValue = sdkHandle
        let listener = makeListener(timeline: timeline)

        let handle = await listener.start { _ in }
        handle.cancel()

        #expect(timeline.addListenerListenerCallsCount == 1)
        #expect(sdkHandle.cancelCallsCount == 1)
    }

    @Test
    func matrixSDKTimelineSignalListenerFailsClosedWhenSafeRawContentIsUnavailable() async throws {
        let timeline = TimelineSDKMock()
        timeline.addListenerListenerReturnValue = TaskHandleSDKMock()
        let listener = makeListener(timeline: timeline)
        var envelopes = [DirectCallMatrixSignalEnvelope]()
        let handle = await listener.start { envelope in
            envelopes.append(envelope)
        }
        handle.cancel()

        let sdkListener = try #require(timeline.addListenerListenerReceivedListener)
        sdkListener.onUpdate(diff: [.append(values: [timelineItem(eventID: "$event-1",
                                                                  content: directCallTimelineContent())])])

        await Task.yield()
        #expect(envelopes.isEmpty)
        #expect(listener.diagnosticSnapshot.timelineUpdateCount == 1)
        #expect(listener.diagnosticSnapshot.timelineDiffReceivedCount == 1)
        #expect(listener.diagnosticSnapshot.lastTimelineDiffKind == .append)
        #expect(listener.diagnosticSnapshot.lastTimelineDiffItemCount == 1)
        #expect(listener.diagnosticSnapshot.timelineEventReceivedCount == 1)
        #expect(listener.diagnosticSnapshot.directCallEventTypeSeenCount == 1)
        #expect(listener.diagnosticSnapshot.envelopeExtractedCount == 0)
        #expect(listener.diagnosticSnapshot.lastEnvelopeRejectedReason == .contentUnavailable)
        #expect(listener.diagnosticSnapshot.receiveRoomFingerprint == DirectCallDiagnosticRedactor.roomFingerprint(roomID))
    }

    @Test
    func matrixSDKTimelineItemEnvelopeExtractorUsesContentOnlyCustomEventAccessor() throws {
        let content = try #require(DirectCallMatrixSignalCodec.encode(.init(roomID: roomID,
                                                                            peerUserID: userB,
                                                                            callID: "call-1",
                                                                            type: .answer,
                                                                            intent: nil)))
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        lazyProvider.messageLikeCustomContentReturnValue = .init(eventType: DirectCallMatrixSignalCodec.eventType,
                                                                 contentJson: content)
        let eventItem = eventTimelineItem(eventID: "$event-1",
                                          content: directCallTimelineContent(),
                                          lazyProvider: lazyProvider)
        let metadata = try #require(DirectCallMatrixSDKTimelineSignalListener.metadata(from: eventItem,
                                                                                       roomID: roomID,
                                                                                       ownUserID: userB,
                                                                                       isDirectOneToOneRoom: true,
                                                                                       isEncryptedRoom: true))
        let envelope = DirectCallMatrixSDKTimelineItemEnvelopeExtractor().envelope(from: metadata, eventItem: eventItem)

        #expect(envelope?.rawContent == content)
        #expect(lazyProvider.messageLikeCustomContentCalled)
        #expect(envelope?.rawContent.contains("event_id") == false)
        #expect(envelope?.rawContent.contains("sender") == false)
    }

    @Test
    func matrixSDKTimelineItemEnvelopeExtractorFailsClosedForOtherCustomEventType() throws {
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        lazyProvider.messageLikeCustomContentReturnValue = .init(eventType: "kz.salemx.other",
                                                                 contentJson: #"{"version":1}"#)
        let eventItem = eventTimelineItem(eventID: "$event-1",
                                          content: directCallTimelineContent(),
                                          lazyProvider: lazyProvider)
        let metadata = try #require(DirectCallMatrixSDKTimelineSignalListener.metadata(from: eventItem,
                                                                                       roomID: roomID,
                                                                                       ownUserID: userB,
                                                                                       isDirectOneToOneRoom: true,
                                                                                       isEncryptedRoom: true))

        #expect(DirectCallMatrixSDKTimelineItemEnvelopeExtractor().envelope(from: metadata, eventItem: eventItem) == nil)
        #expect(lazyProvider.messageLikeCustomContentCalled)
    }

    @Test
    func matrixSDKTimelineSignalListenerRecordsRedactedReceiveBreadcrumbsForValidInvite() async throws {
        let timeline = TimelineSDKMock()
        timeline.addListenerListenerReturnValue = TaskHandleSDKMock()
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let content = try #require(DirectCallMatrixSignalCodec.encode(signal))
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        lazyProvider.messageLikeCustomContentReturnValue = .init(eventType: DirectCallMatrixSignalCodec.eventType,
                                                                 contentJson: content)
        let listener = makeListener(timeline: timeline)
        var envelopes = [DirectCallMatrixSignalEnvelope]()
        let handle = await listener.start { envelope in
            envelopes.append(envelope)
        }
        handle.cancel()

        timeline.addListenerListenerReceivedListener?.onUpdate(diff: [
            .append(values: [
                timelineItem(eventID: "$event-1",
                             content: directCallTimelineContent(),
                             lazyProvider: lazyProvider)
            ])
        ])

        #expect(await waitUntil { envelopes.count == 1 })
        #expect(listener.diagnosticSnapshot.timelineUpdateCount == 1)
        #expect(listener.diagnosticSnapshot.timelineDiffReceivedCount == 1)
        #expect(listener.diagnosticSnapshot.lastTimelineDiffKind == .append)
        #expect(listener.diagnosticSnapshot.lastTimelineDiffItemCount == 1)
        #expect(listener.diagnosticSnapshot.timelineEventReceivedCount == 1)
        #expect(listener.diagnosticSnapshot.directCallEventTypeSeenCount == 1)
        #expect(listener.diagnosticSnapshot.envelopeExtractedCount == 1)
        #expect(listener.diagnosticSnapshot.lastReceiveEventKind == .directCallInvite)
        #expect(listener.diagnosticSnapshot.lastEnvelopeRejectedReason == .none)
        #expect(listener.diagnosticSnapshot.receiveRoomFingerprint == DirectCallDiagnosticRedactor.roomFingerprint(roomID))
        #expect(listener.diagnosticSnapshot.receiveRoomFingerprint != roomID)
    }

    @Test
    func matrixTimelineItemProviderSignalListenerReceivesLiveProviderUpdates() async throws {
        let updates = PassthroughSubject<([TimelineItemProxy], TimelinePaginationState), Never>()
        let timelineItemProvider = TimelineItemProviderMock()
        timelineItemProvider.underlyingUpdatePublisher = updates.eraseToAnyPublisher()
        timelineItemProvider.itemProxies = []
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live
        timelineItemProvider.underlyingMembershipChangePublisher = Empty<Void, Never>().eraseToAnyPublisher()
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let content = try #require(DirectCallMatrixSignalCodec.encode(signal))
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        lazyProvider.messageLikeCustomContentReturnValue = .init(eventType: DirectCallMatrixSignalCodec.eventType,
                                                                 contentJson: content)
        let listener = DirectCallMatrixTimelineItemProviderSignalListener(timelineItemProvider: timelineItemProvider,
                                                                          roomID: roomID,
                                                                          ownUserID: userB,
                                                                          isDirectOneToOneRoom: { true },
                                                                          isEncryptedRoom: { true })
        var envelopes = [DirectCallMatrixSignalEnvelope]()
        let handle = await listener.start { envelope in
            envelopes.append(envelope)
        }
        defer { handle.cancel() }

        let existingMessage = timelineItemProxy(eventID: "$message", content: nonDirectCallTimelineContent())
        updates.send(([existingMessage], .initial))
        await Task.yield()
        #expect(envelopes.isEmpty)

        let directCallInvite = timelineItemProxy(eventID: "$event-1",
                                                 content: directCallTimelineContent(),
                                                 lazyProvider: lazyProvider)
        updates.send(([existingMessage, directCallInvite], .initial))

        #expect(await waitUntil { envelopes.count == 1 })
        #expect(listener.diagnosticSnapshot.timelineUpdateCount == 2)
        #expect(listener.diagnosticSnapshot.timelineDiffReceivedCount == 2)
        #expect(listener.diagnosticSnapshot.lastTimelineDiffKind == .providerUpdate)
        #expect(listener.diagnosticSnapshot.lastTimelineDiffItemCount == 2)
        #expect(listener.diagnosticSnapshot.timelineEventReceivedCount == 2)
        #expect(listener.diagnosticSnapshot.directCallEventTypeSeenCount == 1)
        #expect(listener.diagnosticSnapshot.envelopeExtractedCount == 1)
        #expect(listener.diagnosticSnapshot.lastReceiveEventKind == .directCallInvite)
        #expect(listener.diagnosticSnapshot.lastEnvelopeRejectedReason == .none)
        #expect(listener.diagnosticSnapshot.receiveRoomFingerprint == DirectCallDiagnosticRedactor.roomFingerprint(roomID))
        #expect(listener.diagnosticSnapshot.receiveRoomFingerprint != roomID)
    }

    @Test
    func matrixTimelineItemProviderSignalListenerDeduplicatesProviderSnapshots() async throws {
        let updates = PassthroughSubject<([TimelineItemProxy], TimelinePaginationState), Never>()
        let timelineItemProvider = TimelineItemProviderMock()
        timelineItemProvider.underlyingUpdatePublisher = updates.eraseToAnyPublisher()
        timelineItemProvider.itemProxies = []
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live
        timelineItemProvider.underlyingMembershipChangePublisher = Empty<Void, Never>().eraseToAnyPublisher()
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .invite,
                                              intent: .audio,
                                              keyExchange: keyExchange(callID: "call-1", senderUserID: userA))
        let content = try #require(DirectCallMatrixSignalCodec.encode(signal))
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        lazyProvider.messageLikeCustomContentReturnValue = .init(eventType: DirectCallMatrixSignalCodec.eventType,
                                                                 contentJson: content)
        let listener = DirectCallMatrixTimelineItemProviderSignalListener(timelineItemProvider: timelineItemProvider,
                                                                          roomID: roomID,
                                                                          ownUserID: userB,
                                                                          isDirectOneToOneRoom: { true },
                                                                          isEncryptedRoom: { true })
        var envelopes = [DirectCallMatrixSignalEnvelope]()
        let handle = await listener.start { envelope in
            envelopes.append(envelope)
        }
        defer { handle.cancel() }

        let directCallInvite = timelineItemProxy(eventID: "$event-1",
                                                 content: directCallTimelineContent(),
                                                 lazyProvider: lazyProvider)
        updates.send(([directCallInvite], .initial))
        #expect(await waitUntil { envelopes.count == 1 })

        updates.send(([directCallInvite], .initial))
        await Task.yield()

        #expect(envelopes.count == 1)
        #expect(listener.diagnosticSnapshot.timelineUpdateCount == 2)
        #expect(listener.diagnosticSnapshot.directCallEventTypeSeenCount == 1)
        #expect(listener.diagnosticSnapshot.envelopeExtractedCount == 1)
    }

    @Test
    func matrixSDKTimelineSignalListenerRecordsWrongEventTypeAndOwnEventReasons() async {
        let timeline = TimelineSDKMock()
        timeline.addListenerListenerReturnValue = TaskHandleSDKMock()
        let listener = makeListener(timeline: timeline)
        var envelopes = [DirectCallMatrixSignalEnvelope]()
        let handle = await listener.start { envelope in
            envelopes.append(envelope)
        }
        handle.cancel()

        timeline.addListenerListenerReceivedListener?.onUpdate(diff: [
            .append(values: [
                timelineItem(eventID: "$message", content: nonDirectCallTimelineContent())
            ])
        ])
        await Task.yield()

        #expect(envelopes.isEmpty)
        #expect(listener.diagnosticSnapshot.timelineUpdateCount == 1)
        #expect(listener.diagnosticSnapshot.timelineEventReceivedCount == 1)
        #expect(listener.diagnosticSnapshot.directCallEventTypeSeenCount == 0)
        #expect(listener.diagnosticSnapshot.lastReceiveEventKind == .nonDirectCallEvent)
        #expect(listener.diagnosticSnapshot.lastEnvelopeRejectedReason == .wrongEventType)

        timeline.addListenerListenerReceivedListener?.onUpdate(diff: [
            .append(values: [
                timelineItem(eventID: "$own",
                             senderUserID: userB,
                             isOwn: true,
                             content: directCallTimelineContent())
            ])
        ])
        await Task.yield()

        #expect(envelopes.isEmpty)
        #expect(listener.diagnosticSnapshot.timelineUpdateCount == 2)
        #expect(listener.diagnosticSnapshot.directCallEventTypeSeenCount == 1)
        #expect(listener.diagnosticSnapshot.lastEnvelopeRejectedReason == .ownEvent)
    }

    @Test
    func matrixSDKTimelineSignalListenerEmitsOnlySanitizedEnvelopeFromInjectedExtractor() async throws {
        let timeline = TimelineSDKMock()
        timeline.addListenerListenerReturnValue = TaskHandleSDKMock()
        let signal = DirectCallOutgoingSignal(roomID: roomID,
                                              peerUserID: userB,
                                              callID: "call-1",
                                              type: .answer,
                                              intent: nil)
        let extractor = try MatrixTimelineEnvelopeExtractorSpy(rawContent: #require(DirectCallMatrixSignalCodec.encode(signal)))
        let listener = makeListener(timeline: timeline, envelopeExtractor: extractor)
        var envelopes = [DirectCallMatrixSignalEnvelope]()
        let handle = await listener.start { envelope in
            envelopes.append(envelope)
        }
        handle.cancel()

        let sdkListener = try #require(timeline.addListenerListenerReceivedListener)
        sdkListener.onUpdate(diff: [.append(values: [timelineItem(eventID: "$stable-direct-call-event",
                                                                  senderUserID: userA,
                                                                  content: directCallTimelineContent())])])

        #expect(await waitUntil { envelopes.count == 1 })
        #expect(envelopes.first?.eventID == "$stable-direct-call-event")
        #expect(envelopes.first?.rawContent.contains("encrypted_payload") == false)
        #expect(extractor.metadata.first?.eventID == "$stable-direct-call-event")
    }

    @Test
    func matrixSDKTimelineSignalListenerIgnoresNonDirectCallAndOwnEventsBeforeExtraction() async {
        let timeline = TimelineSDKMock()
        timeline.addListenerListenerReturnValue = TaskHandleSDKMock()
        let extractor = MatrixTimelineEnvelopeExtractorSpy(rawContent: #"{"version":1}"#)
        let listener = makeListener(timeline: timeline, envelopeExtractor: extractor)
        var envelopes = [DirectCallMatrixSignalEnvelope]()
        let handle = await listener.start { envelope in
            envelopes.append(envelope)
        }
        handle.cancel()

        timeline.addListenerListenerReceivedListener?.onUpdate(diff: [
            .append(values: [
                timelineItem(eventID: "$message", content: nonDirectCallTimelineContent()),
                timelineItem(eventID: "$own", senderUserID: userB, isOwn: true, content: directCallTimelineContent())
            ])
        ])

        await Task.yield()
        #expect(envelopes.isEmpty)
        #expect(extractor.metadata.isEmpty)
    }

    @Test
    func matrixSDKTimelineSignalMetadataPreservesStableEventIDAndRejectsTransactionID() {
        let remoteEvent = eventTimelineItem(eventID: "$stable-direct-call-event",
                                            content: directCallTimelineContent())
        let transactionEvent = EventTimelineItem(isRemote: false,
                                                 eventOrTransactionId: .transactionId(transactionId: "txn-1"),
                                                 sender: userA,
                                                 senderProfile: .pending,
                                                 forwarder: nil,
                                                 forwarderProfile: nil,
                                                 isOwn: false,
                                                 isEditable: false,
                                                 content: directCallTimelineContent(),
                                                 timestamp: 1_700_000_000_000,
                                                 localSendState: nil,
                                                 localCreatedAt: nil,
                                                 readReceipts: [:],
                                                 origin: nil,
                                                 canBeRepliedTo: false,
                                                 lazyProvider: LazyTimelineItemProviderSDKMock())

        let metadata = DirectCallMatrixSDKTimelineSignalListener.metadata(from: remoteEvent,
                                                                          roomID: roomID,
                                                                          ownUserID: userB,
                                                                          isDirectOneToOneRoom: true,
                                                                          isEncryptedRoom: true)
        let transactionMetadata = DirectCallMatrixSDKTimelineSignalListener.metadata(from: transactionEvent,
                                                                                     roomID: roomID,
                                                                                     ownUserID: userB,
                                                                                     isDirectOneToOneRoom: true,
                                                                                     isEncryptedRoom: true)

        #expect(metadata?.eventID == "$stable-direct-call-event")
        #expect(transactionMetadata == nil)
    }

    @Test
    func matrixSDKTimelineSignalMetadataDescriptionsDoNotExposeRawContentOrEncryptedPayload() {
        let metadata = DirectCallMatrixTimelineSignalMetadata(eventID: "$event",
                                                              roomID: roomID,
                                                              senderUserID: userA,
                                                              ownUserID: userB,
                                                              isDirectOneToOneRoom: true,
                                                              isEncryptedRoom: true,
                                                              timestamp: .now)

        #expect(String(describing: metadata).contains("rawContent") == false)
        #expect(String(reflecting: metadata).contains("rawContent") == false)
        #expect(String(describing: metadata).contains("encrypted_payload") == false)
        #expect(String(reflecting: metadata).contains("encrypted_payload") == false)
    }

    private func makeListener(timeline: TimelineProtocol,
                              envelopeExtractor: DirectCallMatrixTimelineItemEnvelopeExtracting? = nil) -> DirectCallMatrixSDKTimelineSignalListener {
        .init(timeline: timeline,
              roomID: roomID,
              ownUserID: userB,
              isDirectOneToOneRoom: { true },
              isEncryptedRoom: { true },
              envelopeExtractor: envelopeExtractor)
    }

    private func timelineItem(eventID: String,
                              senderUserID: String? = nil,
                              isOwn: Bool = false,
                              content: TimelineItemContent,
                              lazyProvider: LazyTimelineItemProviderSDKMock? = nil) -> TimelineItem {
        let item = TimelineItemSDKMock()
        item.asEventReturnValue = eventTimelineItem(eventID: eventID,
                                                    senderUserID: senderUserID,
                                                    isOwn: isOwn,
                                                    content: content,
                                                    lazyProvider: lazyProvider)
        return item
    }

    private func timelineItemProxy(eventID: String,
                                   senderUserID: String? = nil,
                                   isOwn: Bool = false,
                                   content: TimelineItemContent,
                                   lazyProvider: LazyTimelineItemProviderSDKMock? = nil) -> TimelineItemProxy {
        .event(.init(item: eventTimelineItem(eventID: eventID,
                                             senderUserID: senderUserID,
                                             isOwn: isOwn,
                                             content: content,
                                             lazyProvider: lazyProvider),
                     uniqueID: .init(eventID)))
    }

    private func eventTimelineItem(eventID: String,
                                   senderUserID: String? = nil,
                                   isOwn: Bool = false,
                                   content: TimelineItemContent,
                                   lazyProvider: LazyTimelineItemProviderSDKMock? = nil) -> EventTimelineItem {
        .init(configuration: .init(eventID: eventID,
                                   sender: senderUserID ?? userA,
                                   isOwn: isOwn,
                                   content: content,
                                   lazyProvider: lazyProvider))
    }

    private func directCallTimelineContent() -> TimelineItemContent {
        .msgLike(content: .init(kind: .other(eventType: .other(DirectCallMatrixSignalCodec.eventType)),
                                reactions: [],
                                inReplyTo: nil,
                                threadRoot: nil,
                                threadSummary: nil))
    }

    private func nonDirectCallTimelineContent() -> TimelineItemContent {
        .msgLike(content: .init(kind: .redacted,
                                reactions: [],
                                inReplyTo: nil,
                                threadRoot: nil,
                                threadSummary: nil))
    }

    private func keyExchange(callID: String,
                             roomID: String? = nil,
                             senderUserID: String,
                             encryptedPayload: String = "encrypted") -> DirectCallEncryptedKeyExchangePayload {
        .init(callID: callID,
              roomID: roomID ?? self.roomID,
              senderUserID: senderUserID,
              keyID: "key-\(callID)",
              encryptedPayload: encryptedPayload)
    }

    private func waitUntil(timeout: Duration = .seconds(2),
                           checkInterval: Duration = .milliseconds(20),
                           condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: checkInterval)
        }
        return condition()
    }
}

@MainActor
private final class MatrixTimelineEnvelopeExtractorSpy: DirectCallMatrixTimelineItemEnvelopeExtracting {
    private let rawContent: String
    private(set) var metadata = [DirectCallMatrixTimelineSignalMetadata]()

    init(rawContent: String) {
        self.rawContent = rawContent
    }

    func envelope(from metadata: DirectCallMatrixTimelineSignalMetadata, eventItem: EventTimelineItem) -> DirectCallMatrixSignalEnvelope? {
        self.metadata.append(metadata)
        return .init(eventID: metadata.eventID,
                     roomID: metadata.roomID,
                     senderUserID: metadata.senderUserID,
                     ownUserID: metadata.ownUserID,
                     isDirectOneToOneRoom: metadata.isDirectOneToOneRoom,
                     isEncryptedRoom: metadata.isEncryptedRoom,
                     timestamp: metadata.timestamp,
                     rawContent: rawContent)
    }
}
