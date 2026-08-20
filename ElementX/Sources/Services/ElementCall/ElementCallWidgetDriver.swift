//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import MatrixRustSDK
import SwiftUI

struct ElementCallWidgetMessage: Codable {
    enum Direction: String, Codable {
        case fromWidget
        case toWidget
    }
    
    enum Action: String, Codable {
        case hangup = "im.vector.hangup"
        case close = "io.element.close"
        case mediaState = "io.element.device_mute"
    }
    
    struct Data: Codable {
        var audioEnabled: Bool?
        var videoEnabled: Bool?
        
        enum CodingKeys: String, CodingKey {
            case audioEnabled = "audio_enabled"
            case videoEnabled = "video_enabled"
        }
    }
    
    let direction: Direction
    let action: Action
    var data: Data = .init()
    
    let widgetId: String
    var requestId = UUID().uuidString
    
    enum CodingKeys: String, CodingKey {
        case direction = "api"
        case action
        case data
        case widgetId
        case requestId
    }
}

final class ElementCallWidgetDriver: WidgetCapabilitiesProvider, ElementCallWidgetDriverProtocol, ElementCallStartModeConfigurable, @unchecked Sendable {
    private enum CallURLParameter {
        static let controlledAudioDevices = "controlledAudioDevices"
        static let header = "header"
        static let showControls = "showControls"
        static let hideScreensharing = "hideScreensharing"
        static let autoLeave = "autoLeave"
    }
    
    private enum HeaderStyle: String {
        case none
    }
    
    private let room: RoomProtocol
    private let deviceID: String
    
    private var widgetDriver: WidgetDriverAndHandle?
    private var driverTasks = [Task<Void, Never>]()
    var startMode: ElementCallStartMode = .audio
    
    let widgetID = UUID().uuidString
    let messagePublisher = PassthroughSubject<String, Never>()
    
    private let actionsSubject: PassthroughSubject<ElementCallWidgetDriverAction, Never> = .init()
    var actions: AnyPublisher<ElementCallWidgetDriverAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(room: RoomProtocol, deviceID: String) {
        self.room = room
        self.deviceID = deviceID
    }
    
    func start(baseURL: URL,
               clientID: String,
               colorScheme: ColorScheme,
               rageshakeURL: String?,
               analyticsConfiguration: ElementCallAnalyticsConfiguration?) async -> Result<URL, ElementCallWidgetDriverError> {
        guard let room = room as? Room else {
            return .failure(.roomInvalid)
        }
        
        async let useEncryption = (try? room.latestEncryptionState() == .encrypted) ?? false
        async let intent = room.joinCallIntent(for: startMode)
        async let isDirectRoomCall = room.isDirect()
        
        let widgetSettings: WidgetSettings
        do {
            widgetSettings = try await newVirtualElementCallWidget(props: .init(elementCallUrl: baseURL.absoluteString,
                                                                                widgetId: widgetID,
                                                                                parentUrl: nil,
                                                                                fontScale: nil,
                                                                                font: nil,
                                                                                encryption: useEncryption ? .perParticipantKeys : .unencrypted,
                                                                                posthogUserId: nil,
                                                                                posthogApiHost: analyticsConfiguration?.posthogAPIHost,
                                                                                posthogApiKey: analyticsConfiguration?.posthogAPIKey,
                                                                                rageshakeSubmitUrl: rageshakeURL,
                                                                                sentryDsn: analyticsConfiguration?.sentryDSN,
                                                                                sentryEnvironment: nil),
                                                                   config: .init(intent: intent))
        } catch {
            MXLog.error("Failed to build widget settings: \(error)")
            return .failure(.failedBuildingWidgetSettings)
        }
        
        let languageTag = "\(Locale.current.language.languageCode ?? "en")-\(Locale.current.language.region ?? "US")"
        let theme = colorScheme == .light ? "light" : "dark"
        
        let urlString: String
        do {
            urlString = try await generateWebviewUrl(widgetSettings: widgetSettings, room: room,
                                                     props: .init(clientId: clientID,
                                                                  languageTag: languageTag,
                                                                  theme: theme))
        } catch {
            MXLog.error("Failed to generate web view URL: \(error)")
            return .failure(.failedBuildingCallURL)
        }
        
        let usesNativeDirectCallChrome = await isDirectRoomCall
        
        guard let url = adjustedCallURL(from: urlString, isDirectRoomCall: usesNativeDirectCallChrome) else {
            return .failure(.failedParsingCallURL)
        }
        
        let widgetDriver: WidgetDriverAndHandle
        do {
            widgetDriver = try makeWidgetDriver(settings: widgetSettings)
        } catch {
            MXLog.error("Failed to build widget driver: \(error)")
            return .failure(.failedBuildingWidgetDriver)
        }
        
        stop()
        self.widgetDriver = widgetDriver
        
        let recvTask = Task.detached { [weak self, widgetDriver, messagePublisher] in
            MXLog.debug("Started message receiving loop")
            
            defer {
                MXLog.debug("Stopped message receiving loop")
            }
            
            while !Task.isCancelled {
                guard let receivedMessage = await widgetDriver.handle.recv() else {
                    return
                }
                
                messagePublisher.send(receivedMessage)
                MXLog.debug("Received message: \(receivedMessage)")
                
                self?.handleMessageIfNeeded(receivedMessage)
            }
        }
        
        let runTask = Task.detached { [widgetDriver] in
            MXLog.debug("Started widget driver")
            
            defer {
                MXLog.debug("Stopped widget driver")
            }
            
            await widgetDriver.driver.run(room: room, capabilitiesProvider: self)
        }
        
        driverTasks = [recvTask, runTask]
        
        return .success(url)
    }
    
    /// native-audio-widget-stop: drop the Rust widget driver so the next incoming call
    /// does not inherit a stale send_to_device session from the previous call.
    func stop() {
        driverTasks.forEach { $0.cancel() }
        driverTasks.removeAll()
        widgetDriver = nil
    }
    
    @discardableResult
    func handleMessage(_ message: String) async -> Result<Bool, ElementCallWidgetDriverError> {
        guard let widgetDriver else {
            return .failure(.driverNotSetup)
        }
        
        let result = await widgetDriver.handle.send(msg: message)
        MXLog.debug("Sent message: \(message) with result: \(result)")
        
        handleMessageIfNeeded(message)
        
        return .success(result)
    }
    
    // MARK: - WidgetCapabilitiesProvider
    
    func acquireCapabilities(capabilities: WidgetCapabilities) -> WidgetCapabilities {
        getElementCallRequiredPermissions(ownUserId: room.ownUserId(), ownDeviceId: deviceID)
    }
    
    // MARK: - Private

    private func adjustedCallURL(from urlString: String, isDirectRoomCall: Bool) -> URL? {
        guard var components = URLComponents(string: urlString) else {
            return nil
        }
        
        // Element Call reads configuration from the fragment first and falls back
        // to the regular query string for backwards compatibility, so we mirror
        // the parameters into both places.
        var queryItems = components.queryItems ?? []
        updateCallURLParameters(&queryItems, isDirectRoomCall: isDirectRoomCall)
        components.queryItems = queryItems
        
        var fragmentQueryItems = components.fragmentQueryItems ?? []
        updateCallURLParameters(&fragmentQueryItems, isDirectRoomCall: isDirectRoomCall)
        components.fragmentQueryItems = fragmentQueryItems
        
        return components.url
    }
    
    private func updateCallURLParameters(_ queryItems: inout [URLQueryItem], isDirectRoomCall: Bool) {
        // Audio 1:1 calls tell Element Call to accept a native-published speaker
        // device with forEarpiece, so it can default to virtual earpiece instead
        // of full-volume speaker. Video calls keep Element Call's own routing.
        setQueryItem(&queryItems, name: CallURLParameter.controlledAudioDevices, value: startMode == .audio ? "true" : "false")
        
        guard isDirectRoomCall else {
            return
        }
        
        setQueryItem(&queryItems, name: CallURLParameter.header, value: HeaderStyle.none.rawValue)
        setQueryItem(&queryItems, name: CallURLParameter.showControls, value: "false")
        setQueryItem(&queryItems, name: CallURLParameter.hideScreensharing, value: "true")
        // In 1:1 widget calls we want telephone-like teardown semantics.
        // When the remote peer leaves, Element Call should auto-leave instead of
        // remaining in a waiting/ringing state until notification timeout.
        setQueryItem(&queryItems, name: CallURLParameter.autoLeave, value: "true")
    }
    
    private func setQueryItem(_ queryItems: inout [URLQueryItem], name: String, value: String) {
        queryItems.removeAll { $0.name == name }
        queryItems.append(URLQueryItem(name: name, value: value))
    }
    
    func handleMessageIfNeeded(_ message: String) {
        guard let data = message.data(using: .utf8) else {
            return
        }
        
        do {
            let widgetMessage = try JSONDecoder().decode(ElementCallWidgetMessage.self, from: data)
            if widgetMessage.direction == .fromWidget {
                switch widgetMessage.action {
                case .hangup:
                    actionsSubject.send(.callEnded(reason: .hangup))
                case .close:
                    actionsSubject.send(.callEnded(reason: .close))
                case .mediaState:
                    guard let audioEnabled = widgetMessage.data.audioEnabled,
                          let videoEnabled = widgetMessage.data.videoEnabled else {
                        MXLog.error("Media state change messages should contain info data")
                        return
                    }
                    
                    actionsSubject.send(.mediaStateChanged(audioEnabled: audioEnabled, videoEnabled: videoEnabled))
                }
            }
        } catch {
            // Not all actions are supported
            MXLog.verbose("Failed processing widget message with error: \(error)")
        }
    }
}
