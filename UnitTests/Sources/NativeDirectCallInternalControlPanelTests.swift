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
    func productCardRefreshAppliesListenerLifecycleStatus() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy(statuses: [
            .init(state: .canStart,
                  receiverAvailability: .listenerNotArmed,
                  restorationAvailability: .unsupported)
        ])
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        let deferred = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.receiverAvailability == .listenerNotArmed
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await deferred.fulfill()

        let card = viewModel.context.viewState.nativeDirectCallRoomCard
        #expect(card.state == .canStart)
        #expect(card.receiverAvailability == .listenerNotArmed)
        #expect(card.restorationAvailability == .unsupported)
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
    func productCardDoubleStartAudioInvokesHandlerOnceWhilePending() async throws {
        let provider = DelayedNativeDirectCallRoomCardProviderSpy(states: [.canStart], delay: .milliseconds(40))
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        let completed = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .startAudio &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .started
        }

        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.startAudio))
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.startAudio))

        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.isLoading)
        #expect(!NativeDirectCallRoomCardAction.startAudio.isEnabled(in: .canStart, isLoading: true))

        try await completed.fulfill()
        #expect(provider.performedActions == [.startAudio])
    }

    @Test
    func productCardDoubleAcceptInvokesHandlerOnceWhilePending() async throws {
        let provider = DelayedNativeDirectCallRoomCardProviderSpy(states: [.incomingRinging], delay: .milliseconds(40))
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        let incoming = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .incomingRinging
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await incoming.fulfill()

        let completed = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .accept &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .started
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.accept))
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.accept))

        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.isLoading)
        #expect(!NativeDirectCallRoomCardAction.accept.isEnabled(in: .incomingRinging, isLoading: true))
        #expect(!NativeDirectCallRoomCardAction.declineIncoming.isEnabled(in: .incomingRinging, isLoading: true))

        try await completed.fulfill()
        #expect(provider.performedActions == [.accept])
    }

    @Test
    func productCardDoubleHangUpInvokesHandlerOnceWhilePending() async throws {
        let provider = DelayedNativeDirectCallRoomCardProviderSpy(states: [.activeAudio], delay: .milliseconds(40))
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        let active = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .activeAudio
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await active.fulfill()

        let completed = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .hangUp &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .started
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.hangUp))
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.hangUp))

        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.isLoading)
        #expect(!NativeDirectCallRoomCardAction.hangUp.isEnabled(in: .activeAudio, isLoading: true))

        try await completed.fulfill()
        #expect(provider.performedActions == [.hangUp])
    }

    @Test
    func productCardHangUpSuppressesImmediateRestartAfterCompletion() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy(states: [.activeAudio])
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider,
                                                 nativeDirectCallRoomCardPostTerminalStartCooldown: .milliseconds(50))
        self.viewModel = viewModel

        let active = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .activeAudio
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await active.fulfill()

        let completed = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .hangUp &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .hungUp &&
                viewState.nativeDirectCallRoomCard.isStartAudioTemporarilyDisabled
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.hangUp))
        try await completed.fulfill()

        let card = viewModel.context.viewState.nativeDirectCallRoomCard
        #expect(card.state == .canStart)
        #expect(!card.isLoading)
        #expect(!card.isActionEnabled(.startAudio))

        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.startAudio))
        try await Task.sleep(for: .milliseconds(10))

        #expect(provider.performedActions == [.hangUp])
    }

    @Test
    func productCardStartAudioReenablesAfterPostTerminalCooldown() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy(states: [.activeAudio])
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider,
                                                 nativeDirectCallRoomCardPostTerminalStartCooldown: .milliseconds(10))
        self.viewModel = viewModel

        let active = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .activeAudio
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await active.fulfill()

        let hungUp = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .hangUp &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .hungUp &&
                viewState.nativeDirectCallRoomCard.isStartAudioTemporarilyDisabled
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.hangUp))
        try await hungUp.fulfill()

        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.isActionEnabled(.startAudio))

        let restarted = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .startAudio &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .started
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.startAudio))
        try await restarted.fulfill()

        #expect(provider.performedActions == [.hangUp, .startAudio])
    }

    @Test
    func productCardManualRefreshClearsPostTerminalStartSuppression() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy(states: [.activeAudio, .canStart])
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider,
                                                 nativeDirectCallRoomCardPostTerminalStartCooldown: .seconds(5))
        self.viewModel = viewModel

        let active = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .activeAudio
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await active.fulfill()

        let hungUp = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .hangUp &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .hungUp &&
                viewState.nativeDirectCallRoomCard.isStartAudioTemporarilyDisabled
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.hangUp))
        try await hungUp.fulfill()

        let refreshed = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .refreshStatus &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .refreshed &&
                !viewState.nativeDirectCallRoomCard.isStartAudioTemporarilyDisabled
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await refreshed.fulfill()

        #expect(viewModel.context.viewState.nativeDirectCallRoomCard.isActionEnabled(.startAudio))
        #expect(provider.performedActions == [.hangUp])
    }

    @Test
    func productCardCancelAndDeclineSuppressImmediateRestartAfterCompletion() async throws {
        let cancelProvider = NativeDirectCallRoomCardProviderSpy(states: [.outgoingRinging])
        let cancelViewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                       nativeDirectCallRoomStateProvider: cancelProvider,
                                                       nativeDirectCallRoomActionHandler: cancelProvider,
                                                       nativeDirectCallRoomCardPostTerminalStartCooldown: .milliseconds(50))
        viewModel = cancelViewModel

        let outgoing = deferFulfillment(cancelViewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .outgoingRinging
        }
        cancelViewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await outgoing.fulfill()

        let cancelled = deferFulfillment(cancelViewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .cancelOutgoing &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .cancelled &&
                viewState.nativeDirectCallRoomCard.isStartAudioTemporarilyDisabled
        }
        cancelViewModel.context.send(viewAction: .nativeDirectCallRoomCard(.cancelOutgoing))
        try await cancelled.fulfill()

        cancelViewModel.context.send(viewAction: .nativeDirectCallRoomCard(.startAudio))
        try await Task.sleep(for: .milliseconds(10))
        #expect(cancelProvider.performedActions == [.cancelOutgoing])

        let declineProvider = NativeDirectCallRoomCardProviderSpy(states: [.incomingRinging])
        let declineViewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                        nativeDirectCallRoomStateProvider: declineProvider,
                                                        nativeDirectCallRoomActionHandler: declineProvider,
                                                        nativeDirectCallRoomCardPostTerminalStartCooldown: .milliseconds(50))
        viewModel = declineViewModel

        let incoming = deferFulfillment(declineViewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .incomingRinging
        }
        declineViewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await incoming.fulfill()

        let declined = deferFulfillment(declineViewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .declineIncoming &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .declined &&
                viewState.nativeDirectCallRoomCard.isStartAudioTemporarilyDisabled
        }
        declineViewModel.context.send(viewAction: .nativeDirectCallRoomCard(.declineIncoming))
        try await declined.fulfill()

        declineViewModel.context.send(viewAction: .nativeDirectCallRoomCard(.startAudio))
        try await Task.sleep(for: .milliseconds(10))
        #expect(declineProvider.performedActions == [.declineIncoming])
    }

    @Test
    func productCardIgnoresRetryDismissAndRefreshWhileActionPending() async throws {
        let provider = DelayedNativeDirectCallRoomCardProviderSpy(states: [.canStart], delay: .milliseconds(40))
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        let completed = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .startAudio &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .started
        }

        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.startAudio))
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.retry))
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.dismissError))
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))

        try await completed.fulfill()

        #expect(provider.performedActions == [.startAudio])
        #expect(provider.refreshCount == 0)
    }

    @Test
    func productCardDeclineAndCancelDoNotUseElementCallRoute() async throws {
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
        let declined = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .declineIncoming
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.declineIncoming))
        try await declined.fulfill()

        let cancelled = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.lastAction == .cancelOutgoing
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.cancelOutgoing))
        try await cancelled.fulfill()
        try await unexpectedDisplayCall.fulfill()

        #expect(provider.performedActions == [.declineIncoming, .cancelOutgoing])
    }

    @Test
    func productCardRetryRefreshesReadOnlyAfterFailure() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy(states: [
            .failed(reason: .liveKitNetworkFailed),
            .canStart
        ])
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        let failed = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .failed(reason: .liveKitNetworkFailed)
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await failed.fulfill()

        let unexpectedDisplayCall = deferFailure(viewModel.actions, timeout: .seconds(1)) { action in
            if case .displayCall = action {
                return true
            }
            return false
        }
        let retried = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .canStart &&
                viewState.nativeDirectCallRoomCard.lastAction == .retry &&
                viewState.nativeDirectCallRoomCard.lastActionOutcome == .retried
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.retry))
        try await retried.fulfill()
        try await unexpectedDisplayCall.fulfill()

        #expect(provider.refreshCount == 2)
        #expect(provider.performedActions.isEmpty)
    }

    @Test
    func productCardDismissErrorClearsDisplayedFailureLocally() async throws {
        let provider = NativeDirectCallRoomCardProviderSpy(states: [
            .failed(reason: .callServiceUnavailable),
            .failed(reason: .liveKitNetworkFailed)
        ])
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init()),
                                                 nativeDirectCallRoomStateProvider: provider,
                                                 nativeDirectCallRoomActionHandler: provider)
        self.viewModel = viewModel

        let failed = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .failed(reason: .callServiceUnavailable)
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await failed.fulfill()

        let unexpectedDisplayCall = deferFailure(viewModel.actions, timeout: .seconds(1)) { action in
            if case .displayCall = action {
                return true
            }
            return false
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.dismissError))
        try await unexpectedDisplayCall.fulfill()

        let card = viewModel.context.viewState.nativeDirectCallRoomCard
        #expect(card.state == .canStart)
        #expect(card.lastAction == .dismissError)
        #expect(card.lastActionOutcome == .dismissed)
        #expect(provider.refreshCount == 1)
        #expect(provider.performedActions.isEmpty)

        let freshFailure = deferFulfillment(viewModel.context.$viewState) { viewState in
            viewState.nativeDirectCallRoomCard.state == .failed(reason: .liveKitNetworkFailed)
        }
        viewModel.context.send(viewAction: .nativeDirectCallRoomCard(.refreshStatus))
        try await freshFailure.fulfill()

        #expect(provider.refreshCount == 2)
        #expect(provider.performedActions.isEmpty)
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
    }

    @Test
    func productCardActionsHaveStableAccessibilityIdentifiers() {
        let identifiers = NativeDirectCallRoomCardAction.allCases.map(\.accessibilityIdentifier)

        #expect(Set(identifiers).count == NativeDirectCallRoomCardAction.allCases.count)
        #expect(identifiers.contains("nativeDirectCallRoomCard.startAudio"))
        #expect(identifiers.contains("nativeDirectCallRoomCard.accept"))
        #expect(identifiers.contains("nativeDirectCallRoomCard.declineIncoming"))
        #expect(identifiers.contains("nativeDirectCallRoomCard.cancelOutgoing"))
        #expect(identifiers.contains("nativeDirectCallRoomCard.retry"))
        #expect(identifiers.contains("nativeDirectCallRoomCard.dismissError"))
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
        #expect(!NativeDirectCallRoomCardAction.startAudio.isEnabled(in: .canStart, isLoading: true))
        #expect(NativeDirectCallRoomCardAction.accept.isEnabled(in: .incomingRinging, isLoading: false))
        #expect(NativeDirectCallRoomCardAction.declineIncoming.isEnabled(in: .incomingRinging, isLoading: false))
        #expect(!NativeDirectCallRoomCardAction.accept.isEnabled(in: .incomingRinging, isLoading: true))
        #expect(!NativeDirectCallRoomCardAction.declineIncoming.isEnabled(in: .incomingRinging, isLoading: true))
        #expect(!NativeDirectCallRoomCardAction.hangUp.isEnabled(in: .incomingRinging, isLoading: false))
        #expect(NativeDirectCallRoomCardAction.cancelOutgoing.isEnabled(in: .outgoingRinging, isLoading: false))
        #expect(NativeDirectCallRoomCardAction.cancelOutgoing.isEnabled(in: .connecting, isLoading: false))
        #expect(!NativeDirectCallRoomCardAction.cancelOutgoing.isEnabled(in: .outgoingRinging, isLoading: true))
        #expect(!NativeDirectCallRoomCardAction.cancelOutgoing.isEnabled(in: .activeAudio, isLoading: false))
        #expect(NativeDirectCallRoomCardAction.hangUp.isEnabled(in: .activeAudio, isLoading: false))
        #expect(!NativeDirectCallRoomCardAction.hangUp.isEnabled(in: .activeAudio, isLoading: true))
        #expect(NativeDirectCallRoomCardAction.retry.isEnabled(in: .failed(reason: .liveKitNetworkFailed), isLoading: false))
        #expect(NativeDirectCallRoomCardAction.dismissError.isEnabled(in: .failed(reason: .liveKitNetworkFailed), isLoading: false))
        #expect(!NativeDirectCallRoomCardAction.retry.isEnabled(in: .failed(reason: .liveKitNetworkFailed), isLoading: true))
        #expect(!NativeDirectCallRoomCardAction.dismissError.isEnabled(in: .failed(reason: .liveKitNetworkFailed), isLoading: true))
        #expect(NativeDirectCallRoomCardAction.dismissError.isEnabled(in: .ended(reason: .cancelled), isLoading: false))
        #expect(!NativeDirectCallRoomCardAction.hangUp.isEnabled(in: .canStart, isLoading: false))
    }

    @Test
    func productCardVisibleActionsFollowStateModel() {
        #expect(NativeDirectCallRoomCardAction.visibleRows(in: .canStart).flatMap { $0 } == [.refreshStatus, .startAudio])
        #expect(NativeDirectCallRoomCardAction.visibleRows(in: .incomingRinging).flatMap { $0 } == [.refreshStatus, .accept, .declineIncoming])
        #expect(NativeDirectCallRoomCardAction.visibleRows(in: .outgoingRinging).flatMap { $0 } == [.refreshStatus, .cancelOutgoing])
        #expect(NativeDirectCallRoomCardAction.visibleRows(in: .activeAudio).flatMap { $0 } == [.refreshStatus, .hangUp])
        #expect(NativeDirectCallRoomCardAction.visibleRows(in: .failed(reason: .callServiceUnavailable)).flatMap { $0 } == [.retry, .dismissError])
        #expect(NativeDirectCallRoomCardAction.visibleRows(in: .ended(reason: .cancelled)).flatMap { $0 } == [.dismissError])
    }

    @Test
    func productCardViewStateFailedRowsRenderRetryAndDismissOnly() {
        let card = NativeDirectCallRoomCardViewState(isVisible: true,
                                                     isLoading: false,
                                                     state: .failed(reason: .callServiceUnavailable),
                                                     lastAction: .accept,
                                                     lastActionOutcome: .failed)
        let visibleActions = card.visibleActionRows.flatMap { $0 }

        #expect(card.visibleActionRows == [[.retry, .dismissError]])
        #expect(visibleActions.contains(.retry))
        #expect(visibleActions.contains(.dismissError))
        #expect(!visibleActions.contains(.startAudio))
        #expect(!visibleActions.contains(.accept))
        #expect(!visibleActions.contains(.declineIncoming))
        #expect(!visibleActions.contains(.hangUp))
        #expect(NativeDirectCallRoomCardAction.retry.isEnabled(in: card.state, isLoading: card.isLoading))
        #expect(NativeDirectCallRoomCardAction.dismissError.isEnabled(in: card.state, isLoading: card.isLoading))
    }

    @Test
    func productCardReducerMapsTypedSnapshotStates() {
        #expect(Self.reducedCardState(sessionState: .idle, hasActiveSession: false) == .canStart)
        #expect(Self.reducedCardState(sessionState: .idle,
                                      hasActiveSession: false,
                                      mediaState: .failed(.tokenHTTPUnavailable)) == .failed(reason: .callServiceUnavailable))
        #expect(Self.reducedCardState(sessionState: .idle,
                                      hasActiveSession: false,
                                      mediaState: .failed(.liveKitNetworkFailed)) == .failed(reason: .liveKitNetworkFailed))
        #expect(Self.reducedCardState(sessionState: .outgoingRinging) == .outgoingRinging)
        #expect(Self.reducedCardState(sessionState: .incomingRinging) == .incomingRinging)
        #expect(Self.reducedCardState(sessionState: .connecting) == .connecting)
        #expect(Self.reducedCardState(sessionState: .activeAudio,
                                      mediaState: .failed(.liveKitNetworkFailed)) == .activeAudio)
        #expect(Self.reducedCardState(sessionState: .failed,
                                      mediaState: .failed(.tokenHTTPUnavailable)) == .failed(reason: .callServiceUnavailable))
        #expect(Self.reducedCardState(sessionState: .failed,
                                      mediaState: .failed(.liveKitNetworkFailed)) == .failed(reason: .liveKitNetworkFailed))
        #expect(Self.reducedCardState(sessionState: .failed,
                                      terminalReason: .outgoingTimeout) == .failed(reason: .callTimedOut))
        #expect(Self.reducedCardState(sessionState: .ended,
                                      terminalReason: .incomingTimeout) == .ended(reason: .callTimedOut))
        #expect(Self.reducedCardState(sessionState: .missed,
                                      terminalReason: .incomingTimeout) == .ended(reason: .callTimedOut))
    }

    @Test
    func productCardReducerMapsListenerLifecycleStatus() {
        let openRoomRequired = Self.reducedCardStatus(listenerAvailable: false,
                                                      roomAttached: false)
        #expect(openRoomRequired.state == .canStart)
        #expect(openRoomRequired.receiverAvailability == .openRoomRequired)
        #expect(openRoomRequired.restorationAvailability == .unsupported)

        let incomingUnavailable = Self.reducedCardStatus(listenerAvailable: false)
        #expect(incomingUnavailable.receiverAvailability == .listenerUnavailable)

        let listenerNotArmed = Self.reducedCardStatus(ownerAvailable: false,
                                                      listenerAvailable: true,
                                                      listenerStarted: false)
        #expect(listenerNotArmed.receiverAvailability == .listenerNotArmed)

        let listenerNotStarted = Self.reducedCardStatus(ownerAvailable: true,
                                                        listenerAvailable: true,
                                                        listenerStarted: false)
        #expect(listenerNotStarted.receiverAvailability == .listenerNotStarted)

        let readyToReceive = Self.reducedCardStatus(ownerAvailable: true,
                                                    listenerAvailable: true,
                                                    listenerStarted: true)
        #expect(readyToReceive.receiverAvailability == .readyToReceive)
    }

    @Test
    func productCardListenerLifecycleDisplayTextUsesUserSafeCopy() {
        #expect(NativeDirectCallRoomReceiverAvailability.openRoomRequired.displayText == UntranslatedL10n.screenRoomNativeDirectCallOpenRoomRequired)
        #expect(NativeDirectCallRoomReceiverAvailability.listenerUnavailable.displayText == UntranslatedL10n.screenRoomNativeDirectCallIncomingUnavailable)
        #expect(NativeDirectCallRoomReceiverAvailability.listenerNotArmed.displayText == UntranslatedL10n.screenRoomNativeDirectCallListenerNotArmed)
        #expect(NativeDirectCallRoomReceiverAvailability.listenerNotStarted.displayText == UntranslatedL10n.screenRoomNativeDirectCallListenerNotArmed)
        #expect(NativeDirectCallRoomReceiverAvailability.readyToReceive.displayText == UntranslatedL10n.screenRoomNativeDirectCallReadyToReceive)
        #expect(NativeDirectCallRoomRestorationAvailability.unsupported.displayText == UntranslatedL10n.screenRoomNativeDirectCallRestorationNotSupported)
        #expect(NativeDirectCallRoomRestorationAvailability.supported.displayText == nil)
    }

    @Test
    func productCardReducerKeepsDismissedErrorLocalToViewState() {
        let snapshot = NativeDirectCallRoomSnapshot(isActivationEnabled: true,
                                                    disabledReason: nil,
                                                    productionHasActiveSession: false,
                                                    currentSessionState: .idle,
                                                    mediaState: .failed(.tokenHTTPUnavailable))
        let localState = NativeDirectCallRoomCardLocalState(lastAction: .dismissError,
                                                            lastActionOutcome: .dismissed,
                                                            hidesDismissedError: true)
        let reducedState = NativeDirectCallRoomCardStateReducer.reduce(snapshot: snapshot, localState: localState)

        #expect(snapshot.currentSessionState == .idle)
        #expect(snapshot.mediaState == .failed(.tokenHTTPUnavailable))
        #expect(reducedState.state == .canStart)
        #expect(reducedState.lastAction == .dismissError)
        #expect(reducedState.lastActionOutcome == .dismissed)
    }

    @Test
    func productCardActionAvailabilityMatchesPreviousBehavior() {
        let canStartAvailability = NativeDirectCallRoomSnapshot(isActivationEnabled: true,
                                                                disabledReason: nil,
                                                                productionHasActiveSession: false,
                                                                currentSessionState: .idle).actionAvailability
        #expect(canStartAvailability.canRefreshStatus)
        #expect(canStartAvailability.canStartAudio)
        #expect(!canStartAvailability.canAccept)
        #expect(!canStartAvailability.canDeclineIncoming)
        #expect(!canStartAvailability.canCancelOutgoing)
        #expect(!canStartAvailability.canHangUp)
        #expect(!canStartAvailability.canRetry)
        #expect(!canStartAvailability.canDismissError)

        let incomingAvailability = NativeDirectCallRoomSnapshot(isActivationEnabled: true,
                                                                disabledReason: nil,
                                                                productionHasActiveSession: true,
                                                                currentSessionState: .incomingRinging).actionAvailability
        #expect(incomingAvailability.canAccept)
        #expect(incomingAvailability.canDeclineIncoming)
        #expect(!incomingAvailability.canStartAudio)
        #expect(!incomingAvailability.canHangUp)

        let failedAvailability = NativeDirectCallRoomActionAvailability(cardState: .failed(reason: .liveKitNetworkFailed),
                                                                        isLoading: false,
                                                                        isStartAudioTemporarilyDisabled: false)
        #expect(failedAvailability.canRetry)
        #expect(failedAvailability.canDismissError)
        #expect(!failedAvailability.canStartAudio)

        let suppressedAvailability = NativeDirectCallRoomActionAvailability(cardState: .canStart,
                                                                            isLoading: false,
                                                                            isStartAudioTemporarilyDisabled: true)
        #expect(!suppressedAvailability.canStartAudio)

        let inactiveFailedAvailability = NativeDirectCallRoomSnapshot(isActivationEnabled: true,
                                                                      disabledReason: nil,
                                                                      productionHasActiveSession: false,
                                                                      currentSessionState: .idle,
                                                                      mediaState: .failed(.tokenHTTPUnavailable)).actionAvailability
        #expect(!inactiveFailedAvailability.canStartAudio)
        #expect(inactiveFailedAvailability.canRetry)
        #expect(inactiveFailedAvailability.canDismissError)
    }

    @Test
    func productCardStateMappingUsesUserSafeReasons() {
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: false,
                                                   sessionState: "idle",
                                                   mediaFailureReason: .none,
                                                   terminalReason: nil) == .canStart)
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: false,
                                                   sessionState: "idle",
                                                   mediaFailureReason: .tokenHTTPUnavailable,
                                                   terminalReason: nil) == .failed(reason: .callServiceUnavailable))
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: false,
                                                   sessionState: "idle",
                                                   mediaFailureReason: .liveKitNetworkFailed,
                                                   terminalReason: nil) == .failed(reason: .liveKitNetworkFailed))
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
                                                   sessionState: "activeAudio",
                                                   mediaFailureReason: .liveKitNetworkFailed,
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
                                                   sessionState: "failed",
                                                   mediaFailureReason: .tokenHTTPUnavailable,
                                                   terminalReason: nil) == .failed(reason: .callServiceUnavailable))
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: true,
                                                   sessionState: "failed",
                                                   mediaFailureReason: .none,
                                                   terminalReason: .outgoingTimeout) == .failed(reason: .callTimedOut))
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: true,
                                                   sessionState: "ended",
                                                   mediaFailureReason: .none,
                                                   terminalReason: .outgoingTimeout) == .ended(reason: .callTimedOut))
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: true,
                                                   sessionState: "missed",
                                                   mediaFailureReason: .none,
                                                   terminalReason: .incomingTimeout) == .ended(reason: .callTimedOut))
        #expect(NativeDirectCallRoomCardState.make(isActivationEnabled: true,
                                                   disabledReason: nil,
                                                   productionHasActiveSession: true,
                                                   sessionState: "cancelled",
                                                   mediaFailureReason: .none,
                                                   terminalReason: .cancelled) == .ended(reason: .cancelled))
    }

    @Test
    func productCardStateDisplayTextUsesUserSafeCopy() {
        #expect(NativeDirectCallRoomCardState.incomingRinging.displayText == UntranslatedL10n.screenRoomNativeDirectCallIncoming)
        #expect(NativeDirectCallRoomCardState.outgoingRinging.displayText == UntranslatedL10n.screenRoomNativeDirectCallCalling)
        #expect(NativeDirectCallRoomCardState.activeAudio.displayText == UntranslatedL10n.screenRoomNativeDirectCallActive)
        #expect(NativeDirectCallRoomCardState.failed(reason: .callServiceUnavailable).displayText == UntranslatedL10n.screenRoomNativeDirectCallBackendUnavailable)
        #expect(NativeDirectCallRoomCardState.failed(reason: .liveKitNetworkFailed).displayText == UntranslatedL10n.screenRoomNativeDirectCallAudioUnavailable)
        #expect(NativeDirectCallRoomCardState.failed(reason: .callTimedOut).displayText == UntranslatedL10n.screenRoomNativeDirectCallTimedOut)
        #expect(NativeDirectCallRoomCardState.failed(reason: .unverifiedDevice).displayText == UntranslatedL10n.screenRoomNativeDirectCallVerifyBeforeCalling)
        #expect(NativeDirectCallRoomCardState.failed(reason: .roomNotEncrypted).displayText == UntranslatedL10n.screenRoomNativeDirectCallRoomNotEncrypted)
        #expect(NativeDirectCallRoomCardState.failed(reason: .roomNotOneToOne).displayText == UntranslatedL10n.screenRoomNativeDirectCallRoomNotOneToOne)
        #expect(NativeDirectCallRoomCardState.ended(reason: .declined).displayText == UntranslatedL10n.screenRoomNativeDirectCallDeclined)
        #expect(NativeDirectCallRoomCardState.ended(reason: .cancelled).displayText == UntranslatedL10n.screenRoomNativeDirectCallCancelled)
        #expect(NativeDirectCallRoomCardState.ended(reason: .unknown).displayText == UntranslatedL10n.screenRoomNativeDirectCallEnded)
    }

    @Test
    func productCardStateDetailTextUsesUserSafeCopy() {
        #expect(NativeDirectCallRoomCardState.canStart.detailText == UntranslatedL10n.screenRoomNativeDirectCallReadyDetail)
        #expect(NativeDirectCallRoomCardState.incomingRinging.detailText == UntranslatedL10n.screenRoomNativeDirectCallIncomingDetail)
        #expect(NativeDirectCallRoomCardState.outgoingRinging.detailText == UntranslatedL10n.screenRoomNativeDirectCallCallingDetail)
        #expect(NativeDirectCallRoomCardState.connecting.detailText == UntranslatedL10n.screenRoomNativeDirectCallConnectingDetail)
        #expect(NativeDirectCallRoomCardState.activeAudio.detailText == UntranslatedL10n.screenRoomNativeDirectCallActiveDetail)
        #expect(NativeDirectCallRoomCardState.failed(reason: .callServiceUnavailable).detailText == UntranslatedL10n.screenRoomNativeDirectCallBackendUnavailableDetail)
        #expect(NativeDirectCallRoomCardState.failed(reason: .liveKitNetworkFailed).detailText == UntranslatedL10n.screenRoomNativeDirectCallAudioUnavailableDetail)
        #expect(NativeDirectCallRoomCardState.failed(reason: .callTimedOut).detailText == UntranslatedL10n.screenRoomNativeDirectCallTimedOutDetail)
        #expect(NativeDirectCallRoomCardState.failed(reason: .unverifiedDevice).detailText == UntranslatedL10n.screenRoomNativeDirectCallVerifyBeforeCallingDetail)
        #expect(NativeDirectCallRoomCardState.failed(reason: .roomNotEncrypted).detailText == UntranslatedL10n.screenRoomNativeDirectCallRoomNotEncryptedDetail)
        #expect(NativeDirectCallRoomCardState.failed(reason: .roomNotOneToOne).detailText == UntranslatedL10n.screenRoomNativeDirectCallRoomNotOneToOneDetail)
        #expect(NativeDirectCallRoomCardState.ended(reason: .declined).detailText == UntranslatedL10n.screenRoomNativeDirectCallDeclinedDetail)
        #expect(NativeDirectCallRoomCardState.ended(reason: .cancelled).detailText == UntranslatedL10n.screenRoomNativeDirectCallCancelledDetail)
        #expect(NativeDirectCallRoomCardState.ended(reason: .unknown).detailText == UntranslatedL10n.screenRoomNativeDirectCallEndedDetail)
    }

    @Test
    func productCardAllReasonsHaveSafeCopy() {
        for reason in NativeDirectCallRoomCardUnavailableReason.allCases {
            let state = NativeDirectCallRoomCardState.unavailable(reason: reason)
            #expect(!state.displayText.isEmpty)
            #expect(state.detailText?.isEmpty == false)
            #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { !state.displayText.contains($0) })
            #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { state.detailText?.contains($0) == false })
        }

        for reason in NativeDirectCallRoomCardFailureReason.allCases {
            let failedState = NativeDirectCallRoomCardState.failed(reason: reason)
            let endedState = NativeDirectCallRoomCardState.ended(reason: reason)
            #expect(!failedState.displayText.isEmpty)
            #expect(failedState.detailText?.isEmpty == false)
            #expect(!endedState.displayText.isEmpty)
            #expect(endedState.detailText?.isEmpty == false)
            #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { !failedState.displayText.contains($0) })
            #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { failedState.detailText?.contains($0) == false })
            #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { !endedState.displayText.contains($0) })
            #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { endedState.detailText?.contains($0) == false })
        }
    }

    @Test
    func productCardRedactedStatusUsesOnlySafeEnumsAndBooleans() {
        let viewState = NativeDirectCallRoomCardViewState(isVisible: true,
                                                          isLoading: false,
                                                          state: .failed(reason: .liveKitNetworkFailed),
                                                          receiverAvailability: .readyToReceive,
                                                          restorationAvailability: .unsupported,
                                                          lastAction: .startAudio,
                                                          lastActionOutcome: .failed)
        let redactedStatus = viewState.redactedStatus
        let redactedSnapshotStatus = NativeDirectCallRoomCardStatus(state: .unavailable(reason: .roomNotEncrypted),
                                                                    receiverAvailability: .openRoomRequired,
                                                                    restorationAvailability: .unsupported).redactedStatus

        #expect(redactedStatus.state == .failed)
        #expect(redactedStatus.unavailableReason == nil)
        #expect(redactedStatus.failureReason == .liveKitNetworkFailed)
        #expect(redactedStatus.receiverAvailability == .readyToReceive)
        #expect(redactedStatus.restorationAvailability == .unsupported)
        #expect(redactedStatus.actions.canRetry)
        #expect(redactedStatus.actions.canDismissError)
        #expect(!redactedStatus.actions.canStartAudio)

        let description = redactedStatus.description
        #expect(description.contains("state: failed"))
        #expect(description.contains("failureReason: liveKitNetworkFailed"))
        #expect(description.contains("canRetry: true"))
        #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { !description.contains($0) })
        #expect(redactedSnapshotStatus.state == .unavailable)
        #expect(redactedSnapshotStatus.unavailableReason == .roomNotEncrypted)
        #expect(redactedSnapshotStatus.failureReason == nil)
        #expect(redactedSnapshotStatus.receiverAvailability == .openRoomRequired)
    }

    @Test
    func statusDescriptionStaysRedacted() {
        let status = Self.nativeDirectCallStatus(canArmListener: true,
                                                 canStartAudio: true,
                                                 canAccept: false,
                                                 canHangUp: false)
        let description = status.description
        #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { !description.contains($0) })

        let cardStateDescription = NativeDirectCallRoomCardState.failed(reason: .liveKitNetworkFailed).description
        let cardActionDescription = NativeDirectCallRoomCardActionResult(action: .startAudio,
                                                                         outcome: .failed,
                                                                         state: .failed(reason: .liveKitNetworkFailed)).description
        let cardStatusDescription = NativeDirectCallRoomCardStatus(state: .canStart,
                                                                   receiverAvailability: .readyToReceive,
                                                                   restorationAvailability: .unsupported).description
        #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { !cardStateDescription.contains($0) })
        #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { !cardActionDescription.contains($0) })
        #expect(Self.forbiddenNativeDirectCallFragments.allSatisfy { !cardStatusDescription.contains($0) })
    }

    private static let forbiddenNativeDirectCallFragments = [
        "participant" + "_" + "tok" + "en",
        "encrypted" + "_payload",
        "raw " + "key",
        "access" + "_" + "tok" + "en",
        "ey" + "J",
        "room" + "_" + "id",
        "user" + "_" + "id",
        "device" + "_" + "id",
        "Bearer"
    ]

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

    private static func reducedCardState(sessionState: NativeDirectCallRoomSessionState,
                                         hasActiveSession: Bool = true,
                                         mediaState: NativeDirectCallRoomMediaState = .none,
                                         terminalReason: NativeDirectCallRoomTerminalReason = .none) -> NativeDirectCallRoomCardState {
        let snapshot = NativeDirectCallRoomSnapshot(isActivationEnabled: true,
                                                    disabledReason: nil,
                                                    productionHasActiveSession: hasActiveSession,
                                                    currentSessionState: sessionState,
                                                    mediaState: mediaState,
                                                    terminalReason: terminalReason)
        return NativeDirectCallRoomCardStateReducer.reduce(snapshot: snapshot).state
    }

    private static func reducedCardStatus(ownerAvailable: Bool = false,
                                          listenerAvailable: Bool = true,
                                          listenerStarted: Bool = false,
                                          roomAttached: Bool = true,
                                          restorationSupported: Bool = false) -> NativeDirectCallRoomCardStatus {
        let snapshot = NativeDirectCallRoomSnapshot(isActivationEnabled: true,
                                                    disabledReason: nil,
                                                    productionOwnerAvailable: ownerAvailable,
                                                    productionListenerAvailable: listenerAvailable,
                                                    productionListenerStarted: listenerStarted,
                                                    productionRoomAttached: roomAttached,
                                                    productionSessionRestorationSupported: restorationSupported,
                                                    productionHasActiveSession: false,
                                                    currentSessionState: .idle)
        return NativeDirectCallRoomCardStateReducer.status(snapshot: snapshot)
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
    private var statuses: [NativeDirectCallRoomCardStatus]?

    init(states: [NativeDirectCallRoomCardState] = [.canStart]) {
        self.states = states
        statuses = nil
    }

    init(statuses: [NativeDirectCallRoomCardStatus]) {
        states = statuses.map(\.state)
        self.statuses = statuses
    }

    func nativeDirectCallRoomCardState() async -> NativeDirectCallRoomCardState {
        await nativeDirectCallRoomCardStatus().state
    }

    func nativeDirectCallRoomCardStatus() async -> NativeDirectCallRoomCardStatus {
        refreshCount += 1
        if var statuses {
            let status: NativeDirectCallRoomCardStatus
            if statuses.count > 1 {
                status = statuses.removeFirst()
            } else {
                status = statuses.first ?? .init(state: .canStart)
            }
            self.statuses = statuses
            return status
        }

        if states.count > 1 {
            return .init(state: states.removeFirst())
        }

        return .init(state: states.first ?? .canStart)
    }

    func performNativeDirectCallRoomCardAction(_ action: NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult {
        performedActions.append(action)
        if action == .startAudio {
            startAudioCount += 1
        }

        switch action {
        case .refreshStatus:
            return .init(action: action, outcome: .refreshed, state: .canStart)
        case .startAudio:
            return .init(action: action, outcome: .started, state: .outgoingRinging)
        case .accept:
            return .init(action: action, outcome: .accepted, state: .activeAudio)
        case .declineIncoming:
            return .init(action: action, outcome: .declined, state: .canStart)
        case .cancelOutgoing:
            return .init(action: action, outcome: .cancelled, state: .canStart)
        case .hangUp:
            return .init(action: action, outcome: .hungUp, state: .canStart)
        case .retry:
            return .init(action: action, outcome: .retried, state: .canStart)
        case .dismissError:
            return .init(action: action, outcome: .dismissed, state: .canStart)
        }
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
