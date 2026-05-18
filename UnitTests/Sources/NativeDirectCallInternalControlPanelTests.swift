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
#endif
