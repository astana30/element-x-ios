//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum SalemXProductionDispatchProtocolVersion: Int, Codable {
    case v1 = 1
}

enum SalemXProductionDispatchIntent: String, Codable {
    case audio
}

enum SalemXProductionDispatchEnvironment: String, Codable {
    case development
    case production
}

enum SalemXProductionDispatchReceiverHandoff: String, Codable {
    case matrixRTCElementCall = "matrixrtc_element_call"
}

enum SalemXProductionDispatchState: String, Codable {
    case prepared
    case claimed
    case sending
    case sent
    case consumed
    case cancelled
    case expired
    case sendFailed = "send_failed"
    case deliveryUnknown = "delivery_unknown"
}

enum SalemXProductionDispatchDeliveryMode: String, Codable {
    case foregroundAndAPNs = "foreground_and_apns"
}

enum SalemXProductionDispatchModelError: Error, Equatable {
    case unsupportedProtocol
    case malformedReference
    case invalidState
}

struct SalemXProductionDispatchCapabilityRegistrationRequest: Codable, CustomStringConvertible {
    let version = 1
    let token: String
    let environment: SalemXProductionDispatchEnvironment
    let protocolVersion = SalemXProductionDispatchProtocolVersion.v1.rawValue
    let intents = [SalemXProductionDispatchIntent.audio]
    let receiverHandoff = SalemXProductionDispatchReceiverHandoff.matrixRTCElementCall
    let appSessionGeneration: String
    let capabilityExpiresInSeconds: Int

    init(token: String,
         environment: SalemXProductionDispatchEnvironment,
         appSessionGeneration: String,
         capabilityExpiresInSeconds: Int = 3600) {
        self.token = token
        self.environment = environment
        self.appSessionGeneration = appSessionGeneration
        self.capabilityExpiresInSeconds = capabilityExpiresInSeconds
    }

    var description: String {
        "SalemXProductionDispatchCapabilityRegistrationRequest(<redacted>)"
    }

    private enum CodingKeys: String, CodingKey {
        case version, token, environment, intents
        case protocolVersion = "protocol_version"
        case receiverHandoff = "receiver_handoff"
        case appSessionGeneration = "app_session_generation"
        case capabilityExpiresInSeconds = "capability_expires_in_seconds"
    }
}

struct SalemXProductionDispatchCapabilityRegistrationResponse: Codable, Equatable {
    let registrationResult: String
    let tokenRedacted: Bool

    private enum CodingKeys: String, CodingKey {
        case registrationResult = "pushkit_token_registration_result"
        case tokenRedacted = "pushkit_token_redacted"
    }
}

struct SalemXProductionDispatchPendingMetadata: Codable, CustomStringConvertible {
    let version = 1
    let callID: String
    let roomID: String
    let intent = SalemXProductionDispatchIntent.audio

    var description: String {
        "SalemXProductionDispatchPendingMetadata(<redacted>)"
    }

    private enum CodingKeys: String, CodingKey {
        case version, intent
        case callID = "call_id"
        case roomID = "room_id"
    }
}

struct SalemXProductionDispatchPrepareRequest: Codable, CustomStringConvertible {
    let dispatchProtocolVersion = SalemXProductionDispatchProtocolVersion.v1.rawValue
    let type = "foreground.call.invite"
    let version = 1
    let recipient: String
    let recipientDevice: String?
    let callHandle: String
    let callKind = SalemXProductionDispatchIntent.audio
    let createdAtMS: Int64
    let expiresAtMS: Int64
    let displayLabel: String
    let deliveryMode = SalemXProductionDispatchDeliveryMode.foregroundAndAPNs
    let appSessionGeneration: String
    let pendingMetadata: SalemXProductionDispatchPendingMetadata

    var description: String {
        "SalemXProductionDispatchPrepareRequest(<redacted>)"
    }

    private enum CodingKeys: String, CodingKey {
        case type, version, recipient
        case dispatchProtocolVersion = "dispatch_protocol_version"
        case recipientDevice = "recipient_device"
        case callHandle = "call_handle"
        case callKind = "call_kind"
        case createdAtMS = "created_at_ms"
        case expiresAtMS = "expires_at_ms"
        case displayLabel = "display_label"
        case deliveryMode = "delivery_mode"
        case appSessionGeneration = "app_session_generation"
        case pendingMetadata = "pending_metadata"
    }
}

struct SalemXProductionDispatchPrepareResponse: Codable, Equatable, CustomStringConvertible {
    let dispatchProtocolVersion: Int
    let dispatchID: UUID
    let senderReference: String
    let receiverReference: String
    let state: SalemXProductionDispatchState

    var description: String {
        "SalemXProductionDispatchPrepareResponse(<redacted>)"
    }

    func validate() throws {
        guard dispatchProtocolVersion == SalemXProductionDispatchProtocolVersion.v1.rawValue else {
            throw SalemXProductionDispatchModelError.unsupportedProtocol
        }
        guard !senderReference.isEmpty, !receiverReference.isEmpty else {
            throw SalemXProductionDispatchModelError.malformedReference
        }
        guard state == .prepared else {
            throw SalemXProductionDispatchModelError.invalidState
        }
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case dispatchProtocolVersion = "dispatch_protocol_version"
        case dispatchID = "dispatch_id"
        case senderReference = "sender_reference"
        case receiverReference = "receiver_reference"
    }
}

struct SalemXProductionDispatchReferenceRequest: Codable, CustomStringConvertible {
    let dispatchProtocolVersion = SalemXProductionDispatchProtocolVersion.v1.rawValue
    let dispatchID: UUID
    let senderReference: String
    let appSessionGeneration: String

    var description: String {
        "SalemXProductionDispatchReferenceRequest(<redacted>)"
    }

    private enum CodingKeys: String, CodingKey {
        case dispatchProtocolVersion = "dispatch_protocol_version"
        case dispatchID = "dispatch_id"
        case senderReference = "sender_reference"
        case appSessionGeneration = "app_session_generation"
    }
}

struct SalemXProductionDispatchSendPreparedRequest: Codable, CustomStringConvertible {
    let dispatchProtocolVersion = SalemXProductionDispatchProtocolVersion.v1.rawValue
    let dispatchID: UUID
    let senderReference: String
    let receiverReference: String
    let appSessionGeneration: String

    var description: String {
        "SalemXProductionDispatchSendPreparedRequest(<redacted>)"
    }

    private enum CodingKeys: String, CodingKey {
        case dispatchProtocolVersion = "dispatch_protocol_version"
        case dispatchID = "dispatch_id"
        case senderReference = "sender_reference"
        case receiverReference = "receiver_reference"
        case appSessionGeneration = "app_session_generation"
    }
}

struct SalemXProductionDispatchClaimResponse: Codable, Equatable {
    let dispatchProtocolVersion: Int
    let state: SalemXProductionDispatchState
    let claimed: Bool
    let dispatchID: UUID?

    private enum CodingKeys: String, CodingKey {
        case state, claimed
        case dispatchProtocolVersion = "dispatch_protocol_version"
        case dispatchID = "dispatch_id"
    }
}

struct SalemXProductionDispatchSendPreparedResponse: Codable, Equatable {
    let dispatchProtocolVersion: Int
    let state: SalemXProductionDispatchState
    let apnsSent: Bool
    let apnsSendCount: Int
    let rawIdentifiersLogged: Bool
    let dispatchID: UUID?

    private enum CodingKeys: String, CodingKey {
        case state
        case dispatchProtocolVersion = "dispatch_protocol_version"
        case apnsSent = "APNs_sent"
        case apnsSendCount = "APNs_send_count"
        case rawIdentifiersLogged = "raw_identifiers_logged"
        case dispatchID = "dispatch_id"
    }
}

struct SalemXProductionDispatchCancelResponse: Codable, Equatable {
    let dispatchProtocolVersion: Int
    let state: SalemXProductionDispatchState
    let cancelled: Bool
    let dispatchID: UUID?

    private enum CodingKeys: String, CodingKey {
        case state, cancelled
        case dispatchProtocolVersion = "dispatch_protocol_version"
        case dispatchID = "dispatch_id"
    }
}

struct SalemXProductionDispatchReceiverConsumeRequest: Codable, CustomStringConvertible {
    let dispatchProtocolVersion = SalemXProductionDispatchProtocolVersion.v1.rawValue
    let dispatchID: UUID
    let receiverReference: String
    let appSessionGeneration: String

    var description: String {
        "SalemXProductionDispatchReceiverConsumeRequest(<redacted>)"
    }

    private enum CodingKeys: String, CodingKey {
        case dispatchProtocolVersion = "dispatch_protocol_version"
        case dispatchID = "dispatch_id"
        case receiverReference = "receiver_reference"
        case appSessionGeneration = "app_session_generation"
    }
}

struct SalemXProductionDispatchReceiverConsumeResponse: Codable, Equatable, CustomStringConvertible {
    let dispatchProtocolVersion: Int
    let state: SalemXProductionDispatchState
    let version: Int
    let callID: String
    let roomID: String
    let peerUserID: String
    let direction: String
    let intent: SalemXProductionDispatchIntent
    let expiresAtMS: Int64

    var description: String {
        "SalemXProductionDispatchReceiverConsumeResponse(<redacted>)"
    }

    private enum CodingKeys: String, CodingKey {
        case state, version, direction, intent
        case dispatchProtocolVersion = "dispatch_protocol_version"
        case callID = "call_id"
        case roomID = "room_id"
        case peerUserID = "peer_user_id"
        case expiresAtMS = "expires_at_ms"
    }
}

struct SalemXProductionDispatchServerErrorResponse: Codable, Equatable, CustomStringConvertible {
    let errcode: String
    let error: String?

    var description: String {
        "SalemXProductionDispatchServerErrorResponse(errcode: <redacted>, error: <redacted>)"
    }
}
