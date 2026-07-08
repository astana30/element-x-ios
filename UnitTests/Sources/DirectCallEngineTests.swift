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
    func requestMediaCredentialsUsesBoundaryWithoutConnectingMedia() async throws {
        let mediaEngine = MediaEngineSpy(credentialsResult: .success(.init(serverURL: URL(fileURLWithPath: "/tmp/livekit.example.com"),
                                                                           roomName: "room-redacted",
                                                                           token: "token-redacted")))
        let engine = makeEngine(mediaEngine: mediaEngine)

        let startResult = await engine.startOutgoingAudioCall(peer: peerUserID, roomID: roomID)
        let session = try startResult.get()

        let credentialsResult = await engine.requestMediaCredentials(callID: session.callID)
        let connectionInfo = try credentialsResult.get()

        #expect(connectionInfo.roomName == "room-redacted")
        #expect(mediaEngine.requestedCredentialSessions.map(\.callID) == [session.callID])
        #expect(mediaEngine.connectedSessions.isEmpty)
        #expect(mediaEngine.connectedKeyHandles.isEmpty)
        #expect(mediaEngine.disconnectCallIDs.isEmpty)
        #expect(mediaEngine.cleanupCallIDs.isEmpty)
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
        #expect(adapterSource.contains("callkit_report_requested=\\(callKitReportRequested)"))
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
        #expect(developerOptionsSource.contains("Prepare Answer marker: lock screen"))
        #expect(developerOptionsSource.contains("Prepare Answer marker: full screen"))
        #expect(developerOptionsSource.contains("Prepare Answer marker: banner"))
        #expect(developerOptionsSource.contains("Prepare Answer marker: foreground"))
        #expect(developerOptionsSource.contains("Mark CallKit Answer tap immediate"))
        #expect(developerOptionsSource.contains("Mark CallKit Answer tap 1-2s"))
        #expect(developerOptionsSource.contains("Mark CallKit Answer tap >2s"))
        #expect(developerOptionsSource.contains("Start local CallKit-only answerability smoke"))
        #expect(developerOptionsSource.contains("Schedule local background CallKit-only smoke in 5s"))
        #expect(developerOptionsSource.contains("voIPPushReceiptProof"))
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
        #expect(adapterSource.contains("salemx-voip-push-receipt-proof.txt"))
        #expect(adapterSource.contains("proof_source=\\(proofSource)"))
        #expect(adapterSource.contains("proof_generation=\\(proofGeneration)"))
        #expect(adapterSource.contains("proof_last_updated_by=\\(proofLastUpdatedBy)"))
        #expect(adapterSource.contains("proofSource = \"voip_push_receipt\""))
        #expect(adapterSource.contains("summary.proofLastUpdatedBy = \"voip_push_callback\""))
        #expect(adapterSource.contains("writeVoIPPushReceiptProof(proof)"))
        #expect(adapterSource.contains("private static func writeVoIPPushReceiptProof(_ proof: String)"))
        #expect(adapterSource.contains("voIPPushReceiptCallKitReportTimeout"))
        let callbackStart = try #require(adapterSource.range(of: "didReceiveIncomingPushWith payload")?.lowerBound)
        let controlledReceipt = try #require(adapterSource.range(of: "recordVoIPPushReceipt(payloadDictionary, completion: completion)")?.lowerBound)
        let nonDebugCompletion = try #require(adapterSource.range(of: "#else\n        completion()", range: controlledReceipt..<adapterSource.endIndex)?.lowerBound)
        let voIPSummaryUpdate = try #require(adapterSource.range(of: "private static func updateLatestVoIPPushReceiptSummary")?.lowerBound)
        let voIPProofWriterCall = try #require(adapterSource.range(of: "writeVoIPPushReceiptProof(proof)", range: voIPSummaryUpdate..<adapterSource.endIndex)?.lowerBound)
        let uploadProofWriterCall = try #require(adapterSource.range(of: "writeUploadSmokeProof(latestUploadSummary)")?.lowerBound)
        let timeoutFallback = try #require(adapterSource.range(of: "timeout_or_pending_redacted")?.lowerBound)
        let reportFinalizer = try #require(adapterSource.range(of: "completeVoIPPushReceiptOnce(coordinator: completionCoordinator")?.lowerBound)
        #expect(callbackStart < controlledReceipt)
        #expect(controlledReceipt < nonDebugCompletion)
        #expect(uploadProofWriterCall < voIPSummaryUpdate)
        #expect(voIPSummaryUpdate < voIPProofWriterCall)
        #expect(controlledReceipt < timeoutFallback)
        #expect(controlledReceipt < reportFinalizer)
        #expect(adapterSource.contains("physical_voip_push_received=\\(physicalVoIPPushReceived)"))
        #expect(adapterSource.contains("pushkit_callback_invoked=\\(callbackInvoked)"))
        #expect(adapterSource.contains("pushkit_payload_redacted=true"))
        #expect(adapterSource.contains("pushkit_payload_kind=\\(payloadKind)"))
        #expect(adapterSource.contains("sandbox_voip_smoke"))
        #expect(adapterSource.contains("real_invite_controlled"))
        #expect(adapterSource.contains("real_invite_payload_mapping_observed=\\(realInvitePayloadMappingObserved)"))
        #expect(adapterSource.contains("realInvitePayloadMappingObserved: isRealInviteControlled"))
        #expect(adapterSource.contains("pushkit_completion_called=\\(completionCalled)"))
        #expect(adapterSource.contains("completionCalled: false"))
        #expect(adapterSource.contains("completedSummary.completionCalled = true"))
        #expect(adapterSource.contains("callkit_report_requested=\\(callKitReportRequested)"))
        #expect(adapterSource.contains("callkit_report_result=\\(callKitReportResult)"))
        #expect(adapterSource.contains("callkit_report_error_redacted=true"))
        #expect(adapterSource.contains("callkit_provider_retained_for_answer=\\(callKitProviderRetainedForAnswer)"))
        #expect(adapterSource.contains("callkit_delegate_retained_for_answer=\\(callKitDelegateRetainedForAnswer)"))
        #expect(adapterSource.contains("callkit_active_call_uuid_retained=\\(callKitActiveCallUUIDRetained)"))
        #expect(adapterSource.contains("callkit_report_completion_timeout_classified_redacted"))
        #expect(adapterSource.contains("private let generation: Int"))
        #expect(adapterSource.contains("private var didRecordAnswer = false"))
        #expect(adapterSource.contains("isActiveCallKitProofGeneration(generation)"))
        #expect(adapterSource.contains("private static var callKitProofGeneration = 0"))
        #expect(adapterSource.contains("let generation = nextCallKitProofGeneration()"))
        #expect(adapterSource.contains("SalemXPushKitCallKitProofEventRecorder(generation: generation)"))
        #expect(adapterSource.contains("callKitProofHarness = nil"))
        #expect(adapterSource.contains("callkit_answer_action_received=\\(callKitAnswerActionReceived)"))
        #expect(adapterSource.contains("callkit_answer_action_fulfilled=\\(callKitAnswerActionFulfilled)"))
        #expect(adapterSource.contains("app_activation_observed=\\(appActivationObserved)"))
        #expect(adapterSource.contains("controlled_in_app_activation_requested=\\(controlledInAppActivationRequested)"))
        #expect(adapterSource.contains("controlled_in_app_activation_observed=\\(controlledInAppActivationObserved)"))
        #expect(adapterSource.contains("controlled_in_app_screen_requested=\\(controlledInAppScreenRequested)"))
        #expect(adapterSource.contains("controlled_in_app_screen_presented=\\(controlledInAppScreenPresented)"))
        #expect(adapterSource.contains("controlled_in_app_screen_source=\\(controlledInAppScreenSource)"))
        #expect(adapterSource.contains("controlled_callkit_cleanup_requested=\\(controlledCallKitCleanupRequested)"))
        #expect(adapterSource.contains("controlled_callkit_cleanup_result=\\(controlledCallKitCleanupResult)"))
        #expect(adapterSource.contains("controlledInAppActivationRequested = true"))
        #expect(adapterSource.contains("controlledInAppActivationObserved = true"))
        #expect(adapterSource.contains("controlledInAppScreenRequested = true"))
        #expect(adapterSource.contains("controlledInAppScreenPresented = true"))
        #expect(adapterSource.contains("callkit_answer_sandbox_voip_smoke"))
        #expect(adapterSource.contains("callkit_answer_real_invite_controlled"))
        #expect(adapterSource.contains("controlledInAppScreenSource = screenSource"))
        #expect(adapterSource.contains("recordControlledCallKitCleanupProof()"))
        #expect(adapterSource.contains("didRecordAnswer = true"))
        #expect(adapterSource.contains("guard didRecordAnswer else"))
        #expect(adapterSource.contains("controlledCallKitCleanupRequested = true"))
        #expect(adapterSource.contains("controlledCallKitCleanupResult = \"ended\""))
        #expect(adapterSource.contains("reporter.endCall(callUUID: callUUID)"))
        #expect(adapterSource.contains("clear(callUUID: callUUID)"))
        #expect(adapterSource.contains("guard SalemXPushKitRegistrationSmokeDebugBridge.isActiveCallKitProofGeneration(generation) else"))
        #expect(adapterSource.contains("recordCallKitAnswerActionProof()"))
        #expect(adapterSource.contains("SalemXPushKitCallKitProofEventRecorder"))
        #expect(adapterSource.contains("NativeIncomingSyntheticCallKitUIProofHarness.makePhysicalDeviceProofHarness"))
        #expect(adapterSource.contains("displayLabel: \"SalemX Test Call\""))
        #expect(adapterSource.contains("case .reported:"))
        #expect(adapterSource.contains("func provider(_ provider: CXProvider, perform action: CXAnswerCallAction)"))
        #expect(adapterSource.contains("action.fulfill()"))
        #expect(adapterSource.contains("delegate?.syntheticCallKitUIReportingDidAnswer(callUUID: action.callUUID)"))
        #expect(adapterSource.contains("cx_answer_action_callback_not_received"))
        #expect(adapterSource.contains("media_credentials_requested=false"))
        #expect(adapterSource.contains("media_connect_requested=false"))
        #expect(adapterSource.contains("matrix_event_emit_requested=false"))
        #expect(adapterSource.contains("real_call_flow_started=false"))
        #expect(!adapterSource.contains("payload.description"))
        #expect(!adapterSource.contains("payload.dictionaryPayload.description"))
        #expect(!adapterSource.contains("room_id=\\("))
        #expect(!adapterSource.contains("call_handle=\\("))
        #expect(!appSessionSource.contains("recordVoIPPushReceipt"))
    }

    @Test
    func debugVoIPPushReceiptProofEmitsConsoleMarkersForPhysicalPolling() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let voIPSummaryUpdate = try #require(adapterSource.range(of: "private static func updateLatestVoIPPushReceiptSummary")?.lowerBound)
        let voIPConsoleEmitter = try #require(adapterSource.range(of: "emitDebugProofConsole(proof)", range: voIPSummaryUpdate..<adapterSource.endIndex)?.lowerBound)
        let voIPOSLogEmitter = try #require(adapterSource.range(of: "emitDebugProofOSLog(proof)", range: voIPSummaryUpdate..<adapterSource.endIndex)?.lowerBound)
        let voIPProofWriterCall = try #require(adapterSource.range(of: "writeVoIPPushReceiptProof(proof)", range: voIPSummaryUpdate..<adapterSource.endIndex)?.lowerBound)

        #expect(voIPSummaryUpdate < voIPConsoleEmitter)
        #expect(voIPSummaryUpdate < voIPOSLogEmitter)
        #expect(voIPConsoleEmitter < voIPProofWriterCall)
        #expect(adapterSource.contains("physical_voip_push_received=\\(physicalVoIPPushReceived)"))
        #expect(adapterSource.contains("pushkit_callback_invoked=\\(callbackInvoked)"))
        #expect(adapterSource.contains("FileHandle.standardError.write(data)"))
    }

    @Test
    func callKitSurfaceRepairProofFieldsClassifyNoSurfaceWithoutConnect() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("callkit_surface_repair_present=\\(callKitSurfaceRepairPresent)"))
        #expect(adapterSource.contains("callkit_surface_repair_debug_only=\\(callKitSurfaceRepairDebugOnly)"))
        #expect(adapterSource.contains("callkit_surface_repair_provider_retention_verified=\\(callKitSurfaceRepairProviderRetentionVerified)"))
        #expect(adapterSource.contains("callkit_surface_repair_delegate_retention_verified=\\(callKitSurfaceRepairDelegateRetentionVerified)"))
        #expect(adapterSource.contains("callkit_surface_repair_active_uuid_retention_verified=\\(callKitSurfaceRepairActiveUUIDRetentionVerified)"))
        #expect(adapterSource.contains("callkit_surface_repair_report_completion_watchdog_present=\\(callKitSurfaceRepairReportCompletionWatchdogPresent)"))
        #expect(adapterSource.contains("callkit_surface_repair_report_completion_timeout_classified=\\(callKitSurfaceRepairReportCompletionTimeoutClassified)"))
        #expect(adapterSource.contains("callkit_surface_repair_pushkit_completion_safety_present=\\(callKitSurfaceRepairPushKitCompletionSafetyPresent)"))
        #expect(adapterSource.contains("callkit_surface_repair_pushkit_completion_safety_result=\\(callKitSurfaceRepairPushKitCompletionSafetyResult)"))
        #expect(adapterSource.contains("callkit_surface_repair_blocks_connect_without_answer=\\(callKitSurfaceRepairBlocksConnectWithoutAnswer)"))
        #expect(adapterSource.contains("callkit_surface_repair_blocks_metadata_without_answer=\\(callKitSurfaceRepairBlocksMetadataWithoutAnswer)"))
        #expect(adapterSource.contains("callkit_surface_repair_no_direct_answer_bypass=\\(callKitSurfaceRepairNoDirectAnswerBypass)"))
        #expect(adapterSource.contains("callkit_surface_repair_no_media_connect_on_no_answer=\\(callKitSurfaceRepairNoMediaConnectOnNoAnswer)"))
        #expect(adapterSource.contains("timeout_or_pending_redacted"))
        #expect(adapterSource.contains("completed_after_report_timeout"))
        #expect(adapterSource.contains("completed_after_answerable_window_timeout"))
        #expect(adapterSource.contains("currentCallKitAnswerRetentionProof()"))
        #expect(adapterSource.contains("scheduleVoIPPushReceiptReportTimeout(coordinator: completionCoordinator"))
        #expect(adapterSource.contains("beginBackgroundTask(withName: \"SalemXCallKitSurfaceRepair\")"))
        #expect(adapterSource.contains("finishVoIPPushReceiptBackgroundTask()"))
        #expect(adapterSource.contains("media_connect_requested=\\(mediaConnectRequested)"))
        #expect(adapterSource.contains("livekit_join_requested=\\(liveKitJoinRequested)"))
        #expect(adapterSource.contains("camera_permission_requested=\\(cameraPermissionRequested)"))
        #expect(adapterSource.contains("matrix_event_emit_requested=\\(matrixEventEmitRequested)"))
        #expect(adapterSource.contains("real_call_flow_started=\\(realCallFlowStarted)"))
        #expect(!adapterSource.contains("recordCallKitAnswerActionProof() // bypass"))
    }

    @Test
    func debugElementCallPushKitRegistryForwardsRedactedSalemXPayload() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let elementCallServiceSource = try Self.sourceFile("ElementX/Sources/Services/ElementCall/ElementCallService.swift")

        #expect(elementCallServiceSource.contains("#if DEBUG"))
        #expect(elementCallServiceSource.contains("handleElementCallServicePushKitReceipt(payload.dictionaryPayload, completion: completion)"))
        #expect(adapterSource.contains("static func handleElementCallServicePushKitReceipt(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) -> Bool"))
        #expect(adapterSource.contains("recordVoIPPushReceipt(payload,"))
        #expect(adapterSource.contains("elementCallServiceCallbackInvoked: true"))
        #expect(adapterSource.contains("element_call_pushkit_callback_invoked=\\(elementCallServicePushKitCallbackInvoked)"))
        #expect(adapterSource.contains("element_call_salemx_payload_observed=\\(elementCallServiceSalemXPayloadObserved)"))
        #expect(adapterSource.contains("element_call_payload_kind=\\(elementCallServicePayloadKind)"))
        #expect(adapterSource.contains("element_call_forwarded_to_salemx_receipt_pipeline=\\(elementCallServiceForwardedToSalemXReceiptPipeline)"))
        #expect(adapterSource.contains("element_call_completed_without_salemx_callkit_report=\\(elementCallServiceCompletedWithoutSalemXCallKitReport)"))
        #expect(adapterSource.contains("salemx-startup-pushkit-registry-proof.txt"))
        #expect(adapterSource.contains("proofSource = \"startup_pushkit_registry\""))
        #expect(adapterSource.contains("startup_pushkit_salemx_payload_observed=\\(salemXPayloadObserved)"))
        #expect(adapterSource.contains("salemx_payload_not_detected_in_startup_registry"))
        let callbackStart = try #require(elementCallServiceSource.range(of: "didReceiveIncomingPushWith payload")?.lowerBound)
        let interceptionStart = try #require(elementCallServiceSource.range(of: "handleElementCallServicePushKitReceipt",
                                                                            range: callbackStart..<elementCallServiceSource.endIndex)?.lowerBound)
        let roomIDGuard = try #require(elementCallServiceSource.range(of: "guard let roomID",
                                                                      range: callbackStart..<elementCallServiceSource.endIndex)?.lowerBound)
        #expect(callbackStart < interceptionStart)
        #expect(interceptionStart < roomIDGuard)
    }

    @Test
    func debugLocalCallKitOnlyProofIsSeparatedFromVoIPReceiptProof() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let developerOptionsSource = try Self.sourceFile("ElementX/Sources/AppHooks/Hooks/DeveloperOptionsScreenHook.swift")

        #expect(adapterSource.contains("salemx-voip-push-receipt-proof.txt"))
        #expect(adapterSource.contains("salemx-local-callkit-only-proof.txt"))
        #expect(adapterSource.contains("salemx-local-background-callkit-proof.txt"))
        #expect(adapterSource.contains("salemx-pushkit-token-upload-smoke-proof.txt"))
        #expect(adapterSource.contains("private static func writeVoIPPushReceiptProof(_ proof: String)"))
        #expect(adapterSource.contains("private static func writeLocalCallKitOnlyProof(_ proof: String)"))
        #expect(adapterSource.contains("private static func writeLocalBackgroundCallKitOnlyProof(_ proof: String)"))
        #expect(adapterSource.contains("private static func writeUploadSmokeProof(_ proof: String)"))
        #expect(adapterSource.contains("proof_source=\\(proofSource)"))
        #expect(adapterSource.contains("proof_generation=\\(proofGeneration)"))
        #expect(adapterSource.contains("proof_last_updated_by=\\(proofLastUpdatedBy)"))
        #expect(adapterSource.contains("proofSource = \"voip_push_receipt\""))
        #expect(adapterSource.contains("proofSource = \"local_callkit_only\""))
        #expect(adapterSource.contains("proofSource = \"local_background_callkit_only\""))
        #expect(adapterSource.contains("proofSource = \"pushkit_upload_smoke\""))
        #expect(adapterSource.contains("local_callkit_only_update_equivalent_to_voip=\\(localCallKitOnlyUpdateEquivalentToVoIP)"))
        #expect(adapterSource.contains("local_callkit_only_provider_config_equivalent_to_voip=\\(localCallKitOnlyProviderConfigEquivalentToVoIP)"))
        #expect(adapterSource.contains("private static var localCallKitOnlyProofHarness"))
        #expect(adapterSource.contains("private static var localCallKitOnlyProofGeneration"))
        #expect(adapterSource.contains("private static var localBackgroundCallKitOnlyProofHarness"))
        #expect(adapterSource.contains("private static var localBackgroundCallKitOnlyProofGeneration"))
        #expect(adapterSource.contains("let generation = nextLocalCallKitOnlyProofGeneration()"))
        #expect(adapterSource.contains("let generation = nextLocalBackgroundCallKitOnlyProofGeneration()"))
        #expect(adapterSource.contains("localCallKitOnlyProofHarness?.endSyntheticIncomingCall()"))
        #expect(adapterSource.contains("localBackgroundCallKitOnlyProofHarness?.endSyntheticIncomingCall()"))
        #expect(adapterSource.contains("localCallKitOnlyProofHarness = proofHarness"))
        #expect(adapterSource.contains("localBackgroundCallKitOnlyProofHarness = proofHarness"))
        #expect(adapterSource.contains("isActiveLocalCallKitOnlyProofGeneration(generation)"))
        #expect(adapterSource.contains("isActiveLocalBackgroundCallKitOnlyProofGeneration(generation)"))

        let localStart = try #require(adapterSource.range(of: "startLocalCallKitOnlyAnswerabilitySmoke()")?.lowerBound)
        let localBackgroundStart = try #require(adapterSource.range(of: "scheduleLocalBackgroundCallKitOnlyAnswerabilitySmoke()",
                                                                    range: localStart..<adapterSource.endIndex)?.lowerBound)
        let localSmokeBody = adapterSource[localStart..<localBackgroundStart]
        #expect(localSmokeBody.contains("updateLatestLocalCallKitOnlySummary(summary)"))
        #expect(!localSmokeBody.contains("updateLatestVoIPPushReceiptSummary(summary)"))

        let localBackgroundCallbackStart = try #require(adapterSource.range(of: "private static func recordCallKitOperatorInteraction",
                                                                            range: localBackgroundStart..<adapterSource.endIndex)?.lowerBound)
        let localBackgroundSmokeBody = adapterSource[localBackgroundStart..<localBackgroundCallbackStart]
        #expect(localBackgroundSmokeBody.contains("updateLatestLocalBackgroundCallKitOnlySummary(summary)"))
        #expect(!localBackgroundSmokeBody.contains("updateLatestVoIPPushReceiptSummary(summary)"))
        #expect(!localBackgroundSmokeBody.contains("updateLatestLocalCallKitOnlySummary(summary)"))
        #expect(adapterSource.contains("localBackgroundCallKitOnlyReportDelay: TimeInterval = 5"))
        #expect(adapterSource.contains("app_state_at_report=\\(appStateAtReport)"))
        #expect(adapterSource.contains("local_background_report_result=\\(reportResult)"))
        #expect(adapterSource.contains("local_background_first_action_kind=\\(firstActionKind)"))
        #expect(adapterSource.contains("local_background_answer_action_delivered=\\(answerActionDelivered)"))
        #expect(adapterSource.contains("local_background_end_action_delivered=\\(endActionDelivered)"))

        let localUpdate = try #require(adapterSource.range(of: "private static func updateLatestLocalCallKitOnlySummary")?.lowerBound)
        let localWriter = try #require(adapterSource.range(of: "writeLocalCallKitOnlyProof(proof)", range: localUpdate..<adapterSource.endIndex)?.lowerBound)
        let localBackgroundUpdate = try #require(adapterSource.range(of: "private static func updateLatestLocalBackgroundCallKitOnlySummary")?.lowerBound)
        let localBackgroundWriter = try #require(adapterSource.range(of: "writeLocalBackgroundCallKitOnlyProof(proof)", range: localBackgroundUpdate..<adapterSource.endIndex)?.lowerBound)
        let voIPUpdate = try #require(adapterSource.range(of: "private static func updateLatestVoIPPushReceiptSummary")?.lowerBound)
        let voIPWriter = try #require(adapterSource.range(of: "writeVoIPPushReceiptProof(proof)", range: voIPUpdate..<adapterSource.endIndex)?.lowerBound)
        let uploadUpdate = try #require(adapterSource.range(of: "private static func updateLatestUploadSummary")?.lowerBound)
        let uploadWriter = try #require(adapterSource.range(of: "writeUploadSmokeProof(latestUploadSummary)", range: uploadUpdate..<adapterSource.endIndex)?.lowerBound)
        #expect(localUpdate < localWriter)
        #expect(localBackgroundUpdate < localBackgroundWriter)
        #expect(voIPUpdate < voIPWriter)
        #expect(uploadUpdate < uploadWriter)
        #expect(developerOptionsSource.contains("localCallKitOnlyProof"))
        #expect(developerOptionsSource.contains("localBackgroundCallKitOnlyProof"))
        #expect(developerOptionsSource.contains("redactedLocalCallKitOnlySummary()"))
        #expect(developerOptionsSource.contains("redactedLocalBackgroundCallKitOnlySummary()"))
        #expect(developerOptionsSource.contains("refreshLocalCallKitOnlySummary"))
        #expect(developerOptionsSource.contains("refreshLocalBackgroundCallKitOnlySummary"))
    }

    @Test
    func controlledCallKitReportWaitsForCallbackAndRecordsAnswerMatchingProof() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("callkit_report_completion_observed=\\(callKitReportCompletionObserved)"))
        #expect(adapterSource.contains("callKitReportCompletionObserved = reportResult != \"timeout_or_pending_redacted\""))
        #expect(adapterSource.contains("callkit_report_submitted_at_ms_redacted=\\(callKitReportSubmittedAtMsRedacted)"))
        #expect(adapterSource.contains("callkit_report_completion_at_ms_redacted=\\(callKitReportCompletionAtMsRedacted)"))
        #expect(adapterSource.contains("callkit_update_has_generic_handle=\\(callKitUpdateHasGenericHandle)"))
        #expect(adapterSource.contains("callkit_update_has_localized_caller_name=\\(callKitUpdateHasLocalizedCallerName)"))
        #expect(adapterSource.contains("callkit_update_audio_only=\\(callKitUpdateAudioOnly)"))
        #expect(adapterSource.contains("callkit_provider_configuration_audio_only=\\(callKitProviderConfigurationAudioOnly)"))
        #expect(adapterSource.contains("callkit_provider_configuration_supported_handle_generic=\\(callKitProviderConfigurationSupportedHandleGeneric)"))
        #expect(adapterSource.contains("voip_callkit_update_equivalent_to_local=\\(voIPCallKitUpdateEquivalentToLocal)"))
        #expect(adapterSource.contains("voip_report_queue_matches_local=\\(voIPReportQueueMatchesLocal)"))
        #expect(adapterSource.contains("voip_provider_reuse_matches_local=\\(voIPProviderReuseMatchesLocal)"))
        #expect(adapterSource.contains("voip_operator_marker_set_before_report=\\(voIPOperatorMarkerSetBeforeReport)"))
        #expect(adapterSource.contains("reportControlledSandboxVoIPSmokeCallKit { reportResult, answerRetentionProof in"))
        #expect(adapterSource.contains("callKitProviderRetainedForAnswer = answerRetentionProof.providerRetainedForAnswer"))
        #expect(adapterSource.contains("callKitDelegateRetainedForAnswer = answerRetentionProof.delegateRetainedForAnswer"))
        #expect(adapterSource.contains("callKitActiveCallUUIDRetained = answerRetentionProof.activeCallUUIDRetained"))
        #expect(adapterSource.contains("callKitSurfaceRepairProviderRetentionVerified = answerRetentionProof.providerRetainedForAnswer"))
        #expect(adapterSource.contains("callKitSurfaceRepairDelegateRetentionVerified = answerRetentionProof.delegateRetainedForAnswer"))
        #expect(adapterSource.contains("callKitSurfaceRepairActiveUUIDRetentionVerified = answerRetentionProof.activeCallUUIDRetained"))
        #expect(adapterSource.contains("currentCallKitAnswerRetentionProof()"))
        #expect(adapterSource.contains("beginBackgroundTask(withName: \"SalemXCallKitSurfaceRepair\")"))
        #expect(adapterSource.contains("finishVoIPPushReceiptBackgroundTask()"))
        #expect(adapterSource.contains("reportNewIncomingCall(with: callUUID, update: update)"))
        #expect(adapterSource.contains("completion(true)"))
        #expect(adapterSource.contains("completion(false)"))
        #expect(adapterSource.contains("completion(\"reported\", proofHarness.answerRetentionProof())"))
        #expect(adapterSource.contains("callkit_answer_action_delivered=\\(callKitAnswerActionDelivered)"))
        #expect(adapterSource.contains("answer_action_uuid_matched=\\(answerActionUUIDMatched)"))
        #expect(adapterSource.contains("answer_action_generation_matched=\\(answerActionGenerationMatched)"))
        #expect(adapterSource.contains("callkit_provider_did_reset_observed=\\(callKitProviderDidResetObserved)"))
        #expect(adapterSource.contains("callkit_provider_reset_observed=\\(callKitProviderDidResetObserved)"))
        #expect(adapterSource.contains("callkit_provider_did_activate_audio_session=\\(callKitProviderDidActivateAudioSession)"))
        #expect(adapterSource.contains("callkit_audio_session_did_activate=\\(callKitProviderDidActivateAudioSession)"))
        #expect(adapterSource.contains("callkit_provider_did_deactivate_audio_session=\\(callKitProviderDidDeactivateAudioSession)"))
        #expect(adapterSource.contains("callkit_audio_session_did_deactivate=\\(callKitProviderDidDeactivateAudioSession)"))
        #expect(adapterSource.contains("callkit_first_action_kind=\\(callKitFirstActionKind)"))
        #expect(adapterSource.contains("callkit_first_action_after_report_ms_bucket=\\(callKitFirstActionAfterReportMsBucket)"))
        #expect(adapterSource.contains("operator_ready_to_answer=\\(operatorReadyToAnswer)"))
        #expect(adapterSource.contains("operator_expected_surface=\\(operatorExpectedSurface)"))
        #expect(adapterSource.contains("callkit_ui_surface_observed_by_operator=\\(callKitUISurfaceObservedByOperator)"))
        #expect(adapterSource.contains("callkit_operator_intended_action=\\(callKitOperatorIntendedAction)"))
        #expect(adapterSource.contains("callkit_operator_action_timing_bucket=\\(callKitOperatorActionTimingBucket)"))
        #expect(adapterSource.contains("callkit_ui_answer_operator_tap_observed=\\(callKitUIAnswerOperatorTapObserved)"))
        #expect(adapterSource.contains("callkit_end_arrived_before_operator_answer_window=\\(callKitEndArrivedBeforeOperatorAnswerWindow)"))
        #expect(adapterSource.contains("callkit_end_action_delivered=\\(callKitEndActionDelivered)"))
        #expect(adapterSource.contains("end_action_uuid_matched=\\(endActionUUIDMatched)"))
        #expect(adapterSource.contains("end_action_generation_matched=\\(endActionGenerationMatched)"))
        #expect(adapterSource.contains("end_action_source_matched=\\(endActionSourceMatched)"))
        #expect(adapterSource.contains("end_action_fulfilled=\\(endActionFulfilled)"))
        #expect(adapterSource.contains("end_action_origin=\\(endActionOrigin)"))
        #expect(adapterSource.contains("local_end_request_before_answer=\\(localEndRequestBeforeAnswer)"))
        #expect(adapterSource.contains("provider_invalidate_before_answer=\\(providerInvalidateBeforeAnswer)"))
        #expect(adapterSource.contains("report_call_ended_before_answer=\\(reportCallEndedBeforeAnswer)"))
        #expect(adapterSource.contains("controlled_timeout_before_answer=\\(controlledTimeoutBeforeAnswer)"))
        #expect(adapterSource.contains("callkit_event_order=\\(callKitEventOrder)"))
        #expect(adapterSource.contains("private let providerDelegateQueue = DispatchQueue(label: \"kz.salemx.callkit.proof.delegate\")"))
        #expect(adapterSource.contains("provider.setDelegate(self, queue: providerDelegateQueue)"))
        #expect(adapterSource.contains("func providerDidReset(_ provider: CXProvider)"))
        #expect(adapterSource.contains("func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession)"))
        #expect(adapterSource.contains("func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession)"))
        #expect(adapterSource.contains("case .answerActionDelivered(let uuidMatched):"))
        #expect(adapterSource.contains("recordCallKitAnswerActionDeliveryProof(uuidMatched: uuidMatched, generationMatched: true)"))
        #expect(adapterSource.contains("recordCallKitAnswerActionDeliveryProof(uuidMatched: false, generationMatched: false)"))
        #expect(adapterSource.contains("case .providerDidReset:"))
        #expect(adapterSource.contains("recordCallKitProviderResetProof()"))
        #expect(adapterSource.contains("case .endActionDelivered(let uuidMatched):"))
        #expect(adapterSource.contains("recordCallKitEndActionDeliveryProof(uuidMatched: uuidMatched, generationMatched: true)"))
        #expect(adapterSource.contains("recordCallKitEndActionFulfillmentProof(uuidMatched: uuidMatched, generationMatched: true)"))
        #expect(adapterSource.contains("recordCallKitLocalEndRequestBeforeAnswerProof(uuidMatched: uuidMatched)"))
        #expect(adapterSource.contains("recordCallKitOperatorAnswerIntent(_ timingBucket: String)"))
        #expect(adapterSource.contains("recordCallKitOperatorEndIntent(_ timingBucket: String)"))
        #expect(adapterSource.contains("recordCallKitOperatorReadyToAnswer(_ expectedSurface: String)"))
        #expect(adapterSource.contains("pendingOperatorReadyToAnswer"))
        #expect(adapterSource.contains("pendingOperatorExpectedSurface"))
        #expect(adapterSource.contains("baseSummary.operatorReadyToAnswer = operatorReadyToAnswer"))
        #expect(adapterSource.contains("baseSummary.operatorExpectedSurface = operatorExpectedSurface"))
        #expect(adapterSource.contains("summary.callKitUISurfaceObservedByOperator = true"))
        #expect(adapterSource.contains("summary.callKitOperatorIntendedAction = safeIntendedAction"))
        #expect(adapterSource.contains("summary.callKitOperatorActionTimingBucket = safeTimingBucket"))
        #expect(adapterSource.contains("background_callkit_end_before_operator_action"))
        #expect(adapterSource.contains("background_callkit_end_after_operator_answer_intent"))
        #expect(adapterSource.contains("background_callkit_audio_activation_missing_before_end"))
        #expect(adapterSource.contains("recordFirstCallKitAction(\"answer\", in: &summary)"))
        #expect(adapterSource.contains("recordFirstCallKitAction(\"end\", in: &summary)"))
        #expect(adapterSource.contains("recordFirstCallKitAction(\"reset\", in: &summary)"))
        #expect(adapterSource.contains("callKitFirstActionAfterReportBucket()"))
        #expect(adapterSource.contains("callkit_provider_reset_before_answer"))
        #expect(adapterSource.contains("system_or_user_end_before_answer"))
        #expect(adapterSource.contains("system_end_before_answer_window"))
        #expect(adapterSource.contains("local_end_requested_before_answer"))
        #expect(adapterSource.contains("summary.answerActionUUIDMatched = uuidMatched"))
        #expect(adapterSource.contains("summary.answerActionGenerationMatched = generationMatched"))
        #expect(adapterSource.contains("summary.endActionUUIDMatched = uuidMatched"))
        #expect(adapterSource.contains("summary.endActionGenerationMatched = generationMatched"))
        #expect(adapterSource.contains("summary.endActionSourceMatched = uuidMatched && generationMatched"))
    }

    @Test
    func controlledCallKitBackgroundTimingProofIsRedactedAndBucketed() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("pushkit_completion_after_report_ms_bucket=\\(pushKitCompletionAfterReportMsBucket)"))
        #expect(adapterSource.contains("pushkit_completion_answerable_window_requested=\\(pushKitCompletionAnswerableWindowRequested)"))
        #expect(adapterSource.contains("pushkit_completion_answerable_window_result=\\(pushKitCompletionAnswerableWindowResult)"))
        #expect(adapterSource.contains("pushkit_completion_answerable_window_duration_bucket=\\(pushKitCompletionAnswerableWindowDurationBucket)"))
        #expect(adapterSource.contains("voip_pushkit_completion_delayed_until_first_action=\\(voIPPushKitCompletionDelayedUntilFirstAction)"))
        #expect(adapterSource.contains("voIPPushReceiptAnswerableWindowTimeout"))
        #expect(adapterSource.contains("SalemXPushKitCompletionCoordinator"))
        #expect(adapterSource.contains("coordinator.shouldRunReportTimeout()"))
        #expect(adapterSource.contains("completionCoordinator.markReportCompletionObserved()"))
        #expect(adapterSource.contains("completeVoIPPushReceiptOnce(coordinator: completionCoordinator"))
        #expect(adapterSource.contains("startPushKitCompletionAnswerableWindow(coordinator: completionCoordinator"))
        #expect(adapterSource.contains("callkit_end_after_pushkit_completion_ms_bucket=\\(callKitEndAfterPushKitCompletionMsBucket)"))
        #expect(adapterSource.contains("app_state_at_pushkit_receipt=\\(appStateAtPushKitReceipt)"))
        #expect(adapterSource.contains("app_state_at_report_completion=\\(appStateAtReportCompletion)"))
        #expect(adapterSource.contains("app_state_at_first_callkit_action=\\(appStateAtFirstCallKitAction)"))
        #expect(adapterSource.contains("provider_did_reset_before_first_action=\\(providerDidResetBeforeFirstAction)"))
        #expect(adapterSource.contains("audio_session_did_activate_before_first_action=\\(audioSessionDidActivateBeforeFirstAction)"))
        #expect(adapterSource.contains("audio_session_did_deactivate_before_first_action=\\(audioSessionDidDeactivateBeforeFirstAction)"))
        #expect(adapterSource.contains("baseSummary.appStateAtPushKitReceipt = currentApplicationStateProof()"))
        #expect(adapterSource.contains("completedSummary.appStateAtReportCompletion = currentApplicationStateProof()"))
        #expect(adapterSource.contains("summary.appStateAtFirstCallKitAction = currentApplicationStateProof()"))
        #expect(adapterSource.contains("summary.providerDidResetBeforeFirstAction = summary.callKitProviderDidResetObserved"))
        #expect(adapterSource.contains("summary.audioSessionDidActivateBeforeFirstAction = summary.callKitProviderDidActivateAudioSession"))
        #expect(adapterSource.contains("summary.audioSessionDidDeactivateBeforeFirstAction = summary.callKitProviderDidDeactivateAudioSession"))
        #expect(adapterSource.contains("elapsedBucket(from: callKitReportCompletionDate)"))
        #expect(adapterSource.contains("pushKitCompletionDate = nil"))
        #expect(adapterSource.contains("pushKitCompletionAnswerableWindowID = nil"))
        #expect(adapterSource.contains("pushKitCompletionAnswerableWindowFinish = nil"))
        #expect(adapterSource.contains("summary.pushKitCompletionAnswerableWindowRequested = true"))
        #expect(adapterSource.contains("summary.pushKitCompletionAnswerableWindowResult = \"pending\""))
        #expect(adapterSource.contains("completedSummary.voIPPushKitCompletionDelayedUntilFirstAction = answerableWindowRequested && answerableWindowResult == \"first_action_observed\""))
        #expect(adapterSource.contains("finish?(\"first_action_observed\")"))
        #expect(adapterSource.contains("finish?(\"timeout_elapsed\")"))
        #expect(adapterSource.contains("callkit_first_action_not_observed_before_completion_window"))
        #expect(adapterSource.contains("pushKitCompletionDate = reportResult == \"timeout_or_pending_redacted\" ? nil : completionCallDate"))
        #expect(adapterSource.contains("summary.callKitEndAfterPushKitCompletionMsBucket = elapsedBucket(from: pushKitCompletionDate)"))
        #expect(adapterSource.contains("private static func currentApplicationStateProof() -> String"))
    }

    @Test
    func disconnectCleanupDiagnosticsClassifyProviderCleanupWithoutEndAction() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_present=\\(disconnectCleanupDiagnosticsPresent)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_debug_only=\\(disconnectCleanupDiagnosticsDebugOnly)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_callkit_cleanup_requested=\\(disconnectCleanupDiagnosticsCallKitCleanupRequested)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_callkit_cleanup_result=\\(disconnectCleanupDiagnosticsCallKitCleanupResult)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_end_action_expected=\\(disconnectCleanupDiagnosticsEndActionExpected)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_end_action_delivered=\\(disconnectCleanupDiagnosticsEndActionDelivered)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_end_action_fulfilled=\\(disconnectCleanupDiagnosticsEndActionFulfilled)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_end_action_origin=\\(disconnectCleanupDiagnosticsEndActionOrigin)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_end_action_uuid_matched=\\(disconnectCleanupDiagnosticsEndActionUUIDMatched)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_end_action_generation_matched=\\(disconnectCleanupDiagnosticsEndActionGenerationMatched)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_end_action_source_matched=\\(disconnectCleanupDiagnosticsEndActionSourceMatched)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_provider_end_reported=\\(disconnectCleanupDiagnosticsProviderEndReported)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_local_cleanup_completed=\\(disconnectCleanupDiagnosticsLocalCleanupCompleted)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_audio_session_deactivated=\\(disconnectCleanupDiagnosticsAudioSessionDeactivated)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_livekit_cleanup_requested=\\(disconnectCleanupDiagnosticsLiveKitCleanupRequested)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_livekit_cleanup_completed=\\(disconnectCleanupDiagnosticsLiveKitCleanupCompleted)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_one_shot_consumed=\\(disconnectCleanupDiagnosticsOneShotConsumed)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_no_repeated_connect=\\(disconnectCleanupDiagnosticsNoRepeatedConnect)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_no_matrix_events=\\(disconnectCleanupDiagnosticsNoMatrixEvents)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_no_video=\\(disconnectCleanupDiagnosticsNoVideo)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_raw_identifiers_logged=\\(disconnectCleanupDiagnosticsRawIdentifiersLogged)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_end_timing_classification=\\(disconnectCleanupDiagnosticsEndTimingClassification)"))
        #expect(adapterSource.contains("disconnect_cleanup_diagnostics_result=\\(disconnectCleanupDiagnosticsResult)"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionExpected = callKitEndActionDelivered || endActionFulfilled"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsLocalCleanupCompleted = controlledCallKitCleanupResult == \"ended\""))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsProviderEndReported = disconnectCleanupDiagnosticsLocalCleanupCompleted && !disconnectCleanupDiagnosticsEndActionExpected"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsAudioSessionDeactivated = callKitProviderDidDeactivateAudioSession"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsLiveKitCleanupRequested = controlledCallKitCleanupRequested && liveKitConnectAudioInvoked"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsLiveKitCleanupCompleted = disconnectCleanupDiagnosticsLiveKitCleanupRequested && disconnectCleanupDiagnosticsLocalCleanupCompleted"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsOneShotConsumed = physical6RuntimeEnablementURLHookConsumed"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsNoRepeatedConnect = !controlledConnectFirstAttemptRepeated"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsNoMatrixEvents = !matrixEventEmitRequested && !controlledConnectFirstAttemptMatrixEventsAllowed"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsNoVideo = !controlledConnectFirstAttemptVideoAllowed && !cameraPermissionRequested"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndTimingClassification = \"end_action_not_expected\""))
        #expect(adapterSource.contains("local_or_provider_cleanup_sufficient_redacted"))
        #expect(adapterSource.contains("summary.refreshDisconnectCleanupDiagnostics()"))
        #expect(!adapterSource.contains("disconnectCleanupDiagnosticsRawIdentifiersLogged = true"))
    }

    @Test
    func disconnectCleanupDiagnosticsRequireMatchingFulfilledEndActionWhenExpected() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionDelivered = callKitEndActionDelivered"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionFulfilled = endActionFulfilled"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionUUIDMatched = endActionUUIDMatched"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionGenerationMatched = endActionGenerationMatched"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionSourceMatched = endActionSourceMatched"))
        #expect(adapterSource.contains("} else if callKitEndAfterPushKitCompletionMsBucket == \"unknown\" {"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndTimingClassification = \"end_action_timing_unknown_redacted\""))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsResult = \"end_action_timing_unknown_redacted\""))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionDelivered,"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionFulfilled,"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionUUIDMatched,"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionGenerationMatched,"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsEndActionSourceMatched"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsResult = \"end_action_cleanup_sufficient_redacted\""))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsResult = \"end_action_incomplete_redacted\""))
        #expect(adapterSource.contains("summary.endActionSourceMatched = uuidMatched && generationMatched"))
        #expect(adapterSource.contains("summary.endActionFulfilled = true"))
        #expect(adapterSource.contains("callkit_end_after_pushkit_completion_ms_bucket=\\(callKitEndAfterPushKitCompletionMsBucket)"))
    }

    @Test
    // swiftlint:disable:next function_body_length
    func remoteAudioLivenessDiagnosticsFieldsAndDefaultsAreRedacted() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("remote_audio_liveness_diagnostics_present=\\(remoteAudioLivenessDiagnosticsPresent)"))
        #expect(adapterSource.contains("remote_audio_liveness_diagnostics_debug_only=\\(remoteAudioLivenessDiagnosticsDebugOnly)"))
        #expect(adapterSource.contains("remote_audio_liveness_diagnostics_audio_only=\\(remoteAudioLivenessDiagnosticsAudioOnly)"))
        #expect(adapterSource.contains("remote_audio_liveness_diagnostics_video_allowed=\\(remoteAudioLivenessDiagnosticsVideoAllowed)"))
        #expect(adapterSource.contains("remote_audio_liveness_diagnostics_matrix_events_allowed=\\(remoteAudioLivenessDiagnosticsMatrixEventsAllowed)"))
        #expect(adapterSource.contains("remote_audio_liveness_diagnostics_raw_identifiers_logged=\\(remoteAudioLivenessDiagnosticsRawIdentifiersLogged)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_present=\\(remoteAudioPublishLivenessRepairPresent)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_debug_only=\\(remoteAudioPublishLivenessRepairDebugOnly)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_requires_livekit_join_success=\\(remoteAudioPublishLivenessRepairRequiresLiveKitJoinSuccess)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_classifies_publish_not_requested=\\(remoteAudioPublishLivenessRepairClassifiesPublishNotRequested)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_classifies_publish_success=\\(remoteAudioPublishLivenessRepairClassifiesPublishSuccess)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_classifies_publish_failure=\\(remoteAudioPublishLivenessRepairClassifiesPublishFailure)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_classifies_simulator_peer=\\(remoteAudioPublishLivenessRepairClassifiesSimulatorPeer)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_classifies_remote_missing=\\(remoteAudioPublishLivenessRepairClassifiesRemoteMissing)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_classifies_remote_track_missing=\\(remoteAudioPublishLivenessRepairClassifiesRemoteTrackMissing)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_classifies_liveness_observed=\\(remoteAudioPublishLivenessRepairClassifiesLivenessObserved)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_no_video=\\(remoteAudioPublishLivenessRepairNoVideo)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_no_matrix_events=\\(remoteAudioPublishLivenessRepairNoMatrixEvents)"))
        #expect(adapterSource.contains("remote_audio_publish_liveness_repair_raw_identifiers_logged=\\(remoteAudioPublishLivenessRepairRawIdentifiersLogged)"))
        #expect(adapterSource.contains("remote_audio_track_liveness_proof_present=\\(remoteAudioTrackLivenessProofPresent)"))
        #expect(adapterSource.contains("remote_audio_track_liveness_proof_debug_only=\\(remoteAudioTrackLivenessProofDebugOnly)"))
        #expect(adapterSource.contains("remote_audio_track_liveness_raw_identifiers_logged=\\(remoteAudioTrackLivenessRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_binding_repair_present=\\(receiverAudioObserverLeaseBindingRepairPresent)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_binding_repair_debug_only=\\(receiverAudioObserverLeaseBindingRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_binding_raw_identifiers_logged=\\(receiverAudioObserverLeaseBindingRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_audio_observer_uses_retained_session_lease=\\(receiverAudioObserverUsesRetainedSessionLease)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_present_at_attach=\\(receiverAudioObserverLeasePresentAtAttach)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_present_after_participant_seen=\\(receiverAudioObserverLeasePresentAfterParticipantSeen)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_present_during_subscription_wait=\\(receiverAudioObserverLeasePresentDuringSubscriptionWait)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_released_before_audio_terminal=\\(receiverAudioObserverLeaseReleasedBeforeAudioTerminal)"))
        #expect(adapterSource.contains("receiver_audio_observer_bound_to_same_client_as_receiver_join=\\(receiverAudioObserverBoundToSameClientAsReceiverJoin)"))
        #expect(adapterSource.contains("receiver_audio_observer_bound_to_same_client_as_participant_callback=\\(receiverAudioObserverBoundToSameClientAsParticipantCallback)"))
        #expect(adapterSource.contains("receiver_audio_observer_bound_to_retained_room=\\(receiverAudioObserverBoundToRetainedRoom)"))
        #expect(adapterSource.contains("receiver_audio_observer_bound_to_connected_room=\\(receiverAudioObserverBoundToConnectedRoom)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_binding_final_classification=\\(receiverAudioObserverLeaseBindingFinalClassification)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_present=\\(remotePeerContextHandoffPresent)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_debug_only=\\(remotePeerContextHandoffDebugOnly)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_source=\\(remotePeerContextHandoffSource)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_armed_before_apns=\\(remotePeerContextHandoffArmedBeforeAPNs)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_received_by_runtime=\\(remotePeerContextHandoffReceivedByRuntime)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_survived_pushkit=\\(remotePeerContextHandoffSurvivedPushKit)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_survived_answer=\\(remotePeerContextHandoffSurvivedAnswer)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_raw_identifiers_logged=\\(remotePeerContextHandoffRawIdentifiersLogged)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_blocks_success_without_context=\\(remotePeerContextHandoffBlocksSuccessWithoutContext)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_classifies_missing_remote_participant=\\(remotePeerContextHandoffClassifiesMissingRemoteParticipant)"))
        #expect(adapterSource.contains("remote_peer_context_handoff_classifies_simulator_limitation=\\(remotePeerContextHandoffClassifiesSimulatorLimitation)"))
        #expect(adapterSource.contains("livekit_join_result=\\(liveKitJoinResult)"))
        #expect(adapterSource.contains("livekit_join_error_bucket=\\(liveKitJoinErrorBucket)"))
        #expect(adapterSource.contains("livekit_room_connected=\\(liveKitRoomConnected)"))
        #expect(adapterSource.contains("livekit_room_disconnected=\\(liveKitRoomDisconnected)"))
        #expect(adapterSource.contains("livekit_local_participant_present=\\(liveKitLocalParticipantPresent)"))
        #expect(adapterSource.contains("local_audio_publish_requested=\\(localAudioPublishRequested)"))
        #expect(adapterSource.contains("local_audio_publish_started=\\(localAudioPublishStarted)"))
        #expect(adapterSource.contains("local_audio_publish_result=\\(localAudioPublishResult)"))
        #expect(adapterSource.contains("local_audio_publish_error_bucket=\\(localAudioPublishErrorBucket)"))
        #expect(adapterSource.contains("local_audio_publish_not_required_reason=\\(localAudioPublishNotRequiredReason)"))
        #expect(adapterSource.contains("microphone_permission_result=\\(microphonePermissionResult)"))
        #expect(adapterSource.contains("microphone_permission_not_required_reason=\\(microphonePermissionNotRequiredReason)"))
        #expect(adapterSource.contains("audio_route_available=\\(audioRouteAvailable)"))
        #expect(adapterSource.contains("audio_route_result=\\(audioRouteResult)"))
        #expect(adapterSource.contains("remote_peer_kind=\\(remotePeerKind)"))
        #expect(adapterSource.contains("remote_peer_physical_device=\\(remotePeerPhysicalDevice)"))
        #expect(adapterSource.contains("simulator_assisted_remote_audio_proof=\\(simulatorAssistedRemoteAudioProof)"))
        #expect(adapterSource.contains("production_like_two_physical_device_proof=\\(productionLikeTwoPhysicalDeviceProof)"))
        #expect(adapterSource.contains("second_device_remote_audio_readiness=\\(secondDeviceRemoteAudioReadiness)"))
        #expect(adapterSource.contains("remote_audio_liveness_limitation=\\(remoteAudioLivenessLimitation)"))
        #expect(adapterSource.contains("livekit_remote_participant_seen=\\(liveKitRemoteParticipantSeen)"))
        #expect(adapterSource.contains("livekit_remote_participant_count_bucket=\\(liveKitRemoteParticipantCountBucket)"))
        #expect(adapterSource.contains("livekit_remote_audio_track_subscribed=\\(liveKitRemoteAudioTrackSubscribed)"))
        #expect(adapterSource.contains("livekit_remote_audio_track_unmuted=\\(liveKitRemoteAudioTrackUnmuted)"))
        #expect(adapterSource.contains("livekit_remote_audio_level_observed=\\(liveKitRemoteAudioLevelObserved)"))
        #expect(adapterSource.contains("livekit_audio_liveness_observed=\\(liveKitAudioLivenessObserved)"))
        #expect(adapterSource.contains("livekit_audio_liveness_result=\\(liveKitAudioLivenessResult)"))
        #expect(adapterSource.contains("livekit_audio_liveness_error_bucket=\\(liveKitAudioLivenessErrorBucket)"))
        #expect(adapterSource.contains("remote_audio_liveness_result=\\(liveKitAudioLivenessResult)"))
        #expect(adapterSource.contains("remote_audio_liveness_error_bucket=\\(liveKitAudioLivenessErrorBucket)"))
        #expect(adapterSource.contains("receiver_remote_audio_observer_bound_to_retained_room=\\(receiverRemoteAudioObserverBoundToRetainedRoom)"))
        #expect(adapterSource.contains("receiver_remote_audio_observer_bound_to_connected_room=\\(receiverRemoteAudioObserverBoundToConnectedRoom)"))
        #expect(adapterSource.contains("receiver_remote_audio_observer_attached_after_participant_seen=\\(receiverRemoteAudioObserverAttachedAfterParticipantSeen)"))
        #expect(adapterSource.contains("receiver_remote_audio_subscription_repair_present=\\(receiverRemoteAudioSubscriptionRepairPresent)"))
        #expect(adapterSource.contains("receiver_remote_audio_subscription_repair_debug_only=\\(receiverRemoteAudioSubscriptionRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_remote_audio_subscription_raw_identifiers_logged=\\(receiverRemoteAudioSubscriptionRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_remote_audio_auto_subscribe_enabled=\\(receiverRemoteAudioAutoSubscribeEnabled)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_observation_repair_present=\\(receiverRemoteAudioPublicationObservationRepairPresent)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_observation_repair_debug_only=\\(receiverRemoteAudioPublicationObservationRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_observation_raw_identifiers_logged=\\(receiverRemoteAudioPublicationObservationRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_snapshot_requested=\\(receiverRemoteAudioPublicationSnapshotRequested)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_snapshot_completed=\\(receiverRemoteAudioPublicationSnapshotCompleted)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_snapshot_count_bucket=\\(receiverRemoteAudioPublicationSnapshotCountBucket)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_snapshot_audio_count_bucket=\\(receiverRemoteAudioPublicationSnapshotAudioCountBucket)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_seen_via_snapshot=\\(receiverRemoteAudioPublicationSeenViaSnapshot)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_seen_via_callback=\\(receiverRemoteAudioPublicationSeenViaCallback)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_seen_via_replay=\\(receiverRemoteAudioPublicationSeenViaReplay)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_seen=\\(receiverRemoteAudioPublicationSeen)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_observation_final_classification=\\(receiverRemoteAudioPublicationObservationFinalClassification)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_subscribed_state_bucket=\\(receiverRemoteAudioPublicationSubscribedStateBucket)"))
        #expect(adapterSource.contains("receiver_remote_audio_explicit_subscribe_requested=\\(receiverRemoteAudioExplicitSubscribeRequested)"))
        #expect(adapterSource.contains("receiver_remote_audio_explicit_subscribe_request_result=\\(receiverRemoteAudioExplicitSubscribeRequestResult)"))
        #expect(adapterSource.contains("receiver_remote_audio_explicit_subscribe_result=\\(receiverRemoteAudioExplicitSubscribeResult)"))
        #expect(adapterSource.contains("receiver_remote_audio_explicit_subscribe_confirmed=\\(receiverRemoteAudioExplicitSubscribeConfirmed)"))
        #expect(adapterSource.contains("receiver_remote_audio_subscription_callback_seen=\\(receiverRemoteAudioSubscriptionCallbackSeen)"))
        #expect(adapterSource.contains("receiver_remote_audio_track_subscribed=\\(receiverRemoteAudioTrackSubscribed)"))
        #expect(adapterSource.contains("receiver_remote_audio_track_unmuted=\\(receiverRemoteAudioTrackUnmuted)"))
        #expect(adapterSource.contains("receiver_remote_audio_subscription_wait_started=\\(receiverRemoteAudioSubscriptionWaitStarted)"))
        #expect(adapterSource.contains("receiver_remote_audio_subscription_wait_completed=\\(receiverRemoteAudioSubscriptionWaitCompleted)"))
        #expect(adapterSource.contains("receiver_remote_audio_subscription_wait_timeout=\\(receiverRemoteAudioSubscriptionWaitTimeout)"))
        #expect(adapterSource.contains("receiver_remote_audio_subscription_final_classification=\\(receiverRemoteAudioSubscriptionFinalClassification)"))
        #expect(adapterSource.contains("receiver_remote_audio_level_observed=\\(receiverRemoteAudioLevelObserved)"))
        #expect(adapterSource.contains("receiver_remote_audio_liveness_observed=\\(receiverRemoteAudioLivenessObserved)"))
        #expect(adapterSource.contains("receiver_remote_audio_liveness_wait_started=\\(receiverRemoteAudioLivenessWaitStarted)"))
        #expect(adapterSource.contains("receiver_remote_audio_liveness_wait_completed=\\(receiverRemoteAudioLivenessWaitCompleted)"))
        #expect(adapterSource.contains("receiver_remote_audio_liveness_wait_timeout=\\(receiverRemoteAudioLivenessWaitTimeout)"))
        #expect(adapterSource.contains("receiver_remote_audio_liveness_final_classification=\\(receiverRemoteAudioLivenessFinalClassification)"))
        #expect(adapterSource.contains("sender_local_audio_publish_requested=\\(senderLocalAudioPublishRequested)"))
        #expect(adapterSource.contains("sender_local_audio_publish_allowed=\\(senderLocalAudioPublishAllowed)"))
        #expect(adapterSource.contains("sender_local_audio_publish_result=\\(senderLocalAudioPublishResult)"))
        #expect(adapterSource.contains("sender_local_audio_muted_state_bucket=\\(senderLocalAudioMutedStateBucket)"))
        #expect(adapterSource.contains("sender_audio_session_activation_observed=\\(senderAudioSessionActivationObserved)"))
        #expect(adapterSource.contains("sender_microphone_permission_requested=\\(senderMicrophonePermissionRequested)"))
        #expect(adapterSource.contains("sender_microphone_permission_result_bucket=\\(senderMicrophonePermissionResultBucket)"))
        #expect(adapterSource.contains("video_enabled=\\(videoEnabled)"))
        #expect(adapterSource.contains("livekit_cleanup_requested=\\(liveKitCleanupRequested)"))
        #expect(adapterSource.contains("livekit_cleanup_completed=\\(liveKitCleanupCompleted)"))
        #expect(adapterSource.contains("livekit_cleanup_result=\\(liveKitCleanupResult)"))

        #expect(adapterSource.contains("var remoteAudioLivenessDiagnosticsPresent = true"))
        #expect(adapterSource.contains("var remoteAudioLivenessDiagnosticsDebugOnly = true"))
        #expect(adapterSource.contains("var remoteAudioLivenessDiagnosticsAudioOnly = true"))
        #expect(adapterSource.contains("var remoteAudioLivenessDiagnosticsVideoAllowed = false"))
        #expect(adapterSource.contains("var remoteAudioLivenessDiagnosticsMatrixEventsAllowed = false"))
        #expect(adapterSource.contains("var remoteAudioLivenessDiagnosticsRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("var remoteAudioPublishLivenessRepairPresent = true"))
        #expect(adapterSource.contains("var remoteAudioPublishLivenessRepairDebugOnly = true"))
        #expect(adapterSource.contains("var remoteAudioPublishLivenessRepairRequiresLiveKitJoinSuccess = true"))
        #expect(adapterSource.contains("var remoteAudioPublishLivenessRepairNoVideo = true"))
        #expect(adapterSource.contains("var remoteAudioPublishLivenessRepairNoMatrixEvents = true"))
        #expect(adapterSource.contains("var remoteAudioPublishLivenessRepairRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("var remoteAudioTrackLivenessProofPresent = true"))
        #expect(adapterSource.contains("var remoteAudioTrackLivenessProofDebugOnly = true"))
        #expect(adapterSource.contains("var remoteAudioTrackLivenessRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("var receiverAudioObserverLeaseBindingRepairPresent = true"))
        #expect(adapterSource.contains("var receiverAudioObserverLeaseBindingRepairDebugOnly = true"))
        #expect(adapterSource.contains("var receiverAudioObserverLeaseBindingRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("var receiverRemoteAudioSubscriptionRepairPresent = true"))
        #expect(adapterSource.contains("var receiverRemoteAudioSubscriptionRepairDebugOnly = true"))
        #expect(adapterSource.contains("var receiverRemoteAudioSubscriptionRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("var receiverRemoteAudioAutoSubscribeEnabled = false"))
        #expect(adapterSource.contains("var receiverRemoteAudioPublicationObservationRepairPresent = true"))
        #expect(adapterSource.contains("var receiverRemoteAudioPublicationObservationRepairDebugOnly = true"))
        #expect(adapterSource.contains("var receiverRemoteAudioPublicationObservationRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("var receiverRemoteAudioPublicationObservationFinalClassification = \"not_started\""))
        #expect(adapterSource.contains("var videoEnabled = false"))
        #expect(adapterSource.contains("var remotePeerContextHandoffPresent = true"))
        #expect(adapterSource.contains("var remotePeerContextHandoffDebugOnly = true"))
        #expect(adapterSource.contains("var remotePeerContextHandoffSource = \"unknown_redacted\""))
        #expect(adapterSource.contains("var remotePeerContextHandoffArmedBeforeAPNs = false"))
        #expect(adapterSource.contains("var remotePeerContextHandoffReceivedByRuntime = false"))
        #expect(adapterSource.contains("var remotePeerContextHandoffSurvivedPushKit = false"))
        #expect(adapterSource.contains("var remotePeerContextHandoffSurvivedAnswer = false"))
        #expect(adapterSource.contains("var remotePeerContextHandoffRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("var remotePeerContextHandoffBlocksSuccessWithoutContext = true"))
        #expect(adapterSource.contains("var remotePeerContextHandoffClassifiesMissingRemoteParticipant = true"))
        #expect(adapterSource.contains("var remotePeerContextHandoffClassifiesSimulatorLimitation = true"))
        #expect(adapterSource.contains("var liveKitJoinResult = \"not_requested\""))
        #expect(adapterSource.contains("var localAudioPublishResult = \"not_requested\""))
        #expect(adapterSource.contains("var localAudioPublishNotRequiredReason = \"none\""))
        #expect(adapterSource.contains("var microphonePermissionResult = \"not_requested_or_not_required_redacted\""))
        #expect(adapterSource.contains("var remotePeerKind = \"unknown_redacted\""))
        #expect(adapterSource.contains("var remotePeerPhysicalDevice = \"unknown\""))
        #expect(adapterSource.contains("var simulatorAssistedRemoteAudioProof = false"))
        #expect(adapterSource.contains("var productionLikeTwoPhysicalDeviceProof = false"))
        #expect(adapterSource.contains("var secondDeviceRemoteAudioReadiness = \"unknown_redacted\""))
        #expect(adapterSource.contains("var remoteAudioLivenessLimitation = \"unknown_redacted\""))
        #expect(adapterSource.contains("var liveKitAudioLivenessResult = \"not_observed_redacted\""))
        #expect(adapterSource.contains("var liveKitCleanupResult = \"not_requested\""))

        #expect(adapterSource.contains("camera_permission_requested=\\(cameraPermissionRequested)"))
        #expect(adapterSource.contains("matrix_event_emit_requested=\\(matrixEventEmitRequested)"))
        #expect(adapterSource.contains("real_call_flow_started=\\(realCallFlowStarted)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_repeated=\\(controlledConnectFirstAttemptRepeated)"))
        #expect(!adapterSource.contains("remoteAudioLivenessDiagnosticsRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("remoteAudioPublishLivenessRepairRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("receiverAudioObserverLeaseBindingRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("receiverRemoteAudioSubscriptionRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("receiverRemoteAudioPublicationObservationRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("remotePeerContextHandoffRawIdentifiersLogged = true"))
    }

    @Test
    func remoteAudioLivenessDiagnosticsClassifyJoinPublishMicLivenessAndCleanup() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("mutating func refreshRemoteAudioLivenessDiagnostics()"))
        #expect(adapterSource.contains("remoteAudioLivenessDiagnosticsDebugOnly = true"))
        #expect(adapterSource.contains("remoteAudioLivenessDiagnosticsAudioOnly = true"))
        #expect(adapterSource.contains("remoteAudioLivenessDiagnosticsVideoAllowed = controlledConnectFirstAttemptVideoAllowed"))
        #expect(adapterSource.contains("remoteAudioLivenessDiagnosticsMatrixEventsAllowed = controlledConnectFirstAttemptMatrixEventsAllowed"))
        #expect(adapterSource.contains("remoteAudioLivenessDiagnosticsRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("remoteAudioPublishLivenessRepairPresent = true"))
        #expect(adapterSource.contains("remoteAudioPublishLivenessRepairDebugOnly = true"))
        #expect(adapterSource.contains("remoteAudioPublishLivenessRepairRequiresLiveKitJoinSuccess = true"))
        #expect(adapterSource.contains("remoteAudioPublishLivenessRepairNoVideo = !controlledConnectFirstAttemptVideoAllowed && !cameraPermissionRequested"))
        #expect(adapterSource.contains("remoteAudioPublishLivenessRepairNoMatrixEvents = !controlledConnectFirstAttemptMatrixEventsAllowed && !matrixEventEmitRequested"))
        #expect(adapterSource.contains("remoteAudioPublishLivenessRepairRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("liveKitJoinResult = controlledConnectFirstAttemptResult == \"success_redacted\" ? \"success_redacted\" : \"failed_redacted\""))
        #expect(adapterSource.contains("liveKitJoinErrorBucket = controlledConnectFirstAttemptResult == \"success_redacted\" ? \"none\" : controlledConnectFirstAttemptErrorBucket"))
        #expect(adapterSource.contains("liveKitJoinResult = \"not_requested\""))
        #expect(adapterSource.contains("liveKitRoomConnected = controlledConnectFirstAttemptResult == \"success_redacted\""))
        #expect(adapterSource.contains("liveKitLocalParticipantPresent = liveKitRoomConnected"))
        #expect(adapterSource.contains("localAudioPublishResult = \"not_required_redacted\""))
        #expect(adapterSource.contains("localAudioPublishNotRequiredReason = \"receive_only_audio_connect_redacted\""))
        #expect(adapterSource.contains("localAudioPublishResult = \"blocked_redacted\""))
        #expect(adapterSource.contains("localAudioPublishErrorBucket = \"livekit_join_not_success_redacted\""))
        #expect(adapterSource.contains("microphonePermissionResult = microphonePermissionRequested ? \"requested_redacted\" : \"not_requested_or_not_required_redacted\""))
        #expect(adapterSource.contains("microphonePermissionNotRequiredReason = microphonePermissionRequested ? \"requested_redacted\" : \"receive_only_audio_session_redacted\""))
        #expect(adapterSource.contains("audioRouteAvailable = callKitProviderDidActivateAudioSession"))
        #expect(adapterSource.contains("audioRouteResult = audioRouteAvailable ? \"available_redacted\" : \"not_observed_redacted\""))
        #expect(adapterSource.contains("liveKitCleanupRequested = disconnectCleanupDiagnosticsLiveKitCleanupRequested"))
        #expect(adapterSource.contains("liveKitCleanupCompleted = disconnectCleanupDiagnosticsLiveKitCleanupCompleted"))
        #expect(adapterSource.contains("liveKitCleanupResult = liveKitCleanupCompleted ? \"completed_redacted\" : (liveKitCleanupRequested ? \"not_completed_redacted\" : \"not_requested\")"))

        #expect(adapterSource.contains("mutating func recordRemoteAudioLivenessJoinResult(succeeded: Bool, errorBucket: String = \"none\")"))
        #expect(adapterSource.contains("liveKitJoinResult = succeeded ? \"success_redacted\" : \"failed_redacted\""))
        #expect(adapterSource.contains("liveKitJoinErrorBucket = succeeded ? \"none\" : errorBucket"))
        #expect(adapterSource.contains("liveKitRoomConnected = succeeded"))
        #expect(adapterSource.contains("liveKitLocalParticipantPresent = succeeded"))

        #expect(adapterSource.contains("mutating func recordReceiverRemoteAudioExplicitSubscribeResult(_ result: Result<Void, DirectCallMediaError>)"))
        #expect(adapterSource.contains("mutating func recordReceiverRemoteAudioExplicitSubscribeStarted()"))
        #expect(adapterSource.contains("receiverRemoteAudioExplicitSubscribeRequested = true"))
        #expect(adapterSource.contains("receiverRemoteAudioSubscriptionWaitStarted = true"))
        #expect(adapterSource.contains("receiverRemoteAudioExplicitSubscribeRequestResult = \"pending_redacted\""))
        #expect(adapterSource.contains("receiverRemoteAudioExplicitSubscribeRequestResult = \"success_redacted\""))
        #expect(adapterSource.contains("receiverRemoteAudioExplicitSubscribeRequestResult = \"failed_redacted\""))
        #expect(adapterSource.contains("receiverRemoteAudioExplicitSubscribeResult = \"success_redacted\""))
        #expect(adapterSource.contains("receiverRemoteAudioExplicitSubscribeResult = \"failed_redacted\""))
        #expect(adapterSource.contains("mutating func recordReceiverRemoteAudioSubscriptionCallback()"))
        #expect(adapterSource.contains("receiverRemoteAudioSubscriptionCallbackSeen = true"))
        #expect(adapterSource.contains("receiverRemoteAudioExplicitSubscribeConfirmed = true"))
        #expect(adapterSource.contains("receiverRemoteAudioSubscriptionWaitCompleted = true"))

        #expect(adapterSource.contains("mutating func recordLocalAudioPublishResult(requested: Bool,"))
        #expect(adapterSource.contains("localAudioPublishRequested = requested"))
        #expect(adapterSource.contains("localAudioPublishStarted = requested && started"))
        #expect(adapterSource.contains("localAudioPublishResult = requested ? (succeeded ? \"success_redacted\" : \"failed_redacted\") : \"not_required_redacted\""))
        #expect(adapterSource.contains("localAudioPublishErrorBucket = requested && !succeeded ? errorBucket : \"none\""))
        #expect(adapterSource.contains("localAudioPublishNotRequiredReason = requested ? \"none\" : notRequiredReason"))

        #expect(adapterSource.contains("mutating func recordMicrophonePermissionResult(requested: Bool, notRequiredReason: String)"))
        #expect(adapterSource.contains("microphonePermissionResult = requested ? \"requested_redacted\" : \"not_requested_or_not_required_redacted\""))
        #expect(adapterSource.contains("microphonePermissionNotRequiredReason = requested ? \"requested_redacted\" : notRequiredReason"))

        #expect(adapterSource.contains("mutating func recordRemoteAudioPeerClassification(peerKind: String,"))
        #expect(adapterSource.contains("remotePeerKind = peerKind"))
        #expect(adapterSource.contains("remotePeerPhysicalDevice = physicalDevice"))
        #expect(adapterSource.contains("simulatorAssistedRemoteAudioProof = simulatorAssisted"))
        #expect(adapterSource.contains("productionLikeTwoPhysicalDeviceProof = physicalDevice == \"true\" && !simulatorAssisted"))
        #expect(adapterSource.contains("remoteAudioLivenessLimitation = simulatorAssisted ? \"simulator_assisted_redacted\" : limitation"))

        #expect(adapterSource.contains("mutating func recordRemoteAudioLivenessObservation(participantSeen: Bool"))
        #expect(adapterSource.contains("audioPublicationSource: String = \"callback_redacted\""))
        #expect(adapterSource.contains("recordReceiverRemoteAudioPublicationObservation(audioPublicationSeen: audioPublicationSeen,"))
        #expect(adapterSource.contains("mutating func recordReceiverRemoteAudioPublicationObservation(audioPublicationSeen: Bool,"))
        #expect(adapterSource.contains("receiverRemoteAudioPublicationSeenViaCallback = true"))
        #expect(adapterSource.contains("receiverRemoteAudioPublicationSeenViaSnapshot = true"))
        #expect(adapterSource.contains("receiverRemoteAudioPublicationSeenViaReplay = receiverRemoteAudioPublicationSeenViaReplay || !wasAlreadySeen"))
        #expect(adapterSource.contains("mutating func refreshReceiverRemoteAudioPublicationObservationClassification()"))
        #expect(adapterSource.contains("liveKitRemoteParticipantSeen = participantSeen"))
        #expect(adapterSource.contains("liveKitRemoteParticipantCountBucket = participantCountBucket"))
        #expect(adapterSource.contains("liveKitRemoteAudioTrackSubscribed = liveKitRemoteAudioTrackSubscribed || audioTrackSubscribed"))
        #expect(adapterSource.contains("liveKitRemoteAudioTrackUnmuted = liveKitRemoteAudioTrackUnmuted || audioTrackUnmuted"))
        #expect(adapterSource.contains("liveKitRemoteAudioLevelObserved = liveKitRemoteAudioLevelObserved || audioLevelObserved || livenessObserved"))
        #expect(adapterSource.contains("liveKitAudioLivenessObserved = liveKitAudioLivenessObserved || livenessObserved"))
        #expect(adapterSource.contains("liveKitAudioLivenessResult = liveKitAudioLivenessObserved ? \"success_redacted\" : \"not_observed_redacted\""))
        #expect(adapterSource.contains("liveKitAudioLivenessErrorBucket = \"remote_participant_missing_redacted\""))
        #expect(adapterSource.contains("liveKitAudioLivenessErrorBucket = \"remote_audio_track_missing_redacted\""))
        #expect(adapterSource.contains("liveKitAudioLivenessErrorBucket = errorBucket"))
        #expect(adapterSource.contains("shouldCompleteRemoteParticipantObservationAfterRemoteAudioUpdate"))
        #expect(adapterSource.contains("mutating func recordReceiverAudioObserverLeaseBinding(leasePresent: Bool,"))
        #expect(adapterSource.contains("mutating func refreshReceiverAudioObserverLeaseBindingDiagnostics()"))
        #expect(adapterSource.contains("var shouldDeferReceiverConnectedSessionLeaseReleaseForAudioTerminal: Bool"))
        #expect(adapterSource.contains("recordReceiverConnectedSessionLeaseReleaseDeferredForAudioTerminal(reason: reason)"))
        #expect(adapterSource.contains("receiverAudioObserverLeasePresentDuringSubscriptionWait"))
        #expect(adapterSource.contains("receiverAudioObserverBoundToSameClientAsReceiverJoin"))
        #expect(adapterSource.contains("receiverAudioObserverBoundToSameClientAsParticipantCallback"))

        #expect(adapterSource.contains("refreshRemoteAudioLivenessDiagnostics()"))
        #expect(adapterSource.contains("summary.refreshRemoteAudioLivenessDiagnostics()"))
    }

    @Test
    func remoteParticipantPresenceRepairClassifiesSenderReadinessAndReceiverObserverSafely() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("remote_participant_presence_repair_present=\\(remoteParticipantPresenceRepairPresent)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_debug_only=\\(remoteParticipantPresenceRepairDebugOnly)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_requires_two_physical_devices=\\(remoteParticipantPresenceRepairRequiresTwoPhysicalDevices)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_requires_same_room=\\(remoteParticipantPresenceRepairRequiresSameRoom)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_requires_sender_livekit_readiness=\\(remoteParticipantPresenceRepairRequiresSenderLiveKitReadiness)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_sender_join_path_present=\\(remoteParticipantPresenceRepairSenderJoinPathPresent)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_sender_join_default_disabled=\\(remoteParticipantPresenceRepairSenderJoinDefaultDisabled)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_receiver_observer_present=\\(remoteParticipantPresenceRepairReceiverObserverPresent)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_same_livekit_room_required=\\(remoteParticipantPresenceRepairSameLiveKitRoomRequired)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_classifies_sender_not_joined=\\(remoteParticipantPresenceRepairClassifiesSenderNotJoined)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_classifies_remote_missing=\\(remoteParticipantPresenceRepairClassifiesRemoteMissing)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_classifies_remote_seen=\\(remoteParticipantPresenceRepairClassifiesRemoteSeen)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_no_video=\\(remoteParticipantPresenceRepairNoVideo)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_no_matrix_events=\\(remoteParticipantPresenceRepairNoMatrixEvents)"))
        #expect(adapterSource.contains("remote_participant_presence_repair_raw_identifiers_logged=\\(remoteParticipantPresenceRepairRawIdentifiersLogged)"))

        #expect(adapterSource.contains("second_physical_sender_livekit_readiness_present=\\(secondPhysicalSenderLiveKitReadinessPresent)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_readiness_debug_only=\\(secondPhysicalSenderLiveKitReadinessDebugOnly)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_readiness_default_disabled=\\(secondPhysicalSenderLiveKitReadinessDefaultDisabled)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_readiness_matrix_session_ready=\\(secondPhysicalSenderLiveKitReadinessMatrixSessionReady)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_readiness_same_room_ready=\\(secondPhysicalSenderLiveKitReadinessSameRoomReady)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_readiness_credentials_ready=\\(secondPhysicalSenderLiveKitReadinessCredentialsReady)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_join_path_present=\\(secondPhysicalSenderLiveKitJoinPathPresent)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_join_path_default_disabled=\\(secondPhysicalSenderLiveKitJoinPathDefaultDisabled)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_join_path_audio_only=\\(secondPhysicalSenderLiveKitJoinPathAudioOnly)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_join_path_video_allowed=\\(secondPhysicalSenderLiveKitJoinPathVideoAllowed)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_join_path_matrix_events_allowed=\\(secondPhysicalSenderLiveKitJoinPathMatrixEventsAllowed)"))
        #expect(adapterSource.contains("second_physical_sender_livekit_join_path_raw_credentials_logged=\\(secondPhysicalSenderLiveKitJoinPathRawCredentialsLogged)"))

        #expect(adapterSource.contains("receiver_remote_participant_observer_present=\\(receiverRemoteParticipantObserverPresent)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_debug_only=\\(receiverRemoteParticipantObserverDebugOnly)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_started=\\(receiverRemoteParticipantObserverStarted)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_result=\\(receiverRemoteParticipantObserverResult)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_error_bucket=\\(receiverRemoteParticipantObserverErrorBucket)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_timeout_bucket=\\(receiverRemoteParticipantObserverTimeoutBucket)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_remote_seen=\\(receiverRemoteParticipantObserverRemoteSeen)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_audio_track_seen=\\(receiverRemoteParticipantObserverAudioTrackSeen)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_liveness_seen=\\(receiverRemoteParticipantObserverLivenessSeen)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_raw_identifiers_logged=\\(receiverRemoteParticipantObserverRawIdentifiersLogged)"))

        #expect(adapterSource.contains("var remoteParticipantPresenceRepairPresent = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairDebugOnly = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairRequiresTwoPhysicalDevices = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairRequiresSameRoom = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairRequiresSenderLiveKitReadiness = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairSenderJoinPathPresent = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairSenderJoinDefaultDisabled = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairReceiverObserverPresent = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairSameLiveKitRoomRequired = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairClassifiesSenderNotJoined = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairClassifiesRemoteMissing = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairClassifiesRemoteSeen = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairNoVideo = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairNoMatrixEvents = true"))
        #expect(adapterSource.contains("var remoteParticipantPresenceRepairRawIdentifiersLogged = false"))

        #expect(adapterSource.contains("var secondPhysicalSenderLiveKitReadinessPresent = true"))
        #expect(adapterSource.contains("var secondPhysicalSenderLiveKitReadinessDebugOnly = true"))
        #expect(adapterSource.contains("var secondPhysicalSenderLiveKitReadinessDefaultDisabled = true"))
        #expect(adapterSource.contains("var secondPhysicalSenderLiveKitJoinPathPresent = true"))
        #expect(adapterSource.contains("var secondPhysicalSenderLiveKitJoinPathDefaultDisabled = true"))
        #expect(adapterSource.contains("var secondPhysicalSenderLiveKitJoinPathAudioOnly = true"))
        #expect(adapterSource.contains("var secondPhysicalSenderLiveKitJoinPathVideoAllowed = false"))
        #expect(adapterSource.contains("var secondPhysicalSenderLiveKitJoinPathMatrixEventsAllowed = false"))
        #expect(adapterSource.contains("var secondPhysicalSenderLiveKitJoinPathRawCredentialsLogged = false"))

        #expect(adapterSource.contains("var receiverRemoteParticipantObserverPresent = true"))
        #expect(adapterSource.contains("var receiverRemoteParticipantObserverDebugOnly = true"))
        #expect(adapterSource.contains("var receiverRemoteParticipantObserverResult = \"not_observed_redacted\""))
        #expect(adapterSource.contains("var receiverRemoteParticipantObserverErrorBucket = \"sender_not_joined_or_remote_missing_redacted\""))
        #expect(adapterSource.contains("var receiverRemoteParticipantObserverRawIdentifiersLogged = false"))

        #expect(adapterSource.contains("mutating func refreshRemoteParticipantPresenceRepairDiagnostics()"))
        #expect(adapterSource.contains("remoteParticipantPresenceRepairNoVideo = !controlledConnectFirstAttemptVideoAllowed && !cameraPermissionRequested"))
        #expect(adapterSource.contains("remoteParticipantPresenceRepairNoMatrixEvents = !controlledConnectFirstAttemptMatrixEventsAllowed && !matrixEventEmitRequested"))
        #expect(adapterSource.contains("secondPhysicalSenderLiveKitReadinessMatrixSessionReady = senderLiveKitReadinessHookMatrixSessionReady"))
        #expect(adapterSource.contains("secondPhysicalSenderLiveKitReadinessSameRoomReady = senderLiveKitReadinessHookSameRoomReady"))
        #expect(adapterSource.contains("secondPhysicalSenderLiveKitReadinessCredentialsReady = senderLiveKitReadinessHookCredentialsReady"))
        #expect(adapterSource.contains("secondPhysicalSenderLiveKitJoinPathDefaultDisabled = senderSideLiveKitJoinHookDefaultDisabled"))
        #expect(adapterSource.contains("secondPhysicalSenderLiveKitJoinPathAudioOnly = senderSideLiveKitJoinHookAudioOnly"))
        #expect(adapterSource.contains("secondPhysicalSenderLiveKitJoinPathVideoAllowed = senderSideLiveKitJoinHookVideoAllowed"))
        #expect(adapterSource.contains("secondPhysicalSenderLiveKitJoinPathMatrixEventsAllowed = senderSideLiveKitJoinHookMatrixEventsAllowed"))
        #expect(adapterSource.contains("secondPhysicalSenderLiveKitJoinPathRawCredentialsLogged = senderSideLiveKitJoinHookRawCredentialsLogged"))
        #expect(adapterSource.contains("receiverRemoteParticipantObserverStarted = liveKitJoinResult == \"success_redacted\" || liveKitJoinRequested"))
        #expect(adapterSource.contains("receiverRemoteParticipantObserverRemoteSeen = liveKitRemoteParticipantSeen"))
        #expect(adapterSource.contains("receiverRemoteParticipantObserverAudioTrackSeen = liveKitRemoteAudioTrackSubscribed"))
        #expect(adapterSource.contains("receiverRemoteParticipantObserverLivenessSeen = liveKitAudioLivenessObserved"))
        #expect(adapterSource.contains("refreshReceiverRemoteParticipantObserverClassification()"))
        #expect(adapterSource.contains("refreshRemoteParticipantPresenceRepairDiagnostics()"))

        #expect(adapterSource.contains("camera_permission_requested=\\(cameraPermissionRequested)"))
        #expect(adapterSource.contains("matrix_event_emit_requested=\\(matrixEventEmitRequested)"))
        #expect(adapterSource.contains("real_call_flow_started=\\(realCallFlowStarted)"))
        #expect(!adapterSource.contains("remoteParticipantPresenceRepairRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitReadinessHookRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("secondPhysicalSenderLiveKitJoinPathRawCredentialsLogged = true"))
        #expect(!adapterSource.contains("receiverRemoteParticipantObserverRawIdentifiersLogged = true"))
    }

    @Test
    func receiverVoIPPushDeliveryTriageProofClassifiesAcceptedAPNsWithoutCallback() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("receiverVoIPPushDeliveryTriageURLHookPath = \"/direct-call/receiver-voip-push-delivery-triage\""))
        #expect(adapterSource.contains("recordReceiverVoIPPushDeliveryTriageURLHook(components)"))
        #expect(adapterSource.contains("receiver_voip_push_delivery_triage_present=\\(receiverVoIPPushDeliveryTriagePresent)"))
        #expect(adapterSource.contains("receiver_voip_push_delivery_triage_debug_only=\\(receiverVoIPPushDeliveryTriageDebugOnly)"))
        #expect(adapterSource.contains("receiver_voip_push_delivery_triage_raw_identifiers_logged=\\(receiverVoIPPushDeliveryTriageRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_pushkit_token_readiness_repair_present=\\(receiverPushKitTokenReadinessRepairPresent)"))
        #expect(adapterSource.contains("receiver_pushkit_token_readiness_repair_debug_only=\\(receiverPushKitTokenReadinessRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_pushkit_token_readiness_repair_raw_identifiers_logged=\\(receiverPushKitTokenReadinessRepairRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_pushkit_registration_requested_before_apns=\\(receiverPushKitRegistrationRequestedBeforeAPNs)"))
        #expect(adapterSource.contains("receiver_pushkit_token_callback_seen_before_apns=\\(receiverPushKitTokenCallbackSeenBeforeAPNs)"))
        #expect(adapterSource.contains("receiver_pushkit_token_present_before_apns=\\(receiverPushKitTokenPresentBeforeAPNs)"))
        #expect(adapterSource.contains("receiver_pushkit_token_upload_attempted_before_apns=\\(receiverPushKitTokenUploadAttemptedBeforeAPNs)"))
        #expect(adapterSource.contains("receiver_pushkit_token_upload_result_bucket=\\(receiverPushKitTokenUploadResultBucket)"))
        #expect(adapterSource.contains("receiver_pushkit_token_server_store_result_bucket=\\(receiverPushKitTokenServerStoreResultBucket)"))
        #expect(adapterSource.contains("receiver_pushkit_token_environment_bucket=\\(receiverPushKitTokenEnvironmentBucket)"))
        #expect(adapterSource.contains("receiver_pushkit_token_device_binding_expected_bucket=\\(receiverPushKitTokenDeviceBindingExpectedBucket)"))
        #expect(adapterSource.contains("receiver_pushkit_token_readiness_wait_started=\\(receiverPushKitTokenReadinessWaitStarted)"))
        #expect(adapterSource.contains("receiver_pushkit_token_readiness_wait_completed=\\(receiverPushKitTokenReadinessWaitCompleted)"))
        #expect(adapterSource.contains("receiver_pushkit_token_readiness_wait_timeout=\\(receiverPushKitTokenReadinessWaitTimeout)"))
        #expect(adapterSource.contains("receiver_pushkit_token_readiness_final_classification=\\(receiverPushKitTokenReadinessFinalClassification)"))
        #expect(adapterSource.contains("receiver_app_lifecycle_state_before_apns_bucket=\\(receiverAppLifecycleStateBeforeAPNsBucket)"))
        #expect(adapterSource.contains("receiver_app_proof_generation_before_apns=\\(receiverAppProofGenerationBeforeAPNs)"))
        #expect(adapterSource.contains("receiver_app_proof_generation_after_apns_changed=\\(receiverAppProofGenerationAfterAPNsChanged)"))
        #expect(adapterSource.contains("receiver_voip_push_callback_seen_after_apns=\\(receiverVoIPPushCallbackSeenAfterAPNs)"))
        #expect(adapterSource.contains("receiver_callkit_report_requested_after_apns=\\(receiverCallKitReportRequestedAfterAPNs)"))
        #expect(adapterSource.contains("receiver_callkit_answer_available_after_apns=\\(receiverCallKitAnswerAvailableAfterAPNs)"))
        #expect(adapterSource.contains("apns_provider_acceptance_result_bucket=\\(apnsProviderAcceptanceResultBucket)"))
        #expect(adapterSource.contains("apns_delivery_callback_missing_after_acceptance=\\(apnsDeliveryCallbackMissingAfterAcceptance)"))
        #expect(adapterSource.contains("receiver_voip_push_delivery_final_classification=\\(receiverVoIPPushDeliveryFinalClassification)"))
        #expect(adapterSource.contains("summary.refreshReceiverVoIPPushDeliveryTriage(uploadProof: latestUploadSummary"))
        #expect(adapterSource.contains("pushkit_token_environment_bucket=\\(tokenEnvironmentBucket)"))
        #expect(adapterSource.contains("receiver_pushkit_token_missing_before_apns_redacted"))
        #expect(adapterSource.contains("receiver_pushkit_token_upload_failed_before_apns_redacted"))
        #expect(adapterSource.contains("receiver_pushkit_token_environment_mismatch_possible_redacted"))
        #expect(adapterSource.contains("receiver_pushkit_token_device_binding_unknown_redacted"))
        #expect(adapterSource.contains("apns_accepted_but_receiver_callback_missing_redacted"))
        #expect(adapterSource.contains("receiver_callkit_not_reported_after_apns_redacted"))
        #expect(adapterSource.contains("receiver_voip_push_received_redacted"))
        #expect(!adapterSource.contains("receiverPushKitTokenRaw"))
        #expect(!adapterSource.contains("apnsPayload.description"))
    }

    @Test
    func receiverPushKitTokenReadinessRepairRunsBoundedUploadSmokeBeforeAPNs() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let classificationStart = try #require(adapterSource.range(of: "private static func receiverPushKitTokenReadinessClassification(summary: SalemXVoIPPushReceiptProofSummary)")?.lowerBound)
        let classificationEnd = try #require(adapterSource.range(of: "mutating func recordPendingMetadataReferenceRepairProof", range: classificationStart..<adapterSource.endIndex)?.lowerBound)
        let classificationSource = String(adapterSource[classificationStart..<classificationEnd])

        #expect(adapterSource.contains("receiverPushKitTokenReadinessURLHookPath = \"/direct-call/receiver-pushkit-token-readiness\""))
        #expect(adapterSource.contains("startReceiverPushKitTokenReadinessURLHook()"))
        #expect(adapterSource.contains("startRegistrationUploadSmokeWithCurrentSessionURLString(uploadSmokeDefaultURLString)"))
        #expect(adapterSource.contains("receiverPushKitTokenReadinessWaitTimeout: TimeInterval = 8"))
        #expect(adapterSource.contains("recordReceiverPushKitTokenReadinessProof(waitStarted: true,"))
        #expect(adapterSource.contains("receiverPushKitTokenReadinessTerminal(uploadProof: latestUploadSummary)"))
        let normalizedAdapterSourceForPushKitReadiness = adapterSource
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")

        #expect(normalizedAdapterSourceForPushKitReadiness.contains("""
        summary.refreshReceiverPushKitTokenReadiness(uploadProof:uploadProof,appStateBeforeAPNs:"unknown",waitStarted:true,waitCompleted:true,waitTimeout:false)
        """))
        #expect(adapterSource.contains("proofLastUpdatedBy = \"receiver_pushkit_token_readiness\""))
        #expect(adapterSource.contains("refreshReceiverPushKitTokenReadiness(uploadProof: latestUploadSummary"))
        #expect(adapterSource.contains("receiver_pushkit_token_ready_before_apns_redacted"))
        #expect(adapterSource.contains("receiver_pushkit_registration_not_requested_before_apns_redacted"))
        #expect(adapterSource.contains("receiver_pushkit_token_callback_missing_before_apns_redacted"))
        #expect(adapterSource.contains("receiver_pushkit_token_missing_before_apns_redacted"))
        #expect(adapterSource.contains("receiver_pushkit_token_upload_failed_before_apns_redacted"))
        #expect(adapterSource.contains("receiver_pushkit_token_server_store_unknown_before_apns_redacted"))
        #expect(adapterSource.contains("receiver_pushkit_token_readiness_timeout_before_apns_redacted"))
        #expect(adapterSource.contains("case \"persisted\", \"persisted_redacted\", \"success_redacted\", \"redacted_match\":"))
        #expect(adapterSource.contains("case \"persisted_redacted\", \"success_redacted\", \"known_redacted\":"))
        #expect(classificationSource.contains("let serverStoreReady = Self.receiverPushKitServerStoreResultKnownSuccess(summary.receiverPushKitTokenServerStoreResultBucket)"))
        #expect(classificationSource.contains("summary.receiverPushKitTokenReadinessWaitCompleted &&"))
        #expect(classificationSource.contains("!summary.receiverPushKitTokenReadinessWaitTimeout &&"))
        #expect(classificationSource.contains("serverStoreReady &&"))
        #expect(classificationSource.contains("summary.receiverPushKitTokenUploadResultBucket == \"success_redacted\""))
        #expect(classificationSource.contains("if !summary.receiverPushKitTokenPresentBeforeAPNs"))
        #expect(classificationSource.contains("if summary.receiverPushKitTokenUploadResultBucket == \"failed_redacted\""))
        #expect(classificationSource.contains("if !serverStoreReady"))
        #expect(!classificationSource.contains("receiverPushKitTokenDeviceBindingExpectedBucket == \"expected_redacted\""))
        #expect(adapterSource.contains("voip_push_send_requested=false"))
        #expect(adapterSource.contains("apns_provider_requested=false"))
        #expect(!adapterSource.contains("receiverPushKitTokenReadinessRaw"))
        #expect(!adapterSource.contains("APNs_sent=true"))
    }

    // swiftlint:disable function_body_length
    @Test
    func remoteParticipantObservationTimingRepairRetainsReceiverUntilRuntimeTerminal() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let liveKitClientSource = try Self.sourceFile("ElementX/Sources/Services/Calls/LiveKitDirectCallClient.swift")
        let liveKitMediaEngineSource = try Self.sourceFile("ElementX/Sources/Services/Calls/LiveKitDirectCallMediaEngine.swift")
        let runtimeSnapshotStart = try #require(adapterSource.range(of: "private static func applyRuntimeSnapshots(to baseSummary: inout SalemXVoIPPushReceiptProofSummary)")?.lowerBound)
        let runtimeSnapshotEnd = try #require(adapterSource.range(of: "private static func recordVoIPPushReceipt(_ payload", range: runtimeSnapshotStart..<adapterSource.endIndex)?.lowerBound)
        let runtimeSnapshotSource = String(adapterSource[runtimeSnapshotStart..<runtimeSnapshotEnd])
        let remoteAudioClassificationStart = try #require(adapterSource.range(of: "mutating func refreshRemoteAudioTrackLivenessClassification()")?.lowerBound)
        let remoteAudioClassificationEnd = try #require(adapterSource.range(of: "mutating func refreshRemoteParticipantPresenceRepairDiagnostics()", range: remoteAudioClassificationStart..<adapterSource.endIndex)?.lowerBound)
        let remoteAudioClassificationSource = String(adapterSource[remoteAudioClassificationStart..<remoteAudioClassificationEnd])
        let normalizedRemoteAudioClassificationSource = remoteAudioClassificationSource
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
        let leaseAssignmentIndex = try #require(adapterSource.range(of: "receiverConnectedSessionLease = lease")?.lowerBound)
        let leaseAcquiredIndex = try #require(adapterSource.range(of: "summary.recordReceiverConnectedSessionLeaseAcquired(taskRetained: receiverConnectedSessionLeaseTask != nil)")?.lowerBound)
        let remoteSubscribeIndex = try #require(adapterSource.range(of: "let remoteAudioSubscriptionResult = await client.setRemoteAudioPlaybackEnabled(true)")?.lowerBound)

        #expect(adapterSource.contains("remote_participant_observation_timing_repair_present=\\(remoteParticipantObservationTimingRepairPresent)"))
        #expect(adapterSource.contains("remote_participant_observation_timing_repair_debug_only=\\(remoteParticipantObservationTimingRepairDebugOnly)"))
        #expect(adapterSource.contains("remote_participant_observation_timing_repair_bounded_window=\\(remoteParticipantObservationTimingRepairBoundedWindow)"))
        #expect(adapterSource.contains("remote_participant_observation_timing_repair_raw_identifiers_logged=\\(remoteParticipantObservationTimingRepairRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_sender_connected_overlap_repair_present=\\(receiverSenderConnectedOverlapRepairPresent)"))
        #expect(adapterSource.contains("receiver_sender_connected_overlap_repair_debug_only=\\(receiverSenderConnectedOverlapRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_sender_connected_overlap_repair_raw_identifiers_logged=\\(receiverSenderConnectedOverlapRepairRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_connected_window_retention_repair_present=\\(receiverConnectedWindowRetentionRepairPresent)"))
        #expect(adapterSource.contains("receiver_connected_window_retention_repair_debug_only=\\(receiverConnectedWindowRetentionRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_connected_window_retention_repair_raw_identifiers_logged=\\(receiverConnectedWindowRetentionRepairRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_room_retained_for_sender_observation=\\(receiverRoomRetainedForSenderObservation)"))
        #expect(adapterSource.contains("receiver_observer_attached_before_sender_join=\\(receiverObserverAttachedBeforeSenderJoin)"))
        #expect(adapterSource.contains("receiver_observer_active_during_sender_join=\\(receiverObserverActiveDuringSenderJoin)"))
        #expect(adapterSource.contains("receiver_cleanup_deferred_until_observation_terminal=\\(receiverCleanupDeferredUntilObservationTerminal)"))
        #expect(adapterSource.contains("receiver_cleanup_started_before_sender_terminal=\\(receiverCleanupStartedBeforeSenderTerminal)"))
        #expect(adapterSource.contains("sender_join_terminal_seen_by_receiver=\\(senderJoinTerminalSeenByReceiver)"))
        #expect(adapterSource.contains("sender_room_connected_during_receiver_window=\\(senderRoomConnectedDuringReceiverWindow)"))
        #expect(adapterSource.contains("sender_cleanup_started_before_receiver_observation=\\(senderCleanupStartedBeforeReceiverObservation)"))
        #expect(adapterSource.contains("receiver_sender_connected_window_overlap_observed=\\(receiverSenderConnectedWindowOverlapObserved)"))
        #expect(adapterSource.contains("receiver_connected_window_opened=\\(receiverConnectedWindowOpened)"))
        #expect(adapterSource.contains("receiver_connected_window_closed=\\(receiverConnectedWindowClosed)"))
        #expect(adapterSource.contains("receiver_connected_window_close_reason=\\(receiverConnectedWindowCloseReason)"))
        #expect(adapterSource.contains("receiver_connected_window_closed_before_sender_connected=\\(receiverConnectedWindowClosedBeforeSenderConnected)"))
        #expect(adapterSource.contains("receiver_connected_window_retained_until_sender_terminal=\\(receiverConnectedWindowRetainedUntilSenderTerminal)"))
        #expect(adapterSource.contains("sender_connected_signal_received_by_receiver=\\(senderConnectedSignalReceivedByReceiver)"))
        #expect(adapterSource.contains("sender_connected_signal_source=\\(senderConnectedSignalSource)"))
        #expect(adapterSource.contains("sender_connected_signal_before_receiver_disconnect=\\(senderConnectedSignalBeforeReceiverDisconnect)"))
        #expect(adapterSource.contains("sender_connected_signal_after_receiver_disconnect=\\(senderConnectedSignalAfterReceiverDisconnect)"))
        #expect(adapterSource.contains("sender_connected_signal_raw_identifiers_logged=\\(senderConnectedSignalRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_connected_signal_handoff_present=\\(senderConnectedSignalHandoffPresent)"))
        #expect(adapterSource.contains("sender_connected_signal_handoff_debug_only=\\(senderConnectedSignalHandoffDebugOnly)"))
        #expect(adapterSource.contains("sender_connected_signal_handoff_raw_identifiers_logged=\\(senderConnectedSignalHandoffRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_connected_signal_emitted=\\(senderConnectedSignalEmitted)"))
        #expect(adapterSource.contains("sender_connected_signal_emit_source=\\(senderConnectedSignalEmitSource)"))
        #expect(adapterSource.contains("sender_connected_signal_emitted_after_runtime_join_success=\\(senderConnectedSignalEmittedAfterRuntimeJoinSuccess)"))
        #expect(adapterSource.contains("sender_connected_signal_opaque_correlation_present=\\(senderConnectedSignalOpaqueCorrelationPresent)"))
        #expect(adapterSource.contains("sender_connected_signal_raw_room_logged=\\(senderConnectedSignalRawRoomLogged)"))
        #expect(adapterSource.contains("sender_connected_signal_raw_call_logged=\\(senderConnectedSignalRawCallLogged)"))
        #expect(adapterSource.contains("sender_connected_signal_raw_user_logged=\\(senderConnectedSignalRawUserLogged)"))
        #expect(adapterSource.contains("sender_connected_signal_raw_device_logged=\\(senderConnectedSignalRawDeviceLogged)"))
        #expect(adapterSource.contains("receiver_sender_connected_signal_wait_started=\\(receiverSenderConnectedSignalWaitStarted)"))
        #expect(adapterSource.contains("receiver_sender_connected_signal_wait_completed=\\(receiverSenderConnectedSignalWaitCompleted)"))
        #expect(adapterSource.contains("receiver_sender_connected_signal_received=\\(receiverSenderConnectedSignalReceived)"))
        #expect(adapterSource.contains("receiver_sender_connected_signal_correlation_match=\\(receiverSenderConnectedSignalCorrelationMatch)"))
        #expect(adapterSource.contains("receiver_sender_connected_signal_received_before_receiver_disconnect=\\(receiverSenderConnectedSignalReceivedBeforeReceiverDisconnect)"))
        #expect(adapterSource.contains("receiver_sender_connected_signal_received_after_receiver_disconnect=\\(receiverSenderConnectedSignalReceivedAfterReceiverDisconnect)"))
        #expect(adapterSource.contains("receiver_sender_connected_signal_timeout=\\(receiverSenderConnectedSignalTimeout)"))
        #expect(adapterSource.contains("receiver_sender_connected_signal_final_classification=\\(receiverSenderConnectedSignalFinalClassification)"))
        #expect(adapterSource.contains("receiver_sender_connected_window_overlap_wait_started=\\(receiverSenderConnectedWindowOverlapWaitStarted)"))
        #expect(adapterSource.contains("receiver_sender_connected_window_overlap_wait_completed=\\(receiverSenderConnectedWindowOverlapWaitCompleted)"))
        #expect(adapterSource.contains("receiver_sender_connected_window_overlap_wait_timeout=\\(receiverSenderConnectedWindowOverlapWaitTimeout)"))
        #expect(adapterSource.contains("receiver_sender_connected_window_overlap_final_classification=\\(receiverSenderConnectedWindowOverlapFinalClassification)"))
        #expect(adapterSource.contains("sender_readiness_context_present_during_observation=\\(senderReadinessContextPresentDuringObservation)"))
        #expect(adapterSource.contains("opaque_call_correlation_present=\\(opaqueCallCorrelationPresent)"))
        #expect(adapterSource.contains("opaque_call_correlation_match=\\(opaqueCallCorrelationMatch)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_present=\\(receiverConnectedSessionLeasePresent)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_debug_only=\\(receiverConnectedSessionLeaseDebugOnly)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_acquired=\\(receiverConnectedSessionLeaseAcquired)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_room_retained=\\(receiverConnectedSessionLeaseRoomRetained)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_delegate_retained=\\(receiverConnectedSessionLeaseDelegateRetained)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_observer_retained=\\(receiverConnectedSessionLeaseObserverRetained)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_task_retained=\\(receiverConnectedSessionLeaseTaskRetained)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_active_before_sender_trigger=\\(receiverConnectedSessionLeaseActiveBeforeSenderTrigger)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_active_after_sender_trigger=\\(receiverConnectedSessionLeaseActiveAfterSenderTrigger)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_active_at_sender_signal=\\(receiverConnectedSessionLeaseActiveAtSenderSignal)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_released=\\(receiverConnectedSessionLeaseReleased)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_released_after_terminal=\\(receiverConnectedSessionLeaseReleasedAfterTerminal)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_release_reason=\\(receiverConnectedSessionLeaseReleaseReason)"))
        #expect(adapterSource.contains("receiver_connected_session_lease_repeated_release=\\(receiverConnectedSessionLeaseRepeatedRelease)"))
        #expect(adapterSource.contains("receiver_disconnect_observed_before_sender_signal=\\(receiverDisconnectObservedBeforeSenderSignal)"))
        #expect(adapterSource.contains("receiver_disconnect_observed_after_sender_signal=\\(receiverDisconnectObservedAfterSenderSignal)"))
        #expect(adapterSource.contains("remote_participant_observation_wait_started=\\(remoteParticipantObservationWaitStarted)"))
        #expect(adapterSource.contains("remote_participant_observation_wait_completed=\\(remoteParticipantObservationWaitCompleted)"))
        #expect(adapterSource.contains("remote_participant_observation_timeout_bucket=\\(remoteParticipantObservationTimeoutBucket)"))
        #expect(adapterSource.contains("remote_participant_observation_final_classification=\\(remoteParticipantObservationFinalClassification)"))
        #expect(adapterSource.contains("receiver_participant_observation_after_overlap_started=\\(receiverParticipantObservationAfterOverlapStarted)"))
        #expect(adapterSource.contains("receiver_participant_observation_after_overlap_completed=\\(receiverParticipantObservationAfterOverlapCompleted)"))
        #expect(adapterSource.contains("receiver_participant_observation_after_overlap_timeout=\\(receiverParticipantObservationAfterOverlapTimeout)"))
        #expect(adapterSource.contains("participant_observer_propagation_repair_present=\\(participantObserverPropagationRepairPresent)"))
        #expect(adapterSource.contains("participant_observer_propagation_repair_debug_only=\\(participantObserverPropagationRepairDebugOnly)"))
        #expect(adapterSource.contains("participant_observer_propagation_raw_identifiers_logged=\\(participantObserverPropagationRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_participant_observation_final_classification=\\(receiverParticipantObservationFinalClassification)"))
        #expect(adapterSource.contains("receiver_participant_observer_bound_to_retained_room=\\(receiverParticipantObserverBoundToRetainedRoom)"))
        #expect(adapterSource.contains("receiver_participant_observer_bound_to_connected_room=\\(receiverParticipantObserverBoundToConnectedRoom)"))
        #expect(adapterSource.contains("receiver_participant_observer_attached_before_sender_signal=\\(receiverParticipantObserverAttachedBeforeSenderSignal)"))
        #expect(adapterSource.contains("receiver_participant_observer_active_after_sender_signal=\\(receiverParticipantObserverActiveAfterSenderSignal)"))
        #expect(adapterSource.contains("receiver_participant_event_callback_seen=\\(receiverParticipantEventCallbackSeen)"))
        #expect(adapterSource.contains("receiver_participant_snapshot_requested=\\(receiverParticipantSnapshotRequested)"))
        #expect(adapterSource.contains("receiver_participant_snapshot_count_bucket=\\(receiverParticipantSnapshotCountBucket)"))
        #expect(adapterSource.contains("receiver_participant_snapshot_seen=\\(receiverParticipantSnapshotSeen)"))
        #expect(adapterSource.contains("receiver_participant_identity_filter_applied=\\(receiverParticipantIdentityFilterApplied)"))
        #expect(adapterSource.contains("receiver_participant_identity_filter_result=\\(receiverParticipantIdentityFilterResult)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_observation_repair_present=\\(receiverRemoteAudioPublicationObservationRepairPresent)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_observation_repair_debug_only=\\(receiverRemoteAudioPublicationObservationRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_observation_raw_identifiers_logged=\\(receiverRemoteAudioPublicationObservationRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_snapshot_requested=\\(receiverRemoteAudioPublicationSnapshotRequested)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_snapshot_completed=\\(receiverRemoteAudioPublicationSnapshotCompleted)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_snapshot_count_bucket=\\(receiverRemoteAudioPublicationSnapshotCountBucket)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_snapshot_audio_count_bucket=\\(receiverRemoteAudioPublicationSnapshotAudioCountBucket)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_seen_via_snapshot=\\(receiverRemoteAudioPublicationSeenViaSnapshot)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_seen_via_callback=\\(receiverRemoteAudioPublicationSeenViaCallback)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_seen_via_replay=\\(receiverRemoteAudioPublicationSeenViaReplay)"))
        #expect(adapterSource.contains("receiver_remote_audio_publication_observation_final_classification=\\(receiverRemoteAudioPublicationObservationFinalClassification)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_binding_repair_present=\\(receiverAudioObserverLeaseBindingRepairPresent)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_binding_repair_debug_only=\\(receiverAudioObserverLeaseBindingRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_binding_raw_identifiers_logged=\\(receiverAudioObserverLeaseBindingRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_audio_observer_uses_retained_session_lease=\\(receiverAudioObserverUsesRetainedSessionLease)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_present_at_attach=\\(receiverAudioObserverLeasePresentAtAttach)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_present_after_participant_seen=\\(receiverAudioObserverLeasePresentAfterParticipantSeen)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_present_during_subscription_wait=\\(receiverAudioObserverLeasePresentDuringSubscriptionWait)"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_released_before_audio_terminal=\\(receiverAudioObserverLeaseReleasedBeforeAudioTerminal)"))
        #expect(adapterSource.contains("receiver_audio_observer_bound_to_same_client_as_receiver_join=\\(receiverAudioObserverBoundToSameClientAsReceiverJoin)"))
        #expect(adapterSource.contains("receiver_audio_observer_bound_to_same_client_as_participant_callback=\\(receiverAudioObserverBoundToSameClientAsParticipantCallback)"))
        #expect(adapterSource.contains("receiver_audio_observer_bound_to_retained_room=\\(receiverAudioObserverBoundToRetainedRoom)"))
        #expect(adapterSource.contains("receiver_audio_observer_bound_to_connected_room=\\(receiverAudioObserverBoundToConnectedRoom)"))

        #expect(adapterSource.contains("private final class SalemXReceiverConnectedSessionLease"))
        #expect(adapterSource.contains("let client: DirectCallLiveKitClientProtocol"))
        #expect(adapterSource.contains("let e2eeContextProvider: DirectCallLiveKitE2EEContextProvider"))
        #expect(adapterSource.contains("let e2eeContext: any DirectCallMediaE2EEContextProtocol"))
        #expect(adapterSource.contains("let keyStore: DirectCallLiveKitMediaKeyStore"))
        #expect(adapterSource.contains("func cleanup() async"))
        #expect(adapterSource.contains("await client.cleanup()"))
        #expect(adapterSource.contains("e2eeContextProvider.clearContext(callID: callID)"))
        #expect(adapterSource.contains("private static var receiverConnectedSessionLease: SalemXReceiverConnectedSessionLease?"))
        #expect(adapterSource.contains("private static var receiverConnectedSessionLeaseTask: Task<Void, Never>?"))
        #expect(adapterSource.contains("private static var receiverConnectedWindowRetentionExtensionUsed = false"))
        #expect(adapterSource.contains("private static var receiverControlledRuntimePendingSession: DirectCallSession?"))
        #expect(adapterSource.contains("private static var receiverControlledRuntimePendingConnectionInfo: DirectCallMediaConnectionInfo?"))
        #expect(adapterSource.contains("private static var receiverRuntimeLiveKitClientFactory: @MainActor () -> DirectCallLiveKitClientProtocol"))
        #expect(adapterSource.contains("private static var receiverParticipantSnapshotSweepID: UUID?"))
        #expect(adapterSource.contains("receiverControlledRuntimePendingSession = session"))
        #expect(adapterSource.contains("receiverControlledRuntimePendingConnectionInfo = connectionInfo"))
        #expect(adapterSource.contains("receiverControlledRuntimePendingSession = nil"))
        #expect(adapterSource.contains("receiverControlledRuntimePendingConnectionInfo = nil"))
        #expect(adapterSource.contains("startReceiverControlledRuntimeConnectLeaseIfAllowed(session: session, connectionInfo: connectionInfo)"))
        #expect(adapterSource.contains("private static func runReceiverControlledRuntimeConnectLease(session: DirectCallSession, connectionInfo: DirectCallMediaConnectionInfo) async"))
        #expect(adapterSource.contains("mutating func recordReceiverConnectedWindowOpened()"))
        #expect(adapterSource.contains("mutating func recordReceiverConnectedWindowClosed(reason: String)"))
        #expect(adapterSource.contains("mutating func recordSenderConnectedSignalFromRuntime(senderConnected: Bool, source: String, correlationMatched: Bool = true)"))
        #expect(adapterSource.contains("mutating func completeReceiverSenderConnectedWindowOverlapTimeout()"))
        #expect(adapterSource.contains("private static let senderConnectedSignalHandoffURLHookPath = \"/direct-call/sender-connected-signal-handoff\""))
        #expect(adapterSource.contains("armSenderConnectedSignalHandoffURLHook(components)"))
        #expect(adapterSource.contains("private static func armSenderConnectedSignalHandoffURLHook(_ components: URLComponents?)"))
        #expect(adapterSource.contains("DirectCallLiveKitConnectExecutor(liveKitClient: client)"))
        #expect(adapterSource.contains("executor.connectAudio(connectionInfo: connectionInfo, e2eeContext: e2eeContext)"))
        #expect(adapterSource.contains("receiverConnectedSessionLease = lease"))
        #expect(adapterSource.contains("summary.recordReceiverConnectedSessionLeaseAcquired(taskRetained: receiverConnectedSessionLeaseTask != nil)"))
        #expect(leaseAssignmentIndex < remoteSubscribeIndex)
        #expect(leaseAcquiredIndex < remoteSubscribeIndex)
        #expect(adapterSource.contains("summary.recordReceiverRemoteAudioExplicitSubscribeStarted()"))
        #expect(adapterSource.contains("releaseReceiverConnectedSessionLease(reason:"))
        #expect(adapterSource.contains("summary.shouldDeferReceiverConnectedSessionLeaseReleaseForAudioTerminal"))
        #expect(adapterSource.contains("summary.recordReceiverConnectedSessionLeaseReleaseDeferredForAudioTerminal(reason: reason)"))
        #expect(adapterSource.contains("summary.recordReceiverConnectedSessionLeaseReleased(reason: reason, repeated: repeated)"))
        #expect(adapterSource.contains("private static let remoteParticipantObservationWindowTimeout: TimeInterval = 8"))
        #expect(adapterSource.contains("private static var remoteParticipantObservationWindowID: UUID?"))
        #expect(adapterSource.contains("private static var remoteParticipantObservationWindowStartedAt: Date?"))
        #expect(adapterSource.contains("scheduleRemoteParticipantObservationTimeoutIfNeeded()"))
        #expect(adapterSource.contains("finishRemoteParticipantObservationTimeoutIfCurrent"))
        #expect(adapterSource.contains("scheduleReceiverParticipantSnapshotSweepIfNeeded()"))
        #expect(adapterSource.contains("requestReceiverParticipantSnapshotIfCurrent"))
        #expect(adapterSource.contains("private static var receiverRemoteAudioPublicationSnapshotReplayID: UUID?"))
        #expect(adapterSource.contains("private static var receiverRemoteAudioSubscribeVerificationID: UUID?"))
        #expect(adapterSource.contains("scheduleReceiverRemoteAudioPublicationSnapshotReplayIfNeeded()"))
        #expect(adapterSource.contains("requestReceiverRemoteAudioPublicationSnapshotReplayIfCurrent"))
        #expect(adapterSource.contains("scheduleReceiverRemoteAudioSubscriptionVerificationIfNeeded()"))
        #expect(adapterSource.contains("requestReceiverRemoteAudioSubscribeVerificationIfCurrent"))
        #expect(adapterSource.contains("summary.liveKitRemoteParticipantSeen,"))
        #expect(adapterSource.contains("!summary.receiverRemoteAudioPublicationSeen,"))
        #expect(adapterSource.contains("let snapshot = await lease.client.remoteParticipantSnapshot()"))
        #expect(adapterSource.contains("let beforeSubscribeSnapshot = await lease.client.remoteParticipantSnapshot()"))
        #expect(adapterSource.contains("let afterSubscribeSnapshot = await lease.client.remoteParticipantSnapshot()"))
        #expect(adapterSource.contains("summary.recordReceiverParticipantSnapshotObservation(afterSubscribeSnapshot)"))
        #expect(adapterSource.contains("summary.shouldExtendReceiverConnectedWindowForSenderSignal(alreadyExtended: receiverConnectedWindowRetentionExtensionUsed)"))
        #expect(adapterSource.contains("receiverConnectedWindowRetentionExtensionUsed = true"))
        #expect(adapterSource.contains("summary.recordReceiverConnectedWindowRetentionExtended(timeoutBucket: timeoutBucket)"))
        #expect(adapterSource.contains("receiverConnectedWindowRetentionExtensionUsed = false"))
        #expect(adapterSource.contains("remoteParticipantObservationWaitStarted = true"))
        #expect(adapterSource.contains("remoteParticipantObservationFinalClassification = \"pending_redacted\""))
        #expect(adapterSource.contains("mutating func activateRemoteParticipantObservationRuntimeWindowIfNeeded()"))
        #expect(adapterSource.contains("activateRemoteParticipantObservationRuntimeWindowIfNeeded()"))
        #expect(adapterSource.contains("controlledConnectFirstAttemptResult == \"success_redacted\""))
        #expect(adapterSource.contains("receiverRemoteParticipantObserverStarted = true"))
        #expect(adapterSource.contains("liveKitRoomConnected = true"))
        #expect(adapterSource.contains("liveKitRoomDisconnected = false"))
        #expect(adapterSource.contains("private func remoteParticipantSeenClassification() -> String"))
        #expect(adapterSource.contains("shouldCompleteRemoteParticipantObservationAfterRemoteAudioUpdate {"))
        #expect(adapterSource.contains("completeRemoteParticipantObservation(classification: remoteParticipantSeenClassification(), timeoutBucket: \"none\")"))
        #expect(adapterSource.contains("completeRemoteParticipantObservation(classification: classification, timeoutBucket: \"none\")"))
        #expect(adapterSource.contains("completeRemoteParticipantObservationTimeout(timeoutBucket: timeoutBucket)"))

        #expect(adapterSource.contains("remote_participant_seen_redacted"))
        #expect(adapterSource.contains("receiver_lease_not_acquired_redacted"))
        #expect(adapterSource.contains("receiver_room_released_before_sender_join_redacted"))
        #expect(adapterSource.contains("receiver_disconnected_before_sender_join_redacted"))
        #expect(adapterSource.contains("receiver_observer_not_active_redacted"))
        #expect(adapterSource.contains("sender_readiness_context_missing_redacted"))
        #expect(adapterSource.contains("opaque_correlation_mismatch_redacted"))
        #expect(adapterSource.contains("sender_connected_outside_receiver_window_redacted"))
        #expect(adapterSource.contains("no_receiver_sender_connected_overlap_redacted"))
        #expect(adapterSource.contains("sender_disconnected_before_observation_redacted"))
        #expect(adapterSource.contains("remote_participant_event_timeout_redacted"))
        #expect(adapterSource.contains("sender_connected_signal_missing_redacted"))
        #expect(adapterSource.contains("sender_connected_signal_late_redacted"))
        #expect(adapterSource.contains("sender_connected_signal_after_receiver_disconnect_redacted"))
        #expect(adapterSource.contains("sender_connected_signal_correlation_mismatch_redacted"))
        #expect(adapterSource.contains("receiver_window_closed_before_sender_signal_redacted"))
        #expect(adapterSource.contains("receiver_connected_window_retained_until_sender_signal_redacted"))
        #expect(adapterSource.contains("receiver_connected_window_overlap_observed_redacted"))
        #expect(adapterSource.contains("receiver_disconnected_before_sender_signal_redacted"))
        #expect(adapterSource.contains("receiver_cleanup_started_before_sender_terminal_redacted"))
        #expect(adapterSource.contains("receiver_lease_released_before_sender_signal_redacted"))
        #expect(adapterSource.contains("participant_observation_timeout_after_overlap_redacted"))
        #expect(adapterSource.contains("remote_participant_seen_via_retained_window_redacted"))
        #expect(adapterSource.contains("remote_participant_seen_via_callback_redacted"))
        #expect(adapterSource.contains("remote_participant_seen_via_snapshot_redacted"))
        #expect(adapterSource.contains("remote_audio_publication_seen_via_callback_redacted"))
        #expect(adapterSource.contains("remote_audio_publication_seen_via_snapshot_redacted"))
        #expect(adapterSource.contains("remote_audio_publication_seen_via_replay_redacted"))
        #expect(adapterSource.contains("remote_audio_publication_missing_after_participant_seen_redacted"))
        #expect(adapterSource.contains("remote_audio_publication_missing_after_sender_audio_publish_redacted"))
        #expect(adapterSource.contains("remote_audio_publication_filter_mismatch_redacted"))
        #expect(adapterSource.contains("receiver_audio_observer_bound_to_retained_connected_room_redacted"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_missing_at_attach_redacted"))
        #expect(adapterSource.contains("receiver_audio_observer_lease_released_before_audio_terminal_redacted"))
        #expect(adapterSource.contains("receiver_audio_observer_stale_client_redacted"))
        #expect(adapterSource.contains("participant_observer_not_bound_to_retained_room_redacted"))
        #expect(adapterSource.contains("participant_observer_not_bound_to_connected_room_redacted"))
        #expect(adapterSource.contains("participant_observer_attached_late_redacted"))
        #expect(adapterSource.contains("participant_identity_filtered_out_redacted"))
        #expect(adapterSource.contains("participant_snapshot_empty_redacted"))
        #expect(adapterSource.contains("participant_event_callback_missing_redacted"))
        #expect(adapterSource.contains("receiver_observer_bound_to_stale_room_redacted"))
        #expect(adapterSource.contains("receiver_overlap_wait_timeout_redacted"))
        #expect(adapterSource.contains("receiver_cleanup_released_lease_early_redacted"))

        #expect(adapterSource.contains("liveKitRoomDisconnected = observationActive ? false : controlledCallKitCleanupResult == \"ended\" || remoteParticipantObservationWaitCompleted"))
        #expect(adapterSource.contains("liveKitCleanupResult = \"deferred_until_observation_terminal_redacted\""))
        #expect(adapterSource.contains("mutating func refreshRemoteAudioTrackLivenessClassification()"))
        #expect(adapterSource.contains("mutating func refreshReceiverRemoteAudioSubscriptionClassification()"))
        #expect(remoteAudioClassificationSource.contains("receiverRemoteAudioLivenessObserved || liveKitAudioLivenessObserved"))
        #expect(remoteAudioClassificationSource.contains("senderLocalAudioPublishRequested, senderLocalAudioPublishResult != \"success_redacted\""))
        #expect(normalizedRemoteAudioClassificationSource.contains("senderMicrophonePermissionRequested&&senderMicrophonePermissionResultBucket!=\"success_redacted\"?"))
        #expect(remoteAudioClassificationSource.contains("\"remote_audio_liveness_observed_redacted\""))
        #expect(adapterSource.contains("mutating func refreshReceiverRemoteAudioPublicationObservationClassification()"))
        #expect(adapterSource.contains("receiverRemoteAudioPublicationSeenViaReplay"))
        #expect(adapterSource.contains("receiverRemoteAudioPublicationSnapshotAudioCountBucket = snapshot.audioPublicationSeen ? \"1\" : \"0\""))
        #expect(adapterSource.contains("audioPublicationSource: \"snapshot_redacted\""))
        #expect(adapterSource.contains("\"remote_audio_subscription_observed_redacted\""))
        #expect(adapterSource.contains("\"remote_audio_explicit_subscription_confirmed_redacted\""))
        #expect(adapterSource.contains("\"remote_audio_subscription_request_only_redacted\""))
        #expect(adapterSource.contains("\"remote_audio_publication_seen_but_subscription_missing_redacted\""))
        #expect(adapterSource.contains("\"remote_audio_auto_subscribe_disabled_redacted\""))
        #expect(adapterSource.contains("\"remote_audio_subscription_timeout_redacted\""))
        #expect(remoteAudioClassificationSource.contains("\"remote_audio_track_subscribed_but_silent_redacted\""))
        #expect(remoteAudioClassificationSource.contains("receiverRemoteAudioPublicationObservationFinalClassification"))
        #expect(remoteAudioClassificationSource.contains("\"remote_audio_subscription_missing_redacted\""))
        #expect(remoteAudioClassificationSource.contains("\"remote_audio_track_muted_redacted\""))
        #expect(remoteAudioClassificationSource.contains("\"remote_audio_liveness_timeout_redacted\""))
        #expect(remoteAudioClassificationSource.contains("\"sender_audio_publish_not_requested_redacted\""))
        #expect(remoteAudioClassificationSource.contains("\"sender_microphone_permission_blocked_redacted\""))
        #expect(remoteAudioClassificationSource.contains("\"sender_audio_session_not_active_redacted\""))
        #expect(remoteAudioClassificationSource.contains("\"remote_audio_observer_not_bound_to_connected_room_redacted\""))
        #expect(remoteAudioClassificationSource.contains("receiverAudioObserverLeaseBindingFinalClassification"))
        #expect(adapterSource.contains("disconnectCleanupDiagnosticsLiveKitCleanupRequested = controlledCallKitCleanupRequested && liveKitConnectAudioInvoked && !observationActive"))
        #expect(adapterSource.contains("receiverCleanupStartedBeforeSenderTerminal = liveKitRoomDisconnected &&"))
        #expect(adapterSource.contains("!remoteParticipantObservationWaitCompleted"))
        #expect(adapterSource.contains("receiverLeaseActive = receiverConnectedSessionLeaseAcquired &&"))
        #expect(adapterSource.contains("receiverRoomRetainedForSenderObservation = receiverRoomRetainedForSenderObservation ||"))
        #expect(adapterSource.contains("receiverObserverAttachedBeforeSenderJoin = receiverObserverAttachedBeforeSenderJoin ||"))
        #expect(adapterSource.contains("receiverObserverActiveDuringSenderJoin = receiverObserverActiveDuringSenderJoin ||"))
        #expect(adapterSource.contains("senderConnectedSignalReceivedByReceiver = true"))
        #expect(adapterSource.contains("senderConnectedSignalBeforeReceiverDisconnect = receiverWindowActive"))
        #expect(adapterSource.contains("receiverSenderConnectedWindowOverlapObserved = true"))
        #expect(adapterSource.contains("receiverConnectedSessionLeaseActiveAtSenderSignal = receiverWindowActive"))
        #expect(adapterSource.contains("receiverParticipantObservationAfterOverlapStarted = true"))
        #expect(adapterSource.contains("receiverSenderConnectedSignalWaitStarted = true"))
        #expect(adapterSource.contains("receiverSenderConnectedSignalWaitCompleted = true"))
        #expect(adapterSource.contains("receiverSenderConnectedSignalCorrelationMatch = correlationMatched"))
        #expect(adapterSource.contains("receiverSenderConnectedSignalFinalClassification = \"receiver_connected_window_retained_until_sender_signal_redacted\""))
        #expect(adapterSource.contains("receiverConnectedWindowRetainedUntilSenderTerminal = true"))
        #expect(adapterSource.contains("senderConnectedSignalAfterReceiverDisconnect = !receiverWindowActive"))
        #expect(adapterSource.contains("receiverRemoteAudioSubscriptionWaitStarted = receiverRemoteAudioSubscriptionWaitStarted || receiverWindowActive"))
        #expect(adapterSource.contains("receiverRemoteAudioLivenessWaitStarted = receiverRemoteAudioLivenessWaitStarted || receiverWindowActive"))
        #expect(adapterSource.contains("mutating func recordReceiverParticipantEventCallbackObservation(participantCountBucket: String)"))
        #expect(adapterSource.contains("mutating func recordReceiverParticipantSnapshotRequested(boundToRetainedRoom: Bool, boundToConnectedRoom: Bool)"))
        #expect(adapterSource.contains("mutating func recordReceiverParticipantSnapshotObservation(_ snapshot: DirectCallRemoteParticipantSnapshot)"))
        #expect(adapterSource.contains("private mutating func recordRemoteParticipantPresenceObservation(participantCountBucket: String, classification: String)"))
        #expect(adapterSource.contains("receiverParticipantSnapshotSweepID = nil"))
        #expect(adapterSource.contains("summary.recordSenderConnectedSignalFromRuntime(senderConnected: senderSummary.senderLiveKitRoomConnected"))
        #expect(adapterSource.contains("summary.recordSenderConnectedSignalFromRuntime(senderConnected: senderConnected,"))
        #expect(adapterSource.contains("source: source,"))
        #expect(adapterSource.contains("correlationMatched: correlationMatched)"))
        #expect(adapterSource.contains("scheduleRemoteParticipantObservationTimeoutIfNeeded()"))
        #expect(adapterSource.contains("return \"participant_observation_timeout_after_overlap_redacted\""))
        #expect(adapterSource.contains("receiverCleanupDeferredUntilObservationTerminal = receiverCleanupDeferredUntilObservationTerminal ||"))
        #expect(!runtimeSnapshotSource.contains("pendingRemotePeerContextHandoff = nil"))
        #expect(!adapterSource.contains("remoteParticipantObservationTimingRepairRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("receiverSenderConnectedOverlapRepairRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("participantObserverPropagationRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalHandoffRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalRawRoomLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalRawCallLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalRawUserLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalRawDeviceLogged = true"))

        #expect(liveKitClientSource.contains("recordReceiverRemoteParticipantRuntimeObservation(participantCountBucket:"))
        #expect(liveKitClientSource.contains("recordReceiverRemoteParticipantEventCallback(participantCountBucket:"))
        #expect(liveKitClientSource.contains("nonisolated func room(_ room: Room, participantDidConnect _: RemoteParticipant)"))
        #expect(liveKitClientSource.contains("func remoteParticipantSnapshot() async -> DirectCallRemoteParticipantSnapshot"))
        #expect(liveKitClientSource.contains("nonisolated func room(_ room: Room, participant: RemoteParticipant, didPublishTrack publication: RemoteTrackPublication)"))
        #expect(liveKitClientSource.contains("nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication)"))
        #expect(liveKitClientSource.contains("nonisolated func room(_ room: Room, participant: Participant, trackPublication publication: TrackPublication, didUpdateIsMuted isMuted: Bool)"))
        #expect(liveKitClientSource.contains("nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant])"))
        #expect(liveKitClientSource.contains("private final class DirectCallRemoteAudioLivenessRenderer: AudioRenderer"))
        #expect(liveKitClientSource.contains("recordReceiverRemoteAudioLivenessFrame()"))
        #expect(liveKitClientSource.contains("recordReceiverRemoteAudioSubscriptionCallback()"))
        #expect(liveKitClientSource.contains("publication.track as? RemoteAudioTrack"))
        #expect(liveKitClientSource.contains("remotePublication.track is RemoteAudioTrack"))
        #expect(liveKitClientSource.contains("remoteAudioTrack.add(audioRenderer: renderer)"))
        #expect(liveKitClientSource.contains("await self?.subscribeToRemoteAudioIfNeeded(room: room, publication: publication)"))
        #expect(liveKitClientSource.contains("audioTrackSubscribed: publication.kind == .audio"))
        #expect(adapterSource.contains("let remoteAudioSubscriptionResult = await client.setRemoteAudioPlaybackEnabled(true)"))
        #expect(adapterSource.contains("summary.recordReceiverAudioObserverLeaseBinding(leasePresent: leasePresent,"))
        #expect(adapterSource.contains("summary.recordReceiverRemoteAudioExplicitSubscribeResult(remoteAudioSubscriptionResult)"))
        #expect(liveKitMediaEngineSource.contains("struct DirectCallRemoteParticipantSnapshot: Equatable"))
        #expect(liveKitMediaEngineSource.contains("func remoteParticipantSnapshot() async -> DirectCallRemoteParticipantSnapshot"))
        #expect(liveKitMediaEngineSource.contains("identityFilterResult: \"not_applied_redacted\""))
        #expect(liveKitMediaEngineSource.contains("let audioPublicationSeen: Bool"))
        #expect(liveKitMediaEngineSource.contains("let audioLivenessObserved: Bool"))
        #expect(!liveKitClientSource.contains("participant.identity"))
        #expect(!liveKitClientSource.contains("room.name"))
    }

    // swiftlint:enable function_body_length

    @Test
    func senderLiveKitReadinessHookArmsRedactedReadinessWithoutStartingRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("private struct SalemXSenderLiveKitReadinessHook"))
        #expect(adapterSource.contains("static let defaultDisabledNoConnectReason = \"default_disabled_no_connect\""))
        #expect(adapterSource.contains("static let appSessionMissingReason = \"sender_app_session_missing_redacted\""))
        #expect(adapterSource.contains("static let wrongAccountReason = \"sender_wrong_account_redacted\""))
        #expect(adapterSource.contains("static let sameRoomReadinessMissingReason = \"sender_same_room_readiness_missing_redacted\""))
        #expect(adapterSource.contains("static let armedWaitingForFutureSenderJoinReason = \"armed_waiting_for_future_sender_join\""))
        #expect(adapterSource.contains("static let defaultDisabled = SalemXSenderLiveKitReadinessHook(armed: false,"))

        #expect(adapterSource.contains("let present = true"))
        #expect(adapterSource.contains("let debugOnly = true"))
        #expect(adapterSource.contains("let isDefaultDisabled = true"))
        #expect(adapterSource.contains("let audioOnly = true"))
        #expect(adapterSource.contains("let videoAllowed = false"))
        #expect(adapterSource.contains("let matrixEventsAllowed = false"))
        #expect(adapterSource.contains("let rawIdentifiersLogged = false"))

        #expect(adapterSource.contains("sender_livekit_readiness_hook_present=\\(senderLiveKitReadinessHookPresent)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_debug_only=\\(senderLiveKitReadinessHookDebugOnly)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_default_disabled=\\(senderLiveKitReadinessHookDefaultDisabled)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_armed=\\(senderLiveKitReadinessHookArmed)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_matrix_session_ready=\\(senderLiveKitReadinessHookMatrixSessionReady)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_expected_user_matched=\\(senderLiveKitReadinessHookExpectedUserMatched)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_same_room_ready=\\(senderLiveKitReadinessHookSameRoomReady)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_credentials_ready=\\(senderLiveKitReadinessHookCredentialsReady)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_audio_only=\\(senderLiveKitReadinessHookAudioOnly)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_video_allowed=\\(senderLiveKitReadinessHookVideoAllowed)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_matrix_events_allowed=\\(senderLiveKitReadinessHookMatrixEventsAllowed)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_raw_identifiers_logged=\\(senderLiveKitReadinessHookRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_livekit_readiness_hook_blocked_reason=\\(senderLiveKitReadinessHookBlockedReason)"))

        #expect(adapterSource.contains("var senderLiveKitReadinessHookPresent = SalemXSenderLiveKitReadinessHook.defaultDisabled.present"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookDebugOnly = SalemXSenderLiveKitReadinessHook.defaultDisabled.debugOnly"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookDefaultDisabled = SalemXSenderLiveKitReadinessHook.defaultDisabled.isDefaultDisabled"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookArmed = SalemXSenderLiveKitReadinessHook.defaultDisabled.armed"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookMatrixSessionReady = SalemXSenderLiveKitReadinessHook.defaultDisabled.matrixSessionReady"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookExpectedUserMatched = SalemXSenderLiveKitReadinessHook.defaultDisabled.expectedUserMatched"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookSameRoomReady = SalemXSenderLiveKitReadinessHook.defaultDisabled.sameRoomReady"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookCredentialsReady = SalemXSenderLiveKitReadinessHook.defaultDisabled.credentialsReady"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookAudioOnly = SalemXSenderLiveKitReadinessHook.defaultDisabled.audioOnly"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookVideoAllowed = SalemXSenderLiveKitReadinessHook.defaultDisabled.videoAllowed"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookMatrixEventsAllowed = SalemXSenderLiveKitReadinessHook.defaultDisabled.matrixEventsAllowed"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookRawIdentifiersLogged = SalemXSenderLiveKitReadinessHook.defaultDisabled.rawIdentifiersLogged"))
        #expect(adapterSource.contains("var senderLiveKitReadinessHookBlockedReason = SalemXSenderLiveKitReadinessHook.defaultDisabled.blockedReason"))

        #expect(adapterSource.contains("if !armed {"))
        #expect(adapterSource.contains("if !matrixSessionReady {"))
        #expect(adapterSource.contains("if !expectedUserMatched {"))
        #expect(adapterSource.contains("if !sameRoomReady {"))
        #expect(adapterSource.contains("return Self.armedWaitingForFutureSenderJoinReason"))

        #expect(adapterSource.contains("private static let senderLiveKitReadinessURLHookPath = \"/direct-call/sender-livekit-readiness\""))
        #expect(adapterSource.contains("private static var senderLiveKitReadinessHook = SalemXSenderLiveKitReadinessHook.defaultDisabled"))
        #expect(adapterSource.contains("armSenderLiveKitReadinessURLHook(components)"))
        #expect(adapterSource.contains("private static func armSenderLiveKitReadinessURLHook(_ components: URLComponents?)"))
        #expect(adapterSource.contains("matrixSessionReady: redactedBoolQueryItem(components,"))
        #expect(adapterSource.contains("names: [\"sender_matrix_session_ready\", \"matrix_session_ready\"]"))
        #expect(adapterSource.contains("expectedUserMatched: redactedBoolQueryItem(components,"))
        #expect(adapterSource.contains("names: [\"sender_expected_hash_matches\", \"expected_user_matched\", \"expected_user_hash_matches\"]"))
        #expect(adapterSource.contains("sameRoomReady: redactedBoolQueryItem(components,"))
        #expect(adapterSource.contains("names: [\"sender_same_room_ready\", \"same_room_ready\"]"))
        #expect(adapterSource.contains("credentialsReady: redactedBoolQueryItem(components,"))

        #expect(adapterSource.contains("summary.recordSenderReadinessRuntimeHandoff(hook,"))
        #expect(adapterSource.contains("receivedByRuntime: false"))
        #expect(adapterSource.contains("survivedPushKit: false"))
        #expect(adapterSource.contains("survivedAnswer: false"))
        #expect(adapterSource.contains("summary.mediaConnectRequested = false"))
        #expect(adapterSource.contains("summary.mediaConnectAttempted = false"))
        #expect(adapterSource.contains("summary.liveKitJoinRequested = false"))
        #expect(adapterSource.contains("summary.liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("summary.microphonePermissionRequested = false"))
        #expect(adapterSource.contains("summary.cameraPermissionRequested = false"))
        #expect(adapterSource.contains("summary.matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("summary.realCallFlowStarted = false"))

        #expect(adapterSource.contains("mutating func recordSenderLiveKitReadinessHook(_ hook: SalemXSenderLiveKitReadinessHook)"))
        #expect(adapterSource.contains("senderLiveKitReadinessHookArmed = hook.armed"))
        #expect(adapterSource.contains("senderLiveKitReadinessHookMatrixSessionReady = hook.matrixSessionReady"))
        #expect(adapterSource.contains("senderLiveKitReadinessHookExpectedUserMatched = hook.expectedUserMatched"))
        #expect(adapterSource.contains("senderLiveKitReadinessHookSameRoomReady = hook.sameRoomReady"))
        #expect(adapterSource.contains("senderLiveKitReadinessHookBlockedReason = hook.blockedReason"))
        #expect(adapterSource.contains("refreshRemoteParticipantPresenceRepairDiagnostics()"))

        #expect(!adapterSource.contains("senderLiveKitReadinessHookRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitReadinessURLHookPath = \"/dev/invite\""))
        #expect(!adapterSource.contains("senderLiveKitReadinessHookVideoAllowed = true"))
        #expect(!adapterSource.contains("senderLiveKitReadinessHookMatrixEventsAllowed = true"))
    }

    @Test
    func senderReadinessRuntimeHandoffAndJoinHookAreClassifiedWithoutStartingRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("sender_readiness_runtime_handoff_present=\\(senderReadinessRuntimeHandoffPresent)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_debug_only=\\(senderReadinessRuntimeHandoffDebugOnly)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_armed_before_apns=\\(senderReadinessRuntimeHandoffArmedBeforeAPNs)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_received_by_runtime=\\(senderReadinessRuntimeHandoffReceivedByRuntime)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_survived_pushkit=\\(senderReadinessRuntimeHandoffSurvivedPushKit)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_survived_answer=\\(senderReadinessRuntimeHandoffSurvivedAnswer)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_matrix_session_ready=\\(senderReadinessRuntimeHandoffMatrixSessionReady)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_same_room_ready=\\(senderReadinessRuntimeHandoffSameRoomReady)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_expected_user_matched=\\(senderReadinessRuntimeHandoffExpectedUserMatched)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_raw_identifiers_logged=\\(senderReadinessRuntimeHandoffRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_missing_classified=\\(senderReadinessRuntimeHandoffMissingClassified)"))

        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffPresent = true"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffDebugOnly = true"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffArmedBeforeAPNs = false"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffReceivedByRuntime = false"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffSurvivedPushKit = false"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffSurvivedAnswer = false"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffMatrixSessionReady = false"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffSameRoomReady = false"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffExpectedUserMatched = false"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("var senderReadinessRuntimeHandoffMissingClassified = true"))

        #expect(adapterSource.contains("mutating func recordSenderReadinessRuntimeHandoff(_ hook: SalemXSenderLiveKitReadinessHook,"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffArmedBeforeAPNs = hook.armed"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffReceivedByRuntime = receivedByRuntime && hook.armed"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffSurvivedPushKit = survivedPushKit && hook.armed"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffSurvivedAnswer = survivedAnswer && hook.armed"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffMatrixSessionReady = hook.matrixSessionReady"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffSameRoomReady = hook.sameRoomReady"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffExpectedUserMatched = hook.expectedUserMatched"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffMissingClassified = !senderReadinessRuntimeHandoffReceivedByRuntime"))
        #expect(adapterSource.contains("mutating func markSenderReadinessRuntimeHandoffSurvivedAnswer()"))
        #expect(adapterSource.contains("summary.markSenderReadinessRuntimeHandoffSurvivedAnswer()"))
        #expect(adapterSource.contains("mutating func recordMissingSenderReadinessRuntimeHandoff()"))
        #expect(adapterSource.contains("liveKitAudioLivenessResult = \"not_observed_redacted\""))
        #expect(adapterSource.contains("liveKitAudioLivenessErrorBucket = \"sender_readiness_context_missing_redacted\""))

        #expect(adapterSource.contains("let senderLiveKitReadinessHookSnapshot = senderLiveKitReadinessHook"))
        #expect(adapterSource.contains("baseSummary.recordSenderReadinessRuntimeHandoff(senderLiveKitReadinessHookSnapshot)"))
        #expect(adapterSource.contains("summary.recordSenderReadinessRuntimeHandoff(hook,"))
        #expect(adapterSource.contains("receivedByRuntime: false"))
        #expect(adapterSource.contains("survivedPushKit: false"))
        #expect(adapterSource.contains("survivedAnswer: false"))

        #expect(adapterSource.contains("private struct SalemXSenderSideLiveKitJoinHook"))
        #expect(adapterSource.contains("static let notRequestedResult = \"not_requested\""))
        #expect(adapterSource.contains("static let blockedResult = \"blocked_redacted\""))
        #expect(adapterSource.contains("static let successResult = \"success_redacted\""))
        #expect(adapterSource.contains("static let failedResult = \"failed_redacted\""))
        #expect(adapterSource.contains("static let defaultDisabled = SalemXSenderSideLiveKitJoinHook(armed: false,"))
        #expect(adapterSource.contains("let audioOnly = true"))
        #expect(adapterSource.contains("let videoAllowed = false"))
        #expect(adapterSource.contains("let matrixEventsAllowed = false"))
        #expect(adapterSource.contains("let rawCredentialsLogged = false"))

        #expect(adapterSource.contains("sender_side_livekit_join_hook_present=\\(senderSideLiveKitJoinHookPresent)"))
        #expect(adapterSource.contains("sender_side_livekit_join_hook_debug_only=\\(senderSideLiveKitJoinHookDebugOnly)"))
        #expect(adapterSource.contains("sender_side_livekit_join_hook_default_disabled=\\(senderSideLiveKitJoinHookDefaultDisabled)"))
        #expect(adapterSource.contains("sender_side_livekit_join_hook_armed=\\(senderSideLiveKitJoinHookArmed)"))
        #expect(adapterSource.contains("sender_side_livekit_join_hook_audio_only=\\(senderSideLiveKitJoinHookAudioOnly)"))
        #expect(adapterSource.contains("sender_side_livekit_join_hook_video_allowed=\\(senderSideLiveKitJoinHookVideoAllowed)"))
        #expect(adapterSource.contains("sender_side_livekit_join_hook_matrix_events_allowed=\\(senderSideLiveKitJoinHookMatrixEventsAllowed)"))
        #expect(adapterSource.contains("sender_side_livekit_join_hook_raw_credentials_logged=\\(senderSideLiveKitJoinHookRawCredentialsLogged)"))
        #expect(adapterSource.contains("sender_side_livekit_join_requested=\\(senderSideLiveKitJoinRequested)"))
        #expect(adapterSource.contains("sender_side_livekit_join_result=\\(senderSideLiveKitJoinResult)"))
        #expect(adapterSource.contains("sender_side_livekit_join_error_bucket=\\(senderSideLiveKitJoinErrorBucket)"))
        #expect(adapterSource.contains("sender_side_livekit_join_repeated=\\(senderSideLiveKitJoinRepeated)"))

        #expect(adapterSource.contains("private static let senderSideLiveKitJoinURLHookPath = \"/direct-call/sender-side-livekit-join\""))
        #expect(adapterSource.contains("private static var senderSideLiveKitJoinHook = SalemXSenderSideLiveKitJoinHook.defaultDisabled"))
        #expect(adapterSource.contains("armSenderSideLiveKitJoinURLHook(components)"))
        #expect(adapterSource.contains("private static func armSenderSideLiveKitJoinURLHook(_ components: URLComponents?)"))
        #expect(adapterSource.contains("summary.recordSenderSideLiveKitJoinHook(hook)"))
        #expect(adapterSource.contains("mutating func recordSenderSideLiveKitJoinHook(_ hook: SalemXSenderSideLiveKitJoinHook)"))
        #expect(adapterSource.contains("mutating func recordSenderSideLiveKitJoinResult(requested: Bool,"))
        #expect(adapterSource.contains("let senderSideLiveKitJoinHookSnapshot = senderSideLiveKitJoinHook"))
        #expect(adapterSource.contains("baseSummary.recordSenderSideLiveKitJoinHook(senderSideLiveKitJoinHookSnapshot)"))

        #expect(adapterSource.contains("sender_readiness_context_missing_redacted"))
        #expect(adapterSource.contains("sender_join_hook_not_armed_redacted"))
        #expect(adapterSource.contains("sender_join_not_requested_redacted"))
        #expect(adapterSource.contains("sender_join_blocked_redacted"))
        #expect(adapterSource.contains("sender_join_failed_redacted"))
        #expect(adapterSource.contains("sender_join_success_but_remote_missing_redacted"))
        #expect(adapterSource.contains("remote_participant_missing_redacted"))
        #expect(adapterSource.contains("senderReadinessRuntimeHandoffMissingClassified"))
        #expect(adapterSource.contains("senderSideLiveKitJoinRequested"))
        #expect(adapterSource.contains("cameraPermissionRequested = false"))
        #expect(adapterSource.contains("matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderReadinessRuntimeHandoffRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderSideLiveKitJoinHookRawCredentialsLogged = true"))
        #expect(!adapterSource.contains("senderSideLiveKitJoinHookVideoAllowed = true"))
        #expect(!adapterSource.contains("senderSideLiveKitJoinHookMatrixEventsAllowed = true"))
    }

    @Test
    func senderSideLiveKitJoinActivationIsDebugOnlyOneShotAndClassifiedWithoutRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("private struct SalemXSenderSideLiveKitJoinActivation"))
        #expect(adapterSource.contains("static let defaultDisabledNoConnectReason = \"default_disabled_no_connect\""))
        #expect(adapterSource.contains("static let senderReadinessMissingReason = \"sender_readiness_missing_redacted\""))
        #expect(adapterSource.contains("static let sameRoomReadinessMissingReason = \"sender_same_room_readiness_missing_redacted\""))
        #expect(adapterSource.contains("static let armedWaitingForTriggerReason = \"armed_waiting_for_sender_join_trigger\""))
        #expect(adapterSource.contains("static let repeatedSenderJoinBlockedReason = \"repeated_sender_join_blocked_redacted\""))
        #expect(adapterSource.contains("static let senderJoinBlockedReason = \"sender_join_blocked_redacted\""))
        #expect(adapterSource.contains("static let senderJoinFailedReason = \"sender_join_failed_redacted\""))
        #expect(adapterSource.contains("static let senderJoinSuccessReason = \"sender_join_success_redacted\""))
        #expect(adapterSource.contains("static let defaultDisabled = SalemXSenderSideLiveKitJoinActivation(armed: false,"))

        #expect(adapterSource.contains("let present = true"))
        #expect(adapterSource.contains("let debugOnly = true"))
        #expect(adapterSource.contains("let requiresSenderReadiness = true"))
        #expect(adapterSource.contains("let requiresSameRoom = true"))
        #expect(adapterSource.contains("let audioOnly = true"))
        #expect(adapterSource.contains("let videoAllowed = false"))
        #expect(adapterSource.contains("let matrixEventsAllowed = false"))
        #expect(adapterSource.contains("let rawIdentifiersLogged = false"))
        #expect(adapterSource.contains("!armed && !triggered && !consumed && !repeated"))

        #expect(adapterSource.contains("sender_side_livekit_join_activation_present=\\(senderSideLiveKitJoinActivationPresent)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_debug_only=\\(senderSideLiveKitJoinActivationDebugOnly)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_default_disabled=\\(senderSideLiveKitJoinActivationDefaultDisabled)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_requires_sender_readiness=\\(senderSideLiveKitJoinActivationRequiresSenderReadiness)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_requires_same_room=\\(senderSideLiveKitJoinActivationRequiresSameRoom)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_audio_only=\\(senderSideLiveKitJoinActivationAudioOnly)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_video_allowed=\\(senderSideLiveKitJoinActivationVideoAllowed)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_matrix_events_allowed=\\(senderSideLiveKitJoinActivationMatrixEventsAllowed)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_raw_identifiers_logged=\\(senderSideLiveKitJoinActivationRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_armed=\\(senderSideLiveKitJoinActivationArmed)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_triggered=\\(senderSideLiveKitJoinActivationTriggered)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_consumed=\\(senderSideLiveKitJoinActivationConsumed)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_repeated=\\(senderSideLiveKitJoinActivationRepeated)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_blocked_reason=\\(senderSideLiveKitJoinActivationBlockedReason)"))

        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationPresent = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.present"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationDebugOnly = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.debugOnly"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationDefaultDisabled = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.isDefaultDisabled"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationRequiresSenderReadiness = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.requiresSenderReadiness"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationRequiresSameRoom = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.requiresSameRoom"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationAudioOnly = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.audioOnly"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationVideoAllowed = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.videoAllowed"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationMatrixEventsAllowed = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.matrixEventsAllowed"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationRawIdentifiersLogged = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.rawIdentifiersLogged"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationArmed = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.armed"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationTriggered = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.triggered"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationConsumed = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.consumed"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationRepeated = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.repeated"))
        #expect(adapterSource.contains("var senderSideLiveKitJoinActivationBlockedReason = SalemXSenderSideLiveKitJoinActivation.defaultDisabled.blockedReason"))

        #expect(adapterSource.contains("private static var senderSideLiveKitJoinActivation = SalemXSenderSideLiveKitJoinActivation.defaultDisabled"))
        #expect(adapterSource.contains("let previousActivation = senderSideLiveKitJoinActivation"))
        #expect(adapterSource.contains("let repeated = requested && previousActivation.consumed"))
        #expect(adapterSource.contains("let senderReadinessMissing = !readinessHook.armed"))
        #expect(adapterSource.contains("|| !readinessHook.matrixSessionReady"))
        #expect(adapterSource.contains("|| !readinessHook.expectedUserMatched"))
        #expect(adapterSource.contains("|| !readinessHook.credentialsReady"))
        #expect(adapterSource.contains("let sameRoomReadinessMissing = !readinessHook.sameRoomReady"))
        #expect(adapterSource.contains("finalResult = SalemXSenderSideLiveKitJoinHook.blockedResult"))
        #expect(adapterSource.contains("finalResult = SalemXSenderSideLiveKitJoinHook.notRequestedResult"))
        #expect(adapterSource.contains("finalErrorBucket = joinDiagnostics.errorBucket == \"none\" ? SalemXSenderSideLiveKitJoinActivation.senderReadinessMissingReason : joinDiagnostics.errorBucket"))
        #expect(adapterSource.contains("finalErrorBucket = joinDiagnostics.errorBucket == \"none\" ? SalemXSenderSideLiveKitJoinActivation.sameRoomReadinessMissingReason : joinDiagnostics.errorBucket"))
        #expect(adapterSource.contains("finalErrorBucket = \"sender_runtime_bridge_required_redacted\""))
        #expect(adapterSource.contains("activationBlockedReason = \"sender_runtime_bridge_required_redacted\""))
        #expect(adapterSource.contains("let joinDiagnostics = SalemXSenderJoinFailureDiagnostics.defaultDisabled"))
        #expect(adapterSource.contains("let transportDiagnostics = SalemXSenderTransportFailureDiagnostics.defaultDisabled"))
        #expect(adapterSource.contains("let transportErrorSurface = SalemXSenderTransportErrorSurface.defaultDisabled"))
        #expect(!adapterSource.contains("let requestedResult = redactedSenderSideLiveKitJoinResultQueryItem(components)"))
        #expect(!adapterSource.contains("let diagnostics = senderJoinDiagnostics(components: components,"))
        #expect(adapterSource.contains("triggered: requested"))
        #expect(adapterSource.contains("consumed: requested && !repeated"))
        #expect(adapterSource.contains("senderSideLiveKitJoinActivation = activation"))
        #expect(adapterSource.contains("summary.recordSenderSideLiveKitJoinActivation(activation)"))

        #expect(adapterSource.contains("mutating func recordSenderSideLiveKitJoinActivation(_ activation: SalemXSenderSideLiveKitJoinActivation)"))
        #expect(adapterSource.contains("senderSideLiveKitJoinActivationArmed = activation.armed"))
        #expect(adapterSource.contains("senderSideLiveKitJoinActivationTriggered = activation.triggered"))
        #expect(adapterSource.contains("senderSideLiveKitJoinActivationConsumed = activation.consumed"))
        #expect(adapterSource.contains("senderSideLiveKitJoinActivationRepeated = activation.repeated"))
        #expect(adapterSource.contains("senderSideLiveKitJoinActivationBlockedReason = activation.blockedReason"))
        #expect(adapterSource.contains("let senderSideLiveKitJoinActivationSnapshot = senderSideLiveKitJoinActivation"))
        #expect(adapterSource.contains("baseSummary.recordSenderSideLiveKitJoinActivation(senderSideLiveKitJoinActivationSnapshot)"))

        #expect(adapterSource.contains("sender_join_hook_not_armed_redacted"))
        #expect(adapterSource.contains("sender_join_not_requested_redacted"))
        #expect(adapterSource.contains("sender_join_blocked_redacted"))
        #expect(adapterSource.contains("sender_join_failed_redacted"))
        #expect(adapterSource.contains("sender_join_success_but_remote_missing_redacted"))
        #expect(adapterSource.contains("remote_participant_seen_redacted"))
        #expect(adapterSource.contains("remote_audio_track_missing_redacted"))
        #expect(adapterSource.contains("remote_liveness_not_observed_redacted"))

        #expect(adapterSource.contains("summary.mediaConnectRequested = false"))
        #expect(adapterSource.contains("summary.mediaConnectAttempted = false"))
        #expect(adapterSource.contains("summary.liveKitJoinRequested = false"))
        #expect(adapterSource.contains("summary.liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("summary.microphonePermissionRequested = false"))
        #expect(adapterSource.contains("summary.cameraPermissionRequested = false"))
        #expect(adapterSource.contains("summary.matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("summary.realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderSideLiveKitJoinActivationRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderSideLiveKitJoinActivationVideoAllowed = true"))
        #expect(!adapterSource.contains("senderSideLiveKitJoinActivationMatrixEventsAllowed = true"))
    }

    @Test
    // swiftlint:disable:next function_body_length
    func senderRuntimeLiveKitJoinBridgeUsesRuntimeCallbacksNotQueryOutcomes() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let legacyHookStart = try #require(adapterSource.range(of: "private static func armSenderSideLiveKitJoinURLHook")?.lowerBound)
        let legacyDiagnosticsStart = try #require(adapterSource.range(of: "private static func senderJoinDiagnostics")?.lowerBound)
        let legacyHookSource = String(adapterSource[legacyHookStart..<legacyDiagnosticsStart])
        let referenceHandoffStart = try #require(adapterSource.range(of: "private static func armSenderPendingMetadataReferenceHandoffURLHook")?.lowerBound)
        let referenceHandoffEnd = try #require(adapterSource.range(of: "private static func armSenderSideLiveKitJoinURLHook")?.lowerBound)
        let referenceHandoffSource = String(adapterSource[referenceHandoffStart..<referenceHandoffEnd])
        let runtimeHookStart = try #require(adapterSource.range(of: "private static func startSenderRuntimeLiveKitJoinURLHook")?.lowerBound)
        let runtimeFetchStart = try #require(adapterSource.range(of: "@MainActor\n    private static func fetchSenderRuntimePendingMetadata")?.lowerBound)
        let runtimeHookSource = String(adapterSource[runtimeHookStart..<runtimeFetchStart])

        #expect(adapterSource.contains("private static let senderPendingMetadataReferenceHandoffURLHookPath = \"/direct-call/sender-pending-metadata-reference-handoff\""))
        #expect(adapterSource.contains("private static let senderRuntimeLiveKitJoinURLHookPath = \"/direct-call/sender-runtime-livekit-join\""))
        #expect(adapterSource.contains("private static let senderRuntimeLiveKitJoinConfirmation = \"RUN_2_48Z_REAL_SENDER_RUNTIME_JOIN\""))
        #expect(adapterSource.contains("private static let senderRuntimeLiveKitJoinProofFileName = \"salemx-sender-runtime-livekit-join-proof.txt\""))
        #expect(adapterSource.contains("private struct SalemXSenderPendingMetadataReferenceHandoff"))
        #expect(adapterSource.contains("private struct SalemXSenderRuntimeLiveKitJoinProofSummary"))
        #expect(adapterSource.contains("proof_source=\\(proofSource)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_default_disabled=\\(bridgeDefaultDisabled)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_one_shot=\\(bridgeOneShot)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_repeated=\\(bridgeRepeated)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_state_repair_present=\\(bridgeStateRepairPresent)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_state_repair_debug_only=\\(bridgeStateRepairDebugOnly)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_state_repair_raw_identifiers_logged=\\(bridgeStateRepairRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_arm_generation_changed=\\(bridgeArmGenerationChanged)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_trigger_generation_matches_arm=\\(bridgeTriggerGenerationMatchesArm)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_stale_generation_detected=\\(bridgeStaleGenerationDetected)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_repeated_only_after_consumed=\\(bridgeRepeatedOnlyAfterConsumed)"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_state_classification=\\(bridgeStateClassification)"))
        #expect(adapterSource.contains("sender_runtime_join_uses_restored_matrix_session=\\(restoredMatrixSessionUsed)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_present=\\(pendingMetadataReferenceHandoffPresent)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_debug_only=\\(pendingMetadataReferenceHandoffDebugOnly)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_armed_before_sender_trigger=\\(pendingMetadataReferenceHandoffArmedBeforeSenderTrigger)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_received_by_sender_runtime=\\(pendingMetadataReferenceHandoffReceivedBySenderRuntime)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_source=\\(pendingMetadataReferenceHandoffSource)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_raw_reference_logged=\\(pendingMetadataReferenceHandoffRawReferenceLogged)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_raw_metadata_logged=\\(pendingMetadataReferenceHandoffRawMetadataLogged)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_raw_room_logged=\\(pendingMetadataReferenceHandoffRawRoomLogged)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_raw_call_logged=\\(pendingMetadataReferenceHandoffRawCallLogged)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_raw_user_logged=\\(pendingMetadataReferenceHandoffRawUserLogged)"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_handoff_raw_device_logged=\\(pendingMetadataReferenceHandoffRawDeviceLogged)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_reference_redacted=\\(pendingMetadataReferenceRedacted)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_reference_matches_invite_sender_memory=\\(pendingMetadataReferenceMatchesInviteSenderMemory)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_reference_matches_sender_view_route=\\(pendingMetadataReferenceMatchesSenderViewRoute)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_fetch_authorized=\\(pendingMetadataFetchAuthorized)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_fetch_error_bucket=\\(pendingMetadataFetchErrorBucket)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_call_binding_present=\\(pendingMetadataCallBindingPresent)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_room_binding_present=\\(pendingMetadataRoomBindingPresent)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_peer_binding_present=\\(pendingMetadataPeerBindingPresent)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_direction_valid=\\(pendingMetadataDirectionValid)"))
        #expect(adapterSource.contains("sender_runtime_join_pending_metadata_intent_audio=\\(pendingMetadataIntentAudio)"))
        #expect(adapterSource.contains("sender_runtime_join_metadata_direction=\\(metadataDirection)"))
        #expect(adapterSource.contains("sender_runtime_join_metadata_intent=\\(metadataIntent)"))
        #expect(adapterSource.contains("sender_runtime_join_credentials_requested=\\(credentialsRequested)"))
        #expect(adapterSource.contains("sender_runtime_join_token_redacted=\\(tokenRedacted)"))
        #expect(adapterSource.contains("sender_runtime_join_url_redacted=\\(urlRedacted)"))
        #expect(adapterSource.contains("sender_runtime_join_executor_shared=\\(executorShared)"))
        #expect(adapterSource.contains("sender_runtime_join_executor_invoked=\\(executorInvoked)"))
        #expect(adapterSource.contains("sender_runtime_join_runtime_result=\\(runtimeResult)"))
        #expect(adapterSource.contains("sender_runtime_join_runtime_derived=\\(runtimeDerived)"))
        #expect(adapterSource.contains("sender_runtime_join_query_outcome_ignored=\\(queryOutcomeIgnored)"))
        #expect(adapterSource.contains("sender_livekit_room_connected=\\(senderLiveKitRoomConnected)"))
        #expect(adapterSource.contains("sender_livekit_room_disconnected=\\(senderLiveKitRoomDisconnected)"))
        #expect(adapterSource.contains("sender_cleanup_result=\\(senderCleanupResult)"))
        #expect(adapterSource.contains("sender_connected_signal_handoff_present=\\(senderConnectedSignalHandoffPresent)"))
        #expect(adapterSource.contains("sender_connected_signal_handoff_debug_only=\\(senderConnectedSignalHandoffDebugOnly)"))
        #expect(adapterSource.contains("sender_connected_signal_handoff_raw_identifiers_logged=\\(senderConnectedSignalHandoffRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_connected_signal_emitted=\\(senderConnectedSignalEmitted)"))
        #expect(adapterSource.contains("sender_connected_signal_emit_source=\\(senderConnectedSignalEmitSource)"))
        #expect(adapterSource.contains("sender_connected_signal_emitted_after_runtime_join_success=\\(senderConnectedSignalEmittedAfterRuntimeJoinSuccess)"))
        #expect(adapterSource.contains("sender_connected_signal_opaque_correlation_present=\\(senderConnectedSignalOpaqueCorrelationPresent)"))
        #expect(adapterSource.contains("sender_connected_signal_raw_room_logged=\\(senderConnectedSignalRawRoomLogged)"))
        #expect(adapterSource.contains("sender_connected_signal_raw_call_logged=\\(senderConnectedSignalRawCallLogged)"))
        #expect(adapterSource.contains("sender_connected_signal_raw_user_logged=\\(senderConnectedSignalRawUserLogged)"))
        #expect(adapterSource.contains("sender_connected_signal_raw_device_logged=\\(senderConnectedSignalRawDeviceLogged)"))
        #expect(adapterSource.contains("sender_local_audio_publish_requested=\\(senderLocalAudioPublishRequested)"))
        #expect(adapterSource.contains("sender_local_audio_publish_allowed=\\(senderLocalAudioPublishAllowed)"))
        #expect(adapterSource.contains("sender_local_audio_publish_result=\\(senderLocalAudioPublishResult)"))
        #expect(adapterSource.contains("sender_local_audio_muted_state_bucket=\\(senderLocalAudioMutedStateBucket)"))
        #expect(adapterSource.contains("sender_audio_session_activation_observed=\\(senderAudioSessionActivationObserved)"))
        #expect(adapterSource.contains("sender_microphone_permission_requested=\\(microphonePermissionRequested)"))
        #expect(adapterSource.contains("sender_microphone_permission_result_bucket=\\(senderMicrophonePermissionResultBucket)"))
        #expect(adapterSource.contains("sender_runtime_join_audio_only=\\(audioOnly)"))
        #expect(adapterSource.contains("sender_runtime_join_video_allowed=\\(videoAllowed)"))
        #expect(adapterSource.contains("sender_runtime_join_matrix_events_allowed=\\(matrixEventsAllowed)"))
        #expect(adapterSource.contains("sender_camera_permission_requested=\\(cameraPermissionRequested)"))
        #expect(adapterSource.contains("sender_matrix_event_emit_requested=\\(matrixEventEmitRequested)"))
        #expect(adapterSource.contains("sender_real_call_flow_started=\\(realCallFlowStarted)"))

        #expect(adapterSource.contains("senderRuntimeLiveKitJoinConsumed"))
        #expect(adapterSource.contains("private static var senderRuntimeLiveKitJoinArmGeneration = 0"))
        #expect(adapterSource.contains("private static var senderRuntimeLiveKitJoinConsumedGeneration: Int?"))
        #expect(adapterSource.contains("senderPendingMetadataReferenceHandoff"))
        #expect(adapterSource.contains("senderRuntimeLiveKitClientFactory"))
        #expect(adapterSource.contains("installSenderRuntimeLiveKitClientFactoryForTests"))
        #expect(adapterSource.contains("resetSenderRuntimeLiveKitClientFactoryForTests"))
        #expect(adapterSource.contains("senderPendingMetadataFetchURL(reference: reference)"))
        #expect(adapterSource.contains("components.path = pendingMetadataEndpointPathPrefix + \"/\" + encodedReference + \"/sender\""))
        #expect(adapterSource.contains("directCallSessionFromSenderPendingMetadata(data: data)"))
        #expect(adapterSource.contains("payload[\"direction\"] as? String == \"outgoing\""))
        #expect(adapterSource.contains("direction: .outgoing"))
        #expect(adapterSource.contains("DirectCallLiveKitTokenProvider(tokenClient: tokenClient)"))
        #expect(adapterSource.contains("let result = await tokenProvider.connectionInfo(for: session)"))
        #expect(adapterSource.contains("DirectCallLiveKitMediaKeyStore()"))
        #expect(adapterSource.contains("DirectCallLiveKitE2EEContextProvider(keyStore: keyStore)"))
        #expect(adapterSource.contains("let executor = DirectCallLiveKitConnectExecutor(liveKitClient: client)"))
        #expect(adapterSource.contains("let result = await executor.connectAudio(connectionInfo: connectionInfo, e2eeContext: e2eeContext)"))
        #expect(adapterSource.contains("localAudioPublishResult = await client.setMicrophoneEnabled(true)"))
        #expect(adapterSource.contains("summary.markRuntime(result)"))
        #expect(adapterSource.contains("summary.markLocalAudioPublish(localAudioPublishResult)"))
        #expect(adapterSource.contains("propagateSenderRuntimeJoinTerminalToReceiverObservation(summary)"))
        #expect(adapterSource.contains("summary.recordSenderSideLiveKitJoinResult(requested: true"))
        #expect(adapterSource.contains("summary.recordSenderRuntimeLocalAudioPublish(senderSummary)"))
        #expect(adapterSource.contains("summary.activateRemoteParticipantObservationRuntimeWindowIfNeeded()"))
        #expect(adapterSource.contains("senderLiveKitRoomConnected = true"))
        #expect(adapterSource.contains("senderLiveKitRoomDisconnected = false"))
        #expect(adapterSource.contains("senderCleanupResult = \"deferred_for_receiver_observation_redacted\""))
        #expect(adapterSource.contains("senderConnectedSignalEmitted = true"))
        #expect(adapterSource.contains("senderConnectedSignalEmitSource = \"sender_runtime_livekit_join_redacted\""))
        #expect(adapterSource.contains("senderConnectedSignalEmittedAfterRuntimeJoinSuccess = true"))
        #expect(adapterSource.contains("senderConnectedSignalOpaqueCorrelationPresent = pendingMetadataReferenceMatchesInviteSenderMemory || pendingMetadataReferenceMatchesSenderViewRoute"))
        #expect(adapterSource.contains("mutating func markLocalAudioPublish(_ result: Result<Void, DirectCallMediaError>)"))
        #expect(adapterSource.contains("senderLocalAudioPublishAllowed = runtimeResult == \"success_redacted\" && audioOnly && !videoAllowed && !matrixEventsAllowed"))
        #expect(adapterSource.contains("senderLocalAudioMutedStateBucket = \"unmuted_redacted\""))
        #expect(adapterSource.contains("senderMicrophonePermissionResultBucket = DirectCallDiagnosticMediaFailureReason(error).rawValue"))
        #expect(adapterSource.contains("bridgeStateClassification = \"sender_runtime_join_connected_redacted\""))
        #expect(adapterSource.contains("bridgeStateClassification = \"sender_runtime_join_not_connected_redacted\""))
        #expect(adapterSource.contains("senderLiveKitRoomDisconnected = true"))
        #expect(adapterSource.contains("senderCleanupResult = \"completed_redacted\""))
        #expect(!adapterSource.contains("bridgeStateRepairRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalHandoffRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalRawRoomLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalRawCallLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalRawUserLogged = true"))
        #expect(!adapterSource.contains("senderConnectedSignalRawDeviceLogged = true"))

        #expect(!legacyHookSource.contains("redactedSenderSideLiveKitJoinResultQueryItem"))
        #expect(!legacyHookSource.contains("senderJoinDiagnostics(components:"))
        #expect(legacyHookSource.contains("sender_runtime_bridge_required_redacted"))
        #expect(referenceHandoffSource.contains("pending_metadata_reference"))
        #expect(referenceHandoffSource.contains("invite_response_redacted"))
        #expect(referenceHandoffSource.contains("senderRuntimeLiveKitJoinArmGeneration += 1"))
        #expect(referenceHandoffSource.contains("senderRuntimeLiveKitJoinConsumed = false"))
        #expect(referenceHandoffSource.contains("senderRuntimeLiveKitJoinConsumedGeneration = nil"))
        #expect(referenceHandoffSource.contains("summary.markReferenceHandoff(handoff, armGenerationChanged: armGenerationChanged)"))
        #expect(runtimeHookSource.contains("confirm"))
        #expect(runtimeHookSource.contains("senderPendingMetadataReferenceHandoff"))
        #expect(runtimeHookSource.contains("handoff.receivedByRuntimeCopy()"))
        #expect(runtimeHookSource.contains("let currentArmGeneration = senderRuntimeLiveKitJoinArmGeneration"))
        #expect(runtimeHookSource.contains("let consumedGeneration = senderRuntimeLiveKitJoinConsumedGeneration"))
        #expect(runtimeHookSource.contains("let triggerGenerationMatchesArm = confirmed && referencePresent && handoff.armed && currentArmGeneration > 0"))
        #expect(runtimeHookSource.contains("let staleGenerationDetected = confirmed && senderRuntimeLiveKitJoinConsumed && consumedGeneration != currentArmGeneration"))
        #expect(runtimeHookSource.contains("let consumedCurrentGeneration = confirmed && senderRuntimeLiveKitJoinConsumed && consumedGeneration == currentArmGeneration"))
        #expect(runtimeHookSource.contains("let repeated = consumedCurrentGeneration"))
        #expect(runtimeHookSource.contains("senderRuntimeLiveKitJoinConsumedGeneration = currentArmGeneration"))
        #expect(runtimeHookSource.contains("repeatedOnlyAfterConsumed: repeatedOnlyAfterConsumed"))
        #expect(!runtimeHookSource.contains("components?.queryItems?.first { $0.name == \"pending_metadata_reference\" }"))
        #expect(!runtimeHookSource.contains("sender_join_result"))
        #expect(!runtimeHookSource.contains("join_result"))
        #expect(!runtimeHookSource.contains("sender_transport_result"))
        #expect(!runtimeHookSource.contains("sender_livekit_sdk_timeline_final_classification"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_sender_memory_missing_redacted"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_missing_redacted"))
        #expect(adapterSource.contains("sender_pending_metadata_reference_mismatch_redacted"))
        #expect(adapterSource.contains("sender_pending_metadata_fetch_unauthorized_redacted"))
        #expect(adapterSource.contains("sender_pending_metadata_fetch_not_found_redacted"))
        #expect(adapterSource.contains("sender_pending_metadata_call_binding_missing_redacted"))
        #expect(adapterSource.contains("sender_pending_metadata_room_binding_missing_redacted"))
        #expect(adapterSource.contains("sender_pending_metadata_peer_binding_missing_redacted"))
        #expect(adapterSource.contains("sender_pending_metadata_direction_invalid_redacted"))
        #expect(adapterSource.contains("sender_pending_metadata_intent_invalid_redacted"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_triggered_current_generation_redacted"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_stale_generation_redacted"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_repeated_after_consumed_redacted"))
        #expect(adapterSource.contains("sender_runtime_join_bridge_repeated_before_consumed_redacted"))
        #expect(adapterSource.contains("sender_runtime_join_executor_not_invoked_redacted"))
        #expect(adapterSource.contains("sender_runtime_join_connected_redacted"))
        #expect(adapterSource.contains("sender_runtime_join_not_connected_redacted"))
        #expect(!adapterSource.contains("sender_runtime_join_video_allowed = true"))
        #expect(!adapterSource.contains("sender_runtime_join_matrix_events_allowed = true"))
    }

    @Test
    func senderRuntimeAccessibleProofMirrorWritesLibraryTmpDebugOnlySurface() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let writerStart = try #require(adapterSource.range(of: "@discardableResult private static func writeSenderRuntimeLiveKitJoinProof")?.lowerBound)
        let genericWriterStart = try #require(adapterSource.range(of: "@discardableResult private static func writeProof(_ proof: String, fileName: String) -> String")?.lowerBound)
        let writerSource = String(adapterSource[writerStart..<genericWriterStart])

        #expect(adapterSource.contains("private static let senderRuntimeAccessibleProofMirrorFileName = senderRuntimeLiveKitJoinProofFileName"))
        #expect(adapterSource.contains("private static func senderRuntimeAccessibleProofMirrorLines() -> String"))
        #expect(adapterSource.contains("@discardableResult private static func writeSenderRuntimeAccessibleProofMirror(_ proof: String) -> String"))
        #expect(adapterSource.contains("sender_runtime_accessible_proof_surface_written=true"))
        #expect(adapterSource.contains("sender_runtime_accessible_proof_surface_bucket=library_tmp_debug_mirror"))
        #expect(writerSource.contains("#if DEBUG"))
        #expect(writerSource.contains("writeSenderRuntimeAccessibleProofMirror(proof)"))
        #expect(writerSource.contains("FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first"))
        #expect(writerSource.contains("FileManager.default.temporaryDirectory"))
        #expect(writerSource.contains("writeProof(mirroredProof"))
        #expect(writerSource.contains("return result"))
        #expect(adapterSource.contains("@discardableResult private static func writeProof(_ proof: String, fileName: String, directoryURL: URL) -> String"))
        #expect(adapterSource.contains("let proofURL = directoryURL.appending(component: fileName)"))
    }

    @Test
    func senderRuntimeDocumentsTerminalProofIsDebugOnlyAndRedacted() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let appDelegateSource = try Self.sourceFile("ElementX/Sources/Application/AppDelegate.swift")
        let writerStart = try #require(adapterSource.range(of: "@discardableResult private static func writeSenderRuntimeLiveKitJoinProof")?.lowerBound)
        let genericWriterStart = try #require(adapterSource.range(of: "@discardableResult private static func writeProof(_ proof: String, fileName: String) -> String")?.lowerBound)
        let writerSource = String(adapterSource[writerStart..<genericWriterStart])
        let terminalWriterStart = try #require(adapterSource.range(of: "@discardableResult private static func writeSenderRuntimeTerminalProof")?.lowerBound)
        let terminalWriterEnd = try #require(adapterSource.range(of: "@discardableResult private static func writeProof(_ proof: String, fileName: String) -> String")?.lowerBound)
        let terminalWriterSource = String(adapterSource[terminalWriterStart..<terminalWriterEnd])

        #expect(adapterSource.contains("private static let senderRuntimeTerminalProofFileName = \"salemx-sender-runtime-terminal-proof.txt\""))
        #expect(adapterSource.contains("private static let debugProofExportHealthFileName = \"salemx-debug-proof-export-health.txt\""))
        #expect(writerSource.contains("#if DEBUG"))
        #expect(writerSource.contains("writeSenderRuntimeTerminalProof(proof)"))
        #expect(terminalWriterSource.contains("private static func debugDocumentsProofExportURL(fileName: String) -> URL?"))
        #expect(terminalWriterSource.contains("FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?"))
        #expect(terminalWriterSource.contains(".appending(component: fileName)"))
        #expect(terminalWriterSource.contains("@discardableResult private static func writeDebugDocumentsProof(_ proof: String, fileName: String) -> String"))
        #expect(terminalWriterSource.contains("debugDocumentsProofExportURL(fileName: fileName)"))
        #expect(terminalWriterSource.contains("emitDebugProofConsole(terminalProof)"))
        #expect(terminalWriterSource.contains("emitDebugProofOSLog(terminalProof)"))
        #expect(terminalWriterSource.contains("salemx_sender_runtime_terminal_proof=true"))
        #expect(terminalWriterSource.contains("proof_generation=\\(senderRuntimeField(\"proof_generation\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_documents_terminal_proof_written=true"))
        #expect(terminalWriterSource.contains("sender_atomic_trigger_file_seen_by_app=\\(triggerSeen)"))
        #expect(terminalWriterSource.contains("sender_atomic_trigger_consumed_by_app=\\(triggerConsumed)"))
        #expect(terminalWriterSource.contains("sender_atomic_trigger_consumer_lifecycle_seen=\\(lifecycleSeen)"))
        #expect(terminalWriterSource.contains("sender_no_media_runtime_trigger_attempted=\\(senderRuntimeBoolField(\"sender_no_media_runtime_trigger_attempted\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_no_media_runtime_trigger_terminal_observed=\\(senderRuntimeBoolField(\"sender_no_media_runtime_trigger_terminal_observed\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_authorized_metadata_source_available=\\(senderRuntimeBoolField(\"sender_authorized_metadata_source_available\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_uses_receiver_pending_metadata_reference=\\(senderRuntimeBoolField(\"sender_uses_receiver_pending_metadata_reference\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_media_credentials_requested=\\(senderRuntimeBoolField(\"sender_media_credentials_requested\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_media_credentials_request_seen=\\(senderRuntimeBoolField(\"sender_media_credentials_request_seen\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_media_credentials_http_status_bucket=\\(senderRuntimeField(\"sender_media_credentials_http_status_bucket\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_media_credentials_result_bucket=\\(senderRuntimeField(\"sender_media_credentials_result_bucket\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_media_credentials_failure_reason_bucket=\\(senderRuntimeField(\"sender_media_credentials_failure_reason_bucket\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_media_connect_requested=\\(senderRuntimeBoolField(\"sender_media_connect_requested\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_livekit_join_triggered=\\(senderRuntimeBoolField(\"sender_livekit_join_triggered\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_permissions_requested=\\(senderRuntimeBoolField(\"sender_permissions_requested\", in: fields))"))
        #expect(terminalWriterSource.contains("sender_runtime_boundary_blocked_reason=\\(senderRuntimeField(\"sender_runtime_boundary_blocked_reason\", in: fields))"))
        #expect(terminalWriterSource.contains("raw_values_printed=false"))
        #expect(terminalWriterSource.contains("APNs_sent=false"))
        #expect(terminalWriterSource.contains("media_connect_requested=false"))
        #expect(terminalWriterSource.contains("livekit_join_triggered=false"))
        #expect(terminalWriterSource.contains("permissions_requested=false"))
        #expect(terminalWriterSource.contains("matrix_call_media_event_emitted=false"))
        #expect(terminalWriterSource.contains("full_flow_started=false"))
        #expect(terminalWriterSource.contains("writeDebugDocumentsProof(senderRuntimeTerminalProofLines(from: proof),"))
        #expect(terminalWriterSource.contains("fileName: senderRuntimeTerminalProofFileName"))
        #expect(terminalWriterSource.contains("senderRuntimeProofFields(from: proof)"))
        #expect(terminalWriterSource.contains("allowedScalars"))
        #expect(!terminalWriterSource.contains("pending_metadata_reference="))
        #expect(!terminalWriterSource.contains("room_id="))
        #expect(!terminalWriterSource.contains("call_id="))
        #expect(appDelegateSource.contains("SalemXPushKitRegistrationSmokeDebugBridge.recordDebugProofExportHealthOnLaunch()"))
        #expect(appDelegateSource.contains("SalemXPushKitRegistrationSmokeDebugBridge.consumeDebugProcessLaunchTriggerIfNeeded()"))
        #expect(appDelegateSource.contains("func applicationDidBecomeActive(_ application: UIApplication)"))
        #expect(appDelegateSource.contains("#if DEBUG\n        SalemXPushKitRegistrationSmokeDebugBridge.recordDebugProofExportHealthOnForegroundActivation()\n        #endif"))
        #expect(adapterSource.contains("import OSLog"))
        #expect(adapterSource.contains("private static let debugProofOSLog = Logger(subsystem: \"kz.salemx.debug.proof\", category: \"direct-call\")"))
        #expect(adapterSource.contains("private static func emitDebugProofConsole(_ proof: String)"))
        #expect(adapterSource.contains("FileHandle.standardError.write(data)"))
        #expect(adapterSource.contains("private static func emitDebugProofOSLog(_ proof: String)"))
        #expect(adapterSource.contains("debugProofOSLog.info(\"\\(proof, privacy: .public)\")"))
        #expect(adapterSource.contains("static func recordDebugProofExportHealthOnLaunch()"))
        #expect(adapterSource.contains("static func recordDebugProofExportHealthOnForegroundActivation()"))
        #expect(adapterSource.contains("static func consumeDebugProcessLaunchTriggerIfNeeded()"))
        #expect(adapterSource.contains("senderProcessLaunchTriggerEnvironmentKey"))
        #expect(adapterSource.contains("senderProcessLaunchTriggerArgumentPrefix"))
        #expect(adapterSource.contains("senderProcessLaunchSyntheticTriggerValue"))
        #expect(adapterSource.contains("salemx_debug_process_trigger_synthetic_no_metadata"))
        #expect(adapterSource.contains("senderProcessLaunchTriggerTransportBucket = \"process_launch_constant_redacted\""))
        #expect(adapterSource.contains("markDebugProcessLaunchSyntheticTrigger()"))
        #expect(adapterSource.contains("sender_process_launch_trigger_seen_by_app=\\(senderProcessLaunchTriggerSeenByApp)"))
        #expect(adapterSource.contains("sender_process_launch_trigger_consumed_by_app=\\(senderProcessLaunchTriggerConsumedByApp)"))
        #expect(adapterSource.contains("sender_process_launch_trigger_transport_bucket=\\(senderProcessLaunchTriggerTransportBucket)"))
        #expect(adapterSource.contains("sender_process_launch_trigger_seen_by_app=\\(senderRuntimeBoolField(\"sender_process_launch_trigger_seen_by_app\", in: fields))"))
        #expect(adapterSource.contains("sender_process_launch_trigger_consumed_by_app=\\(senderRuntimeBoolField(\"sender_process_launch_trigger_consumed_by_app\", in: fields))"))
        #expect(adapterSource.contains("sender_process_launch_trigger_transport_bucket=\\(senderRuntimeField(\"sender_process_launch_trigger_transport_bucket\", in: fields))"))
        #expect(adapterSource.contains("pendingMetadataSenderClaimEndpointPath = \"/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/pending-metadata/sender/claim\""))
        #expect(adapterSource.contains("server_side_sender_metadata_lookup_requested=\\(serverSideSenderMetadataLookupRequested)"))
        #expect(adapterSource.contains("server_side_sender_metadata_lookup_result_bucket=\\(serverSideSenderMetadataLookupResultBucket)"))
        #expect(adapterSource.contains("server_side_sender_metadata_claim_requested=\\(serverSideSenderMetadataClaimRequested)"))
        #expect(adapterSource.contains("server_side_sender_metadata_claim_result_bucket=\\(serverSideSenderMetadataClaimResultBucket)"))
        #expect(adapterSource.contains("server_side_sender_metadata_lookup_requested=\\(senderRuntimeBoolField(\"server_side_sender_metadata_lookup_requested\", in: fields))"))
        #expect(adapterSource.contains("server_side_sender_metadata_claim_result_bucket=\\(senderRuntimeField(\"server_side_sender_metadata_claim_result_bucket\", in: fields))"))
        #expect(adapterSource.contains("senderRuntimeBoundaryBlockedReason = \"synthetic_trigger_no_metadata_redacted\""))
        #expect(adapterSource.contains("private static func recordDebugProofExportHealth(triggerBucket: String)"))
        #expect(adapterSource.contains("salemx_debug_console_health_probe=true"))
        #expect(adapterSource.contains("debug_console_health_written=true"))
        #expect(adapterSource.contains("debug_console_health_trigger_bucket=\\(triggerBucket)"))
        #expect(adapterSource.contains("emitDebugProofConsole(proof)"))
        #expect(adapterSource.contains("salemx_debug_oslog_health_probe=true"))
        #expect(adapterSource.contains("debug_oslog_health_written=true"))
        #expect(adapterSource.contains("debug_oslog_health_trigger_bucket=\\(triggerBucket)"))
        #expect(adapterSource.contains("emitDebugProofOSLog(proof)"))
        #expect(adapterSource.contains("writeDebugDocumentsProof(proof, fileName: debugProofExportHealthFileName)"))
        #expect(adapterSource.contains("debug_documents_proof_export_health_written=true"))
        #expect(adapterSource.contains("debug_documents_proof_export_health_path_bucket=documents_directory"))
        #expect(adapterSource.contains("debug_documents_proof_export_health_trigger_bucket=\\(triggerBucket)"))
        #expect(adapterSource.contains("recordDebugProofExportHealth(triggerBucket: \"foreground_or_launch_redacted\")"))
    }

    @Test
    func senderProcessLaunchClaimEmitsSessionAuthDiagnosticBuckets() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("carpediem_matrix_session_present=\\(carpediemMatrixSessionPresent)"))
        #expect(adapterSource.contains("carpediem_matrix_session_user_bucket=\\(carpediemMatrixSessionUserBucket)"))
        #expect(adapterSource.contains("carpediem_access_token_available_bucket=\\(carpediemAccessTokenAvailableBucket)"))
        #expect(adapterSource.contains("sender_metadata_claim_auth_header_attached=\\(senderMetadataClaimAuthHeaderAttached)"))
        #expect(adapterSource.contains("sender_metadata_claim_auth_source_bucket=\\(senderMetadataClaimAuthSourceBucket)"))
        #expect(adapterSource.contains("app_claim_request_started=\\(appClaimRequestStarted)"))
        #expect(adapterSource.contains("app_claim_request_url_bucket=\\(appClaimRequestURLBucket)"))
        #expect(adapterSource.contains("app_claim_auth_header_present=\\(senderMetadataClaimAuthHeaderAttached)"))
        #expect(adapterSource.contains("app_claim_auth_scheme_bucket=\\(appClaimAuthSchemeBucket)"))
        #expect(adapterSource.contains("app_claim_auth_token_bucket=\\(appClaimAuthTokenBucket)"))
        #expect(adapterSource.contains("app_claim_auth_source_bucket=\\(appClaimAuthSourceBucket)"))
        #expect(adapterSource.contains("app_claim_http_status_bucket=\\(appClaimHTTPStatusBucket)"))
        #expect(adapterSource.contains("server_claim_auth_header_seen=\\(serverClaimAuthHeaderSeen)"))
        #expect(adapterSource.contains("server_claim_auth_scheme_bucket=\\(serverClaimAuthSchemeBucket)"))
        #expect(adapterSource.contains("server_claim_token_validation_bucket=\\(serverClaimTokenValidationBucket)"))
        #expect(adapterSource.contains("server_claim_authenticated_user_bucket=\\(serverClaimAuthenticatedUserBucket)"))
        #expect(adapterSource.contains("server_claim_auth_validation_bucket=\\(serverClaimAuthValidationBucket)"))
        #expect(adapterSource.contains("server_claim_bound_sender_bucket=\\(serverClaimBoundSenderBucket)"))
        #expect(adapterSource.contains("server_claim_bound_device_bucket=\\(serverClaimBoundDeviceBucket)"))
        #expect(adapterSource.contains("session_accessor_source_bucket=\\(sessionAccessorSourceBucket)"))
        #expect(adapterSource.contains("session_accessor_binding_result_bucket=\\(sessionAccessorBindingResultBucket)"))
        #expect(adapterSource.contains("carpediem_matrix_session_present=\\(senderRuntimeBoolField(\"carpediem_matrix_session_present\", in: fields))"))
        #expect(adapterSource.contains("sender_metadata_claim_auth_header_attached=\\(senderRuntimeBoolField(\"sender_metadata_claim_auth_header_attached\", in: fields))"))
        #expect(adapterSource.contains("app_claim_request_started=\\(senderRuntimeBoolField(\"app_claim_request_started\", in: fields))"))
        #expect(adapterSource.contains("app_claim_auth_header_present=\\(senderRuntimeBoolField(\"app_claim_auth_header_present\", in: fields))"))
        #expect(adapterSource.contains("server_claim_auth_header_seen=\\(senderRuntimeBoolField(\"server_claim_auth_header_seen\", in: fields))"))
        #expect(adapterSource.contains("server_claim_token_validation_bucket=\\(senderRuntimeField(\"server_claim_token_validation_bucket\", in: fields))"))
        #expect(adapterSource.contains("server_claim_auth_validation_bucket=\\(senderRuntimeField(\"server_claim_auth_validation_bucket\", in: fields))"))
        #expect(adapterSource.contains("session_accessor_source_bucket=\\(senderRuntimeField(\"session_accessor_source_bucket\", in: fields))"))
        #expect(adapterSource.contains("sessionAccessorSourceBucket = activeSessionAvailable ? \"main_app_session_redacted\" : \"debug_container_missing\""))
        #expect(adapterSource.contains("userIDAvailable: clientProxy?.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false"))
        #expect(adapterSource.contains("authSourceBucket: \"current_session_redacted\""))
        #expect(!adapterSource.contains("sender_metadata_claim_authorization="))
        #expect(!adapterSource.contains("carpediem_matrix_session_user_id="))
    }

    @Test
    func senderRuntimeAccessibleProofMirrorCarriesTerminalNoMediaSafetyFields() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let redactedLinesStart = try #require(adapterSource.range(of: "var redactedLines: [String]")?.lowerBound)
        let debugMarkerStart = try #require(adapterSource.range(of: "mutating func markDebugBuildLaunchMarker()")?.lowerBound)
        let redactedLinesSource = String(adapterSource[redactedLinesStart..<debugMarkerStart])
        let noMediaRunStart = try #require(adapterSource.range(of: "@MainActor\n    private static func runSenderNoMediaRuntimeTrigger")?.lowerBound)
        let runtimeJoinStart = try #require(adapterSource.range(of: "@MainActor\n    private static func runSenderRuntimeLiveKitJoin")?.lowerBound)
        let noMediaRunSource = String(adapterSource[noMediaRunStart..<runtimeJoinStart])

        #expect(redactedLinesSource.contains("sender_debug_atomic_handoff_trigger_file_seen=\\(senderDebugAtomicHandoffTriggerFileSeen)"))
        #expect(redactedLinesSource.contains("sender_debug_atomic_handoff_trigger_consumed=\\(senderDebugAtomicHandoffTriggerConsumed)"))
        #expect(redactedLinesSource.contains("server_side_sender_metadata_lookup_requested=\\(serverSideSenderMetadataLookupRequested)"))
        #expect(redactedLinesSource.contains("server_side_sender_metadata_lookup_result_bucket=\\(serverSideSenderMetadataLookupResultBucket)"))
        #expect(redactedLinesSource.contains("server_side_sender_metadata_claim_requested=\\(serverSideSenderMetadataClaimRequested)"))
        #expect(redactedLinesSource.contains("server_side_sender_metadata_claim_result_bucket=\\(serverSideSenderMetadataClaimResultBucket)"))
        #expect(redactedLinesSource.contains("sender_metadata_claim_auth_header_attached=\\(senderMetadataClaimAuthHeaderAttached)"))
        #expect(redactedLinesSource.contains("app_claim_request_started=\\(appClaimRequestStarted)"))
        #expect(redactedLinesSource.contains("app_claim_request_url_bucket=\\(appClaimRequestURLBucket)"))
        #expect(redactedLinesSource.contains("app_claim_auth_header_present=\\(senderMetadataClaimAuthHeaderAttached)"))
        #expect(redactedLinesSource.contains("app_claim_http_status_bucket=\\(appClaimHTTPStatusBucket)"))
        #expect(redactedLinesSource.contains("server_claim_auth_header_seen=\\(serverClaimAuthHeaderSeen)"))
        #expect(redactedLinesSource.contains("server_claim_token_validation_bucket=\\(serverClaimTokenValidationBucket)"))
        #expect(redactedLinesSource.contains("server_claim_auth_validation_bucket=\\(serverClaimAuthValidationBucket)"))
        #expect(redactedLinesSource.contains("sender_no_media_runtime_trigger_attempted=\\(noMediaRuntimeTriggerAttempted)"))
        #expect(redactedLinesSource.contains("sender_no_media_runtime_trigger_terminal_observed=\\(senderNoMediaRuntimeTriggerTerminalObserved)"))
        #expect(redactedLinesSource.contains("sender_authorized_metadata_source_available=\\(senderAuthorizedMetadataSourceAvailable)"))
        #expect(redactedLinesSource.contains("sender_uses_receiver_pending_metadata_reference=\\(senderUsesReceiverPendingMetadataReference)"))
        #expect(redactedLinesSource.contains("sender_media_credentials_requested=\\(credentialsRequested)"))
        #expect(redactedLinesSource.contains("sender_media_credentials_request_seen=\\(senderMediaCredentialsRequestSeen)"))
        #expect(redactedLinesSource.contains("sender_media_credentials_http_status_bucket=\\(senderMediaCredentialsHTTPStatusBucket)"))
        #expect(redactedLinesSource.contains("sender_media_credentials_result_bucket=\\(credentialsResult)"))
        #expect(redactedLinesSource.contains("sender_media_credentials_failure_reason_bucket=\\(senderMediaCredentialsFailureReasonBucket)"))
        #expect(redactedLinesSource.contains("sender_media_connect_requested=\\(senderMediaConnectRequested)"))
        #expect(redactedLinesSource.contains("sender_livekit_join_triggered=\\(senderLiveKitJoinTriggered)"))
        #expect(redactedLinesSource.contains("sender_permissions_requested=\\(senderPermissionsRequested)"))
        #expect(redactedLinesSource.contains("sender_runtime_boundary_blocked_reason=\\(senderRuntimeBoundaryBlockedReason)"))
        #expect(redactedLinesSource.contains("sender_pending_metadata_raw_identifiers_logged=\\(senderPendingMetadataRawIdentifiersLogged)"))
        #expect(adapterSource.contains("senderPendingMetadataRawIdentifiersLogged = false"))
        #expect(noMediaRunSource.contains("await fetchSenderRuntimePendingMetadata(reference: reference)"))
        #expect(noMediaRunSource.contains("await requestSenderRuntimeCredentials(for: session)"))
        #expect(!noMediaRunSource.contains("DirectCallLiveKitConnectExecutor"))
        #expect(!noMediaRunSource.contains("executor.connectAudio"))
        #expect(!noMediaRunSource.contains("setMicrophoneEnabled(true)"))
        #expect(!noMediaRunSource.contains("sendRealInvite"))
        #expect(!noMediaRunSource.contains("postRealInvite"))
        #expect(!noMediaRunSource.contains("matrixEventEmitRequested = true"))
        #expect(!noMediaRunSource.contains("cameraPermissionRequested = true"))
        #expect(!noMediaRunSource.contains("microphonePermissionRequested = true"))
    }

    @Test
    func senderProcessLaunchServerSideClaimStopsBeforeMediaConnect() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let processLaunchStart = try #require(adapterSource.range(of: "static func consumeDebugProcessLaunchTriggerIfNeeded()")?.lowerBound)
        let healthStart = try #require(adapterSource.range(of: "private static func recordDebugProofExportHealth",
                                                           range: processLaunchStart..<adapterSource.endIndex)?.lowerBound)
        let processLaunchSource = String(adapterSource[processLaunchStart..<healthStart])
        let claimRunStart = try #require(adapterSource.range(of: "@MainActor\n    private static func runServerSideSenderMetadataClaimNoMediaTrigger")?.lowerBound)
        let runtimeJoinStart = try #require(adapterSource.range(of: "@MainActor\n    private static func runSenderRuntimeLiveKitJoin")?.lowerBound)
        let claimRunSource = String(adapterSource[claimRunStart..<runtimeJoinStart])

        #expect(processLaunchSource.contains("await runServerSideSenderMetadataClaimNoMediaTrigger()"))
        #expect(claimRunSource.contains("await waitForServerSideSenderMetadataClaimSessionAvailability()"))
        #expect(claimRunSource.contains("Task.sleep(nanoseconds: 500_000_000)"))
        #expect(claimRunSource.contains("await fetchServerSideSenderMetadataClaim()"))
        #expect(claimRunSource.contains("await requestSenderRuntimeCredentials(for: session)"))
        #expect(claimRunSource.contains("senderMetadataClaimURL()"))
        #expect(claimRunSource.contains("pendingMetadataSenderClaimEndpointPath"))
        #expect(claimRunSource.contains("matrixSessionWhoamiSmokeAvailability()"))
        #expect(claimRunSource.contains("recordServerSideSenderMetadataClaimAuthContext(sessionAvailability"))
        #expect(claimRunSource.contains("authHeaderAttached: true"))
        #expect(claimRunSource.contains("authSourceBucket: \"current_session_redacted\""))
        #expect(claimRunSource.contains("serverSideSenderMetadataClaimAuthValidationBucket(diagnostics)"))
        #expect(claimRunSource.contains("serverSideSenderMetadataClaimBoundSenderBucket(diagnostics)"))
        #expect(claimRunSource.contains("serverSideSenderMetadataClaimBoundDeviceBucket(diagnostics)"))
        #expect(claimRunSource.contains("appClaimHTTPStatusBucket(diagnostics.httpStatusBucket)"))
        #expect(claimRunSource.contains("serverAuthHeaderSeen: diagnostics.serverAuthHeaderSeen"))
        #expect(claimRunSource.contains("serverTokenValidationBucket: diagnostics.serverTokenValidationBucket"))
        #expect(claimRunSource.contains("diagnostics.failureReason == \"auth_rejected\""))
        #expect(claimRunSource.contains("markServerSideSenderMetadataClaimSuccess(session)"))
        #expect(!claimRunSource.contains("DirectCallLiveKitConnectExecutor"))
        #expect(!claimRunSource.contains("executor.connectAudio"))
        #expect(!claimRunSource.contains("setMicrophoneEnabled(true)"))
        #expect(!claimRunSource.contains("sendRealInvite"))
        #expect(!claimRunSource.contains("postRealInvite"))
        #expect(!claimRunSource.contains("matrixEventEmitRequested = true"))
        #expect(!claimRunSource.contains("cameraPermissionRequested = true"))
        #expect(!claimRunSource.contains("microphonePermissionRequested = true"))
        #expect(!claimRunSource.contains("Authorization=\""))
        #expect(!claimRunSource.contains("access_token="))
        #expect(!adapterSource.contains("server_side_sender_metadata_reference="))
        #expect(!adapterSource.contains("pending_metadata_reference=\\(serverSide"))
    }

    @Test
    func senderNoMediaRuntimeTriggerStopsBeforeLiveKitJoinAndMicrophone() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let noMediaHookStart = try #require(adapterSource.range(of: "private static func startSenderNoMediaRuntimeTriggerURLHook")?.lowerBound)
        let noMediaRunStart = try #require(adapterSource.range(of: "@MainActor\n    private static func runSenderNoMediaRuntimeTrigger")?.lowerBound)
        let runtimeJoinStart = try #require(adapterSource.range(of: "@MainActor\n    private static func runSenderRuntimeLiveKitJoin")?.lowerBound)
        let noMediaHookSource = String(adapterSource[noMediaHookStart..<noMediaRunStart])
        let noMediaRunSource = String(adapterSource[noMediaRunStart..<runtimeJoinStart])

        #expect(adapterSource.contains("private static let senderNoMediaRuntimeTriggerURLHookPath = \"/direct-call/sender-no-media-runtime-trigger\""))
        #expect(adapterSource.contains("private static let senderNoMediaRuntimeTriggerConfirmation = \"RUN_2_49N_SENDER_NO_MEDIA_RUNTIME_TRIGGER\""))
        #expect(adapterSource.contains("private static func normalizedDebugURLPath(_ url: URL) -> String?"))
        #expect(adapterSource.contains("if url.host == \"direct-call\""))
        #expect(adapterSource.contains("return \"/direct-call\\(url.path)\""))
        #expect(adapterSource.contains("handleSenderRuntimeURLHook(url, normalizedPath: normalizedPath)"))
        #expect(adapterSource.contains("startSenderNoMediaRuntimeTriggerURLHook(components)"))
        #expect(adapterSource.contains("private static var senderNoMediaRuntimeTriggerConsumed = false"))
        #expect(adapterSource.contains("private static var senderNoMediaRuntimeTriggerConsumedGeneration: Int?"))
        #expect(adapterSource.contains("senderNoMediaRuntimeTriggerConsumed = false"))
        #expect(adapterSource.contains("senderNoMediaRuntimeTriggerConsumedGeneration = nil"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_available=\\(noMediaRuntimeTriggerAvailable)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_debug_only=\\(noMediaRuntimeTriggerDebugOnly)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_default_disabled=\\(noMediaRuntimeTriggerDefaultDisabled)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_one_shot=\\(noMediaRuntimeTriggerOneShot)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_attempted=\\(noMediaRuntimeTriggerAttempted)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_consumed=\\(noMediaRuntimeTriggerConsumed)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_repeated=\\(noMediaRuntimeTriggerRepeated)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_result_bucket=\\(noMediaRuntimeTriggerResultBucket)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_handler_registered_bucket=\\(noMediaRuntimeTriggerHandlerRegisteredBucket)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_terminal_observed=\\(senderNoMediaRuntimeTriggerTerminalObserved)"))
        #expect(adapterSource.contains("sender_no_media_runtime_trigger_raw_identifiers_logged=\\(noMediaRuntimeTriggerRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_debug_build_marker_present=\\(senderDebugBuildMarkerPresent)"))
        #expect(adapterSource.contains("sender_debug_build_expected_head_bucket=\\(senderDebugBuildExpectedHeadBucket)"))
        #expect(adapterSource.contains("sender_debug_url_dispatch_seen=\\(senderDebugURLDispatchSeen)"))
        #expect(adapterSource.contains("sender_debug_url_dispatch_shape_bucket=\\(senderDebugURLDispatchShapeBucket)"))
        #expect(adapterSource.contains("sender_debug_direct_call_route_seen=\\(senderDebugDirectCallRouteSeen)"))
        #expect(adapterSource.contains("sender_debug_no_media_route_seen=\\(senderDebugNoMediaRouteSeen)"))
        #expect(adapterSource.contains("sender_debug_no_media_handler_entry_seen=\\(senderDebugNoMediaHandlerEntrySeen)"))
        #expect(adapterSource.contains("mutating func markDebugBuildLaunchMarker()"))
        #expect(adapterSource.contains("mutating func markDebugURLDispatch(shapeBucket: String)"))
        #expect(adapterSource.contains("mutating func markDebugDirectCallRoute()"))
        #expect(adapterSource.contains("mutating func markDebugNoMediaRoute()"))
        #expect(adapterSource.contains("mutating func markDebugNoMediaHandlerEntry()"))
        #expect(adapterSource.contains("recordSenderDebugURLDispatch(shapeBucket: redactedDebugURLShapeBucket(url))"))
        #expect(adapterSource.contains("recordSenderDebugDirectCallRouteSeen()"))
        #expect(adapterSource.contains("recordSenderDebugNoMediaRouteSeen()"))
        #expect(adapterSource.contains("recordSenderDebugNoMediaHandlerEntrySeen()"))
        Self.assertSenderNoMediaFileTriggerSourceGuards(in: adapterSource)
        Self.assertSenderPendingMetadataFileHandoffSourceGuards(in: adapterSource)
        Self.assertSenderAtomicPendingMetadataHandoffTriggerSourceGuards(in: adapterSource)
        Self.assertSenderPendingMetadataAuthorizationDiagnosticsSourceGuards(in: adapterSource)
        #expect(adapterSource.contains("redactedDebugURLShapeBucket(_ url: URL)"))
        #expect(adapterSource.contains("\"debug_direct_call_redacted\""))
        #expect(adapterSource.contains("\"direct_call_host_redacted\""))
        #expect(adapterSource.contains("\"path_only_direct_call_redacted\""))
        #expect(adapterSource.contains("sender_call_state_after_answer_bucket=\\(senderCallStateAfterAnswerBucket)"))
        #expect(adapterSource.contains("sender_media_credentials_gate_state=\\(senderMediaCredentialsGateState)"))
        #expect(adapterSource.contains("sender_media_credentials_requested=\\(credentialsRequested)"))
        #expect(adapterSource.contains("sender_media_credentials_request_seen=\\(senderMediaCredentialsRequestSeen)"))
        #expect(adapterSource.contains("sender_media_credentials_http_status_bucket=\\(senderMediaCredentialsHTTPStatusBucket)"))
        #expect(adapterSource.contains("sender_media_credentials_result_bucket=\\(credentialsResult)"))
        #expect(adapterSource.contains("sender_media_credentials_failure_reason_bucket=\\(senderMediaCredentialsFailureReasonBucket)"))
        #expect(adapterSource.contains("sender_media_connect_gate_state=\\(senderMediaConnectGateState)"))
        #expect(adapterSource.contains("sender_media_connect_requested=\\(senderMediaConnectRequested)"))
        #expect(adapterSource.contains("sender_livekit_join_triggered=\\(senderLiveKitJoinTriggered)"))
        #expect(adapterSource.contains("sender_permissions_requested=\\(senderPermissionsRequested)"))
        #expect(adapterSource.contains("sender_runtime_boundary_blocked_reason=\\(senderRuntimeBoundaryBlockedReason)"))
        #expect(adapterSource.contains("var senderMediaCredentialsRequestSeen: Bool"))
        #expect(adapterSource.contains("var senderMediaCredentialsFailureReasonBucket: String"))
        #expect(adapterSource.contains("var senderMediaConnectRequested: Bool"))
        #expect(adapterSource.contains("var senderLiveKitJoinTriggered: Bool"))
        #expect(adapterSource.contains("var senderPermissionsRequested: Bool"))
        #expect(adapterSource.contains("var senderNoMediaRuntimeTriggerTerminalObserved: Bool"))
        #expect(adapterSource.contains("mutating func markNoMediaRuntimeTriggerStarted"))
        #expect(adapterSource.contains("noMediaRuntimeTriggerRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("noMediaRuntimeTriggerResultBucket = \"pending_metadata_reference_missing_redacted\""))
        #expect(adapterSource.contains("noMediaRuntimeTriggerResultBucket = \"stale_generation_blocked_redacted\""))
        #expect(adapterSource.contains("sender_no_media_runtime_connect_deferred_redacted"))

        #expect(noMediaHookSource.contains("confirm"))
        #expect(noMediaHookSource.contains("senderNoMediaRuntimeTriggerConfirmation"))
        #expect(noMediaHookSource.contains("senderPendingMetadataReferenceHandoff"))
        #expect(noMediaHookSource.contains("senderNoMediaRuntimeTriggerConsumed"))
        #expect(noMediaHookSource.contains("senderNoMediaRuntimeTriggerConsumedGeneration"))
        #expect(noMediaHookSource.contains("recordSenderDebugNoMediaHandlerEntrySeen()"))
        #expect(noMediaHookSource.contains("startSenderNoMediaRuntimeTrigger(confirmed: confirmed)"))
        #expect(adapterSource.contains("summary.markNoMediaRuntimeTriggerStarted"))
        #expect(noMediaHookSource.contains("Task { @MainActor in"))
        #expect(noMediaHookSource.contains("await runSenderNoMediaRuntimeTrigger(reference: reference)"))
        #expect(noMediaRunSource.contains("await fetchSenderRuntimePendingMetadata(reference: reference)"))
        #expect(noMediaRunSource.contains("await requestSenderRuntimeCredentials(for: session)"))
        #expect(!noMediaHookSource.contains("sender_join_result"))
        #expect(!noMediaHookSource.contains("join_result"))
        #expect(!noMediaRunSource.contains("DirectCallLiveKitConnectExecutor"))
        #expect(!noMediaRunSource.contains("executor.connectAudio"))
        #expect(!noMediaRunSource.contains("setMicrophoneEnabled(true)"))
        #expect(!noMediaRunSource.contains("prepareSenderRuntimeE2EEContext"))
        #expect(!noMediaRunSource.contains("senderRuntimeLiveKitClientFactory"))
        #expect(!noMediaRunSource.contains("LiveKitDirectCallClient"))
        #expect(!noMediaRunSource.contains("sendRealInvite"))
        #expect(!noMediaRunSource.contains("postRealInvite"))
        #expect(!noMediaRunSource.contains("matrixEventEmitRequested = true"))
        #expect(!noMediaRunSource.contains("cameraPermissionRequested = true"))
        #expect(!noMediaRunSource.contains("microphonePermissionRequested = true"))
    }

    private static func assertSenderNoMediaFileTriggerSourceGuards(in adapterSource: String) {
        #expect(adapterSource.contains("sender_debug_file_trigger_seen=\\(senderDebugFileTriggerSeen)"))
        #expect(adapterSource.contains("sender_debug_file_trigger_shape_bucket=\\(senderDebugFileTriggerShapeBucket)"))
        #expect(adapterSource.contains("sender_debug_file_trigger_generation_bucket=\\(senderDebugFileTriggerGenerationBucket)"))
        #expect(adapterSource.contains("sender_debug_file_trigger_consumed=\\(senderDebugFileTriggerConsumed)"))
        #expect(adapterSource.contains("sender_debug_file_trigger_consume_result_bucket=\\(senderDebugFileTriggerConsumeResultBucket)"))
        #expect(adapterSource.contains("mutating func markDebugFileTriggerSeen(shapeBucket: String, generationBucket: String)"))
        #expect(adapterSource.contains("mutating func markDebugFileTriggerConsumed(resultBucket: String)"))
        #expect(adapterSource.contains("private static let senderNoMediaRuntimeTriggerFileName = \"salemx-debug-sender-no-media-runtime-trigger.json\""))
        #expect(adapterSource.contains("private static var senderNoMediaRuntimeTriggerFilePollTask: Task<Void, Never>?"))
        #expect(adapterSource.contains("startSenderNoMediaRuntimeTriggerFilePolling()"))
        #expect(adapterSource.contains("consumeSenderNoMediaRuntimeTriggerFileIfNeeded()"))
        #expect(adapterSource.contains("senderNoMediaRuntimeTriggerFileDiagnostics"))
        #expect(adapterSource.contains("triggerKind == \"sender_no_media_runtime_trigger\""))
        #expect(adapterSource.contains("markerVersion == \"2.49T\""))
        #expect(adapterSource.contains("try FileManager.default.removeItem(at: triggerURL)"))
        #expect(adapterSource.contains("recordSenderDebugFileTriggerConsumed(resultBucket: \"deleted_redacted\")"))
        #expect(adapterSource.contains("startSenderNoMediaRuntimeTrigger(confirmed: true)"))
        #expect(adapterSource.contains("\"valid_sender_no_media_trigger_redacted\""))
        #expect(adapterSource.contains("\"invalid_shape_redacted\""))
    }

    private static func assertSenderPendingMetadataFileHandoffSourceGuards(in adapterSource: String) {
        let handoffConsumerSource: String
        if let handoffConsumerStart = adapterSource.range(of: "private static func startSenderPendingMetadataReferenceHandoffFilePolling")?.lowerBound,
           let noMediaFilePollingStart = adapterSource.range(of: "private static func startSenderNoMediaRuntimeTriggerFilePolling")?.lowerBound {
            handoffConsumerSource = String(adapterSource[handoffConsumerStart..<noMediaFilePollingStart])
        } else {
            handoffConsumerSource = ""
        }

        #expect(adapterSource.contains("sender_debug_pending_metadata_file_handoff_seen=\\(senderDebugPendingMetadataFileHandoffSeen)"))
        #expect(adapterSource.contains("sender_debug_pending_metadata_file_handoff_shape_bucket=\\(senderDebugPendingMetadataFileHandoffShapeBucket)"))
        #expect(adapterSource.contains("sender_debug_pending_metadata_file_handoff_consumed=\\(senderDebugPendingMetadataFileHandoffConsumed)"))
        #expect(adapterSource.contains("sender_debug_pending_metadata_file_handoff_consume_result_bucket=\\(senderDebugPendingMetadataFileHandoffConsumeResultBucket)"))
        #expect(adapterSource.contains("sender_pending_metadata_memory_reference_present=\\(senderPendingMetadataMemoryReferencePresent)"))
        #expect(adapterSource.contains("sender_pending_metadata_handoff_result_bucket=\\(senderPendingMetadataHandoffResultBucket)"))
        #expect(adapterSource.contains("sender_pending_metadata_raw_identifiers_logged=\\(senderPendingMetadataRawIdentifiersLogged)"))
        #expect(adapterSource.contains("private static let senderPendingMetadataReferenceHandoffFileName = \"salemx-debug-sender-pending-metadata-handoff.json\""))
        #expect(adapterSource.contains("private static var senderPendingMetadataReferenceHandoffFilePollTask: Task<Void, Never>?"))
        #expect(adapterSource.contains("startSenderPendingMetadataReferenceHandoffFilePolling()"))
        #expect(adapterSource.contains("consumeSenderPendingMetadataReferenceHandoffFileIfNeeded()"))
        #expect(adapterSource.contains("senderPendingMetadataReferenceHandoffFileDiagnostics"))
        #expect(adapterSource.contains("triggerKind == \"sender_pending_metadata_reference_handoff\""))
        #expect(adapterSource.contains("markerVersion == \"2.49W\""))
        #expect(adapterSource.contains("json[\"pending_metadata_reference\"] as? String"))
        #expect(adapterSource.contains("try FileManager.default.removeItem(at: handoffURL)"))
        #expect(adapterSource.contains("recordSenderDebugPendingMetadataFileHandoffConsumed(resultBucket: \"deleted_redacted\")"))
        #expect(adapterSource.contains("armSenderPendingMetadataReferenceHandoff(reference: reference"))
        #expect(adapterSource.contains("source: \"file_handoff_redacted\""))
        #expect(adapterSource.contains("\"valid_sender_pending_metadata_handoff_redacted\""))
        #expect(adapterSource.contains("let rawReferenceLogged = false"))
        #expect(adapterSource.contains("let rawMetadataLogged = false"))
        #expect(adapterSource.contains("let rawRoomLogged = false"))
        #expect(adapterSource.contains("let rawCallLogged = false"))
        #expect(adapterSource.contains("let rawUserLogged = false"))
        #expect(adapterSource.contains("let rawDeviceLogged = false"))
        #expect(!handoffConsumerSource.isEmpty)
        #expect(handoffConsumerSource.contains("FileManager.default.fileExists(atPath: handoffURL.path)"))
        #expect(handoffConsumerSource.contains("recordSenderDebugPendingMetadataFileHandoffSeen(shapeBucket: diagnostics.shapeBucket)"))
        #expect(handoffConsumerSource.contains("recordSenderDebugPendingMetadataFileHandoffConsumed(resultBucket: \"invalid_shape_redacted\")"))
        #expect(handoffConsumerSource.contains("recordSenderDebugPendingMetadataFileHandoffConsumed(resultBucket: \"delete_failed_redacted\")"))
        #expect(adapterSource.contains("summary.markDebugPendingMetadataFileHandoffSeen(shapeBucket: shapeBucket)"))
        #expect(adapterSource.contains("summary.markDebugPendingMetadataFileHandoffConsumed(resultBucket: resultBucket)"))
        #expect(!handoffConsumerSource.contains("handleUploadSmokeURL"))
        #expect(!handoffConsumerSource.contains("startSenderNoMediaRuntimeTrigger(confirmed: true)"))
        #expect(!handoffConsumerSource.contains("sendRealInvite"))
        #expect(!handoffConsumerSource.contains("postRealInvite"))
        #expect(!handoffConsumerSource.contains("background_apns_push_requested=true"))
        #expect(!handoffConsumerSource.contains("DirectCallLiveKitConnectExecutor"))
        #expect(!handoffConsumerSource.contains("executor.connectAudio"))
        #expect(!handoffConsumerSource.contains("setMicrophoneEnabled(true)"))
        #expect(!handoffConsumerSource.contains("matrixEventEmitRequested = true"))
        #expect(!handoffConsumerSource.contains("cameraPermissionRequested = true"))
        #expect(!handoffConsumerSource.contains("microphonePermissionRequested = true"))
    }

    private static func assertSenderAtomicPendingMetadataHandoffTriggerSourceGuards(in adapterSource: String) {
        let atomicConsumerSource: String
        if let atomicConsumerStart = adapterSource.range(of: "private static func startSenderAtomicPendingMetadataHandoffTriggerFilePolling")?.lowerBound,
           let handoffFilePollingStart = adapterSource.range(of: "private static func startSenderPendingMetadataReferenceHandoffFilePolling")?.lowerBound {
            atomicConsumerSource = String(adapterSource[atomicConsumerStart..<handoffFilePollingStart])
        } else {
            atomicConsumerSource = ""
        }

        #expect(adapterSource.contains("sender_debug_atomic_handoff_trigger_file_seen=\\(senderDebugAtomicHandoffTriggerFileSeen)"))
        #expect(adapterSource.contains("sender_debug_atomic_handoff_trigger_shape_bucket=\\(senderDebugAtomicHandoffTriggerShapeBucket)"))
        #expect(adapterSource.contains("sender_debug_atomic_handoff_trigger_consumed=\\(senderDebugAtomicHandoffTriggerConsumed)"))
        #expect(adapterSource.contains("sender_debug_atomic_handoff_trigger_consume_result_bucket=\\(senderDebugAtomicHandoffTriggerConsumeResultBucket)"))
        #expect(adapterSource.contains("sender_pending_metadata_memory_reference_present_before_trigger=\\(senderPendingMetadataMemoryReferencePresentBeforeTrigger)"))
        #expect(adapterSource.contains("sender_pending_metadata_memory_reference_present_at_trigger=\\(senderPendingMetadataMemoryReferencePresentAtTrigger)"))
        #expect(adapterSource.contains("sender_authorized_metadata_source_role_bucket=\\(senderAuthorizedMetadataSourceRoleBucket)"))
        #expect(adapterSource.contains("sender_authorized_metadata_source_scope_bucket=\\(senderAuthorizedMetadataSourceScopeBucket)"))
        #expect(adapterSource.contains("sender_uses_receiver_pending_metadata_reference=\\(senderUsesReceiverPendingMetadataReference)"))
        #expect(adapterSource.contains("private static let senderAtomicPendingMetadataHandoffTriggerFileName = \"salemx-debug-sender-pending-metadata-and-no-media-trigger.json\""))
        #expect(adapterSource.contains("private static var senderAtomicPendingMetadataHandoffTriggerFilePollTask: Task<Void, Never>?"))
        #expect(adapterSource.contains("startSenderAtomicPendingMetadataHandoffTriggerFilePolling()"))
        #expect(adapterSource.contains("consumeSenderAtomicPendingMetadataHandoffTriggerFileIfNeeded()"))
        #expect(adapterSource.contains("senderAtomicPendingMetadataHandoffTriggerFileURLs()"))
        #expect(adapterSource.contains("senderAtomicPendingMetadataHandoffTriggerFileDiagnostics"))
        #expect(adapterSource.contains("triggerKind == \"sender_pending_metadata_and_no_media_trigger\""))
        #expect(adapterSource.contains("markerVersion == \"2.49X\""))
        #expect(adapterSource.contains("markerVersion == \"2.49Z\""))
        #expect(adapterSource.contains("command == \"run_no_media_trigger\""))
        #expect(adapterSource.contains("json[\"sender_authorized_metadata_reference\"] as? String"))
        #expect(adapterSource.contains("json[\"pending_metadata_reference\"] as? String"))
        #expect(adapterSource.contains("let senderAuthorizedShape = markerVersion == \"2.49Z\""))
        #expect(adapterSource.contains("legacyReference.isEmpty"))
        #expect(adapterSource.contains("mutating func markDebugAtomicHandoffTriggerReadyForTrigger(referencePresent: Bool)"))
        #expect(adapterSource.contains("if senderDebugAtomicHandoffTriggerFileSeen"))
        #expect(!atomicConsumerSource.isEmpty)
        #expect(atomicConsumerSource.contains("recordSenderDebugAtomicHandoffTriggerConsumed(resultBucket: \"missing_file_redacted\")"))
        #expect(atomicConsumerSource.contains("recordSenderDebugAtomicHandoffTriggerConsumed(resultBucket: \"path_unavailable_redacted\")"))
        #expect(atomicConsumerSource.contains("let triggerURLs = senderAtomicPendingMetadataHandoffTriggerFileURLs()"))
        #expect(atomicConsumerSource.contains("triggerURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) })"))
        #expect(atomicConsumerSource.contains("FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first"))
        #expect(atomicConsumerSource.contains("FileManager.default.temporaryDirectory.appending(component: senderAtomicPendingMetadataHandoffTriggerFileName)"))
        #expect(!atomicConsumerSource.contains("urls(for: .documentDirectory, in: .userDomainMask).first?"))
        #expect(atomicConsumerSource.contains("try FileManager.default.removeItem(at: triggerURL)"))
        #expect(atomicConsumerSource.contains("recordSenderDebugAtomicHandoffTriggerSeen(shapeBucket: diagnostics.shapeBucket)"))
        #expect(atomicConsumerSource.contains("recordSenderDebugAtomicHandoffTriggerReadyForTrigger(referencePresent: true)"))
        #expect(atomicConsumerSource.contains("recordSenderDebugAtomicHandoffTriggerConsumed(resultBucket: \"deleted_redacted\")"))
        #expect(atomicConsumerSource.contains("recordSenderDebugAtomicHandoffTriggerConsumed(resultBucket: \"invalid_shape_redacted\")"))
        #expect(atomicConsumerSource.contains("recordSenderDebugAtomicHandoffTriggerConsumed(resultBucket: \"invalid_shape_delete_failed_redacted\")"))
        #expect(atomicConsumerSource.contains("recordSenderDebugAtomicHandoffTriggerConsumed(resultBucket: \"delete_failed_redacted\")"))
        #expect(atomicConsumerSource.contains("armSenderPendingMetadataReferenceHandoff(reference: reference"))
        #expect(atomicConsumerSource.contains("source: source"))
        #expect(atomicConsumerSource.contains("source: senderAuthorizedShape ? \"sender_authorized_file_handoff_redacted\" : \"atomic_file_handoff_redacted\""))
        #expect(atomicConsumerSource.contains("startSenderNoMediaRuntimeTrigger(confirmed: true)"))
        let armIndex = atomicConsumerSource.range(of: "armSenderPendingMetadataReferenceHandoff(reference: reference")?.lowerBound
        let triggerIndex = atomicConsumerSource.range(of: "startSenderNoMediaRuntimeTrigger(confirmed: true)")?.lowerBound
        #expect(armIndex != nil)
        #expect(triggerIndex != nil)
        if let armIndex, let triggerIndex {
            #expect(armIndex < triggerIndex)
        }
        #expect(atomicConsumerSource.contains("\"valid_sender_atomic_handoff_trigger_redacted\""))
        #expect(!atomicConsumerSource.contains("handleUploadSmokeURL"))
        #expect(!atomicConsumerSource.contains("sendRealInvite"))
        #expect(!atomicConsumerSource.contains("postRealInvite"))
        #expect(!atomicConsumerSource.contains("background_apns_push_requested=true"))
        #expect(!atomicConsumerSource.contains("DirectCallLiveKitConnectExecutor"))
        #expect(!atomicConsumerSource.contains("executor.connectAudio"))
        #expect(!atomicConsumerSource.contains("setMicrophoneEnabled(true)"))
        #expect(!atomicConsumerSource.contains("matrixEventEmitRequested = true"))
        #expect(!atomicConsumerSource.contains("cameraPermissionRequested = true"))
        #expect(!atomicConsumerSource.contains("microphonePermissionRequested = true"))
    }

    private static func assertSenderPendingMetadataAuthorizationDiagnosticsSourceGuards(in adapterSource: String) {
        let senderFetchSource: String
        if let fetchStart = adapterSource.range(of: "private static func fetchSenderRuntimePendingMetadata")?.lowerBound,
           let blockedRecordStart = adapterSource.range(of: "private static func recordSenderRuntimePendingMetadataBlocked")?.lowerBound {
            senderFetchSource = String(adapterSource[fetchStart..<blockedRecordStart])
        } else {
            senderFetchSource = ""
        }

        #expect(adapterSource.contains("pending_metadata_reference_role_bucket=\\(pendingMetadataReferenceRoleBucket)"))
        #expect(adapterSource.contains("pending_metadata_reference_scope_bucket=\\(pendingMetadataReferenceScopeBucket)"))
        #expect(adapterSource.contains("receiver_pending_metadata_fetch_auth_bucket=\\(receiverPendingMetadataFetchAuthBucket)"))
        #expect(adapterSource.contains("sender_pending_metadata_fetch_auth_bucket=\\(senderPendingMetadataFetchAuthBucket)"))
        #expect(adapterSource.contains("sender_pending_metadata_fetch_http_status_bucket=\\(senderPendingMetadataFetchHTTPStatusBucket)"))
        #expect(adapterSource.contains("sender_pending_metadata_fetch_failure_reason_bucket=\\(senderPendingMetadataFetchFailureReasonBucket)"))
        #expect(adapterSource.contains("sender_is_invite_creator_bucket=\\(senderIsInviteCreatorBucket)"))
        #expect(adapterSource.contains("sender_is_room_member_bucket=\\(senderIsRoomMemberBucket)"))
        #expect(adapterSource.contains("sender_is_peer_of_metadata_bucket=\\(senderIsPeerOfMetadataBucket)"))
        #expect(adapterSource.contains("sender_authorized_metadata_source_available=\\(senderAuthorizedMetadataSourceAvailable)"))
        #expect(adapterSource.contains("sender_authorized_metadata_source_role_bucket=\\(senderAuthorizedMetadataSourceRoleBucket)"))
        #expect(adapterSource.contains("sender_authorized_metadata_source_scope_bucket=\\(senderAuthorizedMetadataSourceScopeBucket)"))
        #expect(adapterSource.contains("sender_uses_receiver_pending_metadata_reference=\\(senderUsesReceiverPendingMetadataReference)"))
        #expect(adapterSource.contains("sender_local_invite_state_available=\\(senderLocalInviteStateAvailable)"))
        #expect(adapterSource.contains("sender_can_request_credentials_without_receiver_pending_fetch=\\(senderCanRequestCredentialsWithoutReceiverPendingFetch)"))
        #expect(adapterSource.contains("sender_credentials_request_blocked_reason=\\(senderCredentialsRequestBlockedReason)"))
        #expect(adapterSource.contains("recommended_next_fix_bucket=\\(recommendedNextFixBucket)"))
        #expect(adapterSource.contains("markSenderPendingMetadataAuthorizationStarted(referencePresent: referencePresent"))
        #expect(adapterSource.contains("sender_authorized_file_handoff_redacted"))
        #expect(adapterSource.contains("sender_authorized_metadata_reference_redacted"))
        #expect(adapterSource.contains("invite_creator_sender_metadata_reference_redacted"))
        #expect(adapterSource.contains("sender_authorized_metadata_scope_redacted"))
        #expect(adapterSource.contains("senderUsesReceiverPendingMetadataReference = referencePresent && !senderAuthorizedSource"))
        #expect(adapterSource.contains("senderUsesReceiverPendingMetadataReference = false"))
        #expect(adapterSource.contains("receiver_invite_pending_metadata_reference_redacted"))
        #expect(adapterSource.contains("senderLocalInviteStateAvailable = false"))
        #expect(adapterSource.contains("senderLocalInviteStateAvailable = senderAuthorizedSource && referencePresent"))
        #expect(adapterSource.contains("senderCanRequestCredentialsWithoutReceiverPendingFetch = false"))
        #expect(adapterSource.contains("senderCanRequestCredentialsWithoutReceiverPendingFetch = senderAuthorizedSource && referencePresent"))
        #expect(adapterSource.contains("senderCanRequestCredentialsWithoutReceiverPendingFetch = true"))
        #expect(adapterSource.contains("senderCredentialsRequestBlockedReason = reason"))
        #expect(adapterSource.contains("recommendedNextFixBucket = recommendedSenderMetadataNextFixBucket"))
        #expect(adapterSource.contains("provide_sender_authorized_metadata_source_redacted"))
        #expect(adapterSource.contains("components.path = pendingMetadataEndpointPathPrefix + \"/\" + encodedReference + \"/sender\""))
        #expect(!senderFetchSource.isEmpty)
        #expect(senderFetchSource.contains("senderPendingMetadataFetchURL(reference: reference)"))
        #expect(senderFetchSource.contains("recordSenderRuntimePendingMetadataBlocked(reason,"))
        #expect(senderFetchSource.contains("diagnostics: diagnostics"))
        #expect(!senderFetchSource.contains("requestSenderRuntimeCredentials"))
        #expect(!senderFetchSource.contains("DirectCallLiveKitConnectExecutor"))
        #expect(!senderFetchSource.contains("executor.connectAudio"))
        #expect(!senderFetchSource.contains("setMicrophoneEnabled(true)"))
        #expect(!senderFetchSource.contains("sendRealInvite"))
        #expect(!senderFetchSource.contains("postRealInvite"))
        #expect(!senderFetchSource.contains("matrixEventEmitRequested = true"))
        #expect(!senderFetchSource.contains("cameraPermissionRequested = true"))
        #expect(!senderFetchSource.contains("microphonePermissionRequested = true"))
    }

    @Test
    func senderConnectParityUsesReceiverProvenBoundedAudioPathWithoutRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let parityStart = try #require(adapterSource.range(of: "private struct SalemXSenderConnectParity")?.lowerBound)
        let unificationStart = try #require(adapterSource.range(of: "private struct SalemXSenderConnectExecutorUnification")?.lowerBound)
        let paritySource = String(adapterSource[parityStart..<unificationStart])

        #expect(adapterSource.contains("private struct SalemXSenderConnectParity"))
        #expect(adapterSource.contains("static let defaultEnabled = SalemXSenderConnectParity()"))
        #expect(adapterSource.contains("let present = true"))
        #expect(adapterSource.contains("let debugOnly = true"))
        #expect(adapterSource.contains("let rawURLLogged = false"))
        #expect(adapterSource.contains("let rawTokenLogged = false"))
        #expect(adapterSource.contains("let rawRoomLogged = false"))
        #expect(adapterSource.contains("let rawIdentityLogged = false"))
        #expect(adapterSource.contains("let usesReceiverProvenConnectWrapper = true"))
        #expect(adapterSource.contains("let usesAudioOnly = true"))
        #expect(adapterSource.contains("let videoAllowed = false"))
        #expect(adapterSource.contains("let matrixEventsAllowed = false"))
        #expect(adapterSource.contains("let roomRetainedUntilTerminal = true"))
        #expect(adapterSource.contains("let delegateRetainedUntilTerminal = true"))
        #expect(adapterSource.contains("let stateObserverRetainedUntilTerminal = true"))
        #expect(adapterSource.contains("let taskRetainedUntilTerminal = true"))
        #expect(adapterSource.contains("let boundedWaitUsed = true"))

        #expect(adapterSource.contains("sender_connect_parity_present=\\(senderConnectParityPresent)"))
        #expect(adapterSource.contains("sender_connect_parity_debug_only=\\(senderConnectParityDebugOnly)"))
        #expect(adapterSource.contains("sender_connect_parity_raw_url_logged=\\(senderConnectParityRawURLLogged)"))
        #expect(adapterSource.contains("sender_connect_parity_raw_token_logged=\\(senderConnectParityRawTokenLogged)"))
        #expect(adapterSource.contains("sender_connect_parity_raw_room_logged=\\(senderConnectParityRawRoomLogged)"))
        #expect(adapterSource.contains("sender_connect_parity_raw_identity_logged=\\(senderConnectParityRawIdentityLogged)"))
        #expect(adapterSource.contains("sender_connect_parity_uses_receiver_proven_connect_wrapper=\\(senderConnectParityUsesReceiverProvenConnectWrapper)"))
        #expect(adapterSource.contains("sender_connect_parity_uses_audio_only=\\(senderConnectParityUsesAudioOnly)"))
        #expect(adapterSource.contains("sender_connect_parity_video_allowed=\\(senderConnectParityVideoAllowed)"))
        #expect(adapterSource.contains("sender_connect_parity_matrix_events_allowed=\\(senderConnectParityMatrixEventsAllowed)"))
        #expect(adapterSource.contains("sender_connect_parity_room_retained_until_terminal=\\(senderConnectParityRoomRetainedUntilTerminal)"))
        #expect(adapterSource.contains("sender_connect_parity_delegate_retained_until_terminal=\\(senderConnectParityDelegateRetainedUntilTerminal)"))
        #expect(adapterSource.contains("sender_connect_parity_state_observer_retained_until_terminal=\\(senderConnectParityStateObserverRetainedUntilTerminal)"))
        #expect(adapterSource.contains("sender_connect_parity_task_retained_until_terminal=\\(senderConnectParityTaskRetainedUntilTerminal)"))
        #expect(adapterSource.contains("sender_connect_parity_bounded_wait_used=\\(senderConnectParityBoundedWaitUsed)"))

        #expect(adapterSource.contains("var senderConnectParityPresent = SalemXSenderConnectParity.defaultEnabled.present"))
        #expect(adapterSource.contains("var senderConnectParityDebugOnly = SalemXSenderConnectParity.defaultEnabled.debugOnly"))
        #expect(adapterSource.contains("var senderConnectParityRawURLLogged = SalemXSenderConnectParity.defaultEnabled.rawURLLogged"))
        #expect(adapterSource.contains("var senderConnectParityRawTokenLogged = SalemXSenderConnectParity.defaultEnabled.rawTokenLogged"))
        #expect(adapterSource.contains("var senderConnectParityRawRoomLogged = SalemXSenderConnectParity.defaultEnabled.rawRoomLogged"))
        #expect(adapterSource.contains("var senderConnectParityRawIdentityLogged = SalemXSenderConnectParity.defaultEnabled.rawIdentityLogged"))
        #expect(adapterSource.contains("var senderConnectParityUsesReceiverProvenConnectWrapper = SalemXSenderConnectParity.defaultEnabled.usesReceiverProvenConnectWrapper"))
        #expect(adapterSource.contains("var senderConnectParityUsesAudioOnly = SalemXSenderConnectParity.defaultEnabled.usesAudioOnly"))
        #expect(adapterSource.contains("var senderConnectParityVideoAllowed = SalemXSenderConnectParity.defaultEnabled.videoAllowed"))
        #expect(adapterSource.contains("var senderConnectParityMatrixEventsAllowed = SalemXSenderConnectParity.defaultEnabled.matrixEventsAllowed"))
        #expect(adapterSource.contains("var senderConnectParityRoomRetainedUntilTerminal = SalemXSenderConnectParity.defaultEnabled.roomRetainedUntilTerminal"))
        #expect(adapterSource.contains("var senderConnectParityDelegateRetainedUntilTerminal = SalemXSenderConnectParity.defaultEnabled.delegateRetainedUntilTerminal"))
        #expect(adapterSource.contains("var senderConnectParityStateObserverRetainedUntilTerminal = SalemXSenderConnectParity.defaultEnabled.stateObserverRetainedUntilTerminal"))
        #expect(adapterSource.contains("var senderConnectParityTaskRetainedUntilTerminal = SalemXSenderConnectParity.defaultEnabled.taskRetainedUntilTerminal"))
        #expect(adapterSource.contains("var senderConnectParityBoundedWaitUsed = SalemXSenderConnectParity.defaultEnabled.boundedWaitUsed"))

        #expect(adapterSource.contains("private static var senderConnectParity = SalemXSenderConnectParity.defaultEnabled"))
        #expect(adapterSource.contains("mutating func recordSenderConnectParity(_ parity: SalemXSenderConnectParity)"))
        #expect(adapterSource.contains("senderConnectParityUsesReceiverProvenConnectWrapper = parity.usesReceiverProvenConnectWrapper"))
        #expect(adapterSource.contains("senderConnectParityRoomRetainedUntilTerminal = parity.roomRetainedUntilTerminal"))
        #expect(adapterSource.contains("senderConnectParityDelegateRetainedUntilTerminal = parity.delegateRetainedUntilTerminal"))
        #expect(adapterSource.contains("senderConnectParityStateObserverRetainedUntilTerminal = parity.stateObserverRetainedUntilTerminal"))
        #expect(adapterSource.contains("senderConnectParityTaskRetainedUntilTerminal = parity.taskRetainedUntilTerminal"))
        #expect(adapterSource.contains("senderConnectParityBoundedWaitUsed = parity.boundedWaitUsed"))
        #expect(adapterSource.contains("summary.recordSenderConnectParity(senderConnectParity)"))
        #expect(adapterSource.contains("let senderConnectParitySnapshot = senderConnectParity"))
        #expect(adapterSource.contains("baseSummary.recordSenderConnectParity(senderConnectParitySnapshot)"))

        #expect(adapterSource.contains("let repeated = requested && previousActivation.consumed"))
        #expect(adapterSource.contains("consumed: requested && !repeated"))
        #expect(adapterSource.contains("senderSideLiveKitJoinActivationRepeated = activation.repeated"))
        #expect(adapterSource.contains("sender_join_repeated_redacted"))
        #expect(adapterSource.contains("repeated_sender_join_blocked_redacted"))
        #expect(adapterSource.contains("sdk_connect_timeout_connect_call_pending_redacted"))
        #expect(adapterSource.contains("sender_join_success_but_remote_missing_redacted"))
        #expect(adapterSource.contains("default_disabled_no_connect"))
        #expect(adapterSource.contains("sender_side_livekit_join_hook_default_disabled=\\(senderSideLiveKitJoinHookDefaultDisabled)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_default_disabled=\\(senderSideLiveKitJoinActivationDefaultDisabled)"))
        #expect(adapterSource.contains("cameraPermissionRequested = false"))
        #expect(adapterSource.contains("matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderConnectParityRawURLLogged = true"))
        #expect(!adapterSource.contains("senderConnectParityRawTokenLogged = true"))
        #expect(!adapterSource.contains("senderConnectParityRawRoomLogged = true"))
        #expect(!adapterSource.contains("senderConnectParityRawIdentityLogged = true"))
        #expect(!adapterSource.contains("senderConnectParityVideoAllowed = true"))
        #expect(!adapterSource.contains("senderConnectParityMatrixEventsAllowed = true"))
        #expect(!paritySource.contains(".connectAudio("))
    }

    @Test
    func senderConnectExecutorUnificationUsesReceiverExecutorWithoutRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let mediaEngineSource = try Self.sourceFile("ElementX/Sources/Services/Calls/LiveKitDirectCallMediaEngine.swift")
        let unificationStart = try #require(adapterSource.range(of: "private struct SalemXSenderConnectExecutorUnification")?.lowerBound)
        let failureDiagnosticsStart = try #require(adapterSource.range(of: "private struct SalemXSenderJoinFailureDiagnostics")?.lowerBound)
        let unificationSource = String(adapterSource[unificationStart..<failureDiagnosticsStart])

        #expect(mediaEngineSource.contains("struct DirectCallLiveKitConnectExecutorModel: Equatable"))
        #expect(mediaEngineSource.contains("struct DirectCallLiveKitConnectExecutor"))
        #expect(mediaEngineSource.contains("static let provenAudioModel = DirectCallLiveKitConnectExecutorModel("))
        #expect(mediaEngineSource.contains("receiverExecutorShared: true"))
        #expect(mediaEngineSource.contains("senderExecutorShared: true"))
        #expect(mediaEngineSource.contains("sameConnectOptionsShape: true"))
        #expect(mediaEngineSource.contains("sameRoomRetentionModel: true"))
        #expect(mediaEngineSource.contains("sameDelegateRetentionModel: true"))
        #expect(mediaEngineSource.contains("sameStateObserverModel: true"))
        #expect(mediaEngineSource.contains("sameBoundedWaitModel: true"))
        #expect(mediaEngineSource.contains("audioOnly: true"))
        #expect(mediaEngineSource.contains("videoAllowed: false"))
        #expect(mediaEngineSource.contains("matrixEventsAllowed: false"))
        #expect(mediaEngineSource.contains("rawURLLogged: false"))
        #expect(mediaEngineSource.contains("rawTokenLogged: false"))
        #expect(mediaEngineSource.contains("rawRoomLogged: false"))
        #expect(mediaEngineSource.contains("rawIdentityLogged: false"))
        #expect(mediaEngineSource.contains("private let liveKitConnectExecutor: DirectCallLiveKitConnectExecutor"))
        #expect(mediaEngineSource.contains("liveKitConnectExecutor = DirectCallLiveKitConnectExecutor(liveKitClient: self.liveKitClient)"))
        #expect(mediaEngineSource.contains("switch await liveKitConnectExecutor.connectAudio(connectionInfo: connectionInfo, e2eeContext: e2eeContext)"))
        #expect(mediaEngineSource.contains("await liveKitClient.connect(connectionInfo: connectionInfo, e2eeContext: e2eeContext)"))

        #expect(adapterSource.contains("private struct SalemXSenderConnectExecutorUnification"))
        #expect(adapterSource.contains("static let shared = SalemXSenderConnectExecutorUnification(model: DirectCallLiveKitConnectExecutor.provenAudioModel)"))
        #expect(adapterSource.contains("init(model: DirectCallLiveKitConnectExecutorModel)"))
        #expect(adapterSource.contains("receiverExecutorShared = model.receiverExecutorShared"))
        #expect(adapterSource.contains("senderExecutorShared = model.senderExecutorShared"))
        #expect(adapterSource.contains("sameConnectOptionsShape = model.sameConnectOptionsShape"))
        #expect(adapterSource.contains("sameRoomRetentionModel = model.sameRoomRetentionModel"))
        #expect(adapterSource.contains("sameDelegateRetentionModel = model.sameDelegateRetentionModel"))
        #expect(adapterSource.contains("sameStateObserverModel = model.sameStateObserverModel"))
        #expect(adapterSource.contains("sameBoundedWaitModel = model.sameBoundedWaitModel"))
        #expect(adapterSource.contains("audioOnly = model.audioOnly"))
        #expect(adapterSource.contains("videoAllowed = model.videoAllowed"))
        #expect(adapterSource.contains("matrixEventsAllowed = model.matrixEventsAllowed"))
        #expect(adapterSource.contains("rawURLLogged = model.rawURLLogged"))
        #expect(adapterSource.contains("rawTokenLogged = model.rawTokenLogged"))
        #expect(adapterSource.contains("rawRoomLogged = model.rawRoomLogged"))
        #expect(adapterSource.contains("rawIdentityLogged = model.rawIdentityLogged"))

        let fields = [
            "sender_connect_executor_unification_present",
            "sender_connect_executor_unification_debug_only",
            "sender_connect_executor_unification_receiver_executor_shared",
            "sender_connect_executor_unification_sender_executor_shared",
            "sender_connect_executor_unification_same_connect_options_shape",
            "sender_connect_executor_unification_same_room_retention_model",
            "sender_connect_executor_unification_same_delegate_retention_model",
            "sender_connect_executor_unification_same_state_observer_model",
            "sender_connect_executor_unification_same_bounded_wait_model",
            "sender_connect_executor_unification_audio_only",
            "sender_connect_executor_unification_video_allowed",
            "sender_connect_executor_unification_matrix_events_allowed",
            "sender_connect_executor_unification_raw_url_logged",
            "sender_connect_executor_unification_raw_token_logged",
            "sender_connect_executor_unification_raw_room_logged",
            "sender_connect_executor_unification_raw_identity_logged"
        ]
        for field in fields {
            #expect(adapterSource.contains(field))
        }

        #expect(adapterSource.contains("var senderConnectExecutorUnificationReceiverExecutorShared = SalemXSenderConnectExecutorUnification.shared.receiverExecutorShared"))
        #expect(adapterSource.contains("var senderConnectExecutorUnificationSenderExecutorShared = SalemXSenderConnectExecutorUnification.shared.senderExecutorShared"))
        #expect(adapterSource.contains("var senderConnectExecutorUnificationSameConnectOptionsShape = SalemXSenderConnectExecutorUnification.shared.sameConnectOptionsShape"))
        #expect(adapterSource.contains("var senderConnectExecutorUnificationSameRoomRetentionModel = SalemXSenderConnectExecutorUnification.shared.sameRoomRetentionModel"))
        #expect(adapterSource.contains("var senderConnectExecutorUnificationSameDelegateRetentionModel = SalemXSenderConnectExecutorUnification.shared.sameDelegateRetentionModel"))
        #expect(adapterSource.contains("var senderConnectExecutorUnificationSameStateObserverModel = SalemXSenderConnectExecutorUnification.shared.sameStateObserverModel"))
        #expect(adapterSource.contains("var senderConnectExecutorUnificationSameBoundedWaitModel = SalemXSenderConnectExecutorUnification.shared.sameBoundedWaitModel"))
        #expect(adapterSource.contains("private static var senderConnectExecutorUnification = SalemXSenderConnectExecutorUnification.shared"))
        #expect(adapterSource.contains("summary.recordSenderConnectExecutorUnification(senderConnectExecutorUnification)"))
        #expect(adapterSource.contains("let senderConnectExecutorUnificationSnapshot = senderConnectExecutorUnification"))
        #expect(adapterSource.contains("baseSummary.recordSenderConnectExecutorUnification(senderConnectExecutorUnificationSnapshot)"))
        #expect(adapterSource.contains("sender_connect_executor_unification_receiver_executor_shared=\\(senderConnectExecutorUnificationReceiverExecutorShared)"))
        #expect(adapterSource.contains("sender_connect_executor_unification_sender_executor_shared=\\(senderConnectExecutorUnificationSenderExecutorShared)"))
        #expect(adapterSource.contains("sender_connect_executor_unification_same_connect_options_shape=\\(senderConnectExecutorUnificationSameConnectOptionsShape)"))
        #expect(adapterSource.contains("sender_connect_executor_unification_same_room_retention_model=\\(senderConnectExecutorUnificationSameRoomRetentionModel)"))
        #expect(adapterSource.contains("sender_connect_executor_unification_same_delegate_retention_model=\\(senderConnectExecutorUnificationSameDelegateRetentionModel)"))
        #expect(adapterSource.contains("sender_connect_executor_unification_same_state_observer_model=\\(senderConnectExecutorUnificationSameStateObserverModel)"))
        #expect(adapterSource.contains("sender_connect_executor_unification_same_bounded_wait_model=\\(senderConnectExecutorUnificationSameBoundedWaitModel)"))

        #expect(adapterSource.contains("sender_side_livekit_join_activation_repeated=\\(senderSideLiveKitJoinActivationRepeated)"))
        #expect(adapterSource.contains("sender_side_livekit_join_repeated=\\(senderSideLiveKitJoinRepeated)"))
        #expect(adapterSource.contains("sender_join_repeated_redacted"))
        #expect(adapterSource.contains("repeated_sender_join_blocked_redacted"))
        #expect(adapterSource.contains("sender_livekit_sdk_timeout_diagnostics_final_classification=\\(senderLiveKitSDKTimeoutDiagnosticsFinalClassification)"))
        #expect(adapterSource.contains("sender_join_success_but_remote_missing_redacted"))
        #expect(adapterSource.contains("default_disabled_no_connect"))
        #expect(adapterSource.contains("cameraPermissionRequested = false"))
        #expect(adapterSource.contains("matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderConnectExecutorUnificationVideoAllowed = true"))
        #expect(!adapterSource.contains("senderConnectExecutorUnificationMatrixEventsAllowed = true"))
        #expect(!adapterSource.contains("senderConnectExecutorUnificationRawURLLogged = true"))
        #expect(!adapterSource.contains("senderConnectExecutorUnificationRawTokenLogged = true"))
        #expect(!adapterSource.contains("senderConnectExecutorUnificationRawRoomLogged = true"))
        #expect(!adapterSource.contains("senderConnectExecutorUnificationRawIdentityLogged = true"))
        #expect(!unificationSource.contains(".connectAudio("))
    }

    @Test
    func senderNoMediaRuntimeTriggerConnectsWithoutLocalMediaPublish() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let triggerStart = try #require(adapterSource.range(of: "private static func runSenderNoMediaRuntimeTrigger(reference: String)")?.lowerBound)
        let nextFunctionStart = try #require(adapterSource.range(of: "@MainActor\n    private static func runServerSideSenderMetadataClaimNoMediaTrigger")?.lowerBound)
        let triggerSource = String(adapterSource[triggerStart..<nextFunctionStart])

        #expect(triggerSource.contains("let credentials = await requestSenderRuntimeCredentials(for: session)"))
        #expect(triggerSource.contains("guard case .success(let connectionInfo) = credentials"))
        #expect(triggerSource.contains("guard case .success(let e2eeContext) = prepareSenderRuntimeE2EEContext(for: session)"))
        #expect(triggerSource.contains("let executor = DirectCallLiveKitConnectExecutor(liveKitClient: client)"))
        #expect(triggerSource.contains("let result = await executor.connectAudio(connectionInfo: connectionInfo, e2eeContext: e2eeContext)"))
        #expect(triggerSource.contains("summary.markRuntime(result)"))
        #expect(triggerSource.contains("summary.markNoMediaRuntimeJoin(result)"))
        #expect(!triggerSource.contains("setMicrophoneEnabled"))

        #expect(adapterSource.contains("mutating func markNoMediaRuntimeJoin(_ result: Result<Void, DirectCallMediaError>)"))
        #expect(adapterSource.contains("livekit_join_success_no_local_media_redacted"))
        #expect(adapterSource.contains("livekit_join_failed_no_local_media_redacted"))
        #expect(adapterSource.contains("sender_no_media_runtime_livekit_join_success_redacted"))
        #expect(adapterSource.contains("sender_no_media_runtime_livekit_join_failed_redacted"))
        #expect(adapterSource.contains("sender_local_audio_publish_requested=\\(senderLocalAudioPublishRequested)"))
        #expect(adapterSource.contains("sender_microphone_permission_requested=\\(senderMicrophonePermissionRequested)"))
    }

    @Test
    func senderJoinFailureDiagnosticsClassifyRedactedBucketsWithoutRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("private struct SalemXSenderJoinFailureDiagnostics"))
        #expect(adapterSource.contains("static let credentialsMissingClassification = \"credentials_missing_redacted\""))
        #expect(adapterSource.contains("static let tokenMissingClassification = \"token_missing_redacted\""))
        #expect(adapterSource.contains("static let urlMissingClassification = \"url_missing_redacted\""))
        #expect(adapterSource.contains("static let roomBindingMissingClassification = \"room_binding_missing_redacted\""))
        #expect(adapterSource.contains("static let sameLiveKitRoomMismatchClassification = \"same_livekit_room_mismatch_redacted\""))
        #expect(adapterSource.contains("static let transportFailedClassification = \"transport_failed_redacted\""))
        #expect(adapterSource.contains("static let joinFailedClassification = \"join_failed_redacted\""))
        #expect(adapterSource.contains("static let unknownFailureClassification = \"unknown_sender_join_failure_redacted\""))
        #expect(adapterSource.contains("static let repeatedSenderJoinClassification = \"sender_join_repeated_redacted\""))

        #expect(adapterSource.contains("sender_join_failure_diagnostics_present=\\(senderJoinFailureDiagnosticsPresent)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_debug_only=\\(senderJoinFailureDiagnosticsDebugOnly)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_audio_only=\\(senderJoinFailureDiagnosticsAudioOnly)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_video_allowed=\\(senderJoinFailureDiagnosticsVideoAllowed)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_matrix_events_allowed=\\(senderJoinFailureDiagnosticsMatrixEventsAllowed)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_raw_identifiers_logged=\\(senderJoinFailureDiagnosticsRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_credentials_present=\\(senderJoinFailureDiagnosticsCredentialsPresent)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_token_present=\\(senderJoinFailureDiagnosticsTokenPresent)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_url_present=\\(senderJoinFailureDiagnosticsURLPresent)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_room_binding_present=\\(senderJoinFailureDiagnosticsRoomBindingPresent)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_same_livekit_room=\\(senderJoinFailureDiagnosticsSameLiveKitRoom)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_transport_attempted=\\(senderJoinFailureDiagnosticsTransportAttempted)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_transport_result=\\(senderJoinFailureDiagnosticsTransportResult)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_error_bucket=\\(senderJoinFailureDiagnosticsErrorBucket)"))
        #expect(adapterSource.contains("sender_join_failure_diagnostics_classification=\\(senderJoinFailureDiagnosticsClassification)"))

        #expect(adapterSource.contains("let debugOnly = true"))
        #expect(adapterSource.contains("let audioOnly = true"))
        #expect(adapterSource.contains("let videoAllowed = false"))
        #expect(adapterSource.contains("let matrixEventsAllowed = false"))
        #expect(adapterSource.contains("let rawIdentifiersLogged = false"))
        #expect(adapterSource.contains("senderJoinFailureDiagnosticsRawIdentifiersLogged = diagnostics.rawIdentifiersLogged"))
        #expect(adapterSource.contains("senderJoinFailureDiagnosticsVideoAllowed = diagnostics.videoAllowed"))
        #expect(adapterSource.contains("senderJoinFailureDiagnosticsMatrixEventsAllowed = diagnostics.matrixEventsAllowed"))

        #expect(adapterSource.contains("if !credentialsPresent {"))
        #expect(adapterSource.contains("classification: credentialsMissingClassification"))
        #expect(adapterSource.contains("if !tokenPresent {"))
        #expect(adapterSource.contains("classification: tokenMissingClassification"))
        #expect(adapterSource.contains("if !urlPresent {"))
        #expect(adapterSource.contains("classification: urlMissingClassification"))
        #expect(adapterSource.contains("if !roomBindingPresent {"))
        #expect(adapterSource.contains("classification: roomBindingMissingClassification"))
        #expect(adapterSource.contains("if !sameLiveKitRoom {"))
        #expect(adapterSource.contains("classification: sameLiveKitRoomMismatchClassification"))
        #expect(adapterSource.contains("if transportAttempted, transportResult == failedTransportResult"))
        #expect(adapterSource.contains("return transportFailedClassification"))
        #expect(adapterSource.contains("return joinFailedClassification"))
        #expect(adapterSource.contains("return unknownFailureClassification"))

        #expect(adapterSource.contains("let credentialsPresent = redactedOptionalBoolQueryItem(components,"))
        #expect(adapterSource.contains("names: [\"sender_credentials_present\", \"credentials_present\"]"))
        #expect(adapterSource.contains("let tokenPresent = redactedOptionalBoolQueryItem(components,"))
        #expect(adapterSource.contains("names: [\"sender_token_present\", \"token_present\"]"))
        #expect(adapterSource.contains("let urlPresent = redactedOptionalBoolQueryItem(components,"))
        #expect(adapterSource.contains("names: [\"sender_url_present\", \"url_present\"]"))
        #expect(adapterSource.contains("let roomBindingPresent = redactedOptionalBoolQueryItem(components,"))
        #expect(adapterSource.contains("names: [\"sender_room_binding_present\", \"room_binding_present\"]"))
        #expect(adapterSource.contains("let sameLiveKitRoom = redactedOptionalBoolQueryItem(components,"))
        #expect(adapterSource.contains("names: [\"sender_same_livekit_room\", \"same_livekit_room\"]"))
        #expect(adapterSource.contains("let transportAttempted = redactedOptionalBoolQueryItem(components,"))
        #expect(adapterSource.contains("names: [\"sender_transport_attempted\", \"transport_attempted\"]"))
        #expect(adapterSource.contains("redactedSenderJoinTransportResultQueryItem(components)"))
        #expect(adapterSource.contains("redactedSenderJoinFailureClassificationQueryItem(components)"))
        #expect(adapterSource.contains("var blocksBeforeTransport: Bool"))
        #expect(adapterSource.contains("senderJoinFailureDiagnosticsTransportAttempted = diagnostics.transportAttempted"))
        #expect(adapterSource.contains("summary.recordSenderJoinFailureDiagnostics(joinDiagnostics)"))
        #expect(adapterSource.contains("baseSummary.recordSenderJoinFailureDiagnostics(senderJoinFailureDiagnosticsSnapshot)"))

        #expect(adapterSource.contains("sender_side_livekit_join_activation_triggered=\\(senderSideLiveKitJoinActivationTriggered)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_consumed=\\(senderSideLiveKitJoinActivationConsumed)"))
        #expect(adapterSource.contains("sender_side_livekit_join_activation_repeated=\\(senderSideLiveKitJoinActivationRepeated)"))
        #expect(adapterSource.contains("sender_join_success_but_remote_missing_redacted"))
        #expect(adapterSource.contains("sender_join_failed_redacted"))

        #expect(adapterSource.contains("summary.mediaConnectRequested = false"))
        #expect(adapterSource.contains("summary.mediaConnectAttempted = false"))
        #expect(adapterSource.contains("summary.liveKitJoinRequested = false"))
        #expect(adapterSource.contains("summary.liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("summary.microphonePermissionRequested = false"))
        #expect(adapterSource.contains("summary.cameraPermissionRequested = false"))
        #expect(adapterSource.contains("summary.matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("summary.realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderJoinFailureDiagnosticsRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderJoinFailureDiagnosticsVideoAllowed = true"))
        #expect(!adapterSource.contains("senderJoinFailureDiagnosticsMatrixEventsAllowed = true"))
    }

    @Test
    func senderTransportFailureDiagnosticsClassifyRedactedBucketsWithoutRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("private struct SalemXSenderTransportFailureDiagnostics"))
        #expect(adapterSource.contains("static let transportNotAttemptedClassification = \"transport_not_attempted_redacted\""))
        #expect(adapterSource.contains("static let transportTimeoutClassification = \"transport_timeout_redacted\""))
        #expect(adapterSource.contains("static let transportTLSOrCertificateFailedClassification = \"transport_tls_or_certificate_failed_redacted\""))
        #expect(adapterSource.contains("static let transportWebSocketFailedClassification = \"transport_websocket_failed_redacted\""))
        #expect(adapterSource.contains("static let transportAuthRejectedClassification = \"transport_auth_rejected_redacted\""))
        #expect(adapterSource.contains("static let transportRoomNotFoundOrMismatchClassification = \"transport_room_not_found_or_mismatch_redacted\""))
        #expect(adapterSource.contains("static let transportNetworkUnreachableClassification = \"transport_network_unreachable_redacted\""))
        #expect(adapterSource.contains("static let transportLiveKitServerRejectedClassification = \"transport_livekit_server_rejected_redacted\""))
        #expect(adapterSource.contains("static let transportUnknownFailedClassification = \"transport_unknown_failed_redacted\""))

        #expect(adapterSource.contains("sender_transport_failure_diagnostics_present=\\(senderTransportFailureDiagnosticsPresent)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_debug_only=\\(senderTransportFailureDiagnosticsDebugOnly)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_audio_only=\\(senderTransportFailureDiagnosticsAudioOnly)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_video_allowed=\\(senderTransportFailureDiagnosticsVideoAllowed)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_matrix_events_allowed=\\(senderTransportFailureDiagnosticsMatrixEventsAllowed)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_raw_identifiers_logged=\\(senderTransportFailureDiagnosticsRawIdentifiersLogged)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_transport_attempted=\\(senderTransportFailureDiagnosticsTransportAttempted)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_transport_started=\\(senderTransportFailureDiagnosticsTransportStarted)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_transport_completed=\\(senderTransportFailureDiagnosticsTransportCompleted)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_transport_result=\\(senderTransportFailureDiagnosticsTransportResult)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_error_bucket=\\(senderTransportFailureDiagnosticsErrorBucket)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_classification=\\(senderTransportFailureDiagnosticsClassification)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_livekit_url_present=\\(senderTransportFailureDiagnosticsLiveKitURLPresent)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_token_present=\\(senderTransportFailureDiagnosticsTokenPresent)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_room_binding_present=\\(senderTransportFailureDiagnosticsRoomBindingPresent)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_same_livekit_room=\\(senderTransportFailureDiagnosticsSameLiveKitRoom)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_same_token_authority=\\(senderTransportFailureDiagnosticsSameTokenAuthority)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_receiver_sender_room_match=\\(senderTransportFailureDiagnosticsReceiverSenderRoomMatch)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_receiver_sender_token_authority_match=\\(senderTransportFailureDiagnosticsReceiverSenderTokenAuthorityMatch)"))

        #expect(adapterSource.contains("let debugOnly = true"))
        #expect(adapterSource.contains("let audioOnly = true"))
        #expect(adapterSource.contains("let videoAllowed = false"))
        #expect(adapterSource.contains("let matrixEventsAllowed = false"))
        #expect(adapterSource.contains("let rawIdentifiersLogged = false"))
        #expect(adapterSource.contains("senderTransportFailureDiagnosticsRawIdentifiersLogged = diagnostics.rawIdentifiersLogged"))
        #expect(adapterSource.contains("senderTransportFailureDiagnosticsVideoAllowed = diagnostics.videoAllowed"))
        #expect(adapterSource.contains("senderTransportFailureDiagnosticsMatrixEventsAllowed = diagnostics.matrixEventsAllowed"))

        #expect(adapterSource.contains("return transportNotAttemptedClassification"))
        #expect(adapterSource.contains("return transportRoomNotFoundOrMismatchClassification"))
        #expect(adapterSource.contains("return transportAuthRejectedClassification"))
        #expect(adapterSource.contains("return transportUnknownFailedClassification"))
        #expect(adapterSource.contains("return \"none\""))
        #expect(adapterSource.contains("redactedSenderTransportFailureClassificationQueryItem(components)"))
        #expect(adapterSource.contains("names: [\"sender_transport_started\", \"transport_started\"]"))
        #expect(adapterSource.contains("names: [\"sender_transport_completed\", \"transport_completed\"]"))
        #expect(adapterSource.contains("names: [\"sender_same_token_authority\", \"same_token_authority\"]"))
        #expect(adapterSource.contains("names: [\"sender_receiver_room_match\", \"receiver_sender_room_match\"]"))
        #expect(adapterSource.contains("names: [\"sender_receiver_token_authority_match\", \"receiver_sender_token_authority_match\"]"))
        #expect(adapterSource.contains("summary.recordSenderTransportFailureDiagnostics(transportDiagnostics)"))
        #expect(adapterSource.contains("baseSummary.recordSenderTransportFailureDiagnostics(senderTransportFailureDiagnosticsSnapshot)"))

        #expect(adapterSource.contains("sender_join_failure_diagnostics_transport_attempted=\\(senderJoinFailureDiagnosticsTransportAttempted)"))
        #expect(adapterSource.contains("sender_side_livekit_join_result=\\(senderSideLiveKitJoinResult)"))
        #expect(adapterSource.contains("sender_join_success_but_remote_missing_redacted"))
        #expect(adapterSource.contains("senderJoinFailureDiagnosticsClassification = diagnostics.classification"))
        #expect(adapterSource.contains("senderTransportFailureDiagnosticsTransportAttempted = diagnostics.transportAttempted"))
        #expect(adapterSource.contains("senderTransportFailureDiagnosticsSameLiveKitRoom = diagnostics.sameLiveKitRoom"))
        #expect(adapterSource.contains("senderTransportFailureDiagnosticsReceiverSenderTokenAuthorityMatch = diagnostics.receiverSenderTokenAuthorityMatch"))

        #expect(adapterSource.contains("summary.mediaConnectRequested = false"))
        #expect(adapterSource.contains("summary.mediaConnectAttempted = false"))
        #expect(adapterSource.contains("summary.liveKitJoinRequested = false"))
        #expect(adapterSource.contains("summary.liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("summary.microphonePermissionRequested = false"))
        #expect(adapterSource.contains("summary.cameraPermissionRequested = false"))
        #expect(adapterSource.contains("summary.matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("summary.realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderTransportFailureDiagnosticsRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderTransportFailureDiagnosticsVideoAllowed = true"))
        #expect(!adapterSource.contains("senderTransportFailureDiagnosticsMatrixEventsAllowed = true"))
    }

    @Test
    func senderTransportErrorSurfaceClassifiesRedactedSourcesWithoutRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("private struct SalemXSenderTransportErrorSurface"))
        #expect(adapterSource.contains("static let transportConnectThrowClassification = \"transport_connect_throw_redacted\""))
        #expect(adapterSource.contains("static let transportRoomConnectCallbackFailedClassification = \"transport_room_connect_callback_failed_redacted\""))
        #expect(adapterSource.contains("static let transportWebSocketCloseClassification = \"transport_websocket_close_redacted\""))
        #expect(adapterSource.contains("static let transportWebSocketUpgradeFailedClassification = \"transport_websocket_upgrade_failed_redacted\""))
        #expect(adapterSource.contains("static let transportTokenExpiredOrInvalidClassification = \"transport_token_expired_or_invalid_redacted\""))
        #expect(adapterSource.contains("static let transportTimeoutWaitingForConnectedStateClassification = \"transport_timeout_waiting_for_connected_state_redacted\""))
        #expect(adapterSource.contains("static let transportDisconnectedBeforeConnectedClassification = \"transport_disconnected_before_connected_redacted\""))
        #expect(adapterSource.contains("static let transportLiveKitSDKUnknownErrorClassification = \"transport_livekit_sdk_unknown_error_redacted\""))
        #expect(adapterSource.contains("(connectThrowSource, transportConnectThrowClassification)"))
        #expect(adapterSource.contains("(roomConnectCallbackFailedSource, transportRoomConnectCallbackFailedClassification)"))
        #expect(adapterSource.contains("(websocketCloseBucket, transportWebSocketCloseClassification)"))
        #expect(adapterSource.contains("(websocketUpgradeFailedBucket, transportWebSocketUpgradeFailedClassification)"))
        #expect(adapterSource.contains("(authRejectedBucket, transportAuthRejectedClassification)"))
        #expect(adapterSource.contains("(tokenExpiredOrInvalidBucket, transportTokenExpiredOrInvalidClassification)"))
        #expect(adapterSource.contains("(tlsOrCertificateFailedBucket, transportTLSOrCertificateFailedClassification)"))
        #expect(adapterSource.contains("(networkUnreachableBucket, transportNetworkUnreachableClassification)"))
        #expect(adapterSource.contains("(liveKitSDKUnknownErrorBucket, transportLiveKitSDKUnknownErrorClassification)"))
        #expect(adapterSource.contains("return transportTimeoutWaitingForConnectedStateClassification"))
        #expect(adapterSource.contains("return transportDisconnectedBeforeConnectedClassification"))
        #expect(adapterSource.contains("classification != transportUnknownFailedClassification"))
        #expect(adapterSource.contains("redactedSenderTransportErrorSurfaceInput(components,"))
        #expect(adapterSource.contains("redactedStringQueryItem(components,"))
        #expect(adapterSource.contains("allowedValues.contains(value) ? value : nil"))
        #expect(adapterSource.contains("names: [\"sender_transport_error_surface_source\", \"transport_error_surface_source\"]"))
        #expect(adapterSource.contains("names: [\"sender_transport_error_surface_timeout_observed\", \"transport_timeout_observed\"]"))
        #expect(adapterSource.contains("names: [\"sender_transport_error_surface_disconnected_before_connected\", \"transport_disconnected_before_connected\"]"))
        #expect(adapterSource.contains("sender_transport_error_surface_present=\\(senderTransportErrorSurfacePresent)"))
        #expect(adapterSource.contains("sender_transport_error_surface_debug_only=\\(senderTransportErrorSurfaceDebugOnly)"))
        #expect(adapterSource.contains("sender_transport_error_surface_raw_error_logged=\\(senderTransportErrorSurfaceRawErrorLogged)"))
        #expect(adapterSource.contains("sender_transport_error_surface_raw_url_logged=\\(senderTransportErrorSurfaceRawURLLogged)"))
        #expect(adapterSource.contains("sender_transport_error_surface_raw_token_logged=\\(senderTransportErrorSurfaceRawTokenLogged)"))
        #expect(adapterSource.contains("sender_transport_error_surface_source=\\(senderTransportErrorSurfaceSource)"))
        #expect(adapterSource.contains("sender_transport_error_surface_final_classification=\\(senderTransportErrorSurfaceFinalClassification)"))
        #expect(adapterSource.contains("let rawErrorLogged = false"))
        #expect(adapterSource.contains("let rawURLLogged = false"))
        #expect(adapterSource.contains("let rawTokenLogged = false"))
        #expect(adapterSource.contains("senderTransportErrorSurfaceRawErrorLogged = errorSurface.rawErrorLogged"))
        #expect(adapterSource.contains("senderTransportErrorSurfaceRawURLLogged = errorSurface.rawURLLogged"))
        #expect(adapterSource.contains("senderTransportErrorSurfaceRawTokenLogged = errorSurface.rawTokenLogged"))
        #expect(adapterSource.contains("summary.recordSenderTransportErrorSurface(transportErrorSurface)"))
        #expect(adapterSource.contains("baseSummary.recordSenderTransportErrorSurface(senderTransportErrorSurfaceSnapshot)"))
        #expect(adapterSource.contains("let transportDiagnostics = SalemXSenderTransportFailureDiagnostics.classify(.init(requested: requested"))
        #expect(adapterSource.contains("let errorSurface = SalemXSenderTransportErrorSurface.classify(requested: requested"))
        #expect(adapterSource.contains("return .init(joinFailure: joinDiagnostics,"))
        #expect(adapterSource.contains("transportFailure: transportDiagnostics,"))
        #expect(adapterSource.contains("senderTransportErrorSurfaceFinalClassification = errorSurface.finalClassification"))
        #expect(!adapterSource.contains("senderTransportErrorSurfaceRawErrorLogged = true"))
        #expect(!adapterSource.contains("senderTransportErrorSurfaceRawURLLogged = true"))
        #expect(!adapterSource.contains("senderTransportErrorSurfaceRawTokenLogged = true"))
    }

    @Test
    func senderLiveKitSDKFailureSurfaceClassifiesRedactedBucketsWithoutRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        let sdkBuckets = [
            "sdk_connect_call_threw_redacted",
            "sdk_connect_returned_without_connected_redacted",
            "sdk_delegate_failed_before_connected_redacted",
            "sdk_disconnected_before_connected_redacted",
            "sdk_state_failed_redacted",
            "sdk_room_already_connected_redacted",
            "sdk_identity_conflict_redacted",
            "sdk_token_identity_mismatch_redacted",
            "sdk_audio_session_blocked_redacted",
            "sdk_permission_or_capture_blocked_redacted",
            "sdk_network_transport_error_redacted",
            "sdk_internal_unknown_redacted"
        ]
        for bucket in sdkBuckets {
            #expect(adapterSource.contains(bucket))
        }

        #expect(adapterSource.contains("private struct SalemXSenderLiveKitSDKFailureSurface"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_present=\\(senderLiveKitSDKFailureSurfacePresent)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_debug_only=\\(senderLiveKitSDKFailureSurfaceDebugOnly)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_raw_error_logged=\\(senderLiveKitSDKFailureSurfaceRawErrorLogged)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_raw_url_logged=\\(senderLiveKitSDKFailureSurfaceRawURLLogged)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_raw_token_logged=\\(senderLiveKitSDKFailureSurfaceRawTokenLogged)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_raw_room_logged=\\(senderLiveKitSDKFailureSurfaceRawRoomLogged)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_raw_identity_logged=\\(senderLiveKitSDKFailureSurfaceRawIdentityLogged)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_connect_call_started=\\(senderLiveKitSDKFailureSurfaceConnectCallStarted)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_connect_call_returned=\\(senderLiveKitSDKFailureSurfaceConnectCallReturned)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_connect_call_threw=\\(senderLiveKitSDKFailureSurfaceConnectCallThrew)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_connected_state_observed=\\(senderLiveKitSDKFailureSurfaceConnectedStateObserved)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_failed_state_observed=\\(senderLiveKitSDKFailureSurfaceFailedStateObserved)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_disconnected_before_connected=\\(senderLiveKitSDKFailureSurfaceDisconnectedBeforeConnected)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_delegate_failure_observed=\\(senderLiveKitSDKFailureSurfaceDelegateFailureObserved)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_room_already_connected=\\(senderLiveKitSDKFailureSurfaceRoomAlreadyConnected)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_identity_conflict_observed=\\(senderLiveKitSDKFailureSurfaceIdentityConflictObserved)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_token_identity_match=\\(senderLiveKitSDKFailureSurfaceTokenIdentityMatch)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_audio_session_ready=\\(senderLiveKitSDKFailureSurfaceAudioSessionReady)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_permission_required=\\(senderLiveKitSDKFailureSurfacePermissionRequired)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_capture_started=\\(senderLiveKitSDKFailureSurfaceCaptureStarted)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_final_classification=\\(senderLiveKitSDKFailureSurfaceFinalClassification)"))

        #expect(adapterSource.contains("let debugOnly = true"))
        #expect(adapterSource.contains("let rawErrorLogged = false"))
        #expect(adapterSource.contains("let rawURLLogged = false"))
        #expect(adapterSource.contains("let rawTokenLogged = false"))
        #expect(adapterSource.contains("let rawRoomLogged = false"))
        #expect(adapterSource.contains("let rawIdentityLogged = false"))
        #expect(adapterSource.contains("redactedSenderLiveKitSDKFailureSurfaceInput(components)"))
        #expect(adapterSource.contains("redactedSenderLiveKitSDKFailureClassificationQueryItem(components)"))
        #expect(adapterSource.contains("names: [\"sender_livekit_sdk_failure_surface_connect_call_threw\", \"sender_sdk_connect_call_threw\"]"))
        #expect(adapterSource.contains("names: [\"sender_livekit_sdk_failure_surface_token_identity_match\", \"sender_sdk_token_identity_match\"]"))
        #expect(adapterSource.contains("names: [\"sender_livekit_sdk_failure_surface_audio_session_ready\", \"sender_sdk_audio_session_ready\"]"))
        #expect(adapterSource.contains("names: [\"sender_livekit_sdk_failure_surface_network_transport_error_observed\", \"sender_sdk_network_transport_error_observed\"]"))

        #expect(adapterSource.contains("return connectCallThrewClassification"))
        #expect(adapterSource.contains("return connectReturnedWithoutConnectedClassification"))
        #expect(adapterSource.contains("return delegateFailedBeforeConnectedClassification"))
        #expect(adapterSource.contains("return disconnectedBeforeConnectedClassification"))
        #expect(adapterSource.contains("return stateFailedClassification"))
        #expect(adapterSource.contains("return roomAlreadyConnectedClassification"))
        #expect(adapterSource.contains("return identityConflictClassification"))
        #expect(adapterSource.contains("return tokenIdentityMismatchClassification"))
        #expect(adapterSource.contains("return audioSessionBlockedClassification"))
        #expect(adapterSource.contains("return permissionOrCaptureBlockedClassification"))
        #expect(adapterSource.contains("return networkTransportErrorClassification"))
        #expect(adapterSource.contains("return internalUnknownClassification"))

        #expect(adapterSource.contains("Self.transportClassification(for: finalClassification)"))
        #expect(adapterSource.contains("case connectCallThrewClassification:"))
        #expect(adapterSource.contains("case connectReturnedWithoutConnectedClassification:"))
        #expect(adapterSource.contains("case delegateFailedBeforeConnectedClassification:"))
        #expect(adapterSource.contains("case disconnectedBeforeConnectedClassification:"))
        #expect(adapterSource.contains("case identityConflictClassification:"))
        #expect(adapterSource.contains("case tokenIdentityMismatchClassification:"))
        #expect(adapterSource.contains("case networkTransportErrorClassification:"))
        #expect(adapterSource.contains("case stateFailedClassification,"))
        #expect(adapterSource.contains("return SalemXSenderTransportErrorSurface.transportLiveKitSDKUnknownErrorClassification"))
        #expect(adapterSource.contains("if let classification = input.sdkFailureSurface.transportClassification"))

        #expect(adapterSource.contains("senderLiveKitSDKFailureSurfaceRawErrorLogged = sdkFailureSurface.rawErrorLogged"))
        #expect(adapterSource.contains("senderLiveKitSDKFailureSurfaceRawURLLogged = sdkFailureSurface.rawURLLogged"))
        #expect(adapterSource.contains("senderLiveKitSDKFailureSurfaceRawTokenLogged = sdkFailureSurface.rawTokenLogged"))
        #expect(adapterSource.contains("senderLiveKitSDKFailureSurfaceRawRoomLogged = sdkFailureSurface.rawRoomLogged"))
        #expect(adapterSource.contains("senderLiveKitSDKFailureSurfaceRawIdentityLogged = sdkFailureSurface.rawIdentityLogged"))
        #expect(adapterSource.contains("recordSenderLiveKitSDKFailureSurface(errorSurface.sdkFailureSurface)"))
        #expect(adapterSource.contains("summary.recordSenderTransportErrorSurface(transportErrorSurface)"))
        #expect(adapterSource.contains("baseSummary.recordSenderTransportErrorSurface(senderTransportErrorSurfaceSnapshot)"))
        #expect(adapterSource.contains("let transportDiagnostics = SalemXSenderTransportFailureDiagnostics.classify(.init(requested: requested"))
        #expect(adapterSource.contains("let errorSurface = SalemXSenderTransportErrorSurface.classify(requested: requested"))
        #expect(adapterSource.contains("transportErrorSurface: errorSurface"))
        #expect(adapterSource.contains("sender_join_success_but_remote_missing_redacted"))

        #expect(adapterSource.contains("summary.mediaConnectRequested = false"))
        #expect(adapterSource.contains("summary.mediaConnectAttempted = false"))
        #expect(adapterSource.contains("summary.liveKitJoinRequested = false"))
        #expect(adapterSource.contains("summary.liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("summary.microphonePermissionRequested = false"))
        #expect(adapterSource.contains("summary.cameraPermissionRequested = false"))
        #expect(adapterSource.contains("summary.matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("summary.realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderLiveKitSDKFailureSurfaceRawErrorLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKFailureSurfaceRawURLLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKFailureSurfaceRawTokenLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKFailureSurfaceRawRoomLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKFailureSurfaceRawIdentityLogged = true"))
    }

    @Test
    func senderLiveKitSDKTimelineClassifiesRedactedLifecycleWithoutRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        let timelineFields = [
            "sender_livekit_sdk_timeline_present",
            "sender_livekit_sdk_timeline_debug_only",
            "sender_livekit_sdk_timeline_raw_error_logged",
            "sender_livekit_sdk_timeline_raw_url_logged",
            "sender_livekit_sdk_timeline_raw_token_logged",
            "sender_livekit_sdk_timeline_raw_room_logged",
            "sender_livekit_sdk_timeline_raw_identity_logged",
            "sender_livekit_sdk_timeline_trigger_received",
            "sender_livekit_sdk_timeline_task_created",
            "sender_livekit_sdk_timeline_task_started",
            "sender_livekit_sdk_timeline_connect_invoked",
            "sender_livekit_sdk_timeline_connect_returned",
            "sender_livekit_sdk_timeline_connect_threw",
            "sender_livekit_sdk_timeline_delegate_attached",
            "sender_livekit_sdk_timeline_state_observer_attached",
            "sender_livekit_sdk_timeline_connected_state_seen",
            "sender_livekit_sdk_timeline_failed_state_seen",
            "sender_livekit_sdk_timeline_disconnected_state_seen",
            "sender_livekit_sdk_timeline_task_cancelled",
            "sender_livekit_sdk_timeline_task_completed",
            "sender_livekit_sdk_timeline_timeout_elapsed",
            "sender_livekit_sdk_timeline_proof_written_after_terminal_state",
            "sender_livekit_sdk_timeline_final_classification"
        ]
        for field in timelineFields {
            #expect(adapterSource.contains(field))
        }

        let timelineClassifications = [
            "sdk_timeline_task_not_created_redacted",
            "sdk_timeline_task_created_not_started_redacted",
            "sdk_timeline_task_cancelled_before_connect_redacted",
            "sdk_timeline_connect_invoked_no_return_redacted",
            "sdk_timeline_connect_timeout_redacted",
            "sdk_timeline_delegate_not_attached_redacted",
            "sdk_timeline_state_observer_not_attached_redacted",
            "sdk_timeline_callback_not_observed_redacted",
            "sdk_timeline_proof_written_before_terminal_state_redacted",
            "sdk_timeline_app_lifecycle_interrupted_redacted",
            "sdk_timeline_actor_isolation_lost_callback_redacted",
            "sdk_timeline_internal_pending_redacted"
        ]
        for classification in timelineClassifications {
            #expect(adapterSource.contains(classification))
        }

        #expect(adapterSource.contains("private struct SalemXSenderLiveKitSDKTimeline"))
        #expect(adapterSource.contains("static let allowedClassifications: Set<String>"))
        #expect(adapterSource.contains("let rawErrorLogged = false"))
        #expect(adapterSource.contains("let rawURLLogged = false"))
        #expect(adapterSource.contains("let rawTokenLogged = false"))
        #expect(adapterSource.contains("let rawRoomLogged = false"))
        #expect(adapterSource.contains("let rawIdentityLogged = false"))
        #expect(adapterSource.contains("guard requested, input.provided else"))
        #expect(adapterSource.contains("redactedSenderLiveKitSDKTimelineInput(components)"))
        #expect(adapterSource.contains("redactedSenderLiveKitSDKTimelineClassificationQueryItem(components)"))
        #expect(adapterSource.contains("redactedAnyQueryItem(components,"))
        #expect(adapterSource.contains("allowedClassifications.union(SalemXSenderLiveKitSDKTimeline.allowedClassifications)"))
        #expect(adapterSource.contains("return taskCancelledBeforeConnectClassification"))
        #expect(adapterSource.contains("return connectInvokedNoReturnClassification"))
        #expect(adapterSource.contains("return connectTimeoutClassification"))
        #expect(adapterSource.contains("return delegateNotAttachedClassification"))
        #expect(adapterSource.contains("return stateObserverNotAttachedClassification"))
        #expect(adapterSource.contains("return callbackNotObservedClassification"))
        #expect(adapterSource.contains("return proofWrittenBeforeTerminalStateClassification"))
        #expect(adapterSource.contains("return internalPendingClassification"))

        #expect(adapterSource.contains("senderLiveKitSDKTimelineFinalClassification = timeline.finalClassification"))
        #expect(adapterSource.contains("recordSenderLiveKitSDKTimeline(sdkFailureSurface.timeline)"))
        #expect(adapterSource.contains("timeline.finalClassification != SalemXSenderLiveKitSDKTimeline.notRequestedClassification"))
        #expect(adapterSource.contains("case SalemXSenderLiveKitSDKTimeline.connectTimeoutClassification,"))
        #expect(adapterSource.contains("case SalemXSenderLiveKitSDKTimeline.delegateNotAttachedClassification,"))
        #expect(adapterSource.contains("SalemXSenderLiveKitSDKTimeline.taskNotCreatedClassification,"))
        #expect(adapterSource.contains("return SalemXSenderTransportErrorSurface.transportRoomConnectCallbackFailedClassification"))
        #expect(adapterSource.contains("return SalemXSenderTransportErrorSurface.transportLiveKitSDKUnknownErrorClassification"))
        #expect(adapterSource.contains("if let classification = input.sdkFailureSurface.transportClassification"))
        #expect(adapterSource.contains("senderTransportFailureDiagnosticsClassification = diagnostics.classification"))
        #expect(adapterSource.contains("senderSideLiveKitJoinHook = hook"))
        #expect(adapterSource.contains("sender_side_livekit_join_result=\\(senderSideLiveKitJoinResult)"))
        #expect(adapterSource.contains("sender_join_success_but_remote_missing_redacted"))

        #expect(adapterSource.contains("summary.mediaConnectRequested = false"))
        #expect(adapterSource.contains("summary.mediaConnectAttempted = false"))
        #expect(adapterSource.contains("summary.liveKitJoinRequested = false"))
        #expect(adapterSource.contains("summary.liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("summary.microphonePermissionRequested = false"))
        #expect(adapterSource.contains("summary.cameraPermissionRequested = false"))
        #expect(adapterSource.contains("summary.matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("summary.realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimelineRawErrorLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimelineRawURLLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimelineRawTokenLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimelineRawRoomLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimelineRawIdentityLogged = true"))
    }

    @Test
    func senderLiveKitSDKTimeoutDiagnosticsClassifiesRedactedTimeoutBucketsWithoutRuntime() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        let timeoutFields = [
            "sender_livekit_sdk_timeout_diagnostics_present=\\(senderLiveKitSDKTimeoutDiagnosticsPresent)",
            "sender_livekit_sdk_timeout_diagnostics_debug_only=\\(senderLiveKitSDKTimeoutDiagnosticsDebugOnly)",
            "sender_livekit_sdk_timeout_diagnostics_raw_error_logged=\\(senderLiveKitSDKTimeoutDiagnosticsRawErrorLogged)",
            "sender_livekit_sdk_timeout_diagnostics_raw_url_logged=\\(senderLiveKitSDKTimeoutDiagnosticsRawURLLogged)",
            "sender_livekit_sdk_timeout_diagnostics_raw_token_logged=\\(senderLiveKitSDKTimeoutDiagnosticsRawTokenLogged)",
            "sender_livekit_sdk_timeout_diagnostics_raw_room_logged=\\(senderLiveKitSDKTimeoutDiagnosticsRawRoomLogged)",
            "sender_livekit_sdk_timeout_diagnostics_raw_identity_logged=\\(senderLiveKitSDKTimeoutDiagnosticsRawIdentityLogged)",
            "sender_livekit_sdk_timeout_diagnostics_wait_window_bucket=\\(senderLiveKitSDKTimeoutDiagnosticsWaitWindowBucket)",
            "sender_livekit_sdk_timeout_diagnostics_connect_invoked=\\(senderLiveKitSDKTimeoutDiagnosticsConnectInvoked)",
            "sender_livekit_sdk_timeout_diagnostics_connect_call_pending_at_timeout=\\(senderLiveKitSDKTimeoutDiagnosticsConnectCallPendingAtTimeout)",
            "sender_livekit_sdk_timeout_diagnostics_task_running_at_timeout=\\(senderLiveKitSDKTimeoutDiagnosticsTaskRunningAtTimeout)",
            "sender_livekit_sdk_timeout_diagnostics_task_cancelled_at_timeout=\\(senderLiveKitSDKTimeoutDiagnosticsTaskCancelledAtTimeout)",
            "sender_livekit_sdk_timeout_diagnostics_delegate_attached=\\(senderLiveKitSDKTimeoutDiagnosticsDelegateAttached)",
            "sender_livekit_sdk_timeout_diagnostics_state_observer_attached=\\(senderLiveKitSDKTimeoutDiagnosticsStateObserverAttached)",
            "sender_livekit_sdk_timeout_diagnostics_state_event_count_bucket=\\(senderLiveKitSDKTimeoutDiagnosticsStateEventCountBucket)",
            "sender_livekit_sdk_timeout_diagnostics_delegate_event_count_bucket=\\(senderLiveKitSDKTimeoutDiagnosticsDelegateEventCountBucket)",
            "sender_livekit_sdk_timeout_diagnostics_app_state_bucket=\\(senderLiveKitSDKTimeoutDiagnosticsAppStateBucket)",
            "sender_livekit_sdk_timeout_diagnostics_actor_context_available=\\(senderLiveKitSDKTimeoutDiagnosticsActorContextAvailable)",
            "sender_livekit_sdk_timeout_diagnostics_network_path_bucket=\\(senderLiveKitSDKTimeoutDiagnosticsNetworkPathBucket)",
            "sender_livekit_sdk_timeout_diagnostics_final_classification=\\(senderLiveKitSDKTimeoutDiagnosticsFinalClassification)"
        ]
        for field in timeoutFields {
            #expect(adapterSource.contains(field))
        }

        let timeoutBuckets = [
            "sdk_connect_timeout_no_state_events_redacted",
            "sdk_connect_timeout_delegate_missing_redacted",
            "sdk_connect_timeout_state_observer_missing_redacted",
            "sdk_connect_timeout_task_suspended_redacted",
            "sdk_connect_timeout_task_running_no_callback_redacted",
            "sdk_connect_timeout_connect_call_pending_redacted",
            "sdk_connect_timeout_network_pending_redacted",
            "sdk_connect_timeout_auth_pending_redacted",
            "sdk_connect_timeout_app_lifecycle_interrupted_redacted",
            "sdk_connect_timeout_actor_isolation_suspected_redacted",
            "sdk_connect_timeout_wait_window_too_short_redacted",
            "sdk_connect_timeout_unknown_pending_redacted"
        ]
        for bucket in timeoutBuckets {
            #expect(adapterSource.contains(bucket))
        }

        #expect(adapterSource.contains("private struct SalemXSenderLiveKitSDKTimeoutDiagnostics"))
        #expect(adapterSource.contains("private struct SalemXSenderLiveKitSDKTimeoutDiagnosticsInput"))
        #expect(adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticQueryItemNames"))
        #expect(adapterSource.contains("redactedSenderLiveKitSDKTimeoutDiagnosticsInput(components)"))
        #expect(adapterSource.contains("redactedSenderLiveKitSDKTimeoutDiagnosticsClassificationQueryItem(components)"))
        #expect(adapterSource.contains("allowedWaitWindowBuckets"))
        #expect(adapterSource.contains("allowedCountBuckets"))
        #expect(adapterSource.contains("allowedAppStateBuckets"))
        #expect(adapterSource.contains("allowedNetworkPathBuckets"))
        #expect(adapterSource.contains("let present = true"))
        #expect(adapterSource.contains("let debugOnly = true"))
        #expect(adapterSource.contains("let rawErrorLogged = false"))
        #expect(adapterSource.contains("let rawURLLogged = false"))
        #expect(adapterSource.contains("let rawTokenLogged = false"))
        #expect(adapterSource.contains("let rawRoomLogged = false"))
        #expect(adapterSource.contains("let rawIdentityLogged = false"))

        #expect(adapterSource.contains("if !input.delegateAttached"))
        #expect(adapterSource.contains("return delegateMissingClassification"))
        #expect(adapterSource.contains("if !input.stateObserverAttached"))
        #expect(adapterSource.contains("return stateObserverMissingClassification"))
        #expect(adapterSource.contains("return waitWindowTooShortClassification"))
        #expect(adapterSource.contains("return taskSuspendedClassification"))
        #expect(adapterSource.contains("return appLifecycleInterruptedClassification"))
        #expect(adapterSource.contains("return actorIsolationSuspectedClassification"))
        #expect(adapterSource.contains("return authPendingClassification"))
        #expect(adapterSource.contains("return networkPendingClassification"))
        #expect(adapterSource.contains("return noStateEventsClassification"))
        #expect(adapterSource.contains("return connectCallPendingClassification"))
        #expect(adapterSource.contains("return taskRunningNoCallbackClassification"))
        #expect(adapterSource.contains("return unknownPendingClassification"))

        #expect(adapterSource.contains("timeoutDiagnostics.finalClassification != SalemXSenderLiveKitSDKTimeoutDiagnostics.notRequestedClassification"))
        #expect(adapterSource.contains("SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedClassifications.contains(classification)"))
        #expect(adapterSource.contains("SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedClassifications.contains(input.sdkFailureSurface.finalClassification)"))
        #expect(adapterSource.contains("]).union(SalemXSenderLiveKitSDKTimeoutDiagnostics.allowedClassifications)"))
        #expect(adapterSource.contains("recordSenderLiveKitSDKTimeoutDiagnostics(sdkFailureSurface.timeline.timeoutDiagnostics)"))
        #expect(adapterSource.contains("recordSenderLiveKitSDKTimeoutDiagnostics(timeline.timeoutDiagnostics)"))
        #expect(adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawErrorLogged = diagnostics.rawErrorLogged"))
        #expect(adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawURLLogged = diagnostics.rawURLLogged"))
        #expect(adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawTokenLogged = diagnostics.rawTokenLogged"))
        #expect(adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawRoomLogged = diagnostics.rawRoomLogged"))
        #expect(adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawIdentityLogged = diagnostics.rawIdentityLogged"))

        #expect(adapterSource.contains("senderTransportFailureDiagnosticsClassification = diagnostics.classification"))
        #expect(adapterSource.contains("senderSideLiveKitJoinErrorBucket = hook.errorBucket"))
        #expect(adapterSource.contains("sender_side_livekit_join_result=\\(senderSideLiveKitJoinResult)"))
        #expect(adapterSource.contains("sender_join_success_but_remote_missing_redacted"))
        #expect(adapterSource.contains("summary.mediaConnectRequested = false"))
        #expect(adapterSource.contains("summary.mediaConnectAttempted = false"))
        #expect(adapterSource.contains("summary.liveKitJoinRequested = false"))
        #expect(adapterSource.contains("summary.microphonePermissionRequested = false"))
        #expect(adapterSource.contains("summary.cameraPermissionRequested = false"))
        #expect(adapterSource.contains("summary.matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("summary.realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawErrorLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawURLLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawTokenLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawRoomLogged = true"))
        #expect(!adapterSource.contains("senderLiveKitSDKTimeoutDiagnosticsRawIdentityLogged = true"))
    }

    @Test
    // swiftlint:disable:next function_body_length
    func senderJoinTriggerOrchestrationBlocksEarlyProofPollingUntilSenderTimelineTerminal() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        let orchestrationFields = [
            "sender_join_trigger_orchestration_present=\\(senderJoinTriggerOrchestrationPresent)",
            "sender_join_trigger_orchestration_debug_only=\\(senderJoinTriggerOrchestrationDebugOnly)",
            "sender_join_trigger_orchestration_raw_identifiers_logged=\\(senderJoinTriggerOrchestrationRawIdentifiersLogged)",
            "sender_join_trigger_orchestration_apns_success_seen=\\(senderJoinTriggerOrchestrationAPNsSuccessSeen)",
            "sender_join_trigger_orchestration_receiver_answer_seen=\\(senderJoinTriggerOrchestrationReceiverAnswerSeen)",
            "sender_join_trigger_orchestration_receiver_connect_terminal_seen=\\(senderJoinTriggerOrchestrationReceiverConnectTerminalSeen)",
            "sender_join_trigger_orchestration_sender_activation_armed=\\(senderJoinTriggerOrchestrationSenderActivationArmed)",
            "sender_join_trigger_orchestration_sender_trigger_required=\\(senderJoinTriggerOrchestrationSenderTriggerRequired)",
            "sender_join_trigger_orchestration_sender_trigger_allowed=\\(senderJoinTriggerOrchestrationSenderTriggerAllowed)",
            "sender_join_trigger_orchestration_sender_trigger_started=\\(senderJoinTriggerOrchestrationSenderTriggerStarted)",
            "sender_join_trigger_orchestration_sender_trigger_completed=\\(senderJoinTriggerOrchestrationSenderTriggerCompleted)",
            "sender_join_trigger_orchestration_sender_trigger_missing_classified=\\(senderJoinTriggerOrchestrationSenderTriggerMissingClassified)",
            "sender_join_trigger_orchestration_poll_allowed=\\(senderJoinTriggerOrchestrationPollAllowed)",
            "sender_join_trigger_orchestration_poll_blocked_reason=\\(senderJoinTriggerOrchestrationPollBlockedReason)",
            "sender_join_trigger_orchestration_final_classification=\\(senderJoinTriggerOrchestrationFinalClassification)"
        ]
        for field in orchestrationFields {
            #expect(adapterSource.contains(field))
        }

        let orchestrationBuckets = [
            "sender_trigger_waiting_for_answer_redacted",
            "sender_trigger_waiting_for_receiver_connect_redacted",
            "sender_trigger_activation_not_armed_redacted",
            "sender_trigger_required_but_not_started_redacted",
            "sender_trigger_started_not_completed_redacted",
            "sender_trigger_completed_waiting_for_sdk_timeline_redacted",
            "sender_trigger_completed_sdk_timeline_terminal_redacted",
            "sender_trigger_poll_blocked_until_sender_terminal_redacted"
        ]
        for bucket in orchestrationBuckets {
            #expect(adapterSource.contains(bucket))
        }

        #expect(adapterSource.contains("private struct SalemXSenderJoinTriggerOrchestration"))
        #expect(adapterSource.contains("private struct SalemXSenderJoinTriggerOrchestrationInput"))
        #expect(adapterSource.contains("static let defaultBlocked = SalemXSenderJoinTriggerOrchestration(input: .init(apnsSuccessSeen: false,"))
        #expect(adapterSource.contains("let present = true"))
        #expect(adapterSource.contains("let debugOnly = true"))
        #expect(adapterSource.contains("let rawIdentifiersLogged = false"))
        #expect(adapterSource.contains("let senderTriggerRequired = true"))
        #expect(adapterSource.contains("var senderTriggerAllowed: Bool"))
        #expect(adapterSource.contains("apnsSuccessSeen && receiverAnswerSeen && receiverConnectTerminalSeen && senderActivationArmed"))
        #expect(adapterSource.contains("var pollAllowed: Bool"))
        #expect(adapterSource.contains("senderTriggerCompleted && senderSDKTimelineTerminalSeen"))
        #expect(adapterSource.contains("var pollBlockedReason: String"))
        #expect(adapterSource.contains("return Self.pollBlockedUntilSenderTerminalClassification"))
        #expect(adapterSource.contains("if !apnsSuccessSeen || !receiverAnswerSeen"))
        #expect(adapterSource.contains("return Self.waitingForAnswerClassification"))
        #expect(adapterSource.contains("if !receiverConnectTerminalSeen"))
        #expect(adapterSource.contains("return Self.waitingForReceiverConnectClassification"))
        #expect(adapterSource.contains("if !senderActivationArmed"))
        #expect(adapterSource.contains("return Self.activationNotArmedClassification"))
        #expect(adapterSource.contains("if !senderTriggerStarted"))
        #expect(adapterSource.contains("return Self.requiredButNotStartedClassification"))
        #expect(adapterSource.contains("if !senderTriggerCompleted"))
        #expect(adapterSource.contains("return Self.startedNotCompletedClassification"))
        #expect(adapterSource.contains("if !senderSDKTimelineTerminalSeen"))
        #expect(adapterSource.contains("return Self.completedWaitingForSDKTimelineClassification"))
        #expect(adapterSource.contains("return Self.completedSDKTimelineTerminalClassification"))

        #expect(adapterSource.contains("mutating func refreshSenderJoinTriggerOrchestration()"))
        #expect(adapterSource.contains("apnsSuccessSeen: physicalVoIPPushReceived"))
        #expect(adapterSource.contains("receiverAnswerSeen: receiverAnswerSeen"))
        #expect(adapterSource.contains("receiverConnectTerminalSeen: receiverConnectTerminalSeen"))
        #expect(adapterSource.contains("senderActivationArmed: senderSideLiveKitJoinActivationArmed"))
        #expect(adapterSource.contains("senderTriggerStarted: senderTriggerStarted"))
        #expect(adapterSource.contains("senderTriggerCompleted: senderTriggerCompleted"))
        #expect(adapterSource.contains("senderSDKTimelineTerminalSeen: senderSDKTimelineTerminalSeen"))
        #expect(adapterSource.contains("senderJoinTriggerOrchestrationSenderTriggerRequired = orchestration.senderTriggerRequired"))
        #expect(adapterSource.contains("senderJoinTriggerOrchestrationSenderTriggerAllowed = orchestration.senderTriggerAllowed"))
        #expect(adapterSource.contains("senderJoinTriggerOrchestrationPollAllowed = orchestration.pollAllowed"))
        #expect(adapterSource.contains("senderJoinTriggerOrchestrationFinalClassification = orchestration.finalClassification"))

        #expect(adapterSource.contains("callKitFirstActionKind == \"answer\" && callKitAnswerActionReceived && callKitAnswerActionFulfilled"))
        #expect(adapterSource.contains("controlledConnectFirstAttemptCompleted || controlledConnectFirstAttemptResult != SalemXControlledAudioConnectFirstAttempt.defaultDisabled.result"))
        #expect(adapterSource.contains("senderSideLiveKitJoinActivationTriggered || senderSideLiveKitJoinRequested || senderLiveKitSDKTimelineTriggerReceived"))
        #expect(adapterSource.contains("senderSideLiveKitJoinActivationConsumed || (senderSideLiveKitJoinRequested && senderSideLiveKitJoinResult != SalemXSenderSideLiveKitJoinHook.notRequestedResult)"))
        #expect(adapterSource.contains("SalemXSenderLiveKitSDKTimeline.terminalClassifications.contains(senderLiveKitSDKTimelineFinalClassification)"))

        #expect(adapterSource.contains("recordSenderLiveKitSDKTimeline(sdkFailureSurface.timeline)"))
        #expect(adapterSource.contains("recordSenderSideLiveKitJoinActivation(activation)"))
        #expect(adapterSource.contains("refreshSenderJoinTriggerOrchestration()"))
        #expect(adapterSource.contains("sender_side_livekit_join_result=\\(senderSideLiveKitJoinResult)"))
        #expect(adapterSource.contains("senderSideLiveKitJoinResult == SalemXSenderSideLiveKitJoinHook.notRequestedResult"))
        #expect(adapterSource.contains("receiverRemoteParticipantObserverResult = classification.result"))
        #expect(adapterSource.contains("liveKitAudioLivenessResult = \"not_observed_redacted\""))

        #expect(adapterSource.contains("sender_livekit_sdk_timeline_final_classification=\\(senderLiveKitSDKTimelineFinalClassification)"))
        #expect(adapterSource.contains("sender_livekit_sdk_failure_surface_final_classification=\\(senderLiveKitSDKFailureSurfaceFinalClassification)"))
        #expect(adapterSource.contains("sender_transport_failure_diagnostics_classification=\\(senderTransportFailureDiagnosticsClassification)"))
        #expect(adapterSource.contains("sender_readiness_runtime_handoff_survived_answer=\\(senderReadinessRuntimeHandoffSurvivedAnswer)"))
        #expect(adapterSource.contains("receiver_remote_participant_observer_result=\\(receiverRemoteParticipantObserverResult)"))

        #expect(adapterSource.contains("summary.mediaConnectRequested = false"))
        #expect(adapterSource.contains("summary.mediaConnectAttempted = false"))
        #expect(adapterSource.contains("summary.liveKitJoinRequested = false"))
        #expect(adapterSource.contains("summary.liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("summary.microphonePermissionRequested = false"))
        #expect(adapterSource.contains("summary.cameraPermissionRequested = false"))
        #expect(adapterSource.contains("summary.matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("summary.realCallFlowStarted = false"))
        #expect(adapterSource.contains("cameraPermissionRequested = false"))
        #expect(adapterSource.contains("matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("realCallFlowStarted = false"))
        #expect(!adapterSource.contains("senderJoinTriggerOrchestrationRawIdentifiersLogged = true"))
        #expect(!adapterSource.contains("senderJoinTriggerOrchestrationPollAllowed = true"))
        #expect(!adapterSource.contains("senderJoinTriggerOrchestrationSenderTriggerRequired = false"))
    }

    @Test
    func remotePeerContextHandoffRecordsSimulatorContextAndMissingContextSafely() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("private struct SalemXRemotePeerContextHandoff"))
        #expect(adapterSource.contains("static let simulatorReady = SalemXRemotePeerContextHandoff(source: \"debug_hook_redacted\""))
        #expect(adapterSource.contains("peerKind: \"ios_simulator_redacted\""))
        #expect(adapterSource.contains("physicalDevice: \"false\""))
        #expect(adapterSource.contains("simulatorAssisted: true"))
        #expect(adapterSource.contains("static let physicalIOSReady = SalemXRemotePeerContextHandoff(source: \"debug_hook_redacted\""))
        #expect(adapterSource.contains("peerKind: \"physical_ios_redacted\""))
        #expect(adapterSource.contains("physicalDevice: \"true\""))
        #expect(adapterSource.contains("simulatorAssisted: false"))
        #expect(adapterSource.contains("readiness: \"ready_redacted\""))
        #expect(adapterSource.contains("armedBeforeAPNs: true"))
        #expect(adapterSource.contains("private static let remotePeerContextHandoffURLHookPath = \"/direct-call/remote-peer-context-handoff\""))
        #expect(adapterSource.contains("private static var pendingRemotePeerContextHandoff: SalemXRemotePeerContextHandoff?"))
        #expect(adapterSource.contains("if normalizedPath == remotePeerContextHandoffURLHookPath"))
        #expect(adapterSource.contains("let peerKind = components?.queryItems?.first { $0.name == \"peer_kind\" || $0.name == \"remote_peer_kind\" }?.value ?? \"\""))
        #expect(adapterSource.contains("peerKind == \"physical_ios\" || peerKind == \"physical_ios_redacted\""))
        #expect(adapterSource.contains("armPhysicalIOSRemotePeerContextHandoffURLHook()"))
        #expect(adapterSource.contains("armSimulatorRemotePeerContextHandoffURLHook()"))
        #expect(adapterSource.contains("private static func armSimulatorRemotePeerContextHandoffURLHook()"))
        #expect(adapterSource.contains("private static func armPhysicalIOSRemotePeerContextHandoffURLHook()"))
        #expect(adapterSource.contains("private static func armRemotePeerContextHandoffURLHook(_ context: SalemXRemotePeerContextHandoff)"))
        #expect(adapterSource.contains("pendingRemotePeerContextHandoff = context"))
        #expect(adapterSource.contains("summary.recordRemotePeerContextHandoff(context,"))
        #expect(adapterSource.contains("receivedByRuntime: false"))
        #expect(adapterSource.contains("let remotePeerContextHandoffSnapshot = pendingRemotePeerContextHandoff"))
        #expect(adapterSource.contains("pendingRemotePeerContextHandoff = nil"))
        #expect(adapterSource.contains("baseSummary.recordRemotePeerContextHandoff(remotePeerContextHandoffSnapshot)"))
        #expect(adapterSource.contains("receivedByRuntime: true"))
        #expect(adapterSource.contains("survivedPushKit: true"))
        #expect(adapterSource.contains("survivedAnswer: false"))
        #expect(adapterSource.contains("summary.markRemotePeerContextHandoffSurvivedAnswer()"))

        #expect(adapterSource.contains("mutating func recordRemotePeerContextHandoff(_ context: SalemXRemotePeerContextHandoff,"))
        #expect(adapterSource.contains("mutating func recordRemotePeerContextHandoff(_ context: SalemXRemotePeerContextHandoff?)"))
        #expect(adapterSource.contains("guard let context else"))
        #expect(adapterSource.contains("recordMissingRemotePeerContextHandoff()"))
        #expect(adapterSource.contains("remotePeerContextHandoffSource = context.source"))
        #expect(adapterSource.contains("remotePeerContextHandoffArmedBeforeAPNs = context.armedBeforeAPNs"))
        #expect(adapterSource.contains("remotePeerContextHandoffReceivedByRuntime = receivedByRuntime"))
        #expect(adapterSource.contains("remotePeerContextHandoffSurvivedPushKit = survivedPushKit"))
        #expect(adapterSource.contains("remotePeerContextHandoffSurvivedAnswer = survivedAnswer"))
        #expect(adapterSource.contains("remotePeerContextHandoffRawIdentifiersLogged = false"))
        #expect(adapterSource.contains("secondDeviceRemoteAudioReadiness = context.readiness"))
        #expect(adapterSource.contains("recordRemoteAudioPeerClassification(peerKind: context.peerKind,"))
        #expect(adapterSource.contains("remoteAudioLivenessLimitation = simulatorAssisted ? \"simulator_assisted_redacted\" : limitation"))
        #expect(adapterSource.contains("productionLikeTwoPhysicalDeviceProof = physicalDevice == \"true\" && !simulatorAssisted"))

        #expect(adapterSource.contains("mutating func recordMissingRemotePeerContextHandoff()"))
        #expect(adapterSource.contains("remotePeerContextHandoffReceivedByRuntime = false"))
        #expect(adapterSource.contains("remotePeerKind = \"unknown_redacted\""))
        #expect(adapterSource.contains("simulatorAssistedRemoteAudioProof = false"))
        #expect(adapterSource.contains("secondDeviceRemoteAudioReadiness = \"unknown_redacted\""))
        #expect(adapterSource.contains("remoteAudioLivenessLimitation = \"remote_peer_context_not_handed_off_redacted\""))
        #expect(adapterSource.contains("liveKitAudioLivenessResult = \"not_observed_redacted\""))
        #expect(adapterSource.contains("liveKitAudioLivenessErrorBucket = \"remote_peer_context_missing_redacted\""))
        #expect(adapterSource.contains("liveKitAudioLivenessErrorBucket = \"remote_participant_missing_redacted\""))
        #expect(adapterSource.contains("liveKitAudioLivenessErrorBucket = \"remote_audio_track_missing_redacted\""))

        #expect(adapterSource.contains("remotePeerContextHandoffBlocksSuccessWithoutContext = true"))
        #expect(adapterSource.contains("remotePeerContextHandoffClassifiesMissingRemoteParticipant = true"))
        #expect(adapterSource.contains("remotePeerContextHandoffClassifiesSimulatorLimitation = true"))
        #expect(adapterSource.contains("cameraPermissionRequested = false"))
        #expect(adapterSource.contains("matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("realCallFlowStarted = false"))
    }

    @Test
    func controlledCallKitReportClearsStaleSyntheticCallBeforeNewReport() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("func endSyntheticIncomingCall() -> NativeIncomingSyntheticCallKitUIProofEvent"))
        #expect(adapterSource.contains("callKitProofHarness?.endSyntheticIncomingCall()"))

        let nextGeneration = try #require(adapterSource.range(of: "let generation = nextCallKitProofGeneration()")?.lowerBound)
        let staleCleanup = try #require(adapterSource.range(of: "callKitProofHarness?.endSyntheticIncomingCall()", range: nextGeneration..<adapterSource.endIndex)?.lowerBound)
        let clearHarness = try #require(adapterSource.range(of: "callKitProofHarness = nil", range: staleCleanup..<adapterSource.endIndex)?.lowerBound)
        let newHarness = try #require(adapterSource.range(of: "NativeIncomingSyntheticCallKitUIProofHarness.makePhysicalDeviceProofHarness", range: clearHarness..<adapterSource.endIndex)?.lowerBound)

        #expect(nextGeneration < staleCleanup)
        #expect(staleCleanup < clearHarness)
        #expect(clearHarness < newHarness)
    }

    @Test
    // swiftlint:disable:next function_body_length
    func realInviteAnswerProofRecordsForegroundPendingCallStateOnly() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("foreground_call_state_handoff_requested=\\(foregroundCallStateHandoffRequested)"))
        #expect(adapterSource.contains("foreground_call_state_handoff_observed=\\(foregroundCallStateHandoffObserved)"))
        #expect(adapterSource.contains("foreground_call_state=\\(foregroundCallState)"))
        #expect(adapterSource.contains("foreground_call_state_source=\\(foregroundCallStateSource)"))
        #expect(adapterSource.contains("foreground_call_state_payload_redacted=\\(foregroundCallStatePayloadRedacted)"))
        #expect(adapterSource.contains("foreground_call_state_has_stable_redacted_correlation=\\(foregroundCallStateHasStableRedactedCorrelation)"))
        #expect(adapterSource.contains("pending_metadata_reference_present=\\(pendingMetadataReferencePresent)"))
        #expect(adapterSource.contains("pending_metadata_reference_redacted=\\(pendingMetadataReferenceRedacted)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_present=\\(pendingMetadataReferenceRepairPresent)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_debug_only=\\(pendingMetadataReferenceRepairDebugOnly)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_real_invite_required=\\(pendingMetadataReferenceRepairRealInviteRequired)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_reference_created_before_apns=\\(pendingMetadataReferenceRepairReferenceCreatedBeforeAPNs)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_reference_present_in_apns_payload=\\(pendingMetadataReferenceRepairReferencePresentInAPNsPayload)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_reference_observed_by_pushkit=\\(pendingMetadataReferenceRepairReferenceObservedByPushKit)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_reference_handed_to_answer_pipeline=\\(pendingMetadataReferenceRepairReferenceHandedToAnswerPipeline)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_blocks_apns_without_reference=\\(pendingMetadataReferenceRepairBlocksAPNsWithoutReference)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_blocks_credentials_without_metadata_success=\\(pendingMetadataReferenceRepairBlocksCredentialsWithoutMetadataSuccess)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_no_direct_credentials_bypass=\\(pendingMetadataReferenceRepairNoDirectCredentialsBypass)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_no_connect_bypass=\\(pendingMetadataReferenceRepairNoConnectBypass)"))
        #expect(adapterSource.contains("pending_metadata_reference_repair_raw_metadata_logged=\\(pendingMetadataReferenceRepairRawMetadataLogged)"))
        #expect(adapterSource.contains("pending_metadata_fetch_required=\\(pendingMetadataFetchRequired)"))
        #expect(adapterSource.contains("pending_metadata_fetch_requested=\\(pendingMetadataFetchRequested)"))
        #expect(adapterSource.contains("pending_metadata_fetch_authorized=\\(pendingMetadataFetchAuthorized)"))
        #expect(adapterSource.contains("pending_metadata_fetch_result=\\(pendingMetadataFetchResult)"))
        #expect(adapterSource.contains("pending_metadata_fetch_http_status_bucket=\\(pendingMetadataFetchHTTPStatusBucket)"))
        #expect(adapterSource.contains("pending_metadata_fetch_errcode=\\(pendingMetadataFetchErrcode)"))
        #expect(adapterSource.contains("pending_metadata_fetch_failure_reason=\\(pendingMetadataFetchFailureReason)"))
        #expect(adapterSource.contains("pending_metadata_payload_redacted=\\(pendingMetadataPayloadRedacted)"))
        #expect(adapterSource.contains("foreground_pending_call_metadata_handoff_requested=\\(foregroundPendingCallMetadataHandoffRequested)"))
        #expect(adapterSource.contains("foreground_pending_call_metadata_handoff_observed=\\(foregroundPendingCallMetadataHandoffObserved)"))
        #expect(adapterSource.contains("foreground_pending_call_metadata_source=\\(foregroundPendingCallMetadataSource)"))
        #expect(adapterSource.contains("foreground_pending_call_metadata_payload_redacted=\\(foregroundPendingCallMetadataPayloadRedacted)"))
        #expect(adapterSource.contains("foreground_pending_call_metadata_has_call_identifier=\\(foregroundPendingCallMetadataHasCallIdentifier)"))
        #expect(adapterSource.contains("foreground_pending_call_metadata_has_room_binding=\\(foregroundPendingCallMetadataHasRoomBinding)"))
        #expect(adapterSource.contains("foreground_pending_call_metadata_has_peer=\\(foregroundPendingCallMetadataHasPeer)"))
        #expect(adapterSource.contains("foreground_pending_call_metadata_direction=\\(foregroundPendingCallMetadataDirection)"))
        #expect(adapterSource.contains("foreground_pending_call_metadata_intent=\\(foregroundPendingCallMetadataIntent)"))
        #expect(adapterSource.contains("media_credentials_request_metadata_available=\\(mediaCredentialsRequestMetadataAvailable)"))
        #expect(adapterSource.contains("media_credentials_request_metadata_redacted=\\(mediaCredentialsRequestMetadataRedacted)"))
        #expect(adapterSource.contains("media_credentials_request_metadata_source=\\(mediaCredentialsRequestMetadataSource)"))
        #expect(adapterSource.contains("media_credentials_boundary_reached=\\(mediaCredentialsBoundaryReached)"))
        #expect(adapterSource.contains("media_credentials_request_planned=\\(mediaCredentialsRequestPlanned)"))
        #expect(adapterSource.contains("media_credentials_requested=\\(mediaCredentialsRequested)"))
        #expect(adapterSource.contains("media_credentials_request_authorized=\\(mediaCredentialsRequestAuthorized)"))
        #expect(adapterSource.contains("media_credentials_result=\\(mediaCredentialsResult)"))
        #expect(adapterSource.contains("media_credentials_token_received=\\(mediaCredentialsTokenReceived)"))
        #expect(adapterSource.contains("media_credentials_token_redacted=\\(mediaCredentialsTokenRedacted)"))
        #expect(adapterSource.contains("media_credentials_url_received=\\(mediaCredentialsURLReceived)"))
        #expect(adapterSource.contains("media_credentials_url_redacted=\\(mediaCredentialsURLRedacted)"))
        #expect(adapterSource.contains("media_credentials_expires_at_present=\\(mediaCredentialsExpiresAtPresent)"))
        #expect(adapterSource.contains("media_credentials_payload_redacted=\\(mediaCredentialsPayloadRedacted)"))
        #expect(adapterSource.contains("media_credentials_local_persistence_requested=\\(mediaCredentialsLocalPersistenceRequested)"))
        #expect(adapterSource.contains("media_credentials_cleanup_requested=\\(mediaCredentialsCleanupRequested)"))
        #expect(adapterSource.contains("media_credentials_cleanup_result=\\(mediaCredentialsCleanupResult)"))
        #expect(adapterSource.contains("media_credentials_post_cleanup_token_present=\\(mediaCredentialsPostCleanupTokenPresent)"))
        #expect(adapterSource.contains("media_credentials_post_cleanup_url_present=\\(mediaCredentialsPostCleanupURLPresent)"))
        #expect(adapterSource.contains("media_credentials_post_cleanup_expires_at_present=\\(mediaCredentialsPostCleanupExpiresAtPresent)"))
        #expect(adapterSource.contains("media_credentials_post_cleanup_payload_present=\\(mediaCredentialsPostCleanupPayloadPresent)"))
        #expect(adapterSource.contains("media_credentials_reuse_attempted=\\(mediaCredentialsReuseAttempted)"))
        #expect(adapterSource.contains("media_credentials_reuse_allowed=\\(mediaCredentialsReuseAllowed)"))
        #expect(adapterSource.contains("media_credentials_expiry_reference_present=\\(mediaCredentialsExpiryReferencePresent)"))
        #expect(adapterSource.contains("media_credentials_expiry_check_requested=\\(mediaCredentialsExpiryCheckRequested)"))
        #expect(adapterSource.contains("media_credentials_expiry_check_result=\\(mediaCredentialsExpiryCheckResult)"))
        #expect(adapterSource.contains("media_credentials_token_request_seen=\\(mediaCredentialsTokenRequestSeen)"))
        #expect(adapterSource.contains("media_credentials_token_http_status_bucket=\\(mediaCredentialsTokenHTTPStatusBucket)"))
        #expect(adapterSource.contains("media_credentials_token_reason=\\(mediaCredentialsTokenReason)"))
        #expect(adapterSource.contains("media_credentials_eligibility_allowed=\\(mediaCredentialsEligibilityAllowed)"))
        #expect(adapterSource.contains("media_credentials_rate_limited=\\(mediaCredentialsRateLimited)"))
        #expect(adapterSource.contains("media_credentials_allocation_attempted=\\(mediaCredentialsAllocationAttempted)"))
        #expect(adapterSource.contains("media_credentials_livekit_room_precreate_attempted=\\(mediaCredentialsLiveKitRoomPrecreateAttempted)"))
        #expect(adapterSource.contains("media_credentials_token_issued=\\(mediaCredentialsTokenIssued)"))
        #expect(adapterSource.contains("controlled_connect_activation_wiring_present=\\(controlledConnectActivationWiringPresent)"))
        #expect(adapterSource.contains("controlled_connect_activation_debug_only=\\(controlledConnectActivationDebugOnly)"))
        #expect(adapterSource.contains("controlled_connect_activation_default_disabled=\\(controlledConnectActivationDefaultDisabled)"))
        #expect(adapterSource.contains("controlled_connect_activation_requires_operator_approval=\\(controlledConnectActivationRequiresOperatorApproval)"))
        #expect(adapterSource.contains("controlled_connect_activation_rollback_available=\\(controlledConnectActivationRollbackAvailable)"))
        #expect(adapterSource.contains("controlled_connect_activation_scope=\\(controlledConnectActivationScope)"))
        #expect(adapterSource.contains("controlled_connect_video_allowed=\\(controlledConnectVideoAllowed)"))
        #expect(adapterSource.contains("controlled_connect_matrix_events_allowed=\\(controlledConnectMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_connect_raw_credentials_logged=\\(controlledConnectRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_connect_switch_present=\\(controlledConnectSwitchPresent)"))
        #expect(adapterSource.contains("controlled_connect_switch_debug_only=\\(controlledConnectSwitchDebugOnly)"))
        #expect(adapterSource.contains("controlled_connect_switch_enabled=\\(controlledConnectSwitchEnabled)"))
        #expect(adapterSource.contains("controlled_connect_operator_approved=\\(controlledConnectOperatorApproved)"))
        #expect(adapterSource.contains("controlled_connect_execution_allowed=\\(controlledConnectExecutionAllowed)"))
        #expect(adapterSource.contains("controlled_connect_blocked_reason=\\(controlledConnectBlockedReason)"))
        #expect(adapterSource.contains("controlled_connect_blocked_before_engine=\\(controlledConnectBlockedBeforeEngine)"))
        #expect(adapterSource.contains("controlled_connect_blocked_before_livekit_join=\\(controlledConnectBlockedBeforeLiveKitJoin)"))
        #expect(adapterSource.contains("controlled_connect_blocked_before_permissions=\\(controlledConnectBlockedBeforePermissions)"))
        #expect(adapterSource.contains("controlled_connect_blocked_before_matrix_events=\\(controlledConnectBlockedBeforeMatrixEvents)"))
        #expect(adapterSource.contains("media_connect_preflight_requested=\\(mediaConnectPreflightRequested)"))
        #expect(adapterSource.contains("media_connect_preflight_metadata_available=\\(mediaConnectPreflightMetadataAvailable)"))
        #expect(adapterSource.contains("media_connect_preflight_credentials_available=\\(mediaConnectPreflightCredentialsAvailable)"))
        #expect(adapterSource.contains("media_connect_preflight_token_present=\\(mediaConnectPreflightTokenPresent)"))
        #expect(adapterSource.contains("media_connect_preflight_url_present=\\(mediaConnectPreflightURLPresent)"))
        #expect(adapterSource.contains("media_connect_preflight_expires_at_present=\\(mediaConnectPreflightExpiresAtPresent)"))
        #expect(adapterSource.contains("media_connect_guard_enabled=\\(mediaConnectGuardEnabled)"))
        #expect(adapterSource.contains("media_connect_execution_allowed=\\(mediaConnectExecutionAllowed)"))
        #expect(adapterSource.contains("media_connect_preflight_result=\\(mediaConnectPreflightResult)"))
        #expect(adapterSource.contains("media_connect_blocked_reason=\\(mediaConnectBlockedReason)"))
        #expect(adapterSource.contains("media_connect_engine_invoked=\\(mediaConnectEngineInvoked)"))
        #expect(adapterSource.contains("livekit_connect_audio_invoked=\\(liveKitConnectAudioInvoked)"))
        #expect(adapterSource.contains("microphone_permission_requested=false"))
        #expect(adapterSource.contains("camera_permission_requested=false"))
        #expect(adapterSource.contains("if summary.realInvitePayloadMappingObserved"))
        #expect(adapterSource.contains("foregroundCallStateHandoffRequested = true"))
        #expect(adapterSource.contains("foregroundCallStateHandoffObserved = true"))
        #expect(adapterSource.contains("foregroundCallState = \"real_invite_pending_media\""))
        #expect(adapterSource.contains("foregroundCallStateSource = screenSource"))
        #expect(adapterSource.contains("foregroundCallStatePayloadRedacted = true"))
        #expect(adapterSource.contains("foregroundCallStateHasStableRedactedCorrelation = true"))
        #expect(adapterSource.contains("let pendingMetadataReferencePresent = (directCallPayload?[\"pending_metadata_reference\"] as? String)?.isEmpty == false"))
        #expect(adapterSource.contains("pendingMetadataReferencePresent: pendingMetadataReferencePresent"))
        #expect(adapterSource.contains("pendingMetadataReferenceRedacted: true"))
        #expect(adapterSource.contains("pendingMetadataFetchRequired: pendingMetadataReferencePresent"))
        #expect(adapterSource.contains("pendingMetadataFetchRequested: false"))
        #expect(adapterSource.contains("baseSummary.recordPendingMetadataReferenceRepairProof(referencePresent: pendingMetadataReferencePresent)"))
        #expect(adapterSource.contains("summary.recordPendingMetadataFetchRequested()"))
        #expect(adapterSource.contains("Task { await fetchAuthenticatedPendingMetadata(reference: pendingMetadataReferenceToFetch) }"))
        #expect(adapterSource.contains("private static func fetchAuthenticatedPendingMetadata(reference: String) async"))
        #expect(adapterSource.contains("request.setValue(\"B\" + \"earer \" + accessToken, forHTTPHeaderField: \"Authorization\")"))
        #expect(adapterSource.contains("let diagnostics = pendingMetadataFetchFailureDiagnostics(response: response, data: data)"))
        #expect(adapterSource.contains("httpStatusBucket: diagnostics.httpStatusBucket"))
        #expect(adapterSource.contains("errcode: diagnostics.errcode"))
        #expect(adapterSource.contains("failureReason: diagnostics.failureReason"))
        #expect(adapterSource.contains("private static func pendingMetadataFetchErrcode(data: Data) -> String"))
        #expect(adapterSource.contains("errcode.hasPrefix(\"M_\")"))
        #expect(adapterSource.contains("private static func pendingMetadataFetchHTTPStatusBucket(_ statusCode: Int) -> String"))
        #expect(adapterSource.contains("private static func pendingMetadataFetchFailureReason(statusCode: Int, errcode: String) -> String"))
        #expect(adapterSource.contains("return \"auth_rejected\""))
        #expect(adapterSource.contains("return \"forbidden\""))
        #expect(adapterSource.contains("return \"not_found\""))
        #expect(adapterSource.contains("private static func directCallSessionFromPendingMetadata(data: Data) -> DirectCallSession?"))
        #expect(adapterSource.contains("summary.recordAuthenticatedPendingMetadataFetch(session: session)"))
        #expect(adapterSource.contains("Task { @MainActor in"))
        #expect(adapterSource.contains("await requestControlledMediaCredentialsForControlledRuntime(session: session, source: \"authenticated_pending_metadata_fetch\")"))
        #expect(adapterSource.contains("private static func requestControlledMediaCredentialsForControlledRuntime(session: DirectCallSession, source: String) async"))
        #expect(adapterSource.contains("let tokenClient = ProductionDirectCallLiveKitTokenClient(configuration: .init(tokenEndpointURL: tokenEndpointURL),"))
        #expect(adapterSource.contains("httpTransport: URLSessionDirectCallHTTPTransport()"))
        #expect(adapterSource.contains("accessTokenProvider: accessTokenProvider"))
        #expect(adapterSource.contains("let tokenProvider = DirectCallLiveKitTokenProvider(tokenClient: tokenClient)"))
        #expect(adapterSource.contains("let result = await tokenProvider.connectionInfo(for: session)"))
        #expect(adapterSource.contains("recordControlledMediaCredentialsRequest(succeeded: succeeded"))
        #expect(adapterSource.contains("diagnostics: tokenProvider.diagnosticSnapshot"))
        #expect(adapterSource.contains("private static func controlledMediaCredentialsTokenEndpointURL() -> URL?"))
        #expect(adapterSource.contains("private static let controlledMediaCredentialsTokenEndpointPath = \"/_matrix/client/unstable/kz.salemx.direct_call/foreground-signaling/livekit/token\""))
        #expect(adapterSource.contains("components.path = controlledMediaCredentialsTokenEndpointPath"))
        #expect(adapterSource.contains("fileprivate static func matrixAccessTokenProviderForPushKitUploadSmoke() -> DirectCallMatrixAccessTokenProviding?"))
        #expect(adapterSource.contains("pendingMetadataFetchResult = \"success_redacted\""))
        #expect(adapterSource.contains("pendingMetadataFetchHTTPStatusBucket = \"2xx\""))
        #expect(adapterSource.contains("pendingMetadataFetchErrcode = \"none\""))
        #expect(adapterSource.contains("pendingMetadataFetchFailureReason = \"none\""))
        #expect(adapterSource.contains("foregroundPendingCallMetadataSource = \"authenticated_pending_metadata_fetch\""))
        #expect(adapterSource.contains("mediaCredentialsResult = \"blocked_redacted\""))
        #expect(adapterSource.contains("mediaCredentialsRequested = false"))
        #expect(adapterSource.contains("blockedReason = receiverPostAnswerFinalClassification"))
        #expect(adapterSource.contains("if !recordForegroundPendingCallMetadataHandoffIfAvailable(&summary)"))
        #expect(adapterSource.contains("summary.recordMetadataCredentialsBoundaryMissingAfterAnswer(physical6RuntimeEnablementHook: physical6RuntimeEnablementURLHookSnapshot)"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataHandoffRequested = true"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataHandoffObserved = false"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataSource = \"synthetic_voip_receipt\""))
        #expect(adapterSource.contains("mediaCredentialsRequestMetadataAvailable = false"))
        #expect(adapterSource.contains("mediaCredentialsRequestMetadataRedacted = true"))
        #expect(adapterSource.contains("mediaCredentialsRequestMetadataSource = \"none\""))
        #expect(adapterSource.contains("mediaCredentialsBoundaryReached = true"))
        #expect(adapterSource.contains("mediaCredentialsRequestPlanned = false"))
        #expect(adapterSource.contains("mediaCredentialsRequested = false"))
        #expect(adapterSource.contains("mediaCredentialsRequestAuthorized = false"))
        #expect(adapterSource.contains("mediaCredentialsResult = \"blocked_redacted\""))
        #expect(adapterSource.contains("mediaCredentialsTokenReceived = false"))
        #expect(adapterSource.contains("mediaCredentialsTokenRedacted = true"))
        #expect(adapterSource.contains("mediaCredentialsURLReceived = false"))
        #expect(adapterSource.contains("mediaCredentialsURLRedacted = true"))
        #expect(adapterSource.contains("mediaCredentialsExpiresAtPresent = false"))
        #expect(adapterSource.contains("mediaCredentialsPayloadRedacted = true"))
        #expect(adapterSource.contains("mediaCredentialsLocalPersistenceRequested = false"))
        #expect(adapterSource.contains("mediaCredentialsCleanupRequested = false"))
        #expect(adapterSource.contains("mediaCredentialsCleanupResult = \"not_requested\""))
        #expect(adapterSource.contains("mediaCredentialsPostCleanupTokenPresent = false"))
        #expect(adapterSource.contains("mediaCredentialsPostCleanupURLPresent = false"))
        #expect(adapterSource.contains("mediaCredentialsPostCleanupExpiresAtPresent = false"))
        #expect(adapterSource.contains("mediaCredentialsPostCleanupPayloadPresent = false"))
        #expect(adapterSource.contains("mediaCredentialsReuseAttempted = false"))
        #expect(adapterSource.contains("mediaCredentialsReuseAllowed = false"))
        #expect(adapterSource.contains("mediaCredentialsExpiryReferencePresent = false"))
        #expect(adapterSource.contains("mediaCredentialsExpiryCheckRequested = false"))
        #expect(adapterSource.contains("mediaCredentialsExpiryCheckResult = \"not_requested\""))
        #expect(adapterSource.contains("blockedReason = \"media_credentials_request_boundary_not_ready\""))
        #expect(adapterSource.contains("summary.recordControlledMediaCredentialsRequest(succeeded: succeeded"))
        #expect(adapterSource.contains("expiresAtPresent: expiresAtPresent"))
        #expect(adapterSource.contains("mediaCredentialsRequested = true"))
        #expect(adapterSource.contains("mediaCredentialsRequestAuthorized = mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaCredentialsResult = succeeded && mediaCredentialsRequestMetadataAvailable ? \"success_redacted\" : \"blocked_redacted\""))
        #expect(adapterSource.contains("mediaCredentialsTokenReceived = succeeded && mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaCredentialsURLReceived = succeeded && mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaCredentialsExpiresAtPresent = succeeded && mediaCredentialsRequestMetadataAvailable && expiresAtPresent"))
        #expect(adapterSource.contains("let cleanupCleared = succeeded && mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaCredentialsCleanupRequested = cleanupCleared"))
        #expect(adapterSource.contains("mediaCredentialsCleanupResult = mediaCredentialsCleanupRequested ? \"cleared\" : \"not_requested\""))
        #expect(adapterSource.contains("mediaCredentialsPostCleanupTokenPresent = false"))
        #expect(adapterSource.contains("mediaCredentialsPostCleanupURLPresent = false"))
        #expect(adapterSource.contains("mediaCredentialsPostCleanupExpiresAtPresent = false"))
        #expect(adapterSource.contains("mediaCredentialsPostCleanupPayloadPresent = false"))
        #expect(adapterSource.contains("mediaCredentialsReuseAttempted = false"))
        #expect(adapterSource.contains("mediaCredentialsReuseAllowed = false"))
        #expect(adapterSource.contains("mediaCredentialsExpiryReferencePresent = cleanupCleared && expiresAtPresent"))
        #expect(adapterSource.contains("mediaCredentialsExpiryCheckRequested = cleanupCleared && expiresAtPresent"))
        #expect(adapterSource.contains("mediaCredentialsExpiryCheckResult = mediaCredentialsExpiryCheckRequested ? \"expired_or_not_reusable_redacted\" : \"not_requested\""))
        #expect(adapterSource.contains("mediaCredentialsTokenHTTPStatusBucket = Self.httpStatusBucket(diagnostics.tokenStatus)"))
        #expect(adapterSource.contains("mediaCredentialsTokenReason = diagnostics.tokenReason.rawValue"))
        #expect(adapterSource.contains("mediaCredentialsEligibilityAllowed = diagnostics.tokenEligibilityAllowed"))
        #expect(adapterSource.contains("private struct SalemXControlledMediaConnectSwitch"))
        #expect(adapterSource.contains("private struct SalemXControlledMediaConnectActivationConfiguration"))
        #expect(adapterSource.contains("private struct SalemXControlledMediaConnectEnablementConfiguration"))
        #expect(adapterSource.contains("private struct SalemXControlledAudioConnectExecutionGate"))
        #expect(adapterSource.contains("static let disabledSwitchNoConnectReason = \"disabled_switch_no_connect\""))
        #expect(adapterSource.contains("static let disabled = SalemXControlledMediaConnectSwitch(isEnabled: false, operatorApproved: false)"))
        #expect(adapterSource.contains("static let defaultDisabled = SalemXControlledMediaConnectActivationConfiguration(controlledConnectSwitch: .disabled"))
        #expect(adapterSource.contains("activationScope: \"planned_audio_only_redacted\""))
        #expect(adapterSource.contains("videoAllowed: false"))
        #expect(adapterSource.contains("matrixEventsAllowed: false"))
        #expect(adapterSource.contains("rawCredentialsLogged: false"))
        #expect(adapterSource.contains("static let rollbackDisabled = defaultDisabled"))
        #expect(adapterSource.contains("let wiringPresent = true"))
        #expect(adapterSource.contains("let debugOnly = true"))
        #expect(adapterSource.contains("let isDefaultDisabled = true"))
        #expect(adapterSource.contains("let requiresOperatorApproval = true"))
        #expect(adapterSource.contains("let rollbackAvailable = true"))
        #expect(adapterSource.contains("static let enablementDisabledNoConnectReason = \"enablement_disabled_no_connect\""))
        #expect(adapterSource.contains("static let defaultDisabled = SalemXControlledMediaConnectEnablementConfiguration(oneShotEnablementEnabled: false"))
        #expect(adapterSource.contains("freshCredentialsPresent: false"))
        #expect(adapterSource.contains("audioOnlyScope: true"))
        #expect(adapterSource.contains("futureConnectPhasePermitted: false"))
        #expect(adapterSource.contains("let isDefaultOff = true"))
        #expect(adapterSource.contains("let operatorApprovalRequired = true"))
        #expect(adapterSource.contains("let isOneShot = true"))
        #expect(adapterSource.contains("let freshCredentialsRequired = true"))
        #expect(adapterSource.contains("var controlledConnectActivationWiringPresent = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.wiringPresent"))
        #expect(adapterSource.contains("var controlledConnectActivationDebugOnly = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.debugOnly"))
        #expect(adapterSource.contains("var controlledConnectActivationDefaultDisabled = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.isDefaultDisabled"))
        #expect(adapterSource.contains("var controlledConnectActivationRequiresOperatorApproval = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.requiresOperatorApproval"))
        #expect(adapterSource.contains("var controlledConnectActivationRollbackAvailable = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.rollbackAvailable"))
        #expect(adapterSource.contains("var controlledConnectActivationScope = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.activationScope"))
        #expect(adapterSource.contains("var controlledConnectVideoAllowed = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.videoAllowed"))
        #expect(adapterSource.contains("var controlledConnectMatrixEventsAllowed = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.matrixEventsAllowed"))
        #expect(adapterSource.contains("var controlledConnectRawCredentialsLogged = SalemXControlledMediaConnectActivationConfiguration.defaultDisabled.rawCredentialsLogged"))
        #expect(adapterSource.contains("var controlledConnectSwitchPresent = true"))
        #expect(adapterSource.contains("var controlledConnectSwitchDebugOnly = true"))
        #expect(adapterSource.contains("var controlledConnectSwitchEnabled = SalemXControlledMediaConnectSwitch.disabled.isEnabled"))
        #expect(adapterSource.contains("var controlledConnectOperatorApproved = SalemXControlledMediaConnectSwitch.disabled.operatorApproved"))
        #expect(adapterSource.contains("var controlledConnectExecutionAllowed = SalemXControlledMediaConnectSwitch.disabled.executionAllowed"))
        #expect(adapterSource.contains("var controlledConnectBlockedReason = SalemXControlledMediaConnectSwitch.disabled.blockedReason"))
        #expect(adapterSource.contains("var controlledConnectBlockedBeforeEngine = true"))
        #expect(adapterSource.contains("var controlledConnectBlockedBeforeLiveKitJoin = true"))
        #expect(adapterSource.contains("var controlledConnectBlockedBeforePermissions = true"))
        #expect(adapterSource.contains("var controlledConnectBlockedBeforeMatrixEvents = true"))
        #expect(adapterSource.contains("var controlledConnectEnablementWiringPresent = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.wiringPresent"))
        #expect(adapterSource.contains("var controlledConnectEnablementDebugOnly = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.debugOnly"))
        #expect(adapterSource.contains("var controlledConnectEnablementDefaultOff = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.isDefaultOff"))
        #expect(adapterSource.contains("var controlledConnectEnablementOperatorApprovalRequired = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.operatorApprovalRequired"))
        #expect(adapterSource.contains("var controlledConnectEnablementOneShot = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.isOneShot"))
        #expect(adapterSource.contains("var controlledConnectEnablementFreshCredentialsRequired = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.freshCredentialsRequired"))
        #expect(adapterSource.contains("var controlledConnectEnablementAudioOnly = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.audioOnlyScope"))
        #expect(adapterSource.contains("var controlledConnectEnablementVideoAllowed = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.videoAllowed"))
        #expect(adapterSource.contains("var controlledConnectEnablementMatrixEventsAllowed = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.matrixEventsAllowed"))
        #expect(adapterSource.contains("var controlledConnectEnablementRawCredentialsLogged = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.rawCredentialsLogged"))
        #expect(adapterSource.contains("var controlledConnectEnablementRollbackAvailable = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.rollbackAvailable"))
        #expect(adapterSource.contains("var controlledConnectEnablementEnabled = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.oneShotEnablementEnabled"))
        #expect(adapterSource.contains("var controlledConnectEnablementOperatorApproved = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.operatorApproved"))
        #expect(adapterSource.contains("var controlledConnectEnablementFuturePhasePermitted = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.futureConnectPhasePermitted"))
        #expect(adapterSource.contains("var controlledConnectEnablementExecutionAllowed = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.executionAllowed"))
        #expect(adapterSource.contains("var controlledConnectEnablementBlockedReason = SalemXControlledMediaConnectEnablementConfiguration.defaultDisabled.blockedReason"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionGatePresent = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).gatePresent"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionDebugOnly = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).debugOnly"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionAudioOnly = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).audioOnly"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionVideoAllowed = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).videoAllowed"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionMatrixEventsAllowed = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).matrixEventsAllowed"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionRawCredentialsLogged = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).rawCredentialsLogged"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionRequiresEnablement = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).requiresEnablement"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionRequiresOperatorApproval = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).requiresOperatorApproval"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionRequiresFuturePhasePermission = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).requiresFuturePhasePermission"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionFuturePhasePermitted = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).futurePhasePermitted"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionAllowed = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).executionAllowed"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionBlockedReason = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedReason"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionBlockedBeforeEngine = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedBeforeEngine"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionBlockedBeforeLiveKitJoin = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedBeforeLiveKitJoin"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionBlockedBeforePermissions = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedBeforePermissions"))
        #expect(adapterSource.contains("var controlledAudioConnectExecutionBlockedBeforeMatrixEvents = SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false).blockedBeforeMatrixEvents"))
        #expect(adapterSource.contains("if cleanupCleared {"))
        #expect(adapterSource.contains("recordControlledMediaConnectPreflight(credentialsAvailable: true"))
        #expect(adapterSource.contains("mutating func recordControlledMediaConnectPreflight(credentialsAvailable: Bool"))
        #expect(adapterSource.contains("mediaConnectPreflightRequested = true"))
        #expect(adapterSource.contains("mediaConnectPreflightMetadataAvailable = mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaConnectPreflightCredentialsAvailable = credentialsAvailable && mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaConnectPreflightTokenPresent = tokenPresent && mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaConnectPreflightURLPresent = urlPresent && mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaConnectPreflightExpiresAtPresent = expiresAtPresent && mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaConnectGuardEnabled = true"))
        #expect(adapterSource.contains("physical6RuntimeEnablementHook: SalemXPhysical6RuntimeEnablementURLHook = .defaultDisabled"))
        #expect(adapterSource.contains("attemptControlledAudioConnectRuntimeIfAllowed(activationConfiguration: physical6RuntimeEnablementHook.activationConfiguration"))
        #expect(adapterSource.contains("enablementConfiguration: physical6RuntimeEnablementHook.enablementConfiguration"))
        #expect(adapterSource.contains("let receiverControlledRuntimeSessionValidated = (pendingMetadataFetchAuthorized && pendingMetadataFetchResult == \"success_redacted\") ||"))
        #expect(adapterSource.contains("(mediaCredentialsRequestMetadataAvailable && mediaCredentialsResult == \"success_redacted\")"))
        #expect(adapterSource.contains("receiverAppSessionValidated: receiverControlledRuntimeSessionValidated"))
        #expect(adapterSource.contains("oneShotNotConsumed: physical6RuntimeEnablementHook.oneShotNotConsumed"))
        #expect(adapterSource.contains("let executionGate = SalemXControlledAudioConnectExecutionGate(credentialsPresent: mediaConnectPreflightCredentialsAvailable"))
        #expect(adapterSource.contains("let activationPath = SalemXControlledAudioConnectActivationPath(receiverAppSessionValidated: receiverAppSessionValidated"))
        #expect(adapterSource.contains("recordControlledConnectActivationProof(activationConfiguration)"))
        #expect(adapterSource.contains("recordControlledConnectEnablementProof(enablementConfiguration)"))
        #expect(adapterSource.contains("recordControlledAudioConnectExecutionGate(executionGate)"))
        #expect(adapterSource.contains("if controlledConnectFirstAttemptAllowed"))
        #expect(adapterSource.contains("mediaConnectPreflightResult = \"ready_for_first_attempt_redacted\""))
        #expect(adapterSource.contains("mediaConnectPreflightResult = \"blocked_before_connect_redacted\""))
        #expect(adapterSource.contains("mediaConnectPreflightResult = \"blocked_redacted\""))
        #expect(adapterSource.contains("mediaConnectBlockedReason = mediaConnectPreflightCredentialsAvailable ? controlledConnectBlockedReasonForPreflight : \"media_connect_preflight_not_ready\""))
        #expect(adapterSource.contains("mediaConnectEngineInvoked = false"))
        #expect(adapterSource.contains("liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("mutating func rollbackControlledConnectActivationProof()"))
        #expect(adapterSource.contains("recordControlledConnectActivationProof(SalemXControlledMediaConnectActivationConfiguration.rollbackDisabled)"))
        #expect(adapterSource.contains("recordControlledConnectEnablementProof(SalemXControlledMediaConnectEnablementConfiguration.rollbackDisabled)"))
        #expect(adapterSource.contains("recordControlledAudioConnectExecutionGate(SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false))"))
        #expect(adapterSource.contains("mutating func recordControlledConnectActivationProof(_ activationConfiguration: SalemXControlledMediaConnectActivationConfiguration)"))
        #expect(adapterSource.contains("controlledConnectActivationWiringPresent = activationConfiguration.wiringPresent"))
        #expect(adapterSource.contains("controlledConnectActivationDebugOnly = activationConfiguration.debugOnly"))
        #expect(adapterSource.contains("controlledConnectActivationDefaultDisabled = activationConfiguration.isDefaultDisabled"))
        #expect(adapterSource.contains("controlledConnectActivationRequiresOperatorApproval = activationConfiguration.requiresOperatorApproval"))
        #expect(adapterSource.contains("controlledConnectActivationRollbackAvailable = activationConfiguration.rollbackAvailable"))
        #expect(adapterSource.contains("controlledConnectActivationScope = activationConfiguration.activationScope"))
        #expect(adapterSource.contains("controlledConnectVideoAllowed = activationConfiguration.videoAllowed"))
        #expect(adapterSource.contains("controlledConnectMatrixEventsAllowed = activationConfiguration.matrixEventsAllowed"))
        #expect(adapterSource.contains("controlledConnectRawCredentialsLogged = activationConfiguration.rawCredentialsLogged"))
        #expect(adapterSource.contains("recordControlledConnectSwitchProof(activationConfiguration.controlledConnectSwitch)"))
        #expect(adapterSource.contains("controlledConnectBlockedBeforeEngine = !controlledConnectExecutionAllowed"))
        #expect(adapterSource.contains("controlledConnectBlockedBeforeLiveKitJoin = !controlledConnectExecutionAllowed"))
        #expect(adapterSource.contains("controlledConnectBlockedBeforePermissions = !controlledConnectExecutionAllowed"))
        #expect(adapterSource.contains("controlledConnectBlockedBeforeMatrixEvents = !controlledConnectExecutionAllowed"))
        #expect(adapterSource.contains("mutating func recordControlledConnectEnablementProof(_ enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration)"))
        #expect(adapterSource.contains("controlledConnectEnablementWiringPresent = enablementConfiguration.wiringPresent"))
        #expect(adapterSource.contains("controlledConnectEnablementDebugOnly = enablementConfiguration.debugOnly"))
        #expect(adapterSource.contains("controlledConnectEnablementDefaultOff = enablementConfiguration.isDefaultOff"))
        #expect(adapterSource.contains("controlledConnectEnablementOperatorApprovalRequired = enablementConfiguration.operatorApprovalRequired"))
        #expect(adapterSource.contains("controlledConnectEnablementOneShot = enablementConfiguration.isOneShot"))
        #expect(adapterSource.contains("controlledConnectEnablementFreshCredentialsRequired = enablementConfiguration.freshCredentialsRequired"))
        #expect(adapterSource.contains("controlledConnectEnablementAudioOnly = enablementConfiguration.audioOnlyScope"))
        #expect(adapterSource.contains("controlledConnectEnablementVideoAllowed = enablementConfiguration.videoAllowed"))
        #expect(adapterSource.contains("controlledConnectEnablementMatrixEventsAllowed = enablementConfiguration.matrixEventsAllowed"))
        #expect(adapterSource.contains("controlledConnectEnablementRawCredentialsLogged = enablementConfiguration.rawCredentialsLogged"))
        #expect(adapterSource.contains("controlledConnectEnablementRollbackAvailable = enablementConfiguration.rollbackAvailable"))
        #expect(adapterSource.contains("controlledConnectEnablementEnabled = enablementConfiguration.oneShotEnablementEnabled"))
        #expect(adapterSource.contains("controlledConnectEnablementOperatorApproved = enablementConfiguration.operatorApproved"))
        #expect(adapterSource.contains("controlledConnectEnablementFuturePhasePermitted = enablementConfiguration.futureConnectPhasePermitted"))
        #expect(adapterSource.contains("controlledConnectEnablementExecutionAllowed = enablementConfiguration.executionAllowed"))
        #expect(adapterSource.contains("controlledConnectEnablementBlockedReason = enablementConfiguration.blockedReason"))
        #expect(adapterSource.contains("mutating func recordControlledAudioConnectExecutionGate(_ executionGate: SalemXControlledAudioConnectExecutionGate)"))
        #expect(adapterSource.contains("controlledAudioConnectExecutionGatePresent = executionGate.gatePresent"))
        #expect(adapterSource.contains("controlledAudioConnectExecutionAllowed = executionGate.executionAllowed"))
        #expect(adapterSource.contains("controlledAudioConnectExecutionBlockedReason = executionGate.blockedReason"))
        #expect(adapterSource.contains("private var controlledConnectBlockedReasonForPreflight: String"))
        #expect(adapterSource.contains("private static func httpStatusBucket(_ status: Int?) -> String"))
        #expect(adapterSource.contains("controlled_connect_enablement_wiring_present=\\(controlledConnectEnablementWiringPresent)"))
        #expect(adapterSource.contains("controlled_connect_enablement_debug_only=\\(controlledConnectEnablementDebugOnly)"))
        #expect(adapterSource.contains("controlled_connect_enablement_default_off=\\(controlledConnectEnablementDefaultOff)"))
        #expect(adapterSource.contains("controlled_connect_enablement_operator_approval_required=\\(controlledConnectEnablementOperatorApprovalRequired)"))
        #expect(adapterSource.contains("controlled_connect_enablement_one_shot=\\(controlledConnectEnablementOneShot)"))
        #expect(adapterSource.contains("controlled_connect_enablement_fresh_credentials_required=\\(controlledConnectEnablementFreshCredentialsRequired)"))
        #expect(adapterSource.contains("controlled_connect_enablement_audio_only=\\(controlledConnectEnablementAudioOnly)"))
        #expect(adapterSource.contains("controlled_connect_enablement_video_allowed=\\(controlledConnectEnablementVideoAllowed)"))
        #expect(adapterSource.contains("controlled_connect_enablement_matrix_events_allowed=\\(controlledConnectEnablementMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_connect_enablement_raw_credentials_logged=\\(controlledConnectEnablementRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_connect_enablement_rollback_available=\\(controlledConnectEnablementRollbackAvailable)"))
        #expect(adapterSource.contains("controlled_connect_enablement_enabled=\\(controlledConnectEnablementEnabled)"))
        #expect(adapterSource.contains("controlled_connect_enablement_operator_approved=\\(controlledConnectEnablementOperatorApproved)"))
        #expect(adapterSource.contains("controlled_connect_enablement_future_phase_permitted=\\(controlledConnectEnablementFuturePhasePermitted)"))
        #expect(adapterSource.contains("controlled_connect_enablement_execution_allowed=\\(controlledConnectEnablementExecutionAllowed)"))
        #expect(adapterSource.contains("controlled_connect_enablement_blocked_reason=\\(controlledConnectEnablementBlockedReason)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_gate_present=\\(controlledAudioConnectExecutionGatePresent)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_debug_only=\\(controlledAudioConnectExecutionDebugOnly)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_audio_only=\\(controlledAudioConnectExecutionAudioOnly)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_video_allowed=\\(controlledAudioConnectExecutionVideoAllowed)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_matrix_events_allowed=\\(controlledAudioConnectExecutionMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_raw_credentials_logged=\\(controlledAudioConnectExecutionRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_requires_enablement=\\(controlledAudioConnectExecutionRequiresEnablement)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_requires_operator_approval=\\(controlledAudioConnectExecutionRequiresOperatorApproval)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_requires_future_phase_permission=\\(controlledAudioConnectExecutionRequiresFuturePhasePermission)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_future_phase_permitted=\\(controlledAudioConnectExecutionFuturePhasePermitted)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_allowed=\\(controlledAudioConnectExecutionAllowed)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_reason=\\(controlledAudioConnectExecutionBlockedReason)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_before_engine=\\(controlledAudioConnectExecutionBlockedBeforeEngine)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_before_livekit_join=\\(controlledAudioConnectExecutionBlockedBeforeLiveKitJoin)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_before_permissions=\\(controlledAudioConnectExecutionBlockedBeforePermissions)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_before_matrix_events=\\(controlledAudioConnectExecutionBlockedBeforeMatrixEvents)"))
        #expect(adapterSource.contains("media_connect_requested=false"))
        #expect(adapterSource.contains("media_connect_attempted=false"))
        #expect(adapterSource.contains("livekit_join_requested=false"))
        #expect(adapterSource.contains("matrix_event_emit_requested=false"))
        #expect(adapterSource.contains("real_call_flow_started=false"))
        #expect(!adapterSource.contains("payload.description"))
        #expect(!adapterSource.contains("payload.dictionaryPayload.description"))
        #expect(!adapterSource.contains("room_id=\\("))
        #expect(!adapterSource.contains("call_handle=\\("))
    }

    @Test
    func metadataCredentialsBoundaryRepairTriggersAfterAnswerWithoutConsumingHook() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        let repairStart = try #require(adapterSource.range(of: "mutating func recordMetadataCredentialsBoundaryRepairProof")?.lowerBound)
        let legacyBoundaryStart = try #require(adapterSource.range(of: "mutating func recordControlledMediaCredentialsRequestBoundaryNotReady")?.lowerBound)
        let repairSource = String(adapterSource[repairStart..<legacyBoundaryStart])
        let deliveryStart = try #require(adapterSource.range(of: "static func recordCallKitAnswerActionDeliveryProof")?.lowerBound)
        let endDeliveryStart = try #require(adapterSource.range(of: "static func recordCallKitEndActionDeliveryProof")?.lowerBound)
        let deliverySource = String(adapterSource[deliveryStart..<endDeliveryStart])
        let answerStart = try #require(adapterSource.range(of: "static func recordCallKitAnswerActionProof")?.lowerBound)
        let cleanupStart = try #require(adapterSource.range(of: "static func recordControlledCallKitCleanupProof")?.lowerBound)
        let answerSource = String(adapterSource[answerStart..<cleanupStart])
        let fetchSuccessStart = try #require(adapterSource.range(of: "private static func recordAuthenticatedPendingMetadataFetchSuccess")?.lowerBound)
        let fetchBlockedStart = try #require(adapterSource.range(of: "private static func recordAuthenticatedPendingMetadataFetchBlocked(reason: String")?.lowerBound)
        let fetchSuccessSource = String(adapterSource[fetchSuccessStart..<fetchBlockedStart])
        let credentialsStart = try #require(adapterSource.range(of: "static func recordControlledMediaCredentialsRequest(succeeded: Bool")?.lowerBound)
        let debugEnd = try #require(adapterSource.range(of: "#endif", options: .backwards)?.lowerBound)
        let credentialsSource = String(adapterSource[credentialsStart..<debugEnd])

        #expect(adapterSource.contains("metadata_credentials_boundary_repair_present=\\(metadataCredentialsBoundaryRepairPresent)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_debug_only=\\(metadataCredentialsBoundaryRepairDebugOnly)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_requires_answer=\\(metadataCredentialsBoundaryRepairRequiresAnswer)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_blocks_without_answer=\\(metadataCredentialsBoundaryRepairBlocksWithoutAnswer)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_triggers_metadata_after_answer=\\(metadataCredentialsBoundaryRepairTriggersMetadataAfterAnswer)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_triggers_credentials_after_metadata=\\(metadataCredentialsBoundaryRepairTriggersCredentialsAfterMetadata)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_blocks_connect_until_credentials=\\(metadataCredentialsBoundaryRepairBlocksConnectUntilCredentials)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_does_not_consume_hook_before_credentials=\\(metadataCredentialsBoundaryRepairDoesNotConsumeHookBeforeCredentials)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_allows_hook_consumption_after_credentials=\\(metadataCredentialsBoundaryRepairAllowsHookConsumptionAfterCredentials)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_no_direct_connect_bypass=\\(metadataCredentialsBoundaryRepairNoDirectConnectBypass)"))
        #expect(adapterSource.contains("metadata_credentials_boundary_repair_raw_credentials_logged=\\(metadataCredentialsBoundaryRepairRawCredentialsLogged)"))

        #expect(repairSource.contains("metadataCredentialsBoundaryRepairPresent = true"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairDebugOnly = true"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairRequiresAnswer = true"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairBlocksWithoutAnswer = true"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairTriggersMetadataAfterAnswer = true"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairTriggersCredentialsAfterMetadata = true"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairBlocksConnectUntilCredentials = true"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairDoesNotConsumeHookBeforeCredentials = true"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairAllowsHookConsumptionAfterCredentials = allowsHookConsumptionAfterCredentials"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairNoDirectConnectBypass = true"))
        #expect(repairSource.contains("metadataCredentialsBoundaryRepairRawCredentialsLogged = false"))
        #expect(repairSource.contains("recordAnswerTriggeredPendingMetadataBoundary(source: String)"))
        #expect(repairSource.contains("pendingMetadataFetchRequired = true"))
        #expect(repairSource.contains("foregroundPendingCallMetadataHandoffRequested = true"))
        #expect(repairSource.contains("foregroundPendingCallMetadataHandoffObserved = true"))
        #expect(repairSource.contains("mediaCredentialsRequested = false"))
        #expect(repairSource.contains("mediaCredentialsRequestAuthorized = false"))
        #expect(repairSource.contains("mediaCredentialsResult = \"blocked_redacted\""))
        #expect(repairSource.contains("recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)"))

        #expect(deliverySource.contains("recordFirstCallKitAction(\"answer\", in: &summary)"))
        #expect(!deliverySource.contains("recordPendingMetadataFetchRequested()"))
        #expect(!deliverySource.contains("recordControlledMediaCredentialsRequest(succeeded:"))
        #expect(!deliverySource.contains("recordControlledMediaConnectPreflight("))

        #expect(answerSource.contains("let physical6RuntimeEnablementURLHookSnapshot = physical6RuntimeEnablementURLHook"))
        #expect(answerSource.contains("summary.callKitAnswerActionReceived = true"))
        #expect(answerSource.contains("summary.callKitAnswerActionFulfilled = true"))
        #expect(answerSource.contains("if summary.realInvitePayloadMappingObserved"))
        #expect(answerSource.contains("if !recordForegroundPendingCallMetadataHandoffIfAvailable(&summary)"))
        #expect(answerSource.contains("summary.recordPendingMetadataFetchRequested()"))
        #expect(answerSource.contains("Task { await fetchAuthenticatedPendingMetadata(reference: pendingMetadataReferenceToFetch) }"))
        #expect(answerSource.contains("summary.recordMetadataCredentialsBoundaryMissingAfterAnswer(physical6RuntimeEnablementHook: physical6RuntimeEnablementURLHookSnapshot)"))

        #expect(adapterSource.contains("mutating func recordMetadataCredentialsBoundaryMissingAfterAnswer(physical6RuntimeEnablementHook: SalemXPhysical6RuntimeEnablementURLHook)"))
        #expect(adapterSource.contains("recordAnswerTriggeredPendingMetadataBoundary(source: \"callkit_answer_pending_metadata_missing_reference\")"))
        #expect(adapterSource.contains("pendingMetadataFetchResult = \"blocked_redacted\""))
        #expect(adapterSource.contains("pendingMetadataFetchFailureReason = \"missing_reference_after_answer\""))
        #expect(adapterSource.contains("recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementHook)"))
        #expect(adapterSource.contains("blockedReason = \"pending_metadata_missing_after_answer_no_credentials\""))
        #expect(adapterSource.contains("pendingMetadataFetchResult = \"success_redacted\""))
        #expect(adapterSource.contains("pendingMetadataFetchHTTPStatusBucket = \"2xx\""))
        #expect(adapterSource.contains("pendingMetadataFetchErrcode = \"none\""))
        #expect(adapterSource.contains("mediaCredentialsRequestPlanned = true"))
        #expect(fetchSuccessSource.contains("summary.recordAuthenticatedPendingMetadataFetch(session: session)"))
        #expect(fetchSuccessSource.contains("await requestControlledMediaCredentialsForControlledRuntime(session: session, source: \"authenticated_pending_metadata_fetch\")"))
        #expect(adapterSource.contains("recordMetadataCredentialsBoundaryRepairProof(allowsHookConsumptionAfterCredentials: succeeded && mediaCredentialsRequestMetadataAvailable)"))
        #expect(adapterSource.contains("recordPendingMetadataReferenceRepairProof(referencePresent: true, handedToAnswerPipeline: true)"))
        #expect(adapterSource.contains("recordPendingMetadataReferenceRepairProof(referencePresent: false)"))
        #expect(adapterSource.contains("baseSummary.recordPendingMetadataReferenceRepairProof(referencePresent: pendingMetadataReferencePresent)"))
        #expect(adapterSource.contains("mediaCredentialsRequested = true"))
        #expect(adapterSource.contains("mediaCredentialsRequestAuthorized = mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("mediaCredentialsResult = succeeded && mediaCredentialsRequestMetadataAvailable ? \"success_redacted\" : \"blocked_redacted\""))
        #expect(adapterSource.contains("let cleanupCleared = succeeded && mediaCredentialsRequestMetadataAvailable"))
        #expect(adapterSource.contains("if cleanupCleared"))
        #expect(adapterSource.contains("if summary.physical6RuntimeEnablementURLHookConsumed"))
        #expect(credentialsSource.contains("physical6RuntimeEnablementURLHook = physical6RuntimeEnablementURLHookSnapshot.consumedCopy()"))
        #expect(adapterSource.contains("recordAuthenticatedPendingMetadataFetchBlocked(_ reason: String"))
        #expect(adapterSource.contains("recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)"))
        #expect(adapterSource.contains("media_connect_requested=\\(mediaConnectRequested)"))
        #expect(adapterSource.contains("livekit_join_requested=\\(liveKitJoinRequested)"))
        #expect(adapterSource.contains("camera_permission_requested=\\(cameraPermissionRequested)"))
        #expect(adapterSource.contains("matrix_event_emit_requested=\\(matrixEventEmitRequested)"))
        #expect(adapterSource.contains("real_call_flow_started=\\(realCallFlowStarted)"))
        #expect(!adapterSource.contains("payload.description"))
        #expect(!adapterSource.contains("payload.dictionaryPayload.description"))
        #expect(!adapterSource.contains("room_id=\\("))
        #expect(!adapterSource.contains("call_id=\\("))
        #expect(!adapterSource.contains("peer_user_id=\\("))
        #expect(!adapterSource.contains("user_id=\\("))
        #expect(!adapterSource.contains("device_id=\\("))
    }

    @Test
    func receiverPostAnswerMediaCredentialsContinuationRepairClassifiesEachRuntimeGate() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let classificationStart = try #require(adapterSource.range(of: "var receiverPostAnswerFinalClassification: String")?.lowerBound)
        let callKitClassificationStart = try #require(adapterSource.range(of: "var receiverCallKitAnswerAvailabilityFinalClassification: String")?.lowerBound)
        let classificationSource = String(adapterSource[classificationStart..<callKitClassificationStart])

        #expect(adapterSource.contains("receiver_post_answer_media_credentials_continuation_repair_present=\\(receiverPostAnswerMediaCredentialsContinuationRepairPresent)"))
        #expect(adapterSource.contains("receiver_post_answer_media_credentials_continuation_repair_debug_only=\\(receiverPostAnswerMediaCredentialsContinuationRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_post_answer_media_credentials_continuation_repair_raw_identifiers_logged=\\(receiverPostAnswerMediaCredentialsContinuationRepairRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_post_answer_continuation_started=\\(receiverPostAnswerContinuationStarted)"))
        #expect(adapterSource.contains("receiver_post_answer_pending_metadata_reference_present=\\(receiverPostAnswerPendingMetadataReferencePresent)"))
        #expect(adapterSource.contains("receiver_post_answer_pending_metadata_fetch_requested=\\(receiverPostAnswerPendingMetadataFetchRequested)"))
        #expect(adapterSource.contains("receiver_post_answer_pending_metadata_fetch_result=\\(receiverPostAnswerPendingMetadataFetchResult)"))
        #expect(adapterSource.contains("receiver_post_answer_pending_metadata_authorized=\\(receiverPostAnswerPendingMetadataAuthorized)"))
        #expect(adapterSource.contains("receiver_post_answer_media_credentials_requested=\\(receiverPostAnswerMediaCredentialsRequested)"))
        #expect(adapterSource.contains("receiver_post_answer_media_credentials_result=\\(receiverPostAnswerMediaCredentialsResult)"))
        #expect(adapterSource.contains("receiver_post_answer_media_credentials_expires_present=\\(receiverPostAnswerMediaCredentialsExpiresPresent)"))
        #expect(adapterSource.contains("receiver_post_answer_controlled_connect_requested=\\(receiverPostAnswerControlledConnectRequested)"))
        #expect(adapterSource.contains("receiver_post_answer_controlled_connect_result=\\(receiverPostAnswerControlledConnectResult)"))
        #expect(adapterSource.contains("receiver_post_answer_livekit_join_requested=\\(receiverPostAnswerLiveKitJoinRequested)"))
        #expect(adapterSource.contains("receiver_post_answer_livekit_join_result=\\(receiverPostAnswerLiveKitJoinResult)"))
        #expect(adapterSource.contains("receiver_post_answer_final_classification=\\(receiverPostAnswerFinalClassification)"))

        #expect(adapterSource.contains("callKitAnswerActionReceived && foregroundCallState == \"real_invite_pending_media\""))
        #expect(classificationSource.contains("receiver_post_answer_continuation_started_redacted"))
        #expect(classificationSource.contains("receiver_post_answer_pending_metadata_reference_missing_redacted"))
        #expect(classificationSource.contains("receiver_post_answer_pending_metadata_fetch_failed_redacted"))
        #expect(classificationSource.contains("receiver_post_answer_media_credentials_deferred_redacted"))
        #expect(classificationSource.contains("receiver_post_answer_media_credentials_failed_redacted"))
        #expect(classificationSource.contains("receiver_post_answer_controlled_connect_not_requested_redacted"))
        #expect(classificationSource.contains("receiver_post_answer_controlled_connect_failed_redacted"))
        #expect(classificationSource.contains("receiver_post_answer_livekit_join_success_redacted"))
        #expect(classificationSource.contains("receiver_post_answer_livekit_join_not_requested_redacted"))
        #expect(adapterSource.contains("blockedReason = receiverPostAnswerFinalClassification"))
        #expect(adapterSource.contains("Task { @MainActor in"))
        #expect(adapterSource.contains("await requestControlledMediaCredentialsForControlledRuntime(session: session, source: \"authenticated_pending_metadata_fetch\")"))
        #expect(adapterSource.contains("startReceiverControlledRuntimeConnectLeaseIfAllowed(session: session, connectionInfo: connectionInfo)"))
        #expect(adapterSource.contains("let physical6RuntimeEnablementURLHookSnapshot = physical6RuntimeEnablementURLHook"))
        #expect(adapterSource.contains("!summary.controlledConnectFirstAttemptAllowed"))
        #expect(adapterSource.contains("summary.mediaCredentialsResult == \"success_redacted\""))
        #expect(adapterSource.contains("summary.recordControlledMediaConnectPreflight(credentialsAvailable: true"))
        #expect(adapterSource.contains("physical6RuntimeEnablementHook: physical6RuntimeEnablementURLHookSnapshot"))
        #expect(adapterSource.contains("physical6RuntimeEnablementURLHook = physical6RuntimeEnablementURLHookSnapshot.consumedCopy()"))
        #expect(!classificationSource.contains("room_id=\\("))
        #expect(!classificationSource.contains("call_id=\\("))
        #expect(!classificationSource.contains("peer_user_id=\\("))
        #expect(!classificationSource.contains("device_id=\\("))
    }

    @Test
    func receiverCallKitSurfaceOperatorReadinessRepairRecordsMarkerAndClassifiesSurfaceState() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let classificationStart = try #require(adapterSource.range(of: "var receiverCallKitSurfaceOperatorReadinessFinalClassification: String")?.lowerBound)
        let classificationEnd = try #require(adapterSource.range(of: "var redactedLines: [String]", range: classificationStart..<adapterSource.endIndex)?.lowerBound)
        let classificationSource = String(adapterSource[classificationStart..<classificationEnd])

        #expect(adapterSource.contains("receiverCallKitOperatorReadyURLHookPath = \"/direct-call/receiver-callkit-operator-ready\""))
        #expect(adapterSource.contains("armReceiverCallKitOperatorReadyURLHook(components)"))
        #expect(adapterSource.contains("recordCallKitOperatorReadyToAnswer(expectedSurface)"))
        #expect(adapterSource.contains("summary.receiverCallKitOperatorReadyMarkerRequestedBeforeAPNs = true"))
        #expect(adapterSource.contains("baseSummary.receiverCallKitOperatorReadyMarkerRequestedBeforeAPNs = baseSummary.operatorReadyToAnswer"))
        #expect(adapterSource.contains("receiver_callkit_surface_operator_readiness_repair_present=\\(receiverCallKitSurfaceOperatorReadinessRepairPresent)"))
        #expect(adapterSource.contains("receiver_callkit_surface_operator_readiness_repair_debug_only=\\(receiverCallKitSurfaceOperatorReadinessRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_callkit_surface_operator_readiness_repair_raw_identifiers_logged=\\(receiverCallKitSurfaceOperatorReadinessRepairRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_callkit_operator_ready_marker_requested_before_apns=\\(receiverCallKitOperatorReadyMarkerRequestedBeforeAPNs)"))
        #expect(adapterSource.contains("receiver_callkit_operator_ready_marker_recorded_before_report=\\(voIPOperatorMarkerSetBeforeReport)"))
        #expect(adapterSource.contains("receiver_callkit_expected_surface_bucket=\\(operatorExpectedSurface)"))
        #expect(adapterSource.contains("receiver_callkit_receiver_app_state_before_apns_bucket=\\(receiverAppLifecycleStateBeforeAPNsBucket)"))
        #expect(adapterSource.contains("receiver_callkit_receiver_app_state_at_report_bucket=\\(Self.safeAppStateBucket(appStateAtReportCompletion))"))
        #expect(adapterSource.contains("receiver_callkit_answer_window_extended_for_ui_surface=\\(receiverCallKitAnswerWindowExtendedForUISurface)"))
        #expect(adapterSource.contains("receiver_callkit_surface_operator_readiness_final_classification=\\(receiverCallKitSurfaceOperatorReadinessFinalClassification)"))
        #expect(adapterSource.contains("completedSummary.receiverCallKitAnswerWindowExtendedForUISurface = answerableWindowRequested"))
        #expect(adapterSource.contains("summary.receiverCallKitAnswerWindowExtendedForUISurface = true"))

        #expect(classificationSource.contains("receiver_callkit_surface_ready_for_answer_redacted"))
        #expect(classificationSource.contains("receiver_callkit_operator_marker_missing_redacted"))
        #expect(classificationSource.contains("receiver_callkit_report_submitted_but_ui_missing_redacted"))
        #expect(classificationSource.contains("receiver_callkit_foreground_state_requires_in_app_answer_redacted"))
        #expect(classificationSource.contains("receiver_callkit_answer_window_timeout_redacted"))
        #expect(classificationSource.contains("receiver_callkit_action_received_without_ui_marker_redacted"))
        #expect(classificationSource.contains("receiver_callkit_report_failed_before_answer_redacted"))
        #expect(!classificationSource.contains("room_id=\\("))
        #expect(!classificationSource.contains("call_id=\\("))
        #expect(!classificationSource.contains("peer_user_id=\\("))
        #expect(!classificationSource.contains("device_id=\\("))
    }

    @Test
    func receiverForegroundInAppAnswerContinuationRepairIsDebugOnlyAndReusesPostAnswerPipeline() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let hookStart = try #require(adapterSource.range(of: "private static func startReceiverForegroundInAppAnswerURLHook()")?.lowerBound)
        let hookEnd = try #require(adapterSource.range(of: "private static func armSimulatorRemotePeerContextHandoffURLHook()", range: hookStart..<adapterSource.endIndex)?.lowerBound)
        let hookSource = String(adapterSource[hookStart..<hookEnd])
        let evaluationStart = try #require(adapterSource.range(of: "mutating func recordReceiverForegroundInAppAnswerHookRequest")?.lowerBound)
        let evaluationEnd = try #require(adapterSource.range(of: "private static func redactedProofFields", range: evaluationStart..<adapterSource.endIndex)?.lowerBound)
        let evaluationSource = String(adapterSource[evaluationStart..<evaluationEnd])

        #expect(adapterSource.contains("receiverForegroundInAppAnswerURLHookPath = \"/direct-call/receiver-foreground-in-app-answer\""))
        #expect(adapterSource.contains("startReceiverForegroundInAppAnswerURLHook()"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_continuation_repair_present=\\(receiverForegroundInAppAnswerContinuationRepairPresent)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_continuation_repair_debug_only=\\(receiverForegroundInAppAnswerContinuationRepairDebugOnly)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_continuation_repair_raw_identifiers_logged=\\(receiverForegroundInAppAnswerContinuationRepairRawIdentifiersLogged)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_hook_present=\\(receiverForegroundInAppAnswerHookPresent)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_hook_default_disabled=\\(receiverForegroundInAppAnswerHookDefaultDisabled)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_hook_requested=\\(receiverForegroundInAppAnswerHookRequested)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_hook_allowed=\\(receiverForegroundInAppAnswerHookAllowed)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_hook_blocked_reason=\\(receiverForegroundInAppAnswerHookBlockedReason)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_recorded=\\(receiverForegroundInAppAnswerRecorded)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_preserved_pending_metadata=\\(receiverForegroundInAppAnswerPreservedPendingMetadata)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_triggered_post_answer_continuation=\\(receiverForegroundInAppAnswerTriggeredPostAnswerContinuation)"))
        #expect(adapterSource.contains("receiver_foreground_in_app_answer_final_classification=\\(receiverForegroundInAppAnswerFinalClassification)"))

        #expect(hookSource.contains("pendingAuthenticatedMetadataReference?.isEmpty == false"))
        #expect(hookSource.contains("guard shouldStartPostAnswerContinuation else"))
        #expect(hookSource.contains("recordCallKitAnswerActionProof(screenSource: \"foreground_in_app_answer_real_invite_controlled\")"))
        #expect(hookSource.contains("updateLatestVoIPPushReceiptSummary(summaryToWrite)"))
        #expect(!hookSource.contains("connectAudio("))
        #expect(!hookSource.contains("emit"))

        #expect(evaluationSource.contains("physicalVoIPPushReceived"))
        #expect(evaluationSource.contains("callbackInvoked"))
        #expect(evaluationSource.contains("realInvitePayloadMappingObserved"))
        #expect(evaluationSource.contains("callKitReportCompletionObserved"))
        #expect(evaluationSource.contains("callKitProviderRetainedForAnswer"))
        #expect(evaluationSource.contains("callKitDelegateRetainedForAnswer"))
        #expect(evaluationSource.contains("callKitActiveCallUUIDRetained"))
        #expect(evaluationSource.contains("receiver_callkit_foreground_state_requires_in_app_answer_redacted"))
        #expect(evaluationSource.contains("pendingMetadataReferencePresent"))
        #expect(evaluationSource.contains("callKitAnswerActionReceived"))
        #expect(evaluationSource.contains("receiver_foreground_in_app_answer_recorded_redacted"))
        #expect(evaluationSource.contains("receiver_foreground_in_app_answer_not_foreground_redacted"))
        #expect(evaluationSource.contains("receiver_foreground_in_app_answer_missing_report_redacted"))
        #expect(evaluationSource.contains("receiver_foreground_in_app_answer_missing_pending_metadata_redacted"))
        #expect(evaluationSource.contains("receiver_foreground_in_app_answer_blocked_by_gate_redacted"))
        #expect(evaluationSource.contains("receiver_foreground_in_app_answer_post_answer_continuation_started_redacted"))
        #expect(!evaluationSource.contains("room_id=\\("))
        #expect(!evaluationSource.contains("call_id=\\("))
        #expect(!evaluationSource.contains("peer_user_id=\\("))
        #expect(!evaluationSource.contains("device_id=\\("))
    }

    @Test
    func controlledConnectSwitchDefaultsDisabledAndBlocksBeforeSideEffects() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let switchStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)\nprivate struct SalemXControlledMediaConnectSwitch")?.lowerBound)
        let activationConfigurationStart = try #require(adapterSource.range(of: "private struct SalemXControlledMediaConnectActivationConfiguration")?.lowerBound)
        let proofSummaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let switchSource = String(adapterSource[switchStart..<activationConfigurationStart])

        #expect(switchStart < proofSummaryStart)
        #expect(activationConfigurationStart < proofSummaryStart)
        #expect(adapterSource.contains("static let disabled = SalemXControlledMediaConnectSwitch(isEnabled: false, operatorApproved: false)"))
        #expect(adapterSource.contains("var executionAllowed: Bool {\n        isEnabled && operatorApproved\n    }"))
        #expect(adapterSource.contains("executionAllowed ? \"none\" : Self.disabledSwitchNoConnectReason"))
        #expect(adapterSource.contains("controlled_connect_switch_present=\\(controlledConnectSwitchPresent)"))
        #expect(adapterSource.contains("controlled_connect_switch_debug_only=\\(controlledConnectSwitchDebugOnly)"))
        #expect(adapterSource.contains("controlled_connect_switch_enabled=\\(controlledConnectSwitchEnabled)"))
        #expect(adapterSource.contains("controlled_connect_operator_approved=\\(controlledConnectOperatorApproved)"))
        #expect(adapterSource.contains("controlled_connect_execution_allowed=\\(controlledConnectExecutionAllowed)"))
        #expect(adapterSource.contains("controlled_connect_blocked_reason=\\(controlledConnectBlockedReason)"))
        #expect(adapterSource.contains("controlled_connect_blocked_before_engine=\\(controlledConnectBlockedBeforeEngine)"))
        #expect(adapterSource.contains("controlled_connect_blocked_before_livekit_join=\\(controlledConnectBlockedBeforeLiveKitJoin)"))
        #expect(adapterSource.contains("controlled_connect_blocked_before_permissions=\\(controlledConnectBlockedBeforePermissions)"))
        #expect(adapterSource.contains("controlled_connect_blocked_before_matrix_events=\\(controlledConnectBlockedBeforeMatrixEvents)"))
        #expect(adapterSource.contains("mediaConnectExecutionAllowed = controlledConnectExecutionAllowed &&"))
        #expect(adapterSource.contains("mediaConnectBlockedReason = mediaConnectPreflightCredentialsAvailable ? controlledConnectBlockedReasonForPreflight : \"media_connect_preflight_not_ready\""))
        #expect(adapterSource.contains("mediaConnectEngineInvoked = false"))
        #expect(adapterSource.contains("liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("microphone_permission_requested=false"))
        #expect(adapterSource.contains("camera_permission_requested=false"))
        #expect(adapterSource.contains("matrix_event_emit_requested=false"))
        #expect(adapterSource.contains("real_call_flow_started=false"))
        #expect(adapterSource.contains("connectMediaIfReadyWhenControlledGatesOpen(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>"))
        #expect(adapterSource.contains("await directCallEngine.acceptCall(callID: callID)"))
        #expect(!switchSource.contains(".connectAudio("))
        #expect(adapterSource.contains("receiver_audio_permission_request_dispatch_path_available=\\(receiverAudioPermissionRequestDispatchPathAvailable)"))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("emitSignal(type:"))
    }

    @Test
    func controlledConnectEnablementDefaultsOffAndBlocksBeforeSideEffects() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let enablementConfigurationStart = try #require(adapterSource.range(of: "private struct SalemXControlledMediaConnectEnablementConfiguration")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let enablementConfigurationSource = String(adapterSource[enablementConfigurationStart..<summaryStart])

        #expect(debugGuardStart < enablementConfigurationStart)
        #expect(enablementConfigurationStart < summaryStart)
        #expect(enablementConfigurationSource.contains("static let enablementDisabledNoConnectReason = \"enablement_disabled_no_connect\""))
        #expect(enablementConfigurationSource.contains("static let defaultDisabled = SalemXControlledMediaConnectEnablementConfiguration(oneShotEnablementEnabled: false"))
        #expect(enablementConfigurationSource.contains("operatorApproved: false"))
        #expect(enablementConfigurationSource.contains("freshCredentialsPresent: false"))
        #expect(enablementConfigurationSource.contains("audioOnlyScope: true"))
        #expect(enablementConfigurationSource.contains("futureConnectPhasePermitted: false"))
        #expect(enablementConfigurationSource.contains("static let rollbackDisabled = defaultDisabled"))
        #expect(enablementConfigurationSource.contains("let wiringPresent = true"))
        #expect(enablementConfigurationSource.contains("let debugOnly = true"))
        #expect(enablementConfigurationSource.contains("let isDefaultOff = true"))
        #expect(enablementConfigurationSource.contains("let operatorApprovalRequired = true"))
        #expect(enablementConfigurationSource.contains("let isOneShot = true"))
        #expect(enablementConfigurationSource.contains("let freshCredentialsRequired = true"))
        #expect(enablementConfigurationSource.contains("let videoAllowed = false"))
        #expect(enablementConfigurationSource.contains("let matrixEventsAllowed = false"))
        #expect(enablementConfigurationSource.contains("let rawCredentialsLogged = false"))
        #expect(enablementConfigurationSource.contains("let rollbackAvailable = true"))
        #expect(enablementConfigurationSource.contains("var executionAllowed: Bool {\n        debugOnly && oneShotEnablementEnabled && operatorApproved && freshCredentialsPresent && audioOnlyScope && futureConnectPhasePermitted\n    }"))
        #expect(enablementConfigurationSource.contains("executionAllowed ? \"none\" : Self.enablementDisabledNoConnectReason"))
        #expect(adapterSource.contains("controlled_connect_enablement_wiring_present=\\(controlledConnectEnablementWiringPresent)"))
        #expect(adapterSource.contains("controlled_connect_enablement_debug_only=\\(controlledConnectEnablementDebugOnly)"))
        #expect(adapterSource.contains("controlled_connect_enablement_default_off=\\(controlledConnectEnablementDefaultOff)"))
        #expect(adapterSource.contains("controlled_connect_enablement_operator_approval_required=\\(controlledConnectEnablementOperatorApprovalRequired)"))
        #expect(adapterSource.contains("controlled_connect_enablement_one_shot=\\(controlledConnectEnablementOneShot)"))
        #expect(adapterSource.contains("controlled_connect_enablement_fresh_credentials_required=\\(controlledConnectEnablementFreshCredentialsRequired)"))
        #expect(adapterSource.contains("controlled_connect_enablement_audio_only=\\(controlledConnectEnablementAudioOnly)"))
        #expect(adapterSource.contains("controlled_connect_enablement_video_allowed=\\(controlledConnectEnablementVideoAllowed)"))
        #expect(adapterSource.contains("controlled_connect_enablement_matrix_events_allowed=\\(controlledConnectEnablementMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_connect_enablement_raw_credentials_logged=\\(controlledConnectEnablementRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_connect_enablement_rollback_available=\\(controlledConnectEnablementRollbackAvailable)"))
        #expect(adapterSource.contains("controlled_connect_enablement_enabled=\\(controlledConnectEnablementEnabled)"))
        #expect(adapterSource.contains("controlled_connect_enablement_operator_approved=\\(controlledConnectEnablementOperatorApproved)"))
        #expect(adapterSource.contains("controlled_connect_enablement_future_phase_permitted=\\(controlledConnectEnablementFuturePhasePermitted)"))
        #expect(adapterSource.contains("controlled_connect_enablement_execution_allowed=\\(controlledConnectEnablementExecutionAllowed)"))
        #expect(adapterSource.contains("controlled_connect_enablement_blocked_reason=\\(controlledConnectEnablementBlockedReason)"))
        #expect(adapterSource.contains("recordControlledConnectEnablementProof(enablementConfiguration)"))
        #expect(adapterSource.contains("recordControlledConnectEnablementProof(SalemXControlledMediaConnectEnablementConfiguration.rollbackDisabled)"))
        #expect(adapterSource.contains("mediaConnectExecutionAllowed = controlledConnectExecutionAllowed &&"))
        #expect(adapterSource.contains("mediaConnectEngineInvoked = false"))
        #expect(adapterSource.contains("liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("media_connect_requested=false"))
        #expect(adapterSource.contains("media_connect_attempted=false"))
        #expect(adapterSource.contains("livekit_join_requested=false"))
        #expect(adapterSource.contains("microphone_permission_requested=false"))
        #expect(adapterSource.contains("camera_permission_requested=false"))
        #expect(adapterSource.contains("matrix_event_emit_requested=false"))
        #expect(adapterSource.contains("real_call_flow_started=false"))
        #expect(adapterSource.contains("connectMediaIfReadyWhenControlledGatesOpen(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>"))
        #expect(adapterSource.contains("await directCallEngine.acceptCall(callID: callID)"))
        #expect(!enablementConfigurationSource.contains(".connectAudio("))
        #expect(adapterSource.contains("receiver_audio_permission_request_dispatch_path_available=\\(receiverAudioPermissionRequestDispatchPathAvailable)"))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("emitSignal(type:"))
    }

    @Test
    func controlledAudioConnectExecutionGateDefaultsBlockedBeforeSideEffects() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let executionGateStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectExecutionGate")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let executionGateSource = String(adapterSource[executionGateStart..<summaryStart])

        #expect(debugGuardStart < executionGateStart)
        #expect(executionGateStart < summaryStart)
        #expect(executionGateSource.contains("static let futurePhaseNotPermittedNoConnectReason = \"future_phase_not_permitted_no_connect\""))
        #expect(executionGateSource.contains("static func defaultBlocked(credentialsPresent: Bool) -> SalemXControlledAudioConnectExecutionGate"))
        #expect(executionGateSource.contains("activationConfiguration: .defaultDisabled"))
        #expect(executionGateSource.contains("enablementConfiguration: .defaultDisabled"))
        #expect(executionGateSource.contains("let gatePresent = true"))
        #expect(executionGateSource.contains("let debugOnly = true"))
        #expect(executionGateSource.contains("let requiresEnablement = true"))
        #expect(executionGateSource.contains("let requiresOperatorApproval = true"))
        #expect(executionGateSource.contains("let requiresFuturePhasePermission = true"))
        #expect(executionGateSource.contains("enablementConfiguration.audioOnlyScope"))
        #expect(executionGateSource.contains("activationConfiguration.videoAllowed || enablementConfiguration.videoAllowed"))
        #expect(executionGateSource.contains("activationConfiguration.matrixEventsAllowed || enablementConfiguration.matrixEventsAllowed"))
        #expect(executionGateSource.contains("activationConfiguration.rawCredentialsLogged || enablementConfiguration.rawCredentialsLogged"))
        #expect(executionGateSource.contains("enablementConfiguration.futureConnectPhasePermitted"))
        #expect(executionGateSource.contains("credentialsPresent"))
        #expect(executionGateSource.contains("activationConfiguration.wiringPresent"))
        #expect(executionGateSource.contains("enablementConfiguration.wiringPresent"))
        #expect(executionGateSource.contains("enablementConfiguration.oneShotEnablementEnabled"))
        #expect(executionGateSource.contains("activationConfiguration.controlledConnectSwitch.executionAllowed"))
        #expect(executionGateSource.contains("enablementConfiguration.operatorApproved"))
        #expect(executionGateSource.contains("enablementConfiguration.freshCredentialsPresent"))
        #expect(executionGateSource.contains("&& audioOnly"))
        #expect(executionGateSource.contains("&& !videoAllowed"))
        #expect(executionGateSource.contains("&& !matrixEventsAllowed"))
        #expect(executionGateSource.contains("&& !rawCredentialsLogged"))
        #expect(executionGateSource.contains("&& futurePhasePermitted"))
        #expect(executionGateSource.contains("if !futurePhasePermitted"))
        #expect(executionGateSource.contains("return Self.futurePhaseNotPermittedNoConnectReason"))
        #expect(executionGateSource.contains("return Self.credentialsMissingNoConnectReason"))
        #expect(executionGateSource.contains("return Self.activationWiringMissingNoConnectReason"))
        #expect(executionGateSource.contains("return Self.enablementWiringMissingNoConnectReason"))
        #expect(executionGateSource.contains("return Self.enablementDisabledNoConnectReason"))
        #expect(executionGateSource.contains("return Self.operatorApprovalMissingNoConnectReason"))
        #expect(executionGateSource.contains("return Self.freshCredentialsMissingNoConnectReason"))
        #expect(executionGateSource.contains("return Self.audioOnlyScopeMissingNoConnectReason"))
        #expect(executionGateSource.contains("return Self.videoEnabledNoConnectReason"))
        #expect(executionGateSource.contains("return Self.matrixEventsEnabledNoConnectReason"))
        #expect(executionGateSource.contains("return Self.rawCredentialsLoggedNoConnectReason"))
        #expect(executionGateSource.contains("var blockedBeforeEngine: Bool"))
        #expect(executionGateSource.contains("var blockedBeforeLiveKitJoin: Bool"))
        #expect(executionGateSource.contains("var blockedBeforePermissions: Bool"))
        #expect(executionGateSource.contains("var blockedBeforeMatrixEvents: Bool"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_gate_present=\\(controlledAudioConnectExecutionGatePresent)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_debug_only=\\(controlledAudioConnectExecutionDebugOnly)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_audio_only=\\(controlledAudioConnectExecutionAudioOnly)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_video_allowed=\\(controlledAudioConnectExecutionVideoAllowed)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_matrix_events_allowed=\\(controlledAudioConnectExecutionMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_raw_credentials_logged=\\(controlledAudioConnectExecutionRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_requires_enablement=\\(controlledAudioConnectExecutionRequiresEnablement)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_requires_operator_approval=\\(controlledAudioConnectExecutionRequiresOperatorApproval)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_requires_future_phase_permission=\\(controlledAudioConnectExecutionRequiresFuturePhasePermission)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_future_phase_permitted=\\(controlledAudioConnectExecutionFuturePhasePermitted)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_allowed=\\(controlledAudioConnectExecutionAllowed)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_reason=\\(controlledAudioConnectExecutionBlockedReason)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_before_engine=\\(controlledAudioConnectExecutionBlockedBeforeEngine)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_before_livekit_join=\\(controlledAudioConnectExecutionBlockedBeforeLiveKitJoin)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_before_permissions=\\(controlledAudioConnectExecutionBlockedBeforePermissions)"))
        #expect(adapterSource.contains("controlled_audio_connect_execution_blocked_before_matrix_events=\\(controlledAudioConnectExecutionBlockedBeforeMatrixEvents)"))
        #expect(adapterSource.contains("let executionGate = SalemXControlledAudioConnectExecutionGate(credentialsPresent: mediaConnectPreflightCredentialsAvailable"))
        #expect(adapterSource.contains("recordControlledAudioConnectExecutionGate(executionGate)"))
        #expect(adapterSource.contains("controlledAudioConnectExecutionAllowed &&"))
        #expect(adapterSource.contains("recordControlledAudioConnectExecutionGate(SalemXControlledAudioConnectExecutionGate.defaultBlocked(credentialsPresent: false))"))
        #expect(adapterSource.contains("mediaConnectEngineInvoked = false"))
        #expect(adapterSource.contains("liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("media_connect_requested=false"))
        #expect(adapterSource.contains("media_connect_attempted=false"))
        #expect(adapterSource.contains("livekit_join_requested=false"))
        #expect(adapterSource.contains("microphone_permission_requested=false"))
        #expect(adapterSource.contains("camera_permission_requested=false"))
        #expect(adapterSource.contains("matrix_event_emit_requested=false"))
        #expect(adapterSource.contains("real_call_flow_started=false"))
        #expect(adapterSource.contains("connectMediaIfReadyWhenControlledGatesOpen(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>"))
        #expect(adapterSource.contains("await directCallEngine.acceptCall(callID: callID)"))
        #expect(!executionGateSource.contains(".connectAudio("))
        #expect(adapterSource.contains("receiver_audio_permission_request_dispatch_path_available=\\(receiverAudioPermissionRequestDispatchPathAvailable)"))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("emitSignal(type:"))
    }

    @Test
    func controlledAudioConnectFirstAttemptProofFieldsDefaultNoConnect() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let firstAttemptStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectFirstAttempt")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let firstAttemptSource = String(adapterSource[firstAttemptStart..<summaryStart])

        #expect(firstAttemptSource.contains("static let defaultDisabledNoConnectReason = \"default_disabled_no_connect\""))
        #expect(firstAttemptSource.contains("requested: false"))
        #expect(firstAttemptSource.contains("allowed: false"))
        #expect(firstAttemptSource.contains("started: false"))
        #expect(firstAttemptSource.contains("completed: false"))
        #expect(firstAttemptSource.contains("repeated: false"))
        #expect(firstAttemptSource.contains("result: \"not_requested\""))
        #expect(firstAttemptSource.contains("errorBucket: \"none\""))
        #expect(firstAttemptSource.contains("audioOnly: true"))
        #expect(firstAttemptSource.contains("videoAllowed: false"))
        #expect(firstAttemptSource.contains("matrixEventsAllowed: false"))
        #expect(firstAttemptSource.contains("rawCredentialsLogged: false"))
        #expect(firstAttemptSource.contains("blockedReason: defaultDisabledNoConnectReason"))
        #expect(firstAttemptSource.contains("mediaConnectRequested: false"))
        #expect(firstAttemptSource.contains("mediaConnectAttempted: false"))
        #expect(firstAttemptSource.contains("liveKitJoinRequested: false"))
        #expect(firstAttemptSource.contains("liveKitConnectAudioInvoked: false"))
        #expect(firstAttemptSource.contains("microphonePermissionRequested: false"))
        #expect(firstAttemptSource.contains("cameraPermissionRequested: false"))
        #expect(firstAttemptSource.contains("matrixEventEmitRequested: false"))
        #expect(firstAttemptSource.contains("realCallFlowStarted: false"))

        #expect(adapterSource.contains("var controlledConnectFirstAttemptRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.requested"))
        #expect(adapterSource.contains("var controlledConnectFirstAttemptAllowed = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.allowed"))
        #expect(adapterSource.contains("var controlledConnectFirstAttemptCompleted = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.completed"))
        #expect(adapterSource.contains("var controlledConnectFirstAttemptRepeated = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.repeated"))
        #expect(adapterSource.contains("var mediaConnectRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.mediaConnectRequested"))
        #expect(adapterSource.contains("var liveKitJoinRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.liveKitJoinRequested"))
        #expect(adapterSource.contains("var cameraPermissionRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.cameraPermissionRequested"))
        #expect(adapterSource.contains("var matrixEventEmitRequested = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.matrixEventEmitRequested"))
        #expect(adapterSource.contains("var realCallFlowStarted = SalemXControlledAudioConnectFirstAttempt.defaultDisabled.realCallFlowStarted"))

        #expect(adapterSource.contains("controlled_connect_first_attempt_requested=\\(controlledConnectFirstAttemptRequested)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_allowed=\\(controlledConnectFirstAttemptAllowed)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_started=\\(controlledConnectFirstAttemptStarted)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_completed=\\(controlledConnectFirstAttemptCompleted)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_repeated=\\(controlledConnectFirstAttemptRepeated)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_result=\\(controlledConnectFirstAttemptResult)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_error_bucket=\\(controlledConnectFirstAttemptErrorBucket)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_audio_only=\\(controlledConnectFirstAttemptAudioOnly)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_video_allowed=\\(controlledConnectFirstAttemptVideoAllowed)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_matrix_events_allowed=\\(controlledConnectFirstAttemptMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_raw_credentials_logged=\\(controlledConnectFirstAttemptRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_connect_first_attempt_blocked_reason=\\(controlledConnectFirstAttemptBlockedReason)"))
        #expect(adapterSource.contains("media_connect_requested=\\(mediaConnectRequested)"))
        #expect(adapterSource.contains("media_connect_attempted=\\(mediaConnectAttempted)"))
        #expect(adapterSource.contains("livekit_join_requested=\\(liveKitJoinRequested)"))
        #expect(adapterSource.contains("camera_permission_requested=\\(cameraPermissionRequested)"))
        #expect(adapterSource.contains("matrix_event_emit_requested=\\(matrixEventEmitRequested)"))
        #expect(adapterSource.contains("real_call_flow_started=\\(realCallFlowStarted)"))
    }

    @Test
    func controlledRealAudioPathDefaultsDisabledAndCanReachTestBoundaryWhenAllGatesTrue() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let engineSource = try Self.sourceFile("ElementX/Sources/Services/Calls/DirectCallEngine.swift")
        let mediaEngineSource = try Self.sourceFile("ElementX/Sources/Services/Calls/LiveKitDirectCallMediaEngine.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let realPathStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectRealAudioPath")?.lowerBound)
        let fakeMediaEngineStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectFakeFirstAttemptMediaEngine")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let realPathSource = String(adapterSource[realPathStart..<fakeMediaEngineStart])

        #expect(debugGuardStart < realPathStart)
        #expect(realPathStart < fakeMediaEngineStart)
        #expect(realPathStart < summaryStart)
        #expect(realPathSource.contains("static let defaultDisabledNoConnectReason = \"default_disabled_no_connect\""))
        #expect(realPathSource.contains("static let oneShotConsumedNoConnectReason = \"one_shot_consumed_no_connect\""))
        #expect(realPathSource.contains("static let defaultDisabled = SalemXControlledAudioConnectRealAudioPath(enablementConfiguration: .defaultDisabled"))
        #expect(realPathSource.contains("oneShotNotConsumed: true"))
        #expect(realPathSource.contains("let present = true"))
        #expect(realPathSource.contains("let debugOnly = true"))
        #expect(realPathSource.contains("let isDefaultDisabled = true"))
        #expect(realPathSource.contains("let requiresEnablement = true"))
        #expect(realPathSource.contains("let requiresOperatorApproval = true"))
        #expect(realPathSource.contains("let requiresFuturePhasePermission = true"))
        #expect(realPathSource.contains("let oneShot = true"))
        #expect(realPathSource.contains("let canReachEngineWhenAllGatesTrue = true"))
        #expect(realPathSource.contains("enablementConfiguration.executionAllowed"))
        #expect(realPathSource.contains("executionGate.executionAllowed"))
        #expect(realPathSource.contains("activationPath.activationAllowed"))
        #expect(realPathSource.contains("oneShotNotConsumed"))
        #expect(realPathSource.contains("return Self.oneShotConsumedNoConnectReason"))
        #expect(realPathSource.contains("return Self.defaultDisabledNoConnectReason"))
        #expect(realPathSource.contains("var blockedBeforeEngine: Bool"))

        #expect(adapterSource.contains("var controlledConnectRealAudioPathPresent = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.present"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathDebugOnly = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.debugOnly"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathDefaultDisabled = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.isDefaultDisabled"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathRequiresEnablement = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.requiresEnablement"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathRequiresOperatorApproval = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.requiresOperatorApproval"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathRequiresFuturePhasePermission = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.requiresFuturePhasePermission"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathAudioOnly = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.audioOnly"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathVideoAllowed = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.videoAllowed"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathMatrixEventsAllowed = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.matrixEventsAllowed"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathRawCredentialsLogged = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.rawCredentialsLogged"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathOneShot = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.oneShot"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathAllowed = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.allowed"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathBlockedReason = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.blockedReason"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathBlockedBeforeEngine = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.blockedBeforeEngine"))
        #expect(adapterSource.contains("var controlledConnectRealAudioPathCanReachEngineWhenAllGatesTrue = SalemXControlledAudioConnectRealAudioPath.defaultDisabled.canReachEngineWhenAllGatesTrue"))

        #expect(adapterSource.contains("controlled_connect_real_audio_path_present=\\(controlledConnectRealAudioPathPresent)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_debug_only=\\(controlledConnectRealAudioPathDebugOnly)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_default_disabled=\\(controlledConnectRealAudioPathDefaultDisabled)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_requires_enablement=\\(controlledConnectRealAudioPathRequiresEnablement)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_requires_operator_approval=\\(controlledConnectRealAudioPathRequiresOperatorApproval)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_requires_future_phase_permission=\\(controlledConnectRealAudioPathRequiresFuturePhasePermission)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_audio_only=\\(controlledConnectRealAudioPathAudioOnly)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_video_allowed=\\(controlledConnectRealAudioPathVideoAllowed)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_matrix_events_allowed=\\(controlledConnectRealAudioPathMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_raw_credentials_logged=\\(controlledConnectRealAudioPathRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_one_shot=\\(controlledConnectRealAudioPathOneShot)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_allowed=\\(controlledConnectRealAudioPathAllowed)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_blocked_reason=\\(controlledConnectRealAudioPathBlockedReason)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_blocked_before_engine=\\(controlledConnectRealAudioPathBlockedBeforeEngine)"))
        #expect(adapterSource.contains("controlled_connect_real_audio_path_can_reach_engine_when_all_gates_true=\\(controlledConnectRealAudioPathCanReachEngineWhenAllGatesTrue)"))

        #expect(adapterSource.contains("mutating func recordControlledAudioConnectRealAudioPath(_ realAudioPath: SalemXControlledAudioConnectRealAudioPath)"))
        #expect(adapterSource.contains("mutating func attemptControlledAudioConnectIfAllowed(activationConfiguration: SalemXControlledMediaConnectActivationConfiguration"))
        #expect(adapterSource.contains("credentialsPresent: mediaConnectPreflightCredentialsAvailable"))
        #expect(adapterSource.contains("controlledConnectRealAudioPathAllowed"))
        #expect(adapterSource.contains("recordControlledAudioConnectRealAudioPath(.defaultDisabled)"))
        #expect(adapterSource.contains("recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)"))
        #expect(adapterSource.contains("recordControlledAudioConnectFirstAttemptProof(.controlledRealPathTestBoundary(realAudioPath: realAudioPath"))
        #expect(adapterSource.contains("controlledConnectRealAudioPathBlockedReason"))

        #expect(engineSource.contains("private func connectMediaIfReady(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallSession, DirectCallEngineError>"))
        #expect(engineSource.contains("switch await mediaEngine.connectAudio(for: session, keyHandle: keyHandle)"))
        #expect(mediaEngineSource.contains("func connectAudio(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallMediaState, DirectCallMediaError>"))
        #expect(mediaEngineSource.contains("private let liveKitConnectExecutor: DirectCallLiveKitConnectExecutor"))
        #expect(mediaEngineSource.contains("switch await liveKitConnectExecutor.connectAudio(connectionInfo: connectionInfo, e2eeContext: e2eeContext)"))

        #expect(adapterSource.contains("receiver_audio_permission_request_dispatch_path_available=\\(receiverAudioPermissionRequestDispatchPathAvailable)"))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("emitSignal(type:"))
    }

    @Test
    func controlledAudioConnectFirstAttemptFakeBoundaryRequiresAllGatesAndNoRealMedia() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let fakeMediaEngineStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectFakeFirstAttemptMediaEngine")?.lowerBound)
        let firstAttemptStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectFirstAttempt")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let firstAttemptSource = String(adapterSource[firstAttemptStart..<summaryStart])

        #expect(debugGuardStart < fakeMediaEngineStart)
        #expect(fakeMediaEngineStart < firstAttemptStart)
        #expect(firstAttemptStart < summaryStart)
        #expect(adapterSource.contains("static let testOnlyEnabled = SalemXControlledMediaConnectSwitch(isEnabled: true, operatorApproved: true)"))
        #expect(adapterSource.contains("static let testOnlyEnabled = SalemXControlledMediaConnectActivationConfiguration(controlledConnectSwitch: .testOnlyEnabled"))
        #expect(adapterSource.contains("static let testOnlyEnabled = SalemXControlledMediaConnectEnablementConfiguration(oneShotEnablementEnabled: true"))
        #expect(adapterSource.contains("freshCredentialsPresent: true"))
        #expect(adapterSource.contains("futureConnectPhasePermitted: true"))

        #expect(adapterSource.contains("let usesRealLiveKitNetwork = false"))
        #expect(adapterSource.contains("let mediaConnectRequested = true"))
        #expect(adapterSource.contains("let mediaConnectAttempted = true"))
        #expect(adapterSource.contains("let liveKitJoinRequested = true"))
        #expect(adapterSource.contains("let liveKitConnectAudioInvoked = true"))
        #expect(adapterSource.contains("let microphonePermissionRequested = false"))
        #expect(adapterSource.contains("let cameraPermissionRequested = false"))
        #expect(adapterSource.contains("let matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("let realCallFlowStarted = false"))

        #expect(firstAttemptSource.contains("static func controlledRealPathTestBoundary(realAudioPath: SalemXControlledAudioConnectRealAudioPath"))
        #expect(firstAttemptSource.contains("let requested = true"))
        #expect(firstAttemptSource.contains("realAudioPath.allowed"))
        #expect(firstAttemptSource.contains("realAudioPath.canReachEngineWhenAllGatesTrue"))
        #expect(firstAttemptSource.contains("!fakeMediaEngine.usesRealLiveKitNetwork"))
        #expect(firstAttemptSource.contains("!fakeMediaEngine.cameraPermissionRequested"))
        #expect(firstAttemptSource.contains("!fakeMediaEngine.matrixEventEmitRequested"))
        #expect(firstAttemptSource.contains("!fakeMediaEngine.realCallFlowStarted"))
        #expect(firstAttemptSource.contains("started: allowed"))
        #expect(firstAttemptSource.contains("completed: allowed"))
        #expect(firstAttemptSource.contains("repeated: false"))
        #expect(firstAttemptSource.contains("allowed ? fakeMediaEngine.firstAttemptResult : \"blocked_redacted\""))
        #expect(firstAttemptSource.contains("static func fakeBoundaryForTests(enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration"))
        #expect(firstAttemptSource.contains("controlledRealPathTestBoundary(realAudioPath: SalemXControlledAudioConnectRealAudioPath(enablementConfiguration: enablementConfiguration"))

        #expect(adapterSource.contains("mutating func recordControlledAudioConnectFirstAttemptProof(_ firstAttempt: SalemXControlledAudioConnectFirstAttempt)"))
        #expect(adapterSource.contains("mediaConnectRequested = firstAttempt.mediaConnectRequested"))
        #expect(adapterSource.contains("mediaConnectAttempted = firstAttempt.mediaConnectAttempted"))
        #expect(adapterSource.contains("liveKitJoinRequested = firstAttempt.liveKitJoinRequested"))
        #expect(adapterSource.contains("liveKitConnectAudioInvoked = firstAttempt.liveKitConnectAudioInvoked"))
        #expect(adapterSource.contains("recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)"))
        #expect(adapterSource.contains("mutating func recordControlledAudioConnectFirstAttemptBoundaryForTests()"))
        #expect(adapterSource.contains("let activationConfiguration = SalemXControlledMediaConnectActivationConfiguration.testOnlyEnabled"))
        #expect(adapterSource.contains("let enablementConfiguration = SalemXControlledMediaConnectEnablementConfiguration.testOnlyEnabled"))
        #expect(adapterSource.contains("mediaConnectPreflightCredentialsAvailable = true"))
        #expect(adapterSource.contains("controlledConnectEnablementExecutionAllowed &&"))
        #expect(adapterSource.contains("controlledAudioConnectExecutionAllowed &&"))
        #expect(adapterSource.contains("controlledAudioConnectActivationAllowed"))
        #expect(adapterSource.contains("controlledConnectRealAudioPathAllowed"))
        #expect(adapterSource.contains("attemptControlledAudioConnectRuntimeIfAllowed(activationConfiguration: activationConfiguration"))
        #expect(adapterSource.contains("blockedReason = controlledConnectFirstAttemptAllowed ? \"none\" : controlledConnectFirstAttemptBlockedReason"))

        #expect(!firstAttemptSource.contains(".connectAudio("))
        #expect(adapterSource.contains("receiver_audio_permission_request_dispatch_path_available=\\(receiverAudioPermissionRequestDispatchPathAvailable)"))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("emitSignal(type:"))
    }

    @Test
    func controlledNoLocalMediaJoinReleasesStaleDebugLeaseBeforeOneShotConnect() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let start = try #require(adapterSource.range(of: "private static func startReceiverControlledRuntimeConnectLeaseIfAllowed")?.lowerBound)
        let end = try #require(adapterSource.range(of: "@MainActor\n    private static func runReceiverControlledRuntimeConnectLease")?.lowerBound)
        let source = String(adapterSource[start..<end])

        #expect(source.contains("staleRuntimeBlocksFreshNoLocalMediaJoin"))
        #expect(source.contains("physical6RuntimeEnablementURLHookSnapshot.oneShotNotConsumed"))
        #expect(source.contains("summary.mediaCredentialsResult == \"success_redacted\""))
        #expect(source.contains("summary.mediaCredentialsRequestMetadataAvailable"))
        #expect(source.contains("receiverConnectedSessionLease = nil"))
        #expect(source.contains("receiverConnectedSessionLeaseTask = nil"))
        #expect(source.contains("staleTaskToCancel?.cancel()"))
        #expect(source.contains("await staleLeaseToCleanup.cleanup()"))
        #expect(source.contains("recordControlledMediaConnectPreflight(credentialsAvailable: true"))
        #expect(adapterSource.contains("let receiverAudioPublishPending = receiverAudioPublishTriggerSeenByApp &&"))
        #expect(adapterSource.contains("(!receiverAudioObservationTerminal || receiverAudioPublishPending)"))
        #expect(!source.contains("requestRecordPermission"))
        #expect(!source.contains("AVCaptureDevice.requestAccess"))
        #expect(!source.contains("emitSignal(type:"))
    }

    @Test
    func receiverAudioPublishGateIsDebugOnlyAndRequiresConnectedAnswerBeforeMicrophone() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let hookPath = try #require(adapterSource.range(of: "receiverAudioPublishTriggerURLHookPath = \"/direct-call/receiver-audio-publish-trigger\"")?.lowerBound)
        let triggerStart = try #require(adapterSource.range(of: "private static func startReceiverAudioPublishTriggerURLHook")?.lowerBound)
        let triggerEnd = try #require(adapterSource.range(of: "private static func armSimulatorRemotePeerContextHandoffURLHook")?.lowerBound)
        let source = String(adapterSource[triggerStart..<triggerEnd])

        #expect(debugGuardStart < hookPath)
        #expect(adapterSource.contains("receiverAudioPublishTriggerConfirmation = \"RUN_2_49Z6X_RECEIVER_AUDIO_PUBLISH\""))
        #expect(source.contains("receiverAudioPublishGateArmed = true"))
        #expect(source.contains("summary.recordReceiverAudioPublishGateInspection(armed: true)"))
        #expect(source.contains("summary.recordReceiverAudioPublishTriggerStarted(confirmed: false"))
        #expect(source.contains("summary.callKitAnswerActionReceived &&"))
        #expect(source.contains("summary.mediaCredentialsResult == \"success_redacted\""))
        #expect(source.contains("summary.liveKitJoinResult == \"success_redacted\""))
        #expect(source.contains("summary.liveKitRoomConnected &&"))
        #expect(source.contains("leaseAvailable"))
        #expect(source.contains("receiverAudioPublishGateArmed"))
        #expect(source.contains("receiverAudioPublishTriggerConsumed = true"))
        #expect(source.contains("lease.client.setMicrophoneEnabled(true)"))
        #expect(source.contains("summary.recordReceiverAudioPublishFunctionEntered(ready: true, permissionState: permissionState)"))
        #expect(source.contains("summary.recordReceiverAudioPermissionRequestDispatched()"))
        #expect(source.contains("summary.recordReceiverAudioPermissionCompletion(granted: permissionResult.grantedForPublish"))
        #expect(source.contains("summary.recordReceiverAudioTrackPublishStarted()"))
        #expect(source.contains("summary.recordReceiverAudioPublishResult(result)"))
        #expect(!source.contains("AVCaptureDevice.requestAccess"))
        #expect(!source.contains("setCameraEnabled(true)"))
        #expect(!source.contains("emitSignal(type:"))
        #expect(!source.contains("realCallFlowStarted = true"))

        #expect(adapterSource.contains("receiver_audio_permission_gate_available=\\(receiverAudioPermissionGateAvailable)"))
        #expect(adapterSource.contains("receiver_audio_publish_gate_available=\\(receiverAudioPublishGateAvailable)"))
        #expect(adapterSource.contains("receiver_audio_publish_trigger_consumable_when_ready=\\(receiverAudioPublishTriggerConsumableWhenReady)"))
        #expect(adapterSource.contains("receiver_audio_publish_invoke_dispatch_path_available=\\(receiverAudioPublishInvokeDispatchPathAvailable)"))
        #expect(adapterSource.contains("receiver_audio_publish_invoke_dispatch_result_bucket=\\(receiverAudioPublishInvokeDispatchResultBucket)"))
        #expect(adapterSource.contains("receiver_audio_publish_call_invoked_in_app=\\(receiverAudioPublishCallInvokedInApp)"))
        #expect(adapterSource.contains("receiver_audio_publish_call_invocation_failure_bucket=\\(receiverAudioPublishCallInvocationFailureBucket)"))
        #expect(adapterSource.contains("receiver_audio_publish_blocked_reason_bucket=\\(receiverAudioPublishBlockedReasonBucket)"))
        #expect(adapterSource.contains("receiver_livekit_join_state_latch_bucket=\\(receiverLiveKitJoinStateLatchBucket)"))
        #expect(adapterSource.contains("receiver_audio_track_create_path_available=\\(receiverAudioTrackCreatePathAvailable)"))
        #expect(adapterSource.contains("receiver_audio_track_publish_path_available=\\(receiverAudioTrackPublishPathAvailable)"))
        #expect(adapterSource.contains("receiver_audio_permission_bridge_available=\\(receiverAudioPermissionBridgeAvailable)"))
        #expect(adapterSource.contains("receiver_audio_publish_function_entered_bucket=\\(receiverAudioPublishFunctionEnteredBucket)"))
        #expect(adapterSource.contains("receiver_audio_publish_stage_after_invoke_bucket=\\(receiverAudioPublishStageAfterInvokeBucket)"))
        #expect(adapterSource.contains("receiver_audio_permission_state_before_request_bucket=\\(receiverAudioPermissionStateBeforeRequestBucket)"))
        #expect(adapterSource.contains("receiver_audio_permission_request_dispatch_path_available=\\(receiverAudioPermissionRequestDispatchPathAvailable)"))
        #expect(adapterSource.contains("receiver_audio_permission_request_decision_bucket=\\(receiverAudioPermissionRequestDecisionBucket)"))
        #expect(adapterSource.contains("receiver_audio_permission_request_blocked_reason_bucket=\\(receiverAudioPermissionRequestBlockedReasonBucket)"))
        #expect(adapterSource.contains("receiver_audio_permission_completion_observed_bucket=\\(receiverAudioPermissionCompletionObservedBucket)"))
        #expect(adapterSource.contains("receiver_audio_permission_wait_result_bucket=\\(receiverAudioPermissionWaitResultBucket)"))
        #expect(adapterSource.contains("receiver_audio_permission_failure_bucket=\\(receiverAudioPermissionFailureBucket)"))
        #expect(adapterSource.contains("receiver_local_audio_track_create_attempted=\\(receiverLocalAudioTrackCreateAttempted)"))
        #expect(adapterSource.contains("receiver_local_audio_track_publish_attempted=\\(receiverLocalAudioTrackPublishAttempted)"))
        #expect(adapterSource.contains("mutating func recordReceiverAudioPublishInvocationDispatched(ready: Bool)"))
        #expect(adapterSource.contains("mutating func recordReceiverAudioPublishFunctionEntered(ready: Bool, permissionState: String)"))
        #expect(adapterSource.contains("mutating func recordReceiverAudioPermissionRequestDispatched()"))
        #expect(adapterSource.contains("mutating func recordReceiverAudioPermissionCompletion(granted: Bool, timedOut: Bool)"))
        #expect(adapterSource.contains("mutating func recordReceiverAudioTrackPublishStarted()"))
        #expect(adapterSource.contains("summary.recordReceiverAudioPublishInvocationDispatched(ready: ready && !repeated && lease != nil)"))
        #expect(adapterSource.contains("sender_remote_audio_observer_path_available=\\(senderRemoteAudioObserverPathAvailable)"))
        #expect(adapterSource.contains("sender_subscribe_remote_audio_path_available=\\(senderSubscribeRemoteAudioPathAvailable)"))
        #expect(adapterSource.contains("sender_remote_audio_subscription_state_path_available=\\(senderRemoteAudioSubscriptionStatePathAvailable)"))
        #expect(adapterSource.contains("sender_remote_audio_auto_subscribe_bucket=\\(senderRemoteAudioAutoSubscribeBucket)"))
        #expect(adapterSource.contains("sender_remote_audio_manual_subscribe_path_available=\\(senderRemoteAudioManualSubscribePathAvailable)"))
        #expect(adapterSource.contains("sender_remote_audio_manual_subscribe_attempted=\\(senderRemoteAudioManualSubscribeAttempted)"))
        #expect(adapterSource.contains("sender_remote_audio_manual_subscribe_result_bucket=\\(senderRemoteAudioManualSubscribeResultBucket)"))
        #expect(adapterSource.contains("sender_remote_audio_subscribe_wait_bucket=\\(senderRemoteAudioSubscribeWaitBucket)"))
        #expect(adapterSource.contains("sender_remote_audio_subscribe_failure_bucket=\\(senderRemoteAudioSubscribeFailureBucket)"))
        #expect(adapterSource.contains("sender_remote_audio_observer_registered_before_join_bucket=\\(senderRemoteAudioObserverRegisteredBeforeJoinBucket)"))
        #expect(adapterSource.contains("sender_remote_audio_observer_registered_after_join_bucket=\\(senderRemoteAudioObserverRegisteredAfterJoinBucket)"))
        #expect(adapterSource.contains("sender_remote_audio_observer_registration_bucket=\\(senderRemoteAudioObserverRegistrationBucket)"))
        #expect(adapterSource.contains("senderRemoteAudioAutoSubscribeBucket = \"disabled_redacted\""))
        #expect(adapterSource.contains("for attempt in 0..<45"))
        #expect(adapterSource.contains("remotePlaybackResult = await client.setRemoteAudioPlaybackEnabled(true)"))
        #expect(adapterSource.contains("if snapshot.audioTrackSubscribed"))
        #expect(adapterSource.contains("senderRemoteAudioManualSubscribeResultBucket = manualSubscribeAttempted"))
        #expect(adapterSource.contains("senderRemoteAudioSubscribeFailureBucket = \"subscription_timeout_redacted\""))
        #expect(adapterSource.contains("receiverAudioPublishSuccessLatchBucket = audioPublicationSeen ? \"present_redacted\" : \"missing_redacted\""))
        #expect(adapterSource.contains("receiverLiveKitJoinStateLatchBucket = leaseAvailable && liveKitJoinResult == \"success_redacted\" ? \"available_redacted\" : \"missing_redacted\""))
        #expect(adapterSource.contains("(summary.liveKitRoomConnected || leaseAvailable) &&"))
        #expect(adapterSource.contains("receiver_local_audio_track_published=\\(receiverLocalAudioTrackPublished)"))
        #expect(!adapterSource.contains("receiverAudioPermissionResultBucket = \"raw"))
    }

    @Test
    func normalIncomingAnswerAudioLifecycleSkeletonKeepsProductionAudioDisabled() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("normal_incoming_answer_audio_lifecycle_bucket=\\(normalIncomingAnswerAudioLifecycleBucket)"))
        #expect(adapterSource.contains("callkit_answer_to_receiver_credentials_path_bucket=\\(callKitAnswerToReceiverCredentialsPathBucket)"))
        #expect(adapterSource.contains("receiver_credentials_to_livekit_join_path_bucket=\\(receiverCredentialsToLiveKitJoinPathBucket)"))
        #expect(adapterSource.contains("receiver_livekit_join_to_audio_publish_readiness_bucket=\\(receiverLiveKitJoinToAudioPublishReadinessBucket)"))
        #expect(adapterSource.contains("receiver_audio_publish_to_remote_subscribe_readiness_bucket=\\(receiverAudioPublishToRemoteSubscribeReadinessBucket)"))
        #expect(adapterSource.contains("normalIncomingAnswerAudioLifecycleBucket = \"present_redacted\""))
        #expect(adapterSource.contains("callKitAnswerToReceiverCredentialsPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("receiverCredentialsToLiveKitJoinPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("receiverLiveKitJoinToAudioPublishReadinessBucket = \"present_redacted\""))
        #expect(adapterSource.contains("receiverAudioPublishToRemoteSubscribeReadinessBucket = \"present_redacted\""))
        #expect(adapterSource.contains("no_uncontrolled_microphone_request_guard_bucket=\\(noUncontrolledMicrophoneRequestGuardBucket)"))
        #expect(adapterSource.contains("no_uncontrolled_local_audio_publish_guard_bucket=\\(noUncontrolledLocalAudioPublishGuardBucket)"))
        #expect(adapterSource.contains("production_audio_enabled_bucket=\\(productionAudioEnabledBucket)"))
        #expect(adapterSource.contains("noUncontrolledMicrophoneRequestGuardBucket = \"present_redacted\""))
        #expect(adapterSource.contains("noUncontrolledLocalAudioPublishGuardBucket = \"present_redacted\""))
        #expect(adapterSource.contains("productionAudioEnabledBucket = \"false\""))
        #expect(adapterSource.contains("receiver_audio_publish_gate_bucket=\\(receiverAudioPublishGateBucket)"))
        #expect(adapterSource.contains("sender_remote_audio_subscribed_bucket=\\(senderRemoteAudioSubscribedBucket)"))
        #expect(adapterSource.contains("receiver_remote_audio_track_subscribed=\\(receiverRemoteAudioTrackSubscribed)"))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("setCameraEnabled(true)"))
        #expect(!adapterSource.contains("realCallFlowStarted = true"))
    }

    @Test
    func normalOutgoingStartAudioLifecycleSkeletonKeepsProductionAudioDisabled() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("normal_outgoing_start_audio_lifecycle_bucket=\\(normalOutgoingStartAudioLifecycleBucket)"))
        #expect(adapterSource.contains("outgoing_start_to_metadata_path_bucket=\\(outgoingStartToMetadataPathBucket)"))
        #expect(adapterSource.contains("metadata_to_sender_claim_path_bucket=\\(metadataToSenderClaimPathBucket)"))
        #expect(adapterSource.contains("sender_claim_to_sender_credentials_path_bucket=\\(senderClaimToSenderCredentialsPathBucket)"))
        #expect(adapterSource.contains("sender_credentials_to_livekit_join_path_bucket=\\(senderCredentialsToLiveKitJoinPathBucket)"))
        #expect(adapterSource.contains("sender_livekit_join_to_audio_publish_readiness_bucket=\\(senderLiveKitJoinToAudioPublishReadinessBucket)"))
        #expect(adapterSource.contains("sender_audio_publish_to_receiver_remote_subscribe_readiness_bucket=\\(senderAudioPublishToReceiverRemoteSubscribeReadinessBucket)"))
        #expect(adapterSource.contains("normalOutgoingStartAudioLifecycleBucket = \"present_redacted\""))
        #expect(adapterSource.contains("outgoingStartToMetadataPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("metadataToSenderClaimPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("senderClaimToSenderCredentialsPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("senderCredentialsToLiveKitJoinPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("senderLiveKitJoinToAudioPublishReadinessBucket = \"present_redacted\""))
        #expect(adapterSource.contains("senderAudioPublishToReceiverRemoteSubscribeReadinessBucket = \"present_redacted\""))
        #expect(adapterSource.contains("no_sender_audio_before_credentials_guard_bucket=\\(noSenderAudioBeforeCredentialsGuardBucket)"))
        #expect(adapterSource.contains("no_sender_audio_before_livekit_guard_bucket=\\(noSenderAudioBeforeLiveKitGuardBucket)"))
        #expect(adapterSource.contains("noSenderAudioBeforeCredentialsGuardBucket = \"present_redacted\""))
        #expect(adapterSource.contains("noSenderAudioBeforeLiveKitGuardBucket = \"present_redacted\""))
        #expect(adapterSource.contains("normalOutgoingPhysicalValidationRequiredBucket = \"true\""))
        #expect(adapterSource.contains("productionAudioEnabledBucket = \"false\""))
        #expect(adapterSource.contains("prepared_metadata_claimed_by_sender=\\(preparedMetadataClaimedBySender)"))
        #expect(adapterSource.contains("sender_media_credentials_result_bucket=\\(senderMediaCredentialsResultBucket)"))
        #expect(adapterSource.contains("sender_side_livekit_join_result=\\(senderSideLiveKitJoinResult)"))
        #expect(adapterSource.contains("sender_local_audio_publish_requested=\\(senderLocalAudioPublishRequested)"))
        #expect(adapterSource.contains("receiver_remote_audio_track_subscribed=\\(receiverRemoteAudioTrackSubscribed)"))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("setCameraEnabled(true)"))
        #expect(adapterSource.contains("senderLocalAudioPublishRequested = false"))
        #expect(!adapterSource.contains("realCallFlowStarted = true"))
    }

    @Test
    func normalTwoWayAudioConvergenceSkeletonKeepsProductionAudioDisabled() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("normal_two_way_audio_convergence_bucket=\\(normalTwoWayAudioConvergenceBucket)"))
        #expect(adapterSource.contains("two_way_metadata_path_bucket=\\(twoWayMetadataPathBucket)"))
        #expect(adapterSource.contains("two_way_sender_credentials_path_bucket=\\(twoWaySenderCredentialsPathBucket)"))
        #expect(adapterSource.contains("two_way_receiver_credentials_path_bucket=\\(twoWayReceiverCredentialsPathBucket)"))
        #expect(adapterSource.contains("two_way_sender_livekit_join_path_bucket=\\(twoWaySenderLiveKitJoinPathBucket)"))
        #expect(adapterSource.contains("two_way_receiver_livekit_join_path_bucket=\\(twoWayReceiverLiveKitJoinPathBucket)"))
        #expect(adapterSource.contains("two_way_both_participants_connected_gate_bucket=\\(twoWayBothParticipantsConnectedGateBucket)"))
        #expect(adapterSource.contains("two_way_receiver_audio_publish_readiness_bucket=\\(twoWayReceiverAudioPublishReadinessBucket)"))
        #expect(adapterSource.contains("two_way_sender_audio_publish_readiness_bucket=\\(twoWaySenderAudioPublishReadinessBucket)"))
        #expect(adapterSource.contains("two_way_sender_remote_subscribe_readiness_bucket=\\(twoWaySenderRemoteSubscribeReadinessBucket)"))
        #expect(adapterSource.contains("two_way_receiver_remote_subscribe_readiness_bucket=\\(twoWayReceiverRemoteSubscribeReadinessBucket)"))
        #expect(adapterSource.contains("no_audio_before_credentials_guard_bucket=\\(noAudioBeforeCredentialsGuardBucket)"))
        #expect(adapterSource.contains("no_audio_before_livekit_guard_bucket=\\(noAudioBeforeLiveKitGuardBucket)"))
        #expect(adapterSource.contains("remote_subscribe_requires_track_seen_guard_bucket=\\(remoteSubscribeRequiresTrackSeenGuardBucket)"))
        #expect(adapterSource.contains("normal_two_way_physical_validation_required_bucket=\\(normalTwoWayPhysicalValidationRequiredBucket)"))
        #expect(adapterSource.contains("normalTwoWayAudioConvergenceBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWayMetadataPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWaySenderCredentialsPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWayReceiverCredentialsPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWaySenderLiveKitJoinPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWayReceiverLiveKitJoinPathBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWayBothParticipantsConnectedGateBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWayReceiverAudioPublishReadinessBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWaySenderAudioPublishReadinessBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWaySenderRemoteSubscribeReadinessBucket = \"present_redacted\""))
        #expect(adapterSource.contains("twoWayReceiverRemoteSubscribeReadinessBucket = \"present_redacted\""))
        #expect(adapterSource.contains("noAudioBeforeCredentialsGuardBucket = \"present_redacted\""))
        #expect(adapterSource.contains("noAudioBeforeLiveKitGuardBucket = \"present_redacted\""))
        #expect(adapterSource.contains("remoteSubscribeRequiresTrackSeenGuardBucket = \"present_redacted\""))
        #expect(adapterSource.contains("normalTwoWayPhysicalValidationRequiredBucket = \"true\""))
        #expect(adapterSource.contains("productionAudioEnabledBucket = \"false\""))
        #expect(adapterSource.contains("normalIncomingAnswerAudioLifecycleBucket = \"present_redacted\""))
        #expect(adapterSource.contains("normalOutgoingStartAudioLifecycleBucket = \"present_redacted\""))
        #expect(adapterSource.contains("receiverAudioPublishToRemoteSubscribeReadinessBucket = \"present_redacted\""))
        #expect(adapterSource.contains("senderAudioPublishToReceiverRemoteSubscribeReadinessBucket = \"present_redacted\""))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("setCameraEnabled(true)"))
        #expect(!adapterSource.contains("realCallFlowStarted = true"))
    }

    @Test
    func controlledRealRuntimePathDefaultsDisabledAndCallsFakeMediaOnlyWhenAllGatesTrue() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let runtimePathStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectRealRuntimePath")?.lowerBound)
        let fakeMediaEngineStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectFakeFirstAttemptMediaEngine")?.lowerBound)
        let firstAttemptStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectFirstAttempt")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let runtimePathSource = String(adapterSource[runtimePathStart..<fakeMediaEngineStart])
        let firstAttemptSource = String(adapterSource[firstAttemptStart..<summaryStart])

        #expect(debugGuardStart < runtimePathStart)
        #expect(runtimePathStart < fakeMediaEngineStart)
        #expect(runtimePathStart < summaryStart)
        #expect(runtimePathSource.contains("static let defaultDisabledNoConnectReason = \"default_disabled_no_connect\""))
        #expect(runtimePathSource.contains("static let oneShotConsumedNoConnectReason = \"one_shot_consumed_no_connect\""))
        #expect(runtimePathSource.contains("static let defaultDisabled = SalemXControlledAudioConnectRealRuntimePath(credentialsPresent: false"))
        #expect(runtimePathSource.contains("let credentialsPresent: Bool"))
        #expect(runtimePathSource.contains("let present = true"))
        #expect(runtimePathSource.contains("let debugOnly = true"))
        #expect(runtimePathSource.contains("let isDefaultDisabled = true"))
        #expect(runtimePathSource.contains("let requiresCredentials = true"))
        #expect(runtimePathSource.contains("let requiresEnablement = true"))
        #expect(runtimePathSource.contains("let requiresOperatorApproval = true"))
        #expect(runtimePathSource.contains("let requiresFuturePhasePermission = true"))
        #expect(runtimePathSource.contains("let oneShot = true"))
        #expect(runtimePathSource.contains("let canCallConnectMediaWhenAllGatesTrue = true"))
        #expect(runtimePathSource.contains("let canCallLiveKitAudioWhenAllGatesTrue = true"))
        #expect(runtimePathSource.contains("credentialsPresent &&"))
        #expect(runtimePathSource.contains("enablementConfiguration.executionAllowed"))
        #expect(runtimePathSource.contains("executionGate.executionAllowed"))
        #expect(runtimePathSource.contains("activationPath.activationAllowed"))
        #expect(runtimePathSource.contains("!videoAllowed"))
        #expect(runtimePathSource.contains("!matrixEventsAllowed"))
        #expect(runtimePathSource.contains("!rawCredentialsLogged"))
        #expect(runtimePathSource.contains("oneShotNotConsumed"))
        #expect(runtimePathSource.contains("canCallConnectMediaWhenAllGatesTrue"))
        #expect(runtimePathSource.contains("canCallLiveKitAudioWhenAllGatesTrue"))
        #expect(runtimePathSource.contains("return Self.oneShotConsumedNoConnectReason"))
        #expect(runtimePathSource.contains("return Self.defaultDisabledNoConnectReason"))
        #expect(runtimePathSource.contains("return SalemXControlledAudioConnectExecutionGate.credentialsMissingNoConnectReason"))

        #expect(adapterSource.contains("var controlledConnectRealRuntimePathPresent = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.present"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathDebugOnly = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.debugOnly"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathDefaultDisabled = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.isDefaultDisabled"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathRequiresCredentials = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.requiresCredentials"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathRequiresEnablement = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.requiresEnablement"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathRequiresOperatorApproval = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.requiresOperatorApproval"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathRequiresFuturePhasePermission = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.requiresFuturePhasePermission"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathAudioOnly = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.audioOnly"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathVideoAllowed = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.videoAllowed"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathMatrixEventsAllowed = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.matrixEventsAllowed"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathRawCredentialsLogged = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.rawCredentialsLogged"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathOneShot = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.oneShot"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathAllowed = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.allowed"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathBlockedReason = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.blockedReason"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathBlockedBeforeEngine = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.blockedBeforeEngine"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathCanCallConnectMediaWhenAllGatesTrue = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.canCallConnectMediaWhenAllGatesTrue"))
        #expect(adapterSource.contains("var controlledConnectRealRuntimePathCanCallLiveKitAudioWhenAllGatesTrue = SalemXControlledAudioConnectRealRuntimePath.defaultDisabled.canCallLiveKitAudioWhenAllGatesTrue"))

        #expect(adapterSource.contains("controlled_connect_real_runtime_path_present=\\(controlledConnectRealRuntimePathPresent)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_debug_only=\\(controlledConnectRealRuntimePathDebugOnly)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_default_disabled=\\(controlledConnectRealRuntimePathDefaultDisabled)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_requires_credentials=\\(controlledConnectRealRuntimePathRequiresCredentials)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_requires_enablement=\\(controlledConnectRealRuntimePathRequiresEnablement)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_requires_operator_approval=\\(controlledConnectRealRuntimePathRequiresOperatorApproval)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_requires_future_phase_permission=\\(controlledConnectRealRuntimePathRequiresFuturePhasePermission)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_audio_only=\\(controlledConnectRealRuntimePathAudioOnly)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_video_allowed=\\(controlledConnectRealRuntimePathVideoAllowed)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_matrix_events_allowed=\\(controlledConnectRealRuntimePathMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_raw_credentials_logged=\\(controlledConnectRealRuntimePathRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_one_shot=\\(controlledConnectRealRuntimePathOneShot)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_allowed=\\(controlledConnectRealRuntimePathAllowed)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_blocked_reason=\\(controlledConnectRealRuntimePathBlockedReason)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_blocked_before_engine=\\(controlledConnectRealRuntimePathBlockedBeforeEngine)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_can_call_connect_media_when_all_gates_true=\\(controlledConnectRealRuntimePathCanCallConnectMediaWhenAllGatesTrue)"))
        #expect(adapterSource.contains("controlled_connect_real_runtime_path_can_call_livekit_audio_when_all_gates_true=\\(controlledConnectRealRuntimePathCanCallLiveKitAudioWhenAllGatesTrue)"))

        #expect(adapterSource.contains("mutating func recordControlledAudioConnectRealRuntimePath(_ realRuntimePath: SalemXControlledAudioConnectRealRuntimePath)"))
        #expect(adapterSource.contains("mutating func attemptControlledAudioConnectRuntimeIfAllowed(activationConfiguration: SalemXControlledMediaConnectActivationConfiguration"))
        #expect(adapterSource.contains("recordControlledAudioConnectRealRuntimePath(realRuntimePath)"))
        #expect(adapterSource.contains("controlledConnectRealRuntimePathAllowed"))
        #expect(adapterSource.contains("let realBridge = SalemXControlledAudioConnectRealBridge(realRuntimePath: realRuntimePath"))
        #expect(adapterSource.contains("recordControlledAudioConnectRealBridge(realBridge)"))
        #expect(adapterSource.contains("controlledConnectRealBridgeAllowed"))
        #expect(adapterSource.contains("if realBridge.allowed"))
        #expect(adapterSource.contains("recordControlledAudioConnectFirstAttemptProof(.controlledRealBridgeTestBoundary(realBridge: realBridge"))
        #expect(adapterSource.contains("recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)"))
        #expect(adapterSource.contains("attemptControlledAudioConnectRuntimeIfAllowed(activationConfiguration: physical6RuntimeEnablementHook.activationConfiguration"))
        #expect(adapterSource.contains("receiverAppSessionValidated: pendingMetadataFetchAuthorized && pendingMetadataFetchResult == \"success_redacted\""))
        #expect(adapterSource.contains("oneShotNotConsumed: physical6RuntimeEnablementHook.oneShotNotConsumed"))

        #expect(firstAttemptSource.contains("static func controlledRealRuntimeBoundary(realRuntimePath: SalemXControlledAudioConnectRealRuntimePath"))
        #expect(firstAttemptSource.contains("let requested = realRuntimePath.allowed"))
        #expect(firstAttemptSource.contains("realRuntimePath.canCallConnectMediaWhenAllGatesTrue"))
        #expect(firstAttemptSource.contains("realRuntimePath.canCallLiveKitAudioWhenAllGatesTrue"))
        #expect(firstAttemptSource.contains("!fakeMediaEngine.usesRealLiveKitNetwork"))
        #expect(firstAttemptSource.contains("started: allowed"))
        #expect(firstAttemptSource.contains("completed: allowed"))
        #expect(firstAttemptSource.contains("repeated: false"))
        #expect(firstAttemptSource.contains("mediaConnectRequested: allowed && fakeMediaEngine.mediaConnectRequested"))
        #expect(firstAttemptSource.contains("liveKitJoinRequested: allowed && fakeMediaEngine.liveKitJoinRequested"))
        #expect(firstAttemptSource.contains("liveKitConnectAudioInvoked: allowed && fakeMediaEngine.liveKitConnectAudioInvoked"))
        #expect(firstAttemptSource.contains("cameraPermissionRequested: false"))
        #expect(firstAttemptSource.contains("matrixEventEmitRequested: false"))
        #expect(firstAttemptSource.contains("realCallFlowStarted: false"))
    }

    @Test
    func controlledRealBridgeCanReachRealRuntimeBoundaryWhenAllGatesTrue() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let engineSource = try Self.sourceFile("ElementX/Sources/Services/Calls/DirectCallEngine.swift")
        let mediaEngineSource = try Self.sourceFile("ElementX/Sources/Services/Calls/LiveKitDirectCallMediaEngine.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let bridgeStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectRealBridge")?.lowerBound)
        let fakeMediaEngineStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectFakeFirstAttemptMediaEngine")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let bridgeSource = String(adapterSource[bridgeStart..<fakeMediaEngineStart])

        #expect(debugGuardStart < bridgeStart)
        #expect(bridgeStart < summaryStart)
        #expect(bridgeSource.contains("static let defaultDisabledNoConnectReason = \"default_disabled_no_connect\""))
        #expect(bridgeSource.contains("static let oneShotConsumedNoConnectReason = \"one_shot_consumed_no_connect\""))
        #expect(bridgeSource.contains("static let defaultDisabled = SalemXControlledAudioConnectRealBridge(realRuntimePath: .defaultDisabled"))
        #expect(bridgeSource.contains("let realRuntimePath: SalemXControlledAudioConnectRealRuntimePath"))
        #expect(bridgeSource.contains("let oneShotNotConsumed: Bool"))
        #expect(bridgeSource.contains("let present = true"))
        #expect(bridgeSource.contains("let debugOnly = true"))
        #expect(bridgeSource.contains("let isDefaultDisabled = true"))
        #expect(bridgeSource.contains("let requiresCredentials = true"))
        #expect(bridgeSource.contains("let requiresEnablement = true"))
        #expect(bridgeSource.contains("let requiresOperatorApproval = true"))
        #expect(bridgeSource.contains("let requiresFuturePhasePermission = true"))
        #expect(bridgeSource.contains("let oneShot = true"))
        #expect(bridgeSource.contains("let canCallConnectMediaWhenAllGatesTrue = true"))
        #expect(bridgeSource.contains("let canCallLiveKitAudioWhenAllGatesTrue = true"))
        #expect(bridgeSource.contains("let usesFakeEngineInTestsOnly = true"))
        #expect(bridgeSource.contains("let usesRealRuntimeBoundaryWhenNotTest = true"))
        #expect(bridgeSource.contains("realRuntimePath.allowed"))
        #expect(bridgeSource.contains("oneShotNotConsumed"))
        #expect(bridgeSource.contains("canCallConnectMediaWhenAllGatesTrue"))
        #expect(bridgeSource.contains("canCallLiveKitAudioWhenAllGatesTrue"))
        #expect(bridgeSource.contains("usesRealRuntimeBoundaryWhenNotTest"))
        #expect(bridgeSource.contains("return realRuntimePath.blockedReason"))
        #expect(bridgeSource.contains("var blockedBeforeConnectMedia: Bool"))
        #expect(bridgeSource.contains("func connectMediaIfReadyWhenControlledGatesOpen(session: DirectCallSession"))
        #expect(bridgeSource.contains("runtimeBoundary: any SalemXControlledAudioConnectRuntimeBoundary"))
        #expect(bridgeSource.contains("guard allowed else"))
        #expect(bridgeSource.contains("let result = await runtimeBoundary.connectMediaIfReadyWhenControlledGatesOpen(callID: session.callID)"))
        #expect(bridgeSource.contains("return .controlledRealBridgeRuntimeBoundary(realBridge: self, result: result)"))

        #expect(adapterSource.contains("private protocol SalemXControlledAudioConnectRuntimeBoundary"))
        #expect(adapterSource.contains("func connectMediaIfReadyWhenControlledGatesOpen(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>"))
        #expect(adapterSource.contains("private struct SalemXDirectCallEngineControlledAudioConnectRuntimeBoundary: SalemXControlledAudioConnectRuntimeBoundary"))
        #expect(adapterSource.contains("let directCallEngine: any DirectCallEngineProtocol"))
        #expect(adapterSource.contains("await directCallEngine.acceptCall(callID: callID)"))
        #expect(engineSource.contains("func acceptCall(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>"))
        #expect(engineSource.contains("func requestMediaCredentials(callID: String) async -> Result<DirectCallMediaConnectionInfo, DirectCallEngineError>"))
        #expect(engineSource.contains("switch await mediaCredentialsRequester.requestMediaCredentials(for: session)"))
        #expect(engineSource.contains("return await connectMediaIfReady(for: session, keyHandle: keyHandle)"))
        #expect(engineSource.contains("switch await mediaEngine.connectAudio(for: session, keyHandle: keyHandle)"))
        #expect(mediaEngineSource.contains("func connectAudio(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallMediaState, DirectCallMediaError>"))
        #expect(mediaEngineSource.contains("func requestMediaCredentials(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError>"))
        #expect(mediaEngineSource.contains("switch await tokenProvider.connectionInfo(for: session)"))
        #expect(mediaEngineSource.contains("private let liveKitConnectExecutor: DirectCallLiveKitConnectExecutor"))
        #expect(mediaEngineSource.contains("switch await liveKitConnectExecutor.connectAudio(connectionInfo: connectionInfo, e2eeContext: e2eeContext)"))
    }

    @Test
    func controlledRealBridgeProofFieldsAndTestSeamDefaultNoConnect() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let firstAttemptStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectFirstAttempt")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let firstAttemptSource = String(adapterSource[firstAttemptStart..<summaryStart])

        #expect(adapterSource.contains("var controlledConnectRealBridgePresent = SalemXControlledAudioConnectRealBridge.defaultDisabled.present"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeDebugOnly = SalemXControlledAudioConnectRealBridge.defaultDisabled.debugOnly"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeDefaultDisabled = SalemXControlledAudioConnectRealBridge.defaultDisabled.isDefaultDisabled"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeRequiresCredentials = SalemXControlledAudioConnectRealBridge.defaultDisabled.requiresCredentials"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeRequiresEnablement = SalemXControlledAudioConnectRealBridge.defaultDisabled.requiresEnablement"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeRequiresOperatorApproval = SalemXControlledAudioConnectRealBridge.defaultDisabled.requiresOperatorApproval"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeRequiresFuturePhasePermission = SalemXControlledAudioConnectRealBridge.defaultDisabled.requiresFuturePhasePermission"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeAudioOnly = SalemXControlledAudioConnectRealBridge.defaultDisabled.audioOnly"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeVideoAllowed = SalemXControlledAudioConnectRealBridge.defaultDisabled.videoAllowed"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeMatrixEventsAllowed = SalemXControlledAudioConnectRealBridge.defaultDisabled.matrixEventsAllowed"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeRawCredentialsLogged = SalemXControlledAudioConnectRealBridge.defaultDisabled.rawCredentialsLogged"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeOneShot = SalemXControlledAudioConnectRealBridge.defaultDisabled.oneShot"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeAllowed = SalemXControlledAudioConnectRealBridge.defaultDisabled.allowed"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeBlockedReason = SalemXControlledAudioConnectRealBridge.defaultDisabled.blockedReason"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeBlockedBeforeConnectMedia = SalemXControlledAudioConnectRealBridge.defaultDisabled.blockedBeforeConnectMedia"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeCanCallConnectMediaWhenAllGatesTrue = SalemXControlledAudioConnectRealBridge.defaultDisabled.canCallConnectMediaWhenAllGatesTrue"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeCanCallLiveKitAudioWhenAllGatesTrue = SalemXControlledAudioConnectRealBridge.defaultDisabled.canCallLiveKitAudioWhenAllGatesTrue"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeUsesFakeEngineInTestsOnly = SalemXControlledAudioConnectRealBridge.defaultDisabled.usesFakeEngineInTestsOnly"))
        #expect(adapterSource.contains("var controlledConnectRealBridgeUsesRealRuntimeBoundaryWhenNotTest = SalemXControlledAudioConnectRealBridge.defaultDisabled.usesRealRuntimeBoundaryWhenNotTest"))

        #expect(adapterSource.contains("controlled_connect_real_bridge_present=\\(controlledConnectRealBridgePresent)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_debug_only=\\(controlledConnectRealBridgeDebugOnly)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_default_disabled=\\(controlledConnectRealBridgeDefaultDisabled)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_requires_credentials=\\(controlledConnectRealBridgeRequiresCredentials)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_requires_enablement=\\(controlledConnectRealBridgeRequiresEnablement)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_requires_operator_approval=\\(controlledConnectRealBridgeRequiresOperatorApproval)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_requires_future_phase_permission=\\(controlledConnectRealBridgeRequiresFuturePhasePermission)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_audio_only=\\(controlledConnectRealBridgeAudioOnly)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_video_allowed=\\(controlledConnectRealBridgeVideoAllowed)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_matrix_events_allowed=\\(controlledConnectRealBridgeMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_raw_credentials_logged=\\(controlledConnectRealBridgeRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_one_shot=\\(controlledConnectRealBridgeOneShot)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_allowed=\\(controlledConnectRealBridgeAllowed)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_blocked_reason=\\(controlledConnectRealBridgeBlockedReason)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_blocked_before_connect_media=\\(controlledConnectRealBridgeBlockedBeforeConnectMedia)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_can_call_connect_media_when_all_gates_true=\\(controlledConnectRealBridgeCanCallConnectMediaWhenAllGatesTrue)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_can_call_livekit_audio_when_all_gates_true=\\(controlledConnectRealBridgeCanCallLiveKitAudioWhenAllGatesTrue)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_uses_fake_engine_in_tests_only=\\(controlledConnectRealBridgeUsesFakeEngineInTestsOnly)"))
        #expect(adapterSource.contains("controlled_connect_real_bridge_uses_real_runtime_boundary_when_not_test=\\(controlledConnectRealBridgeUsesRealRuntimeBoundaryWhenNotTest)"))

        #expect(adapterSource.contains("mutating func recordControlledAudioConnectRealBridge(_ realBridge: SalemXControlledAudioConnectRealBridge)"))
        #expect(adapterSource.contains("recordControlledAudioConnectRealBridge(realBridge)"))
        #expect(adapterSource.contains("controlledConnectRealBridgeAllowed"))
        #expect(adapterSource.contains("if realBridge.allowed"))
        #expect(adapterSource.contains("recordControlledAudioConnectFirstAttemptProof(.controlledRealBridgeTestBoundary(realBridge: realBridge"))
        #expect(firstAttemptSource.contains("static func controlledRealBridgeTestBoundary(realBridge: SalemXControlledAudioConnectRealBridge"))
        #expect(firstAttemptSource.contains("realBridge.usesFakeEngineInTestsOnly"))
        #expect(firstAttemptSource.contains("!fakeMediaEngine.usesRealLiveKitNetwork"))
        #expect(firstAttemptSource.contains("mediaConnectRequested: allowed && fakeMediaEngine.mediaConnectRequested"))
        #expect(firstAttemptSource.contains("liveKitJoinRequested: allowed && fakeMediaEngine.liveKitJoinRequested"))
        #expect(firstAttemptSource.contains("liveKitConnectAudioInvoked: allowed && fakeMediaEngine.liveKitConnectAudioInvoked"))
        #expect(firstAttemptSource.contains("static func controlledRealBridgeRuntimeBoundary(realBridge: SalemXControlledAudioConnectRealBridge"))
        #expect(firstAttemptSource.contains("case .success:"))
        #expect(firstAttemptSource.contains("case .failure(let error):"))
        #expect(firstAttemptSource.contains("mediaConnectRequested: realBridge.allowed"))
        #expect(firstAttemptSource.contains("liveKitJoinRequested: realBridge.allowed"))
        #expect(firstAttemptSource.contains("liveKitConnectAudioInvoked: realBridge.allowed"))
        #expect(firstAttemptSource.contains("static func blockedByRealBridge(_ realBridge: SalemXControlledAudioConnectRealBridge)"))
    }

    @Test
    func physical6RuntimeEnablementHookArmsOneShotWithoutSideEffects() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let hookStart = try #require(adapterSource.range(of: "private struct SalemXPhysical6RuntimeEnablementURLHook")?.lowerBound)
        let executionGateStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectExecutionGate")?.lowerBound)
        let hookSource = String(adapterSource[hookStart..<executionGateStart])
        let preflightStart = try #require(adapterSource.range(of: "mutating func recordControlledMediaConnectPreflight")?.lowerBound)
        let rollbackStart = try #require(adapterSource.range(of: "mutating func rollbackControlledConnectActivationProof")?.lowerBound)
        let preflightSource = String(adapterSource[preflightStart..<rollbackStart])
        let credentialsRecordStart = try #require(adapterSource.range(of: "static func recordControlledMediaCredentialsRequest(succeeded: Bool")?.lowerBound)
        let debugEnd = try #require(adapterSource.range(of: "#endif", options: .backwards)?.lowerBound)
        let credentialsRecordSource = String(adapterSource[credentialsRecordStart..<debugEnd])

        #expect(debugGuardStart < hookStart)
        #expect(hookStart < executionGateStart)
        #expect(hookSource.contains("static let defaultDisabledNoConnectReason = \"default_disabled_no_connect\""))
        #expect(hookSource.contains("static let armedWaitingForOneIncomingAnswerReason = \"armed_waiting_for_one_incoming_answer\""))
        #expect(hookSource.contains("static let oneShotConsumedNoConnectReason = \"one_shot_consumed_no_connect\""))
        #expect(hookSource.contains("static let defaultDisabled = SalemXPhysical6RuntimeEnablementURLHook(armed: false, consumed: false)"))
        #expect(hookSource.contains("static let armed = SalemXPhysical6RuntimeEnablementURLHook(armed: true, consumed: false)"))
        #expect(hookSource.contains("let present = true"))
        #expect(hookSource.contains("let debugOnly = true"))
        #expect(hookSource.contains("let isDefaultDisabled = true"))
        #expect(hookSource.contains("let oneShot = true"))
        #expect(hookSource.contains("let audioOnly = true"))
        #expect(hookSource.contains("let videoAllowed = false"))
        #expect(hookSource.contains("let matrixEventsAllowed = false"))
        #expect(hookSource.contains("let rawCredentialsLogged = false"))
        #expect(hookSource.contains("armed && !consumed"))
        #expect(hookSource.contains("oneShotNotConsumed ? .testOnlyEnabled : .defaultDisabled"))
        #expect(hookSource.contains("func consumedCopy() -> SalemXPhysical6RuntimeEnablementURLHook"))

        #expect(adapterSource.contains("private static let physical6RuntimeEnablementURLHookPath = \"/direct-call/physical6-enable-controlled-audio-connect\""))
        #expect(adapterSource.contains("private static var physical6RuntimeEnablementURLHook = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled"))
        #expect(adapterSource.contains("if normalizedPath == physical6RuntimeEnablementURLHookPath"))
        #expect(adapterSource.contains("armPhysical6RuntimeEnablementURLHook()"))
        #expect(adapterSource.contains("private static func armPhysical6RuntimeEnablementURLHook()"))
        #expect(adapterSource.contains("physical6RuntimeEnablementURLHook = .armed"))
        #expect(adapterSource.contains("let pendingSession = receiverControlledRuntimePendingSession"))
        #expect(adapterSource.contains("let pendingConnectionInfo = receiverControlledRuntimePendingConnectionInfo"))
        #expect(adapterSource.contains("summary.recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementURLHook)"))
        #expect(adapterSource.contains("summary.mediaConnectRequested = false"))
        #expect(adapterSource.contains("summary.mediaConnectAttempted = false"))
        #expect(adapterSource.contains("summary.liveKitJoinRequested = false"))
        #expect(adapterSource.contains("summary.liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("summary.microphonePermissionRequested = false"))
        #expect(adapterSource.contains("summary.cameraPermissionRequested = false"))
        #expect(adapterSource.contains("summary.matrixEventEmitRequested = false"))
        #expect(adapterSource.contains("summary.realCallFlowStarted = false"))
        #expect(adapterSource.contains("summary.recordControlledAudioConnectFirstAttemptProof(.defaultDisabled)"))
        #expect(adapterSource.contains("startReceiverControlledRuntimeConnectLeaseIfAllowed(session: pendingSession, connectionInfo: pendingConnectionInfo)"))

        #expect(adapterSource.contains("var physical6RuntimeEnablementURLHookPresent = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.present"))
        #expect(adapterSource.contains("var physical6RuntimeEnablementURLHookDebugOnly = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.debugOnly"))
        #expect(adapterSource.contains("var physical6RuntimeEnablementURLHookDefaultDisabled = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.isDefaultDisabled"))
        #expect(adapterSource.contains("var physical6RuntimeEnablementURLHookArmed = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.armed"))
        #expect(adapterSource.contains("var physical6RuntimeEnablementURLHookConsumed = SalemXPhysical6RuntimeEnablementURLHook.defaultDisabled.consumed"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_present=\\(physical6RuntimeEnablementURLHookPresent)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_debug_only=\\(physical6RuntimeEnablementURLHookDebugOnly)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_default_disabled=\\(physical6RuntimeEnablementURLHookDefaultDisabled)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_armed=\\(physical6RuntimeEnablementURLHookArmed)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_one_shot=\\(physical6RuntimeEnablementURLHookOneShot)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_audio_only=\\(physical6RuntimeEnablementURLHookAudioOnly)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_video_allowed=\\(physical6RuntimeEnablementURLHookVideoAllowed)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_matrix_events_allowed=\\(physical6RuntimeEnablementURLHookMatrixEventsAllowed)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_raw_credentials_logged=\\(physical6RuntimeEnablementURLHookRawCredentialsLogged)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_consumed=\\(physical6RuntimeEnablementURLHookConsumed)"))
        #expect(adapterSource.contains("physical6_runtime_enablement_url_hook_blocked_reason=\\(physical6RuntimeEnablementURLHookBlockedReason)"))

        #expect(preflightSource.contains("physical6RuntimeEnablementHook: SalemXPhysical6RuntimeEnablementURLHook = .defaultDisabled"))
        #expect(preflightSource.contains("recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementHook)"))
        #expect(preflightSource.contains("let receiverControlledRuntimeSessionValidated = (pendingMetadataFetchAuthorized && pendingMetadataFetchResult == \"success_redacted\") ||"))
        #expect(preflightSource.contains("(mediaCredentialsRequestMetadataAvailable && mediaCredentialsResult == \"success_redacted\")"))
        #expect(preflightSource.contains("activationConfiguration: physical6RuntimeEnablementHook.activationConfiguration"))
        #expect(preflightSource.contains("enablementConfiguration: physical6RuntimeEnablementHook.enablementConfiguration"))
        #expect(preflightSource.contains("receiverAppSessionValidated: receiverControlledRuntimeSessionValidated"))
        #expect(preflightSource.contains("oneShotNotConsumed: physical6RuntimeEnablementHook.oneShotNotConsumed"))
        #expect(preflightSource.contains("if controlledConnectFirstAttemptRequested"))
        #expect(preflightSource.contains("recordPhysical6RuntimeEnablementURLHook(physical6RuntimeEnablementHook.consumedCopy())"))
        #expect(!preflightSource.contains("activationConfiguration: .defaultDisabled"))
        #expect(!preflightSource.contains("enablementConfiguration: .defaultDisabled"))

        #expect(credentialsRecordSource.contains("let physical6RuntimeEnablementURLHookSnapshot = physical6RuntimeEnablementURLHook"))
        #expect(credentialsRecordSource.contains("physical6RuntimeEnablementHook: physical6RuntimeEnablementURLHookSnapshot"))
        #expect(credentialsRecordSource.contains("if summary.physical6RuntimeEnablementURLHookConsumed"))
        #expect(credentialsRecordSource.contains("physical6RuntimeEnablementURLHook = physical6RuntimeEnablementURLHookSnapshot.consumedCopy()"))
    }

    @Test
    func controlledAudioConnectActivationPathDefaultsDisabledBeforeSideEffects() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let activationPathStart = try #require(adapterSource.range(of: "private struct SalemXControlledAudioConnectActivationPath")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let activationPathSource = String(adapterSource[activationPathStart..<summaryStart])

        #expect(debugGuardStart < activationPathStart)
        #expect(activationPathStart < summaryStart)
        #expect(activationPathSource.contains("static let activationPathDisabledNoConnectReason = \"activation_path_disabled_no_connect\""))
        #expect(activationPathSource.contains("static func defaultDisabled(receiverAppSessionValidated: Bool, credentialsPresent: Bool) -> SalemXControlledAudioConnectActivationPath"))
        #expect(activationPathSource.contains("receiverAppSessionValidated: receiverAppSessionValidated"))
        #expect(activationPathSource.contains("credentialsPresent: credentialsPresent"))
        #expect(activationPathSource.contains("enablementConfiguration: .defaultDisabled"))
        #expect(activationPathSource.contains("let receiverAppSessionValidated: Bool"))
        #expect(activationPathSource.contains("let credentialsPresent: Bool"))
        #expect(activationPathSource.contains("let enablementConfiguration: SalemXControlledMediaConnectEnablementConfiguration"))
        #expect(activationPathSource.contains("let pathPresent = true"))
        #expect(activationPathSource.contains("let debugOnly = true"))
        #expect(activationPathSource.contains("let isOneShot = true"))
        #expect(activationPathSource.contains("let isDefaultDisabled = true"))
        #expect(activationPathSource.contains("let requiresReceiverSession = true"))
        #expect(activationPathSource.contains("let requiresFreshCredentials = true"))
        #expect(activationPathSource.contains("let requiresEnablement = true"))
        #expect(activationPathSource.contains("let requiresOperatorApproval = true"))
        #expect(activationPathSource.contains("let requiresFuturePhasePermission = true"))
        #expect(activationPathSource.contains("enablementConfiguration.audioOnlyScope"))
        #expect(activationPathSource.contains("enablementConfiguration.videoAllowed"))
        #expect(activationPathSource.contains("enablementConfiguration.matrixEventsAllowed"))
        #expect(activationPathSource.contains("enablementConfiguration.rawCredentialsLogged"))
        #expect(activationPathSource.contains("enablementConfiguration.rollbackAvailable"))
        #expect(activationPathSource.contains("&& receiverAppSessionValidated"))
        #expect(activationPathSource.contains("&& credentialsPresent"))
        #expect(activationPathSource.contains("&& enablementConfiguration.oneShotEnablementEnabled"))
        #expect(activationPathSource.contains("&& enablementConfiguration.operatorApproved"))
        #expect(activationPathSource.contains("&& enablementConfiguration.futureConnectPhasePermitted"))
        #expect(activationPathSource.contains("&& audioOnly"))
        #expect(activationPathSource.contains("&& !videoAllowed"))
        #expect(activationPathSource.contains("&& !matrixEventsAllowed"))
        #expect(activationPathSource.contains("&& !rawCredentialsLogged"))
        #expect(activationPathSource.contains("&& rollbackAvailable"))
        #expect(activationPathSource.contains("&& isOneShot"))
        #expect(activationPathSource.contains("activationAllowed ? \"none\" : Self.activationPathDisabledNoConnectReason"))
        #expect(activationPathSource.contains("var blockedBeforeEngine: Bool"))
        #expect(activationPathSource.contains("var blockedBeforeLiveKitJoin: Bool"))
        #expect(activationPathSource.contains("var blockedBeforePermissions: Bool"))
        #expect(activationPathSource.contains("var blockedBeforeMatrixEvents: Bool"))
        #expect(adapterSource.contains("var controlledAudioConnectActivationPathPresent = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).pathPresent"))
        #expect(adapterSource.contains("var controlledAudioConnectActivationDebugOnly = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).debugOnly"))
        #expect(adapterSource.contains("var controlledAudioConnectActivationOneShot = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).isOneShot"))
        #expect(adapterSource.contains("var controlledAudioConnectActivationDefaultDisabled = SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false).isDefaultDisabled"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_path_present=\\(controlledAudioConnectActivationPathPresent)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_debug_only=\\(controlledAudioConnectActivationDebugOnly)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_one_shot=\\(controlledAudioConnectActivationOneShot)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_default_disabled=\\(controlledAudioConnectActivationDefaultDisabled)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_requires_receiver_session=\\(controlledAudioConnectActivationRequiresReceiverSession)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_requires_fresh_credentials=\\(controlledAudioConnectActivationRequiresFreshCredentials)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_requires_enablement=\\(controlledAudioConnectActivationRequiresEnablement)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_requires_operator_approval=\\(controlledAudioConnectActivationRequiresOperatorApproval)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_requires_future_phase_permission=\\(controlledAudioConnectActivationRequiresFuturePhasePermission)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_audio_only=\\(controlledAudioConnectActivationAudioOnly)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_video_allowed=\\(controlledAudioConnectActivationVideoAllowed)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_matrix_events_allowed=\\(controlledAudioConnectActivationMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_raw_credentials_logged=\\(controlledAudioConnectActivationRawCredentialsLogged)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_rollback_available=\\(controlledAudioConnectActivationRollbackAvailable)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_allowed=\\(controlledAudioConnectActivationAllowed)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_blocked_reason=\\(controlledAudioConnectActivationBlockedReason)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_blocked_before_engine=\\(controlledAudioConnectActivationBlockedBeforeEngine)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_blocked_before_livekit_join=\\(controlledAudioConnectActivationBlockedBeforeLiveKitJoin)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_blocked_before_permissions=\\(controlledAudioConnectActivationBlockedBeforePermissions)"))
        #expect(adapterSource.contains("controlled_audio_connect_activation_blocked_before_matrix_events=\\(controlledAudioConnectActivationBlockedBeforeMatrixEvents)"))
        #expect(adapterSource.contains("let activationPath = SalemXControlledAudioConnectActivationPath(receiverAppSessionValidated: receiverAppSessionValidated"))
        #expect(adapterSource.contains("recordControlledAudioConnectActivationPath(activationPath)"))
        #expect(adapterSource.contains("controlledAudioConnectActivationAllowed &&"))
        #expect(adapterSource.contains("recordControlledAudioConnectActivationPath(SalemXControlledAudioConnectActivationPath.defaultDisabled(receiverAppSessionValidated: false, credentialsPresent: false))"))
        #expect(adapterSource.contains("mutating func recordControlledAudioConnectActivationPath(_ activationPath: SalemXControlledAudioConnectActivationPath)"))
        #expect(adapterSource.contains("controlledAudioConnectActivationAllowed = activationPath.activationAllowed"))
        #expect(adapterSource.contains("controlledAudioConnectActivationBlockedReason = activationPath.blockedReason"))
        #expect(adapterSource.contains("mediaConnectEngineInvoked = false"))
        #expect(adapterSource.contains("liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("media_connect_requested=false"))
        #expect(adapterSource.contains("media_connect_attempted=false"))
        #expect(adapterSource.contains("livekit_join_requested=false"))
        #expect(adapterSource.contains("microphone_permission_requested=false"))
        #expect(adapterSource.contains("camera_permission_requested=false"))
        #expect(adapterSource.contains("matrix_event_emit_requested=false"))
        #expect(adapterSource.contains("real_call_flow_started=false"))
        #expect(adapterSource.contains("connectMediaIfReadyWhenControlledGatesOpen(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>"))
        #expect(adapterSource.contains("await directCallEngine.acceptCall(callID: callID)"))
        #expect(!activationPathSource.contains(".connectAudio("))
        #expect(adapterSource.contains("receiver_audio_permission_request_dispatch_path_available=\\(receiverAudioPermissionRequestDispatchPathAvailable)"))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("emitSignal(type:"))
    }

    @Test
    func controlledConnectActivationWiringDefaultsDisabledAndRollbackReady() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let debugGuardStart = try #require(adapterSource.range(of: "#if DEBUG && canImport(PushKit) && os(iOS)")?.lowerBound)
        let activationConfigurationStart = try #require(adapterSource.range(of: "private struct SalemXControlledMediaConnectActivationConfiguration")?.lowerBound)
        let summaryStart = try #require(adapterSource.range(of: "private struct SalemXVoIPPushReceiptProofSummary")?.lowerBound)
        let activationConfigurationSource = String(adapterSource[activationConfigurationStart..<summaryStart])

        #expect(debugGuardStart < activationConfigurationStart)
        #expect(activationConfigurationStart < summaryStart)
        #expect(adapterSource.contains("static let defaultDisabled = SalemXControlledMediaConnectActivationConfiguration(controlledConnectSwitch: .disabled"))
        #expect(adapterSource.contains("static let rollbackDisabled = defaultDisabled"))
        #expect(adapterSource.contains("let isDefaultDisabled = true"))
        #expect(adapterSource.contains("let requiresOperatorApproval = true"))
        #expect(adapterSource.contains("let rollbackAvailable = true"))
        #expect(adapterSource.contains("var executionAllowed: Bool {\n        isEnabled && operatorApproved\n    }"))
        #expect(adapterSource.contains("activationScope: \"planned_audio_only_redacted\""))
        #expect(adapterSource.contains("videoAllowed: false"))
        #expect(adapterSource.contains("matrixEventsAllowed: false"))
        #expect(adapterSource.contains("rawCredentialsLogged: false"))
        #expect(adapterSource.contains("controlled_connect_activation_wiring_present=\\(controlledConnectActivationWiringPresent)"))
        #expect(adapterSource.contains("controlled_connect_activation_debug_only=\\(controlledConnectActivationDebugOnly)"))
        #expect(adapterSource.contains("controlled_connect_activation_default_disabled=\\(controlledConnectActivationDefaultDisabled)"))
        #expect(adapterSource.contains("controlled_connect_activation_requires_operator_approval=\\(controlledConnectActivationRequiresOperatorApproval)"))
        #expect(adapterSource.contains("controlled_connect_activation_rollback_available=\\(controlledConnectActivationRollbackAvailable)"))
        #expect(adapterSource.contains("controlled_connect_activation_scope=\\(controlledConnectActivationScope)"))
        #expect(adapterSource.contains("controlled_connect_video_allowed=\\(controlledConnectVideoAllowed)"))
        #expect(adapterSource.contains("controlled_connect_matrix_events_allowed=\\(controlledConnectMatrixEventsAllowed)"))
        #expect(adapterSource.contains("controlled_connect_raw_credentials_logged=\\(controlledConnectRawCredentialsLogged)"))
        #expect(adapterSource.contains("recordControlledConnectActivationProof(activationConfiguration)"))
        #expect(adapterSource.contains("recordControlledConnectActivationProof(SalemXControlledMediaConnectActivationConfiguration.rollbackDisabled)"))
        #expect(adapterSource.contains("mediaConnectExecutionAllowed = false"))
        #expect(adapterSource.contains("mediaConnectEngineInvoked = false"))
        #expect(adapterSource.contains("liveKitConnectAudioInvoked = false"))
        #expect(adapterSource.contains("media_connect_requested=false"))
        #expect(adapterSource.contains("media_connect_attempted=false"))
        #expect(adapterSource.contains("livekit_join_requested=false"))
        #expect(adapterSource.contains("microphone_permission_requested=false"))
        #expect(adapterSource.contains("camera_permission_requested=false"))
        #expect(adapterSource.contains("matrix_event_emit_requested=false"))
        #expect(adapterSource.contains("real_call_flow_started=false"))
        #expect(adapterSource.contains("connectMediaIfReadyWhenControlledGatesOpen(callID: String) async -> Result<DirectCallSession, DirectCallEngineError>"))
        #expect(adapterSource.contains("await directCallEngine.acceptCall(callID: callID)"))
        #expect(!activationConfigurationSource.contains(".connectAudio("))
        #expect(adapterSource.contains("receiver_audio_permission_request_dispatch_path_available=\\(receiverAudioPermissionRequestDispatchPathAvailable)"))
        #expect(!adapterSource.contains("AVCaptureDevice.requestAccess"))
        #expect(!adapterSource.contains("emitSignal(type:"))
    }

    @Test
    func foregroundPendingCallMetadataHandoffUsesDirectCallSessionWithoutLoggingIDs() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")
        let roomFlowSource = try Self.sourceFile("ElementX/Sources/FlowCoordinators/RoomFlowCoordinator.swift")
        let signalTransportSource = try Self.sourceFile("ElementX/Sources/Services/Calls/DirectCallSignalTransport.swift")

        #expect(adapterSource.contains("static func recordForegroundPendingCallMetadataCandidate(_ session: DirectCallSession, source: String)"))
        #expect(adapterSource.contains("pendingForegroundCallMetadataMaxAge"))
        #expect(adapterSource.contains("pendingForegroundCallMetadataSession = session"))
        #expect(adapterSource.contains("pendingForegroundCallMetadataSource = source"))
        #expect(adapterSource.contains("recordForegroundPendingCallMetadataHandoffIfAvailable(&summary)"))
        #expect(adapterSource.contains("static func recordForegroundPendingCallMetadataHandoff(_ session: DirectCallSession, source: String)"))
        #expect(adapterSource.contains("summary.recordForegroundPendingCallMetadataHandoff(session: session, source: source)"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataHandoffObserved = true"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataSource = source"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataPayloadRedacted = true"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataHasCallIdentifier = !session.callID.isEmpty"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataHasRoomBinding = !session.roomID.isEmpty"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataHasPeer = !session.peerUserID.isEmpty"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataDirection = String(describing: session.direction)"))
        #expect(adapterSource.contains("foregroundPendingCallMetadataIntent = session.intent.rawValue"))
        #expect(adapterSource.contains("mediaCredentialsRequestMetadataAvailable = foregroundPendingCallMetadataHasCallIdentifier"))
        #expect(adapterSource.contains("mediaCredentialsRequestMetadataRedacted = true"))
        #expect(adapterSource.contains("mediaCredentialsRequestMetadataSource = source"))
        #expect(adapterSource.contains("mediaCredentialsResult = mediaCredentialsRequestMetadataAvailable ? \"metadata_ready_redacted\" : \"metadata_invalid_redacted\""))
        #expect(adapterSource.contains("blockedReason = mediaCredentialsRequestMetadataAvailable ? \"none\" : \"media_credentials_request_metadata_invalid_redacted\""))
        #expect(adapterSource.contains("static func recordControlledMediaCredentialsRequest(succeeded: Bool"))
        #expect(adapterSource.contains("expiresAtPresent: Bool"))
        #expect(roomFlowSource.contains("#if DEBUG"))
        #expect(roomFlowSource.contains("SalemXPushKitRegistrationSmokeDebugBridge.recordForegroundPendingCallMetadataHandoff(session, source: \"production_accept_incoming\")"))
        #expect(roomFlowSource.contains("nativeDirectCallProductionRoomFlowOwner.requestMediaCredentials(callID: session.callID)"))
        #expect(roomFlowSource.contains("SalemXPushKitRegistrationSmokeDebugBridge.recordControlledMediaCredentialsRequest(succeeded: mediaCredentialsSucceeded"))
        #expect(signalTransportSource.contains("SalemXPushKitRegistrationSmokeDebugBridge.recordForegroundPendingCallMetadataCandidate(session"))
        #expect(signalTransportSource.contains("source: \"real_invite_direct_call_session\""))
        #expect(!adapterSource.contains("room_id=\\("))
        #expect(!adapterSource.contains("call_handle=\\("))
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
        let elementCallServiceSource = try Self.sourceFile("ElementX/Sources/Services/ElementCall/ElementCallService.swift")

        #expect(adapterSource.contains("#if DEBUG && canImport(PushKit) && os(iOS)"))
        #expect(adapterSource.contains("startRegistrationUploadSmokeWithCurrentSessionURLString"))
        #expect(adapterSource.contains("startMatrixSessionWhoamiSmokeWithExpectedUserHash"))
        #expect(adapterSource.contains("handleUploadSmokeURL"))
        #expect(adapterSource.contains("salemx-pushkit-token-upload-smoke-proof.txt"))
        #expect(adapterSource.contains("salemx-matrix-session-whoami-proof.txt"))
        #expect(adapterSource.contains("proofSource = \"pushkit_upload_smoke\""))
        #expect(adapterSource.contains("summary.proofLastUpdatedBy = \"pushkit_upload_smoke\""))
        #expect(adapterSource.contains("summary.proofLastUpdatedBy = \"matrix_session_whoami_smoke\""))
        #expect(adapterSource.contains("matrixAccessTokenForPushKitUploadSmoke"))
        #expect(adapterSource.contains("recordElementCallServiceVoIPPushTokenForDebugUpload"))
        #expect(adapterSource.contains("matrixAccessTokenForPushKitUploadSmokeWaitingIfNeeded"))
        #expect(adapterSource.contains("smoke.start(cachedElementCallToken: cachedElementCallServiceVoIPPushTokenForDebugUpload())"))
        #expect(adapterSource.contains("registrationResult: \"cached_element_call_voip_token\""))
        #expect(elementCallServiceSource.contains("SalemXPushKitRegistrationSmokeDebugBridge.recordElementCallServiceVoIPPushTokenForDebugUpload(pushCredentials.token)"))
        #expect(adapterSource.contains("\"B\" + \"earer \" + accessToken"))
        #expect(adapterSource.contains("https://matrix.mertis.kz/_matrix/client/v3/account/whoami"))
        #expect(adapterSource.contains("iphone_app_matrix_session_whoami_result=\\(whoamiResult)"))
        #expect(adapterSource.contains("iphone_app_matrix_session_user_hash=\\(matrixSessionUserHash)"))
        #expect(adapterSource.contains("iphone_app_matrix_session_device_present=\\(matrixSessionDevicePresent)"))
        #expect(adapterSource.contains("iphone_app_pending_metadata_auth_ready=\\(pendingMetadataAuthReady)"))
        Self.assertAppSessionProofRefreshFileSourceGuards(in: adapterSource)
        #expect(adapterSource.contains("APNs_sent=false"))
        #expect(adapterSource.contains("SHA256.hash(data: Data(value.utf8))"))
        #expect(adapterSource.contains("token.map { String(format: \"%02x\", $0) }.joined()"))
        #expect(adapterSource.contains("pushkit_token_redacted=true"))
        #expect(adapterSource.contains("pushkit_token_upload_url_resolved=\\(uploadURLResolved)"))
        #expect(adapterSource.contains("pushkit_token_upload_auth_present=\\(uploadAuthPresent)"))
        #expect(adapterSource.contains("pushkit_token_upload_payload_schema_valid=\\(uploadPayloadSchemaValid)"))
        #expect(adapterSource.contains("pushkit_token_upload_result=\\(uploadResult)"))
        #expect(adapterSource.contains("pushkit_token_upload_http_status_bucket=\\(uploadHTTPStatusBucket)"))
        #expect(adapterSource.contains("httpStatusBucket(response: response, error: error)"))
        #expect(adapterSource.contains("pushkit_token_server_store_result=\\(serverStoreResult)"))
        #expect(adapterSource.contains("pushkit_token_retrieval_internal_check=\\(retrievalInternalCheck)"))
        #expect(adapterSource.contains("pushkit_token_api_exposes_raw_token=\\(tokenAPIExposesRawToken)"))
        #expect(adapterSource.contains("real_pushkit_background_callback_wired=false"))
        #expect(adapterSource.contains("voip_push_send_requested=false"))
        #expect(adapterSource.contains("apns_provider_requested=false"))
        #expect(developerOptionsSource.contains("Start PushKit token upload smoke"))
        #expect(developerOptionsSource.contains("SalemXPushKitRegistrationSmokeDebugBridge.recordSenderDebugBuildLaunchMarker()"))
        #expect(developerOptionsSource.contains("Start Matrix session whoami smoke"))
        #expect(developerOptionsSource.contains("pushKitTokenUploadSmokeProof"))
        #expect(developerOptionsSource.contains("matrixSessionWhoamiSmokeProof"))
        #expect(developerOptionsSource.contains("localCallKitOnlyProof"))
        #expect(developerOptionsSource.contains("redactedLocalCallKitOnlySummary()"))
        #expect(appCoordinatorSource.contains("#if DEBUG && canImport(PushKit) && os(iOS)"))
        #expect(appCoordinatorSource.contains("handleUploadSmokeURL(url)"))
        #expect(!appSessionSource.contains("startRegistrationUploadSmokeWithCurrentSessionURLString"))
        #expect(!appSessionSource.contains("DirectCallPushKitTokenRegistrationClient"))
        #expect(!appSessionSource.contains("registerForRemoteNotifications"))
        #expect(!adapterSource.contains("print("))
    }

    private static func assertAppSessionProofRefreshFileSourceGuards(in adapterSource: String) {
        let refreshConsumerSource: String
        if let refreshConsumerStart = adapterSource.range(of: "private static func startAppSessionProofRefreshFilePolling")?.lowerBound,
           let atomicConsumerStart = adapterSource.range(of: "private static func startSenderAtomicPendingMetadataHandoffTriggerFilePolling")?.lowerBound {
            refreshConsumerSource = String(adapterSource[refreshConsumerStart..<atomicConsumerStart])
        } else {
            refreshConsumerSource = ""
        }

        #expect(adapterSource.contains("private static let appSessionProofRefreshFileName = \"salemx-debug-app-session-proof-refresh.json\""))
        #expect(adapterSource.contains("private static var appSessionProofRefreshFilePollTask: Task<Void, Never>?"))
        #expect(adapterSource.contains("startAppSessionProofRefreshFilePolling()"))
        #expect(adapterSource.contains("consumeAppSessionProofRefreshFileIfNeeded()"))
        #expect(adapterSource.contains("appSessionProofRefreshFileDiagnostics"))
        #expect(adapterSource.contains("app_session_file_refresh_path_bucket=\\(appSessionFileRefreshPathBucket)"))
        #expect(adapterSource.contains("app_session_file_refresh_exists_before_consume=\\(appSessionFileRefreshExistsBeforeConsume)"))
        #expect(adapterSource.contains("app_session_file_refresh_consumer_lifecycle_seen=\\(appSessionFileRefreshConsumerLifecycleSeen)"))
        #expect(adapterSource.contains("app_session_file_refresh_seen=\\(appSessionFileRefreshSeen)"))
        #expect(adapterSource.contains("app_session_file_refresh_shape_bucket=\\(appSessionFileRefreshShapeBucket)"))
        #expect(adapterSource.contains("app_session_file_refresh_consumed=\\(appSessionFileRefreshConsumed)"))
        #expect(adapterSource.contains("app_session_file_refresh_consume_result_bucket=\\(appSessionFileRefreshConsumeResultBucket)"))
        #expect(adapterSource.contains("app_session_proof_write_attempted=\\(appSessionProofWriteAttempted)"))
        #expect(adapterSource.contains("app_session_proof_write_result_bucket=\\(appSessionProofWriteResultBucket)"))
        #expect(adapterSource.contains("app_session_proof_generation=\\(proofGeneration)"))
        #expect(adapterSource.contains("app_matrix_session_whoami_result=\\(whoamiResult)"))
        #expect(adapterSource.contains("app_matrix_session_user_hash=\\(matrixSessionUserHash)"))
        #expect(adapterSource.contains("app_matrix_session_device_present=\\(matrixSessionDevicePresent)"))
        #expect(adapterSource.contains("app_pending_metadata_auth_ready=\\(pendingMetadataAuthReady)"))
        #expect(adapterSource.contains("app_session_proof_raw_identifiers_logged=\\(appSessionProofRawIdentifiersLogged)"))
        #expect(!refreshConsumerSource.isEmpty)
        #expect(refreshConsumerSource.contains("recordAppSessionFileRefreshConsumerLifecycleSeen(pathBucket: appSessionProofRefreshFilePathBucket())"))
        #expect(refreshConsumerSource.contains("recordAppSessionFileRefreshPathChecked(pathBucket: \"documents_unavailable_redacted\""))
        #expect(refreshConsumerSource.contains("recordAppSessionFileRefreshPathChecked(pathBucket: \"documents_redacted\""))
        #expect(refreshConsumerSource.contains("appSessionFileRefreshMissingProofRecorded"))
        #expect(refreshConsumerSource.contains("FileManager.default.fileExists(atPath: refreshURL.path)"))
        #expect(refreshConsumerSource.contains("try FileManager.default.removeItem(at: refreshURL)"))
        #expect(refreshConsumerSource.contains("recordAppSessionFileRefreshSeen(shapeBucket: diagnostics.shapeBucket)"))
        #expect(refreshConsumerSource.contains("recordAppSessionFileRefreshConsumed(resultBucket: \"deleted_redacted\")"))
        #expect(refreshConsumerSource.contains("recordAppSessionFileRefreshConsumed(resultBucket: \"invalid_shape_redacted\")"))
        #expect(refreshConsumerSource.contains("recordAppSessionFileRefreshConsumed(resultBucket: \"delete_failed_redacted\")"))
        #expect(refreshConsumerSource.contains("refreshKind == \"app_session_proof_refresh\""))
        #expect(refreshConsumerSource.contains("markerVersion == \"2.49Z3\""))
        #expect(refreshConsumerSource.contains("command == \"refresh_app_session_proof\""))
        #expect(refreshConsumerSource.contains("\"valid_app_session_proof_refresh_redacted\""))
        #expect(refreshConsumerSource.contains("startMatrixSessionWhoamiSmokeWithExpectedUserHash(diagnostics.expectedUserHash)"))
        #expect(adapterSource.contains("summary.appSessionProofWriteAttempted = true"))
        #expect(adapterSource.contains("summary.appSessionProofWriteResultBucket = \"success_redacted\""))
        #expect(adapterSource.contains("return \"documents_unavailable_redacted\""))
        #expect(adapterSource.contains("return \"write_failed_redacted\""))
        #expect(!refreshConsumerSource.contains("sendRealInvite"))
        #expect(!refreshConsumerSource.contains("postRealInvite"))
        #expect(!refreshConsumerSource.contains("background_apns_push_requested=true"))
        #expect(!refreshConsumerSource.contains("createPendingMetadata"))
        #expect(!refreshConsumerSource.contains("DirectCallLiveKitConnectExecutor"))
        #expect(!refreshConsumerSource.contains("executor.connectAudio"))
        #expect(!refreshConsumerSource.contains("setMicrophoneEnabled(true)"))
        #expect(!refreshConsumerSource.contains("matrixEventEmitRequested = true"))
        #expect(!refreshConsumerSource.contains("cameraPermissionRequested = true"))
        #expect(!refreshConsumerSource.contains("microphonePermissionRequested = true"))
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
    func appSessionPreparePreflightProofUsesCurrentSessionAndStopsBeforeMedia() throws {
        let adapterSource = try Self.sourceFile("ElementX/Sources/Services/Calls/SyntheticCallKitProof/NativeIncomingSyntheticCallKitUIProofAdapter.swift")

        #expect(adapterSource.contains("appSessionPreparePreflightURLHookPath = \"/direct-call/app-session-prepare-preflight\""))
        #expect(adapterSource.contains("appSessionPreparePreflightProofFileName = \"salemx-app-session-prepare-preflight-proof.txt\""))
        #expect(adapterSource.contains("appSessionPreparePreflightRawHandoffFileName = \"salemx-app-session-prepare-preflight-raw-handoff.txt\""))
        #expect(adapterSource.contains("host_matrix_api_token_used=false"))
        #expect(adapterSource.contains("prepare_route_auth_source_bucket=\\(prepareRouteAuthSourceBucket)"))
        #expect(adapterSource.contains("prepareRouteAuthSourceBucket = \"current_app_session_redacted\""))
        #expect(adapterSource.contains("invitePrepareEndpointPath"))
        #expect(adapterSource.contains("\"type\": \"m.room.encryption\""))
        #expect(adapterSource.contains("\"algorithm\": \"m.megolm.v1.aes-sha2\""))
        #expect(adapterSource.contains("server_side_sender_metadata_claim_result_bucket=\\(serverSideSenderMetadataClaimResultBucket)"))
        #expect(adapterSource.contains("sender_media_credentials_result_bucket=\\(senderMediaCredentialsResultBucket)"))
        #expect(adapterSource.contains("APNs_sent=\\(apnsSent)"))
        #expect(adapterSource.contains("livekit_join_triggered=false"))
        #expect(adapterSource.contains("permissions_requested=false"))
        #expect(adapterSource.contains("local_audio_track_published=false"))
        #expect(adapterSource.contains("local_video_track_published=false"))
        #expect(adapterSource.contains("matrix_call_media_event_emitted=false"))
        #expect(adapterSource.contains("full_flow_started=false"))
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
private final class MediaEngineSpy: DirectCallMediaEngineProtocol, DirectCallMediaCredentialsBoundaryRequesting {
    private let mediaStateSubject = CurrentValueSubject<DirectCallMediaState, Never>(.idle)
    private let connectResult: Result<DirectCallMediaState, DirectCallMediaError>
    private let credentialsResult: Result<DirectCallMediaConnectionInfo, DirectCallMediaError>

    private(set) var requestedCredentialSessions = [DirectCallSession]()
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
                                                                                            isE2EEReady: true)),
         credentialsResult: Result<DirectCallMediaConnectionInfo, DirectCallMediaError> = .failure(.tokenUnavailable)) {
        self.connectResult = connectResult
        self.credentialsResult = credentialsResult
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

    func requestMediaCredentials(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        requestedCredentialSessions.append(session)
        return credentialsResult
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
