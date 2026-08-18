//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK

struct RoomCallEvent: Equatable {
    enum State: Equatable {
        case incoming
        case outgoing
        case started
        case answered
        case ended
        case missed
        case declined
        case legacyInvite
    }

    enum Intent: String, Equatable {
        case audio
        case video
        case unknown
    }

    let state: State
    let intent: Intent
    let callID: String?

    init(state: State, intent: Intent, callID: String? = nil) {
        self.state = state
        self.intent = intent
        self.callID = callID
    }

    var statusTitle: String {
        switch state {
        case .incoming:
            UntranslatedL10n.commonIncomingCall
        case .outgoing:
            UntranslatedL10n.commonOutgoingCall
        case .started:
            L10n.commonCallStarted
        case .answered:
            UntranslatedL10n.commonCallAnswered
        case .ended:
            UntranslatedL10n.commonCallEnded
        case .missed:
            UntranslatedL10n.commonMissedCall
        case .declined:
            UntranslatedL10n.commonDeclinedCall
        case .legacyInvite:
            L10n.screenRoomTimelineLegacyCall
        }
    }

    var title: String {
        guard let callKindLabel = kindLabel else {
            return statusTitle
        }

        return "\(statusTitle) · \(callKindLabel)"
    }

    var kindLabel: String? {
        switch intent {
        case .audio, .video:
            L10n.commonAudio
        case .unknown:
            nil
        }
    }

    var kindCompoundIcon: KeyPath<CompoundIcons, Image>? {
        switch intent {
        case .audio, .video:
            \.voiceCallSolid
        case .unknown:
            nil
        }
    }
}

enum RoomCallEventParser {
    static func parse(from eventItemProxy: EventTimelineItemProxy) -> RoomCallEvent? {
        parse(content: eventItemProxy.content,
              rawJSONString: eventItemProxy.debugInfo.originalJSON,
              isOutgoing: eventItemProxy.isOwn)
    }

    static func parse(eventTimelineItem: EventTimelineItem) -> RoomCallEvent? {
        parse(content: eventTimelineItem.content,
              rawJSONString: eventTimelineItem.lazyProvider.debugInfo().originalJson,
              isOutgoing: eventTimelineItem.isOwn)
    }

    static func parse(content: TimelineItemContent, isOutgoing: Bool) -> RoomCallEvent? {
        parse(content: content,
              rawJSONString: nil,
              isOutgoing: isOutgoing)
    }

    static func parse(content: TimelineItemContent,
                      rawJSONString: String?,
                      isOutgoing: Bool) -> RoomCallEvent? {
        guard var event = baseEvent(from: content, isOutgoing: isOutgoing) else {
            return nil
        }

        guard let rawEvent = RawMatrixCallEvent(jsonString: rawJSONString) else {
            return event
        }

        event = .init(state: refinedState(from: rawEvent,
                                          defaultState: event.state,
                                          isOutgoing: isOutgoing),
                      intent: rawEvent.intent ?? event.intent,
                      callID: rawEvent.callID ?? event.callID)
        return event
    }

    private static func baseEvent(from content: TimelineItemContent, isOutgoing: Bool) -> RoomCallEvent? {
        switch content {
        case .callInvite:
            return .init(state: .legacyInvite, intent: .unknown, callID: nil)
        case .rtcNotification:
            return .init(state: .started, intent: .unknown, callID: nil)
        case .msgLike(let messageLikeContent):
            guard case .other(let eventType) = messageLikeContent.kind else {
                return nil
            }
            return baseEvent(from: eventType, isOutgoing: isOutgoing)
        case .failedToParseMessageLike,
             .failedToParseState,
             .state,
             .roomMembership,
             .profileChange,
             .liveLocation:
            return nil
        }
    }

    private static func baseEvent(from eventType: MessageLikeEventType, isOutgoing: Bool) -> RoomCallEvent? {
        switch eventType {
        case .callInvite:
            return .init(state: .legacyInvite, intent: .unknown, callID: nil)
        case .callNotify, .rtcNotification:
            return .init(state: .started, intent: .unknown, callID: nil)
        case .callAnswer:
            return .init(state: .answered, intent: .unknown, callID: nil)
        case .callHangup:
            return .init(state: .ended, intent: .unknown, callID: nil)
        case .callReject, .rtcDecline:
            return .init(state: isOutgoing ? .declined : .missed, intent: .unknown, callID: nil)
        case .other(let customType):
            let normalizedType = customType.lowercased()

            if normalizedType.contains("hangup") || normalizedType.contains("ended") {
                return .init(state: .ended, intent: .unknown, callID: nil)
            }

            if normalizedType.contains("reject") || normalizedType.contains("decline") {
                return .init(state: isOutgoing ? .declined : .missed, intent: .unknown, callID: nil)
            }

            if normalizedType.contains("answer") || normalizedType.contains("accept") {
                return .init(state: .answered, intent: .unknown, callID: nil)
            }

            return normalizedType.contains("call") || normalizedType.contains("rtc") ?
                .init(state: isOutgoing ? .outgoing : .incoming, intent: .unknown, callID: nil) :
                nil
        case .audio,
             .beacon,
             .callCandidates,
             .callNegotiate,
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
             .sticker,
             .unstablePollEnd,
             .unstablePollResponse,
             .unstablePollStart,
             .video,
             .voice:
            return nil
        }
    }

    private static func refinedState(from rawEvent: RawMatrixCallEvent,
                                     defaultState: RoomCallEvent.State,
                                     isOutgoing: Bool) -> RoomCallEvent.State {
        switch defaultState {
        case .started:
            guard let notificationType = rawEvent.notificationType else {
                return defaultState
            }
            return notificationType == .ring ? (isOutgoing ? .outgoing : .incoming) : .started
        case .ended:
            guard let hangupReason = rawEvent.hangupReason else {
                return defaultState
            }

            switch hangupReason {
            case .missed:
                return .missed
            case .declined:
                return isOutgoing ? .declined : .missed
            case .ended:
                return .ended
            }
        default:
            return defaultState
        }
    }
}

private struct RawMatrixCallEvent {
    enum NotificationType: String {
        case ring
        case notification
    }

    enum HangupReason {
        case missed
        case declined
        case ended
    }

    let content: [String: Any]

    init?(jsonString: String?) {
        guard let jsonString,
              let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let jsonObject = object as? [String: Any] else {
            return nil
        }

        content = jsonObject["content"] as? [String: Any] ?? [:]
    }

    var intent: RoomCallEvent.Intent? {
        if let callIntent = stringValueRecursively(forAnyOf: ["call_intent", "callIntent", "intent", "call_type", "callType"]),
           let resolvedIntent = resolveIntent(from: callIntent) {
            return resolvedIntent
        }

        if let foci = stringArrayValueRecursively(forAnyOf: ["foci", "foci_preferred", "fociPreferred", "foci_active", "fociActive"]) {
            if foci.contains(where: { $0.localizedCaseInsensitiveContains("video") }) {
                return .video
            }

            if foci.contains(where: { $0.localizedCaseInsensitiveContains("voice") || $0.localizedCaseInsensitiveContains("audio") }) {
                return .audio
            }
        }

        if let isVideoCall = boolValueRecursively(forAnyOf: ["is_video_call", "isVideoCall"]) {
            return isVideoCall ? .video : .audio
        }

        return nil
    }

    var notificationType: NotificationType? {
        guard let notificationType = stringValueRecursively(forAnyOf: ["notification_type", "notificationType", "notify_type", "notifyType"])?.lowercased() else {
            return nil
        }

        return NotificationType(rawValue: notificationType)
    }

    var callID: String? {
        stringValueRecursively(forAnyOf: ["call_id", "callId", "matrix_call_id", "matrixCallId"])
    }

    var hangupReason: HangupReason? {
        guard let rawReason = stringValueRecursively(forAnyOf: ["reason", "hangup_reason", "hangupReason"])?.lowercased() else {
            return nil
        }

        if rawReason.contains("timeout") || rawReason.contains("missed") || rawReason.contains("no_answer") {
            return .missed
        }

        if rawReason.contains("declin") || rawReason.contains("reject") || rawReason.contains("busy") || rawReason.contains("answered_elsewhere") {
            return .declined
        }

        return .ended
    }

    private func resolveIntent(from rawIntent: String) -> RoomCallEvent.Intent? {
        let normalizedIntent = rawIntent.lowercased()

        if normalizedIntent.localizedCaseInsensitiveContains("dmvoice") {
            return .audio
        }

        if normalizedIntent.localizedCaseInsensitiveContains("video") {
            return .video
        }

        if normalizedIntent.localizedCaseInsensitiveContains("startcalldm") || normalizedIntent == "dm" {
            return .video
        }

        if normalizedIntent.localizedCaseInsensitiveContains("startcall"),
           !normalizedIntent.localizedCaseInsensitiveContains("voice"),
           !normalizedIntent.localizedCaseInsensitiveContains("audio") {
            return .video
        }

        if normalizedIntent.localizedCaseInsensitiveContains("voice") || normalizedIntent.localizedCaseInsensitiveContains("audio") {
            return .audio
        }

        return nil
    }

    private func stringValueRecursively(forAnyOf keys: [String]) -> String? {
        keys.compactMap { key in
            valueRecursively(for: key, in: content) as? String
        }.first
    }

    private func stringArrayValueRecursively(forAnyOf keys: [String]) -> [String]? {
        for key in keys {
            guard let value = valueRecursively(for: key, in: content) else {
                continue
            }

            if let values = value as? [String] {
                return values
            }

            if let values = value as? [Any] {
                let stringValues = values.compactMap { $0 as? String }
                if !stringValues.isEmpty {
                    return stringValues
                }
            }
        }

        return nil
    }

    private func boolValueRecursively(forAnyOf keys: [String]) -> Bool? {
        for key in keys {
            guard let value = valueRecursively(for: key, in: content) else {
                continue
            }

            if let boolValue = value as? Bool {
                return boolValue
            }

            if let numberValue = value as? NSNumber {
                return numberValue.boolValue
            }

            if let stringValue = value as? String {
                switch stringValue.lowercased() {
                case "true", "1", "yes":
                    return true
                case "false", "0", "no":
                    return false
                default:
                    break
                }
            }
        }

        return nil
    }

    private func valueRecursively(for key: String, in object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            if let value = dictionary[key] {
                return value
            }

            for value in dictionary.values {
                if let recursiveValue = valueRecursively(for: key, in: value) {
                    return recursiveValue
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let recursiveValue = valueRecursively(for: key, in: value) {
                    return recursiveValue
                }
            }
        }

        return nil
    }
}

#if canImport(Compound) && canImport(SwiftUI)
import Compound
import SwiftUI

extension RoomCallEvent {
    var compoundIcon: KeyPath<CompoundIcons, Image> {
        switch state {
        case .outgoing:
            intent.compoundOutgoingIcon
        case .missed:
            intent.compoundMissedIcon
        case .declined:
            intent.compoundDeclinedIcon
        case .incoming, .started, .answered, .ended, .legacyInvite:
            intent.compoundDefaultIcon
        }
    }

    @MainActor var compoundTintColor: Color {
        switch state {
        case .answered:
            .compound.textSuccessPrimary
        case .missed, .declined:
            .compound.textCriticalPrimary
        case .incoming, .outgoing, .started, .ended, .legacyInvite:
            .compound.textSecondary
        }
    }

    @MainActor var cardBackgroundColor: Color {
        switch state {
        case .answered:
            .compound.bgSuccessSubtle
        case .missed, .declined:
            .compound.bgCriticalSubtle
        case .incoming, .outgoing, .started, .ended, .legacyInvite:
            .compound.bgCanvasDefaultLevel1
        }
    }

    @MainActor var cardBorderColor: Color {
        switch state {
        case .answered:
            .compound.iconSuccessPrimary.opacity(0.22)
        case .missed, .declined:
            .compound.iconCriticalPrimary.opacity(0.22)
        case .incoming, .outgoing, .started, .ended, .legacyInvite:
            .compound._bgSubtleSecondaryAlpha
        }
    }

    @MainActor var cardAccentColor: Color {
        switch state {
        case .answered:
            .compound.iconSuccessPrimary
        case .missed, .declined:
            .compound.iconCriticalPrimary
        case .incoming, .outgoing, .started, .ended, .legacyInvite:
            .compound.iconAccentTertiary
        }
    }
}

private extension RoomCallEvent.Intent {
    var compoundDefaultIcon: KeyPath<CompoundIcons, Image> {
        \.voiceCallSolid
    }

    var compoundOutgoingIcon: KeyPath<CompoundIcons, Image> {
        \.voiceCallOutgoingSolid
    }

    var compoundMissedIcon: KeyPath<CompoundIcons, Image> {
        \.voiceCallMissedSolid
    }

    var compoundDeclinedIcon: KeyPath<CompoundIcons, Image> {
        \.voiceCallDeclinedSolid
    }
}
#endif
