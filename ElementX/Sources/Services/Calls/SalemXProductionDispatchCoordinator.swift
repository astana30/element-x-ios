//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum SalemXProductionDispatchCoordinatorState: Equatable {
    case idle
    case startingMatrixRTC
    case membershipConfirmed
    case preparing
    case claiming
    case sending
    case sent
}

enum SalemXProductionDispatchCoordinatorError: Error, Equatable, CustomStringConvertible {
    case lifecycle
    case dispatch(SalemXProductionDispatchClientError)
    case deliveryUnknown
    case cancelled
    case staleGeneration

    var description: String {
        switch self {
        case .lifecycle:
            "SalemXProductionDispatchCoordinatorError.lifecycle"
        case .dispatch(let error):
            "SalemXProductionDispatchCoordinatorError.dispatch(\(error))"
        case .deliveryUnknown:
            "SalemXProductionDispatchCoordinatorError.deliveryUnknown"
        case .cancelled:
            "SalemXProductionDispatchCoordinatorError.cancelled"
        case .staleGeneration:
            "SalemXProductionDispatchCoordinatorError.staleGeneration"
        }
    }
}

enum SalemXProductionDispatchCoordinatorOutcome: Equatable {
    case sent(UUID)
    case failed(SalemXProductionDispatchCoordinatorError)
}

struct SalemXProductionDispatchStockCallContext: Equatable, CustomStringConvertible {
    let roomID: String
    let callID: String
    let callHandle: String

    var description: String {
        "SalemXProductionDispatchStockCallContext(<redacted>)"
    }
}

enum SalemXProductionDispatchStockCallLifecycleError: Error, Equatable {
    case unavailable
    case membershipNotConfirmed
    case cancelled
}

@MainActor
protocol SalemXProductionDispatchStockCallLifecycleProtocol: AnyObject {
    func startAudioCall() async -> Result<SalemXProductionDispatchStockCallContext, SalemXProductionDispatchStockCallLifecycleError>
    func awaitConfirmedLocalMembership(for context: SalemXProductionDispatchStockCallContext) async
        -> Result<SalemXProductionDispatchStockCallContext, SalemXProductionDispatchStockCallLifecycleError>
    func endAudioCall(_ context: SalemXProductionDispatchStockCallContext) async
    func awaitMembershipRemoval(for context: SalemXProductionDispatchStockCallContext) async
}

struct SalemXProductionDispatchAdmission: Equatable, CustomStringConvertible {
    let recipient: String
    let recipientDevice: String?
    let displayLabel: String

    var description: String {
        "SalemXProductionDispatchAdmission(<redacted>)"
    }
}

struct SalemXProductionDispatchAttemptInput: Equatable, CustomStringConvertible {
    let appSessionGeneration: String
    let admission: SalemXProductionDispatchAdmission
    let createdAtMS: Int64
    let expiresAtMS: Int64

    var description: String {
        "SalemXProductionDispatchAttemptInput(<redacted>)"
    }
}

@MainActor
final class SalemXProductionDispatchCoordinator {
    private struct ActiveAttempt {
        let generation: Int
        let dispatchID: UUID
        let appSessionGeneration: String
        let task: Task<SalemXProductionDispatchCoordinatorOutcome, Never>
        var context: SalemXProductionDispatchStockCallContext?
        var preparedRecord: SalemXProductionDispatchPrepareResponse?
        var cancellationRequested = false
    }

    private let dispatchClient: SalemXProductionDispatchClientProtocol
    private let stockCallLifecycle: SalemXProductionDispatchStockCallLifecycleProtocol
    private let dispatchIDGenerator: () -> UUID
    private var nextGeneration = 0
    private var activeAttempt: ActiveAttempt?
    private var invalidatedSessionGenerations = Set<String>()

    private(set) var state = SalemXProductionDispatchCoordinatorState.idle
    private(set) var lastStartedGeneration = 0
    private(set) var lastStartedDispatchID: UUID?

    init(dispatchClient: SalemXProductionDispatchClientProtocol,
         stockCallLifecycle: SalemXProductionDispatchStockCallLifecycleProtocol,
         dispatchIDGenerator: @escaping () -> UUID = UUID.init) {
        self.dispatchClient = dispatchClient
        self.stockCallLifecycle = stockCallLifecycle
        self.dispatchIDGenerator = dispatchIDGenerator
    }

    func start(_ input: SalemXProductionDispatchAttemptInput) async -> SalemXProductionDispatchCoordinatorOutcome {
        guard !invalidatedSessionGenerations.contains(input.appSessionGeneration) else {
            return .failed(.staleGeneration)
        }
        if let activeAttempt {
            return await activeAttempt.task.value
        }

        nextGeneration += 1
        let generation = nextGeneration
        let dispatchID = dispatchIDGenerator()
        lastStartedGeneration = generation
        lastStartedDispatchID = dispatchID

        let task: Task<SalemXProductionDispatchCoordinatorOutcome, Never> = Task { [weak self] in
            guard let self else { return SalemXProductionDispatchCoordinatorOutcome.failed(.cancelled) }
            let outcome = await runAttempt(input, generation: generation)
            await completeAttempt(generation, outcome: outcome)
            return outcome
        }
        activeAttempt = .init(generation: generation,
                              dispatchID: dispatchID,
                              appSessionGeneration: input.appSessionGeneration,
                              task: task,
                              context: nil,
                              preparedRecord: nil)
        return await task.value
    }

    func cancelActiveAttempt() async {
        guard var activeAttempt else { return }
        if !activeAttempt.cancellationRequested {
            activeAttempt.cancellationRequested = true
            self.activeAttempt = activeAttempt
            activeAttempt.task.cancel()
        }
        _ = await activeAttempt.task.value
    }

    func invalidateSession(_ appSessionGeneration: String) async {
        invalidatedSessionGenerations.insert(appSessionGeneration)
        if activeAttempt?.appSessionGeneration == appSessionGeneration {
            await cancelActiveAttempt()
        }
    }

    private func runAttempt(_ input: SalemXProductionDispatchAttemptInput,
                            generation: Int) async -> SalemXProductionDispatchCoordinatorOutcome {
        guard isCurrent(generation) else { return .failed(.staleGeneration) }
        state = .startingMatrixRTC

        let context: SalemXProductionDispatchStockCallContext
        switch await stockCallLifecycle.startAudioCall() {
        case .success(let startedContext):
            context = startedContext
        case .failure:
            return .failed(Task.isCancelled ? .cancelled : .lifecycle)
        }

        guard updateCurrentAttempt(generation, context: context) else { return .failed(.staleGeneration) }
        guard !Task.isCancelled else {
            return .failed(.cancelled)
        }

        switch await stockCallLifecycle.awaitConfirmedLocalMembership(for: context) {
        case .success:
            break
        case .failure:
            return .failed(Task.isCancelled ? .cancelled : .lifecycle)
        }

        guard isCurrent(generation), !Task.isCancelled else {
            return .failed(Task.isCancelled ? .cancelled : .staleGeneration)
        }
        state = .membershipConfirmed
        return await dispatchConfirmedMembership(input, generation: generation, context: context)
    }

    private func dispatchConfirmedMembership(_ input: SalemXProductionDispatchAttemptInput,
                                             generation: Int,
                                             context: SalemXProductionDispatchStockCallContext) async -> SalemXProductionDispatchCoordinatorOutcome {
        state = .preparing

        let prepareRequest = SalemXProductionDispatchPrepareRequest(recipient: input.admission.recipient,
                                                                    recipientDevice: input.admission.recipientDevice,
                                                                    callHandle: context.callHandle,
                                                                    createdAtMS: input.createdAtMS,
                                                                    expiresAtMS: input.expiresAtMS,
                                                                    displayLabel: input.admission.displayLabel,
                                                                    appSessionGeneration: input.appSessionGeneration,
                                                                    pendingMetadata: .init(callID: context.callID,
                                                                                           roomID: context.roomID))
        let preparedRecord: SalemXProductionDispatchPrepareResponse
        switch await dispatchClient.prepare(prepareRequest) {
        case .success(let response):
            preparedRecord = response
        case .failure(let error):
            return .failed(coordinatorError(for: error))
        }

        guard updateCurrentAttempt(generation, preparedRecord: preparedRecord), !Task.isCancelled else {
            return .failed(Task.isCancelled ? .cancelled : .staleGeneration)
        }
        state = .claiming

        let referenceRequest = SalemXProductionDispatchReferenceRequest(dispatchID: preparedRecord.dispatchID,
                                                                        senderReference: preparedRecord.senderReference,
                                                                        appSessionGeneration: input.appSessionGeneration)
        switch await dispatchClient.claim(referenceRequest) {
        case .success:
            break
        case .failure(let error):
            return .failed(coordinatorError(for: error))
        }

        guard isCurrent(generation), !Task.isCancelled else {
            return .failed(Task.isCancelled ? .cancelled : .staleGeneration)
        }
        state = .sending

        let sendRequest = SalemXProductionDispatchSendPreparedRequest(dispatchID: preparedRecord.dispatchID,
                                                                      senderReference: preparedRecord.senderReference,
                                                                      receiverReference: preparedRecord.receiverReference,
                                                                      appSessionGeneration: input.appSessionGeneration)
        switch await dispatchClient.sendPrepared(sendRequest) {
        case .success:
            guard isCurrent(generation), !Task.isCancelled else {
                return .failed(Task.isCancelled ? .cancelled : .staleGeneration)
            }
            state = .sent
            return .sent(preparedRecord.dispatchID)
        case .failure(.ambiguousSend):
            return .failed(Task.isCancelled ? .cancelled : .deliveryUnknown)
        case .failure(let error):
            return .failed(coordinatorError(for: error))
        }
    }

    private func completeAttempt(_ generation: Int,
                                 outcome: SalemXProductionDispatchCoordinatorOutcome) async {
        guard let attempt = activeAttempt, attempt.generation == generation else { return }

        if case .failed = outcome {
            let cleanupTask = Task { [weak self] in
                guard let self else { return }
                if let preparedRecord = attempt.preparedRecord {
                    let request = SalemXProductionDispatchReferenceRequest(dispatchID: preparedRecord.dispatchID,
                                                                           senderReference: preparedRecord.senderReference,
                                                                           appSessionGeneration: attempt.appSessionGeneration)
                    _ = await dispatchClient.cancelPrepared(request)
                }
                if let context = attempt.context {
                    await endAndAwaitMembershipRemoval(context)
                }
            }
            await cleanupTask.value
        }

        guard activeAttempt?.generation == generation else { return }
        activeAttempt = nil
        if case .failed = outcome {
            state = .idle
        }
    }

    private func endAndAwaitMembershipRemoval(_ context: SalemXProductionDispatchStockCallContext) async {
        await stockCallLifecycle.endAudioCall(context)
        await stockCallLifecycle.awaitMembershipRemoval(for: context)
    }

    private func isCurrent(_ generation: Int) -> Bool {
        activeAttempt?.generation == generation
    }

    private func coordinatorError(for error: SalemXProductionDispatchClientError) -> SalemXProductionDispatchCoordinatorError {
        Task.isCancelled ? .cancelled : .dispatch(error)
    }

    @discardableResult
    private func updateCurrentAttempt(_ generation: Int,
                                      context: SalemXProductionDispatchStockCallContext? = nil,
                                      preparedRecord: SalemXProductionDispatchPrepareResponse? = nil) -> Bool {
        guard var activeAttempt, activeAttempt.generation == generation else { return false }
        if let context {
            activeAttempt.context = context
        }
        if let preparedRecord {
            activeAttempt.preparedRecord = preparedRecord
        }
        self.activeAttempt = activeAttempt
        return true
    }
}
