//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import AVKit
import Foundation

enum CallScreenViewModelAction {
    case pictureInPictureIsAvailable(AVPictureInPictureController)
    case pictureInPictureStarted
    case pictureInPictureStopped
    case dismiss
}

struct DirectRoomCallDetails {
    let title: String
    let subtitle: String?
    let avatar: RoomAvatar
    let startMode: ElementCallStartMode
}

struct CallWebViewSessionIdentity: Equatable, CustomStringConvertible {
    private let roomID: String
    let sessionGeneration: UUID

    init(roomID: String, sessionGeneration: UUID = UUID()) {
        self.roomID = roomID
        self.sessionGeneration = sessionGeneration
    }

    var description: String {
        "room=redacted session_generation=redacted"
    }
}

struct CallWebViewDocumentIdentity: Equatable, CustomStringConvertible {
    let webViewID: UUID
    let documentGeneration: UUID
    let sessionIdentity: CallWebViewSessionIdentity

    var description: String {
        "webview=redacted document_generation=redacted \(sessionIdentity)"
    }
}

struct CallWebViewBinding {
    let identity: CallWebViewDocumentIdentity
    let javaScriptEvaluator: (String) async throws -> Any?
    let requestPictureInPictureHandler: (() async -> Result<Void, CallScreenError>)?
}

struct CallScreenViewState: BindableState {
    let script: String?
    let rtcTransportScript: String?
    var url: URL?
    let isGenericCallLink: Bool
    let directRoomCallDetails: DirectRoomCallDetails?
    let webViewSessionIdentity: CallWebViewSessionIdentity
    var isMicrophoneEnabled: Bool
    var isVideoEnabled: Bool
    var isSpeakerphoneEnabled: Bool
    
    let certificateValidator: CertificateValidatorHookProtocol
    
    var bindings = Bindings()
}

struct Bindings {
    var alertInfo: AlertInfo<UUID>?
}

enum CallScreenViewAction: CustomStringConvertible {
    case urlChanged(URL?)
    case pictureInPictureIsAvailable(AVPictureInPictureController)
    case navigateBack
    case pictureInPictureWillStop
    case endCall
    case toggleMicrophone
    case toggleVideo
    case toggleSpeakerphone
    case mediaCapturePermissionGranted
    case outputDeviceSelected(deviceID: String)
    case widgetAction(message: String)
    case elementCallMediaDiagnostics(message: String)
    case callWebViewCreated(webViewID: UUID, sessionIdentity: CallWebViewSessionIdentity)
    case callWebViewDocumentLoading(CallWebViewDocumentIdentity)
    case callWebViewBindingReady(CallWebViewBinding)
    case callWebViewDismantled(CallWebViewDocumentIdentity)

    var description: String {
        switch self {
        case .urlChanged:
            "urlChanged"
        case .pictureInPictureIsAvailable:
            "pictureInPictureIsAvailable"
        case .navigateBack:
            "navigateBack"
        case .pictureInPictureWillStop:
            "pictureInPictureWillStop"
        case .endCall:
            "endCall"
        case .toggleMicrophone:
            "toggleMicrophone"
        case .toggleVideo:
            "toggleVideo"
        case .toggleSpeakerphone:
            "toggleSpeakerphone"
        case .mediaCapturePermissionGranted:
            "mediaCapturePermissionGranted"
        case .outputDeviceSelected:
            "outputDeviceSelected"
        case .widgetAction:
            "widgetAction"
        case .elementCallMediaDiagnostics:
            "elementCallMediaDiagnostics"
        case .callWebViewCreated:
            "callWebViewCreated"
        case .callWebViewDocumentLoading:
            "callWebViewDocumentLoading"
        case .callWebViewBindingReady:
            "callWebViewBindingReady"
        case .callWebViewDismantled:
            "callWebViewDismantled"
        }
    }
}

enum CallScreenError: Error {
    case pictureInPictureNotAvailable
}

enum ElementCallWebMediaDiagnosticsStage: String, Decodable, Equatable {
    case installed
    case loaded
    case mutation
    case interval
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }
}

enum ElementCallWebMediaDiagnosticsElapsedBucket: String, Decodable, Equatable {
    case underOneSecond = "under_1s"
    case underFiveSeconds = "under_5s"
    case underTenSeconds = "under_10s"
    case overTenSeconds = "over_10s"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .unknown
    }
}

struct ElementCallWebMediaDiagnosticsPayload: Decodable, Equatable, CustomStringConvertible {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case stage
        case elapsedBucket
        case videoElementCount
        case visibleVideoElementCount
        case playingVideoElementCount
        case streamBackedVideoElementCount
        case mutedVideoElementCount
    }

    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let stage: ElementCallWebMediaDiagnosticsStage
    let elapsedBucket: ElementCallWebMediaDiagnosticsElapsedBucket
    let videoElementCount: Int
    let visibleVideoElementCount: Int
    let playingVideoElementCount: Int
    let streamBackedVideoElementCount: Int
    let mutedVideoElementCount: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        stage = try container.decodeIfPresent(ElementCallWebMediaDiagnosticsStage.self, forKey: .stage) ?? .unknown
        elapsedBucket = try container.decodeIfPresent(ElementCallWebMediaDiagnosticsElapsedBucket.self, forKey: .elapsedBucket) ?? .unknown
        videoElementCount = try Self.safeCount(container.decodeIfPresent(Int.self, forKey: .videoElementCount))
        visibleVideoElementCount = try Self.safeCount(container.decodeIfPresent(Int.self, forKey: .visibleVideoElementCount))
        playingVideoElementCount = try Self.safeCount(container.decodeIfPresent(Int.self, forKey: .playingVideoElementCount))
        streamBackedVideoElementCount = try Self.safeCount(container.decodeIfPresent(Int.self, forKey: .streamBackedVideoElementCount))
        mutedVideoElementCount = try Self.safeCount(container.decodeIfPresent(Int.self, forKey: .mutedVideoElementCount))
    }

    static func decode(message: String) -> ElementCallWebMediaDiagnosticsPayload? {
        guard let data = message.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ElementCallWebMediaDiagnosticsPayload.self, from: data),
              payload.schemaVersion == supportedSchemaVersion else {
            return nil
        }

        return payload
    }

    var hasRemoteRendererCandidate: Bool {
        visibleVideoElementCount > 1 || streamBackedVideoElementCount > 1
    }

    var description: String {
        "schema=\(schemaVersion) stage=\(stage.rawValue) elapsed=\(elapsedBucket.rawValue) " +
            "videos=\(videoElementCount) visible=\(visibleVideoElementCount) playing=\(playingVideoElementCount) " +
            "stream_backed=\(streamBackedVideoElementCount) muted=\(mutedVideoElementCount) " +
            "remote_renderer_candidate=\(hasRemoteRendererCandidate)"
    }

    private static func safeCount(_ count: Int?) -> Int {
        min(max(count ?? 0, 0), 99)
    }
}

enum ElementCallRTCTransportDiagnosticsStage: String, Decodable, Equatable {
    case request
    case response
}

enum ElementCallRTCTransportRequestBoundary {
    struct Policy: Equatable {
        let shouldAuthorize: Bool
        let shouldObserveCredentials: Bool
    }

    static let authorizationPaths = [
        "/_matrix/client/unstable/org.matrix.msc4143/rtc/transports",
        "/_matrix/client/v1/rtc/transports",
        "/livekit/jwt"
    ]

    static let credentialObservationPaths = [
        "/livekit/jwt/get_token",
        "/livekit/jwt/sfu/get"
    ]

    static func policy(for requestURL: URL, homeserverURL: URL) -> Policy {
        guard isSameOrigin(requestURL, homeserverURL) else {
            return Policy(shouldAuthorize: false, shouldObserveCredentials: false)
        }

        return Policy(shouldAuthorize: authorizationPaths.contains(requestURL.path),
                      shouldObserveCredentials: credentialObservationPaths.contains(requestURL.path))
    }

    private static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased() &&
            lhs.host?.lowercased() == rhs.host?.lowercased() &&
            effectivePort(for: lhs) == effectivePort(for: rhs)
    }

    private static func effectivePort(for url: URL) -> Int? {
        if let port = url.port {
            return port
        }

        switch url.scheme?.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
        }
    }
}

struct ElementCallRTCTransportDiagnosticsPayload: Decodable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case kind
        case stage
        case httpStatus
    }

    static let supportedSchemaVersion = 1
    static let supportedKind = "rtc_transport"

    let schemaVersion: Int
    let stage: ElementCallRTCTransportDiagnosticsStage
    let httpStatus: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        stage = try container.decode(ElementCallRTCTransportDiagnosticsStage.self, forKey: .stage)
        let kind = try container.decode(String.self, forKey: .kind)
        guard kind == Self.supportedKind else {
            throw DecodingError.dataCorruptedError(forKey: .kind,
                                                   in: container,
                                                   debugDescription: "Unsupported RTC transport diagnostics kind")
        }

        if let decodedHTTPStatus = try container.decodeIfPresent(Int.self, forKey: .httpStatus),
           (100...599).contains(decodedHTTPStatus) {
            httpStatus = decodedHTTPStatus
        } else {
            httpStatus = nil
        }
    }

    static func decode(message: String) -> Self? {
        guard let data = message.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Self.self, from: data),
              payload.schemaVersion == supportedSchemaVersion else {
            return nil
        }

        return payload
    }
}

/// Identifies each event handler used by the CallScreen webview
///
/// The names of the enum need to always match the name of the handlers on the webview.
enum CallScreenJavaScriptMessageName: String, CaseIterable {
    /// Widget actions's handler.
    case widgetAction
    /// Used for redacted Element Call web-side media diagnostics.
    case elementCallMediaDiagnostics
    /// Used to show the native AVRoutePickerView.
    case showNativeOutputDevicePicker
    /// Used to determine if the webview has selected the earpiece or not.
    case onOutputDeviceSelect
    /// Used to handle the webview back button
    case onBackButtonPressed
    
    private var postMessageScript: String {
        switch self {
        case .widgetAction:
            """
            window.addEventListener(
                "message",
                (event) => {
                    let message = {data: event.data, origin: event.origin};
                    if (message.data.response && message.data.api == "toWidget"
                    || !message.data.response && message.data.api == "fromWidget") {
                        window.webkit.messageHandlers.\(rawValue).postMessage(JSON.stringify(message.data));
                    } else {
                        console.log("-- skipped event handling by the client because it is send from the client itself.");
                    }
                },
                false,
            );
            """
        case .elementCallMediaDiagnostics:
            """
            (() => {
                const handler = window.webkit?.messageHandlers?.\(rawValue);
                if (!handler || window.__elementXMediaDiagnosticsInstalled) {
                    return;
                }
                window.__elementXMediaDiagnosticsInstalled = true;
                const startedAt = Date.now();
                let lastPayload = "";
                const elapsedBucket = () => {
                    const elapsed = Date.now() - startedAt;
                    if (elapsed < 1000) { return "under_1s"; }
                    if (elapsed < 5000) { return "under_5s"; }
                    if (elapsed < 10000) { return "under_10s"; }
                    return "over_10s";
                };
                const isVisible = (element) => {
                    const rect = element.getBoundingClientRect();
                    const style = window.getComputedStyle(element);
                    return rect.width > 0
                        && rect.height > 0
                        && style.display !== "none"
                        && style.visibility !== "hidden"
                        && style.opacity !== "0";
                };
                const snapshot = (stage) => {
                    const videos = Array.from(document.querySelectorAll("video"));
                    return {
                        schemaVersion: 1,
                        stage,
                        elapsedBucket: elapsedBucket(),
                        videoElementCount: videos.length,
                        visibleVideoElementCount: videos.filter(isVisible).length,
                        playingVideoElementCount: videos.filter((video) => !video.paused && !video.ended && video.readyState > 2).length,
                        streamBackedVideoElementCount: videos.filter((video) => !!video.srcObject).length,
                        mutedVideoElementCount: videos.filter((video) => video.muted).length,
                    };
                };
                const emit = (stage) => {
                    try {
                        const payload = JSON.stringify(snapshot(stage));
                        if (payload !== lastPayload) {
                            lastPayload = payload;
                            handler.postMessage(payload);
                        }
                    } catch {
                    }
                };
                window.addEventListener("load", () => emit("loaded"));
                const observer = new MutationObserver(() => emit("mutation"));
                observer.observe(document.documentElement, {
                    attributes: true,
                    childList: true,
                    subtree: true,
                });
                window.setInterval(() => emit("interval"), 3000);
                emit("installed");
            })();
            """
        case .showNativeOutputDevicePicker:
            """
            window.controls.\(rawValue) = () => {
                window.webkit.messageHandlers.\(rawValue).postMessage("");
            };
            """
        case .onOutputDeviceSelect:
            """
            window.controls.\(rawValue) = (id) => {
                window.webkit.messageHandlers.\(rawValue).postMessage(id);
            };
            """
        case .onBackButtonPressed:
            """
            window.controls.\(rawValue) = () => {
                window.webkit.messageHandlers.\(rawValue).postMessage("");
            }
            """
        }
    }
    
    static var allCasesInjectionScript: String {
        allCases.map(\.postMessageScript).joined(separator: "\n")
    }
}

struct DecodedWidgetMessage: Decodable {
    private static let decoder = JSONDecoder()
    private static let contentLoadedAction = "content_loaded"
    private static let fromWidget = "fromWidget"
    
    let action: String?
    let api: String?
    
    static func decode(message: String) throws -> DecodedWidgetMessage? {
        guard let data = message.data(using: .utf8) else {
            return nil
        }
        return try decoder.decode(DecodedWidgetMessage.self, from: data)
    }
    
    var hasLoaded: Bool {
        action == Self.contentLoadedAction && api == Self.fromWidget
    }
}

struct ElementCallWidgetRequest: Decodable {
    struct Data: Decodable {
        let audioEnabled: Bool?
        let videoEnabled: Bool?
        let value: Bool?
        
        enum CodingKeys: String, CodingKey {
            case audioEnabled = "audio_enabled"
            case videoEnabled = "video_enabled"
            case value
        }
    }
    
    let api: String
    let action: String
    let widgetId: String
    let requestId: String
    let data: Data?
}
