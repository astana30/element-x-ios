//
// Copyright 2026 Element Creations Ltd.
// Copyright 2026 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Foundation
import Testing
import WebKit

@MainActor
final class CallScreenViewModelTests {
    @Test
    func lifecycleBindingRejectsStaleCoordinatorAndPreservesActiveConsumer() async throws {
        let harness = try makeAudioRoomCallViewModel()
        await waitFor { harness.viewModel.context.viewState.url != nil }
        var registrations = [@MainActor () -> Void]()
        let scheduler: CallView.Coordinator.RegistrationScheduler = { registration in
            registrations.append(registration)
        }

        let firstCoordinator = CallView.Coordinator(viewModelContext: harness.viewModel.context,
                                                    registrationScheduler: scheduler)
        let secondCoordinator = CallView.Coordinator(viewModelContext: harness.viewModel.context,
                                                     registrationScheduler: scheduler)

        #expect(firstCoordinator.webViewID != secondCoordinator.webViewID)
        #expect(ObjectIdentifier(firstCoordinator.lifecycleProbeWebView) != ObjectIdentifier(secondCoordinator.lifecycleProbeWebView))

        secondCoordinator.loadLifecycleProbeDocument(Self.lifecycleProbeDocument(marker: "active", consumerMounted: true))
        await waitUntilLoaded(secondCoordinator.lifecycleProbeWebView)
        await waitFor { registrations.count == 1 }
        firstCoordinator.loadLifecycleProbeDocument(Self.lifecycleProbeDocument(marker: "stale", consumerMounted: false))
        await waitUntilLoaded(firstCoordinator.lifecycleProbeWebView)
        await waitFor { registrations.count == 2 }

        registrations[0]()
        registrations[1]()

        #expect(firstCoordinator.documentGeneration != secondCoordinator.documentGeneration)

        CallView.dismantleUIView(firstCoordinator.webViewWrapper, coordinator: firstCoordinator)

        let activeIdentity = try #require(harness.viewModel.activeCallWebViewIdentity)
        let marker = try #require(try await harness.viewModel.evaluateActiveCallWebViewJavaScript("window.lifecycleMarker") as? String)
        let consumerMounted = try await harness.viewModel.evaluateActiveCallWebViewJavaScript("window.activeCallConsumerMounted") as? Bool

        #expect(activeIdentity.webViewID == secondCoordinator.webViewID)
        #expect(activeIdentity.documentGeneration == secondCoordinator.documentGeneration)
        #expect(activeIdentity.sessionIdentity == harness.viewModel.context.viewState.webViewSessionIdentity)
        #expect(activeIdentity.sessionIdentity.sessionGeneration == harness.viewModel.context.viewState.webViewSessionIdentity.sessionGeneration)
        #expect(marker == "active")
        #expect(consumerMounted == true)

        let secondLoadCount = secondCoordinator.loadCount
        CallView.updateCoordinator(secondCoordinator, url: URL(string: "about:blank"))
        #expect(secondCoordinator.loadCount == secondLoadCount)

        let mismatchedSessionIdentity = CallWebViewSessionIdentity(roomID: "redacted-other-room")
        let mismatchedWebViewID = UUID()
        let mismatchedIdentity = CallWebViewDocumentIdentity(webViewID: mismatchedWebViewID,
                                                             documentGeneration: UUID(),
                                                             sessionIdentity: mismatchedSessionIdentity)
        harness.viewModel.context.send(viewAction: .callWebViewCreated(webViewID: mismatchedWebViewID,
                                                                       sessionIdentity: mismatchedSessionIdentity))
        harness.viewModel.context.send(viewAction: .callWebViewDocumentLoading(mismatchedIdentity))
        harness.viewModel.context.send(viewAction: .callWebViewBindingReady(.init(identity: mismatchedIdentity,
                                                                                  javaScriptEvaluator: { _ in "mismatched" },
                                                                                  requestPictureInPictureHandler: nil)))
        #expect(harness.viewModel.activeCallWebViewIdentity == activeIdentity)
        #expect(harness.widgetDriver.startBaseURLClientIDColorSchemeRageshakeURLAnalyticsConfigurationCallsCount == 1)

        CallView.dismantleUIView(secondCoordinator.webViewWrapper, coordinator: secondCoordinator)
        #expect(harness.viewModel.activeCallWebViewIdentity == nil)
        harness.viewModel.stop()
    }

    @Test
    func delayedStaleEvaluationCannotTerminateNewDocumentSession() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        var delayedEvaluation: CheckedContinuation<Any?, Never>?
        var dismissCount = 0
        let actionsCancellable = harness.viewModel.actions.sink { action in
            if case .dismiss = action {
                dismissCount += 1
            }
        }

        let firstIdentity = installActiveWebViewBinding(in: harness) { script in
            evaluatedScripts.append(script)
            guard script.contains("im.vector.hangup") else {
                return true
            }

            return await withCheckedContinuation { continuation in
                delayedEvaluation = continuation
            }
        }

        harness.viewModel.context.send(viewAction: .endCall)
        await waitFor { delayedEvaluation != nil }

        let loadingIdentity = CallWebViewDocumentIdentity(webViewID: firstIdentity.webViewID,
                                                          documentGeneration: UUID(),
                                                          sessionIdentity: firstIdentity.sessionIdentity)
        harness.viewModel.context.send(viewAction: .callWebViewDocumentLoading(loadingIdentity))
        #expect(harness.viewModel.activeCallWebViewIdentity == nil)

        delayedEvaluation?.resume(returning: true)
        delayedEvaluation = nil
        try await Task.sleep(for: .milliseconds(100))

        #expect(dismissCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)
        #expect(evaluatedScripts.count { $0.contains("im.vector.hangup") } == 1)

        installActiveWebViewBinding(in: harness) { script in
            evaluatedScripts.append(script)
            return true
        }
        harness.viewModel.context.send(viewAction: .endCall)
        await waitFor {
            evaluatedScripts.count { $0.contains("im.vector.hangup") } == 2
        }

        harness.elementCallServiceActions.send(.requestCallTermination(roomID: harness.roomProxy.id))
        try await Task.sleep(for: .milliseconds(50))
        #expect(evaluatedScripts.count { $0.contains("im.vector.hangup") } == 2)
        #expect(dismissCount == 0)

        await completeMatrixRTCHangup(in: harness)
        await waitFor {
            dismissCount == 1 && harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1
        }

        #expect(harness.widgetDriver.startBaseURLClientIDColorSchemeRageshakeURLAnalyticsConfigurationCallsCount == 1)
        harness.viewModel.stop()
        withExtendedLifetime(actionsCancellable) { }
    }

    @Test
    func elementCallWebMediaDiagnosticsPayloadDescriptionIsRedacted() throws {
        let json = """
        {
            "schemaVersion": 1,
            "stage": "interval",
            "elapsedBucket": "under_10s",
            "videoElementCount": 2,
            "visibleVideoElementCount": 2,
            "playingVideoElementCount": 1,
            "streamBackedVideoElementCount": 2,
            "mutedVideoElementCount": 1,
            "ignored": "opaque-private-value"
        }
        """

        let payload = try #require(ElementCallWebMediaDiagnosticsPayload.decode(message: json))

        #expect(payload.hasRemoteRendererCandidate)
        #expect(payload.description.contains("videos=2"))
        #expect(payload.description.contains("remote_renderer_candidate=true"))
        #expect(!payload.description.contains("opaque-private-value"))
    }

    @Test
    func elementCallWebMediaDiagnosticsPayloadRejectsUnsupportedSchema() {
        let json = """
        {
            "schemaVersion": 2,
            "stage": "interval",
            "elapsedBucket": "under_10s",
            "videoElementCount": 1
        }
        """

        #expect(ElementCallWebMediaDiagnosticsPayload.decode(message: json) == nil)
    }

    @Test
    func elementCallWebMediaDiagnosticsPayloadClampsCounts() throws {
        let json = """
        {
            "schemaVersion": 1,
            "stage": "interval",
            "elapsedBucket": "under_10s",
            "videoElementCount": 120,
            "visibleVideoElementCount": -1,
            "playingVideoElementCount": 1,
            "streamBackedVideoElementCount": 1,
            "mutedVideoElementCount": 0
        }
        """

        let payload = try #require(ElementCallWebMediaDiagnosticsPayload.decode(message: json))

        #expect(payload.videoElementCount == 99)
        #expect(payload.visibleVideoElementCount == 0)
        #expect(!payload.hasRemoteRendererCandidate)
    }

    @Test
    func elementCallRTCTransportDiagnosticsPayloadAcceptsOnlyRedactedContract() throws {
        let request = try #require(ElementCallRTCTransportDiagnosticsPayload.decode(message: """
        {"schemaVersion":1,"kind":"rtc_transport","stage":"request","ignored":"opaque-private-value"}
        """))
        #expect(request.stage == .request)
        #expect(request.httpStatus == nil)

        let response = try #require(ElementCallRTCTransportDiagnosticsPayload.decode(message: """
        {"schemaVersion":1,"kind":"rtc_transport","stage":"response","httpStatus":200}
        """))
        #expect(response.stage == .response)
        #expect(response.httpStatus == 200)

        #expect(ElementCallRTCTransportDiagnosticsPayload.decode(message: """
        {"schemaVersion":1,"kind":"other","stage":"request"}
        """) == nil)
    }

    @Test
    func elementCallRTCTransportRequestBoundarySeparatesAuthorizationFromCredentialObservation() throws {
        let homeserverURL = try #require(URL(string: "https://matrix.example"))

        for path in ElementCallRTCTransportRequestBoundary.authorizationPaths {
            let requestURL = try #require(URL(string: path, relativeTo: homeserverURL)?.absoluteURL)
            let policy = ElementCallRTCTransportRequestBoundary.policy(for: requestURL, homeserverURL: homeserverURL)
            #expect(policy.shouldAuthorize)
            #expect(!policy.shouldObserveCredentials)
        }

        for path in ElementCallRTCTransportRequestBoundary.credentialObservationPaths {
            let requestURL = try #require(URL(string: path, relativeTo: homeserverURL)?.absoluteURL)
            let policy = ElementCallRTCTransportRequestBoundary.policy(for: requestURL, homeserverURL: homeserverURL)
            #expect(!policy.shouldAuthorize)
            #expect(policy.shouldObserveCredentials)
        }

        let crossOriginURL = try #require(URL(string: "https://sfu.example/livekit/jwt/get_token"))
        let crossOriginPolicy = ElementCallRTCTransportRequestBoundary.policy(for: crossOriginURL, homeserverURL: homeserverURL)
        #expect(!crossOriginPolicy.shouldAuthorize)
        #expect(!crossOriginPolicy.shouldObserveCredentials)

        let nestedPathURL = try #require(URL(string: "/livekit/jwt/get_token/extra", relativeTo: homeserverURL)?.absoluteURL)
        let nestedPathPolicy = ElementCallRTCTransportRequestBoundary.policy(for: nestedPathURL, homeserverURL: homeserverURL)
        #expect(!nestedPathPolicy.shouldAuthorize)
        #expect(!nestedPathPolicy.shouldObserveCredentials)
    }

    @Test
    func audioRoomCallRecordsRTCTransportCredentialRequestAndResponse() async throws {
        let harness = try makeAudioRoomCallViewModel()

        setenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE", "1", 1)
        defer { unsetenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE") }

        let clearURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/clear"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        harness.viewModel.context.send(viewAction: .elementCallMediaDiagnostics(message: """
        {"schemaVersion":1,"kind":"rtc_transport","stage":"request"}
        """))
        await waitFor {
            (try? self.stage2FSimulatorProofText().contains("receiver_matrixrtc_credentials_requested=true")) == true
        }

        var proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_matrixrtc_credentials_2xx=false"))
        #expect(proof.contains("receiver_matrixrtc_credentials_http_bucket=pending"))

        harness.viewModel.context.send(viewAction: .elementCallMediaDiagnostics(message: """
        {"schemaVersion":1,"kind":"rtc_transport","stage":"response","httpStatus":200}
        """))
        await waitFor {
            (try? self.stage2FSimulatorProofText().contains("receiver_matrixrtc_credentials_2xx=true")) == true
        }

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_matrixrtc_credentials_http_bucket=2xx"))

        harness.viewModel.context.send(viewAction: .elementCallMediaDiagnostics(message: """
        {"schemaVersion":1,"kind":"rtc_transport","stage":"response","httpStatus":503}
        """))
        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_matrixrtc_credentials_2xx=true"))
        #expect(proof.contains("receiver_matrixrtc_credentials_http_bucket=2xx"))

        harness.viewModel.stop()
    }

    @Test
    func directAudioChromeEndCallWaitsForMatrixRTCTermination() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        var dismissCount = 0
        let actionsCancellable = harness.viewModel.actions.sink { action in
            if case .dismiss = action {
                dismissCount += 1
            }
        }
        installActiveWebViewBinding(in: harness) { script in
            evaluatedScripts.append(script)
            return true
        }

        let callScreen = CallScreen(context: harness.viewModel.context)
        callScreen.endCall()
        await waitFor {
            evaluatedScripts.contains { $0.contains("im.vector.hangup") }
        }

        #expect(evaluatedScripts.count { $0.contains("im.vector.hangup") } == 1)
        #expect(evaluatedScripts.count { $0.contains("querySelectorAll(\"audio, video\")") } == 0)
        #expect(dismissCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)

        harness.elementCallServiceActions.send(.requestCallTermination(roomID: harness.roomProxy.id))
        try await Task.sleep(for: .milliseconds(50))
        #expect(evaluatedScripts.count { $0.contains("im.vector.hangup") } == 1)
        #expect(dismissCount == 0)

        await completeMatrixRTCHangup(in: harness)
        await waitFor {
            dismissCount == 1 && harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1
        }
        await waitFor {
            evaluatedScripts.contains { $0.contains("querySelectorAll(\"audio, video\")") }
        }

        #expect(evaluatedScripts.count { $0.contains("querySelectorAll(\"audio, video\")") } == 1)
        harness.viewModel.stop()
        withExtendedLifetime(actionsCancellable) { }
    }

    @Test
    func unmatchedTerminationActionDoesNotEndActiveRoomCall() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        var dismissCount = 0
        let actionsCancellable = harness.viewModel.actions.sink { action in
            if case .dismiss = action {
                dismissCount += 1
            }
        }
        installActiveWebViewBinding(in: harness) { script in
            evaluatedScripts.append(script)
            return true
        }

        harness.elementCallServiceActions.send(.requestCallTermination(roomID: "unmatched-room"))
        try await Task.sleep(for: .milliseconds(50))

        #expect(evaluatedScripts.isEmpty)
        #expect(dismissCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)

        let callScreen = CallScreen(context: harness.viewModel.context)
        callScreen.endCall()
        await waitFor {
            evaluatedScripts.contains { $0.contains("im.vector.hangup") }
        }
        await completeMatrixRTCHangup(in: harness)
        await waitFor {
            dismissCount == 1 && harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1
        }

        harness.viewModel.stop()
        withExtendedLifetime(actionsCancellable) { }
    }

    @Test
    func roomCallEndCallPostsHostHangupDirectlyToWidgetAndRequestsMatrixTermination() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        var dismissCount = 0
        let actionsCancellable = harness.viewModel.actions.sink { action in
            if case .dismiss = action {
                dismissCount += 1
            }
        }
        installActiveWebViewBinding(in: harness) { script in
            evaluatedScripts.append(script)
            return true
        }

        harness.viewModel.context.send(viewAction: .endCall)
        await waitFor {
            evaluatedScripts.contains { $0.contains("im.vector.hangup") }
        }

        let hangupScript = try #require(evaluatedScripts.first { $0.contains("im.vector.hangup") })
        let payload = try widgetMessage(from: hangupScript)

        #expect(payload.direction == .toWidget)
        #expect(payload.action == .hangup)
        #expect(evaluatedScripts.count { $0.contains("im.vector.hangup") } == 1)
        #expect(harness.widgetDriver.handleMessageCallsCount == 0)
        #expect(dismissCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)

        var mismatchedPayload = payload
        mismatchedPayload.requestId = "mismatched-request"
        try harness.viewModel.context.send(viewAction: .widgetAction(message: widgetResponse(for: mismatchedPayload)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(dismissCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)

        try harness.viewModel.context.send(viewAction: .widgetAction(message: widgetResponse(for: payload)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(dismissCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)

        let leaveRequestID = "membership-leave"
        harness.viewModel.context.send(viewAction: .widgetAction(message: matrixRTCMembershipLeaveRequest(requestID: leaveRequestID)))
        await waitFor { harness.widgetDriver.handleMessageCallsCount == 1 }
        #expect(dismissCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)

        harness.widgetDriver.messagePublisher.send(matrixRTCMembershipLeaveResponse(requestID: "mismatched-request"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(dismissCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)

        harness.widgetDriver.messagePublisher.send(matrixRTCMembershipLeaveResponse(requestID: leaveRequestID))
        await waitFor {
            dismissCount == 1 && harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1
        }
        #expect(harness.elementCallService.requestCallTerminationRoomIDReceivedRoomID == harness.roomProxy.id)

        harness.viewModel.stop()
        withExtendedLifetime(actionsCancellable) { }
    }

    @Test
    func roomCallEndCallResetsEmbeddedWebContentForRepeatCall() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        installActiveWebViewBinding(in: harness) { script in
            evaluatedScripts.append(script)
            return true
        }

        harness.viewModel.context.send(viewAction: .endCall)
        await waitFor {
            evaluatedScripts.contains { $0.contains("im.vector.hangup") }
        }

        #expect(evaluatedScripts.count { $0.contains("querySelectorAll(\"audio, video\")") } == 0)
        #expect(evaluatedScripts.count { $0.contains("im.vector.hangup") } == 1)

        harness.viewModel.context.send(viewAction: .endCall)
        try await Task.sleep(for: .milliseconds(100))

        #expect(evaluatedScripts.count == 1)
        #expect(harness.widgetDriver.handleMessageCallsCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)

        let hangupScript = try #require(evaluatedScripts.first { $0.contains("im.vector.hangup") })
        let payload = try widgetMessage(from: hangupScript)
        try harness.viewModel.context.send(viewAction: .widgetAction(message: widgetResponse(for: payload)))
        await completeMatrixRTCHangup(in: harness)
        await waitFor {
            harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1
        }
        await waitFor {
            evaluatedScripts.contains { $0.contains("querySelectorAll(\"audio, video\")") }
        }

        let resetScript = try #require(evaluatedScripts.first { $0.contains("querySelectorAll(\"audio, video\")") })
        #expect(resetScript.contains("querySelectorAll(\"audio, video\")"))
        #expect(resetScript.contains("track.stop()"))
        #expect(resetScript.contains("srcObject = null"))
        #expect(resetScript.contains("window.stop()"))
        #expect(evaluatedScripts.count { $0.contains("querySelectorAll(\"audio, video\")") } == 1)

        harness.viewModel.stop()
    }

    @Test
    func roomCallStopResetsEmbeddedWebContentAndTearsDownCallSession() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        installActiveWebViewBinding(in: harness) { script in
            evaluatedScripts.append(script)
            return true
        }

        harness.viewModel.stop()
        await waitFor {
            evaluatedScripts.contains { $0.contains("querySelectorAll(\"audio, video\")") } &&
                evaluatedScripts.contains { $0.contains("im.vector.hangup") }
        }

        let resetScript = try #require(evaluatedScripts.first { $0.contains("querySelectorAll(\"audio, video\")") })
        #expect(resetScript.contains("querySelectorAll(\"audio, video\")"))
        #expect(resetScript.contains("srcObject = null"))
        #expect(evaluatedScripts.count { $0.contains("querySelectorAll(\"audio, video\")") } == 1)
        #expect(evaluatedScripts.count { $0.contains("im.vector.hangup") } == 1)
        #expect(harness.elementCallService.tearDownCallSessionCalled)
        #expect(harness.widgetDriver.handleMessageCallsCount == 0)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 0)

        let hangupScript = try #require(evaluatedScripts.first { $0.contains("im.vector.hangup") })
        let payload = try widgetMessage(from: hangupScript)
        try harness.viewModel.context.send(viewAction: .widgetAction(message: widgetResponse(for: payload)))
        await completeMatrixRTCHangup(in: harness)
        await waitFor {
            harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1
        }
    }

    @Test
    func roomCallJoinActionAcknowledgesWebAndForwardsToWidgetDriver() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        installActiveWebViewBinding(in: harness) { script in
            evaluatedScripts.append(script)
            return true
        }

        setenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE", "1", 1)
        defer { unsetenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE") }

        let clearURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/clear"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        let joinMessage = """
        {"api":"fromWidget","action":"io.element.join","widgetId":"call-widget","requestId":"join-request","data":{}}
        """

        harness.viewModel.context.send(viewAction: .widgetAction(message: joinMessage))
        await waitFor {
            harness.widgetDriver.handleMessageCallsCount == 1 && !evaluatedScripts.isEmpty
        }

        #expect(harness.widgetDriver.handleMessageReceivedMessage == joinMessage)
        #expect(evaluatedScripts.count == 1)
        #expect(evaluatedScripts[0].contains("\"requestId\":\"join-request\""))
        #expect(evaluatedScripts[0].contains("\"response\""))

        var proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_widget_join_received=true"))
        #expect(proof.contains("receiver_widget_join_acknowledged=true"))
        #expect(proof.contains("receiver_widget_join_driver_response_received=false"))
        #expect(proof.contains("receiver_widget_join_dispatch_attempted=true"))
        #expect(proof.contains("receiver_widget_join_dispatch_completed=true"))
        #expect(proof.contains("receiver_widget_join_dispatch_error_bucket=none"))
        #expect(proof.contains("receiver_membership_send_marker_semantics=widget_driver_dispatch_only"))
        #expect(proof.contains("receiver_membership_send_attempted=true"))
        #expect(proof.contains("receiver_membership_send_completed=true"))
        #expect(proof.contains("receiver_membership_send_error_bucket=none"))
        #expect(proof.contains("receiver_membership_state_send_attempted=false"))
        #expect(proof.contains("receiver_membership_state_send_completed=false"))
        #expect(proof.contains("receiver_membership_state_send_http_bucket=not_requested"))
        #expect(proof.contains("receiver_membership_present_on_synapse=false"))

        let mismatchedDriverResponse = """
        {"api":"fromWidget","action":"io.element.join","widgetId":"call-widget","requestId":"stale-request","response":{"error":{"message":"unsupported"}}}
        """
        harness.widgetDriver.messagePublisher.send(mismatchedDriverResponse)
        await waitFor { evaluatedScripts.count == 2 }

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_widget_join_driver_response_received=false"))

        let matchingDriverResponse = """
        {"api":"fromWidget","action":"io.element.join","widgetId":"call-widget","requestId":"join-request","response":{"error":{"message":"unsupported"}}}
        """
        harness.widgetDriver.messagePublisher.send(matchingDriverResponse)
        await waitFor { evaluatedScripts.count == 3 }

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_widget_join_driver_response_received=true"))

        let delayedMembershipMessage = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"delayed-membership","data":{"type":"org.matrix.msc3401.call.member","state_key":"redacted-state","content":{},"delay":8000}}
        """
        harness.viewModel.context.send(viewAction: .widgetAction(message: delayedMembershipMessage))
        await waitFor { harness.widgetDriver.handleMessageCallsCount == 2 }

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_membership_state_send_attempted=false"))

        let membershipMessage = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"current-membership","data":{"type":"org.matrix.msc3401.call.member","state_key":"redacted-state","content":{"m.calls":[{}]}}}
        """
        harness.viewModel.context.send(viewAction: .widgetAction(message: membershipMessage))
        await waitFor { harness.widgetDriver.handleMessageCallsCount == 3 }

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_membership_state_send_attempted=true"))
        #expect(proof.contains("receiver_membership_state_send_completed=false"))

        let staleMembershipResponse = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"stale-membership","response":{"event_id":"redacted-event"}}
        """
        harness.widgetDriver.messagePublisher.send(staleMembershipResponse)
        await waitFor { evaluatedScripts.count == 4 }

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_membership_state_send_completed=false"))

        let membershipResponse = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"current-membership","response":{"event_id":"redacted-event"}}
        """
        harness.widgetDriver.messagePublisher.send(membershipResponse)
        await waitFor { evaluatedScripts.count == 5 }

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_membership_state_send_completed=true"))
        #expect(proof.contains("receiver_membership_state_send_http_bucket=2xx"))
        #expect(proof.contains("receiver_membership_present_on_synapse=true"))
        #expect(proof.contains("receiver_matrixrtc_membership_published=true"))
        #expect(proof.contains("matrixrtc_two_participants_seen=false"))

        SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCObservation(participantCount: 1,
                                                                        hasActiveCall: true,
                                                                        remoteParticipantPresent: true)
        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_remote_participant_seen=true"))
        #expect(proof.contains("matrixrtc_two_participants_seen=true"))

        harness.viewModel.stop()
    }

    @Test
    func roomCallMatrixRTCDelayedLeaveProofTracksOnlyThePreparedEvent() async throws {
        let harness = try makeAudioRoomCallViewModel()

        setenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE", "1", 1)
        defer { unsetenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE") }

        let clearURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/clear"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        let prepareMessage = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"prepare-leave","data":{"type":"org.matrix.msc3401.call.member","state_key":"redacted-state","content":{},"delay":8000}}
        """
        harness.viewModel.context.send(viewAction: .widgetAction(message: prepareMessage))
        await waitFor { harness.widgetDriver.handleMessageCallsCount == 1 }

        var proof = try stage2FSimulatorProofText()
        #expect(proof.contains("matrixrtc_delayed_leave_prepare_attempted=true"))
        #expect(proof.contains("matrixrtc_delayed_leave_prepared=false"))
        #expect(proof.contains("matrixrtc_delayed_leave_prepare_http_bucket=pending"))

        let prepareResponse = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"prepare-leave","response":{"delay_id":"opaque-delay"}}
        """
        harness.widgetDriver.messagePublisher.send(prepareResponse)
        await waitFor {
            (try? self.stage2FSimulatorProofText().contains("matrixrtc_delayed_leave_prepared=true")) == true
        }

        installActiveWebViewBinding(in: harness) { _ in true }
        harness.viewModel.context.send(viewAction: .endCall)

        let mismatchedLeaveMessage = """
        {"api":"fromWidget","action":"org.matrix.msc4157.update_delayed_event","widgetId":"call-widget","requestId":"stale-leave","data":{"delay_id":"other-delay","action":"send"}}
        """
        harness.viewModel.context.send(viewAction: .widgetAction(message: mismatchedLeaveMessage))
        await waitFor { harness.widgetDriver.handleMessageCallsCount == 2 }

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("matrixrtc_membership_leave_send_attempted=false"))

        let leaveMessage = """
        {"api":"fromWidget","action":"org.matrix.msc4157.update_delayed_event","widgetId":"call-widget","requestId":"current-leave","data":{"delay_id":"opaque-delay","action":"send"}}
        """
        harness.viewModel.context.send(viewAction: .widgetAction(message: leaveMessage))
        await waitFor {
            (try? self.stage2FSimulatorProofText().contains("matrixrtc_membership_leave_send_attempted=true")) == true
        }

        let leaveResponse = """
        {"api":"fromWidget","action":"org.matrix.msc4157.update_delayed_event","widgetId":"call-widget","requestId":"current-leave","response":{}}
        """
        harness.widgetDriver.messagePublisher.send(leaveResponse)
        await waitFor {
            (try? self.stage2FSimulatorProofText().contains("matrixrtc_membership_leave_send_completed=true")) == true
        }

        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("matrixrtc_membership_leave_send_http_bucket=2xx"))

        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))
        proof = try stage2FSimulatorProofText()
        #expect(proof.contains("matrixrtc_delayed_leave_prepare_attempted=false"))
        #expect(proof.contains("matrixrtc_delayed_leave_prepared=false"))
        #expect(proof.contains("matrixrtc_delayed_leave_prepare_http_bucket=not_requested"))
        #expect(proof.contains("matrixrtc_membership_leave_send_attempted=false"))
        #expect(proof.contains("matrixrtc_membership_leave_send_completed=false"))
        #expect(proof.contains("matrixrtc_membership_leave_send_http_bucket=not_requested"))

        harness.viewModel.stop()
    }

    @Test
    func roomCallMatrixRTCFallbackLeaveProofRecordsDriverFailure() async throws {
        let harness = try makeAudioRoomCallViewModel()

        setenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE", "1", 1)
        defer { unsetenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE") }

        let clearURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/clear"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        let leaveMessage = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"fallback-leave","data":{"type":"org.matrix.msc3401.call.member","state_key":"redacted-state","content":{}}}
        """
        harness.viewModel.context.send(viewAction: .widgetAction(message: leaveMessage))
        await waitFor {
            (try? self.stage2FSimulatorProofText().contains("matrixrtc_membership_leave_send_attempted=true")) == true
        }

        let failureResponse = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"fallback-leave","response":{"error":{"message":"redacted","matrix_api_error":{"http_status":403}}}}
        """
        harness.widgetDriver.messagePublisher.send(failureResponse)
        await waitFor {
            (try? self.stage2FSimulatorProofText().contains("matrixrtc_membership_leave_send_http_bucket=forbidden")) == true
        }

        let proof = try stage2FSimulatorProofText()
        #expect(proof.contains("matrixrtc_membership_leave_send_completed=false"))

        harness.viewModel.stop()
    }

    @Test
    func roomCallMembershipStateSendRecordsDriverFailureWithoutPublishing() async throws {
        let harness = try makeAudioRoomCallViewModel()

        setenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE", "1", 1)
        defer { unsetenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE") }

        let clearURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/clear"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        let membershipMessage = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"failed-membership","data":{"type":"org.matrix.msc3401.call.member","state_key":"redacted-state","content":{"m.calls":[{}]}}}
        """
        harness.viewModel.context.send(viewAction: .widgetAction(message: membershipMessage))
        await waitFor { harness.widgetDriver.handleMessageCallsCount == 1 }

        let failureResponse = """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"failed-membership","response":{"error":{"message":"redacted","matrix_api_error":{"http_status":403}}}}
        """
        harness.widgetDriver.messagePublisher.send(failureResponse)

        await waitFor {
            (try? self.stage2FSimulatorProofText().contains("receiver_membership_state_send_http_bucket=forbidden")) == true
        }

        let proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_membership_state_send_attempted=true"))
        #expect(proof.contains("receiver_membership_state_send_completed=false"))
        #expect(proof.contains("receiver_membership_state_send_http_bucket=forbidden"))
        #expect(proof.contains("receiver_membership_present_on_synapse=false"))
        #expect(proof.contains("receiver_matrixrtc_membership_published=false"))

        harness.viewModel.stop()
    }

    @Test
    func roomCallJoinActionRecordsMembershipSendFailureBucketWhenWidgetDriverFails() async throws {
        let harness = try makeAudioRoomCallViewModel()
        harness.widgetDriver.handleMessageReturnValue = .failure(.driverNotSetup)

        setenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE", "1", 1)
        defer { unsetenv("SALEM_X_STAGE2F_SIM_RECEIVER_BRIDGE") }

        let clearURL = try #require(URL(string: "kz.salemx.msg://direct-call/stage2f-sim/clear"))
        #expect(SalemXStage2FSimulatorSignalingDebug.handleURL(clearURL,
                                                               userSession: nil,
                                                               userSessionFlowCoordinator: nil,
                                                               elementCallService: ElementCallServiceMock(.init())))

        let joinMessage = """
        {"api":"fromWidget","action":"io.element.join","widgetId":"call-widget","requestId":"join-request","data":{}}
        """

        harness.viewModel.context.send(viewAction: .widgetAction(message: joinMessage))
        await waitFor {
            harness.widgetDriver.handleMessageCallsCount == 1
        }

        let proof = try stage2FSimulatorProofText()
        #expect(proof.contains("receiver_widget_join_received=true"))
        #expect(proof.contains("receiver_widget_join_acknowledged=false"))
        #expect(proof.contains("receiver_widget_join_dispatch_attempted=true"))
        #expect(proof.contains("receiver_widget_join_dispatch_completed=false"))
        #expect(proof.contains("receiver_widget_join_dispatch_error_bucket=driverNotSetup"))
        #expect(proof.contains("receiver_membership_send_attempted=true"))
        #expect(proof.contains("receiver_membership_send_completed=false"))
        #expect(proof.contains("receiver_membership_send_error_bucket=driverNotSetup"))

        harness.viewModel.stop()
    }

    private struct CallScreenHarness {
        let viewModel: CallScreenViewModel
        let elementCallService: ElementCallServiceMock
        let elementCallServiceActions: PassthroughSubject<ElementCallServiceAction, Never>
        let roomProxy: JoinedRoomProxyMock
        let widgetDriver: ElementCallWidgetDriverMock
    }

    private func makeAudioRoomCallViewModel() throws -> CallScreenHarness {
        let elementCallService = ElementCallServiceMock()
        let elementCallServiceActions = PassthroughSubject<ElementCallServiceAction, Never>()
        elementCallService.underlyingActions = elementCallServiceActions.eraseToAnyPublisher()
        elementCallService.underlyingOngoingCallRoomIDPublisher = CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher()

        let roomProxy = JoinedRoomProxyMock(.init(id: "redacted-room",
                                                  name: "Room",
                                                  isDirect: true))
        let clientProxy = ClientProxyMock(.init(userID: "redacted-user",
                                                deviceID: "redacted-device"))

        let widgetDriver = try #require(roomProxy.elementCallWidgetDriverDeviceIDReturnValue as? ElementCallWidgetDriverMock)
        widgetDriver.underlyingWidgetID = "call-widget"
        widgetDriver.handleMessageReturnValue = .success(true)
        let elementCallBaseURL = try #require(URL(string: "https://call.element.io"))
        widgetDriver.startBaseURLClientIDColorSchemeRageshakeURLAnalyticsConfigurationReturnValue = .success(elementCallBaseURL)

        let appSettings = AppSettings()
        let analyticsService = AnalyticsService(client: AnalyticsClientMock(),
                                                appSettings: appSettings)

        let viewModel = CallScreenViewModel(elementCallService: elementCallService,
                                            configuration: .init(roomProxy: roomProxy,
                                                                 clientProxy: clientProxy,
                                                                 clientID: "client-id",
                                                                 elementCallBaseURL: elementCallBaseURL,
                                                                 elementCallBaseURLOverride: nil,
                                                                 colorScheme: .light,
                                                                 startMode: .audio),
                                            allowPictureInPicture: false,
                                            appHooks: AppHooks(),
                                            appSettings: appSettings,
                                            analyticsService: analyticsService)

        return CallScreenHarness(viewModel: viewModel,
                                 elementCallService: elementCallService,
                                 elementCallServiceActions: elementCallServiceActions,
                                 roomProxy: roomProxy,
                                 widgetDriver: widgetDriver)
    }

    @discardableResult
    private func installActiveWebViewBinding(in harness: CallScreenHarness,
                                             evaluator: @escaping (String) async throws -> Any?) -> CallWebViewDocumentIdentity {
        let webViewID = UUID()
        let sessionIdentity = harness.viewModel.context.viewState.webViewSessionIdentity
        let identity = CallWebViewDocumentIdentity(webViewID: webViewID,
                                                   documentGeneration: UUID(),
                                                   sessionIdentity: sessionIdentity)
        harness.viewModel.context.send(viewAction: .callWebViewCreated(webViewID: webViewID,
                                                                       sessionIdentity: sessionIdentity))
        harness.viewModel.context.send(viewAction: .callWebViewDocumentLoading(identity))
        harness.viewModel.context.send(viewAction: .callWebViewBindingReady(.init(identity: identity,
                                                                                  javaScriptEvaluator: evaluator,
                                                                                  requestPictureInPictureHandler: nil)))
        return identity
    }

    private static func lifecycleProbeDocument(marker: String, consumerMounted: Bool) -> String {
        """
        <!doctype html>
        <html>
        <body>
        <script>
        window.lifecycleMarker = '\(marker)';
        window.activeCallConsumerMounted = \(consumerMounted);
        </script>
        </body>
        </html>
        """
    }

    private func waitUntilLoaded(_ webView: WKWebView) async {
        for _ in 0..<100 where webView.isLoading {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func waitFor(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<20 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func widgetMessage(from script: String) throws -> ElementCallWidgetMessage {
        let prefix = "postMessage("
        let suffix = ", '*')"
        let startIndex = try #require(script.range(of: prefix)?.upperBound)
        let endIndex = try #require(script.range(of: suffix, range: startIndex..<script.endIndex)?.lowerBound)
        let data = try #require(String(script[startIndex..<endIndex]).data(using: .utf8))
        return try JSONDecoder().decode(ElementCallWidgetMessage.self, from: data)
    }

    private func widgetResponse(for message: ElementCallWidgetMessage) throws -> String {
        let encodedMessage = try JSONEncoder().encode(message)
        var payload = try #require(JSONSerialization.jsonObject(with: encodedMessage) as? [String: Any])
        payload["response"] = [String: Any]()
        let response = try JSONSerialization.data(withJSONObject: payload)
        return try #require(String(data: response, encoding: .utf8))
    }

    private func completeMatrixRTCHangup(in harness: CallScreenHarness) async {
        let requestID = "membership-leave"
        let previousHandleMessageCallsCount = harness.widgetDriver.handleMessageCallsCount
        harness.viewModel.context.send(viewAction: .widgetAction(message: matrixRTCMembershipLeaveRequest(requestID: requestID)))
        await waitFor { harness.widgetDriver.handleMessageCallsCount == previousHandleMessageCallsCount + 1 }
        harness.widgetDriver.messagePublisher.send(matrixRTCMembershipLeaveResponse(requestID: requestID))
    }

    private func matrixRTCMembershipLeaveRequest(requestID: String) -> String {
        """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"\(requestID)","data":{"type":"org.matrix.msc3401.call.member","state_key":"redacted-state","content":{}}}
        """
    }

    private func matrixRTCMembershipLeaveResponse(requestID: String) -> String {
        """
        {"api":"fromWidget","action":"send_event","widgetId":"call-widget","requestId":"\(requestID)","response":{}}
        """
    }

    private func stage2FSimulatorProofText() throws -> String {
        let proofURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("salemx-stage2f-sim-proof.txt")
        return try String(contentsOf: proofURL, encoding: .utf8)
    }
}
