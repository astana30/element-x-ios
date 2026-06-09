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
#endif
