//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
protocol DirectCallSignalTransportProtocol {
    func send(_ signal: DirectCallOutgoingSignal, from senderID: String)
    func signalsPublisher(for recipientUserID: String) -> AnyPublisher<DirectCallSignalEvent, Never>
    func detachSignalsPublisher(for recipientUserID: String)
}

/// DEV/TEST ONLY.
/// This transport is in-memory and must never be used as production signalling transport.
@MainActor
final class InMemoryDirectCallSignalTransport: DirectCallSignalTransportProtocol {
    static let shared = InMemoryDirectCallSignalTransport()

    private let now: () -> Date
    private let eventIDProvider: () -> String

    private var subjectsByRecipient = [String: PassthroughSubject<DirectCallSignalEvent, Never>]()

    init(now: @escaping () -> Date = Date.init,
         eventIDProvider: @escaping () -> String = { UUID().uuidString }) {
        self.now = now
        self.eventIDProvider = eventIDProvider
    }

    func send(_ signal: DirectCallOutgoingSignal, from senderID: String) {
        guard !signal.callID.isEmpty,
              !signal.roomID.isEmpty,
              !senderID.isEmpty,
              !signal.peerUserID.isEmpty,
              let recipientSubject = subjectsByRecipient[signal.peerUserID] else {
            return
        }

        let event = DirectCallSignalEvent(eventID: eventIDProvider(),
                                          roomID: signal.roomID,
                                          senderID: senderID,
                                          callID: signal.callID,
                                          type: signal.type,
                                          intent: signal.intent,
                                          timestamp: now(),
                                          keyExchange: signal.keyExchange)
        recipientSubject.send(event)
    }

    func signalsPublisher(for recipientUserID: String) -> AnyPublisher<DirectCallSignalEvent, Never> {
        guard !recipientUserID.isEmpty else {
            return Empty<DirectCallSignalEvent, Never>(completeImmediately: false).eraseToAnyPublisher()
        }
        return subject(for: recipientUserID).eraseToAnyPublisher()
    }

    func detachSignalsPublisher(for recipientUserID: String) {
        guard !recipientUserID.isEmpty else {
            return
        }
        subjectsByRecipient.removeValue(forKey: recipientUserID)
    }

    func reset() {
        subjectsByRecipient.removeAll()
    }

    private func subject(for recipientUserID: String) -> PassthroughSubject<DirectCallSignalEvent, Never> {
        if let existing = subjectsByRecipient[recipientUserID] {
            return existing
        }

        let subject = PassthroughSubject<DirectCallSignalEvent, Never>()
        subjectsByRecipient[recipientUserID] = subject
        return subject
    }
}

@MainActor
final class DirectCallEngineSignalBridge {
    private let ownUserID: String
    private let engine: DirectCallEngineProtocol
    private let signalTransport: DirectCallSignalTransportProtocol

    private var cancellables = Set<AnyCancellable>()

    init(ownUserID: String,
         engine: DirectCallEngineProtocol,
         signalTransport: DirectCallSignalTransportProtocol) {
        self.ownUserID = ownUserID
        self.engine = engine
        self.signalTransport = signalTransport

        subscribeToOutgoingSignals()
        subscribeToIncomingSignals()
    }

    deinit {
        let recipientUserID = ownUserID
        let signalTransport = signalTransport
        Task { @MainActor in
            signalTransport.detachSignalsPublisher(for: recipientUserID)
        }
    }

    private func subscribeToOutgoingSignals() {
        engine.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                guard case .emitSignal(let signal) = action else {
                    return
                }

                signalTransport.send(signal, from: ownUserID)
            }
            .store(in: &cancellables)
    }

    private func subscribeToIncomingSignals() {
        signalTransport.signalsPublisher(for: ownUserID)
            .sink { [weak self] signalEvent in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await engine.receiveIncomingCall(event: signalEvent)
                }
            }
            .store(in: &cancellables)
    }
}
