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

// swiftlint:disable file_length

// swiftlint:disable type_body_length
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
    func calleeMediaConnectFailureAfterAnswerEmitsTerminalAndCleansUp() async {
        let mediaEngine = MediaEngineSpy(connectResult: .failure(.tokenBackendRejected))
        let engine = makeEngine(mediaEngine: mediaEngine)
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$invite",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: "call-a",
                                                          type: .invite,
                                                          intent: .audio,
                                                          timestamp: .now,
                                                          keyExchange: keyExchange(callID: "call-a")))

        let result = await engine.acceptCall(callID: "call-a")

        #expect(result == .failure(.mediaConnectionFailed(.tokenBackendRejected)))
        #expect(engine.activeSessionPublisher.value?.state == .failed)
        #expect(emittedSignals.map(\.type) == [.answer, .hangup])
        #expect(mediaEngine.cleanupCallIDs == ["call-a"])
    }

    @Test
    func callerMediaConnectFailureAfterRemoteAnswerEmitsTerminalAndCleansUp() async {
        let mediaEngine = MediaEngineSpy(connectResult: .failure(.tokenBackendRejected))
        let engine = makeEngine(mediaEngine: mediaEngine)
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

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

        #expect(result == .failure(.mediaConnectionFailed(.tokenBackendRejected)))
        #expect(engine.activeSessionPublisher.value?.state == .failed)
        #expect(emittedSignals.map(\.type) == [.invite, .hangup])
        #expect(mediaEngine.cleanupCallIDs == [startedSession.callID])
    }

    @Test
    func callerManualHangupRacingPostAnswerMediaFailureDeduplicatesTerminal() async {
        let mediaEngine = DelayedMediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine, cleanupDelay: .seconds(120))
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let startedSession) = startResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        let answerTask = Task {
            await engine.receiveIncomingCall(event: .init(eventID: "$answer",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: startedSession.callID,
                                                          type: .answer,
                                                          intent: nil,
                                                          timestamp: .now))
        }
        #expect(await waitUntil { mediaEngine.connectedSessions.map(\.callID) == [startedSession.callID] })

        _ = await engine.hangupActiveCall(callID: startedSession.callID)
        mediaEngine.complete(with: .failure(.tokenBackendRejected))
        _ = await answerTask.value

        #expect(engine.activeSessionPublisher.value?.state == .ended)
        #expect(emittedSignals.map(\.type) == [.invite, .hangup])
        #expect(mediaEngine.cleanupCallIDs.isEmpty)
    }

    @Test
    func duplicatePostAnswerMediaFailureDoesNotEmitDuplicateTerminal() async {
        let mediaEngine = MediaEngineSpy(connectResult: .failure(.tokenBackendRejected))
        let engine = makeEngine(mediaEngine: mediaEngine)
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$invite",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: "call-a",
                                                          type: .invite,
                                                          intent: .audio,
                                                          timestamp: .now,
                                                          keyExchange: keyExchange(callID: "call-a")))

        _ = await engine.acceptCall(callID: "call-a")
        _ = await engine.markEncryptionEstablished(callID: "call-a", keyHandle: .init(callID: "call-a", keyID: "key-a"))
        _ = await engine.acceptCall(callID: "call-a")

        #expect(emittedSignals.map(\.type) == [.answer, .hangup])
        #expect(mediaEngine.cleanupCallIDs == ["call-a"])
    }

    @Test
    func manualHangupRacingPostAnswerMediaFailureDeduplicatesTerminal() async {
        let mediaEngine = DelayedMediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine, cleanupDelay: .seconds(120))
        var emittedSignals = [DirectCallOutgoingSignal]()
        let cancellable = engine.actionsPublisher.sink { action in
            guard case .emitSignal(let signal) = action else {
                return
            }
            emittedSignals.append(signal)
        }
        defer { cancellable.cancel() }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$invite",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: "call-a",
                                                          type: .invite,
                                                          intent: .audio,
                                                          timestamp: .now,
                                                          keyExchange: keyExchange(callID: "call-a")))

        let acceptTask = Task {
            await engine.acceptCall(callID: "call-a")
        }
        #expect(await waitUntil { mediaEngine.connectedSessions.map(\.callID) == ["call-a"] })

        _ = await engine.hangupActiveCall(callID: "call-a")
        mediaEngine.complete(with: .failure(.tokenBackendRejected))
        _ = await acceptTask.value

        #expect(engine.activeSessionPublisher.value?.state == .ended)
        #expect(emittedSignals.map(\.type) == [.answer, .hangup])
        #expect(mediaEngine.cleanupCallIDs.isEmpty)
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

        #expect(engine.activeSessionPublisher.value == nil)
        #expect(emittedSignals.map(\.type) == [.invite, .timeout])
        #expect(mediaEngine.disconnectCallIDs == [session.callID])
        #expect(mediaEngine.cleanupCallIDs == [session.callID])
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

        #expect(engine.activeSessionPublisher.value == nil)
        #expect(emittedSignals.map(\.type) == [.timeout])
        #expect(mediaEngine.disconnectCallIDs == ["call-timeout"])
        #expect(mediaEngine.cleanupCallIDs == ["call-timeout"])
    }

    @Test
    func remoteTimeoutClearsActiveSessionImmediately() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine, cleanupDelay: .seconds(120))

        guard let activeSession = await startConnectedAudioCall(engine: engine) else {
            return
        }

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$remote-timeout",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: activeSession.callID,
                                                          type: .timeout,
                                                          intent: nil,
                                                          timestamp: .now))

        #expect(engine.activeSessionPublisher.value == nil)
        #expect(mediaEngine.disconnectCallIDs == [activeSession.callID])
        #expect(mediaEngine.cleanupCallIDs == [activeSession.callID])
    }

    @Test
    func nextOutgoingCallAfterTimeoutSucceedsWithoutManualCleanup() async throws {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine,
                                cleanupDelay: .seconds(120),
                                outgoingRingingTimeout: .milliseconds(10))

        let timedOutCallResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        guard case .success(let timedOutSession) = timedOutCallResult else {
            Issue.record("Expected outgoing call start to succeed.")
            return
        }

        try await Task.sleep(for: .milliseconds(40))
        #expect(engine.activeSessionPublisher.value == nil)

        let nextCallResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)

        guard case .success(let nextSession) = nextCallResult else {
            Issue.record("Expected next outgoing call to start after timeout cleanup.")
            return
        }

        #expect(nextSession.state == .outgoingRinging)
        #expect(nextSession.callID != timedOutSession.callID)
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
final class NativeIncomingCallLifecycleContractTests {
    @Test
    func disabledNativeIncomingLifecycleServiceFailsClosedByDefault() {
        let dependencies = makeNativeIncomingLifecycleDependencies(isEnabled: false)

        let outcome = dependencies.service.receiveIncomingCall(handle: "safe-local-call",
                                                               receivedAt: .now,
                                                               context: .valid)

        #expect(outcome == .failClosed(.dependencyUnavailable))
        #expect(dependencies.reportingAdapter.reportedIdentities.isEmpty)
        #expect(dependencies.timeoutScheduler.scheduledIdentities.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics == [.failClosed(.dependencyUnavailable)])
    }

    @Test
    func malformedStaleAndDuplicateHandlesFailClosed() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let now = Date(timeIntervalSince1970: 1000)

        let malformed = dependencies.service.receiveIncomingCall(handle: "not safe",
                                                                 receivedAt: now,
                                                                 now: now,
                                                                 context: .valid)
        #expect(malformed == .failClosed(.malformed))

        let stale = dependencies.service.receiveIncomingCall(handle: "safe-local-call-stale",
                                                             receivedAt: now.addingTimeInterval(-120),
                                                             now: now,
                                                             context: .valid)
        #expect(stale == .failClosed(.stale))

        let first = dependencies.service.receiveIncomingCall(handle: "safe-local-call",
                                                             receivedAt: now,
                                                             now: now,
                                                             context: .valid)
        guard case .reported = first else {
            Issue.record("Expected the first safe handle to be reportable through the test adapter.")
            return
        }

        let duplicate = dependencies.service.receiveIncomingCall(handle: "safe-local-call",
                                                                 receivedAt: now,
                                                                 now: now,
                                                                 context: .valid)
        #expect(duplicate == .failClosed(.duplicate))
    }

    @Test
    func invalidValidationContextFailsClosedBeforeReporting() {
        let cases: [(NativeIncomingCallValidationContext, NativeIncomingCallFailClosedReason)] = [
            (.init(isEncryptedDirectOneToOneRoom: false), .notEncryptedDirectOneToOne),
            (.init(isPeerTrustReady: false), .trustNotReady),
            (.init(isEligible: false), .eligibilityDenied),
            (.init(areDependenciesAvailable: false), .dependencyUnavailable),
            (.init(hasExistingActiveNativeSession: true), .existingActiveNativeSession),
            (.init(isLoggedIn: false), .loggedOutOrSessionUnavailable),
            (.init(isRouteAvailable: false), .routeConflict)
        ]

        for (index, testCase) in cases.enumerated() {
            let dependencies = makeNativeIncomingLifecycleDependencies()
            let outcome = dependencies.service.receiveIncomingCall(handle: "safe-local-call-\(index)",
                                                                   receivedAt: .now,
                                                                   context: testCase.0)

            #expect(outcome == .failClosed(testCase.1))
            #expect(dependencies.reportingAdapter.reportedIdentities.isEmpty)
            #expect(dependencies.timeoutScheduler.scheduledIdentities.isEmpty)
        }
    }

    @Test
    func mediaCredentialRejectionMapsToSafeTerminalDiagnostics() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let now = Date(timeIntervalSince1970: 1000)

        let outcome = dependencies.service.receiveIncomingCall(handle: "safe-local-call",
                                                               receivedAt: now,
                                                               now: now,
                                                               context: .valid)
        guard case .reported(let identity) = outcome else {
            Issue.record("Expected safe incoming call identity to be reported.")
            return
        }

        let failure = dependencies.service.failAfterMediaCredentialRejection(identity: identity)

        #expect(failure == .failClosed(.serverIssuedMediaCredentialRejected))
        #expect(dependencies.stateStore.state(for: identity.handle) == .failed)
        #expect(dependencies.reportingAdapter.endedReasons == [.serverIssuedMediaCredentialRejected])
        #expect(dependencies.timeoutScheduler.cancelledIdentities == [identity])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.failClosedReason == .serverIssuedMediaCredentialRejected)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == true)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func callReportingAdapterReceivesOnlySafeIdentityData() {
        let dependencies = makeNativeIncomingLifecycleDependencies()

        _ = dependencies.service.receiveIncomingCall(handle: "safe-local-call",
                                                     receivedAt: .now,
                                                     context: .valid)

        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        let description = String(describing: dependencies.reportingAdapter.reportedIdentities[0])
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func pushRegistryTestDoubleStaysRedacted() {
        let registry = NativeIncomingPushRegistrySpy()
        let credential = NativeIncomingPushRegistrationCredential(kind: .voIP,
                                                                  value: Data("sensitive-incoming-credential-a".utf8))

        registry.updateIncomingCallPushCredential(credential)

        let description = String(describing: credential) + " " + String(describing: registry)
        #expect(description.contains("<redacted>"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func backgroundInvitePayloadParserAcceptsValidMinimalPayload() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()

        let result = parser.parse(makeBackgroundInvitePayload(now: now), now: now)

        guard case .valid(let payload) = result else {
            Issue.record("Expected background invite payload to parse.")
            return
        }
        #expect(payload.kind == .audio)
        #expect(String(describing: result) == "valid(payload: <redacted>)")
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: payload).contains($0) })
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
    }

    @Test
    func backgroundInvitePayloadParserRejectsMalformedMissingAndUnsupportedPayloads() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()

        #expect(parser.parse([:], now: now) == .invalid(.malformedPayload))

        var missingFieldPayload = makeBackgroundInvitePayload(now: now)
        missingFieldPayload.removeValue(forKey: "call_handle")
        #expect(parser.parse(missingFieldPayload, now: now) == .invalid(.missingRequiredField))

        var invalidTypePayload = makeBackgroundInvitePayload(now: now)
        invalidTypePayload["created_at_ms"] = "not-a-timestamp"
        #expect(parser.parse(invalidTypePayload, now: now) == .invalid(.invalidType))

        var unsupportedVersionPayload = makeBackgroundInvitePayload(now: now)
        unsupportedVersionPayload["version"] = 2
        #expect(parser.parse(unsupportedVersionPayload, now: now) == .invalid(.unsupportedVersion))

        var malformedPayload = makeBackgroundInvitePayload(now: now)
        malformedPayload["call_handle"] = "!unsafe-room"
        #expect(parser.parse(malformedPayload, now: now) == .invalid(.malformedPayload))
    }

    @Test
    func backgroundInvitePayloadParserMatchesForegroundTimestampGuardrails() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()

        let current = parser.parse(makeBackgroundInvitePayload(now: now), now: now)
        let smallFutureSkew = parser.parse(makeBackgroundInvitePayload(now: now,
                                                                       createdAt: now.addingTimeInterval(3),
                                                                       expiresAt: now.addingTimeInterval(30)),
                                           now: now)
        let excessiveFutureSkew = parser.parse(makeBackgroundInvitePayload(now: now,
                                                                           createdAt: now.addingTimeInterval(10),
                                                                           expiresAt: now.addingTimeInterval(30)),
                                               now: now)
        let expired = parser.parse(makeBackgroundInvitePayload(now: now,
                                                               createdAt: now.addingTimeInterval(-60),
                                                               expiresAt: now.addingTimeInterval(-1)),
                                   now: now)
        let invalidTimestamp = parser.parse(makeBackgroundInvitePayload(now: now,
                                                                        createdAt: now.addingTimeInterval(10),
                                                                        expiresAt: now.addingTimeInterval(5)),
                                            now: now)

        guard case .valid = current else {
            Issue.record("Expected current timestamp payload to parse.")
            return
        }
        guard case .valid = smallFutureSkew else {
            Issue.record("Expected small future skew payload to parse.")
            return
        }
        #expect(excessiveFutureSkew == .invalid(.futureTimestampExcessive))
        #expect(expired == .invalid(.expired))
        #expect(invalidTimestamp == .invalid(.invalidTimestamp))
    }

    @Test
    func backgroundInvitePayloadParserDiagnosticsStayRedactedAndSideEffectFree() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        var payload = makeBackgroundInvitePayload(now: now)
        payload["call_handle"] = "redacted-fixture-a"
        payload["display_label"] = "unsafe/label"
        payload["private_fixture"] = "redacted-fixture-b"

        let result = parser.parse(payload, now: now)
        let description = String(describing: parser) + " " + String(describing: result)

        #expect(result == .invalid(.malformedPayload))
        #expect(description.contains("pushRegistryRuntime: false"))
        #expect(description.contains("apnsRegistrationRuntime: false"))
        #expect(description.contains("mediaConnectRuntime: false"))
        #expect(description.contains("matrixEventRuntime: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func backgroundInviteIntakePreparesValidParsedInviteWithoutSideEffects() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now), now: now)

        let result = intake.evaluate(parsed, authenticatedSessionAvailable: true)

        #expect(result.decision == .prepareForegroundEquivalentIncoming)
        #expect(result.preparedIncoming != nil)
        #expect(result.diagnostics.payloadParseStatus == "valid")
        #expect(result.diagnostics.callKitReportRequested == false)
        #expect(result.diagnostics.mediaCredentialsRequested == false)
        #expect(result.diagnostics.mediaConnectRequested == false)
        #expect(result.diagnostics.matrixEventEmitRequested == false)
        #expect(result.diagnostics.blockedReason == nil)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
    }

    @Test
    func backgroundInviteIntakeRequiresSessionAndDefersCallKitReporting() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now), now: now)

        let withoutSession = intake.evaluate(parsed)
        let withReportAdapter = intake.evaluate(parsed,
                                                authenticatedSessionAvailable: true,
                                                callKitReportAdapterAvailable: true)

        #expect(withoutSession.decision == .requiresAuthenticatedSession)
        #expect(withoutSession.preparedIncoming == nil)
        #expect(withoutSession.diagnostics.blockedReason == .authenticatedSessionUnavailable)
        #expect(withoutSession.diagnostics.callKitReportRequested == false)
        #expect(withReportAdapter.decision == .requiresCallKitReportLater)
        #expect(withReportAdapter.preparedIncoming != nil)
        #expect(withReportAdapter.diagnostics.callKitReportRequested == false)
    }

    @Test
    func backgroundInviteIntakeIgnoresInvalidExpiredAndExcessiveFuturePayloads() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()

        var missingFieldPayload = makeBackgroundInvitePayload(now: now)
        missingFieldPayload.removeValue(forKey: "call_handle")
        let invalid = intake.evaluate(parser.parse(missingFieldPayload, now: now),
                                      authenticatedSessionAvailable: true)
        let expired = intake.evaluate(parser.parse(makeBackgroundInvitePayload(now: now,
                                                                               createdAt: now.addingTimeInterval(-60),
                                                                               expiresAt: now.addingTimeInterval(-1)),
                                                   now: now),
                                      authenticatedSessionAvailable: true)
        let excessiveFuture = intake.evaluate(parser.parse(makeBackgroundInvitePayload(now: now,
                                                                                       createdAt: now.addingTimeInterval(10),
                                                                                       expiresAt: now.addingTimeInterval(30)),
                                                           now: now),
                                              authenticatedSessionAvailable: true)

        #expect(invalid.decision == .ignoreInvalidPayload)
        #expect(invalid.diagnostics.blockedReason == .invalidPayload)
        #expect(expired.decision == .ignoreExpiredPayload)
        #expect(expired.diagnostics.blockedReason == .expiredPayload)
        #expect(excessiveFuture.decision == .ignoreFutureTimestampExcessive)
        #expect(excessiveFuture.diagnostics.blockedReason == .futureTimestampExcessive)
        #expect(invalid.preparedIncoming == nil)
        #expect(expired.preparedIncoming == nil)
        #expect(excessiveFuture.preparedIncoming == nil)
    }

    @Test
    func backgroundInviteIntakeKeepsDiagnosticsRedactedAndRuntimeFree() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now,
                                                              createdAt: now.addingTimeInterval(3),
                                                              expiresAt: now.addingTimeInterval(30)),
                                  now: now)

        let result = intake.evaluate(parsed,
                                     authenticatedSessionAvailable: true,
                                     callKitReportAdapterAvailable: true)
        let description = String(describing: intake) + " " + String(describing: result)

        #expect(result.decision == .requiresCallKitReportLater)
        #expect(description.contains("payload_parse_status=valid"))
        #expect(description.contains("callkit_report_requested=false"))
        #expect(description.contains("media_credentials_requested=false"))
        #expect(description.contains("media_connect_requested=false"))
        #expect(description.contains("matrix_event_emit_requested=false"))
        #expect(description.contains("pushRegistryRuntime: false"))
        #expect(description.contains("apnsRegistrationRuntime: false"))
        #expect(description.contains("callKitReportRuntime: false"))
        #expect(description.contains("mediaConnectRuntime: false"))
        #expect(description.contains("matrixEventRuntime: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func backgroundCallKitReportPlannerProducesReportableRequestForValidIntake() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now), now: now)
        let intakeResult = intake.evaluate(parsed,
                                           authenticatedSessionAvailable: true,
                                           callKitReportAdapterAvailable: true)
        let planner = DirectCallBackgroundCallKitReportPlanner {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 43))
        }

        let result = planner.plan(from: intakeResult)

        #expect(result.decision == .reportableIncomingCallRequest)
        #expect(result.request?.kind == .audio)
        #expect(result.diagnostics.callKitReportRequested == true)
        #expect(result.diagnostics.mediaCredentialsRequested == false)
        #expect(result.diagnostics.mediaConnectRequested == false)
        #expect(result.diagnostics.matrixEventEmitRequested == false)
        #expect(result.diagnostics.blockedReason == nil)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
    }

    @Test
    func backgroundCallKitReportPlannerRejectsInvalidExpiredAndFutureIntake() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let planner = DirectCallBackgroundCallKitReportPlanner()

        var missingFieldPayload = makeBackgroundInvitePayload(now: now)
        missingFieldPayload.removeValue(forKey: "call_handle")
        let invalid = planner.plan(from: intake.evaluate(parser.parse(missingFieldPayload, now: now),
                                                         authenticatedSessionAvailable: true))
        let expired = planner.plan(from: intake.evaluate(parser.parse(makeBackgroundInvitePayload(now: now,
                                                                                                  createdAt: now.addingTimeInterval(-60),
                                                                                                  expiresAt: now.addingTimeInterval(-1)),
                                                                      now: now),
                                                         authenticatedSessionAvailable: true))
        let excessiveFuture = planner.plan(from: intake.evaluate(parser.parse(makeBackgroundInvitePayload(now: now,
                                                                                                          createdAt: now.addingTimeInterval(10),
                                                                                                          expiresAt: now.addingTimeInterval(30)),
                                                                              now: now),
                                                                 authenticatedSessionAvailable: true))

        #expect(invalid.decision == .notReportableInvalidPayload)
        #expect(invalid.diagnostics.blockedReason == .invalidPayload)
        #expect(expired.decision == .notReportableExpiredPayload)
        #expect(expired.diagnostics.blockedReason == .expiredPayload)
        #expect(excessiveFuture.decision == .notReportableFutureTimestampExcessive)
        #expect(excessiveFuture.diagnostics.blockedReason == .futureTimestampExcessive)
        #expect(invalid.request == nil)
        #expect(expired.request == nil)
        #expect(excessiveFuture.request == nil)
        #expect(invalid.diagnostics.callKitReportRequested == false)
        #expect(expired.diagnostics.callKitReportRequested == false)
        #expect(excessiveFuture.diagnostics.callKitReportRequested == false)
    }

    @Test
    func backgroundCallKitReportPlannerRepresentsMissingSessionSafely() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now), now: now)
        let intakeResult = intake.evaluate(parsed)
        let planner = DirectCallBackgroundCallKitReportPlanner()

        let result = planner.plan(from: intakeResult)

        #expect(result.decision == .notReportableRequiresAuthenticatedSession)
        #expect(result.request == nil)
        #expect(result.diagnostics.blockedReason == .authenticatedSessionUnavailable)
        #expect(result.diagnostics.callKitReportRequested == false)
    }

    @Test
    func backgroundCallKitReportPlannerKeepsDiagnosticsRedactedAndRuntimeFree() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now,
                                                              createdAt: now.addingTimeInterval(3),
                                                              expiresAt: now.addingTimeInterval(30)),
                                  now: now)
        let intakeResult = intake.evaluate(parsed,
                                           authenticatedSessionAvailable: true,
                                           callKitReportAdapterAvailable: true)
        let planner = DirectCallBackgroundCallKitReportPlanner {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 44))
        }

        let result = planner.plan(from: intakeResult)
        let description = String(describing: planner) + " " + String(describing: result)

        #expect(description.contains("callkit_planner_invoked=true"))
        #expect(description.contains("callkit_report_decision=reportable_incoming_call_request"))
        #expect(description.contains("callkit_report_requested=true"))
        #expect(description.contains("media_credentials_requested=false"))
        #expect(description.contains("media_connect_requested=false"))
        #expect(description.contains("matrix_event_emit_requested=false"))
        #expect(description.contains("callKitRuntime: false"))
        #expect(description.contains("pushRegistryRuntime: false"))
        #expect(description.contains("apnsRegistrationRuntime: false"))
        #expect(description.contains("mediaConnectRuntime: false"))
        #expect(description.contains("matrixEventRuntime: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func backgroundCallKitReportingAdapterRecordsOneFakeReportAttempt() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now), now: now)
        let intakeResult = intake.evaluate(parsed,
                                           authenticatedSessionAvailable: true,
                                           callKitReportAdapterAvailable: true)
        let planner = DirectCallBackgroundCallKitReportPlanner {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 45))
        }
        let planningResult = planner.plan(from: intakeResult)
        var recordedRequests = [DirectCallBackgroundCallKitReportRequest]()
        let adapter = DirectCallBackgroundCallKitReportingAdapter { request in
            recordedRequests.append(request)
            return true
        }

        let result = adapter.report(planningResult)

        #expect(recordedRequests.count == 1)
        #expect(result.status == .reportAttemptRecorded)
        #expect(result.diagnostics.callKitAdapterInvoked == true)
        #expect(result.diagnostics.callKitReportAttempted == true)
        #expect(result.diagnostics.callKitReportResult == .reportAttemptRecorded)
        #expect(result.diagnostics.mediaCredentialsRequested == false)
        #expect(result.diagnostics.mediaConnectRequested == false)
        #expect(result.diagnostics.matrixEventEmitRequested == false)
        #expect(result.diagnostics.pushKitRegistrationRequested == false)
        #expect(result.diagnostics.apnsRegistrationRequested == false)
        #expect(result.diagnostics.blockedReason == nil)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: recordedRequests[0]).contains($0) })
    }

    @Test
    func backgroundCallKitReportingAdapterSkipsNonReportableDecisions() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let planner = DirectCallBackgroundCallKitReportPlanner()
        var missingFieldPayload = makeBackgroundInvitePayload(now: now)
        missingFieldPayload.removeValue(forKey: "call_handle")
        let planningResult = planner.plan(from: intake.evaluate(parser.parse(missingFieldPayload, now: now),
                                                                authenticatedSessionAvailable: true))
        var recordedRequests = [DirectCallBackgroundCallKitReportRequest]()
        let adapter = DirectCallBackgroundCallKitReportingAdapter { request in
            recordedRequests.append(request)
            return true
        }

        let result = adapter.report(planningResult)

        #expect(recordedRequests.isEmpty)
        #expect(result.status == .notReportedNotReportable)
        #expect(result.diagnostics.callKitReportAttempted == false)
        #expect(result.diagnostics.blockedReason == .notReportable)
        #expect(result.diagnostics.mediaCredentialsRequested == false)
        #expect(result.diagnostics.mediaConnectRequested == false)
        #expect(result.diagnostics.matrixEventEmitRequested == false)
        #expect(result.diagnostics.pushKitRegistrationRequested == false)
        #expect(result.diagnostics.apnsRegistrationRequested == false)
    }

    @Test
    func backgroundCallKitReportingAdapterRepresentsMissingAuthenticatedContextSafely() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now), now: now)
        let intakeResult = intake.evaluate(parsed)
        let planningResult = DirectCallBackgroundCallKitReportPlanner().plan(from: intakeResult)
        let adapter = DirectCallBackgroundCallKitReportingAdapter { _ in
            Issue.record("Non-reportable missing-session decisions must not record a report attempt.")
            return true
        }

        let result = adapter.report(planningResult)

        #expect(result.status == .notReportedMissingAuthenticatedContext)
        #expect(result.diagnostics.callKitReportAttempted == false)
        #expect(result.diagnostics.blockedReason == .authenticatedSessionUnavailable)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
    }

    @Test
    func backgroundCallKitReportingAdapterKeepsDiagnosticsRedactedAndRuntimeFree() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now,
                                                              createdAt: now.addingTimeInterval(3),
                                                              expiresAt: now.addingTimeInterval(30)),
                                  now: now)
        let intakeResult = intake.evaluate(parsed,
                                           authenticatedSessionAvailable: true,
                                           callKitReportAdapterAvailable: true)
        let planner = DirectCallBackgroundCallKitReportPlanner {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 46))
        }
        let planningResult = planner.plan(from: intakeResult)
        let adapter = DirectCallBackgroundCallKitReportingAdapter { _ in true }

        let result = adapter.report(planningResult)
        let source = try Self.sourceFile("ElementX/Sources/Services/Calls/DirectCallModels.swift")
        let description = String(describing: adapter) + " " + String(describing: result)

        #expect(description.contains("callkit_adapter_invoked=true"))
        #expect(description.contains("callkit_report_attempted=true"))
        #expect(description.contains("callkit_report_result=report_attempt_recorded"))
        #expect(description.contains("media_credentials_requested=false"))
        #expect(description.contains("media_connect_requested=false"))
        #expect(description.contains("matrix_event_emit_requested=false"))
        #expect(description.contains("pushkit_registration_requested=false"))
        #expect(description.contains("apns_registration_requested=false"))
        #expect(description.contains("realCallKitRuntime: false"))
        #expect(description.contains("pushKitRuntime: false"))
        #expect(description.contains("apnsRegistrationRuntime: false"))
        #expect(description.contains("mediaRuntime: false"))
        #expect(description.contains("matrixEventRuntime: false"))
        #expect(!source.contains("PKPushRegistry"))
        #expect(!source.contains("reportNewIncomingCall"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func backgroundRealCallKitAdapterCallsFakeProviderOnce() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now), now: now)
        let intakeResult = intake.evaluate(parsed,
                                           authenticatedSessionAvailable: true,
                                           callKitReportAdapterAvailable: true)
        let planner = DirectCallBackgroundCallKitReportPlanner {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 47))
        }
        let planningResult = planner.plan(from: intakeResult)
        let provider = DirectCallBackgroundCallKitProviderSpy(reportResult: true)
        let adapter = DirectCallBackgroundRealCallKitReportingAdapter(provider: provider)

        let result = adapter.report(planningResult)

        #expect(provider.reportRequests.count == 1)
        #expect(result.status == .reportAttemptRecorded)
        #expect(result.diagnostics.realCallKitAdapterInvoked == true)
        #expect(result.diagnostics.callKitProviderReportAttempted == true)
        #expect(result.diagnostics.callKitProviderReportResult == .reportAttemptRecorded)
        #expect(result.diagnostics.providerFailureClass == nil)
        #expect(result.diagnostics.mediaCredentialsRequested == false)
        #expect(result.diagnostics.mediaConnectRequested == false)
        #expect(result.diagnostics.matrixEventEmitRequested == false)
        #expect(result.diagnostics.pushKitRegistrationRequested == false)
        #expect(result.diagnostics.apnsRegistrationRequested == false)
        #expect(result.diagnostics.blockedReason == nil)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: provider.reportRequests[0]).contains($0) })
    }

    @Test
    func backgroundRealCallKitAdapterSkipsNonReportableRequest() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let planner = DirectCallBackgroundCallKitReportPlanner()
        var missingFieldPayload = makeBackgroundInvitePayload(now: now)
        missingFieldPayload.removeValue(forKey: "call_handle")
        let planningResult = planner.plan(from: intake.evaluate(parser.parse(missingFieldPayload, now: now),
                                                                authenticatedSessionAvailable: true))
        let provider = DirectCallBackgroundCallKitProviderSpy(reportResult: true)
        let adapter = DirectCallBackgroundRealCallKitReportingAdapter(provider: provider)

        let result = adapter.report(planningResult)

        #expect(provider.reportRequests.isEmpty)
        #expect(result.status == .notReportedNotReportable)
        #expect(result.diagnostics.callKitProviderReportAttempted == false)
        #expect(result.diagnostics.blockedReason == .notReportable)
        #expect(result.diagnostics.mediaCredentialsRequested == false)
        #expect(result.diagnostics.mediaConnectRequested == false)
        #expect(result.diagnostics.matrixEventEmitRequested == false)
        #expect(result.diagnostics.pushKitRegistrationRequested == false)
        #expect(result.diagnostics.apnsRegistrationRequested == false)
    }

    @Test
    func backgroundRealCallKitAdapterRedactsProviderFailure() {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now), now: now)
        let intakeResult = intake.evaluate(parsed,
                                           authenticatedSessionAvailable: true,
                                           callKitReportAdapterAvailable: true)
        let planningResult = DirectCallBackgroundCallKitReportPlanner().plan(from: intakeResult)
        let provider = DirectCallBackgroundCallKitProviderSpy(reportResult: false)
        let adapter = DirectCallBackgroundRealCallKitReportingAdapter(provider: provider)

        let result = adapter.report(planningResult)

        #expect(provider.reportRequests.count == 1)
        #expect(result.status == .reportFailedRedacted)
        #expect(result.diagnostics.providerFailureClass == .providerFailedRedacted)
        #expect(result.diagnostics.blockedReason == .providerFailedRedacted)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
    }

    @Test
    func backgroundRealCallKitAdapterKeepsDiagnosticsRedactedAndUnwiredFromPushCallbacks() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let parser = DirectCallBackgroundInvitePayloadParser()
        let intake = DirectCallBackgroundInviteIntake()
        let parsed = parser.parse(makeBackgroundInvitePayload(now: now,
                                                              createdAt: now.addingTimeInterval(3),
                                                              expiresAt: now.addingTimeInterval(30)),
                                  now: now)
        let intakeResult = intake.evaluate(parsed,
                                           authenticatedSessionAvailable: true,
                                           callKitReportAdapterAvailable: true)
        let planner = DirectCallBackgroundCallKitReportPlanner {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 48))
        }
        let planningResult = planner.plan(from: intakeResult)
        let provider = DirectCallBackgroundCallKitProviderSpy(reportResult: true)
        let adapter = DirectCallBackgroundRealCallKitReportingAdapter(provider: provider)

        let result = adapter.report(planningResult)
        let modelSource = try Self.sourceFile("ElementX/Sources/Services/Calls/DirectCallModels.swift")
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let description = String(describing: adapter) + " " + String(describing: provider) + " " + String(describing: result)

        #expect(description.contains("real_callkit_adapter_invoked=true"))
        #expect(description.contains("callkit_provider_report_attempted=true"))
        #expect(description.contains("callkit_provider_report_result=report_attempt_recorded"))
        #expect(description.contains("provider_failure_class=none"))
        #expect(description.contains("media_credentials_requested=false"))
        #expect(description.contains("media_connect_requested=false"))
        #expect(description.contains("matrix_event_emit_requested=false"))
        #expect(description.contains("pushkit_registration_requested=false"))
        #expect(description.contains("apns_registration_requested=false"))
        #expect(description.contains("realCallKitRuntime: true"))
        #expect(description.contains("pushKitCallbackRuntime: false"))
        #expect(!modelSource.contains("PKPushRegistry"))
        #expect(!modelSource.contains("requestAuthorization"))
        #expect(adapterSource.contains("didReceiveIncomingPushWith payload"))
        #expect(adapterSource.contains("callkit_report_requested=false"))
        #expect(!adapterSource.contains("registerForRemoteNotifications"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func fakePushKitLifecyclePayloadFlowsThroughParserIntakePlannerAndFakeCallKit() {
        let now = Date(timeIntervalSince1970: 1000)
        let provider = DirectCallBackgroundCallKitProviderSpy(reportResult: true)
        let adapter = DirectCallBackgroundRealCallKitReportingAdapter(provider: provider)
        var manager = DirectCallFakePushKitLifecycleManager()
        manager.planner = DirectCallBackgroundCallKitReportPlanner {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 49))
        }
        manager.reportCallKit = { adapter.report($0) }

        let result = manager.handle(.payloadReceived(makeBackgroundInvitePayload(now: now)),
                                    now: now,
                                    authenticatedSessionAvailable: true)

        #expect(provider.reportRequests.count == 1)
        #expect(result.decision == .callKitReportAttemptRecorded)
        #expect(result.diagnostics.payloadReceived == true)
        #expect(result.diagnostics.payloadParseStatus == "valid(payload: <redacted>)")
        #expect(result.diagnostics.intakeDecision == .requiresCallKitReportLater)
        #expect(result.diagnostics.callKitReportDecision == .reportableIncomingCallRequest)
        #expect(result.diagnostics.callKitReportAttempted == true)
        #expect(result.diagnostics.pushKitRegistrationRequested == false)
        #expect(result.diagnostics.apnsRegistrationRequested == false)
        #expect(result.diagnostics.mediaCredentialsRequested == false)
        #expect(result.diagnostics.mediaConnectRequested == false)
        #expect(result.diagnostics.matrixEventEmitRequested == false)
        #expect(result.diagnostics.blockedReason == nil)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
    }

    @Test
    func fakePushKitLifecycleStopsInvalidExpiredAndFuturePayloadsSafely() {
        let now = Date(timeIntervalSince1970: 1000)
        let provider = DirectCallBackgroundCallKitProviderSpy(reportResult: true)
        let adapter = DirectCallBackgroundRealCallKitReportingAdapter(provider: provider)
        var manager = DirectCallFakePushKitLifecycleManager()
        manager.reportCallKit = { adapter.report($0) }

        var missingFieldPayload = makeBackgroundInvitePayload(now: now)
        missingFieldPayload.removeValue(forKey: "call_handle")
        let invalid = manager.handle(.payloadReceived(missingFieldPayload),
                                     now: now,
                                     authenticatedSessionAvailable: true)
        let expired = manager.handle(.payloadReceived(makeBackgroundInvitePayload(now: now,
                                                                                  createdAt: now.addingTimeInterval(-60),
                                                                                  expiresAt: now.addingTimeInterval(-1))),
                                     now: now,
                                     authenticatedSessionAvailable: true)
        let excessiveFuture = manager.handle(.payloadReceived(makeBackgroundInvitePayload(now: now,
                                                                                          createdAt: now.addingTimeInterval(10),
                                                                                          expiresAt: now.addingTimeInterval(30))),
                                             now: now,
                                             authenticatedSessionAvailable: true)

        #expect(provider.reportRequests.isEmpty)
        #expect(invalid.decision == .ignoreInvalidPayload)
        #expect(invalid.diagnostics.blockedReason == .invalidPayload)
        #expect(expired.decision == .ignoreExpiredPayload)
        #expect(expired.diagnostics.blockedReason == .expiredPayload)
        #expect(excessiveFuture.decision == .ignoreFutureTimestampExcessive)
        #expect(excessiveFuture.diagnostics.blockedReason == .futureTimestampExcessive)
        #expect([invalid, expired, excessiveFuture].allSatisfy { $0.diagnostics.callKitReportAttempted == false })
        #expect([invalid, expired, excessiveFuture].allSatisfy { $0.diagnostics.mediaCredentialsRequested == false })
        #expect([invalid, expired, excessiveFuture].allSatisfy { $0.diagnostics.mediaConnectRequested == false })
        #expect([invalid, expired, excessiveFuture].allSatisfy { $0.diagnostics.matrixEventEmitRequested == false })
    }

    @Test
    func fakePushKitLifecycleRequiresSessionBeforeCallKitPlanning() {
        let now = Date(timeIntervalSince1970: 1000)
        let provider = DirectCallBackgroundCallKitProviderSpy(reportResult: true)
        let adapter = DirectCallBackgroundRealCallKitReportingAdapter(provider: provider)
        var manager = DirectCallFakePushKitLifecycleManager()
        manager.reportCallKit = { adapter.report($0) }

        let result = manager.handle(.payloadReceived(makeBackgroundInvitePayload(now: now)), now: now)

        #expect(provider.reportRequests.isEmpty)
        #expect(result.decision == .requiresAuthenticatedSession)
        #expect(result.diagnostics.intakeDecision == .requiresAuthenticatedSession)
        #expect(result.diagnostics.callKitReportDecision == .notReportableRequiresAuthenticatedSession)
        #expect(result.diagnostics.callKitReportAttempted == false)
        #expect(result.diagnostics.blockedReason == .authenticatedSessionUnavailable)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
    }

    @Test
    func fakePushKitLifecycleTokenEventsStayRedactedAndUnpersisted() {
        let manager = DirectCallFakePushKitLifecycleManager()
        let tokenEvent = DirectCallPushKitLifecycleEvent.tokenUpdated(Data("sensitive-incoming-credential-a".utf8))
        let tokenUpdated = manager.handle(tokenEvent, now: Date(timeIntervalSince1970: 1000))
        let tokenInvalidated = manager.handle(.tokenInvalidated, now: Date(timeIntervalSince1970: 1000))
        let registrationRequested = manager.handle(.registrationRequested, now: Date(timeIntervalSince1970: 1000))

        let description = String(describing: manager)
            + " " + String(describing: tokenEvent)
            + " " + String(describing: tokenUpdated)
            + " " + String(describing: tokenInvalidated)
            + " " + String(describing: registrationRequested)

        #expect(tokenUpdated.decision == .tokenUpdateReceived)
        #expect(tokenUpdated.diagnostics.tokenUpdateReceived == true)
        #expect(tokenUpdated.diagnostics.blockedReason == .tokenNotPersisted)
        #expect(tokenInvalidated.decision == .tokenInvalidated)
        #expect(tokenInvalidated.diagnostics.tokenInvalidated == true)
        #expect(registrationRequested.decision == .registrationDeferred)
        #expect(registrationRequested.diagnostics.pushKitRegistrationRequested == false)
        #expect(registrationRequested.diagnostics.apnsRegistrationRequested == false)
        #expect(description.contains("tokenPersistenceRuntime: false"))
        #expect(description.contains("pushkit_registration_requested=false"))
        #expect(description.contains("apns_registration_requested=false"))
        #expect(!description.contains("sensitive-incoming-credential-a"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func fakePushKitLifecycleDiagnosticsStayRedactedAndRuntimeFree() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let provider = DirectCallBackgroundCallKitProviderSpy(reportResult: false)
        let adapter = DirectCallBackgroundRealCallKitReportingAdapter(provider: provider)
        var manager = DirectCallFakePushKitLifecycleManager()
        manager.reportCallKit = { adapter.report($0) }

        let result = manager.handle(.payloadReceived(makeBackgroundInvitePayload(now: now)),
                                    now: now,
                                    authenticatedSessionAvailable: true)
        let modelSource = try Self.sourceFile("ElementX/Sources/Services/Calls/DirectCallModels.swift")
        let description = String(describing: manager) + " " + String(describing: result)

        #expect(result.decision == .callKitReportFailedRedacted)
        #expect(result.diagnostics.callKitReportAttempted == true)
        #expect(result.diagnostics.blockedReason == .callKitReportFailedRedacted)
        #expect(description.contains("pushkit_lifecycle_invoked=true"))
        #expect(description.contains("payload_parse_status=valid(payload: <redacted>)"))
        #expect(description.contains("intake_decision=requires_callkit_report_later"))
        #expect(description.contains("callkit_report_decision=reportable_incoming_call_request"))
        #expect(description.contains("media_credentials_requested=false"))
        #expect(description.contains("media_connect_requested=false"))
        #expect(description.contains("matrix_event_emit_requested=false"))
        #expect(description.contains("pushKitRuntime: false"))
        #expect(description.contains("apnsRegistrationRuntime: false"))
        #expect(description.contains("realCallKitRuntime: false"))
        #expect(!modelSource.contains("PKPushRegistry"))
        #expect(!modelSource.contains("PKPushCredentials"))
        #expect(!modelSource.contains("PKPushPayload"))
        #expect(!modelSource.contains("requestAuthorization"))
        #expect(!modelSource.contains("registerForRemoteNotifications"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func gatedPushKitRegistrarDefaultDisabledDoesNotCreateRegistryOrRequestToken() {
        let factory = DirectCallPushKitRegistryFactorySpy()
        let registrar = DirectCallPushKitRegistrar(configuration: .init(registryFactory: factory))

        let result = registrar.startRegistration()

        let description = String(describing: registrar) + " " + String(describing: result)
        #expect(result.status == .disabled)
        #expect(result.diagnostics.pushKitFeatureGateEnabled == false)
        #expect(result.diagnostics.pushKitRegistryCreateRequested == false)
        #expect(result.diagnostics.pushKitTokenUpdateReceived == false)
        #expect(result.diagnostics.pushKitTokenInvalidated == false)
        #expect(result.diagnostics.pushKitTokenPersistenceRequested == false)
        #expect(result.diagnostics.pushKitTokenUploadRequested == false)
        #expect(result.diagnostics.blockedReason == .featureGateDisabled)
        #expect(factory.makeRegistryCount == 0)
        #expect(factory.registry?.requestRegistrationCount == nil)
        #expect(description.contains("startupWiring: false"))
        #expect(description.contains("apnsRegistrationRuntime: false"))
        #expect(description.contains("mediaRuntime: false"))
        #expect(description.contains("matrixEventRuntime: false"))
        #expect(description.contains("tokenPersistenceRuntime: false"))
        #expect(description.contains("tokenUploadRuntime: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func gatedPushKitRegistrarEnabledTestConfigurationCreatesOnlyFakeRegistry() {
        let factory = DirectCallPushKitRegistryFactorySpy()
        let registrar = DirectCallPushKitRegistrar(configuration: .init(featureGate: .init(isEnabled: true),
                                                                        registryFactory: factory))

        let result = registrar.startRegistration()

        #expect(result.status == .registryCreated)
        #expect(result.diagnostics.pushKitFeatureGateEnabled == true)
        #expect(result.diagnostics.pushKitRegistryCreateRequested == true)
        #expect(result.diagnostics.pushKitTokenPersistenceRequested == false)
        #expect(result.diagnostics.pushKitTokenUploadRequested == false)
        #expect(result.diagnostics.blockedReason == nil)
        #expect(factory.makeRegistryCount == 1)
        #expect(factory.registry?.requestRegistrationCount == 1)
        #expect(String(describing: factory).contains("fakeRegistryOnly: true"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
    }

    @Test
    func gatedPushKitRegistrarTokenEventsStayRedactedAndUnpersisted() {
        var handledResults = [DirectCallPushKitRegistrarResult]()
        var configuration = DirectCallPushKitRegistrarConfiguration(featureGate: .init(isEnabled: true),
                                                                    registryFactory: DirectCallPushKitRegistryFactorySpy())
        configuration.resultHandler = { result in
            handledResults.append(result)
        }
        let registrar = DirectCallPushKitRegistrar(configuration: configuration)
        let rawPushKitToken = Data("local-redacted-pushkit-token-fixture".utf8)

        let update = registrar.handleTokenUpdate(rawPushKitToken)
        let invalidation = registrar.handleTokenInvalidation()

        let description = String(describing: update) + " " + String(describing: invalidation)
        #expect(update.status == .tokenUpdateReceived)
        #expect(update.diagnostics.pushKitTokenUpdateReceived == true)
        #expect(update.diagnostics.pushKitTokenPersistenceRequested == false)
        #expect(update.diagnostics.pushKitTokenUploadRequested == false)
        #expect(update.diagnostics.blockedReason == .tokenNotPersisted)
        #expect(invalidation.status == .tokenInvalidated)
        #expect(invalidation.diagnostics.pushKitTokenInvalidated == true)
        #expect(invalidation.diagnostics.pushKitTokenPersistenceRequested == false)
        #expect(invalidation.diagnostics.pushKitTokenUploadRequested == false)
        #expect(handledResults.map(\.status) == [.tokenUpdateReceived, .tokenInvalidated])
        #expect(!description.contains("local-redacted-pushkit-token-fixture"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func gatedPushKitRegistrarDiagnosticsStayRedactedAndUnwiredFromStartup() throws {
        let registrar = DirectCallPushKitRegistrar()
        let result = registrar.startRegistration()
        let modelSource = try Self.sourceFile("ElementX/Sources/Services/Calls/DirectCallModels.swift")
        let registrarSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let developerOptionsSource = try Self.sourceFile("ElementX/Sources/AppHooks/Hooks/DeveloperOptionsScreenHook.swift")
        let appSessionSource = try Self.sourceFile("ElementX/Sources/Services/Session/UserSession.swift")

        let description = String(describing: registrar) + " " + String(describing: result)
        #expect(description.contains("pushkit_registrar_invoked=true"))
        #expect(description.contains("pushkit_feature_gate_enabled=false"))
        #expect(description.contains("pushkit_registry_create_requested=false"))
        #expect(description.contains("pushkit_token_persistence_requested=false"))
        #expect(description.contains("pushkit_token_upload_requested=false"))
        #expect(description.contains("blocked_reason=feature_gate_disabled"))
        #expect(!modelSource.contains("PKPushRegistry"))
        #expect(registrarSource.contains("DirectCallRealPushKitRegistryFactory"))
        #expect(registrarSource.contains("SalemXPushKitRegistrationSmokeDebugBridge"))
        #expect(registrarSource.contains("pushkit_registration_result=\\("))
        #expect(registrarSource.contains("\"token_received\""))
        #expect(developerOptionsSource.contains("PushKit registration smoke"))
        #expect(developerOptionsSource.contains("pushKitRegistrationSmokeProof"))
        #expect(registrarSource.contains("didReceiveIncomingPushWith payload"))
        #expect(!registrarSource.contains("registerForRemoteNotifications"))
        #expect(!appSessionSource.contains("DirectCallPushKitRegistrar"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func debugVoIPPushReceiptProofRequestsControlledCallKitReportOnly() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let appSessionSource = try Self.sourceFile("ElementX/Sources/Services/Session/UserSession.swift")

        #expect(adapterSource.contains("didReceiveIncomingPushWith payload"))
        #expect(adapterSource.contains("guard type == .voIP"))
        #expect(adapterSource.contains("completion()"))
        #expect(adapterSource.contains("recordVoIPPushReceipt(payloadDictionary, completion: completion)"))
        #expect(adapterSource.contains("static func recordVoIPPushReceipt(_ payload: [AnyHashable: Any], completion: @escaping () -> Void)"))
        let callbackStart = try #require(adapterSource.range(of: "didReceiveIncomingPushWith payload")?.lowerBound)
        let controlledReceipt = try #require(adapterSource.range(of: "recordVoIPPushReceipt(payloadDictionary, completion: completion)")?.lowerBound)
        let nonDebugCompletion = try #require(adapterSource.range(of: "#else\n        completion()", range: controlledReceipt..<adapterSource.endIndex)?.lowerBound)
        #expect(callbackStart < controlledReceipt)
        #expect(controlledReceipt < nonDebugCompletion)
        #expect(adapterSource.contains("physical_voip_push_received=\\(physicalVoIPPushReceived)"))
        #expect(adapterSource.contains("pushkit_callback_invoked=\\(callbackInvoked)"))
        #expect(adapterSource.contains("pushkit_payload_redacted=true"))
        #expect(adapterSource.contains("pushkit_payload_kind=\\(payloadKind)"))
        #expect(adapterSource.contains("sandbox_voip_smoke"))
        #expect(adapterSource.contains("pushkit_completion_called=\\(completionCalled)"))
        #expect(adapterSource.contains("completionCalled: false"))
        #expect(adapterSource.contains("reportedSummary.completionCalled = true"))
        #expect(adapterSource.contains("callkit_report_requested=\\(callKitReportRequested)"))
        #expect(adapterSource.contains("callkit_report_result=\\(callKitReportResult)"))
        #expect(adapterSource.contains("callkit_report_error_redacted=true"))
        #expect(adapterSource.contains("callkit_answer_action_received=\\(callKitAnswerActionReceived)"))
        #expect(adapterSource.contains("callkit_answer_action_fulfilled=\\(callKitAnswerActionFulfilled)"))
        #expect(adapterSource.contains("app_activation_observed=\\(appActivationObserved)"))
        #expect(adapterSource.contains("controlled_in_app_activation_requested=\\(controlledInAppActivationRequested)"))
        #expect(adapterSource.contains("controlled_in_app_activation_observed=\\(controlledInAppActivationObserved)"))
        #expect(adapterSource.contains("controlled_in_app_screen_requested=\\(controlledInAppScreenRequested)"))
        #expect(adapterSource.contains("controlled_in_app_screen_presented=\\(controlledInAppScreenPresented)"))
        #expect(adapterSource.contains("controlled_in_app_screen_source=\\(controlledInAppScreenSource)"))
        #expect(adapterSource.contains("controlledInAppActivationRequested = true"))
        #expect(adapterSource.contains("controlledInAppActivationObserved = true"))
        #expect(adapterSource.contains("controlledInAppScreenRequested = true"))
        #expect(adapterSource.contains("controlledInAppScreenPresented = true"))
        #expect(adapterSource.contains("controlledInAppScreenSource = \"callkit_answer_sandbox_voip_smoke\""))
        #expect(adapterSource.contains("reportControlledSandboxVoIPSmokeCallKit()"))
        #expect(adapterSource.contains("recordCallKitAnswerActionProof()"))
        #expect(adapterSource.contains("SalemXPushKitCallKitProofEventRecorder"))
        #expect(adapterSource.contains("NativeIncomingSyntheticCallKitUIProofHarness.makePhysicalDeviceProofHarness"))
        #expect(adapterSource.contains("displayLabel: \"SalemX Test Call\""))
        #expect(adapterSource.contains("case .reported:"))
        #expect(adapterSource.contains("return \"reported\""))
        #expect(adapterSource.contains("func provider(_ provider: CXProvider, perform action: CXAnswerCallAction)"))
        #expect(adapterSource.contains("action.fulfill()"))
        #expect(adapterSource.contains("delegate?.syntheticCallKitUIReportingDidAnswer(callUUID: action.callUUID)"))
        #expect(adapterSource.contains("callkit_answer_action_not_observed"))
        #expect(adapterSource.contains("media_credentials_requested=false"))
        #expect(adapterSource.contains("media_connect_requested=false"))
        #expect(adapterSource.contains("matrix_event_emit_requested=false"))
        #expect(adapterSource.contains("real_call_flow_started=false"))
        #expect(!adapterSource.contains("payload.description"))
        #expect(!adapterSource.contains("payload.dictionaryPayload.description"))
        #expect(!adapterSource.contains("room_id"))
        #expect(!adapterSource.contains("call_handle"))
        #expect(!appSessionSource.contains("recordVoIPPushReceipt"))
    }

    @Test
    func pushKitTokenRegistrationClientValidSyntheticTokenUsesFakeTransportOnly() {
        let transport = DirectCallPushKitTokenRegistrationTransportSpy(result: .success)
        let client = DirectCallPushKitTokenRegistrationClient(transport: transport)
        let rawPushKitToken = Data("sensitive-incoming-credential-b".utf8)

        let result = client.register(token: rawPushKitToken)

        let description = String(describing: client)
            + " " + String(describing: result)
            + " " + String(describing: transport)
            + " " + String(describing: transport.requests)
        #expect(result.uploadResult == .fakeUploadSucceeded)
        #expect(result.diagnostics.pushKitTokenRegistrationInvoked == true)
        #expect(result.diagnostics.pushKitTokenPresent == true)
        #expect(result.diagnostics.pushKitTokenUploadRequested == true)
        #expect(result.diagnostics.pushKitTokenPersistenceRequested == false)
        #expect(result.diagnostics.pushKitTokenRegistrationFailure == nil)
        #expect(result.diagnostics.apnsRegistrationRequested == false)
        #expect(result.diagnostics.mediaCredentialsRequested == false)
        #expect(result.diagnostics.mediaConnectRequested == false)
        #expect(result.diagnostics.matrixEventEmitRequested == false)
        #expect(transport.requests == [.init(tokenPresent: true, environmentClass: "development")])
        #expect(description.contains("realNetworkRuntime: false"))
        #expect(!description.contains("sensitive-incoming-credential-b"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func pushKitTokenRegistrationClientRejectsEmptyTokenWithoutUpload() {
        let transport = DirectCallPushKitTokenRegistrationTransportSpy(result: .success)
        let client = DirectCallPushKitTokenRegistrationClient(transport: transport)

        let result = client.register(token: Data())

        #expect(result.uploadResult == .notRequested)
        #expect(result.diagnostics.pushKitTokenPresent == false)
        #expect(result.diagnostics.pushKitTokenUploadRequested == false)
        #expect(result.diagnostics.pushKitTokenPersistenceRequested == false)
        #expect(result.diagnostics.pushKitTokenRegistrationFailure == .missingToken)
        #expect(result.diagnostics.blockedReason == .missingToken)
        #expect(transport.requests.isEmpty)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: result).contains($0) })
    }

    @Test
    func pushKitTokenRegistrationClientTransportFailureIsRedacted() {
        let transport = DirectCallPushKitTokenRegistrationTransportSpy(result: .failure)
        let client = DirectCallPushKitTokenRegistrationClient(transport: transport)

        let result = client.register(token: Data("sensitive-incoming-credential-b".utf8))

        let description = String(describing: result) + " " + String(describing: transport.requests)
        #expect(result.uploadResult == .failedRedacted)
        #expect(result.diagnostics.pushKitTokenPresent == true)
        #expect(result.diagnostics.pushKitTokenUploadRequested == true)
        #expect(result.diagnostics.pushKitTokenPersistenceRequested == false)
        #expect(result.diagnostics.pushKitTokenRegistrationFailure == .transportFailedRedacted)
        #expect(result.diagnostics.blockedReason == .transportFailedRedacted)
        #expect(transport.requests.count == 1)
        #expect(!description.contains("sensitive-incoming-credential-b"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func pushKitTokenRegistrationClientDefaultDoesNotUploadOrWireRuntime() throws {
        let client = DirectCallPushKitTokenRegistrationClient()
        let result = client.register(token: Data("sensitive-incoming-credential-b".utf8))
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let appSessionSource = try Self.sourceFile("ElementX/Sources/Services/Session/UserSession.swift")

        let description = String(describing: client) + " " + String(describing: result)
        #expect(result.uploadResult == .notRequested)
        #expect(result.diagnostics.pushKitTokenPresent == true)
        #expect(result.diagnostics.pushKitTokenUploadRequested == false)
        #expect(result.diagnostics.pushKitTokenPersistenceRequested == false)
        #expect(result.diagnostics.pushKitTokenRegistrationFailure == .transportUnavailable)
        #expect(description.contains("startupWiring: false"))
        #expect(description.contains("pushKitCallbackWiring: false"))
        #expect(description.contains("apnsRegistrationRuntime: false"))
        #expect(description.contains("mediaRuntime: false"))
        #expect(description.contains("matrixEventRuntime: false"))
        #expect(!adapterSource.contains("DirectCallPushKitTokenRegistrationClient"))
        #expect(!appSessionSource.contains("DirectCallPushKitTokenRegistrationClient"))
        #expect(!appSessionSource.contains("registerForRemoteNotifications"))
        #expect(!description.contains("sensitive-incoming-credential-b"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
    }

    @Test
    func debugPushKitTokenUploadSmokeIsManualRedactedAndNotStartupWired() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let developerOptionsSource = try Self.sourceFile("ElementX/Sources/AppHooks/Hooks/DeveloperOptionsScreenHook.swift")
        let appCoordinatorSource = try Self.sourceFile("ElementX/Sources/Application/AppCoordinator.swift")
        let appSessionSource = try Self.sourceFile("ElementX/Sources/Services/Session/UserSession.swift")

        #expect(adapterSource.contains("#if DEBUG && canImport(PushKit) && os(iOS)"))
        #expect(adapterSource.contains("startRegistrationUploadSmokeWithCurrentSessionURLString"))
        #expect(adapterSource.contains("handleUploadSmokeURL"))
        #expect(adapterSource.contains("salemx-pushkit-token-upload-smoke-proof.txt"))
        #expect(adapterSource.contains("matrixAccessTokenForPushKitUploadSmoke"))
        #expect(adapterSource.contains("\"B\" + \"earer \" + accessToken"))
        #expect(adapterSource.contains("token.map { String(format: \"%02x\", $0) }.joined()"))
        #expect(adapterSource.contains("pushkit_token_redacted=true"))
        #expect(adapterSource.contains("pushkit_token_upload_result=\\(uploadResult)"))
        #expect(adapterSource.contains("pushkit_token_server_store_result=\\(serverStoreResult)"))
        #expect(adapterSource.contains("pushkit_token_retrieval_internal_check=\\(retrievalInternalCheck)"))
        #expect(adapterSource.contains("pushkit_token_api_exposes_raw_token=\\(tokenAPIExposesRawToken)"))
        #expect(adapterSource.contains("real_pushkit_background_callback_wired=false"))
        #expect(adapterSource.contains("voip_push_send_requested=false"))
        #expect(adapterSource.contains("apns_provider_requested=false"))
        #expect(developerOptionsSource.contains("Start PushKit token upload smoke"))
        #expect(developerOptionsSource.contains("pushKitTokenUploadSmokeProof"))
        #expect(appCoordinatorSource.contains("#if DEBUG && canImport(PushKit) && os(iOS)"))
        #expect(appCoordinatorSource.contains("handleUploadSmokeURL(url)"))
        #expect(!appSessionSource.contains("startRegistrationUploadSmokeWithCurrentSessionURLString"))
        #expect(!appSessionSource.contains("DirectCallPushKitTokenRegistrationClient"))
        #expect(!appSessionSource.contains("registerForRemoteNotifications"))
        #expect(!adapterSource.contains("print("))
    }

    @Test
    func diagnosticsAndOutcomesStayRedacted() {
        let diagnostics = NativeIncomingCallRedactedDiagnostics(lifecycleState: .failed,
                                                                failClosedReason: .serverIssuedMediaCredentialRejected,
                                                                reportAttempted: true,
                                                                reportSucceeded: false,
                                                                mediaCredentialRequested: true,
                                                                mediaConnectAttempted: false)
        let outcome = NativeIncomingCallLifecycleOutcome.failClosed(.serverIssuedMediaCredentialRejected)
        let serviceDescription = String(describing: makeNativeIncomingLifecycleDependencies().service)
        let description = String(describing: diagnostics) + " " + String(describing: outcome) + " " + serviceDescription

        #expect(description.contains("serverIssuedMediaCredentialRejected"))
        #expect(description.contains("realRuntime: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
        #expect(!description.contains("displayCall"))
        #expect(!description.contains("presentCallScreen"))
    }

    @Test
    func syntheticCallKitDisplayMetadataAcceptsOnlySafeLabels() {
        #expect(NativeIncomingCallKitDisplayMetadata("Pilot Participant") != nil)
        #expect(NativeIncomingCallKitDisplayMetadata("unsafe@label") == nil)
        #expect(NativeIncomingCallKitDisplayMetadata("unsafe!label") == nil)
        #expect(NativeIncomingCallKitDisplayMetadata("https://invalid.example") == nil)
        #expect(NativeIncomingCallKitDisplayMetadata("") == nil)
    }

    @Test
    func disabledForegroundCallSignalingClientIsNoopAndRedacted() {
        let client = DisabledForegroundCallSignalingClient()

        client.startForegroundCallSignaling { _ in
            Issue.record("Disabled client should not emit foreground invite signals.")
        }
        client.stopForegroundCallSignaling()

        #expect(!client.isStarted)
        #expect(String(describing: client).contains("realTransport: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: client).contains($0) })
    }

    @Test
    func disabledForegroundCallSignalingTransportEmitsNoInvite() {
        let transport = DisabledForegroundCallSignalingTransport()

        transport.start { _ in
            Issue.record("Disabled transport should not emit foreground invite signals.")
        }
        transport.stop()

        #expect(!transport.diagnostics.isStarted)
        #expect(transport.diagnostics.deliveredInviteCount == 0)
        #expect(transport.diagnostics.latestResult == .stopped)
        #expect(String(describing: transport).contains("realTransport: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: transport).contains($0) })
    }

    @Test
    func inMemoryForegroundCallSignalingTransportDeliversInviteImmediately() {
        let now = Date(timeIntervalSince1970: 1000)
        let transport = InMemoryForegroundCallSignalingTransport()
        let signal = makeForegroundCallInviteSignal(now: now)
        var events = [ForegroundCallSignalingTransportEvent]()

        transport.start { event in
            events.append(event)
        }
        let delivered = transport.emitInvite(signal)

        #expect(delivered)
        #expect(events == [.invite(signal)])
        #expect(transport.diagnostics.isStarted)
        #expect(transport.diagnostics.deliveredInviteCount == 1)
        #expect(transport.diagnostics.latestEventKind == .invite)
        #expect(transport.diagnostics.latestResult == .delivered)
        #expect(String(describing: transport).contains("realTransport: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: transport).contains($0) })
    }

    @Test
    func stoppedInMemoryForegroundCallSignalingTransportIgnoresInvite() {
        let now = Date(timeIntervalSince1970: 1000)
        let transport = InMemoryForegroundCallSignalingTransport()
        let signal = makeForegroundCallInviteSignal(now: now)

        let delivered = transport.emitInvite(signal)

        #expect(!delivered)
        #expect(transport.diagnostics.deliveredInviteCount == 0)
        #expect(transport.diagnostics.latestEventKind == .invite)
        #expect(transport.diagnostics.latestResult == .ignored)
    }

    @Test
    func disabledForegroundCallSignalingSSETransportDoesNotStartStream() {
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: false, stream: stream)

        transport.start { _ in
            Issue.record("Disabled SSE transport should not emit foreground invite signals.")
        }

        #expect(stream.startCount == 0)
        #expect(!transport.diagnostics.isStarted)
        #expect(transport.diagnostics.deliveredInviteCount == 0)
        #expect(transport.diagnostics.latestResult == .ignored)
        #expect(String(describing: transport).contains("configured: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: transport).contains($0) })
    }

    @Test
    func foregroundCallSignalingSSETransportSurfacesReadyAndIgnoresMalformedEvents() {
        let now = Date(timeIntervalSince1970: 1000)
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        var events = [ForegroundCallSignalingTransportEvent]()

        transport.start { event in
            events.append(event)
        }
        stream.emit("event: foreground.ready\ndata: {\"ready\":true}\n\n")

        #expect(events == [.ready])
        #expect(transport.diagnostics.isStarted)
        #expect(transport.diagnostics.deliveredInviteCount == 0)
        #expect(transport.diagnostics.latestEventKind == .ready)
        #expect(transport.diagnostics.latestResult == .connected)

        stream.emit("event: foreground.call.invite\ndata: {\"type\":\"foreground.call.invite\"}\n\n")

        #expect(events == [.ready])
        #expect(transport.diagnostics.isStarted)
        #expect(transport.diagnostics.deliveredInviteCount == 0)
        #expect(transport.diagnostics.latestEventKind == .ready)
        #expect(transport.diagnostics.latestResult == .ignored)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: transport).contains($0) })
    }

    @Test
    func foregroundCallSignalingSSETransportReportsRedactedStreamFailureReason() {
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream)
        var events = [ForegroundCallSignalingTransportEvent]()

        transport.start { event in
            events.append(event)
        }
        stream.complete(.failed(.httpStatus(.unauthorized)))

        #expect(events == [.stopped])
        #expect(transport.diagnostics.latestFailureReason == .httpStatus(.unauthorized))
        #expect(String(describing: transport).contains("latestFailureReason: http_unauthorized"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: transport).contains($0) })
    }

    @Test
    func foregroundCallSignalingSSETransportDeliversValidInviteToPipeline() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)

        pipeline.start()
        stream.emit(makeForegroundCallSSEInvite(handle: "safe-sse-call", now: now))

        guard case .reported(let identity) = pipeline.latestOutcome else {
            Issue.record("Expected SSE invite to request incoming call reporting.")
            return
        }
        #expect(dependencies.reportingAdapter.reportedIdentities == [identity])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
        #expect(transport.diagnostics.deliveredInviteCount == 1)
        #expect(transport.diagnostics.latestEventKind == .invite)
        #expect(transport.diagnostics.realTransport)
    }

    @Test
    func foregroundCallSignalingSSETransportAllowsSmallServerClockSkew() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)

        pipeline.start()
        stream.emit(makeForegroundCallSSEInvite(handle: "safe-sse-skew",
                                                now: now,
                                                createdAt: now.addingTimeInterval(3)))

        guard case .reported(let identity) = pipeline.latestOutcome else {
            Issue.record("Expected small server clock skew to remain eligible for incoming reporting.")
            return
        }
        #expect(dependencies.reportingAdapter.reportedIdentities == [identity])
        #expect(transport.diagnostics.deliveredInviteCount == 1)
    }

    @Test
    func foregroundCallSignalingSSETransportRejectsLargeServerClockSkew() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)

        pipeline.start()
        stream.emit(makeForegroundCallSSEInvite(handle: "safe-sse-large-skew",
                                                now: now,
                                                createdAt: now.addingTimeInterval(10)))

        #expect(pipeline.latestOutcome == nil)
        #expect(dependencies.reportingAdapter.reportedIdentities.isEmpty)
        #expect(transport.diagnostics.deliveredInviteCount == 0)
    }

    @Test
    func foregroundCallSignalingSSETransportRejectsExpiredInviteTimestamp() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)

        pipeline.start()
        stream.emit(makeForegroundCallSSEInvite(handle: "safe-sse-expired",
                                                now: now,
                                                createdAt: now.addingTimeInterval(-60),
                                                expiresAt: now.addingTimeInterval(-1)))

        #expect(pipeline.latestOutcome == nil)
        #expect(dependencies.reportingAdapter.reportedIdentities.isEmpty)
        #expect(transport.diagnostics.deliveredInviteCount == 0)
    }

    @Test
    func foregroundCallSignalingSSETransportSuppressesStaleUnsupportedAndDuplicateInvites() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)

        pipeline.start()
        stream.emit(makeForegroundCallSSEInvite(handle: "safe-sse-repeat", now: now))
        stream.emit(makeForegroundCallSSEInvite(handle: "safe-sse-repeat", now: now))
        #expect(pipeline.latestOutcome == .suppressed(.duplicate))

        stream.emit(makeForegroundCallSSEInvite(handle: "safe-sse-stale",
                                                now: now,
                                                expiresAt: now.addingTimeInterval(-1)))
        stream.emit(makeForegroundCallSSEInvite(handle: "safe-sse-video",
                                                kind: "video",
                                                now: now))

        #expect(pipeline.latestOutcome == .suppressed(.duplicate))
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(dependencies.diagnosticsRecorder.diagnostics.suffix(2).map(\.mediaCredentialRequested) == [false, false])
        #expect(dependencies.diagnosticsRecorder.diagnostics.suffix(2).map(\.mediaConnectAttempted) == [false, false])
    }

    @Test
    func foregroundCallSignalingSSETransportDoesNotRequestCredentialConnectMediaOrEmitMatrixEvent() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)

        pipeline.start()
        stream.emit(makeForegroundCallSSEInvite(now: now))

        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(dependencies.reportingAdapter.endedReasons.isEmpty)
        #expect(dependencies.timeoutScheduler.scheduledIdentities.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
        #expect(String(describing: pipeline).contains("mediaConnectRuntime: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: pipeline).contains($0) })
    }

    @Test
    func debugForegroundSSERuntimeOwnerDisabledDoesNotStartTransport() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let transport = InMemoryForegroundCallSignalingTransport()
        let owner = DebugForegroundCallSignalingSSERuntimeOwner(transport: transport,
                                                                inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies, now: now))

        owner.appDidEnterForeground(authenticatedSessionAvailable: true)
        transport.emitInvite(makeForegroundCallInviteSignal(now: now))

        #expect(owner.diagnostics.sseConfigured == false)
        #expect(owner.diagnostics.sseStarted == false)
        #expect(owner.diagnostics.sseConnected == false)
        #expect(owner.diagnostics.inviteReceived == false)
        #expect(dependencies.reportingAdapter.reportedIdentities.isEmpty)
        #expect(String(describing: owner).contains("debugOnly: true"))
        #expect(String(describing: owner).contains("hardcodedEndpoint: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: owner).contains($0) })
    }

    @Test
    func debugForegroundSSERuntimeOwnerRequiresAuthenticatedSessionBeforeStart() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let owner = DebugForegroundCallSignalingSSERuntimeOwner(isEnabled: true,
                                                                transport: transport,
                                                                inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies, now: now))

        owner.appDidEnterForeground(authenticatedSessionAvailable: false)

        #expect(stream.startCount == 0)
        #expect(owner.diagnostics.sseConfigured == false)
        #expect(owner.diagnostics.sseStarted == false)
        #expect(owner.diagnostics.sseConnected == false)
        #expect(dependencies.reportingAdapter.reportedIdentities.isEmpty)
    }

    @Test
    func debugForegroundSSERuntimeOwnerUsesInjectedTransportStartState() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let transport = DisabledForegroundCallSignalingTransport()
        let owner = DebugForegroundCallSignalingSSERuntimeOwner(isEnabled: true,
                                                                transport: transport,
                                                                inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies, now: now))

        owner.appDidEnterForeground(authenticatedSessionAvailable: true)

        #expect(owner.diagnostics.sseConfigured)
        #expect(owner.diagnostics.sseStarted == false)
        #expect(owner.diagnostics.sseConnected == false)
        #expect(dependencies.reportingAdapter.reportedIdentities.isEmpty)
    }

    @Test
    func debugForegroundSSERuntimeOwnerStartsAndStopsConfiguredTransport() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let owner = DebugForegroundCallSignalingSSERuntimeOwner(isEnabled: true,
                                                                transport: transport,
                                                                inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies, now: now))

        owner.appDidEnterForeground(authenticatedSessionAvailable: true)
        owner.appDidEnterBackground()

        #expect(stream.startCount == 1 && stream.stopCount == 1)
        #expect(owner.diagnostics.sseConfigured)
        #expect(owner.diagnostics.sseStarted == false)
        #expect(owner.diagnostics.sseConnected == false)
        #expect(owner.diagnostics.transportStopped)
    }

    @Test
    func debugForegroundSSESmokeDiagnosticsLoggerUsesRedactedPrefixAndFields() {
        let diagnostics = DebugForegroundCallSignalingSSERuntimeDiagnostics(sseConfigured: true,
                                                                            sseStarted: true,
                                                                            sseConnected: true,
                                                                            inviteReceived: true,
                                                                            inviteValid: true,
                                                                            incomingRequested: true,
                                                                            fallbackDeduped: true,
                                                                            transportStopped: true,
                                                                            streamFailure: .network)
        let lines = DebugForegroundCallSignalingSSESmokeDiagnosticsLogger().redactedLines(for: diagnostics)

        #expect(lines.count == 9)
        #expect(lines.allSatisfy { $0.hasPrefix("[SSE-SMOKE-DIAG]") })
        let expectedLines = ["sse_configured", "sse_started", "sse_connected", "invite_received", "invite_valid",
                             "incoming_requested", "fallback_deduped", "transport_stopped", "stream_failure=network"]
        #expect(expectedLines.allSatisfy { expectedLine in lines.contains { $0.contains(expectedLine) } })
        #expect(lines.allSatisfy { line in
            Self.forbiddenNativeIncomingFragments.allSatisfy { !line.contains($0) }
        })
    }

    @Test
    func debugForegroundSSERuntimeOwnerEmitsSmokeDiagnosticsWhenStartedInviteAndStopped() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let logger = DebugForegroundCallSignalingSSESmokeDiagnosticsLogger()
        var lines = [String]()
        let owner = DebugForegroundCallSignalingSSERuntimeOwner(isEnabled: true,
                                                                transport: transport,
                                                                inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies, now: now),
                                                                // swiftlint:disable:next trailing_closure
                                                                diagnosticsObserver: { diagnostics in
                                                                    lines.append(contentsOf: logger.redactedLines(for: diagnostics))
                                                                })

        owner.appDidEnterForeground(authenticatedSessionAvailable: true)
        stream.emit(makeForegroundCallSSEInvite(handle: "safe-runtime-smoke", now: now))
        owner.appDidEnterBackground()

        #expect(lines.contains("[SSE-SMOKE-DIAG] sse_configured=true"))
        #expect(lines.contains("[SSE-SMOKE-DIAG] sse_started=true"))
        #expect(lines.contains("[SSE-SMOKE-DIAG] sse_connected=true"))
        #expect(lines.contains("[SSE-SMOKE-DIAG] invite_received=true"))
        #expect(lines.contains("[SSE-SMOKE-DIAG] invite_valid=true"))
        #expect(lines.contains("[SSE-SMOKE-DIAG] incoming_requested=true"))
        #expect(lines.contains("[SSE-SMOKE-DIAG] transport_stopped=true"))
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
        #expect(lines.allSatisfy { line in
            Self.forbiddenNativeIncomingFragments.allSatisfy { !line.contains($0) }
        })
    }

    @Test
    func debugForegroundSSERuntimeOwnerForwardsValidInviteAndKeepsMediaBlocked() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true, stream: stream, now: fixedDirectCallTestNow(now))
        let owner = DebugForegroundCallSignalingSSERuntimeOwner(isEnabled: true,
                                                                transport: transport,
                                                                inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies, now: now))

        owner.appDidEnterForeground(authenticatedSessionAvailable: true)
        stream.emit(makeForegroundCallSSEInvite(handle: "safe-runtime-sse-call", now: now))

        guard case .reported(let identity) = owner.latestOutcome else {
            Issue.record("Expected DEBUG runtime owner to request foreground incoming reporting.")
            return
        }
        #expect(dependencies.reportingAdapter.reportedIdentities == [identity])
        #expect(owner.diagnostics.sseConfigured)
        #expect(owner.diagnostics.sseStarted)
        #expect(owner.diagnostics.sseConnected)
        #expect(owner.diagnostics.inviteReceived)
        #expect(owner.diagnostics.inviteValid)
        #expect(owner.diagnostics.incomingRequested)
        #expect(owner.diagnostics.fallbackDeduped == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
        #expect(dependencies.reportingAdapter.endedReasons.isEmpty)
        #expect(String(describing: owner).contains("mediaConnectRuntime: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: owner).contains($0) })
    }

    @Test
    func debugForegroundSSERuntimeOwnerSuppressesStaleAndDuplicateInvites() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let transport = InMemoryForegroundCallSignalingTransport()
        let owner = DebugForegroundCallSignalingSSERuntimeOwner(isEnabled: true,
                                                                transport: transport,
                                                                inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies, now: now))

        owner.appDidEnterForeground(authenticatedSessionAvailable: true)
        transport.emitInvite(makeForegroundCallInviteSignal(handle: "safe-runtime-stale",
                                                            now: now,
                                                            expiresAt: now.addingTimeInterval(-1)))
        #expect(owner.latestOutcome == .suppressed(.stale))
        #expect(owner.diagnostics.inviteReceived)
        #expect(owner.diagnostics.inviteValid == false)
        #expect(owner.diagnostics.incomingRequested == false)

        transport.emitInvite(makeForegroundCallInviteSignal(handle: "safe-runtime-terminal",
                                                            now: now,
                                                            state: .terminal))
        #expect(owner.latestOutcome == .suppressed(.stale))

        transport.emitInvite(makeForegroundCallInviteSignal(handle: "safe-runtime-duplicate", now: now))
        transport.emitInvite(makeForegroundCallInviteSignal(handle: "safe-runtime-duplicate", now: now))

        #expect(owner.latestOutcome == .suppressed(.duplicate))
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(dependencies.diagnosticsRecorder.diagnostics.suffix(4).map(\.mediaCredentialRequested) == [false, false, false, false])
        #expect(dependencies.diagnosticsRecorder.diagnostics.suffix(4).map(\.mediaConnectAttempted) == [false, false, false, false])
    }

    @Test
    func debugForegroundSSERuntimeOwnerDedupesTimelineFallbackAfterSSEInvite() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let signal = makeForegroundCallInviteSignal(handle: "safe-runtime-fallback", now: now)
        let transport = InMemoryForegroundCallSignalingTransport()
        let owner = DebugForegroundCallSignalingSSERuntimeOwner(isEnabled: true,
                                                                transport: transport,
                                                                inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies, now: now))

        owner.appDidEnterForeground(authenticatedSessionAvailable: true)
        transport.emitInvite(signal)
        let fallbackOutcome = owner.handleFallbackInvite(signal)

        #expect(fallbackOutcome == .suppressed(.duplicate))
        #expect(owner.diagnostics.fallbackDeduped)
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundSignalingTransportPipelineReportsValidInvite() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let transport = InMemoryForegroundCallSignalingTransport()
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)
        let signal = makeForegroundCallInviteSignal(now: now)

        pipeline.start()
        transport.emitInvite(signal)

        guard case .reported(let identity) = pipeline.latestOutcome else {
            Issue.record("Expected in-memory transport invite to request incoming call reporting.")
            return
        }
        #expect(dependencies.reportingAdapter.reportedIdentities == [identity])
        #expect(dependencies.stateStore.state(for: identity.handle) == .reported)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundSignalingTransportPipelineSuppressesUnsafeInvites() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let transport = InMemoryForegroundCallSignalingTransport()
        let handler = makeForegroundCallInviteHandler(dependencies: dependencies, now: now)
        let pipeline = ForegroundCallSignalingTransportPipeline(transport: transport,
                                                                inviteHandler: handler)
        let signal = makeForegroundCallInviteSignal(now: now)

        pipeline.start()
        transport.emitInvite(signal)
        transport.emitInvite(signal)
        #expect(pipeline.latestOutcome == .suppressed(.duplicate))

        transport.emitInvite(makeForegroundCallInviteSignal(handle: "safe-foreground-transport-stale",
                                                            now: now,
                                                            expiresAt: now.addingTimeInterval(-1)))
        #expect(pipeline.latestOutcome == .suppressed(.stale))

        transport.emitInvite(makeForegroundCallInviteSignal(handle: "safe-foreground-transport-terminal",
                                                            now: now,
                                                            state: .terminal))
        #expect(pipeline.latestOutcome == .suppressed(.stale))

        let malformed = handler.handle(rawHandle: "not safe",
                                       kind: .audio,
                                       state: .incoming,
                                       createdAt: now,
                                       expiresAt: now.addingTimeInterval(30),
                                       displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        #expect(malformed == .suppressed(.malformed))
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(dependencies.diagnosticsRecorder.diagnostics.suffix(4).map(\.mediaCredentialRequested) == [false, false, false, false])
        #expect(dependencies.diagnosticsRecorder.diagnostics.suffix(4).map(\.mediaConnectAttempted) == [false, false, false, false])
    }

    @Test
    func foregroundSignalingTransportInviteDoesNotRequestCredentialConnectMediaOrEmitMatrixEvent() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let transport = InMemoryForegroundCallSignalingTransport()
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)

        pipeline.start()
        transport.emitInvite(makeForegroundCallInviteSignal(now: now))

        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(dependencies.reportingAdapter.endedReasons.isEmpty)
        #expect(dependencies.timeoutScheduler.scheduledIdentities.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
        #expect(String(describing: pipeline).contains("mediaConnectRuntime: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: pipeline).contains($0) })
    }

    @Test
    func foregroundSignalingTransportAnswerStillRequiresAuthorityGate() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let transport = InMemoryForegroundCallSignalingTransport()
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)
        let actionRouter = DisabledNativeIncomingCallStateMachineActionRouter(stateStore: dependencies.stateStore,
                                                                              diagnosticsRecorder: dependencies.diagnosticsRecorder)
        let acceptanceGate = DisabledNativeIncomingForegroundAcceptanceGate(isEnabled: true,
                                                                            stateStore: dependencies.stateStore,
                                                                            diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                                            authorizer: nil)

        pipeline.start()
        transport.emitInvite(makeForegroundCallInviteSignal(now: now))
        guard case .reported(let identity) = pipeline.latestOutcome else {
            Issue.record("Expected transport invite to reach local incoming reporting.")
            return
        }

        actionRouter.requestAnswer(identity: identity)
        let acceptance = acceptanceGate.requestForegroundAcceptance(identity: identity)

        #expect(acceptance == .failClosed(.foregroundCredentialAuthorityUnavailable))
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundCallInviteReportsIncomingCallWithoutCredentialOrMedia() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let handler = makeForegroundCallInviteHandler(dependencies: dependencies, now: now)
        let signal = makeForegroundCallInviteSignal(now: now)

        let outcome = handler.handle(signal)

        guard case .reported(let identity) = outcome else {
            Issue.record("Expected foreground signaling invite to request incoming call reporting.")
            return
        }
        #expect(dependencies.reportingAdapter.reportedIdentities == [identity])
        #expect(dependencies.stateStore.state(for: identity.handle) == .reported)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.reportAttempted == true)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
        #expect(String(describing: signal).contains("<redacted>"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: handler).contains($0) })
    }

    @Test
    func foregroundCallInviteSuppressesDuplicateStaleTerminalAndMalformedInvites() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let handler = makeForegroundCallInviteHandler(dependencies: dependencies, now: now)
        let signal = makeForegroundCallInviteSignal(now: now)

        _ = handler.handle(signal)
        let duplicate = handler.handle(signal)
        let stale = handler.handle(makeForegroundCallInviteSignal(handle: "safe-foreground-call-stale",
                                                                  now: now,
                                                                  expiresAt: now.addingTimeInterval(-1)))
        let terminal = handler.handle(makeForegroundCallInviteSignal(handle: "safe-foreground-call-terminal",
                                                                     now: now,
                                                                     state: .terminal))
        let malformed = handler.handle(rawHandle: "not safe",
                                       kind: .audio,
                                       state: .incoming,
                                       createdAt: now,
                                       expiresAt: now.addingTimeInterval(30),
                                       displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        #expect(duplicate == .suppressed(.duplicate))
        #expect(stale == .suppressed(.stale))
        #expect(terminal == .suppressed(.stale))
        #expect(malformed == .suppressed(.malformed))
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(dependencies.diagnosticsRecorder.diagnostics.suffix(4).map(\.mediaCredentialRequested) == [false, false, false, false])
        #expect(dependencies.diagnosticsRecorder.diagnostics.suffix(4).map(\.mediaConnectAttempted) == [false, false, false, false])
    }

    @Test
    func foregroundCallInviteValidationGuardsRemainFailClosed() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let handler = makeForegroundCallInviteHandler(dependencies: dependencies, now: now)

        let video = handler.handle(makeForegroundCallInviteSignal(handle: "safe-foreground-call-video",
                                                                  kind: .video,
                                                                  now: now))
        let active = handler.handle(makeForegroundCallInviteSignal(handle: "safe-foreground-call-active",
                                                                   now: now),
                                    context: .init(hasExistingActiveNativeSession: true))
        let reportBlockedDependencies = makeNativeIncomingLifecycleDependencies(reportResult: false)
        let reportBlockedHandler = makeForegroundCallInviteHandler(dependencies: reportBlockedDependencies, now: now)
        let reportBlocked = reportBlockedHandler.handle(makeForegroundCallInviteSignal(handle: "safe-foreground-call-report-blocked",
                                                                                       now: now))

        #expect(video == .suppressed(.unverifiable))
        #expect(active == .suppressed(.existingActiveNativeSession))
        #expect(reportBlocked == .suppressed(.callReportingUnavailable))
        #expect(dependencies.reportingAdapter.reportedIdentities.isEmpty)
        #expect(reportBlockedDependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(reportBlockedDependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundCallInviteAnswerStillRequiresAcceptanceGate() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let handler = makeForegroundCallInviteHandler(dependencies: dependencies, now: now)
        let actionRouter = DisabledNativeIncomingCallStateMachineActionRouter(stateStore: dependencies.stateStore,
                                                                              diagnosticsRecorder: dependencies.diagnosticsRecorder)
        let acceptanceGate = DisabledNativeIncomingForegroundAcceptanceGate(isEnabled: true,
                                                                            stateStore: dependencies.stateStore,
                                                                            diagnosticsRecorder: dependencies.diagnosticsRecorder,
                                                                            authorizer: nil)

        let outcome = handler.handle(makeForegroundCallInviteSignal(now: now))
        guard case .reported(let identity) = outcome else {
            Issue.record("Expected foreground signaling invite to reach local incoming reporting.")
            return
        }

        actionRouter.requestAnswer(identity: identity)
        let acceptance = acceptanceGate.requestForegroundAcceptance(identity: identity)

        #expect(dependencies.stateStore.state(for: identity.handle) == .failed)
        #expect(actionRouter.answerRequestCount == 1)
        #expect(acceptance == .failClosed(.foregroundCredentialAuthorityUnavailable))
        #expect(dependencies.diagnosticsRecorder.diagnostics.contains { diagnostics in
            diagnostics.lifecycleState == .answerRequested &&
                diagnostics.mediaCredentialRequested == false &&
                diagnostics.mediaConnectAttempted == false
        })
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func foregroundCallInviteTimelineFallbackDoesNotDuplicateIncomingUI() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let handler = makeForegroundCallInviteHandler(dependencies: dependencies, now: now)
        let signal = makeForegroundCallInviteSignal(now: now)

        _ = handler.handle(signal)
        dependencies.stateStore.clear(signal.handle)
        let fallback = handler.handle(signal)

        #expect(fallback == .suppressed(.duplicate))
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last == .failClosed(.duplicate))
    }

    @Test
    func disabledSyntheticCallKitProofFailsClosedByDefault() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let coordinator = DisabledNativeIncomingSyntheticCallKitProofCoordinator(stateStore: dependencies.stateStore,
                                                                                 reportingAdapter: dependencies.reportingAdapter,
                                                                                 actionHandler: actionHandler,
                                                                                 diagnosticsRecorder: dependencies.diagnosticsRecorder)
        guard let identity = reportedIncomingIdentity(dependencies: dependencies) else {
            return
        }

        let result = coordinator.reportSyntheticIncomingCall(identity: identity,
                                                             displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        #expect(result == .failed(.dependencyUnavailable))
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        #expect(actionHandler.answeredIdentities.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last == .failClosed(.dependencyUnavailable))
    }

    @Test
    func syntheticCallKitProofReportsOnlySafeLocalIdentity() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let coordinator = DisabledNativeIncomingSyntheticCallKitProofCoordinator(isEnabled: true,
                                                                                 stateStore: dependencies.stateStore,
                                                                                 reportingAdapter: dependencies.reportingAdapter,
                                                                                 actionHandler: actionHandler,
                                                                                 diagnosticsRecorder: dependencies.diagnosticsRecorder)
        guard let identity = reportedIncomingIdentity(dependencies: dependencies) else {
            return
        }

        let result = coordinator.reportSyntheticIncomingCall(identity: identity,
                                                             displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        #expect(result == .reported)
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 2)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.lifecycleState == .reported)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: coordinator).contains($0) })
    }

    @Test
    func syntheticAnswerRecordsDisabledCallbackOnly() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let coordinator = makeSyntheticCallKitProofCoordinator(dependencies: dependencies,
                                                               actionHandler: actionHandler)
        guard let identity = reportedIncomingIdentity(dependencies: dependencies) else {
            return
        }
        _ = coordinator.reportSyntheticIncomingCall(identity: identity,
                                                    displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        let result = coordinator.answerSyntheticCall(handle: "safe-local-call")

        #expect(result == .answered)
        #expect(actionHandler.answeredIdentities == [identity])
        #expect(dependencies.stateStore.state(for: identity.handle) == .answered)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func syntheticAnswerRoutesToIncomingStateMachineSurface() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionRouter = DisabledNativeIncomingCallStateMachineActionRouter(stateStore: dependencies.stateStore,
                                                                              diagnosticsRecorder: dependencies.diagnosticsRecorder)
        let actionHandler = NativeIncomingCallStateMachineSyntheticActionHandler(actionRouter: actionRouter)
        let coordinator = makeSyntheticCallKitProofCoordinator(dependencies: dependencies,
                                                               actionHandler: actionHandler)
        guard let identity = reportedIncomingIdentity(dependencies: dependencies) else {
            return
        }
        _ = coordinator.reportSyntheticIncomingCall(identity: identity,
                                                    displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        let result = coordinator.answerSyntheticCall(handle: "safe-local-call")

        #expect(result == .answered)
        #expect(dependencies.stateStore.state(for: identity.handle) == .answerRequested)
        #expect(actionRouter.answerRequestCount == 1)
        #expect(actionRouter.endCount == 0)
        #expect(actionRouter.muteCount == 0)
        #expect(dependencies.diagnosticsRecorder.diagnostics.contains { diagnostics in
            diagnostics.lifecycleState == .answerRequested &&
                diagnostics.mediaCredentialRequested == false &&
                diagnostics.mediaConnectAttempted == false
        })
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: actionHandler).contains($0) })
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !String(describing: actionRouter).contains($0) })
    }

    @Test
    func syntheticEndRoutesToIncomingStateMachineAndClearsLocalState() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionRouter = DisabledNativeIncomingCallStateMachineActionRouter(stateStore: dependencies.stateStore,
                                                                              diagnosticsRecorder: dependencies.diagnosticsRecorder)
        let actionHandler = NativeIncomingCallStateMachineSyntheticActionHandler(actionRouter: actionRouter)
        let coordinator = makeSyntheticCallKitProofCoordinator(dependencies: dependencies,
                                                               actionHandler: actionHandler)
        guard let identity = reportedIncomingIdentity(dependencies: dependencies) else {
            return
        }
        _ = coordinator.reportSyntheticIncomingCall(identity: identity,
                                                    displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        let result = coordinator.endSyntheticCall(handle: "safe-local-call")
        let secondEnd = coordinator.endSyntheticCall(handle: "safe-local-call")

        #expect(result == .ended)
        #expect(secondEnd == .failed(.unverifiable))
        #expect(actionRouter.endCount == 1)
        #expect(dependencies.stateStore.state(for: identity.handle) == nil)
        #expect(dependencies.diagnosticsRecorder.diagnostics.contains { diagnostics in
            diagnostics.lifecycleState == .ended &&
                diagnostics.mediaCredentialRequested == false &&
                diagnostics.mediaConnectAttempted == false
        })
    }

    @Test
    func syntheticMuteRoutesToIncomingStateMachineAsLocalDiagnosticOnly() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionRouter = DisabledNativeIncomingCallStateMachineActionRouter(stateStore: dependencies.stateStore,
                                                                              diagnosticsRecorder: dependencies.diagnosticsRecorder)
        let actionHandler = NativeIncomingCallStateMachineSyntheticActionHandler(actionRouter: actionRouter)
        let coordinator = makeSyntheticCallKitProofCoordinator(dependencies: dependencies,
                                                               actionHandler: actionHandler)
        guard let identity = reportedIncomingIdentity(dependencies: dependencies) else {
            return
        }
        _ = coordinator.reportSyntheticIncomingCall(identity: identity,
                                                    displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        let result = coordinator.setSyntheticCallMuted(true, handle: "safe-local-call")

        #expect(result == .muted(true))
        #expect(actionRouter.muteCount == 1)
        #expect(actionRouter.latestMuteValue == true)
        #expect(dependencies.stateStore.state(for: identity.handle) == .reported)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func syntheticUnknownHandleActionFailsClosed() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let coordinator = makeSyntheticCallKitProofCoordinator(dependencies: dependencies,
                                                               actionHandler: actionHandler)

        let result = coordinator.answerSyntheticCall(handle: "unknown-local-call")

        #expect(result == .failed(.unverifiable))
        #expect(actionHandler.answeredIdentities.isEmpty)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last == .failClosed(.unverifiable))
    }

    @Test
    func syntheticEndClearsLocalState() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let coordinator = makeSyntheticCallKitProofCoordinator(dependencies: dependencies,
                                                               actionHandler: actionHandler)
        guard let identity = reportedIncomingIdentity(dependencies: dependencies) else {
            return
        }
        _ = coordinator.reportSyntheticIncomingCall(identity: identity,
                                                    displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        let result = coordinator.endSyntheticCall(handle: "safe-local-call")

        #expect(result == .ended)
        #expect(actionHandler.endedIdentities == [identity])
        #expect(dependencies.reportingAdapter.endedReasons == [.unknown])
        #expect(dependencies.stateStore.state(for: identity.handle) == nil)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func syntheticMuteIsDiagnosticOnly() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let coordinator = makeSyntheticCallKitProofCoordinator(dependencies: dependencies,
                                                               actionHandler: actionHandler)
        guard let identity = reportedIncomingIdentity(dependencies: dependencies) else {
            return
        }
        _ = coordinator.reportSyntheticIncomingCall(identity: identity,
                                                    displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))

        let result = coordinator.setSyntheticCallMuted(true, handle: "safe-local-call")

        #expect(result == .muted(true))
        #expect(actionHandler.muteActions == [true])
        #expect(actionHandler.mutedIdentities == [identity])
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaCredentialRequested == false)
        #expect(dependencies.diagnosticsRecorder.diagnostics.last?.mediaConnectAttempted == false)
    }

    @Test
    func syntheticProofDiagnosticsStayRedacted() {
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let actionHandler = NativeIncomingSyntheticCallKitActionHandlerSpy()
        let coordinator = makeSyntheticCallKitProofCoordinator(dependencies: dependencies,
                                                               actionHandler: actionHandler)
        guard let identity = reportedIncomingIdentity(dependencies: dependencies) else {
            return
        }
        _ = coordinator.reportSyntheticIncomingCall(identity: identity,
                                                    displayMetadata: NativeIncomingCallKitDisplayMetadata("Pilot Participant"))
        _ = coordinator.answerSyntheticCall(handle: "safe-local-call")

        let description = String(describing: coordinator)
            + " " + dependencies.diagnosticsRecorder.diagnostics.map(String.init(describing:)).joined(separator: " ")
            + " " + actionHandler.description

        #expect(description.contains("realCallKitRuntime: false"))
        #expect(Self.forbiddenNativeIncomingFragments.allSatisfy { !description.contains($0) })
        #expect(!description.contains("displayCall"))
        #expect(!description.contains("presentCallScreen"))
    }

    private static let forbiddenNativeIncomingFragments = [
        "!unsafe-room",
        "@unsafe-user",
        "DEVICE-SECRET",
        "redacted-fixture-a",
        "sensitive-incoming-credential-a",
        "sensitive-incoming-credential-b",
        "sample-media-credential",
        "redacted-fixture-b",
        "redacted-fixture-c",
        "displayCall",
        "presentCallScreen"
    ]

    private static let repositoryRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRootURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func reportedIncomingIdentity(dependencies: NativeIncomingLifecycleDependencies) -> NativeIncomingCallIdentity? {
        let outcome = dependencies.service.receiveIncomingCall(handle: "safe-local-call",
                                                               receivedAt: .now,
                                                               context: .valid)
        guard case .reported(let identity) = outcome else {
            Issue.record("Expected safe incoming call identity to be reported.")
            return nil
        }
        return identity
    }

    private func makeNativeIncomingLifecycleDependencies(isEnabled: Bool = true,
                                                         reportResult: Bool = true) -> NativeIncomingLifecycleDependencies {
        let stateStore = NativeIncomingCallStateStoreSpy()
        let reportingAdapter = NativeIncomingCallReportingAdapterSpy(reportResult: reportResult)
        let timeoutScheduler = NativeIncomingCallTimeoutSchedulerSpy()
        let diagnosticsRecorder = NativeIncomingCallDiagnosticsRecorderSpy()
        let service = DisabledNativeIncomingCallLifecycleService(isEnabled: isEnabled,
                                                                 stateStore: stateStore,
                                                                 reportingAdapter: reportingAdapter,
                                                                 timeoutScheduler: timeoutScheduler,
                                                                 diagnosticsRecorder: diagnosticsRecorder)
        return .init(service: service,
                     stateStore: stateStore,
                     reportingAdapter: reportingAdapter,
                     timeoutScheduler: timeoutScheduler,
                     diagnosticsRecorder: diagnosticsRecorder)
    }

    private func makeSyntheticCallKitProofCoordinator(dependencies: NativeIncomingLifecycleDependencies,
                                                      actionHandler: NativeIncomingSyntheticCallKitActionHandling) -> DisabledNativeIncomingSyntheticCallKitProofCoordinator {
        DisabledNativeIncomingSyntheticCallKitProofCoordinator(isEnabled: true,
                                                               stateStore: dependencies.stateStore,
                                                               reportingAdapter: dependencies.reportingAdapter,
                                                               actionHandler: actionHandler,
                                                               diagnosticsRecorder: dependencies.diagnosticsRecorder)
    }

    private func makeForegroundCallInviteHandler(dependencies: NativeIncomingLifecycleDependencies,
                                                 now: Date) -> ForegroundCallInviteHandler {
        ForegroundCallInviteHandler(isEnabled: true,
                                    stateStore: dependencies.stateStore,
                                    reportingAdapter: dependencies.reportingAdapter,
                                    diagnosticsRecorder: dependencies.diagnosticsRecorder) {
            now
        }
    }

    private func makeForegroundCallSignalingTransportPipeline(dependencies: NativeIncomingLifecycleDependencies,
                                                              transport: ForegroundCallSignalingTransport,
                                                              now: Date) -> ForegroundCallSignalingTransportPipeline {
        ForegroundCallSignalingTransportPipeline(transport: transport,
                                                 inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies,
                                                                                                now: now))
    }

    private func makeForegroundCallInviteSignal(handle: String = "safe-foreground-call",
                                                kind: ForegroundCallInviteKind = .audio,
                                                now: Date,
                                                state: ForegroundCallInviteSignalState = .incoming,
                                                expiresAt: Date? = nil) -> ForegroundCallInviteSignal {
        guard let safeHandle = NativeIncomingCallHandle(handle),
              let displayMetadata = NativeIncomingCallKitDisplayMetadata("Pilot Participant") else {
            preconditionFailure("The local fixture should be valid.")
        }

        return .init(handle: safeHandle,
                     kind: kind,
                     state: state,
                     createdAt: now,
                     expiresAt: expiresAt ?? now.addingTimeInterval(30),
                     displayMetadata: displayMetadata)
    }

    private func makeForegroundCallSSEInvite(handle: String = "safe-sse-call",
                                             kind: String = "audio",
                                             now: Date,
                                             createdAt: Date? = nil,
                                             expiresAt: Date? = nil) -> String {
        let createdAtMs = Int((createdAt ?? now).timeIntervalSince1970 * 1000)
        let expiresAtMs = Int((expiresAt ?? now.addingTimeInterval(30)).timeIntervalSince1970 * 1000)
        let payload = """
        {"type":"foreground.call.invite","version":1,"call_handle":"\(handle)","call_kind":"\(kind)","created_at_ms":\(createdAtMs),"expires_at_ms":\(expiresAtMs),"display_label":"Pilot Participant"}
        """
        return "event: foreground.call.invite\n" +
            "data: \(payload)\n\n"
    }

    private func makeBackgroundInvitePayload(now: Date,
                                             createdAt: Date? = nil,
                                             expiresAt: Date? = nil) -> [String: Any] {
        [
            "type": "salemx.direct_call.background.invite",
            "version": 1,
            "call_handle": "safe-background-call",
            "call_kind": "audio",
            "created_at_ms": Int((createdAt ?? now).timeIntervalSince1970 * 1000),
            "expires_at_ms": Int((expiresAt ?? now.addingTimeInterval(30)).timeIntervalSince1970 * 1000),
            "display_label": "Pilot Participant"
        ]
    }
}

// swiftlint:enable type_body_length

@MainActor
final class ForegroundCallSignalingSSETraceTests {
    @Test
    func debugForegroundSSESmokeDiagnosticsLoggerUsesRedactedHelperFields() {
        let logger = DebugForegroundCallSignalingSSESmokeDiagnosticsLogger()
        let diagnostics = DebugForegroundCallSignalingSSESmokeHelperDiagnostics(helperInvoked: true,
                                                                                activeSessionAvailable: true,
                                                                                accessTokenAvailable: false,
                                                                                deviceIDAvailable: true,
                                                                                homeserverURLAvailable: true,
                                                                                foregroundSSEStartRequested: false,
                                                                                foregroundSSEStartBlockedReason: .missingAccessToken)
        let lines = logger.redactedLines(for: diagnostics)

        #expect(lines == [
            "[SSE-SMOKE-DIAG] helper_invoked=true",
            "[SSE-SMOKE-DIAG] active_session_available=true",
            "[SSE-SMOKE-DIAG] access_token_available=false",
            "[SSE-SMOKE-DIAG] device_id_available=true",
            "[SSE-SMOKE-DIAG] homeserver_url_available=true",
            "[SSE-SMOKE-DIAG] foreground_sse_start_requested=false",
            "[SSE-SMOKE-DIAG] foreground_sse_start_blocked_reason=missing_access_token"
        ])
        #expect(lines.allSatisfy { line in
            Self.forbiddenFragments.allSatisfy { !line.contains($0) }
        })
    }

    @Test
    func debugForegroundSSESmokeDiagnosticsLoggerUsesRedactedParserTraceFields() {
        let logger = DebugForegroundCallSignalingSSESmokeDiagnosticsLogger()
        let lines = [
            logger.redactedLine(for: .rawEventReceived),
            logger.redactedLine(for: .sseEventType(.invite)),
            logger.redactedLine(for: .inviteParseAttempted),
            logger.redactedLine(for: .inviteParseSucceeded(true)),
            logger.redactedLine(for: .pipelineDelivered(true))
        ]

        #expect(lines == [
            "[SSE-SMOKE-DIAG] raw_event_received=true",
            "[SSE-SMOKE-DIAG] sse_event_type=foreground.call.invite",
            "[SSE-SMOKE-DIAG] invite_parse_attempted=true",
            "[SSE-SMOKE-DIAG] invite_parse_succeeded=true",
            "[SSE-SMOKE-DIAG] pipeline_delivered=true"
        ])
        #expect(lines.allSatisfy { line in
            Self.forbiddenFragments.allSatisfy { !line.contains($0) }
        })
    }

    @Test
    func debugForegroundSSESmokeDiagnosticsLoggerUsesRedactedSenderFields() {
        let logger = DebugForegroundCallSignalingSSESmokeDiagnosticsLogger()
        let diagnostics = DebugForegroundCallSignalingRealInviteSenderDiagnostics(senderHelperInvoked: true,
                                                                                  senderActiveSessionAvailable: true,
                                                                                  senderAccessTokenAvailable: true,
                                                                                  senderInvitePostRequested: true,
                                                                                  senderInvitePostStatus: .httpSuccess,
                                                                                  senderInviteDeliveryReportReceived: true,
                                                                                  senderInviteBlockedReason: .none)
        let lines = logger.redactedLines(for: diagnostics)

        #expect(lines == [
            "[SSE-SMOKE-DIAG] sender_helper_invoked=true",
            "[SSE-SMOKE-DIAG] sender_active_session_available=true",
            "[SSE-SMOKE-DIAG] sender_access_token_available=true",
            "[SSE-SMOKE-DIAG] sender_invite_post_requested=true",
            "[SSE-SMOKE-DIAG] sender_invite_post_status=http_success",
            "[SSE-SMOKE-DIAG] sender_invite_delivery_report_received=true",
            "[SSE-SMOKE-DIAG] sender_token_refresh_needed=false",
            "[SSE-SMOKE-DIAG] sender_token_refresh_attempted=false",
            "[SSE-SMOKE-DIAG] sender_token_refresh_succeeded=false",
            "[SSE-SMOKE-DIAG] sender_invite_retry_requested=false",
            "[SSE-SMOKE-DIAG] sender_invite_retry_status=not_requested",
            "[SSE-SMOKE-DIAG] sender_invite_blocked_reason=none"
        ])
        #expect(lines.allSatisfy { line in
            Self.forbiddenFragments.allSatisfy { !line.contains($0) }
        })
    }

    @Test
    func debugForegroundSSESmokeDiagnosticsLoggerUsesRedactedSenderRetryFields() {
        let logger = DebugForegroundCallSignalingSSESmokeDiagnosticsLogger()
        let diagnostics = DebugForegroundCallSignalingRealInviteSenderDiagnostics(senderHelperInvoked: true,
                                                                                  senderActiveSessionAvailable: true,
                                                                                  senderAccessTokenAvailable: true,
                                                                                  senderInvitePostRequested: true,
                                                                                  senderInvitePostStatus: .httpUnauthorized,
                                                                                  senderInviteDeliveryReportReceived: false,
                                                                                  senderTokenRefreshNeeded: true,
                                                                                  senderTokenRefreshAttempted: true,
                                                                                  senderTokenRefreshSucceeded: true,
                                                                                  senderInviteRetryRequested: true,
                                                                                  senderInviteRetryStatus: .httpFailed,
                                                                                  senderInviteBlockedReason: .none)
        let lines = logger.redactedLines(for: diagnostics)

        #expect(lines == [
            "[SSE-SMOKE-DIAG] sender_helper_invoked=true",
            "[SSE-SMOKE-DIAG] sender_active_session_available=true",
            "[SSE-SMOKE-DIAG] sender_access_token_available=true",
            "[SSE-SMOKE-DIAG] sender_invite_post_requested=true",
            "[SSE-SMOKE-DIAG] sender_invite_post_status=http_unauthorized",
            "[SSE-SMOKE-DIAG] sender_invite_delivery_report_received=false",
            "[SSE-SMOKE-DIAG] sender_token_refresh_needed=true",
            "[SSE-SMOKE-DIAG] sender_token_refresh_attempted=true",
            "[SSE-SMOKE-DIAG] sender_token_refresh_succeeded=true",
            "[SSE-SMOKE-DIAG] sender_invite_retry_requested=true",
            "[SSE-SMOKE-DIAG] sender_invite_retry_status=http_failed",
            "[SSE-SMOKE-DIAG] sender_invite_blocked_reason=none"
        ])
        #expect(lines.allSatisfy { line in
            Self.forbiddenFragments.allSatisfy { !line.contains($0) }
        })
        #expect(lines.allSatisfy { !$0.contains("safe-foreground-real-invite") })
        #expect(lines.allSatisfy { !$0.contains("Pilot Participant") })
        #expect(lines.allSatisfy { !$0.contains("foreground-signaling/invite") })
    }

    @Test
    func debugForegroundSSESmokeBridgeExposesObjCRealInviteSelector() throws {
        let bridgeClass = try #require(NSClassFromString("SalemXForegroundSSESmokeDebugBridge") as? NSObject.Type)

        #expect(bridgeClass.responds(to: #selector(SalemXForegroundSSESmokeDebugBridge.sendRealInviteWithURLString(_:recipient:recipientDevice:))))
    }

    @Test
    func debugForegroundSSEReceiverSmokeBridgeExposesRedactedProofSelectors() throws {
        let bridgeClass = try #require(NSClassFromString("SalemXForegroundSSEReceiverSmokeDebugBridge") as? NSObject.Type)

        #expect(bridgeClass.responds(to: #selector(SalemXForegroundSSEReceiverSmokeDebugBridge.configureWithCurrentSessionStreamURLString(_:))))
        #expect(bridgeClass.responds(to: #selector(SalemXForegroundSSEReceiverSmokeDebugBridge.start)))
        #expect(bridgeClass.responds(to: #selector(SalemXForegroundSSEReceiverSmokeDebugBridge.stop)))
        #expect(bridgeClass.responds(to: #selector(SalemXForegroundSSEReceiverSmokeDebugBridge.redactedStateSummary)))
    }

    @Test
    func debugForegroundSSESmokeDeveloperOptionsHookProvidesInAppControls() {
        let appHooks = AppHooks()
        appHooks.setUp()

        #expect(appHooks.developerOptionsScreenHook.generalSectionRows() != nil)
        #expect(SalemXDeveloperOptionsScreenHook().generalSectionRows() != nil)
        #expect(SalemXForegroundSSESmokeControls.receiverStreamURLString.contains("foreground-signaling/stream"))
        #expect(!SalemXForegroundSSESmokeControls.receiverStreamURLString.contains("/dev/"))
        #expect(!SalemXForegroundSSESmokeControls.receiverStreamURLString.contains("8090"))
    }

    @Test
    func debugForegroundSSEReceiverSmokeStateSummaryIsRedacted() {
        SalemXForegroundSSESmokeDebug.clear()

        let summary = SalemXForegroundSSESmokeDebug.redactedStateSummary()
        #expect(summary.split(separator: "\n").map(String.init) == [
            "sse_connected=false",
            "stream_failure=none",
            "raw_event_received=false",
            "sse_event_type=none",
            "invite_parse_attempted=false",
            "invite_parse_succeeded=false",
            "pipeline_delivered=false",
            "invite_received=false",
            "invite_valid=false",
            "incoming_requested=false"
        ])
        #expect(Self.forbiddenFragments.allSatisfy { !summary.contains($0) })
        #expect(!summary.contains("Bearer"))
        #expect(!summary.contains("Authorization"))
        #expect(!summary.contains("foreground-signaling/stream"))
        #expect(!summary.contains("foreground-signaling/invite"))
    }

    @Test
    func debugForegroundSSEInAppSmokeControlsExposeOnlyRedactedSummary() {
        SalemXForegroundSSESmokeDebug.clear()

        let summary = SalemXForegroundSSESmokeControls.redactedReceiverStateSummary()
        #expect(Self.forbiddenFragments.allSatisfy { !summary.contains($0) })
        #expect(!summary.contains("Bearer"))
        #expect(!summary.contains("Authorization"))
        #expect(!summary.contains("foreground-signaling/stream"))
        #expect(!summary.contains("foreground-signaling/invite"))
    }

    @Test
    func debugForegroundSSESmokeSurfaceIsCompileGuarded() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let appHookSource = try Self.sourceFile("ElementX/Sources/AppHooks/Hooks/DeveloperOptionsScreenHook.swift")
        let userSessionSource = try Self.sourceFile("ElementX/Sources/Services/Session/UserSession.swift")
        let settingsModelsSource = try Self.sourceFile("ElementX/Sources/Screens/Settings/SettingsScreen/SettingsScreenModels.swift")
        let settingsCoordinatorSource = try Self.sourceFile("ElementX/Sources/Screens/Settings/SettingsScreen/SettingsScreenCoordinator.swift")
        let settingsViewModelSource = try Self.sourceFile("ElementX/Sources/Screens/Settings/SettingsScreen/SettingsScreenViewModel.swift")
        let settingsViewSource = try Self.sourceFile("ElementX/Sources/Screens/Settings/SettingsScreen/View/SettingsScreen.swift")
        let settingsFlowSource = try Self.sourceFile("ElementX/Sources/FlowCoordinators/SettingsFlowCoordinator.swift")

        #expect(Self.allOccurrences(of: "SalemXForegroundSSESmokeDebug", areInsideDebugBlockIn: adapterSource))
        #expect(Self.allOccurrences(of: "SalemXForegroundSSESmokeDebugBridge", areInsideDebugBlockIn: adapterSource))
        #expect(Self.allOccurrences(of: "SalemXForegroundSSEReceiverSmokeDebugBridge", areInsideDebugBlockIn: adapterSource))
        #expect(Self.allOccurrences(of: "SalemXForegroundSSESmokeDebug.registerActiveUserSession", areInsideDebugBlockIn: userSessionSource))

        #expect(Self.allOccurrences(of: "SalemXDeveloperOptionsScreenHook", areInsideDebugBlockIn: appHookSource))
        #expect(Self.allOccurrences(of: "SalemXForegroundSSESmokeControls", areInsideDebugBlockIn: appHookSource))
        #expect(Self.allOccurrences(of: "foregroundSSESmokeReceiverProof", areInsideDebugBlockIn: appHookSource))

        #expect(Self.allOccurrences(of: "case developerOptions", areInsideDebugBlockIn: settingsModelsSource))
        #expect(Self.allOccurrences(of: "case developerOptions", areInsideDebugBlockIn: settingsCoordinatorSource))
        #expect(Self.allOccurrences(of: "case .developerOptions", areInsideDebugBlockIn: settingsCoordinatorSource))
        #expect(Self.allOccurrences(of: "case .developerOptions", areInsideDebugBlockIn: settingsViewModelSource))
        #expect(Self.allOccurrences(of: "L10n.commonDeveloperOptions", areInsideDebugBlockIn: settingsViewSource))
        #expect(Self.allOccurrences(of: "context.send(viewAction: .developerOptions)", areInsideDebugBlockIn: settingsViewSource))
        #expect(Self.allOccurrences(of: "case .developerOptions", areInsideDebugBlockIn: settingsFlowSource))
        #expect(Self.allOccurrences(of: "presentDeveloperOptions", areInsideDebugBlockIn: settingsFlowSource))
    }

    @Test
    func foregroundCallSignalingSSETransportEmitsRedactedParserTraceForLineDelimitedInvite() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        var traceEvents = [DebugForegroundCallSignalingSSESmokeTraceEvent]()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true,
                                                            stream: stream,
                                                            debugObserver: { event in
                                                                traceEvents.append(event)
                                                            },
                                                            now: fixedDirectCallTestNow(now))
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)

        pipeline.start()
        makeForegroundCallSSEInvite(handle: "safe-sse-trace", now: now)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .forEach { line in
                stream.emit(String(line) + "\n")
            }

        #expect(traceEvents.contains(.rawEventReceived))
        #expect(traceEvents.contains(.sseEventType(.invite)))
        #expect(traceEvents.contains(.inviteParseAttempted))
        #expect(traceEvents.contains(.inviteParseSucceeded(true)))
        #expect(traceEvents.contains(.pipelineDelivered(true)))
        #expect(dependencies.reportingAdapter.reportedIdentities.count == 1)
        let traceDescription = traceEvents.map(\.description).joined(separator: " ")
        #expect(Self.forbiddenFragments.allSatisfy { !traceDescription.contains($0) })
    }

    @Test
    func foregroundCallSignalingSSETransportEmitsRedactedParserTraceForRejectedInvite() {
        let now = Date(timeIntervalSince1970: 1000)
        let dependencies = makeNativeIncomingLifecycleDependencies()
        let stream = ForegroundCallSignalingSSEStreamSpy()
        var traceEvents = [DebugForegroundCallSignalingSSESmokeTraceEvent]()
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true,
                                                            stream: stream,
                                                            debugObserver: { event in
                                                                traceEvents.append(event)
                                                            },
                                                            now: fixedDirectCallTestNow(now))
        let pipeline = makeForegroundCallSignalingTransportPipeline(dependencies: dependencies,
                                                                    transport: transport,
                                                                    now: now)

        pipeline.start()
        makeForegroundCallSSEInvite(handle: String(repeating: "a", count: 65), now: now)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .forEach { line in
                stream.emit(String(line) + "\n")
            }

        #expect(traceEvents.contains(.rawEventReceived))
        #expect(traceEvents.contains(.sseEventType(.invite)))
        #expect(traceEvents.contains(.inviteParseAttempted))
        #expect(traceEvents.contains(.inviteParseSucceeded(false)))
        #expect(!traceEvents.contains(.pipelineDelivered(true)))
        #expect(dependencies.reportingAdapter.reportedIdentities.isEmpty)
        let traceDescription = traceEvents.map(\.description).joined(separator: " ")
        #expect(Self.forbiddenFragments.allSatisfy { !traceDescription.contains($0) })
    }

    private static let forbiddenFragments = [
        "!unsafe-room",
        "@unsafe-user",
        "DEVICE-SECRET",
        "redacted-fixture-a",
        "sensitive-incoming-credential-a",
        "sensitive-incoming-credential-b",
        "sample-media-credential",
        "redacted-fixture-b",
        "redacted-fixture-c",
        "displayCall",
        "presentCallScreen"
    ]

    private static let repositoryRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRootURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func allOccurrences(of symbol: String, areInsideDebugBlockIn source: String) -> Bool {
        var searchRange = source.startIndex..<source.endIndex
        var foundSymbol = false

        while let symbolRange = source.range(of: symbol, range: searchRange) {
            foundSymbol = true
            guard isInsideDebugBlock(symbolRange, in: source) else {
                return false
            }
            searchRange = symbolRange.upperBound..<source.endIndex
        }

        return foundSymbol
    }

    private static func isInsideDebugBlock(_ range: Range<String.Index>, in source: String) -> Bool {
        guard let debugStart = source[..<range.lowerBound].range(of: "#if DEBUG", options: .backwards) else {
            return false
        }

        return source[debugStart.upperBound..<range.lowerBound].range(of: "#endif") == nil
            && source[range.upperBound...].range(of: "#endif") != nil
    }

    private func makeNativeIncomingLifecycleDependencies() -> NativeIncomingLifecycleDependencies {
        let stateStore = NativeIncomingCallStateStoreSpy()
        let reportingAdapter = NativeIncomingCallReportingAdapterSpy(reportResult: true)
        let timeoutScheduler = NativeIncomingCallTimeoutSchedulerSpy()
        let diagnosticsRecorder = NativeIncomingCallDiagnosticsRecorderSpy()
        let service = DisabledNativeIncomingCallLifecycleService(isEnabled: true,
                                                                 stateStore: stateStore,
                                                                 reportingAdapter: reportingAdapter,
                                                                 timeoutScheduler: timeoutScheduler,
                                                                 diagnosticsRecorder: diagnosticsRecorder)
        return .init(service: service,
                     stateStore: stateStore,
                     reportingAdapter: reportingAdapter,
                     timeoutScheduler: timeoutScheduler,
                     diagnosticsRecorder: diagnosticsRecorder)
    }

    private func makeForegroundCallInviteHandler(dependencies: NativeIncomingLifecycleDependencies,
                                                 now: Date) -> ForegroundCallInviteHandler {
        ForegroundCallInviteHandler(isEnabled: true,
                                    stateStore: dependencies.stateStore,
                                    reportingAdapter: dependencies.reportingAdapter,
                                    diagnosticsRecorder: dependencies.diagnosticsRecorder) {
            now
        }
    }

    private func makeForegroundCallSignalingTransportPipeline(dependencies: NativeIncomingLifecycleDependencies,
                                                              transport: ForegroundCallSignalingTransport,
                                                              now: Date) -> ForegroundCallSignalingTransportPipeline {
        ForegroundCallSignalingTransportPipeline(transport: transport,
                                                 inviteHandler: makeForegroundCallInviteHandler(dependencies: dependencies,
                                                                                                now: now))
    }

    private func makeForegroundCallSSEInvite(handle: String,
                                             now: Date) -> String {
        let createdAtMs = Int(now.timeIntervalSince1970 * 1000)
        let expiresAtMs = Int(now.addingTimeInterval(30).timeIntervalSince1970 * 1000)
        let payload = """
        {"type":"foreground.call.invite","version":1,"call_handle":"\(handle)","call_kind":"audio","created_at_ms":\(createdAtMs),"expires_at_ms":\(expiresAtMs),"display_label":"Pilot Participant"}
        """
        return "event: foreground.call.invite\n" +
            "data: \(payload)\n\n"
    }
}

private struct NativeIncomingLifecycleDependencies {
    let service: DisabledNativeIncomingCallLifecycleService
    let stateStore: NativeIncomingCallStateStoreSpy
    let reportingAdapter: NativeIncomingCallReportingAdapterSpy
    let timeoutScheduler: NativeIncomingCallTimeoutSchedulerSpy
    let diagnosticsRecorder: NativeIncomingCallDiagnosticsRecorderSpy
}

private final class NativeIncomingCallStateStoreSpy: NativeIncomingCallStateStoring {
    private var states = [NativeIncomingCallHandle: NativeIncomingCallLifecycleState]()

    func state(for handle: NativeIncomingCallHandle) -> NativeIncomingCallLifecycleState? {
        states[handle]
    }

    func hasSeen(_ handle: NativeIncomingCallHandle) -> Bool {
        states[handle] != nil
    }

    func setState(_ state: NativeIncomingCallLifecycleState, for handle: NativeIncomingCallHandle) {
        states[handle] = state
    }

    func clear(_ handle: NativeIncomingCallHandle) {
        states[handle] = nil
    }
}

private final class ForegroundCallSignalingSSEStreamSpy: ForegroundCallSignalingSSEStreaming {
    private var onChunk: ((Data) -> Void)?
    private var onCompletion: ((ForegroundCallSignalingSSEStreamCompletion) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(onChunk: @escaping (Data) -> Void,
               onCompletion: @escaping (ForegroundCallSignalingSSEStreamCompletion) -> Void) {
        startCount += 1
        self.onChunk = onChunk
        self.onCompletion = onCompletion
    }

    func stop() {
        stopCount += 1
        onChunk = nil
        onCompletion = nil
    }

    func emit(_ text: String) {
        onChunk?(Data(text.utf8))
    }

    func complete(_ completion: ForegroundCallSignalingSSEStreamCompletion) {
        onCompletion?(completion)
    }
}

private func fixedDirectCallTestNow(_ date: Date) -> () -> Date {
    { date }
}

private final class NativeIncomingCallReportingAdapterSpy: NativeIncomingCallReportingAdapting {
    private let reportResult: Bool
    private(set) var reportedIdentities = [NativeIncomingCallIdentity]()
    private(set) var endedReasons = [NativeIncomingCallFailClosedReason]()

    init(reportResult: Bool) {
        self.reportResult = reportResult
    }

    func reportIncomingCall(identity: NativeIncomingCallIdentity) -> Bool {
        reportedIdentities.append(identity)
        return reportResult
    }

    func endReportedCall(identity: NativeIncomingCallIdentity, reason: NativeIncomingCallFailClosedReason) {
        endedReasons.append(reason)
    }
}

private final class NativeIncomingCallTimeoutSchedulerSpy: NativeIncomingCallTimeoutScheduling {
    private(set) var scheduledIdentities = [NativeIncomingCallIdentity]()
    private(set) var cancelledIdentities = [NativeIncomingCallIdentity]()

    func scheduleTimeout(for identity: NativeIncomingCallIdentity, after timeout: Duration) {
        scheduledIdentities.append(identity)
    }

    func cancelTimeout(for identity: NativeIncomingCallIdentity) {
        cancelledIdentities.append(identity)
    }
}

private final class NativeIncomingCallDiagnosticsRecorderSpy: NativeIncomingCallDiagnosticsRecording {
    private(set) var diagnostics = [NativeIncomingCallRedactedDiagnostics]()

    func record(_ diagnostics: NativeIncomingCallRedactedDiagnostics) {
        self.diagnostics.append(diagnostics)
    }
}

private final class NativeIncomingPushRegistrySpy: NativeIncomingPushRegistryManaging, CustomStringConvertible, CustomDebugStringConvertible {
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private var credentialCount = 0

    func registerForIncomingCallPushes() -> Bool {
        registerCount += 1
        return false
    }

    func updateIncomingCallPushCredential(_ credential: NativeIncomingPushRegistrationCredential) {
        credentialCount += credential.isPresent ? 1 : 0
    }

    func unregisterIncomingCallPushes() {
        unregisterCount += 1
    }

    var description: String {
        "NativeIncomingPushRegistrySpy(registerCount: \(registerCount), credentialCount: \(credentialCount), unregisterCount: \(unregisterCount), value: <redacted>)"
    }

    var debugDescription: String {
        description
    }
}

private final class NativeIncomingSyntheticCallKitActionHandlerSpy: NativeIncomingSyntheticCallKitActionHandling, CustomStringConvertible {
    private(set) var answeredIdentities = [NativeIncomingCallIdentity]()
    private(set) var endedIdentities = [NativeIncomingCallIdentity]()
    private(set) var mutedIdentities = [NativeIncomingCallIdentity]()
    private(set) var muteActions = [Bool]()

    func answerSyntheticCall(identity: NativeIncomingCallIdentity) {
        answeredIdentities.append(identity)
    }

    func endSyntheticCall(identity: NativeIncomingCallIdentity) {
        endedIdentities.append(identity)
    }

    func setSyntheticCallMuted(_ isMuted: Bool, identity: NativeIncomingCallIdentity) {
        muteActions.append(isMuted)
        mutedIdentities.append(identity)
    }

    var description: String {
        "NativeIncomingSyntheticCallKitActionHandlerSpy(answeredCount: \(answeredIdentities.count), endedCount: \(endedIdentities.count), mutedCount: \(mutedIdentities.count))"
    }
}

private final class DirectCallBackgroundCallKitProviderSpy: DirectCallBackgroundCallKitProviderProtocol, CustomStringConvertible {
    private let reportResult: Bool
    private(set) var reportRequests = [DirectCallBackgroundCallKitProviderReportRequest]()

    init(reportResult: Bool) {
        self.reportResult = reportResult
    }

    func reportIncomingCall(_ request: DirectCallBackgroundCallKitProviderReportRequest) -> Bool {
        reportRequests.append(request)
        return reportResult
    }

    var description: String {
        "DirectCallBackgroundCallKitProviderSpy(reportCount: \(reportRequests.count), pushKitRuntime: false, apnsRegistrationRuntime: false, mediaRuntime: false, matrixEventRuntime: false)"
    }
}

private final class DirectCallPushKitRegistrySpy: DirectCallPushKitRegistryControlling, CustomStringConvertible {
    private(set) var requestRegistrationCount = 0

    func requestVoIPPushRegistration() {
        requestRegistrationCount += 1
    }

    var description: String {
        "DirectCallPushKitRegistrySpy(requestRegistrationCount: \(requestRegistrationCount), fakeRegistryOnly: true, apnsRegistrationRuntime: false, mediaRuntime: false, matrixEventRuntime: false)"
    }
}

private final class DirectCallPushKitRegistryFactorySpy: DirectCallPushKitRegistryMaking, CustomStringConvertible {
    private(set) var makeRegistryCount = 0
    private(set) var registry: DirectCallPushKitRegistrySpy?

    func makeRegistry(delegate: DirectCallPushKitRegistrarRegistryDelegate) -> DirectCallPushKitRegistryControlling? {
        _ = delegate
        makeRegistryCount += 1
        let registry = DirectCallPushKitRegistrySpy()
        self.registry = registry
        return registry
    }

    var description: String {
        "DirectCallPushKitRegistryFactorySpy(makeRegistryCount: \(makeRegistryCount), fakeRegistryOnly: true, apnsRegistrationRuntime: false, mediaRuntime: false, matrixEventRuntime: false)"
    }
}

private final class DirectCallPushKitTokenRegistrationTransportSpy: DirectCallPushKitTokenRegistrationTransporting, CustomStringConvertible {
    private let result: DirectCallPushKitTokenRegistrationTransportResult
    private(set) var requests = [DirectCallPushKitTokenRegistrationRequest]()

    init(result: DirectCallPushKitTokenRegistrationTransportResult) {
        self.result = result
    }

    func register(_ request: DirectCallPushKitTokenRegistrationRequest) -> DirectCallPushKitTokenRegistrationTransportResult {
        requests.append(request)
        return result
    }

    var description: String {
        "DirectCallPushKitTokenRegistrationTransportSpy(" + [
            "requestCount: \(requests.count)",
            "fakeTransportOnly: true",
            "realNetworkRuntime: false",
            "tokenPersistenceRuntime: false",
            "apnsRegistrationRuntime: false",
            "mediaRuntime: false",
            "matrixEventRuntime: false"
        ].joined(separator: ", ") + ")"
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

@MainActor
private final class DelayedMediaEngineSpy: DirectCallMediaEngineProtocol {
    private let mediaStateSubject = CurrentValueSubject<DirectCallMediaState, Never>(.idle)
    private var continuation: CheckedContinuation<Result<DirectCallMediaState, DirectCallMediaError>, Never>?

    private(set) var connectedSessions = [DirectCallSession]()
    private(set) var connectedKeyHandles = [DirectCallMediaKeyHandle]()
    private(set) var disconnectCallIDs = [String]()
    private(set) var cleanupCallIDs = [String]()

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
        connectedSessions.append(session)
        connectedKeyHandles.append(keyHandle)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(with result: Result<DirectCallMediaState, DirectCallMediaError>) {
        continuation?.resume(returning: result)
        continuation = nil
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
