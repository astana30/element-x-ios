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

    private let ownUserID: String
    private let expectedPeerProvider: (String) -> String?
    private let configuration: DirectCallEngineConfiguration
    private let now: () -> Date

    private var knownPeerByRoomID = [String: String]()

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
         expectedPeerProvider: @escaping (String) -> String?) {
        self.ownUserID = ownUserID
        self.configuration = configuration
        self.now = now
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
            return handleIncomingInvite(event: event, intent: intent)
        case .answer:
            return handleIncomingAnswer(event: event)
        case .reject, .cancel, .hangup, .timeout:
            return handleIncomingTerminalEvent(event)
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
        transitionSession(to: session.intent == .video ? .activeVideo : .activeAudio)
        scheduleConnectingTimeout(for: session.callID)

        session = activeSessionSubject.value ?? session
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
        scheduleCleanup(for: session.callID)

        session = activeSessionSubject.value ?? session
        return .success(session)
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

        knownPeerByRoomID[roomID] = peer
        cancelAllTasks()

        let timestamp = now()
        let session = DirectCallSession(callID: UUID().uuidString,
                                        roomID: roomID,
                                        peerUserID: peer,
                                        direction: .outgoing,
                                        intent: intent,
                                        startedAt: timestamp,
                                        updatedAt: timestamp,
                                        state: .outgoingRinging)
        publish(session)
        emitSignal(type: .invite, from: session)
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
                                      intent: DirectCallIntent) -> Result<DirectCallSession?, DirectCallEngineError> {
        if let activeSession = activeSessionSubject.value,
           !activeSession.state.isTerminal {
            if activeSession.callID == event.callID, activeSession.roomID == event.roomID {
                return .success(activeSession)
            }

            return .failure(.sessionAlreadyActive)
        }

        knownPeerByRoomID[event.roomID] = event.senderID
        cancelAllTasks()

        let timestamp = now()
        let session = DirectCallSession(callID: event.callID,
                                        roomID: event.roomID,
                                        peerUserID: event.senderID,
                                        direction: .incoming,
                                        intent: intent,
                                        startedAt: timestamp,
                                        updatedAt: timestamp,
                                        state: .incomingRinging)
        publish(session)
        scheduleIncomingTimeout(for: session.callID)
        return .success(session)
    }

    private func handleIncomingAnswer(event: DirectCallSignalEvent) -> Result<DirectCallSession?, DirectCallEngineError> {
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
        transitionSession(to: session.intent == .video ? .activeVideo : .activeAudio)
        return .success(activeSessionSubject.value)
    }

    private func handleIncomingTerminalEvent(_ event: DirectCallSignalEvent) -> Result<DirectCallSession?, DirectCallEngineError> {
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

    private func emitSignal(type: DirectCallSignalType, from session: DirectCallSession) {
        actionsSubject.send(.emitSignal(.init(roomID: session.roomID,
                                              peerUserID: session.peerUserID,
                                              callID: session.callID,
                                              type: type,
                                              intent: type == .invite ? session.intent : nil)))
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
        scheduleCleanup(for: session.callID)
    }

    private func handleConnectingTimeout(callID: String) async {
        guard let session = activeSessionSubject.value,
              session.callID == callID,
              session.state == .connecting else {
            return
        }

        transitionSession(to: .failed)
        scheduleCleanup(for: session.callID)
    }

    private func cancelAllTasks() {
        outgoingTimeoutTask?.cancel()
        incomingTimeoutTask?.cancel()
        connectingTimeoutTask?.cancel()
        cleanupTask?.cancel()
    }
}
