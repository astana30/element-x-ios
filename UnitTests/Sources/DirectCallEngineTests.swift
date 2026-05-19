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
                                                          timestamp: .now,
                                                          keyExchange: keyExchange(callID: "call-a")))

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
        let engine = makeEngine(mediaEngine: MediaEngineSpy())
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
        #expect(session.encryptionState == .ready)
        #expect(session.isMediaPublishingAllowed)
    }

    @Test
    func outgoingStartGeneratesKeyBeforeInviteEmission() async {
        let encryptionService = EncryptionServiceSpy(senderUserID: ownUserID)
        let engine = makeEngine(encryptionService: encryptionService)
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        let result = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)

        guard case .success(let session) = result else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        #expect(encryptionService.generatedRequests == [.init(callID: session.callID, roomID: roomID, peerUserID: peerUserID)])
        #expect(emittedSignals.count == 1)
        #expect(emittedSignals.first?.type == .invite)
        #expect(emittedSignals.first?.keyExchange?.callID == session.callID)
        #expect(emittedSignals.first?.keyExchange?.encryptedPayload == "encrypted-\(session.callID)")
    }

    @Test
    func diagnosticEncryptionServiceAllowsOutgoingInviteWithoutE2EEFailure() async throws {
        let encryptionService = try #require(NativeDirectCallDiagnosticEncryptionService(ownUserID: ownUserID,
                                                                                         secret: "diagnostic-shared-secret"))
        let engine = makeEngine(encryptionService: encryptionService)
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        let result = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)

        guard case .success(let session) = result else {
            Issue.record("Expected diagnostic encryption to allow outgoing invite emission.")
            return
        }

        let emittedSignal = try #require(emittedSignals.first)
        let keyExchange = try #require(emittedSignal.keyExchange)
        #expect(session.state == .outgoingRinging)
        #expect(emittedSignal.type == .invite)
        #expect(keyExchange.callID == session.callID)
        #expect(keyExchange.roomID == roomID)
        #expect(keyExchange.senderUserID == ownUserID)
        #expect(keyExchange.encryptedPayload.contains("diagnostic-shared-secret") == false)
        #expect(keyExchange.keyID.contains("diagnostic-shared-secret") == false)
    }

    @Test
    func diagnosticEncryptionServiceConsumesOnlyMatchingSecretAndMetadata() async throws {
        let sender = try #require(NativeDirectCallDiagnosticEncryptionService(ownUserID: ownUserID,
                                                                              secret: "diagnostic-shared-secret"))
        let receiver = try #require(NativeDirectCallDiagnosticEncryptionService(ownUserID: peerUserID,
                                                                                secret: "diagnostic-shared-secret"))
        let mismatchedReceiver = try #require(NativeDirectCallDiagnosticEncryptionService(ownUserID: peerUserID,
                                                                                          secret: "other-diagnostic-secret"))

        let generatedResult = await sender.generatePerCallKey(callID: "call-a",
                                                              roomID: roomID,
                                                              peerUserID: peerUserID)
        guard case .success(let generated) = generatedResult else {
            Issue.record("Expected diagnostic encryption key generation to succeed.")
            return
        }

        #expect(generated.payload.encryptedPayload.contains("diagnostic-shared-secret") == false)
        #expect(generated.payload.encryptedPayload.contains("other-diagnostic-secret") == false)
        #expect(await receiver.consumeRemoteEncryptedKey(generated.payload,
                                                         expectedCallID: "call-a",
                                                         expectedRoomID: roomID,
                                                         expectedSenderUserID: ownUserID) == .success(.init(callID: "call-a", keyID: generated.keyHandle.keyID)))
        #expect(await mismatchedReceiver.consumeRemoteEncryptedKey(generated.payload,
                                                                   expectedCallID: "call-a",
                                                                   expectedRoomID: roomID,
                                                                   expectedSenderUserID: ownUserID) == .failure(.keyMismatch))
        #expect(await receiver.consumeRemoteEncryptedKey(generated.payload,
                                                         expectedCallID: "wrong-call",
                                                         expectedRoomID: roomID,
                                                         expectedSenderUserID: ownUserID) == .failure(.keyMismatch))
        #expect(await receiver.consumeRemoteEncryptedKey(generated.payload,
                                                         expectedCallID: "call-a",
                                                         expectedRoomID: "!wrong:example.com",
                                                         expectedSenderUserID: ownUserID) == .failure(.keyMismatch))
        #expect(await receiver.consumeRemoteEncryptedKey(generated.payload,
                                                         expectedCallID: "call-a",
                                                         expectedRoomID: roomID,
                                                         expectedSenderUserID: peerUserID) == .failure(.keyMismatch))
        #expect(NativeDirectCallDiagnosticEncryptionService(ownUserID: ownUserID, secret: "") == nil)
        #expect(NativeDirectCallDiagnosticEncryptionService(ownUserID: "", secret: "diagnostic-shared-secret") == nil)
    }

    @Test
    func outgoingGenerationFailureEmitsNoInviteAndNoActiveSession() async {
        let encryptionService = EncryptionServiceSpy(senderUserID: ownUserID,
                                                     generateResult: .failure(.keyExchangeFailed))
        let engine = makeEngine(encryptionService: encryptionService)
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        let result = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)

        #expect(result == .failure(.encryptionFailed(.keyExchangeFailed)))
        #expect(engine.activeSessionPublisher.value == nil)
        #expect(emittedSignals.isEmpty)
    }

    @Test
    func outgoingSDKTrustViolationEmitsNoInviteAndNoActiveSession() async {
        let encryptionService = EncryptionServiceSpy(senderUserID: ownUserID,
                                                     generateResult: .failure(.sdkTrustViolation))
        let engine = makeEngine(encryptionService: encryptionService)
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        let result = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)

        #expect(result == .failure(.encryptionFailed(.sdkTrustViolation)))
        #expect(engine.activeSessionPublisher.value == nil)
        #expect(emittedSignals.isEmpty)
    }

    @Test
    func encryptionFailureFailsClosed() async {
        let engine = makeEngine()

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

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
    func incomingInviteMissingKeyExchangeFailsClosed() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        let result = await engine.receiveIncomingCall(event: .init(eventID: "$invite",
                                                                   roomID: roomID,
                                                                   senderID: peerUserID,
                                                                   callID: "call-a",
                                                                   type: .invite,
                                                                   intent: .audio,
                                                                   timestamp: .now))

        #expect(result == .failure(.encryptionFailed(.missingKeyExchange)))
        #expect(engine.activeSessionPublisher.value == nil)
        #expect(mediaEngine.connectedSessions.isEmpty)
    }

    @Test
    func incomingInviteMismatchedKeyExchangeFailsClosed() async {
        let cases: [(DirectCallEncryptedKeyExchangePayload, DirectCallEngineError)] = [
            (keyExchange(callID: "other-call"), .callIDMismatch),
            (keyExchange(callID: "call-a", roomID: "!other:example.com"), .roomMismatch),
            (keyExchange(callID: "call-a", senderUserID: "@mallory:example.com"), .invalidSender)
        ]

        for (payload, expectedError) in cases {
            let mediaEngine = MediaEngineSpy()
            let engine = makeEngine(mediaEngine: mediaEngine)

            let result = await engine.receiveIncomingCall(event: .init(eventID: "$invite",
                                                                       roomID: roomID,
                                                                       senderID: peerUserID,
                                                                       callID: "call-a",
                                                                       type: .invite,
                                                                       intent: .audio,
                                                                       timestamp: .now,
                                                                       keyExchange: payload))

            #expect(result == .failure(expectedError))
            #expect(engine.activeSessionPublisher.value == nil)
            #expect(mediaEngine.connectedSessions.isEmpty)
        }
    }

    @Test
    func incomingInviteEnvelopeMetadataFailuresAreRejectedBeforeSessionCreation() async {
        let expiredPayload = keyExchange(callID: "call-a",
                                         recipientUserID: ownUserID,
                                         intent: .audio,
                                         expiresAt: Date(timeIntervalSince1970: 1))
        let wrongRecipientPayload = keyExchange(callID: "call-b",
                                                recipientUserID: "@other:example.com",
                                                intent: .audio,
                                                expiresAt: Date(timeIntervalSince1970: 60))
        let wrongIntentPayload = keyExchange(callID: "call-c",
                                             recipientUserID: ownUserID,
                                             intent: .video,
                                             expiresAt: Date(timeIntervalSince1970: 60))

        let cases: [(DirectCallEncryptedKeyExchangePayload, DirectCallEngineError)] = [
            (expiredPayload, .encryptionFailed(.expiredKeyExchange)),
            (wrongRecipientPayload, .encryptionFailed(.wrongRecipient)),
            (wrongIntentPayload, .invalidIntent)
        ]

        for (payload, expectedError) in cases {
            let mediaEngine = MediaEngineSpy()
            let engine = makeEngine(mediaEngine: mediaEngine) { Date(timeIntervalSince1970: 30) }

            let result = await engine.receiveIncomingCall(event: .init(eventID: "$invite-\(payload.callID)",
                                                                       roomID: roomID,
                                                                       senderID: peerUserID,
                                                                       callID: payload.callID,
                                                                       type: .invite,
                                                                       intent: .audio,
                                                                       timestamp: .now,
                                                                       keyExchange: payload))

            #expect(result == .failure(expectedError))
            #expect(engine.activeSessionPublisher.value == nil)
            #expect(mediaEngine.connectedSessions.isEmpty)
        }
    }

    @Test
    func validIncomingInviteConsumesKeyAndStoresHandleBeforeAccept() async {
        let encryptionService = EncryptionServiceSpy(senderUserID: ownUserID)
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(encryptionService: encryptionService, mediaEngine: mediaEngine)
        let payload = keyExchange(callID: "call-a")

        let result = await engine.receiveIncomingCall(event: .init(eventID: "$invite",
                                                                   roomID: roomID,
                                                                   senderID: peerUserID,
                                                                   callID: "call-a",
                                                                   type: .invite,
                                                                   intent: .audio,
                                                                   timestamp: .now,
                                                                   keyExchange: payload))

        guard case .success(let session) = result else {
            Issue.record("Expected valid invite key exchange to create an incoming session.")
            return
        }

        #expect(session?.state == .incomingRinging)
        #expect(session?.encryptionState == .ready)
        #expect(encryptionService.consumedPayloads == [payload])
        #expect(mediaEngine.connectedSessions.isEmpty)
    }

    @Test
    func acceptAfterValidIncomingInviteConnectsMediaUsingConsumedHandle() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$invite",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: "call-a",
                                                          type: .invite,
                                                          intent: .audio,
                                                          timestamp: .now,
                                                          keyExchange: keyExchange(callID: "call-a")))

        let result = await engine.acceptCall(callID: "call-a")

        guard case .success(let session) = result else {
            Issue.record("Expected incoming call accept to succeed.")
            return
        }

        #expect(session.state == .activeAudio)
        #expect(session.encryptionState == .ready)
        #expect(mediaEngine.connectedSessions.map(\.callID) == ["call-a"])
        #expect(mediaEngine.connectedKeyHandles == [.init(callID: "call-a", keyID: "key-a")])
    }

    @Test
    func callerReceivingAnswerConnectsMediaUsingGeneratedHandle() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        guard let activeSession = await startOutgoingAndReceiveAnswer(engine: engine) else {
            return
        }

        #expect(activeSession.state == .activeAudio)
        #expect(activeSession.encryptionState == .ready)
        #expect(mediaEngine.connectedSessions.map(\.callID) == [activeSession.callID])
        #expect(mediaEngine.connectedKeyHandles == [.init(callID: activeSession.callID, keyID: "key-\(activeSession.callID)")])
    }

    @Test
    func mediaConnectFailureFailsClosedAndCleansUp() async {
        let mediaEngine = MediaEngineSpy(connectResult: .failure(.mediaSetupUnavailable))
        let engine = makeEngine(mediaEngine: mediaEngine)

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let startedSession) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        let result = await engine.receiveIncomingCall(event: .init(eventID: "$answer",
                                                                   roomID: roomID,
                                                                   senderID: peerUserID,
                                                                   callID: startedSession.callID,
                                                                   type: .answer,
                                                                   intent: nil,
                                                                   timestamp: .now))

        #expect(result == .failure(.mediaConnectionFailed(.mediaSetupUnavailable)))
        #expect(engine.activeSessionPublisher.value?.state == .failed)
        #expect(mediaEngine.cleanupCallIDs == [startedSession.callID])
    }

    @Test
    func wrongKeyHandleDoesNotConnectMedia() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let startedSession) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        let result = await engine.markEncryptionEstablished(callID: startedSession.callID,
                                                            keyHandle: .init(callID: "other-call", keyID: "key-a"))

        #expect(result == .failure(.invalidEncryptionTransition))
        #expect(engine.activeSessionPublisher.value?.state == .outgoingRinging)
        #expect(mediaEngine.connectedSessions.isEmpty)
    }

    @Test
    func unsupportedVideoIntentDoesNotConnectAudioMedia() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        let startResult = await engine.startOutgoingVideoCall(peer: peerUserID, roomID: roomID)
        guard case .success(let startedSession) = startResult else {
            Issue.record("Expected outgoing video call start to succeed.")
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$answer",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: startedSession.callID,
                                                          type: .answer,
                                                          intent: nil,
                                                          timestamp: .now))

        #expect(engine.activeSessionPublisher.value?.state == .failed)
        #expect(mediaEngine.connectedSessions.isEmpty)
        #expect(mediaEngine.cleanupCallIDs == [startedSession.callID])
    }

    @Test
    func localHangupDisconnectsAndCleansMedia() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        guard let activeSession = await startConnectedAudioCall(engine: engine) else {
            return
        }

        _ = await engine.hangupActiveCall(callID: activeSession.callID)
        await engine.cleanupCall(callID: activeSession.callID)

        #expect(mediaEngine.disconnectCallIDs == [activeSession.callID])
        #expect(mediaEngine.cleanupCallIDs == [activeSession.callID])
    }

    @Test
    func remoteTerminalEventsDisconnectAndCleanMedia() async {
        for terminalType in [DirectCallSignalType.reject, .cancel, .hangup, .timeout] {
            let mediaEngine = MediaEngineSpy()
            let engine = makeEngine(mediaEngine: mediaEngine)

            guard let activeSession = await startConnectedAudioCall(engine: engine) else {
                return
            }

            _ = await engine.receiveIncomingCall(event: .init(eventID: "$terminal-\(terminalType.rawValue)",
                                                              roomID: roomID,
                                                              senderID: peerUserID,
                                                              callID: activeSession.callID,
                                                              type: terminalType,
                                                              intent: nil,
                                                              timestamp: .now))
            await engine.cleanupCall(callID: activeSession.callID)

            #expect(mediaEngine.disconnectCallIDs == [activeSession.callID])
            #expect(mediaEngine.cleanupCallIDs == [activeSession.callID])
        }
    }

    @Test
    func duplicateTerminalEventsDoNotDoubleCleanupMedia() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        guard let activeSession = await startConnectedAudioCall(engine: engine) else {
            return
        }

        let terminalEvent = DirectCallSignalEvent(eventID: "$terminal",
                                                  roomID: roomID,
                                                  senderID: peerUserID,
                                                  callID: activeSession.callID,
                                                  type: .hangup,
                                                  intent: nil,
                                                  timestamp: .now)
        _ = await engine.receiveIncomingCall(event: terminalEvent)
        _ = await engine.receiveIncomingCall(event: terminalEvent)
        await engine.cleanupCall(callID: activeSession.callID)
        await engine.cleanupCall(callID: activeSession.callID)

        #expect(mediaEngine.disconnectCallIDs == [activeSession.callID])
        #expect(mediaEngine.cleanupCallIDs == [activeSession.callID])
    }

    @Test
    func outgoingRingingTimeoutEmitsTimeoutSignalAndFailsClosed() async throws {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine,
                                cleanupDelay: .seconds(120),
                                outgoingRingingTimeout: .milliseconds(10))
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let session) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        try await Task.sleep(for: .milliseconds(40))

        #expect(engine.activeSessionPublisher.value?.state == .failed)
        #expect(emittedSignals.map(\.type) == [.invite, .timeout])
        #expect(mediaEngine.disconnectCallIDs == [session.callID])
        #expect(mediaEngine.cleanupCallIDs.isEmpty)
    }

    @Test
    func incomingRingingTimeoutEmitsTimeoutSignalAndMissesCall() async throws {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine,
                                cleanupDelay: .seconds(120),
                                incomingRingingTimeout: .milliseconds(10))
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$invite-timeout",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: "call-timeout",
                                                          type: .invite,
                                                          intent: .audio,
                                                          timestamp: .now,
                                                          keyExchange: keyExchange(callID: "call-timeout")))

        try await Task.sleep(for: .milliseconds(40))

        #expect(engine.activeSessionPublisher.value?.state == .missed)
        #expect(emittedSignals.map(\.type) == [.timeout])
        #expect(mediaEngine.disconnectCallIDs == ["call-timeout"])
        #expect(mediaEngine.cleanupCallIDs.isEmpty)
    }

    @Test
    func newOutgoingCallBeforeDelayedCleanupCleansPreviousTerminalMedia() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine, cleanupDelay: .seconds(120))

        guard let activeSession = await startConnectedAudioCall(engine: engine) else {
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$terminal",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: activeSession.callID,
                                                          type: .hangup,
                                                          intent: nil,
                                                          timestamp: .now))
        #expect(mediaEngine.cleanupCallIDs.isEmpty)

        let newCallResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)

        guard case .success(let newSession) = newCallResult else {
            Issue.record("Expected a new outgoing call to replace the terminal session.")
            return
        }

        #expect(newSession.state == .outgoingRinging)
        #expect(mediaEngine.cleanupCallIDs == [activeSession.callID])
        await engine.cleanupCall(callID: activeSession.callID)
        #expect(mediaEngine.cleanupCallIDs == [activeSession.callID])
    }

    @Test
    func newIncomingInviteBeforeDelayedCleanupCleansPreviousTerminalMedia() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine, cleanupDelay: .seconds(120))

        guard let activeSession = await startConnectedAudioCall(engine: engine) else {
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$terminal",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: activeSession.callID,
                                                          type: .hangup,
                                                          intent: nil,
                                                          timestamp: .now))
        #expect(mediaEngine.cleanupCallIDs.isEmpty)

        let newInviteResult = await engine.receiveIncomingCall(event: .init(eventID: "$invite-new",
                                                                            roomID: roomID,
                                                                            senderID: peerUserID,
                                                                            callID: "call-new",
                                                                            type: .invite,
                                                                            intent: .audio,
                                                                            timestamp: .now,
                                                                            keyExchange: keyExchange(callID: "call-new")))

        guard case .success(let newSession) = newInviteResult else {
            Issue.record("Expected a new incoming invite to replace the terminal session.")
            return
        }

        #expect(newSession?.state == .incomingRinging)
        #expect(mediaEngine.cleanupCallIDs == [activeSession.callID])
        await engine.cleanupCall(callID: activeSession.callID)
        #expect(mediaEngine.cleanupCallIDs == [activeSession.callID])
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

    private func makeEngine(encryptionService: DirectCallEncryptionServiceProtocol? = nil,
                            mediaEngine: DirectCallMediaEngineProtocol? = nil,
                            cleanupDelay: Duration = .milliseconds(20),
                            incomingRingingTimeout: Duration = .seconds(120),
                            outgoingRingingTimeout: Duration = .seconds(120),
                            connectingTimeout: Duration = .seconds(120),
                            now: @escaping () -> Date = Date.init) -> DirectCallEngine {
        DirectCallEngine(ownUserID: ownUserID,
                         configuration: .init(incomingRingingTimeout: incomingRingingTimeout,
                                              outgoingRingingTimeout: outgoingRingingTimeout,
                                              connectingTimeout: connectingTimeout,
                                              cleanupDelay: cleanupDelay,
                                              processedTerminalEventLimit: 64),
                         now: now,
                         encryptionService: encryptionService ?? EncryptionServiceSpy(senderUserID: ownUserID),
                         mediaEngine: mediaEngine) { [roomID, peerUserID] id in
            id == roomID ? peerUserID : nil
        }
    }

    private func keyExchange(callID: String,
                             roomID: String? = nil,
                             senderUserID: String? = nil,
                             keyID: String = "key-a",
                             encryptedPayload: String = "encrypted",
                             recipientUserID: String? = nil,
                             intent: DirectCallIntent? = nil,
                             expiresAt: Date? = nil) -> DirectCallEncryptedKeyExchangePayload {
        .init(callID: callID,
              roomID: roomID ?? self.roomID,
              senderUserID: senderUserID ?? peerUserID,
              keyID: keyID,
              encryptedPayload: encryptedPayload,
              version: recipientUserID == nil && intent == nil && expiresAt == nil ? nil : 1,
              algorithm: recipientUserID == nil && intent == nil && expiresAt == nil ? nil : "salemx.native_direct_call.media_key.v1",
              recipientUserID: recipientUserID,
              intent: intent,
              expiresAt: expiresAt)
    }

    private func startOutgoingAndReceiveAnswer(engine: DirectCallEngine) async -> DirectCallSession? {
        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let startedSession) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return nil
        }

        let answerResult = await engine.receiveIncomingCall(event: .init(eventID: "$answer",
                                                                         roomID: roomID,
                                                                         senderID: peerUserID,
                                                                         callID: startedSession.callID,
                                                                         type: .answer,
                                                                         intent: nil,
                                                                         timestamp: .now))
        guard case .success(let session) = answerResult,
              let session else {
            Issue.record("Expected incoming answer to move call into connecting.")
            return nil
        }

        return session
    }

    private func startConnectedAudioCall(engine: DirectCallEngine) async -> DirectCallSession? {
        await startOutgoingAndReceiveAnswer(engine: engine)
    }
}

@MainActor
private final class EncryptionServiceSpy: DirectCallEncryptionServiceProtocol {
    struct GenerateRequest: Equatable {
        let callID: String
        let roomID: String
        let peerUserID: String
    }

    private let senderUserID: String
    private let generateResult: Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason>?
    private let consumeResult: Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason>?

    private(set) var generatedRequests = [GenerateRequest]()
    private(set) var consumedPayloads = [DirectCallEncryptedKeyExchangePayload]()
    private(set) var clearedCallIDs = Set<String>()

    init(senderUserID: String = "@me:example.com",
         generateResult: Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason>? = nil,
         consumeResult: Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason>? = nil) {
        self.senderUserID = senderUserID
        self.generateResult = generateResult
        self.consumeResult = consumeResult
    }

    func generatePerCallKey(callID: String, roomID: String, peerUserID: String) async -> Result<DirectCallGeneratedKeyExchange, DirectCallEncryptionFailureReason> {
        generatedRequests.append(.init(callID: callID, roomID: roomID, peerUserID: peerUserID))

        if let generateResult {
            return generateResult
        }

        let keyID = "key-\(callID)"
        return .success(.init(payload: .init(callID: callID,
                                             roomID: roomID,
                                             senderUserID: senderUserID,
                                             keyID: keyID,
                                             encryptedPayload: "encrypted-\(callID)"),
                              keyHandle: .init(callID: callID, keyID: keyID)))
    }

    func consumeRemoteEncryptedKey(_ payload: DirectCallEncryptedKeyExchangePayload, expectedCallID: String, expectedRoomID: String, expectedSenderUserID: String) async -> Result<DirectCallMediaKeyHandle, DirectCallEncryptionFailureReason> {
        consumedPayloads.append(payload)

        if let consumeResult {
            return consumeResult
        }

        guard payload.callID == expectedCallID,
              payload.roomID == expectedRoomID,
              payload.senderUserID == expectedSenderUserID,
              !payload.keyID.isEmpty,
              !payload.encryptedPayload.isEmpty else {
            return .failure(.keyMismatch)
        }

        return .success(.init(callID: payload.callID, keyID: payload.keyID))
    }

    func clearPerCallKey(callID: String) {
        clearedCallIDs.insert(callID)
    }
}

@MainActor
private final class MediaEngineSpy: DirectCallMediaEngineProtocol {
    private let mediaStateSubject = CurrentValueSubject<DirectCallMediaState, Never>(.idle)
    private let connectResult: Result<DirectCallMediaState, DirectCallMediaError>

    private(set) var connectedSessions = [DirectCallSession]()
    private(set) var connectedKeyHandles = [DirectCallMediaKeyHandle]()
    private(set) var disconnectCallIDs = [String]()
    private(set) var cleanupCallIDs = [String]()

    var mediaStatePublisher: CurrentValuePublisher<DirectCallMediaState, Never> {
        mediaStateSubject.asCurrentValuePublisher()
    }

    init(connectResult: Result<DirectCallMediaState, DirectCallMediaError> = .success(.init(callID: "call-a",
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
