//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Testing

@MainActor
final class DirectCallEngineTests {
    private let ownUserID = "@me:example.com"
    private let peerUserID = "@alice:example.com"
    private let roomID = "!room:example.com"

    @Test
    func incomingCancelClearsSessionAndStaleAnswerCannotStartCall() async throws {
        let engine = makeEngine()
        var actions = [DirectCallEngineAction]()
        let cancellable = engine.actionsPublisher.sink { actions.append($0) }
        defer { cancellable.cancel() }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$invite",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: "call-a",
                                                          type: .invite,
                                                          intent: .audio,
                                                          timestamp: .now))

        #expect(engine.activeSessionPublisher.value?.state == .incomingRinging)

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$cancel",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: "call-a",
                                                          type: .cancel,
                                                          intent: nil,
                                                          timestamp: .now))

        try await Task.sleep(for: .milliseconds(40))
        #expect(engine.activeSessionPublisher.value == nil)

        let staleAnswer = await engine.acceptCall(callID: "call-a")
        #expect(staleAnswer == .failure(.invalidTransition))
        #expect(!actions.contains { action in
            guard case .emitSignal(let signal) = action else {
                return false
            }
            return signal.type == .answer
        })
    }

    @Test
    func outgoingRejectedByPeerEndsImmediately() async {
        let engine = makeEngine()
        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$reject",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: session.callID,
                                                          type: .reject,
                                                          intent: nil,
                                                          timestamp: .now))

        #expect(engine.activeSessionPublisher.value?.state == .cancelled)
    }

    @Test
    func remoteHangupEndsAcceptedCallImmediately() async {
        let engine = makeEngine()
        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$answer",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: session.callID,
                                                          type: .answer,
                                                          intent: nil,
                                                          timestamp: .now))
        #expect(engine.activeSessionPublisher.value?.state == .activeAudio)

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$hangup",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: session.callID,
                                                          type: .hangup,
                                                          intent: nil,
                                                          timestamp: .now))
        #expect(engine.activeSessionPublisher.value?.state == .ended)
    }

    @Test
    func duplicateTerminalEventsAreIgnoredSafely() async {
        let engine = makeEngine()
        var stateChangeCount = 0
        let cancellable = engine.actionsPublisher.sink { action in
            if case .stateChanged = action {
                stateChangeCount += 1
            }
        }
        defer { cancellable.cancel() }

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$dup",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: session.callID,
                                                          type: .hangup,
                                                          intent: nil,
                                                          timestamp: .now))
        let transitionsAfterFirstTerminal = stateChangeCount

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$dup",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: session.callID,
                                                          type: .hangup,
                                                          intent: nil,
                                                          timestamp: .now))

        #expect(stateChangeCount == transitionsAfterFirstTerminal)
    }

    @Test
    func differentTerminalEventIDsForSameCallIDAreIgnoredAfterTerminal() async {
        let engine = makeEngine()
        var stateChangeCount = 0
        let cancellable = engine.actionsPublisher.sink { action in
            if case .stateChanged = action {
                stateChangeCount += 1
            }
        }
        defer { cancellable.cancel() }

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$terminal-a",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: session.callID,
                                                          type: .hangup,
                                                          intent: nil,
                                                          timestamp: .now))
        #expect(engine.activeSessionPublisher.value?.state == .ended)
        let transitionsAfterFirstTerminal = stateChangeCount

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$terminal-b",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: session.callID,
                                                          type: .cancel,
                                                          intent: nil,
                                                          timestamp: .now))

        #expect(engine.activeSessionPublisher.value?.state == .ended)
        #expect(stateChangeCount == transitionsAfterFirstTerminal)
    }

    @Test
    func invalidSenderAndCallIDDoNotMutateCurrentState() async {
        let engine = makeEngine()
        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        let invalidSender = await engine.receiveIncomingCall(event: .init(eventID: "$invalid-sender",
                                                                          roomID: roomID,
                                                                          senderID: "@mallory:example.com",
                                                                          callID: session.callID,
                                                                          type: .hangup,
                                                                          intent: nil,
                                                                          timestamp: .now))
        #expect(invalidSender == .failure(.invalidSender))
        #expect(engine.activeSessionPublisher.value?.state == .outgoingRinging)

        let invalidCallID = await engine.receiveIncomingCall(event: .init(eventID: "$invalid-call-id",
                                                                          roomID: roomID,
                                                                          senderID: peerUserID,
                                                                          callID: "another-call-id",
                                                                          type: .hangup,
                                                                          intent: nil,
                                                                          timestamp: .now))
        #expect(invalidCallID == .failure(.callIDMismatch))
        #expect(engine.activeSessionPublisher.value?.state == .outgoingRinging)
    }

    @Test
    func outgoingSessionIsE2EERequiredByDefault() async {
        let engine = makeEngine()

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        #expect(session.encryptionMode == .e2eeRequired)
        #expect(session.encryptionState == .pending)
        #expect(session.isMediaPublishingAllowed == false)
    }

    @Test
    func encryptionFailureFailsClosed() async {
        let engine = makeEngine()

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$answer",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: session.callID,
                                                          type: .answer,
                                                          intent: nil,
                                                          timestamp: .now))

        let failureResult = await engine.markEncryptionFailed(callID: session.callID, reason: .e2eeNotProven)
        guard case .success(let failedSession) = failureResult else {
            Issue.record("Expected encryption failure handling to succeed.")
            return
        }

        #expect(failedSession.state == .failed)
        #expect(failedSession.encryptionState == .failed(.e2eeNotProven))
        #expect(failedSession.isMediaPublishingAllowed == false)
    }

    @Test
    func cleanupClearsPerCallKeyMaterial() async {
        let encryptionService = EncryptionServiceSpy()
        let engine = makeEngine(encryptionService: encryptionService)

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$hangup",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: session.callID,
                                                          type: .hangup,
                                                          intent: nil,
                                                          timestamp: .now))

        try? await Task.sleep(for: .milliseconds(40))
        #expect(encryptionService.clearedCallIDs.contains(session.callID))
    }

    private func makeEngine(encryptionService: DirectCallEncryptionServiceProtocol? = nil) -> DirectCallEngine {
        DirectCallEngine(ownUserID: ownUserID,
                         configuration: .init(incomingRingingTimeout: .seconds(120),
                                              outgoingRingingTimeout: .seconds(120),
                                              connectingTimeout: .seconds(120),
                                              cleanupDelay: .milliseconds(20),
                                              processedTerminalEventLimit: 64),
                         encryptionService: encryptionService ?? NoOpDirectCallEncryptionService()) { [roomID, peerUserID] id in
            id == roomID ? peerUserID : nil
        }
    }
}

@MainActor
private final class EncryptionServiceSpy: DirectCallEncryptionServiceProtocol {
    private(set) var clearedCallIDs = Set<String>()

    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) -> Result<DirectCallEncryptedKeyExchangePayload, DirectCallEncryptionFailureReason> {
        .failure(.keyExchangeFailed)
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload, expectedCallID: String, expectedRoomID: String, expectedSenderUserID: String) -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        .failure(.keyExchangeFailed)
    }

    func clearPerCallKey(callID: String) {
        clearedCallIDs.insert(callID)
    }
}
