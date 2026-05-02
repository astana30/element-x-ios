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
        let harness = makeHarness()

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

        try listener.emit(matrixEnvelope(rawContent: #require(DirectCallMatrixSignalCodec.encode(signal))))

        #expect(await waitUntil { events.count == 1 })
        #expect(events.first?.type == .invite)
        #expect(events.first?.keyExchange == payload)
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

        envelopes.forEach(receiver.receive)
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

private struct Harness {
    let transport: InMemoryDirectCallSignalTransport
    let engineA: DirectCallEngine
    let engineB: DirectCallEngine
    let bridgeA: DirectCallEngineSignalBridge
    let bridgeB: DirectCallEngineSignalBridge
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

    var mediaStatePublisher: CurrentValuePublisher<DirectCallMediaState, Never> {
        mediaStateSubject.asCurrentValuePublisher()
    }

    func prepareAudioSession(for session: DirectCallSession) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        .success(.init(callID: session.callID,
                       phase: .preparingAudio,
                       isMicrophoneEnabled: false,
                       isSpeakerEnabled: false,
                       isE2EEReady: session.encryptionState == .ready))
    }

    func connectAudio(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        .success(.init(callID: session.callID,
                       phase: .activeAudio,
                       isMicrophoneEnabled: false,
                       isSpeakerEnabled: false,
                       isE2EEReady: session.encryptionState == .ready))
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

    func disconnect(callID: String) async { }

    func cleanup(callID: String) async { }
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

    var cancelCount: Int {
        handle.cancelCount
    }

    func start(onEnvelope: @escaping @MainActor (DirectCallMatrixSignalEnvelope) -> Void) async -> DirectCallMatrixSignalListeningHandle {
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
              envelopeExtractor: envelopeExtractor ?? DirectCallMatrixFailClosedTimelineItemEnvelopeExtractor())
    }

    private func timelineItem(eventID: String,
                              senderUserID: String? = nil,
                              isOwn: Bool = false,
                              content: TimelineItemContent) -> TimelineItem {
        let item = TimelineItemSDKMock()
        item.asEventReturnValue = eventTimelineItem(eventID: eventID,
                                                    senderUserID: senderUserID,
                                                    isOwn: isOwn,
                                                    content: content)
        return item
    }

    private func eventTimelineItem(eventID: String,
                                   senderUserID: String? = nil,
                                   isOwn: Bool = false,
                                   content: TimelineItemContent) -> EventTimelineItem {
        .init(configuration: .init(eventID: eventID,
                                   sender: senderUserID ?? userA,
                                   isOwn: isOwn,
                                   content: content))
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

    func envelope(from metadata: DirectCallMatrixTimelineSignalMetadata) -> DirectCallMatrixSignalEnvelope? {
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
