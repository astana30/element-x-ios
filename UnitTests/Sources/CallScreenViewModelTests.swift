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
}
