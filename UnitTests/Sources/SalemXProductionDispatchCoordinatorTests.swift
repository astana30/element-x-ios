//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct SalemXProductionDispatchCoordinatorTests {
    @Test
    func membershipIsConfirmedBeforePrepareAndTheSequenceIsExact() async {
        let recorder = Stage5EventRecorder()
        let lifecycle = LifecycleSpy(recorder: recorder)
        let client = DispatchClientSpy(recorder: recorder)
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        let outcome = await coordinator.start(input())

        #expect(outcome == .sent(client.dispatchID))
        #expect(lifecycle.events == [.start, .membershipConfirmed])
        #expect(client.events == [.prepare, .claim, .send])
        #expect(recorder.events == ["start", "membership", "prepare", "claim", "send"])
        #expect(client.claimRequests.first?.dispatchID == client.dispatchID)
        #expect(client.sendRequests.first?.dispatchID == client.dispatchID)
        #expect(coordinator.state == .sent)
    }

    @Test
    func duplicateTapsCoalesceIntoOneStockCallAndOneDispatch() async {
        let lifecycle = LifecycleSpy(waitBeforeStart: true)
        let client = DispatchClientSpy()
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        let first = Task { await coordinator.start(input()) }
        await lifecycle.waitUntilStartIsRequested()
        let second = Task { await coordinator.start(input()) }
        for _ in 0..<8 {
            await Task.yield()
        }
        lifecycle.continueStart()

        #expect(await first.value == .sent(client.dispatchID))
        #expect(await second.value == .sent(client.dispatchID))
        #expect(lifecycle.startCount == 1)
        #expect(client.prepareCount == 1)
        #expect(client.claimCount == 1)
        #expect(client.sendCount == 1)
    }

    @Test
    func concurrentBurstSharesOneAttemptAndResult() async {
        let lifecycle = LifecycleSpy(waitBeforeStart: true)
        let client = DispatchClientSpy()
        var generatedDispatchIDs = [UUID]()
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client,
                                                              stockCallLifecycle: lifecycle) {
            let dispatchID = UUID()
            generatedDispatchIDs.append(dispatchID)
            return dispatchID
        }

        let first = Task { await coordinator.start(input()) }
        await lifecycle.waitUntilStartIsRequested()
        let duplicates = (0..<15).map { _ in
            Task { await coordinator.start(input()) }
        }
        for _ in 0..<32 {
            await Task.yield()
        }
        lifecycle.continueStart()

        let duplicateOutcomes = await duplicates.values
        let outcomes = await [first.value] + duplicateOutcomes
        #expect(outcomes.count == 16)
        #expect(outcomes.allSatisfy { $0 == .sent(client.dispatchID) })
        #expect(generatedDispatchIDs.count == 1)
        #expect(coordinator.lastStartedDispatchID == generatedDispatchIDs.first)
        #expect(lifecycle.startCount == 1)
        #expect(client.prepareCount == 1)
        #expect(client.claimCount == 1)
        #expect(client.sendCount == 1)
    }

    @Test
    func prepareFailureEndsStockCallAndAwaitsMembershipRemoval() async {
        let lifecycle = LifecycleSpy()
        let client = DispatchClientSpy(prepareResult: .failure(.transportUnavailable))
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        #expect(await coordinator.start(input()) == .failed(.dispatch(.transportUnavailable)))
        #expect(lifecycle.events == [.start, .membershipConfirmed, .end, .membershipRemoved])
        #expect(client.cancelCount == 0)
    }

    @Test
    func disabledServerAfterMatrixRTCStartTearsDownExactlyOnce() async {
        let lifecycle = LifecycleSpy()
        let disabled = SalemXProductionDispatchClientError.http(.notFound, .disabled)
        let client = DispatchClientSpy(prepareResult: .failure(disabled))
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        #expect(await coordinator.start(input()) == .failed(.dispatch(disabled)))
        #expect(client.events == [.prepare])
        #expect(client.claimCount == 0)
        #expect(client.sendCount == 0)
        #expect(client.cancelCount == 0)
        #expect(lifecycle.events == [.start, .membershipConfirmed, .end, .membershipRemoved])
        #expect(lifecycle.events.filter { $0 == .end }.count == 1)
        #expect(lifecycle.events.filter { $0 == .membershipRemoved }.count == 1)
        #expect(coordinator.state == .idle)
    }

    @Test
    func claimFailureCancelsExactPreparedRecordAndEndsMembership() async {
        let lifecycle = LifecycleSpy()
        let client = DispatchClientSpy(claimResult: .failure(.http(.forbidden, .capability)))
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        #expect(await coordinator.start(input()) == .failed(.dispatch(.http(.forbidden, .capability))))
        #expect(client.events == [.prepare, .claim, .cancel])
        #expect(client.cancelRequests.count == 1)
        guard let cancelRequest = client.cancelRequests.first else {
            return
        }
        #expect(cancelRequest.dispatchProtocolVersion == SalemXProductionDispatchProtocolVersion.v1.rawValue)
        #expect(cancelRequest.dispatchProtocolVersion == client.referenceRequest.dispatchProtocolVersion)
        #expect(cancelRequest.dispatchID == client.referenceRequest.dispatchID)
        #expect(cancelRequest.senderReference == client.referenceRequest.senderReference)
        #expect(cancelRequest.appSessionGeneration == client.referenceRequest.appSessionGeneration)
        #expect(lifecycle.events.suffix(2) == [.end, .membershipRemoved])
    }

    @Test
    func ambiguousSendNeverRetriesAndFailsClosed() async {
        let lifecycle = LifecycleSpy()
        let client = DispatchClientSpy(sendResult: .failure(.ambiguousSend))
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        #expect(await coordinator.start(input()) == .failed(.deliveryUnknown))
        #expect(client.sendCount == 1)
        #expect(client.cancelCount == 1)
        #expect(lifecycle.events.suffix(2) == [.end, .membershipRemoved])
    }

    @Test
    func cancellationIsIdempotentAndAwaitsMembershipRemoval() async {
        let lifecycle = LifecycleSpy(waitBeforeMembership: true)
        let client = DispatchClientSpy()
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        let task = Task { await coordinator.start(input()) }
        await lifecycle.waitUntilMembershipIsRequested()
        await coordinator.cancelActiveAttempt()
        await coordinator.cancelActiveAttempt()
        lifecycle.continueMembership()

        #expect(await task.value == .failed(.cancelled))
        #expect(lifecycle.events == [.start, .end, .membershipRemoved])
        #expect(client.events.isEmpty)
    }

    @Test
    func sessionReplacementRejectsStaleCompletionWithoutDispatch() async {
        let lifecycle = LifecycleSpy(waitBeforeMembership: true)
        let client = DispatchClientSpy()
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        let task = Task { await coordinator.start(input()) }
        await lifecycle.waitUntilMembershipIsRequested()
        await coordinator.invalidateSession("session-generation")
        lifecycle.continueMembership()

        #expect(await task.value == .failed(.cancelled))
        #expect(client.events.isEmpty)
        #expect(lifecycle.events.suffix(2) == [.end, .membershipRemoved])
        #expect(await coordinator.start(input()) == .failed(.staleGeneration))
        #expect(lifecycle.startCount == 1)
    }

    @Test(arguments: [BlockedDispatchOperation.prepare, .claim, .send])
    fileprivate func cancellationFromNetworkStatesIsBoundedAndIdempotent(operation: BlockedDispatchOperation) async {
        let lifecycle = LifecycleSpy()
        let client = DispatchClientSpy(blockedOperation: operation)
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        let task = Task { await coordinator.start(input()) }
        await client.waitUntilBlockedOperationIsEntered()
        async let firstCancellation: Void = coordinator.cancelActiveAttempt()
        async let secondCancellation: Void = coordinator.cancelActiveAttempt()
        _ = await (firstCancellation, secondCancellation)

        #expect(await task.value == .failed(.cancelled))
        #expect(client.sendCount <= 1)
        #expect(client.cancelCount == (operation == .prepare ? 0 : 1))
        #expect(lifecycle.events.suffix(2) == [.end, .membershipRemoved])
        #expect(lifecycle.events.filter { $0 == .end }.count == 1)
        #expect(lifecycle.events.filter { $0 == .membershipRemoved }.count == 1)
    }

    @Test
    func retryAfterTerminalFailureUsesANewDispatchIdentity() async {
        let lifecycle = LifecycleSpy()
        let client = DispatchClientSpy(sendResult: .failure(.transportUnavailable), dispatchIDs: [firstDispatchID, secondDispatchID])
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        #expect(await coordinator.start(input()) == .failed(.dispatch(.transportUnavailable)))
        client.sendResult = .success(client.sentResponse)
        #expect(await coordinator.start(input()) == .sent(secondDispatchID))
        #expect(client.preparedDispatchIDs == [firstDispatchID, secondDispatchID])
        #expect(coordinator.lastStartedGeneration == 2)
    }

    @Test
    func failureCleanupRetainsTheActiveSlotUntilItCompletes() async {
        let lifecycle = LifecycleSpy(waitBeforeMembershipRemoval: true)
        let client = DispatchClientSpy(prepareResult: .failure(.transportUnavailable))
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        let first = Task { await coordinator.start(input()) }
        await lifecycle.waitUntilMembershipRemovalIsRequested()
        let duplicateDuringCleanup = Task { await coordinator.start(input()) }
        for _ in 0..<8 {
            await Task.yield()
        }
        #expect(lifecycle.startCount == 1)
        lifecycle.continueMembershipRemoval()

        #expect(await first.value == .failed(.dispatch(.transportUnavailable)))
        #expect(await duplicateDuringCleanup.value == .failed(.dispatch(.transportUnavailable)))
        client.prepareResult = nil
        #expect(await coordinator.start(input()) == .sent(client.dispatchID))
        #expect(lifecycle.startCount == 2)
    }

    @Test
    func cancellingADuplicateWaiterDoesNotCancelTheSharedAttempt() async {
        let lifecycle = LifecycleSpy(waitBeforeStart: true)
        let client = DispatchClientSpy()
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        let first = Task { await coordinator.start(input()) }
        await lifecycle.waitUntilStartIsRequested()
        let duplicate = Task { await coordinator.start(input()) }
        for _ in 0..<8 {
            await Task.yield()
        }
        duplicate.cancel()
        lifecycle.continueStart()

        #expect(await first.value == .sent(client.dispatchID))
        #expect(await duplicate.value == .sent(client.dispatchID))
        #expect(lifecycle.startCount == 1)
        #expect(client.prepareCount == 1)
        #expect(client.claimCount == 1)
        #expect(client.sendCount == 1)
        #expect(client.cancelCount == 0)
    }

    @Test
    func sentAttemptTransfersLifecycleOwnershipToStockCall() async {
        let lifecycle = LifecycleSpy()
        let client = DispatchClientSpy()
        let coordinator = SalemXProductionDispatchCoordinator(dispatchClient: client, stockCallLifecycle: lifecycle)

        #expect(await coordinator.start(input()) == .sent(client.dispatchID))
        #expect(lifecycle.events == [.start, .membershipConfirmed])
        #expect(coordinator.state == .sent)
    }

    @Test
    func descriptionsAndStateNamesDoNotExposeIdentifiers() {
        let context = SalemXProductionDispatchStockCallContext(roomID: "!room:example.test",
                                                               callID: "call-id",
                                                               callHandle: "call-handle")
        let admission = SalemXProductionDispatchAdmission(recipient: "@user:example.test",
                                                          recipientDevice: "DEVICE",
                                                          displayLabel: "Audio call")
        #expect(String(describing: context).contains("room") == false)
        #expect(String(describing: admission).contains("user") == false)
        #expect(String(describing: SalemXProductionDispatchCoordinatorError.deliveryUnknown).contains("call-id") == false)
    }

    @Test
    func productionSessionArmsStockObservationBeforeDispatch() async {
        let recorder = Stage5EventRecorder()
        let lifecycleProvider = StockLifecycleProviderSpy(recorder: recorder)
        let client = DispatchClientSpy(recorder: recorder)
        let elementCallService = ElementCallServiceMock()
        let session = SalemXProductionDispatchSession(dispatchClient: client,
                                                      appSessionGeneration: "session-generation",
                                                      elementCallService: elementCallService,
                                                      lifecycleProvider: lifecycleProvider)

        let outcome = await session.startEligibleAudio(input: input(), roomID: "room") {
            recorder.events.append("stock")
            return .init { true }
        }

        #expect(outcome == .sent(client.dispatchID))
        #expect(recorder.events == ["arm", "stock", "membership", "prepare", "claim", "send"])
        #expect(lifecycleProvider.armCount == 1)
    }

    @Test
    func sentStockCallRemovalReleasesLifecycleForNextAttempt() async {
        let lifecycleProvider = StockLifecycleProviderSpy(recorder: .init())
        let client = DispatchClientSpy(dispatchIDs: [UUID(), UUID()])
        let session = SalemXProductionDispatchSession(dispatchClient: client,
                                                      appSessionGeneration: "session-generation",
                                                      elementCallService: ElementCallServiceMock(),
                                                      lifecycleProvider: lifecycleProvider)

        #expect(await session.startEligibleAudio(input: input(), roomID: "room") { .init { true } }.isSent)
        session.stockCallDidEnd()
        while lifecycleProvider.removalCount == 0 {
            await Task.yield()
        }
        #expect(await session.startEligibleAudio(input: input(), roomID: "room") { .init { true } }.isSent)
        #expect(lifecycleProvider.armCount == 2)
    }

    @Test(arguments: [
        (false, ElementCallStartMode.audio, true, true, true, 2, ["self", "other"]),
        (true, .video, true, true, true, 2, ["self", "other"]),
        (true, .audio, false, true, true, 2, ["self", "other"]),
        (true, .audio, true, false, true, 2, ["self", "other"]),
        (true, .audio, true, true, false, 2, ["self", "other"]),
        (true, .audio, true, true, true, 3, ["self", "other", "third"]),
        (true, .audio, true, true, true, 2, ["self", "other", "other-two"])
    ])
    func noneligibleAudioRemainsStockOnly(featureEnabled: Bool,
                                          startMode: ElementCallStartMode,
                                          isJoinedRoom: Bool,
                                          isEncrypted: Bool,
                                          isDirect: Bool,
                                          joinedMembersCount: Int,
                                          joinedUserIDs: [String]) {
        #expect(SalemXProductionDispatchEligibility.recipient(featureEnabled: featureEnabled,
                                                              startMode: startMode,
                                                              isJoinedRoom: isJoinedRoom,
                                                              isEncrypted: isEncrypted,
                                                              isDirect: isDirect,
                                                              joinedMembersCount: joinedMembersCount,
                                                              joinedUserIDs: joinedUserIDs,
                                                              ownUserID: "self") == nil)
    }

    @Test
    func encryptedJoinedOneToOneAudioResolvesOneRecipient() {
        #expect(SalemXProductionDispatchEligibility.recipient(featureEnabled: true,
                                                              startMode: .audio,
                                                              isJoinedRoom: true,
                                                              isEncrypted: true,
                                                              isDirect: true,
                                                              joinedMembersCount: 2,
                                                              joinedUserIDs: ["self", "other"],
                                                              ownUserID: "self") == "other")
    }

    private func input() -> SalemXProductionDispatchAttemptInput {
        .init(appSessionGeneration: "session-generation",
              admission: .init(recipient: "@receiver:example.test",
                               recipientDevice: "DEVICE",
                               displayLabel: "Audio call"),
              createdAtMS: 1000,
              expiresAtMS: 61000)
    }

    private let firstDispatchID = UUID(uuid: (0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x41, 0x11, 0x81, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11))
    private let secondDispatchID = UUID(uuid: (0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x42, 0x22, 0x82, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22))
}

@MainActor
private final class StockLifecycleProviderSpy: SalemXStockElementCallLifecycleProviding {
    private let recorder: Stage5EventRecorder
    private(set) var armCount = 0
    private(set) var removalCount = 0
    private let handle = SalemXStockElementCallObservationHandle(observationID: UUID(),
                                                                 appSessionGeneration: "session-generation",
                                                                 attemptGeneration: 1)

    init(recorder: Stage5EventRecorder) {
        self.recorder = recorder
    }

    func beginOutgoingObservation(roomID: String,
                                  appSessionGeneration: String,
                                  attemptGeneration: UInt64) async
        -> Result<SalemXStockElementCallObservationHandle, SalemXStockElementCallLifecycleError> {
        armCount += 1
        recorder.events.append("arm")
        return .success(handle)
    }

    func awaitMembershipConfirmation(_ handle: SalemXStockElementCallObservationHandle) async
        -> Result<SalemXStockElementCallContext, SalemXStockElementCallLifecycleError> {
        recorder.events.append("membership")
        return .success(.init(callID: "call", roomID: "room", callHandle: "handle"))
    }

    func awaitMembershipRemoval(_ handle: SalemXStockElementCallObservationHandle) async
        -> Result<Void, SalemXStockElementCallLifecycleError> {
        removalCount += 1
        return .success(())
    }

    func cancelObservation(_ handle: SalemXStockElementCallObservationHandle) { }
}

private extension SalemXProductionDispatchCoordinatorOutcome {
    var isSent: Bool {
        if case .sent = self { return true }
        return false
    }
}

@MainActor
private final class LifecycleSpy: SalemXProductionDispatchStockCallLifecycleProtocol {
    enum Event: Equatable {
        case start
        case membershipConfirmed
        case end
        case membershipRemoved
    }

    private let waitBeforeStart: Bool
    private let waitBeforeMembership: Bool
    private let waitBeforeMembershipRemoval: Bool
    private let recorder: Stage5EventRecorder?
    private var startRequested = false
    private var startMayContinue = false
    private var membershipRequested = false
    private var membershipMayContinue = false
    private var membershipRemovalRequested = false
    private var membershipRemovalMayContinue = false
    private(set) var events = [Event]()
    private(set) var startCount = 0

    init(waitBeforeStart: Bool = false,
         waitBeforeMembership: Bool = false,
         waitBeforeMembershipRemoval: Bool = false,
         recorder: Stage5EventRecorder? = nil) {
        self.waitBeforeStart = waitBeforeStart
        self.waitBeforeMembership = waitBeforeMembership
        self.waitBeforeMembershipRemoval = waitBeforeMembershipRemoval
        self.recorder = recorder
    }

    func startAudioCall() async -> Result<SalemXProductionDispatchStockCallContext, SalemXProductionDispatchStockCallLifecycleError> {
        startCount += 1
        events.append(.start)
        recorder?.events.append("start")
        startRequested = true
        if waitBeforeStart {
            while !startMayContinue {
                if Task.isCancelled {
                    return .failure(.cancelled)
                }
                await Task.yield()
            }
        }
        return .success(.init(roomID: "!room:example.test", callID: "call-id", callHandle: "call-handle"))
    }

    func awaitConfirmedLocalMembership(for context: SalemXProductionDispatchStockCallContext) async
        -> Result<SalemXProductionDispatchStockCallContext, SalemXProductionDispatchStockCallLifecycleError> {
        membershipRequested = true
        if waitBeforeMembership {
            while !membershipMayContinue {
                if Task.isCancelled {
                    return .failure(.cancelled)
                }
                await Task.yield()
            }
        }
        events.append(.membershipConfirmed)
        recorder?.events.append("membership")
        return .success(context)
    }

    func endAudioCall(_ context: SalemXProductionDispatchStockCallContext) async {
        events.append(.end)
    }

    func awaitMembershipRemoval(for context: SalemXProductionDispatchStockCallContext) async {
        membershipRemovalRequested = true
        if waitBeforeMembershipRemoval {
            while !membershipRemovalMayContinue {
                await Task.yield()
            }
        }
        events.append(.membershipRemoved)
    }

    func waitUntilStartIsRequested() async {
        while !startRequested {
            await Task.yield()
        }
    }

    func continueStart() {
        startMayContinue = true
    }

    func waitUntilMembershipIsRequested() async {
        while !membershipRequested {
            await Task.yield()
        }
    }

    func continueMembership() {
        membershipMayContinue = true
    }

    func waitUntilMembershipRemovalIsRequested() async {
        while !membershipRemovalRequested {
            await Task.yield()
        }
    }

    func continueMembershipRemoval() {
        membershipRemovalMayContinue = true
    }
}

private extension Array where Element == Task<SalemXProductionDispatchCoordinatorOutcome, Never> {
    var values: [SalemXProductionDispatchCoordinatorOutcome] {
        get async {
            var outcomes = [SalemXProductionDispatchCoordinatorOutcome]()
            for task in self {
                await outcomes.append(task.value)
            }
            return outcomes
        }
    }
}

private enum BlockedDispatchOperation: Equatable {
    case prepare
    case claim
    case send
}

@MainActor
private final class DispatchClientSpy: SalemXProductionDispatchClientProtocol {
    enum Event: Equatable {
        case prepare
        case claim
        case send
        case cancel
    }

    let dispatchIDs: [UUID]
    private let recorder: Stage5EventRecorder?
    private let blockedOperation: BlockedDispatchOperation?
    private var blockedOperationEntered = false
    private var preparedIndex = 0
    private(set) var events = [Event]()
    private(set) var preparedDispatchIDs = [UUID]()
    private(set) var prepareRequests = [SalemXProductionDispatchPrepareRequest]()
    private(set) var claimRequests = [SalemXProductionDispatchReferenceRequest]()
    private(set) var sendRequests = [SalemXProductionDispatchSendPreparedRequest]()
    private(set) var cancelRequests = [SalemXProductionDispatchReferenceRequest]()
    var prepareResult: Result<SalemXProductionDispatchPrepareResponse, SalemXProductionDispatchClientError>?
    var claimResult: Result<SalemXProductionDispatchClaimResponse, SalemXProductionDispatchClientError>
    var sendResult: Result<SalemXProductionDispatchSendPreparedResponse, SalemXProductionDispatchClientError>

    init(prepareResult: Result<SalemXProductionDispatchPrepareResponse, SalemXProductionDispatchClientError>? = nil,
         claimResult: Result<SalemXProductionDispatchClaimResponse, SalemXProductionDispatchClientError>? = nil,
         sendResult: Result<SalemXProductionDispatchSendPreparedResponse, SalemXProductionDispatchClientError>? = nil,
         dispatchIDs: [UUID] = [UUID(uuid: (0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x41, 0x11, 0x81, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11))],
         blockedOperation: BlockedDispatchOperation? = nil,
         recorder: Stage5EventRecorder? = nil) {
        self.dispatchIDs = dispatchIDs
        self.blockedOperation = blockedOperation
        self.recorder = recorder
        self.prepareResult = prepareResult
        self.claimResult = claimResult ?? .success(.init(dispatchProtocolVersion: 1, state: .claimed, claimed: true, dispatchID: nil))
        self.sendResult = sendResult ?? .success(.init(dispatchProtocolVersion: 1,
                                                       state: .sent,
                                                       apnsSent: true,
                                                       apnsSendCount: 1,
                                                       rawIdentifiersLogged: false,
                                                       dispatchID: nil))
    }

    var dispatchID: UUID {
        dispatchIDs[0]
    }

    var prepareCount: Int {
        events.filter { $0 == .prepare }.count
    }

    var claimCount: Int {
        events.filter { $0 == .claim }.count
    }

    var sendCount: Int {
        events.filter { $0 == .send }.count
    }

    var cancelCount: Int {
        events.filter { $0 == .cancel }.count
    }

    var referenceRequest: SalemXProductionDispatchReferenceRequest {
        .init(dispatchID: dispatchID, senderReference: "sender-reference", appSessionGeneration: "session-generation")
    }

    var sentResponse: SalemXProductionDispatchSendPreparedResponse {
        .init(dispatchProtocolVersion: 1,
              state: .sent,
              apnsSent: true,
              apnsSendCount: 1,
              rawIdentifiersLogged: false,
              dispatchID: nil)
    }

    func registerCapability(_ request: SalemXProductionDispatchCapabilityRegistrationRequest) async
        -> Result<SalemXProductionDispatchCapabilityRegistrationResponse, SalemXProductionDispatchClientError> {
        .failure(.invalidState)
    }

    func prepare(_ request: SalemXProductionDispatchPrepareRequest) async
        -> Result<SalemXProductionDispatchPrepareResponse, SalemXProductionDispatchClientError> {
        events.append(.prepare)
        recorder?.events.append("prepare")
        prepareRequests.append(request)
        guard await continueOperation(.prepare) else { return .failure(.cancelled) }
        if let prepareResult { return prepareResult }
        let dispatchID = dispatchIDs[min(preparedIndex, dispatchIDs.count - 1)]
        preparedIndex += 1
        preparedDispatchIDs.append(dispatchID)
        return .success(.init(dispatchProtocolVersion: 1,
                              dispatchID: dispatchID,
                              senderReference: "sender-reference",
                              receiverReference: "receiver-reference",
                              state: .prepared))
    }

    func claim(_ request: SalemXProductionDispatchReferenceRequest) async
        -> Result<SalemXProductionDispatchClaimResponse, SalemXProductionDispatchClientError> {
        events.append(.claim)
        recorder?.events.append("claim")
        claimRequests.append(request)
        guard await continueOperation(.claim) else { return .failure(.cancelled) }
        return claimResult
    }

    func sendPrepared(_ request: SalemXProductionDispatchSendPreparedRequest) async
        -> Result<SalemXProductionDispatchSendPreparedResponse, SalemXProductionDispatchClientError> {
        events.append(.send)
        recorder?.events.append("send")
        sendRequests.append(request)
        guard await continueOperation(.send) else { return .failure(.cancelled) }
        return sendResult
    }

    func cancelPrepared(_ request: SalemXProductionDispatchReferenceRequest) async
        -> Result<SalemXProductionDispatchCancelResponse, SalemXProductionDispatchClientError> {
        events.append(.cancel)
        cancelRequests.append(request)
        return .success(.init(dispatchProtocolVersion: 1, state: .cancelled, cancelled: true, dispatchID: nil))
    }

    func consume(_ request: SalemXProductionDispatchReceiverConsumeRequest) async
        -> Result<SalemXProductionDispatchReceiverConsumeResponse, SalemXProductionDispatchClientError> {
        fatalError("Unexpected consume")
    }

    func waitUntilBlockedOperationIsEntered() async {
        while !blockedOperationEntered {
            await Task.yield()
        }
    }

    private func continueOperation(_ operation: BlockedDispatchOperation) async -> Bool {
        guard blockedOperation == operation else { return true }
        blockedOperationEntered = true
        while !Task.isCancelled {
            await Task.yield()
        }
        return false
    }
}

@MainActor
private final class Stage5EventRecorder {
    var events = [String]()
}
