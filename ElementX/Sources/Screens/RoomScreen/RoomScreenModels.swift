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

enum NativeDirectCallRoomCardUnavailableReason: String, CaseIterable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case nativeCallsUnavailable
    case accountNotEligible
    case peerNotEligible
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

enum NativeDirectCallRoomCardFailureReason: String, CaseIterable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
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

enum NativeDirectCallRoomReceiverAvailability: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case openRoomRequired
    case listenerUnavailable
    case listenerNotArmed
    case listenerNotStarted
    case readyToReceive

    #if DEBUG
    init(snapshot: NativeDirectCallRoomSnapshot) {
        if !snapshot.productionRoomAttached {
            self = .openRoomRequired
        } else if !snapshot.productionListenerAvailable {
            self = .listenerUnavailable
        } else if !snapshot.productionOwnerAvailable {
            self = .listenerNotArmed
        } else if !snapshot.productionListenerStarted {
            self = .listenerNotStarted
        } else {
            self = .readyToReceive
        }
    }
    #endif

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallRoomRestorationAvailability: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case supported
    case unsupported

    #if DEBUG
    init(snapshot: NativeDirectCallRoomSnapshot) {
        self = snapshot.productionSessionRestorationSupported ? .supported : .unsupported
    }
    #endif

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallInternalPilotActivationDryRunDecision: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case disabled
    case unavailable
    case statusOnly
    case activationAllowed

    init(_ activation: NativeDirectCallInternalPilotActivation) {
        switch activation {
        case .disabled:
            self = .disabled
        case .unavailable:
            self = .unavailable
        case .eligibleForStatusOnly:
            self = .statusOnly
        case .activationAllowed:
            self = .activationAllowed
        }
    }

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallInternalPilotActivationDryRunStatus: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let isEnabled: Bool
    let decision: NativeDirectCallInternalPilotActivationDryRunDecision
    let reason: NativeDirectCallInternalPilotActivationUnavailableReason?
    let isProductUIEnabled: Bool
    let isInternalPilotRolloutEnabled: Bool
    let isCapabilityPresent: Bool
    let isEligibilityReady: Bool
    let isRoomEligible: Bool
    let isPeerTrustReady: Bool
    let areDependenciesReady: Bool
    let hasActiveSession: Bool

    static let disabled = Self(isEnabled: false,
                               decision: .disabled,
                               reason: nil,
                               isProductUIEnabled: false,
                               isInternalPilotRolloutEnabled: false,
                               isCapabilityPresent: false,
                               isEligibilityReady: false,
                               isRoomEligible: false,
                               isPeerTrustReady: false,
                               areDependenciesReady: false,
                               hasActiveSession: false)

    init(isEnabled: Bool,
         activation: NativeDirectCallInternalPilotActivation,
         context: NativeDirectCallInternalPilotActivationContext) {
        self.init(isEnabled: isEnabled,
                  decision: .init(activation),
                  reason: Self.reason(for: activation, context: context),
                  isProductUIEnabled: context.isProductUIEnabled,
                  isInternalPilotRolloutEnabled: context.isInternalPilotRolloutEnabled,
                  isCapabilityPresent: context.isCapabilityPresent,
                  isEligibilityReady: context.eligibility == .eligible,
                  isRoomEligible: context.roomEligibility.isEncrypted &&
                      context.roomEligibility.isDirect &&
                      context.roomEligibility.hasExactlyTwoJoinedMembers &&
                      context.roomEligibility.hasPeerUserID,
                  isPeerTrustReady: context.peerTrustReadiness == .peerTrustReady,
                  areDependenciesReady: context.areDependenciesReady,
                  hasActiveSession: context.hasActiveSession)
    }

    init(isEnabled: Bool,
         decision: NativeDirectCallInternalPilotActivationDryRunDecision,
         reason: NativeDirectCallInternalPilotActivationUnavailableReason?,
         isProductUIEnabled: Bool,
         isInternalPilotRolloutEnabled: Bool,
         isCapabilityPresent: Bool,
         isEligibilityReady: Bool = false,
         isRoomEligible: Bool,
         isPeerTrustReady: Bool,
         areDependenciesReady: Bool,
         hasActiveSession: Bool) {
        self.isEnabled = isEnabled
        self.decision = decision
        self.reason = reason
        self.isProductUIEnabled = isProductUIEnabled
        self.isInternalPilotRolloutEnabled = isInternalPilotRolloutEnabled
        self.isCapabilityPresent = isCapabilityPresent
        self.isEligibilityReady = isEligibilityReady
        self.isRoomEligible = isRoomEligible
        self.isPeerTrustReady = isPeerTrustReady
        self.areDependenciesReady = areDependenciesReady
        self.hasActiveSession = hasActiveSession
    }

    var description: String {
        [
            "internalPilotActivationDryRunEnabled=\(isEnabled)",
            "internalPilotActivationDecision=\(decision)",
            "internalPilotActivationReason=\(reason?.description ?? "none")",
            "isProductUIEnabled=\(isProductUIEnabled)",
            "isInternalPilotRolloutEnabled=\(isInternalPilotRolloutEnabled)",
            "isCapabilityPresent=\(isCapabilityPresent)",
            "isEligibilityReady=\(isEligibilityReady)",
            "isRoomEligible=\(isRoomEligible)",
            "isPeerTrustReady=\(isPeerTrustReady)",
            "areDependenciesReady=\(areDependenciesReady)",
            "hasActiveSession=\(hasActiveSession)"
        ].joined(separator: ", ")
    }

    var debugDescription: String {
        description
    }

    private static func reason(for activation: NativeDirectCallInternalPilotActivation,
                               context: NativeDirectCallInternalPilotActivationContext) -> NativeDirectCallInternalPilotActivationUnavailableReason? {
        switch activation {
        case .disabled:
            context.isInternalPilotRolloutEnabled ? nil : .rolloutDisabled
        case .unavailable(let reason):
            reason
        case .eligibleForStatusOnly,
             .activationAllowed:
            nil
        }
    }
}

struct NativeDirectCallRoomCardStatus: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let state: NativeDirectCallRoomCardState
    let receiverAvailability: NativeDirectCallRoomReceiverAvailability?
    let restorationAvailability: NativeDirectCallRoomRestorationAvailability?
    let internalPilotActivationDryRun: NativeDirectCallInternalPilotActivationDryRunStatus

    init(state: NativeDirectCallRoomCardState,
         receiverAvailability: NativeDirectCallRoomReceiverAvailability? = nil,
         restorationAvailability: NativeDirectCallRoomRestorationAvailability? = nil,
         internalPilotActivationDryRun: NativeDirectCallInternalPilotActivationDryRunStatus = .disabled) {
        self.state = state
        self.receiverAvailability = receiverAvailability
        self.restorationAvailability = restorationAvailability
        self.internalPilotActivationDryRun = internalPilotActivationDryRun
    }

    var description: String {
        [
            "state: \(state)",
            "receiverAvailability: \(receiverAvailability?.description ?? "none")",
            "restorationAvailability: \(restorationAvailability?.description ?? "none")",
            "\(internalPilotActivationDryRun)"
        ].joined(separator: ", ")
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallRoomCardStatusRefreshMode: Equatable {
    case cached
    case bypassCache
}

#if DEBUG
enum NativeDirectCallRoomCardRedactedState: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case hidden
    case unavailable
    case canStart
    case outgoingRinging
    case incomingRinging
    case connecting
    case activeAudio
    case failed
    case ended

    init(_ state: NativeDirectCallRoomCardState) {
        switch state {
        case .hidden:
            self = .hidden
        case .unavailable:
            self = .unavailable
        case .canStart:
            self = .canStart
        case .outgoingRinging:
            self = .outgoingRinging
        case .incomingRinging:
            self = .incomingRinging
        case .connecting:
            self = .connecting
        case .activeAudio:
            self = .activeAudio
        case .failed:
            self = .failed
        case .ended:
            self = .ended
        }
    }

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallRoomCardRedactedStatus: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let state: NativeDirectCallRoomCardRedactedState
    let unavailableReason: NativeDirectCallRoomCardUnavailableReason?
    let failureReason: NativeDirectCallRoomCardFailureReason?
    let receiverAvailability: NativeDirectCallRoomReceiverAvailability?
    let restorationAvailability: NativeDirectCallRoomRestorationAvailability?
    let internalPilotActivationDryRun: NativeDirectCallInternalPilotActivationDryRunStatus
    let isLoading: Bool
    let actions: NativeDirectCallRoomActionAvailability

    init(state: NativeDirectCallRoomCardState,
         receiverAvailability: NativeDirectCallRoomReceiverAvailability?,
         restorationAvailability: NativeDirectCallRoomRestorationAvailability?,
         internalPilotActivationDryRun: NativeDirectCallInternalPilotActivationDryRunStatus = .disabled,
         isLoading: Bool,
         isStartAudioTemporarilyDisabled: Bool) {
        self.state = NativeDirectCallRoomCardRedactedState(state)
        switch state {
        case .unavailable(let reason):
            unavailableReason = reason
            failureReason = nil
        case .failed(let reason), .ended(let reason):
            unavailableReason = nil
            failureReason = reason
        case .hidden, .canStart, .outgoingRinging, .incomingRinging, .connecting, .activeAudio:
            unavailableReason = nil
            failureReason = nil
        }
        self.receiverAvailability = receiverAvailability
        self.restorationAvailability = restorationAvailability
        self.internalPilotActivationDryRun = internalPilotActivationDryRun
        self.isLoading = isLoading
        actions = .init(cardState: state,
                        isLoading: isLoading,
                        isStartAudioTemporarilyDisabled: isStartAudioTemporarilyDisabled)
    }

    var description: String {
        [
            "state: \(state)",
            "unavailableReason: \(unavailableReason?.description ?? "none")",
            "failureReason: \(failureReason?.description ?? "none")",
            "receiverAvailability: \(receiverAvailability?.description ?? "none")",
            "restorationAvailability: \(restorationAvailability?.description ?? "none")",
            "\(internalPilotActivationDryRun)",
            "isLoading: \(isLoading)",
            "canRefreshStatus: \(actions.canRefreshStatus)",
            "canStartAudio: \(actions.canStartAudio)",
            "canAccept: \(actions.canAccept)",
            "canDeclineIncoming: \(actions.canDeclineIncoming)",
            "canCancelOutgoing: \(actions.canCancelOutgoing)",
            "canHangUp: \(actions.canHangUp)",
            "canRetry: \(actions.canRetry)",
            "canDismissError: \(actions.canDismissError)"
        ].joined(separator: ", ")
    }

    var debugDescription: String {
        description
    }
}
#endif

struct NativeDirectCallRoomCardActionResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let action: NativeDirectCallRoomCardAction
    let outcome: NativeDirectCallRoomCardActionOutcome
    let status: NativeDirectCallRoomCardStatus

    var state: NativeDirectCallRoomCardState {
        status.state
    }

    init(action: NativeDirectCallRoomCardAction,
         outcome: NativeDirectCallRoomCardActionOutcome,
         state: NativeDirectCallRoomCardState) {
        self.init(action: action,
                  outcome: outcome,
                  status: .init(state: state))
    }

    init(action: NativeDirectCallRoomCardAction,
         outcome: NativeDirectCallRoomCardActionOutcome,
         status: NativeDirectCallRoomCardStatus) {
        self.action = action
        self.outcome = outcome
        self.status = status
    }

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
    func nativeDirectCallRoomCardStatus() async -> NativeDirectCallRoomCardStatus
    func nativeDirectCallRoomCardStatus(refreshMode: NativeDirectCallRoomCardStatusRefreshMode) async -> NativeDirectCallRoomCardStatus
}

extension NativeDirectCallRoomStateProviding {
    func nativeDirectCallRoomCardStatus() async -> NativeDirectCallRoomCardStatus {
        await nativeDirectCallRoomCardStatus(refreshMode: .cached)
    }

    func nativeDirectCallRoomCardStatus(refreshMode: NativeDirectCallRoomCardStatusRefreshMode) async -> NativeDirectCallRoomCardStatus {
        let state = await nativeDirectCallRoomCardState()
        return .init(state: state)
    }
}

@MainActor
protocol NativeDirectCallRoomActionHandling: AnyObject {
    func performNativeDirectCallRoomCardAction(_ action: NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult
}

@MainActor
final class ClosureNativeDirectCallRoomCardProvider: NativeDirectCallRoomStateProviding, NativeDirectCallRoomActionHandling {
    private let statusClosure: @MainActor (NativeDirectCallRoomCardStatusRefreshMode) async -> NativeDirectCallRoomCardStatus
    private let actionClosure: @MainActor (NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult

    init(state: @escaping @MainActor () async -> NativeDirectCallRoomCardState,
         action: @escaping @MainActor (NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult) {
        statusClosure = { _ in
            let state = await state()
            return .init(state: state)
        }
        actionClosure = action
    }

    init(status: @escaping @MainActor () async -> NativeDirectCallRoomCardStatus,
         action: @escaping @MainActor (NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult) {
        statusClosure = { _ in await status() }
        actionClosure = action
    }

    init(status: @escaping @MainActor (NativeDirectCallRoomCardStatusRefreshMode) async -> NativeDirectCallRoomCardStatus,
         action: @escaping @MainActor (NativeDirectCallRoomCardAction) async -> NativeDirectCallRoomCardActionResult) {
        statusClosure = status
        actionClosure = action
    }

    func nativeDirectCallRoomCardState() async -> NativeDirectCallRoomCardState {
        let status = await statusClosure(.cached)
        return status.state
    }

    func nativeDirectCallRoomCardStatus(refreshMode: NativeDirectCallRoomCardStatusRefreshMode) async -> NativeDirectCallRoomCardStatus {
        await statusClosure(refreshMode)
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
    var receiverAvailability: NativeDirectCallRoomReceiverAvailability?
    var restorationAvailability: NativeDirectCallRoomRestorationAvailability?
    var lastAction: NativeDirectCallRoomCardAction?
    var lastActionOutcome: NativeDirectCallRoomCardActionOutcome?

    static let hidden = Self(isVisible: false,
                             isLoading: false,
                             state: .hidden,
                             receiverAvailability: nil,
                             restorationAvailability: nil,
                             lastAction: nil,
                             lastActionOutcome: nil)

    static let visible = Self(isVisible: true,
                              isLoading: false,
                              state: .unavailable(reason: .nativeCallsUnavailable),
                              receiverAvailability: nil,
                              restorationAvailability: nil,
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

    var redactedStatus: NativeDirectCallRoomCardRedactedStatus {
        .init(state: state,
              receiverAvailability: receiverAvailability,
              restorationAvailability: restorationAvailability,
              internalPilotActivationDryRun: .disabled,
              isLoading: isLoading,
              isStartAudioTemporarilyDisabled: isStartAudioTemporarilyDisabled)
    }

    var foregroundLimitationText: String? {
        switch state {
        case .hidden,
             .activeAudio:
            nil
        case .unavailable,
             .canStart,
             .outgoingRinging,
             .incomingRinging,
             .connecting,
             .failed,
             .ended:
            UntranslatedL10n.screenRoomNativeDirectCallForegroundLimitDetail
        }
    }

    var accessibilitySummary: String {
        [
            UntranslatedL10n.screenRoomNativeDirectCallTitle,
            state.displayText,
            state.detailText,
            foregroundLimitationText,
            receiverAvailability?.displayText,
            restorationAvailability?.displayText
        ].compactMap { $0 }
            .joined(separator: ". ")
    }
    #endif
}

#if DEBUG
enum NativeDirectCallRoomSessionState: String, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case unavailable
    case idle
    case outgoingRinging
    case incomingRinging
    case connecting
    case activeAudio
    case activeVideo
    case ending
    case ended
    case missed
    case cancelled
    case failed
    case resetting
    case unknown

    init(productionStatusValue: String) {
        switch productionStatusValue {
        case Self.unavailable.rawValue:
            self = .unavailable
        case Self.idle.rawValue:
            self = .idle
        case Self.outgoingRinging.rawValue:
            self = .outgoingRinging
        case Self.incomingRinging.rawValue:
            self = .incomingRinging
        case Self.connecting.rawValue:
            self = .connecting
        case Self.activeAudio.rawValue:
            self = .activeAudio
        case Self.activeVideo.rawValue:
            self = .activeVideo
        case Self.ending.rawValue:
            self = .ending
        case Self.ended.rawValue:
            self = .ended
        case Self.missed.rawValue:
            self = .missed
        case Self.cancelled.rawValue:
            self = .cancelled
        case Self.failed.rawValue:
            self = .failed
        case Self.resetting.rawValue:
            self = .resetting
        default:
            self = .unknown
        }
    }

    var description: String {
        rawValue
    }

    var debugDescription: String {
        description
    }

    var internalControlAvailability: NativeDirectCallInternalControlAvailability {
        switch self {
        case .outgoingRinging:
            return .outgoingRinging
        case .incomingRinging:
            return .incomingRinging
        case .connecting:
            return .connecting
        case .activeAudio:
            return .activeAudio
        case .activeVideo:
            return .activeVideo
        case .failed:
            return .failed
        case .ended, .cancelled, .missed:
            return .ended
        case .unavailable, .idle, .ending, .resetting, .unknown:
            return .unavailable
        }
    }

    var isInternalControlHangUpEnabled: Bool {
        switch self {
        case .outgoingRinging, .incomingRinging, .connecting, .activeAudio, .activeVideo, .ending:
            true
        case .unavailable, .idle, .ended, .missed, .cancelled, .failed, .resetting, .unknown:
            false
        }
    }
}

enum NativeDirectCallRoomEncryptionState: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case pending
    case ready
    case failed
    case unknown

    init(productionStatusValue: String) {
        switch productionStatusValue {
        case "none":
            self = .none
        case "pending":
            self = .pending
        case "ready":
            self = .ready
        default:
            if productionStatusValue.hasPrefix("failed") {
                self = .failed
            } else {
                self = .unknown
            }
        }
    }

    var description: String {
        switch self {
        case .none:
            "none"
        case .pending:
            "pending"
        case .ready:
            "ready"
        case .failed:
            "failed"
        case .unknown:
            "unknown"
        }
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallRoomMediaState: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case failed(DirectCallDiagnosticMediaFailureReason)

    init(failureReason: DirectCallDiagnosticMediaFailureReason) {
        switch failureReason {
        case .none:
            self = .none
        default:
            self = .failed(failureReason)
        }
    }

    var failureReason: DirectCallDiagnosticMediaFailureReason {
        switch self {
        case .none:
            return .none
        case .failed(let reason):
            return reason
        }
    }

    var description: String {
        switch self {
        case .none:
            "none"
        case .failed(let reason):
            reason.description
        }
    }

    var debugDescription: String {
        description
    }
}

enum NativeDirectCallRoomTerminalReason: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case none
    case outgoingTimeout
    case incomingTimeout
    case connectingFailed
    case cancelled
    case hangup
    case failed
    case unknown

    init(_ reason: DirectCallDiagnosticTerminalReason?) {
        switch reason {
        case .outgoingTimeout:
            self = .outgoingTimeout
        case .incomingTimeout:
            self = .incomingTimeout
        case .connectingFailed:
            self = .connectingFailed
        case .cancelled:
            self = .cancelled
        case .hangup:
            self = .hangup
        case .failed:
            self = .failed
        case .unknown:
            self = .unknown
        case .none:
            self = .none
        }
    }

    var diagnosticReason: DirectCallDiagnosticTerminalReason? {
        switch self {
        case .none:
            return nil
        case .outgoingTimeout:
            return .outgoingTimeout
        case .incomingTimeout:
            return .incomingTimeout
        case .connectingFailed:
            return .connectingFailed
        case .cancelled:
            return .cancelled
        case .hangup:
            return .hangup
        case .failed:
            return .failed
        case .unknown:
            return .unknown
        }
    }

    var description: String {
        switch self {
        case .none:
            "none"
        case .outgoingTimeout:
            "outgoingTimeout"
        case .incomingTimeout:
            "incomingTimeout"
        case .connectingFailed:
            "connectingFailed"
        case .cancelled:
            "cancelled"
        case .hangup:
            "hangup"
        case .failed:
            "failed"
        case .unknown:
            "unknown"
        }
    }

    var debugDescription: String {
        description
    }
}

struct NativeDirectCallRoomActionAvailability: Equatable {
    let canRefreshStatus: Bool
    let canStartAudio: Bool
    let canAccept: Bool
    let canDeclineIncoming: Bool
    let canCancelOutgoing: Bool
    let canHangUp: Bool
    let canRetry: Bool
    let canDismissError: Bool

    static let unavailable = Self(canRefreshStatus: false,
                                  canStartAudio: false,
                                  canAccept: false,
                                  canDeclineIncoming: false,
                                  canCancelOutgoing: false,
                                  canHangUp: false,
                                  canRetry: false,
                                  canDismissError: false)

    init(canRefreshStatus: Bool,
         canStartAudio: Bool,
         canAccept: Bool,
         canDeclineIncoming: Bool,
         canCancelOutgoing: Bool,
         canHangUp: Bool,
         canRetry: Bool,
         canDismissError: Bool) {
        self.canRefreshStatus = canRefreshStatus
        self.canStartAudio = canStartAudio
        self.canAccept = canAccept
        self.canDeclineIncoming = canDeclineIncoming
        self.canCancelOutgoing = canCancelOutgoing
        self.canHangUp = canHangUp
        self.canRetry = canRetry
        self.canDismissError = canDismissError
    }

    init(cardState: NativeDirectCallRoomCardState,
         isLoading: Bool,
         isStartAudioTemporarilyDisabled: Bool) {
        canRefreshStatus = NativeDirectCallRoomCardAction.refreshStatus.isEnabled(in: cardState, isLoading: isLoading)
        canStartAudio = !isStartAudioTemporarilyDisabled && NativeDirectCallRoomCardAction.startAudio.isEnabled(in: cardState, isLoading: isLoading)
        canAccept = NativeDirectCallRoomCardAction.accept.isEnabled(in: cardState, isLoading: isLoading)
        canDeclineIncoming = NativeDirectCallRoomCardAction.declineIncoming.isEnabled(in: cardState, isLoading: isLoading)
        canCancelOutgoing = NativeDirectCallRoomCardAction.cancelOutgoing.isEnabled(in: cardState, isLoading: isLoading)
        canHangUp = NativeDirectCallRoomCardAction.hangUp.isEnabled(in: cardState, isLoading: isLoading)
        canRetry = NativeDirectCallRoomCardAction.retry.isEnabled(in: cardState, isLoading: isLoading)
        canDismissError = NativeDirectCallRoomCardAction.dismissError.isEnabled(in: cardState, isLoading: isLoading)
    }
}

extension NativeDirectCallRoomCardStatus {
    var redactedStatus: NativeDirectCallRoomCardRedactedStatus {
        .init(state: state,
              receiverAvailability: receiverAvailability,
              restorationAvailability: restorationAvailability,
              internalPilotActivationDryRun: internalPilotActivationDryRun,
              isLoading: false,
              isStartAudioTemporarilyDisabled: false)
    }
}

struct NativeDirectCallRoomSnapshot: Equatable {
    let isActivationEnabled: Bool
    let disabledReason: DirectCallProductionActivationDisabledReason?
    let productionOwnerAvailable: Bool
    let productionListenerAvailable: Bool
    let productionListenerStarted: Bool
    let productionRoomAttached: Bool
    let productionSessionRestorationSupported: Bool
    let productionHasActiveSession: Bool
    let currentSessionState: NativeDirectCallRoomSessionState
    let encryptionState: NativeDirectCallRoomEncryptionState
    let mediaState: NativeDirectCallRoomMediaState
    let terminalReason: NativeDirectCallRoomTerminalReason
    let lastOutcome: NativeDirectCallRoomCardActionOutcome?

    init(isActivationEnabled: Bool,
         disabledReason: DirectCallProductionActivationDisabledReason?,
         productionOwnerAvailable: Bool = false,
         productionListenerAvailable: Bool = true,
         productionListenerStarted: Bool = false,
         productionRoomAttached: Bool = true,
         productionSessionRestorationSupported: Bool = false,
         productionHasActiveSession: Bool,
         currentSessionState: NativeDirectCallRoomSessionState,
         encryptionState: NativeDirectCallRoomEncryptionState = .none,
         mediaState: NativeDirectCallRoomMediaState = .none,
         terminalReason: NativeDirectCallRoomTerminalReason = .none,
         lastOutcome: NativeDirectCallRoomCardActionOutcome? = nil) {
        self.isActivationEnabled = isActivationEnabled
        self.disabledReason = disabledReason
        self.productionOwnerAvailable = productionOwnerAvailable
        self.productionListenerAvailable = productionListenerAvailable
        self.productionListenerStarted = productionListenerStarted
        self.productionRoomAttached = productionRoomAttached
        self.productionSessionRestorationSupported = productionSessionRestorationSupported
        self.productionHasActiveSession = productionHasActiveSession
        self.currentSessionState = currentSessionState
        self.encryptionState = encryptionState
        self.mediaState = mediaState
        self.terminalReason = terminalReason
        self.lastOutcome = lastOutcome
    }

    init(triggerDiagnostic: NativeDirectCallProductionTriggerDryRunDiagnostic,
         productionStatus: NativeDirectCallProductionStatus,
         lastOutcome: NativeDirectCallRoomCardActionOutcome? = nil) {
        self.init(isActivationEnabled: triggerDiagnostic.isEnabled,
                  disabledReason: triggerDiagnostic.blockedReason,
                  productionOwnerAvailable: productionStatus.productionOwnerAvailable,
                  productionListenerAvailable: productionStatus.productionListenerAvailable,
                  productionListenerStarted: productionStatus.productionListenerStarted,
                  productionRoomAttached: productionStatus.productionRoomAttached,
                  productionSessionRestorationSupported: productionStatus.productionSessionRestorationSupported,
                  productionHasActiveSession: productionStatus.productionHasActiveSession,
                  currentSessionState: .init(productionStatusValue: productionStatus.productionSessionState),
                  encryptionState: .init(productionStatusValue: productionStatus.productionEncryptionState),
                  mediaState: .init(failureReason: productionStatus.productionMediaFailureReason),
                  terminalReason: .init(productionStatus.productionLastTerminalReason),
                  lastOutcome: lastOutcome)
    }

    var actionAvailability: NativeDirectCallRoomActionAvailability {
        let cardState = NativeDirectCallRoomCardStateReducer.cardState(snapshot: self)
        return .init(cardState: cardState, isLoading: false, isStartAudioTemporarilyDisabled: false)
    }
}

struct NativeDirectCallRoomCardLocalState: Equatable {
    var isLoading = false
    var isStartAudioTemporarilyDisabled = false
    var lastAction: NativeDirectCallRoomCardAction?
    var lastActionOutcome: NativeDirectCallRoomCardActionOutcome?
    var hidesDismissedError = false

    init(isLoading: Bool = false,
         isStartAudioTemporarilyDisabled: Bool = false,
         lastAction: NativeDirectCallRoomCardAction? = nil,
         lastActionOutcome: NativeDirectCallRoomCardActionOutcome? = nil,
         hidesDismissedError: Bool = false) {
        self.isLoading = isLoading
        self.isStartAudioTemporarilyDisabled = isStartAudioTemporarilyDisabled
        self.lastAction = lastAction
        self.lastActionOutcome = lastActionOutcome
        self.hidesDismissedError = hidesDismissedError
    }

    init(viewState: NativeDirectCallRoomCardViewState) {
        self.init(isLoading: viewState.isLoading,
                  isStartAudioTemporarilyDisabled: viewState.isStartAudioTemporarilyDisabled,
                  lastAction: viewState.lastAction,
                  lastActionOutcome: viewState.lastActionOutcome)
    }
}

enum NativeDirectCallUserSafeReasonMapper {
    static func unavailableReason(_ disabledReason: DirectCallProductionActivationDisabledReason?) -> NativeDirectCallRoomCardUnavailableReason {
        switch disabledReason {
        case .serverCapabilityUnavailable,
             .serverCapabilityDisabled,
             .unsupportedCapabilityVersion,
             .unsupportedIntent,
             .unsupportedMediaTransport,
             .e2eeNotRequiredByCapability,
             .unsupportedKeyEnvelope:
            return .serverUnsupported
        case .roomNotEncrypted:
            return .roomNotEncrypted
        case .roomNotDirect, .roomNotOneToOne:
            return .roomNotOneToOne
        case .unverifiedDevice:
            return .unverifiedDevice
        case .peerTrustUnavailable,
             .noEligibleDevice,
             .crossSigningUnavailable,
             .peerTrustUnknown:
            return .peerTrustUnavailable
        case .appRolloutDisabled,
             .roomUnavailable,
             .peerUnavailable,
             .none:
            return .nativeCallsUnavailable
        default:
            return .callServiceUnavailable
        }
    }

    static func unavailableReason(_ internalPilotReason: NativeDirectCallInternalPilotUnavailableReason) -> NativeDirectCallRoomCardUnavailableReason {
        switch internalPilotReason {
        case .accountNotEligible:
            return .accountNotEligible
        case .peerNotEligible:
            return .peerNotEligible
        case .roomNotEligible:
            return .roomNotOneToOne
        case .trustNotReady:
            return .peerTrustUnavailable
        case .serviceUnavailable:
            return .callServiceUnavailable
        case .capabilityMissing, .unsupportedClient:
            return .serverUnsupported
        case .unknown:
            return .unknown
        }
    }

    static func failureReason(_ mediaFailureReason: DirectCallDiagnosticMediaFailureReason) -> NativeDirectCallRoomCardFailureReason {
        switch mediaFailureReason {
        case .none:
            return .unknown
        case .liveKitConnectFailed,
             .liveKitURLInvalid,
             .liveKitURLUnreachable,
             .liveKitNetworkFailed,
             .liveKitSDKError,
             .liveKitUnknown:
            return .liveKitNetworkFailed
        case .factoryUnavailable,
             .credentialUnavailable,
             .e2eeContextUnavailable,
             .keyBridgeMiss,
             .mediaFactoryUnavailable,
             .mediaTokenUnavailable,
             .tokenEndpointUnavailable,
             .accessTokenUnavailable,
             .tokenHTTPUnavailable,
             .tokenBackendRejected,
             .tokenResponseInvalid,
             .mediaE2EEContextUnavailable,
             .mediaConnectFailed,
             .mediaSetupUnavailable,
             .mediaUnsupportedIntent,
             .invalidSessionState,
             .liveKitTokenRejected,
             .liveKitRoomJoinFailed,
             .liveKitE2EEConfigFailed:
            return .callServiceUnavailable
        case .unknown:
            return .unknown
        @unknown default:
            return .callServiceUnavailable
        }
    }

    static func failureReason(_ terminalReason: NativeDirectCallRoomTerminalReason) -> NativeDirectCallRoomCardFailureReason {
        switch terminalReason {
        case .outgoingTimeout, .incomingTimeout:
            return .callTimedOut
        case .connectingFailed:
            return .liveKitNetworkFailed
        case .cancelled:
            return .cancelled
        case .hangup:
            return .unknown
        case .failed, .unknown, .none:
            return .unknown
        }
    }
}

enum NativeDirectCallRoomCardStateReducer {
    static func reduce(snapshot: NativeDirectCallRoomSnapshot,
                       localState: NativeDirectCallRoomCardLocalState = .init()) -> NativeDirectCallRoomCardViewState {
        let status = status(snapshot: snapshot, hidesDismissedError: localState.hidesDismissedError)
        return .init(isVisible: status.state != .hidden,
                     isLoading: localState.isLoading,
                     isStartAudioTemporarilyDisabled: localState.isStartAudioTemporarilyDisabled,
                     state: status.state,
                     receiverAvailability: status.receiverAvailability,
                     restorationAvailability: status.restorationAvailability,
                     lastAction: localState.lastAction,
                     lastActionOutcome: localState.lastActionOutcome ?? snapshot.lastOutcome)
    }

    static func cardState(snapshot: NativeDirectCallRoomSnapshot,
                          hidesDismissedError: Bool = false) -> NativeDirectCallRoomCardState {
        status(snapshot: snapshot, hidesDismissedError: hidesDismissedError).state
    }

    static func status(snapshot: NativeDirectCallRoomSnapshot,
                       hidesDismissedError: Bool = false) -> NativeDirectCallRoomCardStatus {
        let receiverAvailability = NativeDirectCallRoomReceiverAvailability(snapshot: snapshot)
        let restorationAvailability = NativeDirectCallRoomRestorationAvailability(snapshot: snapshot)
        guard snapshot.productionHasActiveSession else {
            let state = inactiveSessionCardState(snapshot: snapshot)
            if hidesDismissedError, state.isFailed || state.isDismissible {
                return .init(state: snapshot.isActivationEnabled ? .canStart : .unavailable(reason: NativeDirectCallUserSafeReasonMapper.unavailableReason(snapshot.disabledReason)),
                             receiverAvailability: receiverAvailability,
                             restorationAvailability: restorationAvailability)
            }

            return .init(state: state,
                         receiverAvailability: receiverAvailability,
                         restorationAvailability: restorationAvailability)
        }

        let state = activeSessionCardState(snapshot: snapshot)
        if hidesDismissedError, state.isFailed || state.isDismissible {
            return .init(state: snapshot.isActivationEnabled ? .canStart : .unavailable(reason: NativeDirectCallUserSafeReasonMapper.unavailableReason(snapshot.disabledReason)),
                         receiverAvailability: receiverAvailability,
                         restorationAvailability: restorationAvailability)
        }

        return .init(state: state,
                     receiverAvailability: receiverAvailability,
                     restorationAvailability: restorationAvailability)
    }

    private static func inactiveSessionCardState(snapshot: NativeDirectCallRoomSnapshot) -> NativeDirectCallRoomCardState {
        if case .failed(let reason) = snapshot.mediaState {
            return .failed(reason: NativeDirectCallUserSafeReasonMapper.failureReason(reason))
        }

        if snapshot.isActivationEnabled {
            return .canStart
        }

        return .unavailable(reason: NativeDirectCallUserSafeReasonMapper.unavailableReason(snapshot.disabledReason))
    }

    private static func activeSessionCardState(snapshot: NativeDirectCallRoomSnapshot) -> NativeDirectCallRoomCardState {
        switch snapshot.currentSessionState {
        case .outgoingRinging:
            return .outgoingRinging
        case .incomingRinging:
            return .incomingRinging
        case .connecting:
            return .connecting
        case .activeAudio:
            return .activeAudio
        case .failed:
            if snapshot.terminalReason == .outgoingTimeout || snapshot.terminalReason == .incomingTimeout {
                return .failed(reason: .callTimedOut)
            }

            return .failed(reason: NativeDirectCallUserSafeReasonMapper.failureReason(snapshot.mediaState.failureReason))
        case .ended, .cancelled, .missed:
            return .ended(reason: NativeDirectCallUserSafeReasonMapper.failureReason(snapshot.terminalReason))
        case .unavailable, .idle, .activeVideo, .ending, .resetting, .unknown:
            return .unavailable(reason: .unknown)
        }
    }
}

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
        NativeDirectCallRoomCardStatus.make(triggerDiagnostic: triggerDiagnostic,
                                            productionStatus: productionStatus).state
    }

    static func make(isActivationEnabled: Bool,
                     disabledReason: DirectCallProductionActivationDisabledReason?,
                     productionHasActiveSession: Bool,
                     sessionState: String,
                     mediaFailureReason: DirectCallDiagnosticMediaFailureReason,
                     terminalReason: DirectCallDiagnosticTerminalReason?) -> Self {
        let snapshot = NativeDirectCallRoomSnapshot(isActivationEnabled: isActivationEnabled,
                                                    disabledReason: disabledReason,
                                                    productionHasActiveSession: productionHasActiveSession,
                                                    currentSessionState: .init(productionStatusValue: sessionState),
                                                    mediaState: .init(failureReason: mediaFailureReason),
                                                    terminalReason: .init(terminalReason))
        return NativeDirectCallRoomCardStateReducer.cardState(snapshot: snapshot)
    }
}

extension NativeDirectCallRoomCardStatus {
    static func make(triggerDiagnostic: NativeDirectCallProductionTriggerDryRunDiagnostic,
                     productionStatus: NativeDirectCallProductionStatus) -> Self {
        NativeDirectCallRoomCardStateReducer.status(snapshot: .init(triggerDiagnostic: triggerDiagnostic,
                                                                    productionStatus: productionStatus))
    }

    func merging(internalPilotEligibility eligibility: NativeDirectCallInternalPilotEligibility) -> Self {
        guard case .unavailable(let currentReason) = state else {
            return self
        }

        guard !currentReason.isLocalRoomOrTrustFailure else {
            return self
        }

        let mergedReason: NativeDirectCallRoomCardUnavailableReason
        switch eligibility {
        case .eligible:
            return self
        case .unavailable(let reason):
            mergedReason = NativeDirectCallUserSafeReasonMapper.unavailableReason(reason)
        case .disabled:
            mergedReason = .nativeCallsUnavailable
        case .unsupported:
            mergedReason = .serverUnsupported
        case .failClosed:
            mergedReason = .unknown
        }

        return .init(state: .unavailable(reason: mergedReason),
                     receiverAvailability: receiverAvailability,
                     restorationAvailability: restorationAvailability,
                     internalPilotActivationDryRun: internalPilotActivationDryRun)
    }

    func merging(internalPilotActivationDryRun dryRun: NativeDirectCallInternalPilotActivationDryRunStatus) -> Self {
        let mergedState: NativeDirectCallRoomCardState
        if dryRun.decision == .activationAllowed,
           state == .unavailable(reason: .nativeCallsUnavailable) {
            mergedState = .canStart
        } else {
            mergedState = state
        }

        return .init(state: mergedState,
                     receiverAvailability: receiverAvailability,
                     restorationAvailability: restorationAvailability,
                     internalPilotActivationDryRun: dryRun)
    }
}

private extension NativeDirectCallRoomCardUnavailableReason {
    var isLocalRoomOrTrustFailure: Bool {
        switch self {
        case .roomNotEncrypted,
             .roomNotOneToOne,
             .unverifiedDevice,
             .peerTrustUnavailable:
            return true
        case .nativeCallsUnavailable,
             .accountNotEligible,
             .peerNotEligible,
             .serverUnsupported,
             .callServiceUnavailable,
             .liveKitNetworkFailed,
             .callTimedOut,
             .unknown:
            return false
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
            if reason == .unknown {
                UntranslatedL10n.screenRoomNativeDirectCallEnded
            } else {
                reason.displayText
            }
        }
    }

    var detailText: String? {
        switch self {
        case .hidden:
            nil
        case .unavailable(let reason):
            reason.detailText
        case .canStart:
            UntranslatedL10n.screenRoomNativeDirectCallReadyDetail
        case .outgoingRinging:
            UntranslatedL10n.screenRoomNativeDirectCallCallingDetail
        case .incomingRinging:
            UntranslatedL10n.screenRoomNativeDirectCallIncomingDetail
        case .connecting:
            UntranslatedL10n.screenRoomNativeDirectCallConnectingDetail
        case .activeAudio:
            UntranslatedL10n.screenRoomNativeDirectCallActiveDetail
        case .failed(let reason):
            reason.detailText
        case .ended(let reason):
            if reason == .unknown {
                UntranslatedL10n.screenRoomNativeDirectCallEndedDetail
            } else {
                reason.detailText
            }
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

extension NativeDirectCallRoomReceiverAvailability {
    var displayText: String {
        switch self {
        case .openRoomRequired:
            UntranslatedL10n.screenRoomNativeDirectCallOpenRoomRequired
        case .listenerUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallIncomingUnavailable
        case .listenerNotArmed, .listenerNotStarted:
            UntranslatedL10n.screenRoomNativeDirectCallListenerNotArmed
        case .readyToReceive:
            UntranslatedL10n.screenRoomNativeDirectCallReadyToReceive
        }
    }
}

extension NativeDirectCallRoomRestorationAvailability {
    var displayText: String? {
        switch self {
        case .supported:
            nil
        case .unsupported:
            UntranslatedL10n.screenRoomNativeDirectCallRestorationNotSupported
        }
    }
}

private extension NativeDirectCallRoomCardUnavailableReason {
    var displayText: String {
        switch self {
        case .unverifiedDevice, .peerTrustUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallVerifyBeforeCalling
        case .liveKitNetworkFailed:
            UntranslatedL10n.screenRoomNativeDirectCallAudioUnavailable
        case .callTimedOut:
            UntranslatedL10n.screenRoomNativeDirectCallTimedOut
        case .roomNotEncrypted:
            UntranslatedL10n.screenRoomNativeDirectCallRoomNotEncrypted
        case .roomNotOneToOne:
            UntranslatedL10n.screenRoomNativeDirectCallRoomNotOneToOne
        case .callServiceUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallBackendUnavailable
        case .nativeCallsUnavailable, .accountNotEligible, .peerNotEligible, .serverUnsupported:
            UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHere
        case .unknown:
            UntranslatedL10n.screenRoomNativeDirectCallUnknownFailure
        }
    }

    var detailText: String {
        switch self {
        case .unverifiedDevice, .peerTrustUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallVerifyBeforeCallingDetail
        case .liveKitNetworkFailed:
            UntranslatedL10n.screenRoomNativeDirectCallAudioUnavailableDetail
        case .callTimedOut:
            UntranslatedL10n.screenRoomNativeDirectCallTimedOutDetail
        case .roomNotEncrypted:
            UntranslatedL10n.screenRoomNativeDirectCallRoomNotEncryptedDetail
        case .roomNotOneToOne:
            UntranslatedL10n.screenRoomNativeDirectCallRoomNotOneToOneDetail
        case .callServiceUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallBackendUnavailableDetail
        case .nativeCallsUnavailable, .accountNotEligible, .peerNotEligible, .serverUnsupported:
            UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHereDetail
        case .unknown:
            UntranslatedL10n.screenRoomNativeDirectCallUnknownFailureDetail
        }
    }
}

private extension NativeDirectCallRoomCardFailureReason {
    var displayText: String {
        switch self {
        case .unverifiedDevice, .peerTrustUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallVerifyBeforeCalling
        case .liveKitNetworkFailed:
            UntranslatedL10n.screenRoomNativeDirectCallAudioUnavailable
        case .callTimedOut:
            UntranslatedL10n.screenRoomNativeDirectCallTimedOut
        case .declined:
            UntranslatedL10n.screenRoomNativeDirectCallDeclined
        case .cancelled:
            UntranslatedL10n.screenRoomNativeDirectCallCancelled
        case .roomNotEncrypted:
            UntranslatedL10n.screenRoomNativeDirectCallRoomNotEncrypted
        case .roomNotOneToOne:
            UntranslatedL10n.screenRoomNativeDirectCallRoomNotOneToOne
        case .callServiceUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallBackendUnavailable
        case .nativeCallsUnavailable, .serverUnsupported:
            UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHere
        case .unknown:
            UntranslatedL10n.screenRoomNativeDirectCallUnknownFailure
        }
    }

    var detailText: String {
        switch self {
        case .unverifiedDevice, .peerTrustUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallVerifyBeforeCallingDetail
        case .liveKitNetworkFailed:
            UntranslatedL10n.screenRoomNativeDirectCallAudioUnavailableDetail
        case .callTimedOut:
            UntranslatedL10n.screenRoomNativeDirectCallTimedOutDetail
        case .declined:
            UntranslatedL10n.screenRoomNativeDirectCallDeclinedDetail
        case .cancelled:
            UntranslatedL10n.screenRoomNativeDirectCallCancelledDetail
        case .roomNotEncrypted:
            UntranslatedL10n.screenRoomNativeDirectCallRoomNotEncryptedDetail
        case .roomNotOneToOne:
            UntranslatedL10n.screenRoomNativeDirectCallRoomNotOneToOneDetail
        case .callServiceUnavailable:
            UntranslatedL10n.screenRoomNativeDirectCallBackendUnavailableDetail
        case .nativeCallsUnavailable, .serverUnsupported:
            UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHereDetail
        case .unknown:
            UntranslatedL10n.screenRoomNativeDirectCallUnknownFailureDetail
        }
    }
}

private extension NativeDirectCallRoomCardUnavailableReason {
    init(_ disabledReason: DirectCallProductionActivationDisabledReason?) {
        self = NativeDirectCallUserSafeReasonMapper.unavailableReason(disabledReason)
    }
}

private extension NativeDirectCallRoomCardFailureReason {
    init(_ mediaFailureReason: DirectCallDiagnosticMediaFailureReason) {
        self = NativeDirectCallUserSafeReasonMapper.failureReason(mediaFailureReason)
    }

    init(_ terminalReason: DirectCallDiagnosticTerminalReason?) {
        self = NativeDirectCallUserSafeReasonMapper.failureReason(.init(terminalReason))
    }
}

extension NativeDirectCallInternalControlStatus {
    static func make(triggerDiagnostic: NativeDirectCallProductionTriggerDryRunDiagnostic,
                     productionStatus: NativeDirectCallProductionStatus,
                     lastAction: NativeDirectCallInternalControlAction? = nil,
                     lastActionOutcome: String = "none",
                     lastActionReason: String = "none") -> Self {
        let snapshot = NativeDirectCallRoomSnapshot(triggerDiagnostic: triggerDiagnostic,
                                                    productionStatus: productionStatus)
        let activationReason = triggerDiagnostic.blockedReason?.description ?? "none"
        let availability = availability(snapshot: snapshot)
        let canArmListener = triggerDiagnostic.isEnabled && (!productionStatus.productionListenerStarted || snapshot.currentSessionState == .idle)
        let canStartAudio = triggerDiagnostic.isEnabled && !productionStatus.productionHasActiveSession
        let canAccept = triggerDiagnostic.isEnabled && snapshot.currentSessionState == .incomingRinging
        let canHangUp = productionStatus.productionHasActiveSession && snapshot.currentSessionState.isInternalControlHangUpEnabled

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

    private static func availability(snapshot: NativeDirectCallRoomSnapshot) -> NativeDirectCallInternalControlAvailability {
        if snapshot.productionHasActiveSession {
            return snapshot.currentSessionState.internalControlAvailability
        }

        return snapshot.isActivationEnabled ? .canStart : .unavailable
    }
}
#endif
