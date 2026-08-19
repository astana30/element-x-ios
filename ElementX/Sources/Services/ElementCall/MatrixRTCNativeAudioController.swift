//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

@MainActor
final class MatrixRTCNativeAudioController: MatrixRTCNativeAudioJoining {
    private let signalingClient: MatrixRTCNativeSignalingClient
    private let liveKitClient: MatrixRTCNativeLiveKitConnecting
    private let widgetBridgeFactory: (ElementCallWidgetDriverProtocol) -> MatrixRTCNativeWidgetBridge
    private let elementCallBaseURL: URL
    private let clientID: String

    private(set) var activeRoomID: String?
    private(set) var state: MatrixRTCNativeAudioState = .inactive

    private var joinGeneration: UInt64 = 0
    private var widgetBridge: MatrixRTCNativeWidgetBridge?
    private var membership: MatrixRTCNativeMembership?
    private var accessToken: String?
    private var homeserverURL: URL?
    private var roomID: String?
    private var joinTask: Task<Void, Never>?

    init(signalingClient: MatrixRTCNativeSignalingClient = MatrixRTCNativeSignalingClient(),
         liveKitClient: MatrixRTCNativeLiveKitConnecting = MatrixRTCNativeLiveKitClient(),
         widgetBridgeFactory: @escaping (ElementCallWidgetDriverProtocol) -> MatrixRTCNativeWidgetBridge = { MatrixRTCNativeWidgetBridge(widgetDriver: $0) },
         elementCallBaseURL: URL,
         clientID: String) {
        self.signalingClient = signalingClient
        self.liveKitClient = liveKitClient
        self.widgetBridgeFactory = widgetBridgeFactory
        self.elementCallBaseURL = elementCallBaseURL
        self.clientID = clientID
    }

    func joinIncomingAudio(roomID: String, clientProxy: ClientProxyProtocol) async {
        if activeRoomID == roomID, state != .inactive {
            return
        }

        leave()
        joinGeneration += 1
        let generation = joinGeneration
        activeRoomID = roomID
        self.roomID = roomID
        state = .connecting
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join")

        joinTask = Task { [weak self] in
            await self?.performJoin(roomID: roomID, clientProxy: clientProxy, generation: generation)
        }
        await joinTask?.value
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        Task {
            await liveKitClient.setMicrophoneEnabled(enabled)
        }
    }

    func leave() {
        joinGeneration += 1
        joinTask?.cancel()
        joinTask = nil

        let membershipToClear = membership
        let accessTokenToUse = accessToken
        let homeserverURLToUse = homeserverURL
        let roomIDToClear = roomID
        membership = nil
        accessToken = nil
        homeserverURL = nil
        roomID = nil

        widgetBridge?.stop()
        widgetBridge = nil

        Task { [liveKitClient, signalingClient] in
            await liveKitClient.disconnect()
            if let membershipToClear, let accessTokenToUse, let homeserverURLToUse, let roomIDToClear {
                _ = await signalingClient.putMembership(homeserverURL: homeserverURLToUse,
                                                        roomID: roomIDToClear,
                                                        accessToken: accessTokenToUse,
                                                        membership: membershipToClear,
                                                        content: [:])
            }
        }

        activeRoomID = nil
        state = .inactive
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=leave")
    }

    private func performJoin(roomID: String, clientProxy: ClientProxyProtocol, generation: UInt64) async {
        guard let session = await sessionContext(roomID: roomID, clientProxy: clientProxy, generation: generation) else {
            return
        }

        let widgetBridge = widgetBridgeFactory(session.widgetDriver)
        let widgetStarted = await widgetBridge.start(baseURL: elementCallBaseURL, clientID: clientID)
        guard isCurrent(generation) else {
            widgetBridge.stop()
            return
        }

        let credentials = await mediaCredentials(session: session, widgetBridge: widgetStarted ? widgetBridge : nil)
        guard let credentials else {
            widgetBridge.stop()
            failIfCurrent(generation: generation)
            return
        }
        guard isCurrent(generation) else {
            widgetBridge.stop()
            return
        }

        let membershipPublished = await publishMembership(session: session, widgetBridge: widgetStarted ? widgetBridge : nil)
        guard membershipPublished else {
            widgetBridge.stop()
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=membership")
            failIfCurrent(generation: generation)
            return
        }

        let localKey = Self.randomKeyBase64()
        widgetBridge.listenForEncryptionKeys { [weak self] key in
            Task { @MainActor in
                guard let self, self.joinGeneration == generation else { return }
                self.liveKitClient.setRemoteParticipantKey(key.keyBase64, identity: key.identity, index: key.index)
            }
        }

        let connected = await liveKitClient.connect(serverURL: credentials.jwt.serverURL,
                                                    token: credentials.jwt.token,
                                                    localIdentity: session.membership.liveKitIdentity,
                                                    localKeyBase64: localKey)
        guard connected, isCurrent(generation) else {
            if connected {
                await liveKitClient.disconnect()
            }
            widgetBridge.stop()
            if isCurrent(generation) {
                failIfCurrent(generation: generation)
            }
            return
        }

        if widgetStarted, let peerUserID = Self.peerUserID(in: session.roomProxy, ownUserID: session.userID) {
            _ = await widgetBridge.sendEncryptionKey(localKey,
                                                     index: 0,
                                                     membership: session.membership,
                                                     roomID: roomID,
                                                     peerUserID: peerUserID,
                                                     peerDeviceID: "*")
        }

        self.widgetBridge = widgetBridge
        membership = session.membership
        accessToken = session.accessToken
        homeserverURL = session.homeserverURL
        self.roomID = roomID
        state = .connected
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=true")
    }

    private struct SessionContext {
        let userID: String
        let accessToken: String
        let homeserverURL: URL
        let roomProxy: JoinedRoomProxyProtocol
        let widgetDriver: ElementCallWidgetDriverProtocol
        let membership: MatrixRTCNativeMembership
    }

    private struct MediaCredentials {
        let jwt: MatrixRTCLiveKitJWT
    }

    private func sessionContext(roomID: String, clientProxy: ClientProxyProtocol, generation: UInt64) async -> SessionContext? {
        guard let deviceID = clientProxy.deviceID,
              let homeserverURL = URL(string: clientProxy.homeserver) else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=session")
            failIfCurrent(generation: generation)
            return nil
        }

        guard let accessToken = await matrixAccessToken(from: clientProxy), !accessToken.isEmpty else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=token")
            failIfCurrent(generation: generation)
            return nil
        }

        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(roomID) else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=room")
            failIfCurrent(generation: generation)
            return nil
        }

        guard isCurrent(generation) else {
            return nil
        }

        let liveKitServiceURL = homeserverURL.appending(path: "/livekit/jwt")
        let membership = MatrixRTCNativeMembership(userID: clientProxy.userID,
                                                   deviceID: deviceID,
                                                   membershipID: UUID().uuidString,
                                                   liveKitServiceURL: liveKitServiceURL)
        let widgetDriver = roomProxy.elementCallWidgetDriver(deviceID: deviceID)
        (widgetDriver as? ElementCallStartModeConfigurable)?.startMode = .audio
        return .init(userID: clientProxy.userID,
                     accessToken: accessToken,
                     homeserverURL: homeserverURL,
                     roomProxy: roomProxy,
                     widgetDriver: widgetDriver,
                     membership: membership)
    }

    private func mediaCredentials(session: SessionContext, widgetBridge: MatrixRTCNativeWidgetBridge?) async -> MediaCredentials? {
        let widgetOpenID = await widgetBridge?.requestOpenIDToken()
        let openIDToken = widgetOpenID ?? await signalingClient.requestOpenIDToken(homeserverURL: session.homeserverURL,
                                                                                   userID: session.userID,
                                                                                   accessToken: session.accessToken)
        guard let openIDToken else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=openid")
            return nil
        }

        let jwt = await signalingClient.requestLiveKitJWT(liveKitServiceURL: session.membership.liveKitServiceURL,
                                                          roomID: session.roomProxy.id,
                                                          deviceID: session.membership.deviceID,
                                                          openIDToken: openIDToken)
        guard let jwt else {
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][APP-NATIVE-AUDIO] stage=join ok=false reason=jwt")
            return nil
        }

        return .init(jwt: jwt)
    }

    private func publishMembership(session: SessionContext, widgetBridge: MatrixRTCNativeWidgetBridge?) async -> Bool {
        let content = session.membership.stateContent()
        if let widgetBridge, await widgetBridge.sendMembership(session.membership, content: content) {
            return true
        }

        return await signalingClient.putMembership(homeserverURL: session.homeserverURL,
                                                   roomID: session.roomProxy.id,
                                                   accessToken: session.accessToken,
                                                   membership: session.membership,
                                                   content: content)
    }

    private func matrixAccessToken(from clientProxy: ClientProxyProtocol) async -> String? {
        if let provider = clientProxy as? DirectCallMatrixAccessTokenProviding {
            return await provider.matrixAccessToken()
        }
        return (clientProxy as? ClientProxy)?.accessToken
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        !Task.isCancelled && joinGeneration == generation
    }

    private func failIfCurrent(generation: UInt64) {
        guard joinGeneration == generation else { return }
        activeRoomID = nil
        state = .inactive
    }

    private static func randomKeyBase64() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private static func peerUserID(in roomProxy: JoinedRoomProxyProtocol, ownUserID: String) -> String? {
        roomProxy.membersPublisher.value.first { $0.userID != ownUserID && !$0.userID.isEmpty }?.userID
    }
}
