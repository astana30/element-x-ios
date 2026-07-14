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

@MainActor
final class CallScreenViewModelTests {
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
    func roomCallEndCallSendsHangupToWidgetAndMatrixTermination() async throws {
        let harness = try makeAudioRoomCallViewModel()

        harness.viewModel.context.send(viewAction: .endCall)
        await waitFor {
            harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1
        }

        let rawMessage = try #require(harness.widgetDriver.handleMessageReceivedMessage)
        let jsonData = try #require(rawMessage.data(using: .utf8))
        let payload = try JSONDecoder().decode(ElementCallWidgetMessage.self, from: jsonData)

        #expect(payload.direction == .toWidget)
        #expect(payload.action == .hangup)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCalled)
        #expect(harness.elementCallService.requestCallTerminationRoomIDReceivedRoomID == harness.roomProxy.id)

        harness.viewModel.stop()
    }

    @Test
    func roomCallEndCallResetsEmbeddedWebContentForRepeatCall() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        harness.viewModel.context.javaScriptEvaluator = { script in
            evaluatedScripts.append(script)
            return true
        }

        harness.viewModel.context.send(viewAction: .endCall)
        await waitFor {
            harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1
        }

        let resetScript = try #require(evaluatedScripts.first)
        #expect(resetScript.contains("querySelectorAll(\"audio, video\")"))
        #expect(resetScript.contains("track.stop()"))
        #expect(resetScript.contains("srcObject = null"))
        #expect(resetScript.contains("window.stop()"))
        #expect(evaluatedScripts.count == 1)

        harness.viewModel.context.send(viewAction: .endCall)
        try await Task.sleep(for: .milliseconds(100))

        #expect(evaluatedScripts.count == 1)
        #expect(harness.widgetDriver.handleMessageCallsCount == 1)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1)

        harness.viewModel.stop()
    }

    @Test
    func roomCallStopResetsEmbeddedWebContentAndTearsDownCallSession() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        harness.viewModel.context.javaScriptEvaluator = { script in
            evaluatedScripts.append(script)
            return true
        }

        harness.viewModel.stop()
        await waitFor {
            harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1
        }

        let resetScript = try #require(evaluatedScripts.first)
        #expect(resetScript.contains("querySelectorAll(\"audio, video\")"))
        #expect(resetScript.contains("srcObject = null"))
        #expect(evaluatedScripts.count == 1)
        #expect(harness.elementCallService.tearDownCallSessionCalled)
        #expect(harness.widgetDriver.handleMessageCallsCount == 1)
        #expect(harness.elementCallService.requestCallTerminationRoomIDCallsCount == 1)
    }

    @Test
    func roomCallJoinActionAcknowledgesWebAndForwardsToWidgetDriver() async throws {
        let harness = try makeAudioRoomCallViewModel()
        var evaluatedScripts = [String]()
        harness.viewModel.context.javaScriptEvaluator = { script in
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
        let roomProxy: JoinedRoomProxyMock
        let widgetDriver: ElementCallWidgetDriverMock
    }

    private func makeAudioRoomCallViewModel() throws -> CallScreenHarness {
        let elementCallService = ElementCallServiceMock()
        elementCallService.underlyingActions = PassthroughSubject<ElementCallServiceAction, Never>()
            .eraseToAnyPublisher()
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
                                 roomProxy: roomProxy,
                                 widgetDriver: widgetDriver)
    }

    private func waitFor(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<20 {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func stage2FSimulatorProofText() throws -> String {
        let proofURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("salemx-stage2f-sim-proof.txt")
        return try String(contentsOf: proofURL, encoding: .utf8)
    }
}
