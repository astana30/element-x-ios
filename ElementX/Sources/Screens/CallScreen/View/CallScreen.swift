//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVKit
import Combine
import Compound
import EmbeddedElementCall
import SFSafeSymbols
import SwiftUI
import WebKit

struct CallScreen: View {
    @ObservedObject var context: CallScreenViewModel.Context
    
    var body: some View {
        ElementNavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(context.viewState.isGenericCallLink ? .visible : .hidden, for: .navigationBar)
                .toolbar { toolbar }
        }
        .alert(item: $context.alertInfo)
        .preferredColorScheme(context.viewState.isGenericCallLink ? .dark : nil)
    }
    
    var content: some View {
        ZStack {
            if showsNativeDirectAudioChrome {
                DirectRoomAudioCallBackground()
            } else if showsNativeDirectVideoChrome {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.compound.bgCanvasDefault,
                                            Color.compound.bgCanvasDefault.opacity(0.92),
                                            .clear],
                                   startPoint: .top,
                                   endPoint: .bottom)
                        .frame(height: 132)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)

                    Spacer()
                }
            }

            if context.viewState.url == nil {
                if !showsNativeDirectAudioChrome {
                    ProgressView()
                }
            } else {
                CallView(url: context.viewState.url, viewModelContext: context)
                    // This URL is stable, forces view reloads if this representable is ever reused for another url
                    .id(context.viewState.url)
                    .opacity(hidesEmbeddedCallView ? 0.02 : 1)
                    .allowsHitTesting(!hidesEmbeddedCallView)
                    .accessibilityHidden(hidesEmbeddedCallView)
                    .ignoresSafeArea(edges: .bottom)
            }

            if let directRoomCallDetails = context.viewState.directRoomCallDetails {
                if directRoomCallDetails.startMode == .audio {
                    VStack(spacing: 0) {
                        DirectRoomCallHeader(details: directRoomCallDetails,
                                             mediaProvider: context.mediaProvider) {
                            context.send(viewAction: .navigateBack)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        DirectRoomAudioCallChrome(details: directRoomCallDetails,
                                                  mediaProvider: context.mediaProvider,
                                                  isMicrophoneEnabled: context.viewState.isMicrophoneEnabled,
                                                  isSpeakerphoneEnabled: context.viewState.isSpeakerphoneEnabled,
                                                  isConnecting: context.viewState.url == nil,
                                                  toggleMicrophoneAction: {
                                                      context.send(viewAction: .toggleMicrophone)
                                                  },
                                                  toggleSpeakerphoneAction: {
                                                      context.send(viewAction: .toggleSpeakerphone)
                                                  },
                                                  endCallAction: {
                                                      context.send(viewAction: .endCall)
                                                  })
                    }
                } else {
                    DirectRoomVideoCallChrome(details: directRoomCallDetails,
                                              isMicrophoneEnabled: context.viewState.isMicrophoneEnabled,
                                              isVideoEnabled: context.viewState.isVideoEnabled,
                                              isConnecting: context.viewState.url == nil,
                                              toggleMicrophoneAction: {
                                                  context.send(viewAction: .toggleMicrophone)
                                              },
                                              toggleVideoAction: {
                                                  context.send(viewAction: .toggleVideo)
                                              },
                                              endCallAction: {
                                                  context.send(viewAction: .endCall)
                                              },
                                              dismissAction: {
                                                  context.send(viewAction: .navigateBack)
                                              })
                }
            }
        }
    }

    private var showsNativeDirectAudioChrome: Bool {
        context.viewState.directRoomCallDetails?.startMode == .audio
    }

    private var showsNativeDirectVideoChrome: Bool {
        context.viewState.directRoomCallDetails?.startMode == .video
    }

    private var hidesEmbeddedCallView: Bool {
        showsNativeDirectAudioChrome
    }
    
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { context.send(viewAction: .navigateBack) } label: {
                Image(systemSymbol: .chevronBackward)
                    .fontWeight(.semibold)
            }
        }
    }
}

private struct DirectRoomAudioCallBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.compound.bgCanvasDefault,
                                    .compound.bgCanvasDefaultLevel1,
                                    .compound.bgSubtleSecondaryLevel0],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)

            Circle()
                .fill(Color.compound.bgActionPrimaryRest.opacity(0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 36)
                .offset(x: 120, y: -220)

            Circle()
                .fill(Color.compound.bgCanvasDefaultLevel1.opacity(0.92))
                .frame(width: 320, height: 320)
                .blur(radius: 32)
                .offset(x: -110, y: 250)
        }
        .ignoresSafeArea()
    }
}

private struct DirectRoomCallHeader: View {
    let details: DirectRoomCallDetails
    let mediaProvider: MediaProviderProtocol?
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoomAvatarImage(avatar: details.avatar,
                            avatarSize: .custom(52),
                            mediaProvider: mediaProvider)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(details.title)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    DirectRoomCallKindBadge(startMode: details.startMode)
                }

                if let subtitle = details.subtitle {
                    Text(subtitle)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(1)
                }
            }

            Button(action: dismissAction) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.compound.iconPrimary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.compound.bgCanvasDefaultLevel1))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.compound.bgCanvasDefaultLevel1.opacity(0.96)))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.compound._bgSubtleSecondaryAlpha, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
    }
}

private struct DirectRoomCallKindBadge: View {
    let startMode: ElementCallStartMode

    var body: some View {
        HStack(spacing: 4) {
            Image(systemSymbol: startMode == .audio ? .phoneFill : .videoFill)
            Text(startMode == .audio ? L10n.commonAudio : L10n.commonVideo)
        }
        .font(.compound.bodySM)
        .foregroundStyle(.compound.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.compound.bgBadgeDefault))
    }
}

private struct DirectRoomVideoCallChrome: View {
    let details: DirectRoomCallDetails
    let isMicrophoneEnabled: Bool
    let isVideoEnabled: Bool
    let isConnecting: Bool
    let toggleMicrophoneAction: () -> Void
    let toggleVideoAction: () -> Void
    let endCallAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DirectRoomVideoCallHeader(details: details, dismissAction: dismissAction)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if isConnecting {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    DirectRoomCallKindBadge(startMode: details.startMode)
                }
                .padding(.top, 18)
            }

            Spacer()

            VStack(spacing: 0) {
                LinearGradient(colors: [.clear,
                                        Color.black.opacity(0.12),
                                        Color.black.opacity(0.4)],
                               startPoint: .top,
                               endPoint: .bottom)
                    .frame(height: 140)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 24) {
                            DirectRoomCallControlButton(symbolName: isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
                                                        isHighlighted: !isMicrophoneEnabled,
                                                        accessibilityLabel: isMicrophoneEnabled ? L10n.commonMute : L10n.commonUnmute,
                                                        accessibilityIdentifier: A11yIdentifiers.callScreen.mute,
                                                        action: toggleMicrophoneAction)

                            DirectRoomCallControlButton(symbolName: isVideoEnabled ? "video.fill" : "video.slash.fill",
                                                        isHighlighted: !isVideoEnabled,
                                                        accessibilityLabel: L10n.screenRoomAttachmentSourceCamera,
                                                        accessibilityIdentifier: A11yIdentifiers.callScreen.camera,
                                                        action: toggleVideoAction)

                            DirectRoomCallControlButton(symbolName: "phone.down.fill",
                                                        style: .destructive,
                                                        accessibilityLabel: UntranslatedL10n.actionEndCall,
                                                        accessibilityIdentifier: A11yIdentifiers.callScreen.endCall,
                                                        action: endCallAction)
                        }
                        .padding(.bottom, 34)
                    }
            }
        }
    }
}

private struct DirectRoomVideoCallHeader: View {
    let details: DirectRoomCallDetails
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            circularButton(symbolName: "chevron.down", action: dismissAction)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text(details.title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                if let subtitle = details.subtitle {
                    Text(subtitle)
                        .font(.compound.bodySM)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.28)))

            Spacer(minLength: 0)

            circularButton(symbolName: "video.fill") { }
                .hidden()
        }
    }

    private func circularButton(symbolName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.28)))
        }
        .buttonStyle(.plain)
    }
}

private struct DirectRoomAudioCallChrome: View {
    let details: DirectRoomCallDetails
    let mediaProvider: MediaProviderProtocol?
    let isMicrophoneEnabled: Bool
    let isSpeakerphoneEnabled: Bool
    let isConnecting: Bool
    let toggleMicrophoneAction: () -> Void
    let toggleSpeakerphoneAction: () -> Void
    let endCallAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 44)

            ZStack {
                Circle()
                    .fill(.compound.bgCanvasDefaultLevel1.opacity(0.78))
                    .frame(width: 176, height: 176)

                Circle()
                    .strokeBorder(Color.compound._bgSubtleSecondaryAlpha, lineWidth: 1)
                    .frame(width: 176, height: 176)

                RoomAvatarImage(avatar: details.avatar,
                                avatarSize: .custom(132),
                                mediaProvider: mediaProvider)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 24, y: 14)

            VStack(spacing: 12) {
                Text(details.title)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let subtitle = details.subtitle {
                    Text(subtitle)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                if isConnecting {
                    ProgressView()
                        .tint(.compound.iconPrimary)
                        .controlSize(.small)
                        .padding(.top, 8)
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)

            Spacer()

            HStack(spacing: 24) {
                DirectRoomCallControlButton(symbolName: isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
                                            isHighlighted: !isMicrophoneEnabled,
                                            accessibilityLabel: isMicrophoneEnabled ? L10n.commonMute : L10n.commonUnmute,
                                            accessibilityIdentifier: A11yIdentifiers.callScreen.mute,
                                            action: toggleMicrophoneAction)

                DirectRoomCallControlButton(symbolName: "speaker.wave.3.fill",
                                            isHighlighted: isSpeakerphoneEnabled,
                                            accessibilityLabel: UntranslatedL10n.commonSpeaker,
                                            accessibilityIdentifier: A11yIdentifiers.callScreen.speaker,
                                            action: toggleSpeakerphoneAction)

                DirectRoomCallControlButton(symbolName: "phone.down.fill",
                                            style: .destructive,
                                            accessibilityLabel: UntranslatedL10n.actionEndCall,
                                            accessibilityIdentifier: A11yIdentifiers.callScreen.endCall,
                                            action: endCallAction)
            }
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 24)
    }
}

private struct DirectRoomCallControlButton: View {
    enum Style {
        case standard
        case destructive
    }

    let symbolName: String
    var isHighlighted = false
    var style: Style = .standard
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 68, height: 68)
                .background(background)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var background: some View {
        Circle()
            .fill(backgroundColor)
            .overlay {
                Circle()
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .shadow(color: Color.black.opacity(style == .destructive ? 0.16 : 0.08), radius: 16, y: 10)
    }

    private var foregroundColor: Color {
        switch style {
        case .standard:
            isHighlighted ? .compound.iconOnSolidPrimary : .compound.iconPrimary
        case .destructive:
            .compound.iconOnSolidPrimary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .standard:
            isHighlighted ? .compound.bgActionPrimaryRest : .compound.bgCanvasDefaultLevel1.opacity(0.96)
        case .destructive:
            .compound.bgCriticalPrimary
        }
    }

    private var borderColor: Color {
        switch style {
        case .standard:
            isHighlighted ? .clear : .compound._bgSubtleSecondaryAlpha
        case .destructive:
            .clear
        }
    }

    private var borderWidth: CGFloat {
        switch style {
        case .standard:
            isHighlighted ? 0 : 1
        case .destructive:
            0
        }
    }
}

private struct CallView: UIViewRepresentable {
    /// The top-level view this representable displays. It wraps the web view when picture in picture isn't running.
    typealias WebViewWrapper = UIView
    
    let url: URL?
    let viewModelContext: CallScreenViewModel.Context
    
    func makeUIView(context: Context) -> WebViewWrapper {
        context.coordinator.webViewWrapper
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModelContext: viewModelContext)
    }
    
    func updateUIView(_ callWebView: WebViewWrapper, context: Context) {
        if let url {
            context.coordinator.load(url)
        }
    }
    
    @MainActor
    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, AVPictureInPictureControllerDelegate {
        private weak var viewModelContext: CallScreenViewModel.Context?
        private let certificateValidator: CertificateValidatorHookProtocol
        
        private var webView: WKWebView!
        private var pictureInPictureController: AVPictureInPictureController?
        private let pictureInPictureViewController: AVPictureInPictureVideoCallViewController
        private let allowsPictureInPicture: Bool
        private var routePickerView: AVRoutePickerView!
        
        /// The view to be shown in the app. This will contain the web view when picture in picture isn't running.
        let webViewWrapper = WebViewWrapper(frame: .zero)
        
        private var url: URL!
        
        init(viewModelContext: CallScreenViewModel.Context) {
            self.viewModelContext = viewModelContext
            certificateValidator = viewModelContext.viewState.certificateValidator
            allowsPictureInPicture = viewModelContext.viewState.isGenericCallLink || viewModelContext.viewState.directRoomCallDetails?.startMode == .video
            pictureInPictureViewController = AVPictureInPictureVideoCallViewController()
            pictureInPictureViewController.preferredContentSize = CGSize(width: 1920, height: 1080)
            
            super.init()
            
            DispatchQueue.main.async { // Avoid `Publishing changes from within view update` warnings
                viewModelContext.javaScriptEvaluator = self.evaluateJavaScript
                viewModelContext.requestPictureInPictureHandler = self.requestPictureInPicture
            }
            
            let configuration = WKWebViewConfiguration()
            
            let userContentController = WKUserContentController()
            CallScreenJavaScriptMessageName.allCases.forEach {
                userContentController.add(WKScriptMessageHandlerWrapper(self), name: $0.rawValue)
            }
            
            // Required to allow a webview that uses file URL to load its own assets
            configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
            configuration.userContentController = userContentController
            configuration.allowsInlineMediaPlayback = true
            configuration.allowsPictureInPictureMediaPlayback = true
            
            if let script = viewModelContext.viewState.script {
                let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
                configuration.userContentController.addUserScript(userScript)
            }
            
            if let rtcTransportScript = viewModelContext.viewState.rtcTransportScript {
                let userScript = WKUserScript(source: rtcTransportScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                configuration.userContentController.addUserScript(userScript)
            }
            
            webView = WKWebView(frame: .zero, configuration: configuration)
            webView.uiDelegate = self
            webView.navigationDelegate = self
            webView.isInspectable = true
            
            webView.customUserAgent = UserAgentBuilder.makeASCIIUserAgent()
            
            // https://stackoverflow.com/a/77963877/730924
            webView.allowsLinkPreview = true
            
            // Try matching Element Call colors
            webView.isOpaque = false
            webView.backgroundColor = .compound.bgCanvasDefault
            webView.scrollView.backgroundColor = .compound.bgCanvasDefault
            
            // This button is always hidden and is only used to be programmaticaly tapped
            routePickerView = AVRoutePickerView(frame: .zero)
            routePickerView.isHidden = true
            routePickerView.isUserInteractionEnabled = false
            webView.addSubview(routePickerView)
            
            webViewWrapper.addMatchedSubview(webView)
            
            if allowsPictureInPicture, AVPictureInPictureController.isPictureInPictureSupported() {
                let pictureInPictureController = AVPictureInPictureController(contentSource: .init(activeVideoCallSourceView: webViewWrapper,
                                                                                                   contentViewController: pictureInPictureViewController))
                pictureInPictureController.delegate = self
                self.pictureInPictureController = pictureInPictureController
                viewModelContext.send(viewAction: .pictureInPictureIsAvailable(pictureInPictureController))
            }
        }
        
        func load(_ url: URL) {
            self.url = url
            // The only file URL we allow is the one coming from our own local ElementCall bundle, so it's okay to allow read permission only to our local EC bundle
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: EmbeddedElementCall.bundle.bundleURL)
            } else {
                let request = URLRequest(url: url)
                webView.load(request)
            }
        }
        
        func evaluateJavaScript(_ script: String) async throws -> Any? {
            // After testing different scenarios it seems that when using async/await version of these
            // methods wkwebView expects JavaScript to return with a value (something other than Void),
            // if there is no value returning from the JavaScript that you evaluate you will have a crash.
            try await withCheckedThrowingContinuation { [weak self] continuaton in
                self?.webView.evaluateJavaScript(script) { result, error in
                    if let error {
                        continuaton.resume(throwing: error)
                    } else {
                        continuaton.resume(returning: result)
                    }
                }
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let handlerID = CallScreenJavaScriptMessageName(rawValue: message.name) else {
                return
            }
            
            switch handlerID {
            case .widgetAction:
                guard let message = message.body as? String else { return }
                viewModelContext?.send(viewAction: .widgetAction(message: message))
            case .elementCallMediaDiagnostics:
                guard let message = message.body as? String else { return }
                viewModelContext?.send(viewAction: .elementCallMediaDiagnostics(message: message))
            case .showNativeOutputDevicePicker:
                DispatchQueue.main.async {
                    self.tapRoutePickerView()
                }
            case .onOutputDeviceSelect:
                guard let deviceID = message.body as? String else { return }
                viewModelContext?.send(viewAction: .outputDeviceSelected(deviceID: deviceID))
            case .onBackButtonPressed:
                viewModelContext?.send(viewAction: .navigateBack)
            }
        }
        
        /// This function is called by the webview output routing button
        /// it allows to open the OS output selector using the hidden button.
        private func tapRoutePickerView() {
            guard let button = routePickerView.subviews.first(where: { $0 is UIButton }) as? UIButton else {
                return
            }
            
            button.sendActions(for: .touchUpInside)
        }
        
        // MARK: - WKUIDelegate
        
        func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
            // Allow if the origin is local, otherwise don't allow permissions for domains different than what the call was started on
            guard origin.protocol == "file" || origin.host == url.host else {
                return .deny
            }
            
            MXLog.info("Element Call media diagnostics: media_capture_permission=granted kind=\(safeMediaCaptureKind(type))")
            viewModelContext?.send(viewAction: .mediaCapturePermissionGranted)
            return .grant
        }

        private func safeMediaCaptureKind(_ type: WKMediaCaptureType) -> String {
            switch type {
            case .camera:
                "camera"
            case .microphone:
                "microphone"
            case .cameraAndMicrophone:
                "camera_and_microphone"
            @unknown default:
                "unknown"
            }
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            await certificateValidator.respondTo(challenge)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if let navigationURL = navigationAction.request.url {
                // Do not allow navigation to a different URL scheme.
                if navigationURL.scheme != url.scheme {
                    return .cancel
                }
                
                // Allow any content from the main URL.
                if navigationURL.host == url.host {
                    return .allow
                }
            }
            
            // Additionally allow any embedded content such as captchas.
            if let targetFrame = navigationAction.targetFrame, !targetFrame.isMainFrame {
                return .allow
            }
            
            // Otherwise the request is invalid.
            return .cancel
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            viewModelContext?.send(viewAction: .urlChanged(webView.url))
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            MXLog.error("Call webview navigation failed: \(error)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            MXLog.error("Call webview provisional navigation failed: \(error)")
        }
        
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            MXLog.error("Call webview content process terminated.")
        }
        
        // MARK: - Picture in Picture
        
        func requestPictureInPicture() async -> Result<Void, CallScreenError> {
            guard allowsPictureInPicture,
                  let pictureInPictureController,
                  pictureInPictureController.isPictureInPicturePossible,
                  case .success(true) = await webViewCanEnterPictureInPicture() else {
                return .failure(.pictureInPictureNotAvailable)
            }
            
            pictureInPictureController.startPictureInPicture()
            return .success(())
        }
        
        func stopPictureInPicture() {
            pictureInPictureController?.stopPictureInPicture()
        }
        
        nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { @MainActor in
                // We move the view via the delegate so it works when you background the app without calling requestPictureInPicture
                pictureInPictureViewController.view.addMatchedSubview(webView)
                _ = try? await evaluateJavaScript("controls.enablePip()")
            }
        }
        
        nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { @MainActor in
                // Double check that the controller is definitely showing a page that supports picture in picture.
                // This is necessary as it doesn't get checked when backgrounding the app or tapping a notification.
                guard case .success(true) = await webViewCanEnterPictureInPicture() else {
                    MXLog.error("Picture in picture started on a webpage that doesn't support it. Ending the call.")
                    viewModelContext?.send(viewAction: .endCall)
                    return
                }
            }
        }
        
        nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { await viewModelContext?.send(viewAction: .pictureInPictureWillStop) }
        }
        
        nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { @MainActor in
                webViewWrapper.addMatchedSubview(webView)
                _ = try? await evaluateJavaScript("controls.disablePip()")
            }
        }
        
        /// Whether the web view can do picture in picture or not (e.g. it is showing an error or the page didn't load).
        private func webViewCanEnterPictureInPicture() async -> Result<Bool, CallScreenError> {
            do {
                guard let canEnterPictureInPicture = try await evaluateJavaScript("controls.canEnterPip()") as? Bool else {
                    MXLog.error("canEnterPip returned an unexpected value, skipping picture in picture.")
                    return .failure(.pictureInPictureNotAvailable)
                }
                MXLog.info("canEnterPip returned \(canEnterPictureInPicture)")
                return .success(canEnterPictureInPicture)
            } catch {
                MXLog.error("Error checking canEnterPip: \(error)")
                return .failure(.pictureInPictureNotAvailable)
            }
        }
    }

    /// Avoids retain loops between the configuration and webView coordinator
    private class WKScriptMessageHandlerWrapper: NSObject, WKScriptMessageHandler {
        private weak var coordinator: Coordinator?
        
        init(_ coordinator: Coordinator) {
            self.coordinator = coordinator
        }
        
        // MARK: - WKScriptMessageHandler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            coordinator?.userContentController(userContentController, didReceive: message)
        }
    }
}

// MARK: - Previews

struct CallScreen_Previews: PreviewProvider, TestablePreview {
    static let roomCallViewModel = {
        let clientProxy = ClientProxyMock()
        clientProxy.deviceID = "call-device-id"
        
        let roomProxy = JoinedRoomProxyMock()
        
        let widgetDriver = ElementCallWidgetDriverMock()
        widgetDriver.underlyingMessagePublisher = .init()
        widgetDriver.underlyingActions = PassthroughSubject<ElementCallWidgetDriverAction, Never>().eraseToAnyPublisher()
        widgetDriver.startBaseURLClientIDColorSchemeRageshakeURLAnalyticsConfigurationReturnValue = .success(URL.userDirectory)
        
        roomProxy.elementCallWidgetDriverDeviceIDReturnValue = widgetDriver
        
        return CallScreenViewModel(elementCallService: ElementCallServiceMock(.init()),
                                   configuration: .init(roomProxy: roomProxy,
                                                        clientProxy: clientProxy,
                                                        clientID: "io.element.elementx",
                                                        elementCallBaseURL: "https://call.element.io",
                                                        elementCallBaseURLOverride: nil,
                                                        colorScheme: .light),
                                   allowPictureInPicture: false,
                                   mediaProvider: MediaProviderMock(configuration: .init()),
                                   appHooks: AppHooks(),
                                   appSettings: ServiceLocator.shared.settings,
                                   analyticsService: ServiceLocator.shared.analytics)
    }()

    static let directAudioViewModel = makeRoomCallViewModel(startMode: .audio)
    static let directVideoViewModel = makeRoomCallViewModel(startMode: .video)
    
    static var previews: some View {
        Group {
            CallScreen(context: directAudioViewModel.context)
                .previewDisplayName("Direct Audio")

            CallScreen(context: directVideoViewModel.context)
                .previewDisplayName("Direct Video")

            CallScreen(context: roomCallViewModel.context)
                .previewDisplayName("Room Call")
        }
    }

    private static func makeRoomCallViewModel(startMode: ElementCallStartMode) -> CallScreenViewModel {
        let clientProxy = ClientProxyMock()
        clientProxy.deviceID = "call-device-id"

        let roomProxy = JoinedRoomProxyMock(.init(name: "Aigerim",
                                                  isDirect: true,
                                                  heroes: [.mockAlice]))

        let widgetDriver = ElementCallWidgetDriverMock()
        widgetDriver.underlyingMessagePublisher = .init()
        widgetDriver.underlyingActions = PassthroughSubject<ElementCallWidgetDriverAction, Never>().eraseToAnyPublisher()
        widgetDriver.startBaseURLClientIDColorSchemeRageshakeURLAnalyticsConfigurationReturnValue = .success(URL.userDirectory)

        roomProxy.elementCallWidgetDriverDeviceIDReturnValue = widgetDriver

        return CallScreenViewModel(elementCallService: ElementCallServiceMock(.init()),
                                   configuration: .init(roomProxy: roomProxy,
                                                        clientProxy: clientProxy,
                                                        clientID: "io.element.elementx",
                                                        elementCallBaseURL: "https://call.element.io",
                                                        elementCallBaseURLOverride: nil,
                                                        colorScheme: .light,
                                                        startMode: startMode),
                                   allowPictureInPicture: false,
                                   mediaProvider: MediaProviderMock(configuration: .init()),
                                   appHooks: AppHooks(),
                                   appSettings: ServiceLocator.shared.settings,
                                   analyticsService: ServiceLocator.shared.analytics)
    }
}
