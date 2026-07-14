//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVFoundation
import CallKit
import Combine
import Foundation
import MatrixRustSDK
import PushKit
import UIKit

#if DEBUG
enum SalemXStage2FCallKitLocalStateBucket: String, Equatable {
    case idle
    case incomingCallActive = "incoming_call_active"
    case ongoingCallActive = "ongoing_call_active"
}

enum SalemXStage2FCallKitReportErrorBucket: String, Equatable {
    case unknown
    case unentitled
    case callUUIDAlreadyExists = "call_uuid_already_exists"
    case filteredByDoNotDisturb = "filtered_by_do_not_disturb"
    case filteredByBlockList = "filtered_by_block_list"
    case filteredDuringRestrictedSharingMode = "filtered_during_restricted_sharing_mode"
    case callIsProtected = "call_is_protected"
    case filteredBySensitiveParticipants = "filtered_by_sensitive_participants"
    case other
}

enum SalemXStage2FCallKitReportResult: Equatable {
    case reported(UUID)
    case blockedByExistingIncomingCall
    case blockedByExistingOngoingCall
    case providerFailed(callID: UUID, errorBucket: SalemXStage2FCallKitReportErrorBucket)

    var reportedCallID: UUID? {
        guard case .reported(let callID) = self else {
            return nil
        }

        return callID
    }

    var localStateBucket: SalemXStage2FCallKitLocalStateBucket {
        switch self {
        case .blockedByExistingIncomingCall:
            .incomingCallActive
        case .blockedByExistingOngoingCall:
            .ongoingCallActive
        case .reported, .providerFailed:
            .idle
        }
    }

    var outcomeBucket: String {
        switch self {
        case .reported:
            "reported"
        case .blockedByExistingIncomingCall:
            "blocked_existing_incoming_call"
        case .blockedByExistingOngoingCall:
            "blocked_existing_ongoing_call"
        case .providerFailed(_, let errorBucket):
            "provider_failed_\(errorBucket.rawValue)"
        }
    }
}
#endif

private enum CallSessionState: String, Equatable {
    case idle
    case outgoingRinging = "outgoing_ringing"
    case incomingRinging = "incoming_ringing"
    case accepted
    case connected
    case declined
    case cancelled
    case missed
    case ended
    case failed

    var isTerminal: Bool {
        switch self {
        case .declined, .cancelled, .missed, .ended, .failed:
            true
        case .idle, .outgoingRinging, .incomingRinging, .accepted, .connected:
            false
        }
    }
}

private enum CallSessionEventType: String, Equatable {
    case invite
    case ringing
    case accept
    case reject
    case hangup
    case timeout
    case ack
    case answeredElsewhere = "answered_elsewhere"
}

private enum CallSessionDirection: Equatable {
    case outgoing
    case incoming
}

private enum CallSessionRejectionReason: Equatable {
    case terminal
    case duplicate
    case outOfOrder
    case invalidTransition
}

private struct CallSessionEvent: Equatable {
    let type: CallSessionEventType
    let direction: CallSessionDirection?
    let sequence: UInt64?
    let deduplicationID: String?
    let timestamp: Date

    init(type: CallSessionEventType,
         direction: CallSessionDirection? = nil,
         sequence: UInt64? = nil,
         deduplicationID: String? = nil,
         timestamp: Date = Date()) {
        self.type = type
        self.direction = direction
        self.sequence = sequence
        self.deduplicationID = deduplicationID
        self.timestamp = timestamp
    }
}

private struct CallSessionTransitionResult: Equatable {
    let previousState: CallSessionState
    let state: CallSessionState
    let rejectionReason: CallSessionRejectionReason?

    var isApplied: Bool {
        rejectionReason == nil
    }
}

private struct CallSession: Equatable {
    let callID: String
    let roomID: String
    let callKitID: UUID
    let direction: CallSessionDirection
    private(set) var remoteCallID: String?

    private(set) var state: CallSessionState = .idle
    private(set) var lastSequence: UInt64?
    private(set) var processedDeduplicationIDs = Set<String>()

    init(callID: String = UUID().uuidString,
         roomID: String,
         callKitID: UUID,
         direction: CallSessionDirection,
         remoteCallID: String? = nil,
         state: CallSessionState = .idle) {
        self.callID = callID
        self.roomID = roomID
        self.callKitID = callKitID
        self.direction = direction
        self.remoteCallID = remoteCallID
        self.state = state
    }

    mutating func updateRemoteCallID(_ remoteCallID: String) {
        guard self.remoteCallID != remoteCallID else {
            return
        }

        self.remoteCallID = remoteCallID
    }

    mutating func apply(_ event: CallSessionEvent) -> CallSessionTransitionResult {
        let previousState = state

        guard !state.isTerminal else {
            return .init(previousState: previousState, state: state, rejectionReason: .terminal)
        }

        if let deduplicationID = event.deduplicationID {
            guard !processedDeduplicationIDs.contains(deduplicationID) else {
                return .init(previousState: previousState, state: state, rejectionReason: .duplicate)
            }
        }

        if let sequence = event.sequence,
           let lastSequence,
           sequence <= lastSequence {
            return .init(previousState: previousState, state: state, rejectionReason: .outOfOrder)
        }

        guard let nextState = Self.reduce(state: state, event: event) else {
            return .init(previousState: previousState, state: state, rejectionReason: .invalidTransition)
        }

        state = nextState
        if let deduplicationID = event.deduplicationID {
            processedDeduplicationIDs.insert(deduplicationID)
        }
        if let sequence = event.sequence {
            lastSequence = sequence
        }

        return .init(previousState: previousState, state: nextState, rejectionReason: nil)
    }

    private static func reduce(state: CallSessionState, event: CallSessionEvent) -> CallSessionState? {
        switch (state, event.type) {
        case (.idle, .invite), (.idle, .ringing):
            switch event.direction {
            case .outgoing:
                return .outgoingRinging
            case .incoming:
                return .incomingRinging
            case .none:
                return nil
            }

        case (.outgoingRinging, .ringing):
            return .outgoingRinging
        case (.incomingRinging, .ringing):
            return .incomingRinging

        case (.outgoingRinging, .accept), (.incomingRinging, .accept):
            return .accepted
        case (.accepted, .ack):
            return .connected
        case (.connected, .ack):
            return .connected

        case (.outgoingRinging, .reject), (.incomingRinging, .reject), (.accepted, .reject):
            return .declined

        case (.outgoingRinging, .hangup):
            return .cancelled
        case (.incomingRinging, .hangup), (.accepted, .hangup), (.connected, .hangup):
            return .ended

        case (.outgoingRinging, .timeout), (.incomingRinging, .timeout):
            return .missed
        case (.accepted, .timeout), (.connected, .timeout):
            return .failed

        case (.outgoingRinging, .answeredElsewhere), (.incomingRinging, .answeredElsewhere), (.accepted, .answeredElsewhere):
            return .cancelled

        default:
            return nil
        }
    }
}

/// Keep this class testable
struct TimeProvider {
    var clock: any Clock<Duration>
    var now: () -> Date
}

struct ForegroundCurrentRoomCallEvent {
    let roomID: String
    let roomDisplayName: String?
    let isDirect: Bool
    let isOwnEvent: Bool
    let callEvent: RoomCallEvent
    let deduplicationID: String
}

// swiftlint:disable type_body_length
class ElementCallService: NSObject, ElementCallServiceProtocol, PKPushRegistryDelegate, CXProviderDelegate {
    private enum IncomingFallbackConstants {
        static let unansweredTimeout: Duration = .seconds(45)
        static let suppressionDuration: TimeInterval = 30
    }

    private enum CallTerminationConstants {
        static let duplicateSuppression: TimeInterval = 1
        static let noForeignParticipantGraceWindow: TimeInterval = 2
    }

    private struct CallID: Equatable {
        let callKitID: UUID
        let roomID: String
        let rtcNotificationID: String?
        let remoteCallID: String?
        let startMode: ElementCallStartMode
        let startedAt: Date
    }

    private final class TerminationEventTracker {
        var eventID: String?
    }

    private final class RoomCallPresenceTracker {
        var hasSeenActiveCall = false
        var hasSeenRemoteParticipant = false
        var noForeignParticipantSince: Date?
    }

    private struct ForegroundRoomIncomingCallCandidate {
        let callEvent: RoomCallEvent
        let deduplicationID: String
        let isOwnEvent: Bool
    }

    private enum DeclineAttemptResult {
        case sent
        case notFound
        case ownEvent
        case failed
    }

    private enum SalemXEmbeddedCallEndedReportReason {
        case remoteEnded
        case localEnded
        case failedBeforeConnection
        case unansweredOrTimeout
        case systemReset

        var callKitEndedReason: CXCallEndedReason? {
            switch self {
            case .remoteEnded:
                .remoteEnded
            case .failedBeforeConnection:
                .failed
            case .unansweredOrTimeout:
                .unanswered
            case .localEnded, .systemReset:
                nil
            }
        }
    }
    
    private let pushRegistry: PKPushRegistry
    private let callController = CXCallController()
    private let callProvider: CXProviderProtocol
    private let timeProvider: TimeProvider
    private let appSettings: AppSettings
    private var salemXAnswerBridgeConfiguration: SalemXEmbeddedCallAnswerBridgeConfiguration
    private var salemXIncomingCallBootstrapResolver: (any SalemXIncomingCallBootstrapResolving)?
    private var salemXAnswerBridge: (any SalemXEmbeddedCallAnswerBridging)?
    private var salemXEndBridge: (any SalemXEmbeddedCallEndBridging)?
    
    private var voIPPushToken: Data?
    private var registeredVoIPPushToken: Data?
    
    private weak var clientProxy: ClientProxyProtocol? {
        didSet {
            // There's a race condition where a call starts when the app has been killed and the
            // observation set in `incomingCallID` occurs *before* the user session is restored.
            // So observe when the client proxy is set to fix this (the method guards for the call).
            Task { await observeIncomingCall() }
            Task { await observeOngoingCall() }
            observeIncomingCallFallback()
        }
    }
    
    private var incomingCallTimelineCancellable: AnyCancellable?
    private var incomingCallRoomInfoCancellable: AnyCancellable?
    private var incomingCallID: CallID? {
        didSet {
            Task { await observeIncomingCall() }
        }
    }
    
    private var endUnansweredCallTask: Task<Void, Never>?
    
    private var ongoingCallTimelineCancellable: AnyCancellable?
    private var ongoingCallRoomInfoCancellable: AnyCancellable?
    private var recentlyEndedCallID: CallID?
    private var cachedRTCNotificationIDByRoomID: [String: String] = [:]
    private var cachedRTCNotificationOwnershipByRoomID: [String: Bool] = [:]
    private var cachedRemoteCallIDByRoomID: [String: String] = [:]
    private var activeCallSession: CallSession?
    private var recentCallSessionByRoomID: [String: CallSession] = [:]
    private var callSessionSequence: UInt64 = 0
    private var ongoingCallID: CallID? {
        didSet {
            ongoingCallRoomIDSubject.send(ongoingCallID?.roomID)
            Task { await observeOngoingCall() }
        }
    }
    
    let ongoingCallRoomIDSubject = CurrentValueSubject<String?, Never>(nil)
    var ongoingCallRoomIDPublisher: CurrentValuePublisher<String?, Never> {
        ongoingCallRoomIDSubject.asCurrentValuePublisher()
    }
    
    private let actionsSubject: PassthroughSubject<ElementCallServiceAction, Never> = .init()
    var actions: AnyPublisher<ElementCallServiceAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var declineListenerHandle: TaskHandle?
    private var incomingCallFallbackCancellable: AnyCancellable?
    private var incomingFallbackSuppressionByRoomID: [String: Date] = [:]
    private var foregroundRoomID: String?
    private var foregroundRoomTimelineCancellable: AnyCancellable?
    private var handledForegroundIncomingCallByRoomID: [String: String] = [:]
    private var ongoingDeclineListenerHandles: [String: TaskHandle] = [:]
    private var isResolvingOngoingDeclines = false
    private let ongoingDeclineObservationLock = NSLock()
    @CancellableTask
    private var ongoingDeclineRefreshTask: Task<Void, Never>?
    private let callTerminationLock = NSLock()
    private var inProgressCallTerminations = Set<String>()
    private var lastCallTerminationAttemptByRoomID: [String: Date] = [:]
    private var salemXEmbeddedAnswerTasks: [UUID: Task<Void, Never>] = [:]
    private var salemXEmbeddedAnswerActions: [UUID: [any SalemXCallKitAnswerActionCompleting]] = [:]
    private var salemXEmbeddedAnswerActionIDs: [UUID: Set<ObjectIdentifier>] = [:]
    private var salemXEmbeddedSupersededAnswerCallIDs = Set<UUID>()
    private var salemXEmbeddedEndTasks: [UUID: Task<Void, Never>] = [:]
    private var salemXEmbeddedEndActions: [UUID: [any SalemXCallKitEndActionCompleting]] = [:]
    private var salemXEmbeddedEndActionIDs: [UUID: Set<ObjectIdentifier>] = [:]
    private var salemXEmbeddedTerminatedCallIDs = Set<UUID>()
    private var salemXEmbeddedReportedEndedCallIDs = Set<UUID>()
    private var salemXEmbeddedClearedBootstrapCallIDs = Set<UUID>()
    
    init(appSettings: AppSettings = AppSettings(),
         callProvider: CXProviderProtocol? = nil,
         timeProvider: TimeProvider? = nil,
         salemXAnswerBridgeConfiguration: SalemXEmbeddedCallAnswerBridgeConfiguration = .init(),
         salemXIncomingCallBootstrapResolver: (any SalemXIncomingCallBootstrapResolving)? = nil,
         salemXAnswerBridge: (any SalemXEmbeddedCallAnswerBridging)? = nil,
         salemXEndBridge: (any SalemXEmbeddedCallEndBridging)? = nil) {
        pushRegistry = PKPushRegistry(queue: nil)
        
        self.appSettings = appSettings
        self.timeProvider = timeProvider ?? TimeProvider(clock: ContinuousClock(), now: Date.init)
        self.salemXAnswerBridgeConfiguration = salemXAnswerBridgeConfiguration
        self.salemXIncomingCallBootstrapResolver = salemXIncomingCallBootstrapResolver
        self.salemXAnswerBridge = salemXAnswerBridge
        self.salemXEndBridge = salemXEndBridge
        
        if let callProvider {
            self.callProvider = callProvider
        } else {
            let configuration = CXProviderConfiguration()
            configuration.supportsVideo = true
            configuration.includesCallsInRecents = true
            configuration.ringtoneSound = "message.caf"
            
            if let callKitIcon = UIImage(named: "images/app-logo") {
                configuration.iconTemplateImageData = callKitIcon.pngData()
            }
            
            // https://stackoverflow.com/a/46077628/730924
            configuration.supportedHandleTypes = [.generic]
            
            self.callProvider = CXProvider(configuration: configuration)
        }
        
        super.init()
        
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]
        
        self.callProvider.setDelegate(self, queue: nil)
    }
    
    func setClientProxy(_ clientProxy: any ClientProxyProtocol) {
        self.clientProxy = clientProxy
        Task { await registerVoIPPusherIfNeeded() }
    }

    #if DEBUG
    func salemXDebugConfigureStage2FSimulatorBridge(configuration: SalemXEmbeddedCallAnswerBridgeConfiguration,
                                                    bootstrapResolver: any SalemXIncomingCallBootstrapResolving,
                                                    answerBridge: any SalemXEmbeddedCallAnswerBridging,
                                                    endBridge: any SalemXEmbeddedCallEndBridging) {
        salemXAnswerBridgeConfiguration = configuration
        salemXIncomingCallBootstrapResolver = bootstrapResolver
        salemXAnswerBridge = answerBridge
        salemXEndBridge = endBridge
    }
    #endif

    @MainActor func observeForegroundRoom(roomProxy: JoinedRoomProxyProtocol, roomDisplayName: String?) {
        foregroundRoomTimelineCancellable = nil

        guard roomProxy.infoPublisher.value.isDirect else {
            clearForegroundRoomObservation()
            return
        }

        foregroundRoomID = roomProxy.id
        let timelineItemProvider = roomProxy.timeline.timelineItemProvider
        handleForegroundRoomTimelineUpdate(itemProxies: timelineItemProvider.itemProxies,
                                           roomProxy: roomProxy,
                                           roomDisplayName: roomDisplayName)

        foregroundRoomTimelineCancellable = timelineItemProvider.updatePublisher
            .map(\.0)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, roomProxy] itemProxies in
                guard let self else { return }
                self.handleForegroundRoomTimelineUpdate(itemProxies: itemProxies,
                                                        roomProxy: roomProxy,
                                                        roomDisplayName: roomDisplayName)
            }
    }

    @MainActor func stopObservingForegroundRoom(roomID: String) {
        guard foregroundRoomID == roomID else {
            return
        }

        clearForegroundRoomObservation()
    }

    func handleForegroundCurrentRoomCallEvent(_ event: ForegroundCurrentRoomCallEvent) {
        handleForegroundRoomIncomingCallCandidate(roomID: event.roomID,
                                                  roomDisplayName: event.roomDisplayName,
                                                  isDirect: event.isDirect,
                                                  candidate: .init(callEvent: event.callEvent,
                                                                   deduplicationID: event.deduplicationID,
                                                                   isOwnEvent: event.isOwnEvent))
    }

    private func clearForegroundRoomObservation() {
        if let foregroundRoomID {
            handledForegroundIncomingCallByRoomID.removeValue(forKey: foregroundRoomID)
        }

        foregroundRoomID = nil
        foregroundRoomTimelineCancellable = nil
    }
    
    func setupCallSession(roomID: String, roomDisplayName: String) async {
        await setupCallSession(roomID: roomID, roomDisplayName: roomDisplayName, startMode: .video)
    }

    func setupCallSession(roomID: String, roomDisplayName: String, startMode: ElementCallStartMode) async {
        if ongoingCallID?.roomID == roomID {
            return
        }

        // Drop any ongoing calls when starting a new one
        if ongoingCallID != nil {
            tearDownCallSession()
        }
        
        // If this starting from a ring reuse those identifiers
        // Make sure the roomID matches
        let callID: CallID
        if let incomingCallID, incomingCallID.roomID == roomID {
            callID = incomingCallID
        } else {
            cachedRemoteCallIDByRoomID.removeValue(forKey: roomID)
            callID = CallID(callKitID: UUID(),
                            roomID: roomID,
                            rtcNotificationID: nil,
                            remoteCallID: nil,
                            startMode: startMode,
                            startedAt: timeProvider.now())
        }
        let isIncomingCallSession = incomingCallID?.roomID == roomID
        
        incomingCallID = nil
        ongoingCallID = callID
        recentlyEndedCallID = nil
        if let rtcNotificationID = callID.rtcNotificationID {
            cacheRTCNotificationID(rtcNotificationID, for: roomID)
        }
        if let remoteCallID = callID.remoteCallID {
            cacheRemoteCallID(remoteCallID, for: roomID)
        }

        openCallSession(roomID: roomID,
                        callKitID: callID.callKitID,
                        direction: isIncomingCallSession ? .incoming : .outgoing,
                        remoteCallID: callID.remoteCallID)
        if isIncomingCallSession {
            applySessionEvent(type: .accept, roomID: roomID)
        }
        
        // Don't bother starting another CallKit session as it won't work properly
        // https://developer.apple.com/forums//thread/767949?answerId=812951022#812951022
        
        // let handle = CXHandle(type: .generic, value: roomDisplayName)
        // let startCallAction = CXStartCallAction(call: callID.callKitID, handle: handle)
        // startCallAction.isVideo = true
        
        // do {
        //     try await callController.request(CXTransaction(action: startCallAction))
        // } catch {
        //     MXLog.error("Failed requesting start call action with error: \(error)")
        // }
    }
    
    func declineIncomingCall() async {
        if let incomingCallID {
            applySessionEvent(type: .reject, roomID: incomingCallID.roomID)
            _ = await sendDeclineCallEventWithRetry(in: incomingCallID.roomID,
                                                    preferredRTCNotificationID: incomingCallID.rtcNotificationID)
            reportEndedCall(incomingCallID: incomingCallID, reason: .declinedElsewhere)
            return
        }

        guard let roomID = resolveIncomingDirectCallRoomIDForDecline() else {
            MXLog.info("No incoming call to decline.")
            return
        }

        applySessionEvent(type: .reject, roomID: roomID)
        _ = await sendDeclineCallEventWithRetry(in: roomID, preferredRTCNotificationID: nil)
    }
    
    func requestCallTermination(roomID: String) async {
        guard beginCallTermination(for: roomID) else {
            MXLog.verbose("Ignoring duplicate call termination request for room \(roomID)")
            return
        }
        defer { finishCallTermination(for: roomID) }

        #if DEBUG
        Task { @MainActor in
            SalemXStage2FSimulatorSignalingDebug.recordSenderUpstreamHangupInvoked(roomID: roomID)
        }
        #endif

        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SERVICE-ENDCALL] room_id=\(roomID)")
        suppressIncomingFallback(for: roomID)
        applySessionEvent(type: .hangup, roomID: roomID)
        actionsSubject.send(.endCall(roomID: roomID))
    }

    func isPreAnswerOutgoingCall(roomID: String) -> Bool {
        activeCallSession?.roomID == roomID && activeCallSession?.state == .outgoingRinging
    }

    func tearDownCallSession() {
        // The embedded call UI doesn't keep an active CallKit call around once it
        // takes over media, so ending our local session shouldn't emit a new
        // CXEndCallAction for a call that no longer exists.
        tearDownCallSession(sendEndCallAction: false)
    }
    
    func setAudioEnabled(_ enabled: Bool, roomID: String) {
        guard let ongoingCallID else {
            MXLog.error("Failed toggling call microphone, no calls running")
            return
        }
        
        guard ongoingCallID.roomID == roomID else {
            MXLog.error("Failed toggling call microphone, rooms don't match: \(ongoingCallID.roomID) != \(roomID)")
            return
        }
    }

    // MARK: - PKPushRegistryDelegate
    
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else {
            return
        }
        
        voIPPushToken = pushCredentials.token
        #if DEBUG
        SalemXPushKitRegistrationSmokeDebugBridge.recordElementCallServiceVoIPPushTokenForDebugUpload(pushCredentials.token)
        #endif
        
        Task { await registerVoIPPusherIfNeeded() }
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        #if DEBUG
        if SalemXPushKitRegistrationSmokeDebugBridge.handleElementCallServicePushKitReceipt(payload.dictionaryPayload, completion: completion) {
            return
        }
        #endif
        guard let roomID = payload.dictionaryPayload[ElementCallServiceNotificationKey.roomID.rawValue] as? String else {
            MXLog.error("Something went wrong, missing room identifier for incoming voip call: \(payload)")
            completion()
            return
        }
        
        guard let rtcNotificationID = payload.dictionaryPayload[ElementCallServiceNotificationKey.rtcNotifyEventID.rawValue] as? String else {
            MXLog.error("Something went wrong, missing rtc notification event identifier for incoming voip call: \(payload)")
            completion()
            return
        }
        
        guard ongoingCallID == nil, incomingCallID == nil else {
            MXLog.warning("A call is already active, ignoring incoming push for room \(roomID)")
            completion()
            return
        }
        
        guard let expirationDate = (payload.dictionaryPayload[ElementCallServiceNotificationKey.expirationDate.rawValue] as? Date) else {
            MXLog.error("Something went wrong, missing expiration timestamp for incoming voip call: \(payload)")
            completion()
            return
        }
        
        let nowDate = timeProvider.now()
        
        guard nowDate < expirationDate else {
            MXLog.warning("Call expired for room \(roomID), ignoring incoming push")
            completion()
            return
        }

        let incomingStartMode = incomingStartMode(for: payload.dictionaryPayload, roomID: roomID)
        let intentTrace = callIntentTrace(from: payload.dictionaryPayload)
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-PUSH] room_id=\(roomID) payload_fields=\(Self.callTracePayloadSummary(payload.dictionaryPayload)) " +
            "parsed_intent_key=\(intentTrace.key ?? "nil") parsed_intent_value=\(intentTrace.value ?? "nil") " +
            "parsed_intent_start_mode=\(Self.callTraceStartMode(intentTrace.parsedStartMode)) incoming_start_mode=\(incomingStartMode)")
        cachedRemoteCallIDByRoomID.removeValue(forKey: roomID)
        
        let callID = CallID(callKitID: UUID(),
                            roomID: roomID,
                            rtcNotificationID: rtcNotificationID,
                            remoteCallID: nil,
                            startMode: incomingStartMode,
                            startedAt: nowDate)
        incomingCallID = callID
        cacheRTCNotificationID(rtcNotificationID, for: roomID, isOwnEvent: false)
        openCallSession(roomID: roomID,
                        callKitID: callID.callKitID,
                        direction: .incoming,
                        remoteCallID: callID.remoteCallID)
        
        let ringDuration: Duration = .seconds(min(expirationDate.timeIntervalSince1970 - nowDate.timeIntervalSince1970, 90))
        
        let roomDisplayName = payload.dictionaryPayload[ElementCallServiceNotificationKey.roomDisplayName.rawValue] as? String
        
        let update = CXCallUpdate()
        // Incoming direct calls behave as regular phone calls unless proven video.
        update.hasVideo = incomingStartMode == .video
        update.localizedCallerName = roomDisplayName
        // https://stackoverflow.com/a/41230020/730924
        update.remoteHandle = .init(type: .generic, value: roomID)
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-CALLKIT] room_id=\(roomID) start_mode=\(incomingStartMode) has_video=\(update.hasVideo) caller_name_source=roomDisplayName")
        
        callProvider.reportNewIncomingCall(with: callID.callKitID, update: update) { [weak self] error in
            if let error {
                MXLog.error("Failed reporting new incoming call with error: \(error)")
            }
            
            self?.actionsSubject.send(.receivedIncomingCallRequest)
            
            completion()
        }
        
        endUnansweredCallTask = Task { [weak self] in
            try? await self?.timeProvider.clock.sleep(for: ringDuration)
            
            guard let self, !Task.isCancelled else {
                return
            }
            
            if let incomingCallID, incomingCallID.callKitID == callID.callKitID {
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-RECIPIENT-TIMEOUT] room_id=\(incomingCallID.roomID) callkit_id=\(incomingCallID.callKitID)")
                reportEndedCall(incomingCallID: incomingCallID, reason: .unanswered)
            }
        }
    }
    
    // MARK: - CXProviderDelegate
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MXLog.info("Call provider did activate audio session")
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MXLog.info("Call provider did deactivate audio session")
    }
    
    func providerDidReset(_ provider: CXProvider) {
        MXLog.info("Call provider did reset: \(provider)")
        guard salemXAnswerBridgeConfiguration.embeddedMatrixRTCAnswerBridgeEnabled else {
            return
        }

        handleEmbeddedMatrixRTCProviderReset()
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        handleAnswerCallAction(action, provider: provider)
    }

    func handleAnswerCallAction(_ action: any SalemXCallKitAnswerActionCompleting, provider: any CXProviderProtocol) {
        guard salemXAnswerBridgeConfiguration.embeddedMatrixRTCAnswerBridgeEnabled else {
            handleLegacyAnswerCallAction(action, provider: provider)
            return
        }

        handleEmbeddedMatrixRTCAnswerCallAction(action)
    }

    private func handleLegacyAnswerCallAction(_ action: any SalemXCallKitAnswerActionCompleting, provider: any CXProviderProtocol) {
        guard let incomingCallID else {
            MXLog.error("Failed answering incoming call, missing incomingCallID")
            return
        }
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-ANSWER] room_id=\(incomingCallID.roomID) callkit_id=\(incomingCallID.callKitID) start_mode=\(incomingCallID.startMode)")
        
        applySessionEvent(type: .accept, roomID: incomingCallID.roomID)
        
        // Fixes broken videos on EC web when a CallKit session is established.
        //
        // Reporting an ongoing call through `reportNewIncomingCall` + `CXAnswerCallAction`
        // or `reportOutgoingCall:connectedAt:` will give exclusive access for media to the
        // ongoing process, which is different than the WKWebKit is running on, making EC
        // unable to aquire media streams.
        // Reporting the call as ended imediately after answering it works around that
        // as EC gets access to media again and EX builds the right UI in `setupCallSession`
        //
        // https://developer.apple.com/forums//thread/767949?answerId=812951022#812951022
        //
        // https://github.com/element-hq/element-x-ios/issues/3041
        // https://forums.developer.apple.com/forums/thread/685268
        // https://stackoverflow.com/questions/71483732/webrtc-running-from-wkwebview-avaudiosession-development-roadblock
        
        // First fullfill the action
        action.fulfill()
        
        // And delay ending the call so that the app has enough time
        // to get deeplinked into
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Task { @MainActor in
                guard self.incomingCallID?.callKitID == incomingCallID.callKitID else {
                    return
                }

                let isIncomingCallAlive = await self.isIncomingCallStillAliveBeforeAnswer(incomingCallID)
                guard self.incomingCallID?.callKitID == incomingCallID.callKitID else {
                    return
                }

                guard isIncomingCallAlive else {
                    self.reportEndedCall(incomingCallID: incomingCallID,
                                         reason: .remoteEnded,
                                         deduplicationID: "stale-answer:\(incomingCallID.callKitID.uuidString)")
                    return
                }

                // Then end the and call rely on `setupCallSession` to create a new one
                provider.reportCall(with: incomingCallID.callKitID, endedAt: nil, reason: .remoteEnded)

                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-START-CALL-SEND] room_id=\(incomingCallID.roomID) start_mode=\(incomingCallID.startMode)")
                self.actionsSubject.send(.startCall(roomID: incomingCallID.roomID, startMode: incomingCallID.startMode))
                self.endUnansweredCallTask?.cancel()
            }
        }
    }

    private func handleEmbeddedMatrixRTCAnswerCallAction(_ action: any SalemXCallKitAnswerActionCompleting) {
        #if DEBUG
        Task { @MainActor in
            SalemXStage2FSimulatorSignalingDebug.recordCallKitAnswerActionSeen()
        }
        #endif

        guard let incomingCallID else {
            action.fail()
            return
        }

        guard incomingCallID.callKitID == action.callUUID else {
            action.fail()
            return
        }

        guard let salemXIncomingCallBootstrapResolver,
              let salemXAnswerBridge else {
            finishEmbeddedMatrixRTCAnswer(callID: action.callUUID,
                                          incomingCallID: incomingCallID,
                                          result: .bootstrapUnavailable)
            action.fail()
            return
        }

        guard let bootstrap = salemXIncomingCallBootstrapResolver.verifiedBootstrap(for: action.callUUID) else {
            finishEmbeddedMatrixRTCAnswer(callID: action.callUUID,
                                          incomingCallID: incomingCallID,
                                          result: .bootstrapUnavailable)
            action.fail()
            return
        }

        guard bootstrap.callID == incomingCallID.callKitID,
              bootstrap.claimedMetadata.roomID == incomingCallID.roomID else {
            finishEmbeddedMatrixRTCAnswer(callID: action.callUUID,
                                          incomingCallID: incomingCallID,
                                          result: .bootstrapMismatch)
            action.fail()
            return
        }

        let actionID = ObjectIdentifier(action)
        if salemXEmbeddedAnswerTasks[action.callUUID] != nil {
            appendEmbeddedMatrixRTCAnswerAction(action, actionID: actionID)
            return
        }

        appendEmbeddedMatrixRTCAnswerAction(action, actionID: actionID)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            let result = await self.embeddedMatrixRTCAnswerResult(callID: action.callUUID,
                                                                  bootstrap: bootstrap,
                                                                  answerBridge: salemXAnswerBridge)
            guard !Task.isCancelled else {
                return
            }

            guard !self.salemXEmbeddedSupersededAnswerCallIDs.contains(action.callUUID) else {
                return
            }

            self.finishEmbeddedMatrixRTCAnswer(callID: action.callUUID,
                                               incomingCallID: incomingCallID,
                                               result: result)
        }
        salemXEmbeddedAnswerTasks[action.callUUID] = task
    }

    private func appendEmbeddedMatrixRTCAnswerAction(_ action: any SalemXCallKitAnswerActionCompleting, actionID: ObjectIdentifier) {
        guard salemXEmbeddedAnswerActionIDs[action.callUUID]?.contains(actionID) != true else {
            return
        }

        salemXEmbeddedAnswerActions[action.callUUID, default: []].append(action)
        salemXEmbeddedAnswerActionIDs[action.callUUID, default: []].insert(actionID)
    }

    @MainActor
    private func embeddedMatrixRTCAnswerResult(callID: UUID,
                                               bootstrap: VerifiedIncomingCallBootstrap,
                                               answerBridge: any SalemXEmbeddedCallAnswerBridging) async -> SalemXEmbeddedCallAnswerResult {
        let answerTimeout = salemXAnswerBridgeConfiguration.answerTimeout
        let result = await withTaskGroup(of: SalemXEmbeddedCallAnswerResult.self) { group in
            group.addTask {
                await answerBridge.answer(callID: callID, bootstrap: bootstrap)
            }
            group.addTask {
                try? await Task.sleep(for: answerTimeout)
                return SalemXEmbeddedCallAnswerResult.timedOut
            }

            guard let result = await group.next() else {
                return SalemXEmbeddedCallAnswerResult.failed
            }

            group.cancelAll()
            return result
        }

        return Task.isCancelled ? .cancelled : result
    }

    private func finishEmbeddedMatrixRTCAnswer(callID: UUID, incomingCallID: CallID, result: SalemXEmbeddedCallAnswerResult) {
        salemXEmbeddedAnswerTasks.removeValue(forKey: callID)?.cancel()
        let actions = salemXEmbeddedAnswerActions.removeValue(forKey: callID) ?? []
        salemXEmbeddedAnswerActionIDs.removeValue(forKey: callID)
        endUnansweredCallTask?.cancel()
        #if DEBUG
        Task { @MainActor in
            SalemXStage2FSimulatorSignalingDebug.recordAnswerGuardReleased()
            SalemXStage2FSimulatorSignalingDebug.recordReceiverAnswerResult(result)
        }
        #endif

        if result.isCallKitSuccess {
            promoteEmbeddedMatrixRTCAnsweredCall(incomingCallID)
            actions.forEach { $0.fulfill() }
        } else {
            removeVerifiedBootstrapOnce(for: callID)
            reportEndedCall(incomingCallID: incomingCallID, reason: .failed)
            actions.forEach { $0.fail() }
        }
    }

    private func promoteEmbeddedMatrixRTCAnsweredCall(_ incomingCallID: CallID) {
        if incomingCallID == self.incomingCallID {
            self.incomingCallID = nil
        }
        ongoingCallID = incomingCallID
        recentlyEndedCallID = nil
        if let rtcNotificationID = incomingCallID.rtcNotificationID {
            cacheRTCNotificationID(rtcNotificationID, for: incomingCallID.roomID)
        }
        if let remoteCallID = incomingCallID.remoteCallID {
            cacheRemoteCallID(remoteCallID, for: incomingCallID.roomID)
        }

        openCallSession(roomID: incomingCallID.roomID,
                        callKitID: incomingCallID.callKitID,
                        direction: .incoming,
                        remoteCallID: incomingCallID.remoteCallID)
        applySessionEvent(type: .accept, roomID: incomingCallID.roomID)
    }

    private func cancelEmbeddedMatrixRTCAnswer(for callID: UUID?) {
        guard let callID,
              let incomingCallID,
              salemXEmbeddedAnswerTasks[callID] != nil else {
            return
        }

        finishEmbeddedMatrixRTCAnswer(callID: callID,
                                      incomingCallID: incomingCallID,
                                      result: .cancelled)
    }

    private func handleEmbeddedMatrixRTCEndCallAction(_ action: any SalemXCallKitEndActionCompleting,
                                                      source: SalemXEmbeddedCallEndSource) {
        if salemXEmbeddedTerminatedCallIDs.contains(action.callUUID) {
            action.fulfill()
            return
        }

        guard let knownCallID = embeddedCallID(for: action.callUUID) else {
            action.fail()
            return
        }

        let actionID = ObjectIdentifier(action)
        if salemXEmbeddedEndTasks[action.callUUID] != nil {
            appendEmbeddedMatrixRTCEndAction(action, actionID: actionID)
            cancelEmbeddedMatrixRTCAnswerForEmbeddedEnd(callID: action.callUUID)
            return
        }

        appendEmbeddedMatrixRTCEndAction(action, actionID: actionID)

        guard let salemXIncomingCallBootstrapResolver,
              let salemXEndBridge else {
            finishEmbeddedMatrixRTCEnd(callID: action.callUUID,
                                       knownCallID: knownCallID,
                                       result: .noVerifiedBootstrap)
            return
        }

        guard let bootstrap = salemXIncomingCallBootstrapResolver.verifiedBootstrap(for: action.callUUID) else {
            finishEmbeddedMatrixRTCEnd(callID: action.callUUID,
                                       knownCallID: knownCallID,
                                       result: .noVerifiedBootstrap)
            return
        }

        guard bootstrap.callID == knownCallID.callKitID,
              bootstrap.claimedMetadata.roomID == knownCallID.roomID else {
            finishEmbeddedMatrixRTCEnd(callID: action.callUUID,
                                       knownCallID: knownCallID,
                                       result: .bootstrapMismatch)
            return
        }

        cancelEmbeddedMatrixRTCAnswerForEmbeddedEnd(callID: action.callUUID)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            let result = await self.embeddedMatrixRTCEndResult(callID: action.callUUID,
                                                               bootstrap: bootstrap,
                                                               source: source,
                                                               endBridge: salemXEndBridge)
            guard !Task.isCancelled else {
                return
            }

            self.finishEmbeddedMatrixRTCEnd(callID: action.callUUID,
                                            knownCallID: knownCallID,
                                            result: result)
        }
        salemXEmbeddedEndTasks[action.callUUID] = task
    }

    private func appendEmbeddedMatrixRTCEndAction(_ action: any SalemXCallKitEndActionCompleting, actionID: ObjectIdentifier) {
        guard salemXEmbeddedEndActionIDs[action.callUUID]?.contains(actionID) != true else {
            return
        }

        salemXEmbeddedEndActions[action.callUUID, default: []].append(action)
        salemXEmbeddedEndActionIDs[action.callUUID, default: []].insert(actionID)
    }

    @MainActor
    private func embeddedMatrixRTCEndResult(callID: UUID,
                                            bootstrap: VerifiedIncomingCallBootstrap,
                                            source: SalemXEmbeddedCallEndSource,
                                            endBridge: any SalemXEmbeddedCallEndBridging) async -> SalemXEmbeddedCallEndResult {
        let endTimeout = salemXAnswerBridgeConfiguration.endTimeout
        let result = await withTaskGroup(of: SalemXEmbeddedCallEndResult.self) { group in
            group.addTask {
                await endBridge.end(callID: callID, bootstrap: bootstrap, source: source)
            }
            group.addTask {
                try? await Task.sleep(for: endTimeout)
                return SalemXEmbeddedCallEndResult.timedOut
            }

            guard let result = await group.next() else {
                return SalemXEmbeddedCallEndResult.failed
            }

            group.cancelAll()
            return result
        }

        return Task.isCancelled ? .cancelled : result
    }

    private func finishEmbeddedMatrixRTCEnd(callID: UUID, knownCallID: CallID, result: SalemXEmbeddedCallEndResult) {
        let actions = drainEmbeddedMatrixRTCEndActions(for: callID)
        removeVerifiedBootstrapOnce(for: callID)
        clearEmbeddedMatrixRTCState(for: knownCallID)

        if result.isCallKitSuccess {
            salemXEmbeddedTerminatedCallIDs.insert(callID)
            actions.forEach { $0.fulfill() }
        } else {
            actions.forEach { $0.fail() }
        }
    }

    func handleEmbeddedMatrixRTCUpstreamTerminalEvent(callID: UUID, source: SalemXEmbeddedCallEndSource) {
        guard let knownCallID = embeddedCallID(for: callID) else {
            return
        }

        _ = handleEmbeddedMatrixRTCTerminalEventIfNeeded(knownCallID,
                                                         source: source,
                                                         deduplicationID: "embedded-terminal:\(source)")
    }

    @discardableResult
    private func handleEmbeddedMatrixRTCTerminalEventIfNeeded(_ knownCallID: CallID,
                                                              source: SalemXEmbeddedCallEndSource,
                                                              deduplicationID _: String?) -> Bool {
        guard salemXAnswerBridgeConfiguration.embeddedMatrixRTCAnswerBridgeEnabled,
              salemXIncomingCallBootstrapResolver?.verifiedBootstrap(for: knownCallID.callKitID) != nil else {
            return false
        }

        #if DEBUG
        Task { @MainActor in
            SalemXStage2FSimulatorSignalingDebug.recordReceiverRemoteEndSeen(source: source)
        }
        #endif

        let actions = drainEmbeddedMatrixRTCEndActions(for: knownCallID.callKitID)
        cancelEmbeddedMatrixRTCAnswerForEmbeddedEnd(callID: knownCallID.callKitID)
        removeVerifiedBootstrapOnce(for: knownCallID.callKitID)

        let inserted = salemXEmbeddedTerminatedCallIDs.insert(knownCallID.callKitID).inserted
        actions.forEach { $0.fulfill() }

        if inserted {
            if let callKitReason = callEndedReportReason(for: source).callKitEndedReason {
                reportEmbeddedMatrixRTCCallEnded(callID: knownCallID, reason: callKitReason)
            }
            actionsSubject.send(.endCall(roomID: knownCallID.roomID))
            clearEmbeddedMatrixRTCState(for: knownCallID)
            #if DEBUG
            Task { @MainActor in
                SalemXStage2FSimulatorSignalingDebug.recordCallUIDismissed()
            }
            #endif
        }

        return true
    }

    private func handleEmbeddedMatrixRTCProviderReset() {
        let callIDs = Set(salemXEmbeddedAnswerTasks.keys)
            .union(salemXEmbeddedEndTasks.keys)
            .union(incomingCallID.map { [$0.callKitID] } ?? [])
            .union(ongoingCallID.map { [$0.callKitID] } ?? [])

        callIDs.forEach { callID in
            cancelEmbeddedMatrixRTCAnswerForEmbeddedEnd(callID: callID)
            releaseEmbeddedMatrixRTCEndGuard(for: callID, result: .cancelled)
            removeVerifiedBootstrapOnce(for: callID)
        }

        if incomingCallID != nil {
            clearIncomingCallState(cancelEmbeddedAnswer: false)
        }

        if ongoingCallID != nil {
            tearDownCallSession(sendEndCallAction: false)
        }
    }

    private func embeddedCallID(for callID: UUID) -> CallID? {
        if let ongoingCallID, ongoingCallID.callKitID == callID {
            return ongoingCallID
        }

        if let incomingCallID, incomingCallID.callKitID == callID {
            return incomingCallID
        }

        return nil
    }

    private func drainEmbeddedMatrixRTCEndActions(for callID: UUID) -> [any SalemXCallKitEndActionCompleting] {
        salemXEmbeddedEndTasks.removeValue(forKey: callID)?.cancel()
        let actions = salemXEmbeddedEndActions.removeValue(forKey: callID) ?? []
        salemXEmbeddedEndActionIDs.removeValue(forKey: callID)
        #if DEBUG
        Task { @MainActor in
            SalemXStage2FSimulatorSignalingDebug.recordEndGuardReleased()
        }
        #endif
        return actions
    }

    private func releaseEmbeddedMatrixRTCEndGuard(for callID: UUID, result: SalemXEmbeddedCallEndResult) {
        let actions = drainEmbeddedMatrixRTCEndActions(for: callID)
        if result.isCallKitSuccess {
            actions.forEach { $0.fulfill() }
        } else {
            actions.forEach { $0.fail() }
        }
    }

    private func cancelEmbeddedMatrixRTCAnswerForEmbeddedEnd(callID: UUID) {
        salemXEmbeddedSupersededAnswerCallIDs.insert(callID)
        salemXEmbeddedAnswerTasks.removeValue(forKey: callID)
        let actions = salemXEmbeddedAnswerActions.removeValue(forKey: callID) ?? []
        salemXEmbeddedAnswerActionIDs.removeValue(forKey: callID)
        endUnansweredCallTask?.cancel()
        actions.forEach { $0.fail() }
    }

    private func clearEmbeddedMatrixRTCState(for knownCallID: CallID) {
        suppressIncomingFallback(for: knownCallID.roomID)

        if incomingCallID?.callKitID == knownCallID.callKitID {
            clearIncomingCallState(cancelEmbeddedAnswer: false)
        }

        if ongoingCallID?.callKitID == knownCallID.callKitID {
            tearDownCallSession(sendEndCallAction: false)
        }
    }

    private func removeVerifiedBootstrapOnce(for callID: UUID) {
        guard salemXEmbeddedClearedBootstrapCallIDs.insert(callID).inserted else {
            return
        }

        salemXIncomingCallBootstrapResolver?.removeVerifiedBootstrap(for: callID)
        #if DEBUG
        Task { @MainActor in
            SalemXStage2FSimulatorSignalingDebug.recordVerifiedBootstrapCleared()
        }
        #endif
    }

    private func reportEmbeddedMatrixRTCCallEnded(callID: CallID, reason: CXCallEndedReason) {
        let inserted = salemXEmbeddedReportedEndedCallIDs.insert(callID.callKitID).inserted
        #if DEBUG
        Task { @MainActor in
            SalemXStage2FSimulatorSignalingDebug.recordReceiverCallKitEndReport(inserted: inserted)
        }
        #endif
        guard inserted else {
            return
        }

        callProvider.reportCall(with: callID.callKitID, endedAt: nil, reason: reason)
    }

    private func callEndedReportReason(for source: SalemXEmbeddedCallEndSource) -> SalemXEmbeddedCallEndedReportReason {
        switch source {
        case .callKitLocalEnd, .embeddedLocalEnd:
            .localEnded
        case .embeddedRemoteEnd:
            .remoteEnded
        case .presentationFailure:
            .failedBeforeConnection
        case .answerTimeout:
            .unansweredOrTimeout
        case .systemReset:
            .systemReset
        }
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        if let ongoingCallID {
            actionsSubject.send(.setAudioEnabled(!action.isMuted, roomID: ongoingCallID.roomID))
        } else {
            MXLog.error("Failed muting/unmuting call, missing ongoingCallID")
        }
        
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        #if targetEnvironment(simulator)
        // This gets called for no reason on simulators, where CallKit
        // isn't even supported, ignore it.
        #else
        handleEndCallAction(action, provider: provider)
        #endif
    }

    func handleEndCallAction(_ action: any SalemXCallKitEndActionCompleting, provider _: any CXProviderProtocol) {
        guard salemXAnswerBridgeConfiguration.embeddedMatrixRTCAnswerBridgeEnabled else {
            handleLegacyEndCallAction(action)
            return
        }

        handleEmbeddedMatrixRTCEndCallAction(action, source: .callKitLocalEnd)
    }

    private func handleLegacyEndCallAction(_ action: any SalemXCallKitEndActionCompleting) {
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-ENDCALL-ENTRY] " +
            "ongoing_room_id=\(ongoingCallID?.roomID ?? "nil") " +
            "ongoing_callkit_id=\(ongoingCallID?.callKitID.uuidString ?? "nil") " +
            "active_room_id=\(activeCallSession?.roomID ?? "nil") " +
            "active_state=\(activeCallSession?.state.rawValue ?? "nil")")
        if let ongoingCallID {
            let isPreAnswerOutgoing = activeCallSession?.roomID == ongoingCallID.roomID &&
                activeCallSession?.state == .outgoingRinging
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-ENDCALL-BRANCH] " +
                "room_id=\(ongoingCallID.roomID) is_pre_answer_outgoing=\(isPreAnswerOutgoing)")
            applySessionEvent(type: .hangup, roomID: ongoingCallID.roomID)
            suppressIncomingFallback(for: ongoingCallID.roomID)
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SERVICE-ACTION-SEND] room_id=\(ongoingCallID.roomID) " +
                "state=\(activeCallSession?.state.rawValue ?? "nil")")
            actionsSubject.send(.requestCallTermination(roomID: ongoingCallID.roomID))
            if isPreAnswerOutgoing {
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-ENDCALL-DIRECT-HELPER] room_id=\(ongoingCallID.roomID) called=true")
                Task { [weak self] in
                    await self?.emitPreJoinOutgoingCancelSignal(roomID: ongoingCallID.roomID)
                }
            } else {
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-ENDCALL-DIRECT-HELPER] room_id=\(ongoingCallID.roomID) called=false reason=branch_false")
            }
            tearDownCallSession(sendEndCallAction: false)
        } else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-ENDCALL-BRANCH] room_id=nil is_pre_answer_outgoing=false reason=missing_ongoing_call_id")
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-ENDCALL-DIRECT-HELPER] room_id=nil called=false reason=missing_ongoing_call_id")
        }
        
        if let incomingCallID {
            applySessionEvent(type: .reject, roomID: incomingCallID.roomID)
            suppressIncomingFallback(for: incomingCallID.roomID)
            clearIncomingCallState()
            Task {
                _ = await sendDeclineCallEventWithRetry(in: incomingCallID.roomID,
                                                        preferredRTCNotificationID: incomingCallID.rtcNotificationID)
            }
        }

        action.fulfill()
    }
    
    // MARK: - Private
    
    private func tearDownCallSession(sendEndCallAction: Bool = true) {
        #if targetEnvironment(simulator)
        ongoingCallID = nil
        #else
        if sendEndCallAction, let ongoingCallID {
            let transaction = CXTransaction(action: CXEndCallAction(call: ongoingCallID.callKitID))
            callController.request(transaction) { error in
                if let error {
                    MXLog.error("Failed transaction with error: \(error)")
                }
            }
        }
        #endif
        
        if let ongoingCallID {
            suppressIncomingFallback(for: ongoingCallID.roomID)
            recentlyEndedCallID = ongoingCallID
            if let rtcNotificationID = ongoingCallID.rtcNotificationID {
                cacheRTCNotificationID(rtcNotificationID, for: ongoingCallID.roomID)
            }
        }
        
        if let activeCallSession {
            recentCallSessionByRoomID[activeCallSession.roomID] = activeCallSession
        }
        activeCallSession = nil

        ongoingDeclineRefreshTask?.cancel()
        ongoingDeclineRefreshTask = nil
        let ongoingDeclineHandles = drainOngoingDeclineListenerHandles()
        ongoingDeclineHandles.forEach { $0.cancel() }
        finishResolvingOngoingDeclines()
        ongoingCallID = nil
        ongoingCallTimelineCancellable = nil
    }
    
    private func registerVoIPPusherIfNeeded() async {
        guard let voIPPushToken, let clientProxy else {
            return
        }
        
        guard registeredVoIPPushToken != voIPPushToken else {
            return
        }
        
        registeredVoIPPushToken = voIPPushToken
        
        do {
            let defaultPayload = APNSPayload(aps: APSInfo(mutableContent: 1,
                                                          alert: APSAlert(locKey: "Notification",
                                                                          locArgs: [])),
                                             pusherNotificationClientIdentifier: clientProxy.pusherNotificationClientIdentifier)
            
            let configuration = try await PusherConfiguration(identifiers: .init(pushkey: voIPPushToken.base64EncodedString(),
                                                                                 appId: appSettings.voIPPusherAppID),
                                                              kind: .http(data: .init(url: appSettings.pushGatewayNotifyEndpoint.absoluteString,
                                                                                      format: .eventIdOnly,
                                                                                      defaultPayload: defaultPayload.toJsonString())),
                                                              appDisplayName: "\(InfoPlistReader.main.bundleDisplayName) (iOS)",
                                                              deviceDisplayName: UIDevice.current.name,
                                                              profileTag: voIPPusherProfileTag(),
                                                              lang: Bundle.app.preferredLocalizations.first ?? "en")
            try await clientProxy.setPusher(with: configuration)
            MXLog.info("Set VoIP pusher succeeded")
        } catch {
            registeredVoIPPushToken = nil
            MXLog.error("Set VoIP pusher failed: \(error)")
        }
    }

    private func observeIncomingCallFallback() {
        incomingCallFallbackCancellable = nil

        guard let clientProxy else {
            return
        }

        incomingCallFallbackCancellable = clientProxy.roomSummaryProvider.roomListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomSummaries in
                self?.handleIncomingCallFallback(roomSummaries: roomSummaries)
            }
    }

    private func handleIncomingCallFallback(roomSummaries: [RoomSummary]) {
        guard let clientProxy else {
            return
        }

        pruneIncomingFallbackSuppression(using: roomSummaries)

        guard incomingCallID == nil, ongoingCallID == nil else {
            return
        }

        let ownUserID = clientProxy.userID
        guard let roomSummary = roomSummaries.first(where: { isIncomingFallbackCandidate(roomSummary: $0, ownUserID: ownUserID) }) else {
            return
        }

        suppressIncomingFallback(for: roomSummary.id)
        Task { [weak self] in
            let isVideoIntent: Bool
            if let lastCallEvent = roomSummary.lastCallEvent,
               !Self.isTerminalCallEvent(lastCallEvent) {
                isVideoIntent = lastCallEvent.intent == .video
            } else {
                isVideoIntent = true
            }
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-FALLBACK-CANDIDATE] room_id=\(roomSummary.id) source=app_fallback " +
                "raw_payload_keys=nil raw_source=room_summary is_direct=\(roomSummary.isDirect) has_ongoing_call=\(roomSummary.hasOngoingCall) " +
                "active_participants=\(roomSummary.activeRoomCallParticipants) last_call_state=\(String(describing: roomSummary.lastCallEvent?.state)) " +
                "last_call_intent=\(String(describing: roomSummary.lastCallEvent?.intent)) parsed_intent_result=\(isVideoIntent ? "video" : "audio")")
            await self?.reportIncomingCallFromFallback(roomID: roomSummary.id,
                                                       roomDisplayName: roomSummary.name,
                                                       isVideo: isVideoIntent)
        }
    }

    private func handleForegroundRoomTimelineUpdate(itemProxies: [TimelineItemProxy],
                                                    roomProxy: JoinedRoomProxyProtocol,
                                                    roomDisplayName: String?) {
        let roomID = roomProxy.id
        guard foregroundRoomID == roomID,
              roomProxy.infoPublisher.value.isDirect else {
            return
        }

        guard incomingCallID == nil, ongoingCallID == nil else {
            return
        }

        guard let candidate = latestForegroundRoomIncomingCallCandidate(in: itemProxies) else {
            return
        }

        handleForegroundRoomIncomingCallCandidate(roomID: roomID,
                                                  roomDisplayName: roomDisplayName ?? roomProxy.infoPublisher.value.displayName,
                                                  isDirect: roomProxy.infoPublisher.value.isDirect,
                                                  candidate: candidate)
    }

    private func handleForegroundRoomIncomingCallCandidate(roomID: String,
                                                           roomDisplayName: String?,
                                                           isDirect: Bool,
                                                           candidate: ForegroundRoomIncomingCallCandidate) {
        guard foregroundRoomID == roomID,
              isDirect,
              incomingCallID == nil,
              ongoingCallID == nil else {
            return
        }

        guard !candidate.isOwnEvent,
              !Self.isTerminalCallEvent(candidate.callEvent),
              Self.isIncomingFallbackStartEvent(candidate.callEvent) else {
            return
        }

        guard handledForegroundIncomingCallByRoomID[roomID] != candidate.deduplicationID else {
            return
        }

        handledForegroundIncomingCallByRoomID[roomID] = candidate.deduplicationID
        incomingFallbackSuppressionByRoomID.removeValue(forKey: roomID)

        if let remoteCallID = candidate.callEvent.callID {
            cacheRemoteCallID(remoteCallID, for: roomID)
        }

        Task { [weak self] in
            await self?.reportIncomingCallFromForegroundRoom(roomID: roomID,
                                                             roomDisplayName: roomDisplayName,
                                                             isVideo: candidate.callEvent.intent != .audio)
        }
    }

    private func latestForegroundRoomIncomingCallCandidate(in itemProxies: [TimelineItemProxy]) -> ForegroundRoomIncomingCallCandidate? {
        for itemProxy in itemProxies.reversed() {
            guard case let .event(eventProxy) = itemProxy,
                  let callEvent = RoomCallEventParser.parse(from: eventProxy) else {
                continue
            }

            return .init(callEvent: callEvent,
                         deduplicationID: eventProxy.id.uniqueID.value,
                         isOwnEvent: eventProxy.isOwn)
        }

        return nil
    }

    private func isIncomingFallbackCandidate(roomSummary: RoomSummary, ownUserID: String) -> Bool {
        guard roomSummary.isDirect, roomSummary.hasOngoingCall else {
            return false
        }

        guard !roomSummary.activeRoomCallParticipants.contains(ownUserID) else {
            return false
        }

        guard !isIncomingFallbackSuppressed(roomSummary: roomSummary, ownUserID: ownUserID) else {
            return false
        }

        guard !Self.isTerminalCallEvent(roomSummary.lastCallEvent) else {
            return false
        }

        // Avoid showing a new incoming call from fallback right after we just placed/cancelled
        // an outgoing call in the same room.
        if roomSummary.lastCallEvent?.state == .outgoing {
            return false
        }

        return true
    }

    private func reportIncomingCallFromFallback(roomID: String, roomDisplayName: String?, isVideo: Bool) async {
        guard incomingCallID == nil, ongoingCallID == nil else {
            return
        }

        let nowDate = timeProvider.now()
        cachedRemoteCallIDByRoomID.removeValue(forKey: roomID)
        let callID = CallID(callKitID: UUID(),
                            roomID: roomID,
                            rtcNotificationID: nil,
                            remoteCallID: nil,
                            startMode: isVideo ? .video : .audio,
                            startedAt: nowDate)

        incomingCallID = callID
        openCallSession(roomID: roomID,
                        callKitID: callID.callKitID,
                        direction: .incoming,
                        remoteCallID: callID.remoteCallID)

        let update = CXCallUpdate()
        update.hasVideo = isVideo
        update.localizedCallerName = roomDisplayName
        update.remoteHandle = .init(type: .generic, value: roomID)
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-FALLBACK-CALLKIT] room_id=\(roomID) source=app_fallback " +
            "start_mode=\(callID.startMode) has_video=\(update.hasVideo) caller_name_source=roomSummary")

        callProvider.reportNewIncomingCall(with: callID.callKitID, update: update) { [weak self] error in
            if let error {
                MXLog.error("Fallback incoming call reporting failed: \(error)")
                self?.clearIncomingCallState()
                return
            }

            self?.actionsSubject.send(.receivedIncomingCallRequest)
        }

        endUnansweredCallTask?.cancel()
        endUnansweredCallTask = Task { [weak self] in
            try? await self?.timeProvider.clock.sleep(for: IncomingFallbackConstants.unansweredTimeout)

            guard let self, !Task.isCancelled else {
                return
            }

            guard let incomingCallID = self.incomingCallID, incomingCallID.callKitID == callID.callKitID else {
                return
            }

            reportEndedCall(incomingCallID: incomingCallID, reason: .unanswered)
        }
    }

    private func reportIncomingCallFromForegroundRoom(roomID: String, roomDisplayName: String?, isVideo: Bool) async {
        guard incomingCallID == nil, ongoingCallID == nil else {
            return
        }

        let nowDate = timeProvider.now()
        let remoteCallID = cachedRemoteCallIDByRoomID[roomID]
        let callID = CallID(callKitID: UUID(),
                            roomID: roomID,
                            rtcNotificationID: nil,
                            remoteCallID: remoteCallID,
                            startMode: isVideo ? .video : .audio,
                            startedAt: nowDate)

        incomingCallID = callID
        openCallSession(roomID: roomID,
                        callKitID: callID.callKitID,
                        direction: .incoming,
                        remoteCallID: callID.remoteCallID)

        let update = CXCallUpdate()
        update.hasVideo = isVideo
        update.localizedCallerName = roomDisplayName
        update.remoteHandle = .init(type: .generic, value: "salemx-call")

        MXLog.info("Element Call lifecycle diagnostics: foreground_current_room_incoming=true start_mode=\(callID.startMode)")

        callProvider.reportNewIncomingCall(with: callID.callKitID, update: update) { [weak self] error in
            if let error {
                MXLog.error("Foreground current-room incoming call reporting failed: \(error)")
                self?.clearIncomingCallState()
                return
            }

            self?.actionsSubject.send(.receivedIncomingCallRequest)
        }

        endUnansweredCallTask?.cancel()
        endUnansweredCallTask = Task { [weak self] in
            try? await self?.timeProvider.clock.sleep(for: IncomingFallbackConstants.unansweredTimeout)

            guard let self, !Task.isCancelled else {
                return
            }

            guard let incomingCallID = self.incomingCallID, incomingCallID.callKitID == callID.callKitID else {
                return
            }

            reportEndedCall(incomingCallID: incomingCallID, reason: .unanswered)
        }
    }

    #if DEBUG
    var salemXDebugStage2FCallKitLocalStateBucket: SalemXStage2FCallKitLocalStateBucket {
        if incomingCallID != nil {
            return .incomingCallActive
        }

        if ongoingCallID != nil {
            return .ongoingCallActive
        }

        return .idle
    }

    @MainActor
    func salemXDebugReportStage2FSimulatorIncomingCall(roomID: String,
                                                       roomDisplayName: String?,
                                                       startMode: ElementCallStartMode,
                                                       storeBootstrap: (UUID) -> Void) async -> SalemXStage2FCallKitReportResult {
        if incomingCallID != nil {
            return .blockedByExistingIncomingCall
        }

        if ongoingCallID != nil {
            return .blockedByExistingOngoingCall
        }

        let nowDate = timeProvider.now()
        let callID = CallID(callKitID: UUID(),
                            roomID: roomID,
                            rtcNotificationID: nil,
                            remoteCallID: nil,
                            startMode: startMode,
                            startedAt: nowDate)

        storeBootstrap(callID.callKitID)
        incomingCallID = callID
        openCallSession(roomID: roomID,
                        callKitID: callID.callKitID,
                        direction: .incoming,
                        remoteCallID: callID.remoteCallID)

        let update = CXCallUpdate()
        update.hasVideo = startMode == .video
        update.localizedCallerName = roomDisplayName
        update.remoteHandle = .init(type: .generic, value: "salemx-call")

        return await withCheckedContinuation { continuation in
            callProvider.reportNewIncomingCall(with: callID.callKitID, update: update) { [weak self] error in
                if let error {
                    self?.clearIncomingCallState()
                    continuation.resume(returning: .providerFailed(callID: callID.callKitID,
                                                                   errorBucket: Self.salemXDebugCallKitReportErrorBucket(error)))
                    return
                }

                self?.actionsSubject.send(.receivedIncomingCallRequest)
                continuation.resume(returning: .reported(callID.callKitID))
            }

            endUnansweredCallTask?.cancel()
            endUnansweredCallTask = Task { [weak self] in
                try? await self?.timeProvider.clock.sleep(for: IncomingFallbackConstants.unansweredTimeout)

                guard let self, !Task.isCancelled else {
                    return
                }

                guard let incomingCallID = self.incomingCallID, incomingCallID.callKitID == callID.callKitID else {
                    return
                }

                reportEndedCall(incomingCallID: incomingCallID, reason: .unanswered)
            }
        }
    }

    private static func salemXDebugCallKitReportErrorBucket(_ error: Error) -> SalemXStage2FCallKitReportErrorBucket {
        let error = error as NSError
        guard error.domain == CXErrorDomainIncomingCall,
              let code = CXErrorCodeIncomingCallError.Code(rawValue: error.code) else {
            return .other
        }

        switch code {
        case .unknown:
            return .unknown
        case .unentitled:
            return .unentitled
        case .callUUIDAlreadyExists:
            return .callUUIDAlreadyExists
        case .filteredByDoNotDisturb:
            return .filteredByDoNotDisturb
        case .filteredByBlockList:
            return .filteredByBlockList
        case .filteredDuringRestrictedSharingMode:
            return .filteredDuringRestrictedSharingMode
        case .callIsProtected:
            return .callIsProtected
        case .filteredBySensitiveParticipants:
            return .filteredBySensitiveParticipants
        @unknown default:
            return .unknown
        }
    }
    #endif

    private static func isTerminalCallEvent(_ roomCallEvent: RoomCallEvent?) -> Bool {
        switch roomCallEvent?.state {
        case .ended, .missed, .declined:
            true
        case .incoming, .outgoing, .started, .answered, .legacyInvite, .none:
            false
        }
    }

    private func suppressIncomingFallback(for roomID: String) {
        incomingFallbackSuppressionByRoomID[roomID] = Date().addingTimeInterval(IncomingFallbackConstants.suppressionDuration)
    }

    private func incomingStartMode(for payload: [AnyHashable: Any], roomID: String) -> ElementCallStartMode {
        if let callIntent = callIntent(from: payload),
           let parsedStartMode = Self.startMode(fromCallIntent: callIntent) {
            return parsedStartMode
        }

        // Keep the legacy fallback explicit: if the push payload has no
        // recognised intent, prefer the latest known room call event and
        // otherwise default to video.
        guard let roomSummary = clientProxy?.roomSummaryProvider.roomListPublisher.value.first(where: { $0.id == roomID }),
              roomSummary.hasOngoingCall,
              let lastCallEvent = roomSummary.lastCallEvent,
              !Self.isTerminalCallEvent(lastCallEvent) else {
            return .video
        }

        switch lastCallEvent.intent {
        case .audio:
            return .audio
        case .video, .unknown:
            return .video
        }
    }

    private func callIntent(from payload: [AnyHashable: Any]) -> String? {
        let intentKeys = [
            ElementCallServiceNotificationKey.callIntent.rawValue,
            "call_intent",
            "intent",
            "call_type",
            "callType"
        ]

        for intentKey in intentKeys {
            if let callIntent = payload.first(where: { payloadKey, _ in
                guard let payloadKey = payloadKey as? String else {
                    return false
                }

                return payloadKey.localizedCaseInsensitiveCompare(intentKey) == .orderedSame
            })?.value as? String {
                return callIntent
            }
        }

        return nil
    }

    private struct CallIntentTrace {
        let key: String?
        let value: String?
        let parsedStartMode: ElementCallStartMode?
    }

    private func callIntentTrace(from payload: [AnyHashable: Any]) -> CallIntentTrace {
        let intentKeys = [
            ElementCallServiceNotificationKey.callIntent.rawValue,
            "call_intent",
            "intent",
            "call_type",
            "callType"
        ]

        for intentKey in intentKeys {
            if let entry = payload.first(where: { payloadKey, _ in
                guard let payloadKey = payloadKey as? String else {
                    return false
                }

                return payloadKey.localizedCaseInsensitiveCompare(intentKey) == .orderedSame
            }), let callIntent = entry.value as? String {
                return CallIntentTrace(key: String(describing: entry.key),
                                       value: callIntent,
                                       parsedStartMode: Self.startMode(fromCallIntent: callIntent))
            }
        }

        return CallIntentTrace(key: nil, value: nil, parsedStartMode: nil)
    }

    private static func callTracePayloadSummary(_ payload: [AnyHashable: Any]) -> String {
        payload.keys.map { String(describing: $0) }.sorted().map { key in
            let value = payload.first { String(describing: $0.key) == key }?.value
            let renderedValue: String
            switch key {
            case ElementCallServiceNotificationKey.roomDisplayName.rawValue:
                renderedValue = "<redacted>"
            default:
                renderedValue = String(describing: value ?? "nil")
            }
            return "\(key)=\(renderedValue)"
        }.joined(separator: ",")
    }

    private static func callTraceStartMode(_ startMode: ElementCallStartMode?) -> String {
        guard let startMode else {
            return "nil"
        }

        return String(describing: startMode)
    }

    private func isIncomingFallbackSuppressed(roomSummary: RoomSummary, ownUserID: String) -> Bool {
        let roomID = roomSummary.id
        guard let expirationDate = incomingFallbackSuppressionByRoomID[roomID] else {
            return false
        }

        guard expirationDate > Date() else {
            incomingFallbackSuppressionByRoomID.removeValue(forKey: roomID)
            return false
        }

        guard !shouldBypassIncomingFallbackSuppression(roomSummary: roomSummary, ownUserID: ownUserID) else {
            incomingFallbackSuppressionByRoomID.removeValue(forKey: roomID)
            MXLog.info("Element Call lifecycle diagnostics: incoming_fallback_suppression_cleared=true reason=fresh_foreground_call")
            return false
        }

        return true
    }

    private func shouldBypassIncomingFallbackSuppression(roomSummary: RoomSummary, ownUserID: String) -> Bool {
        guard roomSummary.isDirect, roomSummary.hasOngoingCall else {
            return false
        }

        guard !roomSummary.activeRoomCallParticipants.contains(ownUserID) else {
            return false
        }

        guard !Self.isTerminalCallEvent(roomSummary.lastCallEvent) else {
            return false
        }

        if roomSummary.lastCallEvent?.state == .outgoing {
            return false
        }

        let hasRemoteParticipant = roomSummary.activeRoomCallParticipants.contains { $0 != ownUserID }
        let hasIncomingCallEvent = roomSummary.lastCallEvent.map(Self.isIncomingFallbackStartEvent) ?? false
        return hasRemoteParticipant || hasIncomingCallEvent
    }

    private static func isIncomingFallbackStartEvent(_ event: RoomCallEvent) -> Bool {
        switch event.state {
        case .incoming, .started, .answered, .legacyInvite:
            return true
        case .outgoing, .ended, .missed, .declined:
            return false
        }
    }

    private func pruneIncomingFallbackSuppression(using _: [RoomSummary]) {
        incomingFallbackSuppressionByRoomID = incomingFallbackSuppressionByRoomID.filter { _, expirationDate in
            expirationDate > Date()
        }
    }

    private func nextSessionSequence() -> UInt64 {
        callSessionSequence += 1
        return callSessionSequence
    }

    private func openCallSession(roomID: String,
                                 callKitID: UUID,
                                 direction: CallSessionDirection,
                                 remoteCallID: String?) {
        var session = CallSession(roomID: roomID,
                                  callKitID: callKitID,
                                  direction: direction,
                                  remoteCallID: remoteCallID)
        let event = CallSessionEvent(type: .invite,
                                     direction: direction,
                                     sequence: nextSessionSequence(),
                                     deduplicationID: "invite:\(callKitID.uuidString)")
        let transition = session.apply(event)
        activeCallSession = session
        recentCallSessionByRoomID[roomID] = session
        logCallSessionTransition(session: session, event: event, transition: transition)
    }

    private func applySessionEvent(type: CallSessionEventType,
                                   roomID: String,
                                   direction: CallSessionDirection? = nil,
                                   deduplicationID: String? = nil) {
        let existingSession: CallSession? = if let activeCallSession, activeCallSession.roomID == roomID {
            activeCallSession
        } else {
            recentCallSessionByRoomID[roomID]
        }

        guard var session = existingSession else {
            return
        }

        let event = CallSessionEvent(type: type,
                                     direction: direction,
                                     sequence: nextSessionSequence(),
                                     deduplicationID: deduplicationID)
        let transition = session.apply(event)
        logCallSessionTransition(session: session, event: event, transition: transition)

        if activeCallSession?.roomID == roomID {
            activeCallSession = session
        }
        recentCallSessionByRoomID[roomID] = session
    }

    private func logCallSessionTransition(session: CallSession, event: CallSessionEvent, transition: CallSessionTransitionResult) {
        if transition.isApplied {
            MXLog.info("Call session \(session.callID) transition \(transition.previousState.rawValue) -> \(transition.state.rawValue) on \(event.type.rawValue)")
        } else if let rejectionReason = transition.rejectionReason {
            MXLog.verbose("Ignored call session event \(event.type.rawValue) for \(session.callID): \(rejectionReason)")
        }
    }

    private func sessionEventType(for reason: CXCallEndedReason) -> CallSessionEventType {
        switch reason {
        case .declinedElsewhere:
            return .reject
        case .answeredElsewhere:
            return .answeredElsewhere
        case .unanswered, .failed:
            return .timeout
        case .remoteEnded:
            return .hangup
        @unknown default:
            return .hangup
        }
    }

    private static func startMode(fromCallIntent callIntent: String?) -> ElementCallStartMode? {
        guard let callIntent else {
            return nil
        }
        let normalizedCallIntent = callIntent
            .lowercased()
            .replacingOccurrences(of: "optional(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let compactIntent = normalizedCallIntent.replacingOccurrences(of: " ", with: "")
        let knownAudioIntents = Set(["audio", "voice", "dmvoice", "startcalldmvoice", "m.intent.voice", "m.intent.audio"])
        let knownVideoIntents = Set(["video", "startcall", "startcalldm", "dm", "m.intent.video"])

        if knownAudioIntents.contains(compactIntent) {
            return .audio
        }

        if knownVideoIntents.contains(compactIntent) {
            return .video
        }

        if compactIntent.contains("video") {
            return .video
        }

        if compactIntent.contains("audio") {
            return .audio
        }

        if compactIntent.contains("voice"), !compactIntent.contains("video") {
            return .audio
        }

        return nil
    }
    
    private func voIPPusherProfileTag() -> String {
        if let currentTag = appSettings.voIPPusherProfileTag {
            return currentTag
        }
        
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        let newTag = (0..<16).map { _ in
            let offset = Int.random(in: 0..<chars.count)
            return String(chars[chars.index(chars.startIndex, offsetBy: offset)])
        }.joined()
        
        appSettings.voIPPusherProfileTag = newTag
        return newTag
    }
    
    @discardableResult
    private func sendDeclineCallEvent(in roomID: String, preferredRTCNotificationID: String?) async -> DeclineAttemptResult {
        guard let clientProxy else {
            MXLog.warning("A ClientProxy is needed to fetch the room.")
            return .failed
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(roomID) else {
            MXLog.warning("Failed to fetch a joined room for room ID \(roomID).")
            return .failed
        }

        guard let rtcNotificationID = await resolveRTCNotificationID(for: roomProxy,
                                                                     roomID: roomID,
                                                                     preferredRTCNotificationID: preferredRTCNotificationID,
                                                                     expectedOwnEvent: false) else {
            MXLog.info("No rtc notification event to decline for room \(roomID).")
            return .notFound
        }
        
        cacheRTCNotificationID(rtcNotificationID, for: roomID)

        switch await roomProxy.declineCall(notificationID: rtcNotificationID) {
        case .success:
            return .sent
        case .failure(let error):
            if isDeclineOwnCallError(error) {
                MXLog.info("Skipping decline for own rtc notification in room \(roomID).")
                return .ownEvent
            }
            MXLog.error("Failed declining call for room \(roomID) with notification \(rtcNotificationID): \(error)")
            return .failed
        }
    }

    @discardableResult
    private func sendDeclineCallEventWithRetry(in roomID: String, preferredRTCNotificationID: String?) async -> Bool {
        switch await sendDeclineCallEvent(in: roomID, preferredRTCNotificationID: preferredRTCNotificationID) {
        case .sent, .notFound, .ownEvent:
            return true
        case .failed:
            return false
        }
    }

    private func emitPreJoinOutgoingCancelSignal(roomID: String) async {
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SENDER-DIRECT] room_id=\(roomID) step=start")

        guard let clientProxy else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SENDER-DIRECT] room_id=\(roomID) step=abort reason=missing_client_proxy")
            return
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(roomID) else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SENDER-DIRECT] room_id=\(roomID) step=abort reason=room_not_joined")
            return
        }

        guard let joinedRoomProxy = roomProxy as? JoinedRoomProxy else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SENDER-DIRECT] room_id=\(roomID) step=abort reason=joined_proxy_not_concrete")
            return
        }

        let callID = preferredRemoteCallID(for: roomID)
        switch await joinedRoomProxy.sendPreJoinCallHangup(callID: callID) {
        case .success:
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SENDER-DIRECT] room_id=\(roomID) step=done call_id=\(callID ?? "nil")")
        case .failure(let error):
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SENDER-DIRECT] room_id=\(roomID) step=failed call_id=\(callID ?? "nil")")
            MXLog.error("Failed sending direct pre-join cancel signal for room \(roomID): \(error)")
        }
    }

    private func resolveIncomingDirectCallRoomIDForDecline() -> String? {
        guard let clientProxy else {
            MXLog.warning("A ClientProxy is needed to resolve incoming calls.")
            return nil
        }

        let ownUserID = clientProxy.userID
        return clientProxy.roomSummaryProvider.roomListPublisher.value.first { room in
            room.isDirect &&
                room.hasOngoingCall &&
                !room.activeRoomCallParticipants.contains(ownUserID)
        }?.id
    }

    private func resolveRTCNotificationID(for roomProxy: JoinedRoomProxyProtocol,
                                          roomID: String,
                                          preferredRTCNotificationID: String?,
                                          expectedOwnEvent: Bool) async -> String? {
        if let preferredRTCNotificationID {
            return preferredRTCNotificationID
        }

        // The timeline item provider is lazily initialized by subscribing.
        // Without this we can hit a crash in TimelineProxy when accessed from
        // call teardown flows that run without an already-open room timeline.
        await ensureTimelineSubscribed(for: roomProxy, roomID: roomID)

        let itemProxies = await MainActor.run { roomProxy.timeline.timelineItemProvider.itemProxies }
        for itemProxy in itemProxies.reversed() {
            guard case let .event(eventProxy) = itemProxy,
                  let eventID = eventProxy.id.eventID,
                  eventProxy.isOwn == expectedOwnEvent,
                  isDeclinableCallNotification(eventProxy) else {
                continue
            }

            return eventID
        }

        return nil
    }

    private func resolveCandidateRTCNotificationIDs(for roomProxy: JoinedRoomProxyProtocol,
                                                    roomID: String,
                                                    preferredRTCNotificationID: String?,
                                                    includeOwnEventIDs: Bool) async -> [String] {
        var rtcNotificationIDs: [String] = []

        await ensureTimelineSubscribed(for: roomProxy, roomID: roomID)
        let itemProxies = await MainActor.run { roomProxy.timeline.timelineItemProvider.itemProxies }
        var ownRTCNotificationIDs = Set<String>()
        var remoteRTCNotificationIDs: [String] = []

        for itemProxy in itemProxies.reversed() {
            guard case let .event(eventProxy) = itemProxy,
                  let eventID = eventProxy.id.eventID,
                  isDeclinableCallNotification(eventProxy) else {
                continue
            }

            if eventProxy.isOwn {
                ownRTCNotificationIDs.insert(eventID)
            } else if !remoteRTCNotificationIDs.contains(eventID) {
                remoteRTCNotificationIDs.append(eventID)
            }
        }

        func appendUnique(_ rtcNotificationID: String?) {
            guard let rtcNotificationID, !rtcNotificationIDs.contains(rtcNotificationID) else {
                return
            }
            if !includeOwnEventIDs, ownRTCNotificationIDs.contains(rtcNotificationID) {
                return
            }
            if !includeOwnEventIDs,
               cachedRTCNotificationIDByRoomID[roomID] == rtcNotificationID,
               cachedRTCNotificationOwnershipByRoomID[roomID] == true {
                return
            }

            rtcNotificationIDs.append(rtcNotificationID)
        }

        appendUnique(preferredRTCNotificationID)
        appendUnique(cachedRTCNotificationIDByRoomID[roomID])

        remoteRTCNotificationIDs.forEach { appendUnique($0) }

        if includeOwnEventIDs {
            ownRTCNotificationIDs.forEach { appendUnique($0) }
        }

        return rtcNotificationIDs
    }

    private func isDeclineOwnCallError(_ error: Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("declineowncall") || description.contains("cannot decline your own call")
    }

    private func isDeclinableCallNotification(_ eventProxy: EventTimelineItemProxy) -> Bool {
        switch eventProxy.content {
        case .callInvite, .rtcNotification:
            return true
        case .msgLike(let messageLikeContent):
            guard case let .other(eventType) = messageLikeContent.kind else {
                return false
            }

            switch eventType {
            case .callInvite, .callNotify, .rtcNotification:
                return true
            case .audio,
                 .beacon,
                 .callAnswer,
                 .callCandidates,
                 .callHangup,
                 .callNegotiate,
                 .callReject,
                 .callSdpStreamMetadataChanged,
                 .callSelectAnswer,
                 .emote,
                 .encrypted,
                 .file,
                 .image,
                 .keyVerificationAccept,
                 .keyVerificationCancel,
                 .keyVerificationDone,
                 .keyVerificationKey,
                 .keyVerificationMac,
                 .keyVerificationReady,
                 .keyVerificationStart,
                 .location,
                 .message,
                 .pollEnd,
                 .pollResponse,
                 .pollStart,
                 .reaction,
                 .roomEncrypted,
                 .roomMessage,
                 .roomRedaction,
                 .rtcDecline,
                 .sticker,
                 .unstablePollEnd,
                 .unstablePollResponse,
                 .unstablePollStart,
                 .video,
                 .voice:
                return false
            case .other:
                return false
            }
        case .failedToParseMessageLike,
             .failedToParseState,
             .liveLocation,
             .profileChange,
             .roomMembership,
             .state:
            return false
        }
    }
    
    private func observeIncomingCall() async {
        incomingCallTimelineCancellable = nil
        incomingCallRoomInfoCancellable = nil
        declineListenerHandle?.cancel()
        declineListenerHandle = nil
        
        guard let incomingCallID else {
            endUnansweredCallTask?.cancel()
            endUnansweredCallTask = nil
            return
        }
        
        guard let clientProxy else {
            MXLog.warning("A ClientProxy is needed to fetch the room.")
            return
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(incomingCallID.roomID) else {
            MXLog.warning("Failed to fetch a joined room for the incoming call.")
            return
        }

        await observeIncomingCallTimeline(roomProxy: roomProxy, incomingCallID: incomingCallID)
        await observeIncomingCallRoomInfo(roomProxy: roomProxy, incomingCallID: incomingCallID)
        
        guard let rtcNotificationID = incomingCallID.rtcNotificationID else {
            MXLog.warning("Decline: No RTC notification ID found for the incoming call.")
            return
        }
        
        let listener: CallDeclineListener = SDKListener { [weak self] senderID in
            guard let self else { return }
            let deduplicationID = "decline:\(rtcNotificationID):\(senderID)"

            if senderID == roomProxy.ownUserID {
                reportEndedCall(incomingCallID: incomingCallID,
                                reason: .declinedElsewhere,
                                deduplicationID: deduplicationID)
            } else {
                reportEndedCall(incomingCallID: incomingCallID,
                                reason: .remoteEnded,
                                deduplicationID: deduplicationID)
            }
        }
        
        guard case let .success(handle) = roomProxy.subscribeToCallDeclineEvents(rtcNotificationEventID: rtcNotificationID, listener: listener) else {
            MXLog.error("Unable to listen for decline events.")
            return
        }
        
        declineListenerHandle = handle
    }

    private func observeOngoingCall() async {
        ongoingCallTimelineCancellable = nil
        ongoingCallRoomInfoCancellable = nil
        ongoingDeclineRefreshTask?.cancel()
        ongoingDeclineRefreshTask = nil
        let ongoingDeclineHandles = drainOngoingDeclineListenerHandles()
        ongoingDeclineHandles.forEach { $0.cancel() }
        finishResolvingOngoingDeclines()

        guard let ongoingCallID else {
            return
        }

        guard let clientProxy else {
            MXLog.warning("A ClientProxy is needed to observe an ongoing call.")
            return
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(ongoingCallID.roomID) else {
            MXLog.warning("Failed to fetch a joined room for the ongoing call.")
            return
        }
        await observeOngoingCallTimeline(roomProxy: roomProxy, ongoingCallID: ongoingCallID)
        await observeOngoingCallRoomInfo(roomProxy: roomProxy, ongoingCallID: ongoingCallID)

        await startObservingOngoingDeclines(roomProxy: roomProxy, ongoingCallID: ongoingCallID)
        scheduleOngoingDeclineRefresh(roomProxy: roomProxy, ongoingCallID: ongoingCallID)
    }

    private func observeIncomingCallTimeline(roomProxy: JoinedRoomProxyProtocol, incomingCallID: CallID) async {
        await ensureTimelineSubscribed(for: roomProxy, roomID: incomingCallID.roomID)

        let timelineItemProvider = await MainActor.run {
            roomProxy.timeline.timelineItemProvider
        }
        let tracker = TerminationEventTracker()

        incomingCallTimelineCancellable = await MainActor.run {
            timelineItemProvider.updatePublisher
                .map(\.0)
                .sink { [weak self] itemProxies in
                    guard let self else { return }
                    guard self.incomingCallID?.callKitID == incomingCallID.callKitID else { return }
                    self.cacheLatestCallContext(in: itemProxies, for: incomingCallID.roomID)
                    guard let terminationEvent = self.latestIncomingCallTerminationEvent(in: itemProxies, roomID: incomingCallID.roomID) else { return }
                    guard terminationEvent.eventID != tracker.eventID else { return }

                    tracker.eventID = terminationEvent.eventID
                    IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-RECIPIENT-TERMINAL] room_id=\(incomingCallID.roomID) " +
                        "event_id=\(terminationEvent.eventID) reason=\(terminationEvent.reason)")
                    self.reportEndedCall(incomingCallID: incomingCallID,
                                         reason: terminationEvent.reason,
                                         deduplicationID: terminationEvent.eventID)
                }
        }
    }

    private func observeOngoingCallTimeline(roomProxy: JoinedRoomProxyProtocol, ongoingCallID: CallID) async {
        await ensureTimelineSubscribed(for: roomProxy, roomID: ongoingCallID.roomID)

        let timelineItemProvider = await MainActor.run {
            roomProxy.timeline.timelineItemProvider
        }
        let tracker = TerminationEventTracker()

        ongoingCallTimelineCancellable = await MainActor.run {
            timelineItemProvider.updatePublisher
                .map(\.0)
                .sink { [weak self] itemProxies in
                    guard let self else { return }
                    guard self.ongoingCallID?.callKitID == ongoingCallID.callKitID else { return }
                    self.cacheLatestCallContext(in: itemProxies, for: ongoingCallID.roomID)
                    self.refreshOngoingDeclineListeners(roomProxy: roomProxy,
                                                        ongoingCallID: ongoingCallID,
                                                        itemProxies: itemProxies)
                    guard let terminationEvent = self.latestRemoteTerminationEvent(in: itemProxies, roomID: ongoingCallID.roomID) else { return }
                    guard terminationEvent.eventID != tracker.eventID else { return }

                    tracker.eventID = terminationEvent.eventID
                    self.endOngoingCall(ongoingCallID,
                                        reason: terminationEvent.reason,
                                        deduplicationID: terminationEvent.eventID)
                }
        }
    }

    private func observeIncomingCallRoomInfo(roomProxy: JoinedRoomProxyProtocol, incomingCallID: CallID) async {
        let tracker = RoomCallPresenceTracker()
        let ownUserID = roomProxy.ownUserID

        incomingCallRoomInfoCancellable = roomProxy.infoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomInfo in
                guard let self else { return }
                guard self.incomingCallID?.callKitID == incomingCallID.callKitID else { return }

                let participants = Set(roomInfo.activeRoomCallParticipants)
                let hasActiveCall = roomInfo.hasRoomCall || !participants.isEmpty
                let hasLocalParticipant = participants.contains { self.participantBelongsToUser($0, userID: ownUserID) }
                let hasRemoteParticipant = participants.contains { !self.participantBelongsToUser($0, userID: ownUserID) }
                #if DEBUG
                Task { @MainActor in
                    SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCObservation(participantCount: participants.count,
                                                                                    hasActiveCall: hasActiveCall,
                                                                                    localParticipantPresent: hasLocalParticipant,
                                                                                    remoteParticipantPresent: hasRemoteParticipant)
                }
                #endif
                if hasActiveCall {
                    tracker.hasSeenActiveCall = true
                    return
                }

                if hasRemoteParticipant {
                    tracker.hasSeenRemoteParticipant = true
                }

                guard tracker.hasSeenActiveCall else {
                    return
                }

                self.reportEndedCall(incomingCallID: incomingCallID,
                                     reason: .remoteEnded,
                                     deduplicationID: self.roomInfoDeduplicationID(prefix: "incoming-info",
                                                                                   roomInfo: roomInfo))
            }
    }

    private func observeOngoingCallRoomInfo(roomProxy: JoinedRoomProxyProtocol, ongoingCallID: CallID) async {
        let tracker = RoomCallPresenceTracker()
        let ownUserID = roomProxy.ownUserID

        ongoingCallRoomInfoCancellable = roomProxy.infoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomInfo in
                guard let self else { return }
                guard self.ongoingCallID?.callKitID == ongoingCallID.callKitID else { return }

                let participants = Set(roomInfo.activeRoomCallParticipants)
                let hasActiveCall = roomInfo.hasRoomCall || !participants.isEmpty
                let hasLocalParticipant = participants.contains { self.participantBelongsToUser($0, userID: ownUserID) }
                #if DEBUG
                Task { @MainActor in
                    SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCObservation(participantCount: participants.count,
                                                                                    hasActiveCall: hasActiveCall,
                                                                                    localParticipantPresent: hasLocalParticipant,
                                                                                    remoteParticipantPresent: participants.contains { !self.participantBelongsToUser($0, userID: ownUserID) })
                }
                #endif
                if hasActiveCall {
                    tracker.hasSeenActiveCall = true
                }

                let foreignParticipantsCount = participants.filter { !self.participantBelongsToUser($0, userID: ownUserID) }.count
                let hasRemoteParticipant = foreignParticipantsCount > 0
                if hasRemoteParticipant {
                    tracker.hasSeenRemoteParticipant = true
                    tracker.noForeignParticipantSince = nil
                }

                let shouldEndBecauseCallStopped = tracker.hasSeenActiveCall && !hasActiveCall
                let shouldTrackNoForeignFallback = roomInfo.isDirect && tracker.hasSeenActiveCall && tracker.hasSeenRemoteParticipant
                if shouldTrackNoForeignFallback && !hasRemoteParticipant && tracker.noForeignParticipantSince == nil {
                    tracker.noForeignParticipantSince = self.timeProvider.now()
                }

                let noForeignParticipantElapsed: TimeInterval? = if let noForeignParticipantSince = tracker.noForeignParticipantSince {
                    self.timeProvider.now().timeIntervalSince(noForeignParticipantSince)
                } else {
                    nil
                }
                let shouldEndBecauseRemoteLeft = shouldTrackNoForeignFallback &&
                    !hasRemoteParticipant &&
                    (noForeignParticipantElapsed ?? 0) >= CallTerminationConstants.noForeignParticipantGraceWindow

                guard shouldEndBecauseCallStopped || shouldEndBecauseRemoteLeft else {
                    return
                }

                self.endOngoingCall(ongoingCallID,
                                    reason: .remoteEnded,
                                    deduplicationID: self.roomInfoDeduplicationID(prefix: "ongoing-info",
                                                                                  roomInfo: roomInfo))
            }
    }

    private func roomInfoDeduplicationID(prefix: String, roomInfo: RoomInfoProxyProtocol) -> String {
        let participants = roomInfo.activeRoomCallParticipants.sorted().joined(separator: ",")
        return "\(prefix):\(roomInfo.id):\(roomInfo.hasRoomCall):\(participants)"
    }

    private func participantBelongsToUser(_ participant: String, userID: String) -> Bool {
        participant == userID || participant.hasPrefix("_\(userID)_")
    }

    private func isIncomingCallStillAliveBeforeAnswer(_ incomingCallID: CallID) async -> Bool {
        guard let clientProxy else {
            MXLog.warning("Incoming answer guard missing ClientProxy for room \(incomingCallID.roomID)")
            return true
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(incomingCallID.roomID) else {
            MXLog.warning("Incoming answer guard missing joined room for room \(incomingCallID.roomID)")
            return true
        }

        for attempt in 0..<6 {
            let participants = Set(roomProxy.infoPublisher.value.activeRoomCallParticipants)
            let hasForeignParticipant = participants.contains { !participantBelongsToUser($0, userID: roomProxy.ownUserID) }
            if hasForeignParticipant {
                return true
            }

            guard attempt < 5 else {
                break
            }

            try? await timeProvider.clock.sleep(for: .milliseconds(250))
        }

        MXLog.info("Incoming answer guard marked stale incoming for room \(incomingCallID.roomID)")
        return false
    }
    
    private func startObservingOngoingDeclines(roomProxy: JoinedRoomProxyProtocol, ongoingCallID: CallID) async {
        guard beginResolvingOngoingDeclines() else {
            return
        }
        defer { finishResolvingOngoingDeclines() }
        
        var unresolvedRTCNotificationIDs: [String] = []
        for attempt in 0..<5 {
            let rtcNotificationIDs = await resolveCandidateRTCNotificationIDs(for: roomProxy,
                                                                              roomID: ongoingCallID.roomID,
                                                                              preferredRTCNotificationID: ongoingCallID.rtcNotificationID,
                                                                              includeOwnEventIDs: true)
            unresolvedRTCNotificationIDs = unresolvedDeclineRTCNotificationIDs(from: rtcNotificationIDs)
            if !unresolvedRTCNotificationIDs.isEmpty {
                break
            }

            guard ongoingCallID.callKitID == self.ongoingCallID?.callKitID else {
                return
            }

            guard attempt < 4 else {
                break
            }

            try? await Task.sleep(for: .milliseconds(150))
        }

        guard !unresolvedRTCNotificationIDs.isEmpty else {
            return
        }

        let listener: CallDeclineListener = SDKListener { [weak self] senderID in
            guard let self else { return }
            guard senderID != roomProxy.ownUserID else { return }
            guard self.ongoingCallID?.callKitID == ongoingCallID.callKitID else { return }
            let deduplicationID = "decline:\(ongoingCallID.roomID):\(senderID)"
            
            endOngoingCall(ongoingCallID, reason: .remoteEnded, deduplicationID: deduplicationID)
        }

        for rtcNotificationID in unresolvedRTCNotificationIDs {
            cacheRTCNotificationID(rtcNotificationID, for: ongoingCallID.roomID)

            guard case let .success(handle) = roomProxy.subscribeToCallDeclineEvents(rtcNotificationEventID: rtcNotificationID,
                                                                                     listener: listener) else {
                MXLog.error("Unable to listen for decline events on ongoing call for notification \(rtcNotificationID).")
                continue
            }

            storeDeclineListenerHandle(handle, for: rtcNotificationID)
        }
    }

    private func scheduleOngoingDeclineRefresh(roomProxy: JoinedRoomProxyProtocol, ongoingCallID: CallID) {
        ongoingDeclineRefreshTask?.cancel()
        ongoingDeclineRefreshTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }

                guard self.ongoingCallID?.callKitID == ongoingCallID.callKitID else {
                    return
                }

                await startObservingOngoingDeclines(roomProxy: roomProxy, ongoingCallID: ongoingCallID)
            }
        }
    }

    private func beginResolvingOngoingDeclines() -> Bool {
        ongoingDeclineObservationLock.lock()
        defer { ongoingDeclineObservationLock.unlock() }

        guard !isResolvingOngoingDeclines else {
            return false
        }

        isResolvingOngoingDeclines = true
        return true
    }

    private func finishResolvingOngoingDeclines() {
        ongoingDeclineObservationLock.lock()
        isResolvingOngoingDeclines = false
        ongoingDeclineObservationLock.unlock()
    }

    private func drainOngoingDeclineListenerHandles() -> [TaskHandle] {
        ongoingDeclineObservationLock.lock()
        defer { ongoingDeclineObservationLock.unlock() }

        let handles = Array(ongoingDeclineListenerHandles.values)
        ongoingDeclineListenerHandles.removeAll()
        return handles
    }

    private func unresolvedDeclineRTCNotificationIDs(from rtcNotificationIDs: [String]) -> [String] {
        ongoingDeclineObservationLock.lock()
        defer { ongoingDeclineObservationLock.unlock() }

        return rtcNotificationIDs.filter { ongoingDeclineListenerHandles[$0] == nil }
    }

    private func storeDeclineListenerHandle(_ handle: TaskHandle, for rtcNotificationID: String) {
        ongoingDeclineObservationLock.lock()
        ongoingDeclineListenerHandles[rtcNotificationID] = handle
        ongoingDeclineObservationLock.unlock()
    }

    private func cacheRTCNotificationID(_ rtcNotificationID: String, for roomID: String, isOwnEvent: Bool? = nil) {
        let previousRTCNotificationID = cachedRTCNotificationIDByRoomID[roomID]
        cachedRTCNotificationIDByRoomID[roomID] = rtcNotificationID
        if let isOwnEvent {
            cachedRTCNotificationOwnershipByRoomID[roomID] = isOwnEvent
        } else if previousRTCNotificationID != rtcNotificationID {
            cachedRTCNotificationOwnershipByRoomID.removeValue(forKey: roomID)
        }

        // Keep the active call identifier stable once it has been set. Updating it on every
        // discovered rtcNotificationID can trigger repeated observe restarts and UI stalls.
        if let ongoingCallID,
           ongoingCallID.roomID == roomID,
           ongoingCallID.rtcNotificationID == nil {
            self.ongoingCallID = CallID(callKitID: ongoingCallID.callKitID,
                                        roomID: ongoingCallID.roomID,
                                        rtcNotificationID: rtcNotificationID,
                                        remoteCallID: ongoingCallID.remoteCallID,
                                        startMode: ongoingCallID.startMode,
                                        startedAt: ongoingCallID.startedAt)
        }

        if let recentlyEndedCallID, recentlyEndedCallID.roomID == roomID, recentlyEndedCallID.rtcNotificationID != rtcNotificationID {
            self.recentlyEndedCallID = CallID(callKitID: recentlyEndedCallID.callKitID,
                                              roomID: recentlyEndedCallID.roomID,
                                              rtcNotificationID: rtcNotificationID,
                                              remoteCallID: recentlyEndedCallID.remoteCallID,
                                              startMode: recentlyEndedCallID.startMode,
                                              startedAt: recentlyEndedCallID.startedAt)
        }
    }

    private func cacheRemoteCallID(_ remoteCallID: String, for roomID: String) {
        cachedRemoteCallIDByRoomID[roomID] = remoteCallID

        if let incomingCallID,
           incomingCallID.roomID == roomID,
           incomingCallID.remoteCallID != remoteCallID {
            self.incomingCallID = CallID(callKitID: incomingCallID.callKitID,
                                         roomID: incomingCallID.roomID,
                                         rtcNotificationID: incomingCallID.rtcNotificationID,
                                         remoteCallID: remoteCallID,
                                         startMode: incomingCallID.startMode,
                                         startedAt: incomingCallID.startedAt)
        }

        if let ongoingCallID,
           ongoingCallID.roomID == roomID,
           ongoingCallID.remoteCallID != remoteCallID {
            self.ongoingCallID = CallID(callKitID: ongoingCallID.callKitID,
                                        roomID: ongoingCallID.roomID,
                                        rtcNotificationID: ongoingCallID.rtcNotificationID,
                                        remoteCallID: remoteCallID,
                                        startMode: ongoingCallID.startMode,
                                        startedAt: ongoingCallID.startedAt)
        }

        if let recentlyEndedCallID,
           recentlyEndedCallID.roomID == roomID,
           recentlyEndedCallID.remoteCallID != remoteCallID {
            self.recentlyEndedCallID = CallID(callKitID: recentlyEndedCallID.callKitID,
                                              roomID: recentlyEndedCallID.roomID,
                                              rtcNotificationID: recentlyEndedCallID.rtcNotificationID,
                                              remoteCallID: remoteCallID,
                                              startMode: recentlyEndedCallID.startMode,
                                              startedAt: recentlyEndedCallID.startedAt)
        }

        if var activeCallSession, activeCallSession.roomID == roomID {
            activeCallSession.updateRemoteCallID(remoteCallID)
            self.activeCallSession = activeCallSession
            recentCallSessionByRoomID[roomID] = activeCallSession
        } else if var recentCallSession = recentCallSessionByRoomID[roomID] {
            recentCallSession.updateRemoteCallID(remoteCallID)
            recentCallSessionByRoomID[roomID] = recentCallSession
        }
    }

    private func cacheLatestCallContext(in itemProxies: [TimelineItemProxy], for roomID: String) {
        for itemProxy in itemProxies.reversed() {
            guard case let .event(eventProxy) = itemProxy,
                  let eventID = eventProxy.id.eventID,
                  let callEvent = RoomCallEventParser.parse(from: eventProxy) else {
                continue
            }

            if let remoteCallID = callEvent.callID {
                cacheRemoteCallID(remoteCallID, for: roomID)
            }

            if isDeclinableCallNotification(eventProxy) {
                cacheRTCNotificationID(eventID, for: roomID, isOwnEvent: eventProxy.isOwn)
                return
            }
        }
    }

    private func preferredRemoteCallID(for roomID: String) -> String? {
        if incomingCallID?.roomID == roomID {
            incomingCallID?.remoteCallID
        } else if ongoingCallID?.roomID == roomID {
            ongoingCallID?.remoteCallID
        } else if recentlyEndedCallID?.roomID == roomID {
            recentlyEndedCallID?.remoteCallID
        } else {
            cachedRemoteCallIDByRoomID[roomID]
        }
    }

    private func beginCallTermination(for roomID: String) -> Bool {
        callTerminationLock.lock()
        defer { callTerminationLock.unlock() }

        let now = Date()
        if let previousAttempt = lastCallTerminationAttemptByRoomID[roomID],
           now.timeIntervalSince(previousAttempt) < CallTerminationConstants.duplicateSuppression {
            return false
        }

        guard !inProgressCallTerminations.contains(roomID) else {
            return false
        }

        inProgressCallTerminations.insert(roomID)
        lastCallTerminationAttemptByRoomID[roomID] = now
        return true
    }

    private func finishCallTermination(for roomID: String) {
        callTerminationLock.lock()
        inProgressCallTerminations.remove(roomID)
        callTerminationLock.unlock()
    }

    private func ensureTimelineSubscribed(for roomProxy: JoinedRoomProxyProtocol, roomID _: String) async {
        await roomProxy.timeline.subscribeForUpdates()
    }

    private func preferredCallStartedAt(for roomID: String) -> Date? {
        if incomingCallID?.roomID == roomID {
            incomingCallID?.startedAt
        } else if ongoingCallID?.roomID == roomID {
            ongoingCallID?.startedAt
        } else if recentlyEndedCallID?.roomID == roomID {
            recentlyEndedCallID?.startedAt
        } else {
            nil
        }
    }

    private func matchesKnownCallContext(_ callEvent: RoomCallEvent, eventTimestamp: Date, roomID: String) -> Bool {
        if let preferredRemoteCallID = preferredRemoteCallID(for: roomID),
           let callEventID = callEvent.callID {
            return callEventID == preferredRemoteCallID
        }

        guard callEvent.callID == nil,
              let preferredCallStartedAt = preferredCallStartedAt(for: roomID) else { return true }

        let threshold = preferredCallStartedAt.addingTimeInterval(-5)
        return eventTimestamp >= threshold
    }

    private func refreshOngoingDeclineListeners(roomProxy: JoinedRoomProxyProtocol,
                                                ongoingCallID: CallID,
                                                itemProxies: [TimelineItemProxy]) {
        guard beginResolvingOngoingDeclines() else {
            return
        }
        defer { finishResolvingOngoingDeclines() }

        guard self.ongoingCallID?.callKitID == ongoingCallID.callKitID else {
            return
        }

        var rtcNotificationIDs: [String] = []
        func appendUnique(_ rtcNotificationID: String?) {
            guard let rtcNotificationID, !rtcNotificationIDs.contains(rtcNotificationID) else {
                return
            }
            rtcNotificationIDs.append(rtcNotificationID)
        }

        appendUnique(ongoingCallID.rtcNotificationID)
        appendUnique(cachedRTCNotificationIDByRoomID[ongoingCallID.roomID])

        for itemProxy in itemProxies.reversed() {
            guard case let .event(eventProxy) = itemProxy,
                  let eventID = eventProxy.id.eventID,
                  isDeclinableCallNotification(eventProxy) else {
                continue
            }

            appendUnique(eventID)
        }

        let unresolvedRTCNotificationIDs = unresolvedDeclineRTCNotificationIDs(from: rtcNotificationIDs)
        guard !unresolvedRTCNotificationIDs.isEmpty else {
            return
        }

        let listener: CallDeclineListener = SDKListener { [weak self] senderID in
            guard let self else { return }
            guard senderID != roomProxy.ownUserID else { return }
            guard self.ongoingCallID?.callKitID == ongoingCallID.callKitID else { return }
            let deduplicationID = "decline:\(ongoingCallID.roomID):\(senderID)"

            endOngoingCall(ongoingCallID, reason: .remoteEnded, deduplicationID: deduplicationID)
        }

        for rtcNotificationID in unresolvedRTCNotificationIDs {
            guard case let .success(handle) = roomProxy.subscribeToCallDeclineEvents(rtcNotificationEventID: rtcNotificationID,
                                                                                     listener: listener) else {
                MXLog.error("Unable to refresh decline listener for ongoing call notification \(rtcNotificationID).")
                continue
            }

            storeDeclineListenerHandle(handle, for: rtcNotificationID)
        }
    }
    
    private func reportEndedCall(incomingCallID: CallID, reason: CXCallEndedReason, deduplicationID: String? = nil) {
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-RECIPIENT-CLEAR] room_id=\(incomingCallID.roomID) " +
            "callkit_id=\(incomingCallID.callKitID) reason=\(reason) deduplication_id=\(deduplicationID ?? "nil")")
        suppressIncomingFallback(for: incomingCallID.roomID)
        applySessionEvent(type: sessionEventType(for: reason),
                          roomID: incomingCallID.roomID,
                          deduplicationID: deduplicationID)
        clearIncomingCallState()
        callProvider.reportCall(with: incomingCallID.callKitID, endedAt: nil, reason: reason)
    }

    private func clearIncomingCallState(cancelEmbeddedAnswer: Bool = true) {
        if cancelEmbeddedAnswer {
            cancelEmbeddedMatrixRTCAnswer(for: incomingCallID?.callKitID)
        }
        incomingCallTimelineCancellable = nil
        declineListenerHandle?.cancel()
        declineListenerHandle = nil
        endUnansweredCallTask?.cancel()
        endUnansweredCallTask = nil
        incomingCallID = nil
    }

    private func latestIncomingCallTerminationEvent(in itemProxies: [TimelineItemProxy], roomID: String) -> (eventID: String, reason: CXCallEndedReason)? {
        for itemProxy in itemProxies.reversed() {
            guard case let .event(eventProxy) = itemProxy,
                  let eventID = eventProxy.id.eventID,
                  let callEvent = RoomCallEventParser.parse(from: eventProxy),
                  matchesKnownCallContext(callEvent, eventTimestamp: eventProxy.timestamp, roomID: roomID) else {
                continue
            }

            if eventProxy.isOwn {
                switch callEvent.state {
                case .answered:
                    return (eventID, .answeredElsewhere)
                case .declined, .missed:
                    return (eventID, .declinedElsewhere)
                case .ended:
                    return (eventID, .remoteEnded)
                case .incoming, .outgoing, .started, .legacyInvite:
                    continue
                }
            } else {
                switch callEvent.state {
                case .ended:
                    return (eventID, .remoteEnded)
                case .declined, .missed:
                    return (eventID, .declinedElsewhere)
                case .incoming, .outgoing, .started, .answered, .legacyInvite:
                    continue
                }
            }
        }

        return nil
    }

    private func latestRemoteTerminationEvent(in itemProxies: [TimelineItemProxy], roomID: String) -> (eventID: String, reason: CXCallEndedReason)? {
        for itemProxy in itemProxies.reversed() {
            guard case let .event(eventProxy) = itemProxy,
                  let eventID = eventProxy.id.eventID,
                  let callEvent = RoomCallEventParser.parse(from: eventProxy) else {
                continue
            }

            guard !eventProxy.isOwn,
                  matchesKnownCallContext(callEvent, eventTimestamp: eventProxy.timestamp, roomID: roomID) else {
                continue
            }

            switch callEvent.state {
            case .ended:
                return (eventID, .remoteEnded)
            case .declined, .missed:
                return (eventID, .declinedElsewhere)
            case .incoming, .outgoing, .started, .answered, .legacyInvite:
                continue
            }
        }

        return nil
    }

    private func endOngoingCall(_ ongoingCallID: CallID, reason: CXCallEndedReason, deduplicationID: String? = nil) {
        guard self.ongoingCallID?.callKitID == ongoingCallID.callKitID else {
            return
        }

        #if DEBUG
        if reason == .remoteEnded {
            Task { @MainActor in
                SalemXStage2FSimulatorSignalingDebug.recordReceiverRemoteEndSeen(source: .embeddedRemoteEnd)
            }
        }
        #endif

        if handleEmbeddedMatrixRTCTerminalEventIfNeeded(ongoingCallID,
                                                        source: source(forEmbeddedTerminalReason: reason),
                                                        deduplicationID: deduplicationID) {
            return
        }

        suppressIncomingFallback(for: ongoingCallID.roomID)
        
        applySessionEvent(type: sessionEventType(for: reason),
                          roomID: ongoingCallID.roomID,
                          deduplicationID: deduplicationID)
        
        switch reason {
        case .remoteEnded:
            MXLog.info("Call ended remotely for room \(ongoingCallID.roomID)")
        case .declinedElsewhere:
            MXLog.info("Call declined by remote for room \(ongoingCallID.roomID)")
        case .failed:
            MXLog.error("Call failed for room \(ongoingCallID.roomID)")
        case .answeredElsewhere:
            MXLog.info("Call answered elsewhere for room \(ongoingCallID.roomID)")
        case .unanswered:
            MXLog.info("Call unanswered for room \(ongoingCallID.roomID)")
        @unknown default:
            MXLog.info("Call ended for room \(ongoingCallID.roomID)")
        }
        
        actionsSubject.send(.endCall(roomID: ongoingCallID.roomID))
        #if DEBUG
        Task { @MainActor in
            SalemXStage2FSimulatorSignalingDebug.recordCallUIDismissed()
        }
        #endif
        tearDownCallSession(sendEndCallAction: false)
    }

    private func source(forEmbeddedTerminalReason reason: CXCallEndedReason) -> SalemXEmbeddedCallEndSource {
        switch reason {
        case .failed:
            .presentationFailure
        case .unanswered:
            .answerTimeout
        case .remoteEnded, .declinedElsewhere, .answeredElsewhere:
            .embeddedRemoteEnd
        @unknown default:
            .embeddedRemoteEnd
        }
    }
}

// swiftlint:enable type_body_length

@MainActor
extension ElementCallService: EmbeddedElementCallTerminating {
    func terminateEmbeddedElementCall(roomID: String) async -> EmbeddedElementCallTerminationResult {
        await requestCallTermination(roomID: roomID)
        return .accepted
    }
}
