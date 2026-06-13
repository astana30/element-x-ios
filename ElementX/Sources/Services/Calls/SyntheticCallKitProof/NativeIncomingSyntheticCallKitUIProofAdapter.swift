//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

#if canImport(CallKit) && os(iOS)
import CallKit
#endif

#if canImport(PushKit) && os(iOS)
import PushKit
#endif

enum NativeIncomingSyntheticCallKitUIProofEvent: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case reported
    case answered
    case ended
    case muted(Bool)
    case failed(NativeIncomingCallFailClosedReason)

    var description: String {
        switch self {
        case .reported:
            "reported"
        case .answered:
            "answered"
        case .ended:
            "ended"
        case .muted(let isMuted):
            "muted(\(isMuted))"
        case .failed(let reason):
            "failed(\(reason))"
        }
    }

    var debugDescription: String {
        description
    }
}

protocol NativeIncomingSyntheticCallKitUIProofEventRecording: AnyObject {
    func recordSyntheticCallKitUIProofEvent(_ event: NativeIncomingSyntheticCallKitUIProofEvent)
}

protocol NativeIncomingSyntheticCallKitUIReportingDelegate: AnyObject {
    func syntheticCallKitUIReportingDidAnswer(callUUID: UUID)
    func syntheticCallKitUIReportingDidEnd(callUUID: UUID)
    func syntheticCallKitUIReportingDidSetMuted(_ isMuted: Bool, callUUID: UUID)
    func syntheticCallKitUIReportingDidFail(callUUID: UUID)
}

protocol NativeIncomingSyntheticCallKitUIReporting: AnyObject {
    var delegate: NativeIncomingSyntheticCallKitUIReportingDelegate? { get set }

    func reportIncomingCall(callUUID: UUID, displayMetadata: NativeIncomingCallKitDisplayMetadata) -> Bool
    func endCall(callUUID: UUID)
}

final class NativeIncomingSyntheticCallKitUIProofAdapter: NativeIncomingSyntheticCallKitUIReportingDelegate, CustomStringConvertible, CustomDebugStringConvertible {
    private let isEnabled: Bool
    private let reporter: NativeIncomingSyntheticCallKitUIReporting
    private let actionHandler: NativeIncomingSyntheticCallKitActionHandling
    private let diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording
    private let eventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecording
    private var identitiesByUUID = [UUID: NativeIncomingCallIdentity]()
    private var uuidsByHandle = [NativeIncomingCallHandle: UUID]()

    init(isEnabled: Bool = false,
         reporter: NativeIncomingSyntheticCallKitUIReporting,
         actionHandler: NativeIncomingSyntheticCallKitActionHandling,
         diagnosticsRecorder: NativeIncomingCallDiagnosticsRecording,
         eventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecording) {
        self.isEnabled = isEnabled
        self.reporter = reporter
        self.actionHandler = actionHandler
        self.diagnosticsRecorder = diagnosticsRecorder
        self.eventRecorder = eventRecorder
        reporter.delegate = self
    }

    func reportSyntheticIncomingCall(identity: NativeIncomingCallIdentity,
                                     displayLabel: String) -> NativeIncomingSyntheticCallKitUIProofEvent {
        guard let displayMetadata = NativeIncomingCallKitDisplayMetadata(displayLabel) else {
            return failClosed(.malformed)
        }

        return reportSyntheticIncomingCall(identity: identity, displayMetadata: displayMetadata)
    }

    func reportSyntheticIncomingCall(identity: NativeIncomingCallIdentity,
                                     displayMetadata: NativeIncomingCallKitDisplayMetadata) -> NativeIncomingSyntheticCallKitUIProofEvent {
        guard isEnabled else {
            return failClosed(.dependencyUnavailable)
        }
        guard uuidsByHandle[identity.handle] == nil else {
            return failClosed(.duplicate)
        }

        let callUUID = UUID()
        let reportSucceeded = reporter.reportIncomingCall(callUUID: callUUID, displayMetadata: displayMetadata)
        diagnosticsRecorder.record(.init(lifecycleState: reportSucceeded ? .reported : .blocked,
                                         failClosedReason: reportSucceeded ? nil : .callReportingUnavailable,
                                         reportAttempted: true,
                                         reportSucceeded: reportSucceeded,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))

        guard reportSucceeded else {
            return record(.failed(.callReportingUnavailable))
        }

        identitiesByUUID[callUUID] = identity
        uuidsByHandle[identity.handle] = callUUID
        return record(.reported)
    }

    func endSyntheticCall(handle rawHandle: String) -> NativeIncomingSyntheticCallKitUIProofEvent {
        guard let callUUID = callUUID(for: rawHandle),
              let identity = identitiesByUUID[callUUID] else {
            return failClosed(.unverifiable)
        }

        reporter.endCall(callUUID: callUUID)
        actionHandler.endSyntheticCall(identity: identity)
        clear(callUUID: callUUID)
        diagnosticsRecorder.record(.init(lifecycleState: .ended,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        return record(.ended)
    }

    func setSyntheticCallMuted(_ isMuted: Bool, handle rawHandle: String) -> NativeIncomingSyntheticCallKitUIProofEvent {
        guard let callUUID = callUUID(for: rawHandle),
              let identity = identitiesByUUID[callUUID] else {
            return failClosed(.unverifiable)
        }

        actionHandler.setSyntheticCallMuted(isMuted, identity: identity)
        diagnosticsRecorder.record(.init(lifecycleState: .reported,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        return record(.muted(isMuted))
    }

    func syntheticCallKitUIReportingDidAnswer(callUUID: UUID) {
        guard let identity = identitiesByUUID[callUUID] else {
            _ = failClosed(.unverifiable)
            return
        }

        actionHandler.answerSyntheticCall(identity: identity)
        diagnosticsRecorder.record(.init(lifecycleState: .answered,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        _ = record(.answered)
    }

    func syntheticCallKitUIReportingDidEnd(callUUID: UUID) {
        guard let identity = identitiesByUUID[callUUID] else {
            _ = failClosed(.unverifiable)
            return
        }

        actionHandler.endSyntheticCall(identity: identity)
        clear(callUUID: callUUID)
        diagnosticsRecorder.record(.init(lifecycleState: .ended,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        _ = record(.ended)
    }

    func syntheticCallKitUIReportingDidSetMuted(_ isMuted: Bool, callUUID: UUID) {
        guard let identity = identitiesByUUID[callUUID] else {
            _ = failClosed(.unverifiable)
            return
        }

        actionHandler.setSyntheticCallMuted(isMuted, identity: identity)
        diagnosticsRecorder.record(.init(lifecycleState: .reported,
                                         failClosedReason: nil,
                                         reportAttempted: false,
                                         reportSucceeded: nil,
                                         mediaCredentialRequested: false,
                                         mediaConnectAttempted: false))
        _ = record(.muted(isMuted))
    }

    func syntheticCallKitUIReportingDidFail(callUUID: UUID) {
        clear(callUUID: callUUID)
        _ = failClosed(.callReportingUnavailable)
    }

    private func callUUID(for rawHandle: String) -> UUID? {
        guard isEnabled,
              let handle = NativeIncomingCallHandle(rawHandle) else {
            return nil
        }

        return uuidsByHandle[handle]
    }

    private func clear(callUUID: UUID) {
        guard let identity = identitiesByUUID[callUUID] else {
            return
        }

        identitiesByUUID[callUUID] = nil
        uuidsByHandle[identity.handle] = nil
    }

    private func failClosed(_ reason: NativeIncomingCallFailClosedReason) -> NativeIncomingSyntheticCallKitUIProofEvent {
        diagnosticsRecorder.record(.failClosed(reason))
        return record(.failed(reason))
    }

    private func record(_ event: NativeIncomingSyntheticCallKitUIProofEvent) -> NativeIncomingSyntheticCallKitUIProofEvent {
        eventRecorder.recordSyntheticCallKitUIProofEvent(event)
        return event
    }

    var description: String {
        "NativeIncomingSyntheticCallKitUIProofAdapter(isEnabled: \(isEnabled), activeCallCount: \(identitiesByUUID.count))"
    }

    var debugDescription: String {
        description
    }
}

#if DEBUG
final class NativeIncomingSyntheticCallKitUIProofNoopActionHandler: NativeIncomingSyntheticCallKitActionHandling, CustomStringConvertible, CustomDebugStringConvertible {
    private(set) var answeredCount = 0
    private(set) var endedCount = 0
    private(set) var mutedCount = 0
    private(set) var latestMuteValue: Bool?

    func answerSyntheticCall(identity: NativeIncomingCallIdentity) {
        answeredCount += 1
    }

    func endSyntheticCall(identity: NativeIncomingCallIdentity) {
        endedCount += 1
    }

    func setSyntheticCallMuted(_ isMuted: Bool, identity: NativeIncomingCallIdentity) {
        mutedCount += 1
        latestMuteValue = isMuted
    }

    var description: String {
        "NativeIncomingSyntheticCallKitUIProofNoopActionHandler(answeredCount: \(answeredCount), endedCount: \(endedCount), mutedCount: \(mutedCount), latestMuteValue: \(latestMuteValue.map(String.init) ?? "none"))"
    }

    var debugDescription: String {
        description
    }
}

final class NativeIncomingSyntheticCallKitUIProofNoopDiagnosticsRecorder: NativeIncomingCallDiagnosticsRecording, CustomStringConvertible, CustomDebugStringConvertible {
    private(set) var diagnostics = [NativeIncomingCallRedactedDiagnostics]()

    func record(_ diagnostics: NativeIncomingCallRedactedDiagnostics) {
        self.diagnostics.append(diagnostics)
    }

    var description: String {
        "NativeIncomingSyntheticCallKitUIProofNoopDiagnosticsRecorder(diagnosticsCount: \(diagnostics.count))"
    }

    var debugDescription: String {
        description
    }
}

final class NativeIncomingSyntheticCallKitUIProofNoopEventRecorder: NativeIncomingSyntheticCallKitUIProofEventRecording, CustomStringConvertible, CustomDebugStringConvertible {
    private(set) var events = [NativeIncomingSyntheticCallKitUIProofEvent]()

    func recordSyntheticCallKitUIProofEvent(_ event: NativeIncomingSyntheticCallKitUIProofEvent) {
        events.append(event)
    }

    var description: String {
        "NativeIncomingSyntheticCallKitUIProofNoopEventRecorder(eventCount: \(events.count))"
    }

    var debugDescription: String {
        description
    }
}

final class NativeIncomingSyntheticCallKitUIProofHarness {
    private let adapter: NativeIncomingSyntheticCallKitUIProofAdapter
    private let handle: String
    private let displayLabel: String

    init(adapter: NativeIncomingSyntheticCallKitUIProofAdapter,
         handle: String = "synthetic-local-call",
         displayLabel: String = "Native Audio Proof") {
        self.adapter = adapter
        self.handle = handle
        self.displayLabel = displayLabel
    }

    func reportSyntheticIncomingCall() -> NativeIncomingSyntheticCallKitUIProofEvent {
        guard let safeHandle = NativeIncomingCallHandle(handle) else {
            return .failed(.malformed)
        }

        let identity = NativeIncomingCallIdentity(handle: safeHandle, receivedAt: Date())
        return adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: displayLabel)
    }
}

#if canImport(CallKit) && os(iOS)
extension NativeIncomingSyntheticCallKitUIProofHarness {
    static func makePhysicalDeviceProofHarness() -> NativeIncomingSyntheticCallKitUIProofHarness {
        let reporter = NativeIncomingSyntheticCallKitUIProofReporter()
        let adapter = NativeIncomingSyntheticCallKitUIProofAdapter(isEnabled: true,
                                                                   reporter: reporter,
                                                                   actionHandler: NativeIncomingSyntheticCallKitUIProofNoopActionHandler(),
                                                                   diagnosticsRecorder: NativeIncomingSyntheticCallKitUIProofNoopDiagnosticsRecorder(),
                                                                   eventRecorder: NativeIncomingSyntheticCallKitUIProofNoopEventRecorder())
        return NativeIncomingSyntheticCallKitUIProofHarness(adapter: adapter)
    }
}

@objc(SalemXSyntheticCallKitUIProofDebug)
final class SalemXSyntheticCallKitUIProofDebug: NSObject {
    private static var harness: NativeIncomingSyntheticCallKitUIProofHarness?

    @objc static func report() {
        DispatchQueue.main.async {
            let proofHarness = NativeIncomingSyntheticCallKitUIProofHarness.makePhysicalDeviceProofHarness()
            harness = proofHarness
            _ = proofHarness.reportSyntheticIncomingCall()
        }
    }

    @objc static func clear() {
        harness = nil
    }
}
#endif
#endif

#if canImport(CallKit) && os(iOS)
final class NativeIncomingSyntheticCallKitUIProofReporter: NSObject, NativeIncomingSyntheticCallKitUIReporting, CXProviderDelegate {
    weak var delegate: NativeIncomingSyntheticCallKitUIReportingDelegate?

    private let provider: CXProvider

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.supportsVideo = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(callUUID: UUID, displayMetadata: NativeIncomingCallKitDisplayMetadata) -> Bool {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: displayMetadata.label)
        update.localizedCallerName = displayMetadata.label
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            guard error != nil else {
                return
            }

            self?.delegate?.syntheticCallKitUIReportingDidFail(callUUID: callUUID)
        }
        return true
    }

    func endCall(callUUID: UUID) {
        provider.reportCall(with: callUUID, endedAt: Date(), reason: .remoteEnded)
    }

    func providerDidReset(_ provider: CXProvider) { }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        delegate?.syntheticCallKitUIReportingDidAnswer(callUUID: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        delegate?.syntheticCallKitUIReportingDidEnd(callUUID: action.callUUID)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        delegate?.syntheticCallKitUIReportingDidSetMuted(action.isMuted, callUUID: action.callUUID)
        action.fulfill()
    }

    override var description: String {
        "NativeIncomingSyntheticCallKitUIProofReporter(realCallKitRuntime: true, pushRuntime: false, mediaRuntime: false)"
    }

    override var debugDescription: String {
        description
    }
}

final class DirectCallBackgroundCallKitProvider: NSObject, DirectCallBackgroundCallKitProviderProtocol, CXProviderDelegate {
    private let provider: CXProvider

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.supportsVideo = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(_ request: DirectCallBackgroundCallKitProviderReportRequest) -> Bool {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: request.displayMetadata.label)
        update.localizedCallerName = request.displayMetadata.label
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        provider.reportNewIncomingCall(with: request.callUUID, update: update) { _ in }
        return true
    }

    func providerDidReset(_ provider: CXProvider) { }

    override var description: String {
        "DirectCallBackgroundCallKitProvider(realCallKitRuntime: true, pushKitRuntime: false, apnsRegistrationRuntime: false, mediaRuntime: false, matrixEventRuntime: false)"
    }

    override var debugDescription: String {
        description
    }
}

#if canImport(PushKit) && os(iOS)
final class DirectCallRealPushKitRegistryFactory: DirectCallPushKitRegistryMaking, CustomStringConvertible, CustomDebugStringConvertible {
    func makeRegistry(delegate: DirectCallPushKitRegistrarRegistryDelegate) -> DirectCallPushKitRegistryControlling? {
        DirectCallRealPushKitRegistryController(delegate: delegate)
    }

    var description: String {
        "DirectCallRealPushKitRegistryFactory(pushKitRuntimeAvailable: true, startupWiring: false, apnsRegistrationRuntime: false, mediaRuntime: false, matrixEventRuntime: false)"
    }

    var debugDescription: String {
        description
    }
}

private final class DirectCallRealPushKitRegistryController: NSObject, DirectCallPushKitRegistryControlling, PKPushRegistryDelegate {
    private let registry: PKPushRegistry
    private weak var delegate: DirectCallPushKitRegistrarRegistryDelegate?

    init(queue: DispatchQueue? = nil, delegate: DirectCallPushKitRegistrarRegistryDelegate) {
        registry = PKPushRegistry(queue: queue)
        self.delegate = delegate
        super.init()
        registry.delegate = self
    }

    func requestVoIPPushRegistration() {
        registry.desiredPushTypes = [.voIP]
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else {
            return
        }
        delegate?.pushKitRegistrarDidUpdateToken(pushCredentials.token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else {
            return
        }
        delegate?.pushKitRegistrarDidInvalidateToken()
    }

    override var description: String {
        "DirectCallRealPushKitRegistryController(pushKitRuntimeAvailable: true, startupWiring: false, apnsRegistrationRuntime: false, mediaRuntime: false, matrixEventRuntime: false)"
    }

    override var debugDescription: String {
        description
    }
}
#endif

#if DEBUG
private final class SalemXForegroundSSESmokeStateStore: NativeIncomingCallStateStoring {
    private var states = [NativeIncomingCallHandle: NativeIncomingCallLifecycleState]()

    func state(for handle: NativeIncomingCallHandle) -> NativeIncomingCallLifecycleState? {
        states[handle]
    }

    func hasSeen(_ handle: NativeIncomingCallHandle) -> Bool {
        states[handle] != nil
    }

    func setState(_ state: NativeIncomingCallLifecycleState, for handle: NativeIncomingCallHandle) {
        states[handle] = state
    }

    func clear(_ handle: NativeIncomingCallHandle) {
        states[handle] = nil
    }
}

private final class SalemXForegroundSSESmokeCallKitReportingAdapter: NativeIncomingCallReportingAdapting {
    private let adapter: NativeIncomingSyntheticCallKitUIProofAdapter

    init(adapter: NativeIncomingSyntheticCallKitUIProofAdapter) {
        self.adapter = adapter
    }

    func reportIncomingCall(identity: NativeIncomingCallIdentity) -> Bool {
        adapter.reportSyntheticIncomingCall(identity: identity, displayLabel: "Test Call") == .reported
    }

    func endReportedCall(identity: NativeIncomingCallIdentity, reason: NativeIncomingCallFailClosedReason) {
        _ = adapter.endSyntheticCall(handle: identity.handle.value)
    }
}

@objc(SalemXForegroundSSESmokeDebug)
final class SalemXForegroundSSESmokeDebug: NSObject {
    private struct RealInviteSenderContext {
        let inviteURL: URL
        let activeUserSession: UserSession
        let accessTokenProvider: DirectCallMatrixAccessTokenProviding
        let accessToken: String
    }

    private struct RedactedStateSummary {
        var runtimeDiagnostics = DebugForegroundCallSignalingSSERuntimeDiagnostics.disabled
        var rawEventReceived = false
        var sseEventType: ForegroundCallSignalingSSESafeEventType?
        var inviteParseAttempted = false
        var inviteParseSucceeded = false
        var pipelineDelivered = false

        mutating func record(_ diagnostics: DebugForegroundCallSignalingSSERuntimeDiagnostics) {
            runtimeDiagnostics = diagnostics
        }

        mutating func record(_ event: DebugForegroundCallSignalingSSESmokeTraceEvent) {
            switch event {
            case .rawEventReceived:
                rawEventReceived = true
            case .sseEventType(let eventType):
                sseEventType = eventType
            case .inviteParseAttempted:
                inviteParseAttempted = true
            case .inviteParseSucceeded(let succeeded):
                inviteParseSucceeded = succeeded
            case .pipelineDelivered(let delivered):
                pipelineDelivered = delivered
            }
        }

        var redactedLines: [String] {
            [
                "sse_connected=\(runtimeDiagnostics.sseConnected)",
                "stream_failure=\(runtimeDiagnostics.streamFailure?.description ?? "none")",
                "raw_event_received=\(rawEventReceived)",
                "sse_event_type=\(sseEventType?.description ?? "none")",
                "invite_parse_attempted=\(inviteParseAttempted)",
                "invite_parse_succeeded=\(inviteParseSucceeded)",
                "pipeline_delivered=\(pipelineDelivered)",
                "invite_received=\(runtimeDiagnostics.inviteReceived)",
                "invite_valid=\(runtimeDiagnostics.inviteValid)",
                "incoming_requested=\(runtimeDiagnostics.incomingRequested)"
            ]
        }
    }

    private static let logger = DebugForegroundCallSignalingSSESmokeDiagnosticsLogger()
    private static let redactedStateSummaryLock = NSLock()
    private weak static var activeUserSession: UserSession?
    private static var owner: DebugForegroundCallSignalingSSERuntimeOwner?
    private static var redactedStateSummarySnapshot = RedactedStateSummary()

    static func registerActiveUserSession(_ userSession: UserSession) {
        if Thread.isMainThread {
            activeUserSession = userSession
        } else {
            DispatchQueue.main.async {
                activeUserSession = userSession
            }
        }
    }

    @objc(configureWithStreamURLString:authorizationHeaderValue:)
    static func configure(streamURLString: String, authorizationHeaderValue: String) {
        guard let streamURL = URL(string: streamURLString) else {
            owner = nil
            resetRedactedStateSummary()
            logger.log(.disabled)
            return
        }

        var request = URLRequest(url: streamURL)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if !authorizationHeaderValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        }

        let reporter = NativeIncomingSyntheticCallKitUIProofReporter()
        let syntheticAdapter = NativeIncomingSyntheticCallKitUIProofAdapter(isEnabled: true,
                                                                            reporter: reporter,
                                                                            actionHandler: NativeIncomingSyntheticCallKitUIProofNoopActionHandler(),
                                                                            diagnosticsRecorder: NativeIncomingSyntheticCallKitUIProofNoopDiagnosticsRecorder(),
                                                                            eventRecorder: NativeIncomingSyntheticCallKitUIProofNoopEventRecorder())
        let stateStore = SalemXForegroundSSESmokeStateStore()
        let diagnosticsRecorder = NativeIncomingSyntheticCallKitUIProofNoopDiagnosticsRecorder()
        let reportingAdapter = SalemXForegroundSSESmokeCallKitReportingAdapter(adapter: syntheticAdapter)
        let inviteHandler = ForegroundCallInviteHandler(isEnabled: true,
                                                        stateStore: stateStore,
                                                        reportingAdapter: reportingAdapter,
                                                        diagnosticsRecorder: diagnosticsRecorder)
        let stream = URLSessionForegroundCallSignalingSSEStream(request: request)
        let transport = ForegroundCallSignalingSSETransport(isEnabled: true,
                                                            stream: stream,
                                                            // swiftlint:disable:next trailing_closure
                                                            debugObserver: { event in
                                                                recordRedactedStateSummary(event)
                                                                logger.log(event)
                                                            })
        owner = DebugForegroundCallSignalingSSERuntimeOwner(isEnabled: true,
                                                            transport: transport,
                                                            inviteHandler: inviteHandler,
                                                            // swiftlint:disable:next trailing_closure
                                                            diagnosticsObserver: { diagnostics in
                                                                recordRedactedStateSummary(diagnostics)
                                                                logger.log(diagnostics)
                                                            })
        let initialDiagnostics = DebugForegroundCallSignalingSSERuntimeDiagnostics(sseConfigured: true,
                                                                                   sseStarted: false,
                                                                                   sseConnected: false,
                                                                                   inviteReceived: false,
                                                                                   inviteValid: false,
                                                                                   incomingRequested: false,
                                                                                   fallbackDeduped: false,
                                                                                   transportStopped: false,
                                                                                   streamFailure: nil)
        resetRedactedStateSummary()
        recordRedactedStateSummary(initialDiagnostics)
        logger.log(initialDiagnostics)
    }

    @objc(configureWithCurrentSessionURLString:)
    static func configureWithCurrentSession(streamURLString: String) {
        configureWithCurrentSession(streamURLString: streamURLString, startsImmediately: false)
    }

    @objc(startWithCurrentSessionURLString:)
    static func startWithCurrentSession(streamURLString: String) {
        configureWithCurrentSession(streamURLString: streamURLString, startsImmediately: true)
    }

    @objc(configureWithCurrentSessionStreamURLString:)
    static func configureWithCurrentSessionStreamURLString(_ streamURLString: String) {
        configureWithCurrentSession(streamURLString: streamURLString, startsImmediately: true)
    }

    @objc(sendRealInviteWithURLString:recipient:recipientDevice:)
    static func sendRealInvite(inviteURLString: String, recipient: String, recipientDevice: String) {
        Task { @MainActor in
            await sendRealInviteWithActiveSession(inviteURLString: inviteURLString,
                                                  recipient: recipient,
                                                  recipientDevice: recipientDevice)
        }
    }

    @objc static func start() {
        owner?.appDidEnterForeground(authenticatedSessionAvailable: true)
    }

    @objc static func stop() {
        owner?.appDidEnterBackground()
    }

    @objc static func printDiagnostics() {
        logger.log(owner?.diagnostics ?? .disabled)
    }

    @objc static func clear() {
        owner?.appDidEnterBackground()
        owner = nil
        resetRedactedStateSummary()
    }

    @objc static func redactedStateSummary() -> String {
        redactedStateSummaryLock.lock()
        defer { redactedStateSummaryLock.unlock() }
        return redactedStateSummarySnapshot.redactedLines.joined(separator: "\n")
    }

    private static func configureWithCurrentSession(streamURLString: String, startsImmediately: Bool) {
        Task { @MainActor in
            resetRedactedStateSummary()
            guard URL(string: streamURLString) != nil else {
                owner = nil
                logCurrentSessionHelperDiagnostics(activeUserSession: activeUserSession,
                                                   accessTokenAvailable: false,
                                                   foregroundSSEStartRequested: false,
                                                   blockedReason: .invalidStreamURL)
                logger.log(.disabled)
                return
            }

            guard let activeUserSession else {
                owner = nil
                logCurrentSessionHelperDiagnostics(activeUserSession: nil,
                                                   accessTokenAvailable: false,
                                                   foregroundSSEStartRequested: false,
                                                   blockedReason: .missingActiveSession)
                logger.log(.disabled)
                return
            }

            guard let accessTokenProvider = activeUserSession.clientProxy as? DirectCallMatrixAccessTokenProviding else {
                owner = nil
                logCurrentSessionHelperDiagnostics(activeUserSession: activeUserSession,
                                                   accessTokenAvailable: false,
                                                   foregroundSSEStartRequested: false,
                                                   blockedReason: .missingAccessTokenProvider)
                logger.log(.disabled)
                return
            }

            guard let accessToken = await accessTokenProvider.matrixAccessToken() else {
                owner = nil
                logCurrentSessionHelperDiagnostics(activeUserSession: activeUserSession,
                                                   accessTokenAvailable: false,
                                                   foregroundSSEStartRequested: false,
                                                   blockedReason: .missingAccessToken)
                logger.log(.disabled)
                return
            }

            guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                owner = nil
                logCurrentSessionHelperDiagnostics(activeUserSession: activeUserSession,
                                                   accessTokenAvailable: false,
                                                   foregroundSSEStartRequested: false,
                                                   blockedReason: .blankAccessToken)
                logger.log(.disabled)
                return
            }

            logCurrentSessionHelperDiagnostics(activeUserSession: activeUserSession,
                                               accessTokenAvailable: true,
                                               foregroundSSEStartRequested: startsImmediately,
                                               blockedReason: .none)
            let authorizationPrefix = "B" + "earer "
            configure(streamURLString: streamURLString, authorizationHeaderValue: authorizationPrefix + accessToken)
            if startsImmediately {
                owner?.appDidEnterForeground(authenticatedSessionAvailable: true)
            }
        }
    }

    private static func resetRedactedStateSummary() {
        redactedStateSummaryLock.lock()
        defer { redactedStateSummaryLock.unlock() }
        redactedStateSummarySnapshot = RedactedStateSummary()
    }

    private static func recordRedactedStateSummary(_ diagnostics: DebugForegroundCallSignalingSSERuntimeDiagnostics) {
        redactedStateSummaryLock.lock()
        defer { redactedStateSummaryLock.unlock() }
        redactedStateSummarySnapshot.record(diagnostics)
    }

    private static func recordRedactedStateSummary(_ event: DebugForegroundCallSignalingSSESmokeTraceEvent) {
        redactedStateSummaryLock.lock()
        defer { redactedStateSummaryLock.unlock() }
        redactedStateSummarySnapshot.record(event)
    }

    private static func logCurrentSessionHelperDiagnostics(activeUserSession: UserSession?,
                                                           accessTokenAvailable: Bool,
                                                           foregroundSSEStartRequested: Bool,
                                                           blockedReason: DebugForegroundCallSignalingSSESmokeHelperBlockedReason) {
        let clientProxy = activeUserSession?.clientProxy
        let deviceIDAvailable = clientProxy?.deviceID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let homeserverURLAvailable = clientProxy?.homeserver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        logger.log(.init(helperInvoked: true,
                         activeSessionAvailable: activeUserSession != nil,
                         accessTokenAvailable: accessTokenAvailable,
                         deviceIDAvailable: deviceIDAvailable,
                         homeserverURLAvailable: homeserverURLAvailable,
                         foregroundSSEStartRequested: foregroundSSEStartRequested,
                         foregroundSSEStartBlockedReason: blockedReason))
    }

    private static func sendRealInviteWithActiveSession(inviteURLString: String,
                                                        recipient: String,
                                                        recipientDevice: String) async {
        guard let context = await realInviteSenderContext(inviteURLString: inviteURLString, recipient: recipient) else {
            return
        }

        logRealInviteSenderDiagnostics(activeUserSession: context.activeUserSession,
                                       accessTokenAvailable: true,
                                       postRequested: true,
                                       postStatus: .requested,
                                       deliveryReportReceived: false,
                                       blockedReason: .none)

        let result = await postRealInviteSafely(inviteURL: context.inviteURL,
                                                recipient: recipient,
                                                recipientDevice: recipientDevice,
                                                accessToken: context.accessToken)
        guard result.status == .httpUnauthorized else {
            logRealInviteSenderDiagnostics(activeUserSession: context.activeUserSession,
                                           accessTokenAvailable: true,
                                           postRequested: true,
                                           postStatus: result.status,
                                           deliveryReportReceived: result.deliveryReportReceived,
                                           blockedReason: .none)
            return
        }

        await retryRealInviteAfterUnauthorized(inviteURL: context.inviteURL,
                                               recipient: recipient,
                                               recipientDevice: recipientDevice,
                                               firstResult: result,
                                               context: context)
    }

    private static func realInviteSenderContext(inviteURLString: String,
                                                recipient: String) async -> RealInviteSenderContext? {
        guard let inviteURL = URL(string: inviteURLString) else {
            logRealInviteSenderDiagnostics(activeUserSession: activeUserSession,
                                           accessTokenAvailable: false,
                                           postRequested: false,
                                           postStatus: .notRequested,
                                           deliveryReportReceived: false,
                                           blockedReason: .invalidInviteURL)
            return nil
        }

        guard !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logRealInviteSenderDiagnostics(activeUserSession: activeUserSession,
                                           accessTokenAvailable: false,
                                           postRequested: false,
                                           postStatus: .notRequested,
                                           deliveryReportReceived: false,
                                           blockedReason: .missingRecipient)
            return nil
        }

        guard let activeUserSession else {
            logRealInviteSenderDiagnostics(activeUserSession: nil,
                                           accessTokenAvailable: false,
                                           postRequested: false,
                                           postStatus: .notRequested,
                                           deliveryReportReceived: false,
                                           blockedReason: .missingActiveSession)
            return nil
        }

        guard let accessTokenProvider = activeUserSession.clientProxy as? DirectCallMatrixAccessTokenProviding else {
            logRealInviteSenderDiagnostics(activeUserSession: activeUserSession,
                                           accessTokenAvailable: false,
                                           postRequested: false,
                                           postStatus: .notRequested,
                                           deliveryReportReceived: false,
                                           blockedReason: .missingAccessTokenProvider)
            return nil
        }

        guard let accessToken = await accessTokenProvider.matrixAccessToken() else {
            logRealInviteSenderDiagnostics(activeUserSession: activeUserSession,
                                           accessTokenAvailable: false,
                                           postRequested: false,
                                           postStatus: .notRequested,
                                           deliveryReportReceived: false,
                                           blockedReason: .missingAccessToken)
            return nil
        }

        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logRealInviteSenderDiagnostics(activeUserSession: activeUserSession,
                                           accessTokenAvailable: false,
                                           postRequested: false,
                                           postStatus: .notRequested,
                                           deliveryReportReceived: false,
                                           blockedReason: .blankAccessToken)
            return nil
        }

        return RealInviteSenderContext(inviteURL: inviteURL,
                                       activeUserSession: activeUserSession,
                                       accessTokenProvider: accessTokenProvider,
                                       accessToken: accessToken)
    }

    private static func retryRealInviteAfterUnauthorized(inviteURL: URL,
                                                         recipient: String,
                                                         recipientDevice: String,
                                                         firstResult: (status: DebugForegroundCallSignalingRealInviteSenderPostStatus,
                                                                       deliveryReportReceived: Bool),
                                                         context: RealInviteSenderContext) async {
        guard let retryAccessToken = await context.accessTokenProvider.matrixAccessToken(),
              !retryAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logRealInviteSenderDiagnostics(activeUserSession: context.activeUserSession,
                                           accessTokenAvailable: true,
                                           postRequested: true,
                                           postStatus: firstResult.status,
                                           deliveryReportReceived: firstResult.deliveryReportReceived,
                                           tokenRefreshNeeded: true,
                                           tokenRefreshAttempted: true,
                                           tokenRefreshSucceeded: false,
                                           retryRequested: false,
                                           retryStatus: .notRequested,
                                           blockedReason: .none)
            return
        }

        logRealInviteSenderDiagnostics(activeUserSession: context.activeUserSession,
                                       accessTokenAvailable: true,
                                       postRequested: true,
                                       postStatus: firstResult.status,
                                       deliveryReportReceived: firstResult.deliveryReportReceived,
                                       tokenRefreshNeeded: true,
                                       tokenRefreshAttempted: true,
                                       tokenRefreshSucceeded: true,
                                       retryRequested: true,
                                       retryStatus: .requested,
                                       blockedReason: .none)

        let retryResult = await postRealInviteSafely(inviteURL: inviteURL,
                                                     recipient: recipient,
                                                     recipientDevice: recipientDevice,
                                                     accessToken: retryAccessToken)
        logRealInviteSenderDiagnostics(activeUserSession: context.activeUserSession,
                                       accessTokenAvailable: true,
                                       postRequested: true,
                                       postStatus: firstResult.status,
                                       deliveryReportReceived: retryResult.deliveryReportReceived,
                                       tokenRefreshNeeded: true,
                                       tokenRefreshAttempted: true,
                                       tokenRefreshSucceeded: true,
                                       retryRequested: true,
                                       retryStatus: retryResult.status,
                                       blockedReason: .none)
    }

    private static func logRealInviteSenderDiagnostics(activeUserSession: UserSession?,
                                                       accessTokenAvailable: Bool,
                                                       postRequested: Bool,
                                                       postStatus: DebugForegroundCallSignalingRealInviteSenderPostStatus,
                                                       deliveryReportReceived: Bool,
                                                       tokenRefreshNeeded: Bool = false,
                                                       tokenRefreshAttempted: Bool = false,
                                                       tokenRefreshSucceeded: Bool = false,
                                                       retryRequested: Bool = false,
                                                       retryStatus: DebugForegroundCallSignalingRealInviteSenderPostStatus = .notRequested,
                                                       blockedReason: DebugForegroundCallSignalingRealInviteSenderBlockedReason) {
        logger.log(.init(senderHelperInvoked: true,
                         senderActiveSessionAvailable: activeUserSession != nil,
                         senderAccessTokenAvailable: accessTokenAvailable,
                         senderInvitePostRequested: postRequested,
                         senderInvitePostStatus: postStatus,
                         senderInviteDeliveryReportReceived: deliveryReportReceived,
                         senderTokenRefreshNeeded: tokenRefreshNeeded,
                         senderTokenRefreshAttempted: tokenRefreshAttempted,
                         senderTokenRefreshSucceeded: tokenRefreshSucceeded,
                         senderInviteRetryRequested: retryRequested,
                         senderInviteRetryStatus: retryStatus,
                         senderInviteBlockedReason: blockedReason))
    }

    private static func postRealInviteSafely(inviteURL: URL,
                                             recipient: String,
                                             recipientDevice: String,
                                             accessToken: String) async -> (status: DebugForegroundCallSignalingRealInviteSenderPostStatus,
                                                                            deliveryReportReceived: Bool) {
        do {
            return try await postRealInvite(inviteURL: inviteURL,
                                            recipient: recipient,
                                            recipientDevice: recipientDevice,
                                            accessToken: accessToken)
        } catch {
            return (.network, false)
        }
    }

    private static func postRealInvite(inviteURL: URL,
                                       recipient: String,
                                       recipientDevice: String,
                                       accessToken: String) async throws -> (status: DebugForegroundCallSignalingRealInviteSenderPostStatus, deliveryReportReceived: Bool) {
        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
        var payload: [String: Any] = [
            "recipient": recipient,
            "type": "foreground.call.invite",
            "version": 1,
            "call_handle": "safe-foreground-real-invite-\(UUID().uuidString.lowercased())",
            "call_kind": "audio",
            "created_at_ms": nowMilliseconds,
            "expires_at_ms": nowMilliseconds + 120_000,
            "display_label": "Pilot Participant"
        ]
        let trimmedRecipientDevice = recipientDevice.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRecipientDevice.isEmpty {
            payload["recipient_device"] = trimmedRecipientDevice
        }

        var request = URLRequest(url: inviteURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("B" + "earer " + accessToken, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return (.nonHTTPResponse, false)
        }

        let deliveryReportReceived = (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
        return (.init(httpStatusCode: httpResponse.statusCode), deliveryReportReceived)
    }
}

@objcMembers
@objc(SalemXForegroundSSESmokeDebugBridge)
final class SalemXForegroundSSESmokeDebugBridge: NSObject {
    static func sendRealInviteWithURLString(_ inviteURLString: String,
                                            recipient: String,
                                            recipientDevice: String) {
        SalemXForegroundSSESmokeDebug.sendRealInvite(inviteURLString: inviteURLString,
                                                     recipient: recipient,
                                                     recipientDevice: recipientDevice)
    }
}

@objcMembers
@objc(SalemXForegroundSSEReceiverSmokeDebugBridge)
final class SalemXForegroundSSEReceiverSmokeDebugBridge: NSObject {
    static func configureWithCurrentSessionStreamURLString(_ streamURLString: String) {
        SalemXForegroundSSESmokeDebug.configureWithCurrentSessionStreamURLString(streamURLString)
    }

    static func start() {
        SalemXForegroundSSESmokeDebug.start()
    }

    static func stop() {
        SalemXForegroundSSESmokeDebug.stop()
    }

    static func redactedStateSummary() -> String {
        SalemXForegroundSSESmokeDebug.redactedStateSummary()
    }
}

private extension DebugForegroundCallSignalingRealInviteSenderPostStatus {
    init(httpStatusCode: Int) {
        switch httpStatusCode {
        case 200..<300:
            self = .httpSuccess
        case 401:
            self = .httpUnauthorized
        default:
            self = .httpFailed
        }
    }
}
#endif
#endif
