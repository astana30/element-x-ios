//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI
import WysiwygComposer

struct RoomScreen: View {
    @ObservedObject private var context: RoomScreenViewModelType.Context
    @ObservedObject private var timelineContext: TimelineViewModelType.Context
    let composerToolbar: ComposerToolbar
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

    init(context: RoomScreenViewModelType.Context,
         timelineContext: TimelineViewModelType.Context,
         composerToolbar: ComposerToolbar) {
        self.context = context
        self.timelineContext = timelineContext
        self.composerToolbar = composerToolbar
    }

    var body: some View {
        TimelineView(timelineContext: timelineContext)
            .overlay(alignment: .bottomTrailing) {
                TimelineScrollToBottomButton(isVisible: isAtBottomAndLive) {
                    timelineContext.send(viewAction: .scrollToBottom)
                }
                .accessibilityIdentifier(A11yIdentifiers.roomScreen.scrollToBottom)
            }
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .topBanner(pinnedItemsBanner, isVisible: context.viewState.shouldShowPinnedEventsBanner && !isVoiceOverEnabled)
            // This can overlay on top of the pinnedItemsBanner
            .topBanner(knockRequestsBanner, isVisible: context.viewState.shouldSeeKnockRequests)
            .safeAreaInset(edge: .top) {
                // When VoiceOver is enabled, the table view isn't reversed and the scroll gestures
                // don't trigger meaning the banner never hides itself and so the .overlay layout
                // above permanently obscures the top of the timeline. So whenever VoiceOver is
                // enabled we use a safe area inset to vertically stack it above the timeline.
                if context.viewState.shouldShowPinnedEventsBanner, isVoiceOverEnabled {
                    pinnedItemsBanner
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    RoomScreenFooterView(details: context.viewState.footerDetails,
                                         mediaProvider: context.mediaProvider) { action in
                        context.send(viewAction: .footerViewAction(action))
                    }

                    #if DEBUG
                    if context.viewState.nativeDirectCallRoomCard.isVisible {
                        NativeDirectCallRoomCard(state: context.viewState.nativeDirectCallRoomCard) { action in
                            context.send(viewAction: action)
                        }
                    }

                    if context.viewState.nativeDirectCallInternalControlPanel.isVisible {
                        NativeDirectCallInternalControlPanel(state: context.viewState.nativeDirectCallInternalControlPanel) { action in
                            context.send(viewAction: action)
                        }
                    }
                    #endif
                    
                    composer
                        .padding(.top, 8)
                        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
                        .environmentObject(timelineContext)
                        .environment(\.timelineContext, timelineContext)
                        // Make sure the reply header honours the hideTimelineMedia setting too.
                        .environment(\.shouldAutomaticallyLoadImages, !timelineContext.viewState.hideTimelineMedia)
                }
            }
            .toolbarRole(RoomHeaderView.toolbarRole)
            .navigationTitle(L10n.screenRoomTitle) // Hidden but used for back button text.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .toolbarBackground(.visible, for: .navigationBar) // Fix the toolbar's background.
            .overlay { loadingIndicator }
            .alert(item: $context.alertInfo)
            .timelineMediaPreview(viewModel: $context.mediaPreviewViewModel)
            .track(screen: .Room)
            .sentryTrace("\(Self.self)")
    }
    
    private var pinnedItemsBanner: some View {
        PinnedItemsBannerView(state: context.viewState.pinnedEventsBannerState,
                              onMainButtonTap: { context.send(viewAction: .tappedPinnedEventsBanner) },
                              onViewAllButtonTap: { context.send(viewAction: .viewAllPins) })
    }
    
    private var knockRequestsBanner: some View {
        KnockRequestsBannerView(requests: context.viewState.displayedKnockRequests,
                                onDismiss: dismissKnockRequestsBanner,
                                onAccept: context.viewState.canAcceptKnocks ? acceptKnockRequest : nil,
                                onViewAll: onViewAllKnockRequests,
                                mediaProvider: context.mediaProvider)
            .padding(.top, 16)
    }
    
    private func dismissKnockRequestsBanner() {
        context.send(viewAction: .dismissKnockRequests)
    }
    
    private func acceptKnockRequest(eventID: String) {
        context.send(viewAction: .acceptKnock(eventID: eventID))
    }
    
    private func onViewAllKnockRequests() {
        context.send(viewAction: .viewKnockRequests)
    }
    
    private var isAtBottomAndLive: Bool {
        timelineContext.isScrolledToBottom && timelineContext.viewState.timelineState.isLive
    }
    
    @ViewBuilder
    private var composer: some View {
        if context.viewState.hasSuccessor {
            tombstonedDialogue
        } else if context.viewState.canSendMessage, !ProcessInfo.isRunningAccessibilityTests {
            // We are not sure why but when wrapped in the room screen the composer toolbar breaks the accessibility tests
            composerToolbar
        } else {
            ComposerDisabledView()
        }
    }
    
    private var tombstonedDialogue: some View {
        VStack(spacing: 16) {
            Text(L10n.screenRoomTimelineTombstonedRoomMessage)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
            
            Button {
                context.send(viewAction: .displaySuccessorRoom)
            } label: {
                Text(L10n.screenRoomTimelineTombstonedRoomAction)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.compound(.primary, size: .medium))
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .highlight(gradient: .compound.info, borderColor: .compound.borderInfoSubtle)
    }
    
    @ViewBuilder
    private var loadingIndicator: some View {
        if timelineContext.viewState.showLoading {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.compound.textPrimary)
                .padding(16)
                .background(.ultraThickMaterial)
                .cornerRadius(8)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // .principal + .primaryAction works better than .navigation leading + trailing
        // as the latter disables interaction in the action button for rooms with long names
        ToolbarItem(placement: .principal) {
            RoomHeaderView(roomName: context.viewState.roomTitle,
                           roomAvatar: context.viewState.roomAvatar,
                           dmRecipientVerificationState: context.viewState.dmRecipientVerificationState,
                           roomHistorySharingState: context.viewState.roomHistorySharingState,
                           mediaProvider: context.mediaProvider) {
                context.send(viewAction: .displayRoomDetails)
            }
        }
        
        if !ProcessInfo.processInfo.isiOSAppOnMac {
            ToolbarItem(placement: .primaryAction) {
                if context.viewState.shouldShowCallButton {
                    callButton
                        .disabled(!context.viewState.canJoinCall)
                }
            }
        }
    }
    
    @ViewBuilder
    private var callButton: some View {
        if timelineContext.viewState.isDirectOneToOneRoom {
            HStack(spacing: 16) {
                Button {
                    context.send(viewAction: .displayCall(startMode: .audio))
                } label: {
                    Image(systemName: "phone.fill")
                }
                .accessibilityLabel(L10n.a11yStartVoiceCall)
                .accessibilityIdentifier(A11yIdentifiers.roomScreen.voiceCall)
                
                Button {
                    context.send(viewAction: .displayCall(startMode: .video))
                } label: {
                    CompoundIcon(\.videoCallSolid)
                }
                .accessibilityLabel(L10n.a11yStartCall)
                .accessibilityIdentifier(A11yIdentifiers.roomScreen.videoCall)
            }
        } else if context.viewState.hasOngoingCall {
            JoinCallButton {
                context.send(viewAction: .displayCall(startMode: .video))
            }
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.joinCall)
        } else {
            Button {
                context.send(viewAction: .displayCall(startMode: .video))
            } label: {
                CompoundIcon(\.videoCallSolid)
            }
            .accessibilityLabel(L10n.a11yStartCall)
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.joinCall)
        }
    }
}

#if DEBUG
struct NativeDirectCallRoomCard: View {
    let state: NativeDirectCallRoomCardViewState
    let send: (RoomScreenViewAction) -> Void

    var body: some View {
        if state.state != .hidden {
            VStack(alignment: .leading, spacing: 10) {
                header
                statusLine
                actionRows
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.compound.bgSubtleSecondary)
            .overlay(alignment: .top) {
                Divider()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nativeDirectCallRoomCard")
            .task {
                send(.nativeDirectCallRoomCardAppeared)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(UntranslatedL10n.screenRoomNativeDirectCallTitle)
                .font(.compound.bodySMSemibold)
                .foregroundStyle(.compound.textPrimary)

            Text(UntranslatedL10n.screenRoomNativeDirectCallPilotBadge)
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.compound.bgCanvasDefault)
                .clipShape(Capsule())

            Spacer()

            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.state.displayText)
                    .font(.compound.bodyXS)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(2)

                if let detailText = state.state.detailText {
                    Text(detailText)
                        .font(.compound.bodyXS)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let receiverAvailability = state.receiverAvailability {
                statusDetail(title: UntranslatedL10n.screenRoomNativeDirectCallIncomingLabel,
                             value: receiverAvailability.displayText)
            }

            if let restorationText = state.restorationAvailability?.displayText {
                statusDetail(title: UntranslatedL10n.screenRoomNativeDirectCallRelaunchLabel,
                             value: restorationText)
            }
        }
        .accessibilityLabel(state.accessibilitySummary)
    }

    private func statusDetail(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(title):")
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
            Text(value)
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(2)
        }
    }

    private var actionRows: some View {
        VStack(spacing: 6) {
            ForEach(state.visibleActionRows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { action in
                        cardButton(action,
                                   isEnabled: state.isActionEnabled(action)) {
                            send(.nativeDirectCallRoomCard(action))
                        }
                    }
                }
            }
        }
    }

    private func cardButton(_ cardAction: NativeDirectCallRoomCardAction, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(cardAction.buttonTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.compound(.secondary, size: .small))
        .frame(maxWidth: .infinity)
        .disabled(!isEnabled)
        .accessibilityIdentifier(cardAction.accessibilityIdentifier)
    }
}

struct NativeDirectCallRoomCard_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 0) {
                previewCard(state: .canStart,
                            receiverAvailability: .readyToReceive)
                previewCard(state: .incomingRinging,
                            receiverAvailability: .readyToReceive)
                previewCard(state: .outgoingRinging,
                            receiverAvailability: .readyToReceive)
                previewCard(state: .activeAudio,
                            receiverAvailability: .readyToReceive)
                previewCard(state: .failed(reason: .callServiceUnavailable),
                            receiverAvailability: .readyToReceive)
                previewCard(state: .failed(reason: .liveKitNetworkFailed),
                            receiverAvailability: .readyToReceive)
                previewCard(state: .unavailable(reason: .peerTrustUnavailable),
                            receiverAvailability: .readyToReceive)
                previewCard(state: .canStart,
                            receiverAvailability: .openRoomRequired,
                            restorationAvailability: .unsupported)
                previewCard(state: .ended(reason: .callTimedOut),
                            receiverAvailability: .readyToReceive)
            }
        }
        .background(Color.compound.bgCanvasDefault)
        .previewDisplayName("Native direct call card")
    }

    private static func previewCard(state: NativeDirectCallRoomCardState,
                                    receiverAvailability: NativeDirectCallRoomReceiverAvailability?,
                                    restorationAvailability: NativeDirectCallRoomRestorationAvailability? = nil) -> some View {
        NativeDirectCallRoomCard(state: .init(isVisible: true,
                                              isLoading: false,
                                              state: state,
                                              receiverAvailability: receiverAvailability,
                                              restorationAvailability: restorationAvailability,
                                              lastAction: nil,
                                              lastActionOutcome: nil)) { _ in }
    }
}

struct NativeDirectCallInternalControlPanel: View {
    let state: NativeDirectCallInternalControlPanelState
    let send: (RoomScreenViewAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Native call controls")
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textPrimary)

                Spacer()

                if state.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            statusGrid

            controlButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.compound.bgCanvasDefault)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityIdentifier("nativeDirectCallInternalControlPanel")
    }

    private var controlButtons: some View {
        VStack(spacing: 6) {
            ForEach(NativeDirectCallInternalControlAction.panelRows.indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(NativeDirectCallInternalControlAction.panelRows[rowIndex], id: \.self) { action in
                        controlButton(action.buttonTitle, isEnabled: action.isEnabled(in: state.status, isLoading: state.isLoading)) {
                            send(.nativeDirectCallInternalControl(action))
                        }
                    }
                }
            }
        }
    }

    private var statusGrid: some View {
        VStack(alignment: .leading, spacing: 3) {
            statusLine("Availability", state.status.availability.description)
            statusLine("Activation", state.status.activationReason)
            statusLine("Peer trust", state.status.peerTrustReadiness)
            statusLine("Session", state.status.sessionState)
            statusLine("Encryption", state.status.encryptionState)
            statusLine("Media", state.status.mediaFailureReason)
            statusLine("Terminal", state.status.terminalReason)
            statusLine("Last action", lastActionDescription)
        }
    }

    private var lastActionDescription: String {
        guard let lastAction = state.status.lastAction else {
            return "none"
        }

        return "\(lastAction.description):\(state.status.lastActionOutcome):\(state.status.lastActionReason)"
    }

    private func statusLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(title):")
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
            Text(value)
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textPrimary)
        }
        .lineLimit(1)
    }

    private func controlButton(_ title: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.compound(.secondary, size: .small))
        .frame(maxWidth: .infinity)
        .disabled(!isEnabled)
    }
}
#endif

// MARK: - Previews

struct RoomScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModels = makeViewModels()
    static let directMessageViewModels = makeViewModels(isDirect: true, hasOngoingCall: false)
    static let readOnlyViewModels = makeViewModels(canSendMessage: false)
    static let tombstonedViewModels = makeViewModels(hasSuccessor: true)

    static var previews: some View {
        ElementNavigationStack {
            RoomScreen(context: viewModels.room.context,
                       timelineContext: viewModels.timeline.context,
                       composerToolbar: ComposerToolbar.mock())
        }
        .previewDisplayName("Normal")
        
        ElementNavigationStack {
            RoomScreen(context: readOnlyViewModels.room.context,
                       timelineContext: readOnlyViewModels.timeline.context,
                       composerToolbar: ComposerToolbar.mock())
        }
        .previewDisplayName("Read-only")
        .snapshotPreferences(expect: readOnlyViewModels.room.context.$viewState.map { !$0.canSendMessage })
        
        ElementNavigationStack {
            RoomScreen(context: directMessageViewModels.room.context,
                       timelineContext: directMessageViewModels.timeline.context,
                       composerToolbar: ComposerToolbar.mock())
        }
        .previewDisplayName("Direct message")
        
        ElementNavigationStack {
            RoomScreen(context: tombstonedViewModels.room.context,
                       timelineContext: tombstonedViewModels.timeline.context,
                       composerToolbar: ComposerToolbar.mock())
        }
        .previewDisplayName("Tombstoned")
        .snapshotPreferences(expect: tombstonedViewModels.room.context.$viewState.map(\.hasSuccessor))
    }
    
    static func makeViewModels(canSendMessage: Bool = true,
                               hasSuccessor: Bool = false,
                               isDirect: Bool = false,
                               hasOngoingCall: Bool = true) -> ViewModels {
        let roomProxyMock = JoinedRoomProxyMock(.init(id: "stable_id",
                                                      name: "Preview room",
                                                      isDirect: isDirect,
                                                      hasOngoingCall: hasOngoingCall,
                                                      successor: hasSuccessor ? .init(roomId: UUID().uuidString, reason: nil) : nil,
                                                      powerLevelsConfiguration: .init(canUserSendMessage: canSendMessage)))
        let roomViewModel = RoomScreenViewModel.mock(roomProxyMock: roomProxyMock)
        let timelineViewModel = TimelineViewModel(roomProxy: roomProxyMock,
                                                  timelineController: MockTimelineController(),
                                                  userSession: UserSessionMock(.init()),
                                                  mediaPlayerProvider: MediaPlayerProviderMock(),
                                                  userIndicatorController: ServiceLocator.shared.userIndicatorController,
                                                  appMediator: AppMediatorMock.default,
                                                  appSettings: ServiceLocator.shared.settings,
                                                  analyticsService: ServiceLocator.shared.analytics,
                                                  emojiProvider: EmojiProvider(appSettings: ServiceLocator.shared.settings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        
        return .init(room: roomViewModel, timeline: timelineViewModel)
    }
    
    struct ViewModels {
        let room: RoomScreenViewModelProtocol
        let timeline: TimelineViewModelProtocol
    }
}
