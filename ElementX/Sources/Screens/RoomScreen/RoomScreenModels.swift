//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK
import OrderedCollections

enum RoomScreenViewModelAction: Equatable {
    case focusEvent(eventID: String)
    case displayThread(threadRootEventID: String, focussedEventID: String)
    case displayPinnedEventsTimeline
    case displayRoomDetails
    case displayCall(startMode: ElementCallStartMode)
    case removeComposerFocus
    case displayKnockRequests
    case displayRoom(roomID: String, via: [String])
    case displayMessageForwarding(MessageForwardingItem)
}

enum RoomScreenViewAction {
    case tappedPinnedEventsBanner
    case viewAllPins
    case displayRoomDetails
    case displayCall(startMode: ElementCallStartMode)
    case nativeDirectCallRoomCardAppeared
    case nativeDirectCallRoomCard(NativeDirectCallRoomCardAction)
    case nativeDirectCallInternalControl(NativeDirectCallInternalControlAction)
    case footerViewAction(RoomScreenFooterViewAction)
    case acceptKnock(eventID: String)
    case dismissKnockRequests
    case viewKnockRequests
    case displaySuccessorRoom
}

struct RoomScreenViewState: BindableState {
    var roomTitle = ""
    var roomAvatar: RoomAvatar
    var dmRecipientVerificationState: UserIdentityVerificationState?
    
    var lastScrollDirection: ScrollDirection?
    // This is used to control the banner
    var pinnedEventsBannerState: PinnedEventsBannerState = .loading(numbersOfEvents: 0)
    var shouldShowPinnedEventsBanner: Bool {
        !pinnedEventsBannerState.isEmpty && lastScrollDirection != .top
    }
    
    var canSendMessage = true
    
    /// Whether or not starting a call is supported.
    var isCallingEnabled = true
    /// Whether or not the user is allowed to join calls in this room.
    var canJoinCall = false
    /// Whether or not this room currently has a call in progress.
    var hasOngoingCall: Bool
    /// Whether or not the user is already part of a call in another room.
    var isParticipatingInOngoingCall = false
    var shouldShowCallButton: Bool {
        isCallingEnabled && !isParticipatingInOngoingCall // Hide the join call button when already in the call
    }
    
    var isKnockingEnabled = false
    var isKnockableRoom = false
    var canAcceptKnocks = false
    var canDeclineKnocks = false
    var canBan = false
    var unseenKnockRequests: [KnockRequestInfo] = []
    var handledEventIDs: Set<String> = []
    
    var hasSuccessor: Bool
    
    var displayedKnockRequests: [KnockRequestInfo] {
        unseenKnockRequests.filter { !handledEventIDs.contains($0.eventID) }
    }
    
    var shouldSeeKnockRequests: Bool {
        isKnockingEnabled &&
            isKnockableRoom &&
            !displayedKnockRequests.isEmpty &&
            (canAcceptKnocks || canDeclineKnocks || canBan)
    }
    
    /// If `enableKeyShareOnInvite` is set, determines the current history sharing state.
    var roomHistorySharingState: RoomHistorySharingState?
    
    var footerDetails: RoomScreenFooterViewDetails?

    var nativeDirectCallRoomCard: NativeDirectCallRoomCardViewState = .hidden
    var nativeDirectCallInternalControlPanel: NativeDirectCallInternalControlPanelState = .hidden
    
    var bindings = RoomScreenViewStateBindings()
}

struct RoomScreenViewStateBindings {
    /// The view model used to present a QuickLook media preview.
    var mediaPreviewViewModel: TimelineMediaPreviewViewModel?
    var alertInfo: AlertInfo<RoomScreenAlertType>?
}

enum RoomScreenAlertType {
    case unknown
}

enum RoomScreenFooterViewAction {
    case resolvePinViolation(userID: String)
    case resolveVerificationViolation(userID: String)
}

enum RoomScreenFooterViewDetails {
    case pinViolation(member: RoomMemberProxyProtocol, learnMoreURL: URL)
    case verificationViolation(member: RoomMemberProxyProtocol, learnMoreURL: URL)
}

@MainActor
enum PinnedEventsBannerState: Equatable {
    case loading(numbersOfEvents: Int)
    case loaded(state: PinnedEventsState)
    
    var isEmpty: Bool {
        switch self {
        case .loaded(let state):
            return state.pinnedEventContents.isEmpty
        case .loading(let numberOfEvents):
            return numberOfEvents == 0
        }
    }
    
    var isLoading: Bool {
        switch self {
        case .loading:
            return true
        default:
            return false
        }
    }
    
    var selectedPinnedEventID: String? {
        switch self {
        case .loaded(let state):
            return state.selectedPinnedEventID
        default:
            return nil
        }
    }
    
    var count: Int {
        switch self {
        case .loaded(let state):
            return state.pinnedEventContents.count
        case .loading(let numberOfEvents):
            return numberOfEvents
        }
    }
    
    var selectedPinnedIndex: Int {
        switch self {
        case .loaded(let state):
            return state.selectedPinnedIndex
        case .loading(let numbersOfEvents):
            // We always want the index to be the last one when loading, since is the default one.
            return numbersOfEvents - 1
        }
    }
    
    var displayedMessage: AttributedString {
        switch self {
        case .loading:
            return AttributedString(L10n.screenRoomPinnedBannerLoadingDescription)
        case .loaded(let state):
            return state.selectedPinnedContent
        }
    }
    
    var bannerIndicatorDescription: AttributedString {
        let index = selectedPinnedIndex + 1
        let boldPlaceholder = "{bold}"
        var finalString = AttributedString(L10n.screenRoomPinnedBannerIndicatorDescription(boldPlaceholder))
        var boldString = AttributedString(L10n.screenRoomPinnedBannerIndicator(index, count))
        boldString.bold()
        finalString.replace(boldPlaceholder, with: boldString)
        return finalString
    }
    
    mutating func previousPin() {
        switch self {
        case .loaded(var state):
            state.previousPin()
            self = .loaded(state: state)
        default:
            break
        }
    }
    
    mutating func setPinnedEventContents(_ pinnedEventContents: OrderedDictionary<String, AttributedString>) {
        switch self {
        case .loading:
            // The default selected event should always be the last one.
            self = .loaded(state: .init(pinnedEventContents: pinnedEventContents, selectedPinnedEventID: pinnedEventContents.keys.last))
        case .loaded(var state):
            state.pinnedEventContents = pinnedEventContents
            self = .loaded(state: state)
        }
    }
    
    /// Note that if we are setting this value, this is definitely sent from the pinned events timeline
    /// so we can assume that the pinned events timeline is already loaded and we only need to set the
    /// selection for the loaded state
    mutating func setSelectedPinnedEventID(_ eventID: String) {
        switch self {
        case .loaded(var state):
            state.selectedPinnedEventID = eventID
            self = .loaded(state: state)
        case .loading:
            break
        }
    }
}

@MainActor
struct PinnedEventsState: Equatable {
    var pinnedEventContents: OrderedDictionary<String, AttributedString> = [:] {
        didSet {
            if selectedPinnedEventID == nil, !pinnedEventContents.keys.isEmpty {
                // The default selected event should always be the last one.
                selectedPinnedEventID = pinnedEventContents.keys.last
            } else if pinnedEventContents.isEmpty {
                selectedPinnedEventID = nil
            } else if let selectedPinnedEventID, !pinnedEventContents.keys.set.contains(selectedPinnedEventID) {
                self.selectedPinnedEventID = pinnedEventContents.keys.last
            }
        }
    }
    
    var selectedPinnedEventID: String?
    
    var selectedPinnedIndex: Int {
        let defaultValue = pinnedEventContents.isEmpty ? 0 : pinnedEventContents.count - 1
        guard let selectedPinnedEventID else {
            return defaultValue
        }
        return pinnedEventContents.keys.firstIndex(of: selectedPinnedEventID) ?? defaultValue
    }
    
    var selectedPinnedContent: AttributedString {
        var content = AttributedString(" ")
        if let selectedPinnedEventID,
           let pinnedEventContent = pinnedEventContents[selectedPinnedEventID] {
            content = pinnedEventContent
        }
        content.font = .compound.bodyMD
        content.link = nil
        return content
    }
    
    mutating func previousPin() {
        guard !pinnedEventContents.isEmpty else {
            return
        }
        let currentIndex = selectedPinnedIndex
        let nextIndex = currentIndex - 1
        if nextIndex == -1 {
            selectedPinnedEventID = pinnedEventContents.keys.last
        } else {
            selectedPinnedEventID = pinnedEventContents.keys[nextIndex % pinnedEventContents.count]
        }
    }
}

@MainActor
protocol NativeDirectCallInternalControlProviding: AnyObject {
    func refreshStatus() async -> NativeDirectCallInternalControlStatus
    func armListener() async -> NativeDirectCallInternalControlActionResult
    func startAudio() async -> NativeDirectCallInternalControlActionResult
    func accept() async -> NativeDirectCallInternalControlActionResult
    func hangUp() async -> NativeDirectCallInternalControlActionResult
}

@MainActor
final class ClosureNativeDirectCallInternalControlProvider: NativeDirectCallInternalControlProviding {
    private let refreshStatusClosure: @MainActor () async -> NativeDirectCallInternalControlStatus
    private let armListenerClosure: @MainActor () async -> NativeDirectCallInternalControlActionResult
    private let startAudioClosure: @MainActor () async -> NativeDirectCallInternalControlActionResult
    private let acceptClosure: @MainActor () async -> NativeDirectCallInternalControlActionResult
    private let hangUpClosure: @MainActor () async -> NativeDirectCallInternalControlActionResult

    init(refreshStatus: @escaping @MainActor () async -> NativeDirectCallInternalControlStatus,
         armListener: @escaping @MainActor () async -> NativeDirectCallInternalControlActionResult,
         startAudio: @escaping @MainActor () async -> NativeDirectCallInternalControlActionResult,
         accept: @escaping @MainActor () async -> NativeDirectCallInternalControlActionResult,
         hangUp: @escaping @MainActor () async -> NativeDirectCallInternalControlActionResult) {
        refreshStatusClosure = refreshStatus
        armListenerClosure = armListener
        startAudioClosure = startAudio
        acceptClosure = accept
        hangUpClosure = hangUp
    }

    func refreshStatus() async -> NativeDirectCallInternalControlStatus {
        await refreshStatusClosure()
    }

    func armListener() async -> NativeDirectCallInternalControlActionResult {
        await armListenerClosure()
    }

    func startAudio() async -> NativeDirectCallInternalControlActionResult {
        await startAudioClosure()
    }

    func accept() async -> NativeDirectCallInternalControlActionResult {
        await acceptClosure()
    }

    func hangUp() async -> NativeDirectCallInternalControlActionResult {
        await hangUpClosure()
    }
}

enum NativeDirectCallInternalControlAction: String, CaseIterable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case refreshStatus
    case armListener
    case startAudio
    case accept
    case hangUp

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }

    #if DEBUG
    static let panelRows: [[Self]] = [
        [.refreshStatus, .armListener],
        [.startAudio, .accept, .hangUp]
    ]

    var buttonTitle: String {
        switch self {
        case .refreshStatus:
            "Refresh"
        case .armListener:
            "Arm listener"
        case .startAudio:
            "Start audio"
        case .accept:
            "Accept"
        case .hangUp:
            "Hang up"
        }
    }

    func isEnabled(in status: NativeDirectCallInternalControlStatus, isLoading: Bool) -> Bool {
        switch self {
        case .refreshStatus:
            return true
        case .armListener:
            return !isLoading && status.canArmListener
        case .startAudio:
            return !isLoading && status.canStartAudio
        case .accept:
            return !isLoading && status.canAccept
        case .hangUp:
            return !isLoading && status.canHangUp
        }
    }
    #endif
}

enum NativeDirectCallInternalControlAvailability: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case hidden
    case notRefreshed
    case unavailable
    case canStart
    case outgoingRinging
    case incomingRinging
    case connecting
    case activeAudio
    case activeVideo
    case failed
    case ended

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallInternalControlStatus: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let availability: NativeDirectCallInternalControlAvailability
    let activationReason: String
    let peerTrustReadiness: String
    let sessionState: String
    let encryptionState: String
    let mediaFailureReason: String
    let terminalReason: String
    let lastAction: NativeDirectCallInternalControlAction?
    let lastActionOutcome: String
    let lastActionReason: String
    let canArmListener: Bool
    let canStartAudio: Bool
    let canAccept: Bool
    let canHangUp: Bool

    static let hidden = Self(availability: .hidden,
                             activationReason: "none",
                             peerTrustReadiness: "unknown",
                             sessionState: "hidden",
                             encryptionState: "none",
                             mediaFailureReason: "none",
                             terminalReason: "none",
                             lastAction: nil,
                             lastActionOutcome: "none",
                             lastActionReason: "none",
                             canArmListener: false,
                             canStartAudio: false,
                             canAccept: false,
                             canHangUp: false)

    static let notRefreshed = Self(availability: .notRefreshed,
                                   activationReason: "notRefreshed",
                                   peerTrustReadiness: "unknown",
                                   sessionState: "notRefreshed",
                                   encryptionState: "none",
                                   mediaFailureReason: "none",
                                   terminalReason: "none",
                                   lastAction: nil,
                                   lastActionOutcome: "none",
                                   lastActionReason: "none",
                                   canArmListener: false,
                                   canStartAudio: false,
                                   canAccept: false,
                                   canHangUp: false)

    static func unavailable(reason: String) -> Self {
        Self(availability: .unavailable,
             activationReason: reason,
             peerTrustReadiness: "unknown",
             sessionState: "unavailable",
             encryptionState: "none",
             mediaFailureReason: "none",
             terminalReason: "none",
             lastAction: nil,
             lastActionOutcome: "none",
             lastActionReason: reason,
             canArmListener: false,
             canStartAudio: false,
             canAccept: false,
             canHangUp: false)
    }

    var description: String {
        let fields = [
            "availability: \(availability)",
            "activationReason: \(activationReason)",
            "peerTrustReadiness: \(peerTrustReadiness)",
            "sessionState: \(sessionState)",
            "encryptionState: \(encryptionState)",
            "mediaFailureReason: \(mediaFailureReason)",
            "terminalReason: \(terminalReason)",
            "lastAction: \(lastAction?.description ?? "none")",
            "lastActionOutcome: \(lastActionOutcome)",
            "lastActionReason: \(lastActionReason)",
            "canArmListener: \(canArmListener)",
            "canStartAudio: \(canStartAudio)",
            "canAccept: \(canAccept)",
            "canHangUp: \(canHangUp)"
        ]
        return "NativeDirectCallInternalControlStatus(\(fields.joined(separator: ", ")))"
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallInternalControlActionResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let action: NativeDirectCallInternalControlAction
    let outcome: String
    let reason: String
    let status: NativeDirectCallInternalControlStatus

    static func unavailable(action: NativeDirectCallInternalControlAction, reason: String) -> Self {
        .init(action: action,
              outcome: "blocked",
              reason: reason,
              status: .unavailable(reason: reason))
    }

    var description: String {
        "NativeDirectCallInternalControlActionResult(action: \(action), outcome: \(outcome), reason: \(reason), status: \(status))"
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallInternalControlPanelState: Equatable {
    var isVisible: Bool
    var isLoading: Bool
    var status: NativeDirectCallInternalControlStatus

    static let hidden = Self(isVisible: false, isLoading: false, status: .hidden)
    static let visible = Self(isVisible: true, isLoading: false, status: .notRefreshed)
}

enum NativeDirectCallRoomCardUnavailableReason: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case nativeCallsUnavailable
    case serverUnsupported
    case roomNotEncrypted
    case roomNotOneToOne
    case unverifiedDevice
    case peerTrustUnavailable
    case callServiceUnavailable
    case liveKitNetworkFailed
    case callTimedOut
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallRoomCardFailureReason: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case nativeCallsUnavailable
    case serverUnsupported
    case roomNotEncrypted
    case roomNotOneToOne
    case unverifiedDevice
    case peerTrustUnavailable
    case callServiceUnavailable
    case liveKitNetworkFailed
    case callTimedOut
    case declined
    case cancelled
    case unknown

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallRoomCardState: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case hidden
    case unavailable(reason: NativeDirectCallRoomCardUnavailableReason)
    case canStart
    case outgoingRinging
    case incomingRinging
    case connecting
    case activeAudio
    case failed(reason: NativeDirectCallRoomCardFailureReason)
    case ended(reason: NativeDirectCallRoomCardFailureReason)

    var description: String {
        switch self {
        case .hidden:
            "hidden"
        case .unavailable(let reason):
            "unavailable(\(reason))"
        case .canStart:
            "canStart"
        case .outgoingRinging:
            "outgoingRinging"
        case .incomingRinging:
            "incomingRinging"
        case .connecting:
            "connecting"
        case .activeAudio:
            "activeAudio"
        case .failed(let reason):
            "failed(\(reason))"
        case .ended(let reason):
            "ended(\(reason))"
        }
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallRoomCardAction: String, CaseIterable, Equatable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    case refreshStatus
    case startAudio
    case accept
    case declineIncoming
    case cancelOutgoing
    case hangUp
    case retry
    case dismissError

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }

    #if DEBUG
    var buttonTitle: String {
        switch self {
        case .refreshStatus:
            UntranslatedL10n.screenRoomNativeDirectCallActionRefresh
        case .startAudio:
            UntranslatedL10n.screenRoomNativeDirectCallActionStartAudio
        case .accept:
            UntranslatedL10n.screenRoomNativeDirectCallActionAccept
        case .declineIncoming:
            UntranslatedL10n.screenRoomNativeDirectCallActionDecline
        case .cancelOutgoing:
            UntranslatedL10n.screenRoomNativeDirectCallActionCancel
        case .hangUp:
            UntranslatedL10n.screenRoomNativeDirectCallActionHangUp
        case .retry:
            L10n.actionRetry
        case .dismissError:
            L10n.actionDismiss
        }
    }

    var accessibilityIdentifier: String {
        "nativeDirectCallRoomCard.\(rawValue)"
    }

    func isEnabled(in state: NativeDirectCallRoomCardState, isLoading: Bool) -> Bool {
        switch self {
        case .refreshStatus:
            true
        case .startAudio:
            !isLoading && state == .canStart
        case .accept, .declineIncoming:
            !isLoading && state == .incomingRinging
        case .cancelOutgoing:
            !isLoading && Self.cancelEnabledStates.contains(state)
        case .hangUp:
            !isLoading && state == .activeAudio
        case .retry:
            !isLoading && state.isFailed
        case .dismissError:
            !isLoading && state.isDismissible
        }
    }

    static func visibleRows(in state: NativeDirectCallRoomCardState) -> [[Self]] {
        switch state {
        case .hidden:
            []
        case .unavailable:
            [[.refreshStatus]]
        case .canStart:
            [[.refreshStatus, .startAudio]]
        case .outgoingRinging:
            [[.refreshStatus, .cancelOutgoing]]
        case .incomingRinging:
            [[.refreshStatus, .accept, .declineIncoming]]
        case .connecting:
            [[.refreshStatus, .cancelOutgoing]]
        case .activeAudio:
            [[.refreshStatus, .hangUp]]
        case .failed:
            [[.retry, .dismissError]]
        case .ended:
            [[.dismissError]]
        }
    }

    private static let cancelEnabledStates: [NativeDirectCallRoomCardState] = [
        .outgoingRinging,
        .connecting
    ]
    #endif
}

enum NativeDirectCallRoomCardActionOutcome: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case refreshed
    case started
    case accepted
    case declined
    case cancelled
    case hungUp
    case retried
    case dismissed
    case blocked
    case failed

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallRoomCardActionResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let action: NativeDirectCallRoomCardAction
    let outcome: NativeDirectCallRoomCardActionOutcome
    let state: NativeDirectCallRoomCardState

    static func blocked(action: NativeDirectCallRoomCardAction,
                        reason: NativeDirectCallRoomCardUnavailableReason) -> Self {
        .init(action: action, outcome: .blocked, state: .unavailable(reason: reason))
    }

    var description: String {
        "NativeDirectCallRoomCardActionResult(action: \(action), outcome: \(outcome), state: \(state))"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
protocol NativeDirectCallRoomStateProviding: AnyObject {
    func nativeDirectCallRoomCardState() async -> NativeDirectCallRoomCardState
}

@MainActor
protocol NativeDirectCallRoomActionHandling: AnyObject {
    func performNativeDirectCallRoomCardAction(_ action: NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult
}

@MainActor
final class ClosureNativeDirectCallRoomCardProvider: NativeDirectCallRoomStateProviding, NativeDirectCallRoomActionHandling {
    private let stateClosure: @MainActor () async -> NativeDirectCallRoomCardState
    private let actionClosure: @MainActor (NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult

    init(state: @escaping @MainActor () async -> NativeDirectCallRoomCardState,
         action: @escaping @MainActor (NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult) {
        stateClosure = state
        actionClosure = action
    }

    func nativeDirectCallRoomCardState() async -> NativeDirectCallRoomCardState {
        await stateClosure()
    }

    func performNativeDirectCallRoomCardAction(_ action: NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult {
        await actionClosure(action)
    }
}

struct NativeDirectCallRoomCardViewState: Equatable {
    var isVisible: Bool
    var isLoading: Bool
    var isStartAudioTemporarilyDisabled = false
    var state: NativeDirectCallRoomCardState
    var lastAction: NativeDirectCallRoomCardAction?
    var lastActionOutcome: NativeDirectCallRoomCardActionOutcome?

    static let hidden = Self(isVisible: false,
                             isLoading: false,
                             state: .hidden,
                             lastAction: nil,
                             lastActionOutcome: nil)

    static let visible = Self(isVisible: true,
                              isLoading: false,
                              state: .unavailable(reason: .nativeCallsUnavailable),
                              lastAction: nil,
                              lastActionOutcome: nil)

    #if DEBUG
    var visibleActionRows: [[NativeDirectCallRoomCardAction]] {
        NativeDirectCallRoomCardAction.visibleRows(in: state)
    }

    func isActionEnabled(_ action: NativeDirectCallRoomCardAction) -> Bool {
        guard action != .startAudio || !isStartAudioTemporarilyDisabled else {
            return false
        }

        return action.isEnabled(in: state, isLoading: isLoading)
    }
    #endif
}

#if DEBUG
extension NativeDirectCallRoomCardActionOutcome {
    init(_ productionStartOutcome: NativeDirectCallProductionStartOutcome) {
        switch productionStartOutcome {
        case .started:
            self = .started
        case .blocked:
            self = .blocked
        case .engineFailure:
            self = .failed
        }
    }

    init(acceptOutcome: NativeDirectCallProductionStartOutcome) {
        switch acceptOutcome {
        case .started:
            self = .accepted
        case .blocked:
            self = .blocked
        case .engineFailure:
            self = .failed
        }
    }

    init(declineOutcome: NativeDirectCallProductionHangupOutcome) {
        switch declineOutcome {
        case .hungUp:
            self = .declined
        case .blocked:
            self = .blocked
        case .engineFailure:
            self = .failed
        }
    }

    init(cancelOutcome: NativeDirectCallProductionHangupOutcome) {
        switch cancelOutcome {
        case .hungUp:
            self = .cancelled
        case .blocked:
            self = .blocked
        case .engineFailure:
            self = .failed
        }
    }

    init(hangUpOutcome: NativeDirectCallProductionHangupOutcome) {
        switch hangUpOutcome {
        case .hungUp:
            self = .hungUp
        case .blocked:
            self = .blocked
        case .engineFailure:
            self = .failed
        }
    }
}

extension NativeDirectCallRoomCardState {
    static func make(triggerDiagnostic: NativeDirectCallProductionTriggerDryRunDiagnostic,
                     productionStatus: NativeDirectCallProductionStatus) -> Self {
        make(isActivationEnabled: triggerDiagnostic.isEnabled,
             disabledReason: triggerDiagnostic.blockedReason,
             productionHasActiveSession: productionStatus.productionHasActiveSession,
             sessionState: productionStatus.productionSessionState,
             mediaFailureReason: productionStatus.productionMediaFailureReason,
             terminalReason: productionStatus.productionLastTerminalReason)
    }

    static func make(isActivationEnabled: Bool,
                     disabledReason: DirectCallProductionActivationDisabledReason?,
                     productionHasActiveSession: Bool,
                     sessionState: String,
                     mediaFailureReason: DirectCallDiagnosticMediaFailureReason,
                     terminalReason: DirectCallDiagnosticTerminalReason?) -> Self {
        guard productionHasActiveSession else {
            if isActivationEnabled {
                return .canStart
            }

            return .unavailable(reason: .init(disabledReason))
        }

        switch sessionState {
        case "outgoingRinging":
            return .outgoingRinging
        case "incomingRinging":
            return .incomingRinging
        case "connecting":
            return .connecting
        case "activeAudio":
            return .activeAudio
        case "failed":
            if let terminalReason,
               terminalReason == .outgoingTimeout || terminalReason == .incomingTimeout {
                return .failed(reason: .callTimedOut)
            }

            return .failed(reason: .init(mediaFailureReason))
        case "ended", "cancelled", "missed":
            return .ended(reason: .init(terminalReason))
        default:
            return .unavailable(reason: .unknown)
        }
    }
}

extension NativeDirectCallRoomCardState {
    var displayText: String {
        switch self {
        case .hidden:
            ""
        case .unavailable(let reason):
            reason.displayText
        case .canStart:
            UntranslatedL10n.screenRoomNativeDirectCallReady
        case .outgoingRinging:
            UntranslatedL10n.screenRoomNativeDirectCallCalling
        case .incomingRinging:
            UntranslatedL10n.screenRoomNativeDirectCallIncoming
        case .connecting:
            UntranslatedL10n.screenRoomNativeDirectCallConnecting
        case .activeAudio:
            UntranslatedL10n.screenRoomNativeDirectCallActive
        case .failed(let reason):
            reason.displayText
        case .ended(let reason):
            reason.displayText
        }
    }

    fileprivate var isFailed: Bool {
        if case .failed = self {
            return true
        }

        return false
    }

    fileprivate var isDismissible: Bool {
        switch self {
        case .failed, .ended:
            true
        case .hidden, .unavailable, .canStart, .outgoingRinging, .incomingRinging, .connecting, .activeAudio:
            false
        }
    }
}

private extension NativeDirectCallRoomCardUnavailableReason {
    var displayText: String {
        switch self {
        case .unverifiedDevice, .peerTrustUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallVerifyBeforeCalling
        case .liveKitNetworkFailed:
            UntranslatedL10n.screenRoomNativeDirectCallCouldntConnectAudio
        case .callTimedOut:
            UntranslatedL10n.screenRoomNativeDirectCallEnded
        case .nativeCallsUnavailable,
             .serverUnsupported,
             .roomNotEncrypted,
             .roomNotOneToOne,
             .callServiceUnavailable,
             .unknown:
            UntranslatedL10n.screenRoomNativeDirectCallServiceUnavailable
        }
    }
}

private extension NativeDirectCallRoomCardFailureReason {
    var displayText: String {
        switch self {
        case .unverifiedDevice, .peerTrustUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallVerifyBeforeCalling
        case .liveKitNetworkFailed:
            UntranslatedL10n.screenRoomNativeDirectCallCouldntConnectAudio
        case .callTimedOut:
            UntranslatedL10n.screenRoomNativeDirectCallEnded
        case .declined:
            UntranslatedL10n.screenRoomNativeDirectCallDeclined
        case .cancelled:
            UntranslatedL10n.screenRoomNativeDirectCallCancelled
        case .nativeCallsUnavailable,
             .serverUnsupported,
             .roomNotEncrypted,
             .roomNotOneToOne,
             .callServiceUnavailable,
             .unknown:
            UntranslatedL10n.screenRoomNativeDirectCallServiceUnavailable
        }
    }
}

private extension NativeDirectCallRoomCardUnavailableReason {
    init(_ disabledReason: DirectCallProductionActivationDisabledReason?) {
        switch disabledReason {
        case .serverCapabilityUnavailable,
             .serverCapabilityDisabled,
             .unsupportedCapabilityVersion,
             .unsupportedIntent,
             .unsupportedMediaTransport,
             .e2eeNotRequiredByCapability,
             .unsupportedKeyEnvelope:
            self = .serverUnsupported
        case .roomNotEncrypted:
            self = .roomNotEncrypted
        case .roomNotDirect, .roomNotOneToOne:
            self = .roomNotOneToOne
        case .unverifiedDevice:
            self = .unverifiedDevice
        case .peerTrustUnavailable,
             .noEligibleDevice,
             .crossSigningUnavailable,
             .peerTrustUnknown:
            self = .peerTrustUnavailable
        case .appRolloutDisabled,
             .roomUnavailable,
             .peerUnavailable,
             .none:
            self = .nativeCallsUnavailable
        default:
            self = .callServiceUnavailable
        }
    }
}

private extension NativeDirectCallRoomCardFailureReason {
    init(_ mediaFailureReason: DirectCallDiagnosticMediaFailureReason) {
        switch mediaFailureReason {
        case .none:
            self = .unknown
        case .liveKitConnectFailed,
             .liveKitURLInvalid,
             .liveKitURLUnreachable,
             .liveKitNetworkFailed,
             .liveKitSDKError,
             .liveKitUnknown:
            self = .liveKitNetworkFailed
        case .factoryUnavailable,
             .credentialUnavailable,
             .e2eeContextUnavailable,
             .keyBridgeMiss,
             .mediaFactoryUnavailable,
             .mediaE2EEContextUnavailable,
             .mediaConnectFailed,
             .mediaSetupUnavailable,
             .mediaUnsupportedIntent,
             .invalidSessionState,
             .liveKitRoomJoinFailed,
             .liveKitE2EEConfigFailed:
            self = .callServiceUnavailable
        case .unknown:
            self = .unknown
        default:
            self = .callServiceUnavailable
        }
    }

    init(_ terminalReason: DirectCallDiagnosticTerminalReason?) {
        switch terminalReason {
        case .outgoingTimeout, .incomingTimeout:
            self = .callTimedOut
        case .connectingFailed:
            self = .liveKitNetworkFailed
        case .cancelled:
            self = .cancelled
        case .hangup:
            self = .unknown
        case .failed, .unknown, .none:
            self = .unknown
        }
    }
}

extension NativeDirectCallInternalControlStatus {
    static func make(triggerDiagnostic: NativeDirectCallProductionTriggerDryRunDiagnostic,
                     productionStatus: NativeDirectCallProductionStatus,
                     lastAction: NativeDirectCallInternalControlAction? = nil,
                     lastActionOutcome: String = "none",
                     lastActionReason: String = "none") -> Self {
        let activationReason = triggerDiagnostic.blockedReason?.description ?? "none"
        let availability = availability(triggerDiagnostic: triggerDiagnostic, productionStatus: productionStatus)
        let canArmListener = triggerDiagnostic.isEnabled && (!productionStatus.productionListenerStarted || productionStatus.productionSessionState == "idle")
        let canStartAudio = triggerDiagnostic.isEnabled && !productionStatus.productionHasActiveSession
        let canAccept = triggerDiagnostic.isEnabled && productionStatus.productionSessionState == "incomingRinging"
        let canHangUp = productionStatus.productionHasActiveSession && hangUpEnabledStates.contains(productionStatus.productionSessionState)

        return Self(availability: availability,
                    activationReason: activationReason,
                    peerTrustReadiness: triggerDiagnostic.peerTrustReadiness.description,
                    sessionState: productionStatus.productionSessionState,
                    encryptionState: productionStatus.productionEncryptionState,
                    mediaFailureReason: productionStatus.productionMediaFailureReason.description,
                    terminalReason: productionStatus.productionLastTerminalReason?.description ?? "none",
                    lastAction: lastAction,
                    lastActionOutcome: lastActionOutcome,
                    lastActionReason: lastActionReason,
                    canArmListener: canArmListener,
                    canStartAudio: canStartAudio,
                    canAccept: canAccept,
                    canHangUp: canHangUp)
    }

    private static let hangUpEnabledStates = Set(["outgoingRinging", "incomingRinging", "connecting", "activeAudio", "activeVideo", "ending"])

    private static func availability(triggerDiagnostic: NativeDirectCallProductionTriggerDryRunDiagnostic,
                                     productionStatus: NativeDirectCallProductionStatus) -> NativeDirectCallInternalControlAvailability {
        if productionStatus.productionHasActiveSession {
            switch productionStatus.productionSessionState {
            case "outgoingRinging":
                return .outgoingRinging
            case "incomingRinging":
                return .incomingRinging
            case "connecting":
                return .connecting
            case "activeAudio":
                return .activeAudio
            case "activeVideo":
                return .activeVideo
            case "failed":
                return .failed
            case "ended", "cancelled", "missed":
                return .ended
            default:
                return .unavailable
            }
        }

        return triggerDiagnostic.isEnabled ? .canStart : .unavailable
    }
}
#endif
