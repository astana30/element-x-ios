//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

#if DEBUG
@testable import ElementX
import MatrixRustSDKMocks
import Testing

@MainActor
final class NativeDirectCallInternalControlPanelTests {
    private var viewModel: RoomScreenViewModel!

    init() async throws {
        AppSettings.resetAllSettings()
    }

    deinit {
        AppSettings.resetAllSettings()
    }

    @Test
    func panelHiddenByDefault() {
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()))
        self.viewModel = viewModel

        #expect(viewModel.context.viewState.nativeDirectCallInternalControlPanel.isVisible == false)
        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.isVisible == false)
    }

    @Test
    func productCardVisibleWithProviderAndRefreshesExplicitly() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy()
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.isVisible)
        #expect(provider.refreshCount == 0)

        let deferred = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .canStart
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await deferred.fulfill()

        #expect(provider.refreshCount == 1)
        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.isLoading == false)
    }

    @Test
    func productCardRefreshesReadOnlyOnFirstAppearance() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy()
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.state == .unavailable(reason: .nativeCallsUnavailable))

        let deferred = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .canStart
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCardAppeared)
        try await deferred.fulfill()

        #expect(provider.refreshCount == 1)
        #expect(provider.performedActions.isEmpty)
        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.lastAction == nil)
        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.lastActionOutcome == nil)

        viewModel.context.send(viewAction: .nativeDirectCallRoomCardAppeared)
        #expect(provider.refreshCount == 1)
        #expect(provider.performedActions.isEmpty)
    }

    @Test
    func productCardRunsReadOnlyFollowUpRefreshAfterEarlyUnavailableState() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy(states: [
            .unavailable(reason: .nativeCallsUnavailable),
            .canStart
        ])
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider,
                                                 nativeDirectCallRoomCardAppearanceFollowUpDelay: .milliseconds(10),
                                                 nativeDirectCallRoomCardAppearanceFollowUpRefreshCount: 1)
        self.viewModel = viewModel

        let deferred = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .canStart
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCardAppeared)
        try await deferred.fulfill()

        #expect(provider.refreshCount == 2)
        #expect(provider.performedActions.isEmpty)
        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.lastAction == nil)
        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.lastActionOutcome == nil)
    }

    @Test
    func productCardPassivelyRefreshesRemoteStateChangesAfterAppearance() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy(states: [
            .canStart,
            .canStart,
            .incomingRinging
        ])
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider,
                                                 nativeDirectCallRoomCardAppearanceFollowUpDelay: .milliseconds(10),
                                                 nativeDirectCallRoomCardAppearanceFollowUpRefreshCount: 2)
        self.viewModel = viewModel

        let deferred = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .incomingRinging
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCardAppeared)
        try await deferred.fulfill()

        #expect(provider.refreshCount == 3)
        #expect(provider.performedActions.isEmpty)
        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.lastAction == nil)
        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.lastActionOutcome == nil)
    }

    @Test
    func productCardPassiveFollowUpRefreshDoesNotDisableActions() async throws {
        let provider = DelayedNativeDirectCallRoomCardProviderSpy(states: [
            .canStart,
            .incomingRinging
        ], delay: .milliseconds(40))
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider,
                                                 nativeDirectCallRoomCardAppearanceFollowUpDelay: .milliseconds(10),
                                                 nativeDirectCallRoomCardAppearanceFollowUpRefreshCount: 10)
        self.viewModel = viewModel

        let canStart = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .canStart && !viewState.nativeDirectCallRoomCard.isLoading
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCardAppeared)
        try await canStart.fulfill()

        let incoming = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .incomingRinging
        }
        try await Task.sleep(for: .milliseconds(25))

        let card = viewModel.context.viewState.nativeDirectCallRoomCard
        #expect(card.state == .canStart)
        #expect(!card.isLoading)
        #expect(NativeDirectCallRoomCardAction.startAudio.isEnabled(in: card.state, isLoading: card.isLoading))

        try await incoming.fulfill()
        #expect(provider.refreshCount >= 2)
        #expect(provider.performedActions.isEmpty)
    }

    @Test
    func productCardStartAudioDoesNotUseElementCallRoute() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy()
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        let unexpectedDisplayCall = deferFailure(viewModel.actions, timeout: .seconds(1)) { action in
            if case .displayCall = action {
                return true
            }
            return false
        }
        let deferred = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .startAudio
        }

        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.startAudio))
        try await deferred.fulfill()
        try await unexpectedDisplayCall.fulfill()

        #expect(provider.startAudioCount == 1)
    }

    @Test
    func panelVisibleWithProviderAndRefreshesExplicitly() async throws {
        let provider = NativeDirectCallInternalControlProviderSpy()
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallInternalControlProvider: provider)
        self.viewModel = viewModel

        #expect(viewModel.context.viewState.nativeDirectCallInternalControlPanel.isVisible)
        #expect(provider.refreshCount == 0)

        let deferred = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallInternalControlPanel.status.availability == .canStart
        }
        viewModel.context.send(viewAction: .nativeDirectCallInternalControl(.refreshStatus))
        try await deferred.fulfill()

        #expect(provider.refreshCount == 1)
        #expect(viewModel.context.viewState.nativeDirectCallInternalControlPanel.isLoading == false)
    }

    @Test
    func startAudioDoesNotUseElementCallRoute() async throws {
        let provider = NativeDirectCallInternalControlProviderSpy()
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallInternalControlProvider: provider)
        self.viewModel = viewModel

        let unexpectedDisplayCall = deferFailure(viewModel.actions, timeout: .seconds(1)) { action in
            if case .displayCall = action {
                return true
            }
            return false
        }
        let deferred = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallInternalControlPanel.status.lastAction == .startAudio
        }

        viewModel.context.send(viewAction: .nativeDirectCallInternalControl(.startAudio))
        try await deferred.fulfill()
        try await unexpectedDisplayCall.fulfill()

        #expect(provider.startAudioCount == 1)
    }

    @Test
    func panelUsesCompactActionRows() {
        let rows = NativeDirectCallInternalControlAction.panelRows

        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.count <= 3 })
        #expect(rows.flatMap { $0 } == NativeDirectCallInternalControlAction.allCases)

        let cardRows = NativeDirectCallRoomCardAction.cardRows
        #expect(cardRows.count == 2)
        #expect(cardRows.allSatisfy { $0.count <= 3 })
        #expect(cardRows.flatMap { $0 } == NativeDirectCallRoomCardAction.allCases)
    }

    @Test
    func productCardActionsHaveStableAccessibilityIdentifiers() {
        let identifiers = NativeDirectCallRoomCardAction.allCases.map(\.accessibilityIdentifier)

        #expect(Set(identifiers).count == NativeDirectCallRoomCardAction.allCases.count)
        #expect(identifiers.contains("nativeDirectCallRoomCard.startAudio"))
        #expect(identifiers.contains("nativeDirectCallRoomCard.accept"))
        #expect(identifiers.contains("nativeDirectCallRoomCard.hangUp"))
    }

    @Test
    func actionEnablementFollowsStateModel() {
        let canStartStatus = Self.nativeDirectCallStatus(canArmListener: true,
                                                         canStartAudio: true,
                                                         canAccept: false,
                                                         canHangUp: false)
        #expect(NativeDirectCallInternalControlAction.refreshStatus.isEnabled(in: canStartStatus, isLoading: true))
        #expect(NativeDirectCallInternalControlAction.armListener.isEnabled(in: canStartStatus, isLoading: false))
        #expect(!NativeDirectCallInternalControlAction.armListener.isEnabled(in: canStartStatus, isLoading: true))
        #expect(NativeDirectCallInternalControlAction.startAudio.isEnabled(in: canStartStatus, isLoading: false))
        #expect(!NativeDirectCallInternalControlAction.accept.isEnabled(in: canStartStatus, isLoading: false))
        #expect(!NativeDirectCallInternalControlAction.hangUp.isEnabled(in: canStartStatus, isLoading: false))

        let incomingStatus = Self.nativeDirectCallStatus(availability: .incomingRinging,
                                                         sessionState: "incomingRinging",
                                                         canArmListener: false,
                                                         canStartAudio: false,
                                                         canAccept: true,
                                                         canHangUp: true)
        #expect(!NativeDirectCallInternalControlAction.startAudio.isEnabled(in: incomingStatus, isLoading: false))
        #expect(NativeDirectCallInternalControlAction.accept.isEnabled(in: incomingStatus, isLoading: false))
        #expect(NativeDirectCallInternalControlAction.hangUp.isEnabled(in: incomingStatus, isLoading: false))

        let activeStatus = Self.nativeDirectCallStatus(availability: .activeAudio,
                                                       sessionState: "activeAudio",
                                                       canArmListener: false,
                                                       canStartAudio: false,
                                                       canAccept: false,
                                                       canHangUp: true)
        #expect(!NativeDirectCallInternalControlAction.accept.isEnabled(in: activeStatus, isLoading: false))
        #expect(NativeDirectCallInternalControlAction.hangUp.isEnabled(in: activeStatus, isLoading: false))

        #expect(NativeDirectCallRoomCardAction.refreshStatus.isEnabled(in: .canStart, isLoading: true))
        #expect(NativeDirectCallRoomCardAction.startAudio.isEnabled(in: .canStart, isLoading: false))
        #expect(!NativeDirectCallRoomCardAction.startAudio.isEnabled(in: .incomingRinging, isLoading: false))
        #expect(NativeDirectCallRoomCardAction.accept.isEnabled(in: .incomingRinging, isLoading: false))
        #expect(NativeDirectCallRoomCardAction.decline.isEnabled(in: .incomingRinging, isLoading: false))
        #expect(NativeDirectCallRoomCardAction.hangUp.isEnabled(in: .incomingRinging, isLoading: false))
        #expect(NativeDirectCallRoomCardAction.hangUp.isEnabled(in: .activeAudio, isLoading: false))
        #expect(!NativeDirectCallRoomCardAction.hangUp.isEnabled(in: .canStart, isLoading: false))
        #expect(!NativeDirectCallRoomCardAction.startAudio.isEnabled(in: .canStart, isLoading: true))
    }

    @Test
    func productCardStateMappingUsesUserSafeReasons() {
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: false,
                                                   sessionState: "idle",
                                                   mediaFailureReason: .none,
                                                   terminalReason: nil) == .canStart)
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: false,
                                                   disabledReason: .unverifiedDevice,
                                                   productionHasActiveSession: false,
                                                   sessionState: "idle",
                                                   mediaFailureReason: .none,
                                                   terminalReason: nil) == .unavailable(reason: .unverifiedDevice))
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: true,
                                                   sessionState: "incomingRinging",
                                                   mediaFailureReason: .none,
                                                   terminalReason: nil) == .incomingRinging)
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: true,
                                                   sessionState: "outgoingRinging",
                                                   mediaFailureReason: .none,
                                                   terminalReason: nil) == .outgoingRinging)
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: true,
                                                   sessionState: "activeAudio",
                                                   mediaFailureReason: .none,
                                                   terminalReason: nil) == .activeAudio)
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: true,
                                                   sessionState: "failed",
                                                   mediaFailureReason: .liveKitNetworkFailed,
                                                   terminalReason: nil) == .failed(reason: .liveKitNetworkFailed))
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: true,
                                                   sessionState: "ended",
                                                   mediaFailureReason: .none,
                                                   terminalReason: .outgoingTimeout) == .ended(reason: .callTimedOut))
    }

    @Test
    func statusDescriptionStaysRedacted() {
        let status = Self.nativeDirectCallStatus(canArmListener: true,
                                                 canStartAudio: true,
                                                 canAccept: false,
                                                 canHangUp: false)
        let description = status.description
        let forbiddenFragments = [
            "participant" + "_" + "tok" + "en",
            "encrypted" + "_payload",
            "raw " + "key",
            "access" + "_" + "tok" + "en",
            "ey" + "J"
        ]

        #expect(forbiddenFragments.allSatisfy { !description.contains($0) })

        let cardStateDescription = NativeDirectCallRoomCardState.failed(reason: .liveKitNetworkFailed).description
        let cardActionDescription = NativeDirectCallRoomCardActionResult(action: .startAudio,
                                                                         outcome: .failed,
                                                                         state: .failed(reason: .liveKitNetworkFailed)).description
        #expect(forbiddenFragments.allSatisfy { !cardStateDescription.contains($0) })
        #expect(forbiddenFragments.allSatisfy { !cardActionDescription.contains($0) })
    }

    private static func nativeDirectCallStatus(availability: NativeDirectCallInternalControlAvailability = .canStart,
                                               sessionState: String = "idle",
                                               canArmListener: Bool,
                                               canStartAudio: Bool,
                                               canAccept: Bool,
                                               canHangUp: Bool) -> NativeDirectCallInternalControlStatus {
        .init(availability: availability,
              activationReason: "none",
              peerTrustReadiness: "peerTrustReady",
              sessionState: sessionState,
              encryptionState: "none",
              mediaFailureReason: "none",
              terminalReason: "none",
              lastAction: nil,
              lastActionOutcome: "none",
              lastActionReason: "none",
              canArmListener: canArmListener,
              canStartAudio: canStartAudio,
              canAccept: canAccept,
              canHangUp: canHangUp)
    }
}

@MainActor
private final class NativeDirectCallInternalControlProviderSpy: NativeDirectCallInternalControlProviding {
    private(set) var refreshCount = 0
    private(set) var startAudioCount = 0

    func refreshStatus() async -> NativeDirectCallInternalControlStatus {
        refreshCount += 1
        return Self.status(lastAction: .refreshStatus)
    }

    func armListener() async -> NativeDirectCallInternalControlActionResult {
        .init(action: .armListener,
              outcome: "started",
              reason: "none",
              status: Self.status(lastAction: .armListener))
    }

    func startAudio() async -> NativeDirectCallInternalControlActionResult {
        startAudioCount += 1
        return .init(action: .startAudio,
                     outcome: "started",
                     reason: "none",
                     status: Self.status(lastAction: .startAudio))
    }

    func accept() async -> NativeDirectCallInternalControlActionResult {
        .init(action: .accept,
              outcome: "started",
              reason: "none",
              status: Self.status(lastAction: .accept))
    }

    func hangUp() async -> NativeDirectCallInternalControlActionResult {
        .init(action: .hangUp,
              outcome: "hungUp",
              reason: "none",
              status: Self.status(lastAction: .hangUp))
    }

    private static func status(lastAction: NativeDirectCallInternalControlAction?) -> NativeDirectCallInternalControlStatus {
        .init(availability: .canStart,
              activationReason: "none",
              peerTrustReadiness: "peerTrustReady",
              sessionState: "idle",
              encryptionState: "none",
              mediaFailureReason: "none",
              terminalReason: "none",
              lastAction: lastAction,
              lastActionOutcome: "started",
              lastActionReason: "none",
              canArmListener: true,
              canStartAudio: true,
              canAccept: false,
              canHangUp: false)
    }
}

@MainActor
private final class NativeDirectCallRoomCardProviderSpy: NativeDirectCallRoomStateProviding, NativeDirectCallRoomActionHandling {
    private(set) var refreshCount = 0
    private(set) var startAudioCount = 0
    private(set) var performedActions = [NativeDirectCallRoomCardAction]()
    private var states: [NativeDirectCallRoomCardState]

    init(states: [NativeDirectCallRoomCardState] = [.canStart]) {
        self.states = states
    }

    func nativeDirectCallRoomCardState() async -> NativeDirectCallRoomCardState {
        refreshCount += 1
        if states.count > 1 {
            return states.removeFirst()
        }

        return states.first ?? .canStart
    }

    func performNativeDirectCallRoomCardAction(_ action: NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult {
        performedActions.append(action)
        if action == .startAudio {
            startAudioCount += 1
        }

        return .init(action: action,
                     outcome: action == .startAudio ? .started : .refreshed,
                     state: action == .startAudio ? .outgoingRinging : .canStart)
    }
}

@MainActor
private final class DelayedNativeDirectCallRoomCardProviderSpy: NativeDirectCallRoomStateProviding, NativeDirectCallRoomActionHandling {
    private(set) var refreshCount = 0
    private(set) var performedActions = [NativeDirectCallRoomCardAction]()
    private let delay: Duration
    private var states: [NativeDirectCallRoomCardState]

    init(states: [NativeDirectCallRoomCardState], delay: Duration) {
        self.states = states
        self.delay = delay
    }

    func nativeDirectCallRoomCardState() async -> NativeDirectCallRoomCardState {
        refreshCount += 1
        try? await Task.sleep(for: delay)
        if states.count > 1 {
            return states.removeFirst()
        }

        return states.first ?? .canStart
    }

    func performNativeDirectCallRoomCardAction(_ action: NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult {
        performedActions.append(action)
        return .init(action: action, outcome: .started, state: .outgoingRinging)
    }
}
#endif
