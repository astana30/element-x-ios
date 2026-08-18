//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import CallKit
import Clocks
import Combine
@testable import ElementX
import Foundation
import PushKit
import Testing

@MainActor
final class SalemXEmbeddedCallAnswerBridgeTests {
    @Test
    func validVerifiedBootstrapAcceptsExistingAudioPresentation() async {
        let handoff = MatrixRTCHandoffSpy(result: .handedOff(.readyToPresent(.audio(roomID: roomID, intent: .presentExisting))))
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .presentationAccepted)
        #expect(handoff.calls == [.init(metadata: claimedMetadata(direction: .incoming), intent: .presentExisting)])
        #expect(!handoff.calls.contains { $0.intent == .startNew })
    }

    @Test
    func alreadyPresentedExistingCallIsAccepted() async {
        let handoff = MatrixRTCHandoffSpy(result: .handedOff(.alreadyPresented(.audio(roomID: roomID, intent: .presentExisting))))
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .alreadyPresented)
        #expect(handoff.calls.map(\.intent) == [.presentExisting])
    }

    @Test
    func unsupportedIncomingJoinFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy(result: .handedOff(.unsupportedIncomingJoin(.audio(roomID: roomID, intent: .presentExisting))))
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .unsupportedIncomingJoin)
        #expect(handoff.calls.map(\.intent) == [.presentExisting])
    }

    @Test
    func noActiveMatrixRTCCallFailsClosedBeforeHandoff() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID,
                                         bootstrap: verifiedBootstrap(activeCallState: .none))

        #expect(result == .noActiveMatrixRTCCall)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func activeCallStateUnavailableFailsClosedBeforeHandoff() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID,
                                         bootstrap: verifiedBootstrap(activeCallState: .unavailable))

        #expect(result == .activeCallStateUnavailable)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func missingAuthenticatedSessionFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(userID: "", handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .noAuthenticatedSession)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func sessionUserMismatchFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(userID: "@other:matrix.org", handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .sessionIdentityMismatch)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func sessionDeviceMismatchFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(deviceID: "OTHERDEVICE", handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .sessionDeviceMismatch)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func dmRoomAmbiguityFailsClosed() async {
        let handoff = MatrixRTCHandoffSpy(result: .blocked(.roomAmbiguous))
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: callID, bootstrap: verifiedBootstrap())

        #expect(result == .dmRoomAmbiguous)
        #expect(handoff.calls.map(\.intent) == [.presentExisting])
    }

    @Test
    func bootstrapUUIDMismatchFailsClosedBeforeHandoff() async {
        let handoff = MatrixRTCHandoffSpy()
        let bridge = makeBridge(handoff: handoff)

        let result = await bridge.answer(callID: UUID(), bootstrap: verifiedBootstrap())

        #expect(result == .bootstrapMismatch)
        #expect(handoff.calls.isEmpty)
    }

    @Test
    func audioOnlyBoundaryDoesNotExposeMediaOrPermissions() throws {
        let preparation = EmbeddedElementCallPreparation.audio(roomID: roomID, intent: .presentExisting)
        let source = try Self.source(named: "ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift")

        #expect(preparation.startMode == .audio)
        #expect(preparation.cameraRequested == false)
        #expect(preparation.videoEnabled == false)
        #expect(!source.contains("requestMediaCredentials"))
        #expect(!source.contains("LiveKitDirectCall"))
        #expect(!source.contains("ProductionDirectCallLiveKitTokenClient"))
        #expect(!source.contains("AVCaptureDevice.requestAccess"))
        #expect(!source.contains("requestRecordPermission"))
    }

    @Test
    func answerBridgeDoesNotSynthesizeConnectedLifecycleFromCallKit() throws {
        let source = try Self.source(named: "ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift")

        #expect(!source.contains("CXAnswerCallAction"))
        #expect(!source.contains("connected"))
    }

    private let callID = UUID()
    private let roomID = "!room:matrix.org"
    private let localUserID = "@me:matrix.org"
    private let localDeviceID = "MEDEVICE"
    private let peerUserID = "@alice:matrix.org"
    private let peerDeviceID = "ALICEDEVICE"

    private func makeBridge(userID: String? = nil,
                            deviceID: String? = nil,
                            handoff: MatrixRTCHandoffSpy) -> SalemXEmbeddedCallAnswerBridge {
        let clientProxy = ClientProxyMock(.init(userID: userID ?? localUserID,
                                                deviceID: deviceID ?? localDeviceID))
        return SalemXEmbeddedCallAnswerBridge(clientProxy: clientProxy, matrixRTCHandoff: handoff)
    }

    private func verifiedBootstrap(activeCallState: VerifiedIncomingCallBootstrapActiveCallState = .active) -> VerifiedIncomingCallBootstrap {
        .init(callID: callID,
              claimedMetadata: claimedMetadata(direction: .incoming),
              localDeviceID: localDeviceID,
              activeCallState: activeCallState)
    }

    private func claimedMetadata(direction: SalemXMatrixRTCHandoffDirection) -> SalemXMatrixRTCClaimedMetadata {
        .init(roomID: roomID,
              localUserID: localUserID,
              peerUserID: peerUserID,
              peerDeviceID: peerDeviceID,
              direction: direction)
    }

    fileprivate static func source(named path: String) throws -> String {
        let repositoryRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRootURL.appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private struct MatrixRTCHandoffCall: Equatable {
        let metadata: SalemXMatrixRTCClaimedMetadata
        let intent: EmbeddedElementCallHandoffIntent
    }

    private final class MatrixRTCHandoffSpy: SalemXMatrixRTCHandoff {
        private let result: SalemXMatrixRTCHandoffResult
        private(set) var calls = [MatrixRTCHandoffCall]()

        init(result: SalemXMatrixRTCHandoffResult = .handedOff(.alreadyPresented(.audio(roomID: "!room:matrix.org", intent: .presentExisting)))) {
            self.result = result
        }

        func prepareAudioCall(claimedMetadata: SalemXMatrixRTCClaimedMetadata,
                              intent: EmbeddedElementCallHandoffIntent) async -> SalemXMatrixRTCHandoffResult {
            calls.append(.init(metadata: claimedMetadata, intent: intent))
            return result
        }
    }
}

@MainActor
final class SalemXEmbeddedCallEndBridgeTests {
    @Test
    func validVerifiedBootstrapTerminatesUpstreamElementCall() async {
        let terminator = EmbeddedElementCallTerminatorSpy(result: .accepted)
        let bridge = makeBridge(terminator: terminator)

        let result = await bridge.end(callID: callID,
                                      bootstrap: verifiedBootstrap(),
                                      source: .callKitLocalEnd)

        #expect(result == .terminationAccepted)
        #expect(terminator.roomIDs == [roomID])
    }

    @Test
    func noActiveMatrixRTCCallFailsClosedBeforeTermination() async {
        let terminator = EmbeddedElementCallTerminatorSpy(result: .accepted)
        let bridge = makeBridge(terminator: terminator)

        let result = await bridge.end(callID: callID,
                                      bootstrap: verifiedBootstrap(activeCallState: .none),
                                      source: .callKitLocalEnd)

        #expect(result == .noActiveMatrixRTCCall)
        #expect(terminator.roomIDs.isEmpty)
    }

    @Test
    func sessionMismatchFailsClosedBeforeTermination() async {
        let terminator = EmbeddedElementCallTerminatorSpy(result: .accepted)
        let bridge = makeBridge(userID: "@other:matrix.org", terminator: terminator)

        let result = await bridge.end(callID: callID,
                                      bootstrap: verifiedBootstrap(),
                                      source: .callKitLocalEnd)

        #expect(result == .sessionIdentityMismatch)
        #expect(terminator.roomIDs.isEmpty)
    }

    @Test
    func audioAndPermissionBoundaryDoesNotExposeMedia() throws {
        let source = try SalemXEmbeddedCallAnswerBridgeTests.source(named: "ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift")

        #expect(!source.contains("requestMediaCredentials"))
        #expect(!source.contains("LiveKitDirectCall"))
        #expect(!source.contains("sendDirectCallSignal"))
        #expect(!source.contains("m.call.hangup"))
        #expect(!source.contains("AVCaptureDevice.requestAccess"))
        #expect(!source.contains("requestRecordPermission"))
    }

    private let callID = UUID()
    private let roomID = "!room:matrix.org"
    private let localUserID = "@me:matrix.org"
    private let localDeviceID = "MEDEVICE"
    private let peerUserID = "@alice:matrix.org"
    private let peerDeviceID = "ALICEDEVICE"

    private func makeBridge(userID: String? = nil,
                            deviceID: String? = nil,
                            terminator: EmbeddedElementCallTerminatorSpy) -> SalemXEmbeddedCallEndBridge {
        let clientProxy = ClientProxyMock(.init(userID: userID ?? localUserID,
                                                deviceID: deviceID ?? localDeviceID))
        return SalemXEmbeddedCallEndBridge(clientProxy: clientProxy,
                                           embeddedElementCallTerminator: terminator)
    }

    private func verifiedBootstrap(activeCallState: VerifiedIncomingCallBootstrapActiveCallState = .active) -> VerifiedIncomingCallBootstrap {
        .init(callID: callID,
              claimedMetadata: .init(roomID: roomID,
                                     localUserID: localUserID,
                                     peerUserID: peerUserID,
                                     peerDeviceID: peerDeviceID,
                                     direction: .incoming),
              localDeviceID: localDeviceID,
              activeCallState: activeCallState)
    }

    private final class EmbeddedElementCallTerminatorSpy: EmbeddedElementCallTerminating {
        private let result: EmbeddedElementCallTerminationResult
        private(set) var roomIDs = [String]()

        init(result: EmbeddedElementCallTerminationResult) {
            self.result = result
        }

        func terminateEmbeddedElementCall(roomID: String) async -> EmbeddedElementCallTerminationResult {
            roomIDs.append(roomID)
            return result
        }
    }
}

@MainActor
final class SalemXStage2FSimulatorSignalingDebugTests {
    @Test
    func receiverBridgeOverrideIsDisabledByDefault() {
        #expect(SalemXEmbeddedCallAnswerBridgeConfiguration().embeddedMatrixRTCAnswerBridgeEnabled == false)
        #expect(ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled(environment: [:], arguments: []) == false)
    }

    @Test
    func receiverBridgeOverrideRequiresExplicitDebugLaunchArgumentOrEnvironment() {
        #expect(ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled(environment: ["SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE": "1"],
                                                                          arguments: []) == true)
        #expect(ProcessInfo.isSalemXStage2FSimulatorReceiverBridgeEnabled(environment: [:],
                                                                          arguments: ["-salemx-stage2f-sim-receiver-bridge"]) == true)
    }

    @Test
    func stage2FSimulatorSenderUsesUpstreamStartNewAudio() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("userSessionFlowCoordinator.startCall(roomID: roomProxy.id, startMode: .audio)"))
        #expect(source.contains("\"start_mode_audio=\\(senderStartModeAudio)\""))
    }

    @Test
    func stage2FSimulatorSenderRequiresActiveEvidenceBeforeInvite() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let waitCall = try #require(source.range(of: "guard await waitForActiveCallEvidence")?.lowerBound)
        let readyMarker = try #require(source.range(of: "senderReadyToSendForegroundInvite = true")?.lowerBound)

        #expect(source.contains("context.activeCallEvidenceSeen"))
        #expect(source.contains("lastFailure = \"activeCallEvidenceTimeout\""))
        #expect(waitCall < readyMarker)
    }

    @Test
    func stage2FSimulatorSenderRevalidatesExactOngoingCallBeforeInvite() throws {
        #expect(SalemXStage2FSimulatorSignalingDebug.senderActiveCallIsCurrent(contextRoomID: "redacted-room",
                                                                               ongoingCallRoomID: "redacted-room"))
        #expect(!SalemXStage2FSimulatorSignalingDebug.senderActiveCallIsCurrent(contextRoomID: "redacted-room",
                                                                                ongoingCallRoomID: nil))
        #expect(!SalemXStage2FSimulatorSignalingDebug.senderActiveCallIsCurrent(contextRoomID: "redacted-room",
                                                                                ongoingCallRoomID: "different-room"))

        let source = try stage2FSimulatorSignalingDebugSource()
        let revalidation = try #require(source.range(of: "senderActiveCallRevalidatedBeforeInvite = senderActiveCallIsCurrent")?.lowerBound)
        let inviteRequest = try #require(source.range(of: "let response = await httpJSON(url: inviteURL")?.lowerBound)

        #expect(source.contains("ongoingCallRoomID: elementCallService.ongoingCallRoomIDPublisher.value"))
        #expect(source.contains("lastFailure = \"activeCallEvidenceStale\""))
        #expect(revalidation < inviteRequest)
    }

    @Test
    func stage2FSimulatorInviteIsOneShotAndRealNonDev() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("!context.foregroundInviteSent"))
        #expect(source.contains("context.foregroundInviteSent"))
        #expect(source.contains("foregroundInviteSentOnce = true"))
        #expect(source.contains("realNonDevForegroundInviteUsed = true"))
        #expect(!source.contains("/dev/invite"))
    }

    @Test
    func stage2FSimulatorInviteRequestsForegroundOnlyDelivery() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let serviceSource = try SalemXEmbeddedCallAnswerBridgeTests.source(named: "ElementX/Sources/Services/ElementCall/ElementCallService.swift")

        #expect(source.contains("\"delivery_mode\": \"foreground_only\""))
        #expect(source.contains("foregroundOnlyInviteResponseAccepted(response.payload)"))
        #expect(!serviceSource.contains("\"delivery_mode\""))
    }

    @Test
    func stage2FSimulatorAuthPreflightUsesCurrentSessionBearerRequest() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("/direct-call/stage2f-sim/sender-auth-preflight"))
        #expect(source.contains("private static let whoamiPath = \"/_matrix/client/v3/account/whoami\""))
        #expect(source.contains("clientProxy as? DirectCallMatrixAccessTokenProviding"))
        #expect(source.contains("accessTokenProvider.matrixAccessToken()"))
        #expect(source.contains("method: \"GET\""))
        #expect(source.contains("requestTokenMatchesCurrentSessionToken = true"))
        #expect(source.contains("requestHomeserverMatchesCurrentSessionHomeserver"))
        #expect(source.contains("senderSameCredentialWhoamiSucceeded"))
    }

    @Test
    func stage2FSimulatorSenderLocalStatePreflightFailsClosed() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("/direct-call/stage2f-sim/sender-local-state-preflight"))
        #expect(source.contains("salemXDebugStage2FCallKitLocalStateBucket"))
        #expect(source.contains("proof.senderLocalActiveCallIdle = stateBucket == .idle"))
        #expect(source.contains("proof.senderLocalStateCheckFingerprint = fingerprint"))
        #expect(source.contains("proof.lastFailure = stateBucket == .idle ? \"none\" : \"activeCallAlreadyExists\""))
        #expect(source.contains("sender_local_active_call_idle=\\(senderLocalActiveCallIdle)"))
        #expect(source.contains("sender_local_call_state_bucket=\\(senderLocalCallStateBucket)"))
    }

    @Test
    func stage2FSimulatorBearerHeaderRejectsMissingAndBlankToken() {
        #expect(SalemXStage2FSimulatorSignalingDebug.bearerAuthorizationHeader(accessToken: nil) == nil)
        #expect(SalemXStage2FSimulatorSignalingDebug.bearerAuthorizationHeader(accessToken: "") == nil)
        #expect(SalemXStage2FSimulatorSignalingDebug.bearerAuthorizationHeader(accessToken: "   ") == nil)
        #expect(SalemXStage2FSimulatorSignalingDebug.bearerAuthorizationHeader(accessToken: "current-session-token") == "Bearer current-session-token")
    }

    @Test
    func stage2FSimulatorAuthPreflightBlocksMissingTokenBeforeNetwork() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("proof.senderCurrentSessionPresent = true"))
        #expect(source.contains("proof.senderCurrentAccessTokenPresent = false"))
        #expect(source.contains("proof.senderRequestAuthHeaderReady = false"))
        #expect(source.contains("return .init(status: nil, payload: [\"errcode\": \"missing_access_token\"])"))
    }

    @Test
    func stage2FSimulatorInviteDoesNotRetryOn401OrCreateAttemptID() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("guard (200..<300).contains(response.status ?? 0) else"))
        #expect(source.contains("proof.lastFailure = \"secureInviteSendFailed\""))
        #expect(source.contains("proof.foregroundInviteSentOnce = true"))
        #expect(!source.contains("retryForegroundInvite"))
        #expect(!source.contains("retryAccessToken"))
    }

    @Test
    func stage2FSimulatorAuthPreflightProofDoesNotWriteRawToken() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("sender_request_auth_header_ready=\\(senderRequestAuthHeaderReady)"))
        #expect(source.contains("request_token_matches_current_session_token=\\(requestTokenMatchesCurrentSessionToken)"))
        #expect(!source.contains("access_token=\\("))
        #expect(!source.contains("Authorization=\\("))
        #expect(!source.contains("Bearer \\("))
    }

    @Test
    func stage2FReceiverAuthPreflightUsesCurrentSessionBearerRequest() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("/direct-call/stage2f-sim/receiver-auth-preflight"))
        #expect(source.contains("private static func preflightReceiverAuthentication"))
        #expect(source.contains("receiverCurrentSessionPresent = true"))
        #expect(source.contains("receiverCurrentAccessTokenPresent = true"))
        #expect(source.contains("receiverClaimAuthHeaderReady = bearerAuthorizationHeader(accessToken: accessToken) != nil"))
        #expect(source.contains("receiverClaimHomeserverMatchesSession"))
        #expect(source.contains("receiverSameCredentialWhoamiAttempted = true"))
        #expect(source.contains("receiverSameCredentialWhoamiSucceeded"))
    }

    @Test
    func stage2FReceiverMetadataClaimRecordsHTTPAndDecodeBeforeActiveEvidence() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let functionStart = try #require(source.range(of: "private static func claimReceiverMetadataAndReportCallKit")?.lowerBound)
        let functionEnd = try #require(source.range(of: "private static func resolveDirectOneToOneDM")?.lowerBound)
        let functionSource = source[functionStart..<functionEnd]
        let claimSuccess = try #require(functionSource.range(of: "proof.receiverMetadataClaimSuccess = true")?.lowerBound)
        let activeEvidence = try #require(functionSource.range(of: "let activeCallState: VerifiedIncomingCallBootstrapActiveCallState")?.lowerBound)
        let callKitReport = try #require(functionSource.range(of: "salemXDebugReportStage2FSimulatorIncomingCall")?.lowerBound)

        #expect(source.contains("proof.receiverMetadataClaimAttempted = true"))
        #expect(source.contains("proof.receiverMetadataClaimHTTPStatus"))
        #expect(source.contains("proof.receiverMetadataClaimResponseDecodeSucceeded = true"))
        #expect(source.contains("proof.receiverMetadataClaimErrorBucket = \"none\""))
        #expect(claimSuccess < activeEvidence)
        #expect(activeEvidence < callKitReport)
    }

    @Test
    func stage2FReceiverActiveCallResolutionUsesClaimedRoomRemoteSnapshot() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let functionStart = try #require(source.range(of: "private static func claimReceiverMetadataAndReportCallKit")?.lowerBound)
        let functionEnd = try #require(source.range(of: "private static func resolveDirectOneToOneDM")?.lowerBound)
        let functionSource = source[functionStart..<functionEnd]
        let exactRoomSubscription = try #require(functionSource.range(of: "await roomProxy.subscribeForUpdates()")?.lowerBound)
        let remoteResolver = try #require(functionSource.range(of: "await waitForRemoteActiveCallEvidence(roomID: metadata.roomID")?.lowerBound)
        let activeState = try #require(functionSource.range(of: "let activeCallState: VerifiedIncomingCallBootstrapActiveCallState")?.lowerBound)
        let callKitReport = try #require(functionSource.range(of: "salemXDebugReportStage2FSimulatorIncomingCall")?.lowerBound)

        #expect(source.contains("private static func waitForRemoteActiveCallEvidence"))
        #expect(source.contains("private func salemXStage2FRemoteActiveCallEvidence"))
        #expect(source.contains("clientProxy.roomSummaryForIdentifier(roomID)"))
        #expect(source.contains("private func salemXStage2FExactRoomTimelineRemoteCallEvidence"))
        #expect(source.contains("roomProxy.timeline.timelineItemProvider.itemProxies"))
        #expect(exactRoomSubscription < remoteResolver)
        #expect(remoteResolver < activeState)
        #expect(activeState < callKitReport)
    }

    @Test
    func stage2FReceiverRemoteActiveCallResolutionDoesNotRequireLocalElementCallRoom() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let remoteStart = try #require(source.range(of: "private func salemXStage2FRemoteActiveCallEvidence")?.lowerBound)
        let remoteEnd = try #require(source.range(of: "enum SalemXStage2FSimulatorSignalingDebug")?.lowerBound)
        let remoteSource = source[remoteStart..<remoteEnd]

        #expect(remoteSource.contains("info.hasRoomCall || !info.activeRoomCallParticipants.isEmpty"))
        #expect(remoteSource.contains("summary.hasOngoingCall || !summary.activeRoomCallParticipants.isEmpty"))
        #expect(remoteSource.contains("await salemXStage2FExactRoomTimelineRemoteCallEvidence(roomProxy: roomProxy)"))
        #expect(source.contains("proof.receiverActiveCallSnapshotChecked = true"))
        #expect(source.contains("proof.receiverRemoteRoomSnapshotChecked = true"))
        #expect(!remoteSource.contains("ongoingCallRoomIDPublisher"))
    }

    @Test
    func stage2FReceiverRemoteActiveCallResolutionUsesExactRoomTimelineFallback() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let timelineStart = try #require(source.range(of: "private func salemXStage2FExactRoomTimelineRemoteCallEvidence")?.lowerBound)
        let timelineEnd = try #require(source.range(of: "private func salemXStage2FRemoteActiveCallEvent")?.lowerBound)
        let timelineSource = source[timelineStart..<timelineEnd]
        let stateStart = try #require(source.range(of: "private func salemXStage2FRemoteActiveCallEvent")?.lowerBound)
        let stateEnd = try #require(source.range(of: "enum SalemXStage2FSimulatorSignalingDebug")?.lowerBound)
        let stateSource = source[stateStart..<stateEnd]

        #expect(timelineSource.contains("roomProxy.timeline.timelineItemProvider.itemProxies"))
        #expect(timelineSource.contains("!eventProxy.isOwn"))
        #expect(timelineSource.contains("RoomCallEventParser.parse(from: eventProxy)"))
        #expect(timelineSource.contains("salemXStage2FRemoteActiveCallEvent(callEvent)"))
        #expect(stateSource.contains("[.incoming, .started, .answered, .legacyInvite].contains(event.state)"))
        #expect(source.contains("receiver_remote_room_snapshot_checked=\\(receiverRemoteRoomSnapshotChecked)"))
        #expect(source.contains("receiver_remote_room_call_state_visible=\\(receiverRemoteRoomCallStateVisible)"))
        #expect(source.contains("receiver_active_call_room_matches_claimed_metadata=\\(receiverActiveCallRoomMatchesClaimedMetadata)"))
    }

    @Test
    func stage2FAnswerBridgePresentsVerifiedRemoteCallWithoutLocalParticipation() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let configurationStart = try #require(source.range(of: "static func configureBridgeIfNeeded")?.lowerBound)
        let configurationEnd = try #require(source.range(of: "static func handleURL")?.lowerBound)
        let configurationSource = source[configurationStart..<configurationEnd]

        #expect(source.contains("func hasActiveBootstrap(roomID: String) -> Bool"))
        #expect(source.contains("bootstrap.activeCallState == .active"))
        #expect(configurationSource.contains("bootstrapStore.hasActiveBootstrap(roomID: roomID)"))
        #expect(configurationSource.contains("EmbeddedElementCallProductionHandoff"))
        #expect(source.contains("intent: .presentExisting"))
        #expect(!configurationSource.contains("intent: .startNew"))
    }

    @Test
    func stage2FReceiverActiveCallTimeoutDoesNotReportCallKit() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let functionStart = try #require(source.range(of: "private static func claimReceiverMetadataAndReportCallKit")?.lowerBound)
        let functionEnd = try #require(source.range(of: "private static func resolveDirectOneToOneDM")?.lowerBound)
        let functionSource = source[functionStart..<functionEnd]
        let timeoutFailure = try #require(functionSource.range(of: "proof.lastFailure = \"activeCallEvidenceTimeout\"")?.lowerBound)
        let callKitReport = try #require(functionSource.range(of: "salemXDebugReportStage2FSimulatorIncomingCall")?.lowerBound)

        #expect(functionSource.contains("guard activeCallState == .active else"))
        #expect(timeoutFailure < callKitReport)
    }

    @Test
    func stage2FReceiverProofRecordsActiveCallResolutionMarkers() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("receiver_active_call_resolution_started=\\(receiverActiveCallResolutionStarted)"))
        #expect(source.contains("receiver_active_call_snapshot_checked=\\(receiverActiveCallSnapshotChecked)"))
        #expect(source.contains("receiver_active_call_evidence_seen=\\(receiverActiveCallEvidenceSeen)"))
        #expect(!source.contains("room_id=\\("))
        #expect(!source.contains("call_id=\\("))
    }

    @Test
    func stage2FSenderPublishesRoomAndCallReadinessMarkersBeforeInviteGate() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let startSender = try #require(source.range(of: "private static func startSender")?.lowerBound)
        let sendInvite = try #require(source.range(of: "private static func sendForegroundInvite")?.lowerBound)
        let startSenderSource = source[startSender..<sendInvite]
        let activeEvidence = try #require(startSenderSource.range(of: "proof.senderActiveCallEvidenceSeen = true")?.lowerBound)
        let ready = try #require(startSenderSource.range(of: "proof.senderReadyToSendForegroundInvite = true")?.lowerBound)

        #expect(startSenderSource.contains("proof.senderExactRoomJoined = true"))
        #expect(startSenderSource.contains("proof.receiverExactRoomJoined = true"))
        #expect(startSenderSource.contains("proof.senderAndReceiverRoomMatch = true"))
        #expect(startSenderSource.contains("proof.senderActiveCallSnapshotPresent = true"))
        #expect(startSenderSource.contains("proof.senderActiveCallStatePublished = true"))
        #expect(startSenderSource.contains("proof.metadataRoomMatchesSenderActiveCallRoom = true"))
        #expect(activeEvidence < ready)
        #expect(source.contains("sender_active_call_state_published=\\(senderActiveCallStatePublished)"))
        #expect(source.contains("metadata_room_matches_sender_active_call_room=\\(metadataRoomMatchesSenderActiveCallRoom)"))
    }

    @Test
    func stage2FReceiverClaim401OrDecodeFailureDoesNotReportCallKit() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let statusGuard = try #require(source.range(of: "guard (200..<300).contains(response.status ?? 0) else")?.lowerBound)
        let decodeGuard = try #require(source.range(of: "guard let metadata = IncomingPendingMetadata(payload: response.payload) else")?.lowerBound)
        let callKitReport = try #require(source.range(of: "salemXDebugReportStage2FSimulatorIncomingCall")?.lowerBound)

        #expect(source.contains("proof.receiverMetadataClaimErrorBucket = metadataClaimErrorBucket(payload: response.payload, status: response.status)"))
        #expect(source.contains("proof.receiverMetadataClaimErrorBucket = \"decode\""))
        #expect(statusGuard < callKitReport)
        #expect(decodeGuard < callKitReport)
    }

    @Test
    func stage2FReceiverProofRecordsClaimPreflightAndFailureBuckets() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("receiver_claim_auth_header_ready=\\(receiverClaimAuthHeaderReady)"))
        #expect(source.contains("receiver_same_credential_whoami_succeeded=\\(receiverSameCredentialWhoamiSucceeded)"))
        #expect(source.contains("receiver_metadata_claim_attempted=\\(receiverMetadataClaimAttempted)"))
        #expect(source.contains("receiver_metadata_claim_http_status=\\(receiverMetadataClaimHTTPStatus)"))
        #expect(source.contains("receiver_metadata_claim_error_bucket=\\(receiverMetadataClaimErrorBucket)"))
        #expect(source.contains("receiver_active_call_evidence_seen=\\(receiverActiveCallEvidenceSeen)"))
        #expect(!source.contains("metadata_reference=\\("))
        #expect(!source.contains("access_token=\\("))
        #expect(!source.contains("Authorization=\\("))
    }

    @Test
    func stage2FReceiverForegroundStreamReadyIsFreshForEachLease() throws {
        let source = try stage2FSimulatorSignalingDebugSource()
        let receiverStart = try #require(source.range(of: "private static func startReceiver")?.lowerBound)
        let staleReadyReset = try #require(source.range(of: "proof.foregroundStreamActive = false; proof.foregroundStreamReady = false; writeProof()")?.lowerBound)
        let transportStart = try #require(source.range(of: "transport.start { event in")?.lowerBound)
        let stoppedCase = try #require(source.range(of: "case .stopped:\n            proof.foregroundStreamActive = false; proof.foregroundStreamReady = false")?.lowerBound)

        #expect(source.contains("receiverTransport?.stop()"))
        #expect(source.contains("case .ready:\n            proof.foregroundStreamActive = true; proof.foregroundStreamReady = true"))
        #expect(receiverStart < staleReadyReset)
        #expect(staleReadyReset < transportStart)
        #expect(transportStart < stoppedCase)
    }

    @Test
    func stage2FSimulatorExecutionNonceArmWritesHashOnlyCurrentNamespace() throws {
        let nonce = "current-run-nonce"
        let armURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/arm-nonce?execution_nonce=\(nonce)"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(armURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        let proof = try stage2FSimulatorProofText()
        let fingerprint = try #require(SalemXStage2FSimulatorSignalingDebug.executionNonceFingerprint(for: nonce))

        #expect(proof.contains("execution_nonce_present=true"))
        #expect(proof.contains("execution_nonce_fingerprint=\(fingerprint)"))
        #expect(proof.contains("execution_nonce_matches=true"))
        #expect(!proof.contains(nonce))
    }

    @Test
    func stage2FSimulatorClearRemovesExecutionNonceNamespaceAndStaleMarkers() throws {
        let armURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/arm-nonce?execution_nonce=stale-run"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(armURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))
        SalemXStage2FSimulatorSignalingDebug.recordReceiverAnswerResult(.presentationAccepted)

        let clearURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/clear"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        let proof = try stage2FSimulatorProofText()

        #expect(proof.contains("execution_nonce_present=false"))
        #expect(proof.contains("execution_nonce_fingerprint=none"))
        #expect(proof.contains("execution_nonce_matches=false"))
        #expect(proof.contains("receiver_callkit_answered=false"))
        #expect(proof.contains("receiver_present_existing_selected=false"))
        #expect(proof.contains("last_failure=none"))
    }

    @Test
    func stage2FSimulatorNewNonceRejectsOldMarkers() throws {
        let oldNonce = "old-run"
        let newNonce = "new-run"
        let oldURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/arm-nonce?execution_nonce=\(oldNonce)"))
        let newURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/arm-nonce?execution_nonce=\(newNonce)"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(oldURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))
        SalemXStage2FSimulatorSignalingDebug.recordReceiverAnswerResult(.presentationAccepted)

        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(newURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        let proof = try stage2FSimulatorProofText()
        let newFingerprint = try #require(SalemXStage2FSimulatorSignalingDebug.executionNonceFingerprint(for: newNonce))
        let oldFingerprint = try #require(SalemXStage2FSimulatorSignalingDebug.executionNonceFingerprint(for: oldNonce))

        #expect(proof.contains("execution_nonce_fingerprint=\(newFingerprint)"))
        #expect(!proof.contains("execution_nonce_fingerprint=\(oldFingerprint)"))
        #expect(proof.contains("receiver_callkit_answered=false"))
        #expect(proof.contains("receiver_present_existing_selected=false"))
    }

    @Test
    func stage2FSimulatorReceiverPreInviteGateRejectsMissingOrMismatchedNonce() throws {
        let nonce = "current-gate"
        let proof = try currentRunReceiverProofText(nonce: nonce)

        #expect(!SalemXStage2FSimulatorSignalingDebug.receiverCurrentRunPreInviteProofAccepted(proof,
                                                                                               expectedExecutionNonce: "other-gate"))
        #expect(!SalemXStage2FSimulatorSignalingDebug.receiverCurrentRunPreInviteProofAccepted(proof,
                                                                                               expectedExecutionNonce: " "))
        #expect(!SalemXStage2FSimulatorSignalingDebug.receiverCurrentRunPreInviteProofAccepted(proof.replacing("execution_nonce_matches=true",
                                                                                                               with: "execution_nonce_matches=false"),
                                                                                               expectedExecutionNonce: nonce))
    }

    @Test
    func stage2FSimulatorReceiverPreInviteGateAcceptsCurrentRunProof() throws {
        let nonce = "accepted-gate"
        let proof = try currentRunReceiverProofText(nonce: nonce)

        #expect(SalemXStage2FSimulatorSignalingDebug.receiverCurrentRunPreInviteProofAccepted(proof,
                                                                                              expectedExecutionNonce: nonce))
    }

    @Test
    func stage2FSimulatorForegroundOnlyResponseAcceptsCurrentAttempt() {
        let payload = foregroundOnlyPayload()

        #expect(SalemXStage2FSimulatorSignalingDebug.foregroundOnlyInviteResponseAccepted(payload,
                                                                                          expectedDeliveryAttemptID: "attempt-current"))
    }

    @Test
    func stage2FSimulatorForegroundOnlyResponseRejectsMissingAttempt() {
        var payload = foregroundOnlyPayload()
        payload.removeValue(forKey: "delivery_attempt_id")

        #expect(!SalemXStage2FSimulatorSignalingDebug.foregroundOnlyInviteResponseAccepted(payload))
    }

    @Test
    func stage2FSimulatorForegroundOnlyResponseRejectsDifferentAttempt() {
        let payload = foregroundOnlyPayload()

        #expect(!SalemXStage2FSimulatorSignalingDebug.foregroundOnlyInviteResponseAccepted(payload,
                                                                                           expectedDeliveryAttemptID: "attempt-other"))
    }

    @Test
    func stage2FSimulatorForegroundOnlyResponseRejectsAPNsRequested() {
        #expect(!SalemXStage2FSimulatorSignalingDebug.foregroundOnlyInviteResponseAccepted(foregroundOnlyPayload(overrides: ["apns_requested": true])))
    }

    @Test
    func stage2FSimulatorForegroundOnlyResponseRejectsProviderInvoked() {
        #expect(!SalemXStage2FSimulatorSignalingDebug.foregroundOnlyInviteResponseAccepted(foregroundOnlyPayload(overrides: ["apns_provider_invoked": true])))
    }

    @Test
    func stage2FSimulatorForegroundOnlyResponseRejectsAPNsSent() {
        #expect(!SalemXStage2FSimulatorSignalingDebug.foregroundOnlyInviteResponseAccepted(foregroundOnlyPayload(overrides: ["APNs_sent": true])))
    }

    @Test
    func stage2FSimulatorAdapterDoesNotUseForbiddenMediaPaths() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(!source.contains("requestMediaCredentials"))
        #expect(!source.contains("LiveKitDirectCall"))
        #expect(!source.contains("m.call.hangup"))
        #expect(!source.contains("AVCaptureDevice.requestAccess"))
        #expect(!source.contains("requestRecordPermission"))
        #expect(!source.contains("startMode: .video"))
    }

    @Test
    func stage2FSimulatorProofRecordsAnswerAndCleanupMarkers() throws {
        let source = try stage2FSimulatorSignalingDebugSource()

        #expect(source.contains("receiver_present_existing_selected=\\(receiverPresentExistingSelected)"))
        #expect(source.contains("receiver_start_new_selected=\\(receiverStartNewSelected)"))
        #expect(source.contains("receiver_join_existing_call_requested=\\(receiverJoinExistingCallRequested)"))
        #expect(source.contains("receiver_element_call_ready=\\(receiverElementCallReady)"))
        #expect(source.contains("receiver_element_call_loaded=\\(receiverElementCallLoaded)"))
        #expect(source.contains("receiver_widget_join_received=\\(receiverWidgetJoinReceived)"))
        #expect(source.contains("receiver_widget_join_acknowledged=\\(receiverWidgetJoinAcknowledged)"))
        #expect(source.contains("receiver_widget_join_driver_response_received=\\(receiverWidgetJoinDriverResponseReceived)"))
        #expect(source.contains("receiver_widget_join_dispatch_attempted=\\(receiverWidgetJoinDispatchAttempted)"))
        #expect(source.contains("receiver_widget_join_dispatch_completed=\\(receiverWidgetJoinDispatchCompleted)"))
        #expect(source.contains("receiver_widget_join_dispatch_error_bucket=\\(receiverWidgetJoinDispatchErrorBucket)"))
        #expect(source.contains("receiver_matrixrtc_join_started=\\(receiverMatrixRTCJoinStarted)"))
        #expect(source.contains("receiver_membership_send_marker_semantics=widget_driver_dispatch_only"))
        #expect(source.contains("receiver_membership_state_send_attempted=\\(receiverMembershipStateSendAttempted)"))
        #expect(source.contains("receiver_membership_state_send_completed=\\(receiverMembershipStateSendCompleted)"))
        #expect(source.contains("receiver_membership_state_send_http_bucket=\\(receiverMembershipStateSendHTTPBucket)"))
        #expect(source.contains("receiver_membership_present_on_synapse=\\(receiverMembershipPresentOnSynapse)"))
        #expect(source.contains("receiver_matrixrtc_credentials_requested=\\(receiverMatrixRTCCredentialsRequested)"))
        #expect(source.contains("receiver_matrixrtc_credentials_2xx=\\(receiverMatrixRTCCredentials2xx)"))
        #expect(source.contains("receiver_matrixrtc_credentials_http_bucket=\\(receiverMatrixRTCCredentialsHTTPBucket)"))
        #expect(source.contains("receiver_matrixrtc_membership_published=\\(receiverMatrixRTCMembershipPublished)"))
        #expect(source.contains("receiver_remote_participant_seen=\\(receiverRemoteParticipantSeen)"))
        #expect(source.contains("matrixrtc_two_participants_seen=\\(matrixRTCTwoParticipantsSeen)"))
        #expect(source.contains("sender_upstream_hangup_invoked=\\(senderUpstreamHangupInvoked)"))
        #expect(source.contains("receiver_upstream_remote_end_seen=\\(receiverUpstreamRemoteEndSeen)"))
        #expect(source.contains("receiver_callkit_ended_reported_once=\\(receiverCallKitEndedReportedOnce)"))
        #expect(source.contains("matrixrtc_room_empty_or_closed=\\(matrixRTCRoomEmptyOrClosed)"))
        #expect(source.contains("duplicate_callkit_end_reported=\\(duplicateCallKitEndReported)"))
    }

    @Test
    func stage2FSimulatorProofClearsStaleAnswerFailureAfterSuccess() throws {
        let clearURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/clear"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        SalemXStage2FSimulatorSignalingDebug.recordReceiverAnswerResult(.timedOut)
        var proof = try stage2FSimulatorProofText()
        #expect(proof.contains("last_failure=timedOut"))

        SalemXStage2FSimulatorSignalingDebug.recordReceiverAnswerResult(.presentationAccepted)
        proof = try stage2FSimulatorProofText()

        #expect(proof.contains("receiver_callkit_answered=true"))
        #expect(proof.contains("receiver_present_existing_selected=true"))
        #expect(proof.contains("last_failure=none"))
        #expect(!proof.contains("last_failure=timedOut"))
    }

    @Test
    func stage2FSimulatorProofClearResetsWidgetJoinMarkers() throws {
        let clearURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/clear"))
        setenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE", "1", 1)
        defer { unsetenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE") }

        SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinReceived()
        SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinAcknowledged()
        SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinDriverResponseReceived()
        SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinDispatchAttempted()
        SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinDispatchCompleted()
        SalemXStage2FSimulatorSignalingDebug.recordReceiverMembershipStateSendAttempted()
        SalemXStage2FSimulatorSignalingDebug.recordReceiverMembershipStateSendCompleted()
        SalemXStage2FSimulatorSignalingDebug.recordReceiverRTCTransportCredentialsRequested()
        SalemXStage2FSimulatorSignalingDebug.recordReceiverRTCTransportCredentialsResponse(httpStatus: 200)

        var proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_widget_join_received=true"))
        #expect(proof.contains("receiver_widget_join_acknowledged=true"))
        #expect(proof.contains("receiver_widget_join_driver_response_received=true"))
        #expect(proof.contains("receiver_widget_join_dispatch_attempted=true"))
        #expect(proof.contains("receiver_widget_join_dispatch_completed=true"))
        #expect(proof.contains("receiver_membership_send_attempted=true"))
        #expect(proof.contains("receiver_membership_send_completed=true"))
        #expect(proof.contains("receiver_membership_state_send_attempted=true"))
        #expect(proof.contains("receiver_membership_state_send_completed=true"))
        #expect(proof.contains("receiver_membership_state_send_http_bucket=2xx"))
        #expect(proof.contains("receiver_membership_present_on_synapse=true"))
        #expect(proof.contains("receiver_matrixrtc_credentials_requested=true"))
        #expect(proof.contains("receiver_matrixrtc_credentials_2xx=true"))
        #expect(proof.contains("receiver_matrixrtc_credentials_http_bucket=2xx"))

        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_widget_join_received=false"))
        #expect(proof.contains("receiver_widget_join_acknowledged=false"))
        #expect(proof.contains("receiver_widget_join_driver_response_received=false"))
        #expect(proof.contains("receiver_widget_join_dispatch_attempted=false"))
        #expect(proof.contains("receiver_widget_join_dispatch_completed=false"))
        #expect(proof.contains("receiver_widget_join_dispatch_error_bucket=not_requested"))
        #expect(proof.contains("receiver_membership_send_attempted=false"))
        #expect(proof.contains("receiver_membership_send_completed=false"))
        #expect(proof.contains("receiver_membership_send_error_bucket=not_requested"))
        #expect(proof.contains("receiver_membership_state_send_attempted=false"))
        #expect(proof.contains("receiver_membership_state_send_completed=false"))
        #expect(proof.contains("receiver_membership_state_send_http_bucket=not_requested"))
        #expect(proof.contains("receiver_membership_present_on_synapse=false"))
        #expect(proof.contains("receiver_matrixrtc_credentials_requested=false"))
        #expect(proof.contains("receiver_matrixrtc_credentials_2xx=false"))
        #expect(proof.contains("receiver_matrixrtc_credentials_http_bucket=not_requested"))
    }

    private func stage2FSimulatorSignalingDebugSource() throws -> String {
        try SalemXEmbeddedCallAnswerBridgeTests.source(named: "ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift")
    }

    private func stage2FSimulatorProofText() throws -> String {
        let proofURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("salemx-stage2f-sim-proof.txt")
        return try String(contentsOf: proofURL, encoding: .utf8)
    }

    private func foregroundOnlyPayload(overrides: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = [
            "delivery_mode": "foreground_only",
            "foreground_delivery_succeeded": true,
            "apns_requested": false,
            "apns_provider_invoked": false,
            "apns_provider_accepted": false,
            "APNs_sent": false,
            "delivery_attempt_id_present": true,
            "delivery_attempt_id": "attempt-current"
        ]
        payload.merge(overrides) { _, new in new }
        return payload
    }

    private func currentRunReceiverProofText(nonce: String, overrides: [String: String] = [:]) throws -> String {
        let fingerprint = try #require(SalemXStage2FSimulatorSignalingDebug.executionNonceFingerprint(for: nonce))
        var fields = [
            "execution_nonce_present": "true",
            "execution_nonce_fingerprint": fingerprint,
            "execution_nonce_matches": "true",
            "receiver_same_credential_whoami_succeeded": "true",
            "foreground_stream_active": "true",
            "foreground_stream_ready": "true",
            "delivery_attempt_id_present": "false",
            "receiver_callkit_incoming_reported": "false",
            "receiver_callkit_answer_action_seen": "false"
        ]
        fields.merge(overrides) { _, new in new }
        return fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }
}

@MainActor
final class SalemXMatrixRTCHandoffTests {
    @Test
    func claimedJoinedDMRoomHandsOffToAudioElementCall() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockAlice]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .handedOff(.readyToPresent(.audio(roomID: roomID, intent: .startNew))))
        #expect(elementCallHandoff.calls == [.init(roomID: roomID, intent: .startNew)])
        #expect(clientProxy.roomForIdentifierReceivedIdentifier == roomID)
        #expect(room.getMemberUserIDReceivedInvocations == [localUserID, peerUserID])
    }

    @Test
    func incomingJoinPreservesUnsupportedJoinSemantics() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockAlice]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy { roomID, intent in
            .unsupportedIncomingJoin(.audio(roomID: roomID, intent: intent))
        }
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(direction: .incoming),
                                                    intent: .joinExisting)

        #expect(result == .handedOff(.unsupportedIncomingJoin(.audio(roomID: roomID, intent: .joinExisting))))
        #expect(elementCallHandoff.calls == [.init(roomID: roomID, intent: .joinExisting)])
    }

    @Test
    func malformedClaimedMetadataBlocksBeforeRoomLookup() async {
        let clientProxy = makeClientProxy()
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(peerDeviceID: " "),
                                                    intent: .startNew)

        #expect(result == .blocked(.malformedClaimedMetadata))
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func unauthenticatedSessionBlocksBeforeRoomLookup() async {
        let clientProxy = makeClientProxy(userID: "")
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.unauthenticatedSession))
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func authenticatedUserMismatchBlocksBeforeRoomLookup() async {
        let clientProxy = makeClientProxy(userID: "@other:matrix.org")
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.authenticatedUserMismatch))
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func unjoinedRoomBlocksBeforeHandoff() async {
        let clientProxy = makeClientProxy()
        clientProxy.roomForIdentifierClosure = { _ in .left }
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.roomNotJoined))
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func nonDirectRoomBlocksBeforeHandoff() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: false,
                                             members: [.mockMe, .mockAlice]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.roomNotDirectOneToOne))
        #expect(room.getMemberUserIDCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func roomWithMoreThanTwoActiveMembersBlocksBeforeHandoff() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockAlice, .mockBob]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.roomNotDirectOneToOne))
        #expect(room.getMemberUserIDCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func peerOutsideRoomBlocksBeforeHandoff() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockBob]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.peerUserNotMember))
        #expect(room.getMemberUserIDReceivedInvocations == [localUserID, peerUserID])
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func claimedMetadataDescriptionIsRedacted() {
        let metadata = claimedMetadata()
        let description = String(describing: metadata)

        #expect(!description.contains(roomID))
        #expect(!description.contains(localUserID))
        #expect(!description.contains(peerUserID))
        #expect(!description.contains(peerDeviceID))
        #expect(description.contains("direction: outgoing"))
    }

    @Test
    func handoffResultDescriptionIsRedacted() {
        let result = SalemXMatrixRTCHandoffResult.handedOff(.readyToPresent(.audio(roomID: roomID, intent: .startNew)))
        let description = String(describing: result)

        #expect(!description.contains(roomID))
        #expect(description.contains("readyToPresent"))
    }

    private let roomID = "!room:matrix.org"
    private let localUserID = "@me:matrix.org"
    private let peerUserID = "@alice:matrix.org"
    private let peerDeviceID = "ALICEDEVICE"

    private func claimedMetadata(peerDeviceID: String? = nil,
                                 direction: SalemXMatrixRTCHandoffDirection = .outgoing) -> SalemXMatrixRTCClaimedMetadata {
        .init(roomID: roomID,
              localUserID: localUserID,
              peerUserID: peerUserID,
              peerDeviceID: peerDeviceID ?? self.peerDeviceID,
              direction: direction)
    }

    private func makeClientProxy(userID: String? = nil,
                                 roomProxy: JoinedRoomProxyProtocol? = nil) -> ClientProxyMock {
        let clientProxy = ClientProxyMock(.init(userID: userID ?? localUserID))
        clientProxy.roomForIdentifierClosure = { requestedRoomID in
            guard requestedRoomID == self.roomID, let roomProxy else {
                return nil
            }

            return .joined(roomProxy)
        }
        return clientProxy
    }

    private struct ElementCallHandoffCall: Equatable {
        let roomID: String
        let intent: EmbeddedElementCallHandoffIntent
    }

    private final class ElementCallHandoffSpy: EmbeddedElementCallHandoff {
        private let result: (String, EmbeddedElementCallHandoffIntent) -> EmbeddedElementCallHandoffResult
        private(set) var calls = [ElementCallHandoffCall]()

        init(result: @escaping (String, EmbeddedElementCallHandoffIntent) -> EmbeddedElementCallHandoffResult = { roomID, intent in
            .readyToPresent(.audio(roomID: roomID, intent: intent))
        }) {
            self.result = result
        }

        func prepareAudioCall(roomID: String, intent: EmbeddedElementCallHandoffIntent) async -> EmbeddedElementCallHandoffResult {
            calls.append(.init(roomID: roomID, intent: intent))
            return result(roomID, intent)
        }
    }
}

@MainActor
final class SalemXEmbeddedCallAnswerBridgeServiceTests {
    private let appSettings = AppSettings()
    private var callProvider: CXProviderMock!
    private var currentDate: Date!
    private var pushRegistry: PKPushRegistry!
    private var service: ElementCallService!
    private let localUserID = "@test:user.net"
    private var cancellables = Set<AnyCancellable>()

    init() {
        AppSettings.resetAllSettings()
        callProvider = CXProviderMock(.init())
        currentDate = Date()
        pushRegistry = PKPushRegistry(queue: nil)
    }

    deinit {
        callProvider = nil
        currentDate = nil
        pushRegistry = nil
    }

    private final class ApplicationActivitySpy {
        var isActive: Bool
        let didBecomeActiveSubject = PassthroughSubject<Void, Never>()

        init(isActive: Bool) {
            self.isActive = isActive
        }

        var provider: ApplicationActivityProvider {
            ApplicationActivityProvider(isActive: { [weak self] in self?.isActive ?? false },
                                        didBecomeActivePublisher: didBecomeActiveSubject.eraseToAnyPublisher())
        }
    }

    @Test
    func foregroundVideoAnswerRetainsLegacyRoute() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.fulfillCount == 1 })
        service.handleCallProviderAudioSessionActivation()
        #expect(action.failCount == 0)
        #expect(answerBridge.calls.isEmpty)
        #expect(await waitUntil { observedActions.contains { action in
            guard case .startCall(let roomID, let startMode) = action else {
                return false
            }
            return roomID == Self.roomID && startMode == .video
        } })
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
    }

    @Test
    func lockedAudioAnswerStartsCallWhenApplicationIsActiveAndKeepsCallKitActive() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall(startMode: .audio)
        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(action.fulfillCount == 1)
        #expect(action.failCount == 0)
        #expect(await waitUntil {
            observedActions.filter { if case .startCall = $0 { true } else { false } }.count == 1
        })
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)

        service.handleCallProviderAudioSessionActivation()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(observedActions.filter { if case .startCall = $0 { true } else { false } }.count == 1)
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)

        await service.setupCallSession(roomID: Self.roomID, roomDisplayName: "welcome", startMode: .audio)
        #expect(service.ongoingCallRoomIDPublisher.value == Self.roomID)

        let firstEndAction = EndActionSpy(callUUID: callID)
        let duplicateEndAction = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(firstEndAction, provider: callProvider)
        service.handleEndCallAction(duplicateEndAction, provider: callProvider)

        #expect(firstEndAction.fulfillCount == 1)
        #expect(duplicateEndAction.fulfillCount == 1)
        #expect(observedActions.filter { if case .requestCallTermination = $0 { true } else { false } }.count == 1)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func publicTearDownEndsKeptAliveAudioCallKitSession() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall(startMode: .audio)
        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)
        service.handleCallProviderAudioSessionActivation()

        #expect(await waitUntil {
            observedActions.filter { if case .startCall = $0 { true } else { false } }.count == 1
        })
        await service.setupCallSession(roomID: Self.roomID, roomDisplayName: "welcome", startMode: .audio)
        #expect(service.ongoingCallRoomIDPublisher.value == Self.roomID)
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)

        service.tearDownCallSession()

        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.uuid == callID)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)
    }

    @Test
    func publicTearDownEndsOutgoingAudioCallKitSession() async {
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: BootstrapResolverSpy(),
                                          answerBridge: AnswerBridgeSpy(result: .alreadyPresented))

        await service.setupCallSession(roomID: Self.roomID, roomDisplayName: "welcome", startMode: .audio)
        #expect(service.ongoingCallRoomIDPublisher.value == Self.roomID)
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)

        service.tearDownCallSession()

        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
        #expect(service.ongoingCallRoomIDPublisher.value == nil)

        service.tearDownCallSession()
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)
    }

    @Test
    func answeredAudioCallStartsWithoutWaitingForCallKitAudioActivation() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall(startMode: .audio)
        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(action.fulfillCount == 1)
        #expect(await waitUntil {
            observedActions.filter { if case .startCall = $0 { true } else { false } }.count == 1
        })
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)
    }

    @Test
    func audioAnswerConfiguresEarpieceBeforeCallKitFulfillAndKeepsCallKitAlive() throws {
        let source = try SalemXEmbeddedCallAnswerBridgeTests.source(named: "ElementX/Sources/Services/ElementCall/ElementCallService.swift")
        #expect(source.contains("CallVoiceAudioSession.configure(speakerEnabled: false)"))
        #expect(source.contains("[CALL-INCOMING-TRACE][APP-AUDIO-EARPIECE] reason=answer"))
        #expect(source.contains("[CALL-INCOMING-TRACE][APP-AUDIO-EARPIECE] reason=callkit_activated"))
        #expect(source.contains("keptAliveAudioCallKitID = incomingCallID.callKitID"))
    }

    @Test
    func answeredAudioCallWaitsForApplicationToBecomeActiveBeforeStarting() async throws {
        let activity = ApplicationActivitySpy(isActive: false)
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge,
                                          applicationActivityProvider: activity.provider)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall(startMode: .audio)
        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(action.fulfillCount == 1)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(!observedActions.contains { if case .startCall = $0 { true } else { false } })
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)

        service.handleCallProviderAudioSessionActivation()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(!observedActions.contains { if case .startCall = $0 { true } else { false } })

        activity.isActive = true
        activity.didBecomeActiveSubject.send()

        #expect(await waitUntil {
            observedActions.filter { if case .startCall = $0 { true } else { false } }.count == 1
        })
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)
    }

    @Test
    func answeredAudioCallReportsCallKitEndedOnRemoteHangupAfterMissingAudioActivation() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall(startMode: .audio)
        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(action.fulfillCount == 1)
        #expect(await waitUntil {
            observedActions.filter { if case .startCall = $0 { true } else { false } }.count == 1
        })
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)

        await service.setupCallSession(roomID: Self.roomID, roomDisplayName: "welcome", startMode: .audio)
        #expect(service.ongoingCallRoomIDPublisher.value == Self.roomID)

        let remoteUserID = "@alice:example.com"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: Self.roomID,
                                                              name: "Room",
                                                              isDirect: true,
                                                              hasOngoingCall: true,
                                                              ownUserID: localUserID))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }
        let roomInfoSubscription = EmbeddedRoomInfoSubscriptionHarness(initialValue: makeRoomInfo(participants: [localUserID, remoteUserID]))
        let localMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership",
                                                                  roomID: Self.roomID,
                                                                  userID: localUserID,
                                                                  deviceID: "LOCAL_DEVICE",
                                                                  membershipID: "LOCAL_PARTY",
                                                                  isActive: true)
        roomInfoSubscription.install(on: room, initialTimelineItems: [
            localMembership,
            makeMatrixRTCMembershipTimelineItem(eventID: "$remote-membership",
                                                roomID: Self.roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: true)
        ])

        let clientProxy = ClientProxyMock(.init(userID: localUserID, deviceID: "LOCAL_DEVICE"))
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        service.setClientProxy(clientProxy)
        #expect(await waitUntil { room.subscribeToRoomInfoUpdatesCallsCount == 1 })
        #expect(await roomInfoSubscription.waitForTimelineSubscription())
        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(participants: [localUserID, remoteUserID])))
        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(participants: [localUserID])))
        #expect(await waitUntil {
            self.callProvider.reportCallWithEndedAtReasonCallsCount == 1 &&
                observedActions.contains { if case .endCall = $0 { true } else { false } } &&
                self.service.ongoingCallRoomIDPublisher.value == nil
        })
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.uuid == callID)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
    }

    @Test
    func duplicateLegacyAnswerIsFulfilledWithoutDuplicatePresentation() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        var startCallCount = 0
        service.actions
            .sink { action in
                if case .startCall = action {
                    startCallCount += 1
                }
            }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall(startMode: .audio)
        let firstAction = AnswerActionSpy(callUUID: callID)
        let duplicateAction = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(firstAction, provider: callProvider)
        service.handleAnswerCallAction(duplicateAction, provider: callProvider)
        service.handleCallProviderAudioSessionActivation()

        #expect(await waitUntil { startCallCount == 1 })
        #expect(firstAction.fulfillCount == 1)
        #expect(duplicateAction.fulfillCount == 1)
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)
    }

    @Test
    func missingIncomingCallFailsAnswerActionOnce() {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let action = AnswerActionSpy(callUUID: UUID())
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(action.failCount == 1)
        #expect(action.fulfillCount == 0)
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)
    }

    @Test
    func enabledBridgeFulfillsSuccessfulPresentationOnceWithoutStartingLegacyRoute() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.fulfillCount == 1 })
        #expect(action.failCount == 0)
        #expect(answerBridge.calls.map(\.callID) == [callID])
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments == nil)
        #expect(bootstrapResolver.removedCallIDs.isEmpty)
        #expect(service.ongoingCallRoomIDPublisher.value == Self.roomID)
        #expect(!observedActions.contains { action in
            if case .startCall = action {
                return true
            }
            return false
        })

        service.handleEmbeddedMatrixRTCUpstreamTerminalEvent(callID: callID, source: .embeddedRemoteEnd)

        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func setupCallSessionForAnsweredEmbeddedRoomPreservesOriginalCallKitID() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.fulfillCount == 1 })
        await service.setupCallSession(roomID: Self.roomID, roomDisplayName: "welcome", startMode: .audio)

        #expect(service.ongoingCallRoomIDPublisher.value == Self.roomID)
        #expect(bootstrapResolver.removedCallIDs.isEmpty)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments == nil)

        service.handleEmbeddedMatrixRTCUpstreamTerminalEvent(callID: callID, source: .embeddedRemoteEnd)

        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func enabledBridgeFailsPresentationErrorOnce() async throws {
        let answerBridge = AnswerBridgeSpy(result: .noActiveMatrixRTCCall)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(action.fulfillCount == 0)
        #expect(answerBridge.calls.count == 1)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .failed)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func duplicateAnswerDoesNotStartSecondTaskOrPresentTwice() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented, delay: .milliseconds(50))
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let firstAction = AnswerActionSpy(callUUID: callID)
        let secondAction = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(firstAction, provider: callProvider)
        service.handleAnswerCallAction(firstAction, provider: callProvider)
        service.handleAnswerCallAction(secondAction, provider: callProvider)

        #expect(await waitUntil { firstAction.fulfillCount == 1 && secondAction.fulfillCount == 1 })
        #expect(firstAction.failCount == 0)
        #expect(secondAction.failCount == 0)
        #expect(answerBridge.calls.count == 1)
    }

    @Test
    func timeoutFailsOnceAndReleasesBootstrap() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented, delay: .milliseconds(100))
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(embeddedMatrixRTCAnswerBridgeEnabled: true,
                                                               answerTimeout: .milliseconds(10)),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(action.fulfillCount == 0)
        #expect(answerBridge.calls.count == 1)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func cancellationReleasesInFlightGuardAndFailsActionOnce() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented, delay: .milliseconds(100))
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)
        await service.declineIncomingCall()

        #expect(await waitUntil { action.failCount == 1 })
        #expect(action.fulfillCount == 0)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func missingSecureBootstrapFailsClosed() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(answerBridge.calls.isEmpty)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .failed)
    }

    @Test
    func bootstrapRoomOrUUIDMismatchFailsClosed() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: UUID())

        let action = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(answerBridge.calls.isEmpty)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func defaultDisabledLocalEndUsesLegacyRoute() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let endBridge = EndBridgeSpy(result: .terminationAccepted)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge,
                                          endBridge: endBridge)

        var observedActions = [ElementCallServiceAction]()
        service.actions
            .sink { observedActions.append($0) }
            .store(in: &cancellables)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)
        await service.setupCallSession(roomID: Self.roomID, roomDisplayName: "welcome", startMode: .audio)

        let action = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(action, provider: callProvider)

        #expect(action.fulfillCount == 1)
        #expect(action.failCount == 0)
        #expect(endBridge.calls.isEmpty)
        #expect(observedActions.contains { action in
            guard case .requestCallTermination(let roomID) = action else {
                return false
            }
            return roomID == Self.roomID
        })
    }

    @Test
    func enabledLocalEndInvokesEmbeddedBridgeAndFulfillsOnce() async throws {
        let endBridge = EndBridgeSpy(result: .terminationAccepted)
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)

        let action = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.fulfillCount == 1 })
        #expect(action.failCount == 0)
        #expect(endBridge.calls.map(\.source) == [.callKitLocalEnd])
        #expect(endBridge.calls.map(\.callID) == [callID])
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func callKitProviderRoutesExactLocalEndToEmbeddedBridge() async throws {
        let endBridge = EndBridgeSpy(result: .terminationAccepted)
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)

        service.provider(CXProvider(configuration: CXProviderConfiguration()),
                         perform: CXEndCallAction(call: callID))

        #expect(await waitUntil { endBridge.calls.count == 1 })
        #expect(endBridge.calls.map(\.callID) == [callID])
        #expect(endBridge.calls.map(\.source) == [.callKitLocalEnd])
    }

    @Test
    func unmatchedLocalEndFailsClosedAndPreservesExactCallMapping() async throws {
        let endBridge = EndBridgeSpy(result: .terminationAccepted)
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)

        let unmatchedAction = EndActionSpy(callUUID: UUID())
        service.handleEndCallAction(unmatchedAction, provider: callProvider)

        #expect(unmatchedAction.failCount == 1)
        #expect(unmatchedAction.fulfillCount == 0)
        #expect(endBridge.calls.isEmpty)
        #expect(bootstrapResolver.removedCallIDs.isEmpty)

        let exactAction = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(exactAction, provider: callProvider)

        #expect(await waitUntil { exactAction.fulfillCount == 1 })
        #expect(exactAction.failCount == 0)
        #expect(endBridge.calls.map(\.callID) == [callID])
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func terminationFailureFailsActionOnce() async throws {
        let endBridge = EndBridgeSpy(result: .failed)
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)

        let action = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(action.fulfillCount == 0)
        #expect(endBridge.calls.count == 1)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func duplicateEndInvokesTerminationOnceAndCompletesBothActions() async throws {
        let endBridge = EndBridgeSpy(result: .terminationAccepted, delay: .milliseconds(50))
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)

        let firstAction = EndActionSpy(callUUID: callID)
        let secondAction = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(firstAction, provider: callProvider)
        service.handleEndCallAction(firstAction, provider: callProvider)
        service.handleEndCallAction(secondAction, provider: callProvider)

        #expect(await waitUntil { firstAction.fulfillCount == 1 && secondAction.fulfillCount == 1 })
        #expect(firstAction.failCount == 0)
        #expect(secondAction.failCount == 0)
        #expect(endBridge.calls.count == 1)

        let lateAction = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(lateAction, provider: callProvider)

        #expect(lateAction.fulfillCount == 1)
        #expect(lateAction.failCount == 0)
        #expect(endBridge.calls.count == 1)
    }

    @Test
    func roomInfoSubscriptionRemoteLeaveEndsCallKitAndUIExactlyOnce() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)
        let answerAction = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(answerAction, provider: callProvider)
        #expect(await waitUntil { answerAction.fulfillCount == 1 })

        let remoteUserID = "@alice:example.com"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: Self.roomID,
                                                              name: "Room",
                                                              isDirect: true,
                                                              hasOngoingCall: true,
                                                              ownUserID: localUserID))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }
        let roomInfoSubscription = EmbeddedRoomInfoSubscriptionHarness(initialValue: makeRoomInfo(participants: [localUserID, remoteUserID]))
        let localMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$local-membership",
                                                                  roomID: Self.roomID,
                                                                  userID: localUserID,
                                                                  deviceID: "LOCAL_DEVICE",
                                                                  membershipID: "LOCAL_PARTY",
                                                                  isActive: true)
        roomInfoSubscription.install(on: room, initialTimelineItems: [
            localMembership,
            makeMatrixRTCMembershipTimelineItem(eventID: "$remote-membership",
                                                roomID: Self.roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: true)
        ])

        let clientProxy = ClientProxyMock(.init(userID: localUserID, deviceID: "LOCAL_DEVICE"))
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        var endCallCount = 0
        var localTerminationRequestCount = 0
        var startCallCount = 0
        service.actions
            .sink { action in
                switch action {
                case .endCall:
                    endCallCount += 1
                case .requestCallTermination:
                    localTerminationRequestCount += 1
                case .startCall:
                    startCallCount += 1
                case .receivedIncomingCallRequest, .setAudioEnabled:
                    break
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        #expect(await waitUntil { room.subscribeToRoomInfoUpdatesCallsCount == 1 })
        #expect(roomInfoSubscription.subscriptionStartCount == 1)
        #expect(room.infoPublisher.value.activeRoomCallParticipants.count == 2)
        #expect(await roomInfoSubscription.waitForTimelineSubscription())
        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(participants: [localUserID, remoteUserID])))
        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(participants: [localUserID])))
        #expect(await waitUntil {
            self.callProvider.reportCallWithEndedAtReasonCallsCount == 1 &&
                endCallCount == 1 &&
                self.service.ongoingCallRoomIDPublisher.value == nil
        })

        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(participants: [localUserID])))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.uuid == callID)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
        #expect(endCallCount == 1)
        #expect(localTerminationRequestCount == 0)
        #expect(startCallCount == 0)
        #expect(room.subscribeToRoomInfoUpdatesCallsCount == 1)
        #expect(roomInfoSubscription.timelineSubscriptionStartCount == 1)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func roomInfoFirstRemoteLeaveSurvivesSameClientReinjectionAndEndsExactlyOnce() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)
        let answerAction = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(answerAction, provider: callProvider)
        #expect(await waitUntil { answerAction.fulfillCount == 1 })

        let remoteUserID = "@alice:example.com"
        let room = MatrixRTCCallMembershipRoomProxyMock(.init(id: Self.roomID,
                                                              name: "Room",
                                                              isDirect: true,
                                                              hasOngoingCall: true,
                                                              ownUserID: localUserID))
        room.subscribeToCallDeclineEventsRtcNotificationEventIDListenerClosure = { _, _ in
            .failure(.missingTransactionID)
        }
        let roomInfoSubscription = EmbeddedRoomInfoSubscriptionHarness(initialValue: makeRoomInfo(participants: [localUserID, remoteUserID]))
        let localMembership = makeMatrixRTCMembershipTimelineItem(eventID: "$reinjection-local-membership",
                                                                  roomID: Self.roomID,
                                                                  userID: localUserID,
                                                                  deviceID: "LOCAL_DEVICE",
                                                                  membershipID: "LOCAL_PARTY",
                                                                  isActive: true)
        roomInfoSubscription.install(on: room, initialTimelineItems: [
            localMembership,
            makeMatrixRTCMembershipTimelineItem(eventID: "$reinjection-remote-membership",
                                                roomID: Self.roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: true)
        ])

        let clientProxy = ClientProxyMock(.init(userID: localUserID, deviceID: "LOCAL_DEVICE"))
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }
        var endCallCount = 0
        var localTerminationRequestCount = 0
        var startCallCount = 0
        service.actions
            .sink { action in
                switch action {
                case .endCall:
                    endCallCount += 1
                case .requestCallTermination:
                    localTerminationRequestCount += 1
                case .startCall:
                    startCallCount += 1
                case .receivedIncomingCallRequest, .setAudioEnabled:
                    break
                }
            }
            .store(in: &cancellables)

        service.setClientProxy(clientProxy)
        #expect(await waitUntil { room.subscribeToRoomInfoUpdatesCallsCount == 1 })
        #expect(await roomInfoSubscription.waitForTimelineSubscription())
        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(participants: [localUserID, remoteUserID])))

        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(participants: [])))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 0)
        #expect(endCallCount == 0)
        #expect(service.ongoingCallRoomIDPublisher.value == Self.roomID)

        service.setClientProxy(clientProxy)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(room.subscribeToRoomInfoUpdatesCallsCount == 1)
        #expect(roomInfoSubscription.subscriptionStartCount == 1)

        let remoteRemoval = [
            localMembership,
            makeMatrixRTCMembershipTimelineItem(eventID: "$reinjection-remote-membership-empty",
                                                roomID: Self.roomID,
                                                userID: remoteUserID,
                                                deviceID: "REMOTE_DEVICE",
                                                membershipID: "REMOTE_PARTY",
                                                isActive: false)
        ]
        #expect(roomInfoSubscription.receiveSDKTimelineUpdate(remoteRemoval))
        #expect(await waitUntil {
            self.callProvider.reportCallWithEndedAtReasonCallsCount == 1 &&
                endCallCount == 1 &&
                self.service.ongoingCallRoomIDPublisher.value == nil
        })

        #expect(roomInfoSubscription.receiveSDKTimelineUpdate(remoteRemoval))
        #expect(roomInfoSubscription.receiveSDKUpdate(makeRoomInfo(participants: [])))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.uuid == callID)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
        #expect(endCallCount == 1)
        #expect(localTerminationRequestCount == 0)
        #expect(startCallCount == 0)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func remoteTerminalEventReportsCallKitEndedOnce() async throws {
        let endBridge = EndBridgeSpy(result: .terminationAccepted)
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)
        var localTerminationRequestCount = 0
        service.actions
            .sink { action in
                if case .requestCallTermination = action {
                    localTerminationRequestCount += 1
                }
            }
            .store(in: &cancellables)

        service.handleEmbeddedMatrixRTCUpstreamTerminalEvent(callID: callID, source: .embeddedRemoteEnd)
        service.handleEmbeddedMatrixRTCUpstreamTerminalEvent(callID: callID, source: .embeddedRemoteEnd)

        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.uuid == callID)
        #expect(callProvider.reportCallWithEndedAtReasonReceivedArguments?.reason == .remoteEnded)
        #expect(endBridge.calls.isEmpty)
        #expect(localTerminationRequestCount == 0)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func localRemoteRaceCompletesOnceAndIgnoresLateCompletion() async throws {
        let endBridge = EndBridgeSpy(result: .terminationAccepted, delay: .milliseconds(100))
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)

        let action = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(action, provider: callProvider)
        service.handleEmbeddedMatrixRTCUpstreamTerminalEvent(callID: callID, source: .embeddedRemoteEnd)

        #expect(await waitUntil { action.fulfillCount == 1 })
        try? await Task.sleep(for: .milliseconds(150))
        #expect(action.fulfillCount == 1)
        #expect(action.failCount == 0)
        #expect(endBridge.calls.count == 1)
        #expect(callProvider.reportCallWithEndedAtReasonCallsCount == 1)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func endDuringAnswerCancelsAnswerAndTerminatesEmbeddedCall() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented, delay: .milliseconds(100))
        let endBridge = EndBridgeSpy(result: .terminationAccepted)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge,
                                          endBridge: endBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let answerAction = AnswerActionSpy(callUUID: callID)
        let endAction = EndActionSpy(callUUID: callID)
        service.handleAnswerCallAction(answerAction, provider: callProvider)
        service.handleEndCallAction(endAction, provider: callProvider)

        #expect(await waitUntil { answerAction.failCount == 1 && endAction.fulfillCount == 1 })
        #expect(answerAction.fulfillCount == 0)
        #expect(endAction.failCount == 0)
        #expect(answerBridge.calls.count == 1)
        #expect(endBridge.calls.count == 1)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func answerTimeoutFollowedByEndIsIdempotent() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented, delay: .milliseconds(100))
        let endBridge = EndBridgeSpy(result: .terminationAccepted)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(configuration: .init(embeddedMatrixRTCAnswerBridgeEnabled: true,
                                                               answerTimeout: .milliseconds(10),
                                                               endTimeout: .seconds(1)),
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge,
                                          endBridge: endBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: callID)

        let answerAction = AnswerActionSpy(callUUID: callID)
        service.handleAnswerCallAction(answerAction, provider: callProvider)

        #expect(await waitUntil { answerAction.failCount == 1 })

        let endAction = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(endAction, provider: callProvider)

        #expect(endAction.failCount == 1)
        #expect(endAction.fulfillCount == 0)
        #expect(endBridge.calls.isEmpty)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func providerResetReleasesEndGuardAndBootstrap() async throws {
        let endBridge = EndBridgeSpy(result: .terminationAccepted, delay: .milliseconds(100))
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)

        let action = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(action, provider: callProvider)
        service.providerDidReset(CXProvider(configuration: CXProviderConfiguration()))

        #expect(await waitUntil { action.failCount == 1 })
        try? await Task.sleep(for: .milliseconds(150))
        #expect(action.fulfillCount == 0)
        #expect(action.failCount == 1)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func endBootstrapUUIDMismatchFailsClosed() async throws {
        let endBridge = EndBridgeSpy(result: .terminationAccepted)
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge,
                                                          bootstrapCallID: UUID())

        let action = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(action, provider: callProvider)

        #expect(action.failCount == 1)
        #expect(action.fulfillCount == 0)
        #expect(endBridge.calls.isEmpty)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func missingBootstrapFailsEndClosed() async throws {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        let endBridge = EndBridgeSpy(result: .terminationAccepted)
        let bootstrapResolver = BootstrapResolverSpy()
        service = makeAnswerBridgeService(bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge,
                                          endBridge: endBridge)

        let callID = try await reportIncomingCall()
        await service.setupCallSession(roomID: Self.roomID, roomDisplayName: "welcome", startMode: .audio)

        let action = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(action, provider: callProvider)

        #expect(action.failCount == 1)
        #expect(action.fulfillCount == 0)
        #expect(endBridge.calls.isEmpty)
    }

    @Test
    func noActiveMatrixRTCCallFailsEndClosed() async throws {
        let endBridge = EndBridgeSpy(result: .noActiveMatrixRTCCall)
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)

        let action = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        #expect(action.fulfillCount == 0)
        #expect(endBridge.calls.count == 1)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    @Test
    func endTimeoutFailsOnceAndIgnoresLateCompletion() async throws {
        let endBridge = EndBridgeSpy(result: .terminationAccepted, delay: .milliseconds(100))
        let bootstrapResolver = BootstrapResolverSpy()
        let callID = try await prepareOngoingEmbeddedCall(configuration: .init(embeddedMatrixRTCAnswerBridgeEnabled: true,
                                                                               answerTimeout: .seconds(1),
                                                                               endTimeout: .milliseconds(10)),
                                                          bootstrapResolver: bootstrapResolver,
                                                          endBridge: endBridge)

        let action = EndActionSpy(callUUID: callID)
        service.handleEndCallAction(action, provider: callProvider)

        #expect(await waitUntil { action.failCount == 1 })
        try? await Task.sleep(for: .milliseconds(150))
        #expect(action.failCount == 1)
        #expect(action.fulfillCount == 0)
        #expect(endBridge.calls.count == 1)
        #expect(bootstrapResolver.removedCallIDs == [callID])
    }

    private func makeAnswerBridgeService(configuration: SalemXEmbeddedCallAnswerBridgeConfiguration = .init(embeddedMatrixRTCAnswerBridgeEnabled: true,
                                                                                                            answerTimeout: .seconds(1)),
                                         bootstrapResolver: BootstrapResolverSpy,
                                         answerBridge: AnswerBridgeSpy,
                                         endBridge: EndBridgeSpy? = nil,
                                         timeProvider: TimeProvider? = nil,
                                         applicationActivityProvider: ApplicationActivityProvider? = nil) -> ElementCallService {
        ElementCallService(appSettings: appSettings,
                           callProvider: callProvider,
                           timeProvider: timeProvider ?? TimeProvider(clock: ContinuousClock()) { self.currentDate },
                           applicationActivityProvider: applicationActivityProvider ?? ApplicationActivityProvider(isActive: { true },
                                                                                                                   didBecomeActivePublisher: Empty().eraseToAnyPublisher()),
                           salemXAnswerBridgeConfiguration: configuration,
                           salemXIncomingCallBootstrapResolver: bootstrapResolver,
                           salemXAnswerBridge: answerBridge,
                           salemXEndBridge: endBridge)
    }

    private func prepareOngoingEmbeddedCall(configuration: SalemXEmbeddedCallAnswerBridgeConfiguration = .init(embeddedMatrixRTCAnswerBridgeEnabled: true,
                                                                                                               answerTimeout: .seconds(1),
                                                                                                               endTimeout: .seconds(1)),
                                            bootstrapResolver: BootstrapResolverSpy,
                                            endBridge: EndBridgeSpy,
                                            bootstrapCallID: UUID? = nil) async throws -> UUID {
        let answerBridge = AnswerBridgeSpy(result: .alreadyPresented)
        service = makeAnswerBridgeService(configuration: configuration,
                                          bootstrapResolver: bootstrapResolver,
                                          answerBridge: answerBridge,
                                          endBridge: endBridge)

        let callID = try await reportIncomingCall()
        bootstrapResolver.bootstrapByCallID[callID] = verifiedBootstrap(callID: bootstrapCallID ?? callID)
        await service.setupCallSession(roomID: Self.roomID, roomDisplayName: "welcome", startMode: .audio)
        return callID
    }

    private func reportIncomingCall(startMode: ElementCallStartMode = .video) async throws -> UUID {
        let payload = Stage2DPKPushPayloadMock().updatingExpiration(currentDate, lifetime: 30)
        if startMode == .audio {
            payload.settingCallIntent("audio")
        }
        await confirmation { confirmation in
            service.pushRegistry(pushRegistry, didReceiveIncomingPushWith: payload, for: .voIP) {
                confirmation()
            }
        }
        return try #require(callProvider.reportNewIncomingCallWithUpdateCompletionReceivedArguments?.uuid)
    }

    private func verifiedBootstrap(callID: UUID,
                                   roomID: String? = nil) -> VerifiedIncomingCallBootstrap {
        let roomID = roomID ?? Self.roomID
        return .init(callID: callID,
                     claimedMetadata: .init(roomID: roomID,
                                            localUserID: localUserID,
                                            peerUserID: "@alice:example.com",
                                            peerDeviceID: "ALICEDEVICE",
                                            direction: .incoming),
                     localDeviceID: "DEVICEID",
                     activeCallState: .active)
    }

    private func makeRoomInfo(participants: [String]) -> RoomInfoProxyProtocol {
        let info = RoomInfoProxyMock()
        info.id = Self.roomID
        info.isEncrypted = true
        info.isDirect = true
        info.isSpace = false
        info.isFavourite = false
        info.membership = .joined
        info.activeMembersCount = 2
        info.invitedMembersCount = 0
        info.joinedMembersCount = 2
        info.highlightCount = 0
        info.notificationCount = 0
        info.hasRoomCall = true
        info.activeRoomCallParticipants = participants
        info.isMarkedUnread = false
        info.unreadMessagesCount = 0
        info.unreadNotificationsCount = 0
        info.unreadMentionsCount = 0
        info.pinnedEventIDs = []
        info.historyVisibility = .shared
        return info
    }

    private func configureLiveTimeline(for room: JoinedRoomProxyMock) {
        guard let timelineProxy = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timelineProxy.timelineItemProvider as? TimelineItemProviderMock else {
            return
        }

        let timelineUpdates = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>(([], .initial))
        timelineItemProvider.itemProxies = []
        timelineItemProvider.updatePublisher = timelineUpdates.eraseToAnyPublisher()
        timelineItemProvider.paginationState = .initial
        timelineItemProvider.kind = .live
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async -> Bool {
        for _ in 0..<30 {
            if condition() {
                return true
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        return false
    }

    static let roomID = "!room:example.com"
}

@MainActor
private final class EmbeddedRoomInfoSubscriptionHarness {
    private let subject: CurrentValueSubject<RoomInfoProxyProtocol, Never>
    private var timelineSubject: CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>?
    private weak var timelineItemProvider: TimelineItemProviderMock?
    private weak var rawMembershipRoom: MatrixRTCCallMembershipRoomProxyMock?
    private(set) var subscriptionStartCount = 0
    private(set) var timelineSubscriptionStartCount = 0

    init(initialValue: RoomInfoProxyProtocol) {
        subject = .init(initialValue)
    }

    func install(on room: JoinedRoomProxyMock, initialTimelineItems: [TimelineItemProxy]) {
        room.infoPublisher = subject.asCurrentValuePublisher()
        room.subscribeToRoomInfoUpdatesClosure = { [weak self] in
            self?.subscriptionStartCount += 1
        }
        if let rawMembershipRoom = room as? MatrixRTCCallMembershipRoomProxyMock {
            self.rawMembershipRoom = rawMembershipRoom
            rawMembershipRoom.initialRawMembershipState = initialTimelineItems
        }
        guard let timeline = room.timeline as? TimelineProxyMock,
              let timelineItemProvider = timeline.timelineItemProvider as? TimelineItemProviderMock else { return }
        let timelineSubject = CurrentValueSubject<([TimelineItemProxy], TimelinePaginationState), Never>((initialTimelineItems, .initial))
        self.timelineSubject = timelineSubject
        self.timelineItemProvider = timelineItemProvider
        timelineItemProvider.itemProxies = initialTimelineItems
        timelineItemProvider.updatePublisher = timelineSubject.eraseToAnyPublisher()
        timelineItemProvider.kind = .live
        timeline.subscribeForUpdatesClosure = { [weak self] in
            guard let self, timelineSubscriptionStartCount == 0 else { return }
            timelineSubscriptionStartCount += 1
        }
    }

    func waitForTimelineSubscription() async -> Bool {
        for _ in 0..<30 {
            if timelineSubscriptionStartCount == 1,
               rawMembershipRoom?.rawMembershipObservationStartCount == 1 {
                return true
            }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return false
    }

    @discardableResult
    func receiveSDKUpdate(_ roomInfo: RoomInfoProxyProtocol) -> Bool {
        guard subscriptionStartCount > 0 else {
            return false
        }

        subject.send(roomInfo)
        return true
    }

    func receiveSDKTimelineUpdate(_ items: [TimelineItemProxy]) -> Bool {
        guard timelineSubscriptionStartCount > 0,
              let timelineSubject,
              let timelineItemProvider,
              rawMembershipRoom?.receiveRawMembershipState(items) == true else { return false }
        timelineItemProvider.itemProxies = items
        timelineSubject.send((items, .initial))
        return true
    }

    func receiveSDKRawMembershipUpdate(_ items: [TimelineItemProxy]) -> Bool {
        rawMembershipRoom?.receiveRawMembershipState(items) ?? false
    }
}

private class Stage2DPKPushPayloadMock: PKPushPayload {
    var dict: [AnyHashable: Any] = [:]

    override init() {
        dict[ElementCallServiceNotificationKey.roomID.rawValue] = SalemXEmbeddedCallAnswerBridgeServiceTests.roomID
        dict[ElementCallServiceNotificationKey.roomDisplayName.rawValue] = "welcome"
        dict[ElementCallServiceNotificationKey.rtcNotifyEventID.rawValue] = "$000"
        dict[ElementCallServiceNotificationKey.expirationDate.rawValue] = Date(timeIntervalSince1970: 10)
    }

    override var dictionaryPayload: [AnyHashable: Any] {
        dict
    }

    func updatingExpiration(_ from: Date, lifetime: TimeInterval) -> Self {
        dict[ElementCallServiceNotificationKey.expirationDate.rawValue] = from.addingTimeInterval(lifetime)
        return self
    }

    func settingCallIntent(_ callIntent: String) {
        dict[ElementCallServiceNotificationKey.callIntent.rawValue] = callIntent
    }
}

private final class AnswerActionSpy: SalemXCallKitAnswerActionCompleting {
    let callUUID: UUID
    private(set) var fulfillCount = 0
    private(set) var failCount = 0

    init(callUUID: UUID) {
        self.callUUID = callUUID
    }

    func fulfill() {
        fulfillCount += 1
    }

    func fail() {
        failCount += 1
    }
}

private final class EndActionSpy: SalemXCallKitEndActionCompleting {
    let callUUID: UUID
    private(set) var fulfillCount = 0
    private(set) var failCount = 0

    init(callUUID: UUID) {
        self.callUUID = callUUID
    }

    func fulfill() {
        fulfillCount += 1
    }

    func fail() {
        failCount += 1
    }
}

private final class BootstrapResolverSpy: SalemXIncomingCallBootstrapResolving {
    var bootstrapByCallID = [UUID: VerifiedIncomingCallBootstrap]()
    private(set) var requestedCallIDs = [UUID]()
    private(set) var removedCallIDs = [UUID]()

    func verifiedBootstrap(for callID: UUID) -> VerifiedIncomingCallBootstrap? {
        requestedCallIDs.append(callID)
        return bootstrapByCallID[callID]
    }

    func removeVerifiedBootstrap(for callID: UUID) {
        removedCallIDs.append(callID)
        bootstrapByCallID.removeValue(forKey: callID)
    }
}

@MainActor
private final class EndBridgeSpy: SalemXEmbeddedCallEndBridging {
    struct Call: Equatable {
        let callID: UUID
        let bootstrap: VerifiedIncomingCallBootstrap
        let source: SalemXEmbeddedCallEndSource
    }

    private let result: SalemXEmbeddedCallEndResult
    private let delay: Duration?
    private(set) var calls = [Call]()

    init(result: SalemXEmbeddedCallEndResult, delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }

    func end(callID: UUID,
             bootstrap: VerifiedIncomingCallBootstrap,
             source: SalemXEmbeddedCallEndSource) async -> SalemXEmbeddedCallEndResult {
        calls.append(.init(callID: callID, bootstrap: bootstrap, source: source))
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return result
    }
}

@MainActor
private final class AnswerBridgeSpy: SalemXEmbeddedCallAnswerBridging {
    struct Call: Equatable {
        let callID: UUID
        let bootstrap: VerifiedIncomingCallBootstrap
    }

    private let result: SalemXEmbeddedCallAnswerResult
    private let delay: Duration?
    private(set) var calls = [Call]()

    init(result: SalemXEmbeddedCallAnswerResult, delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }

    func answer(callID: UUID, bootstrap: VerifiedIncomingCallBootstrap) async -> SalemXEmbeddedCallAnswerResult {
        calls.append(.init(callID: callID, bootstrap: bootstrap))
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return result
    }
}
