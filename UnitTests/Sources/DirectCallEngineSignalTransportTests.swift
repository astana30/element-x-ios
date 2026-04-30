//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
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
                             senderUserID: String,
                             encryptedPayload: String = "encrypted") -> DirectCallEncryptedKeyExchangePayload {
        .init(callID: callID,
              roomID: roomID,
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
