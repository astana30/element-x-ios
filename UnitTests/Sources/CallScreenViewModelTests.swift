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
        let elementCallService = ElementCallServiceMock()
        elementCallService.underlyingActions = PassthroughSubject<ElementCallServiceAction, Never>()
            .eraseToAnyPublisher()
        elementCallService.underlyingOngoingCallRoomIDPublisher = CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher()
        
        let roomProxy = JoinedRoomProxyMock(.init(id: "!room:example.com",
                                                  name: "Room",
                                                  isDirect: true))
        let clientProxy = ClientProxyMock(.init(userID: "@me:example.com",
                                                deviceID: "DEVICE"))
        
        guard let widgetDriver = roomProxy.elementCallWidgetDriverDeviceIDReturnValue as? ElementCallWidgetDriverMock else {
            Issue.record("Expected an ElementCallWidgetDriverMock")
            return
        }
        
        widgetDriver.handleMessageReturnValue = .success(true)
        
        let appSettings = AppSettings()
        let analyticsService = AnalyticsService(client: AnalyticsClientMock(),
                                                appSettings: appSettings)
        let elementCallBaseURL = try #require(URL(string: "https://call.element.io"))
        
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
        
        viewModel.context.send(viewAction: .endCall)
        try await Task.sleep(for: .milliseconds(100))
        
        let rawMessage = try #require(widgetDriver.handleMessageReceivedMessage)
        let jsonData = try #require(rawMessage.data(using: .utf8))
        let payload = try JSONDecoder().decode(ElementCallWidgetMessage.self, from: jsonData)
        
        #expect(payload.direction == .toWidget)
        #expect(payload.action == .hangup)
        #expect(elementCallService.requestCallTerminationRoomIDCalled)
        #expect(elementCallService.requestCallTerminationRoomIDReceivedRoomID == roomProxy.id)
        
        viewModel.stop()
    }
}
