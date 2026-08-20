//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import CallKit
import Foundation
import Testing

@MainActor
final class MatrixRTCNativeAudioTests {
    @Test
    func openIDTokenParsesWidgetAllowedResponse() {
        let token = MatrixRTCOpenIDToken.parse([
            "state": "allowed",
            "access_token": "openid-token",
            "token_type": "Bearer",
            "matrix_server_name": "matrix.example",
            "expires_in": 3600
        ])

        #expect(token?.matrixServerName == "matrix.example")
        #expect(token?.tokenType == "Bearer")
        #expect(token?.expiresIn == 3600)
        #expect(token?.jsonObject["access_token"] as? String == "openid-token")
    }

    @Test
    func liveKitJWTParsesSFUGetResponse() throws {
        let data = Data(#"{"url":"wss://rtc.example","jwt":"livekit-jwt"}"#.utf8)
        let jwt = try #require(MatrixRTCLiveKitJWT.parse(data))
        #expect(jwt.serverURL.absoluteString == "wss://rtc.example")
    }

    @Test
    func membershipUsesElementCallSessionShape() throws {
        let membership = MatrixRTCNativeMembership(userID: "@me:example.com",
                                                   deviceID: "DEVICE",
                                                   membershipID: "party",
                                                   liveKitServiceURL: try #require(URL(string: "https://matrix.example/livekit/jwt")))
        let content = membership.stateContent(createdAt: Date(timeIntervalSince1970: 1_700_000_000))

        #expect(membership.stateKey == "_@me:example.com_DEVICE_party")
        #expect(membership.liveKitIdentity == "@me:example.com:DEVICE")
        #expect(content["application"] as? String == "m.call")
        #expect(content["call_id"] as? String == "")
        #expect(content["scope"] as? String == "m.room")
        #expect(content["device_id"] as? String == "DEVICE")
        #expect(content["membershipID"] as? String == "party")
        let focusActive = try #require(content["focus_active"] as? [String: Any])
        #expect(focusActive["type"] as? String == "livekit")
    }

    @Test
    func signalingRequestsOpenIDAndSFUGetWithoutDirectCallTokenPath() async throws {
        let httpClient = MatrixRTCHTTPClientSpy()
        httpClient.responses = [
            .success(.init(statusCode: 200, data: Data(#"{"access_token":"openid-token","token_type":"Bearer","matrix_server_name":"matrix.example","expires_in":3600}"#.utf8))),
            .success(.init(statusCode: 200, data: Data(#"{"url":"wss://rtc.example","jwt":"livekit-jwt"}"#.utf8))),
            .success(.init(statusCode: 200, data: Data("{}".utf8)))
        ]
        let client = MatrixRTCNativeSignalingClient(httpClient: httpClient)
        let homeserver = try #require(URL(string: "https://matrix.example"))
        let openID = try #require(await client.requestOpenIDToken(homeserverURL: homeserver,
                                                                  userID: "@me:example.com",
                                                                  accessToken: "matrix-access-token"))
        let jwt = try #require(await client.requestLiveKitJWT(liveKitServiceURL: homeserver.appending(path: "/livekit/jwt"),
                                                              roomID: "!room:example.com",
                                                              deviceID: "DEVICE",
                                                              openIDToken: openID))
        let membership = MatrixRTCNativeMembership(userID: "@me:example.com",
                                                   deviceID: "DEVICE",
                                                   membershipID: "party",
                                                   liveKitServiceURL: homeserver.appending(path: "/livekit/jwt"))
        let published = await client.putMembership(homeserverURL: homeserver,
                                                   roomID: "!room:example.com",
                                                   accessToken: "matrix-access-token",
                                                   membership: membership,
                                                   content: membership.stateContent())

        #expect(jwt.serverURL.host == "rtc.example")
        #expect(published)
        #expect(httpClient.requests.count == 3)
        #expect(httpClient.requests[0].url.path.contains("/openid/request_token"))
        #expect(httpClient.requests[1].url.path == "/livekit/jwt/sfu/get")
        #expect(httpClient.requests[2].url.path.contains("org.matrix.msc3401.call.member"))
        #expect(!httpClient.requests.contains { $0.url.path.contains("kz.salemx.direct_call") })
    }

    @Test
    func nativeAudioFilesStayOffTheDirectCallMediaPath() throws {
        let handoff = try Self.source(named: "ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift")
        let nativeStart = try #require(handoff.range(of: "struct MatrixRTCOpenIDToken"))
        let nativeAudio = String(handoff[nativeStart.lowerBound...])
        let callProtocol = try Self.source(named: "ElementX/Sources/Services/ElementCall/ElementCallServiceProtocol.swift")
        let callScreen = try Self.source(named: "ElementX/Sources/Screens/CallScreen/CallScreenViewModel.swift")

        for source in [nativeAudio, callProtocol] {
            #expect(!source.contains("DirectCallEngine"))
            #expect(!source.contains("LiveKitDirectCall"))
            #expect(!source.contains("ProductionDirectCallLiveKitTokenClient"))
            #expect(!source.contains("kz.salemx.direct_call"))
        }

        #expect(callScreen.contains("ownsNativeMatrixRTCAudio"))
        #expect(callScreen.contains("isNativeMatrixRTCAudioActive = true"))
        #expect(callScreen.contains("!elementCallService.ownsNativeMatrixRTCAudio(roomID: configuration.callRoomID)"))
        #expect(!callScreen.contains("DirectCallEngine"))
    }

    @Test
    func nativeAudioSourcesAreInTheSalemXXcodeTarget() throws {
        let protocolSource = try Self.source(named: "ElementX/Sources/Services/ElementCall/ElementCallServiceProtocol.swift")
        #expect(protocolSource.contains("enum MatrixRTCNativeAudioState"))
        #expect(protocolSource.contains("protocol MatrixRTCNativeAudioJoining"))
        #expect(protocolSource.contains("func prepareIncomingKeyListener"))
        #expect(protocolSource.contains("var isActive: Bool"))

        let callService = try Self.source(named: "ElementX/Sources/Services/ElementCall/ElementCallService.swift")
        #expect(callService.contains("nativeAudioController.isActive"))
        #expect(callService.contains("skipped=already_active"))
        #expect(callService.contains("shouldKeepAnsweredCallKitForNativeAudio"))
        #expect(callService.contains("nativeAudioJoinCallKitID = incomingCallID.callKitID"))
        #expect(callService.contains("[APP-INCOMING-SKIP-END]"))
        #expect(!callService.contains("!= .inactive"))

        let generatedMocks = try Self.source(named: "ElementX/Sources/Mocks/Generated/GeneratedMocks.swift")
        #expect(!generatedMocks.contains("MatrixRTCNativeAudioState"))

        let handoff = try Self.source(named: "ElementX/Sources/Services/ElementCall/SalemXMatrixRTCHandoff.swift")
        let pbxproj = try Self.source(named: "SalemX.xcodeproj/project.pbxproj")
        #expect(pbxproj.contains("SalemXMatrixRTCHandoff.swift in Sources"))
        #expect(pbxproj.contains("MatrixRTCNativeAudioTests.swift in Sources"))
        #expect(!pbxproj.contains("MatrixRTCNativeAudioController.swift in Sources"))
        #expect(handoff.contains("final class MatrixRTCNativeAudioController"))
        #expect(!handoff.contains("@MainActor\nfinal class MatrixRTCNativeAudioController"))
        #expect(!handoff.contains("@MainActor\nfinal class MatrixRTCNativeLiveKitClient"))
        #expect(handoff.contains("final class MatrixRTCNativeLiveKitClient"))
        #expect(handoff.contains("struct MatrixRTCNativeSignalingClient"))
        #expect(handoff.contains("final class MatrixRTCNativeWidgetBridge"))
        #expect(!handoff.contains("?? await"))
        #expect(!handoff.contains("if let widgetBridge, await"))
        #expect(handoff.contains("isAutomaticConfigurationEnabled = false"))
        #expect(handoff.contains("isAutomaticDeactivationEnabled = false"))
        #expect(handoff.contains("skipped=already_active"))
        #expect(handoff.contains("private func publishMembership(session: SessionContext) async -> Bool"))
        #expect(!handoff.contains("widgetBridge.sendMembership"))
        #expect(handoff.contains("action: \"content_loaded\""))
        #expect(handoff.contains("stage=widget_caps"))
        #expect(handoff.contains("stage=remote_key"))
        #expect(handoff.contains("stage=local_key"))
        #expect(handoff.contains("org.matrix.msc3819.receive.to_device:io.element.call.encryption_keys"))
        #expect(handoff.contains("enum MatrixRTCNativeEncryptionPeer"))
        #expect(handoff.contains("prepareIncomingKeyListener"))
        #expect(handoff.contains("lastRemoteDeviceID"))
        #expect(handoff.contains("shouldNegotiateCapabilities"))
        #expect(handoff.contains("stage=early_listen"))
        
        let elementCallService = try #require(try? String(contentsOfFile: "\(projectRoot)/ElementX/Sources/Services/ElementCall/ElementCallService.swift", encoding: .utf8))
        #expect(elementCallService.contains("startNativeIncomingKeyListenerIfNeeded"))
        #expect(elementCallService.contains("early_listen_request"))
        #expect(elementCallService.contains("early_listen_skip"))
    }

    @Test
    func widgetToDeviceMessageParsesElementCallEncryptionKeys() {
        let key = MatrixRTCWidgetEncryptionKey.parseWidgetMessage([
            "api": "toWidget",
            "action": "send_to_device",
            "data": [
                "type": "io.element.call.encryption_keys",
                "sender": "@alice:example.com",
                "content": [
                    "keys": [
                        "index": 0,
                        "key": "remote-key"
                    ],
                    "member": [
                        "claimed_device_id": "DEVICE",
                        "id": "party"
                    ]
                ]
            ]
        ])

        #expect(key?.identity == "@alice:example.com:DEVICE")
        #expect(key?.keyBase64 == "remote-key")
        #expect(key?.index == 0)
    }

    @Test
    func controllerJoinsThroughInjectedLiveKitAndLeavesMembership() async throws {
        let signalingHTTP = MatrixRTCHTTPClientSpy()
        signalingHTTP.responses = [
            .success(.init(statusCode: 200, data: Data(#"{"access_token":"openid-token","token_type":"Bearer","matrix_server_name":"matrix.example","expires_in":3600}"#.utf8))),
            .success(.init(statusCode: 200, data: Data(#"{"url":"wss://rtc.example","jwt":"livekit-jwt"}"#.utf8))),
            .success(.init(statusCode: 200, data: Data("{}".utf8))),
            .success(.init(statusCode: 200, data: Data("{}".utf8)))
        ]
        let liveKit = MatrixRTCNativeLiveKitClientSpy()
        let widgetDriver = ElementCallWidgetDriverMock()
        widgetDriver.underlyingWidgetID = "widget"
        widgetDriver.underlyingMessagePublisher = .init()
        widgetDriver.startBaseURLClientIDColorSchemeRageshakeURLAnalyticsConfigurationReturnValue = .success(URL(string: "https://call.element.io")!)
        widgetDriver.handleMessageReturnValue = .success(true)
        let room = JoinedRoomProxyMock(.init(id: "!room:example.com", name: "Room"))
        room.elementCallWidgetDriverDeviceIDReturnValue = widgetDriver
        let clientProxy = TokenClientProxyMock(.init(userID: "@me:example.com", deviceID: "DEVICE", homeserver: "https://matrix.example"))
        clientProxy.roomForIdentifierClosure = { _ in .joined(room) }

        let controller = MatrixRTCNativeAudioController(signalingClient: MatrixRTCNativeSignalingClient(httpClient: signalingHTTP),
                                                        liveKitClient: liveKit,
                                                        elementCallBaseURL: try #require(URL(string: "https://call.example")),
                                                        clientID: "kz.salemx")
        await controller.joinIncomingAudio(roomID: "!room:example.com", clientProxy: clientProxy)

        #expect(controller.state == .connected)
        #expect(liveKit.connectCount == 1)
        #expect(liveKit.microphoneEnabled == true)
        #expect(signalingHTTP.requests.contains { $0.method == "PUT" && $0.url.path.contains("org.matrix.msc3401.call.member") })

        await controller.joinIncomingAudio(roomID: "!room:example.com", clientProxy: clientProxy)
        #expect(liveKit.connectCount == 1)
        #expect(controller.state == .connected)

        controller.leave()
        #expect(controller.state == .inactive)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(liveKit.disconnectCount == 1)
        #expect(signalingHTTP.requests.contains { $0.method == "PUT" && $0.url.path.contains("org.matrix.msc3401.call.member") })
    }
    
    @Test
    func encryptionPeerDeviceIDTargetsSingleRemoteDevice() {
        #expect(MatrixRTCNativeEncryptionPeer.peerDeviceID(from: []) == "*")
        #expect(MatrixRTCNativeEncryptionPeer.peerDeviceID(from: ["aqFw8fCpKO"]) == "aqFw8fCpKO")
        #expect(MatrixRTCNativeEncryptionPeer.peerDeviceID(from: ["aqFw8fCpKO", "x310zhsKGJ"]) == "*")
        #expect(MatrixRTCNativeEncryptionPeer.deviceID(fromIdentity: "@r2:mertis.kz:aqFw8fCpKO") == "aqFw8fCpKO")
        #expect(MatrixRTCNativeEncryptionPeer.deviceID(fromIdentity: "@r2:mertis.kz") == nil)
        #expect(MatrixRTCNativeEncryptionPeer.deviceID(fromIdentity: "no-separator") == nil)
    }
    
    @Test
    func widgetBridgeStartCanSkipCapabilityNegotiation() async {
        let widgetDriver = ElementCallWidgetDriverMock()
        widgetDriver.startBaseURLClientIDColorSchemeRageshakeURLAnalyticsConfigurationReturnValue = .success(URL(string: "https://call.element.io")!)
        widgetDriver.handleMessageReturnValue = .success(true)
        
        let widgetBridge = MatrixRTCNativeWidgetBridge(widgetDriver: widgetDriver)
        let started = await widgetBridge.start(baseURL: URL(string: "https://call.element.io")!,
                                               clientID: "io.element.call",
                                               shouldNegotiateCapabilities: false)
        
        #expect(started)
        #expect(widgetDriver.startBaseURLClientIDColorSchemeRageshakeURLAnalyticsConfigurationCallsCount == 1)
        
        let restarted = await widgetBridge.start(baseURL: URL(string: "https://call.element.io")!,
                                                 clientID: "io.element.call",
                                                 shouldNegotiateCapabilities: false)
        #expect(restarted)
        #expect(widgetDriver.startBaseURLClientIDColorSchemeRageshakeURLAnalyticsConfigurationCallsCount == 1)
    }

    @Test
    func elementCallServiceExposesNativeAudioOwnership() async {
        let service = ElementCallService(appSettings: AppSettings(),
                                         callProvider: CXProviderMock(.init()),
                                         salemXAnswerBridgeConfiguration: .init(embeddedMatrixRTCAnswerBridgeEnabled: false))
        let spy = MatrixRTCNativeAudioJoiningSpy()
        service.setNativeMatrixRTCAudioController(spy)
        #expect(service.ownsNativeMatrixRTCAudio(roomID: "!room:example.com") == false)

        await spy.joinIncomingAudio(roomID: "!room:example.com", clientProxy: ClientProxyMock(.init()))
        #expect(service.ownsNativeMatrixRTCAudio(roomID: "!room:example.com"))
        #expect(service.nativeMatrixRTCAudioState(roomID: "!room:example.com") == MatrixRTCNativeAudioState.connected)
    }

    private static func source(named name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

@MainActor
private final class MatrixRTCNativeAudioJoiningSpy: MatrixRTCNativeAudioJoining {
    private(set) var activeRoomID: String?
    private(set) var state: MatrixRTCNativeAudioState = .inactive

    func joinIncomingAudio(roomID: String, clientProxy _: ClientProxyProtocol) async {
        activeRoomID = roomID
        state = .connected
    }

    func prepareIncomingKeyListener(roomID _: String, clientProxy _: ClientProxyProtocol) { }

    func setMicrophoneEnabled(_: Bool) { }

    func leave() {
        activeRoomID = nil
        state = .inactive
    }
}

private final class TokenClientProxyMock: ClientProxyMock, DirectCallMatrixAccessTokenProviding {
    func matrixAccessToken() async -> String? {
        "matrix-access-token"
    }
}

private final class MatrixRTCHTTPClientSpy: MatrixRTCHTTPClientProtocol {
    struct Request {
        let method: String
        let url: URL
    }

    var responses: [Result<MatrixRTCHTTPResponse, Error>] = []
    private(set) var requests = [Request]()

    func send(method: String, url: URL, headers _: [String: String], body _: Data?) async -> Result<MatrixRTCHTTPResponse, Error> {
        requests.append(.init(method: method, url: url))
        if responses.isEmpty {
            return .failure(URLError(.cannotConnectToHost))
        }
        return responses.removeFirst()
    }
}

@MainActor
private final class MatrixRTCNativeLiveKitClientSpy: MatrixRTCNativeLiveKitConnecting {
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var microphoneEnabled = false

    func connect(serverURL _: URL, token _: String, localIdentity _: String, localKeyBase64 _: String) async -> Bool {
        connectCount += 1
        microphoneEnabled = true
        return true
    }

    func setRemoteParticipantKey(_: String, identity _: String, index _: Int32) { }

    func setMicrophoneEnabled(_ enabled: Bool) async {
        microphoneEnabled = enabled
    }

    func disconnect() async {
        disconnectCount += 1
    }
}
