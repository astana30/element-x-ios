//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
final class DirectCallEngine: DirectCallEngineProtocol {
    var activeSessionPublisher: CurrentValuePublisher<DirectCallSession?, Never> {
        activeSessionSubject.asCurrentValuePublisher()
    }

    var actionsPublisher: AnyPublisher<DirectCallEngineAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    #if DEBUG
    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        (mediaEngine as? DirectCallMediaDiagnosticSnapshotProviding)?.diagnosticSnapshot ?? .empty
    }
    #endif

    private let ownUserID: String
    private let expectedPeerProvider: (String) -> String?
    private let configuration: DirectCallEngineConfiguration
    private let now: () -> Date
    private let encryptionService: DirectCallEncryptionServiceProtocol
    private let mediaEngine: DirectCallMediaEngineProtocol

    private var knownPeerByRoomID = [String: String]()
    private var mediaKeyHandlesByCallID = [String: DirectCallMediaKeyHandle]()
    private var keyClearedCallIDs = Set<String>()
    private var mediaDisconnectedCallIDs = Set<String>()
    private var mediaCleanedCallIDs = Set<String>()

    private var activeSessionSubject = CurrentValueSubject<DirectCallSession?, Never>(nil)
    private let actionsSubject = PassthroughSubject<DirectCallEngineAction, Never>()

    private var outgoingTimeoutTask: Task<Void, Never>?
    private var incomingTimeoutTask: Task<Void, Never>?
    private var connectingTimeoutTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?

    private var processedTerminalEventIDs = Set<String>()
    private var processedTerminalEventOrder = [String]()

    init(ownUserID: String,
         configuration: DirectCallEngineConfiguration = .init(),
         now: @escaping () -> Date = Date.init,
         encryptionService: DirectCallEncryptionServiceProtocol? = nil,
         mediaEngine: DirectCallMediaEngineProtocol? = nil,
         mediaEngineFactory: DirectCallMediaEngineFactoryProtocol? = nil,
         expectedPeerProvider: @escaping (String) -> String?) {
        self.ownUserID = ownUserID
        self.configuration = configuration
        self.now = now
        self.encryptionService = encryptionService ?? NoOpDirectCallEncryptionService()
        self.mediaEngine = Self.makeMediaEngine(mediaEngine: mediaEngine, mediaEngineFactory: mediaEngineFactory)
        self.expectedPeerProvider = expectedPeerProvider
    }

    deinit {
        outgoingTimeoutTask?.cancel()
        incomingTimeoutTask?.cancel()
        connectingTimeoutTask?.cancel()
        cleanupTask?.cancel()
    }

    func startOutgoingAudioCall(peer: String, roomID: String) async -> Result<DirectCallSession, DirectCallEngineError> {
        await startOutgoingCall(peer: peer, roomID: roomID, intent: .audio)
    }

    func startOutgoingVideoCall(peer: String, roomID: String) async -> Result<DirectCallSession, DirectCallEngineError> {
        await startOutgoingCall(peer: peer, roomID: roomID, intent: .video)
    }

    func receiveIncomingCall(event: DirectCallSignalEvent) async -> Result<DirectCallSession?, DirectCallEngineError> {
        if let error = validateIncomingEvent(event) {
            return .failure(error)
        }

        switch event.type {
        case .invite:
            guard let intent = event.intent else {
                return .failure(.invalidIntent)
            }
            return await handleIncomingInvite(event: event, intent: intent)
        case .answer:
            return await handleIncomingAnswer(event: event)
        case .reject, .cancel, .hangup, .timeout:
            return await handleIncomingTerminalEvent(event)
        }
    }

    func acceptCall(callID: String) async -> Result<DirectCallSession, DirectCallEngineError> {
        guard !callID.isEmpty else {
            return .failure(.invalidCallID)
        }

        guard var session = activeSessionSubject.value,
              session.callID == callID,
              session.state == .incomingRinging else {
            return .failure(.invalidTransition)
        }

        transitionSession(to: .connecting)
        emitSignal(type: .answer, from: session)
        scheduleConnectingTimeout(for: session.callID)

        session = activeSessionSubject.value ?? session
        if let keyHandle = mediaKeyHandlesByCallID[session.callID] {
            return await connectMediaIfReady(for: session, keyHandle: keyHandle)
        }

        return .success(session)
    }

    func rejectCall(callID: String) async -> Result<DirectCallSession, DirectCallEngineError> {
        guard !callID.isEmpty else {
            return .failure(.invalidCallID)
        }

        guard var session = activeSessionSubject.value,
              session.callID == callID,
              session.state == .incomingRinging else {
            return .failure(.invalidTransition)
        }

        transitionSession(to: .ending)
        emitSignal(type: .reject, from: session)
        transitionSession(to: .cancelled)
        await disconnectMediaIfNeeded(callID: session.callID)
        scheduleCleanup(for: session.callID)

        session = activeSessionSubject.value ?? session
        return .success(session)
    }

    func cancelOutgoingBeforeAnswer(callID: String) async -> Result<DirectCallSession, DirectCallEngineError> {
        guard !callID.isEmpty else {
            return .failure(.invalidCallID)
        }

        guard var session = activeSessionSubject.value,
              session.callID == callID,
              session.state == .outgoingRinging else {
            return .failure(.invalidTransition)
        }

        transitionSession(to: .ending)
        emitSignal(type: .cancel, from: session)
        transitionSession(to: .cancelled)
        await disconnectMediaIfNeeded(callID: session.callID)
        scheduleCleanup(for: session.callID)

        session = activeSessionSubject.value ?? session
        return .success(session)
    }

    func hangupActiveCall(callID: String) async -> Result<DirectCallSession, DirectCallEngineError> {
        guard !callID.isEmpty else {
            return .failure(.invalidCallID)
        }

        guard var session = activeSessionSubject.value,
              session.callID == callID,
              session.state == .activeAudio || session.state == .activeVideo || session.state == .connecting else {
            return .failure(.invalidTransition)
        }

        transitionSession(to: .ending)
        emitSignal(type: .hangup, from: session)
        transitionSession(to: .ended)
        await disconnectMediaIfNeeded(callID: session.callID)
        scheduleCleanup(for: session.callID)

        session = activeSessionSubject.value ?? session
        return .success(session)
    }

    func markEncryptionEstablished(callID: String, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallSession, DirectCallEngineError> {
        guard !callID.isEmpty else {
            return .failure(.invalidCallID)
        }

        guard keyHandle.callID == callID, !keyHandle.keyID.isEmpty else {
            return .failure(.invalidEncryptionTransition)
        }

        guard let session = activeSessionSubject.value,
              session.callID == callID,
              !session.state.isTerminal else {
            return .failure(.invalidEncryptionTransition)
        }

        switch session.encryptionState {
        case .ready:
            mediaKeyHandlesByCallID[callID] = keyHandle
            guard session.state == .connecting else {
                return .success(session)
            }
            return await connectMediaIfReady(for: session, keyHandle: keyHandle)
        case .failed:
            return .failure(.invalidEncryptionTransition)
        case .pending:
            mediaKeyHandlesByCallID[callID] = keyHandle
            updateSession { updated in
                updated.encryptionState = .ready
            }
            guard let updatedSession = activeSessionSubject.value else {
                return .failure(.invalidEncryptionTransition)
            }
            guard updatedSession.state == .connecting else {
                return .success(updatedSession)
            }
            return await connectMediaIfReady(for: updatedSession, keyHandle: keyHandle)
        }
    }

    private func connectMediaIfReady(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallSession, DirectCallEngineError> {
        guard session.callID == activeSessionSubject.value?.callID,
              session.state == .connecting,
              session.encryptionState == .ready,
              keyHandle.callID == session.callID,
              !keyHandle.keyID.isEmpty else {
            return .failure(.invalidEncryptionTransition)
        }

        guard session.intent == .audio else {
            transitionSession(to: .failed)
            await cleanupMediaIfNeeded(callID: session.callID)
            scheduleCleanup(for: session.callID)
            return .failure(.mediaConnectionFailed)
        }

        switch await mediaEngine.connectAudio(for: session, keyHandle: keyHandle) {
        case .success:
            connectingTimeoutTask?.cancel()
            transitionSession(to: .activeAudio)
            guard let activeSession = activeSessionSubject.value else {
                return .failure(.invalidTransition)
            }
            return .success(activeSession)
        case .failure:
            transitionSession(to: .failed)
            await cleanupMediaIfNeeded(callID: session.callID)
            scheduleCleanup(for: session.callID)
            guard activeSessionSubject.value != nil else {
                return .failure(.mediaConnectionFailed)
            }
            return .failure(.mediaConnectionFailed)
        }
    }

    func markEncryptionFailed(callID: String, reason: DirectCallEncryptionFailureReason) async -> Result<DirectCallSession, DirectCallEngineError> {
        guard !callID.isEmpty else {
            return .failure(.invalidCallID)
        }

        guard let session = activeSessionSubject.value,
              session.callID == callID else {
            return .failure(.invalidEncryptionTransition)
        }

        if session.state.isTerminal {
            return .success(session)
        }

        updateSession { updated in
            updated.encryptionState = .failed(reason)
        }

        transitionSession(to: .failed)
        await disconnectMediaIfNeeded(callID: callID)
        scheduleCleanup(for: callID)

        guard let updatedSession = activeSessionSubject.value else {
            return .failure(.invalidEncryptionTransition)
        }
        return .success(updatedSession)
    }

    func timeoutIncoming(callID: String) async -> Result<DirectCallSession, DirectCallEngineError> {
        guard !callID.isEmpty else {
            return .failure(.invalidCallID)
        }

        guard var session = activeSessionSubject.value,
              session.callID == callID,
              session.state == .incomingRinging else {
            return .failure(.invalidTransition)
        }

        transitionSession(to: .missed)
        await disconnectMediaIfNeeded(callID: session.callID)
        scheduleCleanup(for: session.callID)

        session = activeSessionSubject.value ?? session
        return .success(session)
    }

    func cleanupCall(callID: String) async {
        guard let session = activeSessionSubject.value,
              session.callID == callID,
              session.state.isTerminal else {
            return
        }

        clearPerCallKeyIfNeeded(callID: callID)
        await cleanupMediaIfNeeded(callID: callID)
        mediaKeyHandlesByCallID.removeValue(forKey: callID)
        cancelAllTasks()
        activeSessionSubject.send(nil)
        actionsSubject.send(.sessionCleared(callID: session.callID, roomID: session.roomID))
    }

    private func startOutgoingCall(peer: String,
                                   roomID: String,
                                   intent: DirectCallIntent) async -> Result<DirectCallSession, DirectCallEngineError> {
        guard !roomID.isEmpty else {
            return .failure(.invalidRoomID)
        }

        guard !peer.isEmpty, peer != ownUserID else {
            return .failure(.invalidPeer)
        }

        if let activeSession = activeSessionSubject.value,
           !activeSession.state.isTerminal {
            return .failure(.sessionAlreadyActive)
        }

        if let activeSession = activeSessionSubject.value,
           activeSession.state.isTerminal {
            clearPerCallKeyIfNeeded(callID: activeSession.callID)
            await cleanupMediaIfNeeded(callID: activeSession.callID)
        }

        knownPeerByRoomID[roomID] = peer
        cancelAllTasks()

        let timestamp = now()
        let callID = UUID().uuidString
        let generatedKeyExchange: DirectCallGeneratedKeyExchange
        switch await encryptionService.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peer) {
        case .success(let keyExchange):
            guard isGeneratedKeyExchangeValid(keyExchange, callID: callID, roomID: roomID) else {
                return .failure(.invalidEncryptionTransition)
            }
            generatedKeyExchange = keyExchange
        case .failure:
            return .failure(.invalidEncryptionTransition)
        }

        mediaKeyHandlesByCallID[callID] = generatedKeyExchange.keyHandle
        let session = DirectCallSession(callID: callID,
                                        roomID: roomID,
                                        peerUserID: peer,
                                        direction: .outgoing,
                                        intent: intent,
                                        encryptionMode: .e2eeRequired,
                                        startedAt: timestamp,
                                        updatedAt: timestamp,
                                        state: .outgoingRinging,
                                        encryptionState: .ready)
        publish(session)
        emitSignal(type: .invite, from: session, keyExchange: generatedKeyExchange.payload)
        scheduleOutgoingTimeout(for: session.callID)
        return .success(session)
    }

    private func validateIncomingEvent(_ event: DirectCallSignalEvent) -> DirectCallEngineError? {
        guard !event.roomID.isEmpty else {
            return .invalidRoomID
        }

        guard !event.callID.isEmpty else {
            return .invalidCallID
        }

        guard event.senderID != ownUserID else {
            return .invalidSender
        }

        guard let expectedPeer = expectedPeer(for: event.roomID),
              expectedPeer == event.senderID else {
            return .invalidSender
        }

        return nil
    }

    private func handleIncomingInvite(event: DirectCallSignalEvent,
                                      intent: DirectCallIntent) async -> Result<DirectCallSession?, DirectCallEngineError> {
        if let activeSession = activeSessionSubject.value,
           !activeSession.state.isTerminal {
            if activeSession.callID == event.callID, activeSession.roomID == event.roomID {
                return .success(activeSession)
            }

            return .failure(.sessionAlreadyActive)
        }

        if let activeSession = activeSessionSubject.value,
           activeSession.state.isTerminal {
            clearPerCallKeyIfNeeded(callID: activeSession.callID)
            await cleanupMediaIfNeeded(callID: activeSession.callID)
        }

        knownPeerByRoomID[event.roomID] = event.senderID
        cancelAllTasks()

        guard let keyExchange = event.keyExchange else {
            return .failure(.invalidEncryptionTransition)
        }

        let keyHandle: DirectCallMediaKeyHandle
        switch await encryptionService.consumeRemoteEncryptedKey(keyExchange,
                                                                 expectedCallID: event.callID,
                                                                 expectedRoomID: event.roomID,
                                                                 expectedSenderUserID: event.senderID) {
        case .success(let consumedKeyHandle):
            guard consumedKeyHandle.callID == event.callID, !consumedKeyHandle.keyID.isEmpty else {
                return .failure(.invalidEncryptionTransition)
            }
            keyHandle = consumedKeyHandle
        case .failure:
            return .failure(.invalidEncryptionTransition)
        }

        mediaKeyHandlesByCallID[event.callID] = keyHandle
        let timestamp = now()
        let session = DirectCallSession(callID: event.callID,
                                        roomID: event.roomID,
                                        peerUserID: event.senderID,
                                        direction: .incoming,
                                        intent: intent,
                                        encryptionMode: .e2eeRequired,
                                        startedAt: timestamp,
                                        updatedAt: timestamp,
                                        state: .incomingRinging,
                                        encryptionState: .ready)
        publish(session)
        scheduleIncomingTimeout(for: session.callID)
        return .success(session)
    }

    private func handleIncomingAnswer(event: DirectCallSignalEvent) async -> Result<DirectCallSession?, DirectCallEngineError> {
        guard let session = activeSessionSubject.value else {
            return .failure(.staleOrUnknownEvent)
        }

        guard session.roomID == event.roomID else {
            return .failure(.roomMismatch)
        }

        guard session.callID == event.callID else {
            return .failure(.callIDMismatch)
        }

        guard session.state == .outgoingRinging else {
            return .failure(.invalidTransition)
        }

        transitionSession(to: .connecting)
        scheduleConnectingTimeout(for: session.callID)

        guard let updatedSession = activeSessionSubject.value else {
            return .failure(.invalidTransition)
        }

        guard let keyHandle = mediaKeyHandlesByCallID[session.callID] else {
            transitionSession(to: .failed)
            await cleanupMediaIfNeeded(callID: session.callID)
            scheduleCleanup(for: session.callID)
            return .failure(.invalidEncryptionTransition)
        }

        switch await connectMediaIfReady(for: updatedSession, keyHandle: keyHandle) {
        case .success(let connectedSession):
            return .success(connectedSession)
        case .failure(let error):
            return .failure(error)
        }
    }

    private func handleIncomingTerminalEvent(_ event: DirectCallSignalEvent) async -> Result<DirectCallSession?, DirectCallEngineError> {
        guard let session = activeSessionSubject.value else {
            return .failure(.staleOrUnknownEvent)
        }

        guard session.roomID == event.roomID else {
            return .failure(.roomMismatch)
        }

        guard session.callID == event.callID else {
            return .failure(.callIDMismatch)
        }

        if session.state.isTerminal {
            _ = markTerminalEventAsProcessed(eventID: event.eventID)
            return .success(session)
        }

        if !markTerminalEventAsProcessed(eventID: event.eventID) {
            return .success(session)
        }

        let terminalState: DirectCallState = switch event.type {
        case .timeout:
            .missed
        case .reject, .cancel:
            .cancelled
        case .hangup:
            .ended
        case .invite, .answer:
            .failed
        }

        transitionSession(to: .ending)
        transitionSession(to: terminalState)
        await disconnectMediaIfNeeded(callID: session.callID)
        scheduleCleanup(for: session.callID)
        return .success(activeSessionSubject.value)
    }

    private func expectedPeer(for roomID: String) -> String? {
        knownPeerByRoomID[roomID] ?? expectedPeerProvider(roomID)
    }

    private func markTerminalEventAsProcessed(eventID: String) -> Bool {
        guard !eventID.isEmpty else {
            return false
        }

        if processedTerminalEventIDs.contains(eventID) {
            return false
        }

        processedTerminalEventIDs.insert(eventID)
        processedTerminalEventOrder.append(eventID)

        let overflow = processedTerminalEventOrder.count - configuration.processedTerminalEventLimit
        if overflow > 0 {
            let removedIDs = processedTerminalEventOrder.prefix(overflow)
            processedTerminalEventOrder.removeFirst(overflow)
            for removedID in removedIDs {
                processedTerminalEventIDs.remove(removedID)
            }
        }

        return true
    }

    private func publish(_ session: DirectCallSession) {
        activeSessionSubject.send(session)
        actionsSubject.send(.stateChanged(session))
    }

    private func updateSession(_ update: (inout DirectCallSession) -> Void) {
        guard var session = activeSessionSubject.value else {
            return
        }

        let previous = session
        update(&session)

        if previous == session {
            return
        }

        session.updatedAt = now()
        publish(session)
    }

    private func emitSignal(type: DirectCallSignalType,
                            from session: DirectCallSession,
                            keyExchange: DirectCallEncryptedKeyExchangePayload? = nil) {
        actionsSubject.send(.emitSignal(.init(roomID: session.roomID,
                                              peerUserID: session.peerUserID,
                                              callID: session.callID,
                                              type: type,
                                              intent: type == .invite ? session.intent : nil,
                                              keyExchange: keyExchange)))
    }

    private func isGeneratedKeyExchangeValid(_ keyExchange: DirectCallGeneratedKeyExchange,
                                             callID: String,
                                             roomID: String) -> Bool {
        keyExchange.keyHandle.callID == callID &&
            !keyExchange.keyHandle.keyID.isEmpty &&
            keyExchange.payload.callID == callID &&
            keyExchange.payload.roomID == roomID &&
            keyExchange.payload.senderUserID == ownUserID &&
            keyExchange.payload.keyID == keyExchange.keyHandle.keyID &&
            !keyExchange.payload.encryptedPayload.isEmpty
    }

    private func transitionSession(to state: DirectCallState) {
        guard var session = activeSessionSubject.value else {
            return
        }

        guard session.state != state else {
            return
        }

        session.state = state
        session.updatedAt = now()
        publish(session)
    }

    private func scheduleOutgoingTimeout(for callID: String) {
        outgoingTimeoutTask?.cancel()
        outgoingTimeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: configuration.outgoingRingingTimeout)
            await handleOutgoingTimeout(callID: callID)
        }
    }

    private func scheduleIncomingTimeout(for callID: String) {
        incomingTimeoutTask?.cancel()
        incomingTimeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: configuration.incomingRingingTimeout)
            _ = await timeoutIncoming(callID: callID)
        }
    }

    private func scheduleConnectingTimeout(for callID: String) {
        connectingTimeoutTask?.cancel()
        connectingTimeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: configuration.connectingTimeout)
            await handleConnectingTimeout(callID: callID)
        }
    }

    private func scheduleCleanup(for callID: String) {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: configuration.cleanupDelay)
            await cleanupCall(callID: callID)
        }
    }

    private func handleOutgoingTimeout(callID: String) async {
        guard let session = activeSessionSubject.value,
              session.callID == callID,
              session.state == .outgoingRinging else {
            return
        }

        transitionSession(to: .failed)
        await disconnectMediaIfNeeded(callID: session.callID)
        scheduleCleanup(for: session.callID)
    }

    private func handleConnectingTimeout(callID: String) async {
        guard let session = activeSessionSubject.value,
              session.callID == callID,
              session.state == .connecting else {
            return
        }

        transitionSession(to: .failed)
        await disconnectMediaIfNeeded(callID: session.callID)
        scheduleCleanup(for: session.callID)
    }

    private func cancelAllTasks() {
        outgoingTimeoutTask?.cancel()
        incomingTimeoutTask?.cancel()
        connectingTimeoutTask?.cancel()
        cleanupTask?.cancel()
    }

    private func disconnectMediaIfNeeded(callID: String) async {
        guard !callID.isEmpty, mediaDisconnectedCallIDs.insert(callID).inserted else {
            return
        }

        await mediaEngine.disconnect(callID: callID)
    }

    private func cleanupMediaIfNeeded(callID: String) async {
        guard !callID.isEmpty, mediaCleanedCallIDs.insert(callID).inserted else {
            return
        }

        await mediaEngine.cleanup(callID: callID)
    }

    private func clearPerCallKeyIfNeeded(callID: String) {
        guard !callID.isEmpty else {
            return
        }

        guard keyClearedCallIDs.insert(callID).inserted else {
            return
        }

        encryptionService.clearPerCallKey(callID: callID)
        mediaKeyHandlesByCallID.removeValue(forKey: callID)
    }

    private static func makeMediaEngine(mediaEngine: DirectCallMediaEngineProtocol?,
                                        mediaEngineFactory: DirectCallMediaEngineFactoryProtocol?) -> DirectCallMediaEngineProtocol {
        if let mediaEngine {
            return mediaEngine
        }

        guard let mediaEngineFactory else {
            #if DEBUG
            return makeFallbackMediaEngine(reason: .factoryUnavailable)
            #else
            return makeFallbackMediaEngine()
            #endif
        }

        switch mediaEngineFactory.makeMediaEngine() {
        case .success(let mediaEngine):
            return mediaEngine
        case .failure(let error):
            #if DEBUG
            return makeFallbackMediaEngine(reason: .init(error))
            #else
            return makeFallbackMediaEngine()
            #endif
        }
    }

    private static func makeFallbackMediaEngine() -> DirectCallMediaEngineProtocol {
        NoOpDirectCallMediaEngine()
    }

    #if DEBUG
    private static func makeFallbackMediaEngine(reason: DirectCallDiagnosticMediaFailureReason) -> DirectCallMediaEngineProtocol {
        NoOpDirectCallMediaEngine(diagnosticFailureReason: reason)
    }
    #endif
}

#if DEBUG
extension DirectCallEngine: DirectCallMediaDiagnosticSnapshotProviding { }
#endif
