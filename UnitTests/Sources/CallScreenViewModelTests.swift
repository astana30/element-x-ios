//
// Copyright 2026 Element Creations Ltd.
// Copyright 2026 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import Testing

@MainActor
final class CallScreenViewModelTests {
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
