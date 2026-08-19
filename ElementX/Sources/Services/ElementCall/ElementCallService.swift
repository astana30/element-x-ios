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
    case blockedByConsumedCallIdentity
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
        case .blockedByConsumedCallIdentity:
            .idle
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
        case .blockedByConsumedCallIdentity:
            "blocked_consumed_call_identity"
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

/// Lets CallKit answer handoff wait for the app to be active instead of CallKit audio activation.
struct ApplicationActivityProvider {
    var isActive: () -> Bool
    var didBecomeActivePublisher: AnyPublisher<Void, Never>
    
    static var live: ApplicationActivityProvider {
        ApplicationActivityProvider(isActive: { UIApplication.shared.applicationState == .active },
                                    didBecomeActivePublisher: NotificationCenter.default
                                        .publisher(for: UIApplication.didBecomeActiveNotification)
                                        .map { _ in }
                                        .eraseToAnyPublisher())
    }
}

struct SessionGlobalIncomingCallEvent {
    let roomID: String
    let roomDisplayName: String?
    let isDirect: Bool
    let isOwnEvent: Bool
    let callEvent: RoomCallEvent
    let deduplicationID: String
}

private struct MatrixRTCCallScope: Hashable {
    static let directRoom = MatrixRTCCallScope(application: "m.call", callID: "ROOM", scope: "m.room")

    let application: String
    let callID: String
    let scope: String
}

private struct MatrixRTCCallMembershipIdentity: Hashable {
    let callScope: MatrixRTCCallScope
    let userID: String
    let deviceID: String
    let partyID: String
    let stateKey: String
    let membershipID: String?
}

private struct MatrixRTCCallMembership {
    let identity: MatrixRTCCallMembershipIdentity
    let expiresAtMilliseconds: UInt64?
}

private struct MatrixRTCCallMembershipStateKey: Hashable {
    let eventType: String
    let stateKey: String
}

private struct MatrixRTCCallMembershipStateUpdate {
    let eventID: String
    let roomID: String?
    let stateKey: MatrixRTCCallMembershipStateKey
    let timestampMilliseconds: UInt64
    let memberships: [MatrixRTCCallMembership]
}

private final class SalemXStockElementCallObservationState {
    let handle: SalemXStockElementCallObservationHandle
    let roomID: String
    let ownUserID: String
    let ownDeviceID: String
    let armedAtMilliseconds: UInt64
    var observation: (any MatrixRTCCallMembershipStateObservationProtocol)?
    var roomInfoCancellable: AnyCancellable?
    var baselineEstablished = false
    var baselineMemberships = Set<MatrixRTCCallMembershipIdentity>()
    var roomInfoBaselineEstablished = false
    var baselineLocalParticipantPresent = false
    var confirmedMembership: MatrixRTCCallMembershipIdentity?
    var observedConfirmedMembershipInTimeline = false
    var observedLocalParticipantAfterConfirmation = false
    var confirmationResult: Result<SalemXStockElementCallContext, SalemXStockElementCallLifecycleError>?
    var removalResult: Result<Void, SalemXStockElementCallLifecycleError>?
    var confirmationContinuations = [CheckedContinuation<Result<SalemXStockElementCallContext, SalemXStockElementCallLifecycleError>, Never>]()
    var removalContinuations = [CheckedContinuation<Result<Void, SalemXStockElementCallLifecycleError>, Never>]()

    init(handle: SalemXStockElementCallObservationHandle,
         roomID: String,
         ownUserID: String,
         ownDeviceID: String,
         armedAtMilliseconds: UInt64) {
        self.handle = handle
        self.roomID = roomID
        self.ownUserID = ownUserID
        self.ownDeviceID = ownDeviceID
        self.armedAtMilliseconds = armedAtMilliseconds
    }
}

/// Parses the exact call membership identity that the SDK's `RoomInfo` projection intentionally omits.
///
/// This uses the same raw SDK event surface as `RoomCallEventParser`; raw content is never logged or retained.
private enum MatrixRTCCallMembershipEventParser {
    private enum EventFamily {
        case session
        case rtc
    }

    private static let sessionEventTypes = Set([
        "org.matrix.msc3401.call.member",
        "m.call.member"
    ])
    private static let rtcEventTypes = Set([
        "org.matrix.msc4143.rtc.member",
        "m.rtc.member"
    ])
    private static let defaultExpiryMilliseconds: UInt64 = 14_400_000

    static func parse(_ itemProxy: TimelineItemProxy) -> MatrixRTCCallMembershipStateUpdate? {
        guard case let .event(eventProxy) = itemProxy,
              let eventID = eventProxy.id.eventID,
              let rawJSONString = eventProxy.debugInfo.originalJSON,
              let data = rawJSONString.data(using: .utf8),
              let rawEvent = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = nonEmptyString(rawEvent["type"]),
              let eventFamily = eventFamily(for: eventType),
              let sender = nonEmptyString(rawEvent["sender"]),
              let timestampMilliseconds = unsignedInteger(rawEvent["origin_server_ts"]),
              let content = rawEvent["content"] as? [String: Any] else {
            return nil
        }
        let roomID = nonEmptyString(rawEvent["room_id"])

        let rawStateKey = nonEmptyString(rawEvent["state_key"])
        let stickyKey = stickyKey(in: content)
        guard stickyKey.isValid,
              rawStateKey == nil || stickyKey.value == nil || rawStateKey == stickyKey.value,
              let stateKey = rawStateKey ?? stickyKey.value,
              timelineContentMatches(eventProxy.content,
                                     eventType: eventType,
                                     rawStateKey: rawStateKey) else {
            return nil
        }

        let membershipStateKey = MatrixRTCCallMembershipStateKey(eventType: eventType, stateKey: stateKey)
        if isRemovalContent(content, eventFamily: eventFamily) {
            return .init(eventID: eventID,
                         roomID: roomID,
                         stateKey: membershipStateKey,
                         timestampMilliseconds: timestampMilliseconds,
                         memberships: [])
        }
        if case .session = eventFamily,
           let legacyMemberships = content["memberships"] as? [Any],
           legacyMemberships.isEmpty {
            return .init(eventID: eventID,
                         roomID: roomID,
                         stateKey: membershipStateKey,
                         timestampMilliseconds: timestampMilliseconds,
                         memberships: [])
        }

        let memberships: [MatrixRTCCallMembership]
        switch eventFamily {
        case .session:
            memberships = parseSessionMemberships(content,
                                                  sender: sender,
                                                  stateKey: stateKey,
                                                  fallbackTimestampMilliseconds: timestampMilliseconds) ?? []
            guard !memberships.isEmpty else {
                return nil
            }
        case .rtc:
            guard let membership = parseRTCMembership(content,
                                                      sender: sender,
                                                      stateKey: stateKey,
                                                      fallbackTimestampMilliseconds: timestampMilliseconds) else {
                return nil
            }
            memberships = [membership]
        }

        return .init(eventID: eventID,
                     roomID: roomID,
                     stateKey: membershipStateKey,
                     timestampMilliseconds: timestampMilliseconds,
                     memberships: memberships)
    }

    private static func eventFamily(for eventType: String) -> EventFamily? {
        if sessionEventTypes.contains(eventType) {
            return .session
        }
        if rtcEventTypes.contains(eventType) {
            return .rtc
        }
        return nil
    }

    private static func parseSessionMemberships(_ content: [String: Any],
                                                sender: String,
                                                stateKey: String,
                                                fallbackTimestampMilliseconds: UInt64) -> [MatrixRTCCallMembership]? {
        if let legacyMemberships = content["memberships"] as? [[String: Any]] {
            guard !legacyMemberships.isEmpty else {
                return nil
            }

            let memberships = legacyMemberships.compactMap { membership in
                parseSessionMembership(membership,
                                       sender: sender,
                                       stateKey: stateKey,
                                       partyID: nonEmptyString(membership["membershipID"]),
                                       fallbackTimestampMilliseconds: fallbackTimestampMilliseconds,
                                       requiresMembershipID: true)
            }
            guard memberships.count == legacyMemberships.count else {
                return nil
            }
            return memberships
        }

        guard let membership = parseSessionMembership(content,
                                                      sender: sender,
                                                      stateKey: stateKey,
                                                      partyID: stateKey,
                                                      fallbackTimestampMilliseconds: fallbackTimestampMilliseconds,
                                                      requiresMembershipID: false) else {
            return nil
        }
        return [membership]
    }

    private static func timelineContentMatches(_ content: TimelineItemContent,
                                               eventType: String,
                                               rawStateKey: String?) -> Bool {
        switch content {
        case .state(let timelineStateKey, let content):
            guard timelineStateKey == rawStateKey,
                  case .custom(let timelineEventType) = content else {
                return false
            }
            return timelineEventType == eventType
        case .failedToParseState(let timelineEventType, let timelineStateKey, _):
            return timelineEventType == eventType && timelineStateKey == rawStateKey
        case .msgLike(let content):
            guard rawStateKey == nil,
                  case .other(let messageLikeEventType) = content.kind,
                  case .other(let timelineEventType) = messageLikeEventType else {
                return false
            }
            return timelineEventType == eventType
        case .failedToParseMessageLike(let timelineEventType, _):
            return rawStateKey == nil && timelineEventType == eventType
        default:
            return false
        }
    }

    private static func stickyKey(in content: [String: Any]) -> (value: String?, isValid: Bool) {
        let stableKey = nonEmptyString(content["sticky_key"])
        let unstableKey = nonEmptyString(content["msc4354_sticky_key"])
        guard stableKey == nil || unstableKey == nil || stableKey == unstableKey else {
            return (nil, false)
        }
        return (stableKey ?? unstableKey, true)
    }

    private static func isRemovalContent(_ content: [String: Any], eventFamily: EventFamily) -> Bool {
        guard !content.isEmpty else { return true }

        switch eventFamily {
        case .session:
            return Set(content.keys).isSubset(of: ["leave_reason"])
        case .rtc:
            return Set(content.keys).isSubset(of: ["leave_reason", "msc4354_sticky_key", "sticky_key"])
        }
    }

    private static func parseSessionMembership(_ content: [String: Any],
                                               sender: String,
                                               stateKey: String,
                                               partyID: String?,
                                               fallbackTimestampMilliseconds: UInt64,
                                               requiresMembershipID: Bool) -> MatrixRTCCallMembership? {
        guard content["application"] as? String == MatrixRTCCallScope.directRoom.application,
              let rawCallID = content["call_id"] as? String,
              rawCallID.isEmpty || rawCallID == MatrixRTCCallScope.directRoom.callID,
              content["scope"] as? String == MatrixRTCCallScope.directRoom.scope,
              let deviceID = nonEmptyString(content["device_id"]),
              let partyID else {
            return nil
        }

        let membershipID = nonEmptyString(content["membershipID"])
        guard !requiresMembershipID || membershipID != nil else {
            return nil
        }

        if !requiresMembershipID {
            guard let activeFocus = content["focus_active"] as? [String: Any],
                  nonEmptyString(activeFocus["type"]) != nil else {
                return nil
            }
            if let rawPreferredFoci = content["foci_preferred"] {
                guard let preferredFoci = rawPreferredFoci as? [Any],
                      preferredFoci.allSatisfy({ focus in
                          guard let focus = focus as? [String: Any] else { return false }
                          return nonEmptyString(focus["type"]) != nil
                      }) else {
                    return nil
                }
            }
        }

        if let createdTimestamp = content["created_ts"], unsignedInteger(createdTimestamp) == nil {
            return nil
        }
        if let expiry = content["expires"], unsignedInteger(expiry) == nil {
            return nil
        }

        let createdTimestamp = unsignedInteger(content["created_ts"]) ?? fallbackTimestampMilliseconds
        let expiryDuration = unsignedInteger(content["expires"]) ?? defaultExpiryMilliseconds
        let (expiresAtMilliseconds, overflow) = createdTimestamp.addingReportingOverflow(expiryDuration)
        guard !overflow else {
            return nil
        }

        return .init(identity: .init(callScope: .directRoom,
                                     userID: sender,
                                     deviceID: deviceID,
                                     partyID: partyID,
                                     stateKey: stateKey,
                                     membershipID: membershipID),
                     expiresAtMilliseconds: expiresAtMilliseconds)
    }

    private static func parseRTCMembership(_ content: [String: Any],
                                           sender: String,
                                           stateKey: String,
                                           fallbackTimestampMilliseconds: UInt64) -> MatrixRTCCallMembership? {
        guard let application = content["application"] as? [String: Any],
              application["type"] as? String == MatrixRTCCallScope.directRoom.application,
              content["slot_id"] as? String == "\(MatrixRTCCallScope.directRoom.application)#\(MatrixRTCCallScope.directRoom.callID)",
              let member = content["member"] as? [String: Any],
              let userID = nonEmptyString(member["user_id"]),
              userID == sender,
              let deviceID = nonEmptyString(member["device_id"]),
              let membershipID = nonEmptyString(member["id"]),
              let transports = content["rtc_transports"] as? [[String: Any]],
              transports.allSatisfy({ nonEmptyString($0["type"]) != nil }),
              let versions = content["versions"] as? [Any],
              versions.allSatisfy({ nonEmptyString($0) != nil }) else {
            return nil
        }

        let rawCreatedTimestamp = content["created_ts"]
        let rawExpiryDuration = content["expires"]
        guard rawCreatedTimestamp == nil || unsignedInteger(rawCreatedTimestamp) != nil,
              rawExpiryDuration == nil || unsignedInteger(rawExpiryDuration) != nil else {
            return nil
        }

        let expiresAtMilliseconds: UInt64?
        if let expiryDuration = unsignedInteger(rawExpiryDuration) {
            let createdTimestamp = unsignedInteger(rawCreatedTimestamp) ?? fallbackTimestampMilliseconds
            let (expiry, overflow) = createdTimestamp.addingReportingOverflow(expiryDuration)
            guard !overflow else { return nil }
            expiresAtMilliseconds = expiry
        } else {
            expiresAtMilliseconds = nil
        }

        return .init(identity: .init(callScope: .directRoom,
                                     userID: userID,
                                     deviceID: deviceID,
                                     partyID: membershipID,
                                     stateKey: stateKey,
                                     membershipID: membershipID),
                     expiresAtMilliseconds: expiresAtMilliseconds)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func unsignedInteger(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber,
              !(value is Bool),
              number.doubleValue.isFinite,
              number.doubleValue >= 0,
              number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue <= Double(UInt64.max) else {
            return nil
        }
        return number.uint64Value
    }
}

private struct DirectRoomInfoTerminationContext: Equatable {
    let callKitID: UUID
    let roomID: String
    let callScope: MatrixRTCCallScope
    let retainedProxyIdentity: ObjectIdentifier
    let subscriptionGeneration: UInt64
}

private final class DirectRoomInfoTerminationStateMachine {
    private struct MembershipState {
        let timestampMilliseconds: UInt64
        let memberships: [MatrixRTCCallMembership]
    }

    let context: DirectRoomInfoTerminationContext

    private let ownUserID: String
    private let ownDeviceID: String?
    private var membershipStateByStateKey = [MatrixRTCCallMembershipStateKey: MembershipState]()
    private var exactLocalMembership: MatrixRTCCallMembershipIdentity?
    private var observedRemoteMemberships = Set<MatrixRTCCallMembershipIdentity>()
    private var exactRemoteRoomInfoParticipants = Set<String>()
    private var latestRoomInfo: RoomInfoProxyProtocol?
    private var terminalEventEmitted = false

    private(set) var callbackSequence: UInt64 = 0
    private(set) var exactRemoteSeen = false
    private(set) var exactRemoteSeenSequence: UInt64?

    var exactRemoteMembershipIdentities: Set<MatrixRTCCallMembershipIdentity> {
        observedRemoteMemberships
    }

    init(context: DirectRoomInfoTerminationContext,
         ownUserID: String,
         ownDeviceID: String?) {
        self.context = context
        self.ownUserID = ownUserID
        self.ownDeviceID = ownDeviceID
    }

    func updateRoomInfo(_ roomInfo: RoomInfoProxyProtocol, now: Date) -> Bool {
        guard context.callScope == .directRoom,
              roomInfo.id == context.roomID,
              roomInfo.isDirect,
              callbackSequence < UInt64.max else {
            return false
        }

        callbackSequence += 1
        latestRoomInfo = roomInfo
        let activeMemberships = activeMemberships(now: now)
        guard !resolveExactLocalMembership(from: activeMemberships) else {
            return false
        }

        let activeMembershipIdentities = Set(activeMemberships.map(\.identity))
        let participants = Set(roomInfo.activeRoomCallParticipants)
        let exactForeignParticipants = Set(participants.filter { participant in
            !Self.participant(participant, belongsTo: ownUserID)
        })
        guard exactForeignParticipants.count <= 1 else {
            return false
        }

        if !exactRemoteSeen {
            let confirmedRemoteMemberships = confirmedRemoteMemberships(roomInfo: roomInfo,
                                                                        activeMemberships: activeMemberships,
                                                                        activeMembershipIdentities: activeMembershipIdentities)
            guard !exactForeignParticipants.isEmpty || !confirmedRemoteMemberships.isEmpty else {
                return false
            }

            exactRemoteRoomInfoParticipants = exactForeignParticipants
            observedRemoteMemberships = confirmedRemoteMemberships
            exactRemoteSeen = true
            exactRemoteSeenSequence = callbackSequence
            return false
        }

        guard let exactRemoteSeenSequence,
              callbackSequence > exactRemoteSeenSequence else {
            return false
        }

        let exactRoomInfoParticipantStillPresent = !exactRemoteRoomInfoParticipants.isDisjoint(with: participants)
        let exactRawMembershipStillProjected = observedRemoteMemberships.contains { membership in
            self.roomInfo(roomInfo, projects: membership, among: activeMembershipIdentities)
        }
        guard !roomInfo.hasRoomCall || (!exactRoomInfoParticipantStillPresent && !exactRawMembershipStillProjected) else {
            return false
        }

        guard !terminalEventEmitted else { return false }

        terminalEventEmitted = true
        return true
    }

    func updateAuthoritativeState(_ itemProxies: [TimelineItemProxy], now: Date) {
        var projectedStateByStateKey = [MatrixRTCCallMembershipStateKey: MembershipState]()
        var projectedEventIDs = Set<String>()

        for itemProxy in itemProxies {
            guard let update = MatrixRTCCallMembershipEventParser.parse(itemProxy),
                  projectedEventIDs.insert(update.eventID).inserted else {
                continue
            }

            if let currentState = projectedStateByStateKey[update.stateKey],
               currentState.timestampMilliseconds > update.timestampMilliseconds {
                continue
            }

            projectedStateByStateKey[update.stateKey] = .init(timestampMilliseconds: update.timestampMilliseconds,
                                                              memberships: update.memberships)
        }

        membershipStateByStateKey = projectedStateByStateKey
        guard !exactRemoteSeen,
              callbackSequence > 0,
              let latestRoomInfo,
              latestRoomInfo.id == context.roomID,
              latestRoomInfo.isDirect else {
            return
        }

        let activeMemberships = activeMemberships(now: now)
        guard !resolveExactLocalMembership(from: activeMemberships) else {
            return
        }

        let activeMembershipIdentities = Set(activeMemberships.map(\.identity))
        let confirmedRemoteMemberships = confirmedRemoteMemberships(roomInfo: latestRoomInfo,
                                                                    activeMemberships: activeMemberships,
                                                                    activeMembershipIdentities: activeMembershipIdentities)
        guard !confirmedRemoteMemberships.isEmpty else {
            return
        }

        observedRemoteMemberships = confirmedRemoteMemberships
        exactRemoteSeen = true
        exactRemoteSeenSequence = callbackSequence
    }

    private func activeMemberships(now: Date) -> [MatrixRTCCallMembership] {
        let nowMilliseconds = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        return membershipStateByStateKey.values
            .flatMap(\.memberships)
            .filter { membership in
                membership.expiresAtMilliseconds.map { $0 > nowMilliseconds } ?? true
            }
    }

    private func confirmedRemoteMemberships(roomInfo: RoomInfoProxyProtocol,
                                            activeMemberships: [MatrixRTCCallMembership],
                                            activeMembershipIdentities: Set<MatrixRTCCallMembershipIdentity>)
        -> Set<MatrixRTCCallMembershipIdentity> {
        Set(activeMemberships.lazy
            .map(\.identity)
            .filter { self.isRemote($0) }
            .filter { membership in
                self.roomInfo(roomInfo,
                              projects: membership,
                              among: activeMembershipIdentities)
            })
    }

    /// Returns `true` when the local identity is ambiguous and terminal evaluation must fail closed.
    private func resolveExactLocalMembership(from memberships: [MatrixRTCCallMembership]) -> Bool {
        guard let ownDeviceID else {
            return true
        }

        let candidates = Set(memberships.filter { membership in
            membership.identity.userID == ownUserID && membership.identity.deviceID == ownDeviceID
        }.map(\.identity))
        guard candidates.count <= 1 else {
            return true
        }

        guard let candidate = candidates.first else {
            return false
        }

        if let exactLocalMembership {
            return exactLocalMembership != candidate
        }

        exactLocalMembership = candidate
        return false
    }

    private func isRemote(_ membership: MatrixRTCCallMembershipIdentity) -> Bool {
        guard membership.callScope == .directRoom else {
            return false
        }

        if let exactLocalMembership {
            return membership != exactLocalMembership
        }

        guard let ownDeviceID else {
            return false
        }
        return membership.userID != ownUserID || membership.deviceID != ownDeviceID
    }

    private func roomInfo(_ roomInfo: RoomInfoProxyProtocol,
                          projects remoteMembership: MatrixRTCCallMembershipIdentity,
                          among activeMemberships: Set<MatrixRTCCallMembershipIdentity>) -> Bool {
        let projectedMembershipCount = roomInfo.activeRoomCallParticipants.filter { participant in
            Self.participant(participant, belongsTo: remoteMembership.userID)
        }.count
        let activeLocalMembershipCount = activeMemberships.filter { membership in
            membership.userID == remoteMembership.userID && !isRemote(membership)
        }.count
        return projectedMembershipCount > activeLocalMembershipCount
    }

    private static func participant(_ participant: String, belongsTo userID: String) -> Bool {
        participant == userID || participant.hasPrefix("_\(userID)_")
    }
}

// swiftlint:disable type_body_length
class ElementCallService: NSObject, ElementCallServiceProtocol, SalemXStockElementCallLifecycleProviding, PKPushRegistryDelegate, CXProviderDelegate {
    private struct ProductionDispatchReceiverInput {
        let dispatchID: UUID
        let receiverReference: String
    }

    private enum IncomingFallbackConstants {
        static let unansweredTimeout: Duration = .seconds(45)
        static let suppressionDuration: TimeInterval = 30
    }

    private enum ProductionDispatchObservationConstants {
        static let membershipConfirmationTimeout: Duration = .seconds(5)
        static let capabilityRetryDelay: Duration = .seconds(5)
    }

    private enum CallTerminationConstants {
        static let duplicateSuppression: TimeInterval = 1
    }

    private struct CallID: Equatable {
        let callKitID: UUID
        let roomID: String
        let rtcNotificationID: String?
        let remoteCallID: String?
        let startMode: ElementCallStartMode
        let startedAt: Date
    }

    private enum ConsumedDirectCallIdentityComponent: Hashable {
        case callKit(UUID)
        case rtcNotification(String)
        case remoteCall(String)
        case membership(MatrixRTCCallMembershipIdentity)
    }

    private struct ConsumedDirectCallIdentityKey: Hashable {
        let roomID: String
        let callScope: MatrixRTCCallScope
        let component: ConsumedDirectCallIdentityComponent
    }

    private struct OngoingCallObservationIdentity: Equatable {
        let callKitID: UUID
        let roomID: String
        let callScope: MatrixRTCCallScope

        init(callID: CallID) {
            callKitID = callID.callKitID
            roomID = callID.roomID
            callScope = .directRoom
        }
    }

    private final class OngoingCallObservation {
        let identity: OngoingCallObservationIdentity
        let roomProxy: JoinedRoomProxyProtocol
        let retainedProxyIdentity: ObjectIdentifier
        let subscriptionGeneration: UInt64
        let roomInfoStateMachine: DirectRoomInfoTerminationStateMachine

        init(identity: OngoingCallObservationIdentity,
             roomProxy: JoinedRoomProxyProtocol,
             ownDeviceID: String?,
             subscriptionGeneration: UInt64) {
            self.identity = identity
            self.roomProxy = roomProxy
            retainedProxyIdentity = ObjectIdentifier(roomProxy as AnyObject)
            self.subscriptionGeneration = subscriptionGeneration
            roomInfoStateMachine = .init(context: .init(callKitID: identity.callKitID,
                                                        roomID: identity.roomID,
                                                        callScope: identity.callScope,
                                                        retainedProxyIdentity: retainedProxyIdentity,
                                                        subscriptionGeneration: subscriptionGeneration),
                                         ownUserID: roomProxy.ownUserID,
                                         ownDeviceID: ownDeviceID)
        }
    }

    private final class TerminationEventTracker {
        var eventID: String?
    }

    private final class RoomCallPresenceTracker {
        var hasSeenActiveCall = false
        var hasSeenRemoteParticipant = false
    }

    private struct SessionGlobalIncomingCallCandidate {
        let callEvent: RoomCallEvent
        let deduplicationID: String
        let isOwnEvent: Bool
    }

    private struct SessionGlobalRoomSummaryCandidate {
        let roomSummary: RoomSummary
        let remoteCallID: String
        let identityKeys: Set<ConsumedDirectCallIdentityKey>
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

    @MainActor private var productionDispatchCapabilityConfiguration: SalemXProductionDispatchCapabilityConfiguration?
    @MainActor private var productionDispatchCapabilityTokenRevision: UInt64 = 0
    @MainActor private var registeredProductionDispatchCapability: (appSessionGeneration: String, tokenRevision: UInt64)?
    @MainActor private var productionDispatchCapabilityRegistrationInFlight: (appSessionGeneration: String, tokenRevision: UInt64)?
    @MainActor private var productionDispatchCapabilityRetryCount = 0
    @MainActor private var productionDispatchReceiverConsumptions = Set<UUID>()
    @MainActor private var productionDispatchObservations = [UUID: SalemXStockElementCallObservationState]()
    nonisolated(unsafe) private var productionDispatchObservedRoomIDs = Set<String>()
    
    private weak var clientProxy: ClientProxyProtocol? {
        didSet {
            // There's a race condition where a call starts when the app has been killed and the
            // observation set in `incomingCallID` occurs *before* the user session is restored.
            // So observe when the client proxy is set to fix this (the method guards for the call).
            Task { await observeIncomingCall() }
            clearOngoingCallObservation(matching: nil)
            clearOngoingCallObservationRequest(matching: nil)
            let expectedCallID = ongoingCallID
            Task { await observeOngoingCall(expectedCallID: expectedCallID) }
            observeSessionGlobalIncomingCalls()
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
    private var ongoingCallRawMembershipObservation: (any MatrixRTCCallMembershipStateObservationProtocol)?
    private var ongoingCallObservation: OngoingCallObservation?
    private var ongoingCallObservationRequestIdentity: OngoingCallObservationIdentity?
    private var ongoingCallSubscriptionGeneration: UInt64 = 0
    private var recentlyEndedCallID: CallID?
    private var cachedRTCNotificationIDByRoomID: [String: String] = [:]
    private var cachedRTCNotificationOwnershipByRoomID: [String: Bool] = [:]
    private var cachedRemoteCallIDByRoomID: [String: String] = [:]
    private var activeCallSession: CallSession?
    private var recentCallSessionByRoomID: [String: CallSession] = [:]
    private var callSessionSequence: UInt64 = 0
    private var isCallKitAudioSessionActive = false
    private var pendingLegacyAnswerCallID: CallID?
    private var keptAliveAudioCallKitID: UUID?
    private let applicationActivityProvider: ApplicationActivityProvider
    private var applicationBecameActiveCancellable: AnyCancellable?
    private var ongoingCallID: CallID? {
        didSet {
            ongoingCallRoomIDSubject.send(ongoingCallID?.roomID)
            let previousIdentity = oldValue.map(OngoingCallObservationIdentity.init)
            let currentIdentity = ongoingCallID.map(OngoingCallObservationIdentity.init)
            if previousIdentity != currentIdentity {
                clearOngoingCallObservation(matching: previousIdentity)
                clearOngoingCallObservationRequest(matching: previousIdentity)
            }

            let expectedCallID = ongoingCallID
            Task { await observeOngoingCall(expectedCallID: expectedCallID) }
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
    private var sessionGlobalIncomingCallCancellable: AnyCancellable?
    private var sessionGlobalPresenceCancellable: AnyCancellable?
    private var sessionGlobalIncomingCallObservationStartedAt: Date?
    private var sessionGlobalIncomingCallSubscriptionGeneration: UInt64 = 0
    private var observedSessionGlobalIncomingCallIdentityKeys = Set<ConsumedDirectCallIdentityKey>()
    private var observedSessionGlobalPresenceRoomIDs = Set<String>()
    private var incomingFallbackSuppressionByRoomID: [String: Date] = [:]
    private var consumedDirectCallIdentityKeys = Set<ConsumedDirectCallIdentityKey>()
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
         applicationActivityProvider: ApplicationActivityProvider = .live,
         salemXAnswerBridgeConfiguration: SalemXEmbeddedCallAnswerBridgeConfiguration = .init(),
         salemXIncomingCallBootstrapResolver: (any SalemXIncomingCallBootstrapResolving)? = nil,
         salemXAnswerBridge: (any SalemXEmbeddedCallAnswerBridging)? = nil,
         salemXEndBridge: (any SalemXEmbeddedCallEndBridging)? = nil) {
        pushRegistry = PKPushRegistry(queue: nil)
        
        self.appSettings = appSettings
        self.timeProvider = timeProvider ?? TimeProvider(clock: ContinuousClock(), now: Date.init)
        self.applicationActivityProvider = applicationActivityProvider
        self.salemXAnswerBridgeConfiguration = salemXAnswerBridgeConfiguration
        self.salemXIncomingCallBootstrapResolver = salemXIncomingCallBootstrapResolver
        self.salemXAnswerBridge = salemXAnswerBridge
        self.salemXEndBridge = salemXEndBridge
        
        if let callProvider {
            self.callProvider = callProvider
        } else {
            let configuration = CXProviderConfiguration()
            configuration.supportsVideo = false
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
        
        applicationBecameActiveCancellable = applicationActivityProvider.didBecomeActivePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.resumePendingLegacyAnswerIfApplicationIsActive()
            }
    }
    
    func setClientProxy(_ clientProxy: any ClientProxyProtocol) {
        if self.clientProxy !== clientProxy {
            self.clientProxy = clientProxy
        }
        Task { @MainActor in await registerVoIPPusherIfNeeded() }
    }

    @MainActor
    func configureProductionDispatchCapability(_ configuration: SalemXProductionDispatchCapabilityConfiguration?) {
        productionDispatchCapabilityConfiguration = configuration
        registeredProductionDispatchCapability = nil
        productionDispatchCapabilityRetryCount = 0
        if configuration == nil {
            productionDispatchReceiverConsumptions.removeAll()
        }

        guard configuration != nil else { return }
        Task { @MainActor in await registerVoIPPusherIfNeeded() }
    }

    @MainActor
    func beginOutgoingObservation(roomID: String,
                                  appSessionGeneration: String,
                                  attemptGeneration: UInt64) async
        -> Result<SalemXStockElementCallObservationHandle, SalemXStockElementCallLifecycleError> {
        guard !roomID.isEmpty,
              !appSessionGeneration.isEmpty,
              let clientProxy,
              let ownDeviceID = clientProxy.deviceID,
              case let .joined(roomProxy) = await clientProxy.roomForIdentifier(roomID),
              let stateObserver = roomProxy as? any MatrixRTCCallMembershipStateObserving else {
            return .failure(.unavailable)
        }

        let handle = SalemXStockElementCallObservationHandle(observationID: UUID(),
                                                             appSessionGeneration: appSessionGeneration,
                                                             attemptGeneration: attemptGeneration)
        let state = SalemXStockElementCallObservationState(handle: handle,
                                                           roomID: roomID,
                                                           ownUserID: clientProxy.userID,
                                                           ownDeviceID: ownDeviceID,
                                                           armedAtMilliseconds: UInt64(max(0, timeProvider.now().timeIntervalSince1970 * 1000)))
        productionDispatchObservations[handle.observationID] = state
        syncProductionDispatchObservedRoomIDs()

        let observation = await stateObserver.observeMatrixRTCCallMembershipState { [weak self] itemProxies in
            Task { @MainActor [weak self] in
                self?.reconcileProductionDispatchMembershipState(itemProxies, observationID: handle.observationID)
            }
        }

        guard let observation,
              productionDispatchObservations[handle.observationID] === state else {
            cancelProductionDispatchObservation(observationID: handle.observationID)
            return .failure(.unavailable)
        }
        state.observation = observation

        if !state.baselineEstablished {
            // The SDK observation is diff-driven and doesn't guarantee an initial callback.
            // The timestamp gate below still rejects memberships that predate this observation.
            state.baselineEstablished = true
            state.baselineMemberships = []
        }

        // RoomInfo still updates when the event cache rejects membership timeline diffs.
        roomProxy.subscribeToRoomInfoUpdates()
        reconcileProductionDispatchRoomInfo(roomProxy.infoPublisher.value, observationID: handle.observationID)
        state.roomInfoCancellable = roomProxy.infoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomInfo in
                self?.reconcileProductionDispatchRoomInfo(roomInfo, observationID: handle.observationID)
            }

        return .success(handle)
    }

    @MainActor
    func awaitMembershipConfirmation(_ handle: SalemXStockElementCallObservationHandle) async
        -> Result<SalemXStockElementCallContext, SalemXStockElementCallLifecycleError> {
        await withTaskCancellationHandler {
            await waitForProductionDispatchConfirmation(handle)
        } onCancel: {
            Task { @MainActor in
                self.cancelObservation(handle)
            }
        }
    }

    @MainActor
    func confirmOutgoingCallMembershipAfterCallScreenPresentation(_ handle: SalemXStockElementCallObservationHandle) {
        confirmProductionDispatchMembership(handle, source: "call screen presentation")
    }

    @MainActor
    func awaitMembershipRemoval(_ handle: SalemXStockElementCallObservationHandle) async
        -> Result<Void, SalemXStockElementCallLifecycleError> {
        await withTaskCancellationHandler {
            await waitForProductionDispatchRemoval(handle)
        } onCancel: {
            Task { @MainActor in
                self.cancelObservation(handle)
            }
        }
    }

    @MainActor
    func cancelObservation(_ handle: SalemXStockElementCallObservationHandle) {
        guard productionDispatchObservation(matching: handle) != nil else { return }
        cancelProductionDispatchObservation(observationID: handle.observationID)
    }

    @MainActor
    private func waitForProductionDispatchConfirmation(_ handle: SalemXStockElementCallObservationHandle) async
        -> Result<SalemXStockElementCallContext, SalemXStockElementCallLifecycleError> {
        if Task.isCancelled {
            cancelObservation(handle)
            return .failure(.cancelled)
        }
        guard let state = productionDispatchObservation(matching: handle) else {
            return .failure(.invalidHandle)
        }
        if let result = state.confirmationResult {
            return result
        }

        return await withCheckedContinuation { continuation in
            if Task.isCancelled {
                continuation.resume(returning: .failure(.cancelled))
                self.cancelObservation(handle)
                return
            }
            guard let state = self.productionDispatchObservation(matching: handle) else {
                continuation.resume(returning: .failure(.invalidHandle))
                return
            }
            if let result = state.confirmationResult {
                continuation.resume(returning: result)
                return
            }
            state.confirmationContinuations.append(continuation)
            self.scheduleProductionDispatchMembershipConfirmationTimeout(handle)
            if Task.isCancelled {
                self.cancelObservation(handle)
            }
        }
    }

    @MainActor
    private func scheduleProductionDispatchMembershipConfirmationTimeout(_ handle: SalemXStockElementCallObservationHandle) {
        Task { [weak self] in
            try? await self?.timeProvider.clock.sleep(for: ProductionDispatchObservationConstants.membershipConfirmationTimeout)
            await MainActor.run {
                self?.confirmProductionDispatchMembershipIfTimedOut(handle)
            }
        }
    }

    @MainActor
    private func confirmProductionDispatchMembershipIfTimedOut(_ handle: SalemXStockElementCallObservationHandle) {
        confirmProductionDispatchMembership(handle, source: "observation timeout")
    }

    @MainActor
    private func confirmProductionDispatchMembership(_ handle: SalemXStockElementCallObservationHandle, source: String) {
        guard let state = productionDispatchObservation(matching: handle),
              state.confirmationResult == nil else {
            return
        }

        let identity = Self.productionDispatchRoomInfoMembershipIdentity(ownUserID: state.ownUserID,
                                                                         ownDeviceID: state.ownDeviceID)
        state.confirmedMembership = identity
        let context = SalemXStockElementCallContext(callID: identity.callScope.callID,
                                                    roomID: state.roomID,
                                                    callHandle: SalemXProductionDispatchOpaqueToken.callHandle())
        MXLog.info("Production dispatch confirming local MatrixRTC membership after \(source).")
        finishProductionDispatchConfirmation(state, result: .success(context))
    }

    @MainActor
    private func waitForProductionDispatchRemoval(_ handle: SalemXStockElementCallObservationHandle) async
        -> Result<Void, SalemXStockElementCallLifecycleError> {
        if Task.isCancelled {
            cancelObservation(handle)
            return .failure(.cancelled)
        }
        guard let state = productionDispatchObservation(matching: handle) else {
            return .failure(.invalidHandle)
        }
        if let result = state.removalResult {
            return result
        }

        return await withCheckedContinuation { continuation in
            if Task.isCancelled {
                continuation.resume(returning: .failure(.cancelled))
                self.cancelObservation(handle)
                return
            }
            guard let state = self.productionDispatchObservation(matching: handle) else {
                continuation.resume(returning: .failure(.invalidHandle))
                return
            }
            if let result = state.removalResult {
                continuation.resume(returning: result)
                return
            }
            state.removalContinuations.append(continuation)
            if Task.isCancelled {
                self.cancelObservation(handle)
            }
        }
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

    func handleSessionGlobalIncomingCallEvent(_ event: SessionGlobalIncomingCallEvent) {
        handleSessionGlobalIncomingCallCandidate(roomID: event.roomID,
                                                 roomDisplayName: event.roomDisplayName,
                                                 isDirect: event.isDirect,
                                                 candidate: .init(callEvent: event.callEvent,
                                                                  deduplicationID: event.deduplicationID,
                                                                  isOwnEvent: event.isOwnEvent))
    }
    
    func setupCallSession(roomID: String, roomDisplayName: String) async {
        await setupCallSession(roomID: roomID, roomDisplayName: roomDisplayName, startMode: .audio)
    }

    func setupCallSession(roomID: String, roomDisplayName: String, startMode: ElementCallStartMode) async {
        if ongoingCallID?.roomID == roomID {
            return
        }

        if let incomingCallID, incomingCallID.roomID == roomID,
           let activeCallSession, activeCallSession.roomID == roomID,
           activeCallSession.callKitID == incomingCallID.callKitID {
            adoptIncomingCallKitSession(incomingCallID)
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

    private func adoptIncomingCallKitSession(_ callID: CallID) {
        incomingCallID = nil
        ongoingCallID = callID
        recentlyEndedCallID = nil
        if let rtcNotificationID = callID.rtcNotificationID {
            cacheRTCNotificationID(rtcNotificationID, for: callID.roomID)
        }
        if let remoteCallID = callID.remoteCallID {
            cacheRemoteCallID(remoteCallID, for: callID.roomID)
        }
        if let activeCallSession, !activeCallSession.state.isTerminal,
           activeCallSession.state != .accepted, activeCallSession.state != .connected {
            applySessionEvent(type: .accept, roomID: callID.roomID)
        }
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
        let shouldEndCallKit = ongoingCallID?.startMode == .audio && activeCallSession?.direction == .incoming
        tearDownCallSession(sendEndCallAction: shouldEndCallKit, callKitEndReason: .remoteEnded)
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
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            await registerVoIPPusherIfNeeded()
        }
    }
    
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        if appSettings.salemxProductionDispatchV1Enabled {
            guard let input = Self.productionDispatchReceiverInput(from: payload.dictionaryPayload) else {
                completion()
                return
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    completion()
                    return
                }
                await self.consumeProductionDispatchReceiverInput(input, completion: completion)
            }
            return
        }
        #if DEBUG
        if SalemXPushKitRegistrationSmokeDebugBridge.handleElementCallServicePushKitReceipt(payload.dictionaryPayload, completion: completion) {
            return
        }
        #endif
        handleIncomingPushPayload(payload.dictionaryPayload, completion: completion)
    }

    private func handleIncomingPushPayload(_ payload: [AnyHashable: Any],
                                           requiresRTCNotificationID: Bool = true,
                                           completion: @escaping () -> Void) {
        guard let roomID = payload[ElementCallServiceNotificationKey.roomID.rawValue] as? String else {
            MXLog.error("Incoming VoIP call is missing its room binding.")
            completion()
            return
        }

        let rtcNotificationID = payload[ElementCallServiceNotificationKey.rtcNotifyEventID.rawValue] as? String
        guard !requiresRTCNotificationID || rtcNotificationID != nil else {
            MXLog.error("Incoming VoIP call is missing its notification binding.")
            completion()
            return
        }

        guard !isConsumedDirectCallIdentity(roomID: roomID, rtcNotificationID: rtcNotificationID) else {
            completion()
            return
        }
        
        guard ongoingCallID == nil, incomingCallID == nil else {
            MXLog.warning("A call is already active, ignoring incoming push for room \(roomID)")
            completion()
            return
        }
        
        guard let expirationDate = (payload[ElementCallServiceNotificationKey.expirationDate.rawValue] as? Date) else {
            MXLog.error("Incoming VoIP call is missing its expiration.")
            completion()
            return
        }
        
        let nowDate = timeProvider.now()
        
        guard nowDate < expirationDate else {
            MXLog.warning("Call expired for room \(roomID), ignoring incoming push")
            completion()
            return
        }

        let incomingStartMode = incomingStartMode(for: payload, roomID: roomID)
        let intentTrace = callIntentTrace(from: payload)
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-PUSH] room_id=\(roomID) payload_fields=\(Self.callTracePayloadSummary(payload)) " +
            "parsed_intent_key=\(intentTrace.key ?? "nil") parsed_intent_value=\(intentTrace.value ?? "nil") " +
            "parsed_intent_start_mode=\(Self.callTraceStartMode(intentTrace.parsedStartMode)) incoming_start_mode=\(incomingStartMode)")
        cachedRemoteCallIDByRoomID.removeValue(forKey: roomID)
        
        let callID = CallID(callKitID: UUID(),
                            roomID: roomID,
                            rtcNotificationID: rtcNotificationID,
                            remoteCallID: nil,
                            startMode: incomingStartMode,
                            startedAt: nowDate)
        isCallKitAudioSessionActive = false
        pendingLegacyAnswerCallID = nil
        incomingCallID = callID
        if let rtcNotificationID {
            cacheRTCNotificationID(rtcNotificationID, for: roomID, isOwnEvent: false)
        }
        openCallSession(roomID: roomID,
                        callKitID: callID.callKitID,
                        direction: .incoming,
                        remoteCallID: callID.remoteCallID)
        
        let ringDuration: Duration = .seconds(min(expirationDate.timeIntervalSince1970 - nowDate.timeIntervalSince1970, 90))
        
        let roomDisplayName = payload[ElementCallServiceNotificationKey.roomDisplayName.rawValue] as? String
        
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

    private static func productionDispatchReceiverInput(from payload: [AnyHashable: Any]) -> ProductionDispatchReceiverInput? {
        guard let rawEnvelope = payload[SalemXProductionDispatchNotificationKey.envelope.rawValue] as? NSDictionary,
              let protocolNumber = rawEnvelope[SalemXProductionDispatchNotificationKey.protocolVersion.rawValue] as? NSNumber,
              CFGetTypeID(protocolNumber) != CFBooleanGetTypeID(),
              let protocolVersion = Int(exactly: protocolNumber),
              protocolVersion == SalemXProductionDispatchProtocolVersion.v1.rawValue,
              let dispatchIDString = rawEnvelope[SalemXProductionDispatchNotificationKey.dispatchID.rawValue] as? String,
              let dispatchID = UUID(uuidString: dispatchIDString),
              let receiverReference = rawEnvelope[SalemXProductionDispatchNotificationKey.receiverReference.rawValue] as? String,
              !receiverReference.isEmpty,
              receiverReference.count <= 512 else {
            return nil
        }
        return .init(dispatchID: dispatchID, receiverReference: receiverReference)
    }

    @MainActor
    private func consumeProductionDispatchReceiverInput(_ input: ProductionDispatchReceiverInput,
                                                        completion: @escaping () -> Void) async {
        guard productionDispatchReceiverConsumptions.insert(input.dispatchID).inserted,
              let configuration = productionDispatchCapabilityConfiguration,
              !configuration.appSessionGeneration.isEmpty else {
            completion()
            return
        }

        let request = SalemXProductionDispatchReceiverConsumeRequest(dispatchID: input.dispatchID,
                                                                     receiverReference: input.receiverReference,
                                                                     appSessionGeneration: configuration.appSessionGeneration)
        let result = await configuration.client.consume(request)
        guard !Task.isCancelled,
              productionDispatchCapabilityConfiguration?.appSessionGeneration == configuration.appSessionGeneration,
              case .success(let response) = result,
              response.direction == "incoming",
              response.intent == .audio,
              response.expiresAtMS > Int64(timeProvider.now().timeIntervalSince1970 * 1000) else {
            completion()
            return
        }

        handleIncomingPushPayload([
            ElementCallServiceNotificationKey.roomID.rawValue: response.roomID,
            ElementCallServiceNotificationKey.roomDisplayName.rawValue: "SalemX audio call",
            ElementCallServiceNotificationKey.callIntent.rawValue: "audio",
            ElementCallServiceNotificationKey.expirationDate.rawValue: Date(timeIntervalSince1970: TimeInterval(response.expiresAtMS) / 1000)
        ], requiresRTCNotificationID: false, completion: completion)
    }
    
    // MARK: - CXProviderDelegate
    
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MXLog.info("Call provider did activate audio session")
        handleCallProviderAudioSessionActivation()
    }
    
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MXLog.info("Call provider did deactivate audio session")
        isCallKitAudioSessionActive = false
    }

    func handleCallProviderAudioSessionActivation() {
        isCallKitAudioSessionActive = true
        if keptAliveAudioCallKitID != nil
            || incomingCallID?.startMode == .audio
            || ongoingCallID?.startMode == .audio
            || pendingLegacyAnswerCallID?.startMode == .audio {
            // Log-only: WKWebView WebRTC owns the audio session.
            CallVoiceAudioSession.prepareEarpieceCategoryIfNeeded()
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-EARPIECE] reason=callkit_activated")
        }
        resumePendingLegacyAnswerIfApplicationIsActive()
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
            action.fail()
            return
        }

        guard incomingCallID.callKitID == action.callUUID else {
            action.fail()
            return
        }
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-ANSWER] room_id=\(incomingCallID.roomID) callkit_id=\(incomingCallID.callKitID) start_mode=\(incomingCallID.startMode)")
        
        guard applySessionEvent(type: .accept, roomID: incomingCallID.roomID) else {
            action.fulfill()
            return
        }
        
        // Fixes broken videos on EC web when a CallKit session is established.
        //
        // Reporting an ongoing call through `reportNewIncomingCall` + `CXAnswerCallAction`
        // or `reportOutgoingCall:connectedAt:` will give exclusive access for media to the
        // ongoing process, which is different than the WKWebKit is running on, making EC
        // unable to aquire media streams.
        // Reporting a video call as ended after answering it works around that as EC
        // gets access to media again and EX builds the right UI in `setupCallSession`.
        // Audio calls retain their CallKit session until the real call terminates.
        //
        // https://developer.apple.com/forums//thread/767949?answerId=812951022#812951022
        //
        // https://github.com/element-hq/element-x-ios/issues/3041
        // https://forums.developer.apple.com/forums/thread/685268
        // https://stackoverflow.com/questions/71483732/webrtc-running-from-wkwebview-avaudiosession-development-roadblock
        
        pendingLegacyAnswerCallID = incomingCallID
        if incomingCallID.startMode == .audio {
            keptAliveAudioCallKitID = incomingCallID.callKitID
            // Log-only: WKWebView WebRTC owns the audio session.
            CallVoiceAudioSession.prepareEarpieceCategoryIfNeeded()
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-AUDIO-EARPIECE] reason=answer")
        }
        action.fulfill()
        resumePendingLegacyAnswerIfApplicationIsActive(provider: provider)
    }

    private func resumePendingLegacyAnswerIfApplicationIsActive(provider: (any CXProviderProtocol)? = nil) {
        Task { @MainActor [weak self] in
            guard let self, pendingLegacyAnswerCallID != nil else {
                return
            }

            guard applicationActivityProvider.isActive() else {
                MXLog.info("Delaying answered call presentation until the application becomes active")
                IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-ANSWER-WAIT-ACTIVE]")
                return
            }

            MXLog.info("Resuming answered call because the application is active")
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-ANSWER-RESUME] reason=application_active")
            resumePendingLegacyAnswerPresentation(provider: provider)
        }
    }

    private func resumePendingLegacyAnswerPresentation(provider: (any CXProviderProtocol)? = nil) {
        guard let pendingLegacyAnswerCallID else {
            return
        }

        self.pendingLegacyAnswerCallID = nil
        Task { @MainActor in
            guard self.incomingCallID?.callKitID == pendingLegacyAnswerCallID.callKitID else {
                return
            }

            let isIncomingCallAlive = await self.isIncomingCallStillAliveBeforeAnswer(pendingLegacyAnswerCallID)
            guard self.incomingCallID?.callKitID == pendingLegacyAnswerCallID.callKitID else {
                return
            }

            guard isIncomingCallAlive else {
                self.reportEndedCall(incomingCallID: pendingLegacyAnswerCallID,
                                     reason: .remoteEnded,
                                     deduplicationID: "stale-answer:\(pendingLegacyAnswerCallID.callKitID.uuidString)")
                return
            }

            if pendingLegacyAnswerCallID.startMode == .video {
                (provider ?? self.callProvider).reportCall(with: pendingLegacyAnswerCallID.callKitID, endedAt: nil, reason: .remoteEnded)
            }

            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-START-CALL-SEND] room_id=\(pendingLegacyAnswerCallID.roomID) start_mode=\(pendingLegacyAnswerCallID.startMode)")
            self.actionsSubject.send(.startCall(roomID: pendingLegacyAnswerCallID.roomID, startMode: pendingLegacyAnswerCallID.startMode))
            self.endUnansweredCallTask?.cancel()
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

        if let incomingCallID {
            markConsumedDirectCallIdentity(incomingCallID)
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
        markConsumedDirectCallIdentity(knownCallID)
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
        reportCallKitEndedIfNeeded(uuid: callID.callKitID, reason: reason)
    }

    private func reportCallKitEndedIfNeeded(uuid: UUID, reason: CXCallEndedReason) {
        if keptAliveAudioCallKitID == uuid {
            keptAliveAudioCallKitID = nil
        }
        salemXEmbeddedTerminatedCallIDs.insert(uuid)
        let inserted = salemXEmbeddedReportedEndedCallIDs.insert(uuid).inserted
        #if DEBUG
        Task { @MainActor in
            SalemXStage2FSimulatorSignalingDebug.recordReceiverCallKitEndReport(inserted: inserted)
        }
        #endif
        guard inserted else {
            return
        }

        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-CALLKIT-END] callkit_id=\(uuid) reason=\(reason)")
        MXLog.info("Reported CallKit ended after the call terminated")
        callProvider.reportCall(with: uuid, endedAt: nil, reason: reason)
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
        handleEndCallAction(action, provider: provider)
    }

    func handleEndCallAction(_ action: any SalemXCallKitEndActionCompleting, provider _: any CXProviderProtocol) {
        if salemXEmbeddedTerminatedCallIDs.contains(action.callUUID) {
            action.fulfill()
            return
        }

        guard let knownCallID = embeddedCallID(for: action.callUUID) else {
            action.fail()
            return
        }

        guard salemXAnswerBridgeConfiguration.embeddedMatrixRTCAnswerBridgeEnabled else {
            handleLegacyEndCallAction(action, knownCallID: knownCallID)
            return
        }

        if activeCallSession?.callKitID == knownCallID.callKitID,
           activeCallSession?.direction == .outgoing {
            handleLegacyEndCallAction(action, knownCallID: knownCallID)
            return
        }

        handleEmbeddedMatrixRTCEndCallAction(action, source: .callKitLocalEnd)
    }

    private func handleLegacyEndCallAction(_ action: any SalemXCallKitEndActionCompleting, knownCallID: CallID) {
        salemXEmbeddedTerminatedCallIDs.insert(knownCallID.callKitID)
        salemXEmbeddedReportedEndedCallIDs.insert(knownCallID.callKitID)
        if keptAliveAudioCallKitID == knownCallID.callKitID {
            keptAliveAudioCallKitID = nil
        }
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-ENDCALL-ENTRY] " +
            "ongoing_room_id=\(ongoingCallID?.roomID ?? "nil") " +
            "ongoing_callkit_id=\(ongoingCallID?.callKitID.uuidString ?? "nil") " +
            "active_room_id=\(activeCallSession?.roomID ?? "nil") " +
            "active_state=\(activeCallSession?.state.rawValue ?? "nil")")
        if let ongoingCallID, ongoingCallID.callKitID == knownCallID.callKitID {
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
        
        if let incomingCallID, incomingCallID.callKitID == knownCallID.callKitID {
            applySessionEvent(type: .reject, roomID: incomingCallID.roomID)
            suppressIncomingFallback(for: incomingCallID.roomID)
            markConsumedDirectCallIdentity(incomingCallID)
            clearIncomingCallState()
            Task {
                _ = await sendDeclineCallEventWithRetry(in: incomingCallID.roomID,
                                                        preferredRTCNotificationID: incomingCallID.rtcNotificationID)
            }
        }

        action.fulfill()
    }
    
    // MARK: - Private
    
    private func tearDownCallSession(sendEndCallAction: Bool = true,
                                     callKitEndReason: CXCallEndedReason = .remoteEnded) {
        let terminatingCallID = ongoingCallID
        let callKitUUIDToEnd: UUID?
        if let keptAliveAudioCallKitID {
            callKitUUIDToEnd = keptAliveAudioCallKitID
        } else if terminatingCallID?.startMode == .audio {
            callKitUUIDToEnd = terminatingCallID?.callKitID
        } else {
            callKitUUIDToEnd = nil
        }

        #if !targetEnvironment(simulator)
        if sendEndCallAction, let terminatingCallID {
            let transaction = CXTransaction(action: CXEndCallAction(call: terminatingCallID.callKitID))
            callController.request(transaction) { error in
                if let error {
                    MXLog.error("Failed transaction with error: \(error)")
                }
            }
        }
        #endif
        
        if let terminatingCallID {
            markConsumedDirectCallIdentity(terminatingCallID)
            suppressIncomingFallback(for: terminatingCallID.roomID)
            recentlyEndedCallID = terminatingCallID
            if let rtcNotificationID = terminatingCallID.rtcNotificationID {
                cacheRTCNotificationID(rtcNotificationID, for: terminatingCallID.roomID)
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

        if let callKitUUIDToEnd {
            reportCallKitEndedIfNeeded(uuid: callKitUUIDToEnd, reason: callKitEndReason)
        }
    }
    
    @MainActor
    private func registerVoIPPusherIfNeeded() async {
        guard let voIPPushToken, let clientProxy else {
            return
        }
        
        guard registeredVoIPPushToken != voIPPushToken else {
            await registerProductionDispatchCapabilityIfNeeded(token: voIPPushToken,
                                                               tokenRevision: productionDispatchCapabilityTokenRevision)
            return
        }

        registeredVoIPPushToken = voIPPushToken
        productionDispatchCapabilityTokenRevision &+= 1
        registeredProductionDispatchCapability = nil
        productionDispatchCapabilityRetryCount = 0
        let tokenRevision = productionDispatchCapabilityTokenRevision
        
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
            guard self.voIPPushToken == voIPPushToken,
                  registeredVoIPPushToken == voIPPushToken else {
                return
            }
            await registerProductionDispatchCapabilityIfNeeded(token: voIPPushToken,
                                                               tokenRevision: tokenRevision)
        } catch {
            if registeredVoIPPushToken == voIPPushToken {
                registeredVoIPPushToken = nil
            }
            MXLog.error("Set VoIP pusher failed: \(error)")
        }
    }

    @MainActor
    private func registerProductionDispatchCapabilityIfNeeded(token voIPPushToken: Data, tokenRevision: UInt64) async {
        guard let configuration = productionDispatchCapabilityConfiguration,
              !configuration.appSessionGeneration.isEmpty,
              productionDispatchCapabilityTokenRevision == tokenRevision,
              self.voIPPushToken == voIPPushToken,
              registeredVoIPPushToken == voIPPushToken else {
            return
        }

        let registrationIdentity = (configuration.appSessionGeneration, tokenRevision)
        guard registeredProductionDispatchCapability?.appSessionGeneration != registrationIdentity.0 ||
            registeredProductionDispatchCapability?.tokenRevision != registrationIdentity.1 else {
            return
        }
        guard productionDispatchCapabilityRegistrationInFlight?.appSessionGeneration != registrationIdentity.0 ||
            productionDispatchCapabilityRegistrationInFlight?.tokenRevision != registrationIdentity.1 else {
            return
        }
        productionDispatchCapabilityRegistrationInFlight = registrationIdentity
        defer {
            if productionDispatchCapabilityRegistrationInFlight?.appSessionGeneration == registrationIdentity.0,
               productionDispatchCapabilityRegistrationInFlight?.tokenRevision == registrationIdentity.1 {
                productionDispatchCapabilityRegistrationInFlight = nil
            }
        }

        #if DEBUG
        let environment = SalemXProductionDispatchEnvironment.development
        #else
        let environment = SalemXProductionDispatchEnvironment.production
        #endif
        let request = SalemXProductionDispatchCapabilityRegistrationRequest(token: voIPPushToken.base64EncodedString(),
                                                                            environment: environment,
                                                                            appSessionGeneration: configuration.appSessionGeneration,
                                                                            capabilityExpiresInSeconds: configuration.capabilityExpiresInSeconds)
        let result = await configuration.client.registerCapability(request)
        guard productionDispatchCapabilityConfiguration?.appSessionGeneration == registrationIdentity.0,
              productionDispatchCapabilityTokenRevision == registrationIdentity.1,
              registeredVoIPPushToken == voIPPushToken else {
            return
        }

        switch result {
        case .success:
            registeredProductionDispatchCapability = registrationIdentity
            productionDispatchCapabilityRetryCount = 0
            MXLog.info("Production direct-call capability registration succeeded.")
        case .failure(let error):
            MXLog.error("Production direct-call capability registration failed: \(error)")
            guard productionDispatchCapabilityRetryCount < 2 else {
                return
            }
            productionDispatchCapabilityRetryCount += 1
            Task { [weak self] in
                try? await self?.timeProvider.clock.sleep(for: ProductionDispatchObservationConstants.capabilityRetryDelay)
                await self?.registerProductionDispatchCapabilityIfNeeded(token: voIPPushToken,
                                                                         tokenRevision: tokenRevision)
            }
        }
    }

    @MainActor
    private func reconcileProductionDispatchMembershipState(_ itemProxies: [TimelineItemProxy], observationID: UUID) {
        guard let state = productionDispatchObservations[observationID] else { return }

        var currentMemberships = [MatrixRTCCallMembershipIdentity: UInt64]()
        let nowMilliseconds = UInt64(max(0, timeProvider.now().timeIntervalSince1970 * 1000))
        for itemProxy in itemProxies {
            guard let update = MatrixRTCCallMembershipEventParser.parse(itemProxy),
                  update.roomID == state.roomID else {
                continue
            }

            for membership in update.memberships {
                let isUnexpired = membership.expiresAtMilliseconds.map { $0 > nowMilliseconds } ?? true
                guard membership.identity.userID == state.ownUserID,
                      membership.identity.deviceID == state.ownDeviceID,
                      membership.identity.callScope == MatrixRTCCallScope.directRoom,
                      isUnexpired else {
                    continue
                }
                currentMemberships[membership.identity] = max(currentMemberships[membership.identity] ?? 0,
                                                              update.timestampMilliseconds)
            }
        }

        if !state.baselineEstablished {
            state.baselineEstablished = true
            state.baselineMemberships = Set(currentMemberships.keys)
            return
        }

        if state.confirmedMembership == nil, state.confirmationResult == nil {
            let candidates = currentMemberships.filter { identity, timestamp in
                !state.baselineMemberships.contains(identity) &&
                    Self.isProductionDispatchMembershipFresh(timestamp, armedAtMilliseconds: state.armedAtMilliseconds)
            }
            if candidates.count == 1, let candidate = candidates.first {
                state.confirmedMembership = candidate.key
                state.observedConfirmedMembershipInTimeline = true
                let context = SalemXStockElementCallContext(callID: candidate.key.callScope.callID,
                                                            roomID: state.roomID,
                                                            callHandle: SalemXProductionDispatchOpaqueToken.callHandle())
                MXLog.info("Production dispatch observed a fresh local MatrixRTC membership.")
                finishProductionDispatchConfirmation(state, result: .success(context))
            } else if candidates.count > 1 {
                MXLog.error("Production dispatch observed ambiguous local MatrixRTC memberships.")
                finishProductionDispatchConfirmation(state, result: .failure(.ambiguousMembership))
            }
        }

        if let confirmedMembership = state.confirmedMembership {
            if currentMemberships[confirmedMembership] != nil {
                state.observedConfirmedMembershipInTimeline = true
            } else if state.observedConfirmedMembershipInTimeline, state.removalResult == nil {
                finishProductionDispatchRemoval(state, result: .success(()))
            }
        }
    }

    @MainActor
    private func reconcileProductionDispatchRoomInfo(_ roomInfo: RoomInfoProxyProtocol, observationID: UUID) {
        guard let state = productionDispatchObservations[observationID],
              roomInfo.id == state.roomID else {
            return
        }

        let hasLocalParticipant = roomInfo.activeRoomCallParticipants.contains { participant in
            participantBelongsToUser(participant, userID: state.ownUserID)
        }

        if !state.roomInfoBaselineEstablished {
            state.roomInfoBaselineEstablished = true
            state.baselineLocalParticipantPresent = hasLocalParticipant
            return
        }

        if state.confirmedMembership == nil, state.confirmationResult == nil,
           hasLocalParticipant, !state.baselineLocalParticipantPresent {
            let identity = Self.productionDispatchRoomInfoMembershipIdentity(ownUserID: state.ownUserID,
                                                                             ownDeviceID: state.ownDeviceID)
            state.confirmedMembership = identity
            state.observedLocalParticipantAfterConfirmation = true
            let context = SalemXStockElementCallContext(callID: identity.callScope.callID,
                                                        roomID: state.roomID,
                                                        callHandle: SalemXProductionDispatchOpaqueToken.callHandle())
            MXLog.info("Production dispatch observed local MatrixRTC participation in room info.")
            finishProductionDispatchConfirmation(state, result: .success(context))
        }

        if state.confirmedMembership != nil {
            if hasLocalParticipant {
                state.observedLocalParticipantAfterConfirmation = true
            } else if state.observedLocalParticipantAfterConfirmation, state.removalResult == nil {
                finishProductionDispatchRemoval(state, result: .success(()))
            }
        }
    }

    private static func productionDispatchRoomInfoMembershipIdentity(ownUserID: String,
                                                                     ownDeviceID: String) -> MatrixRTCCallMembershipIdentity {
        let partyID = MatrixRTCCallScope.directRoom.application
        return .init(callScope: .directRoom,
                     userID: ownUserID,
                     deviceID: ownDeviceID,
                     partyID: partyID,
                     stateKey: "_\(ownUserID)_\(ownDeviceID)_\(partyID)",
                     membershipID: partyID)
    }

    private static let productionDispatchMembershipTimestampSkewMilliseconds: UInt64 = 15_000

    private static func isProductionDispatchMembershipFresh(_ timestamp: UInt64, armedAtMilliseconds: UInt64) -> Bool {
        if timestamp >= armedAtMilliseconds {
            return true
        }
        return armedAtMilliseconds - timestamp <= productionDispatchMembershipTimestampSkewMilliseconds
    }

    @MainActor
    private func productionDispatchObservation(matching handle: SalemXStockElementCallObservationHandle)
        -> SalemXStockElementCallObservationState? {
        guard let state = productionDispatchObservations[handle.observationID], state.handle == handle else {
            return nil
        }
        return state
    }

    @MainActor
    private func finishProductionDispatchConfirmation(_ state: SalemXStockElementCallObservationState,
                                                      result: Result<SalemXStockElementCallContext, SalemXStockElementCallLifecycleError>) {
        guard state.confirmationResult == nil else { return }
        state.confirmationResult = result
        let continuations = state.confirmationContinuations
        state.confirmationContinuations.removeAll()
        continuations.forEach { $0.resume(returning: result) }
    }

    @MainActor
    private func finishProductionDispatchRemoval(_ state: SalemXStockElementCallObservationState,
                                                 result: Result<Void, SalemXStockElementCallLifecycleError>) {
        guard state.removalResult == nil else { return }
        state.removalResult = result
        let continuations = state.removalContinuations
        state.removalContinuations.removeAll()
        continuations.forEach { $0.resume(returning: result) }
    }

    @MainActor
    private func cancelProductionDispatchObservation(observationID: UUID) {
        guard let state = productionDispatchObservations.removeValue(forKey: observationID) else { return }
        state.observation?.cancel()
        state.roomInfoCancellable?.cancel()
        state.roomInfoCancellable = nil

        if state.confirmationResult == nil {
            MXLog.info("Production dispatch cancelled before local MatrixRTC membership was confirmed.")
        }
        finishProductionDispatchConfirmation(state, result: .failure(.cancelled))
        finishProductionDispatchRemoval(state, result: .failure(.cancelled))
        syncProductionDispatchObservedRoomIDs()
    }

    @MainActor
    private func syncProductionDispatchObservedRoomIDs() {
        productionDispatchObservedRoomIDs = Set(productionDispatchObservations.values.map(\.roomID))
    }

    private func observeSessionGlobalIncomingCalls() {
        sessionGlobalIncomingCallCancellable = nil
        sessionGlobalPresenceCancellable = nil
        sessionGlobalIncomingCallObservationStartedAt = nil
        sessionGlobalIncomingCallSubscriptionGeneration &+= 1
        observedSessionGlobalIncomingCallIdentityKeys.removeAll()
        observedSessionGlobalPresenceRoomIDs.removeAll()

        guard let clientProxy else {
            return
        }

        let subscriptionGeneration = sessionGlobalIncomingCallSubscriptionGeneration
        let clientIdentity = ObjectIdentifier(clientProxy as AnyObject)
        sessionGlobalIncomingCallObservationStartedAt = timeProvider.now()
        recordSessionGlobalIncomingCallSnapshotHistory(clientProxy.staticRoomSummaryProvider.roomListPublisher.value)
        recordSessionGlobalPresenceSnapshot(clientProxy.staticRoomSummaryProvider.roomListPublisher.value)
        recordSessionGlobalPresenceSnapshot(clientProxy.roomSummaryProvider.roomListPublisher.value)
        sessionGlobalIncomingCallCancellable = clientProxy.actionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard case let .receivedSyncNotification(notification, roomID) = action else {
                    return
                }

                self?.handleSessionGlobalSyncNotification(notification,
                                                          roomID: roomID,
                                                          clientIdentity: clientIdentity,
                                                          subscriptionGeneration: subscriptionGeneration)
            }
        sessionGlobalPresenceCancellable = Publishers.Merge(clientProxy.roomSummaryProvider.roomListPublisher,
                                                            clientProxy.staticRoomSummaryProvider.roomListPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomSummaries in
                self?.handleSessionGlobalRoomSummaries(roomSummaries)
            }
    }

    private func recordSessionGlobalIncomingCallSnapshotHistory(_ roomSummaries: [RoomSummary]) {
        for candidate in sessionGlobalRoomSummaryCandidates(from: roomSummaries) {
            observedSessionGlobalIncomingCallIdentityKeys.formUnion(candidate.identityKeys)
            if Self.isTerminalCallEvent(candidate.roomSummary.lastCallEvent) {
                consumedDirectCallIdentityKeys.formUnion(candidate.identityKeys)
            }
        }
    }

    private func recordSessionGlobalPresenceSnapshot(_ roomSummaries: [RoomSummary]) {
        for summary in roomSummaries where isIncomingMatrixRTCPresence(summary) {
            observedSessionGlobalPresenceRoomIDs.insert(summary.id)
        }
    }

    private func handleSessionGlobalRoomSummaries(_ roomSummaries: [RoomSummary]) {
        guard !salemXAnswerBridgeConfiguration.embeddedMatrixRTCAnswerBridgeEnabled else {
            return
        }

        let roomsWithPresence = Set(roomSummaries.filter { isIncomingMatrixRTCPresence($0) }.map(\.id))
        observedSessionGlobalPresenceRoomIDs.subtract(observedSessionGlobalPresenceRoomIDs.subtracting(roomsWithPresence))

        for summary in roomSummaries {
            guard isIncomingMatrixRTCPresence(summary),
                  !observedSessionGlobalPresenceRoomIDs.contains(summary.id) else {
                continue
            }

            observedSessionGlobalPresenceRoomIDs.insert(summary.id)
            let callEvent: RoomCallEvent
            if let lastCallEvent = summary.lastCallEvent, Self.isIncomingFallbackStartEvent(lastCallEvent) {
                callEvent = lastCallEvent
            } else {
                callEvent = .init(state: .incoming, intent: .audio)
            }
            let presenceIdentity = callEvent.callID ?? "matrixrtc-presence:\(summary.id):\(nextSessionSequence())"
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][MATRIXRTC-PRESENCE-INCOMING] room_id=\(summary.id) source=matrixrtc_presence")
            handleSessionGlobalIncomingCallCandidate(roomID: summary.id,
                                                     roomDisplayName: summary.name,
                                                     isDirect: summary.isDirect,
                                                     candidate: .init(callEvent: .init(state: callEvent.state,
                                                                                       intent: callEvent.intent,
                                                                                       callID: presenceIdentity),
                                                                      deduplicationID: presenceIdentity,
                                                                      isOwnEvent: false))
        }
    }

    private func isIncomingMatrixRTCPresence(_ summary: RoomSummary) -> Bool {
        guard summary.isDirect,
              !summary.isSpace,
              incomingCallID == nil,
              ongoingCallID == nil,
              activeCallSession?.roomID != summary.id,
              !productionDispatchObservedRoomIDs.contains(summary.id),
              let ownUserID = clientProxy?.userID else {
            return false
        }

        if let lastCallEvent = summary.lastCallEvent, Self.isTerminalCallEvent(lastCallEvent) {
            return false
        }

        if let suppressionDeadline = incomingFallbackSuppressionByRoomID[summary.id],
           suppressionDeadline > timeProvider.now() {
            return false
        }

        let hasLocalParticipant = summary.activeRoomCallParticipants.contains { participantBelongsToUser($0, userID: ownUserID) }
        guard !hasLocalParticipant else {
            return false
        }

        return summary.activeRoomCallParticipants.contains { !participantBelongsToUser($0, userID: ownUserID) }
    }

    private func handleSessionGlobalSyncNotification(_ notification: NotificationItem,
                                                     roomID: String,
                                                     clientIdentity: ObjectIdentifier,
                                                     subscriptionGeneration: UInt64) {
        guard sessionGlobalIncomingCallSubscriptionGeneration == subscriptionGeneration,
              let clientProxy,
              ObjectIdentifier(clientProxy as AnyObject) == clientIdentity,
              let observationStartedAt = sessionGlobalIncomingCallObservationStartedAt,
              case .timeline(let event) = notification.event,
              let eventContent = try? event.content(),
              case .messageLike(let content) = eventContent,
              case let .rtcNotification(notificationType, expirationTimestamp, callIntent) = content else {
            return
        }

        let eventID = event.eventId()
        let eventDate = Date(timeIntervalSince1970: TimeInterval(event.timestamp()) / 1000)
        let expirationDate = Date(timeIntervalSince1970: TimeInterval(expirationTimestamp) / 1000)
        guard !eventID.isEmpty,
              eventDate >= observationStartedAt,
              expirationDate > timeProvider.now() else {
            return
        }

        let intent: RoomCallEvent.Intent = switch callIntent {
        case .some(.audio): .audio
        case .some(.video): .video
        case .none: .unknown
        }
        let state: RoomCallEvent.State = notificationType == .ring ? .incoming : .started
        handleSessionGlobalIncomingCallEvent(.init(roomID: roomID,
                                                   roomDisplayName: notification.roomInfo.displayName,
                                                   isDirect: notification.roomInfo.isDirect,
                                                   isOwnEvent: event.senderId() == clientProxy.userID,
                                                   callEvent: .init(state: state, intent: intent),
                                                   deduplicationID: eventID))
    }

    private func sessionGlobalRoomSummaryCandidates(from roomSummaries: [RoomSummary]) -> [SessionGlobalRoomSummaryCandidate] {
        roomSummaries.compactMap { roomSummary in
            guard let remoteCallID = roomSummary.lastCallEvent?.callID,
                  !remoteCallID.isEmpty else {
                return nil
            }

            return .init(roomSummary: roomSummary,
                         remoteCallID: remoteCallID,
                         identityKeys: directCallIdentityKeys(roomID: roomSummary.id, remoteCallID: remoteCallID))
        }
    }

    private func handleSessionGlobalIncomingCallCandidate(roomID: String,
                                                          roomDisplayName: String?,
                                                          isDirect: Bool,
                                                          candidate: SessionGlobalIncomingCallCandidate) {
        guard isDirect,
              incomingCallID == nil,
              ongoingCallID == nil,
              !candidate.isOwnEvent,
              !Self.isTerminalCallEvent(candidate.callEvent),
              Self.isIncomingFallbackStartEvent(candidate.callEvent) else {
            return
        }

        let identityKeys = directCallIdentityKeys(roomID: roomID,
                                                  rtcNotificationID: candidate.deduplicationID,
                                                  remoteCallID: candidate.callEvent.callID)
        guard !identityKeys.isEmpty,
              consumedDirectCallIdentityKeys.isDisjoint(with: identityKeys),
              observedSessionGlobalIncomingCallIdentityKeys.isDisjoint(with: identityKeys) else {
            return
        }

        observedSessionGlobalIncomingCallIdentityKeys.formUnion(identityKeys)
        incomingFallbackSuppressionByRoomID.removeValue(forKey: roomID)
        if let remoteCallID = candidate.callEvent.callID {
            cacheRemoteCallID(remoteCallID, for: roomID)
        }

        Task { [weak self] in
            await self?.reportIncomingCallFromSessionGlobal(roomID: roomID,
                                                            roomDisplayName: roomDisplayName,
                                                            rtcNotificationID: candidate.deduplicationID,
                                                            remoteCallID: candidate.callEvent.callID)
        }
    }

    private func reportIncomingCallFromSessionGlobal(roomID: String,
                                                     roomDisplayName: String?,
                                                     rtcNotificationID: String?,
                                                     remoteCallID: String?) async {
        guard incomingCallID == nil,
              ongoingCallID == nil,
              !isConsumedDirectCallIdentity(roomID: roomID,
                                            rtcNotificationID: rtcNotificationID,
                                            remoteCallID: remoteCallID) else {
            return
        }

        let nowDate = timeProvider.now()
        let callID = CallID(callKitID: UUID(),
                            roomID: roomID,
                            rtcNotificationID: rtcNotificationID,
                            remoteCallID: remoteCallID,
                            startMode: .audio,
                            startedAt: nowDate)

        incomingCallID = callID
        openCallSession(roomID: roomID,
                        callKitID: callID.callKitID,
                        direction: .incoming,
                        remoteCallID: callID.remoteCallID)

        let update = CXCallUpdate()
        update.hasVideo = false
        update.localizedCallerName = roomDisplayName
        update.remoteHandle = .init(type: .generic, value: "salemx-call")

        MXLog.info("Element Call lifecycle diagnostics: session_global_incoming=true start_mode=\(callID.startMode)")

        callProvider.reportNewIncomingCall(with: callID.callKitID, update: update) { [weak self] error in
            if let error {
                MXLog.error("Session-global incoming call reporting failed: \(error)")
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
                                                       rtcNotificationID: String? = nil,
                                                       remoteCallID: String? = nil,
                                                       storeBootstrap: (UUID) -> Void) async -> SalemXStage2FCallKitReportResult {
        if incomingCallID != nil {
            return .blockedByExistingIncomingCall
        }

        if ongoingCallID != nil {
            return .blockedByExistingOngoingCall
        }

        guard !isConsumedDirectCallIdentity(roomID: roomID,
                                            rtcNotificationID: rtcNotificationID,
                                            remoteCallID: remoteCallID) else {
            return .blockedByConsumedCallIdentity
        }

        let nowDate = timeProvider.now()
        let callID = CallID(callKitID: UUID(),
                            roomID: roomID,
                            rtcNotificationID: rtcNotificationID,
                            remoteCallID: remoteCallID,
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

    private func directCallIdentityKeys(roomID: String,
                                        callKitID: UUID? = nil,
                                        rtcNotificationID: String? = nil,
                                        remoteCallID: String? = nil,
                                        membershipIdentities: Set<MatrixRTCCallMembershipIdentity> = []) -> Set<ConsumedDirectCallIdentityKey> {
        var components = Set<ConsumedDirectCallIdentityComponent>()
        if let callKitID {
            components.insert(.callKit(callKitID))
        }
        if let rtcNotificationID, !rtcNotificationID.isEmpty {
            components.insert(.rtcNotification(rtcNotificationID))
        }
        if let remoteCallID, !remoteCallID.isEmpty {
            components.insert(.remoteCall(remoteCallID))
        }
        components.formUnion(membershipIdentities.map(ConsumedDirectCallIdentityComponent.membership))

        return Set(components.map {
            ConsumedDirectCallIdentityKey(roomID: roomID,
                                          callScope: .directRoom,
                                          component: $0)
        })
    }

    private func isConsumedDirectCallIdentity(roomID: String,
                                              rtcNotificationID: String? = nil,
                                              remoteCallID: String? = nil) -> Bool {
        let candidateKeys = directCallIdentityKeys(roomID: roomID,
                                                   rtcNotificationID: rtcNotificationID,
                                                   remoteCallID: remoteCallID)
        return !candidateKeys.isEmpty && !consumedDirectCallIdentityKeys.isDisjoint(with: candidateKeys)
    }

    private func markConsumedDirectCallIdentity(_ callID: CallID) {
        let membershipIdentities: Set<MatrixRTCCallMembershipIdentity>
        if let observation = ongoingCallObservation,
           observation.identity.callKitID == callID.callKitID,
           observation.identity.roomID == callID.roomID {
            membershipIdentities = observation.roomInfoStateMachine.exactRemoteMembershipIdentities
        } else {
            membershipIdentities = []
        }

        consumedDirectCallIdentityKeys.formUnion(directCallIdentityKeys(roomID: callID.roomID,
                                                                        callKitID: callID.callKitID,
                                                                        rtcNotificationID: callID.rtcNotificationID,
                                                                        remoteCallID: callID.remoteCallID,
                                                                        membershipIdentities: membershipIdentities))
    }

    private func suppressIncomingFallback(for roomID: String) {
        incomingFallbackSuppressionByRoomID[roomID] = Date().addingTimeInterval(IncomingFallbackConstants.suppressionDuration)
    }

    private func incomingStartMode(for payload: [AnyHashable: Any], roomID: String) -> ElementCallStartMode {
        if let callIntent = callIntent(from: payload),
           let parsedStartMode = Self.startMode(fromCallIntent: callIntent) {
            return parsedStartMode
        }

        // SalemX direct calls fail closed to audio when the intent is absent or unknown.
        // A current room event can opt into video only when it says so explicitly.
        guard let roomSummary = clientProxy?.roomSummaryProvider.roomListPublisher.value.first(where: { $0.id == roomID }),
              roomSummary.hasOngoingCall,
              let lastCallEvent = roomSummary.lastCallEvent,
              !Self.isTerminalCallEvent(lastCallEvent) else {
            return .audio
        }

        switch lastCallEvent.intent {
        case .audio:
            return .audio
        case .video:
            return .video
        case .unknown:
            return .audio
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
            case SalemXProductionDispatchNotificationKey.envelope.rawValue:
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

    private static func isIncomingFallbackStartEvent(_ event: RoomCallEvent) -> Bool {
        switch event.state {
        case .incoming, .started, .answered, .legacyInvite:
            return true
        case .outgoing, .ended, .missed, .declined:
            return false
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

    @discardableResult
    private func applySessionEvent(type: CallSessionEventType,
                                   roomID: String,
                                   direction: CallSessionDirection? = nil,
                                   deduplicationID: String? = nil) -> Bool {
        let existingSession: CallSession? = if let activeCallSession, activeCallSession.roomID == roomID {
            activeCallSession
        } else {
            recentCallSessionByRoomID[roomID]
        }

        guard var session = existingSession else {
            return false
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
        return transition.isApplied
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

    private func observeOngoingCall(expectedCallID: CallID?) async {
        guard let expectedCallID else {
            return
        }

        let identity = OngoingCallObservationIdentity(callID: expectedCallID)
        guard ongoingCallMatches(identity),
              ongoingCallObservation?.identity != identity,
              ongoingCallObservationRequestIdentity != identity else {
            return
        }

        ongoingCallObservationRequestIdentity = identity
        defer { clearOngoingCallObservationRequest(matching: identity) }

        ongoingDeclineRefreshTask?.cancel()
        ongoingDeclineRefreshTask = nil
        let ongoingDeclineHandles = drainOngoingDeclineListenerHandles()
        ongoingDeclineHandles.forEach { $0.cancel() }
        finishResolvingOngoingDeclines()

        guard let clientProxy else {
            MXLog.warning("A ClientProxy is needed to observe an ongoing call.")
            return
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(expectedCallID.roomID) else {
            MXLog.warning("Failed to fetch a joined room for the ongoing call.")
            return
        }

        guard ongoingCallMatches(identity), ongoingCallObservation == nil else {
            return
        }

        guard ongoingCallSubscriptionGeneration < UInt64.max else { return }
        ongoingCallSubscriptionGeneration += 1
        let observation = OngoingCallObservation(identity: identity,
                                                 roomProxy: roomProxy,
                                                 ownDeviceID: clientProxy.deviceID,
                                                 subscriptionGeneration: ongoingCallSubscriptionGeneration)
        ongoingCallObservation = observation
        roomProxy.subscribeToRoomInfoUpdates()
        observeOngoingCallRoomInfo(ongoingCallID: expectedCallID,
                                   observation: observation)
        await observeOngoingCallRawMembershipState(roomProxy: roomProxy,
                                                   observation: observation)

        guard isCurrentOngoingCallObservation(observation) else {
            return
        }

        await observeOngoingCallTimeline(roomProxy: roomProxy,
                                         ongoingCallID: expectedCallID,
                                         observation: observation)

        guard isCurrentOngoingCallObservation(observation) else {
            return
        }

        await startObservingOngoingDeclines(roomProxy: roomProxy, ongoingCallID: expectedCallID)
        guard isCurrentOngoingCallObservation(observation) else {
            return
        }
        scheduleOngoingDeclineRefresh(roomProxy: roomProxy, ongoingCallID: expectedCallID)
    }

    private func ongoingCallMatches(_ identity: OngoingCallObservationIdentity) -> Bool {
        ongoingCallID?.callKitID == identity.callKitID && ongoingCallID?.roomID == identity.roomID
    }

    private func isCurrentOngoingCallObservation(_ observation: OngoingCallObservation) -> Bool {
        let context = observation.roomInfoStateMachine.context
        return ongoingCallMatches(observation.identity) &&
            ongoingCallObservation === observation &&
            observation.retainedProxyIdentity == ObjectIdentifier(observation.roomProxy as AnyObject) &&
            observation.subscriptionGeneration == ongoingCallSubscriptionGeneration &&
            context.callKitID == observation.identity.callKitID &&
            context.roomID == observation.identity.roomID &&
            context.callScope == observation.identity.callScope &&
            context.retainedProxyIdentity == observation.retainedProxyIdentity &&
            context.subscriptionGeneration == observation.subscriptionGeneration
    }

    private func clearOngoingCallObservation(matching identity: OngoingCallObservationIdentity?) {
        if let identity,
           let ongoingCallObservation,
           ongoingCallObservation.identity != identity {
            return
        }

        ongoingCallTimelineCancellable = nil
        ongoingCallRoomInfoCancellable = nil
        ongoingCallRawMembershipObservation?.cancel()
        ongoingCallRawMembershipObservation = nil
        ongoingCallObservation = nil
    }

    private func clearOngoingCallObservationRequest(matching identity: OngoingCallObservationIdentity?) {
        if let identity,
           let ongoingCallObservationRequestIdentity,
           ongoingCallObservationRequestIdentity != identity {
            return
        }

        ongoingCallObservationRequestIdentity = nil
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

    private func observeOngoingCallTimeline(roomProxy: JoinedRoomProxyProtocol,
                                            ongoingCallID: CallID,
                                            observation: OngoingCallObservation) async {
        await ensureTimelineSubscribed(for: roomProxy, roomID: ongoingCallID.roomID)

        guard isCurrentOngoingCallObservation(observation) else {
            return
        }

        let timelineItemProvider = await MainActor.run {
            roomProxy.timeline.timelineItemProvider
        }
        let tracker = TerminationEventTracker()

        ongoingCallTimelineCancellable = await MainActor.run {
            timelineItemProvider.updatePublisher
                .map(\.0)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] itemProxies in
                    guard let self else { return }
                    guard self.isCurrentOngoingCallObservation(observation) else { return }
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

    private func observeOngoingCallRawMembershipState(roomProxy: JoinedRoomProxyProtocol,
                                                      observation: OngoingCallObservation) async {
        guard let stateObserver = roomProxy as? MatrixRTCCallMembershipStateObserving else {
            MXLog.error("MatrixRTC raw membership state observation is unavailable.")
            return
        }

        let stateObservation = await stateObserver.observeMatrixRTCCallMembershipState { [weak self, weak observation] itemProxies in
            guard let self, let observation else { return }
            guard self.isCurrentOngoingCallObservation(observation) else { return }

            self.reconcileOngoingCallRawMembershipState(itemProxies,
                                                        observation: observation)
        }

        guard isCurrentOngoingCallObservation(observation) else {
            stateObservation?.cancel()
            return
        }

        guard let stateObservation else {
            MXLog.error("Failed observing MatrixRTC raw membership state.")
            return
        }

        ongoingCallRawMembershipObservation?.cancel()
        ongoingCallRawMembershipObservation = stateObservation
    }

    private func reconcileOngoingCallRawMembershipState(_ itemProxies: [TimelineItemProxy],
                                                        observation: OngoingCallObservation) {
        observation.roomInfoStateMachine.updateAuthoritativeState(itemProxies, now: timeProvider.now())
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

    private func observeOngoingCallRoomInfo(ongoingCallID: CallID,
                                            observation: OngoingCallObservation) {
        ongoingCallRoomInfoCancellable = observation.roomProxy.infoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] roomInfo in
                guard let self else { return }
                guard self.isCurrentOngoingCallObservation(observation) else { return }

                #if DEBUG
                let participants = roomInfo.activeRoomCallParticipants
                let hasLocalParticipant = participants.contains { self.participantBelongsToUser($0, userID: observation.roomProxy.ownUserID) }
                Task { @MainActor in
                    SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCObservation(participantCount: participants.count,
                                                                                    hasActiveCall: roomInfo.hasRoomCall || !participants.isEmpty,
                                                                                    localParticipantPresent: hasLocalParticipant,
                                                                                    remoteParticipantPresent: observation.roomInfoStateMachine.exactRemoteSeen)
                }
                #endif
                guard observation.roomInfoStateMachine.updateRoomInfo(roomInfo, now: self.timeProvider.now()) else {
                    return
                }

                self.endOngoingCall(ongoingCallID,
                                    reason: .remoteEnded,
                                    deduplicationID: "ongoing-room-info:\(ongoingCallID.callKitID.uuidString)")
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
        markConsumedDirectCallIdentity(incomingCallID)
        applySessionEvent(type: sessionEventType(for: reason),
                          roomID: incomingCallID.roomID,
                          deduplicationID: deduplicationID)
        clearIncomingCallState()
        reportCallKitEndedIfNeeded(uuid: incomingCallID.callKitID, reason: reason)
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
        if pendingLegacyAnswerCallID?.callKitID == incomingCallID?.callKitID {
            pendingLegacyAnswerCallID = nil
        }
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
        tearDownCallSession(sendEndCallAction: false, callKitEndReason: reason)
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
