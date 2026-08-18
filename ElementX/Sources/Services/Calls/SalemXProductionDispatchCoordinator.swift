//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

@MainActor
final class SalemXProductionDispatchSession {
    let coordinator: SalemXProductionDispatchCoordinator
    let stockCallLifecycle: SalemXProductionDispatchStockCallLifecycleRouter
    let appSessionGeneration: String

    private let elementCallService: ElementCallServiceProtocol
    private let lifecycleProvider: SalemXStockElementCallLifecycleProviding?
    private var invalidated = false
    private var observationGeneration: UInt64 = 0
    private var activeStockCallLifecycle: SalemXProductionDispatchElementCallLifecycle?

    init(dispatchClient: SalemXProductionDispatchClientProtocol,
         appSessionGeneration: String,
         elementCallService: ElementCallServiceProtocol,
         lifecycleProvider: SalemXStockElementCallLifecycleProviding? = nil) {
        self.appSessionGeneration = appSessionGeneration
        self.elementCallService = elementCallService
        self.lifecycleProvider = lifecycleProvider ?? elementCallService as? SalemXStockElementCallLifecycleProviding
        stockCallLifecycle = .init()
        coordinator = .init(dispatchClient: dispatchClient, stockCallLifecycle: stockCallLifecycle)
    }

    static func makeIfEnabled(appSettings: AppSettings,
                              userSession: UserSessionProtocol,
                              elementCallService: ElementCallServiceProtocol) -> SalemXProductionDispatchSession? {
        guard appSettings.salemxProductionDispatchV1Enabled,
              !userSession.productionDispatchSessionGeneration.isEmpty,
              let homeserverOrigin = URL(string: userSession.clientProxy.homeserver),
              let accessTokenProvider = userSession.clientProxy as? DirectCallMatrixAccessTokenProviding else {
            elementCallService.configureProductionDispatchCapability(nil)
            return nil
        }

        let client = SalemXProductionDispatchClient(homeserverOrigin: homeserverOrigin,
                                                    accessTokenProvider: accessTokenProvider)
        let session = SalemXProductionDispatchSession(dispatchClient: client,
                                                      appSessionGeneration: userSession.productionDispatchSessionGeneration,
                                                      elementCallService: elementCallService)
        elementCallService.configureProductionDispatchCapability(.init(client: client,
                                                                       appSessionGeneration: userSession.productionDispatchSessionGeneration))
        return session
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        elementCallService.configureProductionDispatchCapability(nil)
        Task { await coordinator.invalidateSession(appSessionGeneration) }
    }

    func startEligibleAudio(input: SalemXProductionDispatchAttemptInput,
                            roomID: String,
                            presentStockCall: @escaping @MainActor () -> SalemXProductionDispatchStockCallPresentation?) async
        -> SalemXProductionDispatchCoordinatorOutcome {
        if activeStockCallLifecycle == nil {
            guard let lifecycleProvider else {
                return .failed(.lifecycle)
            }

            observationGeneration &+= 1
            let lifecycle = SalemXProductionDispatchElementCallLifecycle(roomID: roomID,
                                                                         appSessionGeneration: appSessionGeneration,
                                                                         attemptGeneration: observationGeneration,
                                                                         lifecycleProvider: lifecycleProvider,
                                                                         presentStockCall: presentStockCall) { [weak self] lifecycle in
                guard let self, activeStockCallLifecycle === lifecycle else { return }
                stockCallLifecycle.remove(lifecycle)
                activeStockCallLifecycle = nil
            }
            guard stockCallLifecycle.install(lifecycle) else {
                return .failed(.lifecycle)
            }
            activeStockCallLifecycle = lifecycle
        }

        return await coordinator.start(input)
    }

    func stockCallDidEnd() {
        guard let activeStockCallLifecycle else { return }
        activeStockCallLifecycle.markExternalTermination()
        Task { [weak self, weak activeStockCallLifecycle] in
            guard let self, let activeStockCallLifecycle else { return }
            await coordinator.cancelActiveAttempt()
            guard self.activeStockCallLifecycle === activeStockCallLifecycle else { return }
            await activeStockCallLifecycle.completeExternalTermination()
        }
    }
}

struct SalemXProductionDispatchStockCallPresentation {
    let requestTermination: @MainActor () async -> Bool
}

enum SalemXOutgoingProductionDispatchPresentation {
    static func shouldPrepare(prefersOutgoingProductionDispatch: Bool,
                              featureEnabled: Bool,
                              startMode: ElementCallStartMode,
                              hasSession: Bool) -> Bool {
        prefersOutgoingProductionDispatch
            && featureEnabled
            && startMode == .audio
            && hasSession
    }
}

enum SalemXProductionDispatchEligibility {
    static func recipient(featureEnabled: Bool,
                          startMode: ElementCallStartMode,
                          isJoinedRoom: Bool,
                          isEncrypted: Bool,
                          isDirect: Bool,
                          joinedMembersCount: Int,
                          joinedUserIDs: [String],
                          ownUserID: String) -> String? {
        guard featureEnabled,
              startMode == .audio,
              isJoinedRoom,
              isEncrypted,
              isDirect,
              joinedMembersCount == 2,
              joinedUserIDs.count == 2 else {
            return nil
        }

        let recipients = joinedUserIDs.filter { $0 != ownUserID }
        guard recipients.count == 1 else { return nil }
        return recipients[0]
    }
}

@MainActor
final class SalemXProductionDispatchStockCallLifecycleRouter: SalemXProductionDispatchStockCallLifecycleProtocol {
    private var lifecycle: SalemXProductionDispatchStockCallLifecycleProtocol?

    func install(_ lifecycle: SalemXProductionDispatchStockCallLifecycleProtocol) -> Bool {
        guard self.lifecycle == nil else { return false }
        self.lifecycle = lifecycle
        return true
    }

    func remove(_ lifecycle: SalemXProductionDispatchStockCallLifecycleProtocol) {
        guard self.lifecycle === lifecycle else { return }
        self.lifecycle = nil
    }

    func startAudioCall() async -> Result<SalemXProductionDispatchStockCallContext, SalemXProductionDispatchStockCallLifecycleError> {
        guard let lifecycle else { return .failure(.unavailable) }
        return await lifecycle.startAudioCall()
    }

    func awaitConfirmedLocalMembership(for context: SalemXProductionDispatchStockCallContext) async
        -> Result<SalemXProductionDispatchStockCallContext, SalemXProductionDispatchStockCallLifecycleError> {
        guard let lifecycle else { return .failure(.unavailable) }
        return await lifecycle.awaitConfirmedLocalMembership(for: context)
    }

    func endAudioCall(_ context: SalemXProductionDispatchStockCallContext) async {
        await lifecycle?.endAudioCall(context)
    }

    func awaitMembershipRemoval(for context: SalemXProductionDispatchStockCallContext) async {
        await lifecycle?.awaitMembershipRemoval(for: context)
    }
}

@MainActor
private final class SalemXProductionDispatchElementCallLifecycle: SalemXProductionDispatchStockCallLifecycleProtocol {
    private let roomID: String
    private let appSessionGeneration: String
    private let attemptGeneration: UInt64
    private let lifecycleProvider: SalemXStockElementCallLifecycleProviding
    private let presentStockCall: @MainActor () -> SalemXProductionDispatchStockCallPresentation?
    private let completion: @MainActor (SalemXProductionDispatchElementCallLifecycle) -> Void

    private var observationHandle: SalemXStockElementCallObservationHandle?
    private var callContext: SalemXProductionDispatchStockCallContext?
    private var stockCallPresentation: SalemXProductionDispatchStockCallPresentation?
    private var externalTermination = false
    private var terminationRequested = false
    private var completed = false

    init(roomID: String,
         appSessionGeneration: String,
         attemptGeneration: UInt64,
         lifecycleProvider: SalemXStockElementCallLifecycleProviding,
         presentStockCall: @escaping @MainActor () -> SalemXProductionDispatchStockCallPresentation?,
         completion: @escaping @MainActor (SalemXProductionDispatchElementCallLifecycle) -> Void) {
        self.roomID = roomID
        self.appSessionGeneration = appSessionGeneration
        self.attemptGeneration = attemptGeneration
        self.lifecycleProvider = lifecycleProvider
        self.presentStockCall = presentStockCall
        self.completion = completion
    }

    func startAudioCall() async -> Result<SalemXProductionDispatchStockCallContext, SalemXProductionDispatchStockCallLifecycleError> {
        let handleResult = await lifecycleProvider.beginOutgoingObservation(roomID: roomID,
                                                                            appSessionGeneration: appSessionGeneration,
                                                                            attemptGeneration: attemptGeneration)
        guard case .success(let handle) = handleResult else {
            finish()
            return .failure(.unavailable)
        }
        observationHandle = handle

        guard let stockCallPresentation = presentStockCall() else {
            lifecycleProvider.cancelObservation(handle)
            finish()
            return .failure(.unavailable)
        }
        self.stockCallPresentation = stockCallPresentation

        guard case .success(let context) = await lifecycleProvider.awaitMembershipConfirmation(handle) else {
            MXLog.error("Production dispatch MatrixRTC membership was not confirmed.")
            await requestTerminationIfNeeded()
            _ = await lifecycleProvider.awaitMembershipRemoval(handle)
            lifecycleProvider.cancelObservation(handle)
            finish()
            return .failure(.membershipNotConfirmed)
        }

        MXLog.info("Production dispatch local MatrixRTC membership confirmed.")

        let dispatchContext = SalemXProductionDispatchStockCallContext(roomID: context.roomID,
                                                                       callID: context.callID,
                                                                       callHandle: context.callHandle)
        callContext = dispatchContext
        return .success(dispatchContext)
    }

    func awaitConfirmedLocalMembership(for context: SalemXProductionDispatchStockCallContext) async
        -> Result<SalemXProductionDispatchStockCallContext, SalemXProductionDispatchStockCallLifecycleError> {
        guard callContext == context else { return .failure(.membershipNotConfirmed) }
        return .success(context)
    }

    func endAudioCall(_ context: SalemXProductionDispatchStockCallContext) async {
        guard callContext == context else { return }
        await requestTerminationIfNeeded()
    }

    func awaitMembershipRemoval(for context: SalemXProductionDispatchStockCallContext) async {
        guard callContext == context, let observationHandle else { return }
        _ = await lifecycleProvider.awaitMembershipRemoval(observationHandle)
        lifecycleProvider.cancelObservation(observationHandle)
        finish()
    }

    func markExternalTermination() {
        externalTermination = true
    }

    func completeExternalTermination() async {
        guard let observationHandle else {
            finish()
            return
        }
        _ = await lifecycleProvider.awaitMembershipRemoval(observationHandle)
        lifecycleProvider.cancelObservation(observationHandle)
        finish()
    }

    private func requestTerminationIfNeeded() async {
        guard !externalTermination, !terminationRequested else { return }
        terminationRequested = true
        _ = await stockCallPresentation?.requestTermination()
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        completion(self)
    }
}

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
        MXLog.info("Production dispatch starting prepare.")

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
