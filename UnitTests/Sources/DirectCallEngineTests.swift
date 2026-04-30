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
        #expect(engine.activeSessionPublisher.value?.state == .connecting)

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
    func acceptCallDoesNotBecomeActiveBeforeEncryptionReady() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        _ = await engine.receiveIncomingCall(event: .init(eventID: "$invite",
                                                          roomID: roomID,
                                                          senderID: peerUserID,
                                                          callID: "call-a",
                                                          type: .invite,
                                                          intent: .audio,
                                                          timestamp: .now))

        let result = await engine.acceptCall(callID: "call-a")

        guard case .success(let session) = result else {
            Issue.record("Expected incoming call accept to succeed.")
            return
        }

        #expect(session.state == .connecting)
        #expect(session.encryptionState == .pending)
        #expect(mediaEngine.connectedSessions.isEmpty)
    }

    @Test
    func incomingAnswerDoesNotBecomeActiveBeforeEncryptionReady() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        guard let session = await startOutgoingAndReceiveAnswer(engine: engine) else {
            return
        }

        #expect(session.state == .connecting)
        #expect(session.encryptionState == .pending)
        #expect(mediaEngine.connectedSessions.isEmpty)
    }

    @Test
    func markEncryptionEstablishedConnectsMediaAndActivatesCurrentCall() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        guard let connectingSession = await startOutgoingAndReceiveAnswer(engine: engine) else {
            return
        }

        let keyHandle = DirectCallMediaKeyHandle(callID: connectingSession.callID, keyID: "key-a")
        let result = await engine.markEncryptionEstablished(callID: connectingSession.callID, keyHandle: keyHandle)

        guard case .success(let activeSession) = result else {
            Issue.record("Expected E2EE-ready media connect to succeed.")
            return
        }

        #expect(activeSession.state == .activeAudio)
        #expect(activeSession.encryptionState == .ready)
        #expect(mediaEngine.connectedSessions.map(\.callID) == [connectingSession.callID])
        #expect(mediaEngine.connectedKeyHandles == [keyHandle])
    }

    @Test
    func mediaConnectFailureFailsClosedAndCleansUp() async {
        let mediaEngine = MediaEngineSpy(connectResult: .failure(.mediaSetupUnavailable))
        let engine = makeEngine(mediaEngine: mediaEngine)

        guard let connectingSession = await startOutgoingAndReceiveAnswer(engine: engine) else {
            return
        }

        let result = await engine.markEncryptionEstablished(callID: connectingSession.callID,
                                                            keyHandle: .init(callID: connectingSession.callID, keyID: "key-a"))

        #expect(result == .failure(.mediaConnectionFailed))
        #expect(engine.activeSessionPublisher.value?.state == .failed)
        #expect(mediaEngine.cleanupCallIDs == [connectingSession.callID])
    }

    @Test
    func wrongKeyHandleDoesNotConnectMedia() async {
        let mediaEngine = MediaEngineSpy()
        let engine = makeEngine(mediaEngine: mediaEngine)

        guard let connectingSession = await startOutgoingAndReceiveAnswer(engine: engine) else {
            return
        }

        let result = await engine.markEncryptionEstablished(callID: connectingSession.callID,
                                                            keyHandle: .init(callID: "other-call", keyID: "key-a"))

        #expect(result == .failure(.invalidEncryptionTransition))
        #expect(engine.activeSessionPublisher.value?.state == .connecting)
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

        let result = await engine.markEncryptionEstablished(callID: startedSession.callID,
                                                            keyHandle: .init(callID: startedSession.callID, keyID: "key-a"))

        #expect(result == .failure(.mediaConnectionFailed))
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
                                                                            timestamp: .now))

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
                            cleanupDelay: Duration = .milliseconds(20)) -> DirectCallEngine {
        DirectCallEngine(ownUserID: ownUserID,
                         configuration: .init(incomingRingingTimeout: .seconds(120),
                                              outgoingRingingTimeout: .seconds(120),
                                              connectingTimeout: .seconds(120),
                                              cleanupDelay: cleanupDelay,
                                              processedTerminalEventLimit: 64),
                         encryptionService: encryptionService ?? NoOpDirectCallEncryptionService(),
                         mediaEngine: mediaEngine) { [roomID, peerUserID] id in
            id == roomID ? peerUserID : nil
        }
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
        guard let connectingSession = await startOutgoingAndReceiveAnswer(engine: engine) else {
            return nil
        }

        let result = await engine.markEncryptionEstablished(callID: connectingSession.callID,
                                                            keyHandle: .init(callID: connectingSession.callID, keyID: "key-a"))
        guard case .success(let activeSession) = result else {
            Issue.record("Expected media connect to activate audio call.")
            return nil
        }

        return activeSession
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
