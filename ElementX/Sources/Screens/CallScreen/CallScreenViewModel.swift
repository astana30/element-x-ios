//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVKit
import CallKit
import Combine
import SwiftUI

typealias CallScreenViewModelType = StateStoreViewModel<CallScreenViewState, CallScreenViewAction>

private struct PendingMatrixRTCMembershipLeaveResponse {
    let continuation: CheckedContinuation<Bool, Never>
}

class CallScreenViewModel: CallScreenViewModelType, CallScreenViewModelProtocol {
    private enum NativeWidgetAction: String {
        case close = "io.element.close"
        case join = "io.element.join"
        case hangup = "im.vector.hangup"
        case mediaState = "io.element.device_mute"
        case setAlwaysOnScreen = "set_always_on_screen"
    }

    private enum MatrixRTCWidgetAction {
        static let membershipEventType = "org.matrix.msc3401.call.member"
        static let sendEvent = "send_event"
        static let updateDelayedEvent = "org.matrix.msc4157.update_delayed_event"
        static let sendDelayedEvent = "send"
    }
    
    private enum PreferredAudioRoute {
        case systemDefault
        case speaker
        case earpiece
    }
    
    private let elementCallService: ElementCallServiceProtocol
    private let configuration: ElementCallConfiguration
    private let isPictureInPictureAllowed: Bool
    private let appSettings: AppSettings
    private let analyticsService: AnalyticsService
    
    private let widgetDriver: ElementCallWidgetDriverProtocol
    private var preferredAudioRoute: PreferredAudioRoute
    private var hasJoinedWidgetCall = false
    private var hasRequestedLocalTermination = false
    private var shouldSendHangupOnStop = true
    private var isDismissingAfterLocalHangup = false
    private var hasRequestedEmbeddedWebContentReset = false
    private var pendingWidgetHangupRequestID: String?
    private var pendingMatrixRTCMembershipLeaveResponse: PendingMatrixRTCMembershipLeaveResponse?
    private var pendingMatrixRTCDelayedLeavePrepareRequestIDs = Set<String>()
    private var matrixRTCDelayedLeaveID: String?
    private var pendingMatrixRTCMembershipLeaveRequestIDs = Set<String>()
    #if DEBUG
    private var pendingReceiverWidgetJoinRequestID: String?
    private var pendingReceiverMembershipStateSendRequestIDs = Set<String>()
    #endif
    
    private let actionsSubject: PassthroughSubject<CallScreenViewModelAction, Never> = .init()
    var actions: AnyPublisher<CallScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    @CancellableTask
    private var setupCallTask: Task<Void, Never>?

    @CancellableTask
    private var audioRouteEnforcementTask: Task<Void, Never>?

    @CancellableTask
    private var timeoutTask: Task<Void, Never>?
        
    /// Designated initialiser
    /// - Parameters:
    ///   - elementCallService: service responsible for setting up CallKit
    ///   - roomProxy: The room in which the call should be created
    ///   - callBaseURL: Which Element Call instance should be used
    ///   - clientID: Something to identify the current client on the Element Call side
    init(elementCallService: ElementCallServiceProtocol,
         configuration: ElementCallConfiguration,
         allowPictureInPicture: Bool,
         mediaProvider: MediaProviderProtocol? = nil,
         appHooks: AppHooks,
         appSettings: AppSettings,
         analyticsService: AnalyticsService) {
        self.elementCallService = elementCallService
        self.configuration = configuration
        self.appSettings = appSettings
        self.analyticsService = analyticsService
        isPictureInPictureAllowed = allowPictureInPicture
        
        var isGenericCallLink = false
        var rtcTransportScript: String?
        var directRoomCallDetails: DirectRoomCallDetails?
        switch configuration.kind {
        case .genericCallLink(let url):
            widgetDriver = GenericCallLinkWidgetDriver(url: url)
            isGenericCallLink = true
            preferredAudioRoute = .systemDefault
        case .roomCall(let roomProxy, let clientProxy, _, _, _, _, let startMode):
            guard let deviceID = clientProxy.deviceID else { fatalError("Missing device ID for the call.") }
            widgetDriver = roomProxy.elementCallWidgetDriver(deviceID: deviceID)
            (widgetDriver as? ElementCallStartModeConfigurable)?.startMode = startMode
            rtcTransportScript = Self.makeRTCTransportScript(clientProxy: clientProxy)
            preferredAudioRoute = startMode == .audio ? .earpiece : .systemDefault
            directRoomCallDetails = Self.makeDirectRoomCallDetails(roomProxy: roomProxy, startMode: startMode)
        }
        
        super.init(initialViewState: CallScreenViewState(script: CallScreenJavaScriptMessageName.allCasesInjectionScript,
                                                         rtcTransportScript: rtcTransportScript,
                                                         isGenericCallLink: isGenericCallLink,
                                                         directRoomCallDetails: directRoomCallDetails,
                                                         isMicrophoneEnabled: true,
                                                         isVideoEnabled: configuration.startMode == .video,
                                                         isSpeakerphoneEnabled: preferredAudioRoute == .speaker,
                                                         certificateValidator: appHooks.certificateValidatorHook),
                   mediaProvider: mediaProvider)
        IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][CALL-VM-CONFIG] room_id=\(configuration.callRoomID) start_mode=\(configuration.startMode) " +
            "is_video_enabled=\(state.isVideoEnabled) preferred_audio_route=\(preferredAudioRoute) " +
            "is_speakerphone_enabled=\(state.isSpeakerphoneEnabled)")
        
        elementCallService.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case let .setAudioEnabled(enabled, roomID):
                    guard roomID == configuration.callRoomID else {
                        MXLog.error("Received mute request for a different room: \(roomID) != \(configuration.callRoomID)")
                        return
                    }
                    
                    Task {
                        self.state.isMicrophoneEnabled = enabled
                        await self.setMediaState(audioEnabled: enabled, videoEnabled: self.state.isVideoEnabled)
                    }
                case let .endCall(roomID):
                    guard roomID == configuration.callRoomID else { return }
                    if hasRequestedLocalTermination {
                        return
                    }
                    requestLocalCallTermination(sendHangupMessage: false)
                case let .requestCallTermination(roomID):
                    guard roomID == configuration.callRoomID else { return }
                    IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-VM-REQUEST-RECEIVED] room_id=\(roomID)")
                    requestLocalCallTermination()
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        widgetDriver.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] receivedMessage in
                guard let self else { return }

                handleMatrixRTCWidgetResponseIfNeeded(receivedMessage)
                
                Task {
                    await self.postJSONToWidget(receivedMessage)
                }
            }
            .store(in: &cancellables)
        
        widgetDriver.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .callEnded(reason: let reason):
                    let sendHangupMessage = reason == .hangup
                    requestLocalCallTermination(sendHangupMessage: sendHangupMessage)
                case .mediaStateChanged(let audioEnabled, let videoEnabled):
                    state.isMicrophoneEnabled = audioEnabled
                    state.isVideoEnabled = videoEnabled
                    elementCallService.setAudioEnabled(audioEnabled, roomID: configuration.callRoomID)
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in
                self?.applyPreferredAudioRouteIfNeeded()
                Task { await self?.updateOutputsListOnWeb() }
            }
            .store(in: &cancellables)
        
        setupCall()
    }
    
    override func process(viewAction: CallScreenViewAction) {
        switch viewAction {
        case .urlChanged(let url):
            guard let url else { return }
            MXLog.info("URL changed to: \(url)")
        case .pictureInPictureIsAvailable(let controller):
            actionsSubject.send(.pictureInPictureIsAvailable(controller))
        case .navigateBack:
            Task { await handleBackwardsNavigation() }
        case .pictureInPictureWillStop:
            actionsSubject.send(.pictureInPictureStopped)
        case .endCall:
            requestLocalCallTermination()
        case .toggleMicrophone:
            Task { await toggleMicrophone() }
        case .toggleVideo:
            Task { await toggleVideo() }
        case .toggleSpeakerphone:
            handleSpeakerphoneToggle()
        case .mediaCapturePermissionGranted:
            schedulePreferredAudioRouteEnforcement()
            Task { await updateOutputsListOnWeb() }
        case .outputDeviceSelected(deviceID: let deviceID):
            handleOutputDeviceSelected(deviceID: deviceID)
        case .widgetAction(let message):
            Task { await handleWidgetAction(message: message) }
        case .elementCallMediaDiagnostics(let message):
            handleElementCallMediaDiagnostics(message: message)
        }
    }
    
    func stop() {
        timeoutTask = nil
        audioRouteEnforcementTask = nil
        finishPendingMatrixRTCMembershipLeaveResponse(completed: false)
        pendingWidgetHangupRequestID = nil
        pendingMatrixRTCDelayedLeavePrepareRequestIDs.removeAll()
        matrixRTCDelayedLeaveID = nil
        pendingMatrixRTCMembershipLeaveRequestIDs.removeAll()
        #if DEBUG
        pendingReceiverWidgetJoinRequestID = nil
        pendingReceiverMembershipStateSendRequestIDs.removeAll()
        #endif
        resetEmbeddedWebContentIfNeeded()
        let pendingSetupCallTask = setupCallTask
        setupCallTask = nil

        if shouldSendHangupOnStop {
            Task {
                await sendCallTerminationSignal(waitingFor: pendingSetupCallTask)
            }
        }
        
        elementCallService.tearDownCallSession()
        UIDevice.current.isProximityMonitoringEnabled = false
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    // MARK: - Private

    private func handleWidgetAction(message: String) async {
        if handleWidgetHangupResponseIfNeeded(message) {
            return
        }

        recordMatrixRTCWidgetRequestIfNeeded(message)

        if timeoutTask != nil,
           let decodedMessage = try? DecodedWidgetMessage.decode(message: message),
           decodedMessage.hasLoaded {
            // This means that the call room was joined succesfully, we can stop the timeout task
            timeoutTask = nil
            #if DEBUG
            SalemXStage2FSimulatorSignalingDebug.recordReceiverElementCallLoaded()
            #endif
            MXLog.info("Element Call media diagnostics: content_loaded=true start_mode=\(configuration.startMode)")
        }

        if await handleNativeWidgetActionIfNeeded(message) {
            return
        }
        
        await widgetDriver.handleMessage(message)
    }

    private func handleElementCallMediaDiagnostics(message: String) {
        #if DEBUG
        if configuration.startMode == .audio,
           let payload = ElementCallRTCTransportDiagnosticsPayload.decode(message: message) {
            switch payload.stage {
            case .request:
                SalemXStage2FSimulatorSignalingDebug.recordReceiverRTCTransportCredentialsRequested()
            case .response:
                SalemXStage2FSimulatorSignalingDebug.recordReceiverRTCTransportCredentialsResponse(httpStatus: payload.httpStatus)
            }
            return
        }
        #endif

        guard configuration.startMode == .video,
              let payload = ElementCallWebMediaDiagnosticsPayload.decode(message: message) else {
            return
        }

        MXLog.info("Element Call media diagnostics: \(payload)")
    }

    private func requestLocalCallTermination(sendHangupMessage: Bool = true) {
        if sendHangupMessage {
            hasRequestedLocalTermination = true
        }
        guard !isDismissingAfterLocalHangup else {
            return
        }
        
        let pendingSetupCallTask = setupCallTask
        isDismissingAfterLocalHangup = true
        hasJoinedWidgetCall = false
        shouldSendHangupOnStop = false
        timeoutTask = nil
        audioRouteEnforcementTask = nil
        #if DEBUG
        pendingReceiverWidgetJoinRequestID = nil
        #endif
        setupCallTask = nil
        
        guard sendHangupMessage else {
            resetEmbeddedWebContentIfNeeded()
            actionsSubject.send(.dismiss)
            return
        }

        Task {
            await sendCallTerminationSignal(waitingFor: pendingSetupCallTask)
            resetEmbeddedWebContentIfNeeded()
            actionsSubject.send(.dismiss)
        }
    }

    private func resetEmbeddedWebContentIfNeeded() {
        guard !hasRequestedEmbeddedWebContentReset,
              state.bindings.javaScriptEvaluator != nil else {
            return
        }

        hasRequestedEmbeddedWebContentReset = true
        Task { [weak self] in
            await self?.resetEmbeddedWebContent()
        }
    }

    private func resetEmbeddedWebContent() async {
        do {
            _ = try await state.bindings.javaScriptEvaluator?(Self.embeddedWebContentResetJavaScript)
            MXLog.info("Element Call lifecycle diagnostics: web_content_reset=true start_mode=\(configuration.startMode)")
        } catch {
            MXLog.info("Element Call lifecycle diagnostics: web_content_reset=false reason=javascript_error start_mode=\(configuration.startMode)")
        }
    }
    
    private func setupCall() {
        switch configuration.kind {
        case .genericCallLink(let url):
            state.url = url
            // We need widget messaging to work before enabling CallKit, otherwise mute, hangup etc do nothing.
            
        case .roomCall(let roomProxy, _, let clientID, let elementCallBaseURL, let elementCallBaseURLOverride, let colorScheme, _):
            setupCallTask = Task { [weak self] in
                guard let self else { return }
                
                let baseURL = if let elementCallBaseURLOverride {
                    elementCallBaseURLOverride
                } else {
                    elementCallBaseURL
                }
                
                // We only set the analytics configuration if analytics are enabled
                let analyticsConfiguration: ElementCallAnalyticsConfiguration? = if analyticsService.isEnabled {
                    .init(posthogAPIHost: appSettings.elementCallPosthogAPIHost,
                          posthogAPIKey: appSettings.elementCallPosthogAPIKey,
                          sentryDSN: appSettings.elementCallPosthogSentryDSN)
                } else {
                    nil
                }
                let rageshakeURL: String? = if case let .url(baseURL) = appSettings.bugReportRageshakeURL.publisher.value {
                    baseURL.absoluteString
                } else {
                    nil
                }
                
                switch await widgetDriver.start(baseURL: baseURL,
                                                clientID: clientID,
                                                colorScheme: colorScheme,
                                                rageshakeURL: rageshakeURL,
                                                analyticsConfiguration: analyticsConfiguration) {
                case .success(let url):
                    guard !Task.isCancelled, !isDismissingAfterLocalHangup else {
                        return
                    }
                    MXLog.info("Element Call media diagnostics: url_generated=true start_mode=\(configuration.startMode) direct_room=\(state.directRoomCallDetails != nil)")
                    #if DEBUG
                    SalemXStage2FSimulatorSignalingDebug.recordReceiverElementCallReady()
                    #endif
                    state.url = url
                case .failure(let error):
                    guard !Task.isCancelled, !isDismissingAfterLocalHangup else {
                        return
                    }
                    MXLog.error("Failed starting ElementCall Widget Driver with error: \(error)")
                    state.bindings.alertInfo = .init(id: UUID(),
                                                     title: L10n.errorUnknown,
                                                     primaryButton: .init(title: L10n.actionOk) {
                                                         self.actionsSubject.send(.dismiss)
                                                     })
                    return
                }
                
                guard !Task.isCancelled, !isDismissingAfterLocalHangup else {
                    return
                }

                await elementCallService.setupCallSession(roomID: roomProxy.id,
                                                          roomDisplayName: roomProxy.infoPublisher.value.displayName ?? roomProxy.id,
                                                          startMode: configuration.startMode)
            }
            
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { return }
                MXLog.error("Failed to join Element Call: Timeout")
                state.bindings.alertInfo = .init(id: UUID(),
                                                 title: L10n.commonError,
                                                 message: L10n.errorUnknown,
                                                 primaryButton: .init(title: L10n.actionDismiss) { [weak self] in self?.actionsSubject.send(.dismiss) })
                timeoutTask = nil
            }
        }
    }
    
    /// This should always match the web app value
    private static let earpieceID = "earpiece-id"

    private static let embeddedWebContentResetJavaScript = """
    (() => {
        const mediaElements = Array.from(document.querySelectorAll("audio, video"));
        mediaElements.forEach((element) => {
            const stream = element.srcObject;
            if (stream && typeof stream.getTracks === "function") {
                stream.getTracks().forEach((track) => track.stop());
            }
            element.pause();
            element.srcObject = null;
            element.removeAttribute("src");
            element.load();
        });
        window.stop();
        return true;
    })()
    """

    private var shouldControlAudioRoute: Bool {
        configuration.startMode == .audio
    }

    private static func makeDirectRoomCallDetails(roomProxy: JoinedRoomProxyProtocol, startMode: ElementCallStartMode) -> DirectRoomCallDetails? {
        let roomInfo = roomProxy.infoPublisher.value

        guard roomInfo.isDirect else {
            return nil
        }

        let title = roomInfo.displayName ?? roomProxy.id
        let subtitle: String? = if let canonicalAlias = roomInfo.canonicalAlias {
            canonicalAlias
        } else if case let .heroes(heroes) = roomInfo.avatar, heroes.count == 1 {
            heroes[0].userID
        } else {
            nil
        }

        return DirectRoomCallDetails(title: title,
                                     subtitle: subtitle,
                                     avatar: roomInfo.avatar,
                                     startMode: startMode)
    }
    
    private func handleOutputDeviceSelected(deviceID: String) {
        guard shouldControlAudioRoute else {
            return
        }
        
        let isEarpiece = deviceID == Self.earpieceID
        preferredAudioRoute = isEarpiece ? .earpiece : .speaker
        applyPreferredAudioRouteIfNeeded()
    }

    private func handleSpeakerphoneToggle() {
        guard shouldControlAudioRoute else {
            return
        }
        
        preferredAudioRoute = state.isSpeakerphoneEnabled ? .earpiece : .speaker
        applyPreferredAudioRouteIfNeeded()
        Task { await updateOutputsListOnWeb() }
    }

    private func toggleMicrophone() async {
        let isMicrophoneEnabled = !state.isMicrophoneEnabled
        state.isMicrophoneEnabled = isMicrophoneEnabled
        await setMediaState(audioEnabled: isMicrophoneEnabled, videoEnabled: state.isVideoEnabled)
    }

    private func toggleVideo() async {
        let isVideoEnabled = !state.isVideoEnabled
        state.isVideoEnabled = isVideoEnabled
        await setMediaState(audioEnabled: state.isMicrophoneEnabled, videoEnabled: isVideoEnabled)
    }

    private func schedulePreferredAudioRouteEnforcement() {
        guard shouldControlAudioRoute else {
            return
        }

        audioRouteEnforcementTask = Task { @MainActor [weak self] in
            let delays: [Duration] = [.zero, .milliseconds(150), .milliseconds(500), .seconds(1)]

            for delay in delays {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }

                guard let self, !Task.isCancelled else {
                    return
                }

                self.applyPreferredAudioRouteIfNeeded()
            }
        }
    }
    
    private func applyPreferredAudioRouteIfNeeded() {
        guard let currentOutput = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            return
        }

        guard shouldControlAudioRoute else {
            state.isSpeakerphoneEnabled = currentOutput.portType == .builtInSpeaker
            UIDevice.current.isProximityMonitoringEnabled = false
            return
        }
        
        switch preferredAudioRoute {
        case .systemDefault:
            state.isSpeakerphoneEnabled = currentOutput.portType == .builtInSpeaker
            UIDevice.current.isProximityMonitoringEnabled = currentOutput.portType == .builtInReceiver
        case .speaker:
            setSpeakerphoneEnabled(true)
        case .earpiece:
            switch currentOutput.portType {
            case .builtInSpeaker:
                setSpeakerphoneEnabled(false)
            case .builtInReceiver:
                state.isSpeakerphoneEnabled = false
                UIDevice.current.isProximityMonitoringEnabled = true
            default:
                state.isSpeakerphoneEnabled = false
                UIDevice.current.isProximityMonitoringEnabled = false
            }
        }
    }
    
    private func setSpeakerphoneEnabled(_ enabled: Bool) {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(enabled ? .speaker : .none)
        } catch {
            MXLog.error("Failed updating call audio route with error: \(error)")
            preferredAudioRoute = .systemDefault
            state.isSpeakerphoneEnabled = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType == .builtInSpeaker
            UIDevice.current.isProximityMonitoringEnabled = false
            return
        }
        
        state.isSpeakerphoneEnabled = enabled
        UIDevice.current.isProximityMonitoringEnabled = !enabled
    }
    
    private func handleBackwardsNavigation() async {
        if case .roomCall(let roomProxy, _, _, _, _, _, _) = configuration.kind,
           !hasJoinedWidgetCall,
           elementCallService.isPreAnswerOutgoingCall(roomID: roomProxy.id) {
            requestLocalCallTermination(sendHangupMessage: true)
            return
        }

        guard state.url != nil,
              isPictureInPictureAllowed,
              let requestPictureInPictureHandler = state.bindings.requestPictureInPictureHandler else {
            if configuration.startMode == .audio {
                actionsSubject.send(.pictureInPictureStarted)
                return
            }
            actionsSubject.send(.dismiss)
            return
        }

        guard configuration.startMode == .video else {
            actionsSubject.send(.pictureInPictureStarted)
            return
        }

        switch await requestPictureInPictureHandler() {
        case .success:
            actionsSubject.send(.pictureInPictureStarted)
        case .failure:
            actionsSubject.send(.dismiss)
        }
    }
    
    private func setMediaState(audioEnabled: Bool, videoEnabled: Bool) async {
        let message = ElementCallWidgetMessage(direction: .toWidget,
                                               action: .mediaState,
                                               data: .init(audioEnabled: audioEnabled,
                                                           videoEnabled: videoEnabled),
                                               widgetId: widgetDriver.widgetID)
        await postMessageToWidget(message)
    }
    
    @discardableResult
    func hangup(waitingFor setupTask: Task<Void, Never>? = nil) async -> Bool {
        let message = ElementCallWidgetMessage(direction: .toWidget,
                                               action: .hangup,
                                               widgetId: widgetDriver.widgetID)
        guard let json = encodeMessage(message) else {
            return false
        }

        if state.bindings.javaScriptEvaluator == nil {
            await setupTask?.value
        }

        #if DEBUG
        SalemXStage2FSimulatorSignalingDebug.recordSenderWidgetHangupPostAttempted()
        #endif

        return await withCheckedContinuation { continuation in
            finishPendingMatrixRTCMembershipLeaveResponse(completed: false)
            pendingWidgetHangupRequestID = message.requestId
            pendingMatrixRTCMembershipLeaveResponse = .init(continuation: continuation)

            Task { [weak self] in
                guard let self else { return }

                let posted = await self.postJSONToWidget(json)
                #if DEBUG
                if posted {
                    SalemXStage2FSimulatorSignalingDebug.recordSenderWidgetHangupPostCompleted()
                }
                #endif
                if !posted {
                    self.finishPendingMatrixRTCMembershipLeaveResponse(completed: false)
                }
            }
        }
    }

    private func handleWidgetHangupResponseIfNeeded(_ message: String) -> Bool {
        guard let data = message.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["api"] as? String == ElementCallWidgetMessage.Direction.toWidget.rawValue,
              payload["action"] as? String == ElementCallWidgetMessage.Action.hangup.rawValue,
              let requestID = payload["requestId"] as? String,
              payload["response"] is [String: Any] else {
            return false
        }

        guard requestID == pendingWidgetHangupRequestID else {
            return true
        }

        #if DEBUG
        SalemXStage2FSimulatorSignalingDebug.recordSenderWidgetHangupResponseReceived()
        #endif
        pendingWidgetHangupRequestID = nil
        return true
    }

    private func finishPendingMatrixRTCMembershipLeaveResponse(completed: Bool) {
        guard let pendingMatrixRTCMembershipLeaveResponse else {
            return
        }

        self.pendingMatrixRTCMembershipLeaveResponse = nil
        pendingWidgetHangupRequestID = nil
        pendingMatrixRTCMembershipLeaveResponse.continuation.resume(returning: completed)
    }
    
    private func sendCallTerminationSignal(waitingFor setupTask: Task<Void, Never>? = nil) async {
        switch configuration.kind {
        case .genericCallLink:
            _ = await hangup(waitingFor: setupTask)
        case .roomCall(let roomProxy, _, _, _, _, _, _):
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SENDER-DISPATCH] room_id=\(roomProxy.id) step=start")
            let matrixRTCMembershipLeaveCompleted = await hangup(waitingFor: setupTask)
            await elementCallService.requestCallTermination(roomID: roomProxy.id)
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-SENDER-DISPATCH] room_id=\(roomProxy.id) step=done " +
                "matrixrtc_membership_leave_completed=\(matrixRTCMembershipLeaveCompleted)")
        }
    }
    
    private func postMessageToWidget(_ message: ElementCallWidgetMessage) async {
        guard let json = encodeMessage(message) else {
            return
        }

        await postJSONToWidget(json)
    }

    private func encodeMessage(_ message: ElementCallWidgetMessage) -> String? {
        let data: Data
        do {
            data = try JSONEncoder().encode(message)
        } catch {
            MXLog.error("Failed encoding widget message with error: \(error)")
            return nil
        }
        
        guard let json = String(data: data, encoding: .utf8) else {
            MXLog.error("Invalid data for widget message")
            return nil
        }

        return json
    }
    
    @discardableResult
    private func postJSONToWidget(_ json: String) async -> Bool {
        guard let javaScriptEvaluator = state.bindings.javaScriptEvaluator else {
            return false
        }

        do {
            let message = "postMessage(\(json), '*')"
            let result = try await javaScriptEvaluator(message)
            MXLog.debug("Evaluated javascript: \(json) with result: \(String(describing: result))")
            return true
        } catch {
            MXLog.error("Received javascript evaluation error: \(error)")
            return false
        }
    }
    
    private func handleNativeWidgetActionIfNeeded(_ message: String) async -> Bool {
        guard let data = message.data(using: .utf8),
              let requestPayloadObject = try? JSONSerialization.jsonObject(with: data),
              let requestPayload = requestPayloadObject as? [String: Any],
              let request = try? JSONDecoder().decode(ElementCallWidgetRequest.self, from: data),
              request.api == ElementCallWidgetMessage.Direction.fromWidget.rawValue,
              let action = NativeWidgetAction(rawValue: request.action) else {
            return false
        }

        switch action {
        case .close:
            let sendHangupMessage: Bool
            switch configuration.kind {
            case .roomCall:
                // Pre-join close in a direct room call must still emit a cancel/hangup signal.
                sendHangupMessage = true
            case .genericCallLink:
                sendHangupMessage = hasJoinedWidgetCall
            }
            IncomingCallTraceFile.log("[CALL-INCOMING-TRACE][PREJOIN-CANCEL-LOCAL-CLOSE] room_id=\(configuration.callRoomID) " +
                "has_joined_widget_call=\(hasJoinedWidgetCall) send_hangup_message=\(sendHangupMessage)")
            requestLocalCallTermination(sendHangupMessage: sendHangupMessage)
            Task { [weak self] in
                await self?.acknowledgeWidgetRequest(requestPayload)
            }
        case .hangup:
            requestLocalCallTermination(sendHangupMessage: false)
            Task { [weak self] in
                await self?.acknowledgeWidgetRequest(requestPayload)
            }
        case .join:
            hasJoinedWidgetCall = true
            timeoutTask = nil
            #if DEBUG
            pendingReceiverWidgetJoinRequestID = request.requestId
            SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinReceived()
            SalemXStage2FSimulatorSignalingDebug.recordReceiverMatrixRTCJoinStarted()
            #endif
            schedulePreferredAudioRouteEnforcement()
            let joinAcknowledged = await acknowledgeWidgetRequest(requestPayload)
            #if DEBUG
            if joinAcknowledged {
                SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinAcknowledged()
            }
            #endif
            await forwardWidgetJoinRequestToDriver(message)
        case .mediaState:
            let audioEnabled = request.data?.audioEnabled ?? state.isMicrophoneEnabled
            let videoEnabled = request.data?.videoEnabled ?? state.isVideoEnabled

            state.isMicrophoneEnabled = audioEnabled
            state.isVideoEnabled = videoEnabled
            MXLog.info("Element Call media diagnostics: media_state audio_enabled=\(audioEnabled) video_enabled=\(videoEnabled)")
            elementCallService.setAudioEnabled(audioEnabled, roomID: configuration.callRoomID)
            await acknowledgeWidgetRequest(requestPayload,
                                           data: [
                                               "audio_enabled": audioEnabled,
                                               "video_enabled": videoEnabled
                                           ])
        case .setAlwaysOnScreen:
            if let value = request.data?.value {
                UIApplication.shared.isIdleTimerDisabled = value
            }
            await acknowledgeWidgetRequest(requestPayload)
        }
        
        return true
    }

    private func forwardWidgetJoinRequestToDriver(_ message: String) async {
        #if DEBUG
        SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinDispatchAttempted()
        #endif

        switch await widgetDriver.handleMessage(message) {
        case .success:
            #if DEBUG
            SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinDispatchCompleted()
            #endif
            MXLog.info("Element Call media diagnostics: widget_join_forwarded_to_driver=true start_mode=\(configuration.startMode)")
        case .failure(let error):
            #if DEBUG
            SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinDispatchError(error)
            #endif
            MXLog.error("Element Call media diagnostics: widget_join_forwarded_to_driver=false error=\(error) start_mode=\(configuration.startMode)")
        }
    }
}

extension CallScreenViewModel {
    private func handleMatrixRTCWidgetResponseIfNeeded(_ message: String) {
        guard let data = message.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["api"] as? String == ElementCallWidgetMessage.Direction.fromWidget.rawValue,
              let action = payload["action"] as? String,
              let response = payload["response"] as? [String: Any],
              let requestID = payload["requestId"] as? String else {
            return
        }

        #if DEBUG
        if action == NativeWidgetAction.join.rawValue,
           requestID == pendingReceiverWidgetJoinRequestID {
            pendingReceiverWidgetJoinRequestID = nil
            SalemXStage2FSimulatorSignalingDebug.recordReceiverWidgetJoinDriverResponseReceived()
        }
        #endif

        if action == MatrixRTCWidgetAction.sendEvent,
           pendingMatrixRTCDelayedLeavePrepareRequestIDs.remove(requestID) != nil {
            if let error = response["error"] as? [String: Any] {
                #if DEBUG
                let matrixAPIError = error["matrix_api_error"] as? [String: Any]
                SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCDelayedLeavePrepareError(httpStatus: matrixAPIError?["http_status"] as? Int)
                #endif
            } else if let delayID = response["delay_id"] as? String, !delayID.isEmpty {
                matrixRTCDelayedLeaveID = delayID
                #if DEBUG
                SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCDelayedLeavePrepared()
                #endif
            } else {
                #if DEBUG
                SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCDelayedLeavePrepareError(httpStatus: nil)
                #endif
            }
        }

        if pendingMatrixRTCMembershipLeaveRequestIDs.remove(requestID) != nil {
            if let error = response["error"] as? [String: Any] {
                #if DEBUG
                let matrixAPIError = error["matrix_api_error"] as? [String: Any]
                SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCMembershipLeaveSendError(httpStatus: matrixAPIError?["http_status"] as? Int)
                #endif
                finishPendingMatrixRTCMembershipLeaveResponse(completed: false)
            } else {
                #if DEBUG
                SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCMembershipLeaveSendCompleted()
                #endif
                finishPendingMatrixRTCMembershipLeaveResponse(completed: true)
            }
        }

        #if DEBUG
        guard action == MatrixRTCWidgetAction.sendEvent,
              pendingReceiverMembershipStateSendRequestIDs.remove(requestID) != nil else {
            return
        }

        if let error = response["error"] as? [String: Any] {
            let matrixAPIError = error["matrix_api_error"] as? [String: Any]
            SalemXStage2FSimulatorSignalingDebug.recordReceiverMembershipStateSendError(httpStatus: matrixAPIError?["http_status"] as? Int)
        } else {
            SalemXStage2FSimulatorSignalingDebug.recordReceiverMembershipStateSendCompleted()
        }
        #endif
    }

    private func recordMatrixRTCWidgetRequestIfNeeded(_ message: String) {
        guard let data = message.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["api"] as? String == ElementCallWidgetMessage.Direction.fromWidget.rawValue,
              let action = payload["action"] as? String,
              let eventData = payload["data"] as? [String: Any],
              let requestID = payload["requestId"] as? String else {
            return
        }

        if action == MatrixRTCWidgetAction.updateDelayedEvent,
           pendingMatrixRTCMembershipLeaveResponse != nil,
           eventData["action"] as? String == MatrixRTCWidgetAction.sendDelayedEvent,
           let delayID = eventData["delay_id"] as? String,
           delayID == matrixRTCDelayedLeaveID,
           pendingMatrixRTCMembershipLeaveRequestIDs.insert(requestID).inserted {
            #if DEBUG
            SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCMembershipLeaveSendAttempted()
            #endif
            return
        }

        guard action == MatrixRTCWidgetAction.sendEvent,
              eventData["type"] as? String == MatrixRTCWidgetAction.membershipEventType,
              eventData["state_key"] is String,
              let content = eventData["content"] as? [String: Any] else {
            return
        }

        if content.isEmpty {
            if eventData["delay"] != nil,
               pendingMatrixRTCDelayedLeavePrepareRequestIDs.insert(requestID).inserted {
                #if DEBUG
                SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCDelayedLeavePrepareAttempted()
                #endif
            } else if eventData["delay"] == nil,
                      pendingMatrixRTCMembershipLeaveResponse != nil,
                      pendingMatrixRTCMembershipLeaveRequestIDs.insert(requestID).inserted {
                #if DEBUG
                SalemXStage2FSimulatorSignalingDebug.recordMatrixRTCMembershipLeaveSendAttempted()
                #endif
            }
        } else if eventData["delay"] == nil {
            #if DEBUG
            if pendingReceiverMembershipStateSendRequestIDs.insert(requestID).inserted {
                SalemXStage2FSimulatorSignalingDebug.recordReceiverMembershipStateSendAttempted()
            }
            #endif
        }
    }
}

extension CallScreenViewModel {
    @discardableResult
    private func acknowledgeWidgetRequest(_ requestPayload: [String: Any], data: [String: Any]? = nil) async -> Bool {
        var responsePayload = requestPayload
        responsePayload["response"] = [String: Any]()
        responsePayload["data"] = data ?? requestPayload["data"] ?? [String: Any]()
        
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: responsePayload)
        } catch {
            MXLog.error("Failed encoding widget response with error: \(error)")
            return false
        }
        
        guard let json = String(data: data, encoding: .utf8) else {
            MXLog.error("Invalid data for widget response")
            return false
        }
        
        return await postJSONToWidget(json)
    }
    
    /// This function updates the list of available audio outputs on the web side
    /// however since we actually handle switching the audio output through the OS,
    /// this is only used to inform the webview when the speaker is selected,
    /// so that the option to use the earpiece can be displayed.
    private func updateOutputsListOnWeb() async {
        guard let currentOutput = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            return
        }
        
        let deviceList = if currentOutput.portType == .builtInSpeaker {
            // This allows the webview to display the earpiece option
            "{id: '\(currentOutput.uid)', name: '\(currentOutput.portName)', forEarpiece: true, isSpeaker: true}"
        } else {
            // Doesn't matter because the switch is handled through the OS
            "{id: 'dummy', name: 'dummy'}"
        }
        
        let javaScript = "window.controls.setAvailableOutputDevices([\(deviceList)])"
        do {
            let result = try await state.bindings.javaScriptEvaluator?(javaScript)
            MXLog.debug("Evaluated  with result: \(String(describing: result))")
        } catch {
            MXLog.error("Received javascript evaluation error: \(error)")
        }
    }
    
    private static func makeRTCTransportScript(clientProxy: ClientProxyProtocol) -> String? {
        guard let homeserverURL = URL(string: clientProxy.homeserver) else {
            return nil
        }
        
        let transportPaths = ElementCallRTCTransportRequestBoundary.authorizationPaths
            .compactMap(javaScriptStringLiteral)
            .joined(separator: ",\n")
        let credentialPaths = ElementCallRTCTransportRequestBoundary.credentialObservationPaths
            .compactMap(javaScriptStringLiteral)
            .joined(separator: ",\n")
        let liveKitServiceURLLiteral = javaScriptStringLiteral(homeserverURL.appending(path: "/livekit/jwt").absoluteString)
        let homeserverLiteral = javaScriptStringLiteral(clientProxy.homeserver)
        
        guard let liveKitServiceURLLiteral, let homeserverLiteral else {
            return nil
        }

        let diagnosticsScript = makeRTCTransportDiagnosticsScript(credentialPaths: credentialPaths,
                                                                  homeserverLiteral: homeserverLiteral)
        
        let authorizationScript: String
        if let clientProxy = clientProxy as? ClientProxy,
           let accessToken = clientProxy.accessToken,
           let accessTokenLiteral = javaScriptStringLiteral(accessToken) {
            authorizationScript = [
                "    const accessToken = \(accessTokenLiteral);",
                "    const homeserverURL = new URL(\(homeserverLiteral));",
                "    const authorizationValue = `Bearer ${accessToken}`;",
                "    const shouldAuthorize = (resource) => {",
                "        try {",
                "            const resourceURL = typeof resource === \"string\"",
                "                ? new URL(resource, homeserverURL)",
                "                : new URL(resource.url, homeserverURL);",
                "            return resourceURL.origin === homeserverURL.origin && transportPaths.has(resourceURL.pathname);",
                "        } catch {",
                "            return false;",
                "        }",
                "    };",
                "    const addAuthorizationHeader = (headers) => {",
                "        const authorizedHeaders = new Headers(headers || {});",
                "        if (!authorizedHeaders.has(\"Authorization\")) {",
                "            authorizedHeaders.set(\"Authorization\", authorizationValue);",
                "        }",
                "        return authorizedHeaders;",
                "    };",
                "    const originalFetch = window.fetch && window.fetch.bind(window);",
                "    if (originalFetch) {",
                "        window.fetch = (input, init) => {",
                "            if (!shouldAuthorize(input)) {",
                "                return originalFetch(input, init);",
                "            }",
                "            if (input instanceof Request) {",
                "                return originalFetch(new Request(input, Object.assign({}, init || {}, {",
                "                    headers: addAuthorizationHeader((init && init.headers) || input.headers)",
                "                })));",
                "            }",
                "            return originalFetch(input, Object.assign({}, init || {}, {",
                "                headers: addAuthorizationHeader(init && init.headers)",
                "            }));",
                "        };",
                "    }",
                "    const originalOpen = XMLHttpRequest.prototype.open;",
                "    const originalSend = XMLHttpRequest.prototype.send;",
                "    const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;",
                "    XMLHttpRequest.prototype.open = function(method, url, ...rest) {",
                "        this.__elementXShouldAuthorizeRTCTransports = shouldAuthorize(url);",
                "        this.__elementXHasAuthorizationHeader = false;",
                "        return originalOpen.call(this, method, url, ...rest);",
                "    };",
                "    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {",
                "        if (String(name).toLowerCase() === \"authorization\") {",
                "            this.__elementXHasAuthorizationHeader = true;",
                "        }",
                "        return originalSetRequestHeader.call(this, name, value);",
                "    };",
                "    XMLHttpRequest.prototype.send = function(body) {",
                "        if (this.__elementXShouldAuthorizeRTCTransports && !this.__elementXHasAuthorizationHeader) {",
                "            originalSetRequestHeader.call(this, \"Authorization\", authorizationValue);",
                "        }",
                "        return originalSend.call(this, body);",
                "    };"
            ].joined(separator: "\n")
        } else {
            authorizationScript = ""
        }
        
        return [
            "(() => {",
            "    const transportPaths = new Set([",
            "        \(transportPaths)",
            "    ]);",
            "    const rtcTransports = [",
            "        {",
            "            type: \"livekit\",",
            "            livekit_service_url: \(liveKitServiceURLLiteral)",
            "        }",
            "    ];",
            "    globalThis.SALEMX_getRTCTransports = async () => rtcTransports;",
            diagnosticsScript,
            authorizationScript,
            "})();"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func makeRTCTransportDiagnosticsScript(credentialPaths: String, homeserverLiteral: String) -> String {
        #if DEBUG
        return [
            "    const rtcCredentialPaths = new Set([",
            "        \(credentialPaths)",
            "    ]);",
            "    const rtcCredentialHomeserverURL = new URL(\(homeserverLiteral));",
            "    const shouldObserveRTCTransport = (resource) => {",
            "        try {",
            "            const resourceURL = typeof resource === \"string\"",
            "                ? new URL(resource, rtcCredentialHomeserverURL)",
            "                : new URL(resource.url, rtcCredentialHomeserverURL);",
            "            return resourceURL.origin === rtcCredentialHomeserverURL.origin && rtcCredentialPaths.has(resourceURL.pathname);",
            "        } catch {",
            "            return false;",
            "        }",
            "    };",
            "    const reportRTCTransport = (stage, httpStatus) => {",
            "        try {",
            "            const handler = window.webkit?.messageHandlers?.elementCallMediaDiagnostics;",
            "            if (!handler) return;",
            "            const payload = { schemaVersion: 1, kind: \"rtc_transport\", stage };",
            "            if (Number.isInteger(httpStatus) && httpStatus >= 100 && httpStatus <= 599) {",
            "                payload.httpStatus = httpStatus;",
            "            }",
            "            handler.postMessage(JSON.stringify(payload));",
            "        } catch {}",
            "    };",
            "    const observeRTCTransportRequest = (request) => {",
            "        reportRTCTransport(\"request\");",
            "        return request.then((response) => {",
            "            reportRTCTransport(\"response\", response.status);",
            "            return response;",
            "        }, (error) => {",
            "            reportRTCTransport(\"response\");",
            "            throw error;",
            "        });",
            "    };",
            "    const originalRTCTransportFetch = window.fetch && window.fetch.bind(window);",
            "    if (originalRTCTransportFetch) {",
            "        window.fetch = (input, init) => {",
            "            const request = originalRTCTransportFetch(input, init);",
            "            return shouldObserveRTCTransport(input) ? observeRTCTransportRequest(request) : request;",
            "        };",
            "    }",
            "    const originalRTCTransportOpen = XMLHttpRequest.prototype.open;",
            "    const originalRTCTransportSend = XMLHttpRequest.prototype.send;",
            "    XMLHttpRequest.prototype.open = function(method, url, ...rest) {",
            "        this.__elementXShouldObserveRTCCredentials = shouldObserveRTCTransport(url);",
            "        return originalRTCTransportOpen.call(this, method, url, ...rest);",
            "    };",
            "    XMLHttpRequest.prototype.send = function(body) {",
            "        if (this.__elementXShouldObserveRTCCredentials) {",
            "            reportRTCTransport(\"request\");",
            "            this.addEventListener(\"loadend\", () => {",
            "                reportRTCTransport(\"response\", this.status);",
            "            }, { once: true });",
            "        }",
            "        return originalRTCTransportSend.call(this, body);",
            "    };"
        ].joined(separator: "\n")
        #else
        return ""
        #endif
    }
    
    private static func javaScriptStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return literal
    }
}
